module DiscoveryGraphGraphMakieExt

using DiscoveryGraph
using GraphMakie
import GraphMakie.Makie: Figure, Axis, DataAspect, hidedecorations!, hidespines!
using NetworkLayout
using SimpleWeightedGraphs
import Graphs: degree, edges, src, dst, nv

# ──────────────────────────────────────────────────────────────────────────────
# Role-color helpers
# ──────────────────────────────────────────────────────────────────────────────

"""
    counsel_roles(corpus::DataFrame;
                  sender_col   = :sender,
                  in_house_col = :in_house,
                  firm_col     = :firm) -> Dict{String,Symbol}

Build a `Dict` mapping each email address in `corpus` to one of:

- `:in_house`  — row has `in_house == true`
- `:outside`   — row has `firm == true` but `in_house == false`
- `:other`     — neither flag is set

Pass the result as `node_roles` to `plot_community` to colour nodes
blue (in-house) and red (outside counsel).

```julia
roles = counsel_roles(df)
fig   = plot_community(subs[Int32(2)]; node_roles = roles, title = "Community 2")
```
"""
function DiscoveryGraph.counsel_roles(
    corpus;
    sender_col   = :sender,
    in_house_col = :in_house,
    firm_col     = :firm,
)::Dict{String,Symbol}
    roles = Dict{String,Symbol}()
    for row in eachrow(corpus)
        addr = string(row[sender_col])
        isempty(addr) && continue
        role = if coalesce(row[in_house_col], false)
            :in_house
        elseif coalesce(row[firm_col], false)
            :outside
        else
            :other
        end
        # keep the most-specific role if the address appears more than once
        prev = get(roles, addr, :other)
        if prev === :other || (prev === :outside && role === :in_house)
            roles[addr] = role
        end
    end
    return roles
end

# ──────────────────────────────────────────────────────────────────────────────
# Plot
# ──────────────────────────────────────────────────────────────────────────────

const _DEFAULT_ROLE_COLORS = Dict{Symbol,Any}(
    :in_house => :steelblue,
    :outside  => :firebrick,
    :other    => :gray70,
)

"""
    plot_community(sub; kwargs...) -> Figure

Plot a community subgraph returned by `community_subgraphs`.

Requires `GraphMakie` and `NetworkLayout` to be loaded alongside `DiscoveryGraph`.

# Visual encoding
- **Node size** scales with degree (high-degree nodes are larger).
- **Edge width** scales with edge weight (more frequent contact = thicker edge).
- **Node labels** are truncated to the local-part of the email address (before `@`).
- **Node colour** reflects counsel role when `node_roles` is supplied.

# Arguments
- `sub`: Named tuple with fields `graph::SimpleWeightedGraph` and
  `labels::Vector{String}`, as returned by `community_subgraphs`.
- `title`: Figure title (default: `"Community"`).
- `layout`: NetworkLayout algorithm (default: `Spring()`).
- `max_node_size`: Maximum node marker diameter in screen units (default: `35`).
- `max_edge_width`: Maximum edge line width (default: `5.0`).
- `node_roles`: `Dict{String,Symbol}` mapping each node label (full email address)
  to `:in_house`, `:outside`, or `:other`. Build with `counsel_roles(corpus)`.
  When empty (default) all nodes use `node_color`.
- `role_colors`: Override colour mapping for each role symbol
  (default: `in_house => :steelblue`, `outside => :firebrick`, `other => :gray70`).
- `node_color`: Fallback colour for nodes absent from `node_roles` (default: `:gray70`).
- `edge_color`: Edge line color (default: `:gray70`).
- `label_color`: Node label text color (default: `:black`).
- `label_fontsize`: Node label font size (default: `11`).
- `figure_size`: `(width, height)` in pixels (default: `(900, 700)`).

# Example
```julia
using GLMakie, GraphMakie, NetworkLayout
subs  = community_subgraphs(g, nodes, result)
roles = counsel_roles(df)          # df = enron_corpus()

fig = plot_community(subs[Int32(3)];
        node_roles = roles,
        title      = "Community 3")
display(fig)
```
"""
function DiscoveryGraph.plot_community(
    sub;
    title          = "Community",
    layout         = Spring(),
    max_node_size  = 35,
    max_edge_width = 5.0,
    node_roles     = Dict{String,Symbol}(),
    role_colors    = _DEFAULT_ROLE_COLORS,
    node_color     = :gray70,
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

    # Per-node colours from role mapping (falls back to node_color when absent)
    if !isempty(node_roles) && !(node_roles isa AbstractDict)
        error("node_roles must be a Dict{String,Symbol} (got $(typeof(node_roles))). " *
              "Build it with: roles = counsel_roles(df)")
    end
    colors = if isempty(node_roles)
        fill(node_color, nv(g))
    else
        [get(role_colors, get(node_roles, labels[i], :other), node_color)
         for i in 1:nv(g)]
    end

    fig = Figure(; size = figure_size)
    ax  = Axis(fig[1, 1]; title, aspect = DataAspect())
    hidedecorations!(ax)
    hidespines!(ax)

    graphplot!(ax, g;
        layout,
        node_size        = node_sizes,
        node_color       = colors,
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
