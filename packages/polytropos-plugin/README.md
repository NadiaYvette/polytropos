# polytropos-plugin

GHC typechecker plugin synthesizing literal dictionaries and $O(1)$ jump tables directly into Core AST for [polytropos](https://github.com/NadiaYvette/polytropos).

## Overview

In traditional Haskell row libraries, solving field offsets or dictionary instances involves either:
1. Recursive type-level search ($O(N)$ or $O(N^2)$ compile-time scaling).
2. Runtime dictionary passing and pointer chasing.

`polytropos-plugin` solves evidence constraints (`FieldIndex`, `ConstructorIndex`, `RowEq`, `RowShow`, `RowEqSum`, `RowShowSum`, `AllFields`) by inspecting the row at compile time and emitting literal slot indices, tags, and dictionary vectors directly into GHC Core AST.

## Usage

Enable the plugin in your `.cabal` file or module:

```cabal
build-depends:
    polytropos-core >= 0.1 && < 0.2
  , polytropos-plugin >= 0.1 && < 0.2

ghc-options: -fplugin=Polytropos.Plugin
```

## Features

- **Literal Offset Resolution**: Solves `FieldIndex @"foo" r` directly to integer slot literals.
- **Literal Tag Resolution**: Solves `ConstructorIndex @"Bar" s` directly to integer constructor tags.
- **Unrolled Core Synthesis**: Direct code generation for record equality (`RowEq`) and formatting (`RowShow`).
- **Human-Centric Error Diagnostics**: Custom `TypeError` reporting with Levenshtein-distance fuzzy field name suggestions when fields or constructors are missing.
- **Cross-GHC Support**: Supports GHC 9.6 through GHC 9.14 via internal compatibility shims.

## Documentation & Repository

- **Main Repository**: [https://github.com/NadiaYvette/polytropos](https://github.com/NadiaYvette/polytropos)
- **Plugin Architecture**: [PLUGIN_INVARIANTS.md](https://github.com/NadiaYvette/polytropos/blob/master/.agents/rules/plugin-invariants.md)

## License

Dual-licensed under `EUPL-1.2 OR Apache-2.0`.
