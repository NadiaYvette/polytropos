#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
set -euo pipefail

echo "=== [task-18-verify] Verifying polytropos-openapi3 ==="

cabal test polytropos-openapi3:test:polytropos-openapi3-test

echo "=== [task-18-verify] PASS ==="
