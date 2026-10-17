{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Tests for the polytropos-beam satellite: a 30-column table exercises
-- tblSkeleton, zipBeamFieldsM lockstep traversal, and allBeamValues. The
-- whole suite (and the 30-column table type itself) compiles in a fraction
-- of a second because the Beamable instance never builds a generic
-- representation tree.
module Main (main) where

import Test.Tasty
import Test.Tasty.HUnit
import Data.Functor.Identity (Identity (..))
import Data.Proxy            (Proxy (..))
import Database.Beam.Schema.Tables (Beamable (..), Columnar' (..), Ignored,
                                    allBeamValues, tableValuesNeeded)
import Polytropos
import Polytropos.Beam
import Polytropos.Core       (RowRep (..), productRep)
import Unsafe.Coerce         (unsafeCoerce)

type Row30 =
  '[ "c00" ':= Int, "c01" ':= Int, "c02" ':= Int, "c03" ':= Int, "c04" ':= Int
   , "c05" ':= Int, "c06" ':= Int, "c07" ':= Int, "c08" ':= Int, "c09" ':= Int
   , "c10" ':= Int, "c11" ':= Int, "c12" ':= Int, "c13" ':= Int, "c14" ':= Int
   , "c15" ':= Int, "c16" ':= Int, "c17" ':= Int, "c18" ':= Int, "c19" ':= Int
   , "c20" ':= Int, "c21" ':= Int, "c22" ':= Int, "c23" ':= Int, "c24" ':= Int
   , "c25" ':= Int, "c26" ':= Int, "c27" ':= Int, "c28" ':= Int, "c29" ':= Int
   ]

-- | Pair column functor for the lockstep-zip test.
newtype PairF x = PairF (x, x)

mkTable :: [Int] -> BeamTable Row30 Identity
mkTable vs = beamTableOfSlots (map (Identity . unsafeCoerce) vs)

recordOf :: [Int] -> Record Row30
recordOf vs = RowRep (productRep (map (Identity . unsafeCoerce) vs))

main :: IO ()
main = defaultMain $ testGroup "Beam Integration"
  [ testCase "skeleton arity for a 30-column table" $
      tableValuesNeeded (Proxy :: Proxy (BeamTable Row30)) @?= 30
  , testCase "skeleton has 30 slots" $
      length (allBeamValues (\(Columnar' _) -> ())
                (tblSkeleton :: BeamTable Row30 Ignored)) @?= 30
  , testCase "default column names from row symbols" $ do
      let ns = fieldNames (Proxy :: Proxy Row30)
      take 3 ns @?= ["c00", "c01", "c02"]
      last ns @?= "c29"
      length ns @?= 30
  , testCase "zipBeamFieldsM zips in lockstep" $ do
      let t1 = mkTable [0 .. 29]
          t2 = mkTable [100 .. 129]
          zipped :: BeamTable Row30 PairF
          zipped = runIdentity $
            zipBeamFieldsM (\(Columnar' x) (Columnar' y) -> pure (Columnar' (PairF (x, y))))
                           t1 t2
          pairs = allBeamValues (\(Columnar' (PairF (x, y))) ->
                                   (unsafeCoerce x :: Int, unsafeCoerce y :: Int))
                                zipped
      pairs @?= zip [0 .. 29] [100 .. 129]
  , testCase "zipBeamFieldsM picks the left table" $ do
      let t1 = mkTable [0 .. 29]
          t2 = mkTable [100 .. 129]
          out :: BeamTable Row30 Identity
          out = runIdentity $
            zipBeamFieldsM (\(Columnar' x) (Columnar' _) -> pure (Columnar' x)) t1 t2
          vals = allBeamValues (\(Columnar' x) -> unsafeCoerce x :: Int) out
      vals @?= [0 .. 29]
  , testCase "allBeamValues roundtrips through a record" $ do
      let rec30 = recordOf ([7, 14, 21, 28] ++ replicate 26 (0 :: Int))
          vals = allBeamValues (\(Columnar' x) -> unsafeCoerce x :: Int)
                               (toBeamTable rec30)
      vals @?= (7 : 14 : 21 : 28 : replicate 26 (0 :: Int))
      fromBeamTable (toBeamTable rec30) `seq` () @?= ()
  , testCase "beam table constructed with REC and updated with REC_UPD" $ do
      let u1 :: Record '[ "id" ':= Int, "username" ':= String ]
          u1 = REC { id = 1, username = "Alice" }
          u2 = (REC_UPD u1) { username = "Bob" }
          tbl = toBeamTable u2
          vals = allBeamValues (\(Columnar' _) -> ()) tbl
      length vals @?= 2
      fromBeamTable tbl @?= u2
  , testCase "HKD record updated with REC_UPD_F" $ do
      let p1 :: RecordF Maybe '[ "id" ':= Maybe Int, "username" ':= Maybe String ]
          p1 = REC_F { id = Just 1, username = Nothing }
          p2 = (REC_UPD_F p1) { username = Just "Bob" }
      p2 @?= REC_F { id = Just 1, username = Just "Bob" }
  ]
