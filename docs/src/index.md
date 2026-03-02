# DiscoveryGraph.jl

`DiscoveryGraph.jl` is a Julia package for communication-network analysis in legal discovery
contexts. It provides a reusable pipeline for building broadcast-discounted graphs from email
corpora, detecting communities via the Leiden algorithm, identifying counsel-role nodes by graph
position, and triaging potentially privileged messages through a configurable two-stage pipeline
(graph identification → semantic analysis).

The Enron email corpus is the reference implementation. The package is designed to be adapted for
any similarly structured corpus — particularly trading-related discovery (Bloomberg chat, Reuters
Eikon, internal email).

**Target audience:** Legal technology researchers and practitioners applying network-analysis
methods to e-discovery workflows.

## Requirements

Community detection uses Python `igraph` and `leidenalg` via
[PythonCall.jl](https://github.com/JuliaPy/PythonCall.jl) and
[CondaPkg.jl](https://github.com/JuliaPy/CondaPkg.jl). Run `CondaPkg.resolve()` once after
installation to provision the Python environment.

## Navigation

- **[Schema](api/schema.md)** — `CorpusConfig`, `RoleConfig`, `load_corpus`, `enron_config`
- **[Network](api/network.md)** — edge construction, community detection, node history
- **[Discovery](api/discovery.md)** — `DiscoverySession`, privilege triage, temporal anomalies, Rule 26(f) memo

!!! note "v0.1.0 status"
    Full API documentation is a post-registration deliverable. Docstrings are complete on all
    exported symbols; the Documenter.jl site is a v0.1.0 skeleton.
