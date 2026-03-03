# src/discovery/privilege_log.jl
using DataFrames, Dates

# Match a single address against cfg.roles using the same three-rule logic as
# find_roles (explicit address → pattern → domain).  Returns (is_counsel, roles).
function _addr_counsel_roles(addr::String, cfg::CorpusConfig)::Tuple{Bool, Vector{String}}
    matched_roles = String[]
    is_counsel    = false
    for rc in cfg.roles
        m = addr ∈ rc.explicit_addresses
        !m && any(occursin(p, addr) for p in rc.address_patterns) && (m = true)
        !m && any(endswith(addr, "@" * d) || endswith(addr, "." * d)
                  for d in rc.domain_list) && (m = true)
        if m
            push!(matched_roles, rc.label)
            rc.counsel_type ∈ (InHouse, OutsideFirm) && (is_counsel = true)
        end
    end
    (is_counsel, matched_roles)
end

# Returns (tier, basis) for one message given lowercase subject and body text.
# Priority: hotbutton → tier1 keywords → tier2 keywords → tier3 keywords → Tier4.
function _classify_tier(subj_lc::String, body_lc::String, cfg::CorpusConfig)::Tuple{TierClass,String}
    for kw in cfg.hotbutton_keywords
        (occursin(kw, subj_lc) || occursin(kw, body_lc)) && return (Tier1, "hotbutton: $kw")
    end
    for kw in cfg.tier1_keywords
        (occursin(kw, subj_lc) || occursin(kw, body_lc)) && return (Tier1, "tier1 keyword: $kw")
    end
    for kw in cfg.tier2_keywords
        (occursin(kw, subj_lc) || occursin(kw, body_lc)) && return (Tier2, "tier2 keyword: $kw")
    end
    for kw in cfg.tier3_keywords
        (occursin(kw, subj_lc) || occursin(kw, body_lc)) && return (Tier3, "tier3 keyword: $kw")
    end
    return (Tier4, "counsel node identified; no keyword signal")
end

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
- `Tier4`: Unclassified — counsel is involved but no keyword from any tier list matched.
  Human judgment required.
- `Tier5`: No counsel involvement — excluded from privilege review queue.
"""
@enum TierClass Tier1 Tier2 Tier3 Tier4 Tier5

"""
    generate_outputs(S::DiscoverySession, node_reg::DataFrame)
        -> NamedTuple{(:community_table, :review_queue, :tier1, :tier2, :tier3, :tier4, :anomaly_list)}

Generate the primary discovery outputs from a `DiscoverySession`.

Processes every message in `S.corpus_df` and identifies those involving at least one
counsel party. Counsel is detected via two complementary paths:
1. **Graph-node counsel**: parties present in `node_reg` with `is_counsel = true`
   (derived from `find_roles`).
2. **Pattern-matched counsel**: parties absent from the graph (e.g., outside counsel
   at firm domains excluded by `cfg.internal_domain`) are checked directly against
   `cfg.roles` using the same domain/pattern/address rules as `find_roles`. This
   closes the privilege gap where messages to outside counsel are missed when the
   communication graph is restricted to internal addresses only.

Each matched message is added to the review queue with the roles implicated and a
keyword-based tier assignment.

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

    # Cache pattern-matching for addresses absent from the graph (e.g., outside
    # counsel at firm domains excluded by cfg.internal_domain filtering).
    addr_role_cache = Dict{String, Tuple{Bool, Vector{String}}}()

    rows = NamedTuple{
        (:hash, :date, :sender, :recipients, :subject, :roles_implicated, :tier, :basis),
        Tuple{String, DateTime, String, String, String, Vector{String}, TierClass, String}
    }[]

    for row in eachrow(S.corpus_df)
        sender  = getproperty(row, cfg.sender)
        tos     = extract_addrs(coalesce(getproperty(row, cfg.recipients_to), "[]"))
        ccs     = extract_addrs(coalesce(getproperty(row, cfg.recipients_cc), "[]"))
        all_parties = vcat([sender], tos, ccs)

        # Collect counsel roles for every party: graph-node counsel first, then
        # pattern-match parties absent from the graph (e.g. outside counsel).
        counsel_roles = Dict{String, Vector{String}}()
        for addr in all_parties
            haskey(counsel_roles, addr) && continue      # dedup within message
            if addr ∈ counsel_nodes
                counsel_roles[addr] = get(role_lookup, addr, String[])
            else
                is_c, roles = get!(addr_role_cache, addr) do
                    _addr_counsel_roles(addr, cfg)
                end
                is_c && (counsel_roles[addr] = roles)
            end
        end
        isempty(counsel_roles) && continue

        roles_implicated = unique(vcat(values(counsel_roles)...))

        subj     = coalesce(getproperty(row, cfg.subject), "")
        body_raw = getproperty(row, cfg.lastword)
        body_lc  = body_raw isa AbstractString ? lowercase(body_raw) : ""
        tier, basis = _classify_tier(lowercase(subj), body_lc, cfg)

        push!(rows, (
            hash             = coalesce(getproperty(row, cfg.hash), ""),
            date             = getproperty(row, cfg.timestamp),
            sender           = sender,
            recipients       = join(vcat(tos, ccs), "; "),
            subject          = subj,
            roles_implicated = roles_implicated,
            tier             = tier,
            basis            = basis,
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
    # Join community_id from S.result (Leiden output) into node_reg, which
    # was built from find_roles and does not carry community_id on its own.
    nr_with_cid = (:community_id ∉ propertynames(node_reg) &&
                   :community_id ∈ propertynames(S.result)) ?
        leftjoin(node_reg, select(S.result, :node, :community_id), on = :node) :
        node_reg
    ct_cols = [:node, :community_id, :roles, :is_counsel, :is_kernel]
    available = [c for c in ct_cols if c ∈ propertynames(nr_with_cid)]
    community_table = select(nr_with_cid, available)

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
