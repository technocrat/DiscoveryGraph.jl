# DiscoveryGraph.jl — communication-network analysis for legal discovery

A Julia package for building, analyzing, and triaging communication networks
from email corpora in legal discovery workflows. Community detection uses the
Leiden algorithm via Python `igraph`/`leidenalg`, which are **required runtime
dependencies** managed automatically through CondaPkg.
The Enron email corpus is the reference implementation; the package is designed
to be adapted for any similarly structured corpus — Bloomberg chat, Reuters
Eikon, internal email, or other trading-desk corpora.

**Target audience:** Legal technology researchers and practitioners applying
network-analysis methods to e-discovery workflows.

---

## Installation

```julia
using Pkg
Pkg.add("DiscoveryGraph")          # once registered in the General registry

# Resolve Python dependencies (igraph + leidenalg via Conda)
using CondaPkg
CondaPkg.resolve()
```

**The Leiden community-detection step is not optional.** Without it the pipeline
cannot partition the graph, so role identification, tier classification, and
privilege triage are all unavailable. `python-igraph` and `leidenalg` are
provisioned by CondaPkg; `CondaPkg.resolve()` must be called once after
installation (or after any update to `CondaPkg.toml`).

---

## Quick start

```julia
using DiscoveryGraph, DataFrames, Dates, SimpleWeightedGraphs

# --- Option A: Enron reference corpus (downloads from Zenodo on first call) ---
# cfg = enron_config()
# df  = enron_corpus()

# --- Option B: bring your own corpus ---
cfg = CorpusConfig(
    sender         = :sender,
    recipients_to  = :tos,
    recipients_cc  = :ccs,
    timestamp      = :date,
    subject        = :subj,
    hash           = :hash,
    lastword       = :lastword,
    corpus_start   = DateTime(2000, 1, 1),
    corpus_end     = DateTime(2002, 12, 31),
    baseline_start = DateTime(2000, 7, 1),
    baseline_end   = DateTime(2000, 9, 30),
    roles = [
        RoleConfig("counsel", InHouse,
                   [r".*@corp\.com"], String[], Set{String}()),
    ],
)

df = load_corpus(my_dataframe, cfg)   # validates schema against cfg

# Build broadcast-discounted edge table
edges = build_edges(df, cfg)

# Detect communities (requires CondaPkg Python environment)
nodes    = unique(vcat(edges.sender, edges.recipient))
node_idx = Dict(n => i for (i, n) in enumerate(nodes))
g        = build_snapshot_graph(edges, node_idx, length(nodes))
result   = leiden_communities(g, nodes)

# Identify role-bearing nodes (counsel, compliance, …)
node_reg = find_roles(DataFrame(node = nodes), cfg)

# Run the discovery session
S       = DiscoverySession(df, result, edges, cfg)
outputs = generate_outputs(S, node_reg)
```

`outputs` contains:

| Field | Contents |
|---|---|
| `outputs.tier1` | Tier 1 messages (litigation / regulatory) |
| `outputs.tier2` | Tier 2 messages (legal advice / compliance) |
| `outputs.tier3` | Tier 3 messages (transactional) |
| `outputs.tier4` | Tier 4 messages (counsel node; no keyword signal) |
| `outputs.review_queue` | Combined Tier 1–4 queue |
| `outputs.community_table` | Node community and role assignments |
| `outputs.anomaly_list` | Temporal spike detections |

Use `write_outputs(S, outputs, "export_dir")` to write Arrow files for each
tier plus a Rule 26(f)(3)(D) methodology memo to disk.

The Arrow files are the intended input to a privilege-review UI (not yet
built). The memo is attorney-ready; the review queue is not — do not
flatten it to CSV or spreadsheet. The schema (`hash`, `date`, `sender`,
`recipients`, `subject`, `tier`, `basis`, `roles_implicated`) is designed
for a record-at-a-time review interface where the attorney marks each
message privileged or not-privileged and the decision is recorded with a
timestamp.

---

## External data — Enron reference corpus

`enron_corpus()` downloads the Enron Arrow dataset from Zenodo on first call
(DOI pending package registration). Subsequent calls use the Pkg artifact cache.
No data is bundled with the package source.

---

## Privilege triage overview

The pipeline applies a two-stage (graph → semantic) triage that assigns each
message to one of five tiers:

| Tier | Label | Disposition |
|---|---|---|
| 1 | Litigation / regulatory anticipation | Immediate review |
| 2 | Regulatory / legal advice context | Secondary review |
| 3 | Transactional — privilege likely waived | Deprioritize |
| 4 | Unclassified | Human judgment required |
| 5 | No counsel involvement | Excluded from review queue |

Classification checks both the message subject and full thread text
(case-insensitive). Hotbutton keywords supplied at configuration time take
precedence over the standard keyword lists; the first matching rule assigns
the tier.

---

## Forking for other corpora

`enron_config()` returns the reference `CorpusConfig` for the Enron corpus.
To adapt the package to a new corpus, construct a `CorpusConfig` with:

- **Column mappings** — match your DataFrame's field names
- **Temporal bounds** — `corpus_start`/`corpus_end`, `baseline_start`/`baseline_end`
- **Bot patterns** — regex patterns for broadcast or system senders to exclude
- **Role definitions** — a `Vector{RoleConfig}` mapping address patterns to
  roles (`InHouse`, `Outside`, `Compliance`, etc.)

The rest of the pipeline (edge building, Leiden detection, role finding, triage)
operates on the `CorpusConfig` abstraction and requires no further changes.

---

## License

MIT — see `LICENSE`.
