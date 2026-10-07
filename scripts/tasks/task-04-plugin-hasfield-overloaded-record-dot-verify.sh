#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail

echo "=== [task-04-verify] Verifying HasField and OverloadedRecordDot ==="

cabal test polytropos-plugin:test:polytropos-plugin-smoke

echo "=== [task-04-verify] PASS ==="
