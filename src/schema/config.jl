# src/schema/config.jl
using DataFrames, Dates

"""
    CounselType

Enum classifying the type of legal counsel associated with a network node.

# Variants
- `NotCounsel`: The node is not identified as legal counsel.
- `InHouse`: The node is identified as in-house legal counsel (employee of the organization).
- `OutsideFirm`: The node is identified as outside legal counsel (external law firm).
- `RegulatoryAdvisor`: The node is a non-attorney staff member who routinely handles
  regulatory or litigation-adjacent correspondence (e.g., government affairs, compliance).
  Sets `is_counsel = true` so messages enter the review queue, but the role label
  distinguishes them from attorneys in the methodology memo and community table.
  Messages involving only `RegulatoryAdvisor` parties are not presumptively privileged —
  they require separate legal analysis to determine privilege status.
"""
@enum CounselType NotCounsel InHouse OutsideFirm RegulatoryAdvisor

"""
    ReferenceDoc

A canonical privilege example used by [`build_tfidf_model`](@ref) to construct
TF-IDF reference vectors for attorney-client (`:AC`) and work-product (`:WP`)
privilege scoring.

# Fields
- `label::Symbol`: Unique identifier (e.g. `:AC_shackleton_advice`).
- `privilege_type::Symbol`: Either `:AC` (attorney-client) or `:WP` (work product).
- `text::String`: Concatenated subject and body of the canonical message.
"""
struct ReferenceDoc
    label::Symbol
    privilege_type::Symbol
    text::String
end

"""
    RoleConfig

Configuration for identifying nodes that hold a particular legal or organizational role.

Each `RoleConfig` defines one role (e.g., "in_house_counsel") and the address-matching
rules used to assign nodes to that role during privilege triage.

# Fields
- `label::String`: Human-readable role name (e.g., `"in_house_counsel"`, `"outside_counsel"`).
- `counsel_type::CounselType`: Whether this role constitutes legal counsel (`InHouse`, `OutsideFirm`, or `NotCounsel`).
- `address_patterns::Vector{Regex}`: Regex patterns matched against node addresses. Any match assigns the role.
- `domain_list::Vector{String}`: Email domains whose addresses are assigned the role.
- `explicit_addresses::Set{String}`: Exact email addresses that are unconditionally assigned the role.

# Example
```julia
rc = RoleConfig(
    "outside_counsel",
    OutsideFirm,
    [r".*@lawfirm\\.com"],
    ["lawfirm.com"],
    Set(["partner@lawfirm.com"]),
)
```
"""
struct RoleConfig
    label::String
    counsel_type::CounselType
    address_patterns::Vector{Regex}
    domain_list::Vector{String}
    explicit_addresses::Set{String}
end

_stub_classifier(messages::DataFrame, cfg) = messages

"""
    DEFAULT_TIER1_KEYWORDS

Matter-independent Tier 1 keywords signalling litigation anticipation or active
regulatory investigation. Any subject or body match promotes a counsel-involved
message to Tier 1 (immediate human review).

These terms are deliberately generic — they apply across matter types without
modification. Corpus-specific regulatory abbreviations (e.g. `"ferc"`, `"sec"`)
should be added via `CorpusConfig(tier1_keywords = vcat(DEFAULT_TIER1_KEYWORDS, [...]))`
or the corpus-specific constant (see [`ENRON_TIER1_EXAMPLES`](@ref)).
"""
const DEFAULT_TIER1_KEYWORDS = [
    "doj", "subpoena", "investigation", "lawsuit",
    "litigation", "deposition", "enforcement", "grand jury",
]

"""
    DEFAULT_TIER2_KEYWORDS

Matter-independent Tier 2 keywords signalling regulatory compliance or direct
legal advice. Messages matching these terms (and no Tier 1 term) are placed in
the secondary review queue.
"""
const DEFAULT_TIER2_KEYWORDS = [
    "attorney", "advice", "opinion", "compliance", "privilege",
    "confidential", "attorney-client", "work product", "legal review",
]

