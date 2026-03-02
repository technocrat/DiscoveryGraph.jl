# Schema Layer

The schema layer defines configuration types and corpus validation. All pipeline functions
accept a `CorpusConfig` that maps arbitrary corpus column names to canonical fields.

## Types

```@docs
CounselType
RoleConfig
CorpusConfig
```

## Functions

```@docs
load_corpus
enron_config
enron_corpus
```
