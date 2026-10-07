#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail

echo "=== [task-18-verify] Verifying polytropos-openapi3 ==="

cabal test polytropos-openapi3:test:polytropos-openapi3-test

echo "=== [task-18-verify] PASS ==="
