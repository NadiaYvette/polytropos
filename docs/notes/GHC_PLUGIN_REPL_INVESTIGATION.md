<!--
SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
-->
# Design Note — GHC Plugin Mechanics, GHCi REPL Interactive Pipeline & Upstream Architecture

Date: 2026-10-19  
Status: LIVING NOTE v0.1 · 2026-10-19 — GHC compiler driver analysis, REPL constraints, and upstream contributions  
Related: `POLYTROPOS_DESIGN.md` (decisions D1, D3, §6 why a plugin),
`FIELD_UPDATE_EFFICIENCY_DESIGN.md`, `DOC_STRATEGY.md` (governance).  
Audience: Maintainers, plugin authors, and GHC upstream contributors.

---

## 0. Executive Summary

This note documents the internal GHC compiler driver architecture governing source plugins, typechecker plugins (`TcPlugin`), and the interactive GHCi statement execution pipeline. It provides the definitive technical explanation for why source-plugin syntax (`REC { ... }`, `VAR { ... }`, and `REC_UPD`) operates seamlessly during module compilation (`.hs` files, `:load`, `:reload`) but fails when entered directly at the `ghci>` prompt.

It further details:
1. The root cause and resolution of the GHCi extended-defaulting RTS crash (`internal error: stg_ap_v_ret`) during interactive dot-projections (`u1.name`).
2. Why a `CorePlugin` (`installCoreToDos`) fundamentally cannot bypass the need for source-plugin or GHC interactive pipeline hooks.
3. The exact behavior of GHC's `-package-env` flag and its local package environment discovery mechanism.
4. A concrete roadmap of three upstream GHC/GHCi contributions, including a review of the interactive source plugin implementation in branch `nadia.chambers/interactive-source-plugin-001`.

---

## 1. GHC Driver Architecture: Modules vs. Interactive Statements

In GHC (`compiler/GHC/Driver/Main.hs`, `compiler/GHC/Driver/Main/Interactive.hs`, and `compiler/GHC/Driver/Plugins.hs`), compilation is bifurcated into two separate pathways:

```
[Module Compilation (.hs / :load)]
  Source Text ──► Lexer/Parser ──► HsParsedModule
                                         │
                                         ▼
                             withPlugins parsedResultAction  ◄── [ModSummary present]
                                         │
                                         ▼
                                   tcRnModule (TcM)
                                   ├── withTcPlugins
                                   └── withPlugins renamedResultAction

[Interactive Statement Execution (ghci> ...)]
  Source Text ──► Lexer/Parser ──► GhciLStmt GhcPs / [LHsDecl GhcPs]
                                         │
                                         ▼  (Source plugins BYPASSED: no ModSummary!)
                                   tcRnStmt / tcRnDeclsi (TcM)
                                   └── withTcPlugins (ACTIVE!)
                                         │
                                         ▼
                                     deSugarExpr
                                         │
                                         ▼  (Core simplifier BYPASSED: no installCoreToDos!)
                                  hscCompileCoreExpr ──► ByteCode
```

### 1.1 Full Module Compilation (`hscParse'`)
When compiling a Haskell module from disk or loading a module in GHCi (`:load Main.hs`), GHC constructs a `ModSummary` representing the compilation node. In `compiler/GHC/Driver/Main.hs`:

```haskell
-- GHC.Driver.Main.hscParse'
let applyPluginAction p opts = parsedResultAction p opts mod_summary
hsc_env <- getHscEnv
(ParsedResult transformed msgs) <-
  withPlugins (hsc_plugins hsc_env) applyPluginAction (ParsedResult res ...)
```

The plugin hook signature in `compiler/GHC/Driver/Plugins.hs` is:
```haskell
parsedResultAction :: [CommandLineOption] -> ModSummary -> ParsedResult -> Hsc ParsedResult
```
Here, `parsedResultAction` executes across the full `HsParsedModule` AST. In `polytropos-plugin`, `Polytropos.Plugin.Source` traverses the parsed AST, rewriting `REC { ... }` into nested `insertField` calls, `VAR { ... }` into variant injections, and `REC_UPD` into `setField` calls.

### 1.2 Interactive Statements and Declarations (`hscParsedStmt`, `hscParsedDecls`)
When an expression or declaration is typed into the interactive prompt (`ghci> ...`):
1. `GHCi.UI.runStmt` in `ghc/GHCi/UI.hs` calls `hscParseStmtWithLocation` (or `hscParseModuleWithLocation`).
2. The parser produces a `GhciLStmt GhcPs` (an individual statement) or `[LHsDecl GhcPs]` (declarations).
3. GHC immediately invokes `tcRnStmt` (or `tcRnDeclsi`).
4. **`withPlugins (hsc_plugins hsc_env) parsedResultAction` is completely omitted.**

