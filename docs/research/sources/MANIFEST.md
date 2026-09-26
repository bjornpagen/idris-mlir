# Master source manifest (skeleton)

Status of this file: **skeleton only.** It enumerates the full target inventory across threads
A–J plus cross-cutting, using the plan's inventory sections as the row list. No file is
recorded as fetched yet. Identifiers, reachability, and pins live in `ACCESS.md`.

**Legend**

- **Storage form**: `papers/<firstauthor-year-shortname>/` (raw TeX or PDF only if no source),
  `sources/docs/...`, `sources/code/...`, `sources/pointers/...`, or `skip`.
- **Status**: `planned` (identified, to collect), `unresolved` (identifier/OA not located —
  see `ACCESS.md` §3c), `skip` (intentionally not collected), `resolved-id` (identifier
  confirmed in `ACCESS.md` but content not yet fetched).
- Licenses marked `verify` are unconfirmed from the publisher/repo; confirm at collection time.

Rows marked *(shared)* appear in more than one thread but must be stored once and cross-linked;
do not duplicate a paper across threads.

---

## Thread A — Tinygrad and first-order dataflow optimizers

| Shortname | Title / path set | Thread(s) | Harvest method | Storage form | Status | License |
| --- | --- | --- | --- | --- | --- | --- |
| `code-tinygrad` | `tinygrad/uop/ops.py`, `uop/upat.py`, `uop/spec.py`, `uop/symbolic.py`, `uop/render.py`, `uop/validate.py`, `codegen/simplify.py`, `schedule/{prepare,rangeify,indexing,memory,multi}.py`, `renderer/{cstyle,llvmir}.py`, `engine/{realize,jit}.py`; locate the BEAM-search module at fetch time | A | pinned raw GitHub @ `b1a9b35bdd89ed2ed3fa69e0786210fbd268b33a`; find BEAM module by tree search | `sources/code/tinygrad/` | stored (`sources/code/tinygrad/` 19 files; BEAM-search module located: `tinygrad/codegen/opt/search.py`, from the `tinygrad/codegen/{opt,late,decomp}` trees — not guessed) | MIT |
| `docs-tinygrad` | tinygrad docs + README | A, G | `docs.tinygrad.org` + pinned README | `sources/docs/tinygrad/` | stored (`sources/docs/tinygrad/` 29 files: repo `README.md` + `docs/**` .md/.py/.svg, plus the live `docs.tinygrad.org` index at snapshot time) | MIT |
| `jia-2019-taso` | TASO: optimizing deep learning computation with automatic generation of graph substitutions | A | DOI (no OA at ACM); find green OA | `papers/jia-2019-taso/` | resolved-id | ACM © verify |
| `chen-2018-tvm` | TVM: An Automated End-to-End Optimizing Compiler for Deep Learning | A, G *(shared)* | arXiv `e-print/1802.04799` | `papers/chen-2018-tvm/` | resolved-id | arXiv non-exclusive |
| `zheng-2020-ansor` | Ansor: Generating High-Performance Tensor Programs for Deep Learning | A, G *(shared)* | arXiv `e-print/2006.06762` | `papers/zheng-2020-ansor/` | resolved-id | arXiv non-exclusive |
| `yang-2021-tensat` | Equality Saturation for Tensor Graph Superoptimization (Tensat) | A, B *(shared)* | arXiv `e-print/2101.01332` | `papers/yang-2021-tensat/` | resolved-id | arXiv non-exclusive |

## Thread B — Equality saturation and rewriting

| Shortname | Title / path set | Thread(s) | Harvest method | Storage form | Status | License |
| --- | --- | --- | --- | --- | --- | --- |
| `willsey-2021-egg` | egg: Fast and Extensible Equality Saturation | B | arXiv `e-print/2004.03082` | `papers/willsey-2021-egg/` | resolved-id | arXiv non-exclusive |
| `zhang-2023-egglog` | Better Together: Unifying Datalog and Equality Saturation | B | arXiv `e-print/2304.04332` | `papers/zhang-2023-egglog/` | resolved-id | arXiv non-exclusive |
| `zhang-2022-relational-ematching` | Relational E-Matching | B | arXiv `e-print/2108.02290` | `papers/zhang-2022-relational-ematching/` | resolved-id | arXiv non-exclusive |
| `wang-2020-spores` | SPORES: Sum-Product Optimization via Relational Equality Saturation for Large Scale Linear Algebra | B | arXiv `e-print/2002.07951` (plan ID corrected) | `papers/wang-2020-spores/` | resolved-id | arXiv non-exclusive |
| `yang-2021-tensat` | Tensat (see Thread A) | A, B *(shared)* | arXiv `e-print/2101.01332` | `papers/yang-2021-tensat/` | resolved-id | arXiv non-exclusive |
| `pal-2023-ruler` | Equality Saturation Theory Exploration à la Carte (tool: Ruler) | B | DOI 10.1145/3622834 (ACM 403); find green OA | `papers/pal-2023-ruler/` | resolved-id | ACM © verify |
| `koehler-2024-guided-eqsat` | Guided Equality Saturation | B | DOI 10.1145/3632900 | `papers/koehler-2024-guided-eqsat/` | resolved-id | ACM © verify |
| `koehler-2021-sketch-eqsat` | Sketch-Guided Equality Saturation | B | arXiv `e-print/2111.13040` | `papers/koehler-2021-sketch-eqsat/` | resolved-id | arXiv non-exclusive |
| `wu-2026-slotted-egraphs` | Typed Flexible-Arity Slotted E-Graphs (slotted e-graphs / binders) | B | arXiv `e-print/2609.03998` (verify future ID) | `papers/wu-2026-slotted-egraphs/` | resolved-id | arXiv non-exclusive |
| `extraction-ilp-maxsat` | e-graph extraction (ILP/MaxSAT) work — specific paper to identify | B | literature probe (arXiv/OpenAlex) at collection time | `papers/…` (TBD) | unresolved | TBD |
| `code-eqsat-dialects` | DialEgg and the MLIR `eqsat` dialect source | B, F | pinned LLVM @ `llvmorg-23.1.2`; DialEgg repo | `sources/code/mlir-eqsat/` | planned | Apache-2.0 WITH LLVM-exception / DialEgg verify |
| `code-egg-repos` | egg / egglog repositories | B | pinned GitHub `2f31b28e…` (egg), `90635860…` (egglog) | `sources/code/egg/`, `sources/code/egglog/` | planned | MIT |
| `panchekha-2015-herbie` | Automatically improving accuracy for floating point expressions (Herbie) | B | DOI 10.1145/2737924.2737959; author host | `papers/panchekha-2015-herbie/` | resolved-id | ACM © verify |

