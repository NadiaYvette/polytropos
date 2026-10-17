# polytropos-rel8

High-level type-safe PostgreSQL database mapping connecting [polytropos](https://github.com/NadiaYvette/polytropos) open rows to Oliver Charles' `rel8` framework.

## Overview

`polytropos-rel8` exposes `PolyRow`, a higher-kinded `Rel8able` schema representation whose columns are derived directly from the row's type-level field specification into an `HProduct` tree.

## Features

- **`PolyRow` Table Schema**: Higher-kinded record schema representation implementing `Rel8able`.
- **Zero-Tuple Mapping**: Converts directly between `rel8` columnar tables and `SmallArray` row representations without intermediate Haskell tuples.
- **Sub-Row Projection**: Slices wide SQL tables into compact view records via `projectRecord`.

## License

Dual-licensed under `EUPL-1.2 OR Apache-2.0`.
