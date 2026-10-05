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

## Next action

Phase 1 decisions all made. Phase 2 sketching done (`docs/notes/PHASE2_SKETCH.md`):
the `RowRep` wrapper + `RowFlavour` class + evidence-class signatures, products-as-
one-constructor-sums (`SumRowT` flavour), handler-type and result-type encodings
(sketched), and the plugin obligation-4 surface (`RowRep f r a` as the type the
plugin solves from, `RowFlavour r` giving the entry kind). Refinement #1 decided:
Sketch B (keep `RowEq`/`RowShow` for product rows as `RowEq (r :: ProductRowT)`,
add separate classes for sum/handler/result rows). Refinement #2 decided: explicit `HandlerType` encoding (`HandlerType n fs res m`).
Handler rows are self-contained, first-class, portable — each entry carries its
constructor name, field types, result type, and monad. Field-type duplication is a
feature (handler rows stand alone). `SubSum` is on handler rows. Eliminator needs
only the handler row (sum row known from value's type). Closed.

Refinement #3 decided: GADT for `Results`/`SumOf` (1a hybrid's result coproduct).
`Results r` is a GADT indexed by the handler row `r :: HandlerRowT`, one constructor
per handlerrow entry, constructors named after the handler's constructor names (e.g.
`"neg"` → `NegResult`), each carrying the result type for that handler. Result is
`m (Results handlerrow)`, specialises to `m a` via flatten map when all result types
are `a`. GADT's readability wins over type-family (nested `Either`). Closed.

Refinement #4 (§7 Q4, DictAny survival) decided with nuance: `f Any` in `Rep` stays
(the array's erased element type, separate concern from `DictAny`). `DictAny` (type-
erased dictionary pack) survives as a forward-looking mechanism for packing field-
class dictionaries (e.g. `Eq x` into one dictionary), needed because the plugin emits
literal comparison structures but the field-class dictionaries are still required.
Not used by current `RowEq`/`RowShow` (which have `undefined` defaults) — forward-
looking, may not be needed immediately. Closed with nuance.

Refinement #5 (role of `a` in `RowRep`) decided: `a` is the value type, independent
of the row `r`. Case 3: `Rep f a` stays erased (doesn't know `r`), `RowRep f r a`
links `a` to `r`. Alternative (Case 1) would make `a` depend on `r` (row-indexed
`Rep`), rejected. Relationship between `a` and `r` enforced by wrapper's type, not
by `Rep`. Closed. What remains: the exact `Results`/`SumOf` shape, whether `DictAny`
survives (§7 Q4), and the exact role of `a` in `RowRep`. Nothing in Phase 1 is
open anymore.
