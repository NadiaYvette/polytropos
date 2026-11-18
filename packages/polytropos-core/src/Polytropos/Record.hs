{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE RoleAnnotations #-}

-- |
-- Module      : Polytropos.Record
-- Description : Reified Record wrapper and Skew Boolean re-exports
module Polytropos.Record
  ( Record(..)
  , emptyRecord
  , (//>)
  , (<//)
  , (<+>)
  , (//~)
  , (|<)
  , (/-/)
  , (\^/)
  ) where

import Data.Kind (Type)
import Data.Primitive.SmallArray (sizeofSmallArray, smallArrayFromList)
import Polytropos.Core (Rep(..), Row)
import Polytropos.MergeMorph

-- | Flat record wrapper carrying row evidence and type constructor parameter.
newtype Record (f :: Type -> Type) (r :: Row) = Record { unRecord :: Rep f () }

instance Show (Record f r) where
  show (Record (Rep t arr)) = "<Record tag=" ++ show t ++ " fields=" ++ show (sizeofSmallArray arr) ++ ">"

-- | Construct an empty record with arity 0.
emptyRecord :: Record f '[]
emptyRecord = Record (Rep 0 (smallArrayFromList []))
