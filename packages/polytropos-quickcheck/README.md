# polytropos-quickcheck

Property-based testing integration connecting [polytropos](https://github.com/NadiaYvette/polytropos) open records and variants to `QuickCheck`.

## Overview

`polytropos-quickcheck` provides `Arbitrary` instances for `Record` and `Variant`, enabling automated test generation and slot-by-slot shrinking.

## Features

- **Slot-by-Slot Shrinking**: Shrinks records one field at a time without Cartesian product state space blowup.
- **Branch-Preserving Variant Shrinking**: Generates constructor variants uniformly and shrinks values strictly within the active constructor branch.
- **Heterogeneous Generation**: Derives generators across all fields using `AllFields Arbitrary r`.

## Quick Example

```haskell
{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}

import Test.QuickCheck
import Polytropos
import Polytropos.QuickCheck

type User = Record '["id" ':= Int, "name" ':= String, "active" ':= Bool]

-- Slot-indexed shrinking shrinks one field at a time without Cartesian explosion
prop_roundtrip :: Property
prop_roundtrip = forAll (arbitrary @User) \u ->
  u.id == u.id && not (null u.name)
```

## License

Dual-licensed under `EUPL-1.2 OR Apache-2.0`.
