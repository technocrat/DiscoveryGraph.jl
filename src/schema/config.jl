# src/schema/config.jl
using DataFrames, Dates

@enum CounselType NotCounsel InHouse OutsideFirm

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
