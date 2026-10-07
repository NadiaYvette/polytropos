#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail

echo "=== [task-07-verify] Verifying polytropos-generics ==="

# 1. Audit package and module
if [ ! -f "packages/polytropos-generics/polytropos-generics.cabal" ]; then
  echo "Error: packages/polytropos-generics/polytropos-generics.cabal does not exist!" >&2
  exit 1
fi
if [ ! -f "packages/polytropos-generics/src/Polytropos/Generics.hs" ]; then
  echo "Error: packages/polytropos-generics/src/Polytropos/Generics.hs does not exist!" >&2
  exit 1
fi
if ! grep -q "class Generic" packages/polytropos-generics/src/Polytropos/Generics.hs; then
  echo "Error: class Generic not defined in Polytropos/Generics.hs!" >&2
  exit 1
fi

# 2. Run test suite
cabal test polytropos-generics:test:polytropos-generics-test

echo "=== [task-07-verify] PASS ==="
