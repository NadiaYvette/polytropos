# polytropos-rel8

High-level type-safe PostgreSQL database mapping connecting [polytropos](https://github.com/NadiaYvette/polytropos) open rows to Oliver Charles' `rel8` framework.

## Overview

`polytropos-rel8` exposes `PolyRow`, a higher-kinded `Rel8able` schema representation whose columns are derived directly from the row's type-level field specification into an `HProduct` tree.

## Features

- **`PolyRow` Table Schema**: Higher-kinded record schema representation implementing `Rel8able`.
- **Zero-Tuple Mapping**: Converts directly between `rel8` columnar tables and `SmallArray` row representations without intermediate Haskell tuples.
- **Sub-Row Projection**: Slices wide SQL tables into compact view records via `projectRecord`.

## Quick Example

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}

import Data.Int (Int64)
import Rel8
import Polytropos
import Polytropos.Rel8

type AccountRow = '["id" ':= Int64, "balance" ':= Double]
type AccountTable = PolyRow AccountRow

-- Lift an open record directly into a Rel8 SQL expression row:
rec :: Record AccountRow
rec = REC { id = 42 :: Int64, balance = 1000.50 :: Double }

sqlExpr :: AccountTable Expr
sqlExpr = litRecord rec
```

## License

Dual-licensed under `EUPL-1.2 OR Apache-2.0`.
