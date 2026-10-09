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
module Polytropos.Plugin
  ( plugin
  ) where

import Prelude

import Control.Monad
  ( forM
  )

import GHC.Core.Make
  ( mkCoreApps
  , mkCoreConApps
  , mkCoreLams
  , mkCharExpr
  , mkStringExpr
  , mkIfThenElse
  , mkListExpr
  )

import GHC.Plugins
  ( Plugin (..)
  , defaultPlugin
  , tcPlugin
  , ppr
  , CoreExpr
  , Expr(..)
  , Type
  , mkTcOcc
  , nameOccName
  , mkTyConTy
  , splitTyConApp_maybe
  , isStrLitTy
  , mkStrLitTy
  , intDataCon
  , wordDataCon
  , FastString
  , unpackFS
  , Literal(..)
  , LitNumType(..)
  , wordTyCon
  , showSDocUnsafe
  , Var(..)
  , varType
  , intTy
  , stringTy
  , mkVarOcc
  , Module
  , mkModuleName
  , coreView
  , splitFunTy
  , splitFunTys
  , splitForAllTyCoVars
  , piResultTys
  , typeKind
  , mkTyVarTy
  , mkAppTy
  , getOccName
  , occNameString
  , fsLit
  , TyCon
  )

import GHC.Unit.Types
  ( mkModule
  , moduleUnit
  )

import GHC.Core.Class
  ( classMethods
  )

import GHC.Core.Multiplicity
  ( scaledThing
  , scaledMult
  )

import GHC.Core.TyCo.Compare
  ( eqType
  )

import GHC.Builtin.Types
  ( boolTy
  , trueDataCon
  , falseDataCon
  , typeSymbolKind
  , liftedTypeKind
  , mkPromotedPairTy
  , mkPromotedListTy
  , mkTupleTy
  )

import Language.Haskell.Syntax.Basic
  ( Boxity(..)
  )

import GHC.Builtin.Names
  ( gHC_CLASSES
  , gHC_INTERNAL_BASE
  , gHC_INTERNAL_SHOW
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
  , EvTerm (..)
  , Ct
  , TcPluginStage(..)
  , mkTcPlugin
  , listToUFM
  , UniqFM
  , lookupOrig
  , tcLookupId
  , tcLookupTyCon
  , findImportedModule
  , resolveImport
  , FindResult(..)
  , Class
  , classDataCon
  , tcLookupClass
  , evDataConApp
  , newName
  , mkLocalId
  , newWanted
  , ctEvExpr
  , mkNonCanonical
  , ctLoc
  , Role(..)
  , TcPluginRewriteResult(..)
  , mkTyFamAppReduction
  )

import GHC.TcPlugin.API.Internal
  ( unsafeLiftTcM
  , TcPluginRewriter
  )

-------------------------------------------------------------------------------
-- Plugin entry point
-------------------------------------------------------------------------------

plugin :: Plugin
plugin = defaultPlugin { tcPlugin = const $ Just $ mkTcPlugin polytroposPlugin }

polytroposPlugin :: TcPlugin
polytroposPlugin = TcPlugin
  { tcPluginInit     = polytroposInit
  , tcPluginSolve    = polytroposSolve
  , tcPluginRewrite  = polytroposRewrite
  , tcPluginPostTc   = const (return ())
  , tcPluginShutdown = const (return ())
  }

--------------------------------------------------------------------------------- Plugin state
-------------------------------------------------------------------------------

data PluginState = PluginState

  { psRepTag        :: !Var    -- ^ repTag :: Rep f a -> Word
  , psRepArity      :: !Var    -- ^ repArity :: Rep f a -> Int
  , psFieldAt       :: !Var    -- ^ fieldAt :: Int -> Rep f a -> f x
  , psUnRowRep      :: !Var    -- ^ unRowRep :: RowRep f r row a -> Rep f a
  , psNoInlineCo    :: !Var    -- ^ noInlineUnsafeCo :: a -> b
  , psAnd           :: !Var    -- ^ GHC.Internal.Classes.&&
  , psComp          :: !Var    -- ^ GHC.Internal.Base.(.)
  , psEqClass       :: !Var    -- ^ GHC.Internal.Classes.== (method)
  , psShowsPrecMeth :: !Var    -- ^ GHC.Internal.Show.showsPrec (method)
  , psShowString    :: !Var    -- ^ GHC.Internal.Show.showString
  , psShowChar      :: !Var    -- ^ GHC.Internal.Show.showChar
  , psFEqInt        :: !Var    -- ^ $fEqInt
  , psFEqBool       :: !Var    -- ^ $fEqBool
  , psFEqWord       :: !Var    -- ^ $fEqWord
  , psFShowInt      :: !Var    -- ^ $fShowInt
  , psFShowBool     :: !Var    -- ^ $fShowBool
  , psRowFlavourCls   :: !Class  -- ^ RowFlavour class
  , psHasFieldCls     :: !Class  -- ^ GHC.Records.HasField class
  , psDictAnyTyCon    :: !TyCon  -- ^ Polytropos.Core.DictAny
  , psMkDictAny       :: !Var    -- ^ Polytropos.Core.mkDictAny
  , psEvidenceAllFields :: !Var  -- ^ Polytropos.Core.evidenceAllFields
  , psFieldTypesTyCon       :: !TyCon -- ^ Polytropos.Core.FieldTypes
  , psSimpleFieldTypesTyCon :: !TyCon -- ^ Polytropos.Core.SimpleFieldTypes
  , psFieldNamesTyCon       :: !TyCon -- ^ Polytropos.Core.FieldNames
  }

-------------------------------------------------------------------------------
-- Plugin initialisation
-------------------------------------------------------------------------------

