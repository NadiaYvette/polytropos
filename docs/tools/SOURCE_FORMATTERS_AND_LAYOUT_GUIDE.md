# Source Formatters & Layout Engines Guide

**Milestone:** T8 (`plans/FULL_COMPLETION_ROADMAP.md`)  
**Status:** ACTIVE SPECIFICATION & TOOLING MANUAL  
**Audience:** Haskell Developers, Tooling Maintainers, and Code Reviewers  

---

## 1. Executive Summary & Problem Space

In traditional Haskell codebases, source formatters are designed primarily around nominal record declarations (`data User = User { name :: String }`). Row-polymorphic systems introduce distinctive syntactic constructs that naive formatters risk mangling:

1. **Type-Level Row Lists:**
   Type declarations carrying promoted type-level symbol/type pairs:
   ```haskell
   type UserRow =
     '[ "id" := Int
      , "name" := String
      , "email" := String
      , "active" := Bool
      ]
   ```
   Formatters without leading-comma alignment or list-indentation awareness may collapse these into unreadable single-line expressions or jagged column layouts.

2. **Overloaded Record Dot Projections:**
   Dot access `u.name` and nested paths `u.user.profile.avatar` must not be ambiguous with function composition (`.`).

3. **Anonymous Record & Variant Syntax Markers:**
   Syntactic devices `REC { ... }`, `REC_F { ... }`, `VAR { ... }`, and `REC_UPD` must retain proper brace spacing (`record-brace-space: true`) and record field alignment.

`polytropos` delivers first-class, verified configuration profiles and layout engine integration across all four major Haskell formatters: **Fourmolu**, **Ormolu**, **Brittany**, and **Floskell**.

---

## 2. Supported Formatter Configurations

```
┌────────────────────────────────────────────────────────────────────────┐
│                      Milestone T8 Formatter Matrix                     │
├──────────────┬──────────────┬──────────────────┬───────────────────────┤
│ Fourmolu     │ Ormolu       │ Brittany         │ Floskell              │
├──────────────┼──────────────┼──────────────────┼───────────────────────┤
│ fourmolu.yaml│ Zero-config  │ .brittany.yaml   │ floskell.json         │
│ • Leading    │ • AST-safe   │ • Column-aligned │ • Custom penalties    │
│   commas     │ • Idempotent │ • Indent special │ • Record field align  │
│ • Fixities   │ • Upstream   │ • GHC options    │ • Operator fixities   │
│   (:=, .==)  │   standard   │   forwarding     │                       │
└──────────────┴──────────────┴──────────────────┴───────────────────────┘
```

### 2.1 Fourmolu Configuration ([`fourmolu.yaml`](../../fourmolu.yaml))
Fourmolu provides rich configuration for alignment and leading commas. The project profile specifies:
```yaml
indentation: 2
column-limit: 100
function-arrows: trailing
comma-style: leading
record-style: aligned
import-export-style: diff-friendly
indent-wheres: true
record-brace-space: true
single-constraint-parens: never
single-deriving-parens: always
respectful: true

fixities:
  - "infixr 5 :="
  - "infixr 5 .=="
  - "infixl 8 .#"
```

Key features:
- `comma-style: leading`: Formats multiline row lists with aligned leading commas (`'[ "a" := Int \n , "b" := Bool ]`).
- `record-brace-space: true`: Preserves ergonomic spacing in `REC { ... }` rather than compact `REC{...}`.
- `fixities`: Informs the parser of `(:=)` operator associativity so expressions like `"name" := "Alice"` format without spurious parentheses.

### 2.2 Ormolu Integration
Ormolu is intentionally zero-config and strictly AST-preserving. Ormolu parses files via `ghc-lib-parser` in Haddock mode:
- Guarantees complete idempotence: formatting formatted code produces identical bytes.
- Supports `OverloadedRecordDot` and promoted row lists out-of-the-box.
- Does not mangle `REC`, `VAR`, or `peel` expressions.

