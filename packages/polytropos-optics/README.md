# polytropos-optics

Profunctor optics integration for [polytropos](https://github.com/NadiaYvette/polytropos) open records and variants via `optics-core`.

## Overview

`polytropos-optics` provides profunctor-based optics compatible with the `optics` ecosystem, offering improved type error messages and faster compile times compared to traditional Van Laarhoven lenses.

## Features

- **`fieldLens`**: `Lens'` for record fields with clean optics composition (`%~`, `.~`, `^.`).
- **`ctorOptic`**: `Prism'` for variant constructors.
- **`LabelOptic`**: Enables `#fieldName` syntax with `OverloadedLabels`.

## Quick Example

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}

import Optics.Core
import Polytropos
import Polytropos.Optics

type Person = Record '["name" ':= String, "age" ':= Int]

alice :: Person
alice = REC { name = "Alice", age = 30 }

-- Read via overloaded label:
aliceAge :: Int
aliceAge = alice ^. #age

-- Update via overloaded label:
olderAlice :: Person
olderAlice = alice & #age %~ (+ 1)

-- Variant prism traversal:
type Shape = Variant '["Circle" ':= '["radius" ':= Double]]

myCircle :: Shape
myCircle = VAR { Circle = REC { radius = 5.0 } }

circleRadius :: Maybe Double
circleRadius = preview (ctorOptic (Field @"Circle") % #radius) myCircle
```

## License

Dual-licensed under `EUPL-1.2 OR Apache-2.0`.