## Thread C — Staging, partial evaluation, supercompilation, fusion

| Shortname | Title / path set | Thread(s) | Harvest method | Storage form | Status | License |
| --- | --- | --- | --- | --- | --- | --- |
| `kovacs-2022-staged` | Staged Compilation with Two-Level Type Theory | C | arXiv `e-print/2209.09729` (plan ID corrected) | `papers/kovacs-2022-staged/` | resolved-id | arXiv non-exclusive |
| `kovacs-2024-closure-free` | Closure-Free Functional Programming in a Two-Level Type Theory | C | DOI 10.1145/3674648 | `papers/kovacs-2024-closure-free/` | resolved-id | ACM © verify |
| `taha-2000-metaml` | MetaML and multi-stage programming with explicit annotations | C | DOI 10.1016/S0304-3975(00)00053-0; ScienceDirect PDF | `papers/taha-2000-metaml/` | resolved-id | Elsevier © verify |
| `taha-2004-gentle-intro-multistage` | A Gentle Introduction to Multi-stage Programming | C | DOI 10.1007/978-3-540-25935-0_3 | `papers/taha-2004-gentle-intro-multistage/` | resolved-id | Springer © verify |
| `futamura-projections` | Futamura, "Partial evaluation of computation process" (1971) | C | resolve via author/library host; no DOI found | `papers/…` (TBD) | unresolved | TBD |
| `turchin-1986-supercompiler` | The concept of a supercompiler | C | DOI 10.1145/5956.5957 | `papers/turchin-1986-supercompiler/` | resolved-id | ACM © verify |
| `sorensen-1996-positive-supercompiler` | A positive supercompiler | C | DOI 10.1017/S0956796800002008 | `papers/sorensen-1996-positive-supercompiler/` | resolved-id | CUP © verify |
| `mitchell-2010-rethinking-supercompilation` | Rethinking supercompilation | C | DOI 10.1145/1863543.1863588 | `papers/mitchell-2010-rethinking-supercompilation/` | resolved-id | ACM © verify |
| `bolingbroke-2010-supercompilation-by-eval` | Supercompilation by evaluation | C | DOI 10.1145/1863523.1863540 | `papers/bolingbroke-2010-supercompilation-by-eval/` | resolved-id | ACM © verify |
| `wadler-1990-deforestation` | Deforestation: transforming programs to eliminate trees | C | DOI 10.1016/0304-3975(90)90147-A | `papers/wadler-1990-deforestation/` | resolved-id | Elsevier © verify |
| `gill-1993-short-cut` | A short cut to deforestation (foldr/build) | C | DOI 10.1145/165180.165214 | `papers/gill-1993-short-cut/` | resolved-id | ACM © verify |
| `coutts-2007-stream-fusion` | Stream fusion: from lists to streams to nothing at all | C | DOI 10.1145/1291151.1291199 | `papers/coutts-2007-stream-fusion/` | resolved-id | ACM © verify |
| `warm-fusion` | warm fusion — intended reference to confirm | C | literature probe at collection time | `papers/…` (TBD) | unresolved | TBD |
| `shortcut-fusion` | shortcut fusion — intended reference to confirm | C | literature probe at collection time | `papers/…` (TBD) | unresolved | TBD |
| `book-pe-jones-gomard-sestoft` | Partial Evaluation and Automatic Program Generation (book) | C | author-hosted free PDF → pointer | `sources/pointers/pe-book.md` | planned | author-hosted free |
| `wurthinger-2013-one-vm` | One VM to rule them all | C | DOI 10.1145/2509578.2509581 | `papers/wurthinger-2013-one-vm/` | resolved-id | ACM © verify |
| `wurthinger-2017-practical-partial-eval` | Practical partial evaluation for high-performance dynamic language runtimes | C | DOI 10.1145/3062341.3062381 | `papers/wurthinger-2017-practical-partial-eval/` | resolved-id | ACM © verify |
| `rompf-2010-lms` | Lightweight modular staging: a pragmatic approach to runtime code generation and compiled DSLs | C | DOI 10.1145/1868294.1868314 | `papers/rompf-2010-lms/` | resolved-id | ACM © verify |
| `christiansen-2016-elaborator-reflection` | Elaborator reflection: extending Idris in Idris | C | DOI 10.1145/2951913.2951932 | `papers/christiansen-2016-elaborator-reflection/` | resolved-id | ACM © verify |
| `christiansen-thesis` | Christiansen PhD thesis | C | author host; no stable OA URL located | `papers/…` (TBD) | unresolved | TBD |

