# Upstream Repositories, Forks & Tool Integrations for Polytropos

**Audience:** Compiler Engineers, Library Maintainers, Tooling Integrators, and Package Authors  
**Location:** `docs/developer/UPSTREAM_REPOSITORIES_AND_INTEGRATIONS.md`  
**Purpose:** An authoritative catalog of external git repositories modified for `polytropos`, explaining *why* each modification was warranted, what branches exist, and how external tools relate to the polytropos ecosystem.

---

## 1. Executive Summary

When building `polytropos`, multiple external repositories across the Haskell ecosystem were evaluated, modified, or integrated:

| Repository | Upstream Role | Polytropos Branch | Modification Nature | Primary Benefit |
|---|---|---|---|---|
| **`haskell-language-server`** | Haskell IDE server | `polytropos-row-completions` | **Source fork** in `ghcide` & plugins | Full IDE autocompletion for row fields, readable hovers, wildcard expansion, typo QuickFixes |
| **`effectful`** | Extensible effects | `polytropos-port` | **Library fork** | $O(1)$ effect dispatch using flat product row (`RowRep`), eliminating `effectful-plugin` |
| **`polysemy`** | Algebraic effects | `polytropos-port` | **Library fork** | $O(1)$ constructor tag `decomp` using flat `Rep` variant coproducts, eliminating `polysemy-plugin` |
| **`kernmantle`** | Arrow / effect pipeline | `polytropos-port` | **Library fork** | Ported from `vinyl`/`large-anon` to polytropos `RecordF` HKD ropes |
| **`synquid`** | Program synthesizer | `nadia.chambers/forward-port-to-ghc-9.14-001` | **Tooling fork** | Forward-ported to GHC 9.14 for type-directed synthesis of row adapters and eliminators |
| **`stan`** | Static analyzer | `main` (with patches) | **HIE compat patches** | GHC 9.14 `.hie` compatibility for performance inspections (STAN-P01–P04) |
| **`retrie`** | Equational refactoring | `xich/912` | **GHC 9.12+ exactprint** | Automated AST-preserving code rewrites (`rules/retrie/*.rules`) |
| **`tricorder`** | Compiler diagnostics | `tasty-spec-fix` | **Daemon & MCP bridge** | Continuous background GHCi daemon with $<50$ token JSON-RPC status |
| **`fourmolu`** / **`ormolu`** / **`brittany`** / **`floskell`** | Source code formatters | *Upstream master* | **Configuration profiles only** (in `rules/formatters/`) | AST-preserving layout without maintaining formatter forks |

---

## 2. Haskell Language Server (`haskell-language-server`)

- **Location:** `/home/nyc/src/haskell-language-server`
- **Branch:** `polytropos-row-completions`
- **Key Commits:**
  - `f0c588d35`: `ghcide: support row polymorphic OverloadedRecordDot completions`
  - `f01e37d81`: `hls: support row hover summaries, open wildcard expansion & typo QuickFixes`

