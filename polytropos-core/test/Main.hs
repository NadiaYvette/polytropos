{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

-- | Tests for @Polytropos.Core@.
--
-- The 'RowEq' and 'RowShow' instances here are written by hand and stand in for
-- what the TcPlugin will synthesise. They are deliberately literal: a fixed
-- number of slot comparisons at fixed indices, with no type-level search. That
-- is exactly the property the plugin has to reproduce, so these tests double as
-- the specification of what the plugin must emit.
--
-- Representations are built at @f ~ Identity@, where @Rep Identity a@ is
-- isomorphic to @a@ and each slot holds a concrete value. Reading a slot is
-- two coercions — 'fieldAt' yields @Identity x@, then 'unslot' recovers @x@ —
-- and the expected value in each assertion supplies the type @x@. That is
-- precisely the information the plugin will get from the row instead.
module Main (main) where

import Data.Functor.Identity        (Identity(..))
import Data.Primitive.SmallArray    (indexSmallArray)
import Data.Proxy                   (Proxy(..))
import GHC.Exts                     (Any)
import Test.Tasty                  (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit            (testCase, (@?=))

import Polytropos.Core

{-------------------------------------------------------------------------------
  Slot helpers
-------------------------------------------------------------------------------}

-- | Store a concrete value in a slot.
slot :: a -> Identity Any
slot = noInlineUnsafeCo

-- | Read a concrete value out of a slot.
unslot :: Identity Any -> a
unslot = noInlineUnsafeCo

-- | Read slot @0@ as an @Int@.
--
-- Polymorphic in @f@ so the same reader serves both the @Identity@-specialised
-- tests and the polymorphic dictionary bodies.
intAt0 :: forall f a. Rep f a -> Int
intAt0 = noInlineUnsafeCo . indexAt 0

-- | Read slot @1@ as an @Int@.
intAt1 :: forall f a. Rep f a -> Int
intAt1 = noInlineUnsafeCo . indexAt 1

-- | Read slot @1@ as a @Bool@.
boolAt1 :: forall f a. Rep f a -> Bool
boolAt1 = noInlineUnsafeCo . indexAt 1

-- | Read a raw slot.
indexAt :: forall f a. Int -> Rep f a -> f Any
indexAt i r = indexSmallArray (repVals r) i

{-------------------------------------------------------------------------------
  Rows under test
-------------------------------------------------------------------------------}

-- | A two-field product: @a :: Int@, @b :: Bool@.
type R2 = '[ "a" := Int, "b" := Bool ]

{-------------------------------------------------------------------------------
  Hand-written evidence: the plugin's job, done manually
-------------------------------------------------------------------------------}

instance RowEq R2 where
  repEq _ r1 r2 =
    repTag r1 == repTag r2
      && repArity r1 == repArity r2
      && intAt0 r1 == intAt0 r2
      && boolAt1 r1 == boolAt1 r2

instance RowShow R2 where
  repShowsPrec _ _ r =
    showString "R2 " . shows (intAt0 r) . showChar ' ' . shows (boolAt1 r)

{-------------------------------------------------------------------------------
  Fixtures
-------------------------------------------------------------------------------}

-- | @R2@ holding @a = 7@, @b = True@.
ab :: Rep Identity (Int, Bool)
ab = productRep [slot (7 :: Int), slot True]

{-------------------------------------------------------------------------------
  Tests
-------------------------------------------------------------------------------}

productTests :: TestTree
productTests = testGroup "products"
  [ testCase "a product's tag is zero" $
      repTag ab @?= 0
  , testCase "arity is the number of fields" $
      repArity ab @?= 2
  , testCase "fieldAt reads slot 0" $
      unslot (fieldAt 0 ab) @?= (7 :: Int)
  , testCase "fieldAt reads slot 1" $
      unslot (fieldAt 1 ab) @?= True
  , testCase "setFieldAt replaces the addressed slot" $
      unslot (fieldAt 0 (setFieldAt 0 (slot (9 :: Int)) ab)) @?= (9 :: Int)
  , testCase "setFieldAt leaves other slots alone" $
      unslot (fieldAt 1 (setFieldAt 0 (slot (9 :: Int)) ab)) @?= True
  , testCase "setFieldAt leaves the tag alone" $
      repTag (setFieldAt 1 (slot False) ab) @?= 0
  , testCase "setFieldAt leaves the arity alone" $
      repArity (setFieldAt 0 (slot (9 :: Int)) ab) @?= 2
  , testCase "the empty product has arity zero" $
      repArity (productRep ([] :: [Identity Any])) @?= 0
  ]

sumTests :: TestTree
sumTests = testGroup "sums"
  [ testCase "the tag records the constructor index" $
      repTag (injectRep 1 [slot True]) @?= 1
  , testCase "arity is the selected constructor's arity" $
      repArity (injectRep 0 [slot (3 :: Int)]) @?= 1
  , testCase "injectRep preserves the payload" $
      unslot (fieldAt 0 (injectRep 0 [slot (3 :: Int)])) @?= (3 :: Int)
  , testCase "projectRep succeeds on a matching tag" $
      (case projectRep 1 (injectRep 1 [slot True]) of
         Just [_] -> True
         Nothing   -> False) @?= True
  , testCase "projectRep fails on a mismatched tag" $
      (case projectRep 0 (injectRep 1 [slot True]) of
         Just _  -> False
         Nothing -> True) @?= True
  , testCase "projectRep round-trips the payload" $ do
      let got = case projectRep 0 (injectRep 0 [slot (42 :: Int)]) of
                  Just [x] -> Just (unslot (x :: Identity Any) :: Int)
                  _        -> Nothing
      got @?= Just 42
  , testCase "projectRep round-trips at a non-zero tag" $ do
      let got = case projectRep 7 (injectRep 7 [slot (11 :: Int)]) of
                  Just [x] -> Just (unslot (x :: Identity Any) :: Int)
                  _        -> Nothing
      got @?= Just 11
  , testCase "matchRep observes the tag" $
      matchRep (\t _ -> t) (injectRep 3 []) @?= (3 :: Word)
  , testCase "matchRep observes the payload" $
      matchRep (\_ xs -> length xs) (injectRep 0 [slot (1 :: Int), slot (2 :: Int)])
        @?= 2
  , testCase "constructors of different arity coexist" $
      map repArity [injectRep 0 [slot (1 :: Int)], injectRep 1 [slot True, slot False]]
        @?= [1, 2]
  ]

evidenceTests :: TestTree
evidenceTests = testGroup "evidence classes (hand-written)"
  [ testCase "repEq is reflexive" $
      repEq (Proxy :: Proxy R2) ab ab @?= True
  , testCase "repEq detects a differing slot" $
      repEq (Proxy :: Proxy R2) ab (productRep [slot (7 :: Int), slot False]) @?= False
  , testCase "repEq detects a differing tag" $
      repEq (Proxy :: Proxy R2) (injectRep 0 [slot (7 :: Int), slot True])
           (injectRep 1 [slot (7 :: Int), slot True]) @?= False
  , testCase "repEq detects a differing arity" $
      repEq (Proxy :: Proxy R2) ab (productRep [slot (7 :: Int)]) @?= False
  , testCase "repShowsPrec renders both fields" $
      repShowsPrec (Proxy :: Proxy R2) 0 ab "" @?= "R2 7 True"
  , testCase "intAt1 sees the rewritten slot" $
      intAt1 (setFieldAt 1 (slot (5 :: Int)) ab) @?= 5
  ]

main :: IO ()
main = defaultMain $ testGroup "polytropos-core"
  [ productTests
  , sumTests
  , evidenceTests
  ]
