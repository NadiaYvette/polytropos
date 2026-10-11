# Compile-time cost of extensible variants

This directory answers one question, asked before committing to the
variant-record plan (`Hybrid Nominal-Structural Haskell Records.md`, an
untracked draft that lived at the root of the `large-data` worktree and is not
part of this repository):

> The plan asserts that extensible variants need a TcPlugin because GHC's
> handling of sums is O(N²), the same way records are. **Is that true?**

The answer is **no for sums, yes for the structural interface** — and the
distinction changes which design is worth building.

## Arms

All arms are generated modules with a fixed 3-field payload `Bench.Payload.P`,
parameterised by N (10 … 100), each with N use sites so the work is forced
into Core. Measured with GHC 9.14.1, `-O0`, `-w`.

| arm | what it is |
|---|---|
| **R** | plain record, N fields, stock `Show`/`Eq`. Intended as a positive control. |
| **A** | plain `data` with N constructors, stock `Show`/`Eq`, full case analysis. |
| **C** | structural variant (`Bench.StructVariant`): runtime tag + `Any` payload, tag found by a **type-level search** of the row. N distinct searches against the same row. |
| **L** | identical to C, but the tag is a **literal** — i.e. exactly what a TcPlugin emits. |
| **P** | structural variant with **`Polytropos.Plugin`**: tag solved at compile time via `ConstructorIndex`. Real-world verification of arm L. |
| **PR** | open record with **`Polytropos.Plugin`**: `Record r` with native `OverloadedRecordDot` (`HasField` solved by plugin). |

C and L differ *only* in how the tag is obtained, so `C / L` isolates precisely
what a plugin buys theoretically, while **P** and **PR** demonstrate what `polytropos`
delivers in practice.

## Results

Core size proxy = non-blank lines in `-ddump-ds-preopt` for the generated
module. "exponent" = least-squares slope of log(Core) against log(N).

```
arm                                          N=10        N=100       x  exponent   RSS@100
R   record (control)                          572         6070     11x      1.04      208M
A   plain sum                                 774         6487      8x      0.93      194M
C   structural, type-level search            3597      2081480    579x      2.80      804M
L   structural, literal tags (plugin target)  349         3591     10x      1.02      192M
P   structural, Polytropos.Plugin solved      941        17066     18x      1.28      290M
PR  record, Polytropos.Plugin dot-syntax      535         5602     11x      1.03      246M
```

The Core columns (`ds_preopt`, `simpl`) are deterministic: a from-scratch
re-run reproduces line counts exactly. They are meaningful only with the
same compiler flags — see *Reproducibility* below.

The other two columns are measurements of a real process and are **not**
reproducible. Peak RSS is the best of three runs; across independent full runs
it drifts by up to about 2%, and wall-clock by more. Treat both as indicative
of magnitude, never as a digit. Every conclusion drawn below rests on the Core
columns, which is why the RSS column is labelled only to the megabyte.

Plugin benefit against unassisted type-level search (`C / P`), grows as roughly N^1.5:

```
  N= 10     4x        N= 60    59x
  N= 20    10x        N= 70    74x
  N= 40    32x        N=100   122x
```

## Findings

1. **Plain sums are already linear** (arm A, exponent 0.93). The plan's
   premise — that large *sums* are quadratically expensive in Core, and hence
   need a plugin — does not hold on GHC 9.14. The quadratic blowup that
   `large-records` exists to fix is specific to records, and arm R shows even
   that is linear now for a plain record with stock deriving. (The historical
   blowup involved field selectors, `HasField`/record-dot and RDP; this arm
   does not exercise those, so it is a weaker control than intended — see
   *Caveats*.)

2. **The structural interface is what is expensive.** Arm C grows as
   ≈ N^2.8. At N=100 it needs ~2.08M lines of pre-optimisation Core and
   ~804 MB RSS, against ~193 MB for a plain sum — roughly 4× the memory for
   320× the Core.

3. **A plugin more than pays for itself.** Arm L, which is arm C with the
   search replaced by a constant, is *cheaper than a plain Haskell sum*
   (0.45–0.55× arm A across the range) and uses less memory than any other arm. So a
   structural variant with plugin-computed indices is strictly the cheapest
   option measured — but only because the plugin removes the search.

4. **The blowup is a typechecker cost, not a runtime cost.** Post-optimisation
   Core (`-ddump-simpl`) is linear for *every* arm (arm C: 637 → 6,216 lines; arm P: 506 → 5,876 lines).
   The type-level search leaves a large trace in `ds-preopt` and disappears
   entirely after simplification. It costs compile time and memory; it does not
   cost anything at run time.

5. **Real-world `Polytropos.Plugin` scales linearly and beats nominal records.**
   - **Variant (Arm P):** Slashes N=100 pre-optimisation Core from 2,081,480 lines (Arm C)
     down to 17,066 lines (**122× reduction**), and peak memory from 804 MB down to 290 MB.
     Post-optimisation Core (`simpl`) is 5,876 lines — even smaller than plain sum Arm A (5,945 lines).
   - **Record (Arm PR):** Native `OverloadedRecordDot` on `Record r` solved by `Polytropos.Plugin`
     scales with an exponent of 1.03, requiring **less Core than standard nominal Haskell records**
     (5,602 lines vs 6,070 lines for Arm R) with peak RSS essentially identical to plain records (246M vs 208M).

## What this implies for the plan

- "Extensible large variants need a plugin because sums are O(N²)" —
  **disproved**. Do not build a plugin to make sums fast; they already are.
