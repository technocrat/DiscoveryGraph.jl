# src/schema/config.jl
using DataFrames, Dates

"""
    CounselType

Enum classifying the type of legal counsel associated with a network node.

# Variants
- `NotCounsel`: The node is not identified as legal counsel.
- `InHouse`: The node is identified as in-house legal counsel (employee of the organization).
- `OutsideFirm`: The node is identified as outside legal counsel (external law firm).
"""
@enum CounselType NotCounsel InHouse OutsideFirm

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
    CorpusConfig(; sender, recipients_to, recipients_cc, timestamp, subject, hash, lastword,
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
- `hash::Symbol`: Column name for the unique message identifier.
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

# Example
```julia
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
    hash::Symbol
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
end

function CorpusConfig(;
    sender::Symbol,
    recipients_to::Symbol,
    recipients_cc::Symbol,
    timestamp::Symbol,
    subject::Symbol,
    hash::Symbol,
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
)
    CorpusConfig(
        sender, recipients_to, recipients_cc, timestamp, subject, hash, lastword,
        extra_columns, internal_domain,
        corpus_start, corpus_end, baseline_start, baseline_end,
        bot_patterns, bot_domains, bot_senders,
        broadcast_discount, kernel_threshold, kernel_jaccard_min,
        anomaly_zscore_threshold, roles, semantic_classifier, stopwords,
    )
end
