#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-POLY-MERGE-001A Verification Gate] ==="
bin/polytropos-verify
cabal v2-test polytropos-core
echo "=== [TP-POLY-MERGE-001A Verification Gate PASSED] ==="
