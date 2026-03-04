# Semantic Privilege Scoring — Design

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:writing-plans to create the implementation plan from this design.

**Goal:** Extend DiscoveryGraph.jl with TF-IDF–based semantic privilege scoring and tier1 re-clustering so that future matters automatically receive privilege-candidate scores alongside the existing keyword tier classification.

**Architecture:** Three new components — a `TFIDFModel` built inside `DiscoverySession`, `annotate_privilege_scores` that scores every review-queue message against user-supplied reference documents, and `cluster_tier_subgraph` that runs a fresh Leiden pass on the tier1 subgraph. All are no-ops when no reference documents are configured, so existing call sites are unaffected.

**Tech stack:** Julia; `SparseArrays` (stdlib) for TF-IDF vectors; existing `PythonCall`/`leidenalg` for re-clustering; `DataFrames.jl`; no new dependencies.

---

## Data structures

### `ReferenceDoc` (new, in `src/schema/config.jl`)

```julia
struct ReferenceDoc
    label::Symbol          # e.g. :AC_shackleton_litigation_hold
    privilege_type::Symbol # :AC or :WP
    text::String           # subject + body of the canonical message (free text)
end
```

### `TFIDFModel` (new, in `src/discovery/tfidf.jl`)

```julia
struct TFIDFModel
    idf::Dict{String, Float64}
    stopwords::Set{String}
    ref_vectors::Vector{Tuple{Symbol, Symbol, SparseVector{Float64, Int}}}
    # (label, privilege_type, unit-normalised TF-IDF vector) — one per ReferenceDoc
end
```

`idf` is computed over the full corpus (`subject + " " + lastword`). An empty `TFIDFModel` (no reference docs) has empty `ref_vectors`; `idf` is still populated and available for `build_community_vocabulary`.

### `CorpusConfig` additions (in `src/schema/config.jl`)

Two new optional fields with safe defaults:

```julia
reference_docs::Vector{ReferenceDoc}    # default: ReferenceDoc[]
similarity_threshold::Float64           # default: 0.15
```

Both are keyword arguments to the `CorpusConfig` constructor with the above defaults. No existing call sites require changes.

### `DiscoverySession` addition (in `src/discovery/outputs.jl`)

```julia
struct DiscoverySession
    corpus::DataFrame
    result::DataFrame
    edges::DataFrame
    cfg::CorpusConfig
    leiden_seed::Int
    leiden_resolution::Float64
    tfidf_model::TFIDFModel    # ← new; built at construction time
end
```

The existing 6-argument outer constructor gains one line:

```julia
function DiscoverySession(corpus, result, edges, cfg, seed, resolution)
    DiscoverySession(corpus, result, edges, cfg, seed, resolution,
                     build_tfidf_model(corpus, cfg))
end
```

No call-site changes required.

### Output schema additions

`tier1`, `tier2`, `tier3`, `tier4`, and `review_queue` each gain:

```julia
privilege_score::Float64    # cosine similarity to nearest reference doc (0.0 if no ref docs)
privilege_label::Symbol     # :AC, :WP, or :none
```

`tier1` additionally gains:

```julia
subcommunity_id::Int32      # from fresh Leiden run on tier1 subgraph
```

---

## Public API (`src/discovery/tfidf.jl`)

### `build_tfidf_model` (replaces stub)

```julia
build_tfidf_model(corpus::DataFrame, cfg::CorpusConfig) -> TFIDFModel
```

- Concatenates `subject + " " + lastword` for every corpus row.
- Tokenises: lowercase, split on `\W+`, drop tokens in `cfg.stopwords`, drop tokens shorter than 2 characters.
- Computes IDF: `log((N + 1) / (df + 1)) + 1` (smoothed) where `N` = number of documents, `df` = document frequency of term.
- For each `ReferenceDoc` in `cfg.reference_docs`: tokenise `rc.text`, compute TF (raw count / doc length), multiply by IDF, L2-normalise → `SparseVector`. Store as `(rc.label, rc.privilege_type, vec)` in `ref_vectors`.
- When `cfg.reference_docs` is empty, `ref_vectors` is empty; `idf` is still computed.
- Exported.

### `score_privilege_similarity`

```julia
score_privilege_similarity(texts::Vector{String}, model::TFIDFModel) -> DataFrame
```

- For each text: tokenise, compute TF-IDF vector (using `model.idf`; unknown terms get weight 0), L2-normalise.
- Compute cosine similarity to each reference vector (dot product of unit vectors).
- Return `DataFrame` with columns `:idx` (1-based), `:best_label::Symbol`, `:best_type::Symbol`, `:best_score::Float64`. Best = highest cosine similarity across all reference vectors.
- Not exported (internal helper).

### `annotate_privilege_scores`

```julia
annotate_privilege_scores(tier_df::DataFrame, S::DiscoverySession) -> DataFrame
```

- Concatenates `subject + " " + lastword` per row (coalescing missing to `""`).
- Calls `score_privilege_similarity`.
- Appends `:privilege_score` and `:privilege_label` to a copy of `tier_df`. Label is `:none` when `best_score < cfg.similarity_threshold` or `model.ref_vectors` is empty.
- Exported.

### `find_reference_candidates`

