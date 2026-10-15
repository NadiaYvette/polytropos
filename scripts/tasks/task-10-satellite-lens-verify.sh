#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
set -euo pipefail

echo "=== [task-10-verify] Verifying polytropos-lens ==="

cabal test polytropos-lens:test:polytropos-lens-test

echo "=== [task-10-verify] PASS ==="
