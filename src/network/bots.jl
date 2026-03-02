# src/network/bots.jl
using DataFrames

"""
    is_bot(address::AbstractString, cfg::CorpusConfig) -> Bool

Return `true` if `address` is a broadcast sender or system account that should be
excluded from the communication network.

Matching proceeds in order:
1. Exact membership in `cfg.bot_senders`.
2. Any pattern in `cfg.bot_patterns` matches via `occursin`.

# Arguments
- `address::AbstractString`: The email address to test.
- `cfg::CorpusConfig`: Configuration carrying `bot_senders` and `bot_patterns`.

# Returns
`true` if the address matches any bot criterion, `false` otherwise.

# Example
```julia
cfg = enron_config()
is_bot("mailer-daemon@corp.com", cfg)  # => true
is_bot("alice@corp.com", cfg)          # => false
```
"""
function is_bot(address::AbstractString, cfg::CorpusConfig)::Bool
    address ∈ cfg.bot_senders && return true
    any(occursin(p, address) for p in cfg.bot_patterns)
end

"""
    identify_bots(senders::Vector{String}, cfg::CorpusConfig) -> DataFrame

Classify a vector of sender addresses as bot or non-bot and return a summary table.

For each address, records whether it matched a bot criterion and, if so, which pattern
or `"(explicit)"` for direct membership in `cfg.bot_senders`.

# Arguments
- `senders::Vector{String}`: Sender addresses to classify.
- `cfg::CorpusConfig`: Configuration carrying `bot_senders` and `bot_patterns`.

# Returns
`DataFrame` with columns:
- `:sender::String` — the address.
- `:is_bot::Bool` — `true` if the address was flagged.
- `:matched_pattern::String` — the matching pattern string, `"(explicit)"` for exact-set matches, or `""` if not flagged.

# Example
```julia
cfg    = enron_config()
senders = ["alice@corp.com", "mailer-daemon@corp.com"]
result  = identify_bots(senders, cfg)
# result.is_bot == [false, true]
```
"""
function identify_bots(senders::Vector{String}, cfg::CorpusConfig)::DataFrame
    rows = NamedTuple{(:sender, :is_bot, :matched_pattern),
                      Tuple{String,Bool,String}}[]
    for s in senders
        matched = ""
        flagged = false
        if s ∈ cfg.bot_senders
            flagged = true
            matched = "(explicit)"
        else
            for p in cfg.bot_patterns
                if occursin(p, s)
                    flagged = true
                    matched = string(p)
                    break
                end
            end
        end
        push!(rows, (sender=s, is_bot=flagged, matched_pattern=matched))
    end
    DataFrame(rows)
end
