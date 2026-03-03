# src/discovery/roles.jl
using DataFrames

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
                rc.counsel_type ∈ (InHouse, OutsideFirm) && (result.is_counsel[i] = true)
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
