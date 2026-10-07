#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail

echo "=== [task-01-verify] Verifying setFieldAt CoW implementation ==="

TARGET_FILE="packages/polytropos-core/src/Polytropos/Core.hs"

# 1. Audit: Ensure toListSlots is NOT called inside setFieldAt
if grep -A 10 "setFieldAt ::" "$TARGET_FILE" | grep -q "toListSlots"; then
  echo "Error: setFieldAt still references toListSlots!" >&2
  exit 1
fi

# 2. Audit: Ensure thawSmallArray and runSmallArray are used
if ! grep -A 10 "setFieldAt ::" "$TARGET_FILE" | grep -q "thawSmallArray"; then
  echo "Error: setFieldAt does not use thawSmallArray!" >&2
  exit 1
fi

# 3. Test verification
cabal test polytropos-core:test:polytropos-core-test

echo "=== [task-01-verify] PASS ==="
