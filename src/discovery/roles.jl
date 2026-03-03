# src/discovery/roles.jl
using DataFrames

"""
    ATTORNEY_KEYWORDS

Default subject-line keywords used by [`audit_counsel_coverage`](@ref) to identify
messages that discuss legal topics but involve no known counsel party. A message
whose subject contains any of these terms (case-insensitive) is a candidate for
review when neither its sender nor any recipient is in the counsel node set.

Pass a custom list as the `keywords` argument to `audit_counsel_coverage` to override.
"""
const ATTORNEY_KEYWORDS = [
    "privilege", "privileged", "attorney", "counsel", "legal advice",
    "attorney-client", "work product", "litigation", "settlement",
    "regulatory", "legal hold", "confidential",
]

"""
    find_roles(node_reg::DataFrame, cfg::CorpusConfig) -> DataFrame

Annotate a node registry with role labels and counsel flags from `cfg.roles`.

For each node address, every `RoleConfig` in `cfg.roles` is tested in order using three
matching rules (any match assigns the role):
1. Exact membership in `rc.explicit_addresses`.
2. Any pattern in `rc.address_patterns` matches via `occursin`.
3. The address ends with `"@<domain>"` or `".<domain>"` for any domain in `rc.domain_list`.

A node's `is_counsel` flag is set to `true` if it matches any role whose `counsel_type`
is `InHouse` or `OutsideFirm`.

# Arguments
- `node_reg::DataFrame`: Node registry with at least a `:node` column of address strings.
- `cfg::CorpusConfig`: Configuration carrying the `roles` vector to apply.

# Returns
A copy of `node_reg` with two additional columns:
- `:roles::Vector{String}` — list of role labels matched for each node (empty if none).
- `:is_counsel::Bool` — `true` if the node matched any counsel role.

# Example
```julia
node_reg = find_roles(base_node_reg, cfg)
counsel_nodes = filter(r -> r.is_counsel, eachrow(node_reg))
```
"""
function find_roles(node_reg::DataFrame, cfg::CorpusConfig)::DataFrame
    result = copy(node_reg)
    result.roles      = [String[] for _ in 1:nrow(result)]
    result.is_counsel = falses(nrow(result))

    for (i, node) in enumerate(result.node)
        for rc in cfg.roles
            matched = false
            node ∈ rc.explicit_addresses && (matched = true)
            !matched && any(occursin(p, node) for p in rc.address_patterns) && (matched = true)
            !matched && any(endswith(node, "." * d) || endswith(node, "@" * d)
                            for d in rc.domain_list) && (matched = true)
            if matched
                push!(result.roles[i], rc.label)
                rc.counsel_type ∈ (InHouse, OutsideFirm, RegulatoryAdvisor) && (result.is_counsel[i] = true)
            end
        end
    end
    result
end

"""
    identify_counsel_communities(result::DataFrame, cfg::CorpusConfig) -> DataFrame

Tentatively identify which Leiden communities contain counsel nodes using `cfg.roles`.

Applies the same role-matching logic as [`find_roles`](@ref) directly to the Leiden
output, without requiring a manually curated node registry. Use this immediately after
[`leiden_communities`](@ref) to identify which community IDs to focus on — replacing
the need to call `review_all_communities` and scan output by eye.

# Arguments
- `result::DataFrame`: Leiden output with at least `:node` and `:community_id` columns.
- `cfg::CorpusConfig`: Configuration carrying the `roles` vector to apply.

# Returns
A `DataFrame` with one row per community containing at least one counsel node:
- `:community_id` — Leiden community identifier.
- `:n_members` — total nodes in the community.
- `:n_counsel` — nodes matching any counsel role.
- `:roles` — unique role labels present (e.g. `["in_house_counsel"]`).
- `:counsel_nodes` — addresses of matched counsel nodes.

Sorted by `:n_counsel` descending. Returns an empty `DataFrame` if no counsel nodes
are found (check `cfg.roles` is correctly populated).

# Example
```julia
result = leiden_communities(g, all_nodes; resolution=1.0, seed=42)
identify_counsel_communities(result, cfg)
# community_id  n_members  n_counsel  roles                  counsel_nodes
#           9        142         6  ["in_house_counsel"]   ["sara.shackleton@enron.com", ...]
```
"""
function identify_counsel_communities(result::DataFrame, cfg::CorpusConfig)::DataFrame
    annotated  = find_roles(result, cfg)
    counsel_df = filter(:is_counsel => identity, annotated)

    isempty(counsel_df) && return DataFrame(
        community_id  = Int[],
        n_members     = Int[],
        n_counsel     = Int[],
        roles         = Vector{String}[],
        counsel_nodes = Vector{String}[],
    )

    sizes       = combine(groupby(result, :community_id), nrow => :n_members)
    size_lookup = Dict(r.community_id => r.n_members for r in eachrow(sizes))

    grouped = groupby(counsel_df, :community_id)
    summary = combine(grouped,
        :node  => (v -> [collect(v)])           => :counsel_nodes,
        :roles => (v -> [unique(vcat(v...))]) => :roles,
        nrow                                     => :n_counsel,
    )

    summary.n_members = [get(size_lookup, cid, 0) for cid in summary.community_id]
    sort!(summary, :n_counsel, rev=true)
    select!(summary, :community_id, :n_members, :n_counsel, :roles, :counsel_nodes)
