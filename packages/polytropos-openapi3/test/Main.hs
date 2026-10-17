{-# LANGUAGE DataKinds #-}
{-# OPTIONS_GHC -Wno-orphans #-}
module Main (main) where

import Test.Tasty
import Test.Tasty.HUnit
import Data.Aeson (decode, encode)
import qualified Data.HashMap.Strict.InsOrd.Compat as IOHM
import Data.OpenApi
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import qualified Data.Text as T
import Polytropos
import Polytropos.OpenApi ()

type MyRec = Record '["x" ':= Int, "flag" ':= Bool, "msg" ':= String]
type MyVar = Variant '["A" ':= '["foo" ':= Int], "B" ':= '["bar" ':= Bool]]

main :: IO ()
main = defaultMain $ testGroup "OpenAPI3 Integration"
  [ testGroup "Record schemas"
      [ testCase "object schema with properties in row order" $ do
          let s = toSchema (Proxy :: Proxy MyRec)
          _schemaType s @?= Just OpenApiObject
          IOHM.keys (_schemaProperties s) @?= (map T.pack ["x", "flag", "msg"])
      , testCase "all fields required" $
          _schemaRequired (toSchema (Proxy :: Proxy MyRec))
            @?= (map T.pack ["x", "flag", "msg"] :: [Text])
      , testCase "field schemas reference primitive types" $ do
          let s = toSchema (Proxy :: Proxy MyRec)
              props = _schemaProperties s
              xSchema = case IOHM.lookup (T.pack "x") props of
                Just (Inline xs) -> xs
                other            -> error ("expected inline schema for x: " ++ show other)
          _schemaType xSchema @?= Just OpenApiInteger
      , testCase "generates valid JSON schema objects" $ do
          let s = toSchema (Proxy :: Proxy MyRec)
          (decode (encode s) :: Maybe Schema) @?= Just s
      ]
  , testGroup "Variant schemas"
      [ testCase "oneOf with one entry per constructor" $ do
          let s = toSchema (Proxy :: Proxy MyVar)
          case _schemaOneOf s of
            Just [Inline a, Inline b] -> do
              IOHM.keys (_schemaProperties a) @?= [T.pack "A"]
              IOHM.keys (_schemaProperties b) @?= [T.pack "B"]
            other -> assertFailure ("expected two oneOf entries, got: " ++ show other)
      , testCase "tagged constructor requires the tag" $ do
          let s = toSchema (Proxy :: Proxy MyVar)
          case _schemaOneOf s of
            Just [Inline a, Inline b] -> do
              _schemaRequired a @?= [T.pack "A"]
              _schemaRequired b @?= [T.pack "B"]
            other -> assertFailure ("expected two oneOf entries, got: " ++ show other)
      , testCase "generates valid JSON schema objects" $ do
          let s = toSchema (Proxy :: Proxy MyVar)
          (decode (encode s) :: Maybe Schema) @?= Just s
      ]
  ]
