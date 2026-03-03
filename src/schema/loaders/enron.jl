# src/schema/loaders/enron.jl
using Dates, DataFrames

"""
    ENRON_HOTBUTTON_EXAMPLES

Illustrative case-specific escalation terms for the Enron investigation.
These are the names of trading schemes, special-purpose entities, and
accounting mechanisms that were central to the FERC and SEC investigations.

Pass any subset to `enron_config()` or `build_corpus_config()` as
`hotbutton_keywords` to promote matching messages to Tier 1 before standard
keyword classification runs.

```julia
cfg = enron_config(hotbutton_keywords = ENRON_HOTBUTTON_EXAMPLES)
```
"""
const ENRON_HOTBUTTON_EXAMPLES = [
    "raptors", "ljm", "jedi", "mark-to-market", "prepay",
    "yosemite", "braveheart", "backbone", "whitewing", "condor",
]

"""
    ENRON_TIER1_EXAMPLES

Corpus-specific Tier 1 regulatory keywords for the Enron investigation.
`ferc` (Federal Energy Regulatory Commission) and `sec` (Securities and Exchange
Commission) are the primary enforcement bodies in the Enron case and are not
part of `DEFAULT_TIER1_KEYWORDS`, which contains only matter-independent terms.

`enron_config()` includes these automatically. For other matters substitute the
relevant regulator abbreviations (e.g., `["occ", "fdic"]` for a banking matter).

```julia
cfg = enron_config()                        # includes ferc + sec automatically
cfg = build_corpus_config(...,
    tier1_keywords = vcat(DEFAULT_TIER1_KEYWORDS, ["occ", "fdic"]))
```
"""
const ENRON_TIER1_EXAMPLES = ["ferc", "sec"]

