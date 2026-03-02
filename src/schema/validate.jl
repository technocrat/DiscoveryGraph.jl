# src/schema/validate.jl
using DataFrames

function load_corpus(df::DataFrame, cfg::CorpusConfig)::DataFrame
    cfg.corpus_start < cfg.corpus_end ||
        throw(ArgumentError("corpus_start must be before corpus_end"))
    cfg.baseline_start < cfg.baseline_end ||
        throw(ArgumentError("baseline_start must be before baseline_end"))

    required = [
        cfg.sender, cfg.recipients_to, cfg.recipients_cc,
        cfg.timestamp, cfg.subject, cfg.hash, cfg.lastword,
    ]
    for col in required
        col in propertynames(df) ||
            throw(ArgumentError("Required column :$col not found in DataFrame"))
    end

    for col in [cfg.sender, cfg.hash, cfg.timestamp]
        any(ismissing, df[!, col]) &&
            throw(ArgumentError("Column :$col must not contain missing values"))
    end

    df
end
