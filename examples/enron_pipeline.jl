# examples/enron_pipeline.jl
#
# Full Enron walkthrough for DiscoveryGraph.jl
#
# This file demonstrates the complete privilege log triage pipeline using the
# Enron email corpus as a worked example. It replaces the numbered scripts/
# directory from the original Enron analysis project and is designed to be
# read as a tutorial -- each section can be copied to a REPL and run
# independently.
#
# Background: The Enron corpus consists of roughly 500,000 emails preserved
# by FERC subpoena during the post-collapse investigation. It is the largest
# publicly available corporate email dataset and a standard benchmark for
# communication network analysis. Our goal is not historical -- it is to
# demonstrate how DiscoveryGraph.jl maps raw email to a defensible Rule 26(f)
# privilege log methodology.
#
# Pipeline overview:
#   1.  Setup and package loading
#   2.  Load corpus (Arrow file or registered artifact)
#   3.  Validate corpus schema
#   4.  Build broadcast-discounted edge table
#   5.  Baseline community detection (Leiden, Q3 2000)
#   *** MANUAL STEP: identify attorney communities ***
#   6.  Build node registry with role annotations
#   7.  Build weekly node history
#   8.  Assemble DiscoverySession
#   9.  Interactive inspection
#   10. Generate discovery outputs
#   11. Temporal anomaly detection
#   12. Community vocabulary (stub in v0.1.0)
#   13. Rule 26(f) methodology memo

# ============================================================================
# 1. SETUP
# ============================================================================
#
# DiscoveryGraph depends on Python igraph/leidenalg via CondaPkg. On first
# use, resolve the Python environment before loading the package.

using CondaPkg
CondaPkg.resolve()       # downloads igraph + leidenalg if not present

using DiscoveryGraph
using Arrow, DataFrames, Dates

# countmap is used in step 5 for community size reporting
using StatsBase: countmap

# ============================================================================
# 2. LOAD CORPUS
# ============================================================================
#
# enron_config() returns a CorpusConfig pre-wired for the Enron Arrow schema:
#   columns  : sender, tos, ccs, date, subj, hash, lastword
#   window   : 1999-01-01 to 2002-12-31
#   baseline : Q3 2000 (2000-07-01 to 2000-09-30)
#   domain   : enron.com (only internal edges are built)
#   roles    : in_house_counsel (8 named attorneys), outside_counsel (5 firms)
#
# enron_corpus() will eventually load the corpus from the package artifact
# store. In v0.1.0 the artifact is not yet registered, so use a local Arrow
# file produced by the original scripts/02_write_arrow.jl instead.

cfg = enron_config()

# Artifact path (v0.1.0: not yet available -- use the fallback below)
# raw_df = enron_corpus()

# Fallback: load from a local Arrow file.
# Point ENRON_ARROW at your local scrub_intermediate.arrow.
ENRON_ARROW = joinpath(@__DIR__, "..", "data", "scrub_intermediate.arrow")
raw_df = Arrow.Table(ENRON_ARROW) |> DataFrame

# Arrow columns are read-only after loading. The pipeline functions only read
# raw_df, so no conversion is needed here. If you add derived columns later,
# convert the affected column to a plain Vector first:
#   raw_df.some_col = Vector{String}(raw_df.some_col)

# ============================================================================
# 3. VALIDATE CORPUS
# ============================================================================
#
# load_corpus checks that all required columns exist and that sender, hash,
# and timestamp columns contain no missing values. It returns the DataFrame
# unchanged on success so the call can be composed in a pipeline.

corpus = load_corpus(raw_df, cfg)

@info "Corpus loaded" nrow = nrow(corpus) ncol = ncol(corpus)

# ============================================================================
# 4. BUILD EDGES
# ============================================================================
#
# build_edges parses the To/CC fields, discards bot senders and garbage
# addresses, and emits one row per (sender, recipient) pair. Edge weight is
# 1/log(n+2) where n is the total recipient count, so mass broadcasts
# approach zero while one-to-one messages weight approximately 0.91.
#
# Only @enron.com <-> @enron.com edges survive because cfg.internal_domain
# is set to "enron.com". External correspondents appear in the corpus but
# are excluded from the network graph. Outside counsel (Vinson & Elkins,
# Bracewell & Patterson, etc.) are identified through cfg.roles even though
# their addresses do not appear as network nodes.

edges = build_edges(corpus, cfg)

@info "Edge table built" nrow = nrow(edges) unique_senders = length(unique(edges.sender))

# ============================================================================
# 5. BASELINE COMMUNITY DETECTION (Q3 2000)
# ============================================================================
#
# We detect communities in a single quarterly snapshot rather than the full
# corpus for two reasons:
#
#   (a) Stability: Q3 2000 predates the crisis. Communities reflect normal
#       organisational structure, not crisis-induced communication bursts.
#
#   (b) Identity tracking: the baseline kernel (nodes active in >= 2/3 of
#       baseline weeks) is used to match community IDs across later weekly
#       snapshots via Jaccard similarity, giving stable IDs despite Leiden's
#       non-determinism.

