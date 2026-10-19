{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin -Wno-orphans #-}

module Main (main) where

import Control.Monad.Reader.Class (ask, local)
import Control.Monad.Trans.Reader (ReaderT(..))
import Control.Monad.Trans.Resource
  ( InternalState
  , MonadResource(..)
  , allocate
  , createInternalState
  , closeInternalState
  )
import Data.IORef
import Polytropos
import Polytropos.ReaderSoup
import Polytropos.ReaderSoup.Resource ()
import Test.Tasty
import Test.Tasty.HUnit

data DBConn = DBConn String deriving (Eq, Show)

type AppCtx =
  '[ "db"       := DBConn
   , "port"     := Int
   , "greeting" := String
   ]

type instance ContextFromName "x" = Int
type instance ContextFromName "y" = String

newtype IntEnv m a = IntEnv { unIntEnv :: ReaderT Int m a }
  deriving (Functor, Applicative, Monad)

instance SoupContext Int IntEnv where
  toReaderT = unIntEnv
  fromReaderT = IntEnv

newtype StrEnv m a = StrEnv { unStrEnv :: ReaderT String m a }
  deriving (Functor, Applicative, Monad)

instance SoupContext String StrEnv where
  toReaderT = unStrEnv
  fromReaderT = StrEnv

mkAppEnv :: DBConn -> Int -> String -> Record AppCtx
mkAppEnv db p g =
  insertField (Field @"db") db
    $ insertField (Field @"port") p
    $ insertField (Field @"greeting") g
    $ emptyRecord

-- Sub-soup requiring only DBConn and greeting:
subWorker :: ReaderSoup '[ "db" := DBConn, "greeting" := String ] String
subWorker = do
  db <- askSoup (Field @"db")
  g <- askSoup (Field @"greeting")
  pure (g ++ " from " ++ show db)

type RunnerRow =
  '[ "x" := ContextRunner IntEnv (ReaderSoup '[ "y" := String ])
   , "y" := ContextRunner StrEnv (ReaderSoup '[])
   ]

type ResCtx = '[ "resource" := InternalState, "tag" := String ]

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Polytropos.ReaderSoup"
  [ testCase "askSoup retrieves individual contexts in O(1)" $ do
      let env = mkAppEnv (DBConn "pg://prod") 5432 "Hello"
      res <- runReaderSoup (do
        db <- askSoup (Field @"db")
        p  <- askSoup (Field @"port")
        g  <- askSoup (Field @"greeting")
        pure (db, p, g)
        ) env
      res @?= (DBConn "pg://prod", 5432, "Hello")

  , testCase "filtering narrows full AppCtx down to sub-soup" $ do
      let env = mkAppEnv (DBConn "pg://cluster") 9000 "Welcome"
      msg <- runReaderSoup (filtering subWorker) env
      msg @?= "Welcome from DBConn \"pg://cluster\""

  , testCase "Spoon provides MonadReader with ask and local" $ do
      let env = mkAppEnv (DBConn "pg://local") 8080 "Hi"
      res <- runReaderSoup (dipping (Field @"port") $ do
        p1 <- ask
        p2 <- local (+ 100) ask
        p3 <- ask
        pure (p1, p2, p3)
        ) env
      res @?= (8080 :: Int, 8180 :: Int, 8080 :: Int)

  , testCase "pickTopping and eatTopping peel contexts iteratively" $ do
      let soup :: ReaderSoup '[ "a" := Int, "b" := String ] String
          soup = do
            a <- askSoup (Field @"a")
            b <- askSoup (Field @"b")
            pure (b ++ show a)

      -- Peel first topping ("a" := Int):
      let toppingA = pickTopping soup
          soupB = runReaderT toppingA (42 :: Int)

      -- Peel second topping ("b" := String):
      let toppingB = pickTopping soupB
          baseSoup = runReaderT toppingB "Answer: "

      result <- finishBroth baseSoup
      result @?= "Answer: 42"

  , testCase "consumeSoup executes runners iteratively" $ do
      let soup :: ReaderSoup '[ "x" := Int, "y" := String ] (Int, String)
          soup = do
            x <- askSoup (Field @"x")
            y <- askSoup (Field @"y")
            pure (x, y)

      let runners :: Record RunnerRow
          runners =
            insertField (Field @"x") (ContextRunner (\(IntEnv act) -> runReaderT act (123 :: Int)))
              $ insertField (Field @"y") (ContextRunner (\(StrEnv act) -> runReaderT act "dynamic"))
              $ emptyRecord

      res <- consumeSoup runners soup
      res @?= (123, "dynamic")

  , testCase "ResourceT integration via Polytropos.ReaderSoup.Resource" $ do
      cleanedUpRef <- newIORef False
      istate <- createInternalState

      let env :: Record ResCtx
          env = insertField (Field @"resource") istate
              $ insertField (Field @"tag") "res-test"
              $ emptyRecord

      res <- runReaderSoup (do
        t <- askSoup (Field @"tag")
        -- Allocate resource with cleanup hook:
        (_key, val) <- liftResourceT (allocate (pure ("resource-" ++ t)) (\_ -> writeIORef cleanedUpRef True))
        pure val
        ) env

      res @?= "resource-res-test"
      wasCleanedBefore <- readIORef cleanedUpRef
      wasCleanedBefore @?= False

      -- Close internal state and verify cleanup hook ran:
      closeInternalState istate
      wasCleanedAfter <- readIORef cleanedUpRef
      wasCleanedAfter @?= True
  ]
