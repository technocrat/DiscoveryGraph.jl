# src/schema/validate.jl
using DataFrames

"""
    load_corpus(df::DataFrame, cfg::CorpusConfig) -> DataFrame

Validate that a corpus `DataFrame` satisfies the requirements of `cfg` and return it unchanged.

Checks that:
- `cfg.corpus_start < cfg.corpus_end` and `cfg.baseline_start < cfg.baseline_end`.
- All required columns (sender, recipients_to, recipients_cc, timestamp, subject, md5, lastword) are present.
- The sender, md5, and timestamp columns contain no missing values.

Throws `ArgumentError` on any violation. If all checks pass, returns `df` unmodified so
the call can be composed in a pipeline.

# Arguments
- `df::DataFrame`: Raw corpus to validate.
- `cfg::CorpusConfig`: Configuration describing expected column names and date bounds.

# Returns
The input `df` unchanged if valid.

# Example
```julia
cfg = enron_config()
corpus = load_corpus(raw_df, cfg)
```
"""
function load_corpus(df::DataFrame, cfg::CorpusConfig)::DataFrame
    cfg.corpus_start < cfg.corpus_end ||
        throw(ArgumentError("corpus_start must be before corpus_end"))
    cfg.baseline_start < cfg.baseline_end ||
        throw(ArgumentError("baseline_start must be before baseline_end"))

    required = [
        cfg.sender, cfg.recipients_to, cfg.recipients_cc,
        cfg.timestamp, cfg.subject, cfg.md5, cfg.lastword,
    ]
    for col in required
        col in propertynames(df) ||
            throw(ArgumentError("Required column :$col not found in DataFrame"))
    end

    for col in [cfg.sender, cfg.md5, cfg.timestamp]
        any(ismissing, df[!, col]) &&
            throw(ArgumentError("Column :$col must not contain missing values"))
    end

    df
end
