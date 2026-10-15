#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
set -euo pipefail

echo "=== [task-19-verify] Verifying polytropos-quickcheck ==="

cabal test polytropos-quickcheck:test:polytropos-quickcheck-test

echo "=== [task-19-verify] PASS ==="
