<!--
SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
-->
# Commit Attribution

Status: POLICY · v2.0 · 2026-10-07 — updated to adopt the canonical `sarutahiko` AI attribution schema.  
Related: `sarutahiko/docs/notes/INFRASTRUCTURE.md` §12, `AGENTS.md` advisory 4, `.githooks/commit-msg`, `.gitmessage`, `.agents/README.md`.

---

## 1. The Attribution Convention

Commits assisted by AI coding assistants or orchestrators use standard RFC 2822 git trailers:

```
Assisted-by: <Tool> (<Provider> / <Model>)
Orchestrated-by: <Engine>
```

### Examples
- **Assisted by model with explicit provider:**
  ```
  Assisted-by: Antigravity (Anthropic / claude-4.6-opus)
  ```
  ```
  Assisted-by: Antigravity (Google / gemini-3.8-pro)
  ```
  ```
  Assisted-by: Freebuff (Upstage AI / Solar Pro 4)
  ```
- **Assisted where model is unspecified or varied across sessions:**
  ```
  Assisted-by: Freebuff
  ```
- **Orchestrated by a workflow/task engine:**
  ```
  Assisted-by: Utai Native (mistral/codestral-latest)
  Orchestrated-by: Yamaarashi Flow Task Runner
  ```

---

## 2. Rationale & Lineage

This attribution schema is inherited directly from the `sarutahiko` program (`INFRASTRUCTURE.md` §12 and `AGENTS.md` advisory 3).

In multi-agent and heterogeneous developer environments, attribution serves critical engineering and audit functions:
1. **Provenance & Auditability:** Distinguishing which tool driver and underlying model generated or assisted code facilitates diagnosing model-specific regressions, hallucinations, or stylistic quirks.
2. **Orchestrator Distinction:** Disentangles the *coding assistant model* (`Assisted-by:`) from the *workflow orchestration engine* (`Orchestrated-by:`).
3. **Accuracy without Misattribution:** Identifies the actual tool and provider in use rather than generic or misattributed labels.

---

## 3. Disallowed Trailers

| Trailer | Why Forbidden |
|---|---|
| `Co-authored-by: <AI-Tool>` | Claims legal co-authorship. An AI tool cannot hold copyright or certify the Developer Certificate of Origin (DCO). |
| `Co-developed-by: <AI-Tool>` | Same legal defect as `Co-authored-by`. |
| `Signed-off-by: <AI-Tool>` | Certifies the DCO. Only a human author can legally sign off on a commit. |
| Robot emojis (`🤖 Generated with ...`) | Decoration carrying no structured semantic metadata; rejected by upstream tooling. |

*Note:* `Signed-off-by:` with a human committer's name and email is fully permitted and unaffected.

---

## 4. Repository Enforcement

The attribution convention is supported and enforced through:

1. **Git Message Template (`.gitmessage`):**
   Provides instructions and trailer format directly in the commit editor.
   ```sh
   git config commit.template .gitmessage
   ```
2. **Git Commit Hook (`.githooks/commit-msg`):**
   Validates trailer syntax, ensures no AI tools appear in `Co-authored-by:` or `Signed-off-by:`, verifies presence of valid `Assisted-by:` trailers on assisted commits, and permits optional `Orchestrated-by:`.
   ```sh
   git config core.hooksPath .githooks
   ```
3. **Agent Guidance (`AGENTS.md` & `.agents/`):**
   Orientation projection pointing assistant sessions to this policy while keeping root context footprint minimal.
