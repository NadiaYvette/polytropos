<!--
SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
-->
# Implementation Plan — Porting `kernmantle` to `polytropos`

Date: 2026-10-10  
Status: DRAFT v0.1 · 2026-10-10 — Blueprint for forking `master` of `~/src/kernmantle/` and replacing `vinyl` with `polytropos`  
Related: `EFFECT_SYSTEMS_PORTING_MASTER_PLAN.md` (master plan), `POLYTROPOS_DESIGN.md` (decisions D1–D10, flat HKD records), `SATELLITE_INTERFACES_DESIGN.md`  
Audience: Maintainers and developers implementing the `kernmantle-polytropos` fork.

---

## 0. Overview & Context

`kernmantle` is an arrow-based extensible effect and pipeline framework that interlaces binary profunctor effects ("strands") into an overarching "rope" (`Rope record mantle core a b`).

On `master` (commit `11431c0`), `kernmantle` uses the `vinyl` package (`Data.Vinyl.Rec`) for its record backend.
An experimental branch (`nadia.chambers/large-anon-port-001`) attempted to migrate from `vinyl` to `large-anon`, but stalled due to severe impedance mismatches:
- `large-anon`'s record structure is rigid and struggled with higher-kinded profunctor parametrization (`Weaver interp :: Strand -> Type`).
- GHC's `proc` arrow desugaring phases conflicted with `large-anon`'s source plugin and label resolution.
- `large-anon` had zero support for open sums or variant branching, preventing arrow choice extensions.

**Explicit Forking Directive:**
This implementation plan **forks strictly from `master`**, leaving the incomplete `large-anon` changes, scratch scripts, and legacy worktrees entirely behind. It replaces `vinyl` with `polytropos`' native Higher-Kinded Data record (`RecordF`) and flat vector operations.

---

## 1. Upstream Architecture & Why `vinyl` Failed

### 1.1 The Vinyl Linked-List Bottleneck

In `~/src/kernmantle/kernmantle/src/Control/Kernmantle/Rope/Internal.hs`:

```haskell
type BinEff = Type -> Type -> Type
type Strand = (Symbol, BinEff)

type RopeRec = (Strand -> Type) -> [Strand] -> Type

newtype Weaver (interp :: BinEff) (strand :: Strand) = Weaver
  { weaveStrand :: StrandEff strand :-> interp }

newtype RopeRunner (record :: RopeRec) (mantle :: [Strand]) (interp :: BinEff) (core :: BinEff) a b =
  RopeRunner (record (Weaver interp) mantle -> core a b)
```

On `master`, `record` is `Data.Vinyl.Rec`:
```haskell
data Rec :: (u -> Type) -> [u] -> Type where
  RNil :: Rec f '[]
  (:&) :: !(f r) -> !(Rec f rs) -> Rec f (r ': rs)
```

**Consequences:**
1. **$O(N)$ Pointer Chasing:** `Rec` is a linked-list spine. Fetching a strand interpreter (`strand l eff`) via `rgetf` traverses the linked list at runtime, chasing pointers across the heap.
2. **Artificial API Fracture (`LooseRope` vs `TightRope`):**  
   To combat the $O(N)$ lookup cost of `Rec`, `kernmantle` introduced `TightRope = Rope ARec` using Vinyl's array-backed `ARec`. However, converting between `Rec` (which supports consing `(:&)`) and `ARec` (which supports array reads) required tedious `tighten` / `loosen` operations and heavy `ToARec` constraints.
3. **Expensive Re-twining:** `retwine r = mkRope $ runRope r . rcast` relied on Vinyl's `rcast`, which re-allocated a brand-new linked-list spine with Peano projections.

---

## 2. Target `polytropos` Architecture

### 2.1 Native Higher-Kinded Records (`RecordF`)

In `polytropos`, records are naturally higher-kinded data structures parameterized over any functor or indexed type:

```haskell
-- In Polytropos:
type RecordF f r = RowRep f 'ProductRowT r ()
```

For `kernmantle`:
- A strand is a row field: `type Strand = Symbol ':= BinEff`.
- The mantle is an open product row of strands: `mantle :: RowOf BinEff`.
- The interpreter record is simply:
  ```haskell
  type RopeRec mantle core = RecordF (Weaver core) mantle
  ```

Every `RecordF` is backed by `Rep`:
$$\text{Rep} = \text{Rep} \{ \text{tag} :: !\text{Word}, \text{payload} :: !\text{SmallArray Any} \}$$

### 2.2 Collapsing `LooseRope` and `TightRope`

Because every `polytropos` record is **already an unboxed, flat `SmallArray`**:
- The distinction between `LooseRope` and `TightRope` is completely eliminated!
- There is only one unified, optimal type:
  ```haskell
  newtype Rope (mantle :: RowOf BinEff) (core :: BinEff) a b =
    Rope (RecordF (Weaver core) mantle -> core a b)
  ```
- No `tighten`, no `loosen`, no `ToARec` boilerplate. Every rope operates with $O(1)$ flat array performance.

### 2.3 $O(1)$ Strand Execution via `FieldIndex`

In `Control.Kernmantle.Rope`:

