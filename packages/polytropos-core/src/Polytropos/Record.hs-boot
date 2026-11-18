{-# LANGUAGE DataKinds #-}
module Polytropos.Record where

import Data.Kind (Type)
import Polytropos.Core (Rep, Row)

newtype Record (f :: Type -> Type) (r :: Row) = Record { unRecord :: Rep f () }
