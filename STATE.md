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

The TcPlugin (Milestone 3), and the elimination algebra (Milestone 2). §4 of the
design note is the blocker: the row shape may need rework once the eliminator's
result type is chosen, and that rework is much cheaper at N=2 than at N=100.

## Open questions

See design note §7. In short: eliminator result type; widening check; whether
`Rep` should be row-indexed; whether `DictAny` survives literal emission; how
polytropos and large-anon coexist, if at all.

## Next action

Answer §7 Q1 (eliminator result type). Everything in Milestone 2 hangs off it.
