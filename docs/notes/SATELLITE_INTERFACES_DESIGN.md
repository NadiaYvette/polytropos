<!--
SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
-->
# Design Note — Satellite Interface Packages & Out-of-Core Ecosystem Interoperability

Date: 2026-10-07  
Status: DRAFT v0.1 · 2026-10-07 — Architecture and catalog for non-invasive satellite interface packages  
Related: `POLYTROPOS_DESIGN.md` (decisions D4, D5, D10),
`FIELD_UPDATE_EFFICIENCY_DESIGN.md` (transients and batch updates),
`DESIGN_REVIEW_CLAUDE-OPUS-4.6.md` (§2 ecosystem deployment potential),
`DOC_STRATEGY.md` (governance and dependency boundaries).  
Audience: Maintainer and contributors implementing satellite packages and ecosystem bridges.

---

## 0. Context & Architectural Thesis

A central goal of `polytropos` is to provide a single, unified runtime representation (`Rep`: tag plus flat `SmallArray`) that serves products, sums, nominal records, and open extensible variants without $O(N^{2.8})$ compile-time penalties.

However, real-world adoption requires interoperability with the broader Haskell ecosystem:
- **Optics:** `lens`, `microlens`, `optics`
- **Serialization:** `aeson`, `cbor` / `serialise`, `cassava`, `protobuf`
- **Databases & ORMs:** `beam`, `hasql`, `rel8`, `persistent`
- **APIs & Testing:** `openapi3`, `servant`, `QuickCheck`, `hedgehog`

### The Core Architectural Dilemma
Many of these ecosystem packages carry heavy or transitively proliferative dependency trees (most notably `lens`, which transitively pulls in dozens of packages, and `aeson` or `beam`). If `polytropos-core` were to depend directly on these libraries, it would contaminate every downstream user with an intractable dependency graph and long build times.

Conversely, if `polytropos` provided no integration, developers would be forced to write boilerplate conversion layers, negating the zero-cost representation advantage.

### The Solution: The Satellite Interface Package Architecture
`polytropos` adopts the **Satellite Package Pattern** (pioneered in `large-records-ecosystem`):
1. **Inviolable Zero-Contamination Core:** `polytropos-core` depends **strictly on `base`, `ghc-prim`, and `primitive`**. It never imports external libraries.
2. **Zero-Dependency Van Laarhoven Primitives:** For basic lenses, `polytropos-core` provides van Laarhoven combinators (`fieldLens`) using only `Functor` from `base`.
3. **Dedicated Satellite Packages:** Independent bridge packages (`polytropos-aeson`, `polytropos-beam`, `polytropos-optics`, etc.) depend jointly on `polytropos-core` and the target library, declaring typeclass instances non-invasively.
4. **Zero Upstream Invasiveness:** Neither `lens`, `aeson`, `beam`, nor `hasql` needs modification. In Haskell, declaring `instance ForeignClass LocalType` is standard, legally well-behaved, and avoids orphan warnings.

---

## 1. The Optics Triad: `lens` vs. `microlens` vs. `optics`

The Haskell optics landscape is split across three distinct philosophies:

| Library | Representation | Dependencies | Role in `polytropos` |
|---|---|---|---|
| **`lens`** | Van Laarhoven (`forall f. Functor f => (a -> f a) -> s -> f s`) | Heavyweight (dozens of transitive packages) | Addressed via `polytropos-lens` for full class hierarchy (`Field1`–`Field9`, `Each`, `Ixed`, `At`, `Choice` Prisms). |
| **`microlens`** | Van Laarhoven (identical type signature) | Minimalist (**zero** dependencies outside `base`) | Addressed via `polytropos-microlens` for dependency-conscious developers. |
| **`optics`** | Tagged Profunctor GADT (`Optic k is s t a b`) | Moderate (`optics-core`) | Addressed via `polytropos-optics` for fast compilation, clean errors, and `LabelOptic` integration. |

### The Van Laarhoven Zero-Dependency Nuance
A van Laarhoven lens requires only `Functor` from `GHC.Base`:
```haskell
type Lens' s a = forall f. Functor f => (a -> f a) -> s -> f s
```
Thus, `polytropos-core` exports:
```haskell
fieldLens :: HasField n (Record r) a => Field n -> (forall f. Functor f => (a -> f a) -> Record r -> f (Record r))
fieldLens (Field _) f r = fmap (\x -> setFieldAt idx (noInlineUnsafeCo x) r) (f (fieldAt idx r))
```
This requires **zero external packages**, yet immediately interoperates with both `lens` (`^.`, `.~`, `%~`) and `microlens`. Dedicated satellite packages (`polytropos-lens` and `polytropos-microlens`) are reserved for class-based overloading (`Field1`, `Each`, `At`, `Choice` prisms).

