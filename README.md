# polytropos

Row-polymorphic / open ADTs in Haskell: one generic representation for products
and sums, so that "nominal versus structural" becomes a choice about the type
rather than about the value.

**Status: skeleton.** The row vocabulary, the `Rep` representation and the
evidence classes exist and are tested. The TcPlugin and the elimination story do
not — see the open questions in the design note.

## Packages

- `polytropos-core` — rows, `Rep`, evidence classes.

## Design

Read [`docs/notes/POLYTROPOS_DESIGN.md`](docs/notes/POLYTROPOS_DESIGN.md) first.
It records the decisions (D1–D10), the known costs, and what is deliberately
still open.

The empirical case is the measurement harness in the sibling project
`~/src/large-data/large-records-benchmarks/variants/` (a local path, not a
vendored dependency): with compile-time-computed indices a row-polymorphic value
costs *less* to compile than a plain Haskell one; without them it costs
≈N^2.8.

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

Sibling projects referenced by path above are local co-development checkouts,
not dependencies: `polytropos` builds against nothing but `base` and
`primitive`.
