# polytropos-reader-soup

Composable multi-context Reader monad with zero-overhead row polymorphism for [polytropos](https://github.com/NadiaYvette/polytropos).

## Overview

In traditional Haskell application design, managing multiple configuration environments, connection pools, and runtime capabilities typically forces one of two unsatisfactory choices:
1. **MTL Class Proliferation:** Defining distinct `MonadDatabase`, `MonadConfig`, `MonadLogger`, `MonadMetrics` classes with $O(N^2)$ quadratic boilerplate instances across every layer of the transformer stack.
2. **Monolithic AppEnv:** Bundling everything into a single nominal `AppEnv` record, coupling small, self-contained sub-routines to the entire global environment and hindering modularity.

`polytropos-reader-soup` solves this dilemma by re-architecting Yves Parès's `reader-soup` on top of Polytropos's high-performance flat contiguous array representation (`Polytropos.Core.Rep`). A `ReaderSoup` hosts an arbitrary open row of labeled contexts in a single `ReaderT (Record ctxs) IO` layer. Subsystems declare exactly the slice of contexts they require, accessing them in $O(1)$ time via compile-time synthesized dictionary offsets, with structural narrowing via `filtering` taking $O(K)$ flat array copy time.

## Features

- **`ReaderSoup`**: Single-layer multi-context Reader environment (`ReaderT (Record ctxs) IO a`).
- **`askSoup`**: $O(1)$ context retrieval using type-level label symbols or `OverloadedRecordDot`.
- **`filtering`**: Zero-boilerplate structural subtyping via `SubRow`, allowing sub-actions to run seamlessly inside larger environments.
- **`Spoon`**: Isolates a single labeled context from the broth and equips it with a standard `MonadReader` instance supporting `ask` and `local`.
- **`SoupContext`**: Bridges existing third-party ReaderT-like monads (e.g. `ResourceT`, `KatipContextT`) via `picking`, `scooping`, and `pouring`.
- **`consumeSoup`**: Composes modular `ContextRunner` handlers to peel and execute contexts sequentially until the base broth is reached.
- **`Polytropos.ReaderSoup.Resource`**: Turnkey `resourcet` integration with `SoupContext InternalState ResourceT` and `MonadResource` instances.

## Quick Example

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}

module Main where

import Control.Monad.IO.Class (liftIO)
import Polytropos
import Polytropos.ReaderSoup

data DBConn = DBConn String
data Logger = Logger (String -> IO ())

type AppCtx =
  '[ "db"     := DBConn
   , "logger" := Logger
   , "port"   := Int
   ]

-- | A database worker only requires the DBConn context:
runQuery :: ReaderSoup '[ "db" := DBConn ] String
runQuery = do
  DBConn connStr <- askSoup (Field @"db")
  pure ("Executed on " ++ connStr)

-- | Main application running with the full AppCtx:
app :: ReaderSoup AppCtx ()
app = do
  Logger logFn <- askSoup (Field @"logger")
  liftIO (logFn "Application starting...")

  -- Narrow the environment from AppCtx down to '[ "db" := DBConn ]:
  res <- filtering runQuery
  liftIO (logFn ("Query result: " ++ res))

main :: IO ()
main = do
  let env = insertField (Field @"db") (DBConn "postgres://localhost:5432/prod")
          $ insertField (Field @"logger") (Logger putStrLn)
          $ insertField (Field @"port") (8080 :: Int)
          $ emptyRecord

  runReaderSoup app env
```

## Attribution & Precedents

This package is inspired by and directly acknowledges Yves Parès's work on `reader-soup` within the [Porcupine](https://github.com/funflow/porcupine) pipeline framework. The original package pioneered the concept of representing open collections of Reader-like monads via Vinyl extensible records. `polytropos-reader-soup` preserves those ergonomic and architectural insights while re-grounding them entirely on Polytropos's native flat array physics, compile-time literal index resolution, and structural `SubRow` evidence synthesis.

## License

Dual-licensed under `EUPL-1.2 OR Apache-2.0`.
