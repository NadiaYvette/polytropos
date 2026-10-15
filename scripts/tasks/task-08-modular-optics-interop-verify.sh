#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
set -euo pipefail

echo "=== [task-08-verify] Verifying polytropos-optics ==="

# 1. Audit package and module
if [ ! -f "packages/polytropos-optics/polytropos-optics.cabal" ]; then
  echo "Error: packages/polytropos-optics/polytropos-optics.cabal does not exist!" >&2
  exit 1
fi
if [ ! -f "packages/polytropos-optics/src/Polytropos/Optics.hs" ]; then
  echo "Error: packages/polytropos-optics/src/Polytropos/Optics.hs does not exist!" >&2
  exit 1
fi
if ! grep -q "LabelOptic" packages/polytropos-optics/src/Polytropos/Optics.hs; then
  echo "Error: LabelOptic not implemented in Polytropos/Optics.hs!" >&2
  exit 1
fi

# 2. Run test suite
cabal test polytropos-optics:test:polytropos-optics-test

echo "=== [task-08-verify] PASS ==="
