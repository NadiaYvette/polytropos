# `.agents` — Assistant Environment Configuration

This directory offloads AI coding assistant configuration and environment rules from `AGENTS.md` to conserve agent context window space while maintaining strict development discipline.

- [`ATTRIBUTION.md`](ATTRIBUTION.md) — Git commit AI attribution schema (`Assisted-by: <Tool> (<Provider> / <Model>)`, `Orchestrated-by: <Engine>`).
- [`mcp.json`](mcp.json) — Model Context Protocol server configuration for `tricorder`, `contextful`, `codegraph`, `open-kioku`, and `haskell-language-server`.
- [`skills/`](skills/) — Specialized on-demand workflow skills (`tricorder`, `code-navigation`, `contextful`).
- [`docs/NEWBIE_GUIDE.md`](../docs/NEWBIE_GUIDE.md) — Token-conservation funnel, symbol jumping, and contributor quickstart.
- [`docs/MAINTAINER_GUIDE.md`](../docs/MAINTAINER_GUIDE.md) — Zero-contamination doctrine, maintainer invariants, and release hygiene.
