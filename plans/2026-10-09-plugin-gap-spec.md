# Concrete spec sketch: immediate next step for the polytropos plugin

**Status:** sketch, not a committed plan
**Companion artifacts:**
- `plans/2026-10-09-plugin-gap-roadmap.md`
- `docs/notes/ROW_ROLE_DEFNS_DRAFT.ott`
- `docs/notes/POLYTROPOS_DESIGN.md`
- `packages/polytropos-core/src/Polytropos/Core.hs`
- `packages/polytropos-plugin/src/Polytropos/Plugin.hs`

**Intent:** This is the "what do we build next so the plugin becomes useful to
callers" sketch the user asked for. It is deliberately concrete about the
constraint shapes, the evidence shapes, the row vocabulary change, and the test
surface, while leaving implementation order and exact module boundaries open.

---

## 1. Goal of this step

Make the plugin supply **generic field-class evidence over a row** so callers can
write row-polymorphic code that needs "every field satisfies `c`" and actually get
usable dictionaries back, rather than merely having the constraint solved as a
yes/no.

This is the most direct route from the current literal-index core to a usable
generic row library, and it is the gap the user named in this session.

A secondary goal of the same step is to **make the row vocabulary HKD-aware**, so
the generic dictionary story can compose with `f`-parametric rows instead of being
stuck on `f ~ Identity` and a hardcoded set of field types.

---

## 2. What changes in the row vocabulary

The current shipped vocabulary is too concrete for the generic story:

```haskell
type Row    = [Pair Symbol Type]
type SumRow = [Pair Symbol Row]
```

That is fine for the current literal-index smoke, but it does not express:

- a functor parameter per field (`HKD`-style `f x` in each slot),
- a row whose element kind is not `Type`,
- the `RowType`-flavor vocabulary already sketched in `PHASE2_SKETCH.md`.

So the spec assumes we move toward a row vocabulary that can carry `f`, and that
the plugin solves constraints against that vocabulary.

### 2.1 Minimal HKD-aware product row

One concrete shape to aim at is something like:

```haskell
type ProductRow f = [Pair Symbol (f Type)]
```

or, if we want to keep the current `Pair` name but generalize it:

```haskell
type RowProd f = [Pair Symbol (App f Type)]
```

The exact spelling is open. What matters is that the row can express "each entry
is a field name paired with a parameterized field type," not just "each entry is a
field name paired with a bare `Type`."

### 2.2 HKD-aware sum row

For sums, the analogue is:

```haskell
type SumRow f = [Pair Symbol (ProductRow f)]
```

so a constructor's payload is itself an HKD-aware product row.

This keeps the existing design decision that a constructor is a product row, while
making the whole sum HKD-aware.

### 2.3 Why this matters for the plugin

If the row vocabulary cannot express `f`, then:

- the plugin can only solve for one concrete instantiation at a time,
- generic dictionary supply has to be redone per `f`,
- the row cannot be the shared generic surface that callers expect.

If the row vocabulary can express `f`, then the plugin can solve once against the
row shape and supply per-field dictionaries parameterized by `f`.

### 2.4 Relationship to the existing `RowRep` wrapper

The design note and `PHASE2_SKETCH.md` already decided on a `RowRep` wrapper that
carries the row in the type. This spec assumes that wrapper stays, and that the
vocabulary change is about **what the row parameter of the wrapper can express**, not
about discarding the wrapper.

So the move is:

- from `RowRep f (r :: Row) a` with `Row = [Pair Symbol Type]`,
- toward `RowRep f (r :: RowType) a` where the row flavor/vocabulary can express
  HKD-aware product and sum rows.

This is consistent with the existing Option D direction and with the current
`RowFlavour` class shape.

---

## 3. What changes in the evidence-class surface

The immediate goal is not "rework every class." It is "add the generic dictionary
supply class and make the existing classes consistent with HKD-aware rows."

### 3.1 Add an all-fields-style class

We want a class whose meaning is:

> for every field in the row, the field type satisfies `c`

and whose evidence is usable as a flat array of type-erased dictionaries.

A sketch of the class shape:

```haskell
class AllFields (r :: RowType) (c :: Type -> Constraint) where
  fieldDicts :: DictAllFields r c
```

with an evidence type like:

```haskell
type DictAllFields (r :: RowType) (c :: Type -> Constraint) =
  Tagged r (SmallArray (DictAny c))
```

and:

```haskell
data DictAny (c :: Type -> Constraint) where
  DictAny :: c x => DictAny c
```

This is deliberately close to the large-anon shape, because that is the precedent
the user wants polytropos to reach. The polytropos-specific adaptation is that the
row parameter is the HKD-aware row vocabulary, not large-anon's `Row k`.

### 3.2 What the evidence is for

The point of `fieldDicts` is not "the constraint is solved." The point is "here is
a flat array of dictionaries you can map over."

That is what lets callers write generic operations such as:

- show every field,
- compare every field,
- convert every field to JSON,
- map a constrained function over every field,
- reify constraints for reflection/generic derivation,

without writing per-row instances by hand.

### 3.3 How this relates to `RowEq`/`RowShow`

Today `RowEq`/`RowShow` are the spec for what the plugin emits for those specific
classes. After this step, `RowEq`/`RowShow` can be seen as **instances of the
generic story**, or at least as compatible with it.

Concretely, we do not need to delete `RowEq`/`RowShow`. We do want them to stop
being the only generic surface, and we want the plugin to be able to supply the
dictionaries they need without a hardcoded type set.

So the right framing is:

- `RowEq`/`RowShow` remain as the existing literal-emission spec where relevant.
- `AllFields`-style supply becomes the generic mechanism underneath a broader class
  of operations.
- The plugin stops being "Eq/Show on Int/Bool/Word only."

