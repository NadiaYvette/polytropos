<!--
SPDX-License-Identifier: BSD-3-Clause
-->
# Design Note — Field Update Efficiency, Array Mutation & Transient Builders

Date: 2026-10-07  
Status: DRAFT v0.1 · 2026-10-07 — Architecture and roadmap for efficient record updates  
Related: `POLYTROPOS_DESIGN.md` (decisions D4, D5, §2 runtime costs),
`DESIGN_REVIEW_CLAUDE-OPUS-4.6.md` (§1 technical debt review),
`PHASE2_SKETCH.md` (Option D vocabulary), `DOC_STRATEGY.md` (governance).  
Audience: Maintainer and contributors implementing runtime primitives and Typechecker Plugin update desugaring.

---

## 0. Context & Motivation

In §1 of [`DESIGN_REVIEW_CLAUDE-OPUS-4.6.md`](DESIGN_REVIEW_CLAUDE-OPUS-4.6.md), field mutation was identified as an operational technical debt in the prototype implementation. Specifically, [`setFieldAt`](../../packages/polytropos-core/src/Polytropos/Core.hs) in `polytropos-core` uses a naive linked-list detour:

```haskell
-- Prototype O(n) implementation:
setFieldAt :: forall f a. Int -> f Any -> Rep f a -> Rep f a
setFieldAt i x (Rep t v) = Rep t (smallArrayFromList (go 0 (toListSlots v)))
  where
    go j ys
      | j == i    = case ys of _ : ys' -> x : ys' ; [] -> [x]
      | otherwise = case ys of y : ys' -> y : go (succ j) ys' ; [] -> []
```

### The Cost of the Prototype
1. **Multiple Full Passes:** `toListSlots` converts the `SmallArray` into a lazy linked list ($N$ cons cells); `go` traverses up to index $i$ allocating updated cons cells; `smallArrayFromList` traverses the list again to measure length, allocates a mutable array, and copies elements.
2. **Severe Heap Garbage:** Allocates $\approx 3N$ words of nursery garbage for a single field update.
3. **Cache Eviction:** Churns pointer chains through the CPU memory hierarchy rather than leveraging contiguous memory caches.

Because `polytropos` is early in its implementation lifecycle, establishing a principled, efficient update architecture now prevents structural lock-in.

---

## 1. The Multi-Tier Efficiency Spectrum

We establish a four-level hierarchy of optimizations balancing read latency, mutation throughput, and API ergonomics.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       FIELD UPDATE OPTIMIZATION TIERS                       │
├─────────────────────────────────────────────────────────────────────────────┤
│ Level 1: Hardware-Vectorized CoW   thawSmallArray# + writeSmallArray#       │
│          (Single allocation, CPU memcpy, O(1) freeze)                       │
├─────────────────────────────────────────────────────────────────────────────┤
│ Level 2: Batched Record Updates    setFieldsAt :: [(Int, f Any)] -> Rep -> Rep│
│          (Clones once, applies K field updates in-place, freezes once)      │
├─────────────────────────────────────────────────────────────────────────────┤
│ Level 3: Ephemeral Transient MRep  modifyRep :: Rep -> (MRep s -> ST s ())  │
│          (Zero intermediate allocations across complex update pipelines)    │
├─────────────────────────────────────────────────────────────────────────────┤
│ Level 4: Two-Tier Diff Log         NoPending Canonical | HasPending Diff    │
│          (Amortized O(1) functional updates via pending IntMap)             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Level 1: Hardware-Vectorized Copy-on-Write (The Primitive PrimOp Fix)

The foundational primitive replaces list conversions with GHC's native `SmallArray#` cloning primitives from `Data.Primitive.SmallArray`:

```haskell
setFieldAt :: forall f a. Int -> f Any -> Rep f a -> Rep f a
setFieldAt i !x (Rep t v) = Rep t $ runSmallArray $ do
  m <- thawSmallArray v 0 n
  writeSmallArray m i x
  pure m
  where
    !n = sizeofSmallArray v
```

### Architectural Properties
- **Zero intermediate linked lists:** Eliminates $100\%$ of cons-cell allocations.
- **Single contiguous allocation:** Allocates exactly one `SmallMutableArray#` of $N$ pointer slots.
- **C-level `memcpy`:** In GHC's runtime system, `thawSmallArray#` maps to an unrolled CPU memory copy (`memcpy`) of word-sized pointers directly in the CPU L1/L2 cache.
- **$O(1)$ zero-cost freeze:** `runSmallArray` freezes the array via `unsafeFreezeSmallArray#`, an erased identity cast at the machine level.
- **Asymptotic complexity:** $O(N)$ in record size, but with a tiny nanosecond-range constant factor.

---

## 3. Level 2: Batched Record Updates (`setFieldsAt`)

Idiomatic record updates frequently modify multiple fields simultaneously (e.g. `r { x = 1, y = 2, z = 3 }`). Chaining single-field updates causes $K \times O(N)$ allocations and memory copies.

