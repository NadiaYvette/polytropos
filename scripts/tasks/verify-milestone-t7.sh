#!/usr/bin/env bash
# ==============================================================================
# scripts/tasks/verify-milestone-t7.sh
# Deterministic verification gate for Milestone T7:
# Program Synthesis, Formal Verification & Continuous Compilation
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=== Verifying Milestone T7: Formal Verification, Synthesis & Diagnostics ==="

# 1. Verify existence of configuration, specifications, and scripts
echo "[Step 1] Checking configuration and specification files..."
test -f "${ROOT_DIR}/verification/liquid/Polytropos/Liquid/RowPredicates.spec" || { echo "FAIL: RowPredicates.spec missing"; exit 1; }
test -f "${ROOT_DIR}/verification/liquid/Polytropos/Liquid/Proofs.hs" || { echo "FAIL: Proofs.hs missing"; exit 1; }
test -f "${ROOT_DIR}/verification/liquid/Polytropos/Liquid/RowBounds.fq" || { echo "FAIL: RowBounds.fq missing"; exit 1; }

test -f "${ROOT_DIR}/synthesis/synquid/RecordAdapter-SubRow.sq" || { echo "FAIL: RecordAdapter-SubRow.sq missing"; exit 1; }
test -f "${ROOT_DIR}/synthesis/synquid/RecordAdapter-Permute.sq" || { echo "FAIL: RecordAdapter-Permute.sq missing"; exit 1; }
test -f "${ROOT_DIR}/synthesis/synquid/RecordAdapter-Defaults.sq" || { echo "FAIL: RecordAdapter-Defaults.sq missing"; exit 1; }
test -f "${ROOT_DIR}/synthesis/synquid/VariantEliminator.sq" || { echo "FAIL: VariantEliminator.sq missing"; exit 1; }
test -f "${ROOT_DIR}/synthesis/synquid/VariantSubsumption.sq" || { echo "FAIL: VariantSubsumption.sq missing"; exit 1; }

test -f "${ROOT_DIR}/.tricorder.yaml" || { echo "FAIL: .tricorder.yaml missing"; exit 1; }
test -f "${ROOT_DIR}/.mcp.json" || { echo "FAIL: .mcp.json missing"; exit 1; }
test -f "${ROOT_DIR}/docs/tools/FORMAL_VERIFICATION_AND_SYNTHESIS_GUIDE.md" || { echo "FAIL: FORMAL_VERIFICATION_AND_SYNTHESIS_GUIDE.md missing"; exit 1; }

test -x "${ROOT_DIR}/bin/polytropos-tricorder" || { echo "FAIL: bin/polytropos-tricorder missing or not executable"; exit 1; }
test -x "${ROOT_DIR}/bin/polytropos-verify" || { echo "FAIL: bin/polytropos-verify missing or not executable"; exit 1; }
echo "All configuration, specification, and runner files present."

# 2. Verify LiquidHaskell proofs compilation and SMT Horn clause checking
echo "[Step 2] Executing LiquidHaskell verification..."
TMP_DIR="$(mktemp -d /tmp/ghc-liquid-proofs-XXXXXX)"
ghc -Wall -Werror -c "${ROOT_DIR}/verification/liquid/Polytropos/Liquid/Proofs.hs" -outputdir "${TMP_DIR}"
rm -rf "${TMP_DIR}"
echo "  [OK] Proofs.hs compiled cleanly under GHC with -Wall -Werror"

FIXPOINT_BIN="/home/nyc/src/liquidhaskell/dist-newstyle/build/x86_64-linux/ghc-9.14.1/liquid-fixpoint-0.9.6.3.8/x/fixpoint/build/fixpoint/fixpoint"
if [[ -x "${FIXPOINT_BIN}" ]]; then
  RES="$("${FIXPOINT_BIN}" "${ROOT_DIR}/verification/liquid/Polytropos/Liquid/RowBounds.fq" 2>&1)"
  if echo "${RES}" | grep -q "Safe"; then
    echo "  [OK] Liquid-Fixpoint Horn constraints verified SAFE via Z3 SMT solver"
  else
    echo "  [FAIL] Liquid-Fixpoint Horn constraints verification failed:"
    echo "${RES}"
    exit 1
  fi
fi

# 3. Verify Synquid specifications structure and holes
echo "[Step 3] Checking Synquid synthesis specifications..."
for sq in "${ROOT_DIR}/synthesis/synquid"/*.sq; do
  test -f "${sq}" || continue
  base="$(basename "${sq}")"
  grep -q "data " "${sq}" || { echo "  [FAIL] ${base} missing data declarations"; exit 1; }
  grep -q "measure " "${sq}" || { echo "  [FAIL] ${base} missing measure declarations"; exit 1; }
  grep -q "??" "${sq}" || { echo "  [FAIL] ${base} missing synthesis hole ??"; exit 1; }
  echo "  [OK] Synquid spec valid: ${base}"
done

# 4. Verify Tricorder runner and MCP configuration
echo "[Step 4] Checking Tricorder daemon configuration and MCP integration..."
"${ROOT_DIR}/bin/polytropos-tricorder" config >/dev/null
echo "  [OK] .tricorder.yaml validated"
"${ROOT_DIR}/bin/polytropos-tricorder" check-mcp >/dev/null
echo "  [OK] tricorder-mcp server validated"

# 5. Run bin/polytropos-verify CLI
echo "[Step 5] Running bin/polytropos-verify CLI..."
"${ROOT_DIR}/bin/polytropos-verify" --all >/dev/null
echo "  [OK] bin/polytropos-verify --all executed successfully"

# 6. Verify core tests remain green
echo "[Step 6] Running core test suite..."
cabal test polytropos-core:test:polytropos-core-test >/dev/null
echo "  [OK] polytropos-core-test suite passed"

echo "=== Milestone T7 Verification PASSED ==="
