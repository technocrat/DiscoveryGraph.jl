# src/network/parse_addrs.jl

"""
    extract_addrs(s) -> Vector{String}

Parse a stringified email address list and return individual addresses.

Handles two common storage formats:
1. Python list literals: `"['a@corp.com', 'b@corp.com']"` — RFC-5321 regex extraction is tried first.
2. Bare comma-separated strings: `"a@corp.com, b@corp.com"` — falls back to comma splitting with quote stripping.

Returns an empty vector for `missing` or empty input.

# Arguments
- `s`: A string (or `missing`) containing one or more email addresses.

# Returns
`Vector{String}` of individual email addresses, or `String[]` if none are found.

# Example
```julia
extract_addrs("['alice@corp.com', 'bob@corp.com']")
# => ["alice@corp.com", "bob@corp.com"]

extract_addrs(missing)
# => String[]
```
"""
function extract_addrs(s)::Vector{String}
    (ismissing(s) || isempty(s)) && return String[]
    bracketed = [m.match for m in eachmatch(r"[\w.+%-]+@[\w.-]+\.[a-z]{2,}", s)]
    isempty(bracketed) || return bracketed
    s_clean = strip(s, ['[', ']', ' '])
    parts = split(s_clean, ',')
    filter!(!isempty, String[strip(p, [' ', '\'', '"', '\n', '\r']) for p in parts])
end
