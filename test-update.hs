{-# LANGUAGE OverloadedRecordUpdate #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE UndecidableInstances #-}
module TestUpdate where
import GHC.TypeLits
import GHC.Exts

class SetField (x :: Symbol) r a where
  setField :: r -> a -> r

getField :: r -> a
getField = undefined

f r = r { x = 10, y = True }
