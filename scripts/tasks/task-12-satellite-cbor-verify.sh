#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
set -euo pipefail

echo "=== [task-12-verify] Verifying polytropos-cbor ==="

cabal test polytropos-cbor:test:polytropos-cbor-test

echo "=== [task-12-verify] PASS ==="
