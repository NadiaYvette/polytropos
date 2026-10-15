# polytropos

Row-polymorphic / open algebraic data types (ADTs) and high-performance
matching generics for Haskell.

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

## Relationship to Other Work

`polytropos` is an independent project. It shares a documentation framework with
the `sarutahiko` project but maintains its own naming range, roadmap, and design.

`large-data` (the `large-records` fork) is a co-development reference checkout;
no code is copied from it, and third-party derivations and licenses are tracked
in [`THIRD_PARTY.md`](THIRD_PARTY.md) and [`docs/notes/PROVENANCE.md`](docs/notes/PROVENANCE.md).

## License

This project is dual-licensed under:

- **European Union Public Licence (EUPL) version 1.2** ([`LICENSES/EUPL-1.2.txt`](LICENSES/EUPL-1.2.txt))
- **Apache License, Version 2.0** ([`LICENSES/Apache-2.0.txt`](LICENSES/Apache-2.0.txt))

You may choose to use this work under the terms of either license. See [`LICENSE`](LICENSE) for details.
