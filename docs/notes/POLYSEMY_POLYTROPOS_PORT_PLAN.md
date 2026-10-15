<!--
SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
-->
# Implementation Plan — Porting `polysemy` to `polytropos`

Date: 2026-10-10  
Status: DRAFT v0.1 · 2026-10-10 — Blueprint for forking and refactoring `~/src/polysemy/` to use `polytropos`  
Related: `EFFECT_SYSTEMS_PORTING_MASTER_PLAN.md` (master plan), `POLYTROPOS_DESIGN.md` (decisions D1–D10, open sums), `ROW_ROLE_DEFNS_DRAFT.ott`  
Audience: Maintainers and developers implementing the `polysemy-polytropos` fork.

---

## 0. Overview & Context

`polysemy` is a higher-order freer-monad effect library based on extensible unions (`Union (r :: EffectRow) m a`).
While `polysemy` offers exceptional expressiveness for higher-order effects (e.g. `Error`, `Reader`, `Resource` with scoped interpreters via `Weaving`), it has historically suffered from:
1. **Severe Runtime Allocation Overhead:** Every interpretation step runs `decomp`, which pattern matches on membership proofs and re-allocates a new `Union` wrapper with decremented tags for unhandled effects.
2. **Unary / Peano Proof Remnants:** Although `ElemOf` was internally coerced to an `Int`, the API and handler decomposition still operate under a linked-list mental model (`Here` vs `There`).
3. **Catastrophic Compile-Time Expansion:** Resolving `Member e r` across polymorphic rows triggers exponential backtracking in GHC's constraint solver, necessitating `polysemy-plugin` to prune the search graph.

This plan details the fork of `~/src/polysemy/` into `polysemy-polytropos`. By replacing `Union` with `polytropos` open sum variants (`Variant` / `RowRep SumRowT`) and `Polytropos.Plugin` constructor solving, `polysemy` achieves true $O(1)$ decomposition, zero-copy weakening, and eliminates `polysemy-plugin`.

---

## 1. Upstream Architecture & Bottleneck Analysis

### 1.1 The `Union` and `Weaving` Mechanics

In `~/src/polysemy/src/Polysemy/Internal/Union.hs`:

```haskell
data Union (r :: EffectRow) (mWoven :: Type -> Type) a where
  Union
      :: ElemOf e r
      -> Weaving e m a
      -> Union r m a

data Weaving e mAfter resultType where
  Weaving
    :: forall f e rInitial a resultType mAfter. (Functor f)
    => { weaveEffect   :: e (Sem rInitial) a
       , weaveState    :: f ()
       , weaveDistrib  :: forall x. f (Sem rInitial x) -> mAfter (f x)
       , weaveResult   :: f a -> resultType
       }
    -> Weaving e mAfter resultType
```

And decomposition:

```haskell
decomp :: Union (e ': r) m a -> Either (Union r m a) (Weaving e m a)
decomp (Union p a) =
  case p of
    Here     -> Right a
    There pr -> Left $ Union pr a
```

**Bottlenecks:**
- Every `Left` branch in `decomp` allocates a fresh `Union` data constructor on the heap. In an effect stack with 8 effects, an action handled by the bottom effect allocates 7 intermediate `Union` wrappers before reaching its interpreter.
- `weaken` allocates a new `Union` wrapper with an incremented proof index.
- `subsume` requires traversing and re-indexing the effect stack proof.

### 1.2 Constraint Explosion & `polysemy-plugin`

In `~/src/polysemy/src/Polysemy/Internal/Union.hs`:

```haskell
class Member (t :: Effect) (r :: EffectRow) where
  membership' :: ElemOf t r

instance {-# OVERLAPPING #-} Member t (t ': z) where
  membership' = Here

instance Member t z => Member t (_1 ': z) where
  membership' = There $ membership' @t @z
```

When an effect stack is open (`r = e1 ': e2 ': rest`), GHC cannot commit to either instance, leading to ambiguity errors. `polysemy-plugin` works around this by inspecting local given constraints, but this adds compiler overhead and compiler-version fragility.

---

## 2. Target `polytropos` Architecture

### 2.1 `Union` as a True Open Variant

In `polytropos`, an extensible variant (`Variant s`) is defined over `Rep`:
$$\text{Rep} = \text{Rep} \{ \text{tag} :: !\text{Word}, \text{payload} :: !\text{SmallArray Any} \}$$

We re-implement `Union` as a specialized higher-kinded variant wrapping `Weaving`:

```haskell
newtype Union (r :: RowOf Effect) (m :: Type -> Type) a = Union
  { unUnion :: RowRep (Weaving m a) 'SumRowT r ()
  }
```

The underlying runtime value is simply:
- An unboxed `Word` tag (0 for the first effect, 1 for the second, etc.).
- A single-element `SmallArray` holding the `Weaving e m a` payload.

### 2.2 Truly $O(1)$ Decomposition Without Re-Allocation

Under `polytropos`, peeling an effect off the head of the row (`decomp`) is an immediate machine-word comparison:

