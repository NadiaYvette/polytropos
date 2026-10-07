{-# LANGUAGE OverloadedRecordUpdate #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE RankNTypes #-}
module TestUpdate where
import GHC.TypeLits
class SetField (x :: Symbol) r a r' where
  setField :: r -> a -> r'
getField r = undefined
fromInteger = undefined
f r = r { x = 10, y = True }
