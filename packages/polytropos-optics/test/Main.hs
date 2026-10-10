{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# OPTIONS_GHC -Wno-orphans #-}
module Main (main) where

import Test.Tasty
import Test.Tasty.HUnit
import Optics.Core
import Polytropos
import Polytropos.Optics

type MyRec = Record '["foo" ':= Int, "bar" ':= Bool]
type MyVar = Variant '["A" ':= '["foo" ':= Int], "B" ':= '["bar" ':= Bool]]

testRec :: MyRec
testRec = insertField (Field @"foo") (42 :: Int)
        $ insertField (Field @"bar") (True :: Bool)
        $ emptyRecord

testVarA :: MyVar
testVarA = Variant (Field @"A") (insertField (Field @"foo") (42 :: Int) emptyRecord)

testVarB :: MyVar
testVarB = Variant (Field @"B") (insertField (Field @"bar") (True :: Bool) emptyRecord)

main :: IO ()
main = defaultMain $ testGroup "Optics Integration"
  [ testGroup "Record Lenses"
      [ testCase "view field" $ do
          (testRec ^. #foo) @?= (42 :: Int)
          (testRec ^. #bar) @?= (True :: Bool)
      , testCase "set field" $ do
          let r' = testRec & #foo .~ (100 :: Int)
          (r' ^. #foo) @?= (100 :: Int)
          (r' ^. #bar) @?= (True :: Bool)
      , testCase "over field" $ do
          let r' = testRec & #foo %~ (+ (1 :: Int))
          (r' ^. #foo) @?= (43 :: Int)
      ]
  , testGroup "Variant Prisms"
      [ testCase "prism match A" $ do
          let opticA = ctorOptic (Field @"A")
          preview opticA testVarA @?= Just (insertField (Field @"foo") (42 :: Int) emptyRecord)
          preview opticA testVarB @?= (Nothing :: Maybe (Record '["foo" ':= Int]))
      , testCase "prism match B" $ do
          let opticB = ctorOptic (Field @"B")
          preview opticB testVarB @?= Just (insertField (Field @"bar") (True :: Bool) emptyRecord)
          preview opticB testVarA @?= (Nothing :: Maybe (Record '["bar" ':= Bool]))
      , testCase "prism inject roundtrip" $ do
          let opticA = ctorOptic (Field @"A")
              recA = insertField (Field @"foo") (42 :: Int) emptyRecord
          review opticA recA @?= testVarA
      ]
  ]
