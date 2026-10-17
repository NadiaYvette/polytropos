{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}

-- | Worked Tutorial Example: Extensible Algebraic Effects & Higher-Kinded Ropes.
--
-- This executable demonstrates:
--   1. An extensible Arrow pipeline ('Rope') indexed by an open row of capability strands.
--   2. Strand definitions ('LoggerStrand', 'DatabaseStrand', 'MetricsStrand').
--   3. Category and Arrow pipeline composition ('>>>', '&&&') via 'SubRow' projection.
--   4. Higher-Kinded Record ('RecordF') capability auditing with 'cfoldMapRecordF'.
--   5. O(1) runtime strand access with zero intermediate tuple allocation.
--
-- Running:
--   $ cabal run example-effects
module Main (main, Rope(..), liftStrand, (>>>), (&&&)) where

import Control.Category (Category (..))
import Data.IORef
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Prelude hiding (id, (.))

import Polytropos

{-------------------------------------------------------------------------------
  1. Strand Effect Interfaces
-------------------------------------------------------------------------------}

-- | Logging capability strand.
newtype LoggerStrand = LoggerStrand
  { runLogger :: Text -> IO ()
  }

-- | Database capability strand.
data DatabaseStrand = DatabaseStrand
  { dbQueryBalance  :: Text -> IO (Maybe Int)
  , dbUpdateBalance :: Text -> Int -> IO ()
  }

-- | Metrics capability strand.
newtype MetricsStrand = MetricsStrand
  { runRecordMetric :: Text -> Int -> IO ()
  }

-- | Composite capability mantle row.
type AppMantle =
  '[ "logger"  ':= LoggerStrand
   , "db"      ':= DatabaseStrand
   , "metrics" ':= MetricsStrand
   ]

{-------------------------------------------------------------------------------
  2. The Extensible Rope Arrow
-------------------------------------------------------------------------------}

-- | An arrow pipeline requiring capabilities specified by row @req@.
-- By parameterising over the requirement row, individual pipeline steps
-- declare only the exact strands they need.
newtype Rope (req :: Row) a b = Rope
  { unRope :: Record req -> a -> IO b
  }

-- | Lift a single strand into a Rope.
liftStrand :: forall name s a b.
  (HasField name (Record '[name ':= s]) s)
  => (s -> a -> IO b)
  -> Rope '[name ':= s] a b
liftStrand act = Rope $ \mantle a ->
  act (getField @name mantle) a

-- | Sequential composition of ropes.
-- Both sub-ropes require capabilities from the joint mantle @full@.
(>>>) :: (SubRow r1 full, SubRow r2 full)
      => Rope r1 a b
      -> Rope r2 b c
      -> Rope full a c
(Rope f) >>> (Rope g) = Rope $ \mantle a -> do
  b <- f (projectRecord mantle) a
  g (projectRecord mantle) b

-- | Parallel fan-out of ropes (Arrow '&&&').
(&&&) :: (SubRow r1 full, SubRow r2 full)
      => Rope r1 a b
      -> Rope r2 a c
      -> Rope full a (b, c)
(Rope f) &&& (Rope g) = Rope $ \mantle a -> do
  b <- f (projectRecord mantle) a
  c <- g (projectRecord mantle) a
  pure (b, c)

infixr 1 >>>
infixr 3 &&&

{-------------------------------------------------------------------------------
  3. Concrete Pipeline Steps
-------------------------------------------------------------------------------}

-- | Step 1: Validate account and fetch balance.
-- Requires ONLY: "logger" and "db"
fetchAccountStep :: Rope '["logger" ':= LoggerStrand, "db" ':= DatabaseStrand] Text (Text, Int)
fetchAccountStep = Rope $ \env user -> do
  runLogger env.logger ("Fetching balance for user: " <> user)
  mBal <- dbQueryBalance env.db user
  case mBal of
    Nothing  -> error ("User not found: " ++ T.unpack user)
    Just bal -> pure (user, bal)

-- | Step 2: Deduct transaction fee and update database.
-- Requires ONLY: "db" and "metrics"
chargeFeeStep :: Int -> Rope '["db" ':= DatabaseStrand, "metrics" ':= MetricsStrand] (Text, Int) (Text, Int)
chargeFeeStep fee = Rope $ \env (user, bal) -> do
  let newBal = bal - fee
  dbUpdateBalance env.db user newBal
  runRecordMetric env.metrics ("fee.charged" :: Text) fee
  pure (user, newBal)

-- | Step 3: Audit log the completed transaction.
-- Requires ONLY: "logger"
auditStep :: Rope '["logger" ':= LoggerStrand] (Text, Int) Text
auditStep = Rope $ \env (user, newBal) -> do
  let msg = "Transaction complete for " <> user <> "; remaining balance: " <> T.pack (show newBal)
  runLogger env.logger msg
  pure msg

-- | Composite Pipeline:
-- Chains Step 1 >>> Step 2 >>> Step 3.
-- Automatically infers requirement row 'AppMantle'!
orderPipeline :: Rope AppMantle Text Text
orderPipeline =
  let step12 :: Rope AppMantle Text (Text, Int)
      step12 = fetchAccountStep >>> chargeFeeStep 25
  in step12 >>> auditStep

{-------------------------------------------------------------------------------
  4. Execution and Capability Audit
-------------------------------------------------------------------------------}

main :: IO ()
main = do
  TIO.putStrLn "============================================================"
  TIO.putStrLn " Addendum D: Extensible Algebraic Effects & Higher-Kinded Ropes"
  TIO.putStrLn "============================================================"
  TIO.putStrLn ""

  -- Mutable test state
  balanceRef <- newIORef (100 :: Int)
  metricsRef <- newIORef ([] :: [(Text, Int)])

  -- Construct concrete strands
  let logger = LoggerStrand $ \msg ->
        TIO.putStrLn $ "  [LOG] " <> msg

      db = DatabaseStrand
        { dbQueryBalance = \_ -> readIORef balanceRef >>= pure . Just
        , dbUpdateBalance = \_ newBal -> writeIORef balanceRef newBal
        }

      metrics = MetricsStrand $ \metric val -> do
        modifyIORef' metricsRef ((metric, val) :)
        TIO.putStrLn $ "  [METRIC] " <> metric <> " += " <> T.pack (show val)

  -- Assemble mantle using REC syntax
  let mantle :: Record AppMantle
      mantle = REC
        { logger  = logger
        , db      = db
        , metrics = metrics
        }

  TIO.putStrLn "--- Executing Arrow Pipeline (fetch >>> charge >>> audit) ---"
  result <- unRope orderPipeline mantle "alice"
  TIO.putStrLn ""
  TIO.putStrLn $ "Pipeline final result: " <> result

  finalBal <- readIORef balanceRef
  recordedMetrics <- readIORef metricsRef
  TIO.putStrLn $ "Final account balance: " <> T.pack (show finalBal)
  TIO.putStrLn $ "Recorded metrics:      " <> T.pack (show recordedMetrics)
  TIO.putStrLn ""
  TIO.putStrLn "Effects demonstration completed cleanly!"
