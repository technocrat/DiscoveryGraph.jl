# Semantic Privilege Scoring Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add TF-IDF privilege scoring and tier1 re-clustering to DiscoveryGraph.jl so every future matter automatically receives per-message AC/WP similarity scores alongside the existing keyword tier classification.

**Architecture:** `ReferenceDoc` structs in `CorpusConfig` carry ur-privilege examples; `build_tfidf_model` (called inside `DiscoverySession`) builds IDF from the full corpus and unit-normalises reference doc vectors; `annotate_privilege_scores` appends `:privilege_score` / `:privilege_label` to every tier DataFrame; `cluster_tier_subgraph` re-runs Leiden on the tier1 subgraph to surface subcommunities. All new behaviour is a no-op when `cfg.reference_docs` is empty.

**Tech stack:** Julia; `SparseArrays` + `LinearAlgebra` (both stdlib, no new deps); existing `PythonCall`/`leidenalg` for re-clustering.

---

## Orientation — key file locations

| Purpose | File |
|---------|------|
| Config types | `src/schema/config.jl` |
| TF-IDF (stub to replace) | `src/discovery/tfidf.jl` |
| DiscoverySession struct | `src/discovery/clusters.jl` |
| generate_outputs | `src/discovery/privilege_log.jl` |
| Arrow write helper | `src/discovery/outputs.jl` |
| Enron reference config | `src/schema/loaders/enron.jl` |
| Module + exports | `src/DiscoveryGraph.jl` |
| Tests | `test/runtests.jl` |
| Test fixtures | `test/fixtures.jl` |

`DiscoverySession` fields are `corpus_df`, `result`, `edge_df`, `cfg`, `leiden_seed`, `leiden_resolution` — note `corpus_df` and `edge_df`, not `corpus`/`edges`.

The existing fixture corpus (`test/fixtures.jl`) uses `Bool` for `:lastword`. New TF-IDF tests need a separate fixture with `String` lastwords — add it to `fixtures.jl`.

---

## Task 1: `ReferenceDoc` struct + `CorpusConfig` additions

**Files:**
- Modify: `src/schema/config.jl`
- Modify: `test/runtests.jl`

**Step 1: Write the failing test**

In `test/runtests.jl`, add inside the existing outer `@testset "DiscoveryGraph"`:

```julia
@testset "ReferenceDoc and CorpusConfig additions" begin
    rd = ReferenceDoc(:AC_test, :AC, "attorney client advice subpoena")
    @test rd.label          === :AC_test
    @test rd.privilege_type === :AC
    @test rd.text           == "attorney client advice subpoena"

    # CorpusConfig accepts reference_docs and similarity_threshold
    cfg_with_refs = CorpusConfig(; FIXTURE_CONFIG_ARGS...,
        roles          = [],
        reference_docs = [rd],
        similarity_threshold = 0.2,
    )
    @test length(cfg_with_refs.reference_docs) == 1
    @test cfg_with_refs.similarity_threshold   == 0.2

    # Defaults: empty reference_docs, threshold 0.15
    cfg_default = CorpusConfig(; FIXTURE_CONFIG_ARGS..., roles = [])
    @test isempty(cfg_default.reference_docs)
    @test cfg_default.similarity_threshold == 0.15
end
```

**Step 2: Run to confirm it fails**

```bash
julia --project=. -e 'using Pkg; Pkg.test()' 2>&1 | grep -E "FAIL|ERROR|ReferenceDoc"
```

Expected: `UndefVarError: ReferenceDoc not defined`

**Step 3: Implement**

In `src/schema/config.jl`, add immediately after the `@enum CounselType` block (before `RoleConfig`):

```julia
"""
    ReferenceDoc

A canonical privilege example used by [`build_tfidf_model`](@ref) to construct
TF-IDF reference vectors for attorney-client (`:AC`) and work-product (`:WP`)
privilege scoring.

# Fields
- `label::Symbol`: Unique identifier (e.g. `:AC_shackleton_advice`).
- `privilege_type::Symbol`: Either `:AC` (attorney-client) or `:WP` (work product).
- `text::String`: Concatenated subject and body of the canonical message.
"""
struct ReferenceDoc
    label::Symbol
    privilege_type::Symbol
    text::String
end
```