## Thread D — Memory from QTT

| Shortname | Title / path set | Thread(s) | Harvest method | Storage form | Status | License |
| --- | --- | --- | --- | --- | --- | --- |
| `marshall-2022-linearity-uniqueness` | Linearity and Uniqueness: An Entente Cordiale | D | DOI 10.1007/978-3-030-99336-8_13; Springer OA PDF | `papers/marshall-2022-linearity-uniqueness/` | resolved-id | Springer OA verify |
| `fractional-uniqueness` | fractional uniqueness (OOPSLA 2024) — title to identify | D | literature probe (author Marshall/Vollmer/Orchard) | `papers/…` (TBD) | unresolved | TBD |
| `reinking-2021-perceus` | Perceus: garbage free reference counting with reuse | D | DOI 10.1145/3453483.3454032 (plan ID corrected) | `papers/reinking-2021-perceus/` | resolved-id | ACM © verify |
| `ullrich-2019-counting-immutable-beans` | Counting Immutable Beans: Reference Counting Optimized for Purely Functional Programming | D | arXiv `e-print/1908.05647` | `papers/ullrich-2019-counting-immutable-beans/` | resolved-id | arXiv non-exclusive |
| `lorenzen-2022-frame-limited-reuse` | Reference counting with frame limited reuse | D | DOI 10.1145/3547634 | `papers/lorenzen-2022-frame-limited-reuse/` | resolved-id | ACM © verify |
| `lorenzen-2023-fp2` | FP²: Fully in-Place Functional Programming | D | DOI 10.1145/3607840 | `papers/lorenzen-2023-fp2/` | resolved-id | ACM © verify |
| `lorenzen-2024-oxidizing-ocaml` | Oxidizing OCaml with Modal Memory Management | D | DOI 10.1145/3674642 | `papers/lorenzen-2024-oxidizing-ocaml/` | resolved-id | ACM © verify |
| `bernardy-2018-linear-haskell` | Linear Haskell: practical linearity in a higher-order polymorphic language | D | arXiv `e-print/1710.09756` | `papers/bernardy-2018-linear-haskell/` | resolved-id | arXiv non-exclusive |
| `wadler-linear-types` | Wadler's linear types papers (e.g. "Linear Types Can Change the World", 1990) | D | author host; no DOI confirmed | `papers/…` (TBD) | unresolved | TBD |
| `peytonjones-1992-stg` | Implementing lazy functional languages on stock hardware: the Spineless Tagless G-machine | D, Cross-cutting | DOI 10.1017/S0956796800000319; Cambridge OA PDF | `papers/peytonjones-1992-stg/` | resolved-id | CUP © verify |
| `marlow-2006-fast-curry` | Making a fast curry: push/enter vs. eval/apply for higher-order languages | D | DOI 10.1017/S0956796806005995; Cambridge OA PDF | `papers/marlow-2006-fast-curry/` | resolved-id | CUP © verify |
| `book-gc-handbook` | Garbage Collection Handbook | D | no OA; pointer only | `sources/pointers/gc-handbook.md` | planned | book © |
| `blackburn-2008-immix` | Immix: a mark-region garbage collector … | D | DOI 10.1145/1375581.1375586 | `papers/blackburn-2008-immix/` | resolved-id | ACM © verify |
| `boehm-gc` | Boehm GC (project/tech report) | D | project page → pointer | `sources/pointers/boehm-gc.md` | planned | verify |
| `precise-tracing-gc` | precise tracing GC — reference to confirm | D | literature probe at collection time | `papers/…` (TBD) | unresolved | TBD |
| `destination-passing-style` | Destination-passing style — reference to confirm | D | literature probe at collection time | `papers/…` (TBD) | unresolved | TBD |
| `leijen-2017-koka-effects` | Type directed compilation of row-typed algebraic effects (Koka) | D, Cross-cutting | DOI 10.1145/3009837.3009872 | `papers/leijen-2017-koka-effects/` | resolved-id | ACM © verify |

## Thread E — Representation from dependent types

