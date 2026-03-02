# src/network/edges.jl
using DataFrames, Dates

const _GARBAGE_PATTERNS = [
    r"^$", r"^no\.address@", r"^\.", r"^[a-z-]+ <\.", r"^credit <", r"^e-mail ",
]
const _BLEED_PATTERN = r"^\.[a-z]"
const _ROLE_PREFIX   = r"^[a-z]+ <\."

function _is_garbage(s::AbstractString, cfg::CorpusConfig)::Bool
    any(occursin(p, s) for p in _GARBAGE_PATTERNS)  && return true
    occursin(_BLEED_PATTERN, s)                      && return true
    occursin(_ROLE_PREFIX, s)                        && return true
    false
end

function _is_internal(address::AbstractString, domain::AbstractString)::Bool
    isempty(domain) && return true
    occursin(domain, address)
end

function build_edges(df::DataFrame, cfg::CorpusConfig)::DataFrame
    rows = NamedTuple{(:hash, :sender, :recipient, :date, :weight),
                      Tuple{String,String,String,DateTime,Float64}}[]

    for row in eachrow(df)
        sender = coalesce(getproperty(row, cfg.sender), "")
        isempty(sender) && continue
        is_bot(sender, cfg) && continue
        _is_garbage(sender, cfg) && continue

        tos  = extract_addrs(coalesce(getproperty(row, cfg.recipients_to), "[]"))
        ccs  = extract_addrs(coalesce(getproperty(row, cfg.recipients_cc), "[]"))
        recipients = vcat(tos, ccs)
        isempty(recipients) && continue

        n = length(recipients)
        w = cfg.broadcast_discount(n)
        h = coalesce(getproperty(row, cfg.hash), "")
        d = getproperty(row, cfg.timestamp)

        for r in recipients
            _is_garbage(r, cfg) && continue
            is_bot(r, cfg) && continue
            if !isempty(cfg.internal_domain)
                (_is_internal(sender, cfg.internal_domain) &&
                 _is_internal(r, cfg.internal_domain)) || continue
            end
            push!(rows, (hash=h, sender=sender, recipient=r, date=d, weight=w))
        end
    end

    DataFrame(rows)
end
