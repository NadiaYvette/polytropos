{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}

module Main (main) where

import qualified Data.Aeson as Aeson
import Data.Aeson (object, (.=))
import qualified Data.Text as T
import qualified Options.Applicative as Opt
import Options.Applicative (info, idm, defaultPrefs, execParserPure)
import Polytropos
import Polytropos.DocRecord
import Test.Tasty
import Test.Tasty.HUnit

type ServerConfig =
  '[ "host"     := String
   , "port"     := Int
   , "verbose"  := Bool
   ]

defaultConfig :: DocRec ServerConfig
defaultConfig =
  consDoc (Field @"host") (docField "127.0.0.1" "Listening host IP")
    $ consDoc (Field @"port") (docField (8080 :: Int) "TCP listen port")
    $ consDoc (Field @"verbose") (docField False "Enable debug logs")
    $ emptyDocRec

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Polytropos.DocRecord"
  [ testCase "inspect default values with OverloadedRecordDot" $ do
      getDocVal defaultConfig.host @?= Just "127.0.0.1"
      getDocVal defaultConfig.port @?= Just 8080
      getDocVal defaultConfig.verbose @?= Just False
      diSource defaultConfig.host @?= DefaultSource
      diSource defaultConfig.port @?= DefaultSource

  , testCase "showDocumentation renders markdown schema table" $ do
      let doc = showDocumentation defaultConfig
      assertBool "contains host field" (T.isInfixOf "`host`" doc)
      assertBool "contains port field" (T.isInfixOf "`port`" doc)
      assertBool "contains verbose field" (T.isInfixOf "`verbose`" doc)
      assertBool "contains port type Int" (T.isInfixOf "`Int`" doc)
      assertBool "contains default 8080" (T.isInfixOf "`8080`" doc)

  , testCase "fromJSONAs merges partial JSON and tags with YamlSource" $ do
      let jsonPayload = object [ "port" .= (9090 :: Int) ]
      case fromJSONAs defaultConfig jsonPayload of
        Aeson.Error err -> assertFailure ("JSON merge failed: " ++ err)
        Aeson.Success cfg -> do
          -- port was updated:
          getDocVal cfg.port @?= Just 9090
          diSource cfg.port @?= YamlSource
          -- host was preserved from defaults:
          getDocVal cfg.host @?= Just "127.0.0.1"
          diSource cfg.host @?= DefaultSource

  , testCase "priority merging chooses higher SourceTag" $ do
      let cliItem = docItemWithSource CliSource (Present (9999 :: Int)) "CLI port"
          cliConfig = consDoc (Field @"host") defaultConfig.host
                    $ consDoc (Field @"port") cliItem
                    $ consDoc (Field @"verbose") defaultConfig.verbose
                    $ emptyDocRec

          merged = mergeDocRec defaultConfig cliConfig
      getDocVal merged.port @?= Just 9999
      diSource merged.port @?= CliSource

  , testCase "parseRecFromCLI parses command-line flags and tags with CliSource" $ do
      let pinfo = info (parseRecFromCLI defaultConfig) idm
          args = ["--port", "7777", "--verbose"]
          parsed = execParserPure defaultPrefs pinfo args
      case parsed of
        Opt.Failure failure -> assertFailure ("CLI parser failed: " ++ show failure)
        Opt.CompletionInvoked _ -> assertFailure "Unexpected completion invocation"
        Opt.Success cfg -> do
          getDocVal cfg.port @?= Just 7777
          diSource cfg.port @?= CliSource
          getDocVal cfg.verbose @?= Just True
          diSource cfg.verbose @?= CliSource
          getDocVal cfg.host @?= Just "127.0.0.1"
          diSource cfg.host @?= DefaultSource
  ]
