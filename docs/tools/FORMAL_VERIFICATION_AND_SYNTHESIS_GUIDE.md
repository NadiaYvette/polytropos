# Formal Verification, Program Synthesis & Continuous Diagnostics Guide

**Milestone:** T7 (`plans/FULL_COMPLETION_ROADMAP.md`)  
**Status:** ACTIVE SPECIFICATION & TOOLING MANUAL  
**Audience:** Compiler Engineers, Formal Methods Practitioners, and AI Coding Assistants  

---

## 1. Executive Summary & Architecture

`polytropos` bridges high-performance row polymorphism with formal methods, type-directed synthesis, and continuous zero-log compiler verification:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Milestone T7 Tooling Matrix                      │
├───────────────────────┬──────────────────────┬─────────────────────────┤
│ LiquidHaskell (Formal)│ Synquid (Synthesis)  │ Tricorder (Continuous)  │
├───────────────────────┼──────────────────────┼─────────────────────────┤
│ • Memory bounds proofs│ • SubRow adapters    │ • Continuous GHCi daemon│
│ • Subrow projection   │ • Field permutations │ • Zero-log diagnostics  │
│ • Jump table dispatch │ • Extension defaults │ • MCP JSON-RPC bridge   │
│ • Field refinements   │ • Variant dispatch   │ • >95% token reduction  │
│ (verification/liquid/)│ (synthesis/synquid/) │ (bin/polytropos-tricorder)│
└───────────────────────┴──────────────────────┴─────────────────────────┘
```

All tooling adheres to the **Zero-Contamination Doctrine** (`.agents/rules/compiler-verification.md`): assistant and formal tools remain strictly out-of-process without altering package dependencies or violating the Tier 0 POSIX build floor.

---

## 2. LiquidHaskell Formal Verification

### 2.1 Specification Files & Artifacts
The formal verification suite is located under `verification/liquid/`:
- **[`RowPredicates.spec`](../../verification/liquid/Polytropos/Liquid/RowPredicates.spec):** LiquidHaskell refinement specifications over `SmallArray` bounds, `Rep` tags and payloads, safe slot indexing, subrow extraction, and domain field predicates.
- **[`Proofs.hs`](../../verification/liquid/Polytropos/Liquid/Proofs.hs):** Fully typechecked Haskell module with LiquidHaskell refinement contracts in `{-@ ... @-}` pragmas, compiling cleanly under GHC with `-Wall -Werror`.
- **[`RowBounds.fq`](../../verification/liquid/Polytropos/Liquid/RowBounds.fq):** First-order Horn clause constraint problem solved by the Liquid-Fixpoint solver and the Z3 SMT solver.

### 2.2 Verified Invariants

#### A. Record Slot Indexing Memory Safety
For any record `r = Rep t v` with arity $N = \text{sizeofSmallArray}(v)$, direct slot access `fieldAt i r` is provably safe:
$$\forall i \in \mathbb{N}, \quad 0 \le i < N \implies \text{indexSmallArray}(v, i) \text{ is well-defined}$$

#### B. SubRow Projection Safety
Given a subrow mapping with indices $I = [i_0, i_1, \dots, i_{K-1}]$ where $\forall j \in [0..K-1], 0 \le i_j < N_{\text{super}}$:
$$\text{projectSubRow}(I, \text{super}) \text{ allocates } K \text{ slots with zero out-of-bounds reads}$$

#### C. Variant Jump Table Exhaustiveness
For open variants with constructor tag $t$ and jump table handler array of size $M$:
$$0 \le t < M \implies \text{handlers}[t] \text{ is reachable in } \mathcal{O}(1) \text{ without branch failure}$$

#### D. Peeling Tag Remapping Underflow Freedom
When peeling constructor $T$ from variant with tag $t$:
$$\text{If } t > T, \quad t' = t - 1 \ge 0$$

### 2.3 Executing Verification
Run the formal verification gate via the CLI runner:
```bash
# Verify LiquidHaskell Horn clauses and GHC proof typechecking
bin/polytropos-verify --liquid
```

---

## 3. Synquid Type-Directed Program Synthesis

### 3.1 Overview & Specifications
Synquid synthesizes functional programs from refinement type specifications using round-trip type-directed deductive search. In `polytropos`, Synquid automates the synthesis of row adapters and variant eliminator bodies under `synthesis/synquid/`:

1. **[`RecordAdapter-SubRow.sq`](../../synthesis/synquid/RecordAdapter-SubRow.sq):**
   Synthesizes width subtyping projections from wider source records (`SuperRec`) to narrower target records (`SubRec`).
2. **[`RecordAdapter-Permute.sq`](../../synthesis/synquid/RecordAdapter-Permute.sq):**
   Synthesizes field permutation adapters (e.g. `RecXYZ` to `RecZYX`) preserving structural values.
3. **[`RecordAdapter-Defaults.sq`](../../synthesis/synquid/RecordAdapter-Defaults.sq):**
   Synthesizes record extension adapters with defaulted optional configuration parameters.
4. **[`VariantEliminator.sq`](../../synthesis/synquid/VariantEliminator.sq):**
   Synthesizes total, exhaustive variant eliminator dispatch logic given variant branches and handler functions.
5. **[`VariantSubsumption.sq`](../../synthesis/synquid/VariantSubsumption.sq):**
   Synthesizes variant widening and constructor tag injection functions.

### 3.2 Synthesis Specification Structure
Every `.sq` specification defines:
- Refined inductive data types (`data SuperRec`, `data SubRec`).
- Logical measures for field values (`measure superId`, `measure subAge`).
- The synthesis goal with a hole:
  ```synquid
  adaptSubRow :: r: SuperRec -> {SubRec | subId _v == superId r && subAge _v == superAge r}
  adaptSubRow = ??
  ```

### 3.3 Validating Synthesis Specifications
```bash
bin/polytropos-verify --synquid
```

---

## 4. Tricorder Continuous Compilation & Zero-Log Diagnostics

### 4.1 Token Economics & Motivation
Traditional `cabal build` or `cabal test` runs emit hundreds of lines of compiler logs into LLM prompt contexts (~2,500 tokens per call).

`tricorder` maintains a persistent GHCi daemon in the background and delivers machine-readable JSON status summaries in $<50$ tokens (>95% token savings):
```json
{"status": "ok", "errors": 0, "warnings": 0}
```

### 4.2 Workspace Configuration (`.tricorder.yaml`)
Configured at repository root:
```yaml
session:
  command: cabal repl --enable-multi-repl
  targets:
    - lib:polytropos-core
    - lib:polytropos-plugin
  test_targets:
    - test:polytropos-core-test
  watch_dirs:
    - packages/polytropos-core/src
    - packages/polytropos-core/test
    - packages/polytropos-plugin/src
    - packages/polytropos-plugin/test
  repl_build_dir: dist-newstyle/tricorder
  test_timeout: 15
  idle_timeout_seconds: 600
