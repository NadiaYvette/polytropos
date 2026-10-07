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

content = re.sub(
    r"walkRowWithTypes rowTy =\n  zipWith",
    r"walkRowWithTypes rowTy =\n  if not (isPromotedList (unwrapSynonyms rowTy)) then [] else zipWith",
    content
)

content = re.sub(
    r"walkSumRowWithTypes rowTy =\n  zipWith",
    r"walkSumRowWithTypes rowTy =\n  if not (isPromotedList (unwrapSynonyms rowTy)) then [] else zipWith",
    content
)

# Fix solveFieldIndex
content = re.sub(
    r"\[nTy, rowTy, _aTy\] -> do",
    r"[_k, nTy, rowTy, _aTy] -> do",
    content
)

# Fix solveConstructorIndex
content = re.sub(
    r"\[nTy, rowTy\] -> do",
    r"[_k, nTy, rowTy] -> do",
    content
)

with open("packages/polytropos-plugin/src/Polytropos/Plugin.hs", "w") as f:
    f.write(content)
