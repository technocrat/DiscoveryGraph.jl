# src/network/community.jl
using PythonCall, Graphs, SimpleWeightedGraphs, DataFrames, Dates
import Graphs: nv, ne, src, dst, add_edge!

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

jaccard(a::Set, b::Set) = isempty(a) && isempty(b) ? 1.0 :
    length(intersect(a, b)) / length(union(a, b))

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
