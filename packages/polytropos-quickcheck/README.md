# polytropos-quickcheck

Property-based testing integration connecting [polytropos](https://github.com/NadiaYvette/polytropos) open records and variants to `QuickCheck`.

## Overview

`polytropos-quickcheck` provides `Arbitrary` instances for `Record` and `Variant`, enabling automated test generation and slot-by-slot shrinking.

## Features

- **Slot-by-Slot Shrinking**: Shrinks records one field at a time without Cartesian product state space blowup.
- **Branch-Preserving Variant Shrinking**: Generates constructor variants uniformly and shrinks values strictly within the active constructor branch.
- **Heterogeneous Generation**: Derives generators across all fields using `AllFields Arbitrary r`.

## License

Dual-licensed under `EUPL-1.2 OR Apache-2.0`.
