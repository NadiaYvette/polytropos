#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
set -euo pipefail

echo "=== [task-05-verify] Verifying OverloadedLabels and OverloadedRecordUpdate ==="

# 1. Audit exports
if ! grep -q "IsLabel" packages/polytropos-core/src/Polytropos/Core.hs; then
  echo "Error: IsLabel not imported or implemented in Core.hs!" >&2
  exit 1
fi
if ! grep -q "data Field" packages/polytropos-core/src/Polytropos/Core.hs; then
  echo "Error: Field witness not defined in Core.hs!" >&2
  exit 1
fi

# 2. Run all tests
cabal test all

echo "=== [task-05-verify] PASS ==="
