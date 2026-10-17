# polytropos-generics

Generic deriving, representation bridging, and structural traversal engine for [polytropos](https://github.com/NadiaYvette/polytropos).

## Overview

`polytropos-generics` connects GHC's native `GHC.Generics` mechanism with open rows, enabling frictionless conversion between standard nominal data types and open `Record` / `Variant` values.

## Features

- **`FromGeneric` & `ToGeneric`**: Zero-overhead translation between nominal Haskell ADTs and flat `Rep` structures.
- **Structural Row Conversions**: Cast between nominal types sharing identical field shapes without manual mapping code.
- **DerivingVia Ergonomics**: Derive typeclasses for nominal types via their structural row representation.

## License

Dual-licensed under `EUPL-1.2 OR Apache-2.0`.
