<!--
SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
-->
# Architectural Survey: Related Work & Ecosystem Prior Art

**Status:** DESIGN NOTE · v1.0 · 2026-10-16  
**Audience:** Compiler Engineers, Library Maintainers, Type Theorists, and Language Designers  
**Parent Strategy:** [`docs/notes/DOC_STRATEGY.md`](DOC_STRATEGY.md)  
**Reading Map:** [`docs/INDEX.md`](../INDEX.md)  
**Related Documents:**
- [`docs/notes/POLYTROPOS_DESIGN.md`](POLYTROPOS_DESIGN.md) (canonical decisions D1–D10)
- [`docs/notes/ADOPTION_BARRIERS_AND_MITIGATIONS.md`](ADOPTION_BARRIERS_AND_MITIGATIONS.md) (8-point barrier matrix)
- [`docs/developer/UPSTREAM_REPOSITORIES_AND_INTEGRATIONS.md`](../developer/UPSTREAM_REPOSITORIES_AND_INTEGRATIONS.md) (catalog of modified upstream repos)
- [`benchmark/variants/README.md`](../../benchmark/variants/README.md) (compile-time & memory measurements)

---

## 0. Prologue: The Extensibility Quest in Typed Functional Programming

The central design space of algebraic data types (ADTs) in typed functional programming is spanned by two orthogonal axes:
1. **Mathematical Shape**: *Products* (conjunction: records, tuples, structs) versus *Sums* (disjunction: tagged unions, variants, coproducts).
2. **Declaration Boundary**: *Nominal* (closed, explicitly declared data definitions with rigid type names) versus *Structural* (open, anonymous row schemas defined by their field or constructor signatures).

