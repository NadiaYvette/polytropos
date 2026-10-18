# polytropos-microlens

Lightweight `microlens` optics integration for [polytropos](https://github.com/NadiaYvette/polytropos) open records and variants.

## Overview

`polytropos-microlens` provides lightweight lenses and prisms for developers who prefer the minimal footprint of `microlens` over full `lens`.

## Features

- **`fieldLens`**: $O(1)$ `Lens'` targeting record fields.
- **`ctorPrism`**: $O(1)$ constructor prism for variant branches.
- **Minimal Dependencies**: Fast compilation and low dependency count.

## Quick Example

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}

import Lens.Micro ((^.), (%~), (&))
import Polytropos
import Polytropos.Microlens

type User = Record '["name" ':= String, "score" ':= Int]

user :: User
user = REC { name = "Alice", score = 95 }

-- Access a field via heterogeneous fieldLens:
userName :: String
userName = user ^. fieldLens (Field @"name")

-- Update a field with minimal dependency footprint:
user' :: User
user' = user & fieldLens (Field @"score") %~ (+ 5)
```

## License

Dual-licensed under `EUPL-1.2 OR Apache-2.0`.
