{-# LANGUAGE CPP #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE ViewPatterns #-}

#if __GLASGOW_HASKELL__ >= 914
{-# OPTIONS_GHC -Wno-pattern-namespace-specifier #-}
#endif

-- | Source plugin for @polytropos@.
--
-- Desugars ergonomic syntax for row-polymorphic records, open variants,
-- and declaration forms into standard @Polytropos@ runtime combinators
-- before renaming and typechecking:
--
-- 1. __Record Construction:__
--    @REC { x = 1, y = True }@ (bare) and @REC_F { x = Just 1 }@ (HKD)
--    with field punning support.
-- 2. __Variant Injection:__
--    @VAR { Ok = 200 }@ or @VARIANT { Err = "fail" }@.
-- 3. __Record Updates:__
--    @REC_UPD r { x = 42 }@ into 'Polytropos.setField' chains.
-- 4. __Pattern Matching:__
--    @REC { x, y }@ into record view patterns, and
--    @VAR { Tag = pat }@ into variant projection view patterns.
-- 5. __Open Declarations:__
--    @data Person = Person { name :: String, age :: Int } deriving OpenRecord@
--    and @data Status = Active | Inactive String deriving OpenVariant@.
module Polytropos.Plugin.Source
  ( sourcePlugin
  ) where

import Prelude

import Data.Data
  ( Data
  , gmapT
  , Typeable
  , cast
  )
import Data.List
  ( nub
  )
import Data.List.NonEmpty
  ( NonEmpty(..)
  )

import GHC.Plugins
  ( CommandLineOption
  , FastString
  , fsLit
  , Hsc
  , GenLocated(..)
  , unLoc
  , mkRdrQual
  , mkRdrUnqual
  , mkVarOcc
  , mkDataOcc
  , mkModuleName
  , rdrNameOcc
  , occNameString
  , occNameFS
  , moduleNameString
  )

import GHC.Hs.Extension
  ( GhcPs
  )

import GHC.Hs
  ( HsParsedModule(..)
  , HsModule(..)
  , HsExpr(..)
  , Pat(..)
  , HsRecFields(..)
  , HsFieldBind(..)
  , FieldOcc(..)
  , LHsExpr
  , LHsRecField
  , LPat
  , LHsDecl
  , noLocA
  , HsConDetails(..)
  , LImportDecl
  , ImportDecl(..)
  , noAnn
  , noExtField
  , HsDecl(..)
  , TyClDecl(..)
  , HsDataDefn(..)
  , ConDecl(..)
  , DataDefnCons(..)
  , HsDerivingClause(..)
  , DerivClauseTys(..)
  , HsSigType(..)
  , HsType(..)
  )

import Language.Haskell.Syntax.Basic
  ( Boxity(..)
  )

import GHC.Driver.Plugins
  ( ParsedResult(..)
  )

import Polytropos.Plugin.Compat
  ( CompatRecUpdField
  , matchRecordUpd
  , extractRecUpdField
  , pattern PrefixConPat
  , stripHsPar
  , polyLabel
  , mkPolytroposImportDecl
  , mkHsApp
  , mkTupArg
  , mkLambda
  )

{-------------------------------------------------------------------------------
  GHC Notes: Source Plugin Architecture and Rewriting Mechanics
-------------------------------------------------------------------------------

Note [Source Plugin Desugaring Architecture: Syntactic Sugar Before Typechecking]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-source-plugin-arch]
GHC's source plugin hook ('parsedResultAction') operates directly on the untyped,
unrenamed abstract syntax tree ('HsParsedModule') immediately after the parser completes,
prior to the Renamer ('rnExpr') and Typechecker ('tcExpr').

Why desugar at the parsed AST level:
1. Native Syntax Feel:
   Developers write natural record syntax:
     @REC { name = "Alice", age = 30 }@
     @VAR { Ok = 200 }@
     @REC_UPD user { age = 31 }@
   without requiring language extensions that modify the lexical grammar or external
   preprocessors (like CPP or Template Haskell quotes).
2. Elimination of Downstream Complexity:
   By lowering syntactic forms to standard Polytropos combinators ('emptyRecord',
   'insertField', 'setField', 'injectVariant', 'projectVariant', 'recordField') before
   renaming, the GHC Typechecker receives standard Haskell function applications
   and view patterns. The typechecker plugin ('Polytropos.Plugin') can then solve
   the resulting 'FieldIndex', 'ConstructorIndex', and 'SubRow' constraints with
   exact literal evidence.
3. Import Injection:
   Source transformation automatically injects 'import qualified Polytropos as Polytropos'
   into the module's import list ('ensurePolytroposImport'), guaranteeing that all
   generated combinators and types resolve without requiring manual boilerplate imports
   by the user.
4. Source Span Preservation:
   Whenever AST nodes are transformed, annotations and source spans are maintained
   where possible, ensuring that compiler diagnostics and IDE hovers pinpoint the exact
   source locations written by the author.

Note [Open Declarations: Lowering Nominal Declarations to Open Rows]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-open-declarations]
Haskell developers frequently want the ergonomic benefits of declaring a named type
with field names or constructors, but want the resulting values to participate in open,
row-polymorphic operations without boilerplate conversion:

  @data Person = Person { name :: String, age :: Int } deriving OpenRecord@
  @data Status = Active | Inactive String deriving OpenVariant@

GHC's built-in deriving engine would reject 'OpenRecord' and 'OpenVariant' because they
are not built-in deriving strategies. The source plugin solves this via a two-stage process:

Stage 1 (Declaration Harvesting & Scrubbing):
- Scans 'hsmodDecls' for 'DataDecl's containing deriving clauses referencing 'OpenRecord'
  or 'OpenVariant'.
- Extracts the type name and constructor names into 'knownRecs' and 'knownVars'.
- Scrubs (filters out) the 'OpenRecord' and 'OpenVariant' deriving clauses from the AST,
  so GHC's stock deriving engine never sees them.

Stage 2 (Expression and Pattern Interception):
- Expressions:
  * Application of a known record constructor:
    @Person { name = "Alice", age = 30 }@
    is lowered into an open record construction chain:
    @insertField #name "Alice" (insertField #age 30 emptyRecord)@
  * Application of a known variant constructor:
    @Active@ or @Inactive "timeout"@
    is lowered into an open variant injection:
    @injectVariant #Active emptyRecord@
    @injectVariant #Inactive (insertField #_1 "timeout" emptyRecord)@
- Patterns:
  * Pattern matching on @Person { name, age }@ is lowered into a record view pattern.
  * Pattern matching on @Active@ or @Inactive err@ is lowered into a variant view pattern.

Note [Record Update and View Pattern Translation]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-view-patterns]
1. Record Updates:
   Haskell's standard record update syntax @r { x = 42 }@ is notoriously problematic:
   it requires nominal field ownership and cannot change field types.
   Polytropos provides @REC_UPD r { x = 42, y = True }@.
   The plugin intercepts 'RecordUpd' (and its compat variants across GHC versions)
   and folds the updates right-to-left:
     @setField #x 42 (setField #y True r)@
   For HKD records, @REC_UPD_F@ desugars into 'setFieldF' chains.

