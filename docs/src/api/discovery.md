# Discovery Layer

The discovery layer provides privilege triage, interactive inspection, temporal anomaly
detection, community vocabulary analysis, and Rule 26(f) documentation.

## Role Detection

```@docs
find_roles
identify_counsel_communities
audit_counsel_coverage
ATTORNEY_KEYWORDS
```

## Semantic Scoring

```@docs
TFIDFModel
build_tfidf_model
annotate_privilege_scores
find_reference_candidates
cluster_tier_subgraph
```

## Interactive Session

```@docs
DiscoverySession
eyeball
inspect_community
inspect_bridge
review_all_communities
```

## Privilege Triage

```@docs
TierClass
generate_outputs
```

## Outputs

```@docs
write_outputs
```

## Temporal Analysis

```@docs
detect_anomalies
```

## Community Vocabulary

```@docs
build_community_vocabulary
```

## Rule 26(f) Documentation

```@docs
generate_rule26f_memo
```
