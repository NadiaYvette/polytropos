# polytropos-aeson

High-performance `aeson` JSON serialization and deserialization codecs for [polytropos](https://github.com/NadiaYvette/polytropos) open records and variants.

## Overview

Unlike `GHC.Generics` which builds intermediate binary tree nodes (`(:*:)`, `(:+:)`) during serialization, `polytropos-aeson` unrolls the flat contiguous `SmallArray` payload directly into JSON objects and back. Open variants serialize into tagged JSON objects with $O(1)$ tag dispatch.

## Features

- **Heterogeneous Record Encoding & Decoding**: Automatic `ToJSON` and `FromJSON` instances for `Record r` via compile-time field unrolling.
- **Tagged Variant Codecs**: Fast $O(1)$ constructor dispatch encoding variants as `{"tag": "Ctor", "contents": payload}`.
- **Homogeneous Fast Path**: Specialized introspection and codec paths for homogeneous records.

## Quick Example

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}

import Data.Aeson (encode, decode)
import Polytropos
import Polytropos.Aeson ()

type Config = Record '[ "host" := String, "port" := Int ]

main :: IO ()
main = do
  let cfg = REC { host = "localhost", port = 8080 } :: Config
  print (encode cfg)
```

## License

Dual-licensed under `EUPL-1.2 OR Apache-2.0`.
