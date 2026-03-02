# src/discovery/temporal.jl
using DataFrames, Dates, Statistics

"""
    detect_anomalies(history_df::DataFrame, cfg::CorpusConfig) -> DataFrame

Detect statistically anomalous weekly message-volume spikes in a node history table.

For each node with at least 3 weeks of history, computes the mean and standard deviation
of `message_count`. Any week where the count exceeds the node mean by
`cfg.anomaly_zscore_threshold` standard deviations is flagged as a `"volume_spike"`.
Nodes with near-zero standard deviation (< 1e-9) are skipped.

# Arguments
- `history_df::DataFrame`: Weekly node history from `build_node_history`, with columns
  `:node`, `:week_start`, and `:message_count`.
- `cfg::CorpusConfig`: Configuration supplying `anomaly_zscore_threshold`.

# Returns
`DataFrame` with one row per detected anomaly and columns:
- `:node::String` — node address.
- `:week_start::Date` — Monday of the anomalous week.
- `:anomaly_type::String` — currently always `"volume_spike"`.
- `:z_score::Float64` — z-score of the anomalous week's message count (rounded to 2 decimal places).
- `:basis::String` — human-readable explanation including raw count, z-score, and node mean.

# Example
```julia
anomalies = detect_anomalies(history, cfg)
filter(r -> r.node == "alice@corp.com", anomalies)
```
"""
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
