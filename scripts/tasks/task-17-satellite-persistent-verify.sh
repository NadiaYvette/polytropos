#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
set -euo pipefail

echo "=== [task-17-verify] Verifying polytropos-persistent ==="

cabal test polytropos-persistent:test:polytropos-persistent-test

echo "=== [task-17-verify] PASS ==="
