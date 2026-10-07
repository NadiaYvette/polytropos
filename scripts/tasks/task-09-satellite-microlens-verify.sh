#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail

echo "=== [task-09-verify] Verifying polytropos-microlens ==="

cabal test polytropos-microlens:test:polytropos-microlens-test

echo "=== [task-09-verify] PASS ==="
