# Phase 2 — Sketching work

Canonical sketch. Records the evidence-class signatures, the products interaction,
and the plugin obligation-4 surface that Phase 1's decisions (1a hybrid + Option D
vocabulary, 1b hybrid `SubSum`, 1c Case 3 wrapper) imply. This is the Phase 2 work
before Phase 3 (the plugin) can start.

## What Phase 2 sketches

Phase 1 settled the *decisions* (what we want). Phase 2 sketches the *shape* (how
it looks in code). Three pieces:

1. **The `RowRep` wrapper and its evidence classes** — the typed, row-carrying layer
   on top of the erased `Rep`.
2. **Products interaction** — the design note §2 says products are one-constructor
   sums; the wrapper should preserve that.
3. **The plugin obligation-4 surface** — the exact constraint shapes the plugin
   solves when retiring the `Proxy` debt.

## Piece 1 — The `RowRep` wrapper and evidence classes

### 1a. The row vocabulary (Option D, concrete flavours)

```haskell
-- A type for row flavours (Option D vocabulary)
data RowType
  = ProductRowT        -- field name → field type   (was Row)
  | SumRowT            -- constructor name → field-row  (was SumRow)
  | HandlerRowT        -- constructor name → handler type
  | ResultRowT         -- constructor name → result type
  -- more flavours as needed

-- The class that abstracts over flavours
class RowFlavour (r :: RowType) where
  type EntryKind (r :: RowType) :: Type
  -- The "kind" of entries in this row:
  --   ProductRowT    → Type
  --   SumRowT        → Row ProductRowT   (a field-row)
  --   HandlerRowT    → HandlerType       (a handler type)
  --   ResultRowT     → ResultType        (a result type)

-- Instances (sketch)
data ProductRowT :: RowType
type instance EntryKind ProductRowT = Type

data SumRowT :: RowType
type instance EntryKind SumRowT = Row ProductRowT

data HandlerRowT :: RowType
type instance EntryKind HandlerRowT = HandlerType   -- sketched below

data ResultRowT :: RowType
type instance EntryKind ResultRowT = ResultType     -- sketched below
```

### 1b. The erased `Rep` (unchanged)

```haskell
-- Rep stays exactly as it is now — the measured, working runtime form.
-- No changes to Rep itself.
data Rep (f :: Type -> Type) a = Rep
  { repTag  :: {-# UNPACK #-} !Word
  , repVals :: !(SmallArray (f Any))
  }
```

### 1c. The typed wrapper (Case 3)

```haskell
-- The typed, row-carrying wrapper. Newtype, zero runtime cost.
data RowRep (f :: Type -> Type) (r :: RowType) a = RowRep
  { unRowRep :: Rep f a
  }
```

The wrapper is a newtype, so at runtime it is exactly `Rep f a` — tag + `SmallArray (f Any)`. The `r :: RowType` is in the wrapper's type, not in the runtime representation.

### 1d. The handler type encoding (sketch)

The handler type encoding is the hard part that every option had to face. It encodes
"handler for constructor X with these field types, returning result type Y in monad M".
A sketch:

```haskell
-- A handler type: "handler for constructor named n, with field types fs,
-- returning result type res in monad m"
data HandlerType (n :: Symbol) (fs :: Row ProductRowT) (res :: Type) (m :: Type -> Type)
  = HandlerType

-- Example: handler for "neg" (one Int field), returning Int in IO
--   HandlerType "neg" '[ 'Int ] Int IO

-- Example: handler for "add" (two Int fields), returning Bool in IO
--   HandlerType "add" '[ 'Int, 'Int ] Bool IO
```

