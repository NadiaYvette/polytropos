{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Module: Main
-- Description: Runtime microbenchmarks for Polytropos vs native nominal ADTs and Data.Map
--
-- Run with allocation tracking enabled:
--   cabal v2-bench polytropos-bench --benchmark-options='--csv=dist-newstyle/polytropos-bench.csv +RTS -T -RTS'
module Main (main) where

import Control.DeepSeq (NFData(..))
import GHC.Generics (Generic)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Polytropos
import Polytropos.Core (RowRep(..))
import Test.Tasty.Bench

-- | Stand-in NFData instance for Polytropos records in microbenchmarks.
instance NFData (RowRep f r row a) where
  rnf (RowRep _) = ()

-- ============================================================================
-- N = 4 Models
-- ============================================================================

data Nom4 = Nom4
  { n4_0 :: {-# UNPACK #-} !Int
  , n4_1 :: {-# UNPACK #-} !Int
  , n4_2 :: {-# UNPACK #-} !Int
  , n4_3 :: {-# UNPACK #-} !Int
  } deriving (Eq, Show, Generic, NFData)

type Poly4 = Record '["f0" ':= Int, "f1" ':= Int, "f2" ':= Int, "f3" ':= Int]

{-# NOINLINE sumNom4 #-}
sumNom4 :: Nom4 -> Int
sumNom4 r = n4_0 r + n4_1 r + n4_2 r + n4_3 r

{-# NOINLINE sumPoly4 #-}
sumPoly4 :: Poly4 -> Int
sumPoly4 r = r.f0 + r.f1 + r.f2 + r.f3

{-# NOINLINE sumMap4 #-}
sumMap4 :: Map Text Int -> Int
sumMap4 m =
  Map.findWithDefault 0 "f0" m
    + Map.findWithDefault 0 "f1" m
    + Map.findWithDefault 0 "f2" m
    + Map.findWithDefault 0 "f3" m

{-# NOINLINE updateNom4 #-}
updateNom4 :: Nom4 -> Nom4
updateNom4 r = r { n4_2 = 99 }

{-# NOINLINE updatePoly4 #-}
updatePoly4 :: Poly4 -> Poly4
updatePoly4 r = REC_UPD r { f2 = 99 :: Int }

-- ============================================================================
-- N = 16 Models
-- ============================================================================

data Nom16 = Nom16
  { n16_0  :: {-# UNPACK #-} !Int
  , n16_1  :: {-# UNPACK #-} !Int
  , n16_2  :: {-# UNPACK #-} !Int
  , n16_3  :: {-# UNPACK #-} !Int
  , n16_4  :: {-# UNPACK #-} !Int
  , n16_5  :: {-# UNPACK #-} !Int
  , n16_6  :: {-# UNPACK #-} !Int
  , n16_7  :: {-# UNPACK #-} !Int
  , n16_8  :: {-# UNPACK #-} !Int
  , n16_9  :: {-# UNPACK #-} !Int
  , n16_10 :: {-# UNPACK #-} !Int
  , n16_11 :: {-# UNPACK #-} !Int
  , n16_12 :: {-# UNPACK #-} !Int
  , n16_13 :: {-# UNPACK #-} !Int
  , n16_14 :: {-# UNPACK #-} !Int
  , n16_15 :: {-# UNPACK #-} !Int
  } deriving (Eq, Show, Generic, NFData)

type Poly16 = Record
  '[ "f0" ':= Int, "f1" ':= Int, "f2" ':= Int, "f3" ':= Int
   , "f4" ':= Int, "f5" ':= Int, "f6" ':= Int, "f7" ':= Int
   , "f8" ':= Int, "f9" ':= Int, "f10" ':= Int, "f11" ':= Int
   , "f12" ':= Int, "f13" ':= Int, "f14" ':= Int, "f15" ':= Int
   ]

{-# NOINLINE accessNom16 #-}
accessNom16 :: Nom16 -> Int
accessNom16 r = n16_0 r + n16_8 r + n16_15 r

{-# NOINLINE accessPoly16 #-}
accessPoly16 :: Poly16 -> Int
accessPoly16 r = r.f0 + r.f8 + r.f15

{-# NOINLINE accessMap16 #-}
accessMap16 :: Map Text Int -> Int
accessMap16 m =
  Map.findWithDefault 0 "f0" m
    + Map.findWithDefault 0 "f8" m
    + Map.findWithDefault 0 "f15" m

{-# NOINLINE updateNom16 #-}
updateNom16 :: Nom16 -> Nom16
updateNom16 r = r { n16_8 = 99 }

{-# NOINLINE updatePoly16 #-}
updatePoly16 :: Poly16 -> Poly16
updatePoly16 r = REC_UPD r { f8 = 99 :: Int }

-- ============================================================================
-- MergeMorph Models (N=4 + N=4 -> N=8)
-- ============================================================================

type PolyLeft = Record '["a0" ':= Int, "a1" ':= Int, "a2" ':= Int, "a3" ':= Int]
type PolyRight = Record '["b0" ':= Int, "b1" ':= Int, "b2" ':= Int, "b3" ':= Int]

{-# NOINLINE morphDisjoint #-}
morphDisjoint :: PolyLeft -> PolyRight -> Record '["a0" ':= Int, "a1" ':= Int, "a2" ':= Int, "a3" ':= Int, "b0" ':= Int, "b1" ':= Int, "b2" ':= Int, "b3" ':= Int]
morphDisjoint l r = l <+> r

-- ============================================================================
-- Main Benchmark Suite
-- ============================================================================

main :: IO ()
main = defaultMain
  [ bgroup "record-access/N4"
      [ env (pure (Nom4 1 2 3 4)) $ \r ->
          bench "nominal/Nom4" $ whnf sumNom4 r
      , env (pure (REC { f0 = 1 :: Int, f1 = 2 :: Int, f2 = 3 :: Int, f3 = 4 :: Int } :: Poly4)) $ \r ->
          bench "polytropos/Poly4" $ whnf sumPoly4 r
      , env (pure (Map.fromList [("f0", 1), ("f1", 2), ("f2", 3), ("f3", 4)])) $ \m ->
          bench "containers/Map4" $ whnf sumMap4 m
      ]
  , bgroup "record-update/N4"
      [ env (pure (Nom4 1 2 3 4)) $ \r ->
          bench "nominal/Nom4" $ whnf updateNom4 r
      , env (pure (REC { f0 = 1 :: Int, f1 = 2 :: Int, f2 = 3 :: Int, f3 = 4 :: Int } :: Poly4)) $ \r ->
          bench "polytropos/Poly4" $ whnf updatePoly4 r
      ]
  , bgroup "record-access/N16"
      [ env (pure (Nom16 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15)) $ \r ->
          bench "nominal/Nom16" $ whnf accessNom16 r
      , env (pure (REC
          { f0 = 0 :: Int, f1 = 1 :: Int, f2 = 2 :: Int, f3 = 3 :: Int
          , f4 = 4 :: Int, f5 = 5 :: Int, f6 = 6 :: Int, f7 = 7 :: Int
          , f8 = 8 :: Int, f9 = 9 :: Int, f10 = 10 :: Int, f11 = 11 :: Int
          , f12 = 12 :: Int, f13 = 13 :: Int, f14 = 14 :: Int, f15 = 15 :: Int
          } :: Poly16)) $ \r ->
          bench "polytropos/Poly16" $ whnf accessPoly16 r
      , env (pure (Map.fromList [(T.pack ("f" ++ show i), i) | i <- [0..15 :: Int]])) $ \m ->
          bench "containers/Map16" $ whnf accessMap16 m
      ]
  , bgroup "record-update/N16"
      [ env (pure (Nom16 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15)) $ \r ->
          bench "nominal/Nom16" $ whnf updateNom16 r
      , env (pure (REC
          { f0 = 0 :: Int, f1 = 1 :: Int, f2 = 2 :: Int, f3 = 3 :: Int
          , f4 = 4 :: Int, f5 = 5 :: Int, f6 = 6 :: Int, f7 = 7 :: Int
          , f8 = 8 :: Int, f9 = 9 :: Int, f10 = 10 :: Int, f11 = 11 :: Int
          , f12 = 12 :: Int, f13 = 13 :: Int, f14 = 14 :: Int, f15 = 15 :: Int
          } :: Poly16)) $ \r ->
          bench "polytropos/Poly16" $ whnf updatePoly16 r
      ]
  , bgroup "merge-morph/N8"
      [ env (pure ( REC { a0 = 1 :: Int, a1 = 2 :: Int, a2 = 3 :: Int, a3 = 4 :: Int } :: PolyLeft
                  , REC { b0 = 5 :: Int, b1 = 6 :: Int, b2 = 7 :: Int, b3 = 8 :: Int } :: PolyRight
                  )) $ \ ~(l, r) ->
          bench "polytropos/DisjointMerge" $ whnf (uncurry morphDisjoint) (l, r)
      ]
  ]
