# polytropos — Implementation Plan

Canonical plan. The operational frontier (what we are doing *right now*) lives
in `STATE.md`; this file records the *order* and the *reasoning* behind it.

## Guiding principle

**Semantics before machinery.** The measurement (`benchmark/variants`) proves
that the *structural interface* is what costs compile time, not the sum itself —
plain sums are already linear (arm A, exponent 0.93). So the plugin is
load-bearing, and the plugin depends on a settled elimination story because the
answers there can reshape the row. Getting the semantics wrong and then
discovering it at N=100 is the project's declared failure mode; the plan exists
to avoid it by doing the expensive reasoning cheaply, at N=2.

## Phase 1 — Semantic settlement (Milestone 2)

**Input:** design note §4 (elimination, open) and §7 Q1–Q3 (open questions).
**Output:** answers recorded in the design note, updated §1/§2 if the row shape
changed, and a short design-threaded document capturing the chosen algebra.

This phase has no code beyond what already exists. Its job is to remove the
blocker that makes Milestone 3 dangerous to start.

### 1a — Eliminator result type (design note §4, Q1) — DECIDED: hybrid

**Decision:** the eliminator's result is a coproduct of per-constructor results,
inside a monad — i.e. `m (SumOf (Results handler-row))`. This is the hybrid of
the result-sum and monadic candidates, and it specialises to the monadic
candidate when all per-constructor results are the same type (via a
coproduct-flattening map that is total because a sum value has exactly one
constructor, so exactly one handler fires).

**Why this is the most general:**

- Per-constructor result types can differ — handler for `"neg"` can return `Int`
  and handler for `"add"` can return `Bool`, and the result sum reflects that
  directly. This is what the database-interaction domain needs (count vs scalar
  vs table have genuinely different result shapes).
- The monad is on the *outside*, so handlers can carry effects (the
  `effectful`/`polysemy`/`kernmantle` consumers) without the monad being part of
  the row vocabulary — the row vocabulary carries the per-constructor result
  types, and `m` is chosen by the caller.
- The uniform-result specialisation (`m a`) is sound and free, so the monadic
  candidate is a special case, not a competing design.

**What this implies for the row vocabulary (flows into 1c):**

The handler row maps constructor names to *handler types*, not field rows —
`'[ "neg" := (Int -> m Int), "add" := (Int -> Int -> m Bool) ]`. Under Option D
(the chosen vocabulary), this is a concrete row flavour — e.g. `HandlerRowD ::
RowType` — alongside `ProductRow` and `SumRowD`, with a `RowFlavour HandlerRowD`
instance that tells the plugin/eliminator/`SubSum` that the entry kind is
`HandlerType`. So the handler row is *not* a polymorphic `Row k` (Option B); it's
a concrete flavour in a class-based vocabulary (Option D). This is the D-shaped
vocabulary, and it constrains 1c's row-indexed-`Rep` or wrapper shape to be
D-consistent (concrete `RowType`, class-based `k`).

**What remains to investigate:**

The *choice* is made. What remains is to (1) write the handler row and
result-coproduct type for a two-constructor sum with *different* per-constructor
result types, and confirm it is usable at the call site; (2) write the same with
*uniform* result types and confirm the specialisation to `m a` via flatten is
acceptable; (3) write a database-style example where results differ and confirm
the coproduct captures it without awkward wrapping; (4) write an
effect-system-style example and confirm the `m`-on-the-outside shape is what
those consumers want. That is the content of the 1a investigation now — not
choosing, but surfacing the row vocabulary the choice implies.

### 1b — Widening check (design note §3, D8; §7 Q2) — DECIDED: hybrid

