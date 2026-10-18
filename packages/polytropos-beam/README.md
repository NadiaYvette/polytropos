# polytropos-beam

Beam table and database entity bindings for [polytropos](https://github.com/NadiaYvette/polytropos) open rows.

## Overview

`polytropos-beam` bridges open rows with the `beam-core` database library, allowing open records to serve as database table schemas via `PolyBeamRow`.

## Features

- **`PolyBeamRow` Schema**: Higher-kinded table schema implementing `Beamable`.
- **Zero-Copy Column Derivation**: Flattens table columns directly into `SmallArray` row representations.
- **Sub-Row Projection**: Seamlessly slice wide database tables into narrow summary records.

## Quick Example

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}

import Database.Beam
import Polytropos
import Polytropos.Beam

type UserRow = '[ "id" := Int, "username" := String ]

-- 1. Construct Beam table directly from open record:
userRec :: Record UserRow
userRec = REC { id = 1, username = "Alice" }

userTable :: PolyBeamRow UserRow (TableField UserTable)
userTable = toBeamTable userRec

-- 2. Functional updates with unparenthesized REC_UPD:
updatedUser :: Record UserRow
updatedUser = REC_UPD userRec { username = "Bob" }
```

## License

Dual-licensed under `EUPL-1.2 OR Apache-2.0`.
