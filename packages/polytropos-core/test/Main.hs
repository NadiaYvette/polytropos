{-# LANGUAGE AllowAmbiguousTypes #-}
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
import Data.Functor.Compose         (Compose(..))
import Data.Functor.Const           (Const(..))
import Data.Functor.Identity        (Identity(..))
import Data.Kind                    (Type)
import Data.Primitive.PrimArray     (sizeofPrimArray)
import Data.Primitive.SmallArray    (indexSmallArray)
import Data.Proxy                   (Proxy(..))
import GHC.Exts                     (Any)
import Test.Tasty                  (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit            (testCase, (@?=))

import Polytropos.Core
import Polytropos
import Polytropos.RowMorph

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

instance AllFields ProductRowT R2 Top where
  fieldDicts = evidenceAllFields [mkDictAny @Top @Int, mkDictAny @Top @Bool]

instance AllFields ProductRowT R2 Show where
  fieldDicts = evidenceAllFields [mkDictAny @Show @Int, mkDictAny @Show @Bool]

-- | Hand-written SubRow witness for testing (sub :- super).
instance SubRow '[ "a" := Int ] R2 where
  subRowIndices = [0]

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
         Just r  -> repArity r == 1
         Nothing -> False) @?= True
  , testCase "projectRep fails on a mismatched tag" $
      (case projectRep 0 (injectRep 1 [slot True]) of
         Just _  -> False
         Nothing -> True) @?= True
  , testCase "projectRep round-trips the payload" $ do
      let got = case projectRep 0 (injectRep 0 [slot (42 :: Int)]) of
                  Just r -> Just (unslot (fieldAt 0 r) :: Int)
                  _      -> Nothing
      got @?= Just 42
  , testCase "projectRep round-trips at a non-zero tag" $ do
      let got = case projectRep 7 (injectRep 7 [slot (11 :: Int)]) of
                  Just r -> Just (unslot (fieldAt 0 r) :: Int)
                  _      -> Nothing
      got @?= Just 11
  , testCase "projectRepList round-trips payload as a list" $ do
      let got = case projectRepList 7 (injectRep 7 [slot (11 :: Int)]) of
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

instance AllFields SumRowT TwoSum Show where
  fieldDicts = evidenceAllFields [mkDictAny @Show @Int, mkDictAny @Show @Int]

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

rowMorphTests :: TestTree
rowMorphTests = testGroup "row-morph"
  [ testCase "unsafeMkRowMorph and indexRowMorph round-trip" $ do
      let m = unsafeMkRowMorph [2, 0, 1] :: RowMorph '[ "c" := Char, "a" := Int, "b" := Bool ] '[ "a" := Int, "b" := Bool, "c" := Char ]
      sizeofPrimArray (unRowMorph m) @?= 3
      indexRowMorph m 0 @?= 2
      indexRowMorph m 1 @?= 0
      indexRowMorph m 2 @?= 1

  , testCase "composeRowMorph fuses morphisms in O(|r1|)" $ do
      let m12 = unsafeMkRowMorph [1, 0] :: RowMorph '[ "b" := Bool, "a" := Int ] '[ "a" := Int, "b" := Bool ]
          m23 = unsafeMkRowMorph [2, 0] :: RowMorph '[ "a" := Int, "b" := Bool ] '[ "b" := Bool, "x" := Char, "a" := Int ]
          m13 = composeRowMorph m12 m23
      sizeofPrimArray (unRowMorph m13) @?= 2
      indexRowMorph m13 0 @?= 0
      indexRowMorph m13 1 @?= 2

  , testCase "gatherRep extracts sub-slots in specified order" $ do
      let full = productRep [slot (10 :: Int), slot True, slot ("hello" :: String)]
          m = unsafeMkRowMorph [2, 0] :: RowMorph '[ "c" := String, "a" := Int ] '[ "a" := Int, "b" := Bool, "c" := String ]
          sub = gatherRep m full
      repArity sub @?= 2
      unslot (fieldAt 0 sub) @?= ("hello" :: String)
      unslot (fieldAt 1 sub) @?= (10 :: Int)

  , testCase "scatterRep overwrites sub-slots in existing rep" $ do
      let full = productRep [slot (10 :: Int), slot True, slot ("hello" :: String)]
          sub = productRep [slot (42 :: Int), slot ("world" :: String)]
          m = unsafeMkRowMorph [0, 2] :: RowMorph '[ "a" := Int, "c" := String ] '[ "a" := Int, "b" := Bool, "c" := String ]
          res = scatterRep m sub full
      repArity res @?= 3
      unslot (fieldAt 0 res) @?= (42 :: Int)
      unslot (fieldAt 1 res) @?= True
      unslot (fieldAt 2 res) @?= ("world" :: String)

  , testCase "gatherRecord and scatterRecord over Record" $ do
      let rFull = insertField (Field @"a") (10 :: Int)
                $ insertField (Field @"b") True
                $ insertField (Field @"c") ("polytropos" :: String)
                $ emptyRecord
          morph = unsafeMkRowMorph [1, 0] :: RowMorph '[ "b" := Bool, "a" := Int ] '[ "a" := Int, "b" := Bool, "c" := String ]
          rSub = gatherRecord morph rFull
      unslot (fieldAt 0 (unRowRep rSub)) @?= True
      unslot (fieldAt 1 (unRowRep rSub)) @?= (10 :: Int)
      let rSub' = insertField (Field @"b") False $ insertField (Field @"a") (99 :: Int) emptyRecord
          rUpdated = scatterRecord morph rSub' rFull
      unslot (fieldAt 0 (unRowRep rUpdated)) @?= (99 :: Int)
      unslot (fieldAt 1 (unRowRep rUpdated)) @?= False
      unslot (fieldAt 2 (unRowRep rUpdated)) @?= ("polytropos" :: String)

  , testCase "executeFrameScatter merges base frame and operation outputs" $ do
      let frameIn = productRep [slot (1 :: Int), slot ("old" :: String)]
          opOut   = productRep [slot ("new" :: String)]
          plan    = unsafeMkFramePlan 2 [0] [0, 1] [1] :: FramePlan '[ "id" := Int, "status" := String ] '[ "id" := Int ] '[ "status" := String ] '[ "id" := Int, "status" := String ]
          frameOut = executeFrameScatter plan frameIn opOut
      repArity frameOut @?= 2
      unslot (fieldAt 0 frameOut) @?= (1 :: Int)
      unslot (fieldAt 1 frameOut) @?= ("new" :: String)

  , testCase "executeFrameRecord merges base frame and operation outputs" $ do
      let fIn = insertField (Field @"id") (1 :: Int)
              $ insertField (Field @"status") ("old" :: String)
              $ emptyRecord
          opOut = insertField (Field @"status") ("new" :: String)
                $ insertField (Field @"extra") True
                $ emptyRecord
          plan = unsafeMkFramePlan 3 [0] [0, 1] [1, 2]
                   :: FramePlan '[ "id" := Int, "status" := String ]
                                '[ "id" := Int ]
                                '[ "status" := String, "extra" := Bool ]
                                '[ "id" := Int, "status" := String, "extra" := Bool ]
          fOut = executeFrameRecord plan fIn opOut
      unslot (fieldAt 0 (unRowRep fOut)) @?= (1 :: Int)
      unslot (fieldAt 1 (unRowRep fOut)) @?= ("new" :: String)
      unslot (fieldAt 2 (unRowRep fOut)) @?= True

  , testCase "SubRow (:-) constraint alias witnesses sub-row projection" $ do
      let witnessSubRow :: forall sub super. (sub :- super) => [Int]
          witnessSubRow = subRowIndices @sub @super
      witnessSubRow @('[ "a" := Int ]) @R2 @?= [0]

  , testCase "RowLayoutDescriptor 2LTT static layout and slot resolution" $ do
      let rldClosed = buildRowLayoutDescriptor ["delta", "alpha", "gamma", "beta"] Nothing
      rldKnownSlots rldClosed @?= [("alpha", 0), ("beta", 1), ("delta", 2), ("gamma", 3)]
      rldOpenTail rldClosed @?= Nothing
      resolveRowSlot rldClosed "beta" @?= StaticSlot 1
      resolveRowSlot rldClosed "gamma" @?= StaticSlot 3
      resolveRowSlot rldClosed "omega" @?= OpenTailSlot "rho_default" "omega"

      let rldOpen = buildRowLayoutDescriptor ["y", "x"] (Just "rho_tail")
      rldKnownSlots rldOpen @?= [("x", 0), ("y", 1)]
      rldOpenTail rldOpen @?= Just "rho_tail"
      resolveRowSlot rldOpen "x" @?= StaticSlot 0
      resolveRowSlot rldOpen "z" @?= OpenTailSlot "rho_tail" "z"
  ]

-- | Mock higher-kinded effect signatures for EffectRowOf testing.
type MockPolyEffect = RowOf Type -> RowOf (RowOf Type) -> Type
data MockStateEff (ins :: RowOf Type) (outs :: RowOf (RowOf Type))
data MockLogEff   (ins :: RowOf Type) (outs :: RowOf (RowOf Type))

type MockEffectRow = EffectRowOf MockPolyEffect
type MyCoreEf = '[ "state" := MockStateEff, "log" := MockLogEff ] :: MockEffectRow

instance FieldIndex "state" MyCoreEf MockStateEff where
  fieldIndex = 0

instance FieldIndex "log" MyCoreEf MockLogEff where
  fieldIndex = 1

instance ConstructorIndex "state" MyCoreEf where
  constructorIndex = 0

instance ConstructorIndex "log" MyCoreEf where
  constructorIndex = 1

effectRowTests :: TestTree
effectRowTests = testGroup "poly-kinded effect rows"
  [ testCase "FieldIndex and ConstructorIndex over EffectRowOf" $ do
      fieldIndex @_ @"state" @MyCoreEf @MockStateEff @?= 0
      fieldIndex @_ @"log" @MyCoreEf @MockLogEff @?= 1
      constructorIndex @_ @"state" @MyCoreEf @?= 0
      constructorIndex @_ @"log" @MyCoreEf @?= 1
  ]

sopTests :: TestTree
sopTests = testGroup "sop combinators (Polytropos.Core.SOP)"
  [ testCase "hcollapse extracts values from Const-wrapped product RowRep" $ do
      let r = RowRep (productRep [Const (10 :: Int), Const (20 :: Int)]) :: RowRep (Const Int) ProductRowT R2 ()
      hcollapse r @?= [10, 20]
      hcollapseFold r @?= [10, 20]

  , testCase "hcollapse extracts active constructor payload from Const-wrapped sum RowRep" $ do
      let s = RowRep (injectRep 1 [Const (42 :: Int)]) :: RowRep (Const Int) SumRowT TwoSum ()
      hcollapse s @?= [42]
      hcollapseFold s @?= [42]

  , testCase "hpure populates product RowRep using Top constraint" $ do
      let p = hpure @R2 (Const (99 :: Int))
      hcollapse p @?= [99, 99]

  , testCase "hpureFromNames populates product RowRep using ReifyFieldNames" $ do
      let p = hpureFromNames @R2 (Const (123 :: Int))
      hcollapse p @?= [123, 123]

  , testCase "hpureArity populates product RowRep with specified length" $ do
      let p = hpureArity 4 (Const ("ok" :: String)) :: RowRep (Const String) ProductRowT R2 ()
      hcollapse p @?= ["ok", "ok", "ok", "ok"]

  , testCase "hcpure populates product RowRep using class constraint" $ do
      let cp = hcpure @Show @R2 (Const ("shown" :: String))
      hcollapse cp @?= ["shown", "shown"]
      let cp_ = hcpure_ (Proxy @Show) (Const ("proxy" :: String)) :: RowRep (Const String) ProductRowT R2 ()
      hcollapse cp_ @?= ["proxy", "proxy"]

  , testCase "hmap and hliftA preserve tag and map over slots" $ do
      let p = RowRep (productRep [slot (1 :: Int), slot (2 :: Int)]) :: RowRep Identity ProductRowT R2 ()
          p' = hmap (\(Identity x) -> Identity (noInlineUnsafeCo ((noInlineUnsafeCo x :: Int) + 10))) p
      unslot (fieldAt 0 (unRowRep p')) @?= (11 :: Int)
      unslot (fieldAt 1 (unRowRep p')) @?= (12 :: Int)

      let s = RowRep (injectRep 1 [slot (5 :: Int)]) :: RowRep Identity SumRowT TwoSum ()
          s' = hliftA (\(Identity x) -> Identity (noInlineUnsafeCo ((noInlineUnsafeCo x :: Int) * 3))) s
      repTag (unRowRep s') @?= 1
      unslot (fieldAt 0 (unRowRep s')) @?= (15 :: Int)

  , testCase "hcmapProduct and hcmapSum apply constrained mapping" $ do
      let p = RowRep (productRep [slot (10 :: Int), slot True]) :: RowRep Identity ProductRowT R2 ()
          shownP = hcmapProduct @Show (\(Identity x) -> Const (show x)) p
      case hcollapse shownP of
        [s0, _] -> s0 @?= "10"
        _       -> error "Expected 2 items"

      let s = RowRep (injectRep 1 [slot (99 :: Int)]) :: RowRep Identity SumRowT TwoSum ()
          shownS = hcmapSum @Show (\(Identity x) -> Const (show x)) s
      hcollapse shownS @?= ["99"]

      let uP = hcmap @Show (\(Const str) -> Const (str ++ "!")) shownP
      case hcollapse uP of
        (s0 : _) -> s0 @?= "10!"
        []       -> error "Expected non-empty list"
      let uS = hcmap @Show (\(Const str) -> Const (str ++ "!")) shownS
      hcollapse uS @?= ["99!"]

  , testCase "hliftA2 and hzipWith pointwise zip product rows" $ do
      let p1 = RowRep (productRep [slot (1 :: Int), slot (2 :: Int)]) :: RowRep Identity ProductRowT R2 ()
          p2 = RowRep (productRep [slot (10 :: Int), slot (20 :: Int)]) :: RowRep Identity ProductRowT R2 ()
          z = hliftA2 (\(Identity x) (Identity y) -> Identity (noInlineUnsafeCo ((noInlineUnsafeCo x :: Int) + (noInlineUnsafeCo y :: Int)))) p1 p2
      unslot (fieldAt 0 (unRowRep z)) @?= (11 :: Int)
      unslot (fieldAt 1 (unRowRep z)) @?= (22 :: Int)

  , testCase "hliftA2Sum succeeds on matching tags and fails on mismatched tags" $ do
      let s1 = RowRep (injectRep 1 [slot (5 :: Int)]) :: RowRep Identity SumRowT TwoSum ()
          s2 = RowRep (injectRep 1 [slot (10 :: Int)]) :: RowRep Identity SumRowT TwoSum ()
          sDiff = RowRep (injectRep 0 [slot (10 :: Int)]) :: RowRep Identity SumRowT TwoSum ()
          zMatch = hliftA2Sum (\(Identity x) (Identity y) -> Identity (noInlineUnsafeCo ((noInlineUnsafeCo x :: Int) + (noInlineUnsafeCo y :: Int)))) s1 s2
      case zMatch of
        Just (RowRep r) -> do
          repTag r @?= 1
          unslot (fieldAt 0 r) @?= (15 :: Int)
        Nothing -> error "Expected Just for matching tags"

      let zMismatch = hliftA2Sum (\(Identity x) (Identity y) -> Identity (noInlineUnsafeCo ((noInlineUnsafeCo x :: Int) + (noInlineUnsafeCo y :: Int)))) s1 sDiff
      case zMismatch of
        Nothing -> pure ()
        Just _  -> error "Expected Nothing for mismatched tags"

  , testCase "hcliftA2 and hczipWith apply constrained binary zip" $ do
      let p1 = RowRep (productRep [slot (1 :: Int), slot True]) :: RowRep Identity ProductRowT R2 ()
          p2 = RowRep (productRep [slot (3 :: Int), slot False]) :: RowRep Identity ProductRowT R2 ()
          cz = hcliftA2 @Show (\(Identity x) (Identity y) -> Const (show x ++ "+" ++ show y)) p1 p2
      hcollapse cz @?= ["1+3", "True+False"]

  , testCase "hliftA3 and hcliftA3 3-way zip product rows" $ do
      let p1 = RowRep (productRep [slot (1 :: Int), slot (2 :: Int)]) :: RowRep Identity ProductRowT R2 ()
          p2 = RowRep (productRep [slot (10 :: Int), slot (20 :: Int)]) :: RowRep Identity ProductRowT R2 ()
          p3 = RowRep (productRep [slot (100 :: Int), slot (200 :: Int)]) :: RowRep Identity ProductRowT R2 ()
          z3 = hliftA3 (\(Identity x) (Identity y) (Identity z) -> Identity (noInlineUnsafeCo ((noInlineUnsafeCo x :: Int) + (noInlineUnsafeCo y :: Int) + (noInlineUnsafeCo z :: Int)))) p1 p2 p3
      unslot (fieldAt 0 (unRowRep z3)) @?= (111 :: Int)
      unslot (fieldAt 1 (unRowRep z3)) @?= (222 :: Int)

  , testCase "hproduct and hunzip roundtrip in single ST pass" $ do
      let p1 = RowRep (productRep [slot (1 :: Int), slot (2 :: Int)]) :: RowRep Identity ProductRowT R2 ()
          p2 = RowRep (productRep [slot ("hello" :: String), slot ("world" :: String)]) :: RowRep Identity ProductRowT R2 ()
          prod = hproduct p1 p2
          (u1, u2) = hunzip prod
      unslot (fieldAt 0 (unRowRep u1)) @?= (1 :: Int)
      unslot (fieldAt 1 (unRowRep u1)) @?= (2 :: Int)
      unslot (fieldAt 0 (unRowRep u2)) @?= ("hello" :: String)
      unslot (fieldAt 1 (unRowRep u2)) @?= ("world" :: String)

  , testCase "hapProduct applies product of functions to product of values" $ do
      let fn1 = Fn (\(Identity x) -> Identity (noInlineUnsafeCo ((noInlineUnsafeCo x :: Int) * 2)))
          fn2 = Fn (\(Identity x) -> Identity (noInlineUnsafeCo ((noInlineUnsafeCo x :: Int) * 10)))
          fns = RowRep (productRep [noInlineUnsafeCo fn1, noInlineUnsafeCo fn2])
                  :: RowRep (Identity -.-> Identity) ProductRowT R2 ()
          args = RowRep (productRep [slot (5 :: Int), slot (6 :: Int)]) :: RowRep Identity ProductRowT R2 ()
          res = hapProduct fns args
      unslot (fieldAt 0 (unRowRep res)) @?= (10 :: Int)
      unslot (fieldAt 1 (unRowRep res)) @?= (60 :: Int)

  , testCase "hapSum dispatches product of functions to sum in O(1)" $ do
      let fn1 = Fn (\(Identity x) -> Identity (noInlineUnsafeCo ((noInlineUnsafeCo x :: Int) * 2)))
          fn2 = Fn (\(Identity x) -> Identity (noInlineUnsafeCo ((noInlineUnsafeCo x :: Int) * 10)))
          fns = RowRep (productRep [noInlineUnsafeCo fn1, noInlineUnsafeCo fn2])
                  :: RowRep (Identity -.-> Identity) ProductRowT TwoSum ()
          argS0 = RowRep (injectRep 0 [slot (7 :: Int)]) :: RowRep Identity SumRowT TwoSum ()
          argS1 = RowRep (injectRep 1 [slot (7 :: Int)]) :: RowRep Identity SumRowT TwoSum ()
          res0 = hapSum fns argS0
          res1 = hapSum fns argS1
      repTag (unRowRep res0) @?= 0
      unslot (fieldAt 0 (unRowRep res0)) @?= (14 :: Int)
      repTag (unRowRep res1) @?= 1
      unslot (fieldAt 0 (unRowRep res1)) @?= (70 :: Int)

  , testCase "helim eliminates sum variant using handler product in O(1)" $ do
      let h1 = Fn (\(Identity x) -> Const (-(noInlineUnsafeCo x :: Int)))
          h2 = Fn (\(Identity x) -> Const ((noInlineUnsafeCo x :: Int) * 100))
          handlers = RowRep (productRep [noInlineUnsafeCo h1, noInlineUnsafeCo h2])
                       :: RowRep (Identity -.-> Const Int) ProductRowT TwoSum ()
          argS0 = RowRep (injectRep 0 [slot (8 :: Int)]) :: RowRep Identity SumRowT TwoSum ()
          argS1 = RowRep (injectRep 1 [slot (8 :: Int)]) :: RowRep Identity SumRowT TwoSum ()
      helim handlers argS0 @?= (-8)
      helim handlers argS1 @?= 800

  , testCase "hfoldMap and hcfoldMap accumulate into monoid" $ do
      let p = RowRep (productRep [slot (1 :: Int), slot True]) :: RowRep Identity ProductRowT R2 ()
          res = hfoldMap (\(Identity _) -> [1 :: Int]) p
      res @?= [1, 1]
      let cfm = hcfoldMap @Show (\(Identity x) -> [show x]) p
      cfm @?= ["1", "True"]

  , testCase "hcfoldMapSum accumulates active constructor into monoid" $ do
      let s = RowRep (injectRep 1 [slot (42 :: Int)]) :: RowRep Identity SumRowT TwoSum ()
          res = hcfoldMapSum @Show (\(Identity x) -> [show x]) s
      res @?= ["42"]

  , testCase "hsequence' and hsequence sequence Applicative effects" $ do
      let compP = RowRep (productRep [Compose (Just (slot (10 :: Int))), Compose (Just (slot (20 :: Int)))])
                    :: RowRep (Compose Maybe Identity) ProductRowT R2 ()
      case hsequence' compP of
        Just r -> do
          unslot (fieldAt 0 (unRowRep r)) @?= (10 :: Int)
          unslot (fieldAt 1 (unRowRep r)) @?= (20 :: Int)
        Nothing -> error "Expected Just"

      let seqP = RowRep (productRep [Just (noInlineUnsafeCo (10 :: Int)), Just (noInlineUnsafeCo (20 :: Int))])
                   :: RowRep Maybe ProductRowT R2 ()
      case hsequence seqP of
        Just r -> do
          unslot (fieldAt 0 (unRowRep r)) @?= (10 :: Int)
          unslot (fieldAt 1 (unRowRep r)) @?= (20 :: Int)
        Nothing -> error "Expected Just"

  , testCase "htraverse and hctraverse traverse Applicative effects" $ do
      let p = RowRep (productRep [slot (1 :: Int), slot (2 :: Int)]) :: RowRep Identity ProductRowT R2 ()
          tRes = htraverse (\(Identity x) -> Just (Identity (noInlineUnsafeCo ((noInlineUnsafeCo x :: Int) + 1)))) p
      case tRes of
        Just r -> do
          unslot (fieldAt 0 (unRowRep r)) @?= (2 :: Int)
          unslot (fieldAt 1 (unRowRep r)) @?= (3 :: Int)
        Nothing -> error "Expected Just"

  , testCase "hindex returns active constructor index in O(1)" $ do
      let s0 = RowRep (injectRep 0 [slot (1 :: Int)]) :: RowRep Identity SumRowT TwoSum ()
          s1 = RowRep (injectRep 1 [slot (2 :: Int)]) :: RowRep Identity SumRowT TwoSum ()
      hindex s0 @?= 0
      hindex s1 @?= 1

  , testCase "hexpand expands sum into Compose Maybe product" $ do
      let s = RowRep (injectRep 1 [slot (99 :: Int)]) :: RowRep Identity SumRowT TwoSum ()
          expanded = hexpand @TwoSum s
      repArity (unRowRep expanded) @?= 2
      case fieldAt 0 (unRowRep expanded) of
        Compose Nothing -> pure ()
        _               -> error "Expected Nothing at slot 0"
      case fieldAt 1 (unRowRep expanded) of
        Compose (Just x) -> unslot x @?= (99 :: Int)
        _                -> error "Expected Just at slot 1"

  , testCase "injections and apInjs sum/product conversions" $ do
      let injs = injections @TwoSum :: RowRep (Identity -.-> Const (RowRep Identity SumRowT TwoSum ())) ProductRowT TwoSum ()
      repArity (unRowRep injs) @?= 2

      let p = RowRep (productRep [slot (10 :: Int), slot (20 :: Int)]) :: RowRep Identity ProductRowT TwoSum ()
          injsList = apInjs p
      case injsList of
        [inj0, inj1] -> do
          repTag (unRowRep inj0) @?= 0
          unslot (fieldAt 0 (unRowRep inj0)) @?= (10 :: Int)
          repTag (unRowRep inj1) @?= 1
          unslot (fieldAt 0 (unRowRep inj1)) @?= (20 :: Int)
        _ -> error "Expected 2 injections"

  , testCase "hhead extracts slot 0" $ do
      let p = RowRep (productRep [slot (77 :: Int), slot (88 :: Int)]) :: RowRep Identity ProductRowT R2 ()
      unslot (hhead p) @?= (77 :: Int)

  , testCase "hcoerce, htoI, hfromI perform zero-copy casts" $ do
      let p = RowRep (productRep [slot (42 :: Int)]) :: RowRep Identity ProductRowT R2 ()
          asI = htoI p
      unI (unslot (fieldAt 0 (unRowRep asI))) @?= (42 :: Int)
      let asId :: RowRep Identity ProductRowT R2 ()
          asId = hfromI asI
      runIdentity (unslot (fieldAt 0 (unRowRep asId))) @?= (42 :: Int)

  , testCase "hfieldNames reifies row symbol names" $ do
      let namesR2 = hfieldNames @R2 :: RowRep (Const String) ProductRowT R2 ()
      hcollapse namesR2 @?= ["a", "b"]
      let namesTwoSum = hfieldNames @TwoSum :: RowRep (Const String) ProductRowT TwoSum ()
      hcollapse namesTwoSum @?= ["Neg", "Pos"]

  , testCase "htoRecord, hfromRecord, htoVariant, hfromVariant bridge facade" $ do
      let p = RowRep (productRep [slot (100 :: Int)]) :: RowRep Identity ProductRowT R2 Int
          recVal = htoRecord p
      repArity (unRowRep recVal) @?= 1
      let p' = hfromRecord recVal :: RowRep Identity ProductRowT R2 Int
      repArity (unRowRep p') @?= 1

      let s = RowRep (injectRep 1 [slot (200 :: Int)]) :: RowRep Identity SumRowT TwoSum Int
          varVal = htoVariant s
      repTag (unRowRep varVal) @?= 1
      let s' = hfromVariant varVal :: RowRep Identity SumRowT TwoSum Int
      repTag (unRowRep s') @?= 1
  ]

main :: IO ()
main = defaultMain $ testGroup "polytropos-core"
  [ productTests
  , sumTests
  , evidenceTests
  , consumerTests
  , simdTests
  , rowMorphTests
  , effectRowTests
  , sopTests
  ]
