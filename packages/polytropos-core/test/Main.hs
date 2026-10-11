{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -Wno-orphans #-}

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
--
-- The evidence classes now work over 'RowRep' (the row-carrying wrapper) with
-- no 'Proxy' argument, as specified by Phase 1 decision 1c (Case 3) and the
-- Phase 2 sketch (Sketch B). The row flavour ('ProductRowT') and the row data
-- ('R2') are passed as type parameters to the evidence class.
module Main (main) where

import Control.Monad.ST             (runST)
import Data.Functor.Identity        (Identity(..))
import Data.Primitive.SmallArray    (indexSmallArray)
import GHC.Exts                     (Any)
import Test.Tasty                  (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit            (testCase, (@?=))

import Polytropos.Core
import Polytropos

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

-- | A type-level proxy for R2, used to avoid kind issues with type synonyms.
-- The row data parameter of 'RowRep' and the evidence classes expects a type
-- of kind 'Type', but type synonyms for type-level lists can cause kind
-- inference issues. This proxy wraps the type-level list in a 'Proxy' to
-- give it an explicit kind.
--
-- Note: This is a workaround for a GHC kind inference issue. In GHC 9.14,
-- type synonyms for type-level lists may not be recognized as having kind
-- 'Type' in all contexts. Wrapping in 'Proxy' forces the kind to be 'Type'.


{-------------------------------------------------------------------------------
  Hand-written evidence: the plugin's job, done manually
-------------------------------------------------------------------------------}

-- | Field-wise equality for the @R2@ product row.
--
-- This instance is written by hand and stands in for what the TcPlugin will
-- emit. It is deliberately literal: it compares the tags, arities, and the
-- two field slots at fixed indices (0 and 1), with no type-level search.
--
-- The instance is indexed by the row flavour (@ProductRowT@) and the row data
-- (@R2@), as specified by the Phase 2 sketch (Sketch B). The 'RowRep' wrapper
-- carries the row in its type, so no 'Proxy' argument is needed.
instance RowEq ProductRowT R2 where
  repEq (RowRep r1) (RowRep r2) =
    repTag r1 == repTag r2
      && repArity r1 == repArity r2
      && intAt0 r1 == intAt0 r2
      && boolAt1 r1 == boolAt1 r2

-- | Field-wise @Show@ for the @R2@ product row.
--
-- This instance is written by hand and stands in for what the TcPlugin will
-- emit. It renders the row as @"R2 " @ followed by the two field values.
--
-- See 'RowEq R2' for the design rationale.
instance RowShow ProductRowT R2 where
  repShowsPrec _ (RowRep r) =
    showString "R2 " . shows (intAt0 r) . showChar ' ' . shows (boolAt1 r)

-- | Field-wise equality for a sum row with one constructor.
instance RowEqSum SumRowT '[ "neg" := '[ Int ] ] where
  repEqSum (RowRep r1) (RowRep r2) =
    repTag r1 == repTag r2
      && repArity r1 == repArity r2
      && intAt0 r1 == intAt0 r2

{-------------------------------------------------------------------------------
  Fixtures
-------------------------------------------------------------------------------}

-- | @R2@ holding @a = 7@, @b = True@, wrapped in 'RowRep'.
--
-- The 'RowRep' wrapper carries the row flavour (@ProductRowT@) and the row
-- data (@R2@) in its type, so that the evidence classes can work over it
-- without a 'Proxy' argument.
ab :: RowRep Identity ProductRowT R2 (Int, Bool)
ab = RowRep (productRep [slot (7 :: Int), slot True])

{-------------------------------------------------------------------------------
  Tests
-------------------------------------------------------------------------------}

productTests :: TestTree
productTests = testGroup "products"
  [ testCase "a product's tag is zero" $
      repTag (unRowRep ab) @?= 0
  , testCase "arity is the number of fields" $
      repArity (unRowRep ab) @?= 2
  , testCase "fieldAt reads slot 0" $
      unslot (fieldAt 0 (unRowRep ab)) @?= (7 :: Int)
  , testCase "fieldAt reads slot 1" $
      unslot (fieldAt 1 (unRowRep ab)) @?= True
  , testCase "setFieldAt updates index 0 and leaves index 1 unchanged" $ do
      let r = setFieldAt 0 (slot (9 :: Int)) (unRowRep ab)
      unslot (fieldAt 0 r) @?= (9 :: Int)
      unslot (fieldAt 1 r) @?= True
  , testCase "setFieldAt updates index 1 and leaves index 0 unchanged" $ do
      let r = setFieldAt 1 (slot False) (unRowRep ab)
      unslot (fieldAt 0 r) @?= (7 :: Int)
      unslot (fieldAt 1 r) @?= False
  , testCase "setFieldAt preserves tag" $ do
      repTag (setFieldAt 0 (slot (9 :: Int)) (unRowRep ab)) @?= 0
      repTag (setFieldAt 1 (slot False) (unRowRep ab)) @?= 0
  , testCase "setFieldAt preserves arity" $ do
      repArity (setFieldAt 0 (slot (9 :: Int)) (unRowRep ab)) @?= 2
      repArity (setFieldAt 1 (slot False) (unRowRep ab)) @?= 2
  , testCase "setFieldsAt updates multiple fields simultaneously" $ do
      let r = setFieldsAt [(0, slot (42 :: Int)), (1, slot False)] (unRowRep ab)
      unslot (fieldAt 0 r) @?= (42 :: Int)
      unslot (fieldAt 1 r) @?= False
  , testCase "setFieldsAt with empty updates is identity" $ do
      let r = setFieldsAt [] (unRowRep ab)
      unslot (fieldAt 0 r) @?= (7 :: Int)
      unslot (fieldAt 1 r) @?= True
  , testCase "modifyRep executes chained in-place mutations" $ do
      let r = modifyRep (unRowRep ab) $ \m -> do
                writeFieldAt m 0 (slot (99 :: Int))
                writeFieldAt m 1 (slot False)
      unslot (fieldAt 0 r) @?= (99 :: Int)
      unslot (fieldAt 1 r) @?= False
  , testCase "thawRep and freezeRep round-trip" $ do
      let r = runST $ do
                m <- thawRep (unRowRep ab)
                writeFieldAt m 0 (slot (100 :: Int))
                freezeRep m
      unslot (fieldAt 0 r) @?= (100 :: Int)
      unslot (fieldAt 1 r) @?= True
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
         _        -> False) @?= True
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
      repEq ab ab @?= True
  , testCase "repEq detects a differing slot" $
      repEq ab (RowRep (productRep [slot (7 :: Int), slot False])) @?= False
  , testCase "repEqSum detects a differing tag" $
      repEqSum
        (RowRep (injectRep 0 [slot (7 :: Int), slot True]) :: RowRep Identity SumRowT ('[ "neg" := '[ Int ] ]) (Int, Int))
        (RowRep (injectRep 1 [slot (7 :: Int), slot True]) :: RowRep Identity SumRowT ('[ "neg" := '[ Int ] ]) (Int, Int))
        @?= False
  , testCase "repEq detects a differing arity" $
      repEq ab (RowRep (productRep [slot (7 :: Int)])) @?= False
  , testCase "repShowsPrec renders both fields" $
      repShowsPrec 0 ab "" @?= "R2 7 True"
  , testCase "intAt1 sees the rewritten slot" $
      intAt1 (setFieldAt 1 (slot (5 :: Int)) (unRowRep ab)) @?= 5
  ]