polytroposInit :: TcPluginM 'Init PluginState
polytroposInit = do
  coreMod <- findPolytroposCoreModule
  psRepTag     <- lookupIdInModule coreMod "repTag"
  psRepArity   <- lookupIdInModule coreMod "repArity"
  psFieldAt    <- lookupIdInModule coreMod "fieldAt"
  psUnRowRep   <- lookupIdInModule coreMod "unRowRep"
  psNoInlineCo <- lookupIdInModule coreMod "noInlineUnsafeCo"

  psEqClass    <- lookupIdInModule gHC_CLASSES "=="
  psAnd        <- lookupIdInModule gHC_CLASSES "&&"
  psFEqInt     <- lookupIdInModule gHC_CLASSES "$fEqInt"
  psFEqBool    <- lookupIdInModule gHC_CLASSES "$fEqBool"
  psFEqWord    <- lookupIdInModule gHC_CLASSES "$fEqWord"

  psShowsPrecMeth <- lookupIdInModule gHC_INTERNAL_SHOW "showsPrec"
  psShowString    <- lookupIdInModule gHC_INTERNAL_SHOW "showString"
  psShowChar      <- lookupIdInModule gHC_INTERNAL_SHOW "showChar"
  psFShowInt      <- lookupIdInModule gHC_INTERNAL_SHOW "$fShowInt"
  psFShowBool     <- lookupIdInModule gHC_INTERNAL_SHOW "$fShowBool"

  psComp <- lookupIdInModule gHC_INTERNAL_BASE "."

  rowFlavourName <- lookupOrig coreMod (mkTcOcc "RowFlavour")
  psRowFlavourCls <- tcLookupClass rowFlavourName

  let ghcRecordsMod = mkModule (moduleUnit gHC_CLASSES) (mkModuleName "GHC.Internal.Records")
  hasFieldOcc <- lookupOrig ghcRecordsMod (mkTcOcc "HasField")
  psHasFieldCls <- tcLookupClass hasFieldOcc

  dictAnyOcc <- lookupOrig coreMod (mkTcOcc "DictAny")
  psDictAnyTyCon <- tcLookupTyCon dictAnyOcc

  psMkDictAny <- lookupIdInModule coreMod "mkDictAny"
  psEvidenceAllFields <- lookupIdInModule coreMod "evidenceAllFields"

  fieldTypesOcc <- lookupOrig coreMod (mkTcOcc "FieldTypes")
  psFieldTypesTyCon <- tcLookupTyCon fieldTypesOcc

  simpleFieldTypesOcc <- lookupOrig coreMod (mkTcOcc "SimpleFieldTypes")
  psSimpleFieldTypesTyCon <- tcLookupTyCon simpleFieldTypesOcc

  fieldNamesOcc <- lookupOrig coreMod (mkTcOcc "FieldNames")
  psFieldNamesTyCon <- tcLookupTyCon fieldNamesOcc

  pure PluginState
    { psRepTag        = psRepTag
    , psRepArity      = psRepArity
    , psFieldAt       = psFieldAt
    , psUnRowRep      = psUnRowRep
    , psNoInlineCo    = psNoInlineCo
    , psEqClass       = psEqClass
    , psAnd           = psAnd
    , psComp          = psComp
    , psShowsPrecMeth = psShowsPrecMeth
    , psShowString    = psShowString
    , psShowChar      = psShowChar
    , psFEqInt        = psFEqInt
    , psFEqBool       = psFEqBool
    , psFEqWord       = psFEqWord
    , psFShowInt      = psFShowInt
    , psFShowBool     = psFShowBool
    , psRowFlavourCls = psRowFlavourCls
    , psHasFieldCls   = psHasFieldCls
    , psDictAnyTyCon  = psDictAnyTyCon
    , psMkDictAny     = psMkDictAny
    , psEvidenceAllFields = psEvidenceAllFields
    , psFieldTypesTyCon       = psFieldTypesTyCon
    , psSimpleFieldTypesTyCon = psSimpleFieldTypesTyCon
    , psFieldNamesTyCon       = psFieldNamesTyCon
    }

findModule :: String -> Maybe String -> TcPluginM 'Init Module
findModule modName mPkg = do
  let modName' = mkModuleName modName
  pkgQual <- resolveImport modName' (fsLit <$> mPkg)
  result <- findImportedModule modName' pkgQual
  case result of
    Found _ mod' -> pure mod'
    _           -> error $ "polytropos: could not find module " ++ modName

findPolytroposCoreModule :: TcPluginM 'Init Module
findPolytroposCoreModule = findModule "Polytropos.Core" (Just "polytropos-core")

lookupIdInModule :: Module -> String -> TcPluginM 'Init Var
lookupIdInModule modName occStr = do
  let occ = mkVarOcc occStr
  name <- lookupOrig modName occ
  tcLookupId name

-------------------------------------------------------------------------------
-- Type family rewriting (FieldNames, SimpleFieldTypes, FieldTypes)
-------------------------------------------------------------------------------

polytroposRewrite :: PluginState -> UniqFM TyCon TcPluginRewriter
polytroposRewrite state = listToUFM
  [ (psFieldTypesTyCon state, rewriteFieldTypes (psFieldTypesTyCon state))
  , (psSimpleFieldTypesTyCon state, rewriteSimpleFieldTypes (psSimpleFieldTypesTyCon state))
  , (psFieldNamesTyCon state, rewriteFieldNames (psFieldNamesTyCon state))
  ]

walkRowFields_maybe :: Type -> Maybe [(FastString, Type)]
walkRowFields_maybe rowTy = do
  elems <- myExtractPromotedList (unwrapSynonyms rowTy)
  mapM extractField elems
  where
    extractField elemTy =
      case splitTyConApp_maybe (unwrapSynonyms elemTy) of
        Just (_, args)
          | length args >= 2
          , let nameTy = args !! (length args - 2)
          , let fieldTy = args !! (length args - 1)
          , Just n <- isStrLitTy (unwrapSynonyms nameTy)
          -> Just (n, fieldTy)
        _ -> Nothing

