# polytropos — Row-Polymorphic / Open ADTs

Status: DRAFT v0.1 · 2026-10-05 — skeleton only; §4 and §6 are open by design
Related: `benchmark/variants/README.md` (the
measurement this design rests on), `~/src/sarutahiko/docs/registers/REUSE_REGISTER.md`
§1 Q1 (why a new generic layer is justified at all)

**Thesis.** One generic representation, indexed by nothing, that serves
products and sums alike, so that "nominal versus structural" stops being a
choice about the *value* and becomes a choice about the *type*. Four quadrants
that currently need four different mechanisms collapse to one.

---

## 0. Scope and status

This note is the institutional memory for the project; per the sarutahiko
skeleton conventions, code implements blessed designs and a stale note must be
corrected rather than ignored.

What exists now: a row vocabulary for products and sums, the `Rep`
representation, hand-written evidence classes, and a passing test suite
(`polytropos-core`); the TcPlugin (§6) has infrastructure in place and solves
`FieldIndex` / `ConstructorIndex` by emitting literal indices; the elimination
story (§4) has answers recorded below and a sketched shape in
`PHASE2_SKETCH.md`.

The rows below are expressed in the current concrete vocabulary — product rows
as `Row` (`[Pair Symbol Type]`) and sum rows as `SumRow` (`[Pair Symbol Row]`)
— until Phase 2 settles the `RowType` / `RowFlavour` vocabulary that the §4
answers imply.

Naming is deliberately outside the Noh-theatre convention used by the
`sarutahiko` program; `polytropos` belongs to a different, project-spanning
naming range. No relationship between the two programs is implied by the shared
documentation skeleton.

AGENTS.md §2 says design changes must correct this note in the same change set;
this update (§4 answered, §7 Q1–Q3 closed, §6 status currentised) is paired with
the commit that records it.

---

## 1. The row vocabulary

```haskell
data Pair a b = a := b

type RowOf k         = [Pair Symbol k]
type Row             = RowOf Type                      -- bare product: fields in order
type ProductRow f    = RowOf Type                      -- HKD product row parameterised by f
type ProductRowHKD f = ProductRow f

type SumRowOf prod   = [Pair Symbol prod]
type SumRow          = SumRowOf Row                    -- bare sum: constructors, each a product row
type SumRowHKD f     = SumRowOf (ProductRow f)         -- HKD sum: constructors with HKD product rows
type SumRowF f       = SumRowHKD f
```

**D1 — order is identity.** Two product rows with the same fields in a
different order are *different* rows. This is the decision that makes a field
index a compile-time constant; it is the same choice `large-anon` makes, and
the same trade (row order is not canonical, so two structurally equal records
may have different types).

**D2 — a sum's constructor is a product row.** `SumRow` nests rather than
flattening, so a constructor's arity is the length of its own row. This keeps
`Rep` uniform: there is no separate "sum field list" to keep in sync.

**D3 — the `f` functor parameter (resolved in §1.2).** `large-anon` threads `f`
through its rows so `Record f r` can box, validate, or delay fields. In
`polytropos`, `f` lives in `Rep f a`, `RowRep f r row a`, `RecordF f r`, and
`VariantF f s`. The row vocabulary is explicitly HKD-aware via `ProductRow f`,
`SumRowHKD f`, and promoted row flavours `ProductRowHKDT` / `SumRowHKDT`.
Evidence classes (`FieldIndex`, `ConstructorIndex`, `AllFields`) and plugin solving
operate directly over HKD rows, allowing generic field-class dictionary supply
(e.g. `Show` over `Maybe Int` fields) and `OverloadedRecordDot` projection on
HKD records.

**D3b — type-level row metadata and plugin rewriting (resolved in §1.3).**
To enable type-level reflection and generic programming without runtime overhead
or type-level search, `Polytropos.Core` provides metadata type families rewritten
directly by the TcPlugin:
- `FieldNames (r :: k) :: [Symbol]`
- `SimpleFieldTypes (r :: k) :: [(Symbol, Type)]`
- `FieldTypes (f :: Type -> Type) (r :: k) :: [(Symbol, Type)]`

When the row `r` is fully known (a closed promoted list of field bindings), the
plugin rewrites these families directly to concrete type-level lists using
`mkTyFamAppReduction`. Open rows (with uninstantiated tail variables) or sum rows
are not rewritten and remain deferred until instantiation.

---

## 2. The generic representation

```haskell
newtype Rep f a = Rep (Word#, SmallArray# (f Any))   -- as proposed
data Rep f a = Rep { repTag :: {-# UNPACK #-} !Word, repVals :: !(SmallArray (f Any)) }
```

