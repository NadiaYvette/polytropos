{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
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
    -- * Re-exports
  , RowEq(..)
  , RowShow(..)
  , RowFlavour(..)
  , Field(..)
  , AllFields(..)
  , DictAllFields
  , FieldNames
  , SimpleFieldTypes
  , FieldTypes
  ) where

import Polytropos.Core
import Data.Functor.Identity (Identity(..))
import Data.Kind (Type)
import GHC.Exts (toList)
import Unsafe.Coerce (unsafeCoerce)

-- | An open record type, parametrised by a functor @f@ and a row @r@.
--
-- A 'RecordF' is a flat, contiguous array of fields where each field slot
-- contains a value wrapped in @f@.
type RecordF (f :: Type -> Type) (r :: Row) = RowRep f ProductRowHKDT r ()

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
type VariantF (f :: Type -> Type) (s :: SumRow) = RowRep f SumRowHKDT s ()

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
insertFieldF :: Field n -> f a -> RecordF f r -> RecordF f ((n ':= a) ': r)
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
injectVariantF :: forall n s fs f. ConstructorIndex n s => Field n -> RecordF f fs -> VariantF f s
injectVariantF _ (RowRep r) =
  RowRep (injectRep (constructorIndex @_ @n @s) (toList (repVals r)))

-- | Project an HKD record from an HKD variant.
projectVariantF :: forall n s fs f. ConstructorIndex n s => Field n -> VariantF f s -> Maybe (RecordF f fs)
projectVariantF _ (RowRep r) =
  case projectRep (constructorIndex @_ @n @s) r of
    Just vals -> Just (RowRep (productRep vals))
    Nothing   -> Nothing

-- | Pattern synonym for matching and constructing HKD variants safely.
pattern VariantF :: forall n s fs f. ConstructorIndex n s => Field n -> RecordF f fs -> VariantF f s
pattern VariantF f r <- ( (\v -> (Field :: Field n, projectVariantF (Field :: Field n) v)) -> (f, Just r) )
  where VariantF f r = injectVariantF f r

-- | Inject a record of fields into a variant for a specific constructor.
--
-- The constraint @'ConstructorIndex' n s@ ensures that the constructor @n@
-- exists in the sum row @s@, and provides its tag index at compile time.
-- This function is typically used via the 'Variant' pattern synonym.
injectVariant :: forall n s fs. ConstructorIndex n s => Field n -> Record fs -> Variant s
injectVariant _ (RowRep r) =
  RowRep (injectRep (constructorIndex @_ @n @s) (toList (repVals r)))

-- | Project a specific constructor from a variant.
--
-- Returns 'Just' the fields if the variant's active tag matches the requested
-- constructor @n@, or 'Nothing' otherwise.
projectVariant :: forall n s fs. ConstructorIndex n s => Field n -> Variant s -> Maybe (Record fs)
projectVariant _ (RowRep r) =
  case projectRep (constructorIndex @_ @n @s) r of
    Just vals -> Just (RowRep (productRep vals))
    Nothing   -> Nothing

-- | A pattern synonym for matching and constructing variants safely.
--
-- This pattern allows ergonomic matching on a 'Variant' without exposing the
-- internal 'Rep' or tag values.
--
-- @
-- case v of
--   Variant (Field \@"Foo") r -> ...
--   Variant (Field \@"Bar") r -> ...
-- @
pattern Variant :: forall n s fs. ConstructorIndex n s => Field n -> Record fs -> Variant s
pattern Variant f r <- ( (\v -> (Field :: Field n, projectVariant (Field :: Field n) v)) -> (f, Just r) )
  where Variant f r = injectVariant f r