| Shortname | Title / path set | Thread(s) | Harvest method | Storage form | Status | License |
| --- | --- | --- | --- | --- | --- | --- |
| `brady-2004-inductive-families` | Inductive Families Need Not Store Their Indices | E | DOI 10.1007/978-3-540-24849-1_8 | `papers/brady-2004-inductive-families/` | resolved-id | Springer © verify |
| `teiiscak-2020-erasure-thesis` | Tejiščák, Erasure in Dependently Typed Programming (thesis 2020) | E | St Andrews repo blocked (000) | `papers/…` (TBD) | unresolved | TBD |
| `teiiscak-2020-erasure-calculus` | A dependently typed calculus with pattern matching and erasure inference | E | DOI 10.1145/3408973 | `papers/teiiscak-2020-erasure-calculus/` | resolved-id | ACM © verify |
| `brady-2021-idris2-qtt` | Idris 2: Quantitative Type Theory in Practice | E | arXiv `e-print/2104.00480` | `papers/brady-2021-idris2-qtt/` | resolved-id | arXiv non-exclusive |
| `brady-2013-thesis` | Brady PhD thesis on dependently typed implementation (2013) | E | St Andrews repo blocked (000) | `papers/…` (TBD) | unresolved | TBD |
| `chataing-2024-unboxed-data-constructors` | Unboxed Data Constructors: Or, How cpp Decides a Halting Problem | E | DOI 10.1145/3632893 (plan attribution corrected) | `papers/chataing-2024-unboxed-data-constructors/` | resolved-id | ACM © verify |
| `docs-ghc-unarisation` | GHC unarisation docs | E | GHC commentary wiki | `sources/docs/ghc/unarisation.*` | unresolved (no `commentary/compiler/unarisation` page exists — HTTP 404 at fetch time; nearest captured material is `sources/docs/ghc/commentary-compiler-code-gen.md` and `...-backends.md`) | BSD-3-Clause verify |
| `maranget-2008-pattern-matching` | Maranget, Compiling Pattern Matching to Good Decision Trees (ML 2008) | E | DOI to confirm | `papers/…` (TBD) | unresolved | TBD |
| `wadler-1987-pattern-matching` | Wadler, efficient compilation of pattern matching (1987) | E | reference to confirm | `papers/…` (TBD) | unresolved | TBD |
| `lee-2001-size-change` | The size-change principle for program termination | E | DOI 10.1145/360204.360210 | `papers/lee-2001-size-change/` | resolved-id | ACM © verify |
| `abel-foetus` | foetus — termination checker for simple functional programs | E | author host; no DOI | `sources/pointers/foetus.md` | unresolved | TBD |
| `rondon-2008-liquid-types` | Liquid types | E | DOI 10.1145/1375581.1375602 | `papers/rondon-2008-liquid-types/` | resolved-id | ACM © verify |

## Thread F — MLIR with and without C++

| Shortname | Title / path set | Thread(s) | Harvest method | Storage form | Status | License |
| --- | --- | --- | --- | --- | --- | --- |
| `lattner-2020-mlir` | MLIR: A Compiler Infrastructure for the End of Moore's Law | F | arXiv `e-print/2002.11054` | `papers/lattner-2020-mlir/` | resolved-id | arXiv non-exclusive |
| `mlir-cgo-2021` | MLIR: Scaling Compiler Infrastructure for Domain Specific Computation (CGO 2021) | F | DOI to confirm | `papers/…` (TBD) | unresolved | TBD |
| `bhat-2022-lambda-ultimate-ssa` | Lambda the Ultimate SSA: Optimizing Functional Programs in SSA | F, I *(shared)* | arXiv `e-print/2201.07272` | `papers/bhat-2022-lambda-ultimate-ssa/` | resolved-id | arXiv non-exclusive |
| `lucke-2024-transform-dialect` | The MLIR Transform Dialect. Your compiler is more powerful than you think | F | arXiv `e-print/2409.03864` | `papers/lucke-2024-transform-dialect/` | resolved-id | arXiv non-exclusive |
| `fehr-2022-irdl` | IRDL: an IR definition language for SSA compilers | F | DOI 10.1145/3519939.3523700 | `papers/fehr-2022-irdl/` | resolved-id | ACM © verify |
| `bhat-2024-verifying-peephole` | Verifying Peephole Rewriting in SSA Compiler IRs (lean-mlir) | F, I *(shared)* | DOI 10.4230/LIPIcs.ITP.2024.9; LIPIcs OA | `papers/bhat-2024-verifying-peephole/` | resolved-id | CC-BY (LIPIcs default) verify |
| `book-ssa-compiler-design` | SSA-based Compiler Design (free book; MLIR/PDL/e-graph chapters) | F, B | free PDF → pointer/chapters | `sources/pointers/ssa-book.md` | pointer (full PDF stored once at `sources/docs/ssa-book/ssa-based-compiler-design.pdf`; this pointer cross-links it) | free book verify |
| `docs-mojo` | Mojo docs | F | `docs.modular.com/mojo/` | `sources/docs/mojo/` | planned | verify |
| `docs-iree` | IREE docs | F | `iree.dev` | `sources/pointers/iree.md` | planned | Apache-2.0 verify |
| `code-polygeist` | Polygeist | F | `polygeist.pages.dev` / repo → pointer | `sources/pointers/polygeist.md` | planned | Apache-2.0 WITH LLVM-exception verify |

## Thread G — Arrays and kernels with shape types

