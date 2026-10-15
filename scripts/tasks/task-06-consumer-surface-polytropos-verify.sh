#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
set -euo pipefail

echo "=== [task-06-verify] Verifying consumer-facing surface in Polytropos ==="

# 1. Audit Polytropos module
TARGET="packages/polytropos-core/src/Polytropos.hs"
if [ ! -f "$TARGET" ]; then
  echo "Error: $TARGET does not exist!" >&2
  exit 1
fi
if ! grep -q "type Record" "$TARGET"; then
  echo "Error: type Record not defined in $TARGET!" >&2
  exit 1
fi
if ! grep -q "type Variant" "$TARGET"; then
  echo "Error: type Variant not defined in $TARGET!" >&2
  exit 1
fi

# 2. Run all tests
cabal test all

echo "=== [task-06-verify] PASS ==="
