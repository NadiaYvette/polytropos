# polytropos-generics

Generic deriving, representation bridging, and structural traversal engine for [polytropos](https://github.com/NadiaYvette/polytropos).

## Overview

`polytropos-generics` connects GHC's native `GHC.Generics` mechanism with open rows, enabling frictionless conversion between standard nominal data types and open `Record` / `Variant` values.

## Features

- **`FromGeneric` & `ToGeneric`**: Zero-overhead translation between nominal Haskell ADTs and flat `Rep` structures.
- **Structural Row Conversions**: Cast between nominal types sharing identical field shapes without manual mapping code.
- **DerivingVia Ergonomics**: Derive typeclasses for nominal types via their structural row representation.

## Quick Example

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}

import GHC.Generics (Generic)
import Polytropos
import Polytropos.Generics

data Person = Person { name :: String, age :: Int }
  deriving (Show, Eq, Generic)

-- Convert nominal ADT to open structural record:
toRow :: Person -> Record '[ "name" := String, "age" := Int ]
toRow = fromGeneric

-- Convert open structural record back to nominal ADT:
fromRow :: Record '[ "name" := String, "age" := Int ] -> Person
fromRow = toGeneric
```

## License

Dual-licensed under `EUPL-1.2 OR Apache-2.0`.
