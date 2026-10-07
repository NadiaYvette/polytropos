#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail

echo "=== [task-03-verify] Verifying RowEqSum and RowShowSum in plugin ==="

# 1. Audit smoke tests
SMOKE_TEST="packages/polytropos-plugin/tests/smoke/Main.hs"
if ! grep -q "RowEqSum" "$SMOKE_TEST"; then
  echo "Error: RowEqSum not tested in $SMOKE_TEST!" >&2
  exit 1
fi
if ! grep -q "RowShowSum" "$SMOKE_TEST"; then
  echo "Error: RowShowSum not tested in $SMOKE_TEST!" >&2
  exit 1
fi

# 2. Run plugin smoke tests
cabal test polytropos-plugin:test:polytropos-plugin-smoke

echo "=== [task-03-verify] PASS ==="
