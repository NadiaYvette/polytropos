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
 
- [x] Q1 eliminator result type and handler-result combination (hybrid monadic coproduct in PHASE2_SKETCH.md)
- [x] Q2 widening check: type-level evidence with runtime bounds check elision (PHASE2_SKETCH.md)
- [x] Q3 row-index `Rep`, or add a row-carrying wrapper beside the erased one (`RowRep` Case 3 wrapper adopted)
- [x] Field update efficiency architecture (`docs/notes/FIELD_UPDATE_EFFICIENCY_DESIGN.md`)
- [ ] Implement CoW updates, batched updates, and transient builders (`task-01`, `task-02`)
- [ ] `OverloadedLabels` / record-dot / record-update instance surface (`task-04`, `task-05`)
- [ ] Deriving (nominal products/sums) and generics (`task-07`)
 
## Milestone 3 — the plugin
 
Design note §6, in order:
 
- [x] Field name → literal slot index (solves `FieldIndex` constraints)
- [x] Constructor name → literal tag (solves `ConstructorIndex` constraints)
- [x] Plugin infrastructure: tcPluginInit looks up names from Polytropos.Core, GHC.Classes, GHC.Show, GHC.Base and stores in PluginState
- [x] RowEq/RowShow/RowEqSum/RowShowSum solvers walk rows with types (walkRowWithTypes, walkSumRowWithTypes)
- [x] Core AST method synthesis for `RowEq` and `RowShow` on literal products (smoke tests pass)
- [ ] Synthesize Core AST for `RowEqSum` and `RowShowSum` on sum rows (`task-03`)
- [ ] Synthesize `HasField` evidence for `OverloadedRecordDot` (`task-04`)
- [ ] Synthesize batched `setFieldsAt` evidence for `OverloadedRecordUpdate` (`task-05`)

## Milestone 4 — scale

- [x] Port the measurement harness into this repo so the compile-time claims
      are first-class and re-runnable here (`benchmark/variants`)
- [ ] Re-measure with the plugin in place; the target is arm-L behaviour
      (linear, and cheaper than a plain sum)
