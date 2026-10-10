# Discord Discussion: Barriers to Adoption of Row-Polymorphic Open ADT Libraries

**Source:** Discord `#fp-general` channel in the *Functional Programming* server  
**Date:** Saturday, 2026-10-10, 16:00 – 18:46 CEST  
**Context:** Discussion initiated by Nadia on why row-polymorphic / open ADT libraries in Haskell have historically faced adoption resistance.  
**Screenshot Artifact:** `/home/nyc/Bilder/Bildschirmfotos/Bildschirmfoto vom 2026-10-10 18-51-17.png`

---

## 1. Verbatim Transcript

```text
[16:00] Nadia:
What have been the barriers to the acceptance/adoption/etc. of row-polymorphic open ADT libraries esp. for Haskell?

[17:06] Cyrus T Crumples:
Try reading vinyl's haddocks and you tell me
https://hackage.haskell.org/package/vinyl
[Hackage: vinyl — Extensible Records]

[17:43] edmundnoble:
Questionable benefit compared to Generics, lack of standardisation, verbosity, bad type errors, no autocompletion
That's my personal list

[17:59] Nadia (replying to @edmundnoble):
Interesting. In what context is autocompletion unavailable for them?

[18:03] Nadia (replying to @Cyrus T Crumples):
From my cursory re-examination of them, I'm reading your comment as saying that both the structure of the interfaces and the quality of the documentation are problematic. Am I interpreting your comment properly?

[18:12] Cyrus T Crumples:
Yes.
Also from what I recall from the last time I tried experimenting with them, the type inferrence/error situation is/was bad...
That was years ago and I was a less good Haskeller and I can't remember much about the specifics... I just remember that while trying to experiment with it I would get error messages that were extremely difficult to use to figure out what I had done wrong.
I don't have much patience for solutions that work perfectly when you make no mistakes, but are nigh impossible to figure out what has gone wrong when you make mistakes...
Fancy constraint heavy interfaces can do this

[18:16] mniip:
it's not even that fancy
it's trying to force computation to happen at compile time, and the only way to do that is to encode your computation in instance selection
I'm not saying it's simple, I'm saying there's no simpler way to do this (bearbeitet)

[18:35] Nadia (replying to @mniip):
Instance selection being via normalisation of instance heads in plug-ins?

[18:36] mniip:
normalization of instance heads and "pattern" "matching"

[18:46] Nadia (replying to @mniip):
I have a bunch of things involving pattern matching for handler types. Is that the issue you're on about?
```

---

## 2. Structured Analysis of Identified Barriers & Polytropos Mitigations

The conversation highlights eight distinct friction points that have hindered developer adoption of extensible records and open sum/variant libraries in Haskell:

| # | Barrier / Complaint | Root Cause in Prior Art (`vinyl`, `superrecord`, etc.) | How `polytropos` Addresses / Mitigates It |
|---|---|---|---|
| **1** | **Documentation & Interface Incomprehensibility** ("Try reading vinyl's haddocks") | Haddock documentation is heavily abstracted into universe functors (`ElField`, `Dict`), Peano type-level lists, and opaque category-theoretic jargon with few worked, practical examples. | Purpose-built documentation governance ([`DOC_STRATEGY.md`](../notes/DOC_STRATEGY.md), [`NEWBIE_GUIDE.md`](../NEWBIE_GUIDE.md)). A clean high-level consumer module ([`Polytropos`](../../packages/polytropos-core/src/Polytropos.hs)) exposing intuitive primitives (`emptyRecord`, `insertField`, `Variant`, `projectVariant`) that read like ordinary standard library code. |
| **2** | **Questionable Benefit Compared to Generics** | If an extensible library only provides generic serialization or lenses at the cost of high complexity, developers default to nominal ADTs with `deriving (Generic)` and `GHC.Generics`. | 1. Genuine open subrow/subsum polymorphism (`SubRow`, `SubSum`) with $O(1)$ widening and bulk projection.<br>2. Avoids the $O(2^N)$ binary tree explosion (`:+:`, `:*:`) in compile time and runtime heap.<br>3. Direct bridge in [`polytropos-generics`](../../packages/polytropos-generics/src/Polytropos/Generics.hs) evaluating `geq`, `gcompare`, `gshowsPrec`, `gmap`, `gfoldMap` over flat `Rep` with zero intermediate metadata allocations.<br>4. Open algebraic effect systems (proven in `effectful`, `polysemy`, and `kernmantle` ports). |
| **3** | **Lack of Standardisation** | Every library invents competing operators (`<+>`, `:>`, `.&.`), entry wrappers, and closed universes, none of which interoperate. | Standardizes on official GHC facilities: native record dot (`OverloadedRecordDot`) via [`GHC.Records.HasField`](../../packages/polytropos-plugin/src/Polytropos/Plugin.hs), [`GHC.OverloadedLabels.IsLabel`](../../packages/polytropos-core/src/Polytropos/Core.hs) (`#field`), standard optics prisms and lenses, and drop-in satellite packages for standard ecosystem libraries (`aeson`, `beam`, `rel8`, `persistent`, `openapi3`, `cassava`, `cbor`, `quickcheck`). |
| **4** | **Verbosity** | Constructing or updating records requires verbose linked-list chains: `Field @"a" 1 :& Field @"b" True :& RNil`. | Milestone §1.6 source-plugin syntax: `[REC| a: 1, b: True |]`, field punning `[REC| a, b |]`, record update `[REC_UPD| r with a: 2 |]`, and open declaration forms (`deriving OpenRecord` / `deriving OpenVariant`). |
| **5** | **Bad Type Errors & Inference Fragility** ("nigh impossible to figure out what has gone wrong") | When typeclass search fails in instance-selection libraries, GHC dumps hundreds of lines of stuck type families and unprovable Peano constraints (`Could not deduce (RecElemFCtx ...)`). | `polytropos` rejects type-level instance search loops. All row indexing and projection is solved deterministically by a dedicated `TcPlugin` (`Polytropos.Plugin`), which calculates literal indices and emits custom human-readable `TypeError` diagnostics specifying missing fields or tag mismatches. |
| **6** | **No Autocompletion in IDE / Tooling (HLS)** | Haskell Language Server (HLS) cannot suggest completions for type-level symbol lists because they are not declared as top-level nominal record selectors. | Source-plugin declaration forms (`deriving OpenRecord`) generate nominal field selector signatures in the module environment that HLS indexes for completion. For `OverloadedRecordDot`, compiler plugins provide explicit candidates when the row is known. |
| **7** | **Compiling via Instance Selection & Normalization** (mniip: "force computation to happen at compile time... in instance selection") | Forcing GHC's instance solver to execute type-level algorithms (sorting, searching, matching) via recursive class instances and head normalization causes compiler slowdowns and solver blowups. | Core architectural invariant in `polytropos`: **zero type-level search**. Computations (FNV-1a 64-bit hashing, slot calculations, subrow projections) occur in native compiled Haskell code inside the `TcPlugin`, directly emitting literal Core AST dictionaries. |
| **8** | **Pattern Matching for Handler Types** | Open variants require exhaustive dispatch across open constructor rows, risking missing cases or cumbersome nested `Either` trees. | Decided hybrid eliminator design: coproduct of per-constructor results `m (SumOf (Results handlerRow))`, paired with compile-time `SubSum` narrowing evidence to eliminate unhandled constructors safely. |

---

## 3. Action Items for Polytropos Documentation and Roadmap

1. **Haddock and Documentation First-Class Invariant:**
   Ensure every exported type and function in `polytropos-core` and satellite packages features complete, runnable examples and clear error expectations, contrasting sharply with Vinyl's opaque documentation.
2. **Custom Type Error Messages in TcPlugin:**
   In `Polytropos.Plugin`, intercept unresolved `FieldIndex`, `ConstructorIndex`, `SubRow`, and `SubSum` wanteds to format clear error messages:
   - *"Field 'email' is missing from record of type { name :: String, age :: Int }."*
   - *"Did you mean 'age'?"*
3. **IDE / HLS Guidance Note:**
   Document how HLS autocompletion behaves with `OverloadedRecordDot` and `deriving OpenRecord`, and explore HLS plugin integration for row-polymorphic records.
4. **Compile-Time Performance Claims:**
   Benchmark and contrast compilation times against `GHC.Generics` and `vinyl` in `benchmark/variants`, quantifying the linear compile-time benefit of TcPlugin literal synthesis over typeclass instance selection.