**D4 — one representation, products are one-constructor sums.** A product is
the degenerate sum, its tag is always `0`, and because the tag is statically
known it folds away. The pay-off is that the four quadrants differ only in what
the type says:

| Quadrant | Type says | Value says |
|---|---|---|
| deep nominal | closed data decl | tag + fields |
| deep structural | `Row` | tag + fields |
| structural sum of nominal products | `SumRow` of closed types | tag + 1 slot |
| nominal sum of structural products | closed decl of `Row`s | tag + fields |

**D5 — `SmallArray`, not `Vector`.** One pointer per element instead of a
three-word box. `large-generics` 0.2 made the same move; `Vector` would have
been a placeholder here, exactly as suspected.

**D6 — the payload is erased, not typed.** `f Any` plus `unsafeCoerce` on
projection. Soundness rests entirely on the plugin only ever producing indices
that a real row justifies. This is `large-anon`'s bargain, taken knowingly.

**Known cost.** `setFieldAt` is `O(n)`: the array is rebuilt from a list
because the representation avoids a mutable array. A plugin that knows the
arity can emit a bounds-checked in-place write. Recorded, not solved (§6).

---

## 3. Arity, widening, narrowing

**D7 — constructor arities may differ.** `Rep` holds only the *selected*
constructor's slots, so `injectRep 0 [x]` and `injectRep 1 [x, y]` coexist
happily. The alternative — a uniform arity across a sum — would let the tag
double as a discriminant into a fixed-size array, at the cost of excluding
GADT-style heterogeneous sums. Heterogeneity is more valuable.

**D8 — widening is total, narrowing is not (resolved in §1.4).** Injecting a constructor of a
sub-row into a super-row sum is always well-defined: the tag is still valid in
the wider row *only if the sub-row is a subset*, which is
precisely the condition a `SubSum sub super` evidence class carries. Widening
(`widenVariant`, `widenVariantF`) is total and re-maps constructor tags in O(1)
using `subSumInjectIndices :: [Word]`.
Narrowing a wider variant to a sub-row (`narrowVariant`, `narrowVariantF`) is
partial: `subSumNarrowIndices :: [Maybe Word]` maps the active super-tag to `Just subTag`
if the constructor belongs to `sub`, or `Nothing` otherwise, avoiding redundant
runtime branching.
Similarly for product rows, `SubRow sub super` emits `subRowIndices :: [Int]`
enabling `projectRecord` and `projectRecordF` to extract sub-records in O(N).

---

## 4. Elimination — ANSWERED (hybrid), sketch in `PHASE2_SKETCH.md`

A variant needs three things, and each now has a decided shape (Phase 1):

1. **A total eliminator.** `matchRep` already hands the tag and payload to a
   continuation. The decided eliminator result is *a coproduct of per-constructor
   results, inside a monad* — `m (SumOf (Results handler-row))`. This is the
   hybrid of the result-sum and monadic candidates: per-constructor result types
   can differ (so the result GADT reflects genuinely different shapes, e.g. count
   vs scalar vs table), while the monad is on the outside so effect-system
   consumers (`effectful`, `polysemy`, `kernmantle`) can choose `m` without it
   becoming part of the row vocabulary. When all per-constructor results are the
   same type, a total flatten map specialises this to `m a` — so the uniform
   monadic candidate is a sound special case, not a competing design.

   The decided vocabulary implication: the handler row maps constructor names to
   *handler types*, not field rows — e.g.
   `'[ "neg" := (Int -> m Int), "add" := (Int -> Int -> m Bool) ]`. Under the
   chosen vocabulary (§7 Q3, Option D below), this is a concrete row flavour
   alongside `ProductRow` and `SumRow`, with a `RowFlavour` instance telling the
   eliminator / plugin / `SubSum` that the entry kind is `HandlerType`. So the
   handler row is not a polymorphic `Row k`; it is a concrete flavour in a
   class-based vocabulary (the D-shaped vocabulary), and that constrains the
   row-indexing decision to be D-consistent.

