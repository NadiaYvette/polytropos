#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
set -euo pipefail

echo "=== [task-09-verify] Verifying polytropos-microlens ==="

cabal test polytropos-microlens:test:polytropos-microlens-test

echo "=== [task-09-verify] PASS ==="
