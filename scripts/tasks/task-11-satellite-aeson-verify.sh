#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail

echo "=== [task-11-verify] Verifying polytropos-aeson ==="

cabal test polytropos-aeson:test:polytropos-aeson-test

echo "=== [task-11-verify] PASS ==="
