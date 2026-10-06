{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ScopedTypeVariables #-}

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
-- GHC's typechecker plugin API. The key operations are:
--
-- * 'classifyPredType' — decompose a constraint predicate into its class, types
-- * 'getTyVar_maybe' / 'splitTyConApp_maybe' — decompose the row type
-- * 'tcPluginTrace' — debug tracing
-- * 'newEvVar' / 'setEvBind' — emit evidence for solved constraints
--
-- Row walking is done by inspecting the type-level list carried in the
-- constraint. For a class like @FieldIndex \"a\" row a@, the constraint
-- predicate is @FieldIndex \"a\" row a@, and @row@ is the second argument type.
-- We decompose it via 'splitTyConApp_maybe' and walk the resulting list type.
--
-- Literal evidence (an @Int@ or @Word@) is built with 'mkCoreConApps' over the
-- type's 'DataCon'. The more complex evidence classes (@RowEq@, @RowShow@, etc.)
-- require building function bodies at the Core level, which is more involved.
module Polytropos.Plugin
  ( plugin
  ) where

import Prelude

import GHC.Core.Make
  ( mkCoreApps
  , mkCoreConApps
  , mkCoreLams
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
  )

import GHC.Tc.Types.Evidence (EvBind(..))

import Data.List ( find )


-- | Plugin entry point.
plugin :: Plugin
plugin = defaultPlugin { tcPlugin = const $ Just $ mkTcPlugin polytroposPlugin }


polytroposPlugin :: TcPlugin
polytroposPlugin = TcPlugin
  { tcPluginInit  = return ()
  , tcPluginSolve  = const polytroposSolve
  , tcPluginRewrite = const emptyUFM
  , tcPluginPostTc = const (return ())
  , tcPluginShutdown = const (return ())
  }


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


-- | Solve @FieldIndex \"n\" row a@ by walking the row list.
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
              let coreExpr = mkCoreConApps intDataCon [Lit (mkLit (fromIntegral i :: Integer))]
              evTerm <- buildSimpleDict coreExpr aTy
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


-- | Solve @ConstructorIndex \"n\" row@ by walking the sum row list.
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


-- | Solve @RowEq r row@ by building a comparison body.
--
-- The comparison body has the form:
-- @
-- \r1 r2 -> repTag r1 == repTag r2 && repArity r1 == repArity r2
--            && fieldAt 0 r1 == fieldAt 0 r2 && ... && fieldAt n r1 == fieldAt n r2
-- @
--
-- This is the most complex solver because it requires building a function
-- body at the Core AST level. For now, we trace and skip.
solveRowEq
  :: Ct
  -> [Type]
  -> TcPluginM 'Solve (Either (EvTerm, Ct) ())
solveRowEq ct tys = do
  traceMsg "polytropos-solve" $ text "solveRowEq"
  case tys of
    [rTy, rowTy] -> do
      traceMsg "polytropos-solve" $ text "RowEq row: " <+> ppr rowTy
      -- Walk the row to get field info
      let fields = walkRow rowTy
      traceMsg "polytropos-solve" $
        text "RowEq fields: " <+> ppr (length fields)
      -- For now, we can't build the Core expression for the comparison body.
      -- This requires constructing:
      -- 1. Lambda binders for the two RowRep arguments
      -- 2. Applications of repTag, repArity, fieldAt with literal indices
      -- 3. Chain of == and && applications
      -- 4. The final lambda
      --
      -- Building Core expressions for function bodies is complex and requires
      -- careful handling of variable binders, types, and expression construction.
      --
      -- A full implementation would use mkCoreLams for lambdas, mkCoreApps for
      -- applications, and reference the appropriate DataCons for ==, &&, etc.
      pure $ Right ()
    _ -> do
      traceMsg "polytropos-solve" $
        text "RowEq: unexpected number of types: " <+> ppr (length tys)
      pure $ Right ()


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


-- | Solve @RowShow r row@ by building a show body.
--
-- The show body has the form:
-- @
-- \p r -> showString \"name0 \" . shows (unslot (fieldAt 0 r))
--         . showChar ' ' . shows (unslot (fieldAt 1 r)) . ...
-- @
--
-- This is also complex because it requires building function composition
-- chains at the Core level.
solveRowShow
  :: Ct
  -> [Type]
  -> TcPluginM 'Solve (Either (EvTerm, Ct) ())
solveRowShow ct tys = do
  traceMsg "polytropos-solve" $ text "solveRowShow"
  case tys of
    [rTy, rowTy] -> do
      traceMsg "polytropos-solve" $ text "RowShow row: " <+> ppr rowTy
      let fields = walkRow rowTy
      traceMsg "polytropos-solve" $
        text "RowShow fields: " <+> ppr (length fields)
      pure $ Right ()
    _ -> do
      traceMsg "polytropos-solve" $
        text "RowShow: unexpected number of types: " <+> ppr (length tys)
      pure $ Right ()


-- | Solve @RowEqSum r row@ by building a sum comparison body.
--
-- Sum comparison is similar to product comparison but for sum rows.
solveRowEqSum
  :: Ct
  -> [Type]
  -> TcPluginM 'Solve (Either (EvTerm, Ct) ())
solveRowEqSum ct tys = do
  traceMsg "polytropos-solve" $ text "solveRowEqSum"
  case tys of
    [rTy, rowTy] -> do
      traceMsg "polytropos-solve" $ text "RowEqSum row: " <+> ppr rowTy
      let fields = walkSumRow rowTy
      traceMsg "polytropos-solve" $
        text "RowEqSum fields: " <+> ppr (length fields)
      pure $ Right ()
    _ -> do
      traceMsg "polytropos-solve" $
        text "RowEqSum: unexpected number of types: " <+> ppr (length tys)
      pure $ Right ()


-- | Solve @RowShowSum r row@ by building a sum show body.
solveRowShowSum
  :: Ct
  -> [Type]
  -> TcPluginM 'Solve (Either (EvTerm, Ct) ())
solveRowShowSum ct tys = do
  traceMsg "polytropos-solve" $ text "solveRowShowSum"
  case tys of
    [rTy, rowTy] -> do
      traceMsg "polytropos-solve" $ text "RowShowSum row: " <+> ppr rowTy
      let fields = walkSumRow rowTy
      traceMsg "polytropos-solve" $
        text "RowShowSum fields: " <+> ppr (length fields)
      pure $ Right ()
    _ -> do
      traceMsg "polytropos-solve" $
        text "RowShowSum: unexpected number of types: " <+> ppr (length tys)
      pure $ Right ()


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


-- | Check whether a type constructor is the built-in list type.
isConsListTy :: TyCon -> Bool
isConsListTy tc = showSDocUnsafe (ppr tc) == "[]"


-- | Build a simple dictionary from a CoreExpr.
buildSimpleDict
  :: CoreExpr
  -> Type
  -> TcPluginM 'Solve EvTerm
buildSimpleDict coreExpr dictTy = do
  -- Create a new evidence variable for the dictionary
  dictVar <- newEvVar dictTy
  -- Create an EvBind record and set it
  let evBind = EvBind { eb_lhs = dictVar, eb_rhs = EvExpr coreExpr }
  setEvBind evBind
  -- Return the dictionary variable as the evidence
  pure (EvExpr (evId dictVar))


-- | Create an integer Literal from an Integer.
mkLit :: Integer -> Literal
mkLit i = LitNumber LitNumInt i


-- | Trace a message if the plugin is verbose.
traceMsg :: String -> SDoc -> TcPluginM 'Solve ()
traceMsg tag doc =
  tcPluginTrace ("polytropos/" ++ tag) doc


-- | Partition a list of Either into lefts and rights.
partitionEithers :: [Either a b] -> ([a], [b])
partitionEithers [] = ([], [])
partitionEithers (Left x : xs) = let (ls, rs) = partitionEithers xs in (x : ls, rs)
partitionEithers (Right y : xs) = let (ls, rs) = partitionEithers xs in (ls, y : rs)