```

### 4.3 MCP JSON-RPC Server Integration
Integrated via `.mcp.json` / `.agents/mcp.json`:
```json
{
  "mcpServers": {
    "tricorder": {
      "command": "tricorder-mcp"
    }
  }
}
```

Available MCP tools:
- **`status(wait: true)`**: Queries current compiler errors and warnings, blocking until in-flight builds finish.
- **`test_results(failed: true)`**: Queries test results without raw console output.
- **`source(module: "Polytropos.Core")`**: Fetches module source from disk for context-budgeted inspection.

### 4.4 Tricorder CLI Runner (`bin/polytropos-tricorder`)
```bash
# Query daemon build status in JSON
bin/polytropos-tricorder status

# Start continuous compilation daemon
bin/polytropos-tricorder start

# Validate configuration and MCP binary
bin/polytropos-tricorder config
bin/polytropos-tricorder check-mcp
```

---

## 5. Unified Verification Gate

Milestone T7 is deterministically verified via:
```bash
./scripts/tasks/verify-milestone-t7.sh
```

The gate asserts:
1. All specification, proof, configuration, and runner files exist.
2. GHC compiles `verification/liquid/Polytropos/Liquid/Proofs.hs` with `-Wall -Werror`.
3. Liquid-Fixpoint / Z3 solves all 5 Horn clause invariants in `RowBounds.fq` returning `Safe`.
4. All 5 Synquid synthesis `.sq` specifications are structurally valid.
5. `.tricorder.yaml` and `tricorder-mcp` configuration pass validation.
6. Unified CLI runner `bin/polytropos-verify --all` exits 0.
7. Core test suite `cabal test polytropos-core:test:polytropos-core-test` passes cleanly.
