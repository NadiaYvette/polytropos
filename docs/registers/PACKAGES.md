<!--
SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
-->
# PACKAGES.md — package register

Status: LIVING DOCUMENT · v0.1 · 2026-10-05

One row per package in this repository, plus one per package we depend on.
The register exists so that the directory layout is self-describing: given a
path, you can tell what it is and where it came from without opening it.

## Discriminator

The question is **how far does this diverge from upstream**, not "did it start
as someone else's code".

| Class | Means | Lives in | In `cabal.project`? |
| --- | --- | --- | --- |
| `native` | Designed here | `packages/` | yes |
| `port` | Their code, our API; upstream merges are dead | `ports/` | yes |
| `fork` | Kept close to upstream to take their fixes | `forks/` | **no** |
| `vendored` | Unmodified dependency | — | no (version bound) |
| `benchmark` | Measurement harness, built in isolation | `benchmark/` | **no** |

Full reasoning, including why `ports/` are not git forks and why submodules are
not used: `../notes/PROVENANCE.md`.

## Packages

| Path | Package | Class | Upstream | Licence | Notes |
| --- | --- | --- | --- | --- | --- |
| `packages/polytropos-core` | `polytropos-core` | native | — | EUPL-1.2 OR Apache-2.0 | Rows, `Rep`, evidence classes. Depends on `base`, `primitive`. |
| `packages/polytropos-plugin` | `polytropos-plugin` | native | — | EUPL-1.2 OR Apache-2.0 | GHC typechecker plugin synthesizing literal dictionaries and O(1) jump tables. |
| `packages/polytropos-aeson` | `polytropos-aeson` | native | — | EUPL-1.2 OR Apache-2.0 | Fast Aeson ToJSON/FromJSON serialization and schema instances for open rows. |
| `packages/polytropos-beam` | `polytropos-beam` | native | — | EUPL-1.2 OR Apache-2.0 | Beam table and database entity bindings for open rows. |
| `packages/polytropos-cassava` | `polytropos-cassava` | native | — | EUPL-1.2 OR Apache-2.0 | High-throughput CSV serialization via Cassava over open rows. |
| `packages/polytropos-cbor` | `polytropos-cbor` | native | — | EUPL-1.2 OR Apache-2.0 | Binary CBOR encoding/decoding via Serialise for open rows. |
| `packages/polytropos-generics` | `polytropos-generics` | native | — | EUPL-1.2 OR Apache-2.0 | GHC.Generics Rep conversions between nominal types and open rows. |
| `packages/polytropos-hasql` | `polytropos-hasql` | native | — | EUPL-1.2 OR Apache-2.0 | High-performance PostgreSQL row decoding and statement encoding via Hasql. |
| `packages/polytropos-lens` | `polytropos-lens` | native | — | EUPL-1.2 OR Apache-2.0 | Control.Lens lenses, prisms, and traversals for open rows. |
| `packages/polytropos-mcp` | `polytropos-mcp` | native | — | EUPL-1.2 OR Apache-2.0 | Model Context Protocol JSON-RPC 2.0 server with OpenAPI synthesis and O(1) jump table dispatch. |
| `packages/polytropos-microlens` | `polytropos-microlens` | native | — | EUPL-1.2 OR Apache-2.0 | Lightweight MicroLens lenses and prisms for open rows. |
| `packages/polytropos-openapi3` | `polytropos-openapi3` | native | — | EUPL-1.2 OR Apache-2.0 | OpenAPI 3.0 schema generation for open records and variants. |
| `packages/polytropos-optics` | `polytropos-optics` | native | — | EUPL-1.2 OR Apache-2.0 | Optics library lenses and affine traversals for open rows. |
| `packages/polytropos-profunctors` | `polytropos-profunctors` | native | — | EUPL-1.2 OR Apache-2.0 | Pure profunctor optics (Strong lenses, Choice prisms) over flat SmallArray memory layout. |
| `packages/polytropos-persistent` | `polytropos-persistent` | native | — | EUPL-1.2 OR Apache-2.0 | Yesod Persistent PersistValue marshalling and entity schemas for open rows. |
| `packages/polytropos-quickcheck` | `polytropos-quickcheck` | native | — | EUPL-1.2 OR Apache-2.0 | Arbitrary and CoArbitrary instances for property testing open rows. |
| `packages/polytropos-docrecords` | `polytropos-docrecords` | native | Yves Parès (`docrecords` / Porcupine) | EUPL-1.2 OR Apache-2.0 | Self-documenting extensible records with provenance tracking and optparse-applicative CLI synthesis. |
| `packages/polytropos-reader-soup` | `polytropos-reader-soup` | native | Yves Parès (`reader-soup` / Porcupine) | EUPL-1.2 OR Apache-2.0 | Composable multi-context Reader monad with zero-overhead row polymorphism and ResourceT integration. |
| `packages/polytropos-rel8` | `polytropos-rel8` | native | — | EUPL-1.2 OR Apache-2.0 | Rel8 Rel8able table schemas and SQL query expressions over open rows. |
| `examples/nanopass` | `example-nanopass` | native | — | EUPL-1.2 OR Apache-2.0 | Worked Nanopass compiler tutorial executable (Addendum A). |
| `examples/resilient` | `example-resilient` | native | — | EUPL-1.2 OR Apache-2.0 | Worked Resilient Parsing and Error Tolerance tutorial executable (Addendum B). |
| `examples/database` | `example-database` | native | — | EUPL-1.2 OR Apache-2.0 | Worked Relational Database Models & Persistent Schemas tutorial executable (Addendum C). |
| `examples/effects` | `example-effects` | native | — | EUPL-1.2 OR Apache-2.0 | Worked Extensible Algebraic Effects & Higher-Kinded Ropes tutorial executable (Addendum D). |
| `examples/mcp-server` | `example-mcp-server` | native | — | EUPL-1.2 OR Apache-2.0 | Worked Federated Context & Memory MCP Server capstone executable (Addendum E). |
| `benchmark/variants` | `bench-variants` | benchmark | — | EUPL-1.2 OR Apache-2.0 | Four-arm compile-time harness. Standalone `cabal.project`, `-O0`, never built by `cabal build all`. |

