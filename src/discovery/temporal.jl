# src/discovery/temporal.jl
using DataFrames, Dates, Statistics

function detect_anomalies(history_df::DataFrame, cfg::CorpusConfig)::DataFrame
    rows = NamedTuple{(:node, :week_start, :anomaly_type, :z_score, :basis),
                      Tuple{String, Date, String, Float64, String}}[]

    threshold = cfg.anomaly_zscore_threshold

    for node_group in groupby(history_df, :node)
        node = node_group.node[1]
        counts = Float64.(node_group.message_count)
        length(counts) < 3 && continue

        μ = mean(counts)
        σ = std(counts)
        σ < 1e-9 && continue

        for (i, row) in enumerate(eachrow(node_group))
            z = (counts[i] - μ) / σ
            z >= threshold || continue
            push!(rows, (
                node         = node,
                week_start   = row.week_start,
                anomaly_type = "volume_spike",
                z_score      = round(z, digits=2),
                basis        = "message_count $(row.message_count) is $(round(z, digits=1))σ above node mean $(round(μ, digits=1))",
            ))
        end
    end

    DataFrame(rows)
end
