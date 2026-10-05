# polytropos — State

Operational frontier. Read with `PLAN.md`; update before ending a session.

## Where we are

Phase 1 decisions all made. Phase 2 sketching done. Phase 3 (the plugin) started
but not complete. `polytropos-core` builds on GHC 9.14.1 and its 25 tests pass.
The plugin package compiles but does not yet solve constraints.

## What exists

- `packages/polytropos-core/src/Polytropos/Core.hs` — `Row`, `SumRow`, `Rep`,
  `RowType`, `RowFlavour`, `RowRep`, `HandlerType`, `ResultType`,
  `productRep`, `injectRep`, `fieldAt`, `setFieldAt`, `projectRep`, `matchRep`,
  `RowEq`, `RowShow`, `RowEqSum`, `RowShowSum`, `FieldIndex`, `ConstructorIndex`,
  `DictAny`, `noInlineUnsafeCo`
- `packages/polytropos-core/test/Main.hs` — 25 tests; the `RowEq`/`RowShow` bodies here
  are the specification of what the plugin must emit
- `packages/polytropos-plugin/polytropos-plugin.cabal` — plugin package with
  `ghc-tcplugin-api` dependency
- `packages/polytropos-plugin/src/Polytropos/Plugin.hs` — plugin skeleton that
  compiles and loads, traces constraints, but does not solve any
- `docs/notes/POLYTROPOS_DESIGN.md` — decisions D1–D10, costs, open questions
- `docs/notes/PHASE2_SKETCH.md` — Phase 2 sketch (all refinements resolved)
- `benchmark/variants/` — the four-arm compile-time harness the design rests on
- `docs/registers/PACKAGES.md`, `docs/notes/PROVENANCE.md`, `THIRD_PARTY.md` —
  layout rules, licence obligations, attribution index

## What is deliberately missing

The plugin's constraint-solving logic — the plugin skeleton traces constraints
but does not solve any. Full implementation requires:
- Inspecting constraints (ctPred, classifyPredType)
- Building dictionary evidence (classDataCon, mkCoreConApps, EvExpr)
- Building equality evidence (mkUnivCo, evCoercion)
- Walking type-level lists to find field/constructor indices

## Next action

Complete the plugin's constraint-solving logic. The plugin must solve:
- `FieldIndex n row a` → literal slot index (obligation 1)
- `ConstructorIndex n row` → literal tag (obligation 2)
- `RowEq r row` / `RowShow r row` → literal comparison/show bodies (obligation 3)
- `RowEqSum r row` / `RowShowSum r row` → literal sum comparison/show bodies

The plugin uses `ghc-tcplugin-api` for the GHC API. The core module changes
are complete and all 25 tests pass. The plugin package compiles but does not
yet solve constraints.
