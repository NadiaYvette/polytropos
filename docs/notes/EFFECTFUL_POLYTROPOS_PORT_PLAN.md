<!--
SPDX-License-Identifier: BSD-3-Clause
-->
# Implementation Plan — Porting `effectful` to `polytropos`

Date: 2026-10-10  
Status: DRAFT v0.1 · 2026-10-10 — Blueprint for forking and refactoring `~/src/effectful/` to use `polytropos`  
Related: `EFFECT_SYSTEMS_PORTING_MASTER_PLAN.md` (master plan), `POLYTROPOS_DESIGN.md` (decisions D1–D10), `ROW_ROLE_DEFNS_DRAFT.ott`  
Audience: Maintainers and developers implementing the `effectful-polytropos` fork.

---

## 0. Overview & Context

`effectful` is an ultra-fast, monadic effect system based on in-place state mutation within a thread-local environment record (`Env (es :: [Effect])`).
While `effectful` achieves high performance compared to traditional free monads, its internal architecture relies on:
1. An indirect two-level memory lookup: an unboxed `PrimArray Ref` table pointing to a mutable `Storage` containing `SmallMutableArray` payload cells.
2. An overlapping typeclass hierarchy for `e :> es` membership, which experiences compile-time degradation on large stacks and requires a bespoke compiler plugin (`effectful-plugin`) to resolve ambiguous candidates.
3. Secondary wrapper types for labeled effects (`Effectful.Labeled.Labeled (label :: Symbol) e`), creating ergonomic frictions when combining multiple instances of the same effect type.

This plan details the fork of `~/src/effectful/` into `effectful-polytropos`, replacing the legacy list-based `Env` and `effectful-plugin` with `polytropos` open product rows, `Polytropos.Plugin` literal index synthesis, and first-class symbol-labeled rows.

---

## 1. Upstream Architecture & Bottleneck Analysis

### 1.1 The Two-Level Indirect `Env`

In `~/src/effectful/effectful-core/src/Effectful/Internal/Env.hs`:

```haskell
data Env (es :: [Effect]) = Env
  { offset  :: !Int
  , refs    :: !(PrimArray Ref)
  , storage :: !(S.IORef Storage)
  }

data Ref = Ref !Int !Version

data StorageData = StorageData
  { size      :: !Int
  , versions  :: !(MutablePrimArray RealWorld Version)
  , effects   :: !(SmallMutableArray RealWorld AnyEffect)
  , relinkers :: !(SmallMutableArray RealWorld AnyRelinker)
  }
```

When an effect action retrieves its state representation via `getLocation`:
1. It looks up `reifyIndex @e @es` in the typeclass dictionary.
2. It indexes `refs` at `(offset + reifyIndex)` to extract `Ref ref version`.
3. It dereferences `storage` via `IORef`.
4. It checks `version == storageVersion` in `versions`.
5. It indexes `effects` at `ref` to obtain the actual `EffectRep`.

**Bottlenecks:**
- **Double indirection on every effect lookup:** `refs` index -> `storage` read -> `effects` index.
- **Cache line misses:** `refs` and `effects` are separate allocations in memory.
- **Allocation on stack modification:** `consEnv` and `subsumeEnv` allocate new `PrimArray Ref` slices.

### 1.2 Constraint Solving & The Need for `effectful-plugin`

In `~/src/effectful/effectful-core/src/Effectful/Internal/Effect.hs`:

```haskell
class (e :: Effect) :> (es :: [Effect]) where
  reifyIndex :: Int

instance {-# OVERLAPPING #-} e :> (e : es) where
  reifyIndex = 0

instance e :> es => e :> (x : es) where
  reifyIndex = 1 + reifyIndex @e @es
```

When `es` has an open polymorphic tail `(e1 : e2 : es)`, GHC cannot decide between the overlapping base instance and the inductive instance, causing compiler stalls or spurious ambiguity errors unless `effectful-plugin` intercepts the constraint solver.

---

## 2. Target `polytropos` Architecture

### 2.1 Direct Open Row Representation

Under `polytropos`, an effect stack `es` is an open product row of effects:

```haskell
type EffectRow = RowOf Effect
-- Example: '[ "state" ':= State Int, "reader" ':= Reader Config, "logger" ':= Logger ]
```

The environment `Env` is restructured to hold a flat `SmallMutableArray` directly, or wrap `RowRep`:

```haskell
data Env (es :: EffectRow) = Env
  { envOffset  :: !Int
  , envStorage :: !(S.IORef (Storage es))
  }

data Storage (es :: EffectRow) = Storage
  { storageVersion :: !Version
  , storageEffects :: !(SmallMutableArray RealWorld Any)
  }
```

### 2.2 Eliminating Level-1 Indirection via `FieldIndex`

Because `Polytropos.Plugin` solves field offsets at compile time:
- `FieldIndex name es eff` emits a literal unboxed `Int#` directly into Core AST.
- Accessing an effect's state does not query a runtime `refs` array:
  $$\text{slotIndex} = \text{envOffset} + \text{fieldIndex} @\text{name} @\text{es}$$
