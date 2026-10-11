{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE Trustworthy #-}

-- |
-- Module      : Polytropos
-- Description : High-level consumer-facing API for Polytropos
-- Copyright   : (c) 2026 The Polytropos Authors
-- License     : BSD-3-Clause
-- Maintainer  : nadia.yvette.chambers@ik.me
--
-- This module provides the high-level, human-friendly API exports and pattern
-- synonyms for @polytropos@. It encapsulates the underlying representations
-- (like 'SmallArray' and 'Rep') and presents a clean, ergonomic surface for
-- working with row-polymorphic records and variants.
--
-- = Worked Example
--
-- Creating a simple record with fields @"x"@ and @"y"@:
--
-- @
-- myRec :: Record '["x" ':= Int, "y" ':= Bool]
-- myRec = insertField (Field \@"x") (10 :: Int)
--       $ insertField (Field \@"y") True
--       $ emptyRecord
-- @
--
-- Working with variants:
--
-- @
-- myVar :: Variant '["A" ':= '[], "B" ':= '["x" ':= Int]]
-- myVar = Variant (Field \@"B") (insertField (Field \@"x") (42 :: Int) emptyRecord)
--
-- -- Pattern matching
-- printVar :: Variant '["A" ':= '[], "B" ':= '["x" ':= Int]] -> String
-- printVar (Variant (Field \@"A") _) = "A"
-- printVar (Variant (Field \@"B") r) = "B with " ++ show r
-- @
module Polytropos
  ( -- * Ergonomic Types & Patterns
    type Record
  , type RecordF
  , type Variant
  , type VariantF
  , data Variant
  , data VariantF
    -- * Construction
  , emptyRecord
  , emptyRecordF
  , insertField
  , insertFieldF
  , injectVariant
  , injectVariantF
  , projectVariant
  , projectVariantF
  , type ConstructorPayload
  , type ConstructorPayloadHKD
    -- * Sub-row & Sub-variant operations
  , SubRow(..)
  , SubSum(..)
  , projectRecord
  , projectRecordF
  , widenVariant
  , widenVariantF
  , narrowVariant
  , narrowVariantF
    -- * Elimination & Peeling
  , peel
  , peelF
  , type Delete
  , type HandlerRecordRow
  , type HandlerRecordRowM
  , type HandlerRecordRowHetero
  , type HandlerRecordRowHeteroM
  , eliminateUniform
  , eliminateUniformM
  , eliminate
  , eliminateM
  , matchVariant
    -- * Re-exports
  , Pair(..)
  , RowEq(..)
  , RowShow(..)
  , RowFlavour(..)
  , Field(..)
  , AllFields(..)
  , DictAllFields
  , FieldNames
  , SimpleFieldTypes
  , FieldTypes
    -- * Label Hashing
  , KnownHash(..)
  , labelHash
  , hashVal
  , fnv1a64
    -- * Syntactic Devices (Source Plugin)
  , REC(..)
  , REC_F(..)
  , VAR(..)
  , type VARIANT
  , data VARIANT
  , REC_UPD(..)
  , REC_UPD_F(..)
  , OpenRecord
  , OpenVariant
  , recordField
  , setField
  , setFieldF
    -- * Generic Row Operations (§1.7)
  , cmapRecord
  , cfoldMapRecord
  , czipWithRecord
  , cmapRecordF
  , cfoldMapRecordF
  ) where

import Polytropos.Core
import Data.Functor.Identity (Identity(..))
import Data.Kind (Type)
import Data.Primitive.SmallArray (indexSmallArray, sizeofSmallArray, thawSmallArray, writeSmallArray, runSmallArray)
import GHC.Exts (toList, Any)
import GHC.Records (HasField(..))
import GHC.TypeLits (Symbol)
import Unsafe.Coerce (unsafeCoerce)

-- | An open record type, parametrised by a functor @f@ and a row @r@.
--
-- A 'RecordF' is a flat, contiguous array of fields where each field slot
-- contains a value wrapped in @f@.
type RecordF (f :: Type -> Type) (r :: ProductRow f) = RowRep f ProductRowHKDT r ()

-- | An open record type, parametrised by a row @r@ with bare field values (@f ~ Identity@).
--
-- A 'Record' is a flat, contiguous array of fields. Its memory layout is a
-- single pointer to a small array of payload slots, plus an erased constructor
-- tag (which is always 0 for products).
type Record (r :: Row) = RowRep Identity ProductRowT r ()

