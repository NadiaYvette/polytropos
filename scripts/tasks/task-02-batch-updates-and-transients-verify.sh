#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
set -euo pipefail

echo "=== [task-02-verify] Verifying setFieldsAt and MRep transients ==="

TARGET_FILE="packages/polytropos-core/src/Polytropos/Core.hs"

# 1. Audit exports
for sym in "setFieldsAt" "MRep" "modifyRep" "setFieldSumAt"; do
  if ! grep -q "$sym" "$TARGET_FILE"; then
    echo "Error: $sym not found in $TARGET_FILE!" >&2
    exit 1
  fi
done

# 2. Test verification
cabal test polytropos-core:test:polytropos-core-test

echo "=== [task-02-verify] PASS ==="