2. **A widening story.** †Narrowing a sum to a sub-row is certified by a type-level
   `SubSum` evidence value *that exists precisely so the runtime bounds check can
   be elided*. I.e. the hybrid: static guarantee (you can only narrow when you
   have the evidence, and the evidence is only constructible when the sub-row
   really is a subset — `large-anon`'s `SubRow` shape), plus the evidence is
   used to skip the runtime check it would otherwise justify, so you do not pay
   for both. For the handler-row flavour this implies, "sub-row" means a subset of
   handled constructors with the same handler types, and the `SubSum` evidence's
   concrete shape depends on the vocabulary decision in §7 Q3 (which is why the
   plan ordered the eliminator decision before the widening decision).

3. **A result combination.** Decided: the coproduct-of-per-constructor-results GADT
   sketched above, indexed by the handler row, with constructors named after their
   constructor names (e.g. `NegResult`, `AddResult`). This is more readable than a
   nested-`Either` type-family approach and specialises to `m a` for uniform
   results. The exact GADT constructors depend on the handler row's entries and are
   Phase 2 detail.

**The risk to watch.** §1 and §2 may need rework once §4 is answered; that is
cheaper to do now, at N=2 constructors, than at N=100. A decision not written
down is a decision not made — the answers above are recorded here and the shape
is sketched in `PHASE2_SKETCH.md`, per `DOC_STRATEGY.md` §4.

---

## 5. Evidence classes

```haskell
-- Current vocabulary (concrete Row / SumRow). The §7-Q3 decision (Case 3 wrapper
-- + Option D vocabulary) will generalise these to RowType and retire the Proxy
-- argument via a RowRep wrapper; see PHASE2_SKETCH.md.
class RowEq  (r :: Row) where repEq       :: Proxy r -> Rep f a -> Rep f a -> Bool
class RowShow (r :: Row) where repShowsPrec :: Proxy r -> Int -> Rep f a -> ShowS

-- Sum-row evidence (sketch, Phase 2): RowEqSum / RowShowSum over SumRow once the
-- vocabulary is settled.
```

Both have `undefined` defaults; the test suite supplies hand-written bodies.
Those bodies are **the specification of what the plugin must emit**: a fixed
number of slot comparisons at fixed literal indices, with no type-level search.

**D8a — explicit `Proxy r` is a known debt.** `Rep` is deliberately not
row-indexed (it is the erased form, shared by products and sums), so `RowEq r`
cannot be solved from the arguments. `large-anon` does not pay this because
`Record f r` carries the row in the type. The decided resolution (§7 Q3, Case 3)
is to keep `Rep` erased and add a typed `RowRep f (r :: RowType) a` wrapper whose
type carries the row; the evidence classes then work over `RowRep` and resolve
from the value's type. Closing the gap is a §6 job (obligation 4).

`DictAny` is present for the plugin's type-erased field dictionaries, mirroring
`large-anon`. Its fate after literal emission is §7 Q4.

`SubRow sub super` and `SubSum sub super` provide the evidence for structural
sub-typing: the TcPlugin emits literal projection slot indices `[Int]` for products,
and literal injection tags `[Word]` / narrowing maps `[Maybe Word]` for sums.

`KnownHash (s :: Symbol)` provides compile-time literal label hashing (FNV-1a 64-bit):
the TcPlugin solves `KnownHash` by evaluating the hash of the label literal at compile time
and emitting a literal `Word` dictionary.
- **Purpose:** O(1) integer keys for dynamic/HAMT label dispatch, name-based indexing,
  and interning without requiring `KnownSymbol` dictionary passing or runtime string hashing
  in hot paths.
- **Non-purpose:** Not used for row slot indexing in records and sums; slot offsets are
  determined statically and densely by `FieldIndex` and `ConstructorIndex` (0, 1, 2, ...).

---

## 6. The plugin — the load-bearing part

The measurement (`benchmark/variants/README.md`, GHC 9.14.1, N=10..100)
settled what the plugin is and is not for:

| Arm | ds-preopt growth | exponent |
|---|---|---|
| plain record (stock deriving) | linear | 1.04 |
| plain sum (stock deriving) | linear | 0.93 |
| structural variant, type-level index search | 579× over 10× N | 2.80 |
| structural variant, literal index (plugin output) | linear | 1.02 |

**D9 — the plugin is for the row-polymorphic index, not for sums.** Plain sums
and plain products are already linear; no plugin is needed to make them fast.
What costs is resolving a symbol to a compile-time index in a row, which
without a plugin is a type-level search costing ≈N^2.8 (2.08M lines of
pre-optimisation Core and 804 MB at N=100). With literal indices the same
values cost *less* than a plain sum (0.45–0.55×), and the benefit grows as
≈N^1.75.

**D10 — the three ergonomic extensions need no plugin.** `OverloadedLabels` is
a language extension over `IsLabel`; `OverloadedRecordDot` is native on GHC ≥
9.10; `OverloadedRecordUpdate` is core since 9.2 and driven entirely by
`HasField`. They will *work* once the `HasField`-shaped evidence is cheap, but
the plugin surface is the constraint solving, not the extensions.

Plugin obligations, in order (design note §6):

1. resolve a field name to a literal slot index (solves `FieldIndex`);
2. resolve a constructor name to a literal tag (solves `ConstructorIndex`);
3. emit `RowEq` / `RowShow` bodies as literals (solves the evidence-class methods);
4. index `Rep` by its row, retiring §5's `Proxy` debt (Case 3 wrapper — obligation
   4 is satisfied by the wrapper, not by changing the erased `Rep`);