For over three decades, functional programming languages have navigated trade-offs across these quadrants:
- **Standard Haskell, SML, and Rust** enforce strict nominal encapsulation: `data Person = Person { name :: String, age :: Int }` exists only under its declared type name. While nominal typing provides strong abstraction barriers and fast static compilation, it forces severe friction when schemas evolve, when intermediate data transfer objects (DTOs) proliferate across compiler passes or network boundaries, and when libraries attempt to share open variants.
- **OCaml** introduced first-class row polymorphism and polymorphic variants (`` `Tag of a ``), showing that structural extensibility can be achieved without nominal type declarations.
- **PureScript and Elm** embedded row polymorphism natively into their compilers, primarily for records and extensible effects.
- **Haskell's Ecosystem** has repeatedly attempted to bring structural rows to GHC through library space—first through pure type-level encoding (`vinyl`, `superrecord`, `row-types`, `extensible`), later through large-record engineering (`large-records`, `large-anon`), and via algebraic effect libraries (`polysemy`, `effectful`, `kernmantle`).

`polytropos` does not emerge in isolation. It stands on the shoulders of these prior explorations while identifying and systematically resolving the foundational bottlenecks that prevented earlier Haskell approaches from achieving widespread mainstream adoption.

---

## 1. Category 1: Classic Haskell Extensible Records & Open Variants

Between 2012 and 2020, Haskell developers explored multiple pure-library approaches to extensible records and open sum types.

### 1.1 `vinyl` (Extensible Records & Functor Universes)
- **Architecture**: `vinyl` represents records as heterogeneous lists (`Rec (f :: u -> Type) (rs :: [u])`) indexed by type-level lists, parameterized over an arbitrary universe interpretation functor `f`. Field lookup is performed via typeclass induction (`RecElem record r rs`).
- **Achievements**: Pioneered higher-kinded data (HKD) records in Haskell, established foundational vocabularies for vinyl-based effect systems (e.g. `kernmantle`), and popularized type-level label manipulation.
- **Limitations & Failure Modes**:
  1. *Superlinear Compile-Time Scaling*: Field lookup and projection rely on recursive typeclass search. As measured in `benchmark/variants/README.md` (Arm C), unassisted type-level search induces superlinear Core explosion ($O(N^{2.8})$ exponent, generating $>2,000,000$ lines of Core and 804 MB RSS at $N=100$).
  2. *Runtime Indirection*: Under the hood, `Rec` is a linked list of boxed cons cells (`(:&)` and `RNil`). Reading the $k$-th field requires traversing $k$ heap pointers.
  3. *Opaque Error Messages & Haddocks*: Type signatures carry complex universe constraints (`RecElemFCtx record f`, `HasField record l mantle eff`), leading to stuck type families and unreadable multi-page compiler error dumps when field lookups fail.

### 1.2 `superrecord` (Type-Level Sorted Array Records)
- **Architecture**: `superrecord` represents records as contiguous arrays of `Any` values (`Record (xs :: [*])`). Field indices are computed at compile time by sorting type-level symbol lists using type families (`Sort`), avoiding linked-list pointer chains at runtime.
- **Achievements**: Proved the viability of array-backed record memory layouts in Haskell and introduced $O(1)$ runtime field indexing.
- **Limitations**:
  1. *Constraint Solver Load*: Sorting large symbol lists using closed type families places enormous pressure on GHC's type normalizer, leading to compiler timeouts on records with $>30$ fields.
  2. *Records-Only*: Strictly a product-type library; provides no support for open sum types, polymorphic variants, or hybrid nominal-structural conversions.

### 1.3 `row-types` (Formal Leijen Row Calculus)
- **Architecture**: Implements Daan Leijen's row calculus with first-class row equality, open row tails (`r .\\ "field"`), and symmetric row extension for both records (`Rec`) and variants (`Var`).
- **Achievements**: Elegant, mathematically principled row calculus with true structural row subtyping and first-class labels.
- **Limitations**:
  1. *Stuck Type Families*: Constraint resolution frequently produces stuck, unprovable type equalities when row tails cannot be inferred, resulting in cryptic compiler diagnostics.
  2. *Compile-Time Blowup*: Normalizing row unions and differences without a dedicated typechecker plugin induces substantial typechecker overhead on large schemas.

### 1.4 `extensible` (Poly-Kinded Multi-Paradigm Extensibility)
- **Architecture**: A comprehensive library providing extensible records (`Record`), extensible variants (`Variant`), and extensible effect handlers using type-level natural numbers and custom type-level combinators (`(:*)`, `(:|)`).
- **Achievements**: Extremely powerful and versatile; unified records and variants earlier than almost any other Haskell library.
- **Limitations**:
  1. *High Cognitive Overhead*: Relies on a heavily idiosyncratic internal DSL, custom operators, and category-theoretic abstractions that deter mainstream adoption.
  2. *Compile-Time Instance Selection*: Computation is embedded inside instance head normalization, inducing significant compile-time cost on high-arity structures.

### 1.5 `open-adt` & `world-peace` (Open Sums & Open Unions)
- **Architecture**: Lightweight open variant and coproduct libraries (`OpenUnion`, `Union`) attempting to solve the Expression Problem and avoid nested `Either` trees without full row-calculus machinery.
- **Achievements**: Made open sum types practical for small coproducts and basic error handling.
- **Limitations**:
  1. *Peano Tag Traversals*: Decomposing or matching constructors typically requires linear $O(N)$ tag peeling at runtime or recursive typeclass induction at compile time.
  2. *Disjoint Representations*: Entirely separate from record mechanisms; did not unify products and sums.

---

## 2. Category 2: High-Arity & Datatype Generics Systems

### 2.1 Standard `GHC.Generics`
- **Architecture**: Built-in GHC datatype generics mapping nominal ADTs to balanced binary trees of metadata wrappers (`M1`), products (`(:*:)`), and sums (`(:+:)`).
- **Limitations at Scale**:
  - *Metadata Explosion*: Types with 50+ fields generate massive binary type trees, inducing $O(2^N)$ compile-time heap allocations and slow compilation.
  - *Runtime Heap Overhead*: Converting to and from `Rep` allocates an intermediate tree of boxed nodes, making generic traversals in hot paths impractical.

### 2.2 `large-records`, `large-anon`, and `large-generics` (Well-Typed / Edsko de Vries)
- **Architecture**: Pioneered the use of flat contiguous arrays (`SmallArray (f Any)`), erased runtime representations (`f Any` with `unsafeCoerce`), and dedicated GHC typechecker plugins (`TcPlugin`) to calculate field offsets at compile time.
- **The Breakthrough**: Proved that compile times for high-arity records can scale strictly linearly ($O(N)$) by bypassing GHC's type-level search entirely and emitting literal array indices directly in Core AST.
- **The Fundamental Limitation**:
  - *Records-Only*: `large-records` and `large-anon` are strictly single-constructor product libraries. Their core representation (`Rep f a = Rep (SmallArray (f Any))`) completely lacks a constructor tag, making it mathematically impossible to represent sum types, open variants, or multi-constructor ADTs.
  - *1D Dictionary Vector*: `large-generics` defines `dict :: Proxy c -> Rep (Dict c) a` as a 1D vector corresponding to the fields of a single constructor.
- **How `polytropos` Advances the Art**:
  - `polytropos` introduces the **four-quadrant collapse**:
    ```haskell
    data Rep (f :: Type -> Type) a = Rep
      {-# UNPACK #-} !Word
      !(SmallArray (f Any))
    ```
  - For a product, the tag is statically `0`; for a sum, the tag is the constructor index.
  - In `polytropos-generics`, dictionary resolution is structured as a **2D dictionary matrix** (`SmallArray (SmallArray (DictAny c))`), where the outer array is indexed in $O(1)$ by the constructor tag, and the inner array provides field dictionaries.
  - Coexistence analysis (D7 Q5 in `POLYTROPOS_DESIGN.md`): `polytropos` maintains an independent row vocabulary rather than inheriting `large-anon`'s record-only types, enabling unified product/sum treatment.

### 2.3 `generics-sop` & `sop-core` (Sums of Products)
- **Architecture**: Datatype generics representing ADTs as an $n$-ary sum (`NS`) of $n$-ary products (`NP`).
- **Comparison**: Provides structural elegance for uniform higher-order mapping, but relies on linked-list type trees (`NP` is a linked list of fields; `NS` is a linked chain of `There` constructors), incurring runtime pointer-chasing and compile-time type-level induction.

---

## 3. Category 3: Algebraic Effect Systems & Extensible Pipelines

Algebraic effect systems are mathematically dual to row polymorphism:
- An **effect environment** (Reader, State, capability bag) is an open product row (`Record`).
- A **freer monad union** (computational commands, resumable exceptions) is an open sum row (`Variant`).

### 3.1 `effectful`
- **Original Architecture**: Fast, static-dispatch effect system using an in-place mutation environment (`Env`). To identify effect positions in the environment, `effectful` originally required either a dedicated typechecker plugin (`effectful-plugin`) or type-level list scanning.
- **The Polytropos Port** (`/home/nyc/src/effectful`, branch `polytropos-port`):
  - Replaces type-level list search with `polytropos` flat open product rows (`RowRep`).
  - `Polytropos.Plugin` solves `FieldIndex` constraints directly to literal slot offsets at compile time, eliminating `effectful-plugin` entirely while maintaining $O(1)$ static environment indexing.

### 3.2 `polysemy`
- **Original Architecture**: Higher-order freer monad using a type-level union (`Union r m a`). Constructor injection (`inj`) and decomposition (`decomp`) relied on type-level natural number search via `polysemy-plugin`.
- **The Polytropos Port** (`/home/nyc/src/polysemy`, branch `polytropos-port`):
  - Replaces the freer union with `polytropos` flat `Rep` variant coproducts.
  - Tag inspection and decomposition (`decomp`) execute in $O(1)$ via literal integer tag comparison, eliminating `polysemy-plugin` and eliminating compiler search stalls.

### 3.3 `kernmantle`
- **Original Architecture**: Clean pipeline architecture for Generalized Arrows and effect tasks, originally implemented using `vinyl` and `large-anon`.
- **The Polytropos Port** (`/home/nyc/src/kernmantle`, branch `polytropos-port`):
  - Migrated from `vinyl`/`large-anon` to `polytropos` `RecordF` Higher-Kinded Data ropes, demonstrating unified record/variant handling in complex arrow pipelines.

---

## 4. Category 4: Language Precedents & Foundational Theory

### 4.1 OCaml: Polymorphic Variants & Row Typing
- **Foundational Work**: Jacques Garrigue (1998, polymorphic variants), Didier Rémy (1989, row variables), Jérôme Vouillon.
- **Core Mechanism**:
  - In OCaml, open and closed variants share the identical internal type representation (`Tvariant { row_fields; row_more; closed; fixed }`). Closedness is purely a property of whether the row tail variable (`row_more`) is unified with `Tnil` or remains an open variable `Tvar`.
  - Structural subtyping (`subtype_row`) checks field/constructor inclusion and emits unification constraints without runtime repackaging.
  - Variant tags (`` `Tag ``) are hashed 31-bit integers computed at compile time, enabling open pattern matching and dynamic dispatch without a global constructor registry.
- **Polytropos Adaptation**:
  - Adopts OCaml's open/closed tail unification semantics (see `docs/notes/OCAML_ROW_TAIL_SUBTYPE_MECHANISM.md`).
  - Synthesizes 64-bit FNV-1a hashes at compile time via `KnownHash` for $O(1)$ constructor dispatch.
  - Advances beyond OCaml by unifying both products and sums into a single unboxed `Word` tag + flat `SmallArray` heap object.

### 4.2 PureScript & Elm
- **PureScript**: Built-in record and row polymorphism with native syntax (`{ name :: String | r }`). In JS codegen, record fields compile to native JS object properties, with row constraints resolved at compile time.
- **Elm**: Extensible records (`{ a | name : String }`) with pure structural subtyping, though deliberately omitting open variants or effect rows.
- **Polytropos Adaptation**: Brings PureScript-like ergonomic row polymorphism to Haskell while compiling to compact C-like contiguous memory arrays rather than dynamic hash tables.

---

## 5. Comprehensive Comparative Matrix

The following matrix contrasts `polytropos` with all major prior Haskell libraries and language precedents:

| System / Library | Target Data Shapes | Runtime Memory Physics | Index / Evidence Solving | Compile-Time Scaling (Core Size) | Error Diagnostics & UX | IDE Support (HLS) |
|---|---|---|---|---|---|---|
| **Standard Haskell ADTs** | Closed nominal products & sums | Unpacked constructor tags + boxed fields | Built-in GHC pattern matching | Linear ($O(N)$) | Excellent (native GHC) | Full native support |
| **`vinyl`** | Extensible products (records) | Linked list of boxed cons cells (`Rec`) | Recursive typeclass search (`RecElem`) | Superlinear ($O(N^{2.8})$ blowup) | Multi-page stuck type family dumps | None (no dot completions) |
| **`superrecord`** | Extensible products (records) | Contiguous `Any` array | Type-level sorting type families (`Sort`) | Heavy solver pressure on $>30$ fields | Cryptic type family mismatch errors | None |
| **`row-types`** | Extensible products & sums | Nested coproduct / product trees | Pure type-level row calculus rewriting | Heavy compile-time normalization | Stuck row equality constraints | None |
| **`extensible`** | Products, variants & effects | Custom poly-kinded tuples | Recursive instance selection loops | Superlinear compile times at scale | Complex internal DSL errors | None |
| **`open-adt` / `world-peace`** | Open sums (variants) | Boxed coproduct wrappers (`OpenUnion`) | Peano natural number type search | Polynomial compile-time scaling | Stuck Peano index constraints | None |
| **`large-records` / `large-anon`** | **Products only** (no sums/variants) | Flat array (`SmallArray (f Any)`) | `TcPlugin` literal slot emission | **Linear ($O(N)$)** | Custom plugin diagnostics | Partial (no open variant support) |
| **OCaml** | Polymorphic variants & object rows | Block tag (sum) vs object table (product) | Compile-time compiler type checker (`subtype_row`) | Linear ($O(N)$) | Clean type error summaries | Full native support (Merlin / OCaml LSP) |
| **`polytropos`** | **Unified Products & Sums** (4 quadrants) | **Unified flat `Rep`** (Word tag + `SmallArray (f Any)`) | **`TcPlugin` literal evidence synthesis** | **Linear ($O(N)$)** (Arm PR: 1.03 exponent; 122× reduction vs type search) | **Human-centric `TypeError` with Levenshtein fuzzy suggestions** | **Full HLS autocompletion, hovers & QuickFixes** |

---

## 6. Epilogue: The Unifying Synthesis

The history of extensible data in functional programming reveals a clear progression:
1. **First-generation (Pure Typeclasses)**: Demonstrated that row polymorphism was expressible in Haskell, but paid an unacceptable price in compilation time ($O(N^{2.8})$), runtime allocation (linked lists), and diagnostic incomprehensibility.
2. **Second-generation (TcPlugins for Large Records)**: Demonstrated that GHC typechecker plugins could eliminate compile-time search blowup and achieve flat array performance, but restricted the breakthrough exclusively to single-constructor records.
3. **`polytropos` (The Unified Generation)**: Unifies the four quadrants of nominal and structural products and sums into a single generic substrate. By combining OCaml's mathematical row typing discipline with flat array memory physics and deterministic `TcPlugin` Core synthesis, `polytropos` delivers:
   - $O(1)$ runtime field and constructor indexing.
   - Linear $O(N)$ compile-time scaling.
   - Human-centric compiler diagnostics with fuzzy typo recovery.
   - First-class IDE tooling integration via Haskell Language Server.

Extensible data in Haskell is no longer an exotic, slow experiment—it is a production-grade engineering reality.
