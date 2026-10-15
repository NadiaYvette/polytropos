#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
set -euo pipefail

echo "=== [task-11-verify] Verifying polytropos-aeson ==="

cabal test polytropos-aeson:test:polytropos-aeson-test

echo "=== [task-11-verify] PASS ==="
