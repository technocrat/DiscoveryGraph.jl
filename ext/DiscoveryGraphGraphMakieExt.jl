module DiscoveryGraphGraphMakieExt

using DiscoveryGraph
using GraphMakie
using NetworkLayout
using SimpleWeightedGraphs
import Graphs: degree, edges, src, dst, nv

"""
    plot_community(sub; kwargs...) -> Figure

Plot a community subgraph returned by `community_subgraphs`.

Requires `GraphMakie` and `NetworkLayout` to be loaded alongside `DiscoveryGraph`.

# Visual encoding
- **Node size** scales with degree (high-degree nodes are larger).
- **Edge width** scales with edge weight (more frequent contact = thicker edge).
- **Node labels** are truncated to the local-part of the email address (before `@`).

# Arguments
- `sub`: Named tuple with fields `graph::SimpleWeightedGraph` and
  `labels::Vector{String}`, as returned by `community_subgraphs`.
- `title`: Figure title (default: `"Community"`).
- `layout`: NetworkLayout algorithm (default: `Spring()`).
- `max_node_size`: Maximum node marker diameter in screen units (default: `35`).
- `max_edge_width`: Maximum edge line width (default: `5.0`).
- `node_color`: Node fill color or vector of colors (default: `:steelblue`).
- `edge_color`: Edge line color (default: `:gray70`).
- `label_color`: Node label text color (default: `:black`).
- `label_fontsize`: Node label font size (default: `11`).
- `figure_size`: `(width, height)` in pixels (default: `(900, 700)`).

# Example
```julia
using GLMakie, GraphMakie, NetworkLayout
subs = community_subgraphs(g, nodes, result)
fig  = plot_community(subs[Int32(3)]; title = "Community 3")
display(fig)

# Stress layout often separates dense clusters more clearly
fig2 = plot_community(subs[Int32(3)]; layout = Stress(), title = "Community 3 — Stress")
```
"""
function DiscoveryGraph.plot_community(
    sub;
    title          = "Community",
    layout         = Spring(),
    max_node_size  = 35,
    max_edge_width = 5.0,
    node_color     = :steelblue,
    edge_color     = :gray70,
    label_color    = :black,
    label_fontsize  = 11,
    figure_size    = (900, 700),
)
    g      = sub.graph
    labels = sub.labels

    # Truncate to local-part (before @) so labels fit
    short_labels = [first(split(l, "@")) for l in labels]

    # Degree-proportional node sizes (floor at 8 so isolated nodes are visible)
    degs    = Float64.(degree(g))
    max_deg = max(1.0, maximum(degs))
    node_sizes = @. max(8.0, max_node_size * degs / max_deg)

    # Weight-proportional edge widths
    edge_list = collect(edges(g))
    if isempty(edge_list)
        ew = Float64[]
    else
        ws    = [SimpleWeightedGraphs.get_weight(g, src(e), dst(e)) for e in edge_list]
        max_w = max(1.0, maximum(ws))
        ew    = @. max(0.5, max_edge_width * ws / max_w)
    end

    fig = Figure(; size = figure_size)
    ax  = Axis(fig[1, 1]; title, aspect = DataAspect())
    hidedecorations!(ax)
    hidespines!(ax)

    graphplot!(ax, g;
        layout,
        node_size        = node_sizes,
        node_color,
        edge_width       = ew,
        edge_color,
        nlabels          = short_labels,
        nlabels_textsize = label_fontsize,
        nlabels_color    = label_color,
        nlabels_align    = (:center, :bottom),
    )

    fig
end

end # module DiscoveryGraphGraphMakieExt
