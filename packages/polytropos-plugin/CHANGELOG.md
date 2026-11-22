# Changelog for polytropos-plugin

## 0.1.2.0 — 2026-11-22

- Defer `RowEq`, `RowShow`, `RowEqSum`, `RowShowSum` whole-row solvers on open tails and unreduced type families.
- Fix `OpReplace` field ordering preserving declaration order of original row.
- Fix `OpRestrict` lookup reading source field slot indices.
- Unconditionally unwrap synonyms in `parseMergeOp`.
- Gate injected `Polytropos` imports to only modules containing transformed `REC` or `VAR` syntax.
- Properly parenthesize desugared expressions and patterns (`mkHsPar`).
- Persist interactive `OpenRecord` and `OpenVariant` declarations across GHCi prompt turns for GHC 10.1+.
- Enable `-dcore-lint` in smoke tests.

## 0.1.1.0 — 2026-11-18

- Add `KnownMergeMorph` constraint solver for skew Boolean row algebra operations.

## 0.1.0.3 — 2026-11-03

- Add `KnownRowMorph` constraint solver emitting literal `RowMorph` index arrays for static channel permutations.
- Add `FrameWire` constraint solver synthesizing automatic gather and scatter plans for frame-rule register wiring.
- Generalize `ConstructorIndex` solver to poly-kinded constructors (`k -> Type` and `Type -> Type`).

## 0.1.0.0 — Initial Release

- GHC typechecker plugin synthesizing literal dictionaries and $O(1)$ jump tables directly into Core AST
- Solves `FieldIndex` by emitting literal slot index integers
- Solves `ConstructorIndex` by emitting literal tag integers
- Solves `RowEq` and `RowShow` by synthesizing unrolled per-field comparison and formatting routines without inductive search
- Solves `RowEqSum` and `RowShowSum` by synthesizing Core pattern match expressions over constructor tags
- Solves `AllFields` by synthesizing dictionary arrays
- Human-centric compile-time `TypeError` diagnostics with Levenshtein-distance fuzzy field name suggestions
- Multi-GHC compatibility covering GHC 9.6 through GHC 9.14 via `Polytropos.Plugin.Compat`
