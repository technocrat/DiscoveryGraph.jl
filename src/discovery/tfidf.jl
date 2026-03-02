# src/discovery/tfidf.jl
using DataFrames

"""
    build_community_vocabulary(corpus_df, community_table, cfg) -> Dict

v0.1.0 stub — returns empty term lists.
Full TF-IDF implementation is a future deliverable.
"""
function build_community_vocabulary(corpus_df::DataFrame,
                                    community_table::DataFrame,
                                    cfg::CorpusConfig)::Dict{Int32, Vector{Pair{String,Float64}}}
    cids = unique(community_table.community_id)
    Dict{Int32, Vector{Pair{String,Float64}}}(cid => Pair{String,Float64}[] for cid in cids)
end