```julia
find_reference_candidates(tier_df::DataFrame, cfg::CorpusConfig;
                          min_chars::Int = 200) -> DataFrame
```

- Filters to rows where:
  - `roles_implicated` contains at least one role whose `counsel_type` is `InHouse` or `OutsideFirm` (not only `RegulatoryAdvisor`).
  - `lastword` length ≥ `min_chars`.
- Adds `:lastword_chars::Int` and `:lastword_preview::String` (first 300 chars of `lastword`).
- Sorts by `:lastword_chars` descending.
- Returns columns `:hash`, `:date`, `:sender`, `:roles_implicated`, `:subject`, `:lastword_preview`, `:lastword_chars`.
- Exported.

### `cluster_tier_subgraph`

```julia
cluster_tier_subgraph(tier_df::DataFrame, S::DiscoverySession) -> DataFrame
```

- Extracts unique sender + recipient addresses from `tier_df`.
- Filters `S.edges` to edges where both endpoints are in that address set.
- Builds a fresh `SimpleWeightedGraph` via `build_snapshot_graph`.
- Runs `leiden_communities` with `S.leiden_seed` and `S.leiden_resolution`.
- Left-joins result back to `tier_df` on `:node == :sender` to assign `:subcommunity_id`.
- Returns copy of `tier_df` with `:subcommunity_id::Int32` column. Rows with no matching node get `subcommunity_id = -1`.
- Exported.

### `build_community_vocabulary` (replaces stub body)

Uses `model.idf` from the session's `TFIDFModel` to compute per-community TF-IDF. Implementation straightforward once the model exists.

---

## Integration with `generate_outputs`

In the inner loop of `generate_outputs`, after building `tier1`/`tier2`/`tier3`/`tier4`:

```julia
# Annotate all tiers with privilege scores (no-op if ref_vectors empty)
tier1 = annotate_privilege_scores(tier1, S)
tier2 = annotate_privilege_scores(tier2, S)
tier3 = annotate_privilege_scores(tier3, S)
tier4 = annotate_privilege_scores(tier4, S)

# Re-cluster tier1 subgraph (requires Python env)
tier1 = cluster_tier_subgraph(tier1, S)

# Rebuild review_queue from annotated tiers
review_queue = vcat(tier1, tier2, tier3, tier4)
```

`community_table` and `anomaly_list` are unchanged.

---

## Enron reference doc workflow

1. Load `t1_full` (tier1 joined to corpus on `:hash`).
2. Call `find_reference_candidates(t1_full, cfg)` to get ranked candidates.
3. For each candidate: inspect `t1_full[t1_full.hash .== hash, :lastword]` to read full body.
4. Pick 2–3 AC examples (attorney giving or receiving direct legal advice) and 2–3 WP examples (litigation strategy, mental impressions).
5. Add to `enron_config()`:

```julia
reference_docs = [
    ReferenceDoc(:AC_shackleton_advice,  :AC, "subject... body..."),
    ReferenceDoc(:AC_derrick_hold,       :AC, "..."),
    ReferenceDoc(:WP_haedicke_strategy,  :WP, "..."),
    ReferenceDoc(:WP_sanders_analysis,   :WP, "..."),
]
```

---

## Testing strategy

Four new testsets in `test/runtests.jl`, all in-memory:

1. **`TFIDFModel construction`** — 10 synthetic messages; verify IDF weights finite and positive; empty `reference_docs` → empty `ref_vectors`; non-empty `reference_docs` → correct `ref_vectors` length and unit norm.

2. **`score_privilege_similarity`** — two reference docs (`:AC`, `:WP`); 6 messages: 2 obviously AC-flavoured, 2 obviously WP-flavoured, 2 noise. Assert AC messages score highest against AC ref; WP against WP; noise below threshold.

3. **`annotate_privilege_scores`** — synthesised `DiscoverySession`; verify `:privilege_score::Float64` and `:privilege_label::Symbol` columns present with correct types; no-op (both columns default) when `reference_docs` empty.

4. **`find_reference_candidates`** — short messages (`< min_chars`) filtered out; regulatory-only rows filtered out; result sorted by `:lastword_chars` descending; expected columns present.

`cluster_tier_subgraph` shares the existing Leiden fixture pattern.

---

## Files to create / modify

| Action | File |
|--------|------|
| Modify | `src/schema/config.jl` — add `ReferenceDoc`, two `CorpusConfig` fields |
| Modify | `src/discovery/tfidf.jl` — replace stub with full implementation |
| Modify | `src/discovery/outputs.jl` — add `tfidf_model` to `DiscoverySession` |
| Modify | `src/discovery/privilege_log.jl` — call `annotate_privilege_scores` + `cluster_tier_subgraph` in `generate_outputs` |
| Modify | `src/schema/loaders/enron.jl` — add `reference_docs` field to `enron_config()` (initially empty; populated after manual candidate selection) |
| Modify | `src/DiscoveryGraph.jl` — export new public symbols |
| Modify | `test/runtests.jl` — four new testsets |
| Modify | `docs/src/api/discovery.md` — add `annotate_privilege_scores`, `find_reference_candidates`, `cluster_tier_subgraph` |
| Modify | `docs/src/api/schema.md` — add `ReferenceDoc` |
