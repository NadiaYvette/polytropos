<!--
SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
-->
# THIRD-PARTY.md

Attribution index. Every package in this repository is dual-licensed under EUPL-1.2 OR Apache-2.0; this file
records what was taken from elsewhere and under what notice.

**Empty is the correct state today.** No code has been copied into this
repository. `polytropos-core` is `native`, and the benchmark harness compiles
modules written for this repository. Observation and measurement are not
derivation; see `docs/notes/PROVENANCE.md`.

## Bundled code

None.

## Design provenance

Ideas and architecture were informed by prior art. None of this carries a
licence obligation, and it is recorded here only so that a later reader can
tell influence from copying.

| Project | Licence | What was taken |
| --- | --- | --- |
| [`large-records`](https://github.com/well-typed/large-records) (Well-Typed LLP, Juspay Technologies Pvt Ltd, Monadfix OÜ) | BSD-3-Clause | The framing of the problem: GHC's handling of large nominal records and row-polymorphic access is superlinear. Also the shape of the response — an AST/TcPlugin intervention rather than a new representation layered on top. |
| [`large-anon`](https://github.com/well-typed/large-anon) (Well-Typed LLP, Juspay Technologies Pvt Ltd) | BSD-3-Clause | The `DictRowHasField`-style observation that a *row-polymorphic* accessor is what costs, not the sum. This is the load-bearing idea behind `polytropos`, and it is confirmed by arm C of the benchmark. |
| `sop-core`, `generics-sop` | BSD-3-Clause | Prior art on SOP-style row handling; surveyed, not used. |

## Sibling checkouts

`~/src/large-data` and `~/src/sarutahiko` are local co-development checkouts.
They are not dependencies, are not vendored, and nothing from them is compiled
as part of this project.

## Adding an entry

When a port lands, add a row to **Bundled code** naming the upstream project,
its copyright holders as they appear in *its* `LICENSE`, the polytropos
package, and the files touched. Then add a `Ported from:` section to that
package's `LICENSE`, and a row to `docs/registers/PACKAGES.md`.

The holder line differs per upstream package — `large-records` adds Monadfix
OÜ to the 2022 holders, the others do not. Copy it from the source, do not
reconstruct it from memory.