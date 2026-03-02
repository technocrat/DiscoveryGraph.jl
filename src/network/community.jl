# src/network/community.jl
using PythonCall, Graphs, SimpleWeightedGraphs, DataFrames, Dates
import Graphs: nv, ne, src, dst, add_edge!

"""
    build_snapshot_graph(edges::DataFrame, node_idx::Dict{String,Int}, n::Int) -> SimpleWeightedGraph

Construct a weighted undirected graph from an edge table for a single time snapshot.

Each unique (sender, recipient) pair in `edges` becomes an undirected edge with the
corresponding weight. Nodes are identified by their integer index in `node_idx`; any
address not present in `node_idx` is silently skipped.

# Arguments
- `edges::DataFrame`: Edge table with columns `:sender`, `:recipient`, and `:weight`.
- `node_idx::Dict{String,Int}`: Mapping from node address to 1-based integer index.
- `n::Int`: Total number of nodes (size of the graph).

# Returns
A `SimpleWeightedGraph` with `n` vertices and one edge per row of `edges` that has
both endpoints in `node_idx`.

# Example
```julia
nodes    = unique(vcat(edges.sender, edges.recipient))
node_idx = Dict(n => i for (i, n) in enumerate(nodes))
g = build_snapshot_graph(edges, node_idx, length(nodes))
```
"""
function build_snapshot_graph(edges::DataFrame,
                               node_idx::Dict{String,Int},
                               n::Int)::SimpleWeightedGraph
    g = SimpleWeightedGraph(n)
    for row in eachrow(edges)
        s = get(node_idx, row.sender,    0)
        r = get(node_idx, row.recipient, 0)
        (s == 0 || r == 0) && continue
        add_edge!(g, s, r, row.weight)
    end
    g
end

function _to_igraph(g::SimpleWeightedGraph, node_labels::Vector{String}, ig)
    n = nv(g)
    ig_g = ig.Graph(n, directed=false)
    ig_g.vs["name"] = node_labels
    edge_list = Tuple{Int,Int}[]
    weights   = Float64[]
    for e in Graphs.edges(g)
        push!(edge_list, (src(e) - 1, dst(e) - 1))
        push!(weights, e.weight)
    end
    ig_g.add_edges(edge_list)
    ig_g.es["weight"] = weights
    ig_g
end

"""
    leiden_communities(g::SimpleWeightedGraph, node_labels::Vector{String};
                       resolution=1.0, n_iterations=10, seed=42) -> DataFrame

Detect communities in a weighted graph using the Leiden algorithm.

Calls the Python `leidenalg` library (via `PythonCall`) with the
`RBConfigurationVertexPartition` objective, which supports weighted edges and a
resolution parameter. Community IDs are 1-based integers in the output (Python's
0-based membership is incremented).

Results are non-deterministic across fresh runs even with the same seed because Leiden's
refinement phase uses a randomised order; use `match_communities` to track identity across
snapshots.

# Arguments
- `g::SimpleWeightedGraph`: The graph to partition.
- `node_labels::Vector{String}`: Address label for each vertex (length must equal `nv(g)`).
- `resolution`: Resolution parameter controlling community granularity. Higher values yield more, smaller communities (default: `1.0`).
- `n_iterations`: Number of Leiden iterations (default: `10`).
- `seed`: Random seed for reproducibility within a single run (default: `42`).

# Returns
`DataFrame` with columns:
- `:node::String` — node address.
- `:community_id::Int32` — 1-based community membership.

# Example
```julia
result = leiden_communities(g, nodes; resolution=1.0)
```
"""
function leiden_communities(g::SimpleWeightedGraph,
                             node_labels::Vector{String};
                             resolution   = 1.0,
                             n_iterations = 10,
                             seed         = 42)::DataFrame
    ig = pyimport("igraph")
    la = pyimport("leidenalg")
    ig_g = _to_igraph(g, node_labels, ig)
    partition = la.find_partition(
        ig_g, la.RBConfigurationVertexPartition;
        weights=ig_g.es["weight"],
        resolution_parameter=resolution,
        n_iterations=n_iterations,
        seed=seed,
    )
    membership = pyconvert(Vector{Int}, partition.membership)
    DataFrame(node=node_labels, community_id=Int32.(membership .+ 1))
end