- "A structural/row-polymorphic variant needs a plugin" — **confirmed, and
  strongly so**. Without one, a 100-constructor structural variant isa non-starter (2M Core lines, 804 MB). This is the real justification for a
  TcPlugin, and it is the *same* justification `large-anon` already has for
  `RowHasField`/`SubRow`.
- Therefore the cheapest first milestone is **S2**: a closed nominal sum with a
  plugin-synthesised structural *view*. The sum itself is free (arm A); only
  the row-polymorphic accessors need the plugin, and that is a small,
  well-understood surface — much smaller than a new `Variant` type with its own
  `Show`/`Eq`/JSON/eliminator story.
- Note that the `Show`/`Eq`/`JSON` story is *not* inherited from
  `large-generics`: its `Rep` is `newtype Rep f a = Rep (SmallArray (f Any))`
  — a flat, positional array for a **single** constructor — its `Metadata`
  carries one `recordConstructor :: String` and one `recordSize`, its `Generic`
  class methods (`from`/`to`, `MetadataOf :: [(Symbol, Type)]`) are all
  product-shaped, and `:+:` occurs in no file in the package. `SOP.hs` bridges
  to `generics-sop` products only (`fromSOP` takes an `NP`, never a `Sum`).
  So a variant needs its own tag and per-constructor shape, i.e. a parallel
  abstraction beside `Rep` — real work, and worth budgeting for. (This affects
  the *product* side only; it does not change any measurement above.)
- The full monorepo restructure (plan §1) and the `Isomorphic` hybrid layer
  (plan §5) remain unjustified by any measurement here. §5 in particular rests
  on a premise that is false about the current code: `large-records` nominal
  records are real Haskell products whose `toVector`/`fromVector` round-trip
  through a **list** of `Any` (an O(n) copy), and `Anon.Record` is a
  two-constructor sum `NoPending | HasPending` with a `Diff`. Neither is a
  bare `SmallArray# Any`, so no single `unsafeCoerce` relates them.

## Caveats

- The record arm (R) failed to reproduce the historical `large-records`
  quadratic blowup, so it does not serve as a positive control. Arms A and C
  do serve that role for each other: the same metric, the same N range, one
  linear and one superlinear.
- Arm C's exact exponent (~2.8) is an artefact of this particular encoding,
  which does two type-level searches per constructor (`Idx` and `Pld`) and
  accumulates with unary `Nat` addition. A better encoding would lower the
  exponent. It would not change the qualitative result, because arm L differs
  only in substituting a literal for the search.
- Wall-clock time did not separate the arms at these sizes (all 110–190 ms,
  dominated by GHC startup); peak RSS is the more reliable compile-time signal
  here. For a stronger timing signal, raise the N range and subtract a
  baseline-module compile.
- Everything is measured on one GHC (9.14.1) at `-O0`. The existing
  `large-records-benchmarks/report` numbers were taken on 8.8.4/8.10.7, so
  absolute values are not comparable across the two — only the shape of each
  curve is meaningful.

## Reproducing

```sh
cd benchmark/variants
python3 gen/gen.py gen/out      # generate the modules
python3 run/measure.py          # compile each in isolation, write results.csv
```

`run/measure.py` takes the min wall time over 3 runs and the max peak RSS
(via `/usr/bin/time`), and counts Core lines from `-ddump-to-file` output.
Note that GHC derives dump-file paths from the *source* path, so `measure.py`
runs `ghc` with `cwd` set to this directory and passes relative paths.

### Reproducibility

`measure.py` passes **`-package-env -`** to every `ghc` invocation, and that
flag is load-bearing. Without it GHC picks up a `.ghc.environment.*` file from
any ancestor directory, which suppresses the `ghc-internal:` unit-id
qualification in Core. Shorter names mean fewer wrapped lines, so the *same
program* measures about 7% smaller purely because of where the checkout sits:

```
  arm A, N=10, with an ambient environment file      830 lines
  arm A, N=10, with -package-env -                   774 lines
```

Since the metric is a count of *lines*, it is sensitive to the pretty-printer's
line width, and line width is sensitive to how qualified the printed names are.
An earlier revision of these results was measured without the flag and was
therefore not reproducible across directories; every figure in the table above
was re-measured with it. If you re-run and get numbers that disagree with the
table, check that flag first.

`benchmark/` sits inside this repository rather than in a `cabal.project`, so
that `cabal build all` at the top level never compiles it. Each arm must be
built at `-O0` and in isolation for the comparison to mean anything, and a
cabal `-O1` build would quietly invalidate the whole harness.

### Checking a re-run against this table

`results.csv` in the repository is the run the table above was computed from. A
fresh `measure.py` will *not* reproduce that file byte for byte, and should not
be expected to: the `wall_ms` and `rss_kb` columns vary between runs. What must
reproduce is the Core. Compare those two columns only:

```sh
python3 - <<'EOF'
import csv
new = list(csv.DictReader(open("results.csv")))
import subprocess
old = list(csv.DictReader(subprocess.run(
    ["git", "show", "HEAD:benchmark/variants/results.csv"],
    capture_output=True, text=True).stdout.splitlines()))
bad = [(a["arm"], a["n"]) for a, b in zip(old, new)
       if a["ds_preopt"] != b["ds_preopt"] or a["simpl"] != b["simpl"]]
print("Core mismatches:", bad or "none")
EOF
```

`Core mismatches: none` is the pass condition. If it lists rows, a flag
changed — check `-package-env -` first, then `-O0`.