"""
    DEFAULT_TIER3_KEYWORDS

Matter-independent Tier 3 keywords signalling transactional legal work where
privilege is likely waived in the transactional context. Deprioritised for review.
"""
const DEFAULT_TIER3_KEYWORDS = [
    "contract", "agreement", "transaction", "deal", "closing",
    "amendment", "executed", "signed",
]

const _DEFAULT_STOPWORDS = Set([
    "the","a","an","and","or","of","to","in","for","on","with",
    "is","was","are","be","been","have","has","had","will","re",
    "fw","fwd","from","this","that","it","at","by","as","we",
    "i","you","he","she","they","our","your","my","his","her",
    "not","but","if","so","do","did","no","up","out","can",
    "all","about","more","also","just","into","than","then",
    "please","hi","hello","thanks","thank","per","am","pm",
    "fyi","here","may","info","call","meeting","deal","update",
    "follow","well","plan","home","news","enron",
])

"""
    CorpusConfig(; sender, recipients_to, recipients_cc, timestamp, subject, md5, lastword,
                   corpus_start, corpus_end, baseline_start, baseline_end, roles,
                   extra_columns, internal_domain, bot_patterns, bot_domains, bot_senders,
                   broadcast_discount, kernel_threshold, kernel_jaccard_min,
                   anomaly_zscore_threshold, semantic_classifier, stopwords)

Configuration struct that fully describes a corpus and its analysis parameters. All
pipeline functions accept a `CorpusConfig` to remain corpus-agnostic.

# Required keyword arguments
- `sender::Symbol`: Column name for the message sender address.
- `recipients_to::Symbol`: Column name for the To-recipients field (stored as a stringified list).
- `recipients_cc::Symbol`: Column name for the CC-recipients field (stored as a stringified list).
- `timestamp::Symbol`: Column name for the message timestamp (`DateTime`).
- `subject::Symbol`: Column name for the subject line.
- `md5::Symbol`: Column name for the unique message identifier.
- `lastword::Symbol`: Column name for a corpus-specific auxiliary text field.
- `corpus_start::DateTime`: Earliest date of the full corpus window.
- `corpus_end::DateTime`: Latest date of the full corpus window.
- `baseline_start::DateTime`: Start of the community-detection baseline period.
- `baseline_end::DateTime`: End of the community-detection baseline period.
- `roles::Vector{RoleConfig}`: Role definitions used by `find_roles`.

# Optional keyword arguments
- `extra_columns::Vector{Symbol}`: Additional corpus columns to preserve (default: `Symbol[]`).
- `internal_domain::String`: Domain suffix used to restrict edges to internal senders/recipients. Empty string disables filtering (default: `""`).
- `bot_patterns::Vector{Regex}`: Regex patterns identifying broadcast/bot senders (default: `Regex[]`).
- `bot_domains::Vector{String}`: Domains whose senders are treated as bots (default: `String[]`).
- `bot_senders::Set{String}`: Explicit sender addresses treated as bots (default: empty set).
- `broadcast_discount::Function`: Weight function `n -> Float64` where `n` is recipient count (default: `n -> 1/log(n+2)`).
- `kernel_threshold::Float64`: Fraction of baseline weeks a node must appear in to be a kernel member (default: `2/3`).
- `kernel_jaccard_min::Float64`: Minimum Jaccard similarity to match a community across snapshots (default: `0.6`).
- `anomaly_zscore_threshold::Float64`: Z-score threshold for volume spike detection (default: `2.0`).
- `semantic_classifier::Function`: Message classifier `(df, cfg) -> df`; default is a no-op stub.
- `stopwords::Set{String}`: Words excluded from TF-IDF vocabulary (default: built-in English stopword list).
- `hotbutton_keywords::Vector{String}`: Case-specific escalation terms supplied by the user; any match assigns Tier1 before standard keyword lists are checked. Disclosed explicitly in the Rule 26(f) memo (default: `String[]`).
- `tier1_keywords::Vector{String}`: Standard litigation/regulatory keywords (default: `DEFAULT_TIER1_KEYWORDS`).
- `tier2_keywords::Vector{String}`: Standard legal-advice keywords (default: `DEFAULT_TIER2_KEYWORDS`).
- `tier3_keywords::Vector{String}`: Standard transactional keywords (default: `DEFAULT_TIER3_KEYWORDS`).
- `reference_docs::Vector{ReferenceDoc}`: Canonical privilege examples for TF-IDF scoring. Default: `ReferenceDoc[]` (no scoring).
- `similarity_threshold::Float64`: Minimum cosine similarity to a reference vector for the message to receive a privilege label. Default: `0.15`.

# Example
```julia
cfg = CorpusConfig(
    sender         = :sender,
    recipients_to  = :tos,
    recipients_cc  = :ccs,
    timestamp      = :date,
    subject        = :subj,
    md5           = :md5,
    lastword       = :lastword,
    corpus_start   = DateTime(2000, 1, 1),
    corpus_end     = DateTime(2002, 12, 31),
    baseline_start = DateTime(2000, 7, 1),
    baseline_end   = DateTime(2000, 9, 30),
    roles          = [in_house_role, outside_role],
    internal_domain = "corp.com",
)
```
"""
struct CorpusConfig
    sender::Symbol
    recipients_to::Symbol
    recipients_cc::Symbol
    timestamp::Symbol
    subject::Symbol
    md5::Symbol
    lastword::Symbol
    extra_columns::Vector{Symbol}
    internal_domain::String
    corpus_start::DateTime
    corpus_end::DateTime
    baseline_start::DateTime
    baseline_end::DateTime
    bot_patterns::Vector{Regex}
    bot_domains::Vector{String}
    bot_senders::Set{String}
    broadcast_discount::Function
    kernel_threshold::Float64
    kernel_jaccard_min::Float64
    anomaly_zscore_threshold::Float64
    roles::Vector{RoleConfig}
    semantic_classifier::Function
    stopwords::Set{String}
    hotbutton_keywords::Vector{String}
    tier1_keywords::Vector{String}
    tier2_keywords::Vector{String}
    tier3_keywords::Vector{String}
    reference_docs::Vector{ReferenceDoc}
    similarity_threshold::Float64
    schema_version::String
