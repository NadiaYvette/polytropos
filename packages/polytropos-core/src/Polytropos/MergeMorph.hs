{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UnboxedTuples #-}

-- |
-- Module      : Polytropos.MergeMorph
-- Description : Skew Boolean Intersection Algebra and O(|rOut|) two-source gather morphs.
--
-- Implements the Skew Boolean Intersection Algebra (Leech 1990; Cockett & Lack 2002)
-- over flat 'Polytropos.Record' arrays using a single unboxed 'PrimArray' gather plan.
module Polytropos.MergeMorph
  ( MergeOp(..)
  , MergeMorph(..)
  , KnownMergeMorph(..)
  , executeMergeMorph
  , unsafeMkMergeMorph#
  , (//>)
  , (<//)
  , (<+>)
  , (//~)
  , (|<)
  , (/-/)
  , (\^/)
  ) where

import Control.Monad.ST (runST)
import Data.Bits (complement)
import Data.Primitive.PrimArray (PrimArray(..), indexPrimArray, sizeofPrimArray)
import Data.Primitive.SmallArray (indexSmallArray, newSmallArray, runSmallArray, writeSmallArray)
import GHC.Exts (Addr#, Int#, copyAddrToByteArray#, newByteArray#, unsafeFreezeByteArray#)
import GHC.ST (ST(..))
import Polytropos.Core (Rep(..), Row, RowRep(..), RowType(..))

-- | Promoted algebra selector for Skew Boolean Intersection operations on rows.
data MergeOp
  = OpOverrideR
  | OpOverrideL
  | OpDisjoint
  | OpReplace
  | OpRestrict
  | OpDiff
  | OpSymDiff
  deriving (Eq, Ord, Show)

-- | Unboxed gather plan mapping each slot of 'rOut' to either 'r1' (k >= 0)
--   or 'r2' (k < 0, reading slot 'complement k').
newtype MergeMorph (op :: MergeOp) (r1 :: Row) (r2 :: Row) (rOut :: Row) =
  MergeMorph { unMergeMorph :: PrimArray Int }
  deriving (Eq, Show)

-- | Solved automatically by Polytropos.Plugin in O(|r1| + |r2|) compile time.
class KnownMergeMorph (op :: MergeOp) (r1 :: Row) (r2 :: Row) (rOut :: Row)
    | op r1 r2 -> rOut where
  mergeMorph :: MergeMorph op r1 r2 rOut

-- | Execute any binary Skew Boolean record operation in a single allocation pass.
{-# INLINE executeMergeMorph #-}
executeMergeMorph
  :: MergeMorph op r1 r2 rOut
  -> RowRep f tag1 r1 ()
  -> RowRep f tag2 r2 ()
  -> RowRep f ProductRowT rOut ()
executeMergeMorph (MergeMorph plan) (RowRep (Rep _ arr1)) (RowRep (Rep _ arr2)) =
  let !nOut = sizeofPrimArray plan
  in RowRep $ Rep 0 $ runSmallArray $ do
       out <- newSmallArray nOut (error "Polytropos.MergeMorph: uninitialized slot")
       let go !i
             | i >= nOut = pure out
             | otherwise = do
                 let !code = indexPrimArray plan i
                     !val  = if code >= 0
                               then indexSmallArray arr1 code
                               else indexSmallArray arr2 (complement code)
                 writeSmallArray out i val
                 go (i + 1)
       go 0

-- | Core synthesis target: materializes a 'MergeMorph' from a static .rodata 'Addr#'.
{-# INLINE unsafeMkMergeMorph# #-}
unsafeMkMergeMorph# :: Int# -> Addr# -> MergeMorph op r1 r2 rOut
unsafeMkMergeMorph# nBytes# addr# = runST $ ST $ \s0 ->
  case newByteArray# nBytes# s0 of
    (# s1, mba# #) ->
      case copyAddrToByteArray# addr# mba# 0# nBytes# s1 of
        s2 ->
          case unsafeFreezeByteArray# mba# s2 of
            (# s3, ba# #) -> (# s3, MergeMorph (PrimArray ba#) #)

infixl 6 //>, <//, <+>, //~
infixl 7 |<, /-/, \^/

-- | Right-biased override (Right Skew Join): fields in 'r2' shadow 'r1'.
{-# INLINE (//>) #-}
(//>) :: forall r1 r2 rOut f tag1 tag2. KnownMergeMorph 'OpOverrideR r1 r2 rOut
      => RowRep f tag1 r1 () -> RowRep f tag2 r2 () -> RowRep f ProductRowT rOut ()
(//>) = executeMergeMorph (mergeMorph @'OpOverrideR @r1 @r2 @rOut)

-- | Left-biased override (Left Skew Join): fields in 'r1' shadow 'r2'.
{-# INLINE (<//) #-}
(<//) :: forall r1 r2 rOut f tag1 tag2. KnownMergeMorph 'OpOverrideL r1 r2 rOut
      => RowRep f tag1 r1 () -> RowRep f tag2 r2 () -> RowRep f ProductRowT rOut ()
(<//) = executeMergeMorph (mergeMorph @'OpOverrideL @r1 @r2 @rOut)

-- | Disjoint separating product: fails at compile time if 'r1' and 'r2' share labels.
{-# INLINE (<+>) #-}
(<+>) :: forall r1 r2 rOut f tag1 tag2. KnownMergeMorph 'OpDisjoint r1 r2 rOut
      => RowRep f tag1 r1 () -> RowRep f tag2 r2 () -> RowRep f ProductRowT rOut ()
(<+>) = executeMergeMorph (mergeMorph @'OpDisjoint @r1 @r2 @rOut)

-- | In-place subset update: overwrites 'r1' fields using 'r2' (r2 must be a sub-row of r1).
{-# INLINE (//~) #-}
(//~) :: forall r1 r2 f tag1 tag2. KnownMergeMorph 'OpReplace r1 r2 r1
      => RowRep f tag1 r1 () -> RowRep f tag2 r2 () -> RowRep f ProductRowT r1 ()
(//~) = executeMergeMorph (mergeMorph @'OpReplace @r1 @r2 @r1)

-- | Domain restriction: keeps only fields of 'r1' whose labels occur in 'r2'.
{-# INLINE (|<) #-}
(|<) :: forall r1 r2 rOut f g tag1 tag2. KnownMergeMorph 'OpRestrict r1 r2 rOut
     => RowRep f tag1 r1 () -> RowRep g tag2 r2 () -> RowRep f ProductRowT rOut ()
r1 |< _ = executeMergeMorph (mergeMorph @'OpRestrict @r1 @r2 @rOut) r1 (RowRep (Rep 0 (runSmallArray (newSmallArray 0 (error "empty")))))

-- | Domain anti-restriction (relative complement): drops from 'r1' any label in 'r2'.
{-# INLINE (/-/) #-}
(/-/) :: forall r1 r2 rOut f g tag1 tag2. KnownMergeMorph 'OpDiff r1 r2 rOut
      => RowRep f tag1 r1 () -> RowRep g tag2 r2 () -> RowRep f ProductRowT rOut ()
r1 /-/ _ = executeMergeMorph (mergeMorph @'OpDiff @r1 @r2 @rOut) r1 (RowRep (Rep 0 (runSmallArray (newSmallArray 0 (error "empty")))))

-- | Symmetric difference: keeps fields present in exactly one of 'r1' or 'r2'.
{-# INLINE (\^/) #-}
(\^/) :: forall r1 r2 rOut f tag1 tag2. KnownMergeMorph 'OpSymDiff r1 r2 rOut
      => RowRep f tag1 r1 () -> RowRep f tag2 r2 () -> RowRep f ProductRowT rOut ()
(\^/) = executeMergeMorph (mergeMorph @'OpSymDiff @r1 @r2 @rOut)
