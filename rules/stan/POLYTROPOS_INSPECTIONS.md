# Polytropos Static Analysis Specification (Stan & HLS)

This document specifies the custom static analysis passes and performance guardrails designed for `stan` and `hls-stan-plugin` when analyzing codebases that use `polytropos`.

---

## 1. Inspection Catalog

### `STAN-P01`: Hot-Loop CoW Update Detection
- **Severity:** `Warning` (Performance)
- **Scope:** Expressions inside `foldl`, `foldr`, `forM_`, `mapAccumL`, or recursive worker loops (`go acc ...`).
- **Description:** A function repeatedly calls `setField` on an immutable `Record r` inside a loop without batching.
- **Problem:** Because `setField` performs a Copy-on-Write (CoW) allocation of the record's underlying `SmallArray`, executing $K$ updates in a loop of length $M$ causes $\mathcal{O}(M \cdot K \cdot N)$ heap allocations.
- **Remediation:**
  1. Use batch updates: `setFieldsAt` for pre-calculated index updates.
  2. Use transient mutable builders: `runMRep (traverse_ (uncurry setFieldM) updates) initialRecord`.
  3. Transform the loop state into an `MRep` accumulator before entering the loop.

---

### `STAN-P02`: Redundant Variant Widening (`widenVariant`)
- **Severity:** `Warning` (Code Smells & Redundant Work)
- **Scope:** Calls to `widenVariant :: Variant sub -> Variant super`.
- **Description:** The source row type `sub` and the target row type `super` are identical (`sub ~ super`).
- **Problem:** `widenVariant` builds evidence and passes the variant through a redundant cast. While $\mathcal{O}(1)$ at runtime, it clutters Core and indicates stale refactoring artifacts.
- **Remediation:** Remove the redundant `widenVariant` call or replace with `id`.

---

### `STAN-P03`: Dead / Unused Fields in Open Product Rows
- **Severity:** `Suggestion` (Maintainability)
- **Scope:** Type-level row declarations `Record r` and constructor sites.
- **Description:** A field label `s := a` exists in a row type `r`, but neither `r.s` nor `getField @"s"` nor a subrow projection `projectRecord` referencing `"s"` occurs across the module graph.
- **Problem:** Carries unnecessary payload slots in every instantiated `Record` array at runtime.
- **Remediation:** Remove the unused field from the row definition or migrate it to a separate extension row.

---

### `STAN-P04`: Non-Exhaustive Manual Variant Cascade
- **Severity:** `Warning` (Robustness & Maintainability)
- **Scope:** Nested `case narrowVariant x of { Just ... -> ...; Nothing -> case narrowVariant ... }`.
- **Description:** A function manually attempts downcasting across multiple variant constructors instead of using total eliminators.
- **Problem:** Sequential $\mathcal{O}(N)$ pattern matching trees have poor branch prediction and lose compile-time exhaustiveness guarantees when new constructors are added to the row.
- **Remediation:**
  - For total elimination of the entire variant, replace with `eliminateUniform handlers x` ($\mathcal{O}(1)$ jump table).
  - For removing a single constructor and passing through the rest, use `peel @"tag" x`.

---

## 2. Integration with HLS and CI

1. **Local CLI Execution:**
   ```bash
   stan --config-file=.stan.toml
   ```
2. **IDE Integration (`hls-stan-plugin`):**
   When `hls-stan-plugin` is active, inspections surface inline as diagnostics with remediation notes in VS Code, Neovim, and Emacs.
