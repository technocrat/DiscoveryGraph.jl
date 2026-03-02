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
