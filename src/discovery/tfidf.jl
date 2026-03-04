# src/discovery/tfidf.jl
using DataFrames, SparseArrays, LinearAlgebra

# ── Internal helpers ──────────────────────────────────────────────────────────

function _tokenize(text::String, stopwords::Set{String})::Vector{String}
    tokens = split(lowercase(text), r"\W+"; keepempty=false)
    [t for t in tokens if length(t) >= 2 && t ∉ stopwords]
end

function _tfidf_vector(tokens::Vector{String},
                        idf::Dict{String, Float64},
                        term_index::Dict{String, Int},
                        vocab::Vector{String},
                        vocab_size::Int)::SparseVector{Float64, Int}
    isempty(tokens) && return spzeros(Float64, vocab_size)
    n  = length(tokens)
    tf = Dict{Int, Float64}()
    for t in tokens
        haskey(term_index, t) || continue
        idx = term_index[t]
        tf[idx] = get(tf, idx, 0.0) + 1.0 / n
    end
    isempty(tf) && return spzeros(Float64, vocab_size)
    inds = sort!(collect(keys(tf)))
    vals = [tf[i] for i in inds] .* [idf[vocab[i]] for i in inds]
    SparseVector(vocab_size, inds, vals)
end

function _l2_norm(v::SparseVector{Float64, Int})::SparseVector{Float64, Int}
    n = norm(v)
    n < 1e-10 ? v : v ./ n
end

# ── Public types ──────────────────────────────────────────────────────────────

"""
    TFIDFModel

Internal representation of a TF-IDF corpus model, constructed by
[`build_tfidf_model`](@ref).

# Fields
- `idf::Dict{String,Float64}`: Smoothed IDF weight per corpus term.
- `term_index::Dict{String,Int}`: Term → column index mapping.
- `vocab::Vector{String}`: Column index → term reverse mapping.
- `stopwords::Set{String}`: Stopwords excluded from tokenisation.
- `ref_vectors::Vector{Tuple{Symbol,Symbol,SparseVector{Float64,Int}}}`:
  Unit-normalised TF-IDF vectors for each `ReferenceDoc`
  as `(label, privilege_type, vector)` triples.
"""
struct TFIDFModel
    idf::Dict{String, Float64}
    term_index::Dict{String, Int}
    vocab::Vector{String}
    stopwords::Set{String}
    ref_vectors::Vector{Tuple{Symbol, Symbol, SparseVector{Float64, Int}}}
end

# ── Public functions ──────────────────────────────────────────────────────────

"""
    build_tfidf_model(corpus::DataFrame, cfg::CorpusConfig) -> TFIDFModel

Build a TF-IDF model from the full corpus.

Tokenises `subject + " " + lastword` for every row, computes smoothed IDF weights
across the corpus, then builds unit-normalised TF-IDF vectors for each
`ReferenceDoc` in `cfg.reference_docs`.

When `cfg.reference_docs` is empty the model's `ref_vectors` field is empty and all
scoring functions are no-ops, so existing call sites require no changes.

# Arguments
- `corpus::DataFrame`: Full message corpus with columns named per `cfg`.
- `cfg::CorpusConfig`: Configuration supplying stopwords and reference docs.

# Returns
A [`TFIDFModel`](@ref).
"""
function build_tfidf_model(corpus::DataFrame, cfg::CorpusConfig)::TFIDFModel
    sw = cfg.stopwords

    # Collect document texts
    texts = String[]
    for row in eachrow(corpus)
        subj = coalesce(getproperty(row, cfg.subject), "")
        body = coalesce(getproperty(row, cfg.lastword), "")
        body_str = body isa Bool ? "" : string(body)
        push!(texts, subj * " " * body_str)
    end
    N = length(texts)

    # Build vocabulary and document-frequency counts
    df_counts = Dict{String, Int}()
    for text in texts
        seen = Set{String}()
        for t in _tokenize(text, sw)
            t ∈ seen && continue
            df_counts[t] = get(df_counts, t, 0) + 1
            push!(seen, t)
        end
    end

    # Build term_index and vocab
    all_terms  = sort!(collect(keys(df_counts)))
    term_index = Dict{String, Int}(t => i for (i, t) in enumerate(all_terms))
    vocab_size = length(all_terms)

    # Smoothed IDF: log((N+1)/(df+1)) + 1
    idf = Dict{String, Float64}(
        t => log((N + 1) / (df_counts[t] + 1)) + 1.0
        for t in all_terms
    )

    # Build reference vectors
    ref_vectors = Tuple{Symbol, Symbol, SparseVector{Float64, Int}}[]
    for rd in cfg.reference_docs
        tokens = _tokenize(rd.text, sw)
        vec    = _tfidf_vector(tokens, idf, term_index, all_terms, vocab_size)
        push!(ref_vectors, (rd.label, rd.privilege_type, _l2_norm(vec)))
    end

    TFIDFModel(idf, term_index, all_terms, sw, ref_vectors)
end