rewriteFieldNames :: TyCon -> [Ct] -> [Type] -> TcPluginM 'Rewrite TcPluginRewriteResult
rewriteFieldNames tyCon _givens args
  | not (null args)
  , let rowTy = last args
  , Just fields <- walkRowFields_maybe rowTy
  = do
      let names = map (mkStrLitTy . fst) fields
          reducedTy = mkPromotedListTy typeSymbolKind names
      pure $ TcPluginRewriteTo
        { tcRewriterNewWanteds = []
        , tcPluginReduction    =
            mkTyFamAppReduction "polytropos" Nominal [] tyCon args reducedTy
        }
  | otherwise = pure TcPluginNoRewrite

rewriteSimpleFieldTypes :: TyCon -> [Ct] -> [Type] -> TcPluginM 'Rewrite TcPluginRewriteResult
rewriteSimpleFieldTypes tyCon _givens args
  | not (null args)
  , let rowTy = last args
  , Just fields <- walkRowFields_maybe rowTy
  = do
      let pairKind = mkTupleTy Boxed [typeSymbolKind, liftedTypeKind]
          pairs = [ mkPromotedPairTy typeSymbolKind liftedTypeKind (mkStrLitTy name) ty
                  | (name, ty) <- fields
                  ]
          reducedTy = mkPromotedListTy pairKind pairs
      pure $ TcPluginRewriteTo
        { tcRewriterNewWanteds = []
        , tcPluginReduction    =
            mkTyFamAppReduction "polytropos" Nominal [] tyCon args reducedTy
        }
  | otherwise = pure TcPluginNoRewrite

rewriteFieldTypes :: TyCon -> [Ct] -> [Type] -> TcPluginM 'Rewrite TcPluginRewriteResult
rewriteFieldTypes tyCon _givens args
  | length args >= 2
  , let rowTy = last args
  , let fTy   = args !! (length args - 2)
  , Just fields <- walkRowFields_maybe rowTy
  = do
      let pairKind = mkTupleTy Boxed [typeSymbolKind, liftedTypeKind]
          pairs = [ mkPromotedPairTy typeSymbolKind liftedTypeKind (mkStrLitTy name) (mkAppTy fTy ty)
                  | (name, ty) <- fields
                  ]
          reducedTy = mkPromotedListTy pairKind pairs
      pure $ TcPluginRewriteTo
        { tcRewriterNewWanteds = []
        , tcPluginReduction    =
            mkTyFamAppReduction "polytropos" Nominal [] tyCon args reducedTy
        }
  | otherwise = pure TcPluginNoRewrite

-------------------------------------------------------------------------------
-- Constraint solving
-------------------------------------------------------------------------------

polytroposSolve
  :: PluginState
  -> [Ct]
  -> [Ct]
  -> TcPluginM 'Solve TcPluginSolveResult
polytroposSolve state givens wanteds = do
  let allCts = givens ++ wanteds
  results <- mapM (solveOne state) allCts
  let (solvedPairs, _) = partitionEithers results
      solvedCts = map fst solvedPairs
      newCts = concatMap snd solvedPairs
  pure $ TcPluginSolveResult
    { tcPluginInsolubleCts = []
    , tcPluginSolvedCts = solvedCts
    , tcPluginNewCts = newCts
    }

solveOne :: PluginState -> Ct -> TcPluginM 'Solve (Either ((EvTerm, Ct), [Ct]) ())
solveOne state ct
  | not (isWanted (ctEvidence ct))
  = pure $ Right ()
  | otherwise
  = do
    let predTy = ctPred ct
    case classifyPredType predTy of
      ClassPred cls tys -> do
        case className cls of
          name
            | nameOccName name == mkTcOcc "FieldIndex"
            -> noNew <$> solveFieldIndex ct cls tys
            | nameOccName name == mkTcOcc "ConstructorIndex"
            -> noNew <$> solveConstructorIndex ct cls tys
            | nameOccName name == mkTcOcc "RowEq"
            -> noNew <$> solveRowEq state ct cls tys
            | nameOccName name == mkTcOcc "RowShow"
            -> noNew <$> solveRowShow state ct cls tys
            | nameOccName name == mkTcOcc "RowEqSum"
            -> noNew <$> solveRowEqSum state ct cls tys
            | nameOccName name == mkTcOcc "RowShowSum"
            -> noNew <$> solveRowShowSum state ct cls tys
            | nameOccName name == mkTcOcc "HasField"
            -> noNew <$> solveHasField state ct cls tys
            | nameOccName name == mkTcOcc "AllFields"
            -> solveAllFields state ct cls tys
            | otherwise
            -> pure $ Right ()
      _ -> pure $ Right ()
  where
    noNew (Left res) = Left (res, [])
    noNew (Right ()) = Right ()

-------------------------------------------------------------------------------
-- FieldIndex solver
-------------------------------------------------------------------------------

solveFieldIndex
  :: Ct
  -> Class
  -> [Type]
  -> TcPluginM 'Solve (Either (EvTerm, Ct) ())
solveFieldIndex ct cls tys = do
  case tys of
    [_k, nTy, rowTy, _aTy] -> do
      case isStrLitTy (unwrapSynonyms nTy) of
        Just fieldName -> do
          case findFieldIndex fieldName rowTy of
            Just i -> do
              let iExpr = mkCoreConApps intDataCon [Lit (mkLit (fromIntegral i :: Integer))]
                  dictExpr = evDataConApp (classDataCon cls) tys [iExpr]
              pure $ Left (EvExpr dictExpr, ct)
            Nothing -> pure $ Right ()
        Nothing -> pure $ Right ()
    _ -> pure $ Right ()

