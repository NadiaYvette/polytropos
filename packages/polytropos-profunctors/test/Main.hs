{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Main (main) where

import Test.Tasty
import Test.Tasty.HUnit

import Polytropos
import Polytropos.Profunctors

type MyRec = Record '["foo" ':= Int, "bar" ':= Bool]
type MyVar = Variant '["A" ':= '["foo" ':= Int], "B" ':= '["bar" ':= Bool]]

testRec :: MyRec
testRec = REC { foo = 42 :: Int, bar = True }

testVarA :: MyVar
testVarA = injectVariant (Field @"A") (REC { foo = 42 :: Int })

testVarB :: MyVar
testVarB = injectVariant (Field @"B") (REC { bar = True })

main :: IO ()
main = defaultMain $ testGroup "Polytropos Profunctors Integration"
  [ testGroup "Record Field Lenses"
      [ testCase "view field via fieldLens" $ do
          view (fieldLens (Field @"foo")) testRec @?= (42 :: Int)
          view (fieldLens (Field @"bar")) testRec @?= True
      , testCase "set field via fieldLens" $ do
          let r' = set (fieldLens (Field @"foo")) (100 :: Int) testRec
          view (fieldLens (Field @"foo")) r' @?= (100 :: Int)
          view (fieldLens (Field @"bar")) r' @?= True
      , testCase "over field via fieldLens" $ do
          let r' = over (fieldLens (Field @"foo")) (+ 1) testRec
          view (fieldLens (Field @"foo")) r' @?= (43 :: Int)
      ]
  , testGroup "Variant Constructor Prisms"
      [ testCase "preview ctorPrism match A" $ do
          let pA :: Prism' MyVar (Record '["foo" ':= Int])
              pA = ctorPrism (Field @"A")
          preview pA testVarA @?= Just (REC { foo = 42 :: Int })
          preview pA testVarB @?= (Nothing :: Maybe (Record '["foo" ':= Int]))
      , testCase "preview ctorPrism match B" $ do
          let pB :: Prism' MyVar (Record '["bar" ':= Bool])
              pB = ctorPrism (Field @"B")
          preview pB testVarB @?= Just (REC { bar = True })
          preview pB testVarA @?= (Nothing :: Maybe (Record '["bar" ':= Bool]))
      , testCase "review ctorPrism inject" $ do
          let pA :: Prism' MyVar (Record '["foo" ':= Int])
              pA = ctorPrism (Field @"A")
              recA = REC { foo = 42 :: Int }
          review pA recA @?= testVarA
      ]
  , testGroup "Low-Level Structural Slot & Tag Optics"
      [ testCase "view & set via typedSlotLens" $ do
          let l0 :: Lens' MyRec Int
              l0 = typedSlotLens 0
              l1 :: Lens' MyRec Bool
              l1 = typedSlotLens 1
          view l0 testRec @?= (42 :: Int)
          view l1 testRec @?= True
          let updated = set l0 (999 :: Int) testRec
          view l0 updated @?= (999 :: Int)
          view l1 updated @?= True
      , testCase "preview via typedVariantPrism" $ do
          let p0 :: Prism' MyVar Int
              p0 = typedVariantPrism 0
              p1 :: Prism' MyVar Bool
              p1 = typedVariantPrism 1
          preview p0 testVarA @?= Just (42 :: Int)
          preview p1 testVarA @?= (Nothing :: Maybe Bool)
          preview p1 testVarB @?= Just True
      ]
  ]
