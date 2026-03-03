# Schema Layer

The schema layer defines configuration types, corpus validation, and corpus-specific
reference data. All pipeline functions accept a `CorpusConfig` that maps arbitrary
corpus column names to canonical fields.

## Types

```@docs
CounselType
RoleConfig
CorpusConfig
```

## Corpus Loading and Validation

```@docs
load_corpus
```

## Enron Reference Configuration

```@docs
enron_config
enron_corpus
ENRON_HOTBUTTON_EXAMPLES
ENRON_TIER1_EXAMPLES
```

## Generic Config Builder

```@docs
build_corpus_config
```

## XLSX Config Helper

```@docs
write_config_template
config_from_xlsx
```

## Default Keyword Lists

```@docs
DEFAULT_TIER1_KEYWORDS
DEFAULT_TIER2_KEYWORDS
DEFAULT_TIER3_KEYWORDS
```