| Shortname | Title / path set | Thread(s) | Harvest method | Storage form | Status | License |
| --- | --- | --- | --- | --- | --- | --- |
| `dex-papers` | Dex papers + index sets — specific references to identify | G | literature probe; author host | `papers/…` (TBD) | unresolved | TBD |
| `code-dex` | `google-research/dex-lang` source | G | pinned GitHub `25e2e389…` | `sources/code/dex/` | planned | Apache-2.0 verify |
| `henriksen-2017-futhark` | Futhark: purely functional GPU-programming with nested parallelism and in-place array updates | G | DOI 10.1145/3062341.3062354 | `papers/henriksen-2017-futhark/` | resolved-id | ACM © verify |
| `hovgaard-2018-defunctionalisation` | Hovgaard et al., defunctionalisation (TFP 2018) | G, Cross-cutting | DOI to confirm; Futhark site | `papers/…` (TBD) | unresolved | TBD |
| `henriksen-thesis` | Henriksen PhD thesis | G | Futhark site / diku; no OA URL located | `papers/…` (TBD) | unresolved | TBD |
| `code-futhark` | Futhark source | G | pinned GitHub `304c56ff…` | `sources/code/futhark/` | planned | BSD-3-Clause verify |
| `shivers-2019-remora` | Introduction to Rank-polymorphic Programming in Remora (Draft) | G | arXiv `e-print/1912.13451` | `papers/shivers-2019-remora/` | resolved-id | arXiv non-exclusive |
| `ragankelley-2013-halide` | Halide: a language and compiler for optimizing parallelism, locality, and recomputation in image processing pipelines | G | DOI 10.1145/2499370.2462176; MIT DSpace OA | `papers/ragankelley-2013-halide/` | resolved-id | MIT OA verify |
| `halide-2012` | Halide (PLDI/SIGGRAPH 2012) — reference to confirm | G | literature probe at collection time | `papers/…` (TBD) | unresolved | TBD |
| `mullapudi-2016-halide-autosched` | Automatically scheduling halide image processing pipelines | G | DOI 10.1145/2897824.2925952 | `papers/mullapudi-2016-halide-autosched/` | resolved-id | ACM © verify |
| `adams-2019-halide-learning` | Learning to optimize halide with tree search and random programs | G | DOI 10.1145/3306346.3322967 | `papers/adams-2019-halide-learning/` | resolved-id | ACM © verify |
| `chen-2018-tvm` | TVM (see Thread A) | A, G *(shared)* | arXiv `e-print/1802.04799` | `papers/chen-2018-tvm/` | resolved-id | arXiv non-exclusive |
| `zheng-2020-ansor` | Ansor (see Thread A) | A, G *(shared)* | arXiv `e-print/2006.06762` | `papers/zheng-2020-ansor/` | resolved-id | arXiv non-exclusive |
| `ikarashi-2022-exo` | Exocompilation for productive programming of hardware accelerators (Exo) | G | DOI 10.1145/3519939.3523446 (venue corrected from plan) | `papers/ikarashi-2022-exo/` | resolved-id | ACM © verify |
| `kjolstad-2017-taco` | The tensor algebra compiler (TACO) | G | DOI 10.1145/3133901 | `papers/kjolstad-2017-taco/` | resolved-id | ACM © verify |
| `sac-language` | SaC — specific reference to confirm | G | literature probe at collection time | `papers/…` (TBD) | unresolved | TBD |
| `idris-vect-material` | Idris `Vect`/index-typed array material; tinygrad symbolic shapes | E, G, A | Idris2 pinned docs/source; tinygrad pinned source | `sources/docs/idris2/`, `sources/code/idris2/`, `sources/code/tinygrad/` | planned | BSD-3-Clause / MIT verify |

## Thread H — Search and cost models

| Shortname | Title / path set | Thread(s) | Harvest method | Storage form | Status | License |
| --- | --- | --- | --- | --- | --- | --- |
| `massalin-1987-superoptimizer` | Superoptimizer: a look at the smallest program | H | DOI 10.1145/36206.36194 | `papers/massalin-1987-superoptimizer/` | resolved-id | ACM © verify |
| `bansal-2006-peephole-superoptimizer` | Automatic generation of peephole superoptimizers | H | DOI 10.1145/1168918.1168906 | `papers/bansal-2006-peephole-superoptimizer/` | resolved-id | ACM © verify |
| `schkufza-2013-stoke` | Stochastic superoptimization (STOKE) | H | DOI 10.1145/2451116.2451150 | `papers/schkufza-2013-stoke/` | resolved-id | ACM © verify |
| `sasnauskas-2017-souper` | Souper: A Synthesizing Superoptimizer | H | arXiv `e-print/1711.04422` | `papers/sasnauskas-2017-souper/` | resolved-id | arXiv non-exclusive |
| `joshi-2002-denali` | Denali: A Goal-directed Superoptimizer | H | DOI 10.1145/512529.512566 | `papers/joshi-2002-denali/` | resolved-id | ACM © verify |
| `mendis-2019-ithemal` | Ithemal: Accurate, Portable and Fast Basic Block Throughput Estimation using Deep Neural Networks | H | arXiv `e-print/1808.07412` | `papers/mendis-2019-ithemal/` | resolved-id | arXiv non-exclusive |
| `learned-cost-models` | learned cost models — references to confirm | H | literature probe at collection time | `papers/…` (TBD) | unresolved | TBD |
| `mlgo-compilergym` | MLGO / CompilerGym | H | project pages + papers; probe | `sources/pointers/mlgo-compilergym.md` | unresolved | TBD |
| `autotuning-surveys` | autotuning and beam-search surveys | H | literature probe at collection time | `papers/…` (TBD) | unresolved | TBD |
| `egraph-extraction-cost` | E-graph extraction cost models | H, B | overlaps Thread B `extraction-ilp-maxsat` | `papers/…` (TBD) | unresolved | TBD |

