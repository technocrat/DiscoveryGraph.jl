# src/discovery/roles.jl
using DataFrames

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
