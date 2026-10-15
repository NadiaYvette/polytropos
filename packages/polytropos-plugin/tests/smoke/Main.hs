{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE ViewPatterns #-}
{-# OPTIONS_GHC -Wno-unused-top-binds #-}

-- | Smoke test: exercise RowEq / RowShow through the TcPlugin on R2.
--
-- This is the acceptance test for Option A: the plugin must emit literal
-- RowEq / RowShow bodies that actually work at runtime, not just compile.

module Main (main) where

import Control.Monad (forM_)
import Data.Functor.Identity (Identity(..))
import Data.Kind (Type)
import Data.List (isInfixOf)
import Data.Primitive.SmallArray (SmallArray, sizeofSmallArray, indexSmallArray)
import Data.Proxy (Proxy(..))
import Data.Type.Equality ((:~:)(Refl))
import GHC.Exts (Any)
import GHC.TypeLits (Symbol)
import System.Directory (getTemporaryDirectory, removeFile)
import System.Environment (lookupEnv)
import System.Exit (ExitCode(..))
import System.FilePath ((</>))
import System.Process (readProcessWithExitCode)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

import Polytropos.Core
import Polytropos

-- | R2: a two-field product: a :: Int, b :: Bool.
type R2 = '[ "a" := Int, "b" := Bool ]

-- | Store a concrete value in a slot.
slot :: a -> Identity Any
slot = noInlineUnsafeCo

-- | The two values under test.
ab :: RowRep Identity ProductRowT R2 (Int, Bool)
ab = RowRep (productRep [slot (7 :: Int), slot True])

other :: RowRep Identity ProductRowT R2 (Int, Bool)
other = RowRep (productRep [slot (7 :: Int), slot False])

type RD = '[ "x" := Int, "y" := Bool ]
rDot :: RowRep Identity ProductRowT RD (Int, Bool)
rDot = RowRep (productRep [slot (42 :: Int), slot True])

data Person = Person { name :: String, age :: Int }
  deriving (Show, Eq, OpenRecord)

data Status = Success { val :: Int } | Failure { msg :: String }
  deriving (Show, Eq, OpenVariant)

main :: IO ()
main = defaultMain $ testGroup "plugin RowEq/RowShow smoke"
  [ testGroup "Products"
      [ testCase "repEq is reflexive" $
          repEq ab ab @?= True
      , testCase "repEq detects a differing slot" $
          repEq ab other @?= False
      , testCase "repShowsPrec renders both fields" $
          repShowsPrec 0 ab "" @?= "R2 7 True"
      ]
  , testGroup "Sums"
      [ testCase "repEqSum (RowEqSum) matches same constructor and same payload" $
          repEqSum sumC1 sumC1 @?= True
      , testCase "repEqSum (RowEqSum) rejects different payloads in same constructor" $
          repEqSum sumC1 sumC1diff @?= False
      , testCase "repEqSum (RowEqSum) rejects different constructors" $
          repEqSum sumC1 sumC2 @?= False
      , testCase "repShowsPrecSum (RowShowSum) renders C1 properly" $
          repShowsPrecSum 0 sumC1 "" @?= "C1 7"
      , testCase "repShowsPrecSum (RowShowSum) renders C2 properly" $
          repShowsPrecSum 0 sumC2 "" @?= "C2 True"
      ]
  , testGroup "OverloadedRecordDot"
      [ testCase "r.x == 42" $
          rDot.x @?= Identity (42 :: Int)
      , testCase "r.y == True" $
          rDot.y @?= Identity True
      , testCase "rHKD.msg == Just \"ok\" on RecordF Maybe" $
          rHKD.msg @?= Just ("ok" :: String)
      , testCase "rHKD.code == Nothing on RecordF Maybe" $
          rHKD.code @?= (Nothing :: Maybe Int)
      ]
  , testGroup "AllFields generic dictionary supply"
      [ testCase "supplies Show dictionaries for homogeneous product row" $
          let arr = fieldDicts @ProductRowT @TwoInts @Show
          in do
            sizeofSmallArray arr @?= 2
            showAllFields arr (repVals (unRowRep twoInts)) @?= "42 7"
      , testCase "supplies Show dictionaries for heterogeneous product row (String, Int, Bool)" $
          let arr = fieldDicts @ProductRowT @HeteroRow @Show
          in do
            sizeofSmallArray arr @?= 3
            showAllFields arr (repVals (unRowRep heteroVal)) @?= "\"hello\" 99 True"
      , testCase "supplies Show dictionaries for HKD product row (Maybe String, Maybe Int)" $
          let arr = fieldDicts @ProductRowHKDT @(HKDProductRow Maybe) @Show
          in do
            sizeofSmallArray arr @?= 2
            showAllFieldsHKD arr (repVals (unRowRep hkdVal)) @?= "Just \"ok\" Nothing"
      ]
  , testGroup "HKD Row Vocabulary"
      [ testCase "FieldIndex resolves on HKD product row" $ do
          fieldIndex @_ @"msg" @(HKDProductRow Maybe) @(Maybe String) @?= 0
          fieldIndex @_ @"code" @(HKDProductRow Maybe) @(Maybe Int) @?= 1
      , testCase "ConstructorIndex resolves on HKD sum row" $ do
          constructorIndex @_ @"Success" @(HKDSumRow Maybe) @?= 0
          constructorIndex @_ @"Failure" @(HKDSumRow Maybe) @?= 1
      ]
  , testGroup "Type-level row metadata rewriting"
      [ testCase "FieldNames reduces on TwoInts" $
          case namesTwoInts of
            Refl -> pure ()
      , testCase "FieldNames reduces on empty row" $
          case namesEmpty of
            Refl -> pure ()
      , testCase "SimpleFieldTypes reduces on TwoInts" $
          case simpleTypesTwoInts of
            Refl -> pure ()
      , testCase "SimpleFieldTypes reduces on empty row" $
          case simpleTypesEmpty of
            Refl -> pure ()
      , testCase "FieldTypes reduces on TwoInts with Maybe" $
          case fieldTypesTwoInts of
            Refl -> pure ()
      , testCase "FieldTypes reduces on HeteroRow with Identity" $
          case fieldTypesHetero of
            Refl -> pure ()
      , testCase "FieldTypes reduces on empty row" $
          case fieldTypesEmpty of
            Refl -> pure ()
      ]
  , testGroup "SubRow and SubSum evidence"
      [ testCase "SubRow emits projection indices" $ do
          subRowIndices @SmallProd @BigProd @?= [2, 0]
          subRowIndices @SmallProd @SmallProd @?= [0, 1]
      , testCase "projectRecord extracts sub-record fields" $ do
          let bigRec :: Record BigProd
              bigRec = insertField (Field @"a") (10 :: Int)
                     $ insertField (Field @"b") True
                     $ insertField (Field @"c") "hello"
                     $ emptyRecord
              smallRec :: Record SmallProd
              smallRec = projectRecord bigRec
          smallRec.c @?= Identity "hello"
          smallRec.a @?= Identity (10 :: Int)
      , testCase "SubSum emits inject and narrow indices" $ do
          subSumInjectIndices @SmallSum @BigSum @?= [0, 2]
          subSumNarrowIndices @SmallSum @BigSum @?= [Just 0, Nothing, Just 1]
      , testCase "widenVariant remaps constructor tag to super-row" $ do
          let vC_small :: Variant SmallSum
              vC_small = injectVariant (Field @"C") (insertField (Field @"y") True emptyRecord)
              vC_wide :: Variant BigSum
              vC_wide = widenVariant vC_small
          repTag (unRowRep vC_wide) @?= 2
          case projectVariant (Field @"C") vC_wide of
            Just (r :: Record '[ "y" := Bool ]) -> r.y @?= Identity True
            Nothing -> error "expected Just in widenVariant"
      , testCase "narrowVariant succeeds on matching constructor" $ do
          let vC_small :: Variant SmallSum
              vC_small = injectVariant (Field @"C") (insertField (Field @"y") True emptyRecord)
              vC_wide :: Variant BigSum
              vC_wide = widenVariant vC_small
          case narrowVariant @SmallSum vC_wide of
            Just vC' -> case projectVariant (Field @"C") vC' of
              Just (r :: Record '[ "y" := Bool ]) -> r.y @?= Identity True
              Nothing -> error "expected Just in narrowVariant"
            Nothing -> error "expected Just in narrowVariant"
      , testCase "narrowVariant returns Nothing for super constructor absent in sub" $ do
          let vB_big :: Variant BigSum
              vB_big = injectVariant (Field @"B") (insertField (Field @"x") (42 :: Int) emptyRecord)
              mNarrow = narrowVariant @SmallSum vB_big
          case mNarrow of
            Nothing -> pure ()
            Just _  -> error "expected Nothing in narrowVariant"
      ]
  , testGroup "Compile-time label hashing (KnownHash)"
      [ testCase "knownHash solves on literal symbols and matches fnv1a64" $ do
          knownHash @"x" @?= fnv1a64 "x"
          knownHash @"greeting" @?= fnv1a64 "greeting"
          knownHash @"a" @?= fnv1a64 "a"
          knownHash @"veryLongFieldNameForTestingCompileTimeHashing"
            @?= fnv1a64 "veryLongFieldNameForTestingCompileTimeHashing"
      , testCase "labelHash and hashVal proxies extract the literal hash" $ do
          labelHash (Field @"greeting") @?= fnv1a64 "greeting"
          hashVal (Field @"greeting") @?= fnv1a64 "greeting"
          labelHash (Proxy @"a") @?= fnv1a64 "a"
      , testCase "different labels yield distinct non-zero hashes" $ do
          knownHash @"x" /= 0 @?= True
          knownHash @"y" /= 0 @?= True
          knownHash @"x" /= knownHash @"y" @?= True
      ]
  , testGroup "Source Plugin Syntax (§1.6)"
      [ testCase "REC bare record construction" $ do
          let r = REC { a = (10 :: Int), b = True }
          r.a @?= Identity (10 :: Int)
          r.b @?= Identity True
      , testCase "REC with field punning" $ do
          let a = (99 :: Int)
              b = False
              r = REC { a, b }
          r.a @?= Identity (99 :: Int)
          r.b @?= Identity False
      , testCase "REC_F HKD record construction" $ do
          let r = REC_F { msg = Just ("hello" :: String), code = (Nothing :: Maybe Int) }
          r.msg @?= Just "hello"
          r.code @?= (Nothing :: Maybe Int)
      , testCase "VAR and VARIANT injection" $ do
          let v1 :: Variant '[ "ok" := '[ "val" := Int ] ]
              v1 = VAR { ok = REC { val = (200 :: Int) } }
          case projectVariant (Field @"ok") v1 of
            Just r -> r.val @?= Identity (200 :: Int)
            Nothing -> error "expected Just in projectVariant"
          let v2 :: Variant '[ "err" := '[ "msg" := String ] ]
              v2 = VARIANT { err = REC { msg = ("not found" :: String) } }
          case projectVariant (Field @"err") v2 of
            Just r -> r.msg @?= Identity "not found"
            Nothing -> error "expected Just in projectVariant"
      , testCase "REC_UPD bare record update" $ do
          let r1 = REC { a = (10 :: Int), b = True }
              r2 = (REC_UPD r1) { a = (42 :: Int) }
          r2.a @?= Identity (42 :: Int)
          r2.b @?= Identity True
      , testCase "REC_UPD_F HKD record update" $ do
          let r1 = REC_F { msg = Just ("hi" :: String), code = (Nothing :: Maybe Int) }
              r2 = (REC_UPD_F r1) { code = (Just 200 :: Maybe Int) }
          r2.msg @?= Just "hi"
          r2.code @?= Just (200 :: Int)
      , testCase "REC pattern matching (single and multiple fields)" $ do
          let r = REC { a = (10 :: Int), b = True }
              valA = case r of
                REC { a = vA } -> vA
              (x, y) = case r of
                REC { a, b } -> (a, b)
          valA @?= (10 :: Int)
          x @?= (10 :: Int)
          y @?= True
      , testCase "VAR pattern matching" $ do
          let v1 = VAR { ok = REC { val = (200 :: Int) } } :: Variant '[ "ok" := '[ "val" := Int ], "err" := '[ "msg" := String ] ]
              v2 = VAR { err = REC { msg = ("oops" :: String) } } :: Variant '[ "ok" := '[ "val" := Int ], "err" := '[ "msg" := String ] ]
              check :: Variant '[ "ok" := '[ "val" := Int ], "err" := '[ "msg" := String ] ] -> String
              check v = case v of
                VAR { ok = REC { val = n } } -> show n
                VAR { err = REC { msg = s } } -> s
                _                             -> error "unreachable"
          check v1 @?= "200"
          check v2 @?= "oops"
      , testCase "OpenRecord declaration form construction and matching" $ do
          let p = Person { name = "Alice", age = (30 :: Int) }
          p.name @?= Identity "Alice"
          p.age @?= Identity (30 :: Int)
          let (resName, resAge) = case p of
                Person { name, age } -> (name, age)
          resName @?= "Alice"
          resAge @?= (30 :: Int)
      , testCase "OpenVariant declaration form construction and matching" $ do
          let s1 = Success { val = (200 :: Int) } :: Variant '[ "Success" := '[ "val" := Int ], "Failure" := '[ "msg" := String ] ]
              s2 = Failure { msg = "bad request" } :: Variant '[ "Success" := '[ "val" := Int ], "Failure" := '[ "msg" := String ] ]
              eval :: Variant '[ "Success" := '[ "val" := Int ], "Failure" := '[ "msg" := String ] ] -> Int
              eval s = case s of
                Success { val } -> val
                Failure { msg } -> length msg
                _               -> error "unreachable"
          eval s1 @?= 200
          eval s2 @?= 11
      ]
  , testGroup "Eliminators and Peeling (§1.7)"
      [ testCase "eliminateUniform handles variants in O(1) with REC handlers" $ do
          let v1 = VAR { ok = REC { val = (42 :: Int) } } :: Variant '[ "ok" := '[ "val" := Int ], "err" := '[ "msg" := String ] ]
              v2 = VAR { err = REC { msg = ("error!" :: String) } } :: Variant '[ "ok" := '[ "val" := Int ], "err" := '[ "msg" := String ] ]
              handlers = REC
                { ok = \(REC { val }) -> "Success: " ++ show (val :: Int)
                , err = \(REC { msg }) -> "Failure: " ++ (msg :: String)
                }
          eliminateUniform handlers v1 @?= "Success: 42"
          eliminateUniform handlers v2 @?= "Failure: error!"
      , testCase "peel isolates single constructor and updates remaining variant tag" $ do
          let vOk = VAR { ok = REC { val = (100 :: Int) } } :: Variant '[ "ok" := '[ "val" := Int ], "err" := '[ "msg" := String ] ]
              vErr = VAR { err = REC { msg = ("oops" :: String) } } :: Variant '[ "ok" := '[ "val" := Int ], "err" := '[ "msg" := String ] ]
          case peel @"ok" vOk of
            Right (REC { val }) -> val @?= (100 :: Int)
            Left _ -> error "expected Right"
          case peel @"ok" vErr of
            Right _ -> error "expected Left"
            Left rest -> case projectVariant (Field @"err") rest of
              Just (REC { msg }) -> msg @?= "oops"
              Nothing -> error "expected err in rest"
      ]
  , testGroup "TypeError human-centric diagnostics"
      [ testCase "missing field diagnostic with available fields list" $
          checkGhcDiag
            (unlines
              [ "{-# LANGUAGE DataKinds, TypeApplications, TypeOperators #-}"
              , "module Test where"
              , "import Polytropos.Core"
              , "t = fieldIndex @_ @\"email\" @'[ \"name\" := String, \"age\" := Int ] @Int"
              ])
            [ "Polytropos Record Error:"
            , "Field 'email' does not exist in record:"
            , "{ name :: String, age :: Int }"
            , "Available fields: 'name', 'age'"
            ]
      , testCase "missing field diagnostic with fuzzy suggestion" $
          checkGhcDiag
            (unlines
              [ "{-# LANGUAGE DataKinds, TypeApplications, TypeOperators #-}"
              , "module Test where"
              , "import Polytropos.Core"
              , "t = fieldIndex @_ @\"naem\" @'[ \"name\" := String, \"age\" := Int ] @String"
              ])
            [ "Polytropos Record Error:"
            , "Field 'naem' does not exist in record:"
            , "Did you mean: 'name'?"
            ]
      , testCase "field type mismatch diagnostic" $
          checkGhcDiag
            (unlines
              [ "{-# LANGUAGE DataKinds, TypeApplications, TypeOperators #-}"
              , "module Test where"
              , "import Polytropos.Core"
              , "t = fieldIndex @_ @\"name\" @'[ \"name\" := String, \"age\" := Int ] @Int"
              ])
            [ "Polytropos Record Error:"
            , "Field 'name' in record has type:"
            , "String"
            , "but expected:"
            , "Int"
            ]
      , testCase "missing constructor diagnostic with available constructors list" $
          checkGhcDiag
            (unlines
              [ "{-# LANGUAGE DataKinds, TypeApplications, TypeOperators #-}"
              , "module Test where"
              , "import Polytropos.Core"
              , "t = constructorIndex @_ @\"Exit\" @'[ \"Start\" := '[ \"x\" := String ], \"Stop\" := '[ \"y\" := Int ] ]"
              ])
            [ "Polytropos Variant Error:"
            , "Constructor 'Exit' is not a member of variant:"
            , "< Start { x :: String } | Stop { y :: Int } >"
            , "Available constructors: 'Start', 'Stop'"
            ]
      , testCase "missing constructor diagnostic with fuzzy suggestion" $
          checkGhcDiag
            (unlines
              [ "{-# LANGUAGE DataKinds, TypeApplications, TypeOperators #-}"
              , "module Test where"
              , "import Polytropos.Core"
              , "t = constructorIndex @_ @\"Strt\" @'[ \"Start\" := '[ \"x\" := String ], \"Stop\" := '[ \"y\" := Int ] ]"
              ])
            [ "Polytropos Variant Error:"
            , "Constructor 'Strt' is not a member of variant:"
            , "Did you mean: 'Start' or 'Stop'?"
            ]
      , testCase "SubRow missing field diagnostic" $
          checkGhcDiag
            (unlines
              [ "{-# LANGUAGE DataKinds, TypeApplications, TypeOperators #-}"
              , "module Test where"
              , "import Polytropos.Core"
              , "t = subRowIndices @'[ \"z\" := Bool ] @'[ \"a\" := Int, \"b\" := Bool ]"
              ])
            [ "Polytropos SubRow Error:"
            , "Cannot project record: field 'z' from sub-record is missing in super-record:"
            , "{ a :: Int, b :: Bool }"
            ]
      , testCase "SubRow field type mismatch diagnostic" $
          checkGhcDiag
            (unlines
              [ "{-# LANGUAGE DataKinds, TypeApplications, TypeOperators #-}"
              , "module Test where"
              , "import Polytropos.Core"
              , "t = subRowIndices @'[ \"a\" := String ] @'[ \"a\" := Int, \"b\" := Bool ]"
              ])
            [ "Polytropos SubRow Error:"
            , "Cannot project record: field 'a' has type:"
            , "String"
            , "in sub-record, but has type:"
            , "Int"
            , "in super-record."
            ]
      , testCase "SubSum missing constructor diagnostic" $
          checkGhcDiag
            (unlines
              [ "{-# LANGUAGE DataKinds, TypeApplications, TypeOperators #-}"
              , "module Test where"
              , "import Polytropos.Core"
              , "t = subSumInjectIndices @'[ \"Missing\" := '[] ] @'[ \"A\" := '[], \"B\" := '[] ]"
              ])
            [ "Polytropos SubSum Error:"
            , "Cannot widen variant: constructor 'Missing' from sub-variant is missing in super-variant:"
            , "< A | B >"
            , "Available constructors: 'A', 'B'"
            ]
      , testCase "SubSum payload mismatch diagnostic" $
          checkGhcDiag
            (unlines
              [ "{-# LANGUAGE DataKinds, TypeApplications, TypeOperators #-}"
              , "module Test where"
              , "import Polytropos.Core"
              , "t = subSumInjectIndices @'[ \"A\" := '[ \"x\" := Int ] ] @'[ \"A\" := '[ \"x\" := String ] ]"
              ])
            [ "Polytropos SubSum Error:"
            , "Cannot widen variant: constructor 'A' has different payload rows:"
            , "sub-variant payload:   { x :: Int }"
            , "super-variant payload: { x :: String }"
            ]
      ]
  ]

checkGhcDiag :: String -> [String] -> IO ()
checkGhcDiag snippet expectedSubstrings = do
  tmpDir <- getTemporaryDirectory
  let tmpFile = tmpDir </> "PolytroposDiagTest.hs"
  writeFile tmpFile snippet
  extraFlags <- maybe [] words <$> lookupEnv "POLYTROPOS_TEST_GHC_FLAGS"
  (exitCode, _stdout, stderr) <- readProcessWithExitCode
    "ghc"
    ([ "-fno-code"
     , tmpFile
     , "-fplugin=Polytropos.Plugin"
     ] ++ extraFlags)
    ""
  removeFile tmpFile
  exitCode @?= ExitFailure 1
  forM_ expectedSubstrings $ \expected ->
    assertBool
      ("Expected diagnostic to contain: " ++ show expected ++ "\nActual stderr:\n" ++ stderr)
      (expected `isInfixOf` stderr)

-- | Use a supplied array of type-erased Show dictionaries to show every slot.
showAllFields :: DictAllFields Show
              -> SmallArray (Identity Any)
              -> String
showAllFields arr slots =
  go 0
  where
    n = sizeofSmallArray slots
    go i
      | i == n = ""
      | otherwise =
          case indexSmallArray arr i of
            DictAny ->
              let Identity x = indexSmallArray slots i
              in show x <> if i + 1 == n then "" else " " <> go (i + 1)

type TwoInts = '[ "x" := Int, "y" := Int ]
twoInts :: RowRep Identity ProductRowT TwoInts ()
twoInts = RowRep (productRep [slot (42 :: Int), slot (7 :: Int)])

type HeteroRow = '[ "greeting" := String, "count" := Int, "active" := Bool ]
heteroVal :: RowRep Identity ProductRowT HeteroRow ()
heteroVal = RowRep (productRep [slot ("hello" :: String), slot (99 :: Int), slot True])

namesTwoInts :: FieldNames TwoInts :~: '[ "x", "y" ]
namesTwoInts = Refl

namesEmpty :: FieldNames ('[] :: [(Symbol, Type)]) :~: '[]
namesEmpty = Refl

simpleTypesTwoInts :: SimpleFieldTypes TwoInts :~: '[ '("x", Int), '("y", Int) ]
simpleTypesTwoInts = Refl

simpleTypesEmpty :: SimpleFieldTypes ('[] :: [(Symbol, Type)]) :~: '[]
simpleTypesEmpty = Refl

fieldTypesTwoInts :: FieldTypes Maybe TwoInts :~: '[ '("x", Maybe Int), '("y", Maybe Int) ]
fieldTypesTwoInts = Refl

fieldTypesHetero :: FieldTypes Identity HeteroRow :~: '[ '("greeting", Identity String), '("count", Identity Int), '("active", Identity Bool) ]
fieldTypesHetero = Refl

fieldTypesEmpty :: FieldTypes Maybe ('[] :: [(Symbol, Type)]) :~: '[]
fieldTypesEmpty = Refl

-- | S2: a sum with two constructors
type S2 = '[ "C1" := '[ "x" := Int ], "C2" := '[ "y" := Bool ] ]

-- | Ensure the plugin solves these dictionaries (RowEqSum, RowShowSum) for S2.

sumC1 :: RowRep Identity SumRowT S2 a
sumC1 = RowRep (injectRep 0 [slot (7 :: Int)])

sumC1diff :: RowRep Identity SumRowT S2 a
sumC1diff = RowRep (injectRep 0 [slot (8 :: Int)])

sumC2 :: RowRep Identity SumRowT S2 a
sumC2 = RowRep (injectRep 1 [slot True])

type HKDProductRow (f :: Type -> Type) = '[ "msg" := f String, "code" := f Int ] :: ProductRow f

type HKDSumRow (f :: Type -> Type) = '[ "Success" := HKDProductRow f, "Failure" := '[] ] :: SumRowHKD f

slotMaybe :: Maybe a -> Maybe Any
slotMaybe = noInlineUnsafeCo

hkdVal :: RowRep Maybe ProductRowHKDT (HKDProductRow Maybe) ()
hkdVal = RowRep (productRep [slotMaybe (Just ("ok" :: String)), slotMaybe (Nothing :: Maybe Int)])

rHKD :: RowRep Maybe ProductRowHKDT (HKDProductRow Maybe) ()
rHKD = hkdVal

showAllFieldsHKD :: DictAllFields Show
                 -> SmallArray (Maybe Any)
                 -> String
showAllFieldsHKD arr slots =
  go 0
  where
    n = sizeofSmallArray slots
    go i
      | i == n = ""
      | otherwise =
          case indexSmallArray arr i of
            DictAny ->
              let x :: Any
                  x = noInlineUnsafeCo (indexSmallArray slots i)
              in show x <> if i + 1 == n then "" else " " <> go (i + 1)

-- | Big product and sub-product for testing SubRow evidence.
type BigProd = '[ "a" := Int, "b" := Bool, "c" := String ]
type SmallProd = '[ "c" := String, "a" := Int ]

-- | Big sum and sub-sum for testing SubSum evidence.
type BigSum = '[ "A" := '[], "B" := '[ "x" := Int ], "C" := '[ "y" := Bool ] ]
type SmallSum = '[ "A" := '[], "C" := '[ "y" := Bool ] ]