## Thread I — Proved optimizations

| Shortname | Title / path set | Thread(s) | Harvest method | Storage form | Status | License |
| --- | --- | --- | --- | --- | --- | --- |
| `lopes-2015-alive` | Provably correct peephole optimizations with Alive | I | DOI 10.1145/2737924.2737965 | `papers/lopes-2015-alive/` | resolved-id | ACM © verify |
| `lopes-2021-alive2` | Alive2: bounded translation validation for LLVM | I | DOI 10.1145/3453483.3454030 | `papers/lopes-2021-alive2/` | resolved-id | ACM © verify |
| `leroy-2009-compcert` | Formal verification of a realistic compiler (CompCert) | I | DOI 10.1145/1538788.1538814 | `papers/leroy-2009-compcert/` | resolved-id | ACM © verify |
| `pnueli-1998-translation-validation` | Translation validation | I | DOI 10.1007/BFb0054170 | `papers/pnueli-1998-translation-validation/` | resolved-id | Springer © verify |
| `certicoq` | CertiCoq papers; Certified Compilation of Coq | I, Cross-cutting | author/lab host; no DOI verified | `papers/…` (TBD) | unresolved | TBD |
| `bhat-2024-verifying-peephole` | lean-mlir verified peephole rewriting (see Thread F) | F, I *(shared)* | DOI 10.4230/LIPIcs.ITP.2024.9 | `papers/bhat-2024-verifying-peephole/` | resolved-id | CC-BY (LIPIcs) verify |
| `smt-rewrite-verification` | SMT-based rewrite verification — references to confirm | I | literature probe at collection time | `papers/…` (TBD) | unresolved | TBD |
| `code-idris-transform` | Idris `%transform` and totality material | I, E | Idris2 pinned source `src/Core/…`, `Compiler/…` | `sources/code/idris2/` | stored (`sources/code/idris2/src/Core/Transform.idr`, `src/TTImp/ProcessTransform.idr`; plus `src/Core/Termination/*` adjacent material not separately copied) | BSD-3-Clause verify |

## Thread J — Bleeding edge, evaluated critically

| Shortname | Title / path set | Thread(s) | Harvest method | Storage form | Status | License |
| --- | --- | --- | --- | --- | --- | --- |
| `lafont-1990-interaction-nets` | Interaction nets | J | DOI 10.1145/96709.96718 | `papers/lafont-1990-interaction-nets/` | resolved-id | ACM © verify |
| `lafont-1997-interaction-combinators` | Interaction Combinators (1997) | J | author host; no DOI verified | `papers/…` (TBD) | unresolved | TBD |
| `lamping-1990-optimal-reduction` | An algorithm for optimal lambda calculus reduction | J | DOI 10.1145/96709.96711 | `papers/lamping-1990-optimal-reduction/` | resolved-id | ACM © verify |
| `code-hvm` | HVM2 source + docs | J | pinned GitHub `7365a56c…` | `sources/code/hvm/` | planned | verify |
| `code-bend` | Bend source + docs | J | pinned GitHub `574b6d39…` | `sources/code/bend/` | planned | verify |
| `inpla-inets` | Inpla / inets | J | repo/author host → pointer | `sources/pointers/inpla-inets.md` | unresolved | TBD |
| `sweep-2024-2026` | 2024–2026 POPL/PLDI/ICFP/OOPSLA/CGO + arXiv `cs.PL` sweep; record demonstrated vs claimed | J, Cross-cutting | live literature sweep in `papers-other` step | `papers/…`, notes in `INDEX.md` | planned | per paper |

## Cross-cutting additions