baseline = filter(r -> cfg.baseline_start <= r.date <= cfg.baseline_end, edges)

all_nodes = String.(unique(vcat(baseline.sender, baseline.recipient)))
node_idx  = Dict(n => i for (i, n) in enumerate(all_nodes))
n_nodes   = length(all_nodes)

g = build_snapshot_graph(baseline, node_idx, n_nodes)

@info "Baseline graph built" vertices = n_nodes graph_edges = ne(g)

# Run Leiden at resolution 1.0.
#
# IMPORTANT -- NON-DETERMINISM: Leiden community IDs change on every fresh
# run even with the same seed, because the refinement phase uses a randomised
# traversal order. The seed parameter controls only the initial partition, not
# the full trajectory. You MUST visually confirm which IDs correspond to which
# organisational groups after each new run before proceeding to step 6.

result = leiden_communities(g, all_nodes; resolution = 1.0, seed = 42)

comm_sizes = sort(collect(countmap(result.community_id)), by = x -> x[2], rev = true)
@info "Communities detected" n_communities = length(comm_sizes) top5 = first(comm_sizes, 5)

# Identify which communities contain counsel nodes using cfg.roles.
# This replaces manual scanning of review_all_communities output.

counsel_communities = identify_counsel_communities(result, cfg)
println(counsel_communities)

# The output shows community_id, n_members, n_counsel, roles, and counsel_nodes
# for every community with at least one matched attorney. The community with the
# highest n_counsel is the anchor for privilege triage.
#
# *** CONFIRM BEFORE PROCEEDING ***
#
# Leiden community IDs change on every fresh run (non-deterministic traversal).
# identify_counsel_communities narrows the field, but you should still verify:
#
#   1. Confirm the top community contains the expected seed attorneys:
#        sara.shackleton@enron.com    mark.haedicke@enron.com
#        richard.sanders@enron.com    tana.jones@enron.com
#   2. If the legal cluster is fragmented across multiple IDs, rerun with a
#      lower resolution (e.g., resolution=0.5) to merge them.
#   3. Record the confirmed ID as LEGAL_CID for use in step 9 below.
#
# *** END CONFIRMATION STEP ***

# ============================================================================
# 6. BUILD NODE REGISTRY WITH ROLE ANNOTATIONS
# ============================================================================
#
# Build a base node registry from the Leiden result, then use find_roles to
# annotate each node with matched role labels and an is_counsel boolean.
#
# find_roles tests each RoleConfig in cfg.roles against every node address
# using three rules (any match assigns the role):
#   1. Exact membership in rc.explicit_addresses
#   2. Any pattern in rc.address_patterns matches via occursin
#   3. Address ends with @domain or .domain for any domain in rc.domain_list
#
# is_counsel is true for InHouse and OutsideFirm counsel types.
# The base registry needs at minimum a :node column; add :community_id so
# downstream outputs can group counsel by community.

base_node_reg = DataFrame(
    node         = result.node,
    community_id = result.community_id,
)

node_reg = find_roles(base_node_reg, cfg)

n_counsel = count(r -> r.is_counsel, eachrow(node_reg))
@info "Role annotation complete" total = nrow(node_reg) counsel = n_counsel

# ============================================================================
# 7. BUILD WEEKLY NODE HISTORY
# ============================================================================
#
# build_node_history creates a weekly time series for every sender: message
# count, distinct recipient count, and Shannon entropy of the recipient
# distribution. Entropy measures how broadly a sender distributes messages --
# low entropy means the sender concentrates on a small group; high entropy
# indicates broadcast behaviour.
#
# The history covers the full corpus window (cfg.corpus_start to
# cfg.corpus_end), not just the baseline, so anomaly detection in step 11
# can flag changes in the crisis period (late 2001 through 2002).

history = build_node_history(edges, cfg)

@info "Node history built" rows = nrow(history) unique_nodes = length(unique(history.node)) weeks = length(unique(history.week_start))

# ============================================================================
# 8. ASSEMBLE DISCOVERYSESSION
# ============================================================================
#
# DiscoverySession bundles corpus_df, result, edge_df, and cfg so that the
# inspection functions do not require repeated argument passing. All
# interactive calls in step 9 go through this session object.
#
# Build the session now so it is also available when running the manual
# community identification step documented above.

S = DiscoverySession(corpus, result, edges, cfg)

# ============================================================================
# 9. INTERACTIVE INSPECTION
# ============================================================================
#
# Replace the community IDs below with the ones confirmed in the manual step.
# The IDs shown (6 and 9) match one representative run of the original project.

# Sample 20 messages from the legal community during the baseline period,
# in chronological order -- confirms the community function before proceeding
eyeball(S, 9; mode = :chrono, n = 20)

# Print structural metrics: member count and top internal senders by volume
inspect_community(S, 9)

# Count cross-community edges between legal (9) and government affairs (6)
# during Q4 2001 -- the period of peak regulatory pressure -- to assess
# whether attorney communication bridged into the lobbying cluster
inspect_bridge(S, 9, 6;
    start = DateTime(2001, 10, 1),
    stop  = DateTime(2001, 12, 31))