```haskell
decomp
  :: forall e r m a.
     Union (e ': r) m a
  -> Either (Union r m a) (Weaving e m a)
decomp (Union (RowRep (Rep tag arr)))
  | tag == 0 =
      Right (unsafeCoerce (indexSmallArray arr 0))
  | otherwise =
      -- O(1) tag decrement; the SmallArray payload pointer is reused as-is!
      Left (Union (RowRep (Rep (tag - 1) arr)))
```

**Key Advantages:**
1. **Zero Payload Re-allocation:** The `SmallArray` payload is preserved identically. Only a single flat wrapper with a decremented unboxed integer is returned.
2. **Zero Branching Depth:** No recursive Peano pattern matches (`There (There ...)`). A single comparison against 0 handles head decomposition.

### 2.3 Eliminating `polysemy-plugin` via `ConstructorIndex`

Instead of `Member` searching type lists, `polytropos`' `ConstructorIndex` is solved by `Polytropos.Plugin`:
```haskell
type Member (e :: Effect) (r :: RowOf Effect) = ConstructorIndex e r (Weaving Any Any)
```
- When `e` is in `r`, `Polytropos.Plugin` emits a literal unboxed `Word#` tag into Core.
- Resolves open rows and polymorphic tails instantly without search explosions.
- `polysemy-plugin` is made completely redundant and discarded.

### 2.4 Arbitrary Re-stacking via `SubSum`

Operations like `raise`, `subsume`, and `inject` map directly to `SubSum`:
```haskell
subsume :: SubSum sub super => Sem sub a -> Sem super a
```
- `SubSum sub super` provides compile-time injection indices (`subSumInjectIndices :: [Word]`).
- Tag remapping is an $O(1)$ table lookup or direct arithmetic offset, with zero traversal overhead.

---

## 3. Phased Execution Roadmap

### Phase 1: Workspace & Cabal Configuration
1. Branch off `~/src/polysemy/` as branch `polytropos-port`.
2. Update `cabal.project` in `~/src/polysemy/`:
   ```cabal
   packages:
     .

   source-repository-package
     type: git
     location: https://github.com/NadiaYvette/polytropos.git
     tag: b24592f41cf5bc243df020db35af0b9e3c39487f
     subdir:
       packages/polytropos-core
       packages/polytropos-plugin
   ```
3. In `polysemy.cabal`:
   - Add `build-depends: polytropos-core, polytropos-plugin`.
   - Remove `polysemy-plugin` from dependencies and test suites.
   - Add default GHC option: `-fplugin=Polytropos.Plugin`.

### Phase 2: Refactoring `Polysemy.Internal.Union`
1. Re-implement `Union` over `RowRep 'SumRowT`:
   ```haskell
   newtype Union (r :: RowOf Effect) (m :: Type -> Type) a = Union
     { unUnion :: RowRep (Weaving m a) 'SumRowT r ()
     }
   ```
2. Replace `ElemOf` GADT and pattern synonyms with `Word` tags.
3. Replace `Member` with `ConstructorIndex`:
   ```haskell
   injWeaving
     :: forall e r m a. Member e r
     => Weaving e m a
     -> Union r m a
   injWeaving w =
     let tag = constructorIndex @_ @e @r
         arr = smallArrayFromList [unsafeCoerce w]
     in Union (RowRep (Rep tag arr))
   ```
4. Implement $O(1)$ `decomp`, `extract`, and `absurdU`:
   ```haskell
   extract :: Union '[e] m a -> Weaving e m a
   extract (Union (RowRep (Rep _ arr))) = unsafeCoerce (indexSmallArray arr 0)
   ```

### Phase 3: Modernizing `Polysemy.Internal` (`Sem`)
1. Update `Sem` definition to use the new `Union`.
2. Re-implement `raise`, `raiseUnder`, and `subsume` using `widenVariant` and `SubSum`.
3. Simplify interpreter runners (`run`, `runM`, `runFinal`).

### Phase 4: Deprecation of `polysemy-plugin`
1. Retain `polysemy-plugin` as a backward-compatibility stub that re-exports `Polytropos.Plugin`.
2. Remove all custom Core plugin passes (`Polysemy.Plugin.Fundep`, etc.).

---

## 4. Verification Gates & Benchmark Metrics

### Gate 1: Test Suite Parity
- `cabal test polysemy:test:polysemy-test` must pass all tests:
  - Higher-order effect scoping (`Error`, `Reader`, `State`, `Resource`).
  - Interleaving interpreters (`runStateInIO`, `errorToIOFinal`).
  - Non-deterministic execution (`NonDet`).

### Gate 2: Benchmark Comparison
- Benchmark against vanilla `polysemy`:
  - **Effect Interpretation Throughput:** Expect 30–50% reduction in execution time and GC allocation due to zero-allocation `decomp` and flat variant tags.
  - **Compile-Time Speedup:** Compilation of 10+ effect modules should see a 3x to 5x reduction in GHC memory consumption and time due to literal Core plugin synthesis.