Add two fields to the `CorpusConfig` struct (after `tier3_keywords` and before `schema_version`):

```julia
    reference_docs::Vector{ReferenceDoc}
    similarity_threshold::Float64
```

Add keyword arguments to the `CorpusConfig` keyword constructor (after `tier3_keywords`):

```julia
    reference_docs::Vector{ReferenceDoc}   = ReferenceDoc[],
    similarity_threshold::Float64          = 0.15,
```

Add to the inner positional constructor call (after `tier3_keywords`):

```julia
        reference_docs, similarity_threshold,
```

**Step 4: Run tests**

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Expected: all previous tests pass + new testset passes.

**Step 5: Commit**

```bash
git add src/schema/config.jl test/runtests.jl
git commit -m "feat: add ReferenceDoc struct and CorpusConfig fields for TF-IDF scoring"
```

---

## Task 2: TF-IDF model infrastructure

**Files:**
- Modify: `src/discovery/tfidf.jl`
- Modify: `test/fixtures.jl`
- Modify: `test/runtests.jl`

**Step 1: Add TF-IDF fixture corpus to `test/fixtures.jl`**

Append to `test/fixtures.jl`:

```julia
# TF-IDF test fixtures — requires String lastword (existing corpus uses Bool)
function make_tfidf_corpus()
    t0 = DateTime(2000, 7, 1)
    DataFrame(
        hash     = [lpad(string(i), 32, "0") for i in 101:115],
        sender   = vcat(
            fill("alice@corp.com",   5),   # AC-flavoured
            fill("bob@lawfirm.com",  5),   # WP-flavoured
            fill("charlie@corp.com", 5),   # noise
        ),
        tos      = fill("['diana@corp.com']", 15),
        ccs      = fill("[]", 15),
        date     = [t0 + Day(i) for i in 1:15],
        subj     = vcat(
            fill("attorney client privilege advice",          5),
            fill("confidential work product litigation strategy", 5),
            fill("quarterly scheduling update meeting",       5),
        ),
        lastword = vcat(
            fill("Please advise on attorney client privilege. We need legal counsel advice on the subpoena response.",           5),
            fill("Confidential work product. Mental impressions regarding litigation strategy. Do not disclose privileged memo.", 5),
            fill("Can we meet Tuesday for the quarterly review? Please confirm your availability for the scheduling update.",     5),
        ),
    )
end

const FIXTURE_TFIDF_CORPUS = make_tfidf_corpus()

function make_tfidf_reference_docs()
    [
        ReferenceDoc(
            :AC_ref, :AC,
            "attorney client privilege advice legal counsel subpoena response",
        ),
        ReferenceDoc(
            :WP_ref, :WP,
            "confidential work product mental impressions litigation strategy privileged memo",
        ),
    ]
end
```

**Step 2: Write the failing test**

In `test/runtests.jl`, add:

```julia
@testset "TFIDFModel construction" begin
    ref_docs = make_tfidf_reference_docs()
    cfg = CorpusConfig(; FIXTURE_CONFIG_ARGS..., roles = [],
                         reference_docs = ref_docs)
    model = build_tfidf_model(FIXTURE_TFIDF_CORPUS, cfg)

    # IDF populated for corpus terms
    @test !isempty(model.idf)
    @test all(isfinite(v) && v > 0 for v in values(model.idf))

    # Stopwords excluded from IDF
    @test !haskey(model.idf, "the")
    @test !haskey(model.idf, "for")

    # ref_vectors: one per ReferenceDoc, unit-normalised
    @test length(model.ref_vectors) == 2
    @test model.ref_vectors[1][1] === :AC_ref
    @test model.ref_vectors[1][2] === :AC
    @test abs(LinearAlgebra.norm(model.ref_vectors[1][3]) - 1.0) < 1e-9

    # Empty reference_docs → empty ref_vectors but IDF still built
    cfg_empty = CorpusConfig(; FIXTURE_CONFIG_ARGS..., roles = [])
    model_empty = build_tfidf_model(FIXTURE_TFIDF_CORPUS, cfg_empty)
    @test isempty(model_empty.ref_vectors)
    @test !isempty(model_empty.idf)
end
```

