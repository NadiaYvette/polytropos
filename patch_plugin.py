import re

with open("packages/polytropos-plugin/src/Polytropos/Plugin.hs", "r") as f:
    content = f.read()

# Add isPromotedListTyCon to imports
content = content.replace("extractPromotedList", "extractPromotedList\n  , isPromotedListTyCon")

# Add isPromotedList definition
is_promoted_list = """
isPromotedList :: Type -> Bool
isPromotedList ty = case splitTyConApp_maybe (unwrapSynonyms ty) of Just (tc, _) -> isPromotedListTyCon tc; Nothing -> False

"""
content = content.replace("walkRowWithTypes :: Type -> [(Int, FastString, Type)]", is_promoted_list + "walkRowWithTypes :: Type -> [(Int, FastString, Type)]")

# Fix solveFieldIndex
content = re.sub(
    r"(\[\_k, nTy, rowTy, \_aTy\] -> do\s*)case isStrLitTy \(unwrapSynonyms nTy\) of\s*Just fieldName -> do",
    r"\1case (isStrLitTy (unwrapSynonyms nTy), isPromotedList (unwrapSynonyms rowTy)) of\n        (Just fieldName, True) -> do",
    content, flags=re.MULTILINE
)

# Fix solveConstructorIndex
content = re.sub(
    r"(\[\_k, nTy, rowTy\] -> do\s*)case isStrLitTy \(unwrapSynonyms nTy\) of\s*Just conName -> do",
    r"\1case (isStrLitTy (unwrapSynonyms nTy), isPromotedList (unwrapSynonyms rowTy)) of\n        (Just conName, True) -> do",
    content, flags=re.MULTILINE
)

# Fix RowEq
content = re.sub(
    r"solveRowEq state ct cls tys = do\s*let rowTy  = last tys\s*rTy    = tys !! \(length tys - 2\)",
    r"solveRowEq state ct cls tys = do\n  let rowTy  = last tys\n      rTy    = tys !! (length tys - 2)\n  if not (isPromotedList (unwrapSynonyms rowTy)) then pure (Right ()) else do",
    content, flags=re.MULTILINE
)

# Fix RowShow
content = re.sub(
    r"solveRowShow state ct cls tys = do\s*let rowTy = last tys\s*rTy   = tys !! \(length tys - 2\)",
    r"solveRowShow state ct cls tys = do\n  let rowTy = last tys\n      rTy   = tys !! (length tys - 2)\n  if not (isPromotedList (unwrapSynonyms rowTy)) then pure (Right ()) else do",
    content, flags=re.MULTILINE
)

# Fix RowEqSum
content = re.sub(
    r"solveRowEqSum state ct cls tys = do\s*let rowTy = last tys\s*rTy   = tys !! \(length tys - 2\)",
    r"solveRowEqSum state ct cls tys = do\n  let rowTy = last tys\n      rTy   = tys !! (length tys - 2)\n  if not (isPromotedList (unwrapSynonyms rowTy)) then pure (Right ()) else do",
    content, flags=re.MULTILINE
)

# Fix RowShowSum
content = re.sub(
    r"solveRowShowSum state ct cls tys = do\s*let rowTy = last tys\s*rTy   = tys !! \(length tys - 2\)",
    r"solveRowShowSum state ct cls tys = do\n  let rowTy = last tys\n      rTy   = tys !! (length tys - 2)\n  if not (isPromotedList (unwrapSynonyms rowTy)) then pure (Right ()) else do",
    content, flags=re.MULTILINE
)

with open("packages/polytropos-plugin/src/Polytropos/Plugin.hs", "w") as f:
    f.write(content)
