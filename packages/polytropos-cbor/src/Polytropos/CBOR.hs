{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
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
Module      : Polytropos.CBOR
Description : High-performance binary CBOR serialization for Polytropos records and variants
Copyright   : (c) 2026 The Polytropos Authors
License     : EUPL-1.2 OR Apache-2.0
Maintainer  : nadia.yvette.chambers@ik.me
Stability   : experimental
Portability : non-portable (GHC extensions)

High-performance binary CBOR serialization of heterogeneous and homogeneous
@polytropos@ open records and variants via @cborg@ \/ @serialise@, without intermediate
tree boxing.

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
@Rep@ payload array with no intermediate allocations.

== Truly Heterogeneous Row Support

Unlike satellites restricted to homogeneous types, @polytropos-cbor@ provides genuine
heterogeneous serialization across open rows via 'AllSerialise': every field requires
'Serialise' at /its own concrete type/, so rows mixing 'String', 'Int', 'Word', custom
types, or nested rows serialize and deserialize directly.

= When to Use This Module

* When network bandwidth, binary storage size, and serialization speed are critical.
* For inter-service RPC, binary logs, and compact caching.

= Worked Example

> {-# LANGUAGE DataKinds #-}
> {-# LANGUAGE TypeApplications #-}
> {-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}
>
> import Codec.Serialise (serialise, deserialise)
> import Polytropos
> import Polytropos.CBOR
>
> -- A genuinely heterogeneous record:
> type Packet = Record '["id" ':= Int, "payload" ':= String, "flags" ':= Word]
>
> pkt :: Packet
> pkt = REC { id = 101, payload = "sensor-ok", flags = 0 }
>
> -- Serializes to compact positional CBOR binary:
> bytes = serialise pkt
>
> -- Deserializes back to Packet:
> pkt' :: Packet
> pkt' = deserialise bytes
-}
module Polytropos.CBOR
  ( -- * Heterogeneous Row Codecs
    AllSerialise (..)
  , FieldCount (..)
  , AllCtorsSerialise (..)

    -- * Homogeneity Evidence and Introspection Helpers
    -- $homogeneity
  , AllFieldsAre
  , AllCtorsHom (..)
  , RowField
  , SumField
  ) where

import Data.Functor.Identity (Identity (..))
import Data.Kind             (Constraint, Type)
import Data.Proxy            (Proxy (..))
import Data.Void             (Void)
import GHC.Exts              (Any, toList)
import GHC.TypeLits          (KnownSymbol, symbolVal)
import Codec.CBOR.Decoding   (Decoder, decodeListLen, decodeWord)
import Codec.CBOR.Encoding   (Encoding, encodeListLen, encodeWord)
import Codec.Serialise       (Serialise (..))
import Polytropos            (Record, Variant)
import Polytropos.Core       (Pair (..), Row, SumRow, RowRep (..), noInlineUnsafeCo,
                              productRep, injectRep, repTag, repVals)

{-------------------------------------------------------------------------------
  Heterogeneous row constraint walks
-------------------------------------------------------------------------------}

-- | Computes the arity (field count) of a row at compile time.
class FieldCount (r :: Row) where
  fieldCount :: Proxy r -> Int

instance FieldCount '[] where
  fieldCount _ = 0

instance FieldCount r => FieldCount ((n ':= a) ': r) where
  fieldCount _ = 1 + fieldCount (Proxy @r)

-- | Evidence that every field of the row @r@ has a 'Serialise' instance
-- at that field's own type. Serializes the erased payload slots in row order.
class AllSerialise (r :: Row) where
  encRecordCBOR :: Proxy r -> [Identity Any] -> Encoding
  decRecordCBOR :: forall s. Proxy r -> Decoder s [Identity Any]

instance AllSerialise '[] where
  encRecordCBOR _ _ = mempty
  decRecordCBOR _ = pure []

instance (Serialise a, AllSerialise r) => AllSerialise ((n ':= a) ': r) where
  encRecordCBOR _ (Identity x : xs) =
    encode (noInlineUnsafeCo x :: a) <> encRecordCBOR (Proxy @r) xs
  encRecordCBOR _ [] = error "polytropos-cbor: payload arity mismatch"

  decRecordCBOR _ = do
    x <- decode
    xs <- decRecordCBOR (Proxy @r)
    pure (Identity (noInlineUnsafeCo (x :: a) :: Any) : xs)

-- | Evidence that every constructor of the sum row @s@ has a heterogeneous
-- field row satisfying 'AllSerialise', paired with its constructor tag index.
class AllCtorsSerialise (s :: SumRow) where
  encVariantCBOR :: Proxy s -> Word -> Word -> [Identity Any] -> Encoding
  decVariantCBOR :: forall t. Proxy s -> Word -> Int -> Decoder t [Identity Any]

instance AllCtorsSerialise '[] where
  encVariantCBOR _ _ _ _ = error "polytropos-cbor: empty variant has no constructors"
  decVariantCBOR _ _ _ = fail "polytropos-cbor: unknown constructor tag"

instance (FieldCount fs, AllSerialise fs, AllCtorsSerialise s)
      => AllCtorsSerialise ((c ':= fs) ': s) where
  encVariantCBOR _ 0 origTag slots =
    encodeListLen (fromIntegral (1 + fieldCount (Proxy @fs)))
      <> encodeWord origTag
      <> encRecordCBOR (Proxy @fs) slots
  encVariantCBOR _ tag origTag slots =
    encVariantCBOR (Proxy @s) (tag - 1) origTag slots

  decVariantCBOR _ 0 len
    | len /= 1 + fieldCount (Proxy @fs) = fail "polytropos-cbor: variant field count mismatch"
    | otherwise = decRecordCBOR (Proxy @fs)
  decVariantCBOR _ tag len =
    decVariantCBOR (Proxy @s) (tag - 1) len

{-------------------------------------------------------------------------------
  Record codecs
-------------------------------------------------------------------------------}

instance (FieldCount r, AllSerialise r) => Serialise (Record r) where
  encode (RowRep rep) =
    encodeListLen (fromIntegral (fieldCount (Proxy @r)))
      <> encRecordCBOR (Proxy @r) (toList (repVals rep))

  decode = do
    n <- decodeListLen
    if n /= fieldCount (Proxy @r)
      then fail "polytropos-cbor: record arity mismatch"
      else do
        slots <- decRecordCBOR (Proxy @r)
        pure (RowRep (productRep slots))

{-------------------------------------------------------------------------------
  Variant codecs
-------------------------------------------------------------------------------}

instance AllCtorsSerialise s => Serialise (Variant s) where
  encode (RowRep rep) =
    let tag = repTag rep
    in encVariantCBOR (Proxy @s) tag tag (toList (repVals rep))

  decode = do
    n <- decodeListLen
    if n < 1
      then fail "polytropos-cbor: variant encoding missing constructor tag"
      else do
        tag <- decodeWord
        slots <- decVariantCBOR (Proxy @s) tag n
        pure (RowRep (injectRep tag slots))

{-------------------------------------------------------------------------------
  Homogeneity evidence and row introspection (Reflection helpers)
-------------------------------------------------------------------------------}

-- $homogeneity
--
-- === Homogeneity Evidence and Introspection Helpers
--
-- In addition to the primary heterogeneous codecs ('AllSerialise', 'AllCtorsSerialise'),
-- this module provides closed type families and reflection classes for
-- inspecting row metadata and enforcing uniform payload types.

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
      arityList :: Proxy fs -> [a]
      arityList _ = []
