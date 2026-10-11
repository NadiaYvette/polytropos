{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- |
-- Module      : Polytropos.Aeson
-- Description : aeson JSON codecs for polytropos open records and variants
-- Copyright   : (c) 2026 The Polytropos Authors
-- License     : BSD-3-Clause
--
-- Linear @O(N)@ 'A.ToJSON' and 'A.FromJSON' instances for 'Record' and t'Variant'
-- without standard GHC.Generics compile slowdowns: the codecs unroll the
-- flat t'Polytropos.Core.Rep' payload directly into a JSON object and back,
-- with no generic-representation tree anywhere.
--
-- = Encoding
--
-- A record encodes as a JSON object with one member per field, in row order;
-- a variant encodes as a single-member object @{"ctor": fields}@, where the
-- member name is the active constructor and the value is an object of that
-- constructor's fields (empty object for a nullary constructor). The decoder
-- is strict: it requires exactly the row's member count for records, and
-- exactly one member naming a constructor of the row for variants.
--
-- All fields must share one type for now ('AllFieldsAre' / 'AllCtorsHom');
-- the codecs walk the payload slots in lockstep with the reified field
-- names, coercing each erased slot to that type exactly as the row evidence
-- guarantees. The field type itself is pinned to the row by 'RowField' and
-- 'SumField', so the instances never leave a metavariable ambiguous.
module Polytropos.Aeson
  ( -- * Homogeneity evidence and row introspection
    AllFieldsAre
  , AllCtorsHom (..)
  , FieldNames (..)
  , RowField
  , SumField
  ) where

import Control.Monad         (forM)
import Data.Functor.Identity (Identity (..))
import Data.Kind             (Constraint, Type)
import Data.Proxy            (Proxy (..))
import Data.Void             (Void)
import qualified Data.Text as T
import GHC.Exts              (Any, toList)
import GHC.TypeLits          (KnownSymbol, symbolVal)
import qualified Data.Aeson        as A
import qualified Data.Aeson.Types  as AT
import qualified Data.Aeson.Key    as K
import qualified Data.Aeson.KeyMap as KM
import Polytropos            (Record, Variant)
import Polytropos.Core       (Pair (..), Row, SumRow, RowRep (..), noInlineUnsafeCo,
                              productRep, injectRep, repTag, repVals)

{-------------------------------------------------------------------------------
  Homogeneity evidence and row introspection
-------------------------------------------------------------------------------}

-- | Evidence that every field of the row @r@ has type @a@.
--
-- Closed type family, so a heterogeneous row fails to reduce and the
-- dependent instances simply do not apply.
type family AllFieldsAre (a :: Type) (r :: Row) :: Constraint where
  AllFieldsAre _  '[]                = ()
  AllFieldsAre a ((n ':= a) ': rest) = AllFieldsAre a rest

-- | The field type of a row: the type of /every/ field for a homogeneous
-- row, 'Void' for the empty row.
type family RowField (r :: Row) :: Type where
  RowField '[]                 = Void
  RowField ((n ':= a) ': rest) = a

-- | The field type shared by every constructor of a sum row, 'Void' for the
-- empty sum.
type family SumField (s :: SumRow) :: Type where
  SumField '[]                = Void
  SumField ((c ':= fs) ': s)  = RowField fs

-- | The field names of a row, in row order, reified from the type level.
class FieldNames (r :: Row) where
  fieldNames :: Proxy r -> [String]

instance FieldNames '[] where
  fieldNames _ = []

instance (KnownSymbol n, FieldNames r) => FieldNames ((n ':= a) ': r) where
  fieldNames _ = symbolVal (Proxy @n) : fieldNames (Proxy @r)

-- | Every constructor of the sum row @s@ has a homogeneous field row of type
-- @a@, reified as constructor names paired with their field names.
--
-- @a@ appears in the method so the dictionary is never ambiguous at a use
-- site (it is otherwise a phantom of the class).
class AllCtorsHom (a :: Type) (s :: SumRow) where
  ctorSpecs :: Proxy a -> Proxy s -> [(String, [String])]

instance AllCtorsHom a '[] where
  ctorSpecs _ _ = []

instance ( KnownSymbol c, FieldNames fs, AllFieldsAre a fs, AllCtorsHom a s )
      => AllCtorsHom a ((c ':= fs) ': s) where
  ctorSpecs pa _ =
    (symbolVal (Proxy @c), fieldNames (Proxy @fs)) : ctorSpecs pa (Proxy @s)

{-------------------------------------------------------------------------------
  Record codecs
-------------------------------------------------------------------------------}

recordObject :: forall a r. (a ~ RowField r, AllFieldsAre a r, FieldNames r, A.ToJSON a)
             => Record r -> KM.KeyMap A.Value
recordObject (RowRep rep) = KM.fromList
  [ (K.fromText (T.pack k), A.toJSON (noInlineUnsafeCo (runIdentity v) :: a))
  | (k, v) <- zip (fieldNames (Proxy @r)) (toList (repVals rep)) ]

parseRecord :: forall a r. (a ~ RowField r, AllFieldsAre a r, FieldNames r, A.FromJSON a)
            => A.Object -> AT.Parser (Record r)
parseRecord obj
  | KM.size obj /= length ks = fail "polytropos-aeson: field count mismatch"
  | otherwise = do
      vs <- forM ks $ \k -> obj A..: K.fromText (T.pack k)
      pure (RowRep (productRep (map (Identity . noInlineUnsafeCo) (vs :: [a]))))
  where
    ks = fieldNames (Proxy @r)

instance {-# OVERLAPPABLE #-} ( a ~ RowField r
                              , AllFieldsAre a r
                              , FieldNames r
                              , A.ToJSON a
                              )
      => A.ToJSON (Record r) where
  toJSON rec = A.Object (recordObject rec)
  toJSONList xs = AT.listValue (A.Object . recordObject) xs
  toEncoding rec = A.toEncoding (A.Object (recordObject rec))
  toEncodingList xs = AT.listEncoding (A.toEncoding . A.Object . recordObject) xs
  omitField _ = False

instance {-# OVERLAPPABLE #-} ( a ~ RowField r
                              , AllFieldsAre a r
                              , FieldNames r
                              , A.FromJSON a
                              )
      => A.FromJSON (Record r) where
  parseJSON = A.withObject "Record" parseRecord
  parseJSONList v = case v of
    AT.Array vals -> traverse step (toList vals)
      where step = A.withObject "Record" (\o -> parseRecord o :: AT.Parser (Record r))
    _             -> fail "polytropos-aeson: expected an array of records"
  omittedField = Nothing

{-------------------------------------------------------------------------------
  Variant codecs
-------------------------------------------------------------------------------}

-- | Encode the active constructor: a single-member object whose key is the
-- constructor name and whose value is that constructor's field object.
variantValue :: forall a s. (a ~ SumField s, AllCtorsHom a s, A.ToJSON a)
             => Variant s -> A.Value
variantValue (RowRep rep) =
  case drop (fromIntegral (repTag rep)) (ctorSpecs (Proxy @a) (Proxy @s)) of
    (nm, ks) : _ ->
      A.Object (KM.fromList [(K.fromText (T.pack nm),
                              A.Object (fieldsObject @a ks (toList (repVals rep))))])
    [] -> error "polytropos-aeson: constructor tag out of range"

fieldsObject :: forall a. A.ToJSON a => [String] -> [Identity Any] -> KM.KeyMap A.Value
fieldsObject ks vs = KM.fromList
  [ (K.fromText (T.pack k), A.toJSON (noInlineUnsafeCo (runIdentity v) :: a))
  | (k, v) <- zip ks vs ]

parseVariant :: forall a s. (a ~ SumField s, AllCtorsHom a s, A.FromJSON a)
             => A.Object -> AT.Parser (Variant s)
parseVariant obj = case KM.toList obj of
  [(k, v)] -> go (K.toText k) (zip [0 :: Int ..] specs) v
  _        -> fail "polytropos-aeson: expected a single-member object"
  where
    specs :: [(String, [String])]
    specs = ctorSpecs (Proxy @a) (Proxy @s)

    go nm ((i, (nm', ks)) : rest) v
      | nm == T.pack nm' = do
          vs <- parseFields ks v
          pure (RowRep (injectRep (fromIntegral i)
                                  (map (Identity . noInlineUnsafeCo) (vs :: [a]))))
      | otherwise = go nm rest v
    go _ [] _ = fail "polytropos-aeson: unknown constructor"

    parseFields ks v = case v of
      A.Object o -> forM ks $ \fn -> o A..: K.fromText (T.pack fn)
      _          -> fail "polytropos-aeson: expected an object of constructor fields"

instance {-# OVERLAPPABLE #-} ( a ~ SumField s
                              , AllCtorsHom a s
                              , A.ToJSON a
                              )
      => A.ToJSON (Variant s) where
  toJSON v = variantValue v
  toJSONList xs = AT.listValue variantValue xs
  toEncoding v = A.toEncoding (variantValue v)
  toEncodingList xs = AT.listEncoding (A.toEncoding . variantValue) xs
  omitField _ = False

instance {-# OVERLAPPABLE #-} ( a ~ SumField s
                              , AllCtorsHom a s
                              , A.FromJSON a
                              )
      => A.FromJSON (Variant s) where
  parseJSON = A.withObject "Variant" parseVariant
  parseJSONList v = case v of
    AT.Array vals -> traverse step (toList vals)
      where step = A.withObject "Variant" (\o -> parseVariant o :: AT.Parser (Variant s))
    _             -> fail "polytropos-aeson: expected an array of variants"
  omittedField = Nothing