end

"""
    audit_counsel_coverage(corpus, node_reg, cfg; keywords, broadcast_min_recipients) -> NamedTuple

Scan the corpus for attorney-flavored messages where no party is a known counsel node.

Identifies potential gaps in `cfg.roles` — senders who write about legal topics but
were not captured by the role-matching rules. Most results will be broadcast
announcements (high `broadcast_fraction`); outliers with low `broadcast_fraction`
and many messages are candidates for manual review and possible addition to `cfg.roles`.

Messages are filtered by subject keyword match (case-insensitive). A message is
excluded from results if the sender or any recipient is already in `node_reg` as
counsel. Bot senders (per `cfg`) are also excluded.

# Arguments
- `corpus::DataFrame`: Full corpus as returned by `load_corpus`.
- `node_reg::DataFrame`: Node registry with `:is_counsel` column from `find_roles`.
- `cfg::CorpusConfig`: Configuration supplying column names and bot rules.
- `keywords`: Subject keywords to match (default: `ATTORNEY_KEYWORDS`).
- `broadcast_min_recipients`: Recipient count at or above which a message is flagged
  as a broadcast (default: `5`).

# Returns
A `NamedTuple` with:
- `:suspicious_senders::DataFrame` — one row per non-counsel sender, columns:
  `:sender`, `:n_messages`, `:n_broadcast`, `:broadcast_fraction`, `:sample_subjects`.
  Sorted by `:n_messages` descending.
- `:uncovered_count::Int` — total attorney-flavored messages with no counsel party.
- `:keywords_used::Vector{String}` — the keyword list applied.

# Example
```julia
node_reg = find_roles(base_node_reg, cfg)
audit  = audit_counsel_coverage(corpus, node_reg, cfg)
# Filter to non-broadcast candidates for cfg.roles additions:
filter(r -> r.broadcast_fraction < 0.5, audit.suspicious_senders)
```
"""
function audit_counsel_coverage(
    corpus::DataFrame,
    node_reg::DataFrame,
    cfg::CorpusConfig;
    keywords::Vector{String}      = ATTORNEY_KEYWORDS,
    broadcast_min_recipients::Int = 5,
)::NamedTuple
    for col in (:roles, :is_counsel)
        col ∈ propertynames(node_reg) ||
            error("node_reg is missing :$col — pass the output of find_roles(node_reg, cfg)")
    end

    counsel_set = Set(node_reg[node_reg.is_counsel, :node])

    rows = NamedTuple{
        (:sender, :subject, :recipient_count, :is_broadcast),
        Tuple{String, String, Int, Bool}
    }[]

    for row in eachrow(corpus)
        subj = lowercase(coalesce(getproperty(row, cfg.subject), ""))
        any(occursin(kw, subj) for kw in keywords) || continue

        sender = coalesce(getproperty(row, cfg.sender), "")
        isempty(sender)        && continue
        is_bot(sender, cfg)    && continue
        sender ∈ counsel_set   && continue

        tos       = extract_addrs(coalesce(getproperty(row, cfg.recipients_to), "[]"))
        ccs       = extract_addrs(coalesce(getproperty(row, cfg.recipients_cc), "[]"))
        all_recips = vcat(tos, ccs)
        any(r ∈ counsel_set for r in all_recips) && continue

        n = length(all_recips)
        push!(rows, (
            sender          = sender,
            subject         = coalesce(getproperty(row, cfg.subject), ""),
            recipient_count = n,
            is_broadcast    = n >= broadcast_min_recipients,
        ))
    end

    empty_df = DataFrame(
        sender             = String[],
        n_messages         = Int[],
        n_broadcast        = Int[],
        broadcast_fraction = Float64[],
        sample_subjects    = String[],
    )
    isempty(rows) && return (
        suspicious_senders = empty_df,
        uncovered_count    = 0,
        keywords_used      = keywords,
    )

    df      = DataFrame(rows)
    grouped = groupby(df, :sender)
    suspicious = combine(grouped,
        nrow                                                      => :n_messages,
        :is_broadcast => sum                                      => :n_broadcast,
        :subject => (v -> join(first(unique(v), 3), " | ")) => :sample_subjects,
    )
    suspicious.broadcast_fraction = suspicious.n_broadcast ./ suspicious.n_messages
    sort!(suspicious, :n_messages, rev=true)
    select!(suspicious, :sender, :n_messages, :n_broadcast, :broadcast_fraction, :sample_subjects)

    return (
        suspicious_senders = suspicious,
        uncovered_count    = nrow(df),
        keywords_used      = keywords,
    )
end
