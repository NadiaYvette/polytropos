<!--
SPDX-License-Identifier: BSD-3-Clause
-->
# Architectural Mitigations for Row-Polymorphism Adoption Barriers

**Status:** DESIGN NOTE · v1.0 · 2026-10-10  
**Context:** Synthesis and direct response to the community feedback captured in [`docs/transcripts/discord-adoption-barriers-row-types.md`](../transcripts/discord-adoption-barriers-row-types.md).  
**Parent Strategy:** [`docs/notes/DOC_STRATEGY.md`](DOC_STRATEGY.md)  
**Reading Map:** [`docs/INDEX.md`](../INDEX.md)  

---

## 1. Executive Summary

Historically, extensible record and variant libraries in Haskell (e.g., `vinyl`, `superrecord`, `row-types`, `extensible`) have suffered from severe adoption barriers. While developers recognized the theoretical elegance of row polymorphism, practical adoption stalled due to:
1. Incomprehensible documentation and intimidating category-theoretic abstractions.
2. Questionable perceived benefit over standard nominal types with `GHC.Generics`.
3. Proliferation of incompatible, non-standard syntax and operators.
4. Syntactic verbosity in record construction and updates.
5. Catastrophic type error dumps when mistakes occur.
6. Complete lack of IDE autocompletion in tooling (HLS).
7. Compiling via fragile typeclass instance selection loops that cause severe compiler slowdowns.
8. Awkward or unsafe pattern matching over open variant and handler types.

`polytropos` was deliberately designed from its inception to eliminate or mitigate each of these historical failure modes. This document formalizes how each barrier is addressed by `polytropos`'s flat `SmallArray` runtime architecture, native `TcPlugin` solver, and progressive user surface.

---

## 2. Comparative Matrix: Prior Art vs. `polytropos`

| # | Barrier / Complaint | Root Cause in Prior Art (`vinyl`, `superrecord`, `row-types`) | How `polytropos` Solves / Mitigates It |
|---|---|---|---|
| **1** | **Opaque Haddocks & Interfaces** ("Try reading vinyl's haddocks") | Haddock documentation is heavily abstracted into universe functors (`ElField`, `Dict`), Peano type-level lists, and opaque category-theoretic jargon with few worked, practical examples. | Governed by [`DOC_STRATEGY.md`](DOC_STRATEGY.md): worked examples, concrete invariants, clear rationale, no filler. A dedicated human-facing consumer module ([`Polytropos`](../../packages/polytropos-core/src/Polytropos.hs)) exposing direct functions (`emptyRecord`, `insertField`, `Variant`, `projectVariant`) that read like ordinary standard library code, hiding internal representation details. |
| **2** | **Questionable Benefit vs. `GHC.Generics`** | If an extensible library only provides generic serialization or lenses at high complexity, developers default to nominal ADTs with `deriving (Generic)` and `GHC.Generics`. | 1. Genuine open subrow/subsum polymorphism (`SubRow`, `SubSum`) with $O(1)$ widening and bulk projection.<br>2. Avoids the $O(2^N)$ binary tree explosion (`:+:`, `:*:`) in compile time and runtime heap allocations.<br>3. Direct bridge in [`polytropos-generics`](../../packages/polytropos-generics/src/Polytropos/Generics.hs) evaluating `geq`, `gcompare`, `gshowsPrec`, `gmap`, `gfoldMap` over flat `Rep` with zero intermediate metadata allocations.<br>4. Open algebraic effect systems without plugin-specific search stalls (proven in `effectful`, `polysemy`, and `kernmantle` ports). |
| **3** | **Lack of Standardisation** | Every library invents competing operators (`<+>`, `:>`, `.&.`), entry wrappers, and closed universes, none of which interoperate. | Standardizes on official GHC facilities: native record dot (`OverloadedRecordDot`) via [`GHC.Records.HasField`](../../packages/polytropos-plugin/src/Polytropos/Plugin.hs), [`GHC.OverloadedLabels.IsLabel`](../../packages/polytropos-core/src/Polytropos/Core.hs) (`#field`), standard optics prisms and lenses, and drop-in satellite packages for standard ecosystem libraries (`aeson`, `beam`, `rel8`, `persistent`, `openapi3`, `cassava`, `cbor`, `quickcheck`). |
| **4** | **Verbosity** | Constructing or updating records requires verbose linked-list chains: `Field @"a" 1 :& Field @"b" True :& RNil`. | Milestone §1.6 source-plugin syntax: `[REC| a: 1, b: True |]`, field punning `[REC| a, b |]`, record updates `[REC_UPD| r with a: 2 |]`, and open declaration forms (`deriving OpenRecord` / `deriving OpenVariant`). |
| **5** | **Bad Type Errors & Inference Fragility** ("nigh impossible to figure out what has gone wrong") | When typeclass search fails in instance-selection libraries, GHC dumps hundreds of lines of stuck type families and unprovable Peano constraints (`Could not deduce (RecElemFCtx ...)`). | `polytropos` rejects type-level instance search loops. All row indexing and projection is solved deterministically by a dedicated `TcPlugin` (`Polytropos.Plugin`), which calculates literal indices and emits custom human-readable `TypeError` diagnostics specifying missing fields or tag mismatches. |
| **6** | **No Autocompletion in IDE / Tooling (HLS)** | Haskell Language Server (HLS) cannot suggest completions for type-level symbol lists because fields are not nominal record selectors in the module environment. | Open declaration forms (`deriving OpenRecord` / `deriving OpenVariant`) generate nominal field selector signatures in the module environment that HLS indexes for completion. For `OverloadedRecordDot`, compiler plugins provide explicit candidates when the row is known. |
| **7** | **Compiling via Instance Selection & Normalization** (mniip: "force computation to happen at compile time... in instance selection") | Forcing GHC's instance solver to execute type-level algorithms (sorting, searching, matching) via recursive class instances and head normalization causes compiler slowdowns and solver blowups. | Core architectural invariant in `polytropos`: **zero type-level search**. Computations (FNV-1a 64-bit hashing, slot calculations, subrow projections) occur in native compiled Haskell code inside the `TcPlugin`, directly emitting literal Core AST dictionaries. |
| **8** | **Pattern Matching for Handler Types** | Open variants require exhaustive dispatch across open constructor rows, risking missing cases or cumbersome nested `Either` trees. | Decided hybrid eliminator design: coproduct of per-constructor results `m (SumOf (Results handlerRow))`, certified by compile-time `SubSum` narrowing evidence to eliminate unhandled constructors safely. |

