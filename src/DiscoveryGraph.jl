module DiscoveryGraph

using Artifacts
using Arrow
using DataFrames
using Dates
using Graphs
using LazyArtifacts
using LibPQ
using Libdl
using LinearAlgebra
using PythonCall
using Random
using SimpleWeightedGraphs
using SparseArrays
using Statistics
using StatsBase

# Schema layer
include("schema/config.jl")
include("schema/validate.jl")
include("schema/loaders/enron.jl")
include("schema/loaders/builder.jl")
include("schema/loaders/xlsx_config.jl")

# Network layer
include("network/parse_addrs.jl")
include("network/bots.jl")
include("network/edges.jl")
include("network/community.jl")
include("network/history.jl")

# Discovery layer
include("discovery/roles.jl")
include("discovery/tfidf.jl")
include("discovery/clusters.jl")
include("discovery/privilege_log.jl")
include("discovery/temporal.jl")
include("discovery/rule26f.jl")
include("discovery/outputs.jl")

# ── Schema ──────────────────────────────────────────────────────────────────
export CounselType, NotCounsel, InHouse, OutsideFirm, RegulatoryAdvisor
export RoleConfig
export ReferenceDoc
export CorpusConfig
export load_corpus
export enron_config, enron_corpus
export build_corpus_config
export write_config_template, config_from_xlsx
export ENRON_HOTBUTTON_EXAMPLES, ENRON_TIER1_EXAMPLES
export DEFAULT_TIER1_KEYWORDS, DEFAULT_TIER2_KEYWORDS, DEFAULT_TIER3_KEYWORDS

# ── Network ──────────────────────────────────────────────────────────────────
export extract_addrs
export is_bot, identify_bots
export build_edges
export build_snapshot_graph, leiden_communities, jaccard, build_kernel, match_communities, community_subgraphs
export build_node_history
export nv, ne

# ── Discovery ────────────────────────────────────────────────────────────────
export find_roles, identify_counsel_communities, audit_counsel_coverage
export ATTORNEY_KEYWORDS
export DiscoverySession, eyeball, inspect_community, inspect_bridge, review_all_communities
export cluster_tier_subgraph
export TierClass, Tier1, Tier2, Tier3, Tier4, Tier5
export generate_outputs
export detect_anomalies
export TFIDFModel, build_tfidf_model, annotate_privilege_scores
export find_reference_candidates
export build_community_vocabulary
export generate_rule26f_memo
export write_outputs

end # module DiscoveryGraph
