# LiquidHaskell & Synquid Developer Guide

**Audience:** Software Engineers, Formal Verification Practitioners, and Library Authors  
**Prerequisites:** Familiarity with basic Haskell, `polytropos-core`, and refinement types  
**Location in Repository:** `verification/liquid/`, `synthesis/synquid/`, `bin/polytropos-verify`

---

## 1. Introduction: Verification & Synthesis vs. Library Forks

When integrating external software for the sake of `polytropos`, external repositories fall into two fundamentally distinct categories:

1. **In-Tree / Library Forks (`effectful`, `polysemy`, `kernmantle`, `haskell-language-server`):**
   These are runtime libraries or compiler services modified to import `polytropos-core` or `polytropos-plugin`. Downstream projects consume them directly as Cabal dependencies or editor language servers.
2. **Formal Verification & Synthesis Engines (`liquidhaskell`, `synquid`):**
   These tools are **never added to your production `build-depends`**. They operate as out-of-process static verification engines and deductive code generators adhering to the **Zero-Contamination Doctrine**:
   - **Zero runtime overhead:** Your production binaries compile cleanly with GHC without depending on theorem provers or synthesis runtimes.
   - **Zero dependency lock-in:** If a downstream user or consumer does not have Z3 or LiquidHaskell installed, the package still compiles and passes its test suite via standard Cabal.

This guide explains how developers can leverage LiquidHaskell and Synquid to verify and generate code for `polytropos`.

---

## 2. LiquidHaskell Formal Verification

### 2.1 Why Use LiquidHaskell with Polytropos?

`polytropos` collapses open records and variants into a single runtime representation (`Rep`):
```haskell
data Rep = Rep {-# UNPACK #-} !Word {-# UNPACK #-} !(SmallArray Any)
```
Because fields are packed into a flat `SmallArray Any` indexed by literal integer offsets emitted by `Polytropos.Plugin`, runtime safety relies on one core truth: **an offset index must never exceed the bounds of the array.**

While `Polytropos.Plugin` guarantees this soundly at compile time through GHC's typechecker, `liquidhaskell` allows developers to write formal, machine-checked contracts about:
1. **Memory Bounds Safety:** Proving that slot index reads and writes never throw array out-of-bounds exceptions or segfaults.
2. **SubRow Projection Soundness:** Proving that projecting $K$ fields from an $N$-field super-record ($K \le N$) always reads valid source indices and produces an array of exactly length $K$.
3. **Exhaustive Variant Dispatch:** Proving that an open variant's constructor tag $t$ is strictly bounded by the size of the jump-table handler array ($0 \le t < M$).
4. **Peeling Tag Arithmetic Underflow Freedom:** Proving that single-constructor elimination (`peel`) never decrements remaining constructor tags below zero.

---

### 2.2 Specification Structure

All LiquidHaskell specifications are located in `verification/liquid/`:

#### A. Reusable Specification Header: `RowPredicates.spec`
Located at `verification/liquid/Polytropos/Liquid/RowPredicates.spec`. This file defines formal measures and refinement predicates over `polytropos` primitives:

```liquid
-- Refinement measure for SmallArray length
measure sizeofSmallArray :: SmallArray a -> Int

-- Safe slot index predicate: index is strictly within array bounds
predicate InBounds I Arr = (0 <= I && I < sizeofSmallArray Arr)

-- Safe projection predicate: all indices in list are within source bounds
predicate ValidProjection Idxs Arr =
  (forall i in Idxs. 0 <= i && i < sizeofSmallArray Arr)
```

#### B. Proof Harness: `Proofs.hs`
Located at `verification/liquid/Polytropos/Liquid/Proofs.hs`. This is a fully valid, typechecked Haskell module that encodes the verified functions using LiquidHaskell contract pragmas (`{-@ ... @-}`):

```haskell
{-@ type SafeIndex Arr = {i:Int | 0 <= i && i < sizeofSmallArray Arr} @-}

-- Proves that accessing any slot satisfying SafeIndex is total and memory-safe
{-@ verifySlotRead :: arr:SmallArray a -> i:SafeIndex arr -> a @-}
verifySlotRead :: SmallArray a -> Int -> a
verifySlotRead arr i = indexSmallArray arr i
```

#### C. First-Order Horn Constraints: `RowBounds.fq`
Located at `verification/liquid/Polytropos/Liquid/RowBounds.fq`. This file encodes the constraints directly in the Liquid-Fixpoint Horn clause format for direct verification via Z3:
```
constraint:
  env [ arr : (SmallArray Any);
        len : {v:Int | v == (sizeofSmallArray arr) && v >= 0};
        idx : {v:Int | 0 <= v && v < len} ]
  lhs {v:Int | v == idx}
  rhs {v:Int | 0 <= v && v < (sizeofSmallArray arr)}
  id 1 tag [1]
```

---

### 2.3 How Downstream Developers Can Use LiquidHaskell

If your package defines custom row invariants (e.g., non-empty records, bounded numeric fields, or complex subrow extraction routines):

1. **Import the Specification:**
   Include `verification/liquid/Polytropos/Liquid/RowPredicates.spec` in your LiquidHaskell invocation:
   ```bash
   liquid --include=verification/liquid/ src/MyModule.hs
   ```
