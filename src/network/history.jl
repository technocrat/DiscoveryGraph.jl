# src/network/history.jl
using DataFrames, Dates, Statistics

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