### The Batched Primitive
```haskell
-- | Clone once, apply K updates in-place, freeze once.
setFieldsAt :: [(Int, f Any)] -> Rep f a -> Rep f a
setFieldsAt [] r = r
setFieldsAt updates (Rep t v) = Rep t $ runSmallArray $ do
  m <- thawSmallArray v 0 (sizeofSmallArray v)
  forM_ updates $ \(i, !x) -> writeSmallArray m i x
  pure m
```

### Typechecker Plugin Integration
When desugaring GHC `OverloadedRecordUpdate` syntax or lens compositions, the `TcPlugin` resolves the target field labels to statically sorted literal integer indices `[i₁, i₂, ..., iₖ]` and emits a **single** call to `setFieldsAt`. The cost drops from $K \times O(N)$ to $1 \times O(N)$ regardless of how many fields are modified.

---

## 4. Level 3: Ephemeral Transient Builders (`MRep` in `ST`)

For bulk updates, JSON decoding, or streaming deserialization, functional immutable updates incur repeated allocations. Borrowing Clojure's transients pattern and Haskell `Vector.modify`, `polytropos` defines an ephemeral mutable representation:

```haskell
-- | Ephemeral mutable representation
data MRep s (f :: Type -> Type) a = MRep
  {-# UNPACK #-} !Word
  !(SmallMutableArray s (f Any))

-- | Safely thaw an immutable Rep into a mutable builder
thawRep :: Rep f a -> ST s (MRep s f a)
thawRep (Rep t v) = do
  m <- thawSmallArray v 0 (sizeofSmallArray v)
  pure (MRep t m)

-- | Safely freeze an ephemeral builder
freezeRep :: MRep s f a -> ST s (Rep f a)
freezeRep (MRep t m) = do
  v <- unsafeFreezeSmallArray m
  pure (Rep t v)

-- | In-place slot write (O(1), zero allocation)
writeFieldAt :: MRep s f a -> Int -> f Any -> ST s ()
writeFieldAt (MRep _ m) i !x = writeSmallArray m i x

-- | Scoped pure modification wrapper
modifyRep :: Rep f a -> (forall s. MRep s f a -> ST s ()) -> Rep f a
modifyRep (Rep t v) act = Rep t $ runSmallArray $ do
  m <- thawSmallArray v 0 (sizeofSmallArray v)
  act (MRep t m)
  pure m
```

---

## 5. Level 4: The Two-Tier Diff Log (`large-anon` Pattern)

Where repeated incremental updates occur over an extended lifecycle without intervening batch opportunities, `polytropos` can optionally adopt Edsko de Vries' two-tier representation from `large-anon`:

```haskell
data Record f (r :: Row) =
    NoPending  {-# UNPACK #-} !(Canonical f)
  | HasPending {-# UNPACK #-} !(Canonical f) !(Diff f)

newtype Canonical f = Canonical (SmallArray (f Any))

data Diff f = Diff {
    diffUpd :: !(IntMap (f Any))  -- ^ Pending updates indexed by canonical slot
  }
```

### Tradeoff Assessment
- **Advantage:** Updating a field is $O(1)$ amortized; it merely inserts into `diffUpd` without cloning the underlying `SmallArray`.
- **Disadvantage:** Reading a field (`fieldAt`) is no longer an unconditional $O(1)$ raw array index; it must first perform an `IntMap` lookup.
- **Recommendation:** Keep `Rep` as the bare flat array (`Rep Word (SmallArray (f Any))`) for Phase 3 to preserve maximum $O(1)$ read performance. The two-tier `Diff` wrapper can be provided as an opt-in surface if profiling demands it.

---

## 6. Sum Row Invariants on Field Updates

In `polytropos`, `Rep` serves both products and sums (Decision **D4**). Updating a field in a sum value requires strict tag verification:

1. **Product Invariance:** In a product row (`RowRep ProductRowT r a`), tag `0` and field offsets are guaranteed by the row type. `setFieldAt` is total.
2. **Sum Invariance:** In a sum row (`RowRep SumRowT r a`), fields belong to a specific constructor `C`. If the runtime value holds constructor $C' \neq C$, the field does not exist in the selected payload array.
3. **Partial Sum Update Primitive:**
   ```haskell
   setFieldSumAt
     :: Word    -- ^ Expected constructor tag
     -> Int     -- ^ Field offset within that constructor's product row
     -> f Any   -- ^ New field payload
     -> Rep f a
     -> Maybe (Rep f a)
   setFieldSumAt expectedTag idx !val (Rep t v)
     | t == expectedTag = Just (setFieldAt idx val (Rep t v))
     | otherwise        = Nothing
   ```

---

## 7. Concrete Implementation Roadmap

1. **Immediate (Phase 3 Core):** Update `setFieldAt` in `Polytropos.Core` to use `thawSmallArray` + `writeSmallArray` + `runSmallArray`. Add test assertions.
2. **Phase 3 Core Extension:** Implement `setFieldsAt`, `MRep`, and `modifyRep` in `Polytropos.Core`.
3. **Phase 3 Plugin Synthesis:** Emit calls to `setFieldsAt` for multi-field updates.
4. **Phase 4 Syntax Integration:** Desugar `OverloadedRecordUpdate` and record dot syntax.
