{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

{-|
Module      : Polytropos.Profunctors
Description : Pure profunctor optics for polytropos open records and variants
Copyright   : (c) 2026 The Polytropos Authors
License     : EUPL-1.2 OR Apache-2.0
Maintainer  : nadia.yvette.chambers@ik.me
Stability   : experimental
Portability : non-portable (GHC extensions)

Integration between @polytropos@ and the @profunctors@ ecosystem.

This module provides first-class profunctor optics operating directly over
Polytropos's unboxed 'Data.Primitive.SmallArray.SmallArray' memory layout:
* Pure profunctor lenses ('Lens', 'Lens'') via 'Data.Profunctor.Strong'.
* Pure profunctor prisms ('Prism', 'Prism'') via 'Data.Profunctor.Choice'.
* High-level typed optics ('fieldLens', 'ctorPrism') resolved at compile time via 'FieldIndex' and 'ConstructorIndex'.
* Low-level structural slot and tag optics ('slotLens', 'typedSlotLens', 'variantPrism', 'typedVariantPrism').

= Architectural Overview & Rationale

Unlike @polytropos-lens@ (which brings in Edward Kmett's heavyweight @lens@ hierarchy)
or @polytropos-optics@ (which relies on @optics-core@'s nominal subtyping lattice),
@polytropos-profunctors@ depends solely on the lightweight @profunctors@ package.

Record updates delegate directly to 'Polytropos.Core.setFieldAt', inheriting its
dual-mode optimization:
* Records with @<= 32@ fields update in-place within L1 CPU cache lines via 'Data.Primitive.SmallArray.thawSmallArray'.
* Records with @> 32@ fields use pre-allocated vectorized slice block copies via 'Data.Primitive.SmallArray.copySmallArray'.

= When to Use This Module

* When building arrow pipelines, categorical architectures, or streaming frameworks
  (such as @kernmantle@) that already rely on @profunctors@.
* When you want minimal dependency overhead without pulling in @lens@ or @optics-core@.

= Worked Example

> {-# LANGUAGE DataKinds #-}
> {-# LANGUAGE OverloadedLabels #-}
> {-# LANGUAGE TypeApplications #-}
> {-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}
>
> import Polytropos
> import Polytropos.Profunctors
>
> type User = Record '["name" ':= String, "score" ':= Int]
>
> bob :: User
> bob = REC { name = "Bob", score = 10 }
>
> -- Reading and writing via profunctor lenses:
> bobScore :: Int
> bobScore = view (fieldLens (Field @"score")) bob  -- 10
>
> promotedBob :: User
> promotedBob = over (fieldLens (Field @"score")) (+ 5) bob  -- score = 15
-}
module Polytropos.Profunctors
  ( -- * Profunctor Optics Types
    Lens
  , Lens'
  , Prism
  , Prism'
    -- * Optics Constructors
  , lens
  , prism
  , prism'
    -- * Optics Eliminators & Modifiers
  , view
  , preview
  , review
  , over
  , set
    -- * High-Level Row Lenses & Prisms
  , fieldLens
  , ctorPrism
    -- * Low-Level Structural Slot & Tag Optics
  , slotLens
  , typedSlotLens
  , variantPrism
  , typedVariantPrism
  ) where

import Data.Functor.Identity (Identity(..))
import Data.Monoid (First(..))
import Data.Primitive.SmallArray
  ( SmallArray
  , sizeofSmallArray
  , indexSmallArray
  , smallArrayFromList
  )
import Data.Profunctor (Profunctor(..), Strong(..), Choice(..))
import Data.Profunctor.Types (Forget(..))
import Data.Tagged (Tagged(..))
import GHC.Exts (Any)
import Unsafe.Coerce (unsafeCoerce)

import Polytropos
  ( Record
  , Variant
  , Field(..)
  , injectVariant
  )
import Polytropos.Core
  ( Rep(..)
  , RowRep(..)
  , FieldIndex(..)
  , ConstructorIndex(..)
  , fieldAt
  , setFieldAt
  , projectRep
  )

-- | Standard Profunctor Lens.
type Lens s t a b = forall p. Strong p => p a b -> p s t

-- | Monomorphic Profunctor Lens.
type Lens' s a = Lens s s a a

-- | Standard Profunctor Prism.
type Prism s t a b = forall p. Choice p => p a b -> p s t

-- | Monomorphic Profunctor Prism.
type Prism' s a = Prism s s a a

-- | Construct a profunctor lens from a getter and setter.
lens :: (s -> a) -> (s -> b -> t) -> Lens s t a b
lens getter setter = dimap (\s -> (getter s, s)) (\(b, s) -> setter s b) . first'
{-# INLINE lens #-}

-- | Construct a profunctor prism from an injector and matcher.
prism :: (b -> t) -> (s -> Either t a) -> Prism s t a b
prism build match = dimap match (either id build) . right'
{-# INLINE prism #-}

-- | Construct a monomorphic profunctor prism from an injector and matcher.
prism' :: (b -> s) -> (s -> Maybe b) -> Prism' s b
prism' build match = prism build (\s -> maybe (Left s) Right (match s))
{-# INLINE prism' #-}

-- | Extract the target of a lens using the 'Forget' profunctor.
view :: Lens' s a -> s -> a
view l = runForget (l (Forget id))
{-# INLINE view #-}

-- | Attempt to extract the focus of a prism using 'Forget (First a)'.
preview :: Prism' s a -> s -> Maybe a
preview p = getFirst . runForget (p (Forget (First . Just)))
{-# INLINE preview #-}

-- | Inject a target into a sum using the 'Tagged' profunctor.
review :: Prism' s a -> a -> s
review p = unTagged . p . Tagged
{-# INLINE review #-}

-- | Modify the focus of an optic using the @(->)@ profunctor.
over :: Lens s t a b -> (a -> b) -> s -> t
over l = l
{-# INLINE over #-}

-- | Set the focus of a lens to a specific value.
set :: Lens s t a b -> b -> s -> t
set l val = over l (const val)
{-# INLINE set #-}

--------------------------------------------------------------------------------
-- High-Level Row Lenses & Prisms
--------------------------------------------------------------------------------

-- | A typed profunctor lens focusing on an open 'Record' field specified by 'Field',
-- resolved at compile time via 'FieldIndex'.
fieldLens :: forall n r a. FieldIndex n r a => Field n -> Lens' (Record r) a
fieldLens _ = lens getter setter
  where
    idx = fieldIndex @_ @n @r @a
    getter (RowRep r) = unsafeCoerce (runIdentity (fieldAt idx r))
    setter (RowRep r) val =
      let boxed = Identity (unsafeCoerce val :: Any)
      in RowRep (setFieldAt idx boxed r)
{-# INLINE fieldLens #-}

-- | A typed profunctor prism focusing on an open 'Variant' constructor specified by 'Field',
-- resolved at compile time via 'ConstructorIndex'.
ctorPrism :: forall c s fs. ConstructorIndex c s => Field c -> Prism' (Variant s) (Record fs)
ctorPrism f = prism (injectVariant f) project
  where
    cIdx = constructorIndex @_ @c @s
    project (RowRep r) = case projectRep cIdx r of
      Just prodRep -> Right (RowRep prodRep)
      Nothing      -> Left (RowRep r)
{-# INLINE ctorPrism #-}

--------------------------------------------------------------------------------
-- Low-Level Structural Slot & Tag Optics
--------------------------------------------------------------------------------

-- | A zero-cost profunctor lens focusing on the raw @i@-th slot of an open 'Record'.
slotLens :: Int -> Lens' (Record r) (Identity Any)
slotLens idx = lens getter setter
  where
    getter (RowRep r) = fieldAt idx r
    setter (RowRep r) val = RowRep (setFieldAt idx val r)
{-# INLINE slotLens #-}

-- | A typed profunctor lens focusing on the @i@-th field of an open 'Record'.
typedSlotLens :: forall a r. Int -> Lens' (Record r) a
typedSlotLens idx = lens getter setter
  where
    getter (RowRep r) = unsafeCoerce (runIdentity (fieldAt idx r))
    setter (RowRep r) val =
      let boxed = Identity (unsafeCoerce val :: Any)
      in RowRep (setFieldAt idx boxed r)
{-# INLINE typedSlotLens #-}

-- | A profunctor prism focusing on an open 'Variant' constructor matching a constructor tag.
variantPrism :: Word -> Prism' (Variant s) (SmallArray (Identity Any))
variantPrism targetTag = prism build match
  where
    build vals = RowRep (Rep targetTag vals)
    match (RowRep rep@(Rep t vals))
      | t == targetTag = Right vals
      | otherwise      = Left (RowRep rep)
{-# INLINE variantPrism #-}

-- | A typed profunctor prism focusing on a single-payload 'Variant' constructor by constructor tag.
typedVariantPrism :: forall a s. Word -> Prism' (Variant s) a
typedVariantPrism targetTag = prism build match
  where
    build x =
      let payload = smallArrayFromList [Identity (unsafeCoerce x :: Any)]
      in RowRep (Rep targetTag payload)
    match (RowRep rep@(Rep t vals))
      | t == targetTag && sizeofSmallArray vals >= 1 =
          Right (unsafeCoerce (runIdentity (indexSmallArray vals 0)))
      | otherwise =
          Left (RowRep rep)
{-# INLINE typedVariantPrism #-}
