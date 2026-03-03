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
    enron_config() -> CorpusConfig

Return a `CorpusConfig` pre-configured for the Enron email corpus.

The configuration encodes:
- Column name mapping for the Enron Arrow schema (`:sender`, `:tos`, `:ccs`, `:date`, `:subj`, `:hash`, `:lastword`).
- Corpus window: 1999-01-01 to 2002-12-31.
- Baseline period: Q3 2000 (2000-07-01 to 2000-09-30).
- Internal domain: `"enron.com"` (only @enron.com ↔ @enron.com edges are built).
- Bot/broadcast sender patterns and explicit bot addresses derived from the Enron corpus.
- Two role definitions:
  - `"in_house_counsel"` (`InHouse`): eight named Enron in-house attorneys by explicit address.
  - `"outside_counsel"` (`OutsideFirm`): Vinson & Elkins, Bracewell & Patterson, Andrews Kurth, Milbank, and Akin Gump by domain and regex.

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
            "sara.shackleton@enron.com",
            "tana.jones@enron.com",
            "gerald.nemec@enron.com",
            "mark.haedicke@enron.com",
            "richard.sanders@enron.com",
            "christian.yoder@enron.com",
            "stinson.gibner@enron.com",
            "janette.elbertson@enron.com",
        ]),
    )

    outside_counsel = RoleConfig(
        "outside_counsel",
        OutsideFirm,
        [r".*@vinson-elkins\.com", r".*@bracepatt\.com", r".*@andrewskurth\.com"],
        ["vinson-elkins.com", "bracepatt.com", "andrewskurth.com",
         "milbank.com", "akin-gump.com"],
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
    )
end

"""
    enron_corpus() -> DataFrame

Load the Enron email corpus from the package artifact store.

Downloads and caches the corpus automatically on first call via Julia's `Artifacts`
system. The artifact is hosted on Zenodo; internet access is required on first use.

!!! warning "v0.1.0 placeholder"
    `Artifacts.toml` contains placeholder SHA-256 and URL values pending the Zenodo
    deposit. This function will error until the placeholder values are replaced.
    See the registration procedure in `Artifacts.toml` for instructions.

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
