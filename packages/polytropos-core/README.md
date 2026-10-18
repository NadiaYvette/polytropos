# polytropos-core

Row-polymorphic / open algebraic data types (ADTs) and high-performance matching generics for Haskell.

`polytropos-core` collapses the four quadrants of nominal vs. structural products and sums into a single generic runtime representation (`Rep`: an unpacked tag plus a flat `SmallArray` of payload slots). Moving between nominal and structural data becomes an erased choice at the type level rather than an impedance mismatch at runtime.

## Key Features

- **Unified Flat Representation**: A single representation for records and variants (`Rep`) backed by contiguous primitive arrays.
- **$O(1)$ Field Access and Update**: Literal slot indexing without runtime inductive dictionary walks or pointer chasing.
- **Pattern Matching & Hybrid Eliminators**: Zero-overhead variant elimination (`eliminateUniform`, `eliminateUniformM`, `eliminate`, `peel`) executing through unrolled jump tables.
- **Higher-Kinded Data (HKD)**: Native support for functor-wrapped records (`RecordF f r`) and variants (`VariantF f r`).
- **Ergonomic Front Door**: Re-exports convenient record syntax, pattern synonyms, and lens-friendly helpers in `Polytropos`.

## Quick Example

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}

import Polytropos

type UserRow = '[ "id" := Int, "name" := String, "active" := Bool ]
type User = Record UserRow

-- 1. Construction without ($) grouping:
alice :: User
alice = REC { id = 42, name = "Alice", active = True }

-- 2. Direct field access via record dot syntax:
userId :: Int
userId = alice.id

-- 3. Functional record update without parentheses:
alicePromoted :: User
alicePromoted = REC_UPD alice { active = False }

-- 4. Passing record expressions without ($):
describeUser :: User -> String
describeUser u = u.name ++ " (ID: " ++ show u.id ++ ")"

summary :: String
summary = describeUser REC { id = 101, name = "Bob", active = True }
```

## Documentation & Repository

- **Main Repository**: [https://github.com/NadiaYvette/polytropos](https://github.com/NadiaYvette/polytropos)
- **Design Specification**: [POLYTROPOS_DESIGN.md](https://github.com/NadiaYvette/polytropos/blob/master/docs/notes/POLYTROPOS_DESIGN.md)
- **Tutorial**: [TUTORIAL.md](https://github.com/NadiaYvette/polytropos/blob/master/docs/TUTORIAL.md)

## License

Dual-licensed under the **European Union Public Licence v1.2** (`EUPL-1.2`) OR the **Apache License, Version 2.0** (`Apache-2.0`).
