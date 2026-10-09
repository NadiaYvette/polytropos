{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | Smoke test: exercise RowEq / RowShow through the TcPlugin on R2.
--
-- This is the acceptance test for Option A: the plugin must emit literal
-- RowEq / RowShow bodies that actually work at runtime, not just compile.

module Main (main) where

import Data.Functor.Identity (Identity(..))
import Data.Kind (Type)
import Data.Primitive.SmallArray (SmallArray, sizeofSmallArray, indexSmallArray)
import Data.Type.Equality ((:~:)(Refl))
import GHC.Exts (Any)
import GHC.TypeLits (Symbol)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

import Polytropos.Core

-- | R2: a two-field product: a :: Int, b :: Bool.
type R2 = '[ "a" := Int, "b" := Bool ]

-- | Store a concrete value in a slot.
slot :: a -> Identity Any
slot = noInlineUnsafeCo

-- | The two values under test.
ab :: RowRep Identity ProductRowT R2 (Int, Bool)
ab = RowRep (productRep [slot (7 :: Int), slot True])

other :: RowRep Identity ProductRowT R2 (Int, Bool)
other = RowRep (productRep [slot (7 :: Int), slot False])

type RD = '[ "x" := Int, "y" := Bool ]
rDot :: RowRep Identity ProductRowT RD (Int, Bool)
rDot = RowRep (productRep [slot (42 :: Int), slot True])

main :: IO ()
main = defaultMain $ testGroup "plugin RowEq/RowShow smoke"
  [ testGroup "Products"
      [ testCase "repEq is reflexive" $
          repEq ab ab @?= True
      , testCase "repEq detects a differing slot" $
          repEq ab other @?= False
      , testCase "repShowsPrec renders both fields" $
          repShowsPrec 0 ab "" @?= "R2 7 True"
      ]
  , testGroup "Sums"
      [ testCase "repEqSum (RowEqSum) matches same constructor and same payload" $
          repEqSum sumC1 sumC1 @?= True
      , testCase "repEqSum (RowEqSum) rejects different payloads in same constructor" $
          repEqSum sumC1 sumC1diff @?= False
      , testCase "repEqSum (RowEqSum) rejects different constructors" $
          repEqSum sumC1 sumC2 @?= False
      , testCase "repShowsPrecSum (RowShowSum) renders C1 properly" $
          repShowsPrecSum 0 sumC1 "" @?= "C1 7"
      , testCase "repShowsPrecSum (RowShowSum) renders C2 properly" $
          repShowsPrecSum 0 sumC2 "" @?= "C2 True"
      ]
  , testGroup "OverloadedRecordDot"
      [ testCase "r.x == 42" $
          rDot.x @?= Identity (42 :: Int)
      , testCase "r.y == True" $
          rDot.y @?= Identity True
      , testCase "rHKD.msg == Just \"ok\" on RecordF Maybe" $
          rHKD.msg @?= Just ("ok" :: String)
      , testCase "rHKD.code == Nothing on RecordF Maybe" $
          rHKD.code @?= (Nothing :: Maybe Int)
      ]
  , testGroup "AllFields generic dictionary supply"
      [ testCase "supplies Show dictionaries for homogeneous product row" $
          let arr = fieldDicts @ProductRowT @TwoInts @Show
          in do
            sizeofSmallArray arr @?= 2
            showAllFields arr (repVals (unRowRep twoInts)) @?= "42 7"
      , testCase "supplies Show dictionaries for heterogeneous product row (String, Int, Bool)" $
          let arr = fieldDicts @ProductRowT @HeteroRow @Show
          in do
            sizeofSmallArray arr @?= 3
            showAllFields arr (repVals (unRowRep heteroVal)) @?= "\"hello\" 99 True"
      , testCase "supplies Show dictionaries for HKD product row (Maybe String, Maybe Int)" $
          let arr = fieldDicts @ProductRowHKDT @(HKDProductRow Maybe) @Show
          in do
            sizeofSmallArray arr @?= 2
            showAllFieldsHKD arr (repVals (unRowRep hkdVal)) @?= "Just \"ok\" Nothing"
      ]
  , testGroup "HKD Row Vocabulary"
      [ testCase "FieldIndex resolves on HKD product row" $ do
          fieldIndex @_ @"msg" @(HKDProductRow Maybe) @(Maybe String) @?= 0
          fieldIndex @_ @"code" @(HKDProductRow Maybe) @(Maybe Int) @?= 1
      , testCase "ConstructorIndex resolves on HKD sum row" $ do
          constructorIndex @_ @"Success" @(HKDSumRow Maybe) @?= 0
          constructorIndex @_ @"Failure" @(HKDSumRow Maybe) @?= 1
      ]
  , testGroup "Type-level row metadata rewriting"
      [ testCase "FieldNames reduces on TwoInts" $
          case namesTwoInts of
            Refl -> pure ()
      , testCase "FieldNames reduces on empty row" $
          case namesEmpty of
            Refl -> pure ()
      , testCase "SimpleFieldTypes reduces on TwoInts" $
          case simpleTypesTwoInts of
            Refl -> pure ()
      , testCase "SimpleFieldTypes reduces on empty row" $
          case simpleTypesEmpty of
            Refl -> pure ()
      , testCase "FieldTypes reduces on TwoInts with Maybe" $
          case fieldTypesTwoInts of
            Refl -> pure ()
      , testCase "FieldTypes reduces on HeteroRow with Identity" $
          case fieldTypesHetero of
            Refl -> pure ()
      , testCase "FieldTypes reduces on empty row" $
          case fieldTypesEmpty of
            Refl -> pure ()
      ]
  ]

-- | Use a supplied array of type-erased Show dictionaries to show every slot.
showAllFields :: DictAllFields Show
              -> SmallArray (Identity Any)
              -> String
showAllFields arr slots =
  go 0
  where
    n = sizeofSmallArray slots
    go i
      | i == n = ""
      | otherwise =
          case indexSmallArray arr i of
            DictAny ->
              let Identity x = indexSmallArray slots i
              in show x <> if i + 1 == n then "" else " " <> go (i + 1)

type TwoInts = '[ "x" := Int, "y" := Int ]
twoInts :: RowRep Identity ProductRowT TwoInts ()
twoInts = RowRep (productRep [slot (42 :: Int), slot (7 :: Int)])

type HeteroRow = '[ "greeting" := String, "count" := Int, "active" := Bool ]
heteroVal :: RowRep Identity ProductRowT HeteroRow ()
heteroVal = RowRep (productRep [slot ("hello" :: String), slot (99 :: Int), slot True])

namesTwoInts :: FieldNames TwoInts :~: '[ "x", "y" ]
namesTwoInts = Refl

namesEmpty :: FieldNames ('[] :: [(Symbol, Type)]) :~: '[]
namesEmpty = Refl

simpleTypesTwoInts :: SimpleFieldTypes TwoInts :~: '[ '("x", Int), '("y", Int) ]
simpleTypesTwoInts = Refl

simpleTypesEmpty :: SimpleFieldTypes ('[] :: [(Symbol, Type)]) :~: '[]
simpleTypesEmpty = Refl

fieldTypesTwoInts :: FieldTypes Maybe TwoInts :~: '[ '("x", Maybe Int), '("y", Maybe Int) ]
fieldTypesTwoInts = Refl

fieldTypesHetero :: FieldTypes Identity HeteroRow :~: '[ '("greeting", Identity String), '("count", Identity Int), '("active", Identity Bool) ]
fieldTypesHetero = Refl

fieldTypesEmpty :: FieldTypes Maybe ('[] :: [(Symbol, Type)]) :~: '[]
fieldTypesEmpty = Refl

-- | S2: a sum with two constructors
type S2 = '[ "C1" := '[ "x" := Int ], "C2" := '[ "y" := Bool ] ]

-- | Ensure the plugin solves these dictionaries (RowEqSum, RowShowSum) for S2.

sumC1 :: RowRep Identity SumRowT S2 a
sumC1 = RowRep (injectRep 0 [slot (7 :: Int)])

sumC1diff :: RowRep Identity SumRowT S2 a
sumC1diff = RowRep (injectRep 0 [slot (8 :: Int)])

sumC2 :: RowRep Identity SumRowT S2 a
sumC2 = RowRep (injectRep 1 [slot True])

type HKDProductRow (f :: Type -> Type) = '[ "msg" := f String, "code" := f Int ] :: ProductRow f

type HKDSumRow (f :: Type -> Type) = '[ "Success" := HKDProductRow f, "Failure" := '[] ] :: SumRowHKD f

slotMaybe :: Maybe a -> Maybe Any
slotMaybe = noInlineUnsafeCo

hkdVal :: RowRep Maybe ProductRowHKDT (HKDProductRow Maybe) ()
hkdVal = RowRep (productRep [slotMaybe (Just ("ok" :: String)), slotMaybe (Nothing :: Maybe Int)])

rHKD :: RowRep Maybe ProductRowHKDT (HKDProductRow Maybe) ()
rHKD = hkdVal

showAllFieldsHKD :: DictAllFields Show
                 -> SmallArray (Maybe Any)
                 -> String
showAllFieldsHKD arr slots =
  go 0
  where
    n = sizeofSmallArray slots
    go i
      | i == n = ""
      | otherwise =
          case indexSmallArray arr i of
            DictAny ->
              let x :: Any
                  x = noInlineUnsafeCo (indexSmallArray slots i)
              in show x <> if i + 1 == n then "" else " " <> go (i + 1)
