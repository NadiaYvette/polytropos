#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail

echo "=== [task-17-verify] Verifying polytropos-persistent ==="

cabal test polytropos-persistent:test:polytropos-persistent-test

echo "=== [task-17-verify] PASS ==="