"""
    jaccard(a::Set, b::Set) -> Float64

Compute the Jaccard similarity between two sets.

Jaccard similarity is `|a ∩ b| / |a ∪ b|`. Returns `1.0` when both sets are empty
(identical empty sets are treated as perfectly similar).

# Arguments
- `a::Set`: First set.
- `b::Set`: Second set.

# Returns
A `Float64` in `[0.0, 1.0]`.

# Example
```julia
jaccard(Set([1,2,3]), Set([2,3,4]))  # => 0.5
jaccard(Set{Int}(), Set{Int}())      # => 1.0
```
"""
jaccard(a::Set, b::Set) = isempty(a) && isempty(b) ? 1.0 :
    length(intersect(a, b)) / length(union(a, b))

"""
    build_kernel(members::Vector{String}, weekly_snapshots::Vector{DataFrame};
                 threshold=2/3) -> Set{String}

Identify the stable core ("kernel") of a community across weekly snapshots.

A node is a kernel member if it appears in at least `threshold` fraction of the
provided weekly snapshot DataFrames. Kernel membership is used by `match_communities`
to produce stable community IDs across Leiden's non-deterministic reassignments.

# Arguments
- `members::Vector{String}`: Candidate community members (typically from the baseline run).
- `weekly_snapshots::Vector{DataFrame}`: Weekly node-membership DataFrames, each with a `:node` column.
- `threshold`: Minimum fraction of weeks a node must appear in to be a kernel member (default: `2/3`).

# Returns
`Set{String}` of addresses that cleared the threshold. Returns an empty set when
`weekly_snapshots` is empty.

# Example
```julia
kernel = build_kernel(community_members, snapshots; threshold=2/3)
```
"""
function build_kernel(members::Vector{String},
                      weekly_snapshots::Vector{DataFrame};
                      threshold = 2/3)::Set{String}
    n_weeks = length(weekly_snapshots)
    n_weeks == 0 && return Set{String}()
    counts = Dict{String,Int}(m => 0 for m in members)
    for snap in weekly_snapshots
        snap_members = Set(snap.node)
        for m in members
            m ∈ snap_members && (counts[m] += 1)
        end
    end
    Set(m for (m, c) in counts if c / n_weeks >= threshold)
end

"""
    match_communities(prior_kernels::Dict{Int32,Set{String}},
                      current_kernels::Dict{Int32,Set{String}};
                      min_jaccard=0.6) -> Dict{Int32,Int32}

Match current community IDs to prior community IDs using kernel Jaccard similarity.

Because Leiden assigns community IDs non-deterministically, this function provides
stable identity tracking across weekly snapshots. All candidate (current, prior) pairs
with Jaccard similarity ≥ `min_jaccard` are scored, sorted descending, and greedily
assigned (each community ID used at most once on either side).

# Arguments
- `prior_kernels::Dict{Int32,Set{String}}`: Kernel sets from the previous snapshot, keyed by community ID.
- `current_kernels::Dict{Int32,Set{String}}`: Kernel sets from the current snapshot, keyed by community ID.
- `min_jaccard`: Minimum Jaccard threshold to consider a pair a match (default: `0.6`).

# Returns
`Dict{Int32,Int32}` mapping `current_community_id => prior_community_id` for all
matched pairs. Unmatched current communities are absent from the dict.

# Example
```julia
mapping = match_communities(prior_kernels, current_kernels; min_jaccard=0.6)
# mapping[current_id] == prior_id
```
"""
function match_communities(prior_kernels::Dict{Int32,Set{String}},
                            current_kernels::Dict{Int32,Set{String}};
                            min_jaccard = 0.6)::Dict{Int32,Int32}
    # Collect all candidate pairs with scores
    candidates = Tuple{Int32,Int32,Float64}[]
    for (curr_id, curr_kernel) in current_kernels
        for (prior_id, prior_kernel) in prior_kernels
            score = jaccard(curr_kernel, prior_kernel)
            score >= min_jaccard && push!(candidates, (curr_id, prior_id, score))
        end
    end
    # Sort descending by score for deterministic greedy assignment
    sort!(candidates, by = t -> t[3], rev=true)

    matches    = Dict{Int32,Int32}()
    used_curr  = Set{Int32}()
    used_prior = Set{Int32}()
    for (curr_id, prior_id, _) in candidates
        curr_id ∈ used_curr  && continue
        prior_id ∈ used_prior && continue
        matches[curr_id] = prior_id
        push!(used_curr,  curr_id)
        push!(used_prior, prior_id)
    end
    matches
end
