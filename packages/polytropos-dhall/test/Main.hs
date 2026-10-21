{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Main (main) where

import Test.Tasty
import Test.Tasty.HUnit
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)
import Dhall (FromDhall, ToDhall, Natural, auto, inject, input, embed, extract)
import qualified Dhall.Core as Core
import qualified Dhall.Map as Map

import Data.Either.Validation (Validation (..))
import Polytropos
import Polytropos.Dhall

{-------------------------------------------------------------------------------
  Record schemas
-------------------------------------------------------------------------------}

type MyRec = Record '["x" ':= Natural, "y" ':= Natural, "z" ':= Natural]
myRec :: MyRec
myRec = REC { x = 1, y = 2, z = 3 }

type HeteroRow = '["host" ':= Text, "port" ':= Natural, "active" ':= Bool, "weight" ':= Double]
type HeteroRec = Record HeteroRow
heteroRec :: HeteroRec
heteroRec = REC { host = "localhost", port = 8080, active = True, weight = 1.75 }

type OptionalRec = Record '["name" ':= Text, "timeout" ':= Maybe Natural]

type AppConfigF = RecordF Maybe '["api" ':= Maybe Text, "workers" ':= Maybe Natural]

type RowOf20 =
  '[ "f00" ':= Natural, "f01" ':= Natural, "f02" ':= Natural, "f03" ':= Natural, "f04" ':= Natural
   , "f05" ':= Natural, "f06" ':= Natural, "f07" ':= Natural, "f08" ':= Natural, "f09" ':= Natural
   , "f10" ':= Natural, "f11" ':= Natural, "f12" ':= Natural, "f13" ':= Natural, "f14" ':= Natural
   , "f15" ':= Natural, "f16" ':= Natural, "f17" ':= Natural, "f18" ':= Natural, "f19" ':= Natural
   ]

buildBig :: Natural -> Record RowOf20
buildBig n =
  insertField (Field @"f00") n
  $ insertField (Field @"f01") n
  $ insertField (Field @"f02") n
  $ insertField (Field @"f03") n
  $ insertField (Field @"f04") n
  $ insertField (Field @"f05") n
  $ insertField (Field @"f06") n
  $ insertField (Field @"f07") n
  $ insertField (Field @"f08") n
  $ insertField (Field @"f09") n
  $ insertField (Field @"f10") n
  $ insertField (Field @"f11") n
  $ insertField (Field @"f12") n
  $ insertField (Field @"f13") n
  $ insertField (Field @"f14") n
  $ insertField (Field @"f15") n
  $ insertField (Field @"f16") n
  $ insertField (Field @"f17") n
  $ insertField (Field @"f18") n
  $ insertField (Field @"f19") n
  $ emptyRecord

{-------------------------------------------------------------------------------
  Variant schemas
-------------------------------------------------------------------------------}

type MyVar = Variant '["A" ':= '["foo" ':= Natural], "B" ':= '["bar" ':= Natural]]
varA :: MyVar
varA = Variant (Field @"A") (REC { foo = 42 :: Natural })

varB :: MyVar
varB = Variant (Field @"B") (REC { bar = 7 :: Natural })

type HeteroVar = Variant '["Msg" ':= '["text" ':= Text, "priority" ':= Natural], "Ping" ':= '[]]
heteroVar1 :: HeteroVar
heteroVar1 = Variant (Field @"Msg") (REC { text = "alert", priority = 1 })

heteroVar2 :: HeteroVar
heteroVar2 = Variant (Field @"Ping") emptyRecord

type ShapeRow = '["Circle" ':= '["radius" ':= Double], "Rect" ':= '["w" ':= Double, "h" ':= Double]]
type ShapeVar = Variant ShapeRow

{-------------------------------------------------------------------------------
  Nominal types for Generic adapters
-------------------------------------------------------------------------------}

data ServerConfig = ServerConfig
  { srvHost :: Text
  , srvPort :: Natural
  , srvTls  :: Bool
  } deriving stock (Generic, Show, Eq)
    deriving (FromDhall, ToDhall) via (GenericDhall ServerConfig)

{-------------------------------------------------------------------------------
  Tests
-------------------------------------------------------------------------------}

