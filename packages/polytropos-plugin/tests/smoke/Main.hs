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
import Data.Primitive.SmallArray (indexSmallArray)
import GHC.Exts (Any)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

import Polytropos.Core

-- | R2: a two-field product: a :: Int, b :: Bool.
type R2 = '[ "a" := Int, "b" := Bool ]

-- | Store a concrete value in a slot.
slot :: a -> Identity Any
slot = noInlineUnsafeCo

-- | Read a concrete value out of a slot.
unslot :: Identity Any -> a
unslot = noInlineUnsafeCo

-- | Read slot 0 as an Int.
intAt0 :: forall f a. Rep f a -> Int
intAt0 = noInlineUnsafeCo . indexAt 0
  where
    indexAt :: forall f a. Int -> Rep f a -> f Any
    indexAt i r = indexSmallArray (repVals r) i

-- | Read slot 1 as a Bool.
boolAt1 :: forall f a. Rep f a -> Bool
boolAt1 = noInlineUnsafeCo . indexAt 1
  where
    indexAt :: forall f a. Int -> Rep f a -> f Any
    indexAt i r = indexSmallArray (repVals r) i

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
