-- | LiquidHaskell Refinement Type Specifications for Polytropos
--
-- This specification defines refinement types over row memory representations,
-- slot index bounds, subrow projection safety, and field predicate refinements.

module spec Polytropos.Liquid.RowPredicates where

import Data.Primitive.SmallArray
import GHC.Word

-- ============================================================================
-- 1. Representation & Array Invariants
-- ============================================================================

measure sizeofSmallArray :: SmallArray a -> Int
invariant {v: SmallArray a | sizeofSmallArray v >= 0}

measure repArity :: Rep f a -> Int
repArity (Rep t v) = sizeofSmallArray v

measure repTagVal :: Rep f a -> Word
repTagVal (Rep t v) = t

-- | The core Rep structure carries a non-negative constructor/product tag
-- and an array of payload slots of non-negative length.
data Rep f a = Rep {
    repTag  :: {t: Word | t >= 0}
  , repVals :: {v: SmallArray (f Any) | sizeofSmallArray v >= 0}
}

-- ============================================================================
-- 2. Slot Indexing & Mutation Bounds Safety
-- ============================================================================

-- | Direct slot lookup is provably bounds-safe: the slot index must be
-- strictly less than the record's arity.
assume fieldAt :: forall f a.
     i: {Int | 0 <= i}
  -> r: {Rep f a | i < sizeofSmallArray (repVals r)}
  -> f Any

-- | In-place slot update preserves the exact arity and tag of the record.
assume setFieldAt :: forall f a.
     i: {Int | 0 <= i}
  -> val: f Any
  -> r: {Rep f a | i < sizeofSmallArray (repVals r)}
  -> {r': Rep f a | sizeofSmallArray (repVals r') == sizeofSmallArray (repVals r) && repTag r' == repTag r}

-- ============================================================================
-- 3. Subrow Projection Safety
-- ============================================================================

-- | A valid SubRow projection mapping guarantees that every target index
-- points to an in-bounds slot in the source record.
--
-- LiquidHaskell verifies that projected records cannot trigger out-of-bounds reads.
assume projectSubRow :: forall f super sub.
     indices: [{idx: Int | 0 <= idx}]
  -> super: {Rep f super | (forall j in indices. j < sizeofSmallArray (repVals super))}
  -> {sub: Rep f sub | sizeofSmallArray (repVals sub) == len indices && repTag sub == 0}

-- ============================================================================
-- 4. Open Variant Dispatch Bounds Safety
-- ============================================================================

-- | Jump-table variant elimination: the active constructor tag must be strictly
-- less than the jump table array size, guaranteeing exhaustive dispatch without
-- out-of-bounds indexing.
assume eliminateUniformRep :: forall f res a.
     handlers: {SmallArray (f Any -> res) | sizeofSmallArray handlers > 0}
  -> var: {Rep f a | repTag var < sizeofSmallArray handlers}
  -> res

-- | Peeling guarantees tag preservation or decrement without underflow.
assume peelRep :: forall f a b.
     targetTag: {Word | targetTag >= 0}
  -> var: {Rep f a | repTag var >= 0}
  -> {res: Either (Rep f a) (Rep f b) |
       (isRight res <=> repTag var == targetTag) &&
       (isLeft res <=> repTag var /= targetTag)}

-- ============================================================================
-- 5. Field Predicate Refinements
-- ============================================================================

-- | Refinement type aliases for domain-specific row field predicates
type NatField = {v: Int | v >= 0}
type PositiveField = {v: Int | v > 0}
type NonEmptyString = {v: String | len v > 0}
type ValidPort = {v: Int | 1 <= v && v <= 65535}
type Probability = {v: Double | 0.0 <= v && v <= 1.0}
