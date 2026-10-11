{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE OverloadedRecordDot #-}
module ModernizerFixtures where

import GHC.Records

-- Test Fixtures for Polytropos HLint and Modernization Rules

-- 1. getField -> r.field
testRecordDot r = getField @"name" r

-- 2. Chained setField -> batch update
testChainedSetField r u v = setField @"x" u (setField @"y" v r)

-- 3. Repeated setField in foldl -> MRep builder
testFoldSetField xs r = foldl (\acc (k, v) -> setField k v acc) r xs

-- 4. narrowVariant case -> peel
testPeel v = case narrowVariant v of { Just a -> 1; Nothing -> 2 }

-- 5. matchVariant -> eliminateUniform
testEliminate v h = matchVariant v h

-- 6. Redundant widenVariant
testRedundantWiden v = widenVariant v

-- 7. Nested insertField -> REC sugar
testInsertField u v = insertField @"x" u (insertField @"y" v emptyRecord)

-- 8. narrowVariant extraction -> VAR pattern
testVarPattern v = case narrowVariant v of Just y -> y
