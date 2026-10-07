#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail

echo "=== [task-07-verify] Verifying polytropos-generics ==="

cabal test polytropos-generics:test:polytropos-generics-test

echo "=== [task-07-verify] PASS ==="