2. **Annotate Your Functions:**
   Write refinement type signatures directly above your record-manipulating functions in ordinary `.hs` source files using `{-@ ... @-}` comments:
   ```haskell
   {-@ projectSubRecord :: indices:{[Int] | ValidProjection indices (repPayload r)}
                       -> r:Record r
                       -> Record sub @-}
   ```
3. **Execute Verification:**
   Run the verification CLI:
   ```bash
   # Run full formal verification gate
   bin/polytropos-verify --liquid
   ```

---

## 3. Synquid Type-Directed Program Synthesis

### 3.1 Why Use Synquid with Polytropos?

When writing production systems with large records (e.g. 50+ columns in database schemas, OpenAPI schemas, or microservice payloads), developers frequently need to write boilerplate adapter functions:
- Extracting a subset of fields (width subtyping adapter).
- Reordering fields to conform to another schema (field permutation adapter).
- Extending a record with defaulted fallback values.
- Writing exhaustive pattern match eliminators across 20-constructor variants.

Writing these functions by hand is tedious and error-prone. **Synquid** is a type-directed deductive program synthesizer: you write the type specification and logical refinement measures, and Synquid automatically **synthesizes the pure, total Haskell implementation.**

---

### 3.2 The Polytropos Synquid Forward-Port

Upstream Synquid was originally developed against older GHC versions (GHC 7.10 / 8.x) and older Z3 APIs.

To support `polytropos` on modern Haskell toolchains, the clone at `/home/nyc/src/synquid` was forward-ported on branch:
```
branch: nadia.chambers/forward-port-to-ghc-9.14-001
```
**Key changes in the forward port:**
- Updated parser, pretty-printer, and error reporting to compile cleanly on modern GHC (GHC 9.10–9.14).
- Modernized Z3 SMT solver bindings in `src/Synquid/Z3.hs` for current Z3 releases.
- Extended typechecker to support modern data declaration syntax and refinement measures compatible with `polytropos` records.

---

### 3.3 Synthesis Specification Catalog (`synthesis/synquid/`)

The repository provides five ready-to-use synthesis specifications under `synthesis/synquid/`:

#### 1. Width Subtyping: `RecordAdapter-SubRow.sq`
Synthesizes a projection function from a wider record (`SuperRec` with 4 fields) to a narrower sub-record (`SubRec` with 2 fields):
```synquid
data SuperRec = SuperRec { superId :: Int, superName :: String, superAge :: Int, superActive :: Bool }
data SubRec   = SubRec   { subId :: Int, subAge :: Int }

adaptSubRow :: r: SuperRec -> {SubRec | subId _v == superId r && subAge _v == superAge r}
adaptSubRow = ??
```
*Synthesized output:*
```haskell
adaptSubRow r = SubRec (superId r) (superAge r)
```

#### 2. Field Permutations: `RecordAdapter-Permute.sq`
Synthesizes a field-reordering function (e.g., swapping column order between legacy and modern APIs) while preserving data identity:
```synquid
data RecXYZ = RecXYZ { xVal :: Int, yVal :: String, zVal :: Bool }
data RecZYX = RecZYX { zOut :: Bool, yOut :: String, xOut :: Int }

permuteRec :: r: RecXYZ -> {RecZYX | xOut _v == xVal r && yOut _v == yVal r && zOut _v == zVal r}
permuteRec = ??
```

#### 3. Defaulted Field Extension: `RecordAdapter-Defaults.sq`
Synthesizes an adapter that takes a partial client input record and fills missing fields with defaults from a configuration record.

#### 4. Variant Jump-Table Dispatch: `VariantEliminator.sq`
Synthesizes an exhaustive eliminator function for open variants, ensuring that all constructor branches are covered and dispatched to their respective handlers:
```synquid
data StatusVar = StatusOk { okVal :: Int } | StatusErr { errCode :: Int }
data Result    = Result { resCode :: Int }

eliminateStatus :: v: StatusVar -> (Int -> Result) -> (Int -> Result) -> Result
eliminateStatus = ??
```

#### 5. Variant Widening / Subsumption: `VariantSubsumption.sq`
Synthesizes constructor tag injection logic for variant subtyping.

---

### 3.4 How Downstream Developers Can Use Synquid

1. **Write a `.sq` Specification:**
   Define your input record/variant types and target types with refinement measures in a `.sq` file (e.g. `MyAdapter.sq`). Place `??` as the synthesis goal.
2. **Run Synquid:**
   Invoke the forward-ported Synquid binary:
   ```bash
   synquid MyAdapter.sq
   ```
3. **Copy the Synthesized Code:**
   Synquid prints the verified Haskell function body. Paste the synthesized function into your `polytropos` Haskell module.
4. **Batch Verification:**
   You can verify all synthesis specifications in `synthesis/synquid/` using the unified verification script:
   ```bash
   bin/polytropos-verify --synquid
   ```

---

## 4. Unified Verification CLI (`bin/polytropos-verify`)

`polytropos` provides a unified verification runner at `bin/polytropos-verify`:

```bash
# Verify LiquidHaskell Horn clauses and GHC proof typechecking
bin/polytropos-verify --liquid

# Verify all Synquid synthesis specifications
bin/polytropos-verify --synquid

# Run all verification and synthesis checks
bin/polytropos-verify --all
```

This runner is integrated into CI via `scripts/tasks/verify-milestone-t7.sh`.
