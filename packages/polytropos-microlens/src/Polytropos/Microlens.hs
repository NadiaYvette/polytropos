{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- |
-- Module      : Polytropos.Microlens
-- Description : microlens integration for polytropos open records
-- Copyright   : (c) 2026 The Polytropos Authors
-- License     : EUPL-1.2 OR Apache-2.0
--
-- Class-based optics integration for developers who use @microlens@
-- specifically to avoid transitive dependency bloat: this package depends
-- strictly on @base@, @polytropos-core@, and @microlens@.
--
-- = Worked Example
--
-- @
-- type Rec = Record '["x" ':= Int, "y" ':= Int]
--
-- bumpAll :: Rec -> Rec
-- bumpAll rec = rec & 'each' %~ (+ 1)
--
-- bumpX :: FieldIndex "x" r a => Record r -> Record r
-- bumpX rec = rec & 'fieldLens' #x %~ (+ 1)
-- @
--
-- The 'each' instance covers every field of a /homogeneous/ record (all
-- fields of the same type; see 'AllFieldsAre'). Name-based access goes
-- through 'fieldLens', whose 'FieldIndex' constraint is solved to a literal
-- slot index by the @polytropos-plugin@ — no type-level search at the use
-- site.
module Polytropos.Microlens
  ( -- * Field lenses
    fieldLens
    -- * Homogeneity evidence
  , AllFieldsAre
  ) where

import Data.Kind            (Constraint, Type)
import Data.Functor.Identity (Identity (..))
import GHC.Exts             (toList)
import Lens.Micro           (Lens')
import Lens.Micro.Internal  (Each (..))
import Polytropos           (Record, Field (..))
import Polytropos.Core      (FieldIndex (..), Row, Pair (..), fieldAt,
                             noInlineUnsafeCo, productRep, repVals, setFieldAt,
                             RowRep (..))

{-------------------------------------------------------------------------------
  Homogeneity evidence
-------------------------------------------------------------------------------}

-- | Evidence that every field of the row @r@ has type @a@.
--
-- Closed type family, so a heterogeneous row fails to reduce and the
-- dependent instances simply do not apply. This is what lets 'each' be a
-- genuine traversal with a single element type instead of an erased
-- @forall@-traversal.
type family AllFieldsAre (a :: Type) (r :: Row) :: Constraint where
  AllFieldsAre _  '[]                = ()
  AllFieldsAre a ((n ':= a) ': rest) = AllFieldsAre a rest

{-------------------------------------------------------------------------------
  Instances
-------------------------------------------------------------------------------}

-- | Homogeneous traversal across all record fields.
--
-- @
-- 'each' :: AllFieldsAre a r => 'Lens.Micro.Traversal' ('Record' ((n ':= a) ': r)) ('Record' ((n ':= a) ': r)) a a
-- @
--
-- The instance head fixes the element type to the row's field type, which is
-- what the @Each@ functional dependencies require: for a row-typed record the
-- row determines the field types, so a type-changing traversal is impossible
-- anyway. Implemented over the flat 'Polytropos.Core.Rep' payload in one
-- pass: read the slots, run the effectful function over the values, and
-- rebuild the record with 'Polytropos.Core.productRep'. For a record with @N@
-- fields this is @O(N)@ with no intermediate tree representation.
--
-- An empty record has no element type to traverse; 'each' deliberately does
-- not apply to @'Record' '[]@.
instance AllFieldsAre a r
      => Each (Record ((n ':= a) ': r)) (Record ((n ':= a) ': r)) a a where
  each f (RowRep rep) =
    RowRep . productRep . noInlineUnsafeCo
      <$> traverse (\(Identity x) -> Identity <$> f (noInlineUnsafeCo x))
                   (toList (repVals rep))
  {-# INLINE each #-}

-- | Lens on a record field by name.
--
-- @
-- 'fieldLens' #foo :: 'FieldIndex' "foo" r a => 'Lens'' ('Record' r) a
-- @
--
-- The 'FieldIndex' dictionary carries the slot index as a literal, computed
-- by the TcPlugin; there is no runtime name lookup and no type-level search.
fieldLens :: forall n r a. FieldIndex n r a => Field n -> Lens' (Record r) a
fieldLens _ f (RowRep rep) =
  fmap (\a' -> RowRep (setFieldAt (fieldIndex @_ @n @r @a)
                                  (Identity (noInlineUnsafeCo a'))
                                  rep))
       (f (noInlineUnsafeCo (runIdentity (fieldAt (fieldIndex @_ @n @r @a) rep))))
{-# INLINE fieldLens #-}
