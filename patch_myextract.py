import re

with open("packages/polytropos-plugin/src/Polytropos/Plugin.hs", "r") as f:
    content = f.read()

content = content.replace("extractPromotedList\n  , isPromotedListTyCon", "extractPromotedList")

# Re-implement myExtractPromotedList safely
my_extract = """
myExtractPromotedList :: Type -> Maybe [Type]
myExtractPromotedList ty = case splitTyConApp_maybe (unwrapSynonyms ty) of
  Just (tc, [_, x, xs]) | occNameString (getOccName tc) == ":" -> do
    rest <- myExtractPromotedList xs
    return (x : rest)
  Just (tc, [_]) | occNameString (getOccName tc) == "[]" -> Just []
  _ -> Nothing

"""
content = content.replace("isPromotedList :: Type -> Bool", my_extract + "isPromotedList :: Type -> Bool")
content = re.sub(r"isPromotedList .*?False\n+", "", content, flags=re.MULTILINE)

content = re.sub(
    r"if not \(isPromotedList \(unwrapSynonyms rowTy\)\) then \[\] else zipWith extractField \[0\.\.\] \(extractPromotedList \(unwrapSynonyms rowTy\)\)",
    r"case myExtractPromotedList (unwrapSynonyms rowTy) of { Just xs -> zipWith extractField [0..] xs; Nothing -> [] }",
    content
)

content = re.sub(
    r"if not \(isPromotedList \(unwrapSynonyms rowTy\)\) then \[\] else zipWith extractCon \[0\.\.\] \(extractPromotedList \(unwrapSynonyms rowTy\)\)",
    r"case myExtractPromotedList (unwrapSynonyms rowTy) of { Just xs -> zipWith extractCon [0..] xs; Nothing -> [] }",
    content
)


with open("packages/polytropos-plugin/src/Polytropos/Plugin.hs", "w") as f:
    f.write(content)
