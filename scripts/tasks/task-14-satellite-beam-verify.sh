#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
set -euo pipefail

echo "=== [task-14-verify] Verifying polytropos-beam ==="

cabal test polytropos-beam:test:polytropos-beam-test

echo "=== [task-14-verify] PASS ==="