**Step 3: Run to confirm it fails**

```bash
julia --project=. -e 'using Pkg; Pkg.test()' 2>&1 | grep -E "FAIL|ERROR|TFIDFModel"
```

Expected: `UndefVarError: TFIDFModel not defined`

**Step 4: Implement `TFIDFModel` and `build_tfidf_model`**

Replace the entire contents of `src/discovery/tfidf.jl` with:

```julia
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
    vals = [tf[i] * idf[_reverse_term(term_index, i)] for i in inds]
    SparseVector(vocab_size, inds, vals)
end

# Build term → index reverse map (called once during model construction)
function _reverse_index(term_index::Dict{String, Int})::Vector{String}
    rev = Vector{String}(undef, length(term_index))
    for (term, idx) in term_index
        rev[idx] = term
    end
    rev
end

function _l2_norm(v::SparseVector{Float64, Int})::SparseVector{Float64, Int}
    n = norm(v)
    n < 1e-10 ? v : v ./ n
end

# ── Public types ──────────────────────────────────────────────────────────────

"""
    TFIDFModel

Internal representation of a TF-IDF corpus model, constructed by
[`build_tfidf_model`](@ref) and stored on [`DiscoverySession`](@ref).

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

Called automatically inside the [`DiscoverySession`](@ref) 6-argument constructor;
results are cached on the session and reused by all scoring functions.

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
    all_terms   = sort!(collect(keys(df_counts)))
    term_index  = Dict{String, Int}(t => i for (i, t) in enumerate(all_terms))
    vocab_size  = length(all_terms)

    # Smoothed IDF: log((N+1)/(df+1)) + 1
    idf = Dict{String, Float64}(
        t => log((N + 1) / (df_counts[t] + 1)) + 1.0
        for t in all_terms
    )

    # Build reference vectors
    ref_vectors = Tuple{Symbol, Symbol, SparseVector{Float64, Int}}[]
    for rd in cfg.reference_docs
        tokens = _tokenize(rd.text, sw)
        vec    = _tfidf_vector(tokens, idf, term_index, vocab_size)
        push!(ref_vectors, (rd.label, rd.privilege_type, _l2_norm(vec)))
    end

    TFIDFModel(idf, term_index, all_terms, sw, ref_vectors)
end

"""
    annotate_privilege_scores(tier_df::DataFrame, S::DiscoverySession) -> DataFrame

Append `:privilege_score::Float64` and `:privilege_label::Symbol` columns to `tier_df`.

Each row's `subject + lastword` is scored against every reference vector in
`S.tfidf_model`. The best cosine similarity is recorded as `:privilege_score`; the
corresponding privilege type (`:AC`, `:WP`) is recorded as `:privilege_label` when
the score meets `S.cfg.similarity_threshold`, otherwise `:none`.

Returns a copy; `tier_df` is not mutated. When `S.tfidf_model.ref_vectors` is empty
the two columns are added with values `0.0` and `:none` for every row (no-op).

# Arguments
- `tier_df::DataFrame`: Any tier DataFrame from `generate_outputs`.
- `S::DiscoverySession`: Active session carrying the TF-IDF model and config.
"""
function annotate_privilege_scores(tier_df::DataFrame,
                                    S::DiscoverySession)::DataFrame
    model  = S.tfidf_model
    cfg    = S.cfg
    result = copy(tier_df)
    n      = nrow(result)

    scores = zeros(Float64, n)
    labels = fill(:none, n)

    if !isempty(model.ref_vectors)
        vocab_size = length(model.vocab)
        for (i, row) in enumerate(eachrow(result))
            subj = coalesce(get(row, :subject, ""), "")
            body = coalesce(get(row, :lastword, ""), "")
            body_str = body isa Bool ? "" : string(body)
            tokens = _tokenize(subj * " " * body_str, model.stopwords)
            vec    = _l2_norm(_tfidf_vector(tokens, model.idf,
                                            model.term_index, vocab_size))
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
        lw = coalesce(get(row, :lastword, ""), "")
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

    out = select(result, :hash, :date, :sender, :roles_implicated, :subject)
    lastwords = [let lw = coalesce(get(row, :lastword, ""), "")
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
    # Build a minimal TFIDFModel from corpus for IDF weights
    model = build_tfidf_model(corpus_df, CorpusConfig(;
        sender         = cfg.sender,
        recipients_to  = cfg.recipients_to,
        recipients_cc  = cfg.recipients_cc,
        timestamp      = cfg.timestamp,
        subject        = cfg.subject,
        hash           = cfg.hash,
        lastword       = cfg.lastword,
        corpus_start   = cfg.corpus_start,
        corpus_end     = cfg.corpus_end,
        baseline_start = cfg.baseline_start,
        baseline_end   = cfg.baseline_end,
        roles          = cfg.roles,
        stopwords      = cfg.stopwords,
    ))

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
```

