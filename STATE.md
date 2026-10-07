# polytropos — State

Operational frontier. Read with `PLAN.md`; update before ending a session.

## Where we are

Phase 1 decisions all made. Phase 2 sketching done. Phase 3 (the plugin) in progress.
Both packages build cleanly on GHC 9.14.1 and all tests pass:
- `polytropos-core` passes all 25 tests (representation, indexing, mutation, projection, matching).
- `polytropos-plugin-smoke` passes all 3 tests with `-fplugin=Polytropos.Plugin` (no handwritten instances: `RowEq` reflexive, `RowEq` mismatch detection, and `RowShow` rendering `R2`).

## What exists

- `packages/polytropos-core/src/Polytropos/Core.hs` — `Row`, `SumRow`, `Rep`,
  `RowType`, `RowFlavour`, `RowRep`, `HandlerType`, `ResultType`,
  `productRep`, `injectRep`, `fieldAt`, `setFieldAt`, `projectRep`, `matchRep`,
  `RowEq`, `RowShow`, `RowEqSum`, `RowShowSum`, `FieldIndex`, `ConstructorIndex`,
  `DictAny`, `noInlineUnsafeCo`, with `repTag`, `repVals`, `unRowRep` top-level accessors
- `packages/polytropos-core/test/Main.hs` — 25 tests; specification of representation
  semantics and literal evidence shapes
- `packages/polytropos-plugin/polytropos-plugin.cabal` — plugin package with
  `ghc-tcplugin-api` dependency and smoke test suite
- `packages/polytropos-plugin/src/Polytropos/Plugin.hs` — TcPlugin that solves:
  * `FieldIndex` and `ConstructorIndex` by literal Int/Word index calculation
  * `RowEq` and `RowShow` on literal product rows by synthesizing Core AST method bodies
    reading payload slots from `repVals` via `indexSmallArray` and chaining equality / show calls
- `packages/polytropos-plugin/tests/smoke/Main.hs` — smoke test suite verifying
  typechecker plugin generation of `RowEq` and `RowShow` dictionaries for `R2`
- `docs/notes/POLYTROPOS_DESIGN.md` — decisions D1–D10, costs, open questions
- `docs/notes/PHASE2_SKETCH.md` — Phase 2 sketch (all refinements resolved)
- `benchmark/variants/` — the four-arm compile-time harness the design rests on
- `docs/registers/PACKAGES.md`, `docs/notes/PROVENANCE.md`, `THIRD_PARTY.md` —
  layout rules, licence obligations, attribution index

## What is deliberately missing

- `RowEqSum` / `RowShowSum` constraint solving — synthesizing sum row equality
  and show bodies matching on constructor tags and reading sum payloads.
- Arbitrary field type dictionary resolution — currently `RowEq` and `RowShow`
  resolve dictionaries for known wired-in/base types (e.g. `Int`, `Bool`, `Char`, `Double`, `Float`, `Integer`, `Word`, `String`); general arbitrary type dictionary lookup in GHC tc context can be generalized.
- Row open/extension polymorphism handling beyond literal closed lists (Option A baseline complete).

## Next action

- Implement Core AST synthesis for `RowEqSum` and `RowShowSum` to handle sum rows.
- Expand smoke tests to cover sum rows and single/empty rows.
