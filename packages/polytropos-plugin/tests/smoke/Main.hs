{-# LANGUAGE DataKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

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

main :: IO ()
main = defaultMain $ testGroup "plugin RowEq/RowShow smoke"
  [ testCase "repEq is reflexive" $
      repEq ab ab @?= True
  , testCase "repEq detects a differing slot" $
      repEq ab other @?= False
  , testCase "repShowsPrec renders both fields" $
      repShowsPrec 0 ab "" @?= "R2 7 True"
  ]
