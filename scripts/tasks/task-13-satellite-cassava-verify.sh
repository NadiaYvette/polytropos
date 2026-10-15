#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
set -euo pipefail

echo "=== [task-13-verify] Verifying polytropos-cassava ==="

cabal test polytropos-cassava:test:polytropos-cassava-test

echo "=== [task-13-verify] PASS ==="
