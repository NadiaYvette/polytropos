#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail

echo "=== [task-13-verify] Verifying polytropos-cassava ==="

cabal test polytropos-cassava:test:polytropos-cassava-test

echo "=== [task-13-verify] PASS ==="