---

## 2. Satellite Packages Taxonomy & Design Principles

```
                                 ┌───────────────────┐
                                 │  polytropos-core  │ (Zero dependencies outside base/primitive)
                                 └─────────┬─────────┘
                                           │
         ┌───────────────────┬─────────────┼─────────────┬───────────────────┐
         ▼                   ▼             ▼             ▼                   ▼
   [Optics]            [Serialization]  [Databases]   [APIs/Web]         [Testing]
   • -optics           • -aeson         • -beam       • -openapi3        • -quickcheck
   • -microlens        • -cbor          • -hasql
   • -lens             • -cassava       • -rel8
                                        • -persistent
```

### 2.1 Optics Satellites
1. **`polytropos-optics`:**
   - Implements `instance (LabelOptic n A_Lens (Record r) (Record r) a a)` via `optics-core`.
   - Provides `Optic A_Prism` for sum variants.
2. **`polytropos-microlens`:**
   - Implements `Lens.Micro.Type` and `Lens.Micro.Each` instances without pulling in heavy transitive trees.
3. **`polytropos-lens`:**
   - Implements `Field1`–`Field9`, `Control.Lens.At.At`, `Control.Lens.Each.Each`, and `profunctors`-based `Prism` constructors.

### 2.2 Serialization Satellites
4. **`polytropos-aeson`:**
   - Derives `ToJSON` and `FromJSON` by unrolling the flat `SmallArray` directly into `Data.Aeson.KeyMap` / `Aeson.Object`.
   - Bypasses $O(N^{2.8})$ generic tree expansions, enabling sub-second compilation for 50+ field JSON models.
5. **`polytropos-cbor`:**
   - Serializes records and variants via `cborg` / `serialise`.
   - Sum variants encode as a 1-byte constructor tag followed by payload fields.
6. **`polytropos-cassava`:**
   - Maps CSV tabular data to `Record r` via `FromNamedRecord` and `ToNamedRecord`.
   - Direct column header string lookup maps to static symbol row offsets.

### 2.3 Database & ORM Satellites
7. **`polytropos-beam`:**
   - `beam` requires tables to be records parameterized over a columnar functor: `TableT f = TableT { col :: Columnar f Int, ... }`.
   - `polytropos` records are **naturally Higher-Kinded Data (HKD)**: `RowRep ProductRowT r f a` matches `beam`'s `Beamable` class directly.
   - Solves the longstanding issue where 60+ column SQL tables trigger GHC memory exhaustion during `Generic` derivation.
8. **`polytropos-hasql`:**
   - Provides `Row (Record r)` applicative row decoders for PostgreSQL query results.
   - Uses `modifyRep` / `MRep` transient builders to stream SQL column values directly into contiguous memory slots.
9. **`polytropos-rel8`:**
   - Oliver Charles' `rel8` operates on `Rel8able (f :: (Type -> Type) -> Type)`.
   - `polytropos` records implement `hfield`, `htabulate`, `htraverse`, and `hzipWith` natively via flat array operations.
10. **`polytropos-persistent`:**
    - Provides `PersistEntity` for Yesod relational mapping, serializing fields to/from `[PersistValue]`.

### 2.4 API Specification & Testing Satellites
11. **`polytropos-openapi3`:**
    - Generates OpenAPI 3.0 schema objects (`ToSchema`) by iterating over type-level label symbols without Core AST tree explosion.
12. **`polytropos-quickcheck`:**
    - Implements `Arbitrary (Record r)` and `Arbitrary (Variant s)` with slot-indexed shrinking.

---

## 3. Implementation Phasing & Task Packet Sequencing

The satellite packages sequence extends the core roadmap numerically from `task-08` through `task-19`:

- **Phase 3 Core & Syntax:** `task-01` through `task-07` (Core CoW, batch updates, plugin sum solving, `HasField`, `OverloadedRecordUpdate`, consumer surface, and generics).
- **Phase 4A Optics Satellites:** `task-08` (`optics`), `task-09` (`microlens`), `task-10` (`lens`).
- **Phase 4B Serialization Satellites:** `task-11` (`aeson`), `task-12` (`cbor`), `task-13` (`cassava`).
- **Phase 4C Database Satellites:** `task-14` (`beam`), `task-15` (`hasql`), `task-16` (`rel8`), `task-17` (`persistent`).
- **Phase 4D Schema & Testing Satellites:** `task-18` (`openapi3`), `task-19` (`quickcheck`).
