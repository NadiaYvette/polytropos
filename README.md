# polytropos

Row-polymorphic / open algebraic data types (ADTs) and high-performance
matching generics for Haskell, bringing the open row typing discipline and
polymorphic variant semantics of OCaml to modern GHC.

`polytropos` collapses the four quadrants of nominal vs. structural products
and sums into **one** generic runtime representation (`Rep`: an unpacked tag
plus a flat `SmallArray` of payload slots). Moving between nominal and
structural data becomes an erased choice at the type level rather than an
impedance mismatch at runtime.

## The Name

The library takes its name from the opening verse of Homer's *Odyssey* (1.1):

> ἄνδρα μοι ἔννεπε, μοῦσα, **πολύτροπον**, ὃς μάλα πολλὰ  
> πλάγχθη, ἐπεὶ Τροίης ἱερὸν πτολίεθρον ἔπερσεν;  
> — [*Odyssey* 1.1–2](https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.01.0135)  
> ("Tell me, Muse, of that man of many turns, who wandered far and wide, after he had sacked the sacred citadel of Troy...")

In Homeric Greek, **πολύτροπος** (*polýtropos*) literally means "of many turns"
or "much-wandering"—describing Odysseus as adaptable, resourceful, and capable
of turning to many shapes to meet every circumstance without losing his identity.

In this library, *polytropos* describes the data representation: a single,
versatile substrate that turns into products, sums, nominal declarations, and
structural rows without runtime repackaging.

## Motivation & Architecture

### What Is a Row-Polymorphic Open ADT? (In Plain English)

For developers without a background in type theory, the terminology can seem daunting. In practice, it directly solves the rigidity of traditional data types:

1. **Algebraic Data Types (ADTs):** The two universal building blocks of typed data—**Product types** (structs/records where data has field A *and* field B) and **Sum types** (enums/variants where data is constructor A *or* constructor B).
2. **Closed vs. Open:** Traditional Haskell data types are **closed**: declared once with a fixed set of fields or constructors. Adding a field (like an authentication token to a `User`) or adding a variant branch (like a new AST error node) requires defining a brand-new type and writing tedious conversion boilerplate. **Open** types can be constructed, extended, and narrowed on the fly without intermediate wrapper types.
3. **Row Polymorphism:** A "row" is an unordered collection of named fields (like database columns). **Row polymorphism** allows writing functions that operate on *any* record containing at least certain fields (or any variant handling at least certain cases), while the compiler statically tracks and preserves all the *other* remaining fields (`r`). Unlike OOP inheritance, no fields are sliced or erased, and no runtime downcasts are needed.
4. **The Polytropos Difference:** Historically, row polymorphism in Haskell was either painfully slow to compile (quadratic $O(N^{2.8})$ typeclass search) or memory-inefficient (nested `Either` pointer trees). `polytropos` solves this by collapsing products and sums into a **single flat runtime representation** (a tag plus a contiguous array) and using a GHC typechecker plugin to resolve field indices into literal numbers at compile time in $\mathcal{O}(1)$.

In mainstream Haskell, data types are divided into two orthogonal axes:
- **Products vs. Sums**: records and tuples vs. algebraic variants and coproducts.
- **Nominal vs. Structural**: closed, named declarations (`data Person = ...`) vs.
  open, anonymous rows (`Record '[ "name" := String, ... ]`).

Combining these typically requires fragmented libraries: records use nominal
syntax or row libraries like `large-records` / `vinyl`, while extensible variants
rely on nested `Either` trees, `Data.OpenUnion`, or complex GADT coproducts.
Standard type-level list induction or `GHC.Generics` binary trees (`(:*:)`,
`(:+:)`) impose quadratic or cubic compile-time scaling ($O(N^{2.8})$ as measured in
our benchmarks) and substantial memory overhead on large data shapes.

### The Unified Representation

`polytropos` unifies products and sums under a single core representation:

```haskell
data Rep (f :: Type -> Type) a = Rep
  {-# UNPACK #-} !Word
  !(SmallArray (f Any))
```

- **A product is a degenerate sum**: its constructor tag is always statically
  `0`, so the tag folds away, and `repVals` holds the product's fields in row order.
- **A sum holds the active constructor**: `repTag` stores the constructor tag,
  and `repVals` holds the payload slots of that selected constructor.
- **Four quadrants, one representation**:

| Quadrant | Type level | Runtime representation |
|---|---|---|
| Deep nominal product | Closed `data` decl | Tag `0` + flat array of fields |
| Deep structural product | Open row `Row` | Tag `0` + flat array of fields |
| Structural sum of nominal products | `SumRow` of nominal types | Tag `t` + 1 slot |
| Nominal sum of structural products | Closed decl of `Row`s | Tag `t` + flat array of fields |

Because the runtime layout is identical, hybrid nominal-structural conversions
are zero-cost coercions.

### The OCaml Heritage: Polymorphic Variants & Row Typing in GHC

Mainstream Haskell historically lacked a native counterpart to OCaml's battle-tested
row typing system. In OCaml (grounded in the foundational type-theoretic work of Jacques
Garrigue, Didier Rémy, and Jérôme Vouillon), **polymorphic variants** (`[> `Tag of a ]`
and `[< `Tag of a ]`) and object rows demonstrate that extensible data structures do
not require runtime conversion gymnastics, nested `Either` trees, or global constructor
registrations.

`polytropos` deliberately borrows and adapts OCaml's row typing discipline to Haskell:

1. **Unified Open and Closed Row Algebra**:
   In OCaml, open and closed variants share the identical internal type shape
   (`Tvariant { row_fields; row_more; closed; fixed }`). Closedness is simply a property
   of the row tail (`Tnil` vs. an open type variable `Tvar`), rather than an ad-hoc
   phantom flag. In `polytropos`, nominal data types and open structural rows inhabit the
   same row algebra: closed types are the closed boundary of the same algebra open rows
   use, ensuring seamless backward compatibility without artificial wrapper types.

2. **Structural Subtyping via Constraint Synthesis (`subtype_row`)**:
   OCaml's structural subtyping does not perform expensive runtime repackaging; its
   `subtype_row` and `merge_row_fields` algorithms check field/constructor inclusion and
   emit deferred unification constraints. In `polytropos`, the GHC typechecker plugin
   (`Polytropos.Plugin`) performs the equivalent role: it solves `SubRow` (record width
   subtyping) and `SubSum` (variant widening/injection) at compile time, synthesizing
   literal array slices and jump-table mappings with zero runtime search overhead.

