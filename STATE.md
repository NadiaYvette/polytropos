# polytropos — State

Operational frontier. Read with `PLAN.md`; update before ending a session.

## Where we are

Milestone 1 complete. `polytropos-core` builds on GHC 9.14.1 and its 25 tests
pass. The design note records the decisions taken and, deliberately, the ones
not taken.

## What exists

- `packages/polytropos-core/src/Polytropos/Core.hs` — `Row`, `SumRow`, `Rep`,
  `productRep`, `injectRep`, `fieldAt`, `setFieldAt`, `projectRep`, `matchRep`,
  `RowEq`, `RowShow`, `DictAny`, `noInlineUnsafeCo`
- `packages/polytropos-core/test/Main.hs` — 25 tests; the `RowEq`/`RowShow` bodies here
  are the specification of what the plugin must emit
- `docs/notes/POLYTROPOS_DESIGN.md` — decisions D1–D10, costs, open questions
- `benchmark/variants/` — the four-arm compile-time harness the design rests on
- `docs/registers/PACKAGES.md`, `docs/notes/PROVENANCE.md`, `THIRD_PARTY.md` —
  layout rules, licence obligations, attribution index

## What is deliberately missing

The TcPlugin (Milestone 3), and the rest of the elimination algebra (Milestone 2).
§4 of the design note is answered: the eliminator result type is decided (hybrid —
coproduct of per-constructor results inside a monad), the row vocabulary is decided
(Option D — concrete row flavours + `RowFlavour` class), the widening check is
decided (hybrid `SubSum` over concrete `RowType` via `RowFlavour`), and 1c is
decided (Case 3: keep erased `Rep` unchanged, add D-shaped `RowRep` wrapper).
What remains from §4 is Phase 2's sketching work: the wrapper's evidence-class
signatures, the wrapper's interaction with products, and the plugin's obligation-4
surface — before Phase 3 (the plugin) can start.

## Open questions

See design note §7. In short: 1a decided (hybrid result type + Option D
vocabulary: concrete row flavours + `RowFlavour` class); 1b decided (hybrid
`SubSum` over concrete `RowType` via `RowFlavour`); 1c decided (Case 3: erased
`Rep` + D-shaped `RowRep` wrapper). What remains from §7: Q4 (does `DictAny`
survive literal emission, or does the array make it redundant?); Q5 (how
polytropos and large-anon coexist, if at all — unresolved by design, no migration
planned). Phase 2's job is to sketch the wrapper's evidence-class signatures and
the plugin's obligation-4 surface before Phase 3.

## Where we are

Milestone 1 complete. `polytropos-core` builds on GHC 9.14.1 and its 25 tests
pass. The core module has been updated with Phase 1 decisions (Case 3 `RowRep`
wrapper, Option D `RowType` vocabulary, Sketch B evidence classes). The design
note records the decisions taken and, deliberately, the ones not taken.

## What exists

- `packages/polytropos-core/src/Polytropos/Core.hs` — `Row`, `SumRow`, `Rep`,
  `RowType`, `RowFlavour`, `RowRep`, `HandlerType`, `ResultType`,
  `productRep`, `injectRep`, `fieldAt`, `setFieldAt`, `projectRep`, `matchRep`,
  `RowEq`, `RowShow`, `RowEqSum`, `RowShowSum`, `FieldIndex`, `ConstructorIndex`,
  `DictAny`, `noInlineUnsafeCo`
- `packages/polytropos-core/test/Main.hs` — 25 tests; the `RowEq`/`RowShow` bodies here
  are the specification of what the plugin must emit
- `packages/polytropos-plugin/polytropos-plugin.cabal` — plugin package skeleton
  (empty, ready for Phase 3 implementation)
- `docs/notes/POLYTROPOS_DESIGN.md` — decisions D1–D10, costs, open questions
- `docs/notes/PHASE2_SKETCH.md` — Phase 2 sketch (all refinements resolved)
- `benchmark/variants/` — the four-arm compile-time harness the design rests on
- `docs/registers/PACKAGES.md`, `docs/notes/PROVENANCE.md`, `THIRD_PARTY.md` —
  layout rules, licence obligations, attribution index

## What is deliberately missing

The TcPlugin (Milestone 3) — the plugin source code that solves the evidence class
constraints. The plugin package skeleton exists but is empty.

## Next action

Phase 3: implement the TcPlugin in `packages/polytropos-plugin/src/Polytropos/Plugin.hs`.
The plugin must solve:
- `FieldIndex n row a` → literal slot index (obligation 1)
- `ConstructorIndex n row` → literal tag (obligation 2)
- `RowEq r row` / `RowShow r row` → literal comparison/show bodies (obligation 3)
- `RowEqSum r row` / `RowShowSum r row` → literal sum comparison/show bodies

The plugin inspects the row data (type-level list) from the constraint to emit
literal indices and bodies. All 25 core tests pass. Plugin package skeleton exists
but is empty — ready for implementation.
