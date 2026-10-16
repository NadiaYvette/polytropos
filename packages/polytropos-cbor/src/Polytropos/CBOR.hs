{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

{-|
Module      : Polytropos.CBOR
Description : High-performance binary CBOR serialization for Polytropos records and variants
Copyright   : (c) 2026 The Polytropos Authors
License     : EUPL-1.2 OR Apache-2.0
Maintainer  : nadia.yvette.chambers@ik.me
Stability   : experimental
Portability : non-portable (GHC extensions)

High-performance binary CBOR serialization of @polytropos@ open records
and variants via @cborg@ \/ @serialise@, without intermediate tree boxing.

= Architectural Overview & Rationale

== Binary Wire Format

* A record encodes as a standard CBOR array: one length header (the row's arity)
  followed by the flat payload field encodings in row order.
* A variant encodes as a CBOR array consisting of the constructor's 'Word' tag followed
  by that constructor's payload field encodings.

== Positional & Allocation-Free

Because field names exist only at the type level in row polymorphism, the binary
encoder is purely /positional/: no string keys are written to the wire. Encoding
and decoding are executed as single unrolled passes directly over the flat
@t'Polytropos.Core.Rep'@ payload array with no intermediate allocations.

= When to Use This Module

* When network bandwidth, binary storage size, and serialization speed are critical.
* For inter-service RPC, binary logs, and compact caching.

= Worked Example

@
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

import Codec.Serialise (serialise, deserialise)
import Polytropos
import Polytropos.CBOR

type Packet = Record '["id" ':= Int, "payload" ':= Int]

pkt :: Packet
pkt = insertField (Field \@"id") (101 :: Int)
    $ insertField (Field \@"payload") (202 :: Int)
    $ emptyRecord

-- Serializes to compact CBOR binary:
bytes = serialise pkt

-- Deserializes back to Packet:
pkt' :: Packet
pkt' = deserialise bytes
@
-}
module Polytropos.CBOR
  ( -- * Homogeneity Evidence
    AllFieldsAre
  , AllCtorsHom (..)
  , RowField
  , SumField
  ) where

-- (re-exports of the module's own families, declared below)

import Data.Functor.Identity (Identity (..))
import Data.Kind             (Constraint, Type)
import Data.Proxy            (Proxy (..))
import Data.Void             (Void)
import GHC.Exts              (Any, toList)
import GHC.TypeLits          (KnownSymbol, symbolVal)
import Codec.CBOR.Encoding   (Encoding, encodeListLen, encodeWord)
import Codec.CBOR.Decoding   (decodeListLen, decodeWord)
import Codec.Serialise       (Serialise (..))
import Polytropos            (Record, Variant)
import Polytropos.Core       (Pair (..), Row, SumRow, RowRep (..), noInlineUnsafeCo,
                              productRep, injectRep, repTag, repVals)

{-------------------------------------------------------------------------------
  Homogeneity evidence and row introspection
-------------------------------------------------------------------------------}

-- | Evidence that every field of the row @r@ has type @a@.
type family AllFieldsAre (a :: Type) (r :: Row) :: Constraint where
  AllFieldsAre _  '[]                = ()
  AllFieldsAre a ((n ':= a) ': rest) = AllFieldsAre a rest

-- | The field type of a homogeneous row: the type of every field, 'Void'
-- for the empty row.
type family RowField (r :: Row) :: Type where
  RowField '[]                 = Void
  RowField ((n ':= a) ': rest) = a

-- | The field type shared by every constructor of a sum row, 'Void' for the
-- empty sum.
type family SumField (s :: SumRow) :: Type where
  SumField '[]                = Void
  SumField ((c ':= fs) ': s)  = RowField fs

-- | Every constructor of the sum row @s@ has a homogeneous field row of type
-- @a@, reified as constructor names paired with their arities.
--
-- @a@ appears in the method so the dictionary is never ambiguous at a use
-- site (it is otherwise a phantom of the class).
class AllCtorsHom (a :: Type) (s :: SumRow) where
  ctorArities :: Proxy a -> Proxy s -> [(String, Int)]

instance AllCtorsHom a '[] where
  ctorArities _ _ = []

instance (KnownSymbol c, AllFieldsAre a fs, AllCtorsHom a s)
      => AllCtorsHom a ((c ':= fs) ': s) where
  ctorArities pa _ =
    (symbolVal (Proxy @c), length (arityList (Proxy @fs)))
      : ctorArities pa (Proxy @s)
    where
      -- pin fs's arity through the type family without walking it at runtime
      arityList :: Proxy fs -> [a]
      arityList _ = []

{-------------------------------------------------------------------------------
  Record codecs
-------------------------------------------------------------------------------}

instance {-# OVERLAPPABLE #-} ( a ~ RowField r
                              , AllFieldsAre a r
                              , Serialise a
                              )
      => Serialise (Record r) where
  encode (RowRep rep) =
    let slots = toList (repVals rep)
    in encodeListLen (fromIntegral (length slots))
         <> mconcat (map encSlot slots)
    where
      encSlot :: Identity Any -> Encoding
      encSlot v = encode (noInlineUnsafeCo (runIdentity v) :: a)

  decode = do
    n <- decodeListLen
    slots <- mapM (const decSlot) [1 .. n :: Int]
    pure (RowRep (productRep (map (Identity . noInlineUnsafeCo) (slots :: [a]))))
    where
      decSlot = decode

{-------------------------------------------------------------------------------
  Variant codecs
-------------------------------------------------------------------------------}

instance {-# OVERLAPPABLE #-} ( a ~ SumField s
                              , AllCtorsHom a s
                              , Serialise a
                              )
      => Serialise (Variant s) where
  encode (RowRep rep) =
    let tag = repTag rep
        slots = toList (repVals rep)
    in encodeListLen (fromIntegral (1 + length slots))
         <> encodeWord tag
         <> mconcat (map encSlot slots)
    where
      encSlot :: Identity Any -> Encoding
      encSlot v = encode (noInlineUnsafeCo (runIdentity v) :: a)

  decode = do
    n <- decodeListLen
    if n < 1
      then fail "polytropos-cbor: variant encoding missing constructor tag"
      else do
        tag  <- decodeWord
        vals <- mapM (const decSlot) [1 .. n - 1 :: Int]
        pure (RowRep (injectRep tag
                                     (map (Identity . noInlineUnsafeCo) (vals :: [a]))))
    where
      decSlot = decode
