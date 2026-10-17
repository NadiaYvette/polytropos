{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -Wno-orphans #-}
{-|
Module      : Polytropos.Optics
Description : optics-core integration for polytropos open records and variants
Copyright   : (c) 2026 The Polytropos Authors
License     : EUPL-1.2 OR Apache-2.0
Maintainer  : nadia.yvette.chambers@ik.me
Stability   : experimental
Portability : non-portable (GHC extensions)

Integration between @polytropos@ and the @optics@ \/ @optics-core@ ecosystem.

This module provides first-class optics for open records and variants:
* Van Laarhoven lenses for record fields via 'fieldLens'.
* First-class prisms for variant constructors via 'ctorOptic'.
* Overloaded labels ('LabelOptic') allowing @#fieldname@ lens syntax with @OverloadedLabels@.

= Architectural Overview & Rationale

Rather than treating record fields as string lookups in runtime maps, @polytropos-optics@
relies on the literal zero-based slot indices synthesized by @polytropos-plugin@.
Each lens focuses directly on an array slot in the underlying contiguous 'Data.Primitive.SmallArray.SmallArray'.
Prisms inspect the unboxed constructor tag in \(O(1)\) and extract the constructor's payload.

= When to Use This Module

* When your application uses the @optics@ library and you want idiomatic lens and prism
  operations over @polytropos@ records and variants.
* When you want @#fieldName@ syntax for record field access and update.

= When Not to Use This Module

* If your project is built around Edward Kmett's @lens@ library, use "Polytropos.Lens" instead.
* If your project aims for minimal dependencies and uses @microlens@, use "Polytropos.Microlens" instead.

= Worked Example

> {-# LANGUAGE DataKinds #-}
> {-# LANGUAGE OverloadedLabels #-}
> {-# LANGUAGE TypeApplications #-}
> {-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}
>
> import Optics.Core
> import Polytropos
> import Polytropos.Optics
>
> type Person = Record '["name" ':= String, "age" ':= Int]
>
> alice :: Person
> alice = REC { name = "Alice", age = 30 }
>
> -- Reading via overloaded label:
> aliceAge :: Int
> aliceAge = alice ^. #age  -- 30
>
> -- Updating via overloaded label:
> olderAlice :: Person
> olderAlice = alice & #age %~ (+ 1)  -- age = 31
>
> -- Working with variant prisms:
> type Shape = Variant '["Circle" ':= '["radius" ':= Double]]
>
> myCircle :: Shape
> myCircle = VAR { Circle = REC { radius = 5.0 } }
>
> circleRadius :: Maybe Double
> circleRadius = preview (ctorOptic (Field @"Circle") % #radius) myCircle  -- Just 5.0
-}
module Polytropos.Optics (
    -- * Record Field Lenses
    fieldLens

    -- * Variant Constructor Prisms
  , ctorOptic
  ) where

import Optics.Core
import Polytropos
import Polytropos.Core
import GHC.TypeLits
import GHC.Records
import Unsafe.Coerce
import Data.Functor.Identity

-- | Van Laarhoven lens for a record field specified by label.
fieldLens :: forall n r a. FieldIndex n r a => Field n -> LensVL (Record r) (Record r) a a
fieldLens _ f (RowRep r) =
  fmap (\a' -> RowRep (setFieldAt (fieldIndex @_ @n @r @a) (Identity (unsafeCoerce a')) r))
       (f (unsafeCoerce (runIdentity (fieldAt (fieldIndex @_ @n @r @a) r))))

instance {-# OVERLAPPING #-} (KnownSymbol n, HasField n (Record r) field, FieldIndex n r field, a ~ field, b ~ field)
      => LabelOptic n A_Lens (Record r) (Record r) a b where
  labelOptic = lensVL (fieldLens (Field @n))

-- | Prism optic for a variant constructor specified by label.
ctorOptic :: forall c s fs. ConstructorIndex c s => Field c -> Optic A_Prism NoIx (Variant s) (Variant s) (Record fs) (Record fs)
ctorOptic f = prism' (injectVariant f) project
  where
    project :: Variant s -> Maybe (Record fs)
    project (RowRep r) = case projectRep (constructorIndex @_ @c @s) r of
      Just vals -> Just (RowRep (productRep vals))
      Nothing   -> Nothing
