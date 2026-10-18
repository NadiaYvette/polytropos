# polytropos-lens

Comprehensive `Control.Lens` optics integration for [polytropos](https://github.com/NadiaYvette/polytropos) open records and variants.

## Overview

`polytropos-lens` provides standard Van Laarhoven lenses for record fields and first-class prisms for variant constructors.

## Features

- **`fieldLens`**: $O(1)$ Van Laarhoven lens for accessing and updating record fields:
  ```haskell
  fieldLens @"name" :: Lens' (Record r) String
  ```
- **`ctorPrism`**: $O(1)$ constructor prism for variant injection and matching:
  ```haskell
  ctorPrism @"Success" :: Prism' (Variant s) a
  ```
- **OverloadedLabels**: Native `#fieldName` lens syntax via `LabelOptic` integration.

## Quick Example

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedLabels #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}

import Control.Lens
import Polytropos
import Polytropos.Lens

type Account = Record '[ "id" := Int, "balance" := Double ]

main :: IO ()
main = do
  let acc = REC { id = 101, balance = 500.0 }
  -- Access and update with standard lens operators:
  let acc' = acc & fieldLens @"balance" +~ 50.0
  print (acc' ^. fieldLens @"balance")
```

## License

Dual-licensed under `EUPL-1.2 OR Apache-2.0`.