Because `parsedResultAction` requires a `ModSummary`, and interactive statements have no associated `ModSummary`, GHC historically provided no hook to invoke source plugins on interactive statements.

### 1.3 Consequence for Polytropos Syntactic Markers
In `polytropos`, the syntactic markers are defined as nominal datatypes:
```haskell
data REC = REC deriving (Show, Eq)
data VAR = VAR deriving (Show, Eq)
```
When entered at the `ghci>` prompt without a source plugin pass:
- GHC treats `REC { name = "Alice", ... }` as nominal record construction for `REC`.
- Because `REC` has no nominal fields, the renamer/typechecker rejects it:
  `Constructor ‘REC’ does not have field ‘name’` (or `Not in scope: ‘name’` without `-XDisambiguateRecordFields`).

### 1.4 Why `TcPlugin` Remains Active in GHCi
In contrast to source plugins, typechecker plugins *do* execute during interactive GHCi evaluation. In `compiler/GHC/Tc/Module.hs`:
```haskell
runTcInteractive :: HscEnv -> TcRn a -> IO (Messages TcRnMessage, Maybe a)
runTcInteractive hsc_env thing_inside
  = initTcInteractive hsc_env $ withTcPlugins hsc_env $
    withDefaultingPlugins hsc_env $ withHoleFitPlugins hsc_env $ ...
```
`runTcInteractive` wraps interactive typechecking in `withTcPlugins`. Therefore, all constraint-solving passes in `Polytropos.Plugin` (`FieldIndex`, `ConstructorIndex`, `RowEq`, `RowShow`, `HasField`, `AllFields`, `SubRow`, `SubSum`, and `KnownHash`) execute at the `ghci>` prompt.

---

## 2. The `u1.name` GHCi Defaulting RTS Crash (`stg_ap_v_ret`)

### 2.1 Failure Mechanism
When evaluating an interactive field projection without an explicit type signature at the prompt:
```haskell
ghci> u1 = insertField (Field @"name") ("Alice" :: String) emptyRecord
ghci> u1.name
<interactive>: internal error: stg_ap_v_ret
```

1. **Unbound Type Variable:** GHCi translates `u1.name` into `getField @"name" u1`, generating the constraint:
   `HasField "name" (Record '[ "name" := String ]) alpha`
   where `alpha` is a free, unbound unification variable.
2. **Premature Solution without Unification:** In `Polytropos.Plugin.solveHasField`, the solver verified that `"name"` existed in the row with type `String`. However, it checked:
   ```haskell
   if isClosedType fieldTy && not validTy
     then ... -- emit diagnostic
     else pure $ Left ((EvExpr dictExpr, ct), [])
   ```
   Because `alpha` was not closed (`isClosedType alpha == False`), it took the `else` branch, marking the `HasField` constraint as solved *without unifying `alpha` or emitting an equality constraint*.
3. **Extended Defaulting to Unit:** GHCi wraps bare expressions as `print (u1.name)`. With `HasField` solved, the only remaining constraint on `alpha` was `Show alpha`. Under GHCi's `-XExtendedDefaultRules`, `alpha` defaulted to `()`.
4. **Bytecode STG Mismatch:** The dictionary synthesized by the plugin coerced `Identity "Alice"` (a pointer to a heap closure) into `alpha`. But GHCi compiled `print` expecting `()`. In STG bytecode, evaluating a heap pointer as a 0-arity unpointed unit constructor caused the runtime system to abort with `internal error: stg_ap_v_ret`.

### 2.2 Resolution
In `Polytropos.Plugin.solveHasField`, when `fieldTy` is not closed, the plugin now emits a nominal equality constraint (`mkEqPredRole Nominal fieldTy targetTy`):
```haskell
if validTy
  then pure $ Left ((EvExpr dictExpr, ct), [])
  else if isClosedType fieldTy
    then do
      errCt <- mkTypeErrorCt state loc diagLines
      pure $ Left ((EvExpr dictExpr, ct), [errCt])
    else do
      -- Context type is not closed (e.g. unbound type variable alpha in GHCi):
      -- Emit nominal equality constraint to determine the result type
      -- and prevent GHCi defaulting alpha to ().
      let targetTy = case splitAppTy_maybe fieldTy of
            Just (h, _) | h `eqType` fTy -> fFieldTy
            _                            -> actualFieldTy
      eqEv <- newWanted loc (mkEqPredRole Nominal fieldTy targetTy)
      pure $ Left ((EvExpr dictExpr, ct), [mkNonCanonical eqEv])
```
This forces GHC to immediately solve `alpha ~ String`, enabling interactive dot-projections to print cleanly.