-------------------------------------------------------------------------------
-- ConstructorIndex solver
-------------------------------------------------------------------------------

solveConstructorIndex
  :: Ct
  -> Class
  -> [Type]
  -> TcPluginM 'Solve (Either (EvTerm, Ct) ())
solveConstructorIndex ct cls tys = do
  case tys of
    [_k, nTy, rowTy] -> do
      case isStrLitTy (unwrapSynonyms nTy) of
        Just conName -> do
          case findConstructorIndex conName rowTy of
            Just w -> do
              let wExpr = mkCoreConApps wordDataCon [Lit (mkLit (fromIntegral w :: Integer))]
                  dictExpr = evDataConApp (classDataCon cls) tys [wExpr]
              pure $ Left (EvExpr dictExpr, ct)
            Nothing -> pure $ Right ()
        Nothing -> pure $ Right ()
    _ -> pure $ Right ()

-------------------------------------------------------------------------------
-- RowEq solver
-------------------------------------------------------------------------------

solveRowEq
  :: PluginState
  -> Ct
  -> Class
  -> [Type]
  -> TcPluginM 'Solve (Either (EvTerm, Ct) ())
solveRowEq state ct cls tys = do
  let rowTy  = last tys
      rTy    = tys !! (length tys - 2)
      fields = walkRowWithTypes rowTy

      scEvidence = evDataConApp (classDataCon (psRowFlavourCls state)) [rTy] []

      repEqId = case classMethods cls of
        (m : _) -> m
        []      -> error "Polytropos.Plugin: RowEq class has no methods"
      methodFullTy = piResultTys (varType repEqId) tys
      (_, _, methodInDictTy) = splitFunTy methodFullTy
      (tyVars, tauTy) = splitForAllTyCoVars methodInDictTy
      (argTys, _) = splitFunTys tauTy
      scaledR1Ty = argTys !! 0
      scaledR2Ty = argTys !! 1

  r1Name <- unsafeLiftTcM $ newName (mkVarOcc "r1")
  r2Name <- unsafeLiftTcM $ newName (mkVarOcc "r2")
  let r1Var = mkLocalId r1Name (scaledMult scaledR1Ty) (scaledThing scaledR1Ty)
      r2Var = mkLocalId r2Name (scaledMult scaledR2Ty) (scaledThing scaledR2Ty)

      kATy   = mkTyVarTy (tyVars !! 0)
      fTy    = mkTyVarTy (tyVars !! 1)
      aTy    = mkTyVarTy (tyVars !! 2)
      kRowTy = typeKind rowTy

      unRowRepTypeArgs = [Type kRowTy, Type kATy, Type fTy, Type rTy, Type rowTy, Type aTy]
      rep1 = mkCoreApps (Var (psUnRowRep state)) (unRowRepTypeArgs ++ [Var r1Var])
      rep2 = mkCoreApps (Var (psUnRowRep state)) (unRowRepTypeArgs ++ [Var r2Var])

      repTypeArgs = [Type kATy, Type fTy, Type aTy]
      tag1 = mkCoreApps (Var (psRepTag state)) (repTypeArgs ++ [rep1])
      tag2 = mkCoreApps (Var (psRepTag state)) (repTypeArgs ++ [rep2])
      eqTag = mkCoreApps (Var (psEqClass state)) [Type (mkTyConTy wordTyCon), Var (psFEqWord state), tag1, tag2]

      arity1 = mkCoreApps (Var (psRepArity state)) (repTypeArgs ++ [rep1])
      arity2 = mkCoreApps (Var (psRepArity state)) (repTypeArgs ++ [rep2])
      eqArity = mkCoreApps (Var (psEqClass state)) [Type intTy, Var (psFEqInt state), arity1, arity2]

      fieldComps = map (compareField rep1 rep2 fTy aTy kATy) fields

      andFn e1 e2 = mkCoreApps (Var (psAnd state)) [e1, e2]
      bodyExpr = foldl andFn (andFn eqTag eqArity) fieldComps
      repEqExpr = mkCoreLams (tyVars ++ [r1Var, r2Var]) bodyExpr

      dictExpr = evDataConApp (classDataCon cls) tys [scEvidence, repEqExpr]
  pure $ Left (EvExpr dictExpr, ct)
  where
    compareField rep1 rep2 fTy aTy kATy (i, _, fieldTy) =
      let fieldAtTypeArgs = [Type kATy, Type fTy, Type aTy, Type fieldTy]
          idxExpr = mkCoreConApps intDataCon [Lit (mkLit (fromIntegral i))]
          raw1 = mkCoreApps (Var (psFieldAt state)) (fieldAtTypeArgs ++ [idxExpr, rep1])
          raw2 = mkCoreApps (Var (psFieldAt state)) (fieldAtTypeArgs ++ [idxExpr, rep2])
          fFieldTy = mkAppTy fTy fieldTy
          val1 = mkCoreApps (Var (psNoInlineCo state)) [Type fFieldTy, Type fieldTy, raw1]
          val2 = mkCoreApps (Var (psNoInlineCo state)) [Type fFieldTy, Type fieldTy, raw2]
          eqDict = getEqDict state fieldTy
      in mkCoreApps (Var (psEqClass state)) [Type fieldTy, eqDict, val1, val2]

-------------------------------------------------------------------------------
-- RowShow solver
-------------------------------------------------------------------------------

solveRowShow
  :: PluginState
  -> Ct
  -> Class
  -> [Type]
  -> TcPluginM 'Solve (Either (EvTerm, Ct) ())
