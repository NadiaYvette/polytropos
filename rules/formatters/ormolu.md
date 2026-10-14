# Ormolu Guide for Polytropos Codebases

[Ormolu](https://github.com/tweag/ormolu) is an opinionated, zero-configuration formatter for Haskell.

## Compatibility with Polytropos

Unlike formatters with extensive styling switches, Ormolu operates with **no configuration file**. It formats code deterministically based on GHC's parsed AST.

`polytropos` was explicitly designed to produce valid, standard GHC syntax that Ormolu formats cleanly without syntax degradation:
1. **Promoted Type-Level Lists (`'[ ... ]`):** Ormolu formats multi-line type lists with consistent indentation.
2. **`OverloadedRecordDot` (`rec.field`):** Ormolu natively understands GHC 9.2+ record dot syntax, preserving field chains without inserting erroneous spaces around dots.
3. **Operators (`:=`, `.==`, `.#`):** Infix constructors and operators format using Ormolu's standard infix spacing rules.

## Recommended Usage

To format your polytropos codebase with Ormolu:

```bash
# In-place formatting
ormolu --mode inplace $(find src app test -name "*.hs")

# CI validation check
ormolu --mode check $(find src app test -name "*.hs")
```

If you require customized comma placement (`leading` comma style) or explicit record field alignment, use [Fourmolu](fourmolu.yaml) instead, which extends Ormolu with configurability.
