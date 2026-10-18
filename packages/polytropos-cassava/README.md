# polytropos-cassava

High-throughput CSV tabular encoding and decoding for [polytropos](https://github.com/NadiaYvette/polytropos) open records via `cassava`.

## Overview

`polytropos-cassava` provides `ToNamedRecord` and `FromNamedRecord` instances for open records, unrolling row fields directly into CSV header maps and byte vectors.

## Features

- **Header Derivation**: Automatically maps type-level field names (`Symbol`) to CSV headers.
- **Heterogeneous Decoding**: Converts CSV row maps into flat `Record r` instances.
- **Zero Intermediates**: Avoids intermediate tuples or algebraic data types.

## Quick Example

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}

import Data.Csv (encodeByName, header)
import Polytropos
import Polytropos.Cassava ()

type Employee = Record '[ "name" := String, "salary" := Int ]

main :: IO ()
main = do
  let emps =
        [ REC { name = "Alice", salary = 95000 }
        , REC { name = "Bob", salary = 85000 }
        ]
  print (encodeByName (header ["name", "salary"]) emps)
```

## License

Dual-licensed under `EUPL-1.2 OR Apache-2.0`.
