#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-POLY-MERGE-001B Verification Gate] ==="
bin/polytropos-verify
cabal v2-test polytropos-plugin
echo "=== [TP-POLY-MERGE-001B Verification Gate PASSED] ==="
