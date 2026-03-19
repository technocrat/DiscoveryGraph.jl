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

"""
    build_edges(df::DataFrame, cfg::CorpusConfig) -> DataFrame

Build a broadcast-discounted edge table from a corpus `DataFrame`.

For each message, the function:
1. Skips rows where the sender is empty, a bot, or a garbage address.
2. Parses To and CC recipient lists via `extract_addrs`.
3. Skips messages with no valid recipients.
4. Computes an edge weight using `cfg.broadcast_discount(n)` where `n` is the total
   recipient count (default: `1/log(n+2)`), so mass broadcasts approach zero weight
   while one-to-one messages weight ≈ 0.91.
5. Emits one row per (sender, recipient) pair, filtering out bot and garbage recipients.
6. When `cfg.internal_domain` is non-empty, restricts output to edges where both sender
   and recipient belong to that domain.

# Arguments
- `df::DataFrame`: Corpus with columns named according to `cfg`.
- `cfg::CorpusConfig`: Configuration supplying column names, domain filter, bot rules, and discount function.

# Returns
`DataFrame` with columns:
- `:md5::String` — message identifier.
- `:sender::String` — sender address.
- `:recipient::String` — recipient address.
- `:date::DateTime` — message timestamp.
- `:weight::Float64` — broadcast-discounted edge weight.

# Example
```julia
cfg   = enron_config()
edges = build_edges(corpus, cfg)
```
"""
function build_edges(df::DataFrame, cfg::CorpusConfig)::DataFrame
    rows = NamedTuple{(:md5, :sender, :recipient, :date, :weight),
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
        h = coalesce(getproperty(row, cfg.md5), "")
        d = getproperty(row, cfg.timestamp)

        for r in recipients
            _is_garbage(r, cfg) && continue
            is_bot(r, cfg) && continue
            if !isempty(cfg.internal_domain)
                (_is_internal(sender, cfg.internal_domain) &&
                 _is_internal(r, cfg.internal_domain)) || continue
            end
            push!(rows, (md5=h, sender=sender, recipient=r, date=d, weight=w))
        end
    end

    DataFrame(rows)
end
