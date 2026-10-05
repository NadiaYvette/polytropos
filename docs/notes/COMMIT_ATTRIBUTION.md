<!--
SPDX-License-Identifier: BSD-3-Clause
-->
# Commit attribution

One convention for AI attribution, shared by every assistant, REPL,
orchestrator or framework that touches this repository.

## The rule

```
Assisted-by: LLM [TOOL1] [TOOL2]
```

The trailing tokens are optional **analysis** tools — `coccinelle`, `sparse`,
`smatch`, `clang-tidy`. The value itself is always the literal word `LLM`.

This is the Linux kernel's rule, from
`Documentation/process/coding-assistants.rst`. It is deliberately
assistant-agnostic.

## Why the assistant is not named

Until 3 August 2026 the kernel's documented format read
`Assisted-by: Claude:claude-3-opus coccinelle sparse` — agent name plus model
version. Christian Brauner's patch, merged that day, deleted both fields. The
stated reason: the requirement "provides free advertising to proprietary
software companies while adding little or no useful information."

Naming the assistant is therefore wrong here, not merely verbose. The hook
rejects it. What a reviewer actually needs to know — that a machine was in the
loop, and which commit to scrutinise — is preserved.

### Which assistant, then?

The trailer answers "was a machine involved?", not "which one?" So when the
*identity* of the assistant is the information a reader needs, it goes in the
document, not the commit. That is the case for imported transcripts: an
archived conversation is one assistant's work by definition, and naming it in
the provenance header is what makes the archive honest about what it holds.

Concretely: `docs/transcripts/gemini-*.md` name Gemini in their provenance
header and carry `Assisted-by: LLM` on the commit that imported them. The
trailer describes *that commit*; the header describes *the archived material*.
Keep the two separate and neither has to bend.

## Three trailers that are wrong

| Trailer | Why not |
| --- | --- |
| `Co-authored-by: <assistant>` | Claims authorship. An assistant cannot be a co-author. |
| `Co-developed-by: <assistant>` | Same claim, softer wording. Still wrong. |
| `Signed-off-by: <assistant>` | Certifies the Developer Certificate of Origin. The kernel: "AI agents MUST NOT add Signed-off-by tags. Only humans can legally certify the Developer Certificate of Origin." |

`Signed-off-by:` with your own name is correct and unaffected.

A robot-emoji footer (`🤖 Generated with … 🤖`) is also rejected. It carries no
information, and some upstreams (QEMU's `checkpatch.pl` among them) now refuse
it outright.

## Enforcement

Four pieces, all opt-in locally, because a repository cannot ship git config:

```sh
git config core.hooksPath .githooks          # enforce on commit
git config commit.template .gitmessage       # guidance while writing
git config trailer.Assisted-by.cmd 'echo LLM' # stamp with --trailer Assisted-by
git config commit.warnMissingAssistedBy true  # opt-in reminder; off by default
```

Then either hand-write the trailer or stamp it:

```sh
git commit --trailer Assisted-by -m "..."
```

Two behaviours of `trailer.<key>.cmd` that will bite you if you forget them,
both found by experiment rather than by reading the docs:

- The command's output is the trailer **value**, not a whole trailer line.
  `echo "Assisted-by: LLM"` produces `Assisted-by: Assisted-by: LLM`. Use
  `echo LLM`.
- The command is **prepended** to an existing value of the same trailer, so
  re-running it over `Assisted-by: LLM coccinelle` yields
  `Assisted-by: LLM LLM coccinelle`. If a trailer is already present, add
  `--if-exists doNothing`.

The hook parses trailers with `git interpret-trailers --parse`, which implies
`--only-input`; that deliberately bypasses the `trailer.<key>.cmd` config so the
hook inspects what was literally written rather than what git would rewrite.

## Attribution inside documents

Imported material records its own origin. A transcript's provenance header
names the assistant, the venue and the date; a port's `LICENSE` names the
upstream holders. See `PROVENANCE.md` for the licensing half and
`docs/registers/PACKAGES.md` for the register.

This is not an exception to the rule above — it is where the rule points when
the identity matters. The trailer says a machine helped write the diff. The
header says whose words are being preserved. Neither tries to do both.

## Scope

The hook checks attribution only. It does not require a trailer: a commit
written entirely by a human must stay committable, so absence is exit 0 unless
`commit.warnMissingAssistedBy` is set. Nothing here detects or forbids AI use —
it standardises the disclosure when there is something to disclose.

## Cross-references

- `AGENTS.md` advisory 4 — the one-line rule agents are pointed at.
- `.gitmessage` — the template; `git commit` strips its `#` lines.
- `.githooks/commit-msg` — the enforcement, with the rationale in its header.