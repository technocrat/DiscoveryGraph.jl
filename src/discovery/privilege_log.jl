# src/discovery/privilege_log.jl
using DataFrames, Dates

@enum TierClass Tier1 Tier2 Tier3 Tier4 Tier5

function generate_outputs(S::DiscoverySession, node_reg::DataFrame)
    # Ensure is_kernel column exists
    if :is_kernel ∉ propertynames(node_reg)
        node_reg = transform(node_reg, [] => ByRow(() -> false) => :is_kernel)
    end

    counsel_nodes = Set(filter(r -> r.is_counsel, node_reg).node)
    cfg = S.cfg

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

        role_lookup = Dict(r.node => r.roles for r in eachrow(node_reg) if r.node ∈ involved)
        roles_implicated = unique(vcat(values(role_lookup)...))

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

    # Build community_table — include columns present in node_reg
    ct_cols = [:node, :community_id, :roles, :is_counsel, :is_kernel]
    available = [c for c in ct_cols if c ∈ propertynames(node_reg)]
    community_table = select(node_reg, available)

    anomaly_list = DataFrame(node=String[], week_start=Date[],
                             anomaly_type=String[], z_score=Float64[],
                             basis=String[])

    (community_table=community_table, review_queue=review_queue, anomaly_list=anomaly_list)
end
