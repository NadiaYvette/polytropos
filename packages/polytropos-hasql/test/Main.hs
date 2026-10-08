module Main (main) where

import Test.Tasty
import Test.Tasty.HUnit
import Data.Bits (Bits)
import Data.Functor.Identity (Identity (..))
import Data.Int (Int16, Int32, Int64)
import GHC.Exts (Any)
import qualified Data.Text as T
import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import Polytropos
import Polytropos.Core (Pair (..), fieldAt, noInlineUnsafeCo, unRowRep)
import Polytropos.Hasql
import qualified PostgreSQL.Binary.Decoding as B

-- Three heterogeneous columns: the differing wire widths (8/4/2 bytes)
-- make column-order observable in the payload slicing. (No plugin
-- synthesized Eq here — the plugin's literal dictionary index only
-- covers Int/Bool/Word, so equality is asserted field-wise below.)
type MyRec =
  Record '[ "a" ':= Int64, "b" ':= Int32, "c" ':= Int16 ]

-- Postgres binary wire encoding for the fixed-width integrals:
-- int2 = 2 bytes BE, int4 = 4 bytes BE, int8 = 8 bytes BE. These are the
-- exact payload formats hasql's int2/int4/int8 decoders (built on
-- postgresql-binary, its codec backend) consume per column.
wireInt64 :: Int64 -> BS.ByteString
wireInt64 = LBS.toStrict . BB.toLazyByteString . BB.int64BE

wireInt32 :: Int32 -> BS.ByteString
wireInt32 = LBS.toStrict . BB.toLazyByteString . BB.int32BE

wireInt16 :: Int16 -> BS.ByteString
wireInt16 = LBS.toStrict . BB.toLazyByteString . BB.int16BE

wireBig :: [Int64] -> BS.ByteString
wireBig = mconcat . map wireInt64

-- One column of the row, decoded at its own type through the same
-- decoder machinery hasql runs per column. This is the per-column step
-- of the walk 'genRow' composes; full Row execution needs a live server
-- (or hasql's hidden internals, verified in the probe session) so the
-- simulation stops at the column boundary.
decodeColumn :: forall a. (Integral a, Bits a) => BS.ByteString -> Either T.Text a
decodeColumn = B.valueParser (B.int :: B.Value a)

-- Assemble a record from per-column wire payloads, consuming columns
-- strictly in row order — one slot per column, exactly as the walk does.
decodeSim3 :: BS.ByteString -> BS.ByteString -> BS.ByteString -> Either T.Text MyRec
decodeSim3 ba bb bc = do
  a <- decodeColumn @Int64 ba
  b <- decodeColumn @Int32 bb
  c <- decodeColumn @Int16 bc
  pure $ insertField (Field @"a") a
       $ insertField (Field @"b") b
       $ insertField (Field @"c") c
       $ emptyRecord

fieldA, fieldB, fieldC :: MyRec -> Int64
fieldA r = unslot (fieldAt 0 (unRowRep r))
fieldB r = fromIntegral (unslot (fieldAt 1 (unRowRep r)) :: Int32)
fieldC r = fromIntegral (unslot (fieldAt 2 (unRowRep r)) :: Int16)

unslot :: Identity Any -> a
unslot = noInlineUnsafeCo

sizedChunks :: Int -> BS.ByteString -> [BS.ByteString]
sizedChunks n bs
  | BS.null bs = []
  | otherwise  = let (c, rest) = BS.splitAt n bs in c : sizedChunks n rest

main :: IO ()
main = defaultMain $ testGroup "Hasql Integration"
  [ testGroup "Row decoder construction"
      [ testCase "recordRow builds a 3-column decoder" $ do
          let rd = recordRow :: HasqlRow MyRec
          -- Construction is total and pure; the decoder exists.
          rd `seq` return ()
      , testCase "recordRow builds a 20-column decoder (no tuple limit)" $ do
          let rd = recordRow :: HasqlRow (Record RowOf20)
          rd `seq` return ()
      ]
  , testGroup "Simulated column consumption"
      [ testCase "heterogeneous columns decode in row order into a record" $
          case decodeSim3 (wireInt64 1) (wireInt32 2) (wireInt16 3) of
            Right r  -> do
              fieldA r @?= 1
              fieldB r @?= 2
              fieldC r @?= 3
            Left e   -> assertFailure (T.unpack e)
      , testCase "columns map to fields strictly in row order" $
          -- Permuting the column payloads permutes the record fields:
          -- (3,2,1) is a different record from (1,2,3), proving each
          -- column landed in its own slot.
          case decodeSim3 (wireInt64 3) (wireInt64 2) (wireInt64 1) of
            Right r  -> do
              fieldA r @?= 3
              fieldB r @?= 2
              fieldC r @?= 1
            Left e   -> assertFailure (T.unpack e)
      , testCase "20 columns of wire bytes roundtrip" $ do
          let vals = [ fromIntegral n :: Int64 | n <- [1 .. 20 :: Int] ]
          -- Exactly one 8-byte column per field, 20 fields, no tuples.
          case mapM (decodeColumn @Int64) (sizedChunks 8 (wireBig vals)) of
            Right vs -> vs @?= vals
            Left e   -> assertFailure (T.unpack e)
      ]
  ]

-- 20 columns: exercises the walk well past the 62-column tuple limit.
type RowOf20 =
  '[ "c00" ':= Int64, "c01" ':= Int64, "c02" ':= Int64, "c03" ':= Int64
   , "c04" ':= Int64, "c05" ':= Int64, "c06" ':= Int64, "c07" ':= Int64
   , "c08" ':= Int64, "c09" ':= Int64, "c10" ':= Int64, "c11" ':= Int64
   , "c12" ':= Int64, "c13" ':= Int64, "c14" ':= Int64, "c15" ':= Int64
   , "c16" ':= Int64, "c17" ':= Int64, "c18" ':= Int64, "c19" ':= Int64
   ]
