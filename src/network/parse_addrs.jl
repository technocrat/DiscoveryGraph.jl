# src/network/parse_addrs.jl
function extract_addrs(s)::Vector{String}
    (ismissing(s) || isempty(s)) && return String[]
    bracketed = [m.match for m in eachmatch(r"[\w.+%-]+@[\w.-]+\.[a-z]{2,}", s)]
    isempty(bracketed) || return bracketed
    s_clean = strip(s, ['[', ']', ' '])
    parts = split(s_clean, ',')
    filter!(!isempty, String[strip(p, [' ', '\'', '"', '\n', '\r']) for p in parts])
end
