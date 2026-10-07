#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail

echo "=== [task-05-verify] Verifying OverloadedLabels and OverloadedRecordUpdate ==="

cabal test all

echo "=== [task-05-verify] PASS ==="