# Internal 3-argument form. Public API: annotate_privilege_scores(tier_df, S::DiscoverySession).
function annotate_privilege_scores(tier_df::DataFrame,
                                    model::TFIDFModel,
                                    cfg::CorpusConfig)::DataFrame
    result = copy(tier_df)
    n      = nrow(result)

    scores = zeros(Float64, n)
    labels = fill(:none, n)

    if !isempty(model.ref_vectors)
        vocab_size = length(model.vocab)
        for (i, row) in enumerate(eachrow(result))
            subj = coalesce(get(row, cfg.subject, ""), "")
            body = coalesce(get(row, cfg.lastword, ""), "")
            body_str = body isa Bool ? "" : string(body)
            tokens = _tokenize(subj * " " * body_str, model.stopwords)
            vec    = _l2_norm(_tfidf_vector(tokens, model.idf,
                                            model.term_index, model.vocab, vocab_size))
            best_score = 0.0
            best_label = :none
            for (_, ptype, ref_vec) in model.ref_vectors
                s = dot(vec, ref_vec)
                if s > best_score
                    best_score = s
                    best_label = ptype
                end
            end
            scores[i] = best_score
            labels[i] = best_score >= cfg.similarity_threshold ? best_label : :none
        end
    end

    result.privilege_score = scores
    result.privilege_label = labels
    result
end

"""
    find_reference_candidates(tier_df::DataFrame, cfg::CorpusConfig;
                              min_chars::Int = 200) -> DataFrame

Surface candidate messages for manual selection as [`ReferenceDoc`](@ref) entries.

Filters `tier_df` to rows where:
- At least one role in `:roles_implicated` corresponds to `InHouse` or `OutsideFirm`
  counsel (not only `RegulatoryAdvisor`).
- `:lastword` length is at least `min_chars`.

Returns columns `:hash`, `:date`, `:sender`, `:roles_implicated`, `:subject`,
`:lastword_preview` (first 300 characters), and `:lastword_chars`, sorted by
`:lastword_chars` descending.

# Workflow
```julia
candidates = find_reference_candidates(t1_full, cfg)
# Inspect a promising row:
t1_full[t1_full.hash .== candidates.hash[1], :lastword]
# Then add to enron_config() as ReferenceDoc(:label, :AC, subject * " " * lastword)
```
"""
function find_reference_candidates(tier_df::DataFrame,
                                    cfg::CorpusConfig;
                                    min_chars::Int = 200)::DataFrame
    # Build set of legal-counsel role labels (InHouse or OutsideFirm only)
    legal_labels = Set{String}(
        rc.label for rc in cfg.roles
        if rc.counsel_type ∈ (InHouse, OutsideFirm)
    )

    function _has_legal_counsel(roles)
        roles isa Vector && any(r ∈ legal_labels for r in roles)
    end

    result = filter(tier_df) do row
        lw = coalesce(get(row, cfg.lastword, ""), "")
        lw_str = lw isa Bool ? "" : string(lw)
        length(lw_str) >= min_chars &&
            _has_legal_counsel(get(row, :roles_implicated, String[]))
    end

    isempty(result) && return DataFrame(
        hash             = String[],
        date             = DateTime[],
        sender           = String[],
        roles_implicated = Vector{String}[],
        subject          = String[],
        lastword_preview = String[],
        lastword_chars   = Int[],
    )

    out = select(result, :hash, :date, :sender, :roles_implicated, cfg.subject => :subject)
    lastwords = [let lw = coalesce(get(row, cfg.lastword, ""), "")
                     lw isa Bool ? "" : string(lw)
                 end for row in eachrow(result)]
    out.lastword_chars   = length.(lastwords)
    out.lastword_preview = [first(lw, 300) for lw in lastwords]
    sort!(out, :lastword_chars, rev=true)
end

"""
    build_community_vocabulary(corpus_df::DataFrame, community_table::DataFrame,
                               cfg::CorpusConfig) -> Dict{Int32, Vector{Pair{String,Float64}}}

Build a TF-IDF vocabulary for each community from corpus subject lines and body text.

# Arguments
- `corpus_df::DataFrame`: Full corpus with columns named per `cfg`.
- `community_table::DataFrame`: Community membership with `:node` and `:community_id`.
- `cfg::CorpusConfig`: Configuration supplying stopwords and column name mappings.

# Returns
`Dict{Int32, Vector{Pair{String,Float64}}}` — each community ID maps to a list of
`(term => tfidf_score)` pairs sorted by descending score (top 50 terms).
"""
function build_community_vocabulary(corpus_df::DataFrame,
                                     community_table::DataFrame,
                                     cfg::CorpusConfig
                                    )::Dict{Int32, Vector{Pair{String,Float64}}}
    model = build_tfidf_model(corpus_df, cfg)

    node_to_cid = Dict(r.node => r.community_id for r in eachrow(community_table))
    cids        = unique(community_table.community_id)
    cid_tfs     = Dict{Int32, Dict{String, Float64}}(cid => Dict() for cid in cids)

    for row in eachrow(corpus_df)
        sender = coalesce(getproperty(row, cfg.sender), "")
        haskey(node_to_cid, sender) || continue
        cid  = node_to_cid[sender]
        subj = coalesce(getproperty(row, cfg.subject), "")
        body = coalesce(getproperty(row, cfg.lastword), "")
        body_str = body isa Bool ? "" : string(body)
        for t in _tokenize(subj * " " * body_str, cfg.stopwords)
            cid_tfs[cid][t] = get(cid_tfs[cid], t, 0.0) + 1.0
        end
    end

    result = Dict{Int32, Vector{Pair{String,Float64}}}()
    for cid in cids
        tf_map = cid_tfs[cid]
        scored = [t => tf * get(model.idf, t, 1.0) for (t, tf) in tf_map]
        sort!(scored, by=last, rev=true)
        result[cid] = first(scored, 50)
    end
    result
end
