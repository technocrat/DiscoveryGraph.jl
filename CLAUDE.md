# CLAUDE.md — DiscoveryGraph.jl

Guidance for Claude Code when working in this repository.

## Project overview

Julia package for communication-network analysis in legal discovery contexts. Builds broadcast-discounted graphs from email corpora, detects communities via the Leiden algorithm (Python `igraph`/`leidenalg` via PythonCall), identifies counsel-role nodes, and triages potentially privileged messages through a configurable keyword + graph pipeline.

- **Version:** 0.2.0
- **GitHub:** https://github.com/technocrat/DiscoveryGraph.jl
- **Docs:** https://technocrat.github.io/DiscoveryGraph.jl/dev/
- **Tests:** 226/226 green
- **Registry:** JuliaRegistrator PR in flight against General registry

The Enron email corpus (248k messages) is the reference implementation. The package is corpus-agnostic via `CorpusConfig`.

## Development commands

```bash
# Run tests
julia --project=. -e 'using Pkg; Pkg.test()'

# Build docs locally
julia --project=docs/ -e 'using Pkg; Pkg.develop(PackageSpec(path=pwd())); Pkg.instantiate()'
julia --project=docs/ docs/make.jl

# Format (no formatter configured — follow existing style)
```

## Repository layout

```
src/
├── DiscoveryGraph.jl           # Main module; all exports live here
├── schema/
│   ├── config.jl               # CounselType enum, RoleConfig, CorpusConfig
│   ├── validate.jl             # load_corpus, corpus validation
│   └── loaders/
│       ├── enron.jl            # enron_config(), enron_corpus(), Enron constants
│       ├── builder.jl          # build_corpus_config() generic helper
│       └── xlsx_config.jl      # write_config_template(), config_from_xlsx()
├── network/
│   ├── parse_addrs.jl          # extract_addrs()
│   ├── bots.jl                 # is_bot(), identify_bots()
│   ├── edges.jl                # build_edges()
│   ├── community.jl            # build_snapshot_graph(), leiden_communities(),
│   │                           #   jaccard(), build_kernel(), match_communities()
│   └── history.jl              # build_node_history()
└── discovery/
    ├── roles.jl                # find_roles(), identify_counsel_communities(),
    │                           #   audit_counsel_coverage(), ATTORNEY_KEYWORDS
    ├── privilege_log.jl        # generate_outputs(), _addr_counsel_roles()
    ├── outputs.jl              # DiscoverySession, write_outputs(), TierClass
    ├── temporal.jl             # detect_anomalies()
    ├── tfidf.jl                # build_community_vocabulary() (stub)
    ├── clusters.jl             # cluster helpers
    └── rule26f.jl              # generate_rule26f_memo()
test/
├── runtests.jl                 # 226 tests across ~15 testsets
└── fixtures.jl                 # shared test data
docs/
├── Project.toml                # Documenter + DiscoveryGraph deps
├── make.jl                     # makedocs + deploydocs
└── src/
    ├── index.md
    └── api/
        ├── schema.md
        ├── network.md
        └── discovery.md
.github/workflows/Documenter.yml   # CI: build + deploy to gh-pages on push to master
Artifacts.toml                     # enron_corpus artifact (lazy = true — required)
```

## Architecture

### CounselType enum

```julia
@enum CounselType NotCounsel InHouse OutsideFirm RegulatoryAdvisor
```

`RegulatoryAdvisor` sets `is_counsel=true` (enters review queue) but is semantically distinct from legal counsel. The Rule 26(f) memo discloses that `RegulatoryAdvisor` messages are not presumptively privileged.

### Privilege triage tiers

| Tier | Signal | Disposition |
|------|--------|-------------|
| 1 | Hotbutton or Tier1 keyword in subject/body | Immediate review |
| 2 | Tier2 keyword | Secondary review |
| 3 | Tier3 keyword | Deprioritize |
| 4 | Counsel involved; no keyword signal | Human judgment |
| 5 | No counsel involvement | Excluded from review queue |

Keyword precedence: hotbutton → tier1 → tier2 → tier3. First match wins.

### Counsel detection (two paths)

1. **Graph-node path** — parties present in `node_reg` with `is_counsel=true` (built by `find_roles`)
2. **Pattern-match path** — non-graph-node parties matched at runtime by `_addr_counsel_roles(addr, cfg)` using the same three-rule logic: explicit_addresses → address_patterns → domain_list