- Reading the effect representation is reduced to a single primitive read:
  `readSmallArray# (storageEffects storage) slotIndex# s`

### 2.3 Native Labeled Effects & OverloadedRecordDot

In `effectful`, distinguishing two `State` effects requires the `Labeled` wrapper:
```haskell
-- Legacy effectful:
foo :: ( Labeled "user" (State User) :> es
       , Labeled "order" (State Order) :> es
       ) => Eff es ()
foo = do
  u <- runLabeled @"user" get
  ...
```

Under `polytropos`, labeled rows are native first-class citizens:
```haskell
-- Polytropos effectful:
foo :: ( FieldIndex "user" es (State User)
       , FieldIndex "order" es (State Order)
       ) => Eff es ()
foo = do
  u <- getState @"user"
  ...
```
Furthermore, `OverloadedRecordDot` (`env.user`, `env.order`) allows inspectable pure environment slices.

### 2.4 Subsumption & Slicing via `SubRow`

`subsume` and `inject` in `effectful` become zero-copy or bulk-copied vector operations backed by `SubRow`:
- `SubRow sub super` supplies compile-time literal projection indices: `subRowIndices :: [Int]`.
- Creating a sub-environment for a local block uses a single hardware-vectorized array copy (`copySmallMutableArray#`).

---

## 3. Phased Execution Roadmap

### Phase 1: Workspace & Cabal Configuration
1. Branch off `~/src/effectful/` as branch `polytropos-port`.
2. Update `cabal.project` in `~/src/effectful/`:
   ```cabal
   packages:
     effectful
     effectful-core
     effectful-th
     -- effectful-plugin is replaced by polytropos-plugin
   extra-packages:
     polytropos-core,
     polytropos-plugin
   ```
3. Update `effectful-core/effectful-core.cabal`:
   - Add dependencies: `polytropos-core >= 0.1`, `polytropos-plugin >= 0.1`.
   - Enable `-fplugin=Polytropos.Plugin`.
   - Remove dependency on `effectful-plugin`.

### Phase 2: Refactoring `Effectful.Internal.Effect`
1. Re-export and alias `polytropos`' row vocabulary:
   ```haskell
   type Effect = (Type -> Type) -> Type -> Type
   type EffectRow = RowOf Effect
   ```
2. Replace `class e :> es` with an alias for `FieldIndex`:
   ```haskell
   type (:>) (e :: Effect) (es :: [Effect]) = FieldIndex (EffectName e) es (EffectRep e)
   ```
   Or for labeled effects:
   ```haskell
   type (:::) (name :: Symbol) (e :: Effect) = name ':= e
   type HasEffect (name :: Symbol) (e :: Effect) (es :: EffectRow) = FieldIndex name es (EffectRep e)
   ```
3. Re-implement `Subset subEs es` in terms of `SubRow subEs es`:
   ```haskell
   type Subset subEs es = SubRow subEs es
   ```

### Phase 3: Refactoring `Effectful.Internal.Env`
1. Modify `data Env (es :: EffectRow)` to eliminate `refs :: PrimArray Ref`.
2. Update `getLocation`:
   ```haskell
   getLocation
     :: forall e es. (HasEffect (EffectName e) e es)
     => Env es
     -> IO (Int, SmallMutableArray RealWorld Any)
   getLocation (Env offset storageRef) = do
     Storage version effects <- S.readIORef storageRef
     let slot = offset + fieldIndex @_ @(EffectName e) @es
     pure (slot, effects)
   ```
3. Refactor `consEnv`, `unconsEnv`, `subsumeEnv`, and `injectEnv` to operate on direct slot indices and flat `SmallMutableArray` copies.

### Phase 4: Modernizing `Effectful.Labeled`
1. Replace `data Labeled (label :: Symbol) (e :: Effect)` with native row pairs:
   `type LabeledEff label e = label ':= e`.
2. Provide high-level operators:
   ```haskell
   sendLabeled :: forall label e es a. HasEffect label e es => e (Eff es) a -> Eff es a
   ```
3. Implement `KnownHash` integration for dynamic string-based label resolution in hot loops.

### Phase 5: Deprecation of `effectful-plugin`
1. Remove `effectful-plugin` from the build tree.
2. Ensure all tests in `effectful-core/test/` and `effectful/test/` compile cleanly with `-fplugin=Polytropos.Plugin`.

---

## 4. Verification Gates & Benchmark Metrics

### Gate 1: Unit Test Suite
- `cabal test effectful-core:test:test` must pass 100% of existing tests (state, reader, error, writer, concurrency, unlift).

### Gate 2: Microbenchmarks
- Run `benchmarks/bench_state.hs` and `benchmarks/bench_countdown.hs`:
  - **Static State Lookup:** Expect 10–15% throughput improvement due to elimination of Level-1 `PrimArray Ref` indirection.
  - **Environment Subsumption (`subsume`):** Expect 20–30% speedup from bulk `SubRow` vector copies.
  - **Compilation Time:** Measure GHC compile time for 20-effect stack modules; compile time should decrease significantly compared to `effectful-plugin` due to $O(1)$ Core literal emission.