**Step 5: Run tests**

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Expected: all tests pass including new `TFIDFModel construction` testset.

**Step 6: Commit**

```bash
git add src/discovery/tfidf.jl test/fixtures.jl test/runtests.jl
git commit -m "feat: implement TFIDFModel, build_tfidf_model, annotate_privilege_scores, find_reference_candidates, build_community_vocabulary"
```

---

## Task 3: Scoring tests

**Files:**
- Modify: `test/runtests.jl`

**Step 1: Write failing tests**

Add three testsets to `test/runtests.jl`:

```julia
@testset "annotate_privilege_scores" begin
    ref_docs = make_tfidf_reference_docs()
    cfg = CorpusConfig(; FIXTURE_CONFIG_ARGS..., roles = [],
                         reference_docs = ref_docs)
    model = build_tfidf_model(FIXTURE_TFIDF_CORPUS, cfg)

    # Build a minimal DiscoverySession-like object — use the 6-arg constructor
    # with a dummy result and edge_df (scoring doesn't use them)
    dummy_result = DataFrame(node=String[], community_id=Int32[])
    dummy_edges  = DataFrame(sender=String[], recipient=String[],
                              date=DateTime[], weight=Float64[])
    S = DiscoverySession(FIXTURE_TFIDF_CORPUS, dummy_result,
                          dummy_edges, cfg, 42, 1.0)

    # tier_df uses :subject and :lastword columns matching FIXTURE_TFIDF_CORPUS schema
    tier_df = select(FIXTURE_TFIDF_CORPUS, :hash, :sender, :date, :subj => :subject, :lastword)
    # Add roles_implicated column required by annotate_privilege_scores
    tier_df.roles_implicated = [String[] for _ in 1:nrow(tier_df)]

    scored = annotate_privilege_scores(tier_df, S)

    @test :privilege_score ∈ propertynames(scored)
    @test :privilege_label ∈ propertynames(scored)
    @test eltype(scored.privilege_score) == Float64
    @test eltype(scored.privilege_label) == Symbol

    # AC rows (1:5) should score highest for :AC
    ac_labels = scored[1:5, :privilege_label]
    @test count(==(:AC), ac_labels) >= 3

    # WP rows (6:10) should score highest for :WP
    wp_labels = scored[6:10, :privilege_label]
    @test count(==(:WP), wp_labels) >= 3

    # Noise rows (11:15) should mostly be :none
    noise_labels = scored[11:15, :privilege_label]
    @test count(==(:none), noise_labels) >= 3
end

@testset "annotate_privilege_scores no-op when no ref docs" begin
    cfg = CorpusConfig(; FIXTURE_CONFIG_ARGS..., roles = [])
    dummy_result = DataFrame(node=String[], community_id=Int32[])
    dummy_edges  = DataFrame(sender=String[], recipient=String[],
                              date=DateTime[], weight=Float64[])
    S = DiscoverySession(FIXTURE_TFIDF_CORPUS, dummy_result, dummy_edges, cfg, 42, 1.0)
    tier_df = select(FIXTURE_TFIDF_CORPUS, :hash, :sender, :date,
                      :subj => :subject, :lastword)
    tier_df.roles_implicated = [String[] for _ in 1:nrow(tier_df)]

    scored = annotate_privilege_scores(tier_df, S)
    @test all(==(0.0), scored.privilege_score)
    @test all(==(:none), scored.privilege_label)
end

@testset "find_reference_candidates" begin
    in_house = RoleConfig("in_house_counsel", InHouse, Regex[], String[],
                           Set(["alice@corp.com"]))
    reg_only = RoleConfig("regulatory_affairs", RegulatoryAdvisor, Regex[], String[],
                           Set(["charlie@corp.com"]))
    cfg = CorpusConfig(; FIXTURE_CONFIG_ARGS..., roles = [in_house, reg_only])

    # Build a tier_df with roles_implicated and lastword columns
    tier_df = DataFrame(
        hash             = ["h1", "h2", "h3", "h4"],
        date             = fill(DateTime(2000, 7, 1), 4),
        sender           = ["alice@corp.com", "alice@corp.com",
                             "charlie@corp.com", "alice@corp.com"],
        roles_implicated = [
            ["in_house_counsel"],      # InHouse — long body → should appear
            ["in_house_counsel"],      # InHouse — short body → filtered out
            ["regulatory_affairs"],    # RegulatoryAdvisor only → filtered out
            ["in_house_counsel"],      # InHouse — long body → should appear
        ],
        subject  = ["Advice on litigation", "Brief note",
                     "Regulatory filing", "Work product memo"],
        lastword = [
            "a"^250,   # long
            "short",   # too short
            "a"^250,   # regulatory only — filtered
            "b"^300,   # long
        ],
    )

    candidates = find_reference_candidates(tier_df, cfg; min_chars=200)
    @test nrow(candidates) == 2
    @test all(candidates.lastword_chars .>= 200)
    @test issorted(candidates.lastword_chars, rev=true)
    @test :lastword_preview ∈ propertynames(candidates)
    @test all(length.(candidates.lastword_preview) .<= 300)
    # regulatory-only row must not appear
    @test !("charlie@corp.com" ∈ candidates.sender)
end
```