| Shortname | Title / path set | Thread(s) | Harvest method | Storage form | Status | License |
| --- | --- | --- | --- | --- | --- | --- |
| `code-lean4-lcnf-specinfo` | Lean 4 `LCNF` and `SpecInfo` | Cross-cutting | lean4 repo pinned at fetch time → pointer/excerpts | `sources/pointers/lean4.md`, `sources/code/lean4/` | planned | Apache-2.0 verify |
| `pointers-ocaml-flambda` | OCaml Flambda | Cross-cutting | repo/docs → pointer | `sources/pointers/ocaml-flambda.md` | planned | verify |
| `docs-ghc-stg-cmm-rts` | GHC STG/Cmm/RTS | Cross-cutting, D | GHC commentary wiki | `sources/docs/ghc/` | stored (`sources/docs/ghc/commentary-compiler-stg-syn-type.md`, `commentary-compiler-cmm-type.md`, `commentary-rts.md`, plus `core-syn-type`, `data-types`, `core-to-core-pipeline`) | BSD-3-Clause verify |
| `pointers-swift-sil` | Swift SIL | Cross-cutting | docs → pointer | `sources/pointers/swift-sil.md` | planned | Apache-2.0 verify |
| `pointers-rust-mir` | Rust MIR | Cross-cutting | docs → pointer | `sources/pointers/rust-mir.md` | planned | MIT/Apache-2.0 verify |
| `pointers-dotnet-ryujit` | .NET RyuJIT | Cross-cutting | docs → pointer | `sources/pointers/dotnet-ryujit.md` | planned | MIT verify |
| `grin` | GRIN | Cross-cutting | papers/repo → pointer | `sources/pointers/grin.md` | unresolved | TBD |
| `certicoq` | CertiCoq (see Thread I) | I, Cross-cutting *(shared)* | author/lab host | `papers/…` (TBD) | unresolved | TBD |
| `code-koka` | Koka | D, Cross-cutting | repo/docs → pointer | `sources/pointers/koka.md` | planned | verify |
| `reynolds-1972-definitional-interpreters` | Definitional interpreters for higher-order programming languages | Cross-cutting | DOI 10.1145/800194.805852 | `papers/reynolds-1972-definitional-interpreters/` | resolved-id | ACM © verify |
| `danvy-2001-defunctionalization` | Defunctionalization at work | Cross-cutting | DOI 10.1145/773184.773202 (BRICS OA) | `papers/danvy-2001-defunctionalization/` | resolved-id | BRICS OA verify |
| `cejtin-2000-defunctionalization` | Cejtin et al. (ESOP 2000) defunctionalization | Cross-cutting | DOI to confirm | `papers/…` (TBD) | unresolved | TBD |
| `huang-yallop-2023-defunctionalization` | Huang & Yallop (PLDI 2023) | Cross-cutting | DOI to confirm | `papers/…` (TBD) | unresolved | TBD |
| `secrets-ghc-inliner` | Secrets of the GHC Inliner (Peyton Jones & Marlow) | Cross-cutting | DOI unconfirmed (candidate resolves elsewhere) | `papers/…` (TBD) | unresolved | TBD |
| `docs-ghc-specialise-specConstr` | GHC `specialise`/`SpecConstr`; dictionary specialisation | Cross-cutting | GHC commentary wiki | `sources/docs/ghc/` | stored (no dedicated commentary page; captured `sources/docs/ghc/users_guide/using-optimisation.html` + `opt-ordering.md` + `core-to-core-pipeline.md`, which document `-fspecialise`/`SpecConstr` and the inliner) | BSD-3-Clause verify |
| `pointers-gmp-manual` | GMP manual | Cross-cutting | gmplib.org → pointer | `sources/pointers/gmp.md` | planned | GFDL verify |
| `pointers-modern-computer-arithmetic` | Modern Computer Arithmetic (free book) | Cross-cutting | author-hosted PDF → pointer | `sources/pointers/mca.md` | planned | free book verify |
| `code-idris-integer-string` | Idris `Integer`/`String` | Cross-cutting, E | Idris2 pinned source | `sources/code/idris2/` | planned | BSD-3-Clause verify |
| `linear-io-qtt` | linear IO in QTT | Cross-cutting, D | literature probe at collection time | `papers/…` (TBD) | unresolved | TBD |
| `algebraic-effects-handlers` | algebraic effects and handlers | Cross-cutting, D | literature probe at collection time | `papers/…` (TBD) | unresolved | TBD |

## `sources/docs/` — official documentation snapshots