**Decision:** narrowing a sum to a sub-row is a type-level `SubSum` evidence value
*that certifies the runtime check can be elided*. I.e. both: the evidence exists
at the type level (like `large-anon`'s `SubRow`), and the point of the evidence
is to tell the compiler/runtime that the bounds check the `Maybe` in
`projectRep` today would do is unnecessary for these particular rows.

**Why this is the hybrid:**

- Pure type-level evidence (`SubSum` without a runtime component) makes narrowing
  total at the call site — you can only call the narrow operation when you have
  the evidence, and the evidence is only constructible when the sub-row really is
  a subset. That's the `large-anon` shape.
- Pure runtime check (`projectRep`'s `Maybe` today) makes narrowing observable —
  a mismatched tag yields `Nothing`, not a type error. That's simple but loses
  the static guarantee.
- The hybrid keeps the static guarantee (you need the evidence to narrow) *and*
  uses the evidence to elide the runtime check when it's present, so you don't
  pay for both. The evidence certifies the check can be skipped.

**What this implies for the row vocabulary (depends on 1a's handler-row decision):**

A `SubSum` evidence value relates two rows — a sub-row and a super-row. For the
value-row case (`SumRow` of constructor names → field-rows), "sub-row" means a
subset of constructors with the same field rows. For the handler-row case the 1a
hybrid implies, "sub-row" would mean a subset of handled constructors with the
same handler types — but that only makes sense if handler rows are their own row
type, or if the vocabulary is polymorphic enough to express both. So 1b's
evidence shape depends on 1a's row-vocabulary decision, which is why the plan
orders 1a before 1b. The decision to go hybrid here is made; the evidence's
concrete shape is pending that vocabulary decision.

### 1c — Row indexing for `Rep` (design note §5, D8a; §7 Q3) — DECIDED: Case 3 (erased `Rep` + D-shaped wrapper)

**Decision:** keep the current erased `Rep f a` (tag + `SmallArray (f Any)`)
exactly as it is, and add a typed wrapper that carries the row:
`data RowRep f (r :: RowType) a = RowRep (Rep f a)`. The wrapper is the typed,
row-carrying layer for evidence classes and plugin solving; the inner `Rep` is the
unchanged, measured, working runtime form (a newtype at runtime, zero cost).

**Why this is the conservative choice:**

- The measured `Rep` stays exactly as it is — no risk to the representation that
  is already measured and working.
- The wrapper is a newtype (`RowRep`), so the runtime cost is the same as the
  current state — tag + array, with zero overhead from the wrapper.
- The `Proxy r` debt is gone at the evidence level: the row is in `RowRep`'s type
  (`RowRep f r a`), so `RowEq r` (or `RowEq (r :: RowType)`) resolves from the
  value's type without a `Proxy` argument. That is plugin obligation 4 (retire
  the Proxy debt), satisfied via the wrapper.
- The plugin sees `RowRep f r a` (concrete `RowType` per Option D) and solves
  from the wrapper's type, using `RowFlavour r` to know the entry kind. The inner
  erased `Rep` is not what the plugin solves against — the wrapper is.

**What this means for the three cases compared earlier:**

- **Case 1 (index `Rep` over `RowType`):** rejected — would change `Rep` from the
  erased form to a row-carrying form, risking the measured representation.
- **Case 2 (index `Rep` over one flavour):** rejected — narrower than case 1, but
  still changes `Rep` and means `Rep` is not the uniform erased form.
- **Case 3 (erased `Rep` + wrapper):** chosen — `Rep` unchanged, wrapper is the
  typed layer. Two types (`Rep` + `RowRep`), but `Rep` stays the measured form.

**What is still open after this decision:**

The *shape* of 1c is decided (Case 3), but two details are not yet sketched:

1. **The wrapper's evidence-class shape:** is it `class RowEq (r :: RowType) where
   repEq :: RowRep f r a -> RowRep f r a -> Bool`, or is the wrapper further
   parameterised (e.g. `RowRep f (r :: RowType) (a :: Type)`)? The plan assumes
   the simple `RowRep f r a` shape, but the evidence classes' exact signatures
   need to be written down in Phase 2.

2. **The wrapper's interaction with products:** a product is a one-constructor sum,
   so it should use the same `RowRep` (with `SumRowT` or a `ProductRowT` flavour).
   The design note §2 says products are one-constructor sums — case 3 should
   preserve that, with the wrapper carrying the product row or sum row as
   appropriate. Needs checking in Phase 2.

3. **The plugin's exact obligation-4 surface:** the plugin solves `RowEq r` / `HasField
   n r a` from `RowRep f r a`'s type, but the exact constraint shapes need to be
   written down before Phase 3. The plan assumes the plugin sees `RowRep f r a`
   and uses `RowFlavour r`; the details are Phase 2/3 work.

### 1d — Deriving and source-plugin sugar (design note §6, D10)

Scope the deriving story for nominal products and sums, and the `IsLabel` /
record-dot / record-update surface. D10 says these extensions need no plugin — the
evidence does — so this is about which `HasField`-shaped evidence the plugin emits,
not about the extensions themselves. Keep the surface small: the measurement says
the payoff is in literal indices, not in a broad deriving sweep.

### 1e — Document the answers

Record each answer in the design note, mark §4 closed if it is, and update §1/§2
if the row shape changed. Update `PLAN.md` to reflect that Milestone 2 is done.
Do not start Milestone 2 code until this is written down — the note is load-bearing
(per `AGENTS.md` advisory 1), and a decision not written down is a decision not
made.

## Phase 2 — Evidence hardening (before the plugin)

**Input:** settled semantics from Phase 1.
**Output:** hand-written evidence instances that reflect the chosen algebra,
updated tests that are the specification the plugin must match, and any new module
shape decided in Phase 1.

This phase prepares the tests that the plugin will be measured against. It is
small in code but large in correctness: the hand-written `RowEq`/`RowShow` bodies
are *the specification of what the plugin emits*, per `AGENTS.md` advisory 3 and
the design note §5. If these bodies do a type-level search, the tests no longer
test the point.

Concrete work:

- Add hand-written evidence for a small sum row (more than one constructor) so the
  plugin's constructor-name → tag obligation has a target to hit.
- Add evidence reflecting the chosen eliminator shape from 1a, if the eliminator
  has a literal evidence form.
- Add evidence reflecting the chosen widening check from 1b.
- If Phase 1 chose row-indexed `Rep` or a wrapper (1c), sketch the module shape and
  update the evidence classes to match before writing the plugin against them.

## Phase 3 — The TcPlugin (Milestone 3)

**Input:** Phase 2 evidence shape, settled semantics.
**Output:** a plugin that solves the constraints in design note §6, in order.

Plugin obligations, in the order the design note gives them:

1. **Field name → literal slot index.** Resolve a field symbol in a `Row` to a
   compile-time integer. This is the obligation the measurement isolating C vs L
   proves is worth building: with it, compile-time cost drops from ≈N^2.8 to
   linear and below a plain sum.
2. **Constructor name → literal tag.** Resolve a constructor symbol in a `SumRow`
   to its position. Plain sums are already linear (arm A), so this is for the
   structural interface only — exactly the scope the measurement justifies.
3. **`RowEq` / `RowShow` bodies as literals.** Emit the fixed-index comparison
   bodies the tests specify, with no type-level search.
4. **Retire the `Proxy r` debt (§5, D8a).** Index `Rep` by its row, or emit the
   wrapper evidence decided in 1c, so row-polymorphic constraints solve from the
   value's type.

Scope discipline: the plugin solves constraints; it does not implement the
extensions. D10 is explicit that `OverloadedLabels`, record-dot, and
record-update are driven by `HasField`/`IsLabel` and need only cheap evidence,
which the plugin provides. Do not expand the plugin surface to "do deriving" — that
is a different plugin shape and the measurement does not justify it yet.

Implementation notes:

- The plugin is a separate package (`polytropos-plugin` in `packages/`), so the
  core package stays measurable and the plugin can be added and removed without
  touching the measured baseline.
- The plugin's own tests compile modules that exercise each obligation and check
  that the emitted Core contains literal indices, not type-level search. Mirror the
  measurement harness's discipline: deterministic Core lines, same flags, same
  `-package-env -`.
- Keep the plugin's interface small and versioned against a specific GHC (9.14
  today): the TcPlugin API is the kind of surface that is expensive to widen later.

## Phase 4 — Integration and scale (Milestone 4)

**Input:** plugin from Phase 3, evidence from Phase 2.
**Output:** the plugin wired in, the measurement re-run with the plugin in place,
and the claimed behaviour verified against the arm-L target.

Concrete work:

- Add the plugin package to `cabal.project` (it was deliberately absent — the
  benchmark harness is standalone and `cabal build all` should not compile it).
- Re-run the measurement harness with the plugin in place. The target is arm-L
  behaviour: linear Core growth, cheaper than a plain sum (0.45–0.55× arm A),
  and the benefit growing as ≈N^1.75.
- Verify the re-run against the existing `results.csv` using the comparison script
  in `benchmark/variants/README.md`: Core columns must reproduce; wall-clock and
  RSS are indicative only.
- If the re-run does not hit arm-L behaviour, the plugin's index emission is wrong
  — not the measurement. Fix the plugin, not the harness.

## Phase 5 — Governance and docs (ongoing, batched)

**Output:** commit discipline, attribution, documentation lifecycle, and register
updates, done as batch work at phase boundaries rather than inline.

- Commits: descriptive-imperative subject, body explains why, HEREDOC style, Linux
  kernel `Assisted-by: LLM` trailer (per `AGENTS.md` advisory 4 and
  `docs/notes/COMMIT_ATTRIBUTION.md`). Never `Co-authored-by:`.
- Documentation: stale notes corrected in the same change set that makes them stale
  (per `DOC_STRATEGY.md` §4). This matters most for the design note across Phase 1
  and Phase 3.
- Registers: `docs/registers/PACKAGES.md` updated when a new package (the plugin)
  is added, and when a package's class changes.
- Attribution: `THIRD_PARTY.md` and `docs/notes/PROVENANCE.md` consulted before
  claiming anything about `large-data`/`large-records`/`large-anon`. Nothing from
  them is compiled as part of this project; the relationship is comparison, not
  dependency.

## What is deliberately not in this plan

- A `Variant` type with its own `Show`/`Eq`/JSON/eliminator story. The measurement
  says the cheapest first milestone is a closed nominal sum with a plugin-synthesised
  structural view, not a new variant type. The `Show`/`Eq` story is not inherited
  from `large-generics`: that package's `Rep` is product-shaped, its `Generic`
  class is product-shaped, and `:+:` occurs in no file in it. A variant needs its
  own tag and per-constructor shape — real work, and not yet justified by any
  measurement here.
- The full monorepo restructure and the `Isomorphic` hybrid layer from the earlier
  draft plan. The measurement disproved the premise those rested on: `large-records`
  nominal records round-trip through a list of `Any` (O(n) copy), and `Anon.Record`
  is a two-constructor sum, so no single `unsafeCoerce` relates them.
- Any migration between `polytropos` and `large-anon`. Coexistence means a
  conversion seam, which is unresolved by design (§7 Q5). No migration is planned.

## Current position

1a decided (hybrid result type + Option D vocabulary). 1b decided (hybrid
`SubSum` over concrete `RowType` via `RowFlavour`). 1c decided (Case 3: keep
erased `Rep` unchanged, add D-shaped `RowRep` wrapper). All of Phase 1's
decisions are made; what remains is Phase 2's sketching work (wrapper's
evidence-class signatures, products interaction, plugin obligation-4 surface)
before Phase 3 (the plugin) can start. The skeleton (Milestone 1) is complete:
`polytropos-core` builds on GHC 9.14.1 and its 25 tests pass.

## Reading map for this plan

- For the *why*: `benchmark/variants/README.md` — the measurement that justifies
  the plugin and scopes its surface.
- For the *what exists*: `STATE.md` and `packages/polytropos-core/src/Polytropos/Core.hs`.
- For the *what is open*: `docs/notes/POLYTROPOS_DESIGN.md` §4 (now answered: 1a hybrid + Option D vocabulary, 1b hybrid widening, 1c Case 3 wrapper all decided); §7 Q4 (does `DictAny` survive literal emission?) and Q5 (polytropos/large-anon coexistence) are the remaining open questions.
- For the *how to change it*: `docs/notes/DOC_STRATEGY.md` and `AGENTS.md`.
