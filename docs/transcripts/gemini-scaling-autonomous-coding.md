# **Scaling Autonomous Coding with Compilers**

[https\://gemini.google.com/app/36df222eb841e468](https://gemini.google.com/app/36df222eb841e468)

*User prompt: Large-Scale Autonomous Coding What research has been done regarding large-scale autonomous coding? How can the scale of autonomous coding be increased? As an instance of large-scale autonomous coding to try to deploy, I have something akin to a „universal compiler“ project, \`frankenstein\`, where the majority of back-end concerns are handled by MLIR. Then the project retrofits at the moment 26 flagship open source compilers for various languages to emit an IR, \`OrganIR\`, based on algebraic effects, that's then in turn translated to MLIR after what's effectively link-time typechecking and link-time code generation. Further work to deploy autonomous coding to do might be: 1\. keeping all of the forks of the flagship open source compilers caught up with upstream 2\. extending the set of 12 languages where bidirectional cross-language calls are supported to cover the full range of languages, at present, 26 3\. covering more languages than just 26, perhaps 100+ 4\. robustifying the phases prior to and including emitting \`OrganIR\` to tolerate erroneous input 5\. LSP-like service for multi-lingual codebases The magnitude of this „programming in the large“ task should hopefully be apparent. There are other ways large-scale autonomous coding could be gone about, but the above is a concrete example. Who's studied trying to get computers to be able to deal with doing large-scale coding projects on very large bodies of code like that? What's needed to enable autonomous coding to be able to handle larger tasks?*

Response: The magnitude of frankenstein is immense, but its architecture—relying on MLIR and an algebraic effect-based intermediate representation (OrganIR)—actually provides the exact deterministic scaffolding that large-scale autonomous coding systems require. Standard generative AI struggles with "programming in the large" because it lacks strict bounds. By forcing compilation through link-time typechecking and MLIR generation, you have built a rigorous reward function for an autonomous agent.

Here is the current state of research into large-scale autonomous coding and the architectural breakthroughs needed to scale it to the level of managing 100+ compiler forks.

### **Who is Studying Large-Scale Autonomous Coding?**

Research has transitioned from passive code completion (like standard Copilot) to active, repository-level autonomous agents that plan, search, and execute in sandboxed environments.

> * **Repository-Level Benchmarking (Princeton & SWE-bench):** The current gold standard for autonomous software engineering research is SWE-bench, developed by researchers at Princeton. It evaluates agents on resolving real-world, multi-file GitHub issues. This research proved that static context windows are insufficient; agents must be able to execute bash commands, navigate directories, and run tests.  
> * **Agentic Search and AST Navigation (NUS & AutoCodeRover):** Researchers at the National University of Singapore developed AutoCodeRover, which focuses on program representation. Instead of using text-based vector search (RAG) which fails on large codebases, it gives the agent APIs to search Abstract Syntax Trees (ASTs) and call graphs, mimicking how a developer navigates via an LSP.  
> * **Multi-Agent Coordination (MetaGPT & ChatDev):** Academic work on multi-agent frameworks demonstrates that monolithic LLM calls fail at scale. Research shows that splitting tasks into discrete personas—a Triage Agent to read the upstream diff, a Systems Architect to plan the IR translation, and a Coder Agent to write the MLIR passes—drastically reduces hallucinations.  
> * **Enterprise-Scale Execution Frameworks (OpenHands & Moderne):** Open-source and enterprise projects like OpenHands (formerly OpenDevin) and Moderne are studying cross-repository automation. They focus on building Large Codebase SDKs that map dependencies across hundreds of repositories and orchestrate agents working in parallel without merge conflicts.

### **What is Needed to Scale Autonomous Coding?**

To achieve your roadmap—particularly keeping 26 (and eventually 100+) flagship compiler forks synced with upstream and robustifying OrganIR emission—several structural paradigms must be implemented.

**1\. Semantic Context Curation over Brute-Force Context Windows** Even with massive 1-million+ token context windows, feeding an entire compiler codebase into an LLM causes "context drift" and hallucinated dependencies. To scale to 100+ languages, the autonomous system needs strict context partitioning. This requires integrating tools like Tree-sitter so the agent only pulls in the specific module, its imported signatures, and the relevant tests, rather than raw text.

**2\. Closed-Loop Execution and Deterministic Sandboxing** Autonomous coding cannot be a "shot in the dark". For your project, the agent must exist in a Read-Eval-Print Loop (REPL) intertwined with the compiler infrastructure.

> * The agent drafts a patch to update a C++ or Rust frontend fork.  
> * A sandboxed compiler node attempts to compile it to OrganIR.  
> * If the algebraic effects or link-time typechecking fail, the exact error stack is fed back to the agent. This deterministic, test-driven feedback loop is what allows agents to fix their own logic errors without human intervention.

**3\. Graph-Aware Diffing for Upstream Syncs** Keeping forks caught up with upstream (Goal 1\) is notoriously difficult for LLMs because text-based git merges are inherently lossy. To automate this, the agent needs to operate on the AST level. When the upstream compiler changes, the system must generate a semantic diff of the AST, isolate the breaking changes against your retrofitted frontend, and task the agent specifically with bridging that semantic gap, rather than resolving standard git merge conflicts.

**4\. Neuro-Symbolic State Machines** To expand bidirectional cross-language calls across 100+ languages (Goals 2 and 3), you cannot rely on an LLM's unstructured reasoning. The process must be governed by a strict state machine. The workflow must be broken down into immutable steps:

> * **Signal:** Detect a missing language binding or a failing cross-language call.  
> * **Plan:** Draft the required IR mapping.  
> * **Execute:** Write the bridging code.  
> * **Validate:** Run the link-time code generation. If validation fails, the agent is forced back to the execution phase. It is not allowed to modify the underlying compiler architecture to bypass the test.

By exposing your OrganIR semantics and MLIR passes as queryable APIs to the agent, you essentially build an environment where the agent cannot cheat—it must produce mathematically and structurally sound IR, or the pipeline immediately halts it. This exact intersection of formal compiler constraints and LLM generative capabilities is the frontier of scaling autonomous software engineering.

**Sources**

> 1. [OpenHands | The Open Platform for Cloud Coding Agents](https://www.openhands.dev/)  
> 2. [The Future of Autonomous Software Engineering: Multi-Agent](https://dev.to/mtahir27/the-future-of-autonomous-software-engineering-multi-agent-collaboration-and-self-healing-code-4n8l)

---

*User prompt: Does this differ by project structure? For instance, there is a \`pgcl\` project to retrofit existing OS kernels to allow kernel allocation units to grow to power-of-two multiples of the minimum MMU mapping granularities while maintaining the ABI that's meant to be leveraged in conjunction with superpaging to try to shift the distribution of MMU translation sizes from a geometric distribution to something like a negative binomial distribution. (In principle, the page clustering technique can also be used in the absence of superpaging.) Just writing a kernel of one's own can also be a very large project, too, also of a different structure. Or, for that matter, a Niklaus Wirth \-style Project Oberon recreating the world from hardware to kernel to userspace if a kernel alone isn't large enough. How do the strategies change for these other cases?*

Response: The structure of the target system fundamentally dictates the autonomous agent's sensory inputs, context boundaries, and required feedback loops. A compiler retrofit relies on deterministic ASTs and static type-checking, whereas deep kernel hacking and hardware-software co-design require dynamic state analysis and cross-domain co-simulation.

As the project structure shifts, the autonomous coding strategies must adapt to the new constraints of the environment.

### **1\. The Invasive Retrofit (pgcl style)**

Modifying deep OS allocation paths—such as adapting buddy systems or slab allocators to support page clustering while strictly preserving the ABI—places the agent inside a massive, highly entangled legacy codebase.

> * **Semantic Slicing:** The agent cannot navigate the entire Linux or BSD kernel. Instead of standard text retrieval, it requires call-graph slicing to isolate the specific subsystem (e.g., the memory management unit, superpaging logic, and the specific interval trees or radix bitmaps used for tracking).  
> * **Dynamic State Feedback:** Compiling without errors is insufficient; the kernel must boot and run stably. The agent’s Read-Eval-Print Loop (REPL) must integrate with a virtual machine sandbox. To verify if the allocation sizes actually shift toward the target negative binomial distribution, the agent must write and deploy dynamic tracing programs (like eBPF or ftrace) into the test kernel, executing workloads and reading the resulting histograms as its success metric.  
> * **ABI Contract Enforcement:** To ensure the ABI remains unbroken, the agent's output is gated by static analysis tools that map struct layouts and function signatures before and after the patch. If a padding byte shifts or a register convention is violated, the patch is rejected before it even reaches the sandbox.

### **2\. Greenfield Kernel Development**

Writing a custom kernel from scratch presents a "blank canvas" problem. Standard LLMs suffer from severe architectural drift over time, losing track of their own abstractions across dozens of files.

> * **Invariant Enforcement:** The autonomous system requires a strictly enforced architectural hierarchy. A dedicated "Architect" agent or static policy file maintains global invariants (e.g., "all IPC must be non-blocking" or "drivers run in isolated user-space rings"). If a "Coder" agent generates a monolithic shortcut that violates the microkernel design, the commit is automatically rejected.  
> * **Hardware Exception Decoding:** The agent must be trained to interpret hardware-level failures rather than standard software exceptions. When code fails in the QEMU sandbox, the agent receives raw register dumps, custom TLB fill faults, or general protection faults, and must translate those low-level hardware signals into logical software fixes. Bottom-up Test-Driven Development is mandatory: the agent must successfully write and test boot code, then MMU initialization, then interrupts, moving sequentially.

### **3\. Full-Stack Co-Design (Project Oberon Style)**

Rebuilding from silicon to userspace means the agent operates across fundamentally different domains, moving between hardware description languages (Verilog/VHDL for FPGA or custom CPUs), systems languages (C/Rust for the kernel), and userspace logic.

> * **Lockstep Co-Simulation:** The feedback loop expands to hardware-software co-simulation. The agent runs its code against cycle-accurate simulators (like Verilator). It must understand timing constraints, gate logic, and how software instructions map to the hardware pipeline.  
> * **Atomic Cross-Boundary Commits:** A change in the instruction set architecture or hardware MMU requires synchronized updates to the compiler backend and the OS page table management. The agent cannot modify the hardware independently. It operates on "Cross-Domain Contracts"—if it alters a hardware capability, the co-simulation immediately breaks the kernel's memory mapping tests, forcing the agent to resolve the dependency across the hardware-software boundary in a single atomic commit.

---

*User prompt: Are any of the research groups attempting to use autonomous coding to approach ambitious, large-scale programming tasks like the ones I've described? Someone has to have thought of this before, even if mere science fiction enthusiasts vs. real practitioners or researchers.*

Response: Yes, this exact class of problem is the central focus of a rapidly maturing field known as **Autonomous Software Engineering**. Researchers and practitioners have realized that raw model capability cannot solve "programming in the large"—instead, the focus has shifted entirely to the sandboxes, control loops, and feedback mechanisms that wrap the AI.

Here are four active research paradigms that map directly to the architectural ambitions of frankenstein, pgcl, and Project Oberon.

## **1\. AI Harness Engineering (The Runtime Substrate)**

Recent academic work, such as the May 2026 paper *AI Harness Engineering*, argues that autonomous software capability is an emergent property of a *Model-Harness-Environment* system, rather than the language model acting alone. Researchers are building "AI-Native Development Environments" that enforce strict, stateful workflows: Reproduce, Attribute, Fix, Verify, and Report. For frankenstein, the deterministic MLIR and link-time typechecking pipeline *is* the harness. Research shows that when an agent is forced to interact through these strict runtime substrates rather than free-text editing, it can successfully execute complex, long-horizon engineering tasks.

## **2\. AST-Driven Evolutionary Refactoring**

Keeping 26 (or 100+) flagship compiler forks synced with upstream is nearly impossible with text-based git merges. Research into "Self-Programming AI" (2025) focuses on agents that operate directly on Abstract Syntax Trees (ASTs) rather than raw text. By parsing the AST, the agent can perform fine-grained, safe refactorings and architectural evolution in a closed loop, using execution metrics to continuously rewrite and adapt the codebase without breaking structural integrity.

## **3\. Agentic Variation Operators for Systems Programming**

For projects like pgcl where you are modifying legacy OS kernels to optimize memory allocation, researchers are exploring "Agentic Variation Operators" (AVO). Instead of traditional evolutionary algorithms that mutate code randomly, this March 2026 research elevates the autonomous agent to act as the variation operator itself. The agent analyzes dynamic execution feedback—such as eBPF histograms tracking your page clustering sizes—and iteratively discovers performance-critical micro-architectural optimizations that can surpass human expert baselines.

## **4\. Evidence Preservation for State-Space Navigation**

As the scale of autonomous coding increases, agents frequently get stuck trying the same broken logic in different syntax. September 2026 research on *Reusing Evidence in Autonomous Coding Research* studies how agents must learn from failed experiments. In a massive system like cross-compiling 12 languages to OrganIR, a failed link-time typecheck isn't just a retry prompt; it's a structural counterexample. This research focuses on mechanisms that force the agent to preserve the evidence of what each failed experiment justifies, actively narrowing the search space so it doesn't repeat structural mistakes across the codebase.

The gap between this research and practical deployment is closing quickly. In 2026, terminal-native agents like Claude Code and massive-context models like Codex (GPT-5.4) are already being deployed to handle repository-wide framework migrations and API upgrades across sprawling legacy codebases.

The limiting factor for scaling autonomous coding on frankenstein or pgcl is no longer the reasoning capability of the underlying LLM. It is entirely dependent on the rigor of your sandboxed testing environment and the formal constraints of the APIs you expose to the agent.

**Sources**

> 1. [AI Harness Engineering: A Runtime Substrate for Foundation-Model](https://arxiv.org/html/2605.13357v1)  
> 2. [(PDF) Self-Programming AI: Code-Learning Agents for Autonomous](https://www.researchgate.net/publication/391933574_Self-Programming_AI_Code-Learning_Agents_for_Autonomous_Refactoring_and_Architectural_Evolution)  
> 3. [AVO: Agentic Variation Operators for Autonomous Evolutionary Search](https://arxiv.org/html/2603.24517v1)  
> 4. [Reusing Evidence in Autonomous Coding Research \- arXiv](https://arxiv.org/html/2609.13299v1)

---

*User prompt: At the moment I've coded an orchestrator that can do something maybe not much more involved than kanban at the moment, perhaps while still needing hand-holding from regular tooling. I asked about some of the theory of how workflows work before, with the attached results. Is there anything like those theories for a theory of autonomous programming in the large?*

Response: A formal theory of autonomous programming in the large sits at the intersection of **Compositional Program Synthesis**, **Categorical Specification Theory**, and **Behavioral Refinement Calculi**.

Where DeRemer and Kron’s original 1975 distinction between *programming-in-the-small* (algorithms and data structures) and *programming-in-the-large* (module interconnection and structural relationships) focused on static human modularity, an autonomous theory requires mathematical machinery capable of bounding search spaces, guaranteeing compositional correctness, and propagating semantic diffs across heterogeneous components.

### **1\. Categorical Software Synthesis & Institutional Architecture**

When scaling code generation beyond isolated functions, treating code as text tokens fails. The foundational mathematics for large-scale structural assembly comes from the theory of **Institutions** (Joseph Goguen and Rod Burstall) and **Categorical Algorithm Design** (Douglas R. Smith / Specware).

> * **The Theory of Specifications as Objects:** Software architectures are modeled as diagrams in a category Spec, where objects are specifications (Σ,Φ) (signatures Σ and formal axioms Φ) and morphisms are specification-preserving translations.  
> * **Architecture via Colimits:** A composite software system (such as an OS kernel or a multi-language compiler pipeline) is not written monolithically; it is computed as the **colimit** of a diagram of specifications:  
>   SystemSpec=colim(*D*)  
>   where *D*:Graph→Spec captures the interconnection and shared interfaces of subsystems.  
> * **Refinement Arrows:** Autonomous coding agents operate not by outputting raw code, but by constructing refinement morphisms:  
>   *ρ*:Specabstract​→Specconcrete​  
>   Because colimits preserve composition, when an agent refines an isolated component morphism *ρi*​, the composite system morphism is automatically valid by the universal property of colimits. This mathematically prevents architectural drift.

### **2\. Modular Counterexample-Guided Inductive Synthesis (Modular CEGIS)**

Single-unit autonomous synthesis typically relies on CEGIS (Armando Solar-Lezama): a synthesizer generates a candidate program *P*, a verifier checks ∀*x*. Spec(*x*,*P*(*x*)), and returns a counterexample if it fails. However, monolithic CEGIS does not scale to systems with millions of lines of code.

> * **Decomposition via Assume-Guarantee (A/G) Synthesis:** Developed by Rajeev Alur, Ashutosh Trivedi, and others, **Modular Synthesis** decomposes the global synthesis problem into localized games. If a system *S*\=*M*1​∥*M*2​ must satisfy global property Φ, the framework synthesizes local contracts (*A*1​,*G*1​) and (*A*2​,*G*2​) such that:  
>   (*A*1​∧*G*2​⟹*G*1​)∧(*A*2​∧*G*1​⟹*G*2​)∧(*G*1​∧*G*2​⟹Φ)  
> * **Circular CEGIS:** When an autonomous agent attempts a change in *M*1​, the verifier only checks against contract *G*1​ under assumption *A*1​. If it fails, the counterexample is confined strictly to *M*1​'s contract interface, preventing combinatorial state-space explosion across the rest of the codebase.

### **3\. Multiparty Session Types (MPST) and Behavioral Choreographies**

When an autonomous system operates across dozens of compiler frontends, link-time code generators, or asynchronous kernel subsystems, structural type-checking is insufficient; the system requires **Behavioral Types** (Kohei Honda, Nobuko Yoshida, Marco Carbone).

> * **Global Choreographies (Γ):** A global session type specifies the valid interaction sequence, state transitions, and algebraic effect propagations across all participating language frontends or kernel threads.  
> * **Projection to Local Types:** The global choreography Γ is projected onto each individual endpoint *p* as a local session type:  
>   Γ↾*p*\=*Tp*​  
> * **Autonomous Compliance:** An agent modifying a compiler frontend or an allocation path is constrained such that its emitted implementation satisfies *Pp*​⊢*Tp*​. If the agent generates an optimization or a synchronization sequence that violates the projection, the choreographic type checker rejects the patch statically, mathematically guaranteeing **deadlock freedom**, **progress**, and **protocol fidelity** without needing full-system execution.

### **4\. Stepwise Program Refinement over Incomplete Code (Hole Semantics)**

Autonomous coding in the large is fundamentally an iterative transformation of *partially realized systems*. This is formalized by **Refinement Calculus** (Ralph-Johan Back, Carroll Morgan) combined with **Contextual Hole Semantics / Gradual Typing** (Cyrus Omar et al., *Hazel*).

> * **The Refinement Lattice:** Codebases are partially ordered by a refinement relation ⊑, where *S*1​⊑*S*2​ denotes that *S*2​ is more concrete and satisfies all specifications of *S*1​:  
>   *S*⊑*S*′⟺∀*R*. wp(*S*,*R*)⟹wp(*S*′,*R*)  
>   where wp is Dijkstra’s weakest precondition.  
> * **Hole Calculi with Semantic Bounds:** An agent never replaces a repository; it operates on an expression with dynamic non-terminals (typed holes) *E*\[□*τ*​\]. The formal theory of hole contexts assigns both an internal required type/contract *τ* and an ambient static environment Γ to □. The autonomous agent's allowable transformations are restricted to monotonic refinement steps *E*\[□\]⊑*E*\[*e*\], ensuring that every intermediate iteration of the repository maintains compilation and whole-system invariants even while features remain unwritten.

### **5\. Equality Saturation on Term Graphs (E-Graphs)**

For tasks like keeping dozens of compiler forks synchronized with upstream changes, standard syntactic diffing fails because semantic equivalence is obscured by syntactic variance. The operational theory for managing this scale is **Equality Saturation** and **E-Graphs** (Tate et al., Willsey et al., egg).

> * **Congruence Closure over ASTs:** An e-graph compactly represents exponential numbers of semantically equivalent ASTs as an equivalence class (e-class).  
> * **Non-Destructive Rewriting:** Instead of forcing an agent to decide on a single merge path, upstream compiler changes and retrofit patches are introduced as rewriting rules over the e-graph. The agent acts not as a lone writer, but as a heuristic guide for rule scheduling.  
> * **Extraction under Objective Functions:** Once equality saturation reaches a fixed point or computational budget, extraction selects the optimal AST that maximizes both upstream patch compatibility and downstream target invariants (such as preserving custom intermediate representation emissions).

### **Unifying Framework: The Sheaf-Theoretic View of Codebases**

If you assemble these theories into a single meta-theory of autonomous programming in the large, a massive codebase is modeled as a **Sheaf** F over an architectural topological space (*X*,O*X*​):

> 1. **Open Sets (*U*∈O*X*​):** Subsystems, modules, or bounded contexts (e.g., frontend parsers, allocators, target code generators).  
> 2. **Sections (F(*U*)):** Valid implementations and local invariants that satisfy the contracts on subsystem *U*.  
> 3. **Restriction Maps (res*U*,*V*​:F(*U*)→F(*V*) for *V*⊆*U*):** The projection of large module contracts onto individual subroutines, structs, or ABI boundaries.  
> 4. **The Sheaf Condition (Gluing):** If an autonomous orchestrator dispatches *N* agents to mutate disjoint subsystems *Ui*​ such that their changes agree on all overlapping boundaries *Ui*​∩*Uj*​, there exists a **unique** global codebase state:  
>    *σ*∈F(*i*⋃​*Ui*​)  
>    that integrates all local patches simultaneously without conflict.

By transitioning your orchestrator from an empirical task tracker (kanban) to a **sheaf-theoretic scheduler with assume-guarantee boundary gates**, the agent's work is bounded by local contracts, and the global integration is mathematically guaranteed to glue together.

---

*User prompt: How can specification extraction be scaled up to autonomous programming in the large? The attached document doesn't seem to have much of a theoretical framework apart from the idea of trying to use neural networks to guide things toward the theoretical framework of plans themselves. Has there been any research into scaling these kinds of specification extraction tasks to autonomous programming in the large sorts of tasks such as I've been on about?*

Response: The "Spec-Extractor Agent" paradigm relies on using structured outputs like JSON Schema or Pydantic to force an LLM to act as a strict compiler, mapping unstructured text into structural configuration files such as a Dhall module or Blueprint format. While effective for initial project scaffolding, scaling specification extraction to massive systems like your frankenstein compiler pipeline or pgcl kernel allocator requires transitioning from syntactic text parsing to **Neuro-Symbolic Specification Synthesis**.

To scale to autonomous programming in the large, the extraction process must be embedded within a closed-loop system that infers formal pre-conditions, post-conditions, and loop invariants directly from the legacy codebase. This operates on a pipeline of mining code context, generating candidate specifications in first-order logic, parsing them into executable assertions, and validating them against existing test suites.

There is a rapidly growing body of recent research specifically focused on formal specification mining and contract synthesis for large-scale, low-level codebases:

> * **FUN2SPEC:** This framework is designed explicitly for synthesizing formal code contracts in real-world, large-scale C++ repositories. It operates by mining type information, functions, and unit tests, prompting an LLM to generate formal first-order logic specifications, and translating those specifications into executable assertions embedded directly into the codebase's existing unit testing suite.  
> * **AutoSpec & SpecGen:** These systems focus on automated formal specification generation. AutoSpec decomposes programs into hierarchical component graphs to query LLMs for local specifications, while SpecGen uses mutation-based refinement and conversational feedback loops to infer complex loop invariants and constraints.  
> * **AutoReSpec:** This framework uses a validator-guided refinement engine that dynamically selects between primary and fallback LLMs based on program complexity. It leverages verifier error feedback to recover from verification failures during specification generation, creating an automated conversational loop between the model and the formal verifier.  
> * **Assume-Guarantee Synthesis:** At the architectural level, research applies solver-guided algorithms (such as AE-VAL for ∀∃-formulas) to generate reactive implementations directly from Assume-Guarantee contracts, where the specifications mathematically restrict environment inputs and guarantee safe system state transitions.

Applying these hybrid connectionist-symbolic architectures to your tasks bridges the gap between LLM hallucination and formal compiler constraints. For a system like frankenstein, an automated miner would first extract the implicit ABIs and type constraints of the 26 upstream compiler frontends. The autonomous agent is then tasked with generating the OrganIR algebraic effects strictly to satisfy those mathematically extracted contracts, turning a massive manual reverse-engineering task into a deterministic, solver-guided refinement loop.

---

