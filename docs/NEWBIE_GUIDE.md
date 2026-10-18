# `polytropos` Newbie Quickstart & Token-Conservation Guide

**Audience:** New human contributors and AI coding assistant drivers (Antigravity, Claude Code, Cursor, Aider).  
**Parent Strategy:** [`docs/notes/DOC_STRATEGY.md`](notes/DOC_STRATEGY.md)  
**Corpus Inventory:** [`docs/INDEX.md`](INDEX.md)  
**Interactive Tutorial:** [`docs/TUTORIAL.md`](TUTORIAL.md)  
**Maintainer Guide:** [`docs/MAINTAINER_GUIDE.md`](MAINTAINER_GUIDE.md)  

---

## 0. Learning the Concepts First: Start with `TUTORIAL.md`

If you are new to `polytropos` and want to understand how open records and variants work, read the **5-Lesson Interactive Tutorial** in [`docs/TUTORIAL.md`](TUTORIAL.md):

- **Lesson 1:** Constructing Records (`emptyRecord`, `insertField`, `REC { ... }`)
- **Lesson 2:** Accessing & Updating Fields (`r.field` dot syntax, `setField`, `REC_UPD`)
- **Lesson 3:** Working with Open Variants (`Variant`, `injectVariant`, `VAR { ... }`, pattern matching)
- **Lesson 4:** Structural Subtyping in Practice (`projectRecord`, `widenVariant`, `narrowVariant`)
- **Lesson 5:** Extensible Pipelines & Total Elimination (`eliminateUniform`, `matchVariant`)
- **Addendum A:** Live worked Nanopass compiler pass (`cabal run example-nanopass`)
- **Addendum B:** Resilient Parsing & Error ASTs ("Stope and Winze") (`cabal run example-resilient`)
- **Addendum C:** Relational Database Models & Persistent Schemas (`cabal run example-database`)
- **Addendum D:** Extensible Algebraic Effects & Higher-Kinded Ropes (`cabal run example-effects`)
- **Addendum E:** Federated Context & Memory MCP Server Capstone (`cabal run example-mcp-server`)

Once you are comfortable with the concepts, use this guide for repository navigation and token conservation.

---

## 1. The Core Invariant: Never Dump Whole Modules

In a Haskell codebase with typechecker plugins and extensive Core AST generation, dumping full 500-line source modules into the conversation context wastes 2,500–4,000 tokens per turn and causes the **"lost in the middle" attention collapse**.

Always follow the **Progressive Disclosure Funnel**:

```
Level 0: Global Navigation  (docs/INDEX.md, ./tags)       →   ~10–50 tokens
Level 1: Structural Outline (ast-grep, sg patterns)       →   ~100–250 tokens
Level 2: Targeted Slice     (view_file Start/EndLine)     →   ~200–500 tokens
```

---

## 2. Fast Symbol Navigation (Level 0 — <15 tokens)

Before opening any file, find the symbol's exact location in `./tags`:

```bash
grep -w "^<SymbolName>" tags
```

*Examples:*
```bash
grep -w "^Rep" tags           # packages/polytropos-core/src/Polytropos/Core.hs
grep -w "^RowRep" tags        # packages/polytropos-core/src/Polytropos/Core.hs
grep -w "^solveRowEq" tags    # packages/polytropos-plugin/src/Polytropos/Plugin.hs
grep -w "^fieldAt" tags       # packages/polytropos-core/src/Polytropos/Core.hs
```

This immediately returns the exact file path and line number in $<15$ tokens.

Next, view **only** the relevant lines using `view_file` (e.g. ±20 lines around the symbol definition).

To regenerate the index after adding new functions or types:
```bash
./bin/generate-tags
```

---

## 3. Instant Compiler Verification with Tweag's Tricorder (<50 tokens)

Do **NOT** run `cabal build all` or full test sweeps after small edits. A full cabal build dumps 200–500 lines of terminal logs (~2,500 tokens).

Instead, query the in-memory background GHCi daemon:

```bash
# Query machine-readable compiler errors and warnings in JSON (<50 tokens)
tricorder status --json

# Block until current incremental compilation finishes
tricorder status --wait --json

# Inspect dependency source code directly without downloading tarballs
tricorder source <Module.Name>
```

If your REPL supports the Model Context Protocol (configured via [`.mcp.json`](../.mcp.json) or [`.agents/mcp.json`](../.agents/mcp.json)):
- Call MCP tool `status(wait: true)`.

### Tier 0 POSIX Fallback
If the `tricorder` daemon is not running:
```bash
cabal build all --dry-run   # Quick dependency/plan check
cabal test all              # Full test execution
```

---

## 4. Structural Code Audits with `ast-grep` (<300 tokens)

When refactoring or searching across packages, query the Concrete Syntax Tree directly using `sg`:

```bash
# Find all typeclass declarations
sg -p 'class $CLASS $PARAM where $$$METHODS' packages/

# Find all TcPlugin constraint solvers
sg -p 'solve$NAME state ct cls tys = $$$BODY' packages/

# Find all test cases
sg -p 'testCase $NAME $BODY' packages/
```

---

## 5. Local Search with Contextful

When searching for conceptual topics across notes and code:

```bash
# Query with token-budgeted evidence pack
cxf query "<query>" --budget 2000

# Quick search hits
cxf search "<query>" --limit 10
```

---

## 6. Testing & Quality Gates

Run the test suites:
```bash
# Core representation & eliminator tests (37 tests)
cabal test --jobs=20 polytropos-core-test

# Typechecker plugin smoke tests (54 tests)
cabal test --jobs=20 polytropos-plugin-smoke

# Run the live Nanopass tutorial executable
cabal run --jobs=20 example-nanopass

# Complete workspace suite (14 packages, ~180 tests)
cabal test --jobs=20 all
```

---

## 7. Git Commit Attribution Protocol

Commits must follow the `sarutahiko` attribution schema enforced by `.githooks/commit-msg`:

```
<Imperative subject line>

<Why this change was made in the body>

Assisted-by: <Tool> (<Provider> / <Model>)
Orchestrated-by: <Engine>
```

*Examples:*
- `Assisted-by: Antigravity (Anthropic / claude-4.6-opus)`
- `Assisted-by: Freebuff`

**Inviolable rule:** Never use `Co-authored-by:` or `Signed-off-by:` for AI assistants. Only human developers can certify the DCO.

---

## 8. Interactive REPL Workflows (`cabal repl`, `ghci`, `stack repl`)

Because `polytropos` uses a dual-hook compiler plugin (`-fplugin=Polytropos.Plugin`), it is important to understand how GHC interacts with plugins in REPL sessions:

> [!IMPORTANT] GHC Plugin Invariant: Module Compilation vs. Interactive Prompt
> - **Source Plugin (`parsedResultAction`):** Desugars syntactic sugar (`REC { ... }`, `VAR { ... }`, `REC_UPD`) into core combinators. **GHC only executes source plugins when compiling modules (`.hs` files, `:load`, `:reload`).**
> - **Interactive Prompt (`ghci>`):** Statements typed directly at the interactive prompt (`ghci> ...`) bypass GHC's source plugin hook. Therefore, at the `ghci>` prompt, use the core combinators with `#label` syntax (`insertField #name ...`, `recordField #name ...`, `setField #name ...`), OR define records inside a loaded module (`Scratch.hs`).
> - **Typechecker Plugin (`tcPlugin`):** Runs everywhere—both in modules and at the `ghci>` prompt—solving all row constraints (`FieldIndex`, `ConstructorIndex`, `SubRow`, `SubSum`, `RowEq`, `RowShow`).

### 8.1 In-Tree REPL (`cabal repl`)
The fastest way to test code interactively in this repository:
```bash
# Start GHCi with polytropos and example components preloaded:
cabal repl example-resilient

# Or start a test suite target:
cabal repl polytropos-plugin-smoke
```
Targets with `ghc-options: -fplugin=Polytropos.Plugin` declared in their `.cabal` stanza load the plugin and all modules automatically.