5. emit `SubRow` and `SubSum` projection/narrowing indices as literal evidence;
6. compile-time label hashing via `KnownHash` solving;
7. source-plugin syntactic devices & open declaration forms (`Polytropos.Plugin.Source`):
   - Anonymous record construction & punning: `REC { x = 1, y = True }` / `REC_F { msg = Just "ok" }`.
   - Anonymous variant injection: `VAR { ok = ... }` / `VARIANT { err = ... }`.
   - Record update desugaring: `(REC_UPD r) { x = 42 }` into `setField` chains, `REC_UPD_F` for HKD.
   - Record & variant pattern matching: desugars into view patterns (`recordField`, `projectVariant`).
   - Open declaration forms: `data Person = Person { ... } deriving OpenRecord` and
     `data Status = Success { ... } | Failure { ... } deriving OpenVariant`, providing ergonomic
     nominal-looking syntax that compiles into open, structural, row-polymorphic types under the hood.
8. generic instance layer & dynamic dictionary emission:
   - `Polytropos.Plugin` emits wanted constraints for each field type (`Eq fieldTy`, `Show fieldTy`) dynamically in `solveRowEq`, `solveRowShow`, `solveRowEqSum`, and `solveRowShowSum`, lifting any restriction to hardcoded types.
   - Canonical `Eq`, `Show`, `Ord` instances for `RowRep` (products, sums, and HKD records) provided in `Polytropos.Core`.
   - `polytropos-generics` bridges `Generic` and `GInstances` to `RowRep`, deriving `geq`, `gcompare`, `gshowsPrec`, `gmap`, and `gfoldMap` over product and sum rows.
   - Row combinators `cmapRecord`, `cfoldMapRecord`, `czipWithRecord`, `cmapRecordF`, `cfoldMapRecordF` exported from `Polytropos`.

Status: obligations 1 through 8 fully implemented, verified across all 13 test suites in all 10 workspace packages with zero compiler warnings and zero errors.

---

## 7. Open questions

Decisions (closed):

- **Q1 (§4)** — *Decided.* Hybrid: `m (SumOf (Results handler-row))`, a coproduct
  of per-constructor results inside a monad. Per-constructor result types can
  differ (GADT indexed by the handler row); uniform results specialise to `m a`
  via a total flatten map. Handler row is a concrete row flavour (Option D),
  mapped constructor-name → handler-type. Sketch and rationale in
  `PHASE2_SKETCH.md` §1a.
- **Q2 (§3 / D8)** — *Decided.* Hybrid: a type-level `SubSum` evidence value that
  certifies the runtime bounds check can be elided. Static guarantee (evidence
  only constructible for genuine subsets) plus evidence-driven check elision, so
  you don't pay for both. Concrete evidence shape depends on the vocabulary
  decision (§7 Q3). Rationale in `IMPLEMENTATION_PLAN.md` §1b.
- **Q3 (§5, D8a)** — *Decided.* Case 3: keep the erased `Rep` unchanged and add a
  typed `RowRep f (r :: RowType) a` newtype wrapper that carries the row. `Rep`
  stays the measured runtime form; `RowRep` is the typed layer for evidence
  classes and plugin solving. Evidence classes generalise from `Row` to
  `RowType` and drop the `Proxy` argument. Vocabulary is Option D (concrete
  `RowType` flavours + `RowFlavour` class), so handler/result rows are concrete
  flavours alongside `ProductRow`/`SumRow`. Rationale in `IMPLEMENTATION_PLAN.md`
  §1c and sketch in `PHASE2_SKETCH.md`.

Still open:

- **Q4** Is `DictAny`-style erasure still needed once the plugin emits literals,
  or does the array make it redundant? Partially resolved: `f Any` stays (the
  `large-anon` erasure bargain, separate from `DictAny`); `DictAny` survives as a
  forward-looking dictionary-packing mechanism, but whether it is *needed* depends
  on whether the evidence classes carry field-class dictionaries (the current
  `RowEq`/`RowShow` don't), so it may not be needed immediately. Closed with nuance.
- **Q5** Interaction with `large-anon`: polytropos defines its own row vocabulary,
  so coexistence means a conversion seam. Unresolved by design — no migration is
  planned.
