# **Resilient and Error-Tolerant Parsing Strategies**

[https\://gemini.google.com/app/b459fe0bf196481b](https://gemini.google.com/app/b459fe0bf196481b)

*User prompt: Robust Parsing of Programming Languages I have the notion that robust parsing for IDEs and coding assistants is worthwhile, but apart from the idea that chart parsing could potentially provide a way to keep the language structure intelligible for potential further purposes, I need more concrete ways to actually make use of it. Error reporting has some exploration in literature; however, stopping at merely rejecting whole modules at a time isn't sufficient for my purposes. Robust and error-tolerant source code processing, which lacks much exploration in literature that I can see, would, I hope, be able to take the portions of a module that have parsed and perform feasible further stages of analysis past parsing on them. The kinds of errors I usually see discussions of tolerance of largely stop at parsing like with Kegler's Marpa, where, for instance, scoping errors like referring to a symbol not in scope, or type errors like definitions that fail typechecking, have very little discussion in the literature that I'm aware of. In a slightly more „blue-sky“, handwavy and conceptual discussion, there's seemingly some prominence to „island parsing“ where the analysable input is conceived of as small islands within seas of error. I would, perhaps, want to reconceptualise as a „stope and winze“ model instead, where the errors — perhaps „gangue“? — are conceived of limited, narrower sub-components that can be regarded as dispensable or potentially accessible more broadly with the proviso that they're understood to be erroneous. For instance, a symbol defined within some module in a way that fails typechecking might be deemed accessible in a way that imports of the symbol are still allowed so its satisfaction of scoping correctness constraints is still understood even while its definition's ill-typedness might remain understood and the type error's true location is understood so that the error reporting doesn't meaninglessly attribute the symbol's uses when imported to the importing module. This particular example is often not difficult, as an explicit top-level type declaration reflecting the intention will fail to be realised by the type error in the definition while it's still fine for other modules importing it to regard it as having the declared type. Still, this is the larger context in which I would like the parsing to sit. Within this larger context, the winze of an erroneous declaration or definition within a module needs to be able to be carved out while still deriving a module AST or IR spanning the longer range of input forming a stope (usually a file, though e.g. Standard ML and some others have the potential for more complexity regarding modules). This doesn't fit with the island parsing model as I understand it. I'm not versed enough in the field to be able to effectively search for the kinds of things I'm hoping for using Google Scholar. Please help me find what papers, algorithms and codebases relate to these ideas within the literature, especially regarding parsing.*

Response: Your “stope and winze” metaphor is remarkably apt. You have accurately identified the core limitation of **Island Parsing** (Moonen, 2001). Island parsing assumes you only care about small, isolated constructs (islands) and treats the rest of the file as meaningless "water." As you noted, this fails for compilers and language servers because the "water" often contains structural scopes, indentation, and module boundaries that the rest of the program depends on.

What you are describing—carving out a constrained, localized pocket of erroneous code (the gangue) while preserving the overarching structural integrity of the module (the stope) so that further semantic analysis can proceed—is the foundation of modern **Resilient Parsing** (also called **Error-Tolerant Parsing**).

Here is a breakdown of the algorithms, paradigms, and codebases that implement this philosophy, along with the exact terminology you need to find them in the literature.

### **1\. Structural Containment: Full-Fidelity CSTs and "Error Nodes"**

To achieve your goal, modern IDE compilers abandon traditional Abstract Syntax Trees (ASTs) during the initial parse. Traditional parsers halt or drop data on an error. Instead, resilient parsers produce **Lossless Concrete Syntax Trees (CSTs)**.

In this model, the parser *never fails*. If it encounters gangue (syntax errors, missing tokens, or garbage characters), it does not drop the tree or reject the module. Instead, it wraps the erroneous tokens in an explicit **ErrorNode** (the winze) and attaches it to the tree.

> * **Synchronization / Panic-Mode Recovery:** When the parser encounters an error, it enters "panic mode" and skips tokens until it finds a reliable structural boundary (like a closing brace }, a semicolon ;, or a new keyword like fn or class).  
> * **AST Placeholders:** It then inserts an ErrorNode representing the skipped tokens, and immediately resumes parsing the surrounding "stope".

