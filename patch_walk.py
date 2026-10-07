import re

with open("packages/polytropos-plugin/src/Polytropos/Plugin.hs", "r") as f:
    content = f.read()

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

with open("packages/polytropos-plugin/src/Polytropos/Plugin.hs", "w") as f:
    f.write(content)
