{-# LANGUAGE DataKinds #-}
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
import GHC.Exts (Any)
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
      ]
  ]

-- | S2: a sum with two constructors
type S2 = '[ "C1" := '[ "x" := Int ], "C2" := '[ "y" := Bool ] ]

-- | Ensure the plugin solves these dictionaries (RowEqSum, RowShowSum) for S2.

sumC1 :: RowRep Identity SumRowT S2 a
sumC1 = RowRep (injectRep 0 [slot (7 :: Int)])

sumC1diff :: RowRep Identity SumRowT S2 a
sumC1diff = RowRep (injectRep 0 [slot (8 :: Int)])

sumC2 :: RowRep Identity SumRowT S2 a
sumC2 = RowRep (injectRep 1 [slot True])
