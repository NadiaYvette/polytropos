# Polytropos Rules & Tool Configuration Library

This directory provides a curated, production-tested suite of configuration profiles, linters, static analysis checks, and refactoring rules for downstream developers using `polytropos`.

---

## 1. Directory Structure

```
rules/
├── formatters/              # Code formatter configurations preserving row syntax
│   ├── fourmolu.yaml        # Recommended Fourmolu profile (leading comma, record alignment, fixities)
│   ├── .brittany.yaml       # Brittany configuration with GHC extension forwarding
│   ├── floskell.json        # Floskell profile with custom penalties and fixities
│   └── ormolu.md            # Ormolu compatibility notes and CLI usage
├── hlint/                   # HLint rule definitions & modernizers
│   ├── polytropos.yaml      # 8 semantic and performance lint rules
│   └── .hlint.yaml          # Downstream project-level template importing polytropos.yaml
├── retrie/                  # Retrie automated equational rewrite scripts
│   ├── record-dot.rules     # Modernize getField to record.dot
│   ├── batch-updates.rules  # Convert chained setField to runMRep
│   ├── variant-eliminators.rules # Convert case cascades to eliminateUniform / peel
│   └── open-adt-migration.rules  # Migrate nominal records to open rows
├── stan/                    # Stan static analysis guardrails
│   ├── .stan.toml           # Workspace inspection configuration
│   └── POLYTROPOS_INSPECTIONS.md # Inspection catalog (STAN-P01 through STAN-P04)
├── tricorder/               # Continuous compilation daemon templates
│   └── .tricorder.yaml      # Configuration template for background multi-repl
└── test/                    # Verification fixtures
    └── ModernizerFixtures.hs# Test cases verifying all linter and rewrite rules
```

---

## 2. Why Formatter & Linter Repositories Don't Need Custom Forks

A common question for developers adopting `polytropos` is:
> *“Do I need to maintain custom forks of Fourmolu, Ormolu, Brittany, or Stan to format and analyze code using open row types?”*

**No.** Unlike compiler-level integrations (such as GHC plugins or language servers), Haskell formatters and linters operate on standard GHC syntax trees:
1. **Standard GHC Syntax:** `polytropos` relies exclusively on standard Haskell language extensions (`-XDataKinds`, `-XTypeOperators`, `-XOverloadedRecordDot`, `-XTypeApplications`).
2. **Configuration Profiles Over Forking:** Upstream formatters like Fourmolu or Floskell handle row types properly when configured with the correct comma style (`leading`), list indentation (`indentListSpecial`), and operator fixities (`infixr 5 :=`, `infixr 5 .==`, `infixl 8 .#`).
3. **Zero-Config Compatibility:** Ormolu natively parses and formats GHC 9.2+ record-dot syntax and promoted type lists without requiring any modification.

Rather than maintaining forks, copy the configuration files from `rules/` directly into your repository.

---

## 3. How Downstream Developers Adopt These Rules

### A. Code Formatting
- **Using Fourmolu:** Copy `rules/formatters/fourmolu.yaml` to your project root as `fourmolu.yaml`.
- **Using Brittany:** Copy `rules/formatters/.brittany.yaml` to your project root as `.brittany.yaml`.
- **Using Floskell:** Copy `rules/formatters/floskell.json` to your project root as `floskell.json`.
- **Using Ormolu:** Run `ormolu --mode inplace $(find src test -name "*.hs")` (no config file required).

### B. Linters & Performance Guardrails
- **Using HLint:** Copy `rules/hlint/polytropos.yaml` into your project and add `- import: rules/hlint/polytropos.yaml` to your `.hlint.yaml`. This alerts your team when code performs inefficient chained Copy-on-Write updates or fragile cascading variant matches.
- **Using Stan:** Copy `rules/stan/.stan.toml` to your project root as `.stan.toml` to catch memory regressions and dead row fields.

### C. Automated Refactoring
- **Using Retrie:** Run `retrie --rule rules/retrie/record-dot.rules` to automatically modernize `getField` calls into `OverloadedRecordDot` syntax across your repository.

### D. Continuous Compilation & Diagnostics
- **Using Tricorder:** Copy `rules/tricorder/.tricorder.yaml` to your project root as `.tricorder.yaml`, update package target names, and run `tricorder start` to enjoy $<50$ token compile diagnostics.