This encoding is sketched, not final — the exact shape of `HandlerType` is a Phase 2 detail, and it may be simplified (e.g. the field types might be derivable from the constructor's row in the sum, rather than stored explicitly in the handler type). The important point for the sketch is that `HandlerType` is the `EntryKind` of `HandlerRowT`, and it encodes enough information for the eliminator (1a hybrid) to dispatch to the right handler and for `SubSum` (1b hybrid) to check that handler rows are subsets.

#### 1d.1 — The `HandlerType` encoding question (refinement #2, explained)

The question is: **does a handler type need to carry the field types of its constructor explicitly, or can it derive them from the constructor's row in the sum?**

**The sketched encoding (explicit field types):**

```haskell
data HandlerType (n :: Symbol) (fs :: Row ProductRowT) (res :: Type) (m :: Type -> Type)
  = HandlerType

-- A handler row entry for "neg" (one Int field), returning Int in IO:
--   HandlerType "neg" '[ 'Int ] Int IO
```

Here each `HandlerType` carries the field types (`fs`) explicitly. The handler row alone tells you everything: which constructor, what fields, what result, what monad.

**The alternative (field types derived from the sum row):**

```haskell
data HandlerType (n :: Symbol) (res :: Type) (m :: Type -> Type)
  = HandlerType

-- A handler row entry for "neg", returning Int in IO:
--   HandlerType "neg" Int IO
```

Here the handler type does *not* carry the field types. The field types come from the sum row (the constructor's fieldrow). The eliminator needs both the handler row *and* the sum row: it dispatches to the handler for constructor `n`, looks up `n` in the sum row to get the field types, and passes the field values to the handler.

**The trade-off:**

- **Explicit (sketched):** the handler row is self-contained. A `SubSum` check between handler rows checks that each handler has the same field types. The eliminator needs only the handler row. The cost: field types are duplicated (in the sum row *and* in each handler type).
- **Derived (alternative):** the handler type is lighter (no `fs`). A `SubSum` check is between sum rows, not handler rows. The eliminator needs both the handler row and the sum row, and the pairing between them (constructor `n` in the handler row corresponds to constructor `n` in the sum row) must be known. The cost: the handler row is not self-contained.

**Why this matters:**

- For `SubSum` (1b): explicit → `SubSum` is a handlerrow check; derived → `SubSum` is a sum-row check.
- For the eliminator (1a): explicit → handler row alone suffices; derived → handler row + sum row needed.
- For the plugin: obligation 1 solves `HasField` against the sum row's fieldrow, not the handler row. So the handler type's field-type encoding doesn't directly affect obligation 1. But it affects whether the plugin needs to know that a handler type's `fs` matches the sum row's fieldrow for constructor `n`.

**The sketch assumes explicit field types** because it makes the handler row self-contained. The derivation alternative is simpler (lighter handler types) but requires pairing. Both are valid; the choice is a Phase 2 refinement. The key question: *do we want the handler row to stand alone, or paired with the sum row?*

### 1e. The result type encoding (sketch)

The result type encoding is what the 1a hybrid's coproduct is indexed by. A sketch:

```haskell
-- A result type: "result for constructor named n, of type res"
data ResultType (n :: Symbol) (res :: Type)
  = ResultType

-- Example: result for "neg", of type Int
--   ResultType "neg" Int

-- Example: result for "add", of type Bool
--   ResultType "add" Bool
```

The 1a hybrid's result is `m (SumOf (Results handler-row))`, where `Results handler-row` is a sum type with one constructor per handled constructor, each carrying the result type for that constructor. The `SumOf` is a *new* type — the coproduct of the result types. A sketch:

```haskell
-- The coproduct of result types for a handler row.
-- This is the 1a hybrid's result type (before the monad).
data Results (r :: HandlerRowT) where
  -- One constructor per entry in the handler row
  -- Results :: proxy r -> (EntryKind r) -> ... -> Results r
  -- (sketch — the exact constructors depend on the handler row's entries)

-- The 1a hybrid's eliminator result:
--   eliminate :: ... -> m (Results handlerRow)
```

This is sketched, not final — `Results` and `SumOf` are the 1a hybrid's result-coproduct machinery, and their exact shape is Phase 2 work. The important point is that the result type is *indexed by the handler row* (which constructors are handled, and what their result types are), and that it specialises to `m a` when all result types are the same (via a flatten map).

### 1f. The evidence classes (sketch)

The evidence classes work over the wrapper. The current `RowEq (r :: Row)` (product-row-only) needs to generalize or be joined by a sum-row class. Two sketches:

**Sketch A — generalize `RowEq`/`RowShow` to `RowType`**

```haskell
class RowFlavour r => RowEq (r :: RowType) where
  repEq :: RowRep f r a -> RowRep f r a -> Bool
  repEq = undefined   -- plugin emits literal index comparisons

class RowFlavour r => RowShow (r :: RowType) where
  repShowsPrec :: Int -> RowRep f r a -> ShowS
  repShowsPrec = undefined   -- plugin emits literal show bodies
```

This generalizes the current `RowEq (r :: Row)` to `RowEq (r :: RowType)`, so products, sums, handler rows, and result rows all use the same class. The `RowFlavour r` constraint gives the class the entry kind for the row.

**Sketch B — keep `RowEq`/`RowShow` for product rows, add a sum-row class**

```haskell
-- Product rows: current RowEq, generalised slightly
class RowEq (r :: ProductRowT) where
  repEq :: RowRep f r a -> RowRep f r a -> Bool

-- Sum rows: a new class
class RowEqSum (r :: SumRowT) where
  repEqSum :: RowRep f r a -> RowRep f r a -> Bool
```

This keeps the current `RowEq` for product rows and adds a separate class for sum rows. Handler rows and result rows would have their own classes (or be handled by a general `RowEq` over `RowType`).

**Comparison:** Sketch A is more uniform (one `RowEq` for all flavours), but it changes the current `RowEq (r :: Row)` to `RowEq (r :: RowType)`. Sketch B is less disruptive to the current classes (they stay product-row-only), but it adds a new class per non-product flavour. The plan's Phase 2 says "sketch the evidence-class signatures" — both sketches are options; the choice is a Phase 2 detail.

Decision (refinement #1): **Sketch B** — keep `RowEq`/`RowShow` for product rows (`RowEq (r :: ProductRowT)`), and add separate classes for sum rows (`RowEqSum (r :: SumRowT)`), handler rows (`RowEqHandler (r :: HandlerRowT)`), and result rows (`RowEqResult (r :: ResultRowT)`) as needed. Rationale: less disruptive to the current classes (the test suite's `RowEq R2` stays `RowEq (r :: ProductRowT)` with `R2 :: ProductRowT`), and it keeps the product-row evidence classes as they are while adding new classes only for the new flavours. The cost is more classes, but that's the Option D trade-off (concrete flavours, more instances).

### 1g. The call site (sketch)

```haskell
-- A two-constructor sum
type MySum :: SumRowT
type MySum = '[ "neg" :-> '[ 'Int ], "add" :-> '[ 'Int, 'Int ] ]

-- Build values (same as now, but wrapped)
negVal :: RowRep Identity SumRowT
negVal = RowRep (injectRep 0 [slot (7 :: Int)])

addVal :: RowRep Identity SumRowT
addVal = RowRep (injectRep 1 [slot (3 :: Int), slot (4 :: Int)])

-- repEq call site — row is in RowRep's type, no Proxy
same :: Bool
same = repEq negVal negVal   -- both are RowRep Identity SumRowT

diff :: Bool
diff = repEq negVal addVal   -- both are RowRep Identity SumRowT, different tags
```

The call site is the same as case 3 in the earlier sketching: the row is in `RowRep`'s type, no `Proxy` argument, and the inner `Rep` is erased.

## Piece 2 — Products interaction

The design note §2 says products are one-constructor sums. The wrapper should preserve that: a product is a `RowRep` with a `ProductRowT` flavour (or a `SumRowT` flavour with one constructor — the design note says the latter is the point, so `SumRowT` with one constructor is the natural choice).

### 2a. Product as a one-constructor sum (design note §2)

```haskell
-- A two-field product: a :: Int, b :: Bool
type R2Product :: ProductRowT
type R2Product = '[ "a" := 'Int, "b" := 'Bool ]

-- The product as a one-constructor sum (design note §2)
type R2AsSum :: SumRowT
type R2AsSum = '[ "theProduct" :-> R2Product ]

-- Build the product (tag is 0, one constructor)
prodVal :: RowRep Identity SumRowT
prodVal = RowRep (productRep [slot (7 :: Int), slot True])
  -- or equivalently:
  -- prodVal = RowRep (injectRep 0 [slot (7 :: Int), slot True])
```

The product is a `RowRep Identity SumRowT` with one constructor (tag 0). The wrapper's type says `SumRowT`, and the row says one constructor carrying a `ProductRowT`. This is the design note §2 point: a product is the degenerate sum, its tag is always 0 and folds away.

### 2b. The alternative — product as a `ProductRowT` directly

```haskell
-- Alternative: product as a ProductRowT directly (not via SumRowT)
type R2Product :: ProductRowT
type R2Product = '[ "a" := 'Int, "b" := 'Bool ]

prodVal :: RowRep Identity ProductRowT
prodVal = RowRep (productRep [slot (7 :: Int), slot True])
```

This is the other option: the product is a `RowRep Identity ProductRowT`, not a `SumRowT`. The design note §2 says the point is that products and sums share one `Rep` — which they do in all three options (the inner `Rep` is the same). The question is whether the *wrapper* treats products as `ProductRowT` or as one-constructor `SumRowT`.

**Comparison:** The `SumRowT` option (2a) is the design note §2 point — products are one-constructor sums, so they use `SumRowT`. The `ProductRowT` option (2b) treats products as a separate flavour. The `SumRowT` option is more uniform (one flavour for all sums, including products-as-one-constructor-sums), but it means a product's wrapper type is `RowRep f SumRowT a`, which says "sum" even though it's a product. The `ProductRowT` option is more precise (the wrapper type says "product"), but it means products and sums are different flavours in the wrapper, even though they share the same inner `Rep`.

**The design note §2 point:** "A product is the degenerate sum, its tag is always 0 and folds away." This points to the `SumRowT` option — the product is a sum with one constructor, and the tag being 0 is what makes it fold away. So the `SumRowT` option is the design-note-consistent choice. The sketch assumes this.

### 2c. Implications for `RowFlavour`

If products are `SumRowT` (one-constructor sums), then `ProductRowT` is only used for the *field row* of a constructor (the nested row in a `SumRowT`). So:

- `ProductRowT` is the flavour of a *field row* (field name → field type).
- `SumRowT` is the flavour of a *constructor row* (constructor name → field-row), including products-as-one-constructor-sums.
- `HandlerRowT` is the flavour of a *handler row* (constructor name → handler type).
- `ResultRowT` is the flavour of a *result row* (constructor name → result type).

This means the four flavours are: field rows, constructor rows (including products), handler rows, result rows. The `RowFlavour` class has instances for all four, and the `EntryKind` of each is:

```haskell
type instance EntryKind ProductRowT = Type          -- a field type
type instance EntryKind SumRowT    = Row ProductRowT  -- a field-row
type instance EntryKind HandlerRowT = HandlerType     -- a handler type
type instance EntryKind ResultRowT = ResultType       -- a result type
```

## Piece 3 — The plugin obligation-4 surface

Obligation 4 (design note §6): "index `Rep` by its row, retiring §5's `Proxy` debt."
In Case 3, `Rep` stays erased, and the *wrapper* (`RowRep`) carries the row. So
obligation 4 is satisfied by the wrapper: the plugin solves constraints from
`RowRep f r a`'s type, and the `Proxy r` argument disappears from the evidence
classes.

### 3a. The current state (before obligation 4)

```haskell
-- Current: RowEq takes a Proxy r
class RowEq (r :: Row) where
  repEq :: Proxy r -> Rep f a -> Rep f a -> Bool

-- Current call site: repEq (Proxy :: Proxy R2) r1 r2
```

The `Proxy r` is the debt. The row is not in `Rep`'s type, so the constraint
`RowEq r` cannot be solved from the arguments alone — the `Proxy` is passed
explicitly.

### 3b. After obligation 4 (Case 3 wrapper)

```haskell
-- After: RowEq is over RowType, takes no Proxy
class RowFlavour r => RowEq (r :: RowType) where
  repEq :: RowRep f r a -> RowRep f r a -> Bool

-- After call site: repEq r1 r2  (both are RowRep f r a, row in the type)
```

The row is in `RowRep`'s type, so `RowEq r` can be solved from the arguments
(the `RowRep f r a` values carry `r` in their types). No `Proxy` needed.

### 3c. The plugin's view (obligation 4)

The plugin solves the constraints that the evidence classes generate. In Case 3,
the constraints are:

```haskell
-- When the user writes repEq r1 r2, GHC generates:
--   RowEq r
--   RowFlavour r
--   (and the types of r1, r2 are RowRep f r a, which carry r)
```

The plugin sees `RowEq r` with `r :: RowType`, and `RowFlavour r`. The plugin's
job (obligation 4) is to *solve* `RowEq r` — i.e., to prove that the row `r` has
an equality evidence, which means emitting the literal index comparisons that
`repEq` does.

But wait — obligation 4 is about *retiring the Proxy debt*, which is about the
*constraint solving* (the plugin makes `RowEq r` solvable from the type), not about
*emitting the bodies* (that's obligation 3). So obligation 4's surface is:

```haskell
-- The plugin makes RowEq r solvable for any r :: RowType (that has a RowFlavour
-- instance). The plugin does this by providing the RowEq instance for each
-- RowType that has a RowFlavour instance.
--
-- Concretely: the plugin emits
--   instance RowFlavour SumRowT => RowEq SumRowT where
--     repEq (RowRep r1) (RowRep r2) = ... (literal comparisons) ...
--   instance RowFlavour ProductRowT => RowEq ProductRowT where
--     repEq (RowRep r1) (RowRep r2) = ... (literal comparisons) ...
--   -- etc. for HandlerRowT, ResultRowT, and any future flavours
```

So obligation 4's surface is: the plugin *provides the `RowEq` (and `RowShow`) instances* for each `RowType` flavour, using the `RowFlavour` instance to know the entry kind. The instances are the evidence that the row is comparable/showable, and they are emitted as literals (obligation 3). Obligation 4 is the *fact* that the instances exist and are solvable from the type; obligation 3 is the *content* of the instances (literal comparisons).

### 3d. The plugin's view (obligations 1 and 2)

Obligations 1 and 2 (field name → slot index, constructor name → tag) are about
resolving symbols to indices. In Case 3, these are solved against the wrapper's
row:

```haskell
-- Obligation 1: given a field name n and a row r (ProductRowT), find the slot index
--   HasField n r a  →  the plugin emits the index as a literal
--   The row r is the ProductRowT in the RowRep's type (or in the SumRowT's
--   nested field-rows)
--
-- Obligation 2: given a constructor name n and a row r (SumRowT), find the tag
--   HasConstructor n r  →  the plugin emits the tag as a literal
--   The row r is the SumRowT in the RowRep's type
```

The plugin sees `HasField n r a` with `r :: ProductRowT` (or `r` is the field-row
of a `SumRowT`), and `HasConstructor n r` with `r :: SumRowT`. The plugin resolves
the symbol in the row and emits a literal index/tag.

### 3e. The plugin's surface summary (Case 3)

The plugin's surface, in Case 3, is:

```haskell
-- The plugin solves these constraint shapes:
--   HasField n (r :: ProductRowT) a        -- obligation 1 (field → index)
--   HasConstructor n (r :: SumRowT)        -- obligation 2 (constructor → tag)
--   RowEq (r :: RowType)                    -- obligation 3+4 (literal bodies, no Proxy)
--   RowShow (r :: RowType)                  -- obligation 3+4 (literal show bodies, no Proxy)
--
-- For each, the plugin uses RowFlavour r to know the entry kind, and emits
-- literal indices/bodies. The RowRep wrapper carries the row in its type, so
-- the constraints are solvable from the value's type (no Proxy).
```

The plugin is *not* kind-polymorphic (Option D, concrete flavours). It sees concrete
`ProductRowT`, `SumRowT`, `RowType` constraints, and uses `RowFlavour` instances to
know the entry kind. If a new flavour is added later (e.g. a new `RowType`
constructor), the project adds a `RowFlavour` instance, and the plugin may or may
not need to change (it needs to change if the new flavour generates new constraint
shapes the plugin has to solve).

### 3f. What obligation 4 does *not* mean in Case 3

Obligation 4 says "index `Rep` by its row." In Case 3, `Rep` is *not* indexed by
its row — `Rep` stays erased. The *wrapper* (`RowRep`) is indexed by the row. So
obligation 4 is satisfied by the wrapper, not by changing `Rep`. The design note §6
says obligation 4 is "index `Rep` by its row, retiring §5's `Proxy` debt" — but
in Case 3, this is interpreted as "the row is in the type that the evidence classes
work over" (the `RowRep` wrapper), not as "change `Rep` to carry the row." The
effect is the same (the `Proxy` debt is gone), but the mechanism is the wrapper,
not a row-indexed `Rep`.

This is the Case 3 decision: `Rep` stays erased, the wrapper carries the row, and
obligation 4 is satisfied via the wrapper. The design note's wording ("index `Rep`
by its row") is slightly imprecise for Case 3 — it should be read as "index the
*type the evidence works over* by its row," which in Case 3 is `RowRep`, not `Rep`.

## Open details after this sketch

The sketch leaves these details open (they are Phase 2 refinement, not Phase 1
decisions):

1. **The exact `HandlerType` encoding.** **DECIDED — explicit field types (`HandlerType n fs res m`).**
   Handler rows are self-contained: each entry carries its constructor name, field
   types, result type, and monad. This makes handler rows first-class, portable
   objects that can be passed around and stored without needing a paired sum row.
   The field-type duplication (in the sum row and in each handler entry) is a feature,
   not a cost — it makes the handler row stand alone. The `SubSum` check is on
   handler rows (field-type compatibility per entry). The eliminator needs only the
   handler row (the value's sum row is known from the value's type). **Closed.**

2. **The exact `Results` / `SumOf` shape.** **DECIDED — GADT with one constructor per
   handlerrow entry, constructors named after the handler's constructor names.**
   `Results r` is a GADT indexed by the handler row `r :: HandlerRowT`, with one
   constructor per entry in `r`. Each constructor is named after the handler's
   constructor name (e.g. `"neg"` → `NegResult`, `"add"` → `AddResult`) and carries
   the result type for that handler. The result is `m (Results handlerrow)`, which
   specialises to `m a` via a flatten map when all result types are `a`. The GADT's
   readability (named, per-constructor) wins over the type-family approach (nested
   `Either`, less readable). **Closed.**

3. **Whether `RowEq`/`RowShow` generalize to `RowType` (Sketch A) or stay
   product-row-only with a sum-row class (Sketch B).** **Decided: Sketch B.** The
   current `RowEq (r :: Row)` class stays as `RowEq (r :: ProductRowT)` (product
   rows only), and sum/handler/result rows get their own classes. Closed.

4. **Whether `DictAny` survives (§7 Q4).** **Partially resolved — `f Any` stays;
   `DictAny` survives as a forward-looking mechanism for packing field-class
   dictionaries.** The array needs *some* erased element type (`f Any`), which is
   the `large-anon`-style erasure bargain and is separate from `DictAny`. `DictAny`
   is the type-erased dictionary pack (for packing field-class dictionaries like
   `Eq x` into one dictionary). It is *not* used by the current `RowEq`/`RowShow`
   classes (which have `undefined` defaults and don't mention `DictAny`), but it is
   present in `Core.hs` as a forward-looking mechanism. The plugin emits literal
   indices and comparison bodies (obligations 1/2/3), not dictionary replacements —
   the field-class dictionaries are still needed for the comparisons the plugin
   emits, and `DictAny` packs them. So `DictAny` survives as a mechanism for
   dictionary packing, with a possibly narrower role than the sketch assumed. **Closed
   with nuance** — `f Any` stays (separate concern), `DictAny` stays as a forward-
   looking dictionary-packing mechanism, but its necessity depends on whether the
   evidence classes carry field-class dictionaries (which the current classes don't),
   so it may not be needed immediately.

5. **The role of `a` in `RowRep f r a`.** **DECIDED — `a` is the value type, independent
   of the row `r`.** In Case 3, `Rep` stays erased (`Rep f a` doesn't know the row),
   and the wrapper `RowRep f r a` links the value type `a` to the row `r`. The two
   are independent in `Rep`, linked by the wrapper. This is the Case 3 trade-off:
   `Rep` stays erased (and `a` is the value type, independent of `r`), the wrapper
   carries the row (and `r` is the row, independent of `a`). The alternative (Case 1)
   would make `a` depend on `r` (row-indexed `Rep`), which we rejected. So `a` is
   the value type, `r` is the row, and the wrapper links them. The relationship
   between `a` and `r` is enforced by the wrapper's type, not by `Rep` (which is
   erased). **Closed.**
