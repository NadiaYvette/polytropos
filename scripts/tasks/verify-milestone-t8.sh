#!/usr/bin/env bash
# ==============================================================================
# scripts/tasks/verify-milestone-t8.sh
# Deterministic verification gate for Milestone T8:
# Source Formatters & Layout Engines
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=== Verifying Milestone T8: Source Formatters & Layout Engines ==="

# 1. Verify existence of configuration files and scripts
echo "[Step 1] Checking configuration and fixture files..."
test -f "${ROOT_DIR}/fourmolu.yaml" || { echo "FAIL: fourmolu.yaml missing"; exit 1; }
test -f "${ROOT_DIR}/.brittany.yaml" || { echo "FAIL: .brittany.yaml missing"; exit 1; }
test -f "${ROOT_DIR}/floskell.json" || { echo "FAIL: floskell.json missing"; exit 1; }
test -f "${ROOT_DIR}/formatters/test/FormatFixtures.hs" || { echo "FAIL: FormatFixtures.hs missing"; exit 1; }
test -f "${ROOT_DIR}/docs/tools/SOURCE_FORMATTERS_AND_LAYOUT_GUIDE.md" || { echo "FAIL: SOURCE_FORMATTERS_AND_LAYOUT_GUIDE.md missing"; exit 1; }
test -x "${ROOT_DIR}/bin/polytropos-format" || { echo "FAIL: bin/polytropos-format missing or not executable"; exit 1; }
echo "All configuration, fixture, and runner files present."

# 2. Verify Fourmolu formatting on open row fixtures
echo "[Step 2] Testing Fourmolu on open row syntax fixtures..."
if command -v fourmolu >/dev/null 2>&1; then
  fourmolu --config="${ROOT_DIR}/fourmolu.yaml" "${ROOT_DIR}/formatters/test/FormatFixtures.hs" >/dev/null
  echo "  [OK] Fourmolu formatted open row fixtures cleanly"
else
  echo "  [SKIP] fourmolu binary not found in PATH"
fi

# 3. Verify Ormolu formatting on open row fixtures
echo "[Step 3] Testing Ormolu on open row syntax fixtures..."
if command -v ormolu >/dev/null 2>&1; then
  ormolu "${ROOT_DIR}/formatters/test/FormatFixtures.hs" >/dev/null
  echo "  [OK] Ormolu formatted open row fixtures cleanly"
else
  echo "  [SKIP] ormolu binary not found in PATH"
fi

# 4. Verify Brittany formatting on open row fixtures
echo "[Step 4] Testing Brittany on open row syntax fixtures..."
if command -v brittany >/dev/null 2>&1; then
  brittany --config-file="${ROOT_DIR}/.brittany.yaml" "${ROOT_DIR}/formatters/test/FormatFixtures.hs" >/dev/null
  echo "  [OK] Brittany formatted open row fixtures cleanly"
else
  echo "  [SKIP] brittany binary not found in PATH"
fi

# 5. Verify Floskell configuration JSON syntax
echo "[Step 5] Validating floskell.json layout configuration..."
python3 -c "import json; d = json.load(open('${ROOT_DIR}/floskell.json')); assert 'formatting' in d and 'extensions' in d"
echo "  [OK] floskell.json structure and syntax validated"

# 6. Run bin/polytropos-format --fixtures
echo "[Step 6] Running bin/polytropos-format CLI..."
"${ROOT_DIR}/bin/polytropos-format" --fixtures >/dev/null
echo "  [OK] bin/polytropos-format --fixtures passed"

# 7. Verify core tests remain green
echo "[Step 7] Running core test suite..."
cabal test polytropos-core:test:polytropos-core-test >/dev/null
echo "  [OK] polytropos-core-test suite passed"

echo "=== Milestone T8 Verification PASSED ==="