## Dependencies

| Package | Version | Why |
| --- | --- | --- |
| `base` | `>= 4.19 && < 4.23` | Implicit. |
| `primitive` | `>= 0.9 && < 0.10` | `SmallArray` for the `Rep` payload. |
| `tasty`, `tasty-hunit` | test only | Test harness. |

Nothing here reaches into `large-data`, `large-records`, `large-anon` or
`large-generics`. That is a design constraint, not an accident: the engine
stands alone so that its compile-time claims can be checked against a
measurement that does not depend on the thing being replaced.

## Sibling checkouts

Not dependencies. Local co-development checkouts, referenced by path, never
built as part of this project:

| Path | Relationship |
| --- | --- |
| `~/src/large-data` | The `large-records` fork, kept for comparison and for benchmarking *against*. Its `large-records-benchmarks/variants` harness moved here to `benchmark/variants`; the original tree no longer needs to be kept in sync. |
| `~/src/sarutahiko` | Shares a documentation skeleton only. Not a naming source, not a dependency. See design note §7 Q5. |

## Conventions

- `notes/` — designs and specs; `registers/` — this file, living;
  `imports/` — verbatim third-party material; `transcripts/` — conversation
  archives.
- Genre, stage and tier are index metadata only; no filenames encode them.
- Superseded rows stay in place with successor links; there is no archive
  directory.
- A row is added when a package is added, and updated when its class changes.
  A `port` that has fully absorbed its upstream stops being a port and is
  recorded as `native` with a provenance note — the history of where it came
  from is not erased, only the obligation.