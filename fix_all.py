import re

with open("packages/polytropos-plugin/src/Polytropos/Plugin.hs", "r") as f:
    content = f.read()

content = content.replace("isPromotedList", "myIsPromotedList")

my_is_promoted = """
myIsPromotedList :: Type -> Bool
myIsPromotedList ty = case myExtractPromotedList ty of Just _ -> True; Nothing -> False
"""

content = content.replace("myExtractPromotedList :: Type -> Maybe [Type]", my_is_promoted + "\nmyExtractPromotedList :: Type -> Maybe [Type]")

with open("packages/polytropos-plugin/src/Polytropos/Plugin.hs", "w") as f:
    f.write(content)
