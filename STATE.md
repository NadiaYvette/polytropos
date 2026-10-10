# polytropos — State

Operational frontier. Read with `PLAN.md`; update before ending a session.

## Where we are

Phases 3, 4A and 4B/4D foundations are in. Tasks `task-01` through `task-19` have been executed
and verified through their deterministic gates. All milestones of `plans/2026-10-09-plugin-gap-roadmap.md`
(§1.1 generic field-class dictionary supply, §1.2 HKD-aware row vocabulary, §1.3 type-level row metadata + rewriting,
§1.4 subrow/subsum projection evidence, §1.5 compile-time label hashing `KnownHash`, §1.6 source-plugin construction syntax & open declaration forms,
and §1.7 generic instance layer over rows & dynamic dictionary emission) are implemented and verified.
All packages build cleanly on GHC 9.14.1 with `-Wall -Werror`:
- `polytropos-core` passes 32 tests (primitive SmallArray CoW updates, `setFieldsAt` batch updates,
  `MRep` transient builders, `Polytropos` consumer surface, `Record`, `Variant`).
- `polytropos-plugin-smoke` passes 43 tests with `-fplugin=Polytropos.Plugin` (`RowEq`, `RowShow`,
  `RowEqSum`, `RowShowSum`, native `OverloadedRecordDot` on bare and `RecordF Maybe` records,
  `AllFields` generic dictionary supply across standard and HKD product rows, `FieldIndex`/`ConstructorIndex` on HKD rows,
  compile-time `Refl` type equality rewriting for `FieldNames`, `SimpleFieldTypes`, and `FieldTypes`,
  `SubRow`/`SubSum` projection, injection, and narrowing evidence with `projectRecord`, `widenVariant`, and `narrowVariant`,
  `KnownHash` compile-time label hashing with literal FNV-1a 64-bit `Word` dictionaries,
  and source-plugin syntactic devices: `REC`, `REC_F`, field punning, `VAR`, `VARIANT`, `REC_UPD`, `REC_UPD_F`,
  record & variant view pattern matching, and `deriving OpenRecord` / `deriving OpenVariant` declaration forms).
- `polytropos-generics-test` passes 13 tests (`Generic` and `GInstances` datatype generics bridge over flat `Rep`
  and `RowRep`, `geq`, `gcompare`, `gshowsPrec`, `gmap`, `gfoldMap` over product and sum ADTs and plugin-solved rows,
  including HKD `RecordF Maybe`).
- `polytropos-optics-test` passes 6 tests (`optics-core` + `LabelOptic` `#field` lenses and variant prisms).
- `polytropos-microlens-test` passes 5 tests (homogeneous `each` traversal, plugin-indexed `fieldLens`).
- `polytropos-lens-test` passes 14 tests (positional `_1`..`_9`, name-keyed `At`/`Ixed`, `each`,
  `fieldLens`, variant prisms).
- `polytropos-aeson-test` passes 7 tests (O(N) record/variant codecs, 20-field roundtrip,
  canonical row-order encoding, tagged variant shape).
- `polytropos-beam-test` passes 6 tests (30-column `Beamable` table: skeleton arity, lockstep
  `zipBeamFieldsM`, `allBeamValues`, row-symbol column names; compiles in a fraction of a second).
- `polytropos-openapi3-test` passes 7 tests (record object schemas with properties/required in row
  order, variant `oneOf` tagged unions, JSON roundtrip of the generated schemas).
- `polytropos-cbor-test` passes 6 tests (3- and 20-field record roundtrips, variant roundtrips,
  byte-level format assertions: length header + flat payload, tag + payload).
- `polytropos-cassava-test` passes 4 tests (heterogeneous CSV named record codecs, 12-field roundtrips).
- `polytropos-persistent-test` passes 10 tests (PersistRow marshalling, 20-field roundtrips,
  row-order serialization, PersistField bridge, and Entity wrapper).
- `polytropos-rel8-test` passes 13 tests (Rel8 `Rel8able (PolyRow r)` instance, `RowHTable` right-nested
  column tree, `namesFromLabels` symbol column synthesis, `showQuery` SELECT/VALUES projections,
  `toRecord`/`fromRecord` and `columnsToRow`/`rowToColumns` roundtrips, and columnar combinators
  `hfield`, `hfieldAt`, `htabulate`, `hmap`, `htraverse`, `hzipWith`).
- `polytropos-quickcheck-test` passes 9 tests (record and variant arbitrary generation and convergence shrinking).

## What exists

- `packages/polytropos-core/src/Polytropos/Core.hs` — `RowOf`, `Row`, `ProductRow`,
  `ProductRowHKD`, `SumRowOf`, `SumRow`, `SumRowHKD`, `SumRowF`, `Rep`,
  `RowType` (`ProductRowT`, `SumRowT`, `ProductRowHKDT`, `SumRowHKDT`), `RowFlavour`, `RowRep`,
  `HandlerType`, `ResultType`, `FieldNames`, `SimpleFieldTypes`, `FieldTypes`,
  `SubRow(..)`, `SubSum(..)`, `KnownHash(..)`, `labelHash`, `hashVal`, `fnv1a64`, `productRep`, `injectRep`, `fieldAt`, `setFieldAt` (primitive CoW),
  `setFieldsAt` (batch update), `MRep`, `thawRep`, `freezeRep`, `writeFieldAt`, `modifyRep` (ST transients),
  `setFieldSumAt`, `projectRep`, `matchRep`, `RowEq`, `RowShow`, `RowEqSum`, `RowShowSum`, `FieldIndex`,
  `ConstructorIndex`, `Field(..)`, `IsLabel`, `DictAny`, `AllFields`, `noInlineUnsafeCo`
