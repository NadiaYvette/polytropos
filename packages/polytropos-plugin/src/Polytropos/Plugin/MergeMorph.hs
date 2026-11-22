{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

-- |
-- Module      : Polytropos.Plugin.MergeMorph
-- Description : Compile-time Skew Boolean row solver and .rodata gather byte encoder.
--
-- Evaluates 'MergeOp' row equations inside 'Polytropos.Plugin' in O(|r1| + |r2|)
-- time and serializes the resulting two-complement gather codes into static
-- C-string bytes.
module Polytropos.Plugin.MergeMorph
  ( RowEntry(..)
  , MergeEvalResult(..)
  , evalMergeOp
  , encodeGatherBytes
  ) where

import Data.Bits (complement)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as BSB
import qualified Data.ByteString.Lazy as BSL
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import GHC.Core.TyCo.Compare (eqType)
import GHC.Plugins (FastString, Type, unpackFS)
import Polytropos.MergeMorph (MergeOp(..))

-- | Single field entry in a ground type-level Row.
data RowEntry = RowEntry
  { entryLabel :: !FastString
  , entryType  :: !Type
  , entrySlot  :: !Int
  }

instance Eq RowEntry where
  e1 == e2 =
    entryLabel e1 == entryLabel e2
      && entrySlot e1 == entrySlot e2
      && entryType e1 `eqType` entryType e2

-- | Outcome of compile-time Skew Boolean row algebra evaluation.
data MergeEvalResult
  = MergeSuccess ![RowEntry] ![Int]
  | MergeDisjointOverlap !FastString
  | MergeReplaceMissing !FastString
  deriving (Eq)

-- | Pure compile-time evaluator for all 7 Skew Boolean row operations.
--
-- Left entries use slot >= 0.
-- Right entries use slot < 0, encoded as 'complement slot2'.
evalMergeOp :: MergeOp -> [RowEntry] -> [RowEntry] -> MergeEvalResult
evalMergeOp op r1 r2 =
  let m1 = Map.fromList [ (unpackFS (entryLabel e), e) | e <- r1 ]
      m2 = Map.fromList [ (unpackFS (entryLabel e), e) | e <- r2 ]
      s1 = Map.keysSet m1
      s2 = Map.keysSet m2
  in case op of
       OpOverrideR ->
         let keys = Set.toList (Set.union s1 s2)
             outEntries =
               [ case Map.lookup k m2 of
                   Just e2 -> (e2, complement (entrySlot e2))
                   Nothing -> case Map.lookup k m1 of
                     Just e1 -> (e1, entrySlot e1)
                     Nothing -> error "evalMergeOp: impossible key"
               | k <- keys
               ]
             reIndexed = zipWith (\idx (e, _) -> e { entrySlot = idx }) [0..] outEntries
             gather = map snd outEntries
         in MergeSuccess reIndexed gather

       OpOverrideL ->
         let keys = Set.toList (Set.union s1 s2)
             outEntries =
               [ case Map.lookup k m1 of
                   Just e1 -> (e1, entrySlot e1)
                   Nothing -> case Map.lookup k m2 of
                     Just e2 -> (e2, complement (entrySlot e2))
                     Nothing -> error "evalMergeOp: impossible key"
               | k <- keys
               ]
             reIndexed = zipWith (\idx (e, _) -> e { entrySlot = idx }) [0..] outEntries
             gather = map snd outEntries
         in MergeSuccess reIndexed gather

       OpDisjoint ->
         let overlap = Set.intersection s1 s2
         in case Set.lookupMin overlap of
              Just badKey ->
                let badFS = entryLabel (m1 Map.! badKey)
                in MergeDisjointOverlap badFS
              Nothing ->
                let keys = Set.toList (Set.union s1 s2)
                    outEntries =
                      [ case Map.lookup k m1 of
                          Just e1 -> (e1, entrySlot e1)
                          Nothing -> case Map.lookup k m2 of
                            Just e2 -> (e2, complement (entrySlot e2))
                            Nothing -> error "evalMergeOp: impossible key"
                      | k <- keys
                      ]
                    reIndexed = zipWith (\idx (e, _) -> e { entrySlot = idx }) [0..] outEntries
                    gather = map snd outEntries
                in MergeSuccess reIndexed gather

       OpReplace ->
         let missing = Set.difference s2 s1
         in case Set.lookupMin missing of
              Just badKey ->
                let badFS = entryLabel (m2 Map.! badKey)
                in MergeReplaceMissing badFS
              Nothing ->
                let outEntries =
                      [ case Map.lookup (unpackFS (entryLabel e1)) m2 of
                          Just e2 -> (e2, complement (entrySlot e2))
                          Nothing -> (e1, entrySlot e1)
                      | e1 <- r1
                      ]
                    reIndexed = zipWith (\idx (e, _) -> e { entrySlot = idx }) [0..] outEntries
                    gather = map snd outEntries
                in MergeSuccess reIndexed gather

       OpRestrict ->
         let keys = Set.toList (Set.intersection s1 s2)
             outEntries =
               [ case Map.lookup k m1 of
                   Just e1 -> (e1, entrySlot e1)
                   Nothing -> error "evalMergeOp: impossible key"
               | k <- keys
               ]
             reIndexed = zipWith (\idx (e, _) -> e { entrySlot = idx }) [0..] outEntries
             gather = map snd outEntries
         in MergeSuccess reIndexed gather

       OpDiff ->
         let keys = Set.toList (Set.difference s1 s2)
             outEntries =
               [ case Map.lookup k m1 of
                   Just e1 -> (e1, entrySlot e1)
                   Nothing -> error "evalMergeOp: impossible key"
               | k <- keys
               ]
             reIndexed = zipWith (\idx (e, _) -> e { entrySlot = idx }) [0..] outEntries
             gather = map snd outEntries
         in MergeSuccess reIndexed gather

       OpSymDiff ->
         let keys = Set.toList (Set.difference (Set.union s1 s2) (Set.intersection s1 s2))
             outEntries =
               [ case Map.lookup k m1 of
                   Just e1 -> (e1, entrySlot e1)
                   Nothing -> case Map.lookup k m2 of
                     Just e2 -> (e2, complement (entrySlot e2))
                     Nothing -> error "evalMergeOp: impossible key"
               | k <- keys
               ]
             reIndexed = zipWith (\idx (e, _) -> e { entrySlot = idx }) [0..] outEntries
             gather = map snd outEntries
         in MergeSuccess reIndexed gather

-- | Serialize each gather slot (64-bit integer) into 8 little-endian bytes.
encodeGatherBytes :: [Int] -> BS.ByteString
encodeGatherBytes slots =
  BSL.toStrict $ BSB.toLazyByteString $
    mconcat [ BSB.int64LE (fromIntegral s) | s <- slots ]