**Step 2: Run to verify tests pass**

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Expected: all tests pass.

**Step 3: Commit**

```bash
git add test/runtests.jl
git commit -m "test: add annotate_privilege_scores and find_reference_candidates testsets"
```

---

## Task 4: `DiscoverySession` gains `tfidf_model` + `cluster_tier_subgraph`

**Files:**
- Modify: `src/discovery/clusters.jl`
- Modify: `test/runtests.jl`

**Step 1: Write failing test**

Add to `test/runtests.jl`:

```julia
@testset "DiscoverySession carries tfidf_model" begin
    cfg = CorpusConfig(; FIXTURE_CONFIG_ARGS..., roles = [])
    dummy_result = DataFrame(node=String[], community_id=Int32[])
    dummy_edges  = DataFrame(sender=String[], recipient=String[],
                              date=DateTime[], weight=Float64[])
    S = DiscoverySession(FIXTURE_TFIDF_CORPUS, dummy_result, dummy_edges, cfg, 42, 1.0)

    @test S.tfidf_model isa TFIDFModel
    @test !isempty(S.tfidf_model.idf)

    # 4-arg constructor still works
    S4 = DiscoverySession(FIXTURE_TFIDF_CORPUS, dummy_result, dummy_edges, cfg)
    @test S4.tfidf_model isa TFIDFModel
    @test S4.leiden_seed == 42
    @test S4.leiden_resolution == 1.0
end
```

**Step 2: Run to confirm it fails**

```bash
julia --project=. -e 'using Pkg; Pkg.test()' 2>&1 | grep -E "FAIL|ERROR|tfidf_model"
```

Expected: `type DiscoverySession has no field tfidf_model`

**Step 3: Update `DiscoverySession` in `src/discovery/clusters.jl`**

Replace the struct definition and constructors (lines 35–46):

