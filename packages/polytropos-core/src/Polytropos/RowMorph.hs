{-|
Module      : Polytropos.RowMorph
Description : Reified unboxed row morphisms and primitive gather/scatter operations
Copyright   : (c) 2026 The Polytropos Authors
License     : EUPL-1.2 OR Apache-2.0
Maintainer  : nadia.yvette.chambers@ik.me
Stability   : experimental
Portability : non-portable (GHC extensions)

Reified unboxed row morphisms and primitive gather/scatter operations for @polytropos@.

= Architectural Overview & Rationale

In conventional polymorphic record and pipeline architectures, wire routing and subrow
projection typically incur either:
1. Opaque runtime closures (@arr (\\(a, (b, c)) -> (b, a))@) that prevent static inspection,
   optimizer inlining, and peephole fusion.
2. Inductive type-level searches (@KnownNat@ / inductive dictionary trees) that generate
   \(O(N)\) or \(O(N^2)\) pointer-chasing calls at runtime.

'RowMorph' collapses row routing and projection into a single unboxed 'PrimArray' 'Int'
(backed by a contiguous 'GHC.Exts.ByteArray#' primitive). Each index @i@ in @[0 .. |r1| - 1]@
contains the literal 0-based slot offset in the target row @r2@.

== Key Features & Operations

* __Unboxed Reification:__ 'RowMorph' has zero heap allocation overhead per element, storing
  pure integer indices densely in cache lines.
* __\(O(|r1|)\) Category Composition:__ 'composeRowMorph' composes two morphisms in a single
  branchless pass, computing @m23(m12(i))@ into a newly allocated 'PrimArray' without intermediate lists.
* __Contravariant Reduct Gather:__ 'gatherRep' extracts an arbitrary subrow or permutation from
  an existing 'Polytropos.Core.Rep' in \(O(|sub|)\) time with a single 'Data.Primitive.SmallArray.SmallArray' allocation.
* __In-Place Scatter:__ 'scatterRep' writes back updated subrow slots into an existing 'Rep'
  in \(O(|full|)\) time via 'Data.Primitive.SmallArray.thawSmallArray'.
* __Compile-Time Synthesis:__ The evidence class 'KnownRowMorph' is solved directly by
  @Polytropos.Plugin@, emitting literal index vectors into Core AST with zero runtime dictionary search.

= Note [Reified Row Morphisms and Gather-Scatter] [tag:note-row-morph-routing]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
A row morphism @RowMorph r1 r2@ models a structural embedding / projection map from @r1@ into @r2@.
Rather than representing morphisms as functions @Record r2 -> Record r1@ or type-level inductive
witnesses, 'RowMorph' reifies the mapping as a flat primitive array of integers.

1. Category Structure:
   - Identity: @idMorph = RowMorph [0, 1, .. n-1]@.
   - Composition: @composeRowMorph m12 m23@ computes @dstIdx = m23[m12[i]]@ for all @i@.
     Associativity @(m1 >>> m2) >>> m3 == m1 >>> (m2 >>> m3)@ holds strictly by array index equality.

2. Contravariant Reduct / Port Gather:
   Given a wider register frame or handler record @full@ and a required sub-signature @sub@,
   @gatherRep morph full@ acts as the contravariant reduct \(\mathrm{Mod}(\sigma)(M')\), pulling
   exactly the active ports or handler methods into a compact, contiguous memory buffer.

3. Frame-Rule Auto-Wiring:
   'FramePlan' and 'FrameWire' generalize binary port routing to stateful execution frames:
   an operation @(opIn -> opOut)@ inside @(frameIn -> frameOut)@ executes by gathering @opIn@
   from @frameIn@, copying surviving @frameIn@ slots to @frameOut@, and scattering @opOut@ into @frameOut@
   in two tight branchless loops.
-}

{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RoleAnnotations #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneKindSignatures #-}
{-# LANGUAGE TypeApplications #-}

module Polytropos.RowMorph
  ( -- * Reified Row Morphisms
    RowMorph(..)
  , KnownRowMorph(..)
  , unsafeMkRowMorph
  , composeRowMorph
  , indexRowMorph
    -- * Record Gather & Scatter over Rep
  , gatherRep
  , scatterRep
    -- * Frame-Rule Auto-Wiring Plan
  , FramePlan(..)
  , FrameWire(..)
  , unsafeMkFramePlan
  , executeFrameScatter
  ) where

import Control.Monad.ST
  ( runST
  )
import Data.Kind
  ( Constraint
  , Type
  )
import Data.Primitive.PrimArray
  ( PrimArray
  , indexPrimArray
  , newPrimArray
  , primArrayFromList
  , sizeofPrimArray
  , unsafeFreezePrimArray
  , writePrimArray
  )
import Data.Primitive.SmallArray
  ( indexSmallArray
  , newSmallArray
  , runSmallArray
  , sizeofSmallArray
  , thawSmallArray
  , writeSmallArray
  )
import Polytropos.Core
  ( Rep(..)
  )

{-------------------------------------------------------------------------------
  Reified Row Morphisms
-------------------------------------------------------------------------------}

-- | A compile-time synthesized slot injection map from @r1@ into @r2@.
--
-- Each index @i@ in @[0 .. |r1| - 1]@ maps to its target slot in @[0 .. |r2| - 1]@.
-- Backed by an unboxed 'PrimArray' 'Int' with nominal type role parameters,
-- preventing illicit coercions across distinct row types.
--
-- See Note [Reified Row Morphisms and Gather-Scatter] [ref:note-row-morph-routing]
type RowMorph :: forall {k1} {k2}. k1 -> k2 -> Type
type role RowMorph nominal nominal
newtype RowMorph (r1 :: k1) (r2 :: k2) = RowMorph
  { unRowMorph :: PrimArray Int }
  deriving stock (Eq, Show)

-- | Solved by @Polytropos.Plugin@ into a static 'RowMorph' CAF constant.
--
-- When @r1@ is a subrow or permutation of @r2@, the compiler plugin synthesizes
-- the literal permutation array and emits the instance dictionary directly into Core AST.
type KnownRowMorph :: forall {k1} {k2}. k1 -> k2 -> Constraint
class KnownRowMorph (r1 :: k1) (r2 :: k2) where
  rowMorph :: RowMorph r1 r2

-- | Entry point called by Core expressions synthesized by @Polytropos.Plugin@.
--
-- Must be marked @NOINLINE@ to establish an optimization barrier for the Core simplifier.
unsafeMkRowMorph :: forall {k1} {k2} (r1 :: k1) (r2 :: k2). [Int] -> RowMorph r1 r2
{-# NOINLINE unsafeMkRowMorph #-}
unsafeMkRowMorph idxs = RowMorph (primArrayFromList idxs)

-- | Reads the target slot index for the @i@-th entry of @r1@.
indexRowMorph :: RowMorph r1 r2 -> Int -> Int
{-# INLINE indexRowMorph #-}
indexRowMorph (RowMorph arr) !i = indexPrimArray arr i

-- | Category composition for 'RowMorph': \(\mathcal{O}(|r1|)\) primitive array indexing.
--
-- Given morphisms @m12 : r1 -> r2@ and @m23 : r2 -> r3@, computes @m13 : r1 -> r3@
-- where each slot @i@ in @r1@ maps to @m23(m12(i))@ in @r3@.
--
-- See Note [Reified Row Morphisms and Gather-Scatter] [ref:note-row-morph-routing]
composeRowMorph :: RowMorph r1 r2 -> RowMorph r2 r3 -> RowMorph r1 r3
{-# INLINE composeRowMorph #-}
composeRowMorph (RowMorph m12) (RowMorph m23) = RowMorph $ runST $ do
  let !n = sizeofPrimArray m12
  out <- newPrimArray n
  let go !i
        | i >= n    = unsafeFreezePrimArray out
        | otherwise = do
            let !midIdx = indexPrimArray m12 i
                !dstIdx = indexPrimArray m23 midIdx
            writePrimArray out i dstIdx
            go (i + 1)
  go 0

{-------------------------------------------------------------------------------
  Record Gather & Scatter over Rep
-------------------------------------------------------------------------------}

-- | Contravariant reduct / port gather: extracts @sub@ slots from @full@ in \(\mathcal{O}(|sub|)\).
--
-- Directly implements \(\mathrm{Mod}(\sigma)(M')\) for handler records, input port frames,
-- and structural subrow extraction with a single 'SmallArray' allocation.
--
-- See Note [Reified Row Morphisms and Gather-Scatter] [ref:note-row-morph-routing]
gatherRep :: RowMorph sub full -> Rep f a -> Rep f b
{-# INLINE gatherRep #-}
gatherRep (RowMorph morph) (Rep _ srcArr) = Rep 0 $ runSmallArray $ do
  let !n = sizeofPrimArray morph
  dstArr <- newSmallArray n (error "gatherRep: uninitialized slot")
  let go !i
        | i >= n    = pure dstArr
        | otherwise = do
            let !srcIdx = indexPrimArray morph i
            writeSmallArray dstArr i (indexSmallArray srcArr srcIdx)
            go (i + 1)
  go 0

-- | Overwrites @sub@ slots inside an existing @full@ record in \(\mathcal{O}(|full|)\).
--
-- Preserves the runtime constructor tag of the target representation while updating
-- matching slots in place via array thawing and non-overlapping writes.
scatterRep :: RowMorph sub full -> Rep f a -> Rep f b -> Rep f b
{-# INLINE scatterRep #-}
scatterRep (RowMorph morph) (Rep _ subArr) (Rep t fullArr) = Rep t $ runSmallArray $ do
  let !fullLen = sizeofSmallArray fullArr
      !subLen  = sizeofPrimArray morph
  dstArr <- thawSmallArray fullArr 0 fullLen
  let go !i
        | i >= subLen = pure dstArr
        | otherwise   = do
            let !targetIdx = indexPrimArray morph i
            writeSmallArray dstArr targetIdx (indexSmallArray subArr i)
            go (i + 1)
  go 0

{-------------------------------------------------------------------------------
  Frame-Rule Auto-Wiring Plan
-------------------------------------------------------------------------------}

-- | Concrete execution plan for wiring an operation @(opIn -> opOut)@
-- inside a live register frame @(frameIn -> frameOut)@.
--
-- See Note [Reified Row Morphisms and Gather-Scatter] [ref:note-row-morph-routing]
type FramePlan :: forall {k1} {k2} {k3} {k4}. k1 -> k2 -> k3 -> k4 -> Type
data FramePlan frameIn opIn opOut frameOut = FramePlan
  { fpOutSize     :: {-# UNPACK #-} !Int
  , fpGatherIn    :: !(RowMorph opIn frameIn)
    -- ^ Gathers the operation's input ports from @frameIn@.
  , fpBaseScatter :: !(RowMorph frameIn frameOut)
    -- ^ Places surviving @frameIn@ ports into @frameOut@.
  , fpOpScatter   :: !(RowMorph opOut frameOut)
    -- ^ Places @opOut@ ports into @frameOut@ (overwriting collided @frameIn@ ports).
  }
  deriving stock (Eq, Show)

-- | Solved by @Polytropos.Plugin@:
-- 1. Verifies @opIn@ is a subrow of @frameIn@ (unifying port types).
-- 2. Synthesizes @frameOut ~ RowOverwrite frameIn opOut@.
-- 3. Emits the 'FramePlan' dictionary.
type FrameWire :: forall {k1} {k2} {k3} {k4}. k1 -> k2 -> k3 -> k4 -> Constraint
class FrameWire frameIn opIn opOut frameOut where
  framePlan :: FramePlan frameIn opIn opOut frameOut

-- | Entry point called by Core expressions synthesized by @Polytropos.Plugin@ for 'FrameWire'.
unsafeMkFramePlan
  :: forall {k1} {k2} {k3} {k4} (frameIn :: k1) (opIn :: k2) (opOut :: k3) (frameOut :: k4).
     Int
  -> [Int]
  -> [Int]
  -> [Int]
  -> FramePlan frameIn opIn opOut frameOut
{-# NOINLINE unsafeMkFramePlan #-}
unsafeMkFramePlan outSz gatherIdxs baseIdxs opIdxs = FramePlan
  { fpOutSize     = outSz
  , fpGatherIn    = unsafeMkRowMorph gatherIdxs
  , fpBaseScatter = unsafeMkRowMorph baseIdxs
  , fpOpScatter   = unsafeMkRowMorph opIdxs
  }

-- | Merges the previous frame @frameIn@ and the operation output @opOut@
-- into the next frame @frameOut@ in two tight, branchless loops.
executeFrameScatter
  :: FramePlan frameIn opIn opOut frameOut
  -> Rep f a
  -> Rep f b
  -> Rep f c
{-# INLINE executeFrameScatter #-}
executeFrameScatter (FramePlan !outSz _ (RowMorph baseMap) (RowMorph opMap)) (Rep _ baseArr) (Rep _ opArr) =
  Rep 0 $ runSmallArray $ do
    let !baseLen = sizeofPrimArray baseMap
        !opLen   = sizeofPrimArray opMap
    dst <- newSmallArray outSz (error "executeFrameScatter: uninitialized slot")
    let copyBase !i
          | i >= baseLen = pure ()
          | otherwise    = do
              let !dstIdx = indexPrimArray baseMap i
              writeSmallArray dst dstIdx (indexSmallArray baseArr i)
              copyBase (i + 1)
        copyOp !j
          | j >= opLen   = pure dst
          | otherwise    = do
              let !dstIdx = indexPrimArray opMap j
              writeSmallArray dst dstIdx (indexSmallArray opArr j)
              copyOp (j + 1)
    copyBase 0
    copyOp 0
