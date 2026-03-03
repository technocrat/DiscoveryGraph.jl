using Documenter
using DiscoveryGraph

makedocs(
    sitename = "DiscoveryGraph.jl",
    authors  = "Richard Careaga",
    modules  = [DiscoveryGraph],
    format   = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
    ),
    checkdocs = :none,   # tighten to :exports once all re-exports carry docstrings
    pages = [
        "Home" => "index.md",
        "API Reference" => [
            "Schema"    => "api/schema.md",
            "Network"   => "api/network.md",
            "Discovery" => "api/discovery.md",
        ],
    ],
)

deploydocs(
    repo      = "github.com/technocrat/DiscoveryGraph.jl.git",
    devbranch = "master",
)