solveRowShow state ct cls tys = do
  let rowTy  = last tys
      rTy    = tys !! (length tys - 2)
      fields = walkRowWithTypes rowTy

      scEvidence = evDataConApp (classDataCon (psRowFlavourCls state)) [rTy] []

      repShowsPrecId = case classMethods cls of
        (m : _) -> m
        []      -> error "Polytropos.Plugin: RowShow class has no methods"
      methodFullTy = piResultTys (varType repShowsPrecId) tys
      (_, _, methodInDictTy) = splitFunTy methodFullTy
      (tyVars, tauTy) = splitForAllTyCoVars methodInDictTy
      (argTys, _) = splitFunTys tauTy
      scaledPrecTy = argTys !! 0
      scaledRTy    = argTys !! 1

  precName <- unsafeLiftTcM $ newName (mkVarOcc "p")
  rName <- unsafeLiftTcM $ newName (mkVarOcc "r")
  let precVar = mkLocalId precName (scaledMult scaledPrecTy) (scaledThing scaledPrecTy)
      rVar    = mkLocalId rName (scaledMult scaledRTy) (scaledThing scaledRTy)

      kATy   = mkTyVarTy (tyVars !! 0)
      fTy    = mkTyVarTy (tyVars !! 1)
      aTy    = mkTyVarTy (tyVars !! 2)
      kRowTy = typeKind rowTy

      unRowRepTypeArgs = [Type kRowTy, Type kATy, Type fTy, Type rTy, Type rowTy, Type aTy]
      rep = mkCoreApps (Var (psUnRowRep state)) (unRowRepTypeArgs ++ [Var rVar])

      rowName = case splitTyConApp_maybe rowTy of
        Just (tc, _)
          | let name = occNameString (getOccName tc)
          , name /= ":" && name /= "[]" && name /= "''[]"
          -> name
        _ -> "R" ++ show (length fields)

  prefixExpr <- unsafeLiftTcM $ mkStringExpr (rowName ++ " ")
  let prefixShowS = mkCoreApps (Var (psShowString state)) [prefixExpr]
      spaceShowS  = mkCoreApps (Var (psShowChar state)) [mkCharExpr ' ']

      fieldShows = map (showField rep fTy aTy kATy) fields
      showParts = case fieldShows of
        [] -> [prefixShowS]
        (f0 : fs) -> prefixShowS : f0 : concatMap (\f -> [spaceShowS, f]) fs

      compFn f g = mkCoreApps (Var (psComp state)) [Type stringTy, Type stringTy, Type stringTy, f, g]
      bodyExpr = foldr1 compFn showParts
      repShowsPrecExpr = mkCoreLams (tyVars ++ [precVar, rVar]) bodyExpr

      dictExpr = evDataConApp (classDataCon cls) tys [scEvidence, repShowsPrecExpr]
  pure $ Left (EvExpr dictExpr, ct)
  where
    showField rep fTy aTy kATy (i, _, fieldTy) =
      let fieldAtTypeArgs = [Type kATy, Type fTy, Type aTy, Type fieldTy]
          idxExpr = mkCoreConApps intDataCon [Lit (mkLit (fromIntegral i))]
          raw = mkCoreApps (Var (psFieldAt state)) (fieldAtTypeArgs ++ [idxExpr, rep])
          fFieldTy = mkAppTy fTy fieldTy
          val = mkCoreApps (Var (psNoInlineCo state)) [Type fFieldTy, Type fieldTy, raw]
          showDict = getShowDict state fieldTy
          zeroPrec = mkCoreConApps intDataCon [Lit (mkLit 0)]
      in mkCoreApps (Var (psShowsPrecMeth state)) [Type fieldTy, showDict, zeroPrec, val]

-------------------------------------------------------------------------------
-- RowEqSum / RowShowSum stubs
-------------------------------------------------------------------------------

solveRowEqSum
  :: PluginState
  -> Ct
  -> Class
  -> [Type]
  -> TcPluginM 'Solve (Either (EvTerm, Ct) ())
