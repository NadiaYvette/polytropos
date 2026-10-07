#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail

echo "=== [task-12-verify] Verifying polytropos-cbor ==="

cabal test polytropos-cbor:test:polytropos-cbor-test

echo "=== [task-12-verify] PASS ==="
