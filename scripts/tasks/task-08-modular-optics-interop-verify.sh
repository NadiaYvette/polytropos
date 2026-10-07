#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail

echo "=== [task-08-verify] Verifying polytropos-optics ==="

cabal test polytropos-optics:test:polytropos-optics-test

echo "=== [task-08-verify] PASS ==="