solveRowEqSum state ct cls tys = do
  let rowTy  = last tys
      rTy    = tys !! (length tys - 2)
      constructors = walkSumRowWithTypes rowTy

      scEvidence = evDataConApp (classDataCon (psRowFlavourCls state)) [rTy] []

      repEqSumId = case classMethods cls of
        (m : _) -> m
        []      -> error "Polytropos.Plugin: RowEqSum class has no methods"
      methodFullTy = piResultTys (varType repEqSumId) tys
      (_, _, methodInDictTy) = splitFunTy methodFullTy
      (tyVars, tauTy) = splitForAllTyCoVars methodInDictTy
      (argTys, _) = splitFunTys tauTy
      scaledR1Ty = argTys !! 0
      scaledR2Ty = argTys !! 1

  r1Name <- unsafeLiftTcM $ newName (mkVarOcc "r1")
  r2Name <- unsafeLiftTcM $ newName (mkVarOcc "r2")
  let r1Var = mkLocalId r1Name (scaledMult scaledR1Ty) (scaledThing scaledR1Ty)
      r2Var = mkLocalId r2Name (scaledMult scaledR2Ty) (scaledThing scaledR2Ty)

      kATy   = mkTyVarTy (tyVars !! 0)
      fTy    = mkTyVarTy (tyVars !! 1)
      aTy    = mkTyVarTy (tyVars !! 2)
      kRowTy = typeKind rowTy

      unRowRepTypeArgs = [Type kRowTy, Type kATy, Type fTy, Type rTy, Type rowTy, Type aTy]
      rep1 = mkCoreApps (Var (psUnRowRep state)) (unRowRepTypeArgs ++ [Var r1Var])
      rep2 = mkCoreApps (Var (psUnRowRep state)) (unRowRepTypeArgs ++ [Var r2Var])

      repTypeArgs = [Type kATy, Type fTy, Type aTy]
      tag1 = mkCoreApps (Var (psRepTag state)) (repTypeArgs ++ [rep1])
      tag2 = mkCoreApps (Var (psRepTag state)) (repTypeArgs ++ [rep2])
      eqTag = mkCoreApps (Var (psEqClass state)) [Type (mkTyConTy wordTyCon), Var (psFEqWord state), tag1, tag2]

      falseExpr = mkCoreConApps falseDataCon []
      trueExpr  = mkCoreConApps trueDataCon []
      andFn e1 e2 = mkCoreApps (Var (psAnd state)) [e1, e2]

      compareConFields conRowTy =
        let fields = walkRowWithTypes conRowTy
            fieldComps = map (compareField rep1 rep2 fTy aTy kATy) fields
        in foldl andFn trueExpr fieldComps

      buildTree _ [] = falseExpr
      buildTree tagExpr ((i, _conName, conRowTy) : rest) =
        let iLit = mkCoreConApps wordDataCon [Lit (mkLit (fromIntegral i :: Integer))]
            cond = mkCoreApps (Var (psEqClass state)) [Type (mkTyConTy wordTyCon), Var (psFEqWord state), tagExpr, iLit]
        in mkIfThenElse cond (compareConFields conRowTy) (buildTree tagExpr rest)

      bodyExpr = mkIfThenElse eqTag (buildTree tag1 constructors) falseExpr

      repEqSumExpr = mkCoreLams (tyVars ++ [r1Var, r2Var]) bodyExpr

      dictExpr = evDataConApp (classDataCon cls) tys [scEvidence, repEqSumExpr]
  pure $ Left (EvExpr dictExpr, ct)
  where
    compareField rep1 rep2 fTy aTy kATy (i, _, fieldTy) =
      let fieldAtTypeArgs = [Type kATy, Type fTy, Type aTy, Type fieldTy]
          idxExpr = mkCoreConApps intDataCon [Lit (mkLit (fromIntegral i :: Integer))]
          raw1 = mkCoreApps (Var (psFieldAt state)) (fieldAtTypeArgs ++ [idxExpr, rep1])
          raw2 = mkCoreApps (Var (psFieldAt state)) (fieldAtTypeArgs ++ [idxExpr, rep2])
          fFieldTy = mkAppTy fTy fieldTy
          val1 = mkCoreApps (Var (psNoInlineCo state)) [Type fFieldTy, Type fieldTy, raw1]
          val2 = mkCoreApps (Var (psNoInlineCo state)) [Type fFieldTy, Type fieldTy, raw2]
          eqDict = getEqDict state fieldTy
      in mkCoreApps (Var (psEqClass state)) [Type fieldTy, eqDict, val1, val2]

solveRowShowSum
  :: PluginState
  -> Ct
  -> Class
  -> [Type]
  -> TcPluginM 'Solve (Either (EvTerm, Ct) ())
solveRowShowSum state ct cls tys = do
  let rowTy  = last tys
      rTy    = tys !! (length tys - 2)
      constructors = walkSumRowWithTypes rowTy

      scEvidence = evDataConApp (classDataCon (psRowFlavourCls state)) [rTy] []

      repShowsPrecSumId = case classMethods cls of
        (m : _) -> m
        []      -> error "Polytropos.Plugin: RowShowSum class has no methods"
      methodFullTy = piResultTys (varType repShowsPrecSumId) tys
      (_, _, methodInDictTy) = splitFunTy methodFullTy
      (tyVars, tauTy) = splitForAllTyCoVars methodInDictTy
      (argTys, _) = splitFunTys tauTy
      scaledPrecTy = argTys !! 0
      scaledRTy    = argTys !! 1

  precName <- unsafeLiftTcM $ newName (mkVarOcc "p")
  rName <- unsafeLiftTcM $ newName (mkVarOcc "r")
  let precVar = mkLocalId precName (scaledMult scaledPrecTy) (scaledThing scaledPrecTy)
      rVar    = mkLocalId rName (scaledMult scaledRTy) (scaledThing scaledRTy)

      kATy   = mkTyVarTy (tyVars !! 0)
      fTy    = mkTyVarTy (tyVars !! 1)
      aTy    = mkTyVarTy (tyVars !! 2)
      kRowTy = typeKind rowTy

      unRowRepTypeArgs = [Type kRowTy, Type kATy, Type fTy, Type rTy, Type rowTy, Type aTy]
      rep = mkCoreApps (Var (psUnRowRep state)) (unRowRepTypeArgs ++ [Var rVar])

      repTypeArgs = [Type kATy, Type fTy, Type aTy]
      tag = mkCoreApps (Var (psRepTag state)) (repTypeArgs ++ [rep])

      spaceShowS  = mkCoreApps (Var (psShowChar state)) [mkCharExpr ' ']
      compFn f g = mkCoreApps (Var (psComp state)) [Type stringTy, Type stringTy, Type stringTy, f, g]

      showConFields conNameFS conRowTy = do
        let conName = unpackFS conNameFS
        prefixExpr <- unsafeLiftTcM $ mkStringExpr (conName ++ " ")
        let prefixShowS = mkCoreApps (Var (psShowString state)) [prefixExpr]
            fields = walkRowWithTypes conRowTy
            fieldShows = map (showField rep fTy aTy kATy) fields
            showParts = case fieldShows of
              [] -> [prefixShowS]
              (f0 : fs) -> prefixShowS : f0 : concatMap (\f -> [spaceShowS, f]) fs
        pure $ foldr1 compFn showParts

  -- We need to build the tree in TcPluginM 'Solve because of unsafeLiftTcM/mkStringExpr
  let buildTree _tagExpr [] = do
        errorPrefix <- unsafeLiftTcM $ mkStringExpr "??? "
        pure $ mkCoreApps (Var (psShowString state)) [errorPrefix]
      buildTree tagExpr ((i, conNameFS, conRowTy) : rest) = do
        let iLit = mkCoreConApps wordDataCon [Lit (mkLit (fromIntegral i :: Integer))]
            cond = mkCoreApps (Var (psEqClass state)) [Type (mkTyConTy wordTyCon), Var (psFEqWord state), tagExpr, iLit]
        trueBranch <- showConFields conNameFS conRowTy
        falseBranch <- buildTree tagExpr rest
        pure $ mkIfThenElse cond trueBranch falseBranch

  bodyExpr <- buildTree tag constructors
  let repShowsPrecSumExpr = mkCoreLams (tyVars ++ [precVar, rVar]) bodyExpr

      dictExpr = evDataConApp (classDataCon cls) tys [scEvidence, repShowsPrecSumExpr]
  pure $ Left (EvExpr dictExpr, ct)
  where
    showField rep fTy aTy kATy (i, _, fieldTy) =
      let fieldAtTypeArgs = [Type kATy, Type fTy, Type aTy, Type fieldTy]
          idxExpr = mkCoreConApps intDataCon [Lit (mkLit (fromIntegral i :: Integer))]
          raw = mkCoreApps (Var (psFieldAt state)) (fieldAtTypeArgs ++ [idxExpr, rep])
          fFieldTy = mkAppTy fTy fieldTy
          val = mkCoreApps (Var (psNoInlineCo state)) [Type fFieldTy, Type fieldTy, raw]
          showDict = getShowDict state fieldTy
          zeroPrec = mkCoreConApps intDataCon [Lit (mkLit 0)]
      in mkCoreApps (Var (psShowsPrecMeth state)) [Type fieldTy, showDict, zeroPrec, val]

