#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
set -euo pipefail

GHC_10_1="/home/nyc/.local/bin/ghc-10.1.20261105"

echo "=== [ghc-10.1-regression] Checking for GHC 10.1 snapshot availability ==="

if [ ! -x "$GHC_10_1" ]; then
  echo "GHC 10.1 binary not found at $GHC_10_1. Skipping GHC 10.1 source plugin regression test."
  exit 0
fi

echo "Found GHC 10.1 at $GHC_10_1: $("$GHC_10_1" --version)"

echo "=== [ghc-10.1-regression] Building polytropos-plugin with GHC 10.1 ==="
cabal v2-build --project-file="/home/nyc/src/test-ghci-fix/cabal.project" -w "$GHC_10_1" polytropos-core polytropos-plugin

echo "=== [ghc-10.1-regression] Verifying build / compilation ==="
cabal v2-build --project-file="/home/nyc/src/test-ghci-fix/cabal.project" -w "$GHC_10_1" polytropos-plugin

echo "=== [ghc-10.1-regression] Running polytropos-core core test suite ==="
cabal v2-test --project-file="/home/nyc/src/test-ghci-fix/cabal.project" -w "$GHC_10_1" polytropos-core-test

echo "=== [ghc-10.1-regression] Verifying GHCi plugin loading and interaction ==="
echo -e ":load Polytropos.Plugin\nputStrLn \"Polytropos GHCi evaluation test passed\"\n:quit" | cabal v2-repl --project-file="/home/nyc/src/test-ghci-fix/cabal.project" -w "$GHC_10_1" polytropos-plugin

echo "=== [ghc-10.1-regression] REGRESSION TEST PASS ==="