---

## 3. Deep-Dive on Core Mitigations

### 3.1 Documentation & Interface Clarity (Addressing Cyrus T Crumples)

The primary barrier cited by users trying libraries like `vinyl` is the incomprehensibility of the documentation and type signatures:
```haskell
-- Typical Vinyl signature:
rget :: (RecElemFCtx record f, HasField record l mantle mantle eff eff) => Label l -> record f mantle -> f '(l, eff)
```
A newcomer is immediately confronted by `RecElemFCtx`, `HasField` with duplicated parameters, and universe constraints.

**The Polytropos Approach:**
1. **Separation of Consumer and Internal Modules:**
   - [`Polytropos`](../../packages/polytropos-core/src/Polytropos.hs) is strictly for end-users. It exposes simple, clean types: `Record r`, `Variant s`, `emptyRecord`, `insertField`, `projectRecord`, `widenVariant`.
   - [`Polytropos.Core`](../../packages/polytropos-core/src/Polytropos/Core.hs) is for library authors and satellite integrations, housing the underlying `Rep`, `SmallArray`, and evidence classes.
2. **Standard Terminology:**
   Instead of category-theoretic jargon, documentation describes records as "flat arrays of fields with compile-time literal indexing" and variants as "unboxed word tag plus payload".

### 3.2 True Value Beyond `GHC.Generics` (Addressing edmundnoble)

If extensible records only provide generic `FromJSON` or lenses, why not use standard nominal types with `deriving Generic`?

**Polytropos Delivers Three Capabilities `GHC.Generics` Cannot Match:**
1. **$O(1)$ and Bulk Subtyping Without Re-allocation:**
   In nominal `GHC.Generics`, converting a 20-field record to an 8-field subset requires allocating an entirely new data structure through an intermediate binary tree of `M1`, `:+:`, `:*:`, and `K1` constructors. In `polytropos`, `SubRow` generates literal integer indices, and `rcast` copies slots directly into a pre-sized array in a single memory block.
2. **Open Variant Widening & Narrowing:**
   Nominal sums cannot be widened or narrowed without manual pattern matching. `polytropos` provides `widenVariant` (total, $O(1)$ tag rewriting via literal lookup tables) and `narrowVariant` (partial, branchless tag matching).
3. **Algebraic Effect Interoperability:**
   As demonstrated in the `effectful`, `polysemy`, and `kernmantle` ports, `polytropos` allows effect rows to be open, modular, and indexed in $O(1)$ without recursive Peano typeclass induction.

### 3.3 Zero Type-Level Search (Addressing mniip)

As mniip observed in the Discord discussion:
> *"it's trying to force computation to happen at compile time, and the only way to do that is to encode your computation in instance selection... normalization of instance heads and 'pattern' 'matching'"*

This observation hits the fundamental weakness of pure-Haskell extensible record libraries: GHC's typeclass constraint solver was designed for type inference and dictionary passing, **not** as a general-purpose compile-time compute engine. Forcing it to perform $O(N)$ or $O(N^2)$ list searching causes:
- Quadratic or exponential compile-time explosion ($O(N^{2.8})$ in `vinyl`).
- Horrendous error dumps when a constraint cannot be resolved.
- Fragile backtracking behavior.

**Polytropos Solves This via the TcPlugin Architecture:**
`polytropos` completely breaks out of the "instance selection as compute engine" trap. The typechecker plugin (`Polytropos.Plugin`) intercepts `FieldIndex`, `ConstructorIndex`, `SubRow`, `SubSum`, and `KnownHash` constraints. It performs all hashing, array indexing, and subrow subset checks in native, compiled Haskell code, and emits literal integers, words, and Core AST expressions directly into the compiled output. The GHC constraint solver never loops, never backtracks, and never searches.