### 3.4 Do not overgeneralize yet

The spec does **not** require:

- a fully kind-polymorphic row vocabulary immediately,
- every possible class to be solvable immediately,
- a full reflection/reify layer on day one.

It does require the class and evidence shape to be concrete enough that the plugin
can solve it and the test suite can assert it.

---

## 4. What changes in the plugin

### 4.1 Dictionary resolution must become generic-style

Today the plugin resolves `Eq`/`Show` dictionaries for a small hardcoded set of
types. The spec wants this to become:

- extensible in a controlled way,
- grounded in the row's field types,
- usable for a broad set of field-class constraints, not just `Eq`/`Show`.

That does **not** mean "do type-level search at the use site." It means "when the
row is known, the plugin walks it and supplies the per-field dictionaries the row
justifies."

So the plugin gains a path that is:

- row-walking, yes,
- but literal/closed-world evidence supply, not open-ended type-level induction at
  the call site.

This is the same spirit as large-anon: the plugin does the row walk once and emits
the evidence.

### 4.2 The plugin should solve the all-fields constraint

When GHC wants `AllFields r c`, the plugin should:

1. inspect the row `r`,
2. for each field type in the row, obtain the dictionary for `c` on that field type,
3. wrap each in `DictAny c`,
4. emit the array as the evidence for `AllFields r c`.

If any field type cannot be satisfied, the constraint should fail in a clear way
rather than being left unsolved or falling back to a tiny hardcoded set.

### 4.3 The plugin should be ready for HKD-aware rows

Because the row vocabulary is becoming HKD-aware, the plugin's row walking and
dictionary supply must be able to work over the parameterized field types.

That means the plugin must not assume:

- that every field type is a bare `Type`,
- that the only interesting `f` is `Identity`,
- that dictionary supply is independent of the row's element kind.

It does mean the plugin can still assume:

- the row is known at solve time for the cases it is built to handle,
- the field order is fixed and known,
- the plugin emits literal evidence derived from that known row.

### 4.4 Keep the literal-index obligations intact

This step does **not** replace the existing obligations. It layers on top of them:

- `FieldIndex` / `ConstructorIndex` stay as literal index solving.
- `RowEq` / `RowShow` / `RowEqSum` / `RowShowSum` stay as literal emission where
  they are used.
- `HasField`-style dot access stays where it is used.

The new surface is additive: it is the generic dictionary supply path, not a
replacement for the literal index core.

---

## 5. Test surface for this step

The test surface should prove that the plugin supplies usable dictionaries through
the new class, not merely that the class compiles.

### 5.1 Concrete test cases to add

At minimum, the step should be asserted by tests that show:

1. **A small HKD-aware product row** whose fields are not confined to
   `Int`/`Bool`/`Word`, and where `AllFields r c` is solved through the plugin.
2. **A sum row** with HKD-aware constructor payloads, where the same generic
   dictionary supply works per constructor row.
3. **A consumer function** that uses `fieldDicts` to do something generic, such as
   show every field or compare every field, and that works for more than the
   current hardcoded type set.
4. **A negative or boundary case** showing that an unsatisfiable field class fails
   clearly, so the plugin is not silently incomplete.

### 5.2 Smoke test posture

The existing smoke tests already assert the literal index/equality/show story. This
step should add a complementary smoke that asserts the **generic dictionary supply**
story.

That smoke should be readable as "the plugin supplies dictionaries for this row and
this class, and a generic consumer can use them."

### 5.3 Hand-written instances stay as spec where they still matter

The hand-written `RowEq`/`RowShow` instances in
`packages/polytropos-core/test/Main.hs` remain useful as the literal-emission spec
for those classes. They do **not** need to be the only way to test generic dictionary
supply.

In other words: keep the existing spec where it is still the right spec; add a new
spec surface for the new generic surface.

---

## 6. What this step does not yet require

To keep the step buildable, it is deliberately limited.

It does **not** yet require:

- a full `FieldTypes`/`SimpleFieldTypes` metadata family and rewriter,
- a `KnownHash`-style label hashing mechanism,
- a subrow/projection evidence class,
- a source-plugin construction syntax,
- a complete generic instance layer for all stock classes,
- a fully final HKD row vocabulary spelling.

Those are later items on the roadmap. This step is the one that makes the plugin
generically useful in the dictionary sense, and makes the row vocabulary HKD-aware
enough to support that.

---

## 7. Open design questions this sketch leaves explicit

### 7.1 Exact HKD row spelling

Do we generalize `Row`/`SumRow`, or introduce a new flavor in the `RowType`
vocabulary, or both? The sketch assumes HKD awareness is added, but not a single
fixed spelling.

### 7.2 Scope of the initial generic class set

What is the initial closed-but-expandable set of classes/types the plugin will cover?
The sketch assumes "broader than Int/Bool/Word, but still a deliberate set," not
"literally every class everywhere."

### 7.3 How `DictAny` is used

Do callers consume `DictAny` directly, or is there a small reification helper layer
on top? The sketch assumes `DictAny` is the core erasure mechanism and leaves the
consumer surface open.

### 7.4 Interaction with `RowRep` and `RowFlavour`

How exactly the all-fields class is indexed relative to `RowRep` and `RowFlavour`
is left open; the sketch only requires consistency with the existing Option D
direction.

---

## 8. Success criteria for this step

A good version of this step would mean:

- the plugin can supply generic field-class dictionaries for HKD-aware rows,
- the current literal-index obligations still hold,
- the plugin is no longer gated to a tiny hardcoded type set for `Eq`/`Show`,
- the test suite can assert the generic dictionary supply through the plugin,
- the row vocabulary and evidence classes are concrete enough that callers can
  start writing row-polymorphic generic code against them.

That is the "useful to potential callers" threshold this step is trying to reach.
