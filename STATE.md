# polytropos — State

Operational frontier. Read with `PLAN.md`; update before ending a session.

## Where we are

Phase 3 Core & Syntax and Phase 4A Optics baseline completed! Tasks `task-01` through `task-08`
have been autonomously executed, verified through deterministic gates, and merged via `yamaarashi-exec`.
All 4 packages build cleanly on GHC 9.14.1 with `-Wall -Werror` and all 54 tests pass:
- `polytropos-core` passes 32 tests (primitive SmallArray CoW updates, `setFieldsAt` batch updates,
  `MRep` transient builders, `Polytropos` consumer surface, `Record`, `Variant`).
- `polytropos-plugin-smoke` passes 10 tests with `-fplugin=Polytropos.Plugin` (`RowEq`, `RowShow`,
  `RowEqSum`, `RowShowSum`, and `GHC.Records.HasField` for native `OverloadedRecordDot`).
- `polytropos-generics-test` passes 6 tests (`Generic` datatype generics bridge over flat `Rep`,
  `geq`, `gshowsPrec`, product and sum roundtrips).
- `polytropos-optics-test` passes 6 tests (`optics-core` + `LabelOptic` `#field` lenses and variant prisms).

## What exists

- `packages/polytropos-core/src/Polytropos/Core.hs` — `Row`, `SumRow`, `Rep`,
  `RowType`, `RowFlavour`, `RowRep`, `HandlerType`, `ResultType`,
  `productRep`, `injectRep`, `fieldAt`, `setFieldAt` (primitive CoW), `setFieldsAt` (batch update),
  `MRep`, `thawRep`, `freezeRep`, `writeFieldAt`, `modifyRep` (ST transients), `setFieldSumAt`,
  `projectRep`, `matchRep`, `RowEq`, `RowShow`, `RowEqSum`, `RowShowSum`, `FieldIndex`,
  `ConstructorIndex`, `Field(..)`, `IsLabel`, `DictAny`, `noInlineUnsafeCo`
- `packages/polytropos-core/src/Polytropos.hs` — Human-facing consumer module:
  `Record`, `Variant`, `emptyRecord`, `insertField`, `injectVariant`, pattern synonyms, and re-exports
- `packages/polytropos-core/test/Main.hs` — 32 unit tests verifying representations, batch mutations,
  transients, and consumer API
- `packages/polytropos-plugin/src/Polytropos/Plugin.hs` — TcPlugin that solves:
  * `FieldIndex` and `ConstructorIndex` by literal Int/Word calculation
  * `RowEq` and `RowShow` for product rows via Core AST synthesis
  * `RowEqSum` and `RowShowSum` for sum rows via tag testing and constructor dispatch
  * `GHC.Records.HasField` for native `OverloadedRecordDot` (`r.field`)
- `packages/polytropos-plugin/tests/smoke/Main.hs` — Smoke tests exercising plugin-solved dictionary synthesis
- `packages/polytropos-generics/` — Datatype generics library unifying nominal Haskell ADTs with `polytropos`
  `Rep` with zero boxed intermediate tree representations
- `packages/polytropos-optics/` — Satellite package integrating with `optics-core` and `LabelOptic`
- `docs/NEWBIE_GUIDE.md` — quickstart and token-conservation workflow guide
- `docs/MAINTAINER_GUIDE.md` — engineering governance and zero-contamination doctrine
- `docs/notes/POLYTROPOS_DESIGN.md` — decisions D1–D10, costs, open questions
- `docs/notes/DESIGN_REVIEW_CLAUDE-OPUS-4.6.md` — architectural evaluation and ecosystem deployment assessment
- `docs/notes/PHASE2_SKETCH.md` — Phase 2 sketch (all refinements resolved)
- `docs/notes/FIELD_UPDATE_EFFICIENCY_DESIGN.md` — architectural roadmap for hardware-vectorized CoW updates
- `docs/notes/SATELLITE_INTERFACES_DESIGN.md` — architecture and package catalogue for 12 ecosystem satellites
- `docs/task_packets/` — 19 structured task packets (`task-01` through `task-19`)
- `scripts/tasks/` — deterministic test verification scripts for task packet gates (`task-01` through `task-19`)
- `bin/yamaarashi-exec` & `.agents/skills/yamaarashi/SKILL.md` — runner script and skill with SQLite ledger
- `benchmark/variants/` — four-arm compile-time harness
- `.agents/rules/` — subdivided AI coding assistant operational rules

## What is deliberately missing

- Phase 4A remaining optics satellites: `polytropos-microlens` (`task-09`) and `polytropos-lens` (`task-10`).
- Phase 4B Serialization Satellites: `polytropos-aeson` (`task-11`), `polytropos-cbor` (`task-12`), `polytropos-cassava` (`task-13`).
- Phase 4C Database Satellites: `polytropos-beam` (`task-14`), `polytropos-hasql` (`task-15`), `polytropos-rel8` (`task-16`), `polytropos-persistent` (`task-17`).
- Phase 4D Schema & Testing Satellites: `polytropos-openapi3` (`task-18`), `polytropos-quickcheck` (`task-19`).

## Next action

- Execute `task-09-satellite-microlens.yaml` via `bin/yamaarashi-exec run` to establish `polytropos-microlens`.
- Continue sequential pipeline through `task-19`.
