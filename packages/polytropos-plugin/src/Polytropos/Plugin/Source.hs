{-# LANGUAGE CPP #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE ViewPatterns #-}

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
  , RawPkgQual(..)
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
  , LHsRecUpdField
  , LPat
  , LHsDecl
  , noLocA
  , LHsRecUpdFields(..)
  , HsConDetails(..)
  , LImportDecl
  , ImportDecl(..)
  , ImportDeclQualifiedStyle(..)
  , IsBootInterface(..)
  , ImportDeclLevelStyle(..)
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
  , mkHsLam
  )

import Language.Haskell.Syntax.Basic
  ( Boxity(..)
  )

import Language.Haskell.Syntax.Expr
  ( HsTupArg(..)
  )

import GHC.Hs.ImpExp
  ( XImportDeclPass(..)
  )

import GHC.Types.SourceText
  ( SourceText(..)
  )

import GHC.Driver.Plugins
  ( ParsedResult(..)
  )

{-------------------------------------------------------------------------------
  Top-Level Source Plugin Entry Point
-------------------------------------------------------------------------------}

-- | Top-level entry point for GHC's 'parsedResultAction'.
sourcePlugin :: [CommandLineOption] -> ParsedResult -> Hsc ParsedResult
sourcePlugin _opts res = do
  let pm = parsedResultModule res
  let pm' = transformParsedModule pm
  pure res { parsedResultModule = pm' }

-- | Transform a parsed module AST.
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

mkT :: (Typeable a, Typeable b) => (b -> b) -> a -> a
mkT f x = case cast x of
  Just y -> case cast (f y) of
    Just x' -> x'
    Nothing -> x
  Nothing -> x

everywhere :: (forall a. Data a => a -> a) -> (forall a. Data a => a -> a)
everywhere f x = f (gmapT (everywhere f) x)

{-------------------------------------------------------------------------------
  Declaration Analysis (OpenRecord & OpenVariant discovery)
-------------------------------------------------------------------------------}

-- | Scan declarations for 'OpenRecord' and 'OpenVariant' deriving clauses,
-- record their names, and strip the clauses so GHC doesn't attempt stock deriving.
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

    isDerivingOpenRecord (L _ (HsDerivingClause _ _ (L _ dtys))) =
      hasSigNamed "OpenRecord" dtys
    isDerivingOpenRecord _ = False

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

transformExpr :: [String] -> [String] -> HsExpr GhcPs -> HsExpr GhcPs
transformExpr knownRecs knownVars expr = case expr of
  -- 1. Record Construction: REC { x = 1, y = True }
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

  -- 4. Record Update: (REC_UPD r) { x = 42 } or REC_UPD (r { x = 42 }) or REC_UPD_F
  RecordUpd _ext (stripHsPar -> L _ (HsApp _ (stripHsPar -> L _ (HsVar _ (L _ nm))) r)) (RegularRecUpdFields _ flds)
    | let nmStr = occNameString (rdrNameOcc nm)
    , nmStr == "REC_UPD" || nmStr == "REC_UPD_F"
    -> desugarRecordUpd (nmStr == "REC_UPD_F") r flds

  HsApp _ (stripHsPar -> L _ (HsVar _ (L _ nm))) (stripHsPar -> L _ (RecordUpd _ r (RegularRecUpdFields _ flds)))
    | let nmStr = occNameString (rdrNameOcc nm)
    , nmStr == "REC_UPD" || nmStr == "REC_UPD_F"
    -> desugarRecordUpd (nmStr == "REC_UPD_F") r flds

  -- 5. Open Variant Constructor Application
  -- 5a. Record syntax: Success { val = 200 }
  RecordCon _ext (L _ nm) HsRecFields{ rec_flds = flds }
    | let conStr = occNameString (rdrNameOcc nm)
    , conStr `elem` knownVars
    -> let injFn = polyVar "injectVariant"
           lblExpr = polyLabel (fsLit conStr)
           recPayload = noLocA (desugarRecordCon False flds)
       in HsApp noExtField (noLocA (HsApp noExtField injFn lblExpr)) recPayload

  -- 5b. Prefix application: Success r
  HsApp appExt (L _ (HsVar _ (L _ nm))) arg
    | let conStr = occNameString (rdrNameOcc nm)
    , conStr `elem` knownVars
    -> let injFn = polyVar "injectVariant"
           lblExpr = polyLabel (fsLit conStr)
       in HsApp appExt (noLocA (HsApp noExtField injFn lblExpr)) arg

  -- 5c. Nullary constructor: Loading
  HsVar _ (L _ nm)
    | let conStr = occNameString (rdrNameOcc nm)
    , conStr `elem` knownVars
    -> let injFn = polyVar "injectVariant"
           lblExpr = polyLabel (fsLit conStr)
           emptyFn = polyVar "emptyRecord"
       in HsApp noExtField (noLocA (HsApp noExtField injFn lblExpr)) emptyFn

  other -> other

-- | Strip enclosing parenthesis expressions.
stripHsPar :: LHsExpr GhcPs -> LHsExpr GhcPs
stripHsPar (L _ (HsPar _ e)) = stripHsPar e
stripHsPar e = e

-- | Desugar record construction into emptyRecord + insertField chain.
desugarRecordCon :: Bool -> [LHsRecField GhcPs (LHsExpr GhcPs)] -> HsExpr GhcPs
desugarRecordCon isHKD flds =
  let emptyFn = polyVar (if isHKD then "emptyRecordF" else "emptyRecord")
      insertFnName = if isHKD then "insertFieldF" else "insertField"
      foldStep :: LHsRecField GhcPs (LHsExpr GhcPs) -> LHsExpr GhcPs -> LHsExpr GhcPs
      foldStep fld acc =
        let (lbl, arg) = extractRecField fld
            insFn = polyVar insertFnName
            lblExpr = polyLabel lbl
        in noLocA $ HsApp noExtField (noLocA (HsApp noExtField (noLocA (HsApp noExtField insFn lblExpr)) arg)) acc
  in unLoc $ foldr foldStep emptyFn flds

-- | Desugar variant injection into injectVariant #Tag val.
desugarVariantCon :: [LHsRecField GhcPs (LHsExpr GhcPs)] -> HsExpr GhcPs
desugarVariantCon [] =
  error "Polytropos.Plugin.Source: VAR {} requires a constructor tag (e.g. VAR { Ok = 200 })"
desugarVariantCon (fld : _) =
  let (lbl, arg) = extractRecField fld
      injFn = polyVar "injectVariant"
      lblExpr = polyLabel lbl
  in HsApp noExtField (noLocA (HsApp noExtField injFn lblExpr)) arg

-- | Desugar record updates into chained setField calls.
desugarRecordUpd :: Bool -> LHsExpr GhcPs -> [LHsRecUpdField GhcPs GhcPs] -> HsExpr GhcPs
desugarRecordUpd isHKD r flds =
  let setFnName = if isHKD then "setFieldF" else "setField"
      foldStep :: LHsRecUpdField GhcPs GhcPs -> LHsExpr GhcPs -> LHsExpr GhcPs
      foldStep (L _ (HsFieldBind _ (L _ (FieldOcc _ (L _ lbl))) arg _)) acc =
        let fs = occNameFS (rdrNameOcc lbl)
            setFn = polyVar setFnName
            lblExpr = polyLabel fs
        in noLocA $ HsApp noExtField (noLocA (HsApp noExtField (noLocA (HsApp noExtField setFn lblExpr)) arg)) acc
  in unLoc $ foldr foldStep r flds

-- | Extract label and argument from record field with punning support.
extractRecField :: LHsRecField GhcPs (LHsExpr GhcPs) -> (FastString, LHsExpr GhcPs)
extractRecField (L _ (HsFieldBind _ (L _ (FieldOcc _ (L _ lbl))) arg pun)) =
  let fs = occNameFS (rdrNameOcc lbl)
      arg' = if pun then noLocA (HsVar noExtField (noLocA lbl)) else arg
  in (fs, arg')

{-------------------------------------------------------------------------------
  Pattern Rewriting
-------------------------------------------------------------------------------}

transformPat :: [String] -> [String] -> Pat GhcPs -> Pat GhcPs
transformPat knownRecs knownVars pat = case pat of
  -- 1. Record Pattern: REC { x, y } or Person { x, y }
  ConPat _ext (L _ nm) (RecCon HsRecFields{ rec_flds = flds })
    | let conStr = occNameString (rdrNameOcc nm)
    , conStr == "REC" || conStr `elem` knownRecs
    -> desugarRecordPat flds

  -- 2. Variant Pattern: VAR { Ok = p }
  ConPat _ext (L _ nm) (RecCon HsRecFields{ rec_flds = flds })
    | let conStr = occNameString (rdrNameOcc nm)
    , conStr == "VAR" || conStr == "VARIANT"
    -> desugarVariantPat flds

  -- 3. Open Variant Constructor Pattern:
  -- 3a. Record syntax: Success { val }
  ConPat _ext (L _ nm) (RecCon HsRecFields{ rec_flds = flds })
    | let conStr = occNameString (rdrNameOcc nm)
    , conStr `elem` knownVars
    -> let viewExpr = noLocA $ HsApp noExtField (polyVar "projectVariant") (polyLabel (fsLit conStr))
           justCon  = noLocA (mkRdrUnqual (mkDataOcc "Just"))
           innerPat = noLocA (desugarRecordPat flds)
           justPat  = noLocA $ ConPat noAnn justCon (PrefixCon [innerPat])
       in ViewPat noAnn viewExpr justPat

  -- 3b. 1-arg prefix pattern: Success r
  ConPat _ext (L _ nm) (PrefixCon [argPat])
    | let conStr = occNameString (rdrNameOcc nm)
    , conStr `elem` knownVars
    -> let viewExpr = noLocA $ HsApp noExtField (polyVar "projectVariant") (polyLabel (fsLit conStr))
           justCon  = noLocA (mkRdrUnqual (mkDataOcc "Just"))
           justPat  = noLocA $ ConPat noAnn justCon (PrefixCon [argPat])
       in ViewPat noAnn viewExpr justPat

  -- 3c. Nullary prefix pattern: Loading
  ConPat _ext (L _ nm) (PrefixCon [])
    | let conStr = occNameString (rdrNameOcc nm)
    , conStr `elem` knownVars
    -> let viewExpr = noLocA $ HsApp noExtField (polyVar "projectVariant") (polyLabel (fsLit conStr))
           justCon  = noLocA (mkRdrUnqual (mkDataOcc "Just"))
           wildPat  = noLocA (WildPat noExtField)
           justPat  = noLocA $ ConPat noAnn justCon (PrefixCon [wildPat])
       in ViewPat noAnn viewExpr justPat

  other -> other

-- | Desugar record pattern matching into view patterns.
desugarRecordPat :: [LHsRecField GhcPs (LPat GhcPs)] -> Pat GhcPs
desugarRecordPat [] =
  WildPat noExtField
desugarRecordPat [fld] =
  let (lbl, p) = extractRecPatField fld
      viewExpr = noLocA $ HsApp noExtField (polyVar "recordField") (polyLabel lbl)
  in ViewPat noAnn viewExpr p
desugarRecordPat flds =
  let (lbls, pats) = unzip (map extractRecPatField flds)
      rVar         = mkRdrUnqual (mkVarOcc "_r")
      rExpr        = noLocA (HsVar noExtField (noLocA rVar))
      mkProj lbl   = noLocA $ HsApp noExtField (noLocA (HsApp noExtField (polyVar "recordField") (polyLabel lbl))) rExpr
      tupExpr      = noLocA $ ExplicitTuple noAnn (map (Present noExtField . mkProj) lbls) Boxed
      rPat         = noLocA (VarPat noExtField (noLocA rVar))
      lamExpr      = mkHsLam (noLocA [rPat]) tupExpr
      tupPat       = noLocA $ TuplePat noAnn pats Boxed
  in ViewPat noAnn lamExpr tupPat

-- | Desugar variant pattern matching into (projectVariant #Tag -> Just p).
desugarVariantPat :: [LHsRecField GhcPs (LPat GhcPs)] -> Pat GhcPs
desugarVariantPat [] =
  error "Polytropos.Plugin.Source: VAR {} pattern requires a constructor tag"
desugarVariantPat (fld : _) =
  let (lbl, p)   = extractRecPatField fld
      viewExpr   = noLocA $ HsApp noExtField (polyVar "projectVariant") (polyLabel lbl)
      justCon    = noLocA (mkRdrUnqual (mkDataOcc "Just"))
      justPat    = noLocA $ ConPat noAnn justCon (PrefixCon [p])
  in ViewPat noAnn viewExpr justPat

-- | Extract label and sub-pattern from record pattern field.
extractRecPatField :: LHsRecField GhcPs (LPat GhcPs) -> (FastString, LPat GhcPs)
extractRecPatField (L _ (HsFieldBind _ (L _ (FieldOcc _ (L _ lbl))) p pun)) =
  let fs = occNameFS (rdrNameOcc lbl)
      p' = if pun then noLocA (VarPat noExtField (noLocA lbl)) else p
  in (fs, p')

{-------------------------------------------------------------------------------
  Helper Functions
-------------------------------------------------------------------------------}

polyVar :: String -> LHsExpr GhcPs
polyVar occ = noLocA (HsVar noExtField (noLocA (mkRdrQual (mkModuleName "Polytropos") (mkVarOcc occ))))

polyLabel :: FastString -> LHsExpr GhcPs
polyLabel fs = noLocA (HsOverLabel noAnn fs)

-- | Ensure 'import qualified Polytropos as Polytropos' is present in imports.
ensurePolytroposImport :: [LImportDecl GhcPs] -> [LImportDecl GhcPs]
ensurePolytroposImport imps =
  if any isPolytroposImport imps
    then imps
    else polytroposImportDecl : imps
  where
    isPolytroposImport (L _ ImportDecl{ ideclName = L _ modNm }) =
      moduleNameString modNm == "Polytropos"
    isPolytroposImport _ = False

    polytroposImportDecl :: LImportDecl GhcPs
    polytroposImportDecl = noLocA $ ImportDecl
      { ideclExt       = XImportDeclPass noAnn NoSourceText False
      , ideclName      = noLocA (mkModuleName "Polytropos")
      , ideclPkgQual   = NoRawPkgQual
      , ideclSource    = NotBoot
      , ideclLevelSpec = NotLevelled
      , ideclSafe      = False
      , ideclQualified = QualifiedPre
      , ideclAs        = Just (noLocA (mkModuleName "Polytropos"))
      , ideclImportList = Nothing
      }
