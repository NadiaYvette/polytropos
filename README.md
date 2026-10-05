# polytropos

Row-polymorphic / open ADTs in Haskell: one generic representation for products
and sums, so that "nominal versus structural" becomes a choice about the type
rather than about the value.

**Status: skeleton.** The row vocabulary, the `Rep` representation and the
evidence classes exist and are tested. The TcPlugin and the elimination story do
not — see the open questions in the design note.

## Packages

- [`packages/polytropos-core`](packages/polytropos-core) — rows, `Rep`,
  evidence classes.

Directory roles and the rule that decides them (native / port / fork) are in
[`docs/registers/PACKAGES.md`](docs/registers/PACKAGES.md); `ports/` and
`forks/` exist and are empty.

## Design

Read [`docs/notes/POLYTROPOS_DESIGN.md`](docs/notes/POLYTROPOS_DESIGN.md) first.
It records the decisions (D1–D10), the known costs, and what is deliberately
still open.

The empirical case is the measurement harness in
[`benchmark/variants`](benchmark/variants), which lives here: with
compile-time-computed indices a row-polymorphic value costs *less* to compile
than a plain Haskell one; without them it costs ≈N^2.8.

## Build & Test

Toolchain: GHC 9.14 / Cabal 3.18.

```bash
cabal build all
cabal test all
```

## Relationship to other work

`polytropos` is independent. It shares a documentation *skeleton* with the
`~/src/sarutahiko` program but not its naming convention, its register, or its
roadmap. No migration between the two is planned; see design note §7 Q5.

`~/src/large-data` (the `large-records` fork) is a local co-development
checkout, not a dependency and not an upstream: nothing from it is compiled as
part of this project, and no code has been copied from it. The
attribution ledger is [`THIRD_PARTY.md`](THIRD_PARTY.md) and the rules are in
[`docs/notes/PROVENANCE.md`](docs/notes/PROVENANCE.md).
