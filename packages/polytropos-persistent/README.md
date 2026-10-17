# polytropos-persistent

Yesod `persistent` relational database marshalling and entity wrappers for [polytropos](https://github.com/NadiaYvette/polytropos) open records.

## Overview

`polytropos-persistent` connects open records with the Yesod ecosystem's `persistent` library, providing fast zero-tuple marshalling to and from `[PersistValue]` rows.

## Features

- **`PersistRow`**: Fast conversion between open records and `[PersistValue]` lists (`toPersistFieldsRecord`, `fromPersistValuesRecord`).
- **`PolyRowEntity`**: Type-safe wrapper for database entities storing `Key` alongside open records.
- **Whole-Record Column Storage**: Direct `PersistField` and `PersistFieldSql` serialization for embedded records.

## License

Dual-licensed under `EUPL-1.2 OR Apache-2.0`.