```julia
struct DiscoverySession
    corpus_df::DataFrame
    result::DataFrame
    edge_df::DataFrame
    cfg::CorpusConfig
    leiden_seed::Int
    leiden_resolution::Float64
    tfidf_model::TFIDFModel
end

# 6-arg outer constructor: builds TFIDFModel automatically
function DiscoverySession(corpus_df, result, edge_df, cfg,
                           leiden_seed::Int, leiden_resolution::Float64)
    DiscoverySession(corpus_df, result, edge_df, cfg,
                      leiden_seed, leiden_resolution,
                      build_tfidf_model(corpus_df, cfg))
end

# 4-arg backward-compatible constructor
DiscoverySession(corpus_df, result, edge_df, cfg) =
    DiscoverySession(corpus_df, result, edge_df, cfg, 42, 1.0)
```

Also add `cluster_tier_subgraph` to the end of `src/discovery/clusters.jl`:

```julia
"""
    cluster_tier_subgraph(tier_df::DataFrame, S::DiscoverySession) -> DataFrame

Run a fresh Leiden pass on the subgraph induced by the participants in `tier_df`.

Filters `S.edge_df` to edges where both endpoints appear as `:sender` or
`:recipient` in `tier_df`, builds a `SimpleWeightedGraph`, runs
`leiden_communities` with `S.leiden_seed` and `S.leiden_resolution`, and
left-joins the resulting community assignments back onto `tier_df` by
matching `:node == :sender`.

# Returns
A copy of `tier_df` with an added `:subcommunity_id::Int32` column.
Rows with no matching node receive `subcommunity_id = -1`.

# Notes
Requires the Python `leidenalg`/`igraph` environment (managed by CondaPkg).
Will emit a warning and return `tier_df` unchanged (with `subcommunity_id = -1`
for all rows) if fewer than 2 nodes are found in the subgraph.
"""
function cluster_tier_subgraph(tier_df::DataFrame,
                                 S::DiscoverySession)::DataFrame
    # Collect all participant addresses in this tier
    tier_senders = Set(tier_df.sender)
    tier_recips  = !isempty(tier_df) && :recipients ∈ propertynames(tier_df) ?
        Set(Iterators.flatten(split.(coalesce.(tier_df.recipients, ""), r";\s*"))) :
        Set{String}()
    all_addrs = union(tier_senders, tier_recips)

    # Filter edges to subgraph
    sub_edges = filter(r -> r.sender ∈ all_addrs && r.recipient ∈ all_addrs,
                       S.edge_df)

    nodes = unique(vcat(sub_edges.sender, sub_edges.recipient))
    if length(nodes) < 2
        @warn "cluster_tier_subgraph: fewer than 2 nodes; returning unchanged"
        result = copy(tier_df)
        result.subcommunity_id = fill(Int32(-1), nrow(result))
        return result
    end

    node_idx  = Dict(n => i for (i, n) in enumerate(nodes))
    g         = build_snapshot_graph(sub_edges, node_idx, length(nodes))
    sub_result = leiden_communities(g, nodes;
                                     seed       = S.leiden_seed,
                                     resolution = S.leiden_resolution)

    cid_lookup = Dict(r.node => r.community_id for r in eachrow(sub_result))
    result = copy(tier_df)
    result.subcommunity_id = Int32[get(cid_lookup, s, -1)
                                    for s in result.sender]
    result
end
```

**Step 4: Run tests**

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Expected: all tests pass including new `DiscoverySession carries tfidf_model` testset.

**Step 5: Commit**

```bash
git add src/discovery/clusters.jl test/runtests.jl
git commit -m "feat: add tfidf_model to DiscoverySession; add cluster_tier_subgraph"
```

---

## Task 5: Wire into `generate_outputs` + fix Arrow serialisation

**Files:**
- Modify: `src/discovery/privilege_log.jl`
- Modify: `src/discovery/outputs.jl`

**Step 1: Add calls inside `generate_outputs`**

In `src/discovery/privilege_log.jl`, in the `generate_outputs` function, find the block where `tier1`, `tier2`, `tier3`, `tier4` DataFrames are assembled and add immediately after (before the `review_queue = vcat(...)` line):

```julia
    # Semantic privilege scoring (no-op when cfg.reference_docs is empty)
    tier1 = annotate_privilege_scores(tier1, S)
    tier2 = annotate_privilege_scores(tier2, S)
    tier3 = annotate_privilege_scores(tier3, S)
    tier4 = annotate_privilege_scores(tier4, S)

    # Re-cluster tier1 subgraph (requires Python/leidenalg env)
    tier1 = cluster_tier_subgraph(tier1, S)

    review_queue = vcat(tier1, tier2, tier3, tier4)
```

