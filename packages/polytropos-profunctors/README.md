# polytropos-profunctors

Pure profunctor optics integration for [polytropos](https://github.com/NadiaYvette/polytropos) open records and variants via `profunctors`.

## Overview

`polytropos-profunctors` provides first-class profunctor lenses and prisms (`Lens`, `Prism`, `view`, `preview`, `review`, `over`, `set`) operating directly over Polytropos's unboxed `SmallArray` memory layout.

Unlike `polytropos-optics` (which relies on `optics-core`) or `polytropos-lens` (which depends on Edward Kmett's `lens`), `polytropos-profunctors` requires only the lightweight `profunctors` package (`Data.Profunctor.Strong`, `Data.Profunctor.Choice`), making it ideal for categorical frameworks, arrow engines (such as Kernmantle), and streaming pipelines.

## Features

- **`fieldLens`**: High-level typed profunctor lens focusing on an open record field via compile-time `FieldIndex`.
- **`ctorPrism`**: High-level typed profunctor prism focusing on an open variant constructor via compile-time `ConstructorIndex`.
- **`slotLens` & `typedSlotLens`**: Low-level profunctor lenses focusing on physical array slots with dual-mode in-place updates.
- **`variantPrism` & `typedVariantPrism`**: Low-level profunctor prisms matching unboxed constructor tags in $O(1)$ time.

## Quick Example

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}

import Polytropos
import Polytropos.Profunctors

type Person = Record '["name" ':= String, "age" ':= Int]

alice :: Person
alice = REC { name = "Alice", age = 30 }

-- Read field via profunctor lens:
aliceAge :: Int
aliceAge = view (fieldLens (Field @"age")) alice  -- 30

-- Update field via profunctor lens:
olderAlice :: Person
olderAlice = over (fieldLens (Field @"age")) (+ 1) alice  -- age = 31

-- Variant constructor matching:
type Shape = Variant '["Circle" ':= '["radius" ':= Double]]

myCircle :: Shape
myCircle = VAR { Circle = REC { radius = 5.0 } }

circlePayload :: Maybe (Record '["radius" ':= Double])
circlePayload = preview (ctorPrism (Field @"Circle")) myCircle
```

## License

Dual-licensed under `EUPL-1.2 OR Apache-2.0`.
