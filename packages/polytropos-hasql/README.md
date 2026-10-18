# polytropos-hasql

High-performance PostgreSQL row decoding and statement encoding integrating [polytropos](https://github.com/NadiaYvette/polytropos) open records with `hasql`.

## Overview

`polytropos-hasql` maps PostgreSQL binary query results directly into flat `SmallArray` payload slots, eliminating intermediate tuple allocations and tuple arity limits.

## Features

- **Direct Binary Decoding**: Unrolls `RowDecoder` directly into target record payload slots in wire order.
- **Statement Encoders**: Encodes heterogeneous open records into query parameters.
- **Arity Freedom**: Decodes wide database tables (e.g., >30 columns) beyond standard Haskell 62-tuple limits.

## Quick Example

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}

import qualified Hasql.Decoders as D
import Polytropos
import Polytropos.Hasql

type MetricRow = '[ "metric" := String, "value" := Double ]

-- Decode PostgreSQL columns directly into flat SmallArray slots:
metricDecoder :: D.Row (Record MetricRow)
metricDecoder = recordRow
```

## License

Dual-licensed under `EUPL-1.2 OR Apache-2.0`.
