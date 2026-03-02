# src/network/bots.jl
using DataFrames

function is_bot(address::AbstractString, cfg::CorpusConfig)::Bool
    address ∈ cfg.bot_senders && return true
    any(occursin(p, address) for p in cfg.bot_patterns)
end

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
