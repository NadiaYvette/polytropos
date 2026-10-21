{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

{-|
Module      : Polytropos.Dhall
Description : High-performance Dhall codecs and generic adapters for Polytropos open records and variants
Copyright   : (c) 2026 The Polytropos Authors
License     : EUPL-1.2 OR Apache-2.0
Maintainer  : nadia.yvette.chambers@ik.me
Stability   : experimental
Portability : non-portable (GHC extensions)

Linear \(O(N)\) 'Dhall.FromDhall' and 'Dhall.ToDhall' codecs for heterogeneous open
'Record', 'Variant', and higher-kinded 'RecordF' types, alongside generic adapters
powered by "Dhall.Marshal.Decode.GenericFromDhall" and "Dhall.Marshal.Encode.GenericToDhall".

= Architectural Overview & Rationale

== Flat Memory Physics vs. GHC.Generics Binary Trees

Standard "GHC.Generics" deriving for Dhall walks a deeply nested binary tree of
@(:*:)@, @(:+:)@, @M1@, and @K1@ constructors. On larger configuration schemas
(20+ fields or constructors), this induces substantial compile-time overhead and
allocates intermediate representation nodes for every parsed field.

In contrast, @polytropos-dhall@ unrolls the flat contiguous
'Data.Primitive.SmallArray.SmallArray' payload directly into and out of Dhall's
abstract syntax tree ('Dhall.Syntax.Expr'):

* __Records__: An open 'Record' encodes into a native Dhall record literal
  @RecordLit { x = ..., y = ... }@ in exact row order, and decodes directly from
  the field map into flat memory with zero intermediate binary tree allocations.
* __Variants__: An open 'Variant' encodes into a native Dhall union literal
  @< Ctor : { ... } | ... >@ with \(O(1)\) constructor tag dispatch, avoiding
  linear cascading searches.
* __Higher-Kinded Data (HKD)__: 'RecordF' (such as @RecordF Maybe r@) integrates
  natively, with automatic 'Nothing' fallback semantics for omitted configuration fields.

== Generic Adapters for Nominal Schemas and Gachi Substrates

In addition to open rows, this package provides turnkey generic adapters
('GenericDhall', 'genericFromDhall', 'genericToDhall') leveraging Dhall's internal
'GenericFromDhall' and 'GenericToDhall' classes. Nominal Haskell records or
osteological structures (such as in @gachi@) can derive 'FromDhall' and 'ToDhall'
via 'GenericDhall' through @DerivingVia@:

> data ServerConfig = ServerConfig
>   { host :: Text
>   , port :: Natural
>   } deriving stock (Generic, Show, Eq)
>     deriving (FromDhall, ToDhall) via (GenericDhall ServerConfig)

= When to Use This Module

* When reading or writing configuration files, environment profiles, or service
  manifests modeled with @polytropos@ open records or variants.
* When deriving Dhall encoders and decoders for nominal records via 'GenericDhall'.
* When building extensible, multi-agent configuration pipelines (such as in
  @sarutahiko@ or @gachi@) requiring deterministic schemas.

= Worked Example

Open records are constructed using the @REC { ... }@ syntax enabled by the
@polytropos@ source plugin (via @-fplugin=Polytropos.Plugin@):

> {-# LANGUAGE DataKinds #-}
> {-# LANGUAGE OverloadedStrings #-}
> {-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}
>
> import Dhall (input, auto, embed, inject, Natural)
> import Data.Text (Text)
> import Polytropos
> import Polytropos.Dhall
>
> type AppConfig = Record '["host" ':= Text, "port" ':= Natural, "debug" ':= Bool]
>
> cfg :: AppConfig
> cfg = REC { host = "localhost", port = 8080, debug = True }
>
> -- Embed to Dhall expression:
> dhallExpr = embed inject cfg
>
> -- Decode from Dhall text:
> cfg' <- input auto "{ host = \"0.0.0.0\", port = 9000, debug = False }"
-}
module Polytropos.Dhall
  ( -- * High-Level Convenience API
    encodeDhall
  , injectDhall
  , decodeDhall
  , extractDhall

    -- * Heterogeneous Row Codecs
  , AllToDhall (..)
  , AllFromDhall (..)
  , AllCtorsToDhall (..)
  , AllCtorsFromDhall (..)
  , DhallFieldFallback (..)

    -- * Higher-Kinded Data Codecs
  , AllToDhallHKD (..)
  , AllFromDhallHKD (..)

    -- * Generic Adapters & DerivingVia
  , GenericDhall (..)
  , genericFromDhall
  , genericFromDhallWith
  , genericToDhall
  , genericToDhallWith
  , GenericFromDhall (..)
  , GenericFromDhallUnion (..)
  , GenericToDhall (..)

    -- * Homogeneity Evidence and Row Introspection
    -- $homogeneity
  , AllFieldsAre
  , AllCtorsHom (..)
  , FieldNames (..)
  , RowField
  , SumField
  ) where

import Data.Functor ((<&>))
import Data.Functor.Contravariant (contramap)
import Data.Functor.Identity (Identity (..))
import Data.Kind (Constraint, Type)
import Data.Primitive.SmallArray (smallArrayFromList)
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import qualified Data.Text as T
import Data.Void (Void)
import GHC.Exts (Any, toList)
import GHC.Generics (Generic)
import qualified GHC.Generics as GHC
import GHC.TypeLits (KnownSymbol, symbolVal)

import Dhall
  ( Decoder (..)
  , Encoder (..)
  , FromDhall (..)
  , InputNormalizer (..)
  , InterpretOptions (..)
  , ToDhall (..)
  , defaultInterpretOptions
  , genericAuto
  , genericAutoWithInputNormalizer
  , genericToDhall
  , genericToDhallWith
  , genericToDhallWithInputNormalizer
  )
import qualified Dhall
import qualified Dhall.Core as Core
import qualified Dhall.Map as Dhall.Map
import Dhall.Marshal.Decode
  ( Expector
  , Extractor
  , GenericFromDhall (..)
  , GenericFromDhallUnion (..)
  , extractError
  , typeError
  )
import Dhall.Marshal.Encode (GenericToDhall (..))
import Dhall.Core
  ( Expr (..)
  , FieldSelection (..)
  )
import Dhall.Src (Src (..))

import Polytropos (Record, RecordF, Variant)
import Polytropos.Core
  ( Pair (..)
  , ProductRow
  , Rep (..)
  , Row
  , RowRep (..)
  , SumRow
  , injectRep
  , noInlineUnsafeCo
  , productRep
  , repTag
  , repVals
  )

{-------------------------------------------------------------------------------
  High-Level Convenience API
-------------------------------------------------------------------------------}

-- | Encode any 'ToDhall' value directly into a formatted Dhall text string.
encodeDhall :: ToDhall a => a -> Text
encodeDhall = Core.pretty . injectDhall

-- | Embed any 'ToDhall' value into a Dhall abstract syntax tree ('Expr Src Void').
injectDhall :: ToDhall a => a -> Expr Src Void
injectDhall = Dhall.embed Dhall.inject

-- | Decode a Dhall text expression directly into a Haskell value.
decodeDhall :: FromDhall a => Text -> IO a
decodeDhall = Dhall.input Dhall.auto

-- | Extract a Haskell value from a parsed Dhall expression.
extractDhall :: FromDhall a => Expr Src Void -> Extractor Src Void a
extractDhall = extract Dhall.auto

{-------------------------------------------------------------------------------
  Field Fallback Handling
-------------------------------------------------------------------------------}

-- | Provides a default fallback value when a field is missing from a Dhall record literal.
--
-- By default, missing fields produce an extraction error ('extractError').
-- For 'Maybe' fields, missing fields gracefully evaluate to 'Nothing', aligning
-- with Dhall's native optional field conventions.
class DhallFieldFallback a where
  dhallMissingField :: Maybe (Extractor Src Void a)

instance {-# OVERLAPPABLE #-} DhallFieldFallback a where
  dhallMissingField = Nothing

instance DhallFieldFallback (Maybe a) where
  dhallMissingField = Just (pure Nothing)

{-------------------------------------------------------------------------------
  Heterogeneous Row Codecs
-------------------------------------------------------------------------------}

-- | Evidence that every field of the row @r@ has a 'ToDhall' instance
-- at that field's own concrete type. Unrolls payload slots in row order.
class AllToDhall (r :: Row) where
  declaredRecordFields :: InputNormalizer -> Proxy r -> [(Text, Core.RecordField Src Void)]
  encRecordFields :: InputNormalizer -> Proxy r -> [Identity Any] -> [(Text, Core.RecordField Src Void)]

instance AllToDhall '[] where
  declaredRecordFields _ _ = []
  encRecordFields _ _ _ = []

instance (KnownSymbol n, ToDhall a, AllToDhall r) => AllToDhall ((n ':= a) ': r) where
  declaredRecordFields norm _ =
    let key = T.pack (symbolVal (Proxy @n))
        Encoder _ declA = injectWith norm :: Encoder a
    in (key, Core.makeRecordField declA) : declaredRecordFields norm (Proxy @r)

  encRecordFields norm _ (Identity x : xs) =
    let key = T.pack (symbolVal (Proxy @n))
        Encoder embedA _ = injectWith norm :: Encoder a
    in (key, Core.makeRecordField (embedA (noInlineUnsafeCo x :: a)))
       : encRecordFields norm (Proxy @r) xs
  encRecordFields _ _ [] = error "polytropos-dhall: payload arity mismatch"

-- | Evidence that every field of the row @r@ has a 'FromDhall' instance
-- at that field's own concrete type. Decodes each field by name from the Dhall record.
class AllFromDhall (r :: Row) where
  expectedRecordFields :: InputNormalizer -> Proxy r -> Expector [(Text, Core.RecordField Src Void)]
  decRecordFields :: InputNormalizer -> Proxy r -> Dhall.Map.Map Text (Core.RecordField Src Void) -> Extractor Src Void [Identity Any]

instance AllFromDhall '[] where
  expectedRecordFields _ _ = pure []
  decRecordFields _ _ _ = pure []

instance (KnownSymbol n, FromDhall a, DhallFieldFallback a, AllFromDhall r) => AllFromDhall ((n ':= a) ': r) where
  expectedRecordFields norm _ =
    let key = T.pack (symbolVal (Proxy @n))
        Decoder _ expectedA = autoWith norm :: Decoder a
        expectedRest = expectedRecordFields norm (Proxy @r)
    in liftA2 (\tyA rest -> (key, Core.makeRecordField tyA) : rest) expectedA expectedRest

  decRecordFields norm _ kvs =
    let key = T.pack (symbolVal (Proxy @n))
        Decoder extractA _ = autoWith norm :: Decoder a
        valA = case Dhall.Map.lookup key kvs of
                 Just rf -> extractA (Core.recordFieldValue rf)
                 Nothing -> case dhallMissingField @a of
                              Just fallback -> fallback
                              Nothing -> extractError ("Record is missing required field: " <> key)
        valRest = decRecordFields norm (Proxy @r) kvs
    in liftA2 (\x xs -> Identity (noInlineUnsafeCo x :: Any) : xs) valA valRest

-- | Helper class for permissive extraction of single-field variant payloads.
class DecSingleField (fs :: Row) where
  decRecordFieldsSingle :: InputNormalizer -> Proxy fs -> Expr Src Void -> Maybe (Extractor Src Void [Identity Any])

instance {-# OVERLAPPABLE #-} DecSingleField fs where
  decRecordFieldsSingle _ _ _ = Nothing

instance (KnownSymbol n, FromDhall a) => DecSingleField '[(n ':= a)] where
  decRecordFieldsSingle norm _ expr =
    let Decoder extractA _ = autoWith norm :: Decoder a
    in Just ((\x -> [Identity (noInlineUnsafeCo x :: Any)]) <$> extractA expr)

-- | Evidence that every constructor of the sum row @s@ has a heterogeneous
-- field row satisfying 'AllToDhall', paired with its constructor tag index.
class AllCtorsToDhall (s :: SumRow) where
  declaredUnionAlts :: InputNormalizer -> Proxy s -> [(Text, Maybe (Expr Src Void))]
  encVariantTag :: InputNormalizer -> Dhall.Map.Map Text (Maybe (Expr Src Void)) -> Proxy s -> Word -> [Identity Any] -> Expr Src Void

instance AllCtorsToDhall '[] where
  declaredUnionAlts _ _ = []
  encVariantTag _ _ _ _ _ = error "polytropos-dhall: empty variant has no constructors"

instance (KnownSymbol c, AllToDhall fs, AllCtorsToDhall s)
      => AllCtorsToDhall ((c ':= fs) ': s) where
  declaredUnionAlts norm _ =
    let cName = T.pack (symbolVal (Proxy @c))
        fsDecls = declaredRecordFields norm (Proxy @fs)
        altType = case fsDecls of
                    [] -> Nothing
                    _  -> Just (Record (Dhall.Map.fromList fsDecls))
    in (cName, altType) : declaredUnionAlts norm (Proxy @s)

  encVariantTag norm fullUnion _ 0 slots =
    let cName = T.pack (symbolVal (Proxy @c))
        fieldSel = Core.makeFieldSelection cName
        fsFields = encRecordFields norm (Proxy @fs) slots
    in case fsFields of
         [] -> Field (Union fullUnion) fieldSel
         _  -> App (Field (Union fullUnion) fieldSel) (RecordLit (Dhall.Map.fromList fsFields))

  encVariantTag norm fullUnion _ tag slots =
    encVariantTag norm fullUnion (Proxy @s) (tag - 1) slots

-- | Evidence that every constructor of the sum row @s@ has a heterogeneous
-- field row satisfying 'AllFromDhall', paired with its constructor tag index.
class AllCtorsFromDhall (s :: SumRow) where
  expectedUnionAlts :: InputNormalizer -> Proxy s -> Expector [(Text, Maybe (Expr Src Void))]
  decVariantVal :: InputNormalizer -> Proxy s -> Word -> Text -> Expr Src Void -> Extractor Src Void (Word, [Identity Any])

instance AllCtorsFromDhall '[] where
  expectedUnionAlts _ _ = pure []
  decVariantVal _ _ _ cName _ = extractError ("Unknown variant constructor: " <> cName)

instance (KnownSymbol c, AllFromDhall fs, DecSingleField fs, AllCtorsFromDhall s)
      => AllCtorsFromDhall ((c ':= fs) ': s) where
  expectedUnionAlts norm _ =
    let cName = T.pack (symbolVal (Proxy @c))
        fsExpected = expectedRecordFields norm (Proxy @fs)
        altType = fsExpected <&> \case
                    [] -> Nothing
                    fields -> Just (Record (Dhall.Map.fromList fields))
        restAlts = expectedUnionAlts norm (Proxy @s)
    in liftA2 (\alt rest -> (cName, alt) : rest) altType restAlts

  decVariantVal norm _ idx cKey val
    | cKey == T.pack (symbolVal (Proxy @c)) = case val of
        RecordLit kvs ->
          (\slots -> (idx, slots)) <$> decRecordFields norm (Proxy @fs) kvs
        _ -> case decRecordFieldsSingle norm (Proxy @fs) val of
               Just slotsExtractor ->
                 (\slots -> (idx, slots)) <$> slotsExtractor
               Nothing -> extractError ("Expected a record literal of fields for constructor: " <> cKey)
    | otherwise =
        decVariantVal norm (Proxy @s) (idx + 1) cKey val

{-------------------------------------------------------------------------------
  Record Codecs
-------------------------------------------------------------------------------}

instance AllToDhall r => ToDhall (Record r) where
  injectWith norm = Encoder
    { embed = \(RowRep rep) ->
        RecordLit (Dhall.Map.fromList (encRecordFields norm (Proxy @r) (toList (repVals rep))))
    , declared = Record (Dhall.Map.fromList (declaredRecordFields norm (Proxy @r)))
    }

instance AllFromDhall r => FromDhall (Record r) where
  autoWith norm =
    let expectedFields = expectedRecordFields norm (Proxy @r)
        expectedRec = Record . Dhall.Map.fromList <$> expectedFields
    in Decoder
      { extract = \expr -> case expr of
          RecordLit kvs -> RowRep . productRep <$> decRecordFields norm (Proxy @r) kvs
          _             -> typeError expectedRec expr
      , expected = expectedRec
      }

{-------------------------------------------------------------------------------
  Variant Codecs
-------------------------------------------------------------------------------}

-- | Deconstruct an AST node into its constructor name and payload expression.
extractUnionTag :: Expr s a -> Maybe (Text, Expr s a)
extractUnionTag = \case
  App (Field _ (FieldSelection _ fld _)) e -> Just (fld, e)
  Field _ (FieldSelection _ fld _)        -> Just (fld, RecordLit mempty)
  _                                       -> Nothing

instance AllCtorsToDhall s => ToDhall (Variant s) where
  injectWith norm =
    let alts = Dhall.Map.fromList (declaredUnionAlts norm (Proxy @s))
    in Encoder
      { embed = \(RowRep rep) ->
          encVariantTag norm alts (Proxy @s) (repTag rep) (toList (repVals rep))
      , declared = Union alts
      }

instance AllCtorsFromDhall s => FromDhall (Variant s) where
  autoWith norm =
    let expectedU = Union . Dhall.Map.fromList <$> expectedUnionAlts norm (Proxy @s)
    in Decoder
      { extract = \expr -> case extractUnionTag expr of
          Just (cKey, val) ->
            (\(idx, slots) -> RowRep (injectRep (fromIntegral idx) slots))
              <$> decVariantVal norm (Proxy @s) 0 cKey val
          Nothing -> typeError expectedU expr
      , expected = expectedU
      }

{-------------------------------------------------------------------------------
  Higher-Kinded Data Codecs (RecordF f r)
-------------------------------------------------------------------------------}

-- | Evidence that every field of an HKD row @r@ has a 'ToDhall' instance
-- for the functor-wrapped payload @f a@.
class AllToDhallHKD (f :: Type -> Type) (r :: ProductRow f) where
  declaredRecordFieldsHKD :: InputNormalizer -> Proxy f -> Proxy r -> [(Text, Core.RecordField Src Void)]
  encRecordFieldsHKD :: InputNormalizer -> Proxy f -> Proxy r -> [f Any] -> [(Text, Core.RecordField Src Void)]

instance AllToDhallHKD f '[] where
  declaredRecordFieldsHKD _ _ _ = []
  encRecordFieldsHKD _ _ _ _ = []

instance (KnownSymbol n, ToDhall (f a), AllToDhallHKD f r)
      => AllToDhallHKD f ((n ':= f a) ': r) where
  declaredRecordFieldsHKD norm pf _ =
    let key = T.pack (symbolVal (Proxy @n))
        Encoder _ declA = injectWith norm :: Encoder (f a)
    in (key, Core.makeRecordField declA) : declaredRecordFieldsHKD norm pf (Proxy @r)

  encRecordFieldsHKD norm pf _ (x : xs) =
    let key = T.pack (symbolVal (Proxy @n))
        Encoder embedA _ = injectWith norm :: Encoder (f a)
    in (key, Core.makeRecordField (embedA (noInlineUnsafeCo x :: f a)))
       : encRecordFieldsHKD norm pf (Proxy @r) xs
  encRecordFieldsHKD _ _ _ [] = error "polytropos-dhall: HKD payload arity mismatch"

-- | Evidence that every field of an HKD row @r@ has a 'FromDhall' instance
-- for the functor-wrapped payload @f a@.
class AllFromDhallHKD (f :: Type -> Type) (r :: ProductRow f) where
  expectedRecordFieldsHKD :: InputNormalizer -> Proxy f -> Proxy r -> Expector [(Text, Core.RecordField Src Void)]
  decRecordFieldsHKD :: InputNormalizer -> Proxy f -> Proxy r -> Dhall.Map.Map Text (Core.RecordField Src Void) -> Extractor Src Void [f Any]

instance AllFromDhallHKD f '[] where
  expectedRecordFieldsHKD _ _ _ = pure []
  decRecordFieldsHKD _ _ _ _ = pure []

instance (KnownSymbol n, FromDhall (f a), DhallFieldFallback (f a), AllFromDhallHKD f r)
      => AllFromDhallHKD f ((n ':= f a) ': r) where
  expectedRecordFieldsHKD norm pf _ =
    let key = T.pack (symbolVal (Proxy @n))
        Decoder _ expectedA = autoWith norm :: Decoder (f a)
        expectedRest = expectedRecordFieldsHKD norm pf (Proxy @r)
    in liftA2 (\tyA rest -> (key, Core.makeRecordField tyA) : rest) expectedA expectedRest

  decRecordFieldsHKD norm pf _ kvs =
    let key = T.pack (symbolVal (Proxy @n))
        Decoder extractA _ = autoWith norm :: Decoder (f a)
        valA = case Dhall.Map.lookup key kvs of
                 Just rf -> extractA (Core.recordFieldValue rf)
                 Nothing -> case dhallMissingField @(f a) of
                              Just fallback -> fallback
                              Nothing -> extractError ("Record is missing required field: " <> key)
        valRest = decRecordFieldsHKD norm pf (Proxy @r) kvs
    in liftA2 (\x xs -> (noInlineUnsafeCo x :: f Any) : xs) valA valRest

instance AllToDhallHKD f r => ToDhall (RecordF f r) where
  injectWith norm = Encoder
    { embed = \(RowRep rep) ->
        RecordLit (Dhall.Map.fromList (encRecordFieldsHKD norm (Proxy @f) (Proxy @r) (toList (repVals rep))))
    , declared = Record (Dhall.Map.fromList (declaredRecordFieldsHKD norm (Proxy @f) (Proxy @r)))
    }

instance AllFromDhallHKD f r => FromDhall (RecordF f r) where
  autoWith norm =
    let expectedFields = expectedRecordFieldsHKD norm (Proxy @f) (Proxy @r)
        expectedRec = Record . Dhall.Map.fromList <$> expectedFields
    in Decoder
      { extract = \expr -> case expr of
          RecordLit kvs -> RowRep . Rep 0 . smallArrayFromList <$> decRecordFieldsHKD norm (Proxy @f) (Proxy @r) kvs
          _             -> typeError expectedRec expr
      , expected = expectedRec
      }

{-------------------------------------------------------------------------------
  Generic Adapters & DerivingVia
-------------------------------------------------------------------------------}

-- | Newtype wrapper providing generic 'FromDhall' and 'ToDhall' instances
-- for any data type with a 'Generic' instance, via 'GenericFromDhall'
-- and 'GenericToDhall'.
--
-- Usage with @DerivingVia@:
--
-- > data Config = Config
-- >   { host :: Text
-- >   , port :: Natural
-- >   } deriving stock (Generic, Show, Eq)
-- >     deriving (FromDhall, ToDhall) via (GenericDhall Config)
newtype GenericDhall a = GenericDhall { unGenericDhall :: a }

instance (Generic a, GenericFromDhall a (GHC.Rep a)) => FromDhall (GenericDhall a) where
  autoWith norm = fmap GenericDhall (genericAutoWithInputNormalizer defaultInterpretOptions norm)

instance (Generic a, GenericToDhall (GHC.Rep a)) => ToDhall (GenericDhall a) where
  injectWith norm = contramap unGenericDhall (genericToDhallWithInputNormalizer defaultInterpretOptions norm)

-- | Construct a 'Decoder' for any 'Generic' data type using Dhall's generic adapter
-- 'GenericFromDhall'.
genericFromDhall :: forall a. (Generic a, GenericFromDhall a (GHC.Rep a)) => Decoder a
genericFromDhall = genericAuto

-- | Construct a 'Decoder' for any 'Generic' data type using custom 'InterpretOptions'
-- and 'InputNormalizer'.
genericFromDhallWith
  :: forall a. (Generic a, GenericFromDhall a (GHC.Rep a))
  => InterpretOptions
  -> InputNormalizer
  -> Decoder a
genericFromDhallWith = genericAutoWithInputNormalizer


{-------------------------------------------------------------------------------
  Homogeneity evidence and row introspection (Reflection helpers)
-------------------------------------------------------------------------------}

-- $homogeneity
--
-- === Homogeneity Evidence and Introspection Helpers
--
-- In addition to the primary heterogeneous codecs ('AllToDhall', 'AllFromDhall'),
-- this module provides closed type families and reflection classes for
-- inspecting row metadata and enforcing uniform payload types.
--
-- 1. 'AllFieldsAre' is a closed type family asserting that /every/ field in a row
--    has the uniform type @a@.
-- 2. 'RowField' and 'SumField' compute the uniform payload type directly from
--    the row or sum row, eliminating type ambiguity for custom instances.
-- 3. 'FieldNames' reifies type-level 'GHC.TypeLits.Symbol' field labels into
--    runtime @['String']@ keys in exact row order.
-- 4. 'AllCtorsHom' reifies the constructor topology of a homogeneous sum row into
--    @[(String, [String])]@ (mapping each constructor name to its list of field names).

-- | Evidence that every field of the row @r@ has type @a@.
type family AllFieldsAre (a :: Type) (r :: Row) :: Constraint where
  AllFieldsAre _  '[]                = ()
  AllFieldsAre a ((n ':= a) ': rest) = AllFieldsAre a rest

-- | Extracts the uniform field type of a homogeneous row: the type of /every/
-- field, or 'Void' for the empty row @'[]@.
type family RowField (r :: Row) :: Type where
  RowField '[]                 = Void
  RowField ((n ':= a) ': rest) = a

-- | Extracts the uniform field type shared by every constructor of a homogeneous
-- sum row, or 'Void' for the empty sum @'[]@.
type family SumField (s :: SumRow) :: Type where
  SumField '[]                = Void
  SumField ((c ':= fs) ': s)  = RowField fs

-- | The field names of a row, in exact row order, reified from type-level
-- 'GHC.TypeLits.Symbol' labels into runtime @['String']@ keys.
class FieldNames (r :: Row) where
  fieldNames :: Proxy r -> [String]

instance FieldNames '[] where
  fieldNames _ = []

instance (KnownSymbol n, FieldNames r) => FieldNames ((n ':= a) ': r) where
  fieldNames _ = symbolVal (Proxy @n) : fieldNames (Proxy @r)

-- | Reflection dictionary for homogeneous sum rows (variants).
--
-- Reifies the full constructor topology into a runtime list pairing each
-- constructor symbol with its ordered field symbols: @[(String, [String])]@.
class AllCtorsHom (a :: Type) (s :: SumRow) where
  ctorSpecs :: Proxy a -> Proxy s -> [(String, [String])]

instance AllCtorsHom a '[] where
  ctorSpecs _ _ = []

instance (KnownSymbol c, FieldNames fs, AllFieldsAre a fs, AllCtorsHom a s)
      => AllCtorsHom a ((c ':= fs) ': s) where
  ctorSpecs pa _ =
    (symbolVal (Proxy @c), fieldNames (Proxy @fs)) : ctorSpecs pa (Proxy @s)
