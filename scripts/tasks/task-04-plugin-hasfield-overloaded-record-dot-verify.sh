#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail

echo "=== [task-04-verify] Verifying HasField and OverloadedRecordDot ==="

# 1. Audit smoke tests
SMOKE_TEST="packages/polytropos-plugin/tests/smoke/Main.hs"
if ! grep -q "OverloadedRecordDot" "$SMOKE_TEST" && ! grep -q "HasField" "$SMOKE_TEST"; then
  echo "Error: OverloadedRecordDot or HasField not tested in $SMOKE_TEST!" >&2
  exit 1
fi

# 2. Run plugin smoke tests
cabal test polytropos-plugin:test:polytropos-plugin-smoke

echo "=== [task-04-verify] PASS ==="