"""
    enron_config() -> CorpusConfig

Return a `CorpusConfig` pre-configured for the Enron email corpus.

The configuration encodes:
- Column name mapping for the Enron Arrow schema (`:sender`, `:tos`, `:ccs`, `:date`, `:subj`, `:hash`, `:lastword`).
- Corpus window: 1999-01-01 to 2002-12-31.
- Baseline period: Q3 2000 (2000-07-01 to 2000-09-30).
- Internal domain: `"enron.com"` (only @enron.com ↔ @enron.com edges are built).
- Bot/broadcast sender patterns and explicit bot addresses derived from the Enron corpus.
- Two role definitions:
  - `"in_house_counsel"` (`InHouse`): 21 named Enron in-house attorneys by explicit address,
    including General Counsel James Derrick and attorneys surfaced by `audit_counsel_coverage`.
  - `"outside_counsel"` (`OutsideFirm`): 13 firm domains including Vinson & Elkins, Bracewell &
    Patterson, Andrews Kurth, Sullivan & Cromwell, Weil Gotshal, Gibbs & Bruns, Jones Day, and others.

# Returns
A fully populated `CorpusConfig` ready to pass to `load_corpus`, `build_edges`, and the
rest of the DiscoveryGraph pipeline.

# Example
```julia
cfg    = enron_config()
corpus = load_corpus(raw_df, cfg)
edges  = build_edges(corpus, cfg)
```
"""
function enron_config(; hotbutton_keywords::Vector{String} = String[])::CorpusConfig
    in_house = RoleConfig(
        "in_house_counsel",
        InHouse,
        Regex[],
        String[],
        Set([
            # Original custodians (subpoenaed)
            "sara.shackleton@enron.com",
            "tana.jones@enron.com",
            "gerald.nemec@enron.com",
            "mark.haedicke@enron.com",
            "richard.sanders@enron.com",
            "christian.yoder@enron.com",
            "stinson.gibner@enron.com",
            "janette.elbertson@enron.com",
            # Additional attorneys surfaced by audit_counsel_coverage
            "james.derrick@enron.com",      # General Counsel
            "kay.mann@enron.com",
            "michelle.cash@enron.com",
            "mark.taylor@enron.com",
            "elizabeth.sager@enron.com",
            "dan.hyvl@enron.com",
            "carol.clair@enron.com",
            "travis.mccullough@enron.com",
            "alan.aronowitz@enron.com",
            "lara.leibman@enron.com",
            "stuart.zisman@enron.com",
            "jeffrey.hodge@enron.com",
            "debra.perlingiere@enron.com",
            "jordan.mintz@enron.com",
        ]),
    )

    outside_counsel = RoleConfig(
        "outside_counsel",
        OutsideFirm,
        [r".*@vinson-elkins\.com", r".*@bracepatt\.com", r".*@andrewskurth\.com"],
        [
            # Original domains
            "vinson-elkins.com", "bracepatt.com", "andrewskurth.com",
            "milbank.com", "akin-gump.com",
            # Additional firms surfaced by audit_counsel_coverage
            "sullcrom.com",          # Sullivan & Cromwell
            "weil.com",              # Weil Gotshal & Manges
            "gmssr.com",             # Gray Maynard Stierholt Rogers
            "brobeck.com",           # Brobeck Phleger & Harrison
            "kslaw.com",             # King & Spalding
            "gibbs-bruns.com",       # Gibbs & Bruns
            "troutmansanders.com",   # Troutman Sanders
            "jonesday.com",          # Jones Day
        ],
        Set{String}(),
    )

    CorpusConfig(
        sender         = :sender,
        recipients_to  = :tos,
        recipients_cc  = :ccs,
        timestamp      = :date,
        subject        = :subj,
        hash           = :hash,
        lastword       = :lastword,
        internal_domain = "enron.com",
        corpus_start   = DateTime(1999, 1,  1),
        corpus_end     = DateTime(2002, 12, 31),
        baseline_start = DateTime(2000, 7,  1),
        baseline_end   = DateTime(2000, 9,  30),
        bot_patterns   = [
            r"^mailer-daemon@", r"^postmaster@", r"^no\.address@",
            r"^noreply@", r"^no-reply@", r"^bounce", r"^arsystem@",
            r"^enron-admin@", r"^listserv@", r"@listserv\.",
            r"^enron\.announcement", r"^ect\.announcement",
            r"^general\.announcement", r"^gpg\.announcement",
            r"^the\.buzz@", r"^office\.chairman@", r"^ect\.chairman@",
            r"^enron\.chairman@", r"^team\.", r"^legal\.[0-9]",
        ],
        bot_senders    = Set([
            "arsystem@ect.enron.com", "arsystem@mailman.enron.com",
            "ect.announcement@enron.com", "ect.chairman@enron.com",
            "enron.announcement@enron.com", "general.announcement@enron.com",
            "gpg.announcement@enron.com", "gpg.center@enron.com",
            "the.buzz@enron.com", "survey.test@enron.com",
            "mailer-daemon@ect.enron.com", "postmaster@enron.com",
        ]),
        roles              = [in_house, outside_counsel],
        hotbutton_keywords = hotbutton_keywords,
        tier1_keywords     = vcat(DEFAULT_TIER1_KEYWORDS, ENRON_TIER1_EXAMPLES),
        schema_version     = "enron-v1",
    )
end

"""
    enron_corpus() -> DataFrame

Load the Enron email corpus from the package artifact store.

Downloads and caches the corpus automatically on first call via Julia's `Artifacts`
system. The artifact is hosted on Zenodo; internet access is required on first use.

# Returns
A `DataFrame` with the Enron corpus in the schema expected by `enron_config()`:
columns `:sender`, `:tos`, `:ccs`, `:date`, `:subj`, `:hash`, `:lastword`.

# Example
```julia
cfg    = enron_config()
corpus = load_corpus(enron_corpus(), cfg)
edges  = build_edges(corpus, cfg)
```
"""
function enron_corpus()::DataFrame
    artifact_dir = @artifact_str("enron_corpus")
    path = joinpath(artifact_dir, "scrub_intermediate.arrow")
    isfile(path) || error(
        "enron_corpus(): expected file not found in artifact directory: $path\n" *
        "Ensure Artifacts.toml contains valid SHA-256 and Zenodo URL " *
        "(see registration procedure in Artifacts.toml)."
    )
    return Arrow.Table(path) |> DataFrame
end
