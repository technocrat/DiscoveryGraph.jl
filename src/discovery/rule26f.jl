# src/discovery/rule26f.jl
using DataFrames, Dates

function generate_rule26f_memo(S::DiscoverySession, outputs::NamedTuple)::String
    cfg         = S.cfg
    corpus_n    = nrow(S.corpus_df)
    queue_n     = nrow(outputs.review_queue)
    reduction   = corpus_n > 0 ? round(corpus_n / max(queue_n, 1), digits=1) : 0.0
    ct = outputs.community_table
    for required_col in (:is_counsel, :roles)
        required_col ∈ propertynames(ct) || error(
            "community_table is missing column :$required_col — " *
            "ensure generate_outputs received the output of find_roles(node_reg, cfg)"
        )
    end
    n_counsel     = count(r -> r.is_counsel, eachrow(ct))
    n_communities = :community_id ∈ propertynames(ct) ?
        length(unique(ct.community_id)) : 0
    role_labels   = unique(vcat([r.roles for r in eachrow(ct)]...))
    role_list   = isempty(role_labels) ? "(none identified)" : join(role_labels, ", ")
    run_date    = Dates.format(today(), "yyyy-mm-dd")

    """
# Rule 26(f)(3)(D) Privilege Log Methodology Statement
**Generated:** $run_date
**Package:** DiscoveryGraph.jl v0.1.0 — [Zenodo DOI: pending registration]

## Corpus

| Metric | Value |
|--------|-------|
| Total messages | $(corpus_n) |
| Review queue (Tier 1–4) | $(queue_n) |
| Reduction ratio | $(reduction):1 |
| Corpus period | $(Dates.format(Date(cfg.corpus_start), "yyyy-mm-dd")) to $(Dates.format(Date(cfg.corpus_end), "yyyy-mm-dd")) |
| Baseline period | $(Dates.format(Date(cfg.baseline_start), "yyyy-mm-dd")) to $(Dates.format(Date(cfg.baseline_end), "yyyy-mm-dd")) |

## Community Detection

Algorithm: Leiden (Python leidenalg via PythonCall), resolution = 1.0 (default; may vary by run).
Communities identified: $(n_communities).
Kernel threshold: $(round(cfg.kernel_threshold * 100, digits=0))%.
Jaccard continuity threshold: $(cfg.kernel_jaccard_min).

## Attorney/Role Roster

Roles identified: $(role_list).
Nodes with counsel function: $(n_counsel).
Role identification is a precondition for privilege analysis, not a privilege determination.

## Tiering Criteria

| Tier | Description | Disposition |
|------|-------------|-------------|
| Tier 1 | Litigation anticipation, regulatory investigation | Immediate human review |
| Tier 2 | Regulatory, legal advice | Secondary human review |
| Tier 3 | Transactional (likely waived) | Deprioritized |
| Tier 4 | Unclassified — semantic analysis inconclusive | Human judgment required |
| Tier 5 | No counsel involvement | Excluded from privilege review |

Semantic analysis: v0.1.0 stub classifier (counsel-involved messages → Tier 4 pending TF-IDF).

## Reproducibility

Complete methodology deposited at Zenodo [DOI: pending].
"""
end
