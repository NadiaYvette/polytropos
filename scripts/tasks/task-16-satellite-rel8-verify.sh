#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
set -euo pipefail

echo "=== [task-16-verify] Verifying polytropos-rel8 ==="

cabal test polytropos-rel8:test:polytropos-rel8-test

echo "=== [task-16-verify] PASS ==="
