# `.agents` — Assistant Environment Configuration & Subdivided Rules

This directory offloads AI coding assistant configuration and environment rules from [`AGENTS.md`](../AGENTS.md) into a subdivided, progressive-disclosure form to conserve agent context window space while maintaining strict development discipline.

## 1. Subdivided Rules Catalog (`rules/`)

Hierarchical and domain-specific rules discovered and loaded by AI assistants (`Antigravity`, `Claude Code`, `Cursor`, `Aider`):

- [`rules/commit-attribution.md`](rules/commit-attribution.md) — Git commit authoring, RFC 2822 `Assisted-by:` trailers, DCO certification boundaries, and hook enforcement.
- [`rules/code-navigation.md`](rules/code-navigation.md) — Progressive disclosure funnel (`./tags` -> `ast-grep` -> surgical `view_file` slices) to prevent context pollution.
- [`rules/compiler-verification.md`](rules/compiler-verification.md) — Low-token compiler diagnostics via `tricorder status --json` (<50 tokens) and the zero-contamination doctrine.
- [`rules/documentation-precedence.md`](rules/documentation-precedence.md) — `DOC_STRATEGY.md` §4 precedence rule ("code wins at runtime, notes corrected regardless") and the two-file session loop (`PLAN.md` + `STATE.md`).
- [`rules/plugin-invariants.md`](rules/plugin-invariants.md) — TcPlugin literal index evidence, Core AST dictionary synthesis, and avoiding selector mangling (`$sel:...`).
- [`../docs/notes/REVIEWER_WFU_ARGUMENT.md`](../docs/notes/REVIEWER_WFU_ARGUMENT.md) — source-mapping and well-foundedness-argument structure for the row/role judgement draft, including which external sources are in, which are out, and why.

## 2. Infrastructure & Tooling Configurations

- [`ATTRIBUTION.md`](ATTRIBUTION.md) — Quick reference for git commit AI attribution trailers.
- [`mcp.json`](mcp.json) — Model Context Protocol server configuration for `tricorder`, `contextful`, `codegraph`, `open-kioku`, and `haskell-language-server`.
- [`skills/`](skills/) — Specialized on-demand workflow skills (`tricorder`, `code-navigation`, `contextful`).
- [`docs/NEWBIE_GUIDE.md`](../docs/NEWBIE_GUIDE.md) — Token-conservation funnel, symbol jumping, and contributor quickstart.
- [`docs/MAINTAINER_GUIDE.md`](../docs/MAINTAINER_GUIDE.md) — Zero-contamination doctrine, maintainer invariants, and release hygiene.
