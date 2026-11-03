# Changelog for polytropos-plugin

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