**Step 2: Fix Arrow serialisation in `src/discovery/outputs.jl`**

The `_arrow_safe` helper must coerce the two new columns. Add to the existing `_arrow_safe` function inside `write_outputs`:

```julia
        if :privilege_label ∈ propertynames(out)
            out.privilege_label = string.(out.privilege_label)
        end
        if :subcommunity_id ∈ propertynames(out)
            out.subcommunity_id = Vector{Int32}(out.subcommunity_id)
        end
```

**Step 3: Run tests**

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Expected: all 226+ tests pass.

**Step 4: Commit**

```bash
git add src/discovery/privilege_log.jl src/discovery/outputs.jl
git commit -m "feat: wire annotate_privilege_scores and cluster_tier_subgraph into generate_outputs"
```

---

## Task 6: Exports, docs, version bump

**Files:**
- Modify: `src/DiscoveryGraph.jl`
- Modify: `docs/src/api/schema.md`
- Modify: `docs/src/api/discovery.md`
- Modify: `Project.toml`

**Step 1: Update exports in `src/DiscoveryGraph.jl`**

Add to the Schema export block:

```julia
export ReferenceDoc
```

Add to the Discovery export block:

```julia
export TFIDFModel
export annotate_privilege_scores, find_reference_candidates, cluster_tier_subgraph
```

**Step 2: Update `docs/src/api/schema.md`**

Add `ReferenceDoc` to the Types section:

```markdown
## Types

```@docs
CounselType
RoleConfig
ReferenceDoc
CorpusConfig
```
```

**Step 3: Update `docs/src/api/discovery.md`**

Add a new **Semantic Scoring** section after Role Detection:

```markdown
## Semantic Scoring

```@docs
TFIDFModel
build_tfidf_model
annotate_privilege_scores
find_reference_candidates
cluster_tier_subgraph
```
```

**Step 4: Bump version in `Project.toml`**

```toml
version = "0.3.0"
```

**Step 5: Run final test pass**

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Expected: all tests green.

**Step 6: Build docs locally to catch any missing docstrings**

```bash
julia --project=docs/ -e '
using Pkg
Pkg.develop(PackageSpec(path=pwd()))
Pkg.instantiate()
' && julia --project=docs/ docs/make.jl 2>&1 | grep -E "Error|Warning|missing"
```

Expected: no errors (deprecation warnings from Documenter are OK).

**Step 7: Commit and push**

```bash
git add src/DiscoveryGraph.jl docs/src/api/schema.md docs/src/api/discovery.md Project.toml
git commit -m "feat: export ReferenceDoc, TFIDFModel, scoring functions; bump to v0.3.0"
git push origin master
```

---

## Post-implementation: find ur-privilege examples in the Enron corpus

Once the above is merged, identify the Enron reference docs interactively:

```julia
using DiscoveryGraph, Arrow, DataFrames

corpus = DataFrame(Arrow.Table("/path/to/scrub_intermediate.arrow"))
cfg    = enron_config()
# (build S as normal with leiden result and edges)

t1     = DataFrame(Arrow.Table("data/tier1.arrow"))
corpus_slim = select(corpus, :hash, :lastword)
t1_full = leftjoin(t1, corpus_slim, on = :hash)

# Surface candidates
candidates = find_reference_candidates(t1_full, cfg; min_chars=300)
first(candidates, 20)

# Inspect a promising row
t1_full[t1_full.hash .== candidates.hash[1], :lastword]
```

Pick 2–3 AC and 2–3 WP examples, then add to `enron_config()` in
`src/schema/loaders/enron.jl`:

```julia
reference_docs = [
    ReferenceDoc(:AC_shackleton_advice, :AC,
        "subject line here full body text here"),
    ReferenceDoc(:WP_haedicke_strategy, :WP,
        "subject line here full body text here"),
    # ...
]
```

Re-run the pipeline with the updated config to get scored outputs.
