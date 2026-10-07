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
module Polytropos.Optics (
    fieldLens
  , ctorOptic
  ) where

import Optics.Core
import Polytropos
import Polytropos.Core
import GHC.TypeLits
import GHC.Records
import Unsafe.Coerce
import Data.Functor.Identity

fieldLens :: forall n r a. FieldIndex n r a => Field n -> LensVL (Record r) (Record r) a a
fieldLens _ f (RowRep r) =
  fmap (\a' -> RowRep (setFieldAt (fieldIndex @_ @n @r @a) (Identity (unsafeCoerce a')) r))
       (f (unsafeCoerce (runIdentity (fieldAt (fieldIndex @_ @n @r @a) r))))

instance {-# OVERLAPPING #-} (KnownSymbol n, HasField n (Record r) field, FieldIndex n r field, a ~ field, b ~ field)
      => LabelOptic n A_Lens (Record r) (Record r) a b where
  labelOptic = lensVL (fieldLens (Field @n))

ctorOptic :: forall c s fs. ConstructorIndex c s => Field c -> Optic A_Prism NoIx (Variant s) (Variant s) (Record fs) (Record fs)
ctorOptic f = prism' (injectVariant f) project
  where
    project :: Variant s -> Maybe (Record fs)
    project (RowRep r) = case projectRep (constructorIndex @_ @c @s) r of
      Just vals -> Just (RowRep (productRep vals))
      Nothing   -> Nothing
