# src/discovery/outputs.jl
using Arrow, DataFrames

"""
    write_outputs(S::DiscoverySession, outputs::NamedTuple, dir::AbstractString;
                  overwrite::Bool = false) -> NamedTuple

Write per-tier DataFrames and the Rule 26(f) memo to `dir`.

Creates the directory if it does not exist. By default refuses to overwrite
existing files; set `overwrite = true` to replace them.

# Files written
| File | Contents |
|------|----------|
| `tier1.arrow` | Tier 1 review queue (litigation / regulatory) |
| `tier2.arrow` | Tier 2 review queue (legal advice / compliance) |
| `tier3.arrow` | Tier 3 review queue (transactional) |
| `tier4.arrow` | Tier 4 review queue (no keyword signal) |
| `review_queue.arrow` | Combined Tier 1–4 queue |
| `rule26f_memo.md` | Rule 26(f)(3)(D) methodology statement |

The Arrow files are the intended input to a privilege-review UI (not yet built).
They are not designed for direct attorney use; do not export to CSV or spreadsheet.
The memo is attorney-ready as written.

# Arguments
- `S::DiscoverySession`: Active session (used to generate the memo).
- `outputs::NamedTuple`: Return value of `generate_outputs(S, node_reg)`.
- `dir::AbstractString`: Destination directory path.
- `overwrite::Bool`: If `false` (default), error if any output file already exists.

# Returns
A `NamedTuple` of absolute paths for each file written.

# Example
```julia
outputs = generate_outputs(S, node_reg)
paths   = write_outputs(S, outputs, "discovery_export")
@info "Memo" path=paths.memo
```
"""
function write_outputs(
    S::DiscoverySession,
    outputs::NamedTuple,
    dir::AbstractString;
    overwrite::Bool = false,
)::NamedTuple
    mkpath(dir)

    files = (
        tier1        = joinpath(dir, "tier1.arrow"),
        tier2        = joinpath(dir, "tier2.arrow"),
        tier3        = joinpath(dir, "tier3.arrow"),
        tier4        = joinpath(dir, "tier4.arrow"),
        review_queue = joinpath(dir, "review_queue.arrow"),
        memo         = joinpath(dir, "rule26f_memo.md"),
    )

    if !overwrite
        for (_, path) in zip(keys(files), files)
            isfile(path) && error(
                "write_outputs: file already exists: $path\n" *
                "Pass overwrite=true to replace existing files."
            )
        end
    end

    # Arrow cannot serialise Vector{String} cells or TierClass enum directly;
    # coerce tier to String and roles_implicated to joined string.
    # Also coerce new semantic columns: privilege_label (Symbol→String) and
    # subcommunity_id (→Int32).
    function _arrow_safe(df::DataFrame)::DataFrame
        out = copy(df)
        if :tier ∈ propertynames(out)
            out.tier = string.(out.tier)
        end
        if :roles_implicated ∈ propertynames(out)
            out.roles_implicated = join.(out.roles_implicated, "; ")
        end
        if :privilege_label ∈ propertynames(out)
            out.privilege_label = string.(out.privilege_label)
        end
        if :subcommunity_id ∈ propertynames(out)
            out.subcommunity_id = Vector{Int32}(coalesce.(out.subcommunity_id, Int32(-1)))
        end
        out
    end

    Arrow.write(files.tier1,        _arrow_safe(outputs.tier1);        compress = :zstd)
    Arrow.write(files.tier2,        _arrow_safe(outputs.tier2);        compress = :zstd)
    Arrow.write(files.tier3,        _arrow_safe(outputs.tier3);        compress = :zstd)
    Arrow.write(files.tier4,        _arrow_safe(outputs.tier4);        compress = :zstd)
    Arrow.write(files.review_queue, _arrow_safe(outputs.review_queue); compress = :zstd)

    memo = generate_rule26f_memo(S, outputs)
    write(files.memo, memo)

    files
end
