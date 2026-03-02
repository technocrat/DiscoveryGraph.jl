module DiscoveryGraph

using Artifacts
using Arrow
using DataFrames
using Dates
using Graphs
using PythonCall
using Random
using SimpleWeightedGraphs
using Statistics
using StatsBase

# Schema layer
include("schema/config.jl")
include("schema/validate.jl")
include("schema/loaders/enron.jl")

# Network layer
include("network/parse_addrs.jl")
include("network/bots.jl")
include("network/edges.jl")
include("network/community.jl")
include("network/history.jl")

# Discovery layer
include("discovery/roles.jl")
include("discovery/clusters.jl")
include("discovery/privilege_log.jl")
include("discovery/temporal.jl")
include("discovery/tfidf.jl")
include("discovery/rule26f.jl")

# ── Schema ──────────────────────────────────────────────────────────────────
export CounselType, NotCounsel, InHouse, OutsideFirm
export RoleConfig
export CorpusConfig
export load_corpus
export enron_config, enron_corpus

# ── Network ──────────────────────────────────────────────────────────────────
export extract_addrs
export is_bot, identify_bots
export build_edges
export build_snapshot_graph, leiden_communities, jaccard, build_kernel, match_communities
export build_node_history

# ── Discovery ────────────────────────────────────────────────────────────────
export find_roles
export DiscoverySession, eyeball, inspect_community, inspect_bridge, review_all_communities
export TierClass, Tier1, Tier2, Tier3, Tier4, Tier5
export generate_outputs
export detect_anomalies
export build_community_vocabulary
export generate_rule26f_memo

end # module DiscoveryGraph
