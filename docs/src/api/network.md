# Network Layer

The network layer builds the communication graph, detects communities, and computes node
activity history. All functions accept a `DataFrame` and `CorpusConfig`; no file paths
or global state.

## Address Parsing

```@docs
extract_addrs
```

## Bot Detection

```@docs
is_bot
identify_bots
```

## Edge Construction

```@docs
build_edges
```

## Community Detection

```@docs
build_snapshot_graph
leiden_communities
jaccard
build_kernel
match_communities
```

## Node History

```@docs
build_node_history
```
