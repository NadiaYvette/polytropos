{-# LANGUAGE CPP #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ViewPatterns #-}

#if __GLASGOW_HASKELL__ >= 914
{-# OPTIONS_GHC -Wno-pattern-namespace-specifier #-}
#endif

-- | Compatibility layer for GHC 9.6 through 9.14.
--
-- Isolates all compiler AST and builtin namespace churn behind a uniform
-- interface, keeping the solver and source desugaring logic clean.
module Polytropos.Plugin.Compat
  ( modBase
  , modShow
  , modRecords
  , CompatRecUpdField
  , matchRecordUpd
  , extractRecUpdField
  , pattern PrefixConPat
  , pattern RecConPat
  , stripHsPar
  , mkHsPar
  , polyLabel
  , mkPolytroposImportDecl
  , compatImportModName
  , mkHsApp
  , mkTupArg
  , mkLambda
  ) where

import GHC.Unit.Types
  ( mkModule
  , moduleUnit
  )

import GHC.Plugins
  ( Module
  , FastString
#if __GLASGOW_HASKELL__ >= 1001
  , unpackFS
#else
  , moduleNameString
#endif
  , unLoc
  , mkModuleName
  , rdrNameOcc
  , occNameFS
  , RawPkgQual(..)
  )

import GHC.Hs.Extension
  ( GhcPs
  )

import GHC.Hs
  ( LHsExpr
  , LHsRecUpdField
  , LImportDecl
  , ImportDecl(..)
  , ImportDeclQualifiedStyle(..)
  , IsBootInterface(..)
#if __GLASGOW_HASKELL__ >= 1001
  , NoExtField
#endif
  , noAnn
  , noLocA
#if __GLASGOW_HASKELL__ >= 910
  , noExtField
#endif
  , HsExpr(..)
  , HsFieldBind(..)
  , HsConDetails(..)
  , LPat
  , mkHsLam
#if __GLASGOW_HASKELL__ >= 908
  , LHsRecUpdFields(..)
#endif
#if __GLASGOW_HASKELL__ >= 914
  , ImportDeclLevelStyle(..)
#endif
#if __GLASGOW_HASKELL__ >= 912
  , FieldOcc(..)
#else
  , AmbiguousFieldOcc(..)
#endif
  )

import Language.Haskell.Syntax.Expr
  ( HsTupArg(..)
  )
#if __GLASGOW_HASKELL__ >= 1001
import Language.Haskell.Syntax.Type (XPrefixCon)
import Language.Haskell.Syntax.Text (packHText)
import Language.Haskell.Syntax.Module.Name (HsModuleName(..), hsModuleNameString)
import GHC.Types.UnresolvedImport (ImportDeclOrigin(..))
#endif

import GHC.Hs.ImpExp
  ( XImportDeclPass(..)
  )

import GHC.Types.SourceText
  ( SourceText(..)
  )

#if __GLASGOW_HASKELL__ >= 1001
import GHC.Builtin.Modules
  ( gHC_INTERNAL_BASE
  )
#elif __GLASGOW_HASKELL__ >= 910
import GHC.Builtin.Names
  ( gHC_INTERNAL_BASE
  , gHC_INTERNAL_SHOW
  )
#else
import GHC.Builtin.Names
  ( gHC_BASE
  , gHC_SHOW
  )
#endif

-------------------------------------------------------------------------------
-- Module locations for base / show / records
-------------------------------------------------------------------------------

-- | Location of GHC.Base (or GHC.Internal.Base in 9.10+)
modBase :: Module
#if __GLASGOW_HASKELL__ >= 910
modBase = gHC_INTERNAL_BASE
#else
modBase = gHC_BASE
#endif

-- | Location of GHC.Show (or GHC.Internal.Show in 9.10+)
modShow :: Module
#if __GLASGOW_HASKELL__ >= 1001
modShow = mkModule (moduleUnit modBase) (mkModuleName "GHC.Internal.Show")
#elif __GLASGOW_HASKELL__ >= 910
modShow = gHC_INTERNAL_SHOW
#else
modShow = gHC_SHOW
#endif

-- | Location of GHC.Records (or GHC.Internal.Records in 9.10+)
modRecords :: Module
#if __GLASGOW_HASKELL__ >= 910
modRecords = mkModule (moduleUnit modBase) (mkModuleName "GHC.Internal.Records")
#else
modRecords = mkModule (moduleUnit modBase) (mkModuleName "GHC.Records")
#endif

-------------------------------------------------------------------------------
-- Record Update Compatibility (GHC 9.6 vs 9.8 vs 9.14)
-------------------------------------------------------------------------------

#if __GLASGOW_HASKELL__ >= 908
type CompatRecUpdField = LHsRecUpdField GhcPs GhcPs
#else
type CompatRecUpdField = LHsRecUpdField GhcPs
#endif

-- | Extract the updated record expression and fields from RecordUpd.
matchRecordUpd :: HsExpr GhcPs -> Maybe (LHsExpr GhcPs, [CompatRecUpdField])
#if __GLASGOW_HASKELL__ >= 908
matchRecordUpd (RecordUpd _ r (RegularRecUpdFields _ flds)) = Just (r, flds)
matchRecordUpd _ = Nothing
#else
matchRecordUpd (RecordUpd _ r (Left flds)) = Just (r, flds)
matchRecordUpd _ = Nothing
#endif

-- | Extract the label FastString and value expression from a record update field.
extractRecUpdField :: CompatRecUpdField -> (FastString, LHsExpr GhcPs)
#if __GLASGOW_HASKELL__ >= 912
extractRecUpdField (unLoc -> HsFieldBind _ (unLoc -> FieldOcc _ (unLoc -> lbl)) arg _) =
  (occNameFS (rdrNameOcc lbl), arg)
#else
extractRecUpdField (unLoc -> HsFieldBind _ (unLoc -> ambOcc) arg _) =
  let lbl = case ambOcc of
        Unambiguous _ (unLoc -> rdr) -> rdr
        Ambiguous _ (unLoc -> rdr)   -> rdr
  in (occNameFS (rdrNameOcc lbl), arg)
#endif

-------------------------------------------------------------------------------
-- Pattern & Expression AST Compatibility
-------------------------------------------------------------------------------

-- | Pattern synonym matching PrefixCon constructor details across GHC versions.
#if __GLASGOW_HASKELL__ >= 1001
pattern PrefixConPat :: (XPrefixCon p ~ NoExtField) => [arg] -> HsConDetails p arg rec
pattern PrefixConPat args <- PrefixCon _ args where
  PrefixConPat args = PrefixCon noExtField args

pattern RecConPat :: rec -> HsConDetails p arg rec
pattern RecConPat r <- RecCon _ r
#elif __GLASGOW_HASKELL__ >= 914
pattern PrefixConPat :: [arg] -> HsConDetails arg rec
pattern PrefixConPat args = PrefixCon args

pattern RecConPat :: rec -> HsConDetails arg rec
pattern RecConPat r <- RecCon r
#else
pattern PrefixConPat :: [arg] -> HsConDetails tyarg arg rec
pattern PrefixConPat args <- PrefixCon _ args
  where PrefixConPat args = PrefixCon [] args

pattern RecConPat :: rec -> HsConDetails tyarg arg rec
pattern RecConPat r <- RecCon r
#endif

-- | Strip enclosing parenthesis expressions across GHC versions.
stripHsPar :: LHsExpr GhcPs -> LHsExpr GhcPs
#if __GLASGOW_HASKELL__ >= 910
stripHsPar (unLoc -> HsPar _ e) = stripHsPar e
#else
stripHsPar (unLoc -> HsPar _ _ e _) = stripHsPar e
#endif
stripHsPar e = e

-- | Construct a parenthesized expression across GHC versions.
mkHsPar :: LHsExpr GhcPs -> LHsExpr GhcPs
#if __GLASGOW_HASKELL__ >= 910
mkHsPar e = noLocA (HsPar noAnn e)
#else
mkHsPar e = noLocA (HsPar noAnn noAnn e noAnn)
#endif

-- | Construct an overloaded label expression across GHC 9.6-9.14.
polyLabel :: FastString -> LHsExpr GhcPs
#if __GLASGOW_HASKELL__ >= 1001
polyLabel fs = noLocA (HsOverLabel NoSourceText (packHText (unpackFS fs)))
#elif __GLASGOW_HASKELL__ >= 912
polyLabel fs = noLocA (HsOverLabel NoSourceText fs)
#elif __GLASGOW_HASKELL__ >= 910
polyLabel fs = noLocA (HsOverLabel noExtField NoSourceText fs)
#else
polyLabel fs = noLocA (HsOverLabel noAnn NoSourceText fs)
#endif

-- | Construct the 'import qualified Polytropos as Polytropos' declaration.
mkPolytroposImportDecl :: LImportDecl GhcPs
#if __GLASGOW_HASKELL__ >= 1001
mkPolytroposImportDecl = noLocA $ ImportDecl
  { ideclExt        = XImportDeclPass noAnn NoSourceText UserWrittenImport
  , ideclName       = noLocA (HsModuleName (packHText "Polytropos"))
  , ideclPkgQual    = NoRawPkgQual
  , ideclSource     = NotBoot
  , ideclLevelSpec  = NotLevelled
  , ideclSafe       = False
  , ideclQualified  = QualifiedPre
  , ideclAs         = Just (noLocA (HsModuleName (packHText "Polytropos")))
  , ideclImportList = Nothing
  }
#elif __GLASGOW_HASKELL__ >= 914
mkPolytroposImportDecl = noLocA $ ImportDecl
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
#else
mkPolytroposImportDecl = noLocA $ ImportDecl
  { ideclExt       = XImportDeclPass noAnn NoSourceText False
  , ideclName      = noLocA (mkModuleName "Polytropos")
  , ideclPkgQual   = NoRawPkgQual
  , ideclSource    = NotBoot
  , ideclSafe      = False
  , ideclQualified = QualifiedPre
  , ideclAs        = Just (noLocA (mkModuleName "Polytropos"))
  , ideclImportList = Nothing
  }
#endif

-- | Extract the imported module name as a String across GHC versions.
compatImportModName :: LImportDecl GhcPs -> String
#if __GLASGOW_HASKELL__ >= 1001
compatImportModName (unLoc -> ImportDecl{ ideclName = unLoc -> modNm }) =
  hsModuleNameString modNm
#else
compatImportModName (unLoc -> ImportDecl{ ideclName = unLoc -> modNm }) =
  moduleNameString modNm
#endif

-- | Construct a function application expression across GHC 9.6-9.14.
mkHsApp :: LHsExpr GhcPs -> LHsExpr GhcPs -> LHsExpr GhcPs
#if __GLASGOW_HASKELL__ >= 910
mkHsApp f x = noLocA (HsApp noExtField f x)
#else
mkHsApp f x = noLocA (HsApp noAnn f x)
#endif

-- | Construct a tuple present argument across GHC 9.6-9.14.
mkTupArg :: LHsExpr GhcPs -> HsTupArg GhcPs
#if __GLASGOW_HASKELL__ >= 910
mkTupArg e = Present noExtField e
#else
mkTupArg e = Present noAnn e
#endif

-- | Construct a lambda expression across GHC 9.6-9.14.
mkLambda :: [LPat GhcPs] -> LHsExpr GhcPs -> LHsExpr GhcPs
#if __GLASGOW_HASKELL__ >= 912
mkLambda pats body = mkHsLam (noLocA pats) body
#else
mkLambda pats body = mkHsLam pats body
#endif
