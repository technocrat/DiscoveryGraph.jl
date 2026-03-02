# src/network/history.jl
using DataFrames, Dates, Statistics

function build_node_history(edges::DataFrame, cfg::CorpusConfig)::DataFrame
    rows = NamedTuple{(:node, :week_start, :message_count, :recipient_count, :entropy),
                      Tuple{String, Date, Int, Int, Float64}}[]

    start_date   = Date(cfg.corpus_start)
    end_date     = Date(cfg.corpus_end)
    start_monday = start_date - Day(dayofweek(start_date) - 1)

    week_starts = Date[]
    d = start_monday
    while d <= end_date
        push!(week_starts, d)
        d += Week(1)
    end

    all_nodes = unique(edges.sender)

    for node in all_nodes
        node_edges = filter(r -> r.sender == node, edges)
        for ws in week_starts
            we = ws + Day(6)
            week_edges = filter(r -> Date(r.date) >= ws && Date(r.date) <= we, node_edges)
            isempty(week_edges) && continue

            recipients = week_edges.recipient
            uniq_r = unique(recipients)
            mc  = nrow(week_edges)
            rc  = length(uniq_r)
            freq = [count(==(r), recipients) / mc for r in uniq_r]
            ent  = -sum(p * log(p) for p in freq if p > 0)

            push!(rows, (node=node, week_start=ws,
                         message_count=mc, recipient_count=rc, entropy=ent))
        end
    end

    DataFrame(rows)
end