{-------------------------------------------------------------------------------
  Consumer API Tests
-------------------------------------------------------------------------------}

type TwoSum = '[ "Neg" ':= '[ "v" ':= Int ], "Pos" ':= '[ "v" ':= Int ] ]
type ResRow = '[ "Neg" ':= '[ "out" ':= Int ], "Pos" ':= '[ "out" ':= Int ] ]

instance ConstructorIndex "Neg" TwoSum where
  constructorIndex = 0

instance ConstructorIndex "Pos" TwoSum where
  constructorIndex = 1

instance ConstructorIndex "Pos" '[ "Pos" ':= '[ "v" ':= Int ] ] where
  constructorIndex = 0

instance ConstructorIndex "Neg" '[ "Neg" ':= '[ "v" ':= Int ] ] where
  constructorIndex = 0

consumerTests :: TestTree
consumerTests = testGroup "consumer api (Polytropos)"
  [ testCase "emptyRecord has arity 0" $
      repArity (unRowRep emptyRecord) @?= 0
  , testCase "insertField builds record" $ do
      let r = insertField (Field @"a") (42 :: Int) emptyRecord
      unslot (fieldAt 0 (unRowRep r)) @?= (42 :: Int)
      repArity (unRowRep r) @?= 1
  , testCase "Variant pattern and injection" $ do
      let r = insertField (Field @"v") (7 :: Int) emptyRecord
          v :: Variant ('[ "Neg" ':= '[ "v" ':= Int ] ])
          v = Variant (Field @"Neg") r
      case v of
        Variant (Field :: Field "Neg") r' -> unslot (fieldAt 0 (unRowRep r')) @?= (7 :: Int)
        _ -> error "Pattern match failed"
  , testCase "peel isolates target constructor" $ do
      let r = insertField (Field @"v") (10 :: Int) emptyRecord
          v = injectVariant (Field @"Neg") r :: Variant TwoSum
      case peel @"Neg" v of
        Right r' -> unslot (fieldAt 0 (unRowRep r')) @?= (10 :: Int)
        Left _   -> error "Expected Right on matching constructor"
  , testCase "peel remaps tag on non-matching constructor" $ do
      let r = insertField (Field @"v") (20 :: Int) emptyRecord
          v = injectVariant (Field @"Pos") r :: Variant TwoSum
      case peel @"Neg" v of
        Left (remV :: Variant '[ "Pos" ':= '[ "v" ':= Int ] ]) ->
          repTag (unRowRep remV) @?= 0
        Right _ -> error "Expected Left on non-matching constructor"
  , testCase "eliminateUniform dispatches to matching handler in O(1)" $ do
      let rNeg = insertField (Field @"v") (7 :: Int) emptyRecord
          rPos = insertField (Field @"v") (7 :: Int) emptyRecord
          vNeg = injectVariant (Field @"Neg") rNeg :: Variant TwoSum
          vPos = injectVariant (Field @"Pos") rPos :: Variant TwoSum
          handlers = insertField (Field @"Neg") (\r -> -(unslot (fieldAt 0 (unRowRep r)) :: Int))
                   $ insertField (Field @"Pos") (\r -> (unslot (fieldAt 0 (unRowRep r)) :: Int))
                   $ emptyRecord
      eliminateUniform handlers vNeg @?= (-7)
      eliminateUniform handlers vPos @?= 7
      matchVariant vNeg handlers @?= (-7)
  , testCase "eliminateUniformM dispatches inside monad" $ do
      let rNeg = insertField (Field @"v") (3 :: Int) emptyRecord
          vNeg = injectVariant (Field @"Neg") rNeg :: Variant TwoSum
          handlersM = insertField (Field @"Neg") (\r -> pure (-(unslot (fieldAt 0 (unRowRep r)) :: Int)))
                    $ insertField (Field @"Pos") (\r -> pure ((unslot (fieldAt 0 (unRowRep r)) :: Int)))
                    $ emptyRecord
      eliminateUniformM handlersM vNeg @?= Just (-3)
  , testCase "eliminate produces heterogeneous Variant result" $ do
      let rNeg = insertField (Field @"v") (4 :: Int) emptyRecord
          rPos = insertField (Field @"v") (4 :: Int) emptyRecord
          vNeg = injectVariant (Field @"Neg") rNeg :: Variant TwoSum
          vPos = injectVariant (Field @"Pos") rPos :: Variant TwoSum
          hHet = insertField (Field @"Neg") (\r -> insertField (Field @"out") (-(unslot (fieldAt 0 (unRowRep r)) :: Int)) emptyRecord)
               $ insertField (Field @"Pos") (\r -> insertField (Field @"out") ((unslot (fieldAt 0 (unRowRep r)) :: Int) * 10) emptyRecord)
               $ emptyRecord
          outNeg = eliminate @_ @ResRow hHet vNeg
          outPos = eliminate @_ @ResRow hHet vPos
      repTag (unRowRep outNeg) @?= 0
      repTag (unRowRep outPos) @?= 1
  ]