- `packages/polytropos-core/src/Polytropos.hs` — Human-facing consumer module:
  `Record`, `RecordF`, `Variant`, `VariantF`, `emptyRecord`, `emptyRecordF`, `insertField`, `insertFieldF`,
  `injectVariant`, `injectVariantF`, `projectVariant`, `projectVariantF`, `projectRecord`, `projectRecordF`,
  `widenVariant`, `widenVariantF`, `narrowVariant`, `narrowVariantF`, pattern synonyms, and re-exports
  (`KnownHash`, `labelHash`, `hashVal`, `fnv1a64`)
- `packages/polytropos-core/test/Main.hs` — 32 unit tests verifying representations, batch mutations,
  transients, and consumer API
- `packages/polytropos-plugin/src/Polytropos/Plugin.hs` — TcPlugin that solves:
  * `FieldIndex` and `ConstructorIndex` by literal Int/Word calculation
  * `RowEq` and `RowShow` for product rows via Core AST synthesis
  * `RowEqSum` and `RowShowSum` for sum rows via tag testing and constructor dispatch
  * `GHC.Records.HasField` for native `OverloadedRecordDot` (`r.field`)
  * `AllFields` generic field-class dictionary supply (solving wanteds and packing flat `SmallArray (DictAny c)`)
  * Type-level row metadata rewriter: reduces `FieldNames`, `SimpleFieldTypes`, and `FieldTypes`
    when the product row is fully known
  * `SubRow` and `SubSum` evidence solver: emits literal projection slot indices `[Int]` for products,
    and literal injection tags `[Word]` / narrowing maps `[Maybe Word]` for sums
  * `KnownHash` compile-time label hashing: evaluates literal symbol names and synthesizes literal
    FNV-1a 64-bit `Word` dictionaries
- `packages/polytropos-plugin/tests/smoke/Main.hs` — Smoke tests exercising plugin-solved dictionary synthesis,
  `AllFields` generic dictionary supply across homogeneous and heterogeneous rows, compile-time `Refl`
  equality reduction of metadata families, `SubRow`/`SubSum` widening, narrowing, and projection,
  and `KnownHash` compile-time symbol hashing matching `fnv1a64`
- `packages/polytropos-generics/` — Datatype generics library unifying nominal Haskell ADTs with `polytropos`
  `Rep` with zero boxed intermediate tree representations
- `packages/polytropos-optics/` — Satellite package integrating with `optics-core` and `LabelOptic`
- `packages/polytropos-microlens/` — Satellite package: `microlens` `Each` for homogeneous records
  (`AllFieldsAre`-gated) and plugin-indexed `fieldLens`, zero deps beyond base/microlens/core/plugin
- `packages/polytropos-lens/` — Satellite package: positional `Field1`..`Field9`, name-keyed
  `At`/`Ixed`, `Each`, `fieldLens`, and `prismVariant` profunctor prisms over `lens`
- `packages/polytropos-aeson/` — Satellite package: linear O(N) `ToJSON`/`FromJSON` for records
  (row-order canonical objects) and variants (single-member tagged objects), no GHC.Generics tree
- `packages/polytropos-beam/` — Satellite package: erased `Beamable` instance over `BeamTable r f`
  (zero-cost newtype over `RowRep f ProductRowT r ()`), lockstep `zipBeamFieldsM` over flat arrays
- `packages/polytropos-openapi3/` — Satellite package: `ToSchema` for records (object schema,
  properties/required from row symbols) and variants (`oneOf` tagged unions), row-walked not
  Generic-derived
- `packages/polytropos-cbor/` — Satellite package: `Serialise` for records (CBOR array: length
  header + flat payload) and variants (array: constructor Word tag + payload), positional encoding
  mirroring the runtime Rep layout; scoped allow-newer for cborg/serialise's pre-9.14 base bounds
- `packages/polytropos-rel8/` — Satellite package: `Rel8able (PolyRow r)` for PostgreSQL schemas,
  mapping open product rows directly to a nested `RowHTable r` column tree (`HProduct`/`HLabel`/`HIdentity`),
  type-level label symbol synthesis via `namesFromLabels`, `litPolyRow`/`litRecord`, and columnar combinators
  (`hfield`, `hfieldAt`, `htabulate`, `hmap`, `htraverse`, `hzipWith`).
- `plans/2026-10-09-plugin-gap-roadmap.md` & `plans/2026-10-09-plugin-gap-spec.md` — Plugin gap-closing
  roadmap and specification sketches (all milestones §1.1 through §1.7 complete).
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

- None in the plugin-gap roadmap (§1.1 through §1.7 are complete). Future phases (hardware-vectorized CoW update SIMD, streaming backends).

## Next action

- All gaps from `plans/2026-10-09-plugin-gap-roadmap.md` are closed. Ready for review and subsequent roadmap planning.
