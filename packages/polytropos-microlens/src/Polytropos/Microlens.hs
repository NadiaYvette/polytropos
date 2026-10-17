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

{-|
Module      : Polytropos.Microlens
Description : Lightweight microlens optics integration for Polytropos open records
Copyright   : (c) 2026 The Polytropos Authors
License     : EUPL-1.2 OR Apache-2.0
Maintainer  : nadia.yvette.chambers@ik.me
Stability   : experimental
Portability : non-portable (GHC extensions)

Class-based optics integration for developers who use @microlens@
specifically to avoid transitive dependency bloat: this package depends
strictly on @base@, @polytropos-core@, and @microlens@.

= Architectural Overview & Rationale

Unlike full @lens@, which brings in a large dependency graph, @microlens@
provides the core lens combinators in a lightweight package.

In @polytropos-microlens@:
* Name-based field access goes through 'fieldLens', whose 'FieldIndex'
  constraint is solved to a literal slot index by @polytropos-plugin@.
* The 'each' instance traverses every field of a homogeneous record (where
  all fields have the same type, witnessed by 'AllFieldsAre') in a single
  pass over the flat 'Data.Primitive.SmallArray.SmallArray'.

= When to Use This Module

* When your project prioritizes fast build times and minimal transitive
  dependencies, and requires basic lens access to @polytropos@ records.

= When Not to Use This Module

* When you need prisms over sum variants or advanced indexed optics; use
  "Polytropos.Optics" or "Polytropos.Lens" instead.

= Worked Example

> {-# LANGUAGE DataKinds #-}
> {-# LANGUAGE TypeApplications #-}
> {-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}
>
> import Lens.Micro ((^.), (%~), (&))
> import Polytropos
> import Polytropos.Microlens
>
> -- A genuinely heterogeneous record:
> type User = Record '["name" ':= String, "score" ':= Int]
>
> user :: User
> user = REC { name = "Alice", score = 95 }
>
> -- Accessing a field via heterogeneous fieldLens:
> userName :: String
> userName = user ^. fieldLens (Field @"name")  -- "Alice"
>
> -- Modifying a field:
> user' :: User
> user' = user & fieldLens (Field @"score") %~ (+ 5)  -- score = 100
-}
module Polytropos.Microlens
  ( -- * Field Lenses
    fieldLens

    -- * Homogeneity Evidence
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
