# Changelog for polytropos-core

## 0.1.0.2 — 2026-10-21

- Coordinated release across all 20 Polytropos packages, benchmarks, and examples.
- Comprehensive worked examples added to `polytropos-docrecords` and `polytropos-reader-soup`.
- Inclusion of `polytropos-dhall` package in ecosystem release.

## 0.1.0.1 — 2026-10-20

- Performance optimization: eliminate lingering list conversions in peeling, projection and injection.
- Repertoire expansion: coordinate release with `polytropos-profunctors` and `polytropos-reader-soup`.

## 0.1.0.0 — Initial Release

- Core row vocabulary: `Row`, `SumRow`, `ProductRow`, `Pair((:=))`
- Unified flat runtime representation: `Rep (f :: Type -> Type) a` combining a runtime tag and `SmallArray` payload
- First-class evidence classes: `FieldIndex`, `ConstructorIndex`, `RowEq`, `RowShow`, `RowEqSum`, `RowShowSum`, `AllFields`
- Primitive operations: `emptyRecord`, `insertField`, `getField`, `setField`, `injectVariant`, `matchVariant`, `projectRecord`, `restrictRecord`
- Hybrid monadic and pure eliminators with $O(1)$ jump table dispatch: `eliminateUniform`, `eliminateUniformM`, `eliminate`, `eliminateM`, `peel`, `peelF`
- Higher-Kinded Data support: `RecordF`, `VariantF`
- SIMD and unrolled copy operations for record updates
- Re-exported front-door module `Polytropos`
