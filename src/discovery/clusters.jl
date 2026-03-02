# src/discovery/clusters.jl
using DataFrames, Dates, Random

struct DiscoverySession
    corpus_df::DataFrame
    result::DataFrame
    edge_df::DataFrame
    cfg::CorpusConfig
end

function eyeball(S::DiscoverySession, cid::Integer;
                 mode  = :random,
                 n     = 25,
                 start = nothing,
                 stop  = nothing,
                 block = nothing)

    start = isnothing(start) ? S.cfg.baseline_start : start
    stop  = isnothing(stop)  ? S.cfg.baseline_end   : stop
    if mode == :block && !isnothing(block)
        start, stop = block
        mode = :chrono
    end

    members  = Set(filter(r -> r.community_id == cid, S.result).node)
    in_range = filter(r ->
        getproperty(r, S.cfg.sender) ∈ members &&
        start <= getproperty(r, S.cfg.timestamp) <= stop,
        S.corpus_df)

    sample_df = if mode == :random
        nrow(in_range) <= n ? in_range : in_range[shuffle(1:nrow(in_range))[1:n], :]
    else
        nrow(in_range) <= n ? in_range : in_range[1:n, :]
    end

    for row in eachrow(sort(sample_df, S.cfg.timestamp))
        println(getproperty(row, S.cfg.timestamp), " | ",
                getproperty(row, S.cfg.sender), " → ",
                getproperty(row, S.cfg.subject))
    end
    nothing
end

function inspect_community(S::DiscoverySession, cid::Integer)
    members    = filter(r -> r.community_id == cid, S.result).node
    member_set = Set(members)
    println("Community $cid — $(length(members)) members")
    internal = filter(r -> r.sender ∈ member_set && r.recipient ∈ member_set, S.edge_df)
    println("  Internal edges: $(nrow(internal))")
    by_sender = combine(groupby(internal, :sender), nrow => :n)
    sort!(by_sender, :n, rev=true)
    println("  Top senders:")
    for row in eachrow(first(by_sender, 5))
        println("    $(row.sender): $(row.n)")
    end
    nothing
end

function inspect_bridge(S::DiscoverySession, cid_a::Integer, cid_b::Integer;
                         start = nothing, stop = nothing)
    start = isnothing(start) ? S.cfg.baseline_start : start
    stop  = isnothing(stop)  ? S.cfg.baseline_end   : stop
    ma = Set(filter(r -> r.community_id == cid_a, S.result).node)
    mb = Set(filter(r -> r.community_id == cid_b, S.result).node)
    bridge = filter(r ->
        (r.sender ∈ ma && r.recipient ∈ mb) ||
        (r.sender ∈ mb && r.recipient ∈ ma),
        S.edge_df)
    bridge = filter(r -> start <= r.date <= stop, bridge)
    println("Bridge edges between communities $cid_a ↔ $cid_b: $(nrow(bridge))")
    nothing
end

function review_all_communities(S::DiscoverySession; n=10, start=nothing, stop=nothing)
    cids = sort(unique(S.result.community_id))
    for cid in cids
        println("\n=== Community $cid ===")
        eyeball(S, cid; n=n, start=start, stop=stop)
    end
    nothing
end