3. **Compile-Time Tag Hashing & $O(1)$ Dispatch**:
   OCaml polymorphic variant tags (e.g. `` `Tag ``) are hashed integer tags computed at
   compile time, allowing open pattern matching and dynamic dispatch without a central
   registry. `polytropos` pairs `KnownHash` (compile-time 64-bit FNV-1a hash synthesis)
   with the core `Rep` unpacked `Word` tag to achieve $O(1)$ constructor dispatch and
   jump-table eliminators (`eliminate`, `matchVariant`).

4. **Advancing the Memory Physics**:
   While OCaml maintains separate heap block encodings for variant tags and record objects,
   `polytropos` advances the state of the art by collapsing both products and sums into
   a **single** unboxed `Word` tag + contiguous flat `SmallArray (f Any)` payload layout.

### Techniques from `large-records`, `large-anon`, and `large-generics`

To achieve $O(1)$ runtime efficiency and strictly linear ($O(N)$) compile-time
scaling, `polytropos` builds on the pioneering techniques developed in Well-Typed's
`large-records`, `large-anon`, and `large-generics` suites:

1. **Flat arrays over nested trees**:
   Instead of linked lists or balanced binary trees (`(:*:)`, `(:+:)`), payload
   slots are indexed contiguously in a `SmallArray (f Any)`. Each field is a
   single pointer with zero box overhead.

2. **Erased runtime representation**:
   Field types are erased to `Any` inside the array, with typed access performed
   via `unsafeCoerce` under compiler-guaranteed indices. Soundness is enforced
   by the type system and plugin, not runtime wrappers.

3. **GHC Typechecker Plugin (`TcPlugin`)**:
   Type-level searches over rows during typechecking induce severe compile-time
   slowdowns. The `polytropos` TcPlugin resolves field names (`FieldIndex`) and
   constructor names (`ConstructorIndex`) to compile-time literal slot indices
   and tags directly. It synthesizes dictionary method bodies (such as `RowEq`
   and `RowShow`) as literal expressions without type-level list traversals.

4. **Matching Generics Layer**:
   Following `large-generics`, `polytropos` pairs row-polymorphic variants with
   a datatype-generic programming layer that avoids intermediate generic representations,
   enabling boilerplate-free derivation of serialization, database mappings, and
   codecs at linear compile-time cost.

### High-Leverage Abstraction Synthesis

As explored in our design records and transcripts, `polytropos` is designed to
serve as an architectural foundation alongside:
- **Algebraic Effect Systems** (e.g. `kernmantle`, `effectful`): decoupling the
  *capabilities* of a program (effect rows) from its *data shapes* (variant rows).
- **Profunctor Optics & Codecs**: defining bidirectional readers and writers
  over extensible records and variants with zero synchronization boilerplate.

## Packages

- [`packages/polytropos-core`](packages/polytropos-core): The core representation
  (`Rep`, `RowRep`), type-level vocabulary (`Row`, `SumRow`), field projection and
  mutation, and evidence classes (`RowEq`, `RowShow`, `RowEqSum`, `RowShowSum`,
  `FieldIndex`, `ConstructorIndex`).
- [`packages/polytropos-plugin`](packages/polytropos-plugin): GHC typechecker
  plugin (`Polytropos.Plugin`) that solves row constraints and synthesizes literal
  evidence bodies at compile time. Includes smoke test suite.
- [`benchmark/variants`](benchmark/variants): Empirical compile-time measurement
  harness validating linear scaling against plain GHC data types and type-level search.

Package roles, directory conventions, and reuse rules are documented in
[`docs/registers/PACKAGES.md`](docs/registers/PACKAGES.md).

## Documentation & Reading Paths

- **Newcomer / Contributor**: Start with [`docs/NEWBIE_GUIDE.md`](docs/NEWBIE_GUIDE.md)
  for token-conservation workflows, symbol navigation, and build commands.
- **Maintainer / Lead**: See [`docs/MAINTAINER_GUIDE.md`](docs/MAINTAINER_GUIDE.md)
  for engineering governance, plugin invariants, and the zero-contamination doctrine.
- **Architectural Overview**: Read [`docs/notes/POLYTROPOS_DESIGN.md`](docs/notes/POLYTROPOS_DESIGN.md)
  for canonical architectural decisions (D1–D10) and open questions.
- **Design Review**: Read [`docs/notes/DESIGN_REVIEW_CLAUDE-OPUS-4.6.md`](docs/notes/DESIGN_REVIEW_CLAUDE-OPUS-4.6.md)
  for the comprehensive design review and ecosystem deployment synthesis.
- **Empirical Evidence**: [`benchmark/variants/README.md`](benchmark/variants/README.md)
  demonstrates the compile-time scaling of plugin-emitted literals vs. type-level search.
- **Ideation & Transcripts**:
  - [`docs/transcripts/gemini-powerful-abstraction-techniques-in-haskell.md`](docs/transcripts/gemini-powerful-abstraction-techniques-in-haskell.md):
    Discussion of high-leverage Haskell abstraction patterns (effects, open ADTs, generics, profunctors).
  - [`docs/transcripts/gemini-large-data-hybrid-variant-records-spec.md`](docs/transcripts/gemini-large-data-hybrid-variant-records-spec.md):
    Early transcript exploring hybrid nominal-structural variant records.
- **Theoretical Foundations & Row Algebra**:
  - [`docs/notes/OCAML_BACKWARD_COMPAT_ROW_ALGEBRA.md`](docs/notes/OCAML_BACKWARD_COMPAT_ROW_ALGEBRA.md):
    Deep-dive into OCaml's `ctype.ml` row representation and how backward compatibility is maintained without ad-hoc flags.
  - [`docs/notes/OCAML_ROW_TAIL_SUBTYPE_MECHANISM.md`](docs/notes/OCAML_ROW_TAIL_SUBTYPE_MECHANISM.md):
    Detailed analysis of OCaml's `subtype_row` and `unify_row` tail-merging algorithms.
  - [`docs/notes/ROW_ROLE_JUDGEMENT_SKETCH.md`](docs/notes/ROW_ROLE_JUDGEMENT_SKETCH.md) & [`docs/notes/ROW_ROLE_DEFNS_DRAFT.ott`](docs/notes/ROW_ROLE_DEFNS_DRAFT.ott):
    Formal typing judgements bridging OCaml row algebra with GHC Core role semantics.
- **Developer & Tooling Integration**:
  - [`docs/developer/UPSTREAM_REPOSITORIES_AND_INTEGRATIONS.md`](docs/developer/UPSTREAM_REPOSITORIES_AND_INTEGRATIONS.md):
    Authoritative catalog of upstream repositories modified for polytropos (HLS autocompletions & hovers, effect system ports, toolchain forks, and why formatters need no forks).
  - [`docs/developer/LIQUIDHASKELL_AND_SYNQUID_GUIDE.md`](docs/developer/LIQUIDHASKELL_AND_SYNQUID_GUIDE.md):
    Developer guide for out-of-process LiquidHaskell formal verification contracts and Synquid type-directed program synthesis.
  - [`rules/README.md`](rules/README.md):
    Pre-tested downstream configuration library (Fourmolu, Brittany, Floskell, Ormolu, Stan, HLint, Retrie, Tricorder).
- **Corpus Map**: See [`docs/INDEX.md`](docs/INDEX.md) for full document inventory and reading paths.

## Build & Test

Toolchain: GHC 9.14.1 / Cabal 3.18.

```bash
cabal build all
cabal test all
```

## Relationship to Other Work & Theoretical Precedents

`polytropos` is an independent project. It synthesizes two distinct PL traditions:

1. **OCaml's Row Typing & Polymorphic Variants**: The row algebra, open/closed tail
   mechanics, and structural subtyping discipline are directly informed by Jacques
   Garrigue's polymorphic variants and the OCaml typechecker's `ctype.ml` row unification
   architecture.
2. **Well-Typed's Flat Array Representation**: The runtime memory model, type-erased
   `SmallArray (f Any)` storage, and GHC `TcPlugin` literal synthesis build upon techniques
   pioneered in Well-Typed's `large-records`, `large-anon`, and `large-generics` suites.

It shares a documentation framework with the `sarutahiko` project but maintains its own
naming range, roadmap, and design.

`large-data` (the `large-records` fork) is a co-development reference checkout;
no code is copied from it, and third-party derivations and licenses are tracked
in [`THIRD_PARTY.md`](THIRD_PARTY.md) and [`docs/notes/PROVENANCE.md`](docs/notes/PROVENANCE.md).

## License

This project is dual-licensed under:

- **European Union Public Licence (EUPL) version 1.2** ([`LICENSES/EUPL-1.2.txt`](LICENSES/EUPL-1.2.txt))
- **Apache License, Version 2.0** ([`LICENSES/Apache-2.0.txt`](LICENSES/Apache-2.0.txt))

You may choose to use this work under the terms of either license. See [`LICENSE`](LICENSE) for details.
