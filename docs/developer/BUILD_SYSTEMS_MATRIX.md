<!--
SPDX-License-Identifier: BSD-3-Clause
-->
# Build Systems Matrix: Cabal, Stack & Nix

**Status:** LIVING DEVELOPER GUIDE · Operational Tooling Specification  
**Canonicity:** Secondary to Cabal / GHC runtime reality (`DOC_STRATEGY.md` §4)  
**Applicability:** `polytropos-core`, `polytropos-plugin`, and ecosystem satellites  

---

## 1. Overview

`polytropos` supports reproducible compilation and test execution across three major Haskell build systems:
1. **Cabal (`cabal-install >= 3.10`):** The primary build driver and reference solver.
2. **Stack (`stack >= 2.13`):** Curated Stackage LTS snapshots and custom compiler overlays.
3. **Nix (`nix >= 2.18`, Flakes & Flake-less):** Hermetic, sandboxed package sets and reproducible developer shells.

All three build systems are deterministically verified across the entire compiler target matrix:
- **GHC 9.6.7:** LTS Baseline (`base-4.18.3.0`)
- **GHC 9.8.4:** Hackage Baseline (`base-4.19.2.0`)
- **GHC 9.10.3:** `ghc-internal` Split Baseline (`base-4.20.1.0`)
- **GHC 9.12.4:** Constructor Details & `FieldOcc` AST Baseline (`base-4.21.2.0`)
- **GHC 9.14.1:** Primary Toolchain (`base-4.22.0.0`)

---

## 2. Quick Command Reference

### A. Cabal

Cabal relies on multi-compiler project overlays in the root directory:

| Compiler Target | Build Command | Test Command |
| :--- | :--- | :--- |
| **GHC 9.14.1 (Default)** | `cabal build all` | `cabal test polytropos-core polytropos-plugin` |
| **GHC 9.12.4** | `cabal --project-file=cabal.project.ghc-9.12 build` | `cabal --project-file=cabal.project.ghc-9.12 test` |
| **GHC 9.10.3** | `cabal --project-file=cabal.project.ghc-9.10 build` | `cabal --project-file=cabal.project.ghc-9.10 test` |
| **GHC 9.8.4** | `cabal --project-file=cabal.project.ghc-9.8 build` | `cabal --project-file=cabal.project.ghc-9.8 test` |
| **GHC 9.6.7** | `cabal --project-file=cabal.project.ghc-9.6 build` | `cabal --project-file=cabal.project.ghc-9.6 test` |

### B. Stack

Stack relies on dedicated `stack-ghc-*.yaml` project files:

| Compiler Target | Resolver / Strategy | Test Command |
| :--- | :--- | :--- |
| **GHC 9.14.1 (Default)** | `stack.yaml` (`ghc-9.14.1` + extra-deps) | `stack test` |
| **GHC 9.12.4** | `stack-ghc-9.12.yaml` (`ghc-9.12.4` + extra-deps) | `stack test --stack-yaml stack-ghc-9.12.yaml` |
| **GHC 9.10.3** | `stack-ghc-9.10.yaml` (`ghc-9.10.3` + extra-deps) | `stack test --stack-yaml stack-ghc-9.10.yaml` |
| **GHC 9.8.4** | `stack-ghc-9.8.yaml` (`lts-23.12`) | `stack test --stack-yaml stack-ghc-9.8.yaml` |
| **GHC 9.6.7** | `stack-ghc-9.6.yaml` (`lts-22.44`) | `stack test --stack-yaml stack-ghc-9.6.yaml` |

### C. Nix (Flakes & Classic)

Nix provides native package outputs for supported Nixpkgs compilers and reproducible developer shells:

