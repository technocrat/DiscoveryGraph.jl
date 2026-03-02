# src/discovery/clusters.jl
using DataFrames, Dates, Random

"""
    DiscoverySession

Primary interactive interface for exploring a communication network and its detected
communities. Bundles the four DataFrames and configuration that all inspection functions
require, eliminating repetitive argument passing.

# Fields
- `corpus_df::DataFrame`: The full message corpus, with columns named according to `cfg`.
- `result::DataFrame`: Community membership table with columns `:node` and `:community_id`.
- `edge_df::DataFrame`: Broadcast-discounted edge table from `build_edges`, with columns
  `:sender`, `:recipient`, `:date`, and `:weight`.
- `cfg::CorpusConfig`: The corpus configuration (column names, date bounds, roles, etc.).

# Example
```julia
S = DiscoverySession(corpus_df, leiden_result, edge_df, cfg)
eyeball(S, 6; mode=:block, block=(DateTime(2000,7,1), DateTime(2000,7,31)), n=20)
inspect_community(S, 6)
```
"""
struct DiscoverySession
    corpus_df::DataFrame
    result::DataFrame
    edge_df::DataFrame
    cfg::CorpusConfig
end

"""
    eyeball(S::DiscoverySession, cid::Integer;
            mode=:random, n=25, start=nothing, stop=nothing, block=nothing)

Print a sample of message headers from a single community to the console.

Filters the corpus to messages sent by members of community `cid` within the time
window, then prints timestamp, sender, and subject for up to `n` messages.

# Arguments
- `S::DiscoverySession`: The active discovery session.
- `cid::Integer`: Community ID to inspect.
- `mode`: Sampling mode — `:random` (default) shuffles before taking `n`; `:chrono` takes the first `n` in chronological order.
- `n`: Maximum number of messages to display (default: `25`).
- `start`: Window start (`DateTime`); defaults to `S.cfg.baseline_start`.
- `stop`: Window end (`DateTime`); defaults to `S.cfg.baseline_end`.
- `block`: A `(start, stop)` tuple of `DateTime` values; sets the window and forces `mode=:chrono`. Overrides `start`/`stop` when provided.

# Returns
`nothing` (output goes to stdout).

# Example
```julia
eyeball(S, 9; mode=:chrono, n=10)
eyeball(S, 6; block=(DateTime(2000,7,1), DateTime(2000,7,31)), n=20)
```
"""
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

"""
    inspect_community(S::DiscoverySession, cid::Integer)

Print a structural summary of a single community to the console.

Displays the community's member count, total internal edge count, and the top-5
internal senders by message volume.

# Arguments
- `S::DiscoverySession`: The active discovery session.
- `cid::Integer`: Community ID to summarise.

# Returns
`nothing` (output goes to stdout).

# Example
```julia
inspect_community(S, 6)
```
"""
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

"""
    inspect_bridge(S::DiscoverySession, cid_a::Integer, cid_b::Integer;
                   start=nothing, stop=nothing)

Print the count of cross-community edges between two communities within a time window.

Identifies edges where one endpoint is a member of `cid_a` and the other is a member of
`cid_b` (in either direction), filtered to the specified date range.

# Arguments
- `S::DiscoverySession`: The active discovery session.
- `cid_a::Integer`: First community ID.
- `cid_b::Integer`: Second community ID.
- `start`: Window start (`DateTime`); defaults to `S.cfg.baseline_start`.
- `stop`: Window end (`DateTime`); defaults to `S.cfg.baseline_end`.

# Returns
`nothing` (output goes to stdout).

# Example
```julia
inspect_bridge(S, 9, 6; start=DateTime(2000,10,1), stop=DateTime(2000,12,31))
```
"""
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

"""
    review_all_communities(S::DiscoverySession; n=10, start=nothing, stop=nothing)

Run `eyeball` on every community in the session and print the results sequentially.

Communities are processed in ascending `community_id` order. Useful for a first-pass
review of all communities immediately after Leiden detection.

# Arguments
- `S::DiscoverySession`: The active discovery session.
- `n`: Maximum messages to display per community (default: `10`).
- `start`: Window start (`DateTime`); defaults to `S.cfg.baseline_start`.
- `stop`: Window end (`DateTime`); defaults to `S.cfg.baseline_end`.

# Returns
`nothing` (output goes to stdout).

# Example
```julia
review_all_communities(S; n=5)
```
"""
function review_all_communities(S::DiscoverySession; n=10, start=nothing, stop=nothing)
    cids = sort(unique(S.result.community_id))
    for cid in cids
        println("\n=== Community $cid ===")
        eyeball(S, cid; n=n, start=start, stop=stop)
    end
    nothing
end