---

## 3. Could a `CorePlugin` Dodge GHC/GHCi Changes?

A recurring question is whether implementing a `CorePlugin` (`installCoreToDos`) could bypass the need to modify GHC or GHCi.

The answer is **no**, for two structural and insurmountable reasons:

### 3.1 Ordering: Fatal Type Errors Precede Core Generation
A `CorePlugin` operates on GHC's Core intermediate representation (`CoreProgram` / `[CoreBind]`), which is synthesized *after* desugaring:
$$\text{Source Text} \xrightarrow{\text{Parse}} \text{HsSyn GhcPs} \xrightarrow{\text{Rename}} \text{HsSyn GhcRn} \xrightarrow{\text{Typecheck}} \text{HsSyn GhcTc} \xrightarrow{\text{Desugar}} \text{Core} \xrightarrow{\text{CorePlugin}} \text{Core}$$

When a user writes `u1 = REC { name = "Alice" }`:
- GHC's renamer and typechecker verify that the constructor `REC` possesses a record field named `name`.
- Because `data REC = REC` has zero nominal fields, GHC emits a fatal type error (`GHC-53822: Constructor ‘REC’ does not have field ‘name’`) and **aborts compilation immediately**.
- GHC halts before desugaring. Core is never generated, and `installCoreToDos` is never invoked.

Haskell's grammar only allows curly-brace record construction on constructors (`ConDecl`), not arbitrary functions. Therefore, syntactic sugar that re-interprets record syntax *must* run at or before the renamer (`parsedResultAction`).

### 3.2 The GHCi Interactive Pipeline Skips the Core Simplifier
Even if an expression were valid Haskell that successfully desugared to Core, GHCi's interactive evaluator in `compiler/GHC/Driver/Main/Interactive.hs` (`hscParsedStmt`) does not run the Core optimization pipeline:
```haskell
-- compiler/GHC/Driver/Main/Interactive.hs:359-369
ds_expr <- ioMsgMaybe $ hoistDsMessage $ deSugarExpr hsc_env tc_expr
liftIO (lintInteractiveExpr (text "desugar expression") hsc_env ds_expr)
let src_span = srcLocSpan interactiveSrcLoc
(hval,_,_) <- liftIO $ hscCompileCoreExpr hsc_env src_span ds_expr
```
`hscParsedStmt` calls `deSugarExpr` and passes `ds_expr` directly to `hscCompileCoreExpr` (bytecode generation). It completely bypasses `hscSimplify`. Because `CorePlugin` hooks are registered as `CoreToDo` passes within `hscSimplify`, **Core plugins are never executed on interactive statements in GHCi**.

---

## 4. GHC Package Environment Resolution Mechanics

In `compiler/GHC.hs`:
```haskell
getCmdLineArg >>= \env -> msum [
    probeNullEnv env
  , probeEnvFile env
  , probeEnvName env
  , cmdLineError env
  ]
```

1. **Why `ghci -package-env .` fails:**
   `probeEnvFile path` checks `doesFileExist path`. Because `.` is a directory, `doesFileExist "."` returns `False`. GHC then looks for a user environment at `~/.ghc/<arch-os-ver>/environments/.`, which also does not exist. It therefore throws:
   `<command line>: Package environment "." not found`
2. **Automatic Environment Discovery:**
   When **no** `-package-env` argument is passed, GHC falls back to:
   ```haskell
   findLocalEnvFile :: MaybeT IO FilePath
   ```
   `findLocalEnvFile` starts in the current working directory and walks up parent directories searching for `.ghc.environment.<arch>-<os>-<ghc-ver>`.
   When working with Cabal, running plain `ghci` (or `cabal repl`) automatically finds and loads the package environment generated by Cabal. If passed explicitly on the command line, the exact file path must be provided:
   `ghci -package-env ./.ghc.environment.x86_64-linux-9.14.1`

---

## 5. Practical REPL Workflows Today

Until interactive source plugin hooks land in upstream GHC, developers can use two workflows:

### 5.1 Interactive Combinator Workflow (At `ghci>` Prompt)
Because `tcPlugin` is fully active interactively, records can be constructed and manipulated at the prompt using core combinators with `#labels`:
```haskell
ghci> :set -fplugin=Polytropos.Plugin -XDataKinds -XOverloadedLabels -XOverloadedRecordDot
ghci> import Polytropos
ghci> u1 = insertField #name "Alice" (insertField #age (30 :: Int) (insertField #active True emptyRecord))
ghci> u1.name
"Alice"
ghci> u1.age
30
ghci> u2 = setField #age 31 u1
ghci> u2.age
31
```

### 5.2 Scratch Module Workflow (Syntactic Sugar)
To use `REC { ... }`, `VAR { ... }`, and `REC_UPD`:
1. Define records in a scratch file (e.g. `Scratch.hs`):
   ```haskell
   module Scratch where
   import Polytropos
   u1 = REC { name = "Alice", age = 30 :: Int, active = True }
   ```
2. Load the file in GHCi:
   ```haskell
   ghci> :load Scratch.hs
   ghci> u1.name
   "Alice"
   ```
   Because `:load` compiles a module, `parsedResultAction` runs and desugars all record expressions.

---

## 6. Upstream GHC/GHCi Contribution Roadmap

### Contribution 1: Interactive Source Plugin Hooks
*Branch:* `nadia.chambers/interactive-source-plugin-001` in `~/src/ghc/` (Commit `769d5fff4c`).  
*Goal:* Add plugin hooks for interactive statements and declarations.

#### Code Review of Commit `769d5fff4c`
1. **Design & Signatures:**
   In `compiler/GHC/Driver/Plugins.hs`:
   ```haskell
   , parsedStmtAction  :: [CommandLineOption] -> GhciLStmt GhcPs -> Hsc (GhciLStmt GhcPs)
   , parsedDeclsAction :: [CommandLineOption] -> [LHsDecl GhcPs] -> Hsc [LHsDecl GhcPs]
   ```
   Default implementations: `\_ -> return`.
   This is idiomatic and matches existing plugin design.

2. **Call Sites:**
   In `compiler/GHC/Driver/Main/Interactive.hs`:
   - `hscParsedStmt`:
     ```haskell
     stmt' <- withPlugins (hsc_plugins hsc_env) parsedStmtAction stmt
     (ids, tc_expr, fix_env) <- ioMsgMaybe $ hoistTcRnMessage $ tcRnStmt hsc_env stmt'
     ```
   - `hscParsedDecls`:
     ```haskell
     decls' <- withPlugins (hsc_plugins hsc_env) parsedDeclsAction decls
     tc_gblenv <- ioMsgMaybe $ hoistTcRnMessage $ tcRnDeclsi hsc_env decls'
     ```
   These are placed exactly where the parsed AST transitions to renaming and typechecking.

3. **Required Fix for Build Failure:**
   In `compiler/GHC/Driver/Main/Interactive.hs`, `withPlugins`, `parsedStmtAction`, and `parsedDeclsAction` are referenced, but `GHC.Driver.Plugins` is not imported.
   Adding the import resolves the build failure:
   ```haskell
   import GHC.Driver.Plugins ( withPlugins, parsedStmtAction, parsedDeclsAction )
   ```
   Importing `GHC.Driver.Plugins` from `GHC.Driver.Main.Interactive` introduces no circular dependencies.

4. **Error Handling Considerations:**
   `parsedResultAction` on modules produces `ParsedResult` containing `PsMessages`. For interactive statements, `Hsc` can log messages via `logDiagnostics` or fail via `throwErrors`. Documenting this convention in `Plugins.hs` will satisfy GHC code review standards.

### Contribution 2: Directory Resolution for `-package-env`
In `compiler/GHC.hs`:
```haskell
probeEnvDir :: FilePath -> MaybeT IO FilePath
probeEnvDir dir = do
  isDir <- liftMaybeT (doesDirectoryExist dir)
  guard isDir
  probeEnvFile (dir </> localEnvFileName)
```
Adding `probeEnvDir` to `getCmdLineArg` allows `-package-env .` or `-package-env <dir>` to resolve intuitively.

### Contribution 3: GHCi Command `:show plugins`
In `ghc/GHCi/UI.hs` (`showCmd`), adding `:show plugins` allows users and developers to inspect active `staticPlugins`, `externalPlugins`, and `loadedPlugins` from `hsc_plugins hsc_env`. Currently, GHCi provides `:show packages` and `:show languages`, but no mechanism to verify plugin activation.
