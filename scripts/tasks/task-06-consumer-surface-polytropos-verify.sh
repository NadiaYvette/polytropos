#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail

echo "=== [task-06-verify] Verifying consumer-facing surface in Polytropos ==="

cabal test all

echo "=== [task-06-verify] PASS ==="