### 2.3 Brittany Configuration ([`.brittany.yaml`](../../.brittany.yaml))
Brittany uses `ghc-exactprint` and a document-rendering engine (`bridoc`). The project configuration specifies:
```yaml
conf_version: 1

conf_forward:
  options_ghc:
    - "-XDataKinds"
    - "-XTypeOperators"
    - "-XOverloadedRecordDot"
    - "-XFlexibleContexts"

conf_layout:
  lconfig_cols: 100
  lconfig_indentAmount: 2
  lconfig_indentListSpecial: true
  lconfig_indentWhereSpecial: true
  lconfig_alignmentBreakOnMultiline: true
  lconfig_columnAlignMode:
    tag: ColumnAlignModeMajority
    contents: 0.7
  lconfig_allowHangingQuasiQuotes: true
  lconfig_importColumn: 50
  lconfig_importAsColumn: 50
```

Key features:
- `lconfig_indentListSpecial: true`: Aligns promoted type-level list brackets and items.
- `conf_forward.options_ghc`: Forwards `DataKinds`, `TypeOperators`, and `OverloadedRecordDot` directly to the Brittany GHC frontend.

### 2.4 Floskell Configuration ([`floskell.json`](../../floskell.json))
Floskell provides fine-grained AST alignment and penalty-based line breaking. The project configuration specifies:
```json
{
  "extensions": [
    "BangPatterns",
    "DataKinds",
    "FlexibleContexts",
    "OverloadedRecordDot",
    "OverloadedStrings",
    "TypeOperators"
  ],
  "fixities": [
    "infixr 5 :=",
    "infixr 5 .=="
  ],
  "formatting": {
    "align": {
      "record-fields": true,
      "import-module": true,
      "import-spec": true,
      "limits": [12, 30]
    },
    "indent": {
      "case": 2,
      "do": 2,
      "let": 2,
      "where": 2
    },
    "penalty": {
      "max-line-length": 100
    }
  },
  "language": "GHC2021",
  "style": "base"
}
```

---

## 3. Formatter CLI Runner (`bin/polytropos-format`)

The project provides an executable runner script under [`bin/polytropos-format`](../../bin/polytropos-format):

```bash
# Check formatting of source files against Fourmolu (non-destructive)
bin/polytropos-format --check

# Format files in-place
bin/polytropos-format --apply packages/polytropos-core/src/Polytropos.hs

# Test formatters against the open row test fixtures
bin/polytropos-format --fixtures

# Validate all formatter configuration files
bin/polytropos-format --verify-configs
```

---

## 4. Test Fixtures & AST Preservation

The test fixture module [`formatters/test/FormatFixtures.hs`](../../formatters/test/FormatFixtures.hs) exercises:
- Multi-line type-level row lists (`type UserRow = '[ "id" := Int, ... ]`).
- Open variant coproduct rows (`type StatusVariant = Variant '[ "pending" ':= ... ]`).
- Record dot accessor calls (`u.name ++ " <" ++ u.email ++ ">"`).
- In-place field updates (`setField (Field @"id") (...) u`).
- Pipeline record construction (`insertField (Field @"id") ... $ emptyRecord`).
- Constructor peeling (`peel @"pending"`).

All formatters format this fixture cleanly without parse errors, syntax mutations, or AST corruption.

---

## 5. Editor & HLS Integration

To configure Haskell Language Server (HLS) to use the project configuration in VS Code, Neovim, or Emacs:

```json
{
  "haskell.formattingProvider": "fourmolu"
}
```

HLS will automatically locate `fourmolu.yaml` at the project root and format files on save using the verified `polytropos` rules.

---

## 6. Deterministic Verification Gate

Milestone T8 is deterministically verified via:
```bash
./scripts/tasks/verify-milestone-t8.sh
```

The gate asserts:
1. All four configuration and fixture files exist.
2. Fourmolu formats open row fixtures cleanly.
3. Ormolu formats open row fixtures cleanly.
4. Brittany formats open row fixtures cleanly.
5. `floskell.json` syntax and schema are valid.
6. `bin/polytropos-format --fixtures` exits 0.
7. Core test suite `cabal test polytropos-core:test:polytropos-core-test` passes cleanly.
