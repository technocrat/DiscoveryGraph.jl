# src/schema/loaders/xlsx_config.jl
using XLSX, Dates

"""
    write_config_template(path::AbstractString) -> String

Write a blank DiscoveryGraph configuration workbook to `path`.

Creates an `.xlsx` file with four sheets that a paralegal or technician can
populate and return to the developer. Pass the completed file to
[`config_from_xlsx`](@ref) to produce a `CorpusConfig`.

# Sheets

| Sheet | Contents |
|-------|----------|
| `Metadata` | Internal domain, corpus/baseline date bounds, schema version |
| `InHouseAttorneys` | One in-house counsel email address per row |
| `OutsideFirmDomains` | One outside-counsel email domain per row |
| `HotbuttonKeywords` | One case-specific escalation keyword per row |

# Returns
The absolute path written (same as `path`).

# Example
```julia
write_config_template("matter_config_template.xlsx")
# Hand the file to a paralegal; receive it back completed.
cfg = config_from_xlsx("matter_config_completed.xlsx")
```
"""
function write_config_template(path::AbstractString)::String
    XLSX.openxlsx(path, mode="w") do xf
        # ── Sheet 1: Metadata ───────────────────────────────────────────────
        meta = xf[1]
        XLSX.rename!(meta, "Metadata")
        meta["A1"] = "Field"
        meta["B1"] = "Value"
        meta["C1"] = "Notes"
        rows = [
            ("internal_domain",  "",             "Email domain defining internal nodes, e.g. corp.com"),
            ("corpus_start",     "",             "Earliest corpus date, YYYY-MM-DD"),
            ("corpus_end",       "",             "Latest corpus date, YYYY-MM-DD"),
            ("baseline_start",   "",             "Community-detection baseline start, YYYY-MM-DD"),
            ("baseline_end",     "",             "Community-detection baseline end, YYYY-MM-DD"),
            ("schema_version",   "1.0",          "Identifier for this column-mapping configuration"),
        ]
        for (i, (f, v, n)) in enumerate(rows)
            meta["A$(i+1)"] = f
            meta["B$(i+1)"] = v
            meta["C$(i+1)"] = n
        end

        # ── Sheet 2: InHouseAttorneys ────────────────────────────────────────
        atty = XLSX.addsheet!(xf, "InHouseAttorneys")
        atty["A1"] = "email"
        atty["B1"] = "notes"
        atty["A2"] = "# example: jane.smith@corp.com"

        # ── Sheet 3: OutsideFirmDomains ──────────────────────────────────────
        firms = XLSX.addsheet!(xf, "OutsideFirmDomains")
        firms["A1"] = "domain"
        firms["B1"] = "notes"
        firms["A2"] = "# example: biglaw.com"

        # ── Sheet 4: HotbuttonKeywords ───────────────────────────────────────
        kws = XLSX.addsheet!(xf, "HotbuttonKeywords")
        kws["A1"] = "keyword"
        kws["B1"] = "notes"
        kws["A2"] = "# example: project-x"
    end
    abspath(path)
end

"""
    config_from_xlsx(path::AbstractString) -> CorpusConfig

Load a `CorpusConfig` from a completed DiscoveryGraph configuration workbook.

Reads the four sheets produced by [`write_config_template`](@ref) and constructs
a `CorpusConfig` via [`build_corpus_config`](@ref). Rows beginning with `#` are
treated as comments and ignored.

# Sheet requirements
- **Metadata**: `Field`/`Value` columns; all six fields must be present.
- **InHouseAttorneys**: `email` column; one address per row.
- **OutsideFirmDomains**: `domain` column; one domain per row.
- **HotbuttonKeywords**: `keyword` column; one term per row (case-insensitive matching applied at runtime).

# Returns
A fully populated `CorpusConfig`.

# Example
```julia
cfg    = config_from_xlsx("matter_config.xlsx")
corpus = load_corpus(raw_df, cfg)
```
"""
function config_from_xlsx(path::AbstractString)::CorpusConfig
    isfile(path) || error("config_from_xlsx: file not found: $path")

    xf = XLSX.readxlsx(path)

    # ── Metadata ─────────────────────────────────────────────────────────────
    meta_sheet = xf["Metadata"]
    meta = Dict{String,String}()
    for row in XLSX.eachrow(meta_sheet)
        XLSX.row_number(row) == 1 && continue   # header
        field = _cell_string(row[1])
        value = _cell_string(row[2])
        isempty(field) && continue
        meta[field] = value
    end

    required = ["internal_domain", "corpus_start", "corpus_end",
                "baseline_start", "baseline_end"]
    for f in required
        haskey(meta, f) && !isempty(meta[f]) ||
            error("config_from_xlsx: Metadata sheet missing required field '$f'")
    end

    schema_ver = get(meta, "schema_version", "1.0")

    # ── In-house attorneys ───────────────────────────────────────────────────
    attorneys = _read_single_column(xf["InHouseAttorneys"], "email")

    # ── Outside firm domains ─────────────────────────────────────────────────
    domains = _read_single_column(xf["OutsideFirmDomains"], "domain")

    # ── Hotbutton keywords ───────────────────────────────────────────────────
    keywords = _read_single_column(xf["HotbuttonKeywords"], "keyword")

    build_corpus_config(
        internal_domain      = meta["internal_domain"],
        corpus_start         = Date(meta["corpus_start"]),
        corpus_end           = Date(meta["corpus_end"]),
        baseline_start       = Date(meta["baseline_start"]),
        baseline_end         = Date(meta["baseline_end"]),
        in_house_attorneys   = attorneys,
        outside_firm_domains = domains,
        hotbutton_keywords   = keywords,
        schema_version       = schema_ver,
    )
end

# ── Internal helpers ──────────────────────────────────────────────────────────

function _cell_string(cell)::String
    cell === missing && return ""
    s = strip(string(cell))
    # XLSX sometimes returns numeric dates as floats; leave as string for caller
    s
end

# Read all non-header, non-comment, non-empty values from the first column of a sheet.
function _read_single_column(sheet, expected_header::String)::Vector{String}
    values = String[]
    for row in XLSX.eachrow(sheet)
        n = XLSX.row_number(row)
        val = _cell_string(row[1])
        if n == 1
            lowercase(val) == lowercase(expected_header) || @warn(
                "config_from_xlsx: expected column header '$(expected_header)', " *
                "found '$(val)' — proceeding anyway"
            )
            continue
        end
        isempty(val) && continue
        startswith(val, "#") && continue   # comment row
        push!(values, val)
    end
    values
end
