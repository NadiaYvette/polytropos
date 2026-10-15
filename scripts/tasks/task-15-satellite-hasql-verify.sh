#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
set -euo pipefail

echo "=== [task-15-verify] Verifying polytropos-hasql ==="

cabal test polytropos-hasql:test:polytropos-hasql-test

echo "=== [task-15-verify] PASS ==="