-------------------------------------------------------------------------------
-- HasField solver
-------------------------------------------------------------------------------

solveHasField
  :: PluginState
  -> Ct
  -> Class
  -> [Type]
  -> TcPluginM 'Solve (Either (EvTerm, Ct) ())
solveHasField state ct cls tys = do
  let len = length tys
  if len >= 3 then do
    let fieldTy = last tys
        recTy   = tys !! (len - 2)
        nTy     = tys !! (len - 3)
    case isStrLitTy (unwrapSynonyms nTy) of
      Just fieldName -> do
        case splitTyConApp_maybe (unwrapSynonyms recTy) of
          Just (tc, args)
            | occNameString (getOccName tc) == "RowRep"
            , length args >= 4 -> do
              let aTy   = last args
                  rowTy = args !! (length args - 2)
                  rTy   = args !! (length args - 3)
                  fTy   = args !! (length args - 4)
                  kATy  = typeKind aTy
                  kRowTy = typeKind rowTy
              case splitTyConApp_maybe (unwrapSynonyms rTy) of
                Just (tcR, []) | occNameString (getOccName tcR) `elem` ["ProductRowT", "ProductRowHKDT"] -> do
                  case findFieldType fieldName rowTy of
                    Just (i, actualFieldTy) -> do
                      let getFieldId = case classMethods cls of
                            (m : _) -> m
                            [] -> error "Polytropos.Plugin: HasField has no methods"
                          methodFullTy = piResultTys (varType getFieldId) tys
                          (_, _, methodInDictTy) = splitFunTy methodFullTy
                          (tyVars, tauTy) = splitForAllTyCoVars methodInDictTy
                          (argTys, _) = splitFunTys tauTy
                          scaledRTy = argTys !! 0

                      rName <- unsafeLiftTcM $ newName (mkVarOcc "rec")
                      let rVar = mkLocalId rName (scaledMult scaledRTy) (scaledThing scaledRTy)

                          unRowRepTypeArgs = [Type kRowTy, Type kATy, Type fTy, Type rTy, Type rowTy, Type aTy]
                          rep = mkCoreApps (Var (psUnRowRep state)) (unRowRepTypeArgs ++ [Var rVar])

                          fieldAtTypeArgs = [Type kATy, Type fTy, Type aTy, Type actualFieldTy]
                          idxExpr = mkCoreConApps intDataCon [Lit (mkLit (fromIntegral i :: Integer))]
                          raw = mkCoreApps (Var (psFieldAt state)) (fieldAtTypeArgs ++ [idxExpr, rep])

                          fFieldTy = mkAppTy fTy actualFieldTy
                          val = mkCoreApps (Var (psNoInlineCo state)) [Type fFieldTy, Type fieldTy, raw]

                          getFieldExpr = mkCoreLams (tyVars ++ [rVar]) val
                          dictExpr = evDataConApp (classDataCon cls) tys [getFieldExpr]

                      pure $ Left (EvExpr dictExpr, ct)
                    Nothing -> pure $ Right ()
                _ -> pure $ Right ()
          _ -> pure $ Right ()
      Nothing -> pure $ Right ()
  else pure $ Right ()

-------------------------------------------------------------------------------
-- AllFields solver (generic field-class dictionary supply)
-------------------------------------------------------------------------------

solveAllFields
  :: PluginState
  -> Ct
  -> Class
  -> [Type]
  -> TcPluginM 'Solve (Either ((EvTerm, Ct), [Ct]) ())