Outside counsel at firm domains never appear in the internal graph, so path 2 is essential for outside-counsel privilege detection.

### Broadcast discounting

Edge weights: `1/log(n+2)` where `n` = recipient count. One-to-one ≈ 0.91; mass broadcasts → 0.

### Community detection

Leiden algorithm via Python `igraph`/`leidenalg`. Community IDs are non-deterministic — they change on every run. The `seed` and `resolution` parameters are stored on `DiscoverySession` and reported in the Rule 26(f) memo for reproducibility documentation.

## Key design decisions / pitfalls

### Artifacts.toml MUST have `lazy = true`

```toml
[enron_corpus]
lazy = true
git-tree-sha1 = "..."
```

Without `lazy = true`, `Pkg.instantiate` in CI tries to download the Zenodo artifact. Zenodo serves a raw `.arrow` file, not a TAR archive, and Julia's artifact system fails with a checksum/TAR error. The artifact is only needed when `enron_corpus()` is explicitly called.

### Arrow column mutability

Arrow columns are read-only after loading. Any `setindex!` (including `.=`) will error. Convert first:

```julia
df.col = Vector{String}(df.col)
df.col = Vector{Bool}(df.col)
```

### CondaPkg / PythonCall restart requirement

After `CondaPkg.resolve()`, Julia **must be restarted** before `leiden_communities` (or any `PythonCall` import) works. This is a PythonCall limitation, not a bug.

### Pkg cache (manual testing)

`Pkg.add(url=...)` caches the clone in `~/.julia/clones/` and never auto-updates. After pushing, clear all three caches before re-testing:

```bash
rm -rf ~/.julia/packages/DiscoveryGraph/
rm -rf ~/.julia/compiled/*/DiscoveryGraph/
rm -rf ~/.julia/clones/<most-recent-by-mtime>
```

### GitHub Pages / gh-pages ordering

The GitHub Pages API requires the `gh-pages` branch to exist before it can be enabled. The branch is created by the first successful Documenter workflow run. Enable Pages only after that run succeeds.

### Community IDs are run-specific

Leiden IDs differ on every run. The `community_registry` in the Enron reference implementation reflects one specific run. If Leiden is re-run, community IDs must be remapped manually.

## Testing

Tests use only in-memory fixtures (no disk I/O, no network, no Python). `test/fixtures.jl` defines shared `DataFrame` helpers.

Key testsets in `runtests.jl`:
- `extract_addrs` — address parsing edge cases
- `is_bot / identify_bots` — bot detection
- `build_edges` — broadcast discounting, weight correctness
- `find_roles` — all three matching rules, counsel flags, RegulatoryAdvisor
- `audit_counsel_coverage` — keyword matching, broadcast fraction
- `generate_outputs` — tier assignment, hotbutton precedence, RegulatoryAdvisor
- `outside counsel privilege gap fix` — `_addr_counsel_roles` path for non-graph-node parties
- `hotbutton keyword coverage` — all 10 ENRON_HOTBUTTON_EXAMPLES, subject + body, precedence
- `RegulatoryAdvisor` — five tests covering enum, is_counsel flag, memo split
- `config_from_xlsx` / `write_config_template` — XLSX round-trip

Run with:
```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

## Docs CI

`.github/workflows/Documenter.yml` triggers on every push to `master`. It:
1. Installs Julia + dependencies (no artifact download thanks to `lazy = true`)
2. Runs `docs/make.jl` → `makedocs` + `deploydocs`
3. Pushes built HTML to the `gh-pages` branch

All exported symbols must have docstrings — `@docs` blocks in `docs/src/api/*.md` will fail the build otherwise. `checkdocs = :none` is set so undocumented non-exported symbols don't block the build.

## Enron reference configuration

`enron_config()` in `src/schema/loaders/enron.jl` is the canonical example of a complete `CorpusConfig`. It defines:
- Three `RoleConfig` entries: `in_house` (InHouse), `outside_counsel` (OutsideFirm), `regulatory_affairs` (RegulatoryAdvisor)
- `internal_domain = "enron.com"`
- Enron-specific bot patterns and domains
- `tier1_keywords = vcat(DEFAULT_TIER1_KEYWORDS, ENRON_TIER1_EXAMPLES)` (adds ferc, sec, etc.)
- `hotbutton_keywords = []` by default; pass `ENRON_HOTBUTTON_EXAMPLES` to activate

For a new corpus, use `build_corpus_config()` or `config_from_xlsx()`.
