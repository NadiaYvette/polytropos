#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail

echo "=== [task-14-verify] Verifying polytropos-beam ==="

cabal test polytropos-beam:test:polytropos-beam-test

echo "=== [task-14-verify] PASS ==="
