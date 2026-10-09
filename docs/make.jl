using Documenter
using MaterialDocs
using DiscoveryGraph

makedocs(;
    sitename = "DiscoveryGraph.jl",
    authors = "Richard Careaga <public@careaga.net>",
    modules = [DiscoveryGraph],
    format = Material3(;
        theme = :ocean_depth,
        dark_mode = :toggle,
        edit_link = "master",
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://technocrat.github.io/DiscoveryGraph.jl",
    ),
    repo = Remotes.GitHub("technocrat", "DiscoveryGraph.jl"),
    pages = [
        "Home" => "index.md",
        "API Reference" => [
            "Schema" => "api/schema.md",
            "Network" => "api/network.md",
            "Discovery" => "api/discovery.md",
        ],
    ],
    checkdocs = :none,
)

deploydocs(;
    repo = "github.com/technocrat/DiscoveryGraph.jl.git",
    devbranch = "master",
)
