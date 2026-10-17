# polytropos-beam

Beam table and database entity bindings for [polytropos](https://github.com/NadiaYvette/polytropos) open rows.

## Overview

`polytropos-beam` bridges open rows with the `beam-core` database library, allowing open records to serve as database table schemas via `PolyBeamRow`.

## Features

- **`PolyBeamRow` Schema**: Higher-kinded table schema implementing `Beamable`.
- **Zero-Copy Column Derivation**: Flattens table columns directly into `SmallArray` row representations.
- **Sub-Row Projection**: Seamlessly slice wide database tables into narrow summary records.

## License

Dual-licensed under `EUPL-1.2 OR Apache-2.0`.
