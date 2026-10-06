{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE PolyKinds #-}

-- | GHC typechecker plugin for @polytropos@.
--
-- Solves the evidence-class constraints (@'FieldIndex'@, @'ConstructorIndex'@,
-- @'RowEq'@, @'RowShow'@, @'RowEqSum'@, @'RowShowSum'@) by inspecting the row
-- carried in a @'RowRep'@'s type and emitting literal slot indices, tags, and
-- comparison bodies — the same technique @large-anon@ uses for
-- @DictRowHasField@.
--
-- Load with @ghc-options: -fplugin=Polytropos.Plugin@ in the consuming
-- package's .cabal file.
--
-- == Implementation notes
--
-- The plugin uses 'ghc-tcplugin-api' (0.20.x) for a streamlined interface to
-- GHC's typechecker plugin API.
--
-- Solved constraints:
-- * 'FieldIndex' — walks the type-level row and emits a literal Int
-- * 'ConstructorIndex' — walks the type-level sum row and emits a literal Word
-- * 'RowEq' / 'RowShow' / 'RowEqSum' / 'RowShowSum' — build Core expression
--   bodies for the evidence class methods.

module Polytropos.Plugin
  ( plugin
  ) where

import Prelude

import GHC.Core.Make
  ( mkCoreApps
  , mkCoreConApps
  )

import GHC.Plugins
  ( Plugin (..)
  , defaultPlugin
  , tcPlugin
  , ppr
  , text
  , (<+>)
  , CoreExpr
  , Expr(..)
  , Type
  , TyCon
  , mkTcOcc
  , nameOccName
  , mkTyConTy
  , mkTyConApp
  , dataConTyCon
  , splitTyConApp_maybe
  , isStrLitTy
  , intDataCon
  , wordDataCon
  , FastString
  , Literal(..)
  , LitNumType(..)
  , wordTyCon
  , showSDocUnsafe
  , SDoc
  , Var(..)
  , idDetails
  , idInfo
  , vanillaIdInfo
  , boolTyCon
  , intTy
  , stringTy
  , varName
  , varType
  , mkFunTy
  , liftedTypeKind
  , FunTyFlag( FTF_T_T )
  , TyVar
  , mkTyVar
  , mkTyVarBinder
  , ForAllTyFlag( Invisible )
  , Specificity( SpecifiedSpec )
  , mkWildValBinder
  , mkVanillaGlobal
  , mkInternalName
  , mkVarOcc
  , SrcSpan(UnhelpfulSpan)
  , manyDataCon
  , dataConTyCon
  , Module
  , ModuleName
  , mkModuleName
  , fsLit
  , stringToUnitId
  , PkgQual(NoPkgQual, OtherPkg)
  )

import GHC.TcPlugin.API
  ( TcPlugin (..)
  , TcPluginSolveResult(..)
  , TcPluginM
  , classifyPredType
  , Pred(..)
  , ctPred
  , ctEvidence
  , isWanted
  , className
  , tcPluginTrace
  , EvTerm (..)
  , EvExpr (..)
  , newEvVar
  , setEvBind
  , evId
  , Ct
  , TcPluginStage(..)
  , mkTcPlugin
  , emptyUFM
  , lookupOrig
  , tcLookupId
  , findImportedModule
  , PkgQual
  , FindResult(..)
  )

import GHC.Tc.Types.Evidence (EvBind(..))

import Data.List ( find )
import Prelude hiding (find)

import Polytropos.Core (Rep(..), RowRep(..), repTag, repArity, fieldAt, noInlineUnsafeCo, unRowRep)

-------------------------------------------------------------------------------
-- Plugin entry point
-------------------------------------------------------------------------------

plugin :: Plugin
plugin = defaultPlugin { tcPlugin = const $ Just $ mkTcPlugin polytroposPlugin }


polytroposPlugin :: TcPlugin
polytroposPlugin = TcPlugin
  { tcPluginInit  = polytroposInit
  , tcPluginSolve  = const polytroposSolve
  , tcPluginRewrite = const emptyUFM
  , tcPluginPostTc = const (return ())
  , tcPluginShutdown = const (return ())
  }


-------------------------------------------------------------------------------
-- Plugin state
-------------------------------------------------------------------------------

-- | The plugin's state: references to all the GHC and Polytropos functions
-- that the solvers need when building Core expressions.
data PluginState = PluginState
  { psRepTag     :: !Var    -- ^ repTag :: Rep f a -> Word
  , psRepArity   :: !Var    -- ^ repArity :: Rep f a -> Int
  , psFieldAt    :: !Var    -- ^ fieldAt :: Int -> Rep f a -> f x
  , psUnRowRep   :: !Var    -- ^ unRowRep :: RowRep f r row a -> Rep f a
  , psNoInlineCo :: !Var    -- ^ noInlineUnsafeCo :: a -> b
  , psAnd        :: !Var    -- ^ GHC.Classes.&& :: Bool -> Bool -> Bool
  , psShowsPrec :: !Var    -- ^ GHC.Show.showsPrec (class method)
  , psShowString :: !Var   -- ^ GHC.Show.showString :: String -> ShowS
  , psShowChar   :: !Var   -- ^ GHC.Show.showChar :: Char -> ShowS
  , psComp       :: !Var    -- ^ GHC.Base.(.) :: (b -> c) -> (a -> b) -> a -> c
  , psEqClass    :: !Var    -- ^ GHC.Classes.== (class method, polymorphic)
  , psShowsPrecMeth :: !Var -- ^ GHC.Show.showsPrec (class method, polymorphic)
  , psEqMethod   :: !Var    -- ^ GHC.Classes.== (alias for psEqClass)
  }


-------------------------------------------------------------------------------
-- Plugin initialisation: look up all needed names
-------------------------------------------------------------------------------

polytroposInit :: TcPluginM 'Init PluginState
polytroposInit = do
  -- Look up Polytropos.Core functions
  coreMod <- findPolytroposCoreModule
  psRepTag     <- lookupIdInModule coreMod "repTag"
  psRepArity   <- lookupIdInModule coreMod "repArity"
  psFieldAt    <- lookupIdInModule coreMod "fieldAt"
  psUnRowRep   <- lookupIdInModule coreMod "unRowRep"
  psNoInlineCo <- lookupIdInModule coreMod "noInlineUnsafeCo"

  -- Look up GHC.Classes functions
  classesMod <- findGhcClassesModule
  psEqClass    <- lookupIdInModule classesMod "=="
  psAnd        <- lookupIdInModule classesMod "&&"

  -- Look up GHC.Show functions
  showMod <- findGhcShowModule
  psShowsPrecMeth <- lookupIdInModule showMod "showsPrec"
  psShowString    <- lookupIdInModule showMod "showString"
  psShowChar      <- lookupIdInModule showMod "showChar"

  -- Look up GHC.Base.(.)
  baseMod <- findGhcBaseModule
  psComp <- lookupIdInModule baseMod "."

  pure PluginState
    { psRepTag     = psRepTag
    , psRepArity   = psRepArity
    , psFieldAt    = psFieldAt
    , psUnRowRep   = psUnRowRep
    , psNoInlineCo = psNoInlineCo
    , psEqClass    = psEqClass
    , psAnd        = psAnd
    , psShowsPrec = psShowsPrecMeth
    , psShowString = psShowString
    , psShowChar   = psShowChar
    , psComp       = psComp
    , psShowsPrecMeth = psShowsPrecMeth
    , psEqMethod   = psEqClass
    }


-- | Look up a module by name and package.
findModule :: String -> String -> TcPluginM 'Init Module
findModule modName pkgName = do
  let modName' = mkModuleName modName
      pkgQual  = OtherPkg (stringToUnitId pkgName)
  result <- findImportedModule modName' pkgQual
  case result of
    Found _ mod' -> pure mod'
    _           -> error $ "polytropos: could not find module " ++ modName

findPolytroposCoreModule :: TcPluginM 'Init Module
findPolytroposCoreModule = findModule "Polytropos.Core" "polytropos-core"

findGhcClassesModule :: TcPluginM 'Init Module
findGhcClassesModule = findModule "GHC.Classes" "base"

findGhcShowModule :: TcPluginM 'Init Module
findGhcShowModule = findModule "GHC.Show" "base"

findGhcBaseModule :: TcPluginM 'Init Module
findGhcBaseModule = findModule "GHC.Base" "base"

-- | Look up an Id by name in a module.
lookupIdInModule :: Module -> String -> TcPluginM 'Init Var
lookupIdInModule modName occStr = do
  let occ = mkVarOcc occStr
  name <- lookupOrig modName occ
  tcLookupId name


-------------------------------------------------------------------------------
-- Constraint solving
-------------------------------------------------------------------------------

-- | Solve evidence-class constraints by inspecting the row carried in the
-- constraint's types.
polytroposSolve
  :: [Ct]
  -> [Ct]
  -> TcPluginM 'Solve TcPluginSolveResult
polytroposSolve givens wanteds = do
  let allCts = givens ++ wanteds
  traceMsg "polytropos-solve" $ text "num constraints: " <+> ppr (length allCts)

  solved <- mapM solveOne allCts
  let (solved', fskipped) = partitionEithers solved
  traceMsg "polytropos-solve" $ text "solved: " <+> ppr (length solved')
                         <+> text "skipped: " <+> ppr (length fskipped)
  pure $ TcPluginSolveResult { tcPluginInsolubleCts = []
                           , tcPluginSolvedCts = solved'
                           , tcPluginNewCts = []
                           }


-- | Solve a single constraint.
solveOne :: Ct -> TcPluginM 'Solve (Either (EvTerm, Ct) ())
solveOne ct
  | not (isWanted (ctEvidence ct))
  = pure $ Right ()
  | otherwise
  = do
    let pred = ctPred ct
    case classifyPredType pred of
      ClassPred cls tys -> do
        traceMsg "polytropos-solve" $ text "class: " <+> ppr (className cls)
                               <+> text "tys: " <+> ppr tys
        case className cls of
          name
            | nameOccName name == mkTcOcc "FieldIndex"
            -> solveFieldIndex ct tys
            | nameOccName name == mkTcOcc "ConstructorIndex"
            -> solveConstructorIndex ct tys
            | nameOccName name == mkTcOcc "RowEq"
            -> solveRowEq ct tys
            | nameOccName name == mkTcOcc "RowShow"
            -> solveRowShow ct tys
            | nameOccName name == mkTcOcc "RowEqSum"
            -> solveRowEqSum ct tys
            | nameOccName name == mkTcOcc "RowShowSum"
            -> solveRowShowSum ct tys
            | otherwise
            -> pure $ Right ()
      _ -> pure $ Right ()


-------------------------------------------------------------------------------
-- FieldIndex solver
-------------------------------------------------------------------------------

-- | Solve @"FieldIndex" "n" row a@ by walking the row list.
solveFieldIndex
  :: Ct
  -> [Type]
  -> TcPluginM 'Solve (Either (EvTerm, Ct) ())
solveFieldIndex ct tys = do
  traceMsg "polytropos-solve" $ text "solveFieldIndex"
  case tys of
    [nTy, rowTy, aTy] -> do
      n <- getSymbolLit nTy
      case n of
        Just fieldName -> do
          let idx = findFieldIndex fieldName rowTy
          case idx of
            Just i -> do
              traceMsg "polytropos-solve" $
                text "FieldIndex " <+> ppr fieldName <+>
                text " = " <+> ppr i <+> text " (literal)"
              let iExpr = mkCoreConApps intDataCon [Lit (mkLit (fromIntegral i :: Integer))]
              evTerm <- buildSimpleDict iExpr aTy
              pure $ Left (evTerm, ct)
            Nothing -> do
              traceMsg "polytropos-solve" $
                text "FieldIndex " <+> ppr fieldName <+>
                text " not found in row"
              pure $ Right ()
        Nothing -> do
          traceMsg "polytropos-solve" $
            text "FieldIndex: could not extract field name"
          pure $ Right ()
    _ -> do
      traceMsg "polytropos-solve" $
        text "FieldIndex: unexpected number of types: " <+> ppr (length tys)
      pure $ Right ()


-------------------------------------------------------------------------------
-- ConstructorIndex solver
-------------------------------------------------------------------------------

-- | Solve @"ConstructorIndex" "n" row@ by walking the sum row list.
solveConstructorIndex
  :: Ct
  -> [Type]
  -> TcPluginM 'Solve (Either (EvTerm, Ct) ())
solveConstructorIndex ct tys = do
  traceMsg "polytropos-solve" $ text "solveConstructorIndex"
  case tys of
    [nTy, rowTy] -> do
      n <- getSymbolLit nTy
      case n of
        Just conName -> do
          let idx = findConstructorIndex conName rowTy
          case idx of
            Just w -> do
              traceMsg "polytropos-solve" $
                text "ConstructorIndex " <+> ppr conName <+>
                text " = " <+> ppr w <+> text " (literal)"
              let coreExpr = mkCoreConApps wordDataCon [Lit (mkLit (fromIntegral w :: Integer))]
              evTerm <- buildSimpleDict coreExpr (mkTyConTy wordTyCon)
              pure $ Left (evTerm, ct)
            Nothing -> do
              traceMsg "polytropos-solve" $
                text "ConstructorIndex " <+> ppr conName <+>
                text " not found in row"
              pure $ Right ()
        Nothing -> do
          traceMsg "polytropos-solve" $
            text "ConstructorIndex: could not extract constructor name"
          pure $ Right ()
    _ -> do
      traceMsg "polytropos-solve" $
        text "ConstructorIndex: unexpected number of types: " <+> ppr (length tys)
      pure $ Right ()


-------------------------------------------------------------------------------
-- RowEq solver
-------------------------------------------------------------------------------

-- | Walk a product row and extract field names with their types.
-- Returns a list of (index, fieldName, fieldType).
walkRowWithTypes :: Type -> [(Int, FastString, Type)]
walkRowWithTypes rowTy = go 0 rowTy
  where
    go :: Int -> Type -> [(Int, FastString, Type)]
    go i ty = case splitTyConApp_maybe ty of
      Just (tc, [headTy, _])
        | isConsListTy tc ->
            case splitTyConApp_maybe headTy of
              Just (pairTc, [nameTy, fieldTy])
                | isConsListTy pairTc ->
                    case isStrLitTy nameTy of
                      Just n -> (i, n, fieldTy) : go (i + 1) (listTail ty)
                      Nothing -> go (i + 1) (listTail ty)
              _ -> []
      _ -> []

    listTail :: Type -> Type
    listTail ty = case splitTyConApp_maybe ty of
      Just (_, (_ : tail : _)) -> tail
      _ -> error "walkRowWithTypes: impossible: not a list type"


-- | Build the Core expression for RowEq.
--
-- The method type is: forall f a. RowRep f r row a -> RowRep f r row a -> Bool
--
-- The body compares:
-- 1. repTag of both (Word equality)
-- 2. repArity of both (Int equality)
-- 3. For each field i: fieldAt i (unRowRep r1) == fieldAt i (unRowRep r2)
--
-- All comparisons use (==) at the appropriate type, with noInlineUnsafeCo
-- to coerce field values from f x to x.
--
-- NOTE: This is a work-in-progress. The full implementation requires:
-- 1. Constructing the RowRep type properly
-- 2. Looking up Eq dictionaries for each field type
-- 3. Building the comparison chain with proper type applications
buildRowEqBody
  :: PluginState
  -> [(Int, FastString, Type)]  -- ^ fields with their types
  -> Type                       -- ^ the row type (for error messages)
  -> TcPluginM 'Solve CoreExpr
buildRowEqBody _state _fields _rowTy = do
  -- For now, return a placeholder. The full implementation is complex
  -- and requires proper Eq dictionary resolution.
  error "buildRowEqBody: not yet implemented - requires Eq dictionary resolution"


-- | Build a comparison chain for RowEq.
-- NOTE: This is a stub. The full implementation requires Eq dictionary resolution.
buildComparisonChain
  :: PluginState
  -> Var  -- ^ r1 binder
  -> Var  -- ^ r2 binder
  -> [Type]  -- ^ field types
  -> TcPluginM 'Solve CoreExpr
buildComparisonChain _state _r1Bndr _r2Bndr _fieldTypes = do
  error "buildComparisonChain: not yet implemented"


-------------------------------------------------------------------------------
-- RowEq solver (stub - full implementation pending)
-------------------------------------------------------------------------------

-- | Solve @"RowEq" r row@ by building a comparison body.
--
-- This requires building a function body at the Core level.
solveRowEq
  :: Ct
  -> [Type]
  -> TcPluginM 'Solve (Either (EvTerm, Ct) ())
solveRowEq ct tys = do
  traceMsg "polytropos-solve" $ text "solveRowEq"
  case tys of
    [rTy, rowTy] -> do
      traceMsg "polytropos-solve" $ text "RowEq row: " <+> ppr rowTy
      let fields = walkRowWithTypes rowTy
      traceMsg "polytropos-solve" $ text "RowEq fields: " <+> ppr (length fields)
                     <+> text "(names: " <+> ppr (map (\(_,n,_) -> n) fields) <+> text ")"
      -- For now, trace and skip - full implementation requires Eq dictionary resolution
      pure $ Right ()
    _ -> do
      traceMsg "polytropos-solve" $
        text "RowEq: unexpected number of types: " <+> ppr (length tys)
      pure $ Right ()


-------------------------------------------------------------------------------
-- RowShow solver (stub)
-------------------------------------------------------------------------------

-- | Walk a product row and extract field names with their types (for RowShow).
walkRowForShow :: Type -> [(Int, FastString, Type)]
walkRowForShow = walkRowWithTypes


-- | Solve @"RowShow" r row@ by building a show body.
solveRowShow
  :: Ct
  -> [Type]
  -> TcPluginM 'Solve (Either (EvTerm, Ct) ())
solveRowShow ct tys = do
  traceMsg "polytropos-solve" $ text "solveRowShow"
  case tys of
    [rTy, rowTy] -> do
      traceMsg "polytropos-solve" $ text "RowShow row: " <+> ppr rowTy
      let fields = walkRowForShow rowTy
      traceMsg "polytropos-solve" $ text "RowShow fields: " <+> ppr (length fields)
                     <+> text "(names: " <+> ppr (map (\(_,n,_) -> n) fields) <+> text ")"
      -- For now, trace and skip
      pure $ Right ()
    _ -> do
      traceMsg "polytropos-solve" $
        text "RowShow: unexpected number of types: " <+> ppr (length tys)
      pure $ Right ()


-------------------------------------------------------------------------------
-- RowEqSum solver (stub)
-------------------------------------------------------------------------------

-- | Walk a sum row and extract constructor info with their field types.
walkSumRowWithTypes :: Type -> [(Int, FastString, Type)]
walkSumRowWithTypes rowTy = go 0 rowTy
  where
    go :: Int -> Type -> [(Int, FastString, Type)]
    go i ty = case splitTyConApp_maybe ty of
      Just (tc, [headTy, _])
        | isConsListTy tc ->
            case splitTyConApp_maybe headTy of
              Just (pairTc, [nameTy, _])
                | isConsListTy pairTc ->
                    case isStrLitTy nameTy of
                      Just n -> (i, n, nameTy) : go (i + 1) (listTail ty)
                      Nothing -> go (i + 1) (listTail ty)
              _ -> []
      _ -> []

    listTail :: Type -> Type
    listTail ty = case splitTyConApp_maybe ty of
      Just (_, (_ : tail : _)) -> tail
      _ -> error "walkSumRowWithTypes: impossible: not a list type"


-- | Solve @"RowEqSum" r row@ by building a sum comparison body.
solveRowEqSum
  :: Ct
  -> [Type]
  -> TcPluginM 'Solve (Either (EvTerm, Ct) ())
solveRowEqSum ct tys = do
  traceMsg "polytropos-solve" $ text "solveRowEqSum"
  case tys of
    [rTy, rowTy] -> do
      traceMsg "polytropos-solve" $ text "RowEqSum row: " <+> ppr rowTy
      let fields = walkSumRowWithTypes rowTy
      traceMsg "polytropos-solve" $ text "RowEqSum fields: " <+> ppr (length fields)
      pure $ Right ()
    _ -> do
      traceMsg "polytropos-solve" $
        text "RowEqSum: unexpected number of types: " <+> ppr (length tys)
      pure $ Right ()


-------------------------------------------------------------------------------
-- RowShowSum solver (stub)
-------------------------------------------------------------------------------

-- | Solve @"RowShowSum" r row@ by building a sum show body.
solveRowShowSum
  :: Ct
  -> [Type]
  -> TcPluginM 'Solve (Either (EvTerm, Ct) ())
solveRowShowSum ct tys = do
  traceMsg "polytropos-solve" $ text "solveRowShowSum"
  case tys of
    [rTy, rowTy] -> do
      traceMsg "polytropos-solve" $ text "RowShowSum row: " <+> ppr rowTy
      let fields = walkSumRowWithTypes rowTy
      traceMsg "polytropos-solve" $ text "RowShowSum fields: " <+> ppr (length fields)
      pure $ Right ()
    _ -> do
      traceMsg "polytropos-solve" $
        text "RowShowSum: unexpected number of types: " <+> ppr (length tys)
      pure $ Right ()


-------------------------------------------------------------------------------
-- Row walking helpers (original, for FieldIndex/ConstructorIndex)
-------------------------------------------------------------------------------

-- | Walk a product row and extract field names with their indices.
walkRow :: Type -> [(Int, FastString)]
walkRow rowTy = go 0 rowTy
  where
    go :: Int -> Type -> [(Int, FastString)]
    go i ty = case splitTyConApp_maybe ty of
      Just (tc, [headTy, _])
        | isConsListTy tc ->
            case splitTyConApp_maybe headTy of
              Just (pairTc, [nameTy, _])
                | isConsListTy pairTc ->
                    case isStrLitTy nameTy of
                      Just n -> (i, n) : go (i + 1) (listTail ty)
                      Nothing -> go (i + 1) (listTail ty)
              _ -> []
      _ -> []

    listTail :: Type -> Type
    listTail ty = case splitTyConApp_maybe ty of
      Just (_, (_ : tail : _)) -> tail
      _ -> error "walkRow: impossible: not a list type"


-- | Walk a sum row and extract constructor info.
walkSumRow :: Type -> [(Int, FastString)]
walkSumRow rowTy = go 0 rowTy
  where
    go :: Int -> Type -> [(Int, FastString)]
    go i ty = case splitTyConApp_maybe ty of
      Just (tc, [headTy, _])
        | isConsListTy tc ->
            case splitTyConApp_maybe headTy of
              Just (pairTc, [nameTy, _])
                | isConsListTy pairTc ->
                    case isStrLitTy nameTy of
                      Just n -> (i, n) : go (i + 1) (listTail ty)
                      Nothing -> go (i + 1) (listTail ty)
              _ -> []
      _ -> []

    listTail :: Type -> Type
    listTail ty = case splitTyConApp_maybe ty of
      Just (_, (_ : tail : _)) -> tail
      _ -> error "walkSumRow: impossible: not a list type"


-------------------------------------------------------------------------------
-- Utility functions
-------------------------------------------------------------------------------

-- | Extract a FastString literal from a type, if it's a type-level string.
getSymbolLit :: Type -> TcPluginM 'Solve (Maybe FastString)
getSymbolLit ty = do
  traceMsg "polytropos-utils" $ text "getSymbolLit: " <+> ppr ty
  case isStrLitTy ty of
    Just fs -> pure (Just fs)
    Nothing -> pure Nothing


-- | Find the field index of a named field in a row type.
findFieldIndex
  :: FastString
  -> Type
  -> Maybe Int
findFieldIndex fieldName rowTy =
  go 0 rowTy
  where
    go :: Int -> Type -> Maybe Int
    go i ty = case splitTyConApp_maybe ty of
      Just (tc, [headTy, _])
        | isConsListTy tc ->
            case splitTyConApp_maybe headTy of
              Just (pairTc, [nameTy, _])
                | isConsListTy pairTc ->
                    case isStrLitTy nameTy of
                      Just n | n == fieldName -> Just i
                      _ -> go (i + 1) (listTail ty)
              _ -> Nothing
      _ -> Nothing

    listTail :: Type -> Type
    listTail ty = case splitTyConApp_maybe ty of
      Just (_, (_ : tail : _)) -> tail
      _ -> error "findFieldIndex: impossible: not a list type"


-- | Find the constructor index of a named constructor in a sum row type.
findConstructorIndex
  :: FastString
  -> Type
  -> Maybe Word
findConstructorIndex conName rowTy =
  go 0 rowTy
  where
    go :: Word -> Type -> Maybe Word
    go w ty = case splitTyConApp_maybe ty of
      Just (tc, [headTy, _])
        | isConsListTy tc ->
            case splitTyConApp_maybe headTy of
              Just (pairTc, [nameTy, _])
                | isConsListTy pairTc ->
                    case isStrLitTy nameTy of
                      Just n | n == conName -> Just w
                      _ -> go (w + 1) (listTail ty)
              _ -> Nothing
      _ -> Nothing

    listTail :: Type -> Type
    listTail ty = case splitTyConApp_maybe ty of
      Just (_, (_ : tail : _)) -> tail
      _ -> error "findConstructorIndex: impossible: not a list type"


-- | Check whether a type constructor is the built-in list type.
isConsListTy :: TyCon -> Bool
isConsListTy tc = showSDocUnsafe (ppr tc) == "[]"


-- | Build a simple dictionary from a CoreExpr.
buildSimpleDict
  :: CoreExpr
  -> Type
  -> TcPluginM 'Solve EvTerm
buildSimpleDict coreExpr dictTy = do
  dictVar <- newEvVar dictTy
  let evBind = EvBind { eb_lhs = dictVar, eb_rhs = EvExpr coreExpr }
  setEvBind evBind
  pure (EvExpr (evId dictVar))


-------------------------------------------------------------------------------
-- Tracing
-------------------------------------------------------------------------------

traceMsg :: String -> SDoc -> TcPluginM 'Solve ()
traceMsg tag doc =
  tcPluginTrace ("polytropos/" ++ tag) doc


-------------------------------------------------------------------------------
-- Utility
-------------------------------------------------------------------------------

partitionEithers :: [Either a b] -> ([a], [b])
partitionEithers [] = ([], [])
partitionEithers (Left x : xs) = let (ls, rs) = partitionEithers xs in (x : ls, rs)
partitionEithers (Right y : xs) = let (ls, rs) = partitionEithers xs in (ls, y : rs)

-- | Create an integer Literal from an Integer.
mkLit :: Integer -> Literal
mkLit i = LitNumber LitNumInt i