2. Record Patterns & View Pattern Bundling:
   A pattern like @REC { name = p1, age = p2 }@ cannot be matched with standard data constructors
   because 'Record' is backed by a flat 'SmallArray'.
   The plugin desugars this into GHC View Patterns ('ViewPat'):
   - Single-field match:
     @REC { name = p1 }@  ==>  @(recordField #name -> p1)@
   - Multi-field match:
     Naively creating nested view patterns would inspect the record multiple times.
     The plugin bundles multi-field matches into a single tuple projection lambda:
     @REC { name = p1, age = p2 }@  ==>
     @(\_r -> (recordField #name _r, recordField #age _r)) -> (p1, p2)@
     This projects all requested fields in a single step matching against an unboxed tuple.

3. Variant Patterns:
   @VAR { Ok = p }@ is desugared into:
     @(projectVariant #Ok -> Just p)@
   If the variant's active tag matches '#Ok', 'projectVariant' yields 'Just payload' and
   matching proceeds against 'p'. If the tag does not match, 'projectVariant' yields
   'Nothing', causing GHC to fall through to the next pattern match branch.
-}

{-------------------------------------------------------------------------------
  Top-Level Source Plugin Entry Point
-------------------------------------------------------------------------------}

-- | Top-level entry point for GHC's @parsedResultAction@.
-- Invoked immediately after GHC's parser completes on each source file.
-- See Note [Source Plugin Desugaring Architecture: Syntactic Sugar Before Typechecking] [ref:note-source-plugin-arch]
sourcePlugin :: [CommandLineOption] -> ParsedResult -> Hsc ParsedResult
sourcePlugin _opts res = do
  let pm = parsedResultModule res
  let pm' = transformParsedModule pm
  pure res { parsedResultModule = pm' }

-- | Transforms a parsed module AST through three sequential compiler passes:
-- 1. Declaration Harvesting & Scrubbing: discovers 'OpenRecord' and 'OpenVariant' deriving
--    clauses, registers their nominal constructors, and strips the clauses.
--    See Note [Open Declarations: Lowering Nominal Declarations to Open Rows] [ref:note-open-declarations]
-- 2. Expression Transformation: rewrites 'REC', 'VAR', 'REC_UPD', and nominal constructors
--    into Polytropos runtime function application chains.
-- 3. Pattern Transformation: rewrites 'REC' and 'VAR' patterns into view patterns.
--    See Note [Record Update and View Pattern Translation] [ref:note-view-patterns]
-- 4. Import Management: ensures 'import qualified Polytropos as Polytropos' is present.
transformParsedModule :: HsParsedModule -> HsParsedModule
transformParsedModule pm@HsParsedModule{ hpm_module = L modLoc hsmod } =
  let decls0 = hsmodDecls hsmod
      (knownRecs, knownVars, decls1) = extractAndCleanDeclarations decls0
      decls2 = everywhere (mkT (transformExpr knownRecs knownVars)) decls1
      decls3 = everywhere (mkT (transformPat knownRecs knownVars)) decls2
      hsmod' = hsmod
        { hsmodDecls   = decls3
        , hsmodImports = ensurePolytroposImport (hsmodImports hsmod)
        }
  in pm { hpm_module = L modLoc hsmod' }

{-------------------------------------------------------------------------------
  SYB Combinators (Self-contained Data.Data helpers)
-------------------------------------------------------------------------------}

-- | Casts a transformation function 'b -> b' over any type 'a' satisfying 'Typeable'.
-- Provides lightweight Scrap Your Boilerplate traversal without external library dependencies.
mkT :: (Typeable a, Typeable b) => (b -> b) -> a -> a
mkT f x = case cast x of
  Just y -> case cast (f y) of
    Just x' -> x'
    Nothing -> x
  Nothing -> x

-- | Bottom-up traversal over all subtrees of a data term.
everywhere :: (forall a. Data a => a -> a) -> (forall a. Data a => a -> a)
everywhere f x = f (gmapT (everywhere f) x)

{-------------------------------------------------------------------------------
  Declaration Analysis (OpenRecord & OpenVariant discovery)
-------------------------------------------------------------------------------}

-- | Scans top-level declarations for @OpenRecord@ and @OpenVariant@ deriving clauses,
-- records their names, and strips the clauses so GHC's stock deriving engine does
-- not halt with "Cannot derive OpenRecord" errors.
--
-- See Note [Open Declarations: Lowering Nominal Declarations to Open Rows] [ref:note-open-declarations]
extractAndCleanDeclarations :: [LHsDecl GhcPs] -> ([String], [String], [LHsDecl GhcPs])
extractAndCleanDeclarations decls =
  let (recs, vars, cleanedDecls) = foldr step ([], [], []) decls
  in (nub recs, nub vars, cleanedDecls)
  where
    step (L loc (TyClD x decl)) (rAcc, vAcc, dAcc)
      | DataDecl ext (L _ name) tyvars fixity (HsDataDefn defnExt ctxt mtype mkind cons derivs) <- decl
      , let hasOpenRec = any isDerivingOpenRecord derivs
      , let hasOpenVar = any isDerivingOpenVariant derivs
      = let typeNameStr = occNameString (rdrNameOcc name)
            rAcc' = if hasOpenRec then typeNameStr : rAcc else rAcc
            vCons = if hasOpenVar then extractConNames cons else []
            vAcc' = if hasOpenVar then vCons ++ vAcc else vAcc
            cleanedDerivs = filter (\c -> not (isDerivingOpenRecord c || isDerivingOpenVariant c)) derivs
            defn' = HsDataDefn defnExt ctxt mtype mkind cons cleanedDerivs
            decl' = DataDecl ext (noLocA name) tyvars fixity defn'
        in (rAcc', vAcc', L loc (TyClD x decl') : dAcc)
    step d (rAcc, vAcc, dAcc) =
      (rAcc, vAcc, d : dAcc)

    -- Detects 'deriving OpenRecord' or 'deriving (..., OpenRecord, ...)'
    isDerivingOpenRecord (L _ (HsDerivingClause _ _ (L _ dtys))) =
      hasSigNamed "OpenRecord" dtys
    isDerivingOpenRecord _ = False

    -- Detects 'deriving OpenVariant' or 'deriving (..., OpenVariant, ...)'
    isDerivingOpenVariant (L _ (HsDerivingClause _ _ (L _ dtys))) =
      hasSigNamed "OpenVariant" dtys
    isDerivingOpenVariant _ = False

    hasSigNamed target (DctSingle _ sig) = sigMatches target sig
    hasSigNamed target (DctMulti _ sigs) = any (sigMatches target) sigs
    hasSigNamed _ _ = False

    sigMatches target (L _ (HsSig _ _ (L _ hty))) =
      case hty of
        HsTyVar _ _ (L _ rdr) -> occNameString (rdrNameOcc rdr) == target
        HsAppTy _ (L _ (HsTyVar _ _ (L _ rdr))) _ -> occNameString (rdrNameOcc rdr) == target
        _ -> False
    sigMatches _ _ = False

    -- Extract constructor names from data definition
    extractConNames cons =
      [ occNameString (rdrNameOcc (unLoc conName))
      | L _ cdecl <- case cons of
          DataTypeCons _ cs -> cs
          NewTypeCon c      -> [c]
      , let conName = case cdecl of
              ConDeclH98 { con_name = n } -> n
              ConDeclGADT { con_names = (n :| _) } -> n
              _ -> noLocA (mkRdrUnqual (mkDataOcc "Unknown"))
      ]

{-------------------------------------------------------------------------------
  Expression Rewriting
-------------------------------------------------------------------------------}

-- | Rewrites expressions matching syntactic sugar markers ('REC', 'VAR', 'REC_UPD',
-- 'REC_UPD_F', and nominal constructors deriving 'OpenRecord' / 'OpenVariant') into
-- standard Polytropos library combinator expressions.
--
-- Supported Syntactic Forms:
-- 1. Bare Record Construction:
--    @REC { x = 1, y = True }@ or @Person { name = "Alice", age = 30 }@
--    Lowered into a chain of 'insertField' calls ending in 'emptyRecord'.
-- 2. HKD Record Construction:
--    @REC_F { x = Just 1 }@
--    Lowered into a chain of 'insertFieldF' calls ending in 'emptyRecordF'.
-- 3. Variant Injection:
--    @VAR { Ok = 200 }@ or @VARIANT { Err = "msg" }@
--    Lowered into @injectVariant #Tag val@.
-- 4. Functional Record Update:
--    @REC_UPD r { x = 42 }@ (or @REC_UPD (r { x = 42 })@ or @(REC_UPD r) { x = 42 }@)
--    Lowered into chained @setField #x 42 r@ calls.
-- 5. Open Variant Constructor Application:
--    - Record payload: @Success { val = 200 }@ ==> @injectVariant #Success (REC { val = 200 })@
--    - Prefix payload: @Success val@           ==> @injectVariant #Success val@
--    - Nullary:        @Loading@               ==> @injectVariant #Loading emptyRecord@
transformExpr :: [String] -> [String] -> HsExpr GhcPs -> HsExpr GhcPs
transformExpr knownRecs knownVars expr = case expr of
  -- 1. Record Construction: REC { x = 1, y = True } or Person { x = 1, y = True }
  RecordCon _ext (L _ nm) HsRecFields{ rec_flds = flds }
    | let conStr = occNameString (rdrNameOcc nm)
    , conStr == "REC" || conStr `elem` knownRecs
    -> desugarRecordCon False flds

  -- 2. HKD Record Construction: REC_F { x = Just 1 }
  RecordCon _ext (L _ nm) HsRecFields{ rec_flds = flds }
    | occNameString (rdrNameOcc nm) == "REC_F"
    -> desugarRecordCon True flds

  -- 3. Variant Injection: VAR { Ok = 200 } or VARIANT { Err = "msg" }
  RecordCon _ext (L _ nm) HsRecFields{ rec_flds = flds }
    | let conStr = occNameString (rdrNameOcc nm)
    , conStr == "VAR" || conStr == "VARIANT"
    -> desugarVariantCon flds

  -- 4. Record Update: REC_UPD r { x = 42 } or REC_UPD (r { x = 42 }) or (REC_UPD r) { x = 42 } or REC_UPD_F
  (matchRecordUpd -> Just (stripHsPar -> L _ (HsApp _ (stripHsPar -> L _ (HsVar _ (L _ nm))) r), flds))
    | let nmStr = occNameString (rdrNameOcc nm)
    , nmStr == "REC_UPD" || nmStr == "REC_UPD_F"
    -> desugarRecordUpd (nmStr == "REC_UPD_F") r flds

  HsApp _ (stripHsPar -> L _ (HsVar _ (L _ nm))) (stripHsPar -> L _ (matchRecordUpd -> Just (r, flds)))
    | let nmStr = occNameString (rdrNameOcc nm)
    , nmStr == "REC_UPD" || nmStr == "REC_UPD_F"
    -> desugarRecordUpd (nmStr == "REC_UPD_F") r flds

  -- 5. Open Variant Constructor Application (Lowering nominal forms to Variant)
  -- 5a. Record syntax payload: Success { val = 200 }
  RecordCon _ext (L _ nm) HsRecFields{ rec_flds = flds }
    | let conStr = occNameString (rdrNameOcc nm)
    , conStr `elem` knownVars
    -> let injFn = polyVar "injectVariant"
           lblExpr = polyLabel (fsLit conStr)
           recPayload = noLocA (desugarRecordCon False flds)
       in unLoc (mkHsApp (mkHsApp injFn lblExpr) recPayload)

  -- 5b. Prefix payload application: Success r
  HsApp appExt (L _ (HsVar _ (L _ nm))) arg
    | let conStr = occNameString (rdrNameOcc nm)
    , conStr `elem` knownVars
    -> let injFn = polyVar "injectVariant"
           lblExpr = polyLabel (fsLit conStr)
       in HsApp appExt (mkHsApp injFn lblExpr) arg

  -- 5c. Nullary constructor: Loading (payload is emptyRecord)
  HsVar _ (L _ nm)
    | let conStr = occNameString (rdrNameOcc nm)
    , conStr `elem` knownVars
    -> let injFn = polyVar "injectVariant"
           lblExpr = polyLabel (fsLit conStr)
           emptyFn = polyVar "emptyRecord"
       in unLoc (mkHsApp (mkHsApp injFn lblExpr) emptyFn)

  other -> other

-- | Desugars record construction into a nested fold of 'insertField' calls:
-- @REC { x = 1, y = True }@ ==> @insertField #x 1 (insertField #y True emptyRecord)@
--
-- When 'isHKD' is true, emits 'insertFieldF' and 'emptyRecordF' instead.
-- Supports field punning: @REC { x }@ extracts local variable 'x' as argument.
desugarRecordCon :: Bool -> [LHsRecField GhcPs (LHsExpr GhcPs)] -> HsExpr GhcPs
desugarRecordCon isHKD flds =
  let emptyFn = polyVar (if isHKD then "emptyRecordF" else "emptyRecord")
      insertFnName = if isHKD then "insertFieldF" else "insertField"
      foldStep :: LHsRecField GhcPs (LHsExpr GhcPs) -> LHsExpr GhcPs -> LHsExpr GhcPs
      foldStep fld acc =
        let (lbl, arg) = extractRecField fld
            insFn = polyVar insertFnName
            lblExpr = polyLabel lbl
        in mkHsApp (mkHsApp (mkHsApp insFn lblExpr) arg) acc
  in unLoc $ foldr foldStep emptyFn flds

-- | Desugars variant injection into @injectVariant #Tag val@:
-- @VAR { Ok = 200 }@ ==> @injectVariant #Ok 200@
desugarVariantCon :: [LHsRecField GhcPs (LHsExpr GhcPs)] -> HsExpr GhcPs
desugarVariantCon [] =
  error "Polytropos.Plugin.Source: VAR {} requires a constructor tag (e.g. VAR { Ok = 200 })"
desugarVariantCon (fld : _) =
  let (lbl, arg) = extractRecField fld
      injFn = polyVar "injectVariant"
      lblExpr = polyLabel lbl
  in unLoc (mkHsApp (mkHsApp injFn lblExpr) arg)

-- | Desugars functional record update into a fold of 'setField' calls:
-- @REC_UPD r { x = 42, y = False }@ ==> @setField #x 42 (setField #y False r)@
--
-- When 'isHKD' is true, emits 'setFieldF' instead.
desugarRecordUpd :: Bool -> LHsExpr GhcPs -> [CompatRecUpdField] -> HsExpr GhcPs
desugarRecordUpd isHKD r flds =
  let setFnName = if isHKD then "setFieldF" else "setField"
      foldStep :: CompatRecUpdField -> LHsExpr GhcPs -> LHsExpr GhcPs
      foldStep fld acc =
        let (fs, arg) = extractRecUpdField fld
            setFn = polyVar setFnName
            lblExpr = polyLabel fs
        in mkHsApp (mkHsApp (mkHsApp setFn lblExpr) arg) acc
  in unLoc $ foldr foldStep r flds

-- | Extracts the field label and value expression from a record field node.
-- Handles GHC field punning: if @pun@ flag is set, synthesizes a variable
-- expression referencing the field identifier in local scope.
extractRecField :: LHsRecField GhcPs (LHsExpr GhcPs) -> (FastString, LHsExpr GhcPs)
extractRecField (L _ (HsFieldBind _ (L _ (FieldOcc _ (L _ lbl))) arg pun)) =
  let fs = occNameFS (rdrNameOcc lbl)
      arg' = if pun then noLocA (HsVar noExtField (noLocA lbl)) else arg
  in (fs, arg')

{-------------------------------------------------------------------------------
  Pattern Rewriting
-------------------------------------------------------------------------------}

-- | Rewrites pattern matches on @REC@, @VAR@, and open nominal constructors into
-- GHC View Patterns ('ViewPat').
--
-- See Note [Record Update and View Pattern Translation] [ref:note-view-patterns]
--
-- Desugared Patterns:
-- 1. Record Pattern:
--    @REC { x, y }@ or @Person { name, age }@
--    Lowered into tuple-bundled view patterns via 'desugarRecordPat'.
-- 2. Variant Pattern:
--    @VAR { Ok = p }@
--    Lowered into @(projectVariant #Ok -> Just p)@.
-- 3. Open Variant Constructor Pattern:
--    - Record payload: @Success { val }@ ==> @(projectVariant #Success -> Just (val view pattern))@
--    - Prefix payload: @Success p@      ==> @(projectVariant #Success -> Just p)@
--    - Nullary:        @Loading@        ==> @(projectVariant #Loading -> Just _)@
transformPat :: [String] -> [String] -> Pat GhcPs -> Pat GhcPs
transformPat knownRecs knownVars pat = case pat of
  -- 1. Record Pattern: REC { x, y } or Person { x, y }
  ConPat _ext (L _ nm) (RecCon HsRecFields{ rec_flds = flds })
    | let conStr = occNameString (rdrNameOcc nm)
    , conStr == "REC" || conStr `elem` knownRecs
    -> desugarRecordPat flds

  -- 2. Variant Pattern: VAR { Ok = p } or VARIANT { Err = p }
  ConPat _ext (L _ nm) (RecCon HsRecFields{ rec_flds = flds })
    | let conStr = occNameString (rdrNameOcc nm)
    , conStr == "VAR" || conStr == "VARIANT"
    -> desugarVariantPat flds

  -- 3. Open Variant Constructor Pattern (Lowering nominal constructor patterns)
  -- 3a. Record syntax payload: Success { val }
  ConPat _ext (L _ nm) (RecCon HsRecFields{ rec_flds = flds })
    | let conStr = occNameString (rdrNameOcc nm)
    , conStr `elem` knownVars
    -> let viewExpr = mkHsApp (polyVar "projectVariant") (polyLabel (fsLit conStr))
           justCon  = noLocA (mkRdrUnqual (mkDataOcc "Just"))
           innerPat = noLocA (desugarRecordPat flds)
           justPat  = noLocA $ ConPat noAnn justCon (PrefixConPat [innerPat])
       in ViewPat noAnn viewExpr justPat

  -- 3b. 1-arg prefix pattern: Success r
  ConPat _ext (L _ nm) (PrefixConPat [argPat])
    | let conStr = occNameString (rdrNameOcc nm)
    , conStr `elem` knownVars
    -> let viewExpr = mkHsApp (polyVar "projectVariant") (polyLabel (fsLit conStr))
           justCon  = noLocA (mkRdrUnqual (mkDataOcc "Just"))
           justPat  = noLocA $ ConPat noAnn justCon (PrefixConPat [argPat])
       in ViewPat noAnn viewExpr justPat

  -- 3c. Nullary prefix pattern: Loading
  ConPat _ext (L _ nm) (PrefixConPat [])
    | let conStr = occNameString (rdrNameOcc nm)
    , conStr `elem` knownVars
    -> let viewExpr = mkHsApp (polyVar "projectVariant") (polyLabel (fsLit conStr))
           justCon  = noLocA (mkRdrUnqual (mkDataOcc "Just"))
           wildPat  = noLocA (WildPat noExtField)
           justPat  = noLocA $ ConPat noAnn justCon (PrefixConPat [wildPat])
       in ViewPat noAnn viewExpr justPat

  other -> other

-- | Desugars record pattern matching into GHC View Patterns ('ViewPat').
--
-- Optimization:
-- - Empty pattern @REC {}@ desugars to wildcard ('WildPat').
-- - Single field @REC { x = p }@ desugars to @(recordField #x -> p)@.
-- - Multi-field @REC { x = p1, y = p2 }@ bundles projections into a single tuple lambda:
--   @(\_r -> (recordField #x _r, recordField #y _r)) -> (p1, p2)@
--   This projects all fields in one evaluation pass rather than cascading multiple view patterns.
desugarRecordPat :: [LHsRecField GhcPs (LPat GhcPs)] -> Pat GhcPs
desugarRecordPat [] =
  WildPat noExtField
desugarRecordPat [fld] =
  let (lbl, p) = extractRecPatField fld
      viewExpr = mkHsApp (polyVar "recordField") (polyLabel lbl)
  in ViewPat noAnn viewExpr p
desugarRecordPat flds =
  let (lbls, pats) = unzip (map extractRecPatField flds)
      rVar         = mkRdrUnqual (mkVarOcc "_r")
      rExpr        = noLocA (HsVar noExtField (noLocA rVar))
      mkProj lbl   = mkHsApp (mkHsApp (polyVar "recordField") (polyLabel lbl)) rExpr
      tupExpr      = noLocA $ ExplicitTuple noAnn (map (mkTupArg . mkProj) lbls) Boxed
      rPat         = noLocA (VarPat noExtField (noLocA rVar))
      lamExpr      = mkLambda [rPat] tupExpr
      tupPat       = noLocA $ TuplePat noAnn pats Boxed
  in ViewPat noAnn lamExpr tupPat

-- | Desugars variant pattern matching into @(projectVariant #Tag -> Just p)@:
-- @VAR { Ok = p }@ ==> @(projectVariant #Ok -> Just p)@
--
-- If the runtime tag matches '#Ok', 'projectVariant' returns 'Just payload' and
-- succeeds; otherwise it returns 'Nothing' and pattern matching falls through.
desugarVariantPat :: [LHsRecField GhcPs (LPat GhcPs)] -> Pat GhcPs
desugarVariantPat [] =
  error "Polytropos.Plugin.Source: VAR {} pattern requires a constructor tag"
desugarVariantPat (fld : _) =
  let (lbl, p)   = extractRecPatField fld
      viewExpr   = mkHsApp (polyVar "projectVariant") (polyLabel lbl)
      justCon    = noLocA (mkRdrUnqual (mkDataOcc "Just"))
      justPat    = noLocA $ ConPat noAnn justCon (PrefixConPat [p])
  in ViewPat noAnn viewExpr justPat

-- | Extracts the field label and sub-pattern from a record pattern field node.
-- Supports field punning: @REC { x }@ binds to pattern variable 'x'.
extractRecPatField :: LHsRecField GhcPs (LPat GhcPs) -> (FastString, LPat GhcPs)
extractRecPatField (L _ (HsFieldBind _ (L _ (FieldOcc _ (L _ lbl))) p pun)) =
  let fs = occNameFS (rdrNameOcc lbl)
      p' = if pun then noLocA (VarPat noExtField (noLocA lbl)) else p
  in (fs, p')

{-------------------------------------------------------------------------------
  Helper Functions
-------------------------------------------------------------------------------}

-- | Synthesizes a qualified RdrName expression: @Polytropos.<identifier>@.
-- Ensures that transformed expressions reference canonical Polytropos symbols
-- regardless of userland import shadowing.
polyVar :: String -> LHsExpr GhcPs
polyVar occ = noLocA (HsVar noExtField (noLocA (mkRdrQual (mkModuleName "Polytropos") (mkVarOcc occ))))

-- | Ensures that @import qualified Polytropos as Polytropos@ is present in the module's imports.
-- Injected automatically during 'transformParsedModule' so generated combinators resolve cleanly.
ensurePolytroposImport :: [LImportDecl GhcPs] -> [LImportDecl GhcPs]
ensurePolytroposImport imps =
  if any isPolytroposImport imps
    then imps
    else mkPolytroposImportDecl : imps
  where
    isPolytroposImport (L _ ImportDecl{ ideclName = L _ modNm }) =
      moduleNameString modNm == "Polytropos"
    isPolytroposImport _ = False