### 8.2 Interactive Prompt Walkthrough (`ghci>`)
At the prompt, use the core combinators with `#labels` (`OverloadedLabels`):
```haskell
ghci> :set -XDataKinds -XTypeApplications -XOverloadedLabels -XOverloadedRecordDot
ghci> import Polytropos

-- 1. Construct an open record using insertField:
ghci> u1 = insertField #name "Alice" (insertField #age (30 :: Int) (insertField #active True emptyRecord))
ghci> :type u1
u1 :: Record '["name" := [Char], "age" := Int, "active" := Bool]

-- 2. Access fields via recordField or dot syntax:
ghci> recordField #name u1
"Alice"
ghci> recordField #age u1
30

-- 3. Functional updates via setField:
ghci> u2 = setField #age 31 u1
ghci> recordField #age u2
31

-- 4. Construct open variants via injectVariant:
ghci> v1 = injectVariant #ok (insertField #code (200 :: Int) emptyRecord)
ghci> :type v1
v1 :: Variant '["ok" := '["code" := Int]]
```

### 8.3 Using Native `REC` / `VAR` / `REC_UPD` via Scratch Modules
If you prefer writing the high-level `REC { ... }` and `VAR { ... }` syntax interactively, place your definitions in a scratch file (e.g. `Scratch.hs`):
```haskell
{-# LANGUAGE DataKinds #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}
module Scratch where

import Polytropos

u1 = REC { name = "Alice", age = 30 :: Int, active = True }
u2 = REC_UPD u1 { age = 31 }
v1 = VAR { ok = REC { code = 200 :: Int, message = "Success" } }
```
Then load it into GHCi:
```haskell
ghci> :load Scratch.hs
[1 of 1] Compiling Scratch ( Scratch.hs, interpreted )
Ok, one module loaded.
ghci> u1.name
"Alice"
ghci> u2.age
31
```
Because `Scratch.hs` is compiled as a module, GHC invokes the source plugin, lowering all syntactic sugar seamlessly!

### 8.4 Downstream Projects (`cabal` & `stack`)
- **Cabal:** In your `.cabal` file, add:
  ```cabal
  build-depends: polytropos-core, polytropos-plugin
  ghc-options:   -fplugin=Polytropos.Plugin
  ```
  Then run `cabal repl`.
- **Stack:** Launch the REPL with the plugin flag:
  ```bash
  stack repl --ghci-options="-fplugin=Polytropos.Plugin"
  ```

---

## 9. IDE Setup & Upstream Toolchain Integrations

For full editor intelligence, row completions, and formal verification:

1. **Haskell Language Server (HLS):**
   Standard HLS does not recognize row-polymorphic dot access (`rec.`). Use the official `polytropos` HLS fork from branch `polytropos-row-completions`:
   - Hosted across 4 public git mirrors and Radicle (see [`docs/developer/UPSTREAM_REPOSITORIES_AND_INTEGRATIONS.md`](developer/UPSTREAM_REPOSITORIES_AND_INTEGRATIONS.md)).
   - Features: full tab autocompletions for record fields and variant constructors, readable hover types (e.g. `Record { name :: String }`), `REC { .. }` wildcard expansion, and typo QuickFixes.
   - Build and install:
     ```bash
     git clone https://github.com/NadiaYvette/haskell-language-server.git -b polytropos-row-completions
     cd haskell-language-server && cabal build exe:haskell-language-server
     ```
2. **Formal Verification & Synthesis:**
   - **LiquidHaskell:** Used out-of-process to verify refinement contracts and memory bounds in `verification/liquid/`.
   - **Synquid:** Used for type-directed synthesis of record adapters in `synthesis/synquid/`.
   - See [`docs/developer/LIQUIDHASKELL_AND_SYNQUID_GUIDE.md`](developer/LIQUIDHASKELL_AND_SYNQUID_GUIDE.md).
3. **Source Formatters (Fourmolu, Ormolu, Brittany, Floskell):**
   No formatter forks are needed. Standard formatters parse `polytropos` code out of the box using configuration profiles in [`rules/formatters/`](../rules/formatters/).
