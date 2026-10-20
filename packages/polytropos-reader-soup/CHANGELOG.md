# Revision history for polytropos-reader-soup

## 0.1.0.1 -- 2026-10-20

* Coordinated release with `polytropos-core-0.1.0.1`.

## 0.1.0.0 -- 2026-10-19

* First release.
* Re-architected from Yves Parès's `reader-soup` (from the Porcupine pipeline framework) onto Polytropos's native contiguous flat array representation (`Polytropos.Core.Rep`) and compile-time dictionary synthesis (`Polytropos.Plugin`).
* Core `ReaderSoup` type: a flat, single-layer environment for hosting multiple Reader-like contexts without exponential mtl class boilerplate.
* Direct context access: `askSoup` with $O(1)$ indexing.
* Row slicing: `filtering` with $O(K)$ flat array copy via `SubRow` evidence synthesis.
* MonadReader projection: `Spoon` exposing single contexts as standard `MonadReader` instances with local modification support.
* Context bridging: `SoupContext` with `picking`, `scooping`, and `pouring` for seamless integration with ReaderT-like monads.
* Modular runner composition: `ContextRunner`, `pickTopping`, `eatTopping`, `finishBroth`, and `consumeSoup`.
* Resource management: `Polytropos.ReaderSoup.Resource` providing `SoupContext InternalState ResourceT` and `MonadResource (ReaderSoup ctxs)` support.