Because the resulting CST is strictly lossless (it contains every whitespace, comment, and error), the broader structure of the file remains intact. The module, its imports, and its top-level declarations are successfully parsed, with the errors confined entirely to local sub-nodes.

### **2\. Semantic Containment: "Poisoning" and the Error Type**

Your specific example—where a symbol fails to typecheck in its definition, but should still be visible to other modules importing it—is solved in the literature using **Semantic Poisoning** and the **Error / Any Type**.

Once your resilient parser builds a tree containing ErrorNodes, the subsequent compiler passes (name resolution, scoping, type checking) must be taught how to step around the winze:

> * **Symbol Table Preservation:** Even if a function's body is entirely garbage, the parser still parsed its signature. The name resolution pass registers the function in the scope. When an importing module queries that symbol, it is successfully found, satisfying the scoping constraints.  
> * **Type-Level Recovery (The Error Type):** If a definition's type cannot be inferred due to an error, the compiler assigns it a synthetic ErrorType (sometimes called Unknown or Any).  
> * **Poisoning:** The ErrorType acts as a wildcard that implicitly satisfies *all* type constraints. If module B imports a symbol from module A that is infected with an ErrorType, module B will not emit cascading type errors. The error is reported exactly once: at the site of the original "gangue." Walter Bright (creator of the D programming language) popularized AST poisoning specifically to stop cascading false-positive errors during semantic analysis.

### **Codebases to Study**

The literature on this specific architecture is relatively sparse because it was largely pioneered in industry rather than academia. To see it in action, you should study these three landmark codebases:

> 1. **rust-analyzer (and the rowan crate):** This is arguably the modern gold standard for resilient parsing. It is the language server for Rust. It uses a "Red/Green Tree" architecture to build lossless CSTs. Aleksey Kladov, its original architect, has written extensively on this.  
> 2. **Roslyn (The .NET Compiler Platform):** Microsoft's C\# compiler was the first major production compiler to completely redesign its architecture around IDE-first, error-tolerant, lossless syntax trees. Anders Hejlsberg's talks on Roslyn's design are foundational to this space.  
> 3. **Tree-sitter:** An incremental parser generator tool used by GitHub and modern text editors (like Neovim). Unlike standard recursive descent parsers, Tree-sitter uses a Generalized LR (GLR) algorithm. When it hits an error, it forks its parse state, tries multiple combinations of token insertions and deletions, and uses a cost metric to find the shortest path back to a valid parse state, ultimately emitting an (ERROR) node in the tree.

### **Search Terms for Google Scholar**

To bypass the older, less relevant literature (like Island Parsing or simple yacc-style panic modes), use these specific terms in your searches:

> * *"Error-tolerant parsing" OR "Resilient parsing"*  
> * *"Lossless syntax trees" OR "Full-fidelity syntax trees"*  
> * *"AST Placeholders" OR "Error nodes compiler"*  
> * *"Incremental parsing IDE"*  
> * *"Semantic poisoning compiler" OR "Cascading error recovery"*

**Recommended Reading:**