end

function CorpusConfig(;
    sender::Symbol,
    recipients_to::Symbol,
    recipients_cc::Symbol,
    timestamp::Symbol,
    subject::Symbol,
    md5::Symbol,
    lastword::Symbol,
    corpus_start::DateTime,
    corpus_end::DateTime,
    baseline_start::DateTime,
    baseline_end::DateTime,
    roles::Vector{RoleConfig},
    extra_columns::Vector{Symbol}       = Symbol[],
    internal_domain::String             = "",
    bot_patterns::Vector{Regex}         = Regex[],
    bot_domains::Vector{String}         = String[],
    bot_senders::Set{String}            = Set{String}(),
    broadcast_discount::Function        = n -> 1.0 / log(n + 2),
    kernel_threshold::Float64           = 2/3,
    kernel_jaccard_min::Float64         = 0.6,
    anomaly_zscore_threshold::Float64   = 2.0,
    semantic_classifier::Function       = _stub_classifier,
    stopwords::Set{String}              = _DEFAULT_STOPWORDS,
    hotbutton_keywords::Vector{String}  = String[],
    tier1_keywords::Vector{String}      = DEFAULT_TIER1_KEYWORDS,
    tier2_keywords::Vector{String}      = DEFAULT_TIER2_KEYWORDS,
    tier3_keywords::Vector{String}      = DEFAULT_TIER3_KEYWORDS,
    reference_docs::Vector{ReferenceDoc}   = ReferenceDoc[],
    similarity_threshold::Float64          = 0.15,
    schema_version::String              = "1.0",
)
    CorpusConfig(
        sender, recipients_to, recipients_cc, timestamp, subject, md5, lastword,
        extra_columns, internal_domain,
        corpus_start, corpus_end, baseline_start, baseline_end,
        bot_patterns, bot_domains, bot_senders,
        broadcast_discount, kernel_threshold, kernel_jaccard_min,
        anomaly_zscore_threshold, roles, semantic_classifier, stopwords,
        hotbutton_keywords, tier1_keywords, tier2_keywords, tier3_keywords,
        reference_docs, similarity_threshold,
        schema_version,
    )
end
