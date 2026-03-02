# src/network/history.jl
using DataFrames, Dates, Statistics

"""
    build_node_history(edges::DataFrame, cfg::CorpusConfig) -> DataFrame

Build a weekly activity time series for every sender in the edge table.

For each sender and each calendar week (Monday-aligned) in which they sent at least one
message, the function computes:
- **message_count**: total outgoing edges (one per recipient, including duplicates).
- **recipient_count**: number of distinct recipients contacted.
- **entropy**: Shannon entropy of the recipient frequency distribution (nats), measuring
  how broadly the sender distributed messages across recipients.

Weeks beyond `cfg.corpus_end` are excluded. Returns an empty `DataFrame` with the
correct schema when `edges` is empty.

# Arguments
- `edges::DataFrame`: Edge table from `build_edges`, with columns `:sender`, `:recipient`, and `:date`.
- `cfg::CorpusConfig`: Configuration supplying `corpus_end` for the date filter.

# Returns
`DataFrame` with columns:
- `:node::String` — sender address.
- `:week_start::Date` — Monday of the calendar week.
- `:message_count::Int` — outgoing edge count for that week.
- `:recipient_count::Int` — distinct recipient count for that week.
- `:entropy::Float64` — Shannon entropy of recipient distribution (nats).

# Example
```julia
history = build_node_history(edges, cfg)
```
"""
function build_node_history(edges::DataFrame, cfg::CorpusConfig)::DataFrame
    isempty(edges) && return DataFrame(
        node=String[], week_start=Date[], message_count=Int[],
        recipient_count=Int[], entropy=Float64[])

    # Pre-compute week_start for every edge row (Monday-aligned)
    week_starts_col = map(d -> d - Day(dayofweek(d) - 1), Date.(edges.date))
    edges_w = transform(edges, :date => ByRow(d -> Date(d) - Day(dayofweek(Date(d)) - 1)) => :week_start)

    corpus_end_date = Date(cfg.corpus_end)

    rows = NamedTuple{(:node, :week_start, :message_count, :recipient_count, :entropy),
                      Tuple{String, Date, Int, Int, Float64}}[]

    for sender_group in groupby(edges_w, :sender)
        node = sender_group.sender[1]
        for week_group in groupby(sender_group, :week_start)
            ws = week_group.week_start[1]
            ws > corpus_end_date && continue

            recipients = week_group.recipient
            mc  = length(recipients)
            uniq_r = unique(recipients)
            rc  = length(uniq_r)
            freq = [count(==(r), recipients) / mc for r in uniq_r]
            ent  = -sum(p * log(p) for p in freq if p > 0)

            push!(rows, (node=node, week_start=ws,
                         message_count=mc, recipient_count=rc, entropy=ent))
        end
    end

    DataFrame(rows)
end
