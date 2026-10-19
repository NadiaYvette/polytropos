# polytropos-docrecords

Self-documenting extensible records with provenance tracking and CLI synthesis for [polytropos](https://github.com/NadiaYvette/polytropos).

## Overview

`polytropos-docrecords` provides self-documenting configuration records where every field carries human-readable documentation, tri-state missing value semantics, and provenance tracking (`CLI > YAML > Default`).

Inspired by and acknowledging Yves Parès's `@docrecords@` package from the [Porcupine](https://github.com/funflow/porcupine) pipeline framework, re-architected on top of Polytropos's high-performance flat array representation (`Polytropos.Core.Rep`).

## Features

- **`DocRec`**: Extensible documented record type (`RecordF DocItem r`) backed by Polytropos's $O(1)$ flat array representation.
- **`PossiblyEmpty`**: Distinguishes unconfigured defaults from missing values.
- **`SourceTag`**: Multi-tier configuration provenance (`DefaultSource`, `YamlSource`, `CliSource`) with automatic precedence overriding.
- **`showDocumentation`**: Formats the record schema into human-readable Markdown tables.
- **`fromJSONAs`**: Decodes JSON/YAML against a default schema, updating only provided fields and marking them with `YamlSource`.
- **`parseRecFromCLI`**: Synthesizes full `optparse-applicative` command-line option parsers directly from record schemas with zero boilerplate.

## Quick Example

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}

import qualified Data.Text.IO as T
import Options.Applicative
import Polytropos
import Polytropos.DocRecord

type ServerConfig =
  '[ "host"     := String
   , "port"     := Int
   , "verbose"  := Bool
   ]

defaultConfig :: DocRec ServerConfig
defaultConfig =
  consDoc (Field @"host") (docField "127.0.0.1" "Listening IP address or hostname")
    $ consDoc (Field @"port") (docField (8080 :: Int) "TCP service port")
    $ consDoc (Field @"verbose") (docField False "Enable debug logging")
    $ emptyDocRec

main :: IO ()
main = do
  -- 1. Print formatted Markdown schema documentation:
  T.putStrLn (showDocumentation defaultConfig)

  -- 2. Inspect individual field values with standard dot notation:
  print (getDocVal defaultConfig.host)
  print (getDocVal defaultConfig.port)
```

## Attribution & Precedents

This package is inspired by Yves Parès's work on `docrecords` within the `porcupine` workflow library. While the interface is re-architected to leverage Polytropos's flat contiguous array physics and compile-time dictionary synthesis, the conceptual model of self-documenting records with provenance tracking originates from `docrecords`.

## License

Dual-licensed under `EUPL-1.2 OR Apache-2.0`.
