#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail

echo "=== [task-10-verify] Verifying polytropos-lens ==="

cabal test polytropos-lens:test:polytropos-lens-test

echo "=== [task-10-verify] PASS ==="