| Target / Workflow | Flake Command | Classic / Flake-less Command |
| :--- | :--- | :--- |
| **Build Core (GHC 9.6)** | `nix build .#ghc96-polytropos-core` | `nix-build default.nix -A core --argstr compiler ghc96` |
| **Build Plugin (GHC 9.6)** | `nix build .#ghc96-polytropos-plugin` | `nix-build default.nix -A plugin --argstr compiler ghc96` |
| **Build Core (GHC 9.8)** | `nix build .#ghc98-polytropos-core` | `nix-build default.nix -A core --argstr compiler ghc98` |
| **Build Plugin (GHC 9.8)** | `nix build .#ghc98-polytropos-plugin` | `nix-build default.nix -A plugin --argstr compiler ghc98` |
| **Dev Shell (GHC 9.10)** | `nix develop .#ghc910` | `nix-shell shell.nix --argstr compiler ghc910` |
| **Dev Shell (GHC 9.6)** | `nix develop .#ghc96` | `nix-shell shell.nix --argstr compiler ghc96` |
| **Default Shell (9.10)** | `nix develop` | `nix-shell` |

---

## 3. Architectural Invariants & Toolchain Interop

### A. The Internal GHC Plugin Lifecycle

`polytropos-plugin` is a compiler plugin (`-fplugin=Polytropos.Plugin`) exercised during compile time by its own smoke test suite (`polytropos-plugin-smoke`) and all satellite test suites.

- **In Cabal:** Cabal automatically detects intra-workspace package dependencies, builds the plugin shared library first, registers it into the temporary package environment, and passes it to downstream test compilations.
- **In Stack:** Stack resolves workspace packages in topological order. When compiling tests, Stack ensures the plugin is built and registered into the local snapshot database.
- **In Nix (`checkPhase`):** In isolated Nix sandboxes, `Setup test` executes tests in a clean environment where GHC subprocesses only see boot libraries. The test runner (`tests/smoke/Main.hs`) inspects `POLYTROPOS_TEST_GHC_FLAGS`. `flake.nix` and `default.nix` set:
  ```bash
  export POLYTROPOS_TEST_GHC_FLAGS="-package-db=$pkgDb -package-db=$PWD/dist/package.conf.inplace"
  ```
  allowing `checkGhcDiag`'s spawned `ghc -fno-code` subprocesses to cleanly locate and invoke `Polytropos.Plugin` and its dependencies.

### B. Dependency Bounds & Uncurated Compilers

GHC 9.12 and GHC 9.14 represent bleeding-edge compiler baselines that do not have curated Stackage snapshots or stable Nixpkgs package sets:

- **Stack Strategy:**
  Uses `snapshot: { compiler: ghc-X.Y.Z }` with `system-ghc: true` (pointing to the GHCup-managed toolchain) and `allow-newer: true`. Required test packages (`tasty`, `tasty-hunit`, `optparse-applicative`, `transformers-compat`, `primitive`) are specified explicitly in `extra-deps`.
- **Nix Strategy:**
  Nix provides direct derivations for GHC 9.6, 9.8, and 9.10 via `pkgs.haskell.packages`. For GHC 9.12 and 9.14, Nix developer shells bundle GHCup/system C libraries (`zlib`, `gmp`, `libffi`, `ncurses`) and `cabal-install`, allowing `cabal` to drive builds with complete binary portability.

---

## 4. Verification Gates

All three build systems must pass verification prior to release:

```bash
# 1. Cabal Matrix Verification (All 5 compilers)
cabal --project-file=cabal.project.ghc-9.6 test
cabal --project-file=cabal.project.ghc-9.8 test
cabal --project-file=cabal.project.ghc-9.10 test
cabal --project-file=cabal.project.ghc-9.12 test
cabal test polytropos-core polytropos-plugin

# 2. Stack Matrix Verification (All 5 compilers)
stack test --stack-yaml stack-ghc-9.6.yaml
stack test --stack-yaml stack-ghc-9.8.yaml
stack test --stack-yaml stack-ghc-9.10.yaml
stack test --stack-yaml stack-ghc-9.12.yaml
stack test

# 3. Nix Flake & Classic Derivation Verification
nix-build default.nix -A core --no-out-link
nix-build default.nix -A plugin --no-out-link
nix develop .#ghc96 -c ghc --version
```
