<!--
SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
-->
Status: POLICY · v1.0 · 2026-10-05 — blessed; see `DOC_STRATEGY.md` §3 for what
blessing certifies and §8 for the authority it transfers.

# Provenance and licensing

What `polytropos` may legitimately take from elsewhere, what it must not, and
where the line falls for the packages we expect to port.

## The short version

`polytropos` builds against `base` and `primitive` and nothing else. It is not
a fork of anything. Where a *design idea* came from is recorded here and in
`docs/registers/PACKAGES.md`. Per-file licence obligations arise only when code
is **copied**, and the obligation is narrow: BSD-3-Clause condition 1 requires
retaining the copyright notice.

## What is actually a derivative work

Copyright protects expression, not method. Three cases, in increasing order of
obligation:

| What we do | Obligation |
| --- | --- |
| Measure a library, benchmark it, read its Core | **None.** Observation is not derivation. |
| Adopt an idea, a representation, an architecture | **None.** Ideas are not copyrightable. |
| Copy source — even a few lines — | Retain the copyright notice (BSD-3 §1). |

So the `large-data` relationship today is entirely in the first two rows. The
benchmark in this repository compiles modules written for this repository; it
reads nothing from `large-data`. Nothing in `polytropos-core` is derived from
`large-records` source. `large-data` is a *sibling checkout* used for
comparison and measurement, not a dependency and not an upstream.

The practical test for a line of code: **if you had to look at it to write
yours, cite it.** That covers copying without lifting verbatim.

## Attribution when a port does copy

Every `large-data` package is BSD-3-Clause, compatible with this
repository's dual `EUPL-1.2 OR Apache-2.0` license, so there is no
incompatibility to negotiate — only a notice to keep. The holder lines differ
per package and are *not* uniform:

```
large-records        Copyright (c) 2022, Well-Typed LLP, Juspay Technologies
                     Pvt Ltd, Monadfix OÜ
large-anon           Copyright (c) 2021, Well-Typed LLP, Juspay Technologies
                     Pvt Ltd
large-generics       Copyright (c) 2022, Well-Typed LLP, Juspay Technologies
                     Pvt Ltd
typelet              Copyright (c) 2021, Well-Typed LLP, Juspay Technologies
                     Pvt Ltd
beam-large-records   Copyright (c) 2021, Well-Typed LLP, Juspay Technologies
                     Pvt Ltd
```

None of those packages puts a copyright header in individual source files, so
there is no existing per-file header to copy forward. If a port lifts code, the
ported file gets the header the upstream file lacked:

```haskell
-- Ported from large-generics, Copyright (c) 2022, Well-Typed LLP,
-- Juspay Technologies Pvt Ltd. BSD-3-Clause.
```

One mechanism discharges this: the per-package `LICENSE` file carries a
`Ported from:` section, and `THIRD_PARTY.md` at the repository root is the
index. A file that is a clean-room reimplementation gets neither, and says so
in `PACKAGES.md`.

## Ports are not forks

The discriminator in `docs/registers/PACKAGES.md` is **how far a package
diverges from upstream**, not whether it started as someone's code. A port
that changes the API to run on polytropos rows can never merge upstream again,
so keeping it as a git fork of theirs buys nothing and costs a second repo, a
pin, and a merge policy. It becomes *our* package, with *our* name, in
`ports/`, with their notice only where we actually took code.

A **fork** (`forks/`) is for a package we keep close to upstream because we
want their fixes. Those we do not develop here, and they are never listed in
`cabal.project` — they are built from their own checkout, by upstream's
project. We are not using submodules; see the note below.

## Why not submodules

The expectation was that most of this repository would end up as submodules
holding forks. That turns out to be the wrong tool for the job:

- Friction scales with exactly the frequency we intend to work at. Retrofitting
  a package to a framework that keeps changing means committing into that
  fork constantly, and each change becomes two commits in two repositories plus
  a pointer bump, forever.
- Every clone needs `--recursive`; a forgotten one produces a mysteriously
  empty build rather than an error.
- Attribution is unaffected either way. A submodule preserves *history*; the
  obligation is to retain a *notice*, which a `LICENSE` section does.

If upstream history is wanted without the two-repository tax, `git subtree add`
keeps it in one repository. But note that for most ports the history is
actively unhelpful — the early commits describe an API that no longer exists.

## Reviewing a port

Before a port lands, three questions:

1. Does any file contain copied upstream code? If yes, does it carry the
   notice?
2. Is the divergence large enough that upstream merges are dead? If yes, it is
   a port, not a fork.
3. Is the package listed in `cabal.project`, `PACKAGES.md`, and
   `THIRD_PARTY.md` as applicable?

## Cross-references

- `docs/registers/PACKAGES.md` — the per-package register.
- `THIRD_PARTY.md` — the attribution index.
- `LICENSE` — this repository's own dual EUPL-1.2 OR Apache-2.0 license.
- `docs/notes/POLYTROPOS_DESIGN.md` §7 Q5 — how polytropos and `large-anon`
  coexist, which is a design question this note does not prejudge.