-- | An open variant type, parametrised by a functor @f@ and a sum row @s@.
--
-- A 'VariantF' is a single value that can be any one of the constructors
-- defined in the sum row @s@, with each field slot wrapped in @f@.
type VariantF (f :: Type -> Type) (s :: SumRowHKD f) = RowRep f SumRowHKDT s ()

-- | An open variant type, parametrised by a sum row @s@ with bare field values (@f ~ Identity@).
--
-- A 'Variant' is a single value that can be any one of the constructors
-- defined in the sum row @s@. Its memory layout is exactly identical to a
-- 'Record', except the tag distinguishes which constructor is currently active.
type Variant (s :: SumRow) = RowRep Identity SumRowT s ()

-- | Construct an empty HKD record.
emptyRecordF :: RecordF f '[]
emptyRecordF = RowRep (productRep [])

-- | Insert a new field wrapped in @f@ into an HKD record.
insertFieldF :: Field n -> f a -> RecordF f r -> RecordF f ((n ':= f a) ': r)
insertFieldF _ fa (RowRep r) =
  RowRep (productRep (unsafeCoerce fa : toList (repVals r)))

-- | Construct an empty record.
--
-- The empty record has no fields and an arity of 0.
emptyRecord :: Record '[]
emptyRecord = RowRep (productRep [])

-- | Insert a new field at the beginning of a record.
--
-- This extends the record's row type by prepending the new field. At runtime,
-- this copies the underlying array and adds the new value.
--
-- /Invariant/: This function expects the type-level field list to match the
-- runtime representation. Using it sequentially correctly builds up a record
-- in standard layout format.
insertField :: Field n -> a -> Record r -> Record ((n ':= a) ': r)
insertField _ a (RowRep r) =
  RowRep (productRep (Identity (unsafeCoerce a) : toList (repVals r)))

-- | Inject an HKD record into an HKD variant for a specific constructor.
-- | Compute the payload product row of a constructor @n@ in a sum row @s@.
type family ConstructorPayload (n :: Symbol) (s :: SumRow) :: Row where
  ConstructorPayload n ((n ':= fs) ': rest) = fs
  ConstructorPayload n ((m ':= fs) ': rest) = ConstructorPayload n rest

-- | Compute the HKD payload product row of a constructor @n@ in an HKD sum row @s@.
type family ConstructorPayloadHKD (f :: Type -> Type) (n :: Symbol) (s :: SumRowHKD f) :: ProductRow f where
  ConstructorPayloadHKD f n ((n ':= fs) ': rest) = fs
  ConstructorPayloadHKD f n ((m ':= fs) ': rest) = ConstructorPayloadHKD f n rest

-- | Inject an HKD record into an HKD variant for a specific constructor.
injectVariantF :: forall (n :: Symbol) (f :: Type -> Type) (s :: SumRowHKD f) (fs :: ProductRow f).
                  ConstructorIndex n s => Field n -> RecordF f fs -> VariantF f s
injectVariantF _ (RowRep r) =
  RowRep (injectRep (constructorIndex @_ @n @s) (toList (repVals r)))

-- | Project an HKD record from an HKD variant.
projectVariantF :: forall (n :: Symbol) (f :: Type -> Type) (s :: SumRowHKD f).
                   ConstructorIndex n s
                => Field n -> VariantF f s -> Maybe (RecordF f (ConstructorPayloadHKD f n s))
projectVariantF _ (RowRep r) =
  case projectRep (constructorIndex @_ @n @s) r of
    Just vals -> Just (RowRep (productRep vals))
    Nothing   -> Nothing

-- | Pattern synonym for matching and constructing HKD variants safely.
pattern VariantF :: forall (n :: Symbol) (f :: Type -> Type) (s :: SumRowHKD f).
                    ConstructorIndex n s
                 => Field n -> RecordF f (ConstructorPayloadHKD f n s) -> VariantF f s
pattern VariantF f r <- ( (\v -> (Field :: Field n, projectVariantF (Field :: Field n) v)) -> (f, Just r) )
  where VariantF f r = injectVariantF f r

-- | Inject a record of fields into a variant for a specific constructor.
injectVariant :: forall n s fs. ConstructorIndex n s => Field n -> Record fs -> Variant s
injectVariant _ (RowRep r) =
  RowRep (injectRep (constructorIndex @_ @n @s) (toList (repVals r)))

-- | Project a specific constructor from a variant.
projectVariant :: forall (n :: Symbol) (s :: SumRow).
                  ConstructorIndex n s
               => Field n -> Variant s -> Maybe (Record (ConstructorPayload n s))
projectVariant _ (RowRep r) =
  case projectRep (constructorIndex @_ @n @s) r of
    Just vals -> Just (RowRep (productRep vals))
    Nothing   -> Nothing

-- | A pattern synonym for matching and constructing variants safely.
pattern Variant :: forall (n :: Symbol) (s :: SumRow).
                   ConstructorIndex n s
                => Field n -> Record (ConstructorPayload n s) -> Variant s
pattern Variant f r <- ( (\v -> (Field :: Field n, projectVariant (Field :: Field n) v)) -> (f, Just r) )
  where Variant f r = injectVariant f r

-- | Project a sub-record from a super-record (HKD).
--
-- Extracts only the fields present in @sub@ in the order specified by @sub@.
projectRecordF :: forall (f :: Type -> Type) (sub :: ProductRow f) (super :: ProductRow f).
                  SubRow sub super => RecordF f super -> RecordF f sub
projectRecordF (RowRep rep) =
  let vals = repVals rep
      idxs = subRowIndices @sub @super
      newSlots = [ indexSmallArray vals i | i <- idxs ]
  in RowRep (productRep newSlots)

-- | Project a sub-record from a super-record (bare).
--
-- Extracts only the fields present in @sub@ in the order specified by @sub@.
projectRecord :: forall sub super. SubRow sub super => Record super -> Record sub
projectRecord (RowRep rep) =
  let vals = repVals rep
      idxs = subRowIndices @sub @super
      newSlots = [ indexSmallArray vals i | i <- idxs ]
  in RowRep (productRep newSlots)

-- | Widen a variant from a sub-row to a super-row (HKD).
--
-- Widening is total and constant time: the active constructor tag in @sub@ is
-- remapped to its corresponding tag in @super@, preserving payload slots.
widenVariantF :: forall (f :: Type -> Type) (sub :: SumRowHKD f) (super :: SumRowHKD f).
                 SubSum sub super => VariantF f sub -> VariantF f super
widenVariantF (RowRep rep) =
  let tag = fromIntegral (repTag rep) :: Int
      superTag = (subSumInjectIndices @sub @super) !! tag
  in RowRep (Rep superTag (repVals rep))

-- | Widen a variant from a sub-row to a super-row (bare).
--
-- Widening is total and constant time: the active constructor tag in @sub@ is
-- remapped to its corresponding tag in @super@, preserving payload slots.
widenVariant :: forall sub super. SubSum sub super => Variant sub -> Variant super
widenVariant (RowRep rep) =
  let tag = fromIntegral (repTag rep) :: Int
      superTag = (subSumInjectIndices @sub @super) !! tag
  in RowRep (Rep superTag (repVals rep))

-- | Narrow a variant from a super-row to a sub-row (HKD).
--
-- Returns 'Just' with the active tag remapped to @sub@ if the constructor belongs
-- to @sub@, or 'Nothing' if the constructor is not in @sub@.
narrowVariantF :: forall (f :: Type -> Type) (sub :: SumRowHKD f) (super :: SumRowHKD f).
                  SubSum sub super => VariantF f super -> Maybe (VariantF f sub)
narrowVariantF (RowRep rep) =
  let tag = fromIntegral (repTag rep) :: Int
      narrowMap = subSumNarrowIndices @sub @super
  in case drop tag narrowMap of
    (Just subTag : _) -> Just (RowRep (Rep subTag (repVals rep)))
    _                 -> Nothing

-- | Narrow a variant from a super-row to a sub-row (bare).
--
-- Returns 'Just' with the active tag remapped to @sub@ if the constructor belongs
-- to @sub@, or 'Nothing' if the constructor is not in @sub@.
narrowVariant :: forall sub super. SubSum sub super => Variant super -> Maybe (Variant sub)
narrowVariant (RowRep rep) =
  let tag = fromIntegral (repTag rep) :: Int
      narrowMap = subSumNarrowIndices @sub @super
  in case drop tag narrowMap of
    (Just subTag : _) -> Just (RowRep (Rep subTag (repVals rep)))
    _                 -> Nothing

{-------------------------------------------------------------------------------
  Elimination & Peeling
-------------------------------------------------------------------------------}

-- | Delete a constructor @n@ from a sum row @s@.
type family Delete (n :: Symbol) (s :: [Pair Symbol k]) :: [Pair Symbol k] where
  Delete n ((n ':= fs) ': rest) = rest
  Delete n ((m ':= fs) ': rest) = (m ':= fs) ': Delete n rest
  Delete n '[]                  = '[]

-- | Peel a constructor @n@ from an open variant in O(1) time.
--
-- If the variant contains constructor @n@, returns @Right (Record fs)@.
-- Otherwise, returns @Left (Variant (Delete n s))@ with the runtime tag
-- adjusted in O(1) time without copying the payload array.
peel :: forall (n :: Symbol) (s :: SumRow).
        ConstructorIndex n s
     => Variant s
     -> Either (Variant (Delete n s)) (Record (ConstructorPayload n s))
peel (RowRep r) =
  case peelRep (constructorIndex @_ @n @s) r of
    Right vals -> Right (RowRep (productRep vals))
    Left remR  -> Left (RowRep remR)

-- | Peel a constructor @n@ from an open HKD variant in O(1) time.
peelF :: forall (n :: Symbol) (f :: Type -> Type) (s :: SumRowHKD f).
         ConstructorIndex n s
      => VariantF f s
      -> Either (VariantF f (Delete n s)) (RecordF f (ConstructorPayloadHKD f n s))
peelF (RowRep r) =
  case peelRep (constructorIndex @_ @n @s) r of
    Right vals -> Right (RowRep (productRep vals))
    Left remR  -> Left (RowRep remR)

-- | Row of handler functions for a sum row @s@ returning a uniform result @res@.
type family HandlerRecordRow (s :: SumRow) (res :: Type) :: Row where
  HandlerRecordRow '[] _ = '[]
  HandlerRecordRow ((n ':= fs) ': rest) res = (n ':= (Record fs -> res)) ': HandlerRecordRow rest res

-- | Row of monadic handler functions for a sum row @s@ returning @m res@.
type family HandlerRecordRowM (s :: SumRow) (m :: Type -> Type) (res :: Type) :: Row where
  HandlerRecordRowM '[] _ _ = '[]
  HandlerRecordRowM ((n ':= fs) ': rest) m res = (n ':= (Record fs -> m res)) ': HandlerRecordRowM rest m res

-- | Row of heterogeneous handler functions mapping constructors in @s@ to results in @resRow@.
type family HandlerRecordRowHetero (s :: SumRow) (resRow :: SumRow) :: Row where
  HandlerRecordRowHetero '[] _ = '[]
  HandlerRecordRowHetero ((n ':= fs) ': rest) ((n ':= rfs) ': rrest) =
    (n ':= (Record fs -> Record rfs)) ': HandlerRecordRowHetero rest rrest

-- | Row of heterogeneous monadic handler functions mapping constructors in @s@ to monadic results in @m (Record rfs)@.
type family HandlerRecordRowHeteroM (s :: SumRow) (resRow :: SumRow) (m :: Type -> Type) :: Row where
  HandlerRecordRowHeteroM '[] _ _ = '[]
  HandlerRecordRowHeteroM ((n ':= fs) ': rest) ((n ':= rfs) ': rrest) m =
    (n ':= (Record fs -> m (Record rfs))) ': HandlerRecordRowHeteroM rest rrest m

-- | Eliminate a closed variant uniformly with O(1) array jump table dispatch.
eliminateUniform :: forall (s :: SumRow) a.
                    Record (HandlerRecordRow s a)
                 -> Variant s
                 -> a
eliminateUniform (RowRep (Rep _ hVals)) (RowRep (Rep tag vals)) =
  let Identity hAny = indexSmallArray hVals (fromIntegral tag)
      h = unsafeCoerce hAny :: Record '[] -> a
      payload = RowRep (Rep 0 vals) :: Record '[]
  in h payload

-- | Eliminate a closed variant uniformly inside a monad @m@ with O(1) array jump table dispatch.
eliminateUniformM :: forall (s :: SumRow) m a.
                     Record (HandlerRecordRowM s m a)
                  -> Variant s
                  -> m a
eliminateUniformM (RowRep (Rep _ hVals)) (RowRep (Rep tag vals)) =
  let Identity hAny = indexSmallArray hVals (fromIntegral tag)
      h = unsafeCoerce hAny :: Record '[] -> m a
      payload = RowRep (Rep 0 vals) :: Record '[]
  in h payload

-- | Full hybrid eliminator: eliminate a closed variant into an open variant of per-constructor results.
eliminate :: forall (s :: SumRow) (resRow :: SumRow).
             Record (HandlerRecordRowHetero s resRow)
          -> Variant s
          -> Variant resRow
eliminate (RowRep (Rep _ hVals)) (RowRep (Rep tag vals)) =
  let Identity hAny = indexSmallArray hVals (fromIntegral tag)
      h = unsafeCoerce hAny :: Record '[] -> Record '[]
      payload = RowRep (Rep 0 vals) :: Record '[]
      RowRep (Rep _ resVals) = h payload
  in RowRep (Rep tag resVals)

-- | Full monadic hybrid eliminator: eliminate a closed variant into an open variant of per-constructor results inside @m@.
eliminateM :: forall (s :: SumRow) (resRow :: SumRow) m.
              Monad m
           => Record (HandlerRecordRowHeteroM s resRow m)
           -> Variant s
           -> m (Variant resRow)
eliminateM (RowRep (Rep _ hVals)) (RowRep (Rep tag vals)) =
  let Identity hAny = indexSmallArray hVals (fromIntegral tag)
      h = unsafeCoerce hAny :: Record '[] -> m (Record '[])
      payload = RowRep (Rep 0 vals) :: Record '[]
  in do
    RowRep (Rep _ resVals) <- h payload
    pure (RowRep (Rep tag resVals))

-- | Syntactic synonym for 'eliminateUniform' taking the variant value first.
--
-- Convenient for direct pattern matching expressions:
--
-- @
-- matchVariant expr REC
--   { lit = \(REC { val }) -> val
--   , add = \(REC { left, right }) -> left + right
--   }
-- @
matchVariant :: forall (s :: SumRow) a.
                Variant s
             -> Record (HandlerRecordRow s a)
             -> a
matchVariant = flip eliminateUniform

{-------------------------------------------------------------------------------
  Syntactic Devices & Helpers (Source Plugin)
-------------------------------------------------------------------------------}

-- | Syntactic marker for anonymous record construction and pattern matching.
-- Desugared by the @Polytropos@ source plugin.
data REC = REC
  deriving (Show, Eq)

-- | Syntactic marker for anonymous functorial/HKD record construction.
-- Desugared by the @Polytropos@ source plugin.
data REC_F = REC_F
  deriving (Show, Eq)

-- | Syntactic marker for anonymous variant injection and pattern matching.
-- Desugared by the @Polytropos@ source plugin.
data VAR = VAR
  deriving (Show, Eq)

-- | Syntactic alias for 'VAR'.
type VARIANT = VAR

pattern VARIANT :: VAR
pattern VARIANT = VAR

-- | Marker for record update syntax: @REC_UPD r { x = 42 }@.
-- Desugared by the @Polytropos@ source plugin into 'setField' calls.
data REC_UPD = REC_UPD
  deriving (Show, Eq)

-- | Marker for functorial/HKD record update syntax: @REC_UPD_F r { x = Just 42 }@.
-- Desugared by the @Polytropos@ source plugin into 'setFieldF' calls.
data REC_UPD_F = REC_UPD_F
  deriving (Show, Eq)

-- | Marker class for open record declarations desugared by the source plugin.
class OpenRecord a

-- | Marker class for open variant declarations desugared by the source plugin.
class OpenVariant a

-- | Fetch a field value from a record, used for pattern matching and field access.
recordField :: forall n a r. HasField n (Record r) (Identity a) => Field n -> Record r -> a
recordField _ r = case getField @n r of Identity x -> x

-- | Update an existing field in a 'Record'.
setField :: forall n a r. FieldIndex n r a => Field n -> a -> Record r -> Record r
setField _ val (RowRep rep) =
  RowRep (setFieldAt (fieldIndex @_ @n @r @a) (Identity (noInlineUnsafeCo val)) rep)

-- | Update an existing field in a 'RecordF'.
setFieldF :: forall n a f r. FieldIndex n r (f a) => Field n -> f a -> RecordF f r -> RecordF f r
setFieldF _ val (RowRep rep) =
  RowRep (setFieldAt (fieldIndex @_ @n @r @(f a)) (noInlineUnsafeCo val) rep)

{-------------------------------------------------------------------------------
  Generic Row Operations (§1.7 Generic instance layer)
-------------------------------------------------------------------------------}

-- | Map a class-constrained function over all fields of a record.
cmapRecord
  :: forall c r. AllFields ProductRowT r c
  => (forall x. c x => x -> x)
  -> Record r
  -> Record r
cmapRecord f (RowRep (Rep t v)) =
  let dicts = fieldDicts @ProductRowT @r @c
      n = sizeofSmallArray v
      v' = runSmallArray $ do
        m <- thawSmallArray v 0 n
        let loop i
              | i == n = pure ()
              | otherwise = do
                  let d = indexSmallArray dicts i
                      Identity vi = indexSmallArray v i
                  case d of
                    DictAny -> do
                      let vi' = f (noInlineUnsafeCo vi :: Any)
                      writeSmallArray m i (Identity (noInlineUnsafeCo vi'))
                      loop (i + 1)
        loop 0
        pure m
  in RowRep (Rep t v')

-- | Fold over all fields of a record using a class constraint.
cfoldMapRecord
  :: forall c r m. (AllFields ProductRowT r c, Monoid m)
  => (forall x. c x => x -> m)
  -> Record r
  -> m
cfoldMapRecord f (RowRep (Rep _ v)) =
  let dicts = fieldDicts @ProductRowT @r @c
      n = sizeofSmallArray v
      loop i
        | i == n = mempty
        | otherwise =
            let d = indexSmallArray dicts i
                Identity vi = indexSmallArray v i
            in case d of
                 DictAny ->
                   let val = f (noInlineUnsafeCo vi :: Any)
                   in val <> loop (i + 1)
  in loop 0

-- | Zip two records of identical row shape applying a class-constrained function.
czipWithRecord
  :: forall c r. AllFields ProductRowT r c
  => (forall x. c x => x -> x -> x)
  -> Record r
  -> Record r
  -> Record r
czipWithRecord f (RowRep (Rep t v1)) (RowRep (Rep _ v2)) =
  let dicts = fieldDicts @ProductRowT @r @c
      n = sizeofSmallArray v1
      v' = runSmallArray $ do
        m <- thawSmallArray v1 0 n
        let loop i
              | i == n = pure ()
              | otherwise = do
                  let d = indexSmallArray dicts i
                      Identity x1 = indexSmallArray v1 i
                      Identity x2 = indexSmallArray v2 i
                  case d of
                    DictAny -> do
                      let res = f (noInlineUnsafeCo x1 :: Any) (noInlineUnsafeCo x2 :: Any)
                      writeSmallArray m i (Identity (noInlineUnsafeCo res))
                      loop (i + 1)
        loop 0
        pure m
  in RowRep (Rep t v')

-- | Map a class-constrained function over all fields of an HKD record.
cmapRecordF
  :: forall c f r. AllFields ProductRowHKDT r c
  => (forall x. c x => x -> x)
  -> RecordF f r
  -> RecordF f r
cmapRecordF f (RowRep (Rep t v)) =
  let dicts = fieldDicts @ProductRowHKDT @r @c
      n = sizeofSmallArray v
      v' = runSmallArray $ do
        m <- thawSmallArray v 0 n
        let loop i
              | i == n = pure ()
              | otherwise = do
                  let d = indexSmallArray dicts i
                      vi = indexSmallArray v i
                  case d of
                    DictAny -> do
                      let vi' = f (noInlineUnsafeCo vi :: Any)
                      writeSmallArray m i (noInlineUnsafeCo vi')
                      loop (i + 1)
        loop 0
        pure m
  in RowRep (Rep t v')

-- | Fold over all fields of an HKD record using a class constraint.
cfoldMapRecordF
  :: forall c f r m. (AllFields ProductRowHKDT r c, Monoid m)
  => (forall x. c x => x -> m)
  -> RecordF f r
  -> m
cfoldMapRecordF f (RowRep (Rep _ v)) =
  let dicts = fieldDicts @ProductRowHKDT @r @c
      n = sizeofSmallArray v
      loop i
        | i == n = mempty
        | otherwise =
            let d = indexSmallArray dicts i
                vi = indexSmallArray v i
            in case d of
                 DictAny ->
                   let val = f (noInlineUnsafeCo vi :: Any)
                   in val <> loop (i + 1)
  in loop 0


