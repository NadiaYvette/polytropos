#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail

echo "=== [task-03-verify] Verifying RowEqSum and RowShowSum in plugin ==="

# Run plugin smoke tests
cabal test polytropos-plugin:test:polytropos-plugin-smoke

echo "=== [task-03-verify] PASS ==="
