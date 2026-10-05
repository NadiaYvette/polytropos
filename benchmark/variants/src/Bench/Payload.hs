-- | A fixed payload type, shared by all benchmark arms.
--
-- The payload is deliberately small and defined ONCE, so that growth in the
-- benchmark modules is attributable purely to the number of constructors (or
-- fields), not to the payload's own size.
module Bench.Payload (P(..), mkP, unP) where

-- | Fixed 3-field record payload.
data P = P { pA :: !Int, pB :: !Int, pC :: !Int }
  deriving (Show, Eq)

mkP :: Int -> P
mkP i = P i (i * 2) (i * 3)

unP :: P -> Int
unP = pA
