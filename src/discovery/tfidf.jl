# src/discovery/tfidf.jl
using DataFrames

"""
    build_community_vocabulary(corpus_df::DataFrame, community_table::DataFrame,
                               cfg::CorpusConfig) -> Dict{Int32, Vector{Pair{String,Float64}}}

Build a TF-IDF vocabulary for each community from the corpus subject lines.

!!! warning "v0.1.0 stub"
    This function is not yet implemented. It returns empty term lists for every
    community. Full TF-IDF computation is a future deliverable.

# Arguments
- `corpus_df::DataFrame`: The full message corpus with columns named according to `cfg`.
- `community_table::DataFrame`: Community membership table with a `:community_id` column.
- `cfg::CorpusConfig`: Configuration supplying stopwords and column name mappings.

# Returns
`Dict{Int32, Vector{Pair{String,Float64}}}` mapping each community ID to a list of
`(term => tfidf_score)` pairs sorted by descending score. In v0.1.0 every community
maps to an empty vector.

# Example
```julia
vocab = build_community_vocabulary(corpus_df, community_table, cfg)
# vocab[6] => Pair{String,Float64}[]  (stub; always empty in v0.1.0)
```
"""
function build_community_vocabulary(corpus_df::DataFrame,
                                    community_table::DataFrame,
                                    cfg::CorpusConfig)::Dict{Int32, Vector{Pair{String,Float64}}}
    cids = unique(community_table.community_id)
    Dict{Int32, Vector{Pair{String,Float64}}}(cid => Pair{String,Float64}[] for cid in cids)
end
