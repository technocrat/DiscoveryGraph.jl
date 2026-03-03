# src/discovery/rule26f.jl
using DataFrames, Dates

"""
    generate_rule26f_memo(S::DiscoverySession, outputs::NamedTuple) -> String

Generate a Rule 26(f)(3)(D) privilege log methodology statement as a Markdown string.

Produces a structured memo suitable for filing or service that documents:
- Corpus size and the reduction ratio achieved by the review queue.
- Community detection algorithm, parameters, and thresholds.
- Attorney/role roster derived from `outputs.community_table`.
- The five-tier classification scheme and the v0.1.0 semantic analysis caveat.
- A reproducibility reference (Zenodo DOI pending in v0.1.0).

`outputs` must be the result of `generate_outputs(S, node_reg)` where `node_reg` was
produced by `find_roles`. The `outputs.community_table` must contain columns
`:is_counsel` and `:roles`.

# Arguments
- `S::DiscoverySession`: The active discovery session (supplies corpus size and `cfg`).
- `outputs::NamedTuple`: Named tuple returned by `generate_outputs`, with fields
  `community_table`, `review_queue`, and `anomaly_list`.

# Returns
A `String` containing the complete methodology memo in Markdown format.

# Example
```julia
node_reg = find_roles(base_reg, cfg)
outputs  = generate_outputs(S, node_reg)
memo     = generate_rule26f_memo(S, outputs)
write("rule26f_memo.md", memo)
```
"""
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
    # Split counsel nodes by detection method: explicit address list vs domain/pattern
    n_explicit = count(
        r -> r.is_counsel && any(r.node ∈ rc.explicit_addresses for rc in cfg.roles),
        eachrow(ct),
    )
    n_auto = n_counsel - n_explicit
    n_communities = :community_id ∈ propertynames(ct) ?
        length(unique(ct.community_id)) : 0
    role_labels   = unique(vcat([r.roles for r in eachrow(ct)]...))
    role_list   = isempty(role_labels) ? "(none identified)" : join(role_labels, ", ")
    run_date    = Dates.format(today(), "yyyy-mm-dd")

    t1 = haskey(outputs, :tier1) ? nrow(outputs.tier1) : 0
    t2 = haskey(outputs, :tier2) ? nrow(outputs.tier2) : 0
    t3 = haskey(outputs, :tier3) ? nrow(outputs.tier3) : 0
    t4 = haskey(outputs, :tier4) ? nrow(outputs.tier4) : 0
    t5 = corpus_n - queue_n

    # Bot/broadcast filter audit
    sender_col   = cfg.sender
    all_senders  = unique(S.corpus_df[!, sender_col])
    bot_addrs    = filter(s -> is_bot(s, cfg), all_senders)
    n_bot_msgs   = count(r -> is_bot(getproperty(r, sender_col), cfg), eachrow(S.corpus_df))
    bot_sample   = join(first(sort(bot_addrs), 10), ", ")

    hotbutton_section = if !isempty(cfg.hotbutton_keywords)
        "**Case-specific escalation terms (corpus-specific; auto-Tier 1 — replace entirely " *
        "when adapting for a different matter):** " *
        join(cfg.hotbutton_keywords, ", ") * "\n\n"
    else
        "**Case-specific escalation terms:** none configured for this matter.\n\n"
    end
    kw1 = join(cfg.tier1_keywords, ", ")
    kw2 = join(cfg.tier2_keywords, ", ")
    kw3 = join(cfg.tier3_keywords, ", ")

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
| Schema version | $(cfg.schema_version) |

## Bot/Broadcast Filter

| Metric | Value |
|--------|-------|
| Messages excluded (bot/broadcast sender) | $(n_bot_msgs) |
| Unique bot addresses identified | $(length(bot_addrs)) |

Bot identification applies pattern matching against `cfg.bot_patterns` and exact
membership in `cfg.bot_senders`. Sample excluded addresses (up to 10): $(bot_sample).

## Community Detection

Algorithm: Leiden (Python leidenalg via PythonCall), resolution = $(S.leiden_resolution), seed = $(S.leiden_seed).
Communities identified: $(n_communities).
Kernel threshold: $(round(cfg.kernel_threshold * 100, digits=0))%.
Jaccard continuity threshold: $(cfg.kernel_jaccard_min).

## Attorney/Role Roster

Roles identified: $(role_list).
Nodes with counsel function: $(n_counsel) ($(n_explicit) explicitly specified by address; $(n_auto) auto-detected by domain or pattern match).
The explicit address list was verified and supplemented by `audit_counsel_coverage` QC;
personal accounts and seconded attorneys may not be captured by domain matching alone.
Role identification is a precondition for privilege analysis, not a privilege determination.

## Tiering Criteria

Classification applies to message subject and full thread text (case-insensitive).
First matching rule assigns the tier.

$(hotbutton_section)**Standard keyword lists (matter-independent defaults; may be extended via `CorpusConfig` but not replaced):**
- Tier 1: $kw1
- Tier 2: $kw2
- Tier 3: $kw3

| Tier | Description | Count | Disposition |
|------|-------------|-------|-------------|
| Tier 1 | Litigation anticipation, regulatory investigation | $t1 | Immediate human review |
| Tier 2 | Regulatory, legal advice | $t2 | Secondary human review |
| Tier 3 | Transactional (likely waived) | $t3 | Deprioritized |
| Tier 4 | Unclassified — no keyword signal | $t4 | Human judgment required |
| Tier 5 | No counsel involvement | $t5 | Excluded from privilege review |

## Reproducibility

Complete methodology deposited at Zenodo [DOI: pending].
"""
end
