#!/usr/bin/env bash
# ==============================================================================
# scripts/tasks/verify-milestone-t6.sh
# Deterministic verification gate for Milestone T6:
# Refactoring, Linters & Semantic Code Modernizers
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=== Verifying Milestone T6: Refactoring, Linters & Code Modernizers ==="

# 1. Verify existence of configuration files
echo "[Step 1] Checking configuration and ruleset files..."
test -f "${ROOT_DIR}/.hlint.yaml" || { echo "FAIL: .hlint.yaml missing"; exit 1; }
test -f "${ROOT_DIR}/rules/hlint/polytropos.yaml" || { echo "FAIL: rules/hlint/polytropos.yaml missing"; exit 1; }
test -f "${ROOT_DIR}/.stan.toml" || { echo "FAIL: .stan.toml missing"; exit 1; }
test -f "${ROOT_DIR}/rules/stan/POLYTROPOS_INSPECTIONS.md" || { echo "FAIL: rules/stan/POLYTROPOS_INSPECTIONS.md missing"; exit 1; }
test -f "${ROOT_DIR}/rules/retrie/record-dot.rules" || { echo "FAIL: record-dot.rules missing"; exit 1; }
test -f "${ROOT_DIR}/rules/retrie/batch-updates.rules" || { echo "FAIL: batch-updates.rules missing"; exit 1; }
test -f "${ROOT_DIR}/rules/retrie/variant-eliminators.rules" || { echo "FAIL: variant-eliminators.rules missing"; exit 1; }
test -f "${ROOT_DIR}/rules/retrie/open-adt-migration.rules" || { echo "FAIL: open-adt-migration.rules missing"; exit 1; }
test -f "${ROOT_DIR}/docs/tools/MODERNIZER_AND_LINTER_GUIDE.md" || { echo "FAIL: MODERNIZER_AND_LINTER_GUIDE.md missing"; exit 1; }
test -x "${ROOT_DIR}/bin/polytropos-modernize" || { echo "FAIL: bin/polytropos-modernize missing or not executable"; exit 1; }
echo "All configuration and rule files present."

# 2. Verify HLint rule triggering on fixtures
echo "[Step 2] Running HLint against ModernizerFixtures..."
FIXTURE="${ROOT_DIR}/rules/test/ModernizerFixtures.hs"
OUTPUT=$(hlint --hint="${ROOT_DIR}/.hlint.yaml" "${FIXTURE}" || true)

check_hint() {
    local name="$1"
    if echo "${OUTPUT}" | grep -q "${name}"; then
        echo "  [OK] Hint triggered: ${name}"
    else
        echo "  [FAIL] Expected hint not found: ${name}"
        echo "${OUTPUT}"
        exit 1
    fi
}

check_hint "Use OverloadedRecordDot"
check_hint "Avoid chained setField"
check_hint "Avoid repeated setField in foldl"
check_hint "Use peel for single-constructor elimination"
check_hint "Use eliminateUniform for handler dispatch"
check_hint "Redundant widenVariant"
check_hint "Use REC sugar instead of nested insertField"
check_hint "Use VAR pattern matching"

# 3. Verify bin/polytropos-modernize CLI options
echo "[Step 3] Testing bin/polytropos-modernize CLI options..."
"${ROOT_DIR}/bin/polytropos-modernize" --rules >/dev/null
"${ROOT_DIR}/bin/polytropos-modernize" --retrie-rules >/dev/null
"${ROOT_DIR}/bin/polytropos-modernize" --stan-spec >/dev/null

echo "=== Milestone T6 Verification PASSED ==="
exit 0