{-------------------------------------------------------------------------------
  Milestone T3: Hardware-vectorized SIMD CoW tests (records > 32 fields)
-------------------------------------------------------------------------------}

simdTests :: TestTree
simdTests = testGroup "simd-cow (records > 32 fields)"
  [ testCase "setFieldAt on 64-field record correctly updates index 0" $ do
      let n = 64
          initial = productRep [slot (i :: Int) | i <- [0 .. n - 1]]
          updated = setFieldAt 0 (slot (999 :: Int)) initial
      repArity updated @?= n
      repTag updated @?= 0
      unslot (fieldAt 0 updated) @?= (999 :: Int)
      map (\i -> unslot (fieldAt i updated) :: Int) [1 .. n - 1] @?= [1 .. n - 1]

  , testCase "setFieldAt on 64-field record correctly updates middle and last slots" $ do
      let n = 64
          initial = productRep [slot (i :: Int) | i <- [0 .. n - 1]]
          updMid = setFieldAt 32 (slot (777 :: Int)) initial
          updLast = setFieldAt 63 (slot (888 :: Int)) updMid
      unslot (fieldAt 32 updLast) @?= (777 :: Int)
      unslot (fieldAt 63 updLast) @?= (888 :: Int)
      unslot (fieldAt 0 updLast) @?= (0 :: Int)
      unslot (fieldAt 31 updLast) @?= (31 :: Int)
      unslot (fieldAt 33 updLast) @?= (33 :: Int)

  , testCase "setFieldAt on 100-field record scales cleanly" $ do
      let n = 100
          initial = productRep [slot (i * 2 :: Int) | i <- [0 .. n - 1]]
          updated = setFieldAt 99 (slot (12345 :: Int)) initial
      repArity updated @?= 100
      unslot (fieldAt 99 updated) @?= (12345 :: Int)
      unslot (fieldAt 0 updated) @?= (0 :: Int)
      unslot (fieldAt 50 updated) @?= (100 :: Int)

  , testCase "setFieldsAt batch updates multiple slots in 64-field record" $ do
      let n = 64
          initial = productRep [slot (i :: Int) | i <- [0 .. n - 1]]
          batch = [(0, slot (100 :: Int)), (15, slot (200 :: Int)), (32, slot (300 :: Int)), (63, slot (400 :: Int))]
          updated = setFieldsAt batch initial
      repArity updated @?= 64
      unslot (fieldAt 0 updated) @?= (100 :: Int)
      unslot (fieldAt 15 updated) @?= (200 :: Int)
      unslot (fieldAt 32 updated) @?= (300 :: Int)
      unslot (fieldAt 63 updated) @?= (400 :: Int)
      unslot (fieldAt 1 updated) @?= (1 :: Int)
      unslot (fieldAt 14 updated) @?= (14 :: Int)
      unslot (fieldAt 16 updated) @?= (16 :: Int)
      unslot (fieldAt 31 updated) @?= (31 :: Int)
      unslot (fieldAt 62 updated) @?= (62 :: Int)

  , testCase "setFieldsAt on 100-field record handles sorted and unsorted batches" $ do
      let n = 100
          initial = productRep [slot (i :: Int) | i <- [0 .. n - 1]]
          batch = [(90, slot (990 :: Int)), (10, slot (110 :: Int)), (50, slot (550 :: Int))]
          updated = setFieldsAt batch initial
      repArity updated @?= 100
      unslot (fieldAt 10 updated) @?= (110 :: Int)
      unslot (fieldAt 50 updated) @?= (550 :: Int)
      unslot (fieldAt 90 updated) @?= (990 :: Int)
      unslot (fieldAt 99 updated) @?= (99 :: Int)

  , testCase "MRep fast-path batch write and slice copy on 64-field builder" $ do
      let n = 64
          initial = productRep [slot (i :: Int) | i <- [0 .. n - 1]]
          res = runST $ do
            m <- thawRep initial
            writeFieldsAt m [(5, slot (555 :: Int)), (35, slot (355 :: Int))]
            freezeRep m
      unslot (fieldAt 5 res) @?= (555 :: Int)
      unslot (fieldAt 35 res) @?= (355 :: Int)
      unslot (fieldAt 0 res) @?= (0 :: Int)

  , testCase "MRep newMRep and copyFieldsFrom block copies" $ do
      let n = 64
          src = productRep [slot (i :: Int) | i <- [0 .. n - 1]]
          res = runST $ do
            dst <- newMRep 0 n (slot (0 :: Int))
            copyFieldsFrom src 10 dst 10 40
            freezeRep dst
      unslot (fieldAt 0 res) @?= (0 :: Int)
      unslot (fieldAt 9 res) @?= (0 :: Int)
      unslot (fieldAt 10 res) @?= (10 :: Int)
      unslot (fieldAt 49 res) @?= (49 :: Int)
      unslot (fieldAt 50 res) @?= (0 :: Int)

  , testCase "thawRepSlice and copyMFields between builders" $ do
      let n = 64
          src = productRep [slot (i * 10 :: Int) | i <- [0 .. n - 1]]
          res = runST $ do
            sub <- thawRepSlice src 20 10
            dst <- newMRep 0 10 (slot (0 :: Int))
            copyMFields sub 0 dst 0 10
            freezeRep dst
      repArity res @?= 10
      unslot (fieldAt 0 res) @?= (200 :: Int)
      unslot (fieldAt 9 res) @?= (290 :: Int)
  ]

main :: IO ()
main = defaultMain $ testGroup "polytropos-core"
  [ productTests
  , sumTests
  , evidenceTests
  , consumerTests
  , simdTests
  ]