| Shortname | Path set | Thread(s) | Harvest method | Storage form | Status | License |
| --- | --- | --- | --- | --- | --- | --- |
| `docs-mlir-llvm` | all `mlir/docs/**`; `mlir/include/mlir/Transforms/Passes.td`; dialect docs (arith, builtin, cf, func, index, linalg, llvm, memref, pdl, ptr, scf, transform, ub, vector); selected LLVM docs (LangRef, GC/Statepoints, ORC/JITLink, DataLayout, Programmer's Manual, Passes) | F, B, I | pinned tag `llvmorg-23.1.2` (`2d567403…`) via raw + tree API | `sources/docs/mlir/`, `sources/docs/llvm/` | stored (mlir/ 100 files incl. all `mlir/docs/**` + `include/mlir/Transforms/Passes.td`; llvm/ 11 files LangRef, GarbageCollection, Statepoints, ORCv2, JITLink, MCJIT, DebuggingJITedCode, ProgrammersManual, Passes, NewPassManager, WritingAnLLVMPass. CORRECTIONS: arith/cf/index/ptr/scf/ub/pdl have no standalone `.md` at this pin — ODS-generated; LLVM DataLayout has no separate file — it is in LangRef) | Apache-2.0 WITH LLVM-exception |
| `docs-idris2` | `docs/source/**` (rst), `docs/README.md`, backend docs (refc, chez, incremental, custom), `libs/**` where informative | E, D | pinned submodule `1c630e67c386629a0fbbc6b78a59176fde7f0a76` via raw | `sources/docs/idris2/` | stored (`sources/docs/idris2/docs/source/**` + `docs/README.md`, 71 files; backend docs refc/chez/incremental/custom/gambit/racket/javascript included. Fetched from pinned raw URLs because the local `third_party/Idris2` checkout was empty) | BSD-3-Clause verify |
| `docs-ghc` | GitLab commentary pages (compiler pipeline, Core, STG, Cmm, RTS, demand analysis, inliner, unarisation) + relevant `downloads.haskell.org` users-guide pages | D, E, Cross-cutting | GitLab wiki + downloads.haskell.org | `sources/docs/ghc/` | stored (`sources/docs/ghc/` 22 files: 13 commentary pages + 9 users-guide pages. CORRECTIONS: no `commentary/compiler/inliner` or `unarisation` pages exist (404) — nearest material is `core-to-core-pipeline`, `opt-ordering`, `code-gen`, `backends`) | BSD-3-Clause verify |
| `docs-mlton` | selected `doc/guide/src/*.adoc` (CompilerOverview, WholeProgramOptimization, Closure, ClosureConvert, SSA, SSA2, RSSA, SSASimplify, Contify, Useless, RemoveUnused, Flatten, DeepFlatten, GarbageCollection, Codegen, CallingFromSMLToC) | D, G | pinned GitHub `aa2fd1ad…` via raw; Wayback fallback | `sources/docs/mlton/` | stored (`sources/docs/mlton/doc/guide/src/*.adoc`, all 16 named pages) | MLton license (HPND-style) verify |
| `docs-tinygrad` | tinygrad docs and README | A, G | `docs.tinygrad.org` + pinned README | `sources/docs/tinygrad/` | stored (`sources/docs/tinygrad/` 29 files: repo `README.md` + `docs/**` .md/.py/.svg, plus the live `docs.tinygrad.org` index at snapshot time) | MIT |
| `docs-ssa-book` | SSA-based Compiler Design (free PDF) | F, B | free PDF → store once under docs | `sources/docs/ssa-book/` | stored (`sources/docs/ssa-book/ssa-based-compiler-design.pdf`, 5,257,556 bytes; retrieved via Wayback snapshot `20210621194509` because `ssabook.gforge.inria.fr` no longer resolves) | free book verify |

## `sources/code/` — selected pinned excerpts

| Shortname | Path set | Thread(s) | Harvest method | Storage form | Status | License |
| --- | --- | --- | --- | --- | --- | --- |
| `code-mlir` | `PatternMatch.h`, `OpDefinition.h`, `RewriterBase.h`, Interfaces (`include/mlir/Interfaces/*.td`), dialect conversion, dataflow framework, `Transform`, `PDL`/`PDLInterp`, `LLVMOps.td` tail-call/GC attributes; pointers for large lib trees | F, B, I | pinned tag `llvmorg-23.1.2` | `sources/code/mlir/` | stored (`sources/code/mlir/` 94 files. CORRECTIONS: `include/mlir/IR/RewriterBase.h` does not exist at this pin — `RewriterBase` is in `PatternMatch.h`; `lib/**` implementation trees => `sources/pointers/mlir-lib-trees.md`) | Apache-2.0 WITH LLVM-exception |
| `code-idris2` | `src/Core/TT.idr`, `Core/TTImp/*`, `Core/Context/Context.idr`, `Core/Case/CaseTree.idr`, `Compiler/CompileExpr.idr`, `Compiler/Erase.idr` (verify path), `Compiler/Inline.idr`, `Compiler/ANF.idr`, `Compiler/LambdaLift.idr`, `Compiler/CaseOpt.idr`, RefC/Scheme/VM backends; `detagabbleBy`, Nat/newtype handling | E, D, I, Cross-cutting | pinned submodule `1c630e67…` | `sources/code/idris2/` | stored (`sources/code/idris2/` 30 files. CORRECTIONS: `TTImp` is `src/TTImp/**` not `Core/TTImp/**`; there is no `Compiler/Erase.idr` — erasure lives in `src/Core/LinearCheck.idr` + `eraseArgs`/`safeErase` in `src/Core/Context/Context.idr`; file is `Compiler/CaseOpts.idr` not `CaseOpt.idr`; fetched from pinned raw URLs because the submodule checkout was empty) | BSD-3-Clause verify |
| `code-tinygrad` | Thread A module set | A, G | pinned GitHub `b1a9b35b…` | `sources/code/tinygrad/` | stored (`sources/code/tinygrad/` 19 files: the Thread A module set plus `codegen/opt/search.py` — the BEAM search module located at the pin — and `codegen/opt/heuristic.py`) | MIT |
| `code-mlton` | selected pass sources (`closure-convert`, `ssa` contify/useless/remove-unused, `rssa` representation/layout) | D, G | pinned GitHub `aa2fd1ad…` | `sources/code/mlton/` | stored (`sources/code/mlton/` 16 files: `mlton/closure-convert/*`, `mlton/ssa/{contify,useless,remove-unused,inline,ssa-tree,ssa2}.fun`, `mlton/backend/{ssa2-to-rssa,rssa,packed-representation,machine}.{fun,sig}` — RSSA lives under `mlton/backend/`, not a `mlton/rssa/` dir) | MLton license (HPND-style) verify |
| `pointers-ghc` | GHC pin pointers only + a few key `.hs` excerpts if small | D, E, Cross-cutting | GHC repo pin / GitLab wiki | `sources/pointers/ghc.md`, `sources/code/ghc/` | pointer (`sources/pointers/ghc.md`; no `sources/code/ghc/` excerpts this pass) | BSD-3-Clause verify |

---

## Notes for the collection steps

- Do not duplicate a paper across threads; use the *(shared)* markers to cross-link.
- Store PDFs only when no TeX/source exists (plan rule). Skip generated files and anything > 20 MB.
- Every row that lands content must get its resolved commit/hash recorded in `ACCESS.md` or `INDEX.md`.
- `unresolved` rows are collected in `ACCESS.md` §3c with the reason; re-attempt them in the
  `papers-other` step before giving up.