main :: IO ()
main = defaultMain $ testGroup "Dhall Integration"
  [ testGroup "Record Codecs"
      [ testCase "Roundtrip 3 fields" $ do
          let rendered = Core.pretty (embed inject myRec)
          rec' <- input auto rendered
          rec' @?= myRec
      , testCase "Roundtrip empty record" $ do
          let emptyR = emptyRecord :: Record '[]
              rendered = Core.pretty (embed inject emptyR)
          rec' <- input auto rendered
          rec' @?= emptyR
      , testCase "Roundtrip heterogeneous 4 fields" $ do
          let rendered = Core.pretty (embed inject heteroRec)
          rec' <- input auto rendered
          rec' @?= heteroRec
      , testCase "Roundtrip 20 fields" $ do
          let big = buildBig 42
              rendered = Core.pretty (embed inject big)
          rec' <- input auto rendered
          rec' @?= big
      , testCase "Decode from literal Dhall text" $ do
          let dhallSrc = "{ host = \"prod.cluster\", port = 443, active = True, weight = 2.5 }"
          rec' <- input auto dhallSrc
          rec' @?= (REC { host = "prod.cluster", port = 443, active = True, weight = 2.5 } :: HeteroRec)
      , testCase "Optional field present vs omitted fallback" $ do
          let withTimeout = "{ name = \"service-a\", timeout = Some 3000 }"
              withoutTimeout = "{ name = \"service-b\", timeout = None Natural }"
          r1 <- input auto withTimeout
          r2 <- input auto withoutTimeout
          r1 @?= (REC { name = "service-a", timeout = Just (3000 :: Natural) } :: OptionalRec)
          r2 @?= (REC { name = "service-b", timeout = Nothing } :: OptionalRec)

          -- Test AST extraction with field omitted entirely (DhallFieldFallback):
          let omittedFieldExpr = Core.RecordLit (Map.singleton "name" (Core.makeRecordField (Core.TextLit "service-b")))
          case extract auto omittedFieldExpr of
            Success r3 -> r3 @?= (REC { name = "service-b", timeout = Nothing } :: OptionalRec)
            Failure err -> assertFailure (show err)
      , testCase "encodeDhall row order" $ do
          let rendered = encodeDhall myRec
          T.strip rendered @?= "{ x = 1, y = 2, z = 3 }"
      ]
  , testGroup "Variant Codecs"
      [ testCase "Roundtrip A" $ do
          let rendered = Core.pretty (embed inject varA)
          v' <- input auto rendered
          v' @?= varA
      , testCase "Roundtrip B" $ do
          let rendered = Core.pretty (embed inject varB)
          v' <- input auto rendered
          v' @?= varB
      , testCase "Roundtrip heterogeneous Msg" $ do
          let rendered = Core.pretty (embed inject heteroVar1)
          v' <- input auto rendered
          v' @?= heteroVar1
      , testCase "Roundtrip nullary Ping" $ do
          let rendered = Core.pretty (embed inject heteroVar2)
          v' <- input auto rendered
          v' @?= heteroVar2
      , testCase "Permissive single-field payload decoding" $ do
          -- Union constructor with record payload in Dhall syntax:
          let srcRecord = "< Circle : { radius : Double } | Rect : { w : Double, h : Double } >.Circle { radius = 5.0 }"
          v1 <- input auto srcRecord :: IO ShapeVar
          let expectedCircle = Variant (Field @"Circle") (REC { radius = 5.0 :: Double }) :: ShapeVar
          v1 @?= expectedCircle

          -- Permissive single-field payload extraction on raw AST expression:
          let directExpr = Core.App (Core.Field (Core.Union mempty) (Core.makeFieldSelection "Circle")) (Core.DoubleLit (Core.DhallDouble 5.0))
          case extract auto directExpr of
            Success v2 -> v2 @?= expectedCircle
            Failure err -> assertFailure (show err)
      , testCase "Nullary variant parsing from bare constructor" $ do
          let srcBare = "< Msg : { text : Text, priority : Natural } | Ping >.Ping"
          v <- input auto srcBare :: IO HeteroVar
          v @?= heteroVar2
      ]
  , testGroup "Higher-Kinded Record Codecs (RecordF)"
      [ testCase "RecordF Maybe present & omitted roundtrip" $ do
          let srcFull = "{ api = Some \"https://api.v1\", workers = Some 8 }"
              srcPartial = "{ api = Some \"https://api.v2\", workers = None Natural }"
          c1 <- input auto srcFull :: IO AppConfigF
          c2 <- input auto srcPartial :: IO AppConfigF
          c1 @?= (insertFieldF (Field @"api") (Just "https://api.v1" :: Maybe Text)
                 $ insertFieldF (Field @"workers") (Just 8 :: Maybe Natural)
                 $ emptyRecordF)
          c2 @?= (insertFieldF (Field @"api") (Just "https://api.v2" :: Maybe Text)
                 $ insertFieldF (Field @"workers") (Nothing :: Maybe Natural)
                 $ emptyRecordF)

          -- Test HKD AST extraction with omitted field:
          let omittedHKDExpr = Core.RecordLit (Map.singleton "api" (Core.makeRecordField (embed inject (Just ("https://api.v2" :: Text)))))
          case extract auto omittedHKDExpr of
            Success c3 -> c3 @?= (insertFieldF (Field @"api") (Just "https://api.v2" :: Maybe Text)
                                 $ insertFieldF (Field @"workers") (Nothing :: Maybe Natural)
                                 $ emptyRecordF)
            Failure err -> assertFailure (show err)
      ]
  , testGroup "Generic Adapters (GenericDhall / GenericFromDhall / GenericToDhall)"
      [ testCase "DerivingVia GenericDhall roundtrip" $ do
          let cfg = ServerConfig { srvHost = "127.0.0.1", srvPort = 8443, srvTls = True }
              rendered = Core.pretty (embed inject cfg)
          cfg' <- input auto rendered
          cfg' @?= cfg
      , testCase "Direct genericFromDhall and genericToDhall" $ do
          let cfg = ServerConfig { srvHost = "gw.local", srvPort = 80, srvTls = False }
              enc = genericToDhall @ServerConfig
              dec = genericFromDhall @ServerConfig
              expr = embed enc cfg
          case extract dec expr of
            Success cfg' -> cfg' @?= cfg
            Failure err -> assertFailure (show err)
      ]
  , testGroup "Homogeneity Reflection"
      [ testCase "fieldNames in row order" $ do
          fieldNames (Proxy @HeteroRow) @?= ["host", "port", "active", "weight"]
      , testCase "ctorSpecs for homogeneous variant" $ do
          ctorSpecs (Proxy @Double) (Proxy @ShapeRow) @?= [("Circle", ["radius"]), ("Rect", ["w", "h"])]
      ]
  ]
