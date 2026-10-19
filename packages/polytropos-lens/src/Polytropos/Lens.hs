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
Module      : Polytropos.Lens
Description : Comprehensive lens-suite integration for Polytropos open records and variants
Copyright   : (c) 2026 The Polytropos Authors
License     : EUPL-1.2 OR Apache-2.0
Maintainer  : nadia.yvette.chambers@ik.me
Stability   : experimental
Portability : non-portable (GHC extensions)

Complete integration with Edward Kmett's @lens@ library while keeping the
core @polytropos@ packages free of the heavyweight transitive dependency tree.

= Architectural Overview & Rationale

This module bridges @polytropos@ flat runtime representations to standard @lens@
abstractions:
* __Positional lenses__: 'Field1' through 'Field9' instances on product records,
  so @rec ^. _1@ and @rec ^. _2@ read the first and second slots by position in \(O(1)\).
* __Name-based lenses__: 'fieldLens' focuses on a field by label symbol with literal
  index calculation via @polytropos-plugin@.
* __Container classes__: 'Ixed' and 'At' instances keyed by field name for dynamic
  or symbol-indexed access.
* __Homogeneous traversals__: 'Each' instances over records whose fields share one
  type ('AllFieldsAre').
* __Variant prisms__: 'prismVariant' constructs first-class 'Prism'' optics for
  open variant constructors with \(O(1)\) tag matching.

= When to Use This Module

* When your codebase heavily utilizes the full @lens@ hierarchy (profunctor optics,
  indexed traversals, 'Field1'..'Field9').

= When Not to Use This Module

* If you only need lightweight lenses and want to minimize dependencies, use
  "Polytropos.Microlens" instead.
* If your codebase uses the newer @optics@ hierarchy, use "Polytropos.Optics" instead.

= Worked Example