solveAllFields state ct cls tys
  | length tys >= 3
  , let rowTy = tys !! (length tys - 2)
  , Just _ <- myExtractPromotedList (unwrapSynonyms rowTy)
  = do
      let cTy    = last tys
          rTy    = tys !! (length tys - 3)
          fields = walkRowWithTypes rowTy
          loc    = ctLoc ct
          dictAnyTy = mkAppTy (mkTyConTy (psDictAnyTyCon state)) cTy

      -- For each field, create a new wanted constraint for (c fieldTy)
      wanteds <- forM fields $ \(_i, _nameFS, fieldTy) -> do
        ev <- newWanted loc (mkAppTy cTy fieldTy)
        pure (fieldTy, ev)

      -- For each field, construct: mkDictAny @c @fieldTy dict
      let dictAnys = [ mkCoreApps (Var (psMkDictAny state))
                                  [Type cTy, Type fieldTy, ctEvExpr ev]
                     | (fieldTy, ev) <- wanteds
                     ]

      -- Construct: evidenceAllFields @c [dictAny_0, dictAny_1, ...]
      let listExpr = mkListExpr dictAnyTy dictAnys
          arrExpr  = mkCoreApps (Var (psEvidenceAllFields state)) [Type cTy, listExpr]

      -- Superclass evidence for RowFlavour r
      let scEvidence = evDataConApp (classDataCon (psRowFlavourCls state)) [rTy] []

      -- Class dictionary: AllFields r row c
      let dictExpr = evDataConApp (classDataCon cls) tys [scEvidence, arrExpr]
          newWanteds = [mkNonCanonical ev | (_fieldTy, ev) <- wanteds]

      pure $ Left ((EvExpr dictExpr, ct), newWanteds)
  | otherwise = pure $ Right ()

-------------------------------------------------------------------------------
-- Row walking
-------------------------------------------------------------------------------

unwrapSynonyms :: Type -> Type
unwrapSynonyms ty = case coreView ty of
  Just ty' -> unwrapSynonyms ty'
  Nothing  -> ty


myExtractPromotedList :: Type -> Maybe [Type]
myExtractPromotedList ty = case splitTyConApp_maybe (unwrapSynonyms ty) of
  Just (tc, [_, x, xs]) | occNameString (getOccName tc) == ":" -> do
    rest <- myExtractPromotedList xs
    return (x : rest)
  Just (tc, [_]) | occNameString (getOccName tc) == "[]" -> Just []
  _ -> Nothing

walkRowWithTypes :: Type -> [(Int, FastString, Type)]
walkRowWithTypes rowTy =
  case myExtractPromotedList (unwrapSynonyms rowTy) of { Just xs -> zipWith extractField [0..] xs; Nothing -> [] }
  where
    extractField i elemTy =
      case splitTyConApp_maybe (unwrapSynonyms elemTy) of
        Just (_, args)
          | length args >= 2
          , let nameTy = args !! (length args - 2)
          , let fieldTy = args !! (length args - 1)
          , Just n <- isStrLitTy (unwrapSynonyms nameTy)
          -> (i, n, fieldTy)
        _ -> error $ "walkRowWithTypes: malformed field entry: " ++ showSDocUnsafe (ppr elemTy)

walkSumRowWithTypes :: Type -> [(Int, FastString, Type)]
walkSumRowWithTypes rowTy =
  case myExtractPromotedList (unwrapSynonyms rowTy) of { Just xs -> zipWith extractCon [0..] xs; Nothing -> [] }
  where
    extractCon i elemTy =
      case splitTyConApp_maybe (unwrapSynonyms elemTy) of
        Just (_, args)
          | length args >= 2
          , let nameTy = args !! (length args - 2)
          , let conRowTy = args !! (length args - 1)
          , Just n <- isStrLitTy (unwrapSynonyms nameTy)
          -> (i, n, conRowTy)
        _ -> error $ "walkSumRowWithTypes: malformed constructor entry: " ++ showSDocUnsafe (ppr elemTy)

findFieldIndex :: FastString -> Type -> Maybe Int
findFieldIndex fieldName rowTy =
  case [i | (i, n, _) <- walkRowWithTypes rowTy, n == fieldName] of
    (i : _) -> Just i
    []      -> Nothing

findConstructorIndex :: FastString -> Type -> Maybe Word
findConstructorIndex conName rowTy =
  case [fromIntegral i | (i, n, _) <- walkSumRowWithTypes rowTy, n == conName] of
    (w : _) -> Just w
    []      -> Nothing

findFieldType :: FastString -> Type -> Maybe (Int, Type)
findFieldType fieldName rowTy =
  case [(i, ty) | (i, n, ty) <- walkRowWithTypes rowTy, n == fieldName] of
    (res : _) -> Just res
    []      -> Nothing

-------------------------------------------------------------------------------
-- Dictionary resolution for basic types
-------------------------------------------------------------------------------

getEqDict :: PluginState -> Type -> CoreExpr
getEqDict state ty
  | ty `eqType` intTy = Var (psFEqInt state)
  | ty `eqType` boolTy = Var (psFEqBool state)
  | ty `eqType` mkTyConTy wordTyCon = Var (psFEqWord state)
  | otherwise = error $ "polytropos: unsupported field type for Eq: " ++ showSDocUnsafe (ppr ty) ++ " (generic field-class dict supply not yet implemented)"

getShowDict :: PluginState -> Type -> CoreExpr
getShowDict state ty
  | ty `eqType` intTy = Var (psFShowInt state)
  | ty `eqType` boolTy = Var (psFShowBool state)
  | otherwise = error $ "polytropos: unsupported field type for Show: " ++ showSDocUnsafe (ppr ty) ++ " (generic field-class dict supply not yet implemented)"

-------------------------------------------------------------------------------
-- Utilities
-------------------------------------------------------------------------------

partitionEithers :: [Either a b] -> ([a], [b])
partitionEithers [] = ([], [])
partitionEithers (Left x : xs) = let (ls, rs) = partitionEithers xs in (x : ls, rs)
partitionEithers (Right y : xs) = let (ls, rs) = partitionEithers xs in (ls, y : rs)

mkLit :: Integer -> Literal
mkLit i = LitNumber LitNumInt i
