# src/discovery/privilege_log.jl
using DataFrames, Dates

"""
    TierClass

Five-tier classification for privilege log triage, used by `generate_outputs`.

# Variants
- `Tier1`: High-priority privilege review — litigation anticipation or active regulatory
  investigation. Requires immediate human review.
- `Tier2`: Secondary privilege review — regulatory compliance or direct legal advice.
  Requires human review after Tier 1.
- `Tier3`: Transactional legal work — privilege likely waived in transactional context.
  Deprioritised; review if time permits.
- `Tier4`: Unclassified — counsel is involved but semantic analysis was inconclusive.
  Human judgment required. All messages in v0.1.0 are assigned this tier pending
  full TF-IDF implementation.
- `Tier5`: No counsel involvement — excluded from privilege review queue.
"""
@enum TierClass Tier1 Tier2 Tier3 Tier4 Tier5

"""
    generate_outputs(S::DiscoverySession, node_reg::DataFrame)
        -> NamedTuple{(:community_table, :review_queue, :tier1, :tier2, :tier3, :tier4, :anomaly_list)}

Generate the primary discovery outputs from a `DiscoverySession`.

Processes every message in `S.corpus_df` and identifies those involving at least one
counsel node (as determined by `node_reg.is_counsel`). Each such message is added to the
review queue with the roles implicated and an initial tier assignment. In v0.1.0, all
counsel-involved messages are classified as `Tier4` pending full semantic analysis.

`node_reg` must be the output of `find_roles(node_reg, cfg)` — it must contain columns
`:roles` and `:is_counsel`.

# Arguments
- `S::DiscoverySession`: The active discovery session.
- `node_reg::DataFrame`: Node registry annotated by `find_roles`, with columns
  `:node`, `:community_id`, `:roles`, `:is_counsel`, and optionally `:is_kernel`.

# Returns
A `NamedTuple` with:
- `community_table::DataFrame` — subset of `node_reg` with columns `:node`,
  `:community_id`, `:roles`, `:is_counsel`, and `:is_kernel` (when present).
- `review_queue::DataFrame` — all Tier1–4 messages combined; columns `:hash`, `:date`,
  `:sender`, `:recipients`, `:subject`, `:roles_implicated`, `:tier` (`TierClass`), `:basis`.
- `tier1`–`tier4::DataFrame` — per-tier subsets of `review_queue` for direct access.
- `anomaly_list::DataFrame` — empty placeholder (anomaly detection performed separately
  by `detect_anomalies`); columns `:node`, `:week_start`, `:anomaly_type`, `:z_score`, `:basis`.

# Example
```julia
node_reg = find_roles(base_reg, cfg)
S        = DiscoverySession(corpus, result, edges, cfg)
outputs  = generate_outputs(S, node_reg)
memo     = generate_rule26f_memo(S, outputs)
```
"""
function generate_outputs(S::DiscoverySession, node_reg::DataFrame)
    # Ensure is_kernel column exists
    if :is_kernel ∉ propertynames(node_reg)
        node_reg = transform(node_reg, [] => ByRow(() -> false) => :is_kernel)
    end

    counsel_nodes = Set(filter(r -> r.is_counsel, node_reg).node)
    cfg = S.cfg

    # Pre-build role lookup once; avoids O(n_messages × n_nodes) work
    role_lookup = Dict(r.node => r.roles for r in eachrow(node_reg) if r.node ∈ counsel_nodes)

    rows = NamedTuple{
        (:hash, :date, :sender, :recipients, :subject, :roles_implicated, :tier, :basis),
        Tuple{String, DateTime, String, String, String, Vector{String}, TierClass, String}
    }[]

    for row in eachrow(S.corpus_df)
        sender  = getproperty(row, cfg.sender)
        tos     = extract_addrs(coalesce(getproperty(row, cfg.recipients_to), "[]"))
        ccs     = extract_addrs(coalesce(getproperty(row, cfg.recipients_cc), "[]"))
        all_parties = vcat([sender], tos, ccs)
        involved = intersect(Set(all_parties), counsel_nodes)
        isempty(involved) && continue

        roles_implicated = unique(vcat([get(role_lookup, n, String[]) for n in involved]...))

        push!(rows, (
            hash             = coalesce(getproperty(row, cfg.hash), ""),
            date             = getproperty(row, cfg.timestamp),
            sender           = sender,
            recipients       = join(vcat(tos, ccs), "; "),
            subject          = coalesce(getproperty(row, cfg.subject), ""),
            roles_implicated = roles_implicated,
            tier             = Tier4,
            basis            = "counsel node identified; semantic analysis pending",
        ))
    end

    review_queue = DataFrame(rows)

    # Build community_table — roles and is_counsel must be present (output of find_roles)
    for required_col in (:roles, :is_counsel)
        required_col ∈ propertynames(node_reg) || error(
            "node_reg is missing column :$required_col — " *
            "pass the output of find_roles(node_reg, cfg) to generate_outputs"
        )
    end
    ct_cols = [:node, :community_id, :roles, :is_counsel, :is_kernel]
    available = [c for c in ct_cols if c ∈ propertynames(node_reg)]
    community_table = select(node_reg, available)

    anomaly_list = DataFrame(node=String[], week_start=Date[],
                             anomaly_type=String[], z_score=Float64[],
                             basis=String[])

    (
        community_table = community_table,
        review_queue    = review_queue,
        tier1           = filter(r -> r.tier == Tier1, review_queue),
        tier2           = filter(r -> r.tier == Tier2, review_queue),
        tier3           = filter(r -> r.tier == Tier3, review_queue),
        tier4           = filter(r -> r.tier == Tier4, review_queue),
        anomaly_list    = anomaly_list,
    )
end
