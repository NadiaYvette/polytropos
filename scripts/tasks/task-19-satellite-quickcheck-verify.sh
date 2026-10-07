#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail

echo "=== [task-19-verify] Verifying polytropos-quickcheck ==="

cabal test polytropos-quickcheck:test:polytropos-quickcheck-test

echo "=== [task-19-verify] PASS ==="
