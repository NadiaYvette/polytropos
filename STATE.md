# polytropos — State

Operational frontier. Read with `PLAN.md`; update before ending a session.

## Where we are

Phase 1 decisions all made. Phase 2 sketching done. Phase 3 (the plugin) in progress.
`polytropos-core` builds on GHC 9.14.1 and its 25 tests pass.
The plugin package now compiles and solves `FieldIndex` and `ConstructorIndex`
constraints by emitting literal slot indices and tags.

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
- `packages/polytropos-plugin/src/Polytropos/Plugin.hs` — plugin that compiles,
  loads, and solves `FieldIndex` and `ConstructorIndex` constraints by walking
  the type-level row list and emitting literal Int/Word evidence
- `docs/notes/POLYTROPOS_DESIGN.md` — decisions D1–D10, costs, open questions
- `docs/notes/PHASE2_SKETCH.md` — Phase 2 sketch (all refinements resolved)
- `benchmark/variants/` — the four-arm compile-time harness the design rests on
- `docs/registers/PACKAGES.md`, `docs/notes/PROVENANCE.md`, `THIRD_PARTY.md` —
  layout rules, licence obligations, attribution index

## What is deliberately missing

- `RowEq` / `RowShow` / `RowEqSum` / `RowShowSum` constraint solving — these
  require building function bodies at the Core AST level (lambdas, applications,
  composition chains), which needs careful handling of GHC's Core representation.
  The plugin now has the infrastructure to look up names from GHC.Classes, GHC.Show,
  GHC.Base, and Polytropos.Core at init time, and stores them in PluginState.
  The RowEq/RowShow/RowEqSum/RowShowSum solvers trace the row structure and skip
  (full Core building pending Eq dictionary resolution).
- Testing the plugin end-to-end against the core tests

## Next action

The plugin infrastructure is in place: tcPluginInit looks up all needed names
(from Polytropos.Core, GHC.Classes, GHC.Show, GHC.Base) and stores them in
PluginState. The RowEq/RowShow/RowEqSum/RowShowSum solvers now walk the row
with types (walkRowWithTypes, walkSumRowWithTypes) to extract field/constructor
names AND types. The buildRowEqBody/buildComparisonChain functions are stubs that
error with a message about pending Eq dictionary resolution.

The hard part that remains: building Core expressions that use (==) at field
types requires Eq dictionaries for those types. For simple types (Int, Bool),
the dictionaries are in GHC.Classes ($fEqInt, $fEqBool). For arbitrary types,
the plugin needs to look them up from the typechecking environment.

The plugin package compiles and solves FieldIndex/ConstructorIndex constraints.
All 25 core tests pass.