# Print a short sample from every community -- run this immediately after
# Leiden detection to satisfy the manual identification step above
review_all_communities(S; n = 10)

# ============================================================================
# 10. GENERATE DISCOVERY OUTPUTS
# ============================================================================
#
# generate_outputs processes the full corpus and identifies every message
# where at least one party (sender or recipient) is a counsel node. Each
# such message enters the review queue with an initial tier assignment.
#
# In v0.1.0, the semantic classifier is a stub: all counsel-involved messages
# receive Tier4 (inconclusive) pending TF-IDF implementation.
#
# Tier definitions:
#   Tier1 -- litigation anticipation / active regulatory investigation
#   Tier2 -- regulatory compliance / direct legal advice
#   Tier3 -- transactional (privilege likely waived in transactional context)
#   Tier4 -- counsel involved; semantic analysis inconclusive (all in v0.1.0)
#   Tier5 -- no counsel involvement (excluded from review queue)

outputs = generate_outputs(S, node_reg)

@info "Outputs generated" queue = nrow(outputs.review_queue) community_nodes = nrow(outputs.community_table)

println("Review queue -- first 5 rows:")
println(first(outputs.review_queue, 5))

# ============================================================================
# 11. TEMPORAL ANOMALY DETECTION
# ============================================================================
#
# detect_anomalies flags weeks where a node's message count exceeds its
# historical mean by cfg.anomaly_zscore_threshold standard deviations
# (default 2.0 sigma). Nodes with fewer than 3 weeks of history or near-zero
# standard deviation are skipped.
#
# Volume spikes in counsel nodes during the crisis window (October 2001
# onward) are strong candidates for Tier1 escalation -- they correlate with
# the period when FERC began formal investigation and SEC subpoenas followed.

anomalies = detect_anomalies(history, cfg)

@info "Anomalies detected" n = nrow(anomalies)

counsel_set      = Set(filter(r -> r.is_counsel, eachrow(node_reg)).node)
crisis_start     = Date(2001, 10, 1)
crisis_anomalies = filter(
    r -> r.node in counsel_set && r.week_start >= crisis_start,
    anomalies)

@info "Crisis-window counsel anomalies" n = nrow(crisis_anomalies)
println(crisis_anomalies)

# ============================================================================
# 12. COMMUNITY VOCABULARY (STUB IN v0.1.0)
# ============================================================================
#
# build_community_vocabulary will compute TF-IDF term scores from subject
# lines, associating the most distinctive vocabulary with each community.
# This is intended to feed into semantic tiering (Tier1 vs. Tier2 vs. Tier3).
#
# In v0.1.0 the function returns empty term lists for every community.
# Full TF-IDF computation is planned for a future release. The call is
# included here so the pipeline structure is complete and callers can
# substitute their own classifier via cfg.semantic_classifier when
# constructing the CorpusConfig.

vocab = build_community_vocabulary(corpus, result, cfg)

@info "Vocabulary stub complete" communities = length(vocab)
# vocab[9] == Pair{String,Float64}[]  (always empty until TF-IDF is implemented)

# ============================================================================
# 13. RULE 26(f) METHODOLOGY MEMO
# ============================================================================
#
# generate_rule26f_memo produces a Markdown document suitable for filing or
# service under Rule 26(f)(3)(D). It records:
#   - Corpus size and review queue reduction ratio
#   - Community detection algorithm and parameters
#   - Attorney/role roster derived from outputs.community_table
#   - Five-tier classification scheme and v0.1.0 semantic analysis caveat
#   - Reproducibility reference (Zenodo DOI pending in v0.1.0)
#
# outputs must come from generate_outputs called with the find_roles-annotated
# node_reg. The community_table inside outputs must carry :is_counsel and
# :roles columns; generate_outputs enforces this at runtime.

memo = generate_rule26f_memo(S, outputs)

println(memo)

# Write to a file for filing or service
memo_path = joinpath(@__DIR__, "rule26f_memo.md")
write(memo_path, memo)
@info "Memo written" path = memo_path

# ============================================================================
# END OF WALKTHROUGH
# ============================================================================
#
# Artifacts produced by this pipeline:
#
#   edges        DataFrame  broadcast-discounted edge table
#   result       DataFrame  Leiden community membership (Q3 2000 baseline)
#   node_reg     DataFrame  node registry with counsel role flags
#   history      DataFrame  weekly message-count / entropy time series
#   outputs      NamedTuple community_table, review_queue, anomaly_list
#   anomalies    DataFrame  volume-spike flags across the full corpus window
#   vocab        Dict       per-community TF-IDF vocabulary (stub in v0.1.0)
#   memo         String     Rule 26(f)(3)(D) methodology statement (Markdown)
#
# To persist the DataFrames to Arrow files for later use:
#
#   Arrow.write("edges.arrow",    edges;    compress = :zstd)
#   Arrow.write("result.arrow",   result;   compress = :zstd)
#   Arrow.write("node_reg.arrow", node_reg; compress = :zstd)
#   Arrow.write("history.arrow",  history;  compress = :zstd)
