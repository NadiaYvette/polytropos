#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail

echo "=== [task-15-verify] Verifying polytropos-hasql ==="

cabal test polytropos-hasql:test:polytropos-hasql-test

echo "=== [task-15-verify] PASS ==="
