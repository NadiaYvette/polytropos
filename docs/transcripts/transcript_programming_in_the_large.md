# Transcript: Setting up a project skeleton for autonomous programming in the large

## Participants
- User (Nadia)
- Hermes Agent

## Summary
The user proposes to use the existing structures of `~/src/sarutahiko/` and `~/src/polytropos/` as precedents for initializing a new project `~/src/programming-in-the-large/` that will host research and implementation of theoretical frameworks for autonomous programming at scale by AI coding agents. The discussion enumerates a range of formalisms and tools that could be modeled or integrated, and suggests where relevant documentation already exists.

## Precedents to emulate

### Sarutahiko
- Provides a Haskell library for effect‑based workflow orchestration (`keiro-ops`, `keiro-ops-mcp`).
- Includes a `packages/` directory with composable components (keiro, hashigakari, yamaarashi, etc.).
- Demonstrates a clear separation between the core language (`src/`), tooling (`bin/`), and documentation (`docs/`).
- Uses a Cabal project with local packages and a `cabal.project` file for multi‑package builds.
- Shows how to expose MCP servers (`tricorder-mcp`) and how to integrate with Hermes via effect rows.

### Polytropos
- Focuses on extensible records/variants via the `large‑records`/`large‑anon` plugin ecosystem.
- Contains a `docs/transcripts/` directory for tutorial‑style explanations and a `docs/notes/` for design reviews.
- Illustrates how to grow a Haskell library around a GHC plugin (type‑level row algebra, `KnownHash`, `AllFields`, `SubRow`, …).
- Maintains a clear distinction between nominal and structural interpretations using phantom flags.
- Provides example of integrating `typelet` for O(1) construction.

## Suggested skeleton for `~/src/programming-in-the-large/`

```
programming-in-the-large/
├── src/                -- Haskell source (core language, plugins, libraries)
│   ├── Core/           -- Core data structures (e.g. AST, intermediate representations)
│   ├── Plugins/        -- GHC plugins for row‑algebra, effect inference, etc.
│   └── Lib/            -- Utility libraries (e.g. effect system, graph rewriting)
├── packages/           -- Optional: separate Cabal packages for each major component
├── bin/                -- Executables (orchestrator, REPL, code‑generation tools)
├── docs/
│   ├── transcripts/    -- Tutorial‑style write‑ups (e.g. Goguen‑Burstall institutions, CEGIS)
│   └── notes/          -- Design reviews, meeting minutes, architectural decisions
├── test/               -- Test suites (unit, property‑based, integration)
├── .agents/            -- Hermes agent configuration (skills, plugins, cron, memories)
├── cabal.project       -- Multi‑package build configuration
├── shell.nix or default.nix (optional) -- reproducible builds
└── README.md
```

## Concepts to model / integrate

| Area | Reference | How it could appear in the repo |
|------|-----------|--------------------------------|
| **Goguen‑Burstall institutions** | Abstract model of logical systems | A type‑class `Institution sig model` with signature and model functors; could live in `Lib/Logic/`. |
| **Smith‑Specware categorical algorithm design** | Specware’s algebra of specifications | DSL for building specifications via categorical constructions; maybe a GHC‑plugin that derives spec‑level code from Haskell. |
| **Solar‑Lezama modular CEGIS** | Counterexample‑guided inductive synthesis | A library `CEGIS` offering `synthesize :: Spec -> IO Prog` using SAT/SMT backends; could be a package under `packages/`. |
| **Honda‑Yoshida‑Carbone multiparty session types** | Session‑typed communication | Bindings to existing session‑type libraries (e.g. `sessiontypes`) or a new embedding; placed in `Lib/Concurrency/`. |
| **Behavioural choreographies** | Global behavioural specifications | Choreography language compiled to endpoint APIs; could be a code‑gen plugin. |
| **Back‑Morgan refinement calculus** | Stepwise refinement of programs | A refinement monad or DSL for expressing refinement steps; in `Lib/Refinement/`. |
| **Omar et al contextual hole semantics** | Typed holes with context | Extension of GHC’s hole mechanism; could be a GHC plugin that enriches hole messages. |
| **Tate et al equality saturation** | Equality‑based rewriting using E‑graphs | Wrapper around the `egraph` library; provide a plugin that performs saturation during compilation. |
| **Willsey et al E‑graphs** | Core E‑graph data structure | Direct dependency or a fork; used by the equality‑saturation pass. |
| **Unifying sheaf‑theoretic framework** | From `gemini‑scaling‑autonomous‑coding.md` | A high‑level abstraction layer that composes the above via sheaves of data over a site of program transformations; could reside in `Lib/Sheaf/`. |

## Existing transcripts to reuse

The user noted that `~/src/programming-in-the-large/docs/` may already contain relevant transcripts.  If present, they could be:

- `docs/transcripts/goguen-burstall-institutions.md`
- `docs/transcripts/cegis-overview.md`
- `docs/transcripts/session-types-intro.md`
- `docs/transcripts/choreography-compilation.md`
- `docs/transcripts/refinement-calculus.md`
- `docs/transcripts/contextual-holes.md`
- `docs/transcripts/equality-saturation.md`
- `docs/transcripts/e-graphs-basics.md`
- `docs/transcripts/sheaf-theoretic-unification.md`

These would be good starting points for the `docs/transcripts/` directory of the new project.

## Next steps (as agreed)

1. Create the directory skeleton as outlined above.
2. Seed the repository with a minimal `README.md` and a `cabal.project` that references `sarutahiko` and `polytropos` as optional dependencies (via `extra-deps` if needed).
3. Add a placeholder Haskell module `src/Core/AST.hs` defining a simple expression type to experiment with.
4. Begin populating `docs/transcripts/` with short write‑ups for each of the listed concepts, reusing existing material where available.
5. Set up a Hermes agent profile for the new project (copy from default, adjust `skills/` to include `hermes-agent`, `code-navigation`, `contextful`, etc.) so that the agent can assist with navigation and code generation.

## Closing remarks

By mirroring the proven layouts of Sarutahiko (effect‑orchestrated, multi‑package) and Polytropos (plugin‑driven, extensible‑records‑centric) we obtain a solid foundation for a research project that can host a variety of formalisms for autonomous programming at scale.  The separation of concerns—core language, plugins, libraries, documentation, and agent configuration—mirrors the best practices already established in the user’s other repositories and will facilitate incremental growth and collaboration.

[End of transcript]