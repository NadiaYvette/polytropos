# polytropos — Row-Polymorphic / Open ADTs

Status: DRAFT v0.1 · 2026-10-05 — skeleton only; §4 and §6 are open by design
Related: `~/src/large-data/large-records-benchmarks/variants/README.md` (the
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
(`polytropos-core`). What does **not** exist yet: the TcPlugin (§6), the
elimination story (§4), and the row-indexing that would remove the `Proxy`
debt in §5.2.

Naming is deliberately outside the Noh-theatre convention used by the
`sarutahiko` program; `polytropos` belongs to a different, project-spanning
naming range. No relationship between the two programs is implied by the shared
documentation skeleton.

---

## 1. The row vocabulary

```haskell
data Pair a b = a := b

type Row    = [Pair Symbol Type]   -- a product: fields in order
type SumRow = [Pair Symbol Row]    -- a sum: constructors, each a product row
```

**D1 — order is identity.** Two product rows with the same fields in a
different order are *different* rows. This is the decision that makes a field
index a compile-time constant; it is the same choice `large-anon` makes, and
the same trade (row order is not canonical, so two structurally equal records
may have different types).

**D2 — a sum's constructor is a product row.** `SumRow` nests rather than
flattening, so a constructor's arity is the length of its own row. This keeps
`Rep` uniform: there is no separate "sum field list" to keep in sync.

**D3 — the `f` functor parameter is deferred.** `large-anon` threads `f` through
its rows so `Record f r` can box or delay fields. `Rep` carries `f`, but `Row`
does not yet, so `f ~ Identity` is the only inhabited case. Deferred, not
decided against: `Rep f` with `f = Maybe` already means something.

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

**D8 — widening is total, narrowing is not.** Injecting a constructor of a
sub-row into a super-row sum is always well-defined: the tag is still valid in
the wider row *only if the sub-row is a prefix-compatible subset*, which is
precisely the condition a `SubSum` evidence value would carry. Projecting out
of a wider row is **not** total: an unexpected tag has no statically known
recovery, so `projectRep` returns `Maybe` and the failure is observable rather
than a type error.

This asymmetry is real and is inherited from records in a modified form
(records' `SubRow` is total in both directions because field access is total;
sum access is not). It is the reason §4 is open.

---

## 4. Elimination — OPEN, and deliberately so

A variant needs three things this skeleton does not yet have:

1. **A total eliminator.** `matchRep` hands the tag and payload to a
   continuation and leaves the unmatched case to it. A real eliminator over an
   *open* row needs a row of handlers and a rule for combining their results.
2. **A widening story.** The §3 asymmetry means a handler stack must be checked
   against the row it claims to handle, and the failure mode must be chosen.
3. **A result combination.** `Either`? a sum of results? an effect? For
   effect-system consumers (`effectful`, `polysemy`, `kernmantle`) this is the
   load-bearing question, and it is the one most likely to force the row shape
   to change.

**The risk to watch.** Shipping the representation before settling the algebra
is the classic failure mode here. §1 and §2 may well need rework once §4 is
answered; that is cheaper to do now, at N=2 constructors, than at N=100.

---

## 5. Evidence classes

```haskell
class RowEq  (r :: Row) where repEq       :: Proxy r -> Rep f a -> Rep f a -> Bool
class RowShow (r :: Row) where repShowsPrec :: Proxy r -> Int -> Rep f a -> ShowS
```

Both have `undefined` defaults; the test suite supplies hand-written bodies.
Those bodies are **the specification of what the plugin must emit**: a fixed
number of slot comparisons at fixed literal indices, with no type-level search.

**D8a — explicit `Proxy r` is a known debt.** `Rep` is deliberately not
row-indexed (it is the erased form, shared by products and sums), so `RowEq r`
cannot be solved from the arguments. `large-anon` does not pay this because
`Record f r` carries the row in the type. Closing the gap is a §6 job.

`DictAny` is present for the plugin's type-erased field dictionaries, mirroring
`large-anon`.

---

## 6. The plugin — the load-bearing part

The measurement (`large-records-benchmarks/variants/README.md`, GHC 9.14.1, N=10..100)
settled what the plugin is and is not for:

| Arm | ds-preopt growth | exponent |
|---|---|---|
| plain record (stock deriving) | linear | 1.04 |
| plain sum (stock deriving) | linear | 0.94 |
| structural variant, type-level index search | 569× over 10× N | 2.80 |
| structural variant, literal index (plugin output) | linear | 1.01 |

**D9 — the plugin is for the row-polymorphic index, not for sums.** Plain sums
and plain products are already linear; no plugin is needed to make them fast.
What costs is resolving a symbol to a compile-time index in a row, which
without a plugin is a type-level search costing ≈N^2.8 (2.08M lines of
pre-optimisation Core and 865 MB at N=100). With literal indices the same
values cost *less* than a plain sum (0.52×), and the benefit grows exactly
linearly in N.

**D10 — the three ergonomic extensions need no plugin.** `OverloadedLabels` is
a language extension over `IsLabel`; `OverloadedRecordDot` is native on GHC ≥
9.10; `OverloadedRecordUpdate` is core since 9.2 and driven entirely by
`HasField`. They will *work* once the `HasField`-shaped evidence is cheap, but
the plugin surface is the constraint solving, not the extensions.

Plugin obligations, in order: (1) resolve a field name to a literal slot
index; (2) resolve a constructor name to a literal tag; (3) emit `RowEq` /
`RowShow` bodies as literals; (4) index `Rep` by its row, retiring §5's
`Proxy` debt.

---

## 7. Open questions

- **Q1 (§4)** What is the eliminator's result type, and what combines handler
  results? Blocks everything downstream of the row shape.
- **Q2 (§3)** Is the widening check a type-level `SubSum` evidence value, a
  runtime bounds check, or both?
- **Q3 (§5)** Should `Rep` become row-indexed, or should a distinct
  row-carrying wrapper exist alongside the erased `Rep`?
- **Q4** Is `DictAny`-style erasure still needed once the plugin emits
  literals, or does the array make it redundant?
- **Q5** Interaction with `large-anon`: polytropos defines its own row
  vocabulary, so coexistence means a conversion seam. Unresolved by design —
  no migration is planned.