```haskell
strand
  :: forall label eff mantle core.
     FieldIndex label mantle eff
  => Label label
  -> eff :-> Rope mantle core
strand _ eff = Rope $ \(RowRep (Rep _ arr)) ->
  let idx = fieldIndex @_ @label @mantle @eff
      Weaver w = unsafeCoerce (indexSmallArray arr idx)
  in w eff
```

- `Polytropos.Plugin` solves `fieldIndex` to a literal unboxed integer `Int#` at compile time.
- At runtime, executing a strand is a single array index read `indexSmallArray arr idx`. Zero pointer chasing, zero list traversal.

### 2.4 Zero-Copy Sub-Pipeline Re-twining via `SubRow`

`retwine` re-orders and projects strands to match an expected sub-pipeline context:

```haskell
retwine
  :: forall sub super core.
     SubRow sub super
  => Rope sub core
 :-> Rope super core
retwine (Rope runSub) = Rope $ \superRec ->
  let subRec = projectRecordF superRec
  in runSub subRec
```

- `SubRow sub super` supplies literal slice indices (`subRowIndices :: [Int]`).
- `projectRecordF` copies only the required slots into a new flat `SmallArray` in a single tightly unrolled loop.

### 2.5 Future Extension: Variant Strands & `BranchingRope`

`vinyl` and `large-anon` could only model product records.
Because `polytropos` unifies products and sums, `kernmantle` can natively introduce **Variant Strands** (`BranchingRope`):
```haskell
newtype BranchingRope (mantle :: RowOf BinEff) (core :: BinEff) a b =
  BranchingRope (VariantF (Weaver core) mantle -> core a b)
```
This enables first-class arrow choice branching across dynamic effect pipelines with $O(1)$ `Word` tag dispatch.

---

## 3. Phased Execution Roadmap

### Phase 1: Forking and Sanitization
1. Fork from `~/src/kernmantle/` on branch `master` (commit `11431c0`):
   ```bash
   git checkout master
   git checkout -b polytropos-port
   ```
2. Clean out unversioned files and experimental large-anon scratch scripts:
   - Remove `vinyl-to-large-anon-migration-plan.md`, `migrate_rope.py`, `hermes_run.log`, `.ok/`.
3. In `kernmantle/package.yaml` / `kernmantle.cabal`:
   - Drop `vinyl`.
   - Add `polytropos-core >= 0.1`, `polytropos-plugin >= 0.1`.
   - Add default GHC option: `-fplugin=Polytropos.Plugin`.
4. In `cabal.project`:
   ```cabal
   packages:
     kernmantle
     batteries

   source-repository-package
     type: git
     location: https://github.com/NadiaYvette/polytropos.git
     tag: b24592f41cf5bc243df020db35af0b9e3c39487f
     subdir:
       packages/polytropos-core
       packages/polytropos-plugin
   ```

### Phase 2: Refactoring `Control.Kernmantle.Rope.Internal`
1. Redefine `Strand` as `Pair Symbol BinEff`:
   ```haskell
   type Strand = Symbol ':= BinEff
   ```
2. Redefine `RopeRunner`:
   ```haskell
   newtype RopeRunner (mantle :: RowOf BinEff) (interp :: BinEff) (core :: BinEff) a b =
     RopeRunner (RecordF (Weaver interp) mantle -> core a b)
   ```
3. Re-implement arrow instances (`Category`, `Arrow`, `ArrowChoice`, `ArrowLoop`) over `RopeRunner`.

### Phase 3: Refactoring `Control.Kernmantle.Rope`
1. Define unified `Rope`:
   ```haskell
   type Rope mantle core = RopeRunner mantle core core
   ```
   (Provide deprecated type aliases for `LooseRope` and `TightRope` pointing to `Rope` for backwards compatibility).
2. Re-implement `strand` and `mapStrand` using `FieldIndex`.
3. Re-implement `weave`, `weave'`, and `weaveK`:
   - Extending the mantle with a new interpreter uses `insertFieldF`.
4. Re-implement `retwine` using `SubRow` and `projectRecordF`.
5. Re-implement `weaveAll` using `AllFields` or `htraverse` over the flat array.

### Phase 4: Porting Satellite Packages & Examples
1. Update `batteries/` (`kernmantle-batteries.cabal`) to use the new `Rope`.
2. Port examples in `kernmantle/examples/`:
   - `Ex1.hs` (basic rope workflow).
   - `ExBypass.hs` (strand bypassing).
   - `ExCli.hs` (command-line options pipeline).
   - `ExLenses.hs` (stateful strand with profunctor lenses).

---

## 4. Verification Gates & Benchmark Metrics

### Gate 1: Example Execution
- Build and execute all four example executables:
  ```bash
  cabal run ex1
  cabal run exBypass
  cabal run exCli -- --help
  cabal run exLenses
  ```
- All examples must produce identical output to the upstream master reference.

### Gate 2: Microbenchmarks
- Measure strand invocation latency across mantles of sizes 5, 10, 20, 40:
  - **Strand Dispatch Latency:** Expect $O(1)$ constant time execution under `polytropos`, eliminating Vinyl's linear $O(N)$ degradation.
  - **Memory Footprint:** 50%+ reduction in heap allocation during pipeline construction due to elimination of linked-list cons cells `(:&)`.
