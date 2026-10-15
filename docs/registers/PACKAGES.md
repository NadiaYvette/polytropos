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
| `examples/nanopass` | `example-nanopass` | native | — | EUPL-1.2 OR Apache-2.0 | Worked Nanopass compiler tutorial executable. |
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