### Why Modification Was Worthy
Prior to this branch, HLS's completion engine in `ghcide` assumed all `OverloadedRecordDot` access was performed on standard nominal Haskell records (`data User = User { name :: String }`). When a developer typed `rec.` on a row-polymorphic record (`Record r` or `RowRep`), HLS offered zero autocompletions. Furthermore, hovering over a record displayed unreadable, internal compiler representations (`RowRep Identity ProductRowT ('[ 'Pair "name" String, ...])`).

### Exact Changes Made
1. **`ghcide` Row Autocompletion (`Development.IDE.Plugin.Completions.Logic`):**
   - Traverses promoted type-level cons lists (`:`) and unwraps type synonyms via `coreView`.
   - Extracts field labels and types from promoted pairs `'(Symbol, Type)` and `polytropos` `Pair Symbol Type`.
   - Queries `identType` from `nodeIdentifiers` (in addition to `nodeType`), resolving variable bindings (e.g. `u.`) to their row types.
   - Corrected guard precedence in `Logic.hs` where uncapitalized record variable prefixes were prematurely discarded.
   - Mapped completion positions back through `PositionMapping` with `lowerRange`, preserving query accuracy on active document edits.
2. **Human-Readable Hover Type Summaries (`Development.IDE.Spans.AtPoint`):**
   - Formats complex internal `RowRep` ASTs into ergonomic representations: `Record { field :: Type, ... }` for products and `Variant < Con :: Type | ... >` for variants.
3. **Open Record & Variant Wildcard Expansion (`hls-explicit-record-fields-plugin`):**
   - Added `OpenRecordWildcardExpansion` and `OpenVariantBranchExpansion` recognizing `REC { .. }` and `VAR { .. }` constructs.
   - Generates code actions expanding wildcards into explicit field puns and branch handlers.
4. **LSP QuickFix CodeActions for Typo Diagnostics (`hls-refactor-plugin`):**
   - Extends `extractRenamableTerms` to parse Levenshtein-distance fuzzy typo suggestions from GHC `TypeError` diagnostics.
   - Offers instant `Replace with ‘...’` QuickFix actions for typos in record fields and variant constructors.

---

## 3. Algebraic & Extensible Effect Systems

### 3.1 `effectful`
- **Location:** `/home/nyc/src/effectful`
- **Branch:** `polytropos-port`
- **Key Commit:** `470e6d7`: `Integrate polytropos-core and polytropos-plugin into effectful`
- **Why Modified:**  
  `effectful` originally tracked effects in an `Eff (es :: [Effect]) a` list, relying on type-level membership evidence solved by `effectful-plugin`. While faster than `freer-simple`, type-level list resolution still added compile-time overhead.
- **Port Architecture:**  
  The effect environment was converted to a polytropos flat product row (`Polytropos.Core.RowRep`). Effect lookups are dispatched via `Polytropos.Plugin`'s literal `FieldIndex` resolution, completely eliminating the need for `effectful-plugin` and providing compile-time $O(1)$ offset lookups into the effect environment array.

### 3.2 `polysemy`
- **Location:** `/home/nyc/src/polysemy`
- **Branch:** `polytropos-port`
- **Key Commit:** `6247540`: `Integrate polytropos-core and polytropos-plugin into polysemy`
- **Why Modified:**  
  `polysemy` represented effect unions using a recursive sum type with linear $O(N)$ peeling during interpretation, necessitating `polysemy-plugin` to avoid exponential compile slowdowns.
- **Port Architecture:**  
  The `Union` data type was replaced with `Polytropos.Core.Rep` variant coproducts. Effect decomp is performed in $O(1)$ by comparing the constructor `Word` tag against the target effect tag, discarding `polysemy-plugin` entirely.

### 3.3 `kernmantle`
- **Location:** `/home/nyc/src/kernmantle` (and `/home/nyc/src/kenmantle`)
- **Branch:** `polytropos-port`
- **Key Commit:** `60b2ddc`: `Integrate polytropos-core and polytropos-plugin into kernmantle`
- **Why Modified:**  
  `kernmantle`'s arrow pipeline originally used `vinyl` extensible records and later considered `large-anon`.
- **Port Architecture:**  
  Converted to `polytropos` `RecordF` Higher-Kinded Data ropes, demonstrating that flat `SmallArray` payloads seamlessly handle higher-kinded profunctor pipelines without generic tree allocations.

---

## 4. Formal Verification & Program Synthesis

### 4.1 `synquid`
- **Location:** `/home/nyc/src/synquid`
- **Branch:** `nadia.chambers/forward-port-to-ghc-9.14-001`
- **Why Modified:**  
  Upstream Synquid was abandoned on older GHC releases (GHC 7.10/8.x). To enable type-directed synthesis of record adapters and variant eliminators on modern codebases, Nadia forward-ported Synquid to GHC 9.14, updating the parser, AST, error reporting, and modern Z3 SMT solver bindings.
- **How Developers Use It:**  
  Used out-of-process via `synthesis/synquid/*.sq` specifications to synthesize pure Haskell functions for width subtyping, permutations, and variant dispatch. See [`LIQUIDHASKELL_AND_SYNQUID_GUIDE.md`](LIQUIDHASKELL_AND_SYNQUID_GUIDE.md).

### 4.2 `liquidhaskell`
- **Location:** `/home/nyc/src/liquidhaskell`
- **Branch:** `develop`
- **Role in Polytropos:**  
  LiquidHaskell is used out-of-process as a refinement typechecker over `verification/liquid/`. Because it is an external verifier, downstream packages do not need a custom fork; they simply verify refinement contracts (`RowPredicates.spec`, `Proofs.hs`, `RowBounds.fq`) using the Z3 solver.

---

## 5. Developer Tools & Why Formatters/Linters Need No Forks

### 5.1 `stan` & `retrie`
- **`stan` (`/home/nyc/src/stan`):** Patched for GHC 9.14 `.hie` compatibility to run inspections `STAN-P01` through `STAN-P04` (catching hot-loop CoW array updates and dead row fields).
- **`retrie` (`/home/nyc/src/retrie` on branch `xich/912`):** Modernized for GHC 9.12+ exactprint to automate equational rewrites (e.g. converting `getField` to `OverloadedRecordDot`).

### 5.2 `fourmolu`, `ormolu`, `brittany`, and `floskell`
Developers frequently wonder if they need a special fork of Fourmolu, Ormolu, Brittany, or Floskell to format code containing row polymorphism.

**The Answer is No:**
- `polytropos` syntax is 100% standard GHC syntax (`-XDataKinds`, `-XTypeOperators`, `-XOverloadedRecordDot`).
- Upstream formatters parse `polytropos` code without any modifications to their source code.
- Instead of forking formatters, downstream packages simply adopt the curated configuration profiles placed in the [`rules/formatters/`](../../rules/formatters/) directory:
  * `rules/formatters/fourmolu.yaml`: Enables `leading` commas and operator fixities (`:=`, `.==`, `.#`).
  * `rules/formatters/.brittany.yaml`: Enables `indentListSpecial` and forwards GHC language extensions.
  * `rules/formatters/floskell.json`: Custom alignment penalties and operator fixities.
  * `rules/formatters/ormolu.md`: Zero-configuration CLI commands.

---

## 6. Guidelines for Downstream Package Authors

If you are developing a package that depends on `polytropos`:

1. **Add Polytropos Dependencies:**
   ```cabal
   build-depends:
       polytropos-core
     , polytropos-plugin
   ghc-options: -fplugin=Polytropos.Plugin
   ```
2. **Use the Polytropos HLS Build for Editor Support:**
   Compile `haskell-language-server` from branch `polytropos-row-completions` in `/home/nyc/src/haskell-language-server` to get full tab autocompletion on row types, readable hovers, and wildcard code actions.
3. **Adopt Rules and Formatter Profiles:**
   Copy the pre-tested configuration files from [`rules/`](../../rules/) into your project repository.
4. **Use Out-of-Process Verification When Needed:**
   Consult [`LIQUIDHASKELL_AND_SYNQUID_GUIDE.md`](LIQUIDHASKELL_AND_SYNQUID_GUIDE.md) to formally prove memory bounds with LiquidHaskell or synthesize row adapters with Synquid.
