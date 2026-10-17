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

## License

Dual-licensed under `EUPL-1.2 OR Apache-2.0`.