> * **"Resilient LL Parsing Tutorial"** by Aleksey Kladov (matklad). Not a peer-reviewed paper, but widely considered the definitive modern text on implementing the exact "stope and winze" parser you are conceptualizing.  
> * **"Error-Tolerant Parsing and Compilation for Hylo"** (TU Delft, 2024). A very recent academic paper that surveys state-of-the-art error-tolerant compilation techniques, explicitly covering AST Placeholders and token synchronization in modern architectures.  
> * **"Efficient and Flexible Incremental Parsing"** (Tim Wagner's 1998 UC Berkeley Ph.D. thesis). While older, this is the foundational academic text that eventually led to systems like Tree-sitter.

**Sources**

> 1. [Error-Tolerant Parsing and Compilation for Hylo \- TU Delft Repository](https://repository.tudelft.nl/file/File_c8b9533c-f030-4f38-95ff-8f53c5665fca)

---

*User prompt: Do any of the more modern techniques like rowan/rust-analyzer, Swift's libsyntax, Roslyn or tree-sitter use chart parsing for an improved ability to take the desired grammar into account? Or would any of them be compatible with using a chart parsing parsing engine for their purposes?*

Response: The short answer is **no**. None of the industry-standard resilient parsing architectures you mentioned use chart parsing (such as Earley, CYK, or Marpa).

However, to answer your second question: **yes, the underlying data structures they use are entirely compatible with chart parsing.**

Here is a breakdown of what these modern tools actually use, why they avoid chart parsing, and how you could theoretically adapt a chart parser to achieve the "stope and winze" resilience you are aiming for.

### **1\. What the Modern Tools Actually Use**

The tools you listed fall into two distinct algorithmic camps, neither of which is chart parsing:

> * **Hand-Written Recursive Descent (Roslyn, Rowan/rust-analyzer, Swift swift-syntax):** These architectures abandoned parser generators entirely. They use deeply optimized, hand-written recursive descent (LL) parsers. When they hit an error, they do not rely on algorithmic state-space exploration. Instead, they rely on human-coded heuristics. The programmer explicitly writes panic-mode recovery logic (e.g., *"If you see garbage inside a function, skip tokens until you see a } or a let keyword, wrap the garbage in an ErrorNode, and resume"*).  
> * **Generalized LR / GLR (Tree-sitter):** Tree-sitter is the closest to what you are envisioning, but it uses GLR, not chart parsing. When Tree-sitter hits an error, it doesn't just panic; it forks its state machine. It explores multiple parallel timelines (inserting synthetic tokens in one branch, deleting "gangue" tokens in another) and uses a cost metric to pick the timeline that gets back to a valid state with the least modification.

### **2\. Compatibility: The "Red/Green Tree" is Algorithm-Agnostic**

You absolutely *can* use a chart parser for modern IDE tooling because architectures like Roslyn and Rowan decouple the **parsing algorithm** from the **data structure**.

The core innovation of these systems is the **Red/Green Tree** (a specific implementation of a lossless Concrete Syntax Tree). A Red/Green tree simply requires that whatever engine is doing the parsing must emit every single token—including whitespace, comments, and erroneous garbage—into the tree.

If you write an Earley chart parser that, upon encountering an error, successfully identifies the bounds of the "gangue," wraps it in an ErrorNode, and continues parsing, you can feed that directly into a Rowan-style CST. The subsequent compiler passes (type checking, semantic poisoning) won't know or care that a chart parser built the tree.

### **3\. The Catch: Why Industry Avoids Chart Parsing for IDEs**

If chart parsing is so elegant and naturally handles ambiguous grammars, why doesn't Microsoft, Apple, or the Rust team use it for their resilient parsers? The answer comes down to the **State-Space Explosion** and IDE latency budgets.

For an IDE, parsing must happen on every single keystroke, usually within 16 to 50 milliseconds.

> 1. **Baseline Complexity:** Chart parsers inherently explore all possible parses simultaneously. For unambiguous grammars, Earley parsing is *O*(*n*2) or *O*(*n*), but for highly ambiguous or complex grammars, it can hit *O*(*n*3).  
> 2. **The Error Recovery Blow-up:** To make a chart parser error-tolerant, you typically have to inject "wildcard" or "skip" edges into the chart when a parse fails. Because chart parsers are exhaustive, injecting a wildcard edge forces the engine to calculate *every possible combination* of skipped tokens and valid continuations. This combinatorial explosion destroys the keystroke-level performance required by language servers.  
> 3. **Heuristics beat purity:** In practice, language designers found that a human writing a recursive descent parser is vastly better at guessing the *intent* of a broken program than an algorithm trying to calculate the mathematical shortest path to a valid syntax tree.

### **How to Pursue Chart Parsing for This**

If you are determined to build a resilient "stope and winze" model on top of a chart parser, you will need to constrain how the chart handles errors so it doesn't stall the CPU.

To find literature on this specific intersection, you should step away from standard compiler design and look into Natural Language Processing (NLP) from the late 90s and early 2000s, where chart parsing was heavily used to parse grammatically broken human sentences.

> * Search for **"Error recovery in Earley parsers"** or **"Cost-based chart parsing."**  
> * Look into *"A parsing"*\* (A-Star parsing), which applies heuristic weights to chart edges so the parser doesn't waste time exploring error-recovery paths that are statistically unlikely.

You would essentially be building an Earley parser that operates normally for the "stope" (valid code), but when it gets stuck, it temporarily shifts into a heavily constrained, cost-weighted mode to isolate the "winze" (gangue), closes off the error node, and resumes normal chart generation.

---

*User prompt: If I wanted an IDE or coding assistant \-integrated compiler to have front-ends for 100+ languages, hand-written recursive descent seems very unlikely to scale for the development problem. How does the Lark parser library fit into our picture?*

Response: You are completely right to identify that hand-writing recursive descent parsers for 100+ languages is a logistical nightmare. That approach is only viable for companies maintaining a single language (like Microsoft with C\# or the Rust foundation with rust-analyzer). To scale to 100+ languages, you absolutely must use a parser generator where you only have to write declarative grammars.

**Lark** is an excellent general-purpose parsing library in Python, and its Earley engine is fantastic for ingesting ambiguous grammars without modification. However, for an IDE or coding assistant requiring "stope and winze" error-isolation, Lark introduces critical bottlenecks.

Here is exactly how Lark fits into the picture, and where its architecture falls short for this specific use case:

### **1\. Error Recovery is Manual, Not Algorithmic**

Lark does not automatically wrap "gangue" in error nodes and resume parsing. When Lark encounters an error, it throws an UnexpectedToken or UnexpectedCharacters exception.

To recover, Lark provides an InteractiveParser (often called a "puppet" parser). You catch the exception, inspect the internal state machine, and write Python code to explicitly mutate the state—either by forcing synthetic tokens into the stream (like an assumed missing comma) or consuming tokens until you reach a safe state.

Because you have to manually define *how* to recover from specific errors based on the state machine, you are trading the burden of hand-writing 100 parsers for the burden of hand-writing 100 sets of error-recovery heuristics.

### **2\. Lack of Native Lossless CSTs**

To achieve resilient IDE parsing, the parser must generate a Lossless Concrete Syntax Tree (CST) containing every whitespace character, comment, and erroneous token. Lark primarily builds standard Abstract Syntax Trees (ASTs) or basic parse trees.

While you can force Lark to preserve whitespace and comments, doing so pollutes the grammar rules, and the engine does not have a native concept of "Red/Green" trees or transparent ErrorNode boundaries. You would have to build the entire "stope and winze" data structure heavily on top of Lark's outputs.

### **3\. Earley Latency**

Lark's Earley implementation is optimized, but Earley parsing in Python is generally too slow to meet the 16-to-50 millisecond latency budget required to re-parse a large file on every keystroke in an IDE. Earley is highly flexible, but for an IDE language server, the algorithmic overhead combined with Python's runtime makes real-time syntax highlighting and scoping sluggish.

### **The Industry Solution: Tree-sitter**

If you want the scale of a parser generator (writing 100+ declarative grammars) combined with the "stope and winze" resilient architecture of modern IDEs, the exact tool you are looking for is **Tree-sitter**.

Tree-sitter was built explicitly to solve the exact problem you are describing for the exact scale you are targeting (it currently powers GitHub's syntax highlighting and Neovim's parsing for hundreds of languages).

> * **Declarative Scale:** You write grammars in a simple JavaScript DSL. Tree-sitter compiles them into highly optimized C or Rust parsers.  
> * **Algorithmic Error Recovery:** It uses a Generalized LR (GLR) algorithm. When it hits an error, you don't write custom recovery logic. The GLR engine automatically explores parallel parse states, drops the minimum number of "gangue" tokens necessary, isolates them in a literal (ERROR) node, and resumes the "stope".  
> * **Lossless by Default:** It natively generates the exact lossless CSTs required for semantic poisoning and IDE tooling, preserving all whitespace and structural bounds.

**Sources**

> 1. [lark.js \- Documentation](https://www.lark-parser.org/Lark.js/lark.js.html)  
> 2. [Error handling using an interactive parser \- Lark documentation](https://lark-parser.readthedocs.io/en/stable/examples/advanced/error_handling.html)

---

*User prompt: Could it make sense to drive the parse via GLR à la tree-sitter while maintaining some kind of state or otherwise information regarding the grammar or derivations for the sake of improved error reporting of the kinds able to be offered via chart parsing?*

Response: Yes, this makes profound sense. In fact, you have hit upon a very deep theoretical connection in parsing literature: **GLR parsing and Chart parsing (like Earley) are not as different as they appear.**

If you want the keystroke-level performance of Tree-sitter’s GLR, but the rich, derivation-aware error reporting of a chart parser, you do not need to abandon GLR. You simply need to expose and utilize the hidden state that GLR already maintains.

Here is how this hybrid approach makes sense, how the data structures align, and how you would extract chart-level diagnostics from a GLR engine.

### **1\. The Bridge: GSS and SPPF**

A standard LR parser uses a flat stack. When it fails, it knows almost nothing about the broader context, which is why older compilers give terrible errors like "Unexpected token 'ident'".

However, because GLR must handle ambiguity, it cannot use a flat stack. Instead, it uses a **Graph-Structured Stack (GSS)** to explore multiple parse paths simultaneously. As it parses, it builds a **Shared Packed Parse Forest (SPPF)**—a structure that records all possible derivations of the input.

**An Earley chart and a GLR GSS are mathematically duals of each other.**

> * An Earley chart explicitly stores "items" representing partially completed grammar rules at every index (e.g., Statement \-\> if ( Expr ) • Statement).  
> * A GLR parser compiles those items into a state machine ahead of time. The active "heads" of the GSS correspond directly to sets of Earley items.

### **2\. How to get Chart-like Reporting out of GLR**

In Tree-sitter, when the GLR engine hits an error, it immediately prioritizes *recovery*: it calculates a cost-based heuristic to drop or insert tokens, wraps the bad code in an (ERROR) node, and moves on to save the "stope." The rich grammatical context of *why* it failed is largely discarded in the final tree.

To get chart-level diagnostics, you intercept the GLR parser at the exact moment of failure, *before* it begins heuristic recovery, and perform **LR Item Introspection**:

> 1. **Halt and Inspect the GSS:** When the parser encounters "gangue" and no shift actions are valid, look at the active heads of the Graph-Structured Stack.  
> 2. **Decompile the LR State:** Each node at the head of the GSS represents an LR state integer (e.g., State 42). You query your grammar table to reverse-map State 42 back into its **Kernel Items** (the exact grammar rules being processed, with the • indicating the parser's current position).  
> 3. **Walk the Derivation:** Because the GSS is a graph of previous states, you can walk backwards down the stack. By tracing the stack, you reconstruct the exact grammatical derivation tree that led to the failure.

Instead of Tree-sitter's generic syntax error, your GLR parser can now output:

*"While parsing a FunctionDeclaration, inside the ParameterList, expected a TypeAnnotation but found an operator."*

### **3\. Why This Architecture is the "Best of Both Worlds"**

This approach perfectly satisfies the needs of a modern IDE:

> * **The Fast Path (GLR):** For the 99% of the file that is well-formed (the stope), the GLR engine runs at *O*(1) LR-speed. It does not waste CPU cycles maintaining explicit chart items like Earley does.  
> * **The Diagnostic Path (Chart-like):** For the 1% of the file that contains errors (the winze), the parser stalls. You spend a few milliseconds walking the GSS and decompiling LR states to generate a rich, chart-level diagnostic report.  
> * **The Recovery Path:** Once the diagnostic is generated and attached to the error, the standard GLR cost-based recovery kicks in, bounds the error in an ErrorNode, and resumes the fast path.

### **Literature and Algorithms to Explore**

If you want to read up on how to implement this specific mapping of GLR state back to grammar derivations for error reporting, look for these concepts:

> * **"LR Item Set Introspection" or "LR State Decompilation":** The act of mapping an LR automaton state back to the human-readable CFG rules it represents.  
> * **Tomita's GLR algorithm (1985):** Masaru Tomita originally invented GLR for Natural Language Processing. His original papers heavily emphasize the construction of the SPPF, which is exactly the data structure you would traverse to get chart-like output.  
> * **"Merr" (Menhir Error Reporting):** While not GLR, François Pottier's work on error reporting for the Menhir parser generator (used heavily in OCaml) is required reading. Pottier proved that you can achieve incredibly precise, context-aware error messages in LR parsers by analyzing the LR state stack at the point of failure.

In summary: Yes, driving the parse via GLR for speed and structural recovery, while introspecting the GSS/LR-items upon failure to extract chart-like diagnostic information, is arguably the theoretical ideal for a robust, IDE-integrated parser.

**Sources**

> 1. [An overview of parsing algorithms \- stereobooster](https://stereobooster.com/posts/an-overview-of-parsing-algorithms/)

---