> {-# LANGUAGE DataKinds #-}
> {-# LANGUAGE TypeApplications #-}
> {-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}
>
> import Control.Lens
> import Polytropos
> import Polytropos.Lens
>
> -- A genuinely heterogeneous record:
> type Person = Record '["name" ':= String, "age" ':= Int]
>
> person :: Person
> person = REC { name = "Bob", age = 25 }
>
> -- Positional heterogeneous access:
> firstField :: String
> firstField = person ^. _1  -- "Bob"
>
> -- Name-based heterogeneous access:
> ageVal :: Int
> ageVal = person ^. fieldLens (Field @"age")  -- 25
>
> -- Positional modification:
> olderPerson :: Person
> olderPerson = person & _2 .~ 26
>
> -- Name-based modification:
> olderPerson' :: Person
> olderPerson' = person & fieldLens (Field @"age") %~ (+ 1)
-}
module Polytropos.Lens
  ( -- * Field Lenses by Name
    fieldLens

    -- * Variant Prisms
  , prismVariant

    -- * Homogeneity Evidence and Row Introspection
  , AllFieldsAre
  , RowField
  , FieldNames (..)
  ) where

import Data.Functor.Identity (Identity (..))
import Data.Kind             (Constraint, Type)
import Data.List             (elemIndex)
import Data.Proxy            (Proxy (..))
import Data.Void             (Void)
import Control.Lens          (At (..), Each (..), Field1 (..), Field2 (..),
                              Field3 (..), Field4 (..), Field5 (..),
                              Field6 (..), Field7 (..), Field8 (..),
                              Field9 (..), Ixed (..), IxValue, Index, Lens',
                              Prism', preview, prism, set, (<&>))
import GHC.Exts              (toList)
import GHC.TypeLits          (KnownSymbol, symbolVal)
import Polytropos            (Record, Variant, Field (..), injectVariant)
import Polytropos.Core       (ConstructorIndex (..), FieldIndex (..), Pair (..),
                              Row, fieldAt, noInlineUnsafeCo, productRep,
                              projectRep, repVals, setFieldAt, RowRep (..))

{-------------------------------------------------------------------------------
  Row introspection
-------------------------------------------------------------------------------}

-- | The element type of a homogeneous row: the type of every field.
--
-- Undefined for @'[]@ (an empty record has no field type) and meaningless for
-- heterogeneous rows; both cases are ruled out where it matters by
-- 'AllFieldsAre'.
type family RowField (r :: Row) :: Type where
  RowField '[]                = Void
  RowField ((n ':= a) ': rest) = a

-- | Evidence that every field of the row @r@ has type @a@.
--
-- Closed type family, so a heterogeneous row fails to reduce and the
-- dependent instances simply do not apply.
type family AllFieldsAre (a :: Type) (r :: Row) :: Constraint where
  AllFieldsAre _  '[]                = ()
  AllFieldsAre a ((n ':= a) ': rest) = AllFieldsAre a rest

-- | The field names of a row, in row order, reified from the type level.
class FieldNames (r :: Row) where
  fieldNames :: Proxy r -> [String]

instance FieldNames '[] where
  fieldNames _ = []

instance (KnownSymbol n, FieldNames r) => FieldNames ((n ':= a) ': r) where
  fieldNames _ = symbolVal (Proxy @n) : fieldNames (Proxy @r)

{-------------------------------------------------------------------------------
  Slot plumbing (internal)
-------------------------------------------------------------------------------}

-- | Lens to the slot at index @i@. The caller must know that slot @i@ holds
-- a value of type @a@; every exported use site guarantees this from the row
-- type (a literal below the row's arity, a plugin-computed 'FieldIndex', or a
-- runtime name resolved against the reified row).
slotLens :: forall r a. Int -> Lens' (Record r) a
slotLens i f (RowRep rep) =
  fmap (\a' -> RowRep (setFieldAt i (Identity (noInlineUnsafeCo a')) rep))
       (f (noInlineUnsafeCo (runIdentity (fieldAt i rep))))
{-# INLINE slotLens #-}

{-------------------------------------------------------------------------------
  Positional lenses: Field1 .. Field9
-------------------------------------------------------------------------------}

instance Field1 (Record ((n ':= a) ': r)) (Record ((n ':= a) ': r)) a a where
  _1 = slotLens 0

instance Field2 (Record ((n1 ':= a1) ': (n2 ':= a2) ': r))
                (Record ((n1 ':= a1) ': (n2 ':= a2) ': r)) a2 a2 where
  _2 = slotLens 1

instance Field3 (Record ((n1 ':= a1) ': (n2 ':= a2) ': (n3 ':= a3) ': r))
                (Record ((n1 ':= a1) ': (n2 ':= a2) ': (n3 ':= a3) ': r)) a3 a3 where
  _3 = slotLens 2

instance Field4 (Record ((n1 ':= a1) ': (n2 ':= a2) ': (n3 ':= a3) ': (n4 ':= a4) ': r))
                (Record ((n1 ':= a1) ': (n2 ':= a2) ': (n3 ':= a3) ': (n4 ':= a4) ': r)) a4 a4 where
  _4 = slotLens 3

instance Field5 (Record ((n1 ':= a1) ': (n2 ':= a2) ': (n3 ':= a3) ': (n4 ':= a4) ': (n5 ':= a5) ': r))
                (Record ((n1 ':= a1) ': (n2 ':= a2) ': (n3 ':= a3) ': (n4 ':= a4) ': (n5 ':= a5) ': r)) a5 a5 where
  _5 = slotLens 4

instance Field6 (Record ((n1 ':= a1) ': (n2 ':= a2) ': (n3 ':= a3) ': (n4 ':= a4) ': (n5 ':= a5) ': (n6 ':= a6) ': r))
                (Record ((n1 ':= a1) ': (n2 ':= a2) ': (n3 ':= a3) ': (n4 ':= a4) ': (n5 ':= a5) ': (n6 ':= a6) ': r)) a6 a6 where
  _6 = slotLens 5

instance Field7 (Record ((n1 ':= a1) ': (n2 ':= a2) ': (n3 ':= a3) ': (n4 ':= a4) ': (n5 ':= a5) ': (n6 ':= a6) ': (n7 ':= a7) ': r))
                (Record ((n1 ':= a1) ': (n2 ':= a2) ': (n3 ':= a3) ': (n4 ':= a4) ': (n5 ':= a5) ': (n6 ':= a6) ': (n7 ':= a7) ': r)) a7 a7 where
  _7 = slotLens 6

instance Field8 (Record ((n1 ':= a1) ': (n2 ':= a2) ': (n3 ':= a3) ': (n4 ':= a4) ': (n5 ':= a5) ': (n6 ':= a6) ': (n7 ':= a7) ': (n8 ':= a8) ': r))
                (Record ((n1 ':= a1) ': (n2 ':= a2) ': (n3 ':= a3) ': (n4 ':= a4) ': (n5 ':= a5) ': (n6 ':= a6) ': (n7 ':= a7) ': (n8 ':= a8) ': r)) a8 a8 where
  _8 = slotLens 7

instance Field9 (Record ((n1 ':= a1) ': (n2 ':= a2) ': (n3 ':= a3) ': (n4 ':= a4) ': (n5 ':= a5) ': (n6 ':= a6) ': (n7 ':= a7) ': (n8 ':= a8) ': (n9 ':= a9) ': r))
                (Record ((n1 ':= a1) ': (n2 ':= a2) ': (n3 ':= a3) ': (n4 ':= a4) ': (n5 ':= a5) ': (n6 ':= a6) ': (n7 ':= a7) ': (n8 ':= a8) ': (n9 ':= a9) ': r)) a9 a9 where
  _9 = slotLens 8

{-------------------------------------------------------------------------------
  Homogeneous traversal: Each
-------------------------------------------------------------------------------}

-- | @each :: AllFieldsAre a r => Traversal (Record ((n ':= a) ': r)) ('Record' ((n ':= a) ': r)) a a@
--
-- The instance head fixes the element type to the row's field type, which is
-- what the @Each@ functional dependencies require: for a row-typed record the
-- row determines the field types, so a type-changing traversal is impossible
-- anyway. An empty record has no element type to traverse and deliberately
-- gets no instance.
instance AllFieldsAre a r
      => Each (Record ((n ':= a) ': r)) (Record ((n ':= a) ': r)) a a where
  each f (RowRep rep) =
    RowRep . productRep . noInlineUnsafeCo
      <$> traverse (\(Identity x) -> Identity <$> f (noInlineUnsafeCo x))
                   (toList (repVals rep))
  {-# INLINE each #-}

{-------------------------------------------------------------------------------
  Container classes: Ixed and At, keyed by field name
-------------------------------------------------------------------------------}

-- | @ix :: String -> Traversal' (Record r) (RowField r)@
--
-- Field access by symbol name for /homogeneous/ records: the name is resolved
-- at runtime against the reified 'fieldNames' of the row, an @O(N)@ scan, and
-- a name that is not in the row gives the empty traversal. @'Index'
-- ('Record' r)@ is 'String' and @'IxValue' ('Record' r)@ is 'RowField' r.
--
-- Setting through 'ix' can only update existing fields: a record's shape is
-- fixed by its row, so addressing a name not in the row is a no-op.
type instance Index (Record r)   = String
type instance IxValue (Record r) = RowField r

instance (FieldNames r, AllFieldsAre (RowField r) r) => Ixed (Record r) where
  ix k f rec = case elemIndex k (fieldNames (Proxy @r)) of
    Just i  -> slotLens i f rec
    Nothing -> pure rec

-- | @'at' :: 'String' -> 'Lens'' ('Record' r) ('Maybe' ('RowField' r))@
--
-- Map-style lookup and update by field name, defined in terms of 'ix'.
-- Viewing yields 'Just' exactly for names in the row. Setting @'Just' v@
-- updates the field when present; setting @'Nothing'@ (deletion) and
-- insertion of names not in the row are no-ops, because a record's shape is
-- fixed by its row — the same caveat @lens@ documents for fixed-size
-- containers, and the reason 'ix' (which cannot insert anyway) is the
-- preferred interface.
instance Ixed (Record r) => At (Record r) where
  at k f rec = f (preview (ix k) rec) <&> \mv -> case mv of
    Just v  -> set (ix k) v rec
    Nothing -> rec

{-------------------------------------------------------------------------------
  Name-based lens and variant prisms
-------------------------------------------------------------------------------}

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

-- | Prism from a sum variant to the field record of one constructor.
--
-- @
-- 'prismVariant' (Field \@\"Some\") :: 'ConstructorIndex' \"Some\" s
--                                => 'Prism'' (t'Variant' s) ('Record' fs)
-- @
--
-- Built from 'Polytropos.injectVariant' and 'Polytropos.Core.projectRep': the
-- 'ConstructorIndex' dictionary carries the constructor's tag as a literal,
-- so matching is a single runtime tag comparison.
prismVariant :: forall c s fs. ConstructorIndex c s
             => Field c -> Prism' (Variant s) (Record fs)
prismVariant f = prism (injectVariant f) project
  where
    project :: Variant s -> Either (Variant s) (Record fs)
    project (RowRep rep) =
      case projectRep (constructorIndex @_ @c @s) rep of
        Just prodRep -> Right (RowRep prodRep)
        Nothing      -> Left (RowRep rep)
