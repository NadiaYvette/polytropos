# polytropos — Plan

Canonical roadmap. The operational frontier lives in `STATE.md`.

## Milestone 1 — skeleton (current)

- [x] Row vocabulary for products and sums (`Row`, `SumRow`)
- [x] `Rep`: tag + `SmallArray` payload, one representation for both shapes
- [x] Construction, access, injection, projection, elimination primitive
- [x] Evidence classes (`RowEq`, `RowShow`) with hand-written test instances
- [x] Design note with decisions, costs, and open questions

## Milestone 2 — semantics before machinery

Settle design note §4 and §7 **before** writing the plugin, because the answers
can change the row shape:

- [ ] Q1 eliminator result type and handler-result combination
- [ ] Q2 widening check: type-level evidence, runtime bounds check, or both
- [ ] Q3 row-index `Rep`, or add a row-carrying wrapper beside the erased one
- [ ] Deriving (nominal products/sums) and the source-plugin sugar
- [ ] `OverloadedLabels` / record-dot / record-update instance surface (design
      note D10: the extensions need no plugin, the evidence does)

## Milestone 3 — the plugin

Design note §6, in order:

- [x] Field name → literal slot index (solves `FieldIndex` constraints)
- [x] Constructor name → literal tag (solves `ConstructorIndex` constraints)
- [ ] `RowEq` / `RowShow` bodies emitted as literals (solvers stubbed — exported repTag/repArity/fieldAt from Core, need Core AST building)
- [ ] Retire the `Proxy r` debt (§5, D8a) by indexing `Rep` by its row

## Milestone 4 — scale

- [x] Port the measurement harness into this repo so the compile-time claims
      are first-class and re-runnable here (`benchmark/variants`)
- [ ] Re-measure with the plugin in place; the target is arm-L behaviour
      (linear, and cheaper than a plain sum)
