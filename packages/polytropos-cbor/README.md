# polytropos-cbor

Binary CBOR serialization and deserialization for [polytropos](https://github.com/NadiaYvette/polytropos) open records and variants via `cborg` / `serialise`.

## Overview

`polytropos-cbor` provides fast binary encoding and decoding for open records and variants, mapping contiguous payload slots to compact CBOR maps or arrays.

## Features

- **Heterogeneous `Serialise` Codecs**: Direct encoding of open records to CBOR byte streams.
- **Variant Serialization**: Tag-based binary framing with $O(1)$ tag decoding.
- **Compact Wire Representation**: Minimizes overhead for high-throughput distributed messaging.

## License

Dual-licensed under `EUPL-1.2 OR Apache-2.0`.
