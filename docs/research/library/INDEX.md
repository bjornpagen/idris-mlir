# Research library index

Every paper the library holds or catalogues, by topic, with the code and documentation
snapshots each topic draws on. Topics: [Memory](#memory),
[Specialization](#specialization), [Rewriting](#rewriting), [MLIR](#mlir),
[Arrays and scheduling](#arrays-and-scheduling), [Verification](#verification),
[Types and quantities](#types-and-quantities).

Each paper appears once, under its main topic; a topic's "Also" line names papers filed
elsewhere that serve it too. Per entry: the folder (or shortname when nothing is stored),
title, authors, venue and year, canonical link, what is stored, the collection threads,
licence and status. The provenance of each stored copy is in its folder's `README.md`;
identifiers, access, pins, licences, and the record for papers not stored are in
[README.md](README.md). Paths below are relative to this folder.

Storage rule: raw LaTeX source is preferred; a PDF (or PostScript) is stored only when no
TeX source exists. Every stored file is under the 20 MB per-file cap and no generated LaTeX
artefacts remain. Licences marked `unknown–verify` were not confirmed from the publisher:
confirm before redistributing.

## Summary

| Outcome | Count |
| --- | --- |
| Stored as TeX source (arXiv e-prints) | 20 |
| Stored as PDF | 30 |
| Stored as PostScript | 1 |
| **Papers stored** | **51** |
| Book stored as a documentation snapshot (`docs/ssa-book/`) | 1 |
| Link only (identifier known, no copy stored) | 30 |
| Unresolved (no identifier or copy located, or no canonical reference chosen) | 26 rows |

Five paper folders hold two copies that differ (other host or version):
`adams-2019-halide-learning`, `ikarashi-2022-exo`, `kjolstad-2017-taco`,
`leroy-2009-compcert`, `marshall-2022-linearity-uniqueness`.

## Threads

The collection passes filed every source under a thread of the first-principles
optimization study; the "Threads" column keeps that filing.

| Thread | Subject | Topic here |
| --- | --- | --- |
| A | Tinygrad and first-order dataflow optimizers | Arrays and scheduling |
| B | Equality saturation and rewriting | Rewriting |
| C | Staging, partial evaluation, supercompilation, fusion | Specialization |
| D | Memory from QTT | Memory |
| E | Representation from dependent types | Types and quantities |
| F | MLIR with and without C++ | MLIR |
| G | Arrays and kernels with shape types | Arrays and scheduling |
| H | Search and cost models | Rewriting |
| I | Proved optimizations | Verification |
| J | Bleeding edge, evaluated critically | Rewriting |
| Cross-cutting | Compiler prior art, defunctionalisation, specialisation, bignums, effects | by subject |

## Memory

Reference counting and reuse, linearity and uniqueness, evaluation models (thread D, with
the cross-cutting STG and eval/apply papers).

| Paper | Title | Authors | Venue / year | Link | Stored | Threads | Licence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [`ullrich-2019-counting-immutable-beans`](papers/ullrich-2019-counting-immutable-beans/) | Counting Immutable Beans: Reference Counting Optimized for Purely Functional Programming | Ullrich, de Moura | IFL 2019 | https://arxiv.org/abs/1908.05647 | TeX (arXiv 1908.05647) | D | arXiv non-exclusive | stored |
| [`reinking-2021-perceus`](papers/reinking-2021-perceus/) | Perceus: garbage free reference counting with reuse | Reinking, Xie, de Moura, Leijen | PLDI 2021 | https://doi.org/10.1145/3453483.3454032 | PDF (MSR technical report, `perceus-tr-v4.pdf`) | D | ACM CC-BY; none stated on the TR copy | stored (OA pass; papers pass: link-only, CC-BY but only on `dl.acm.org` 403); resolved-corrected |
| [`lorenzen-2023-fp2`](papers/lorenzen-2023-fp2/) | FP²: Fully in-Place Functional Programming | Lorenzen, Leijen, Swierstra | ICFP 2023 | https://doi.org/10.1145/3607840 | PDF (Utrecht repository, submitted version) | D | ACM CC-BY; Utrecht copy other-oa (Unpaywall) | stored (OA pass; papers pass: link-only, ACM 403, Utrecht record exposes no direct PDF) |
| [`bernardy-2018-linear-haskell`](papers/bernardy-2018-linear-haskell/) | Linear Haskell: practical linearity in a higher-order polymorphic language | Bernardy, Boespflug, Newton, Peyton Jones, Spiwack | POPL 2018 | https://arxiv.org/abs/1710.09756 (DOI 10.1145/3158093) | TeX (arXiv 1710.09756) | D | arXiv non-exclusive | stored |
| [`marshall-2022-linearity-uniqueness`](papers/marshall-2022-linearity-uniqueness/) | Linearity and Uniqueness: An Entente Cordiale | Marshall, Vollmer, Orchard | ESOP 2022 | https://doi.org/10.1007/978-3-030-99336-8_13 | 2 PDFs (Springer OA; Kent repository) | D | CC-BY | stored |
| [`marshall-2024-fractional-uniqueness`](papers/marshall-2024-fractional-uniqueness/) | Functional Ownership through Fractional Uniqueness | Marshall, Orchard | OOPSLA 2024 | https://doi.org/10.1145/3649848 | PDF (Kent repository, accepted version) | D | ACM CC-BY (published); none stated on the accepted copy | stored (OA pass; unresolved before: no matching title for "fractional uniqueness") |
| [`wadler-1990-linear-types`](papers/wadler-1990-linear-types/) | Linear Types Can Change the World! | Wadler | IFIP TC2 Working Conference on Programming Concepts and Methods, 1990 | no DOI; https://homepages.inf.ed.ac.uk/wadler/papers/linear/linear.ps | PostScript (author site, `linear.ps`) | D | author-hosted, none stated | stored (OA pass; unresolved before: no DOI confirmed) |
| [`peytonjones-1992-stg`](papers/peytonjones-1992-stg/) | Implementing lazy functional languages on stock hardware: the Spineless Tagless G-machine | Peyton Jones | JFP 1992 | https://doi.org/10.1017/S0956796800000319 | PDF (Cambridge Core OA) | D, cross-cutting | CUP © unknown–verify | stored |
| [`marlow-2006-fast-curry`](papers/marlow-2006-fast-curry/) | Making a fast curry: push/enter vs. eval/apply for higher-order languages | Marlow, Peyton Jones | JFP 2006 (ICFP 2004) | https://doi.org/10.1017/S0956796806005995 | PDF (Cambridge Core OA) | D | CUP © unknown–verify | stored |
| [`leijen-2017-koka-effects`](papers/leijen-2017-koka-effects/) | Type directed compilation of row-typed algebraic effects | Leijen | POPL 2017 | https://doi.org/10.1145/3009837.3009872 | PDF (MSR author page) | D, cross-cutting | ACM © unknown–verify; none stated on the copy | stored (OA pass; papers pass: link-only, ACM 403) |

| Shortname | Title | Authors | Venue / year | Link | Threads | Licence | Status / reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `lorenzen-2022-frame-limited-reuse` | Reference counting with frame limited reuse | Lorenzen, Leijen | ICFP 2022 | https://doi.org/10.1145/3547634 | D | ACM CC-BY | link-only (ACM 403; the CC-BY copy is only on `dl.acm.org`) |
| `lorenzen-2024-oxidizing-ocaml` | Oxidizing OCaml with Modal Memory Management | Lorenzen, White, Dolan, Eisenberg, Lindley | ICFP 2024 | https://doi.org/10.1145/3674642 | D | ACM CC-BY | link-only (ACM 403; Edinburgh green OA returned 403) |
| `blackburn-2008-immix` | Immix: a mark-region garbage collector with space efficiency, fast collection, and mutator performance | Blackburn, McKinley | ISMM 2008 | https://doi.org/10.1145/1375581.1375586 | D | ACM © unknown–verify | link-only (ACM 403; ANU repository 503, author-site guess 404) |

| Unresolved | Threads | Status / reason |
| --- | --- | --- |
| Garbage Collection Handbook | D | book; no OA. Pointer only (`gc-handbook.md` was planned and not written). |
| Boehm GC; "precise tracing GC" | D | tech report / project pages; no single canonical paper selected. Pointers only (`boehm-gc.md` planned, not written). |
| Destination-passing style | D | no specific canonical reference selected. |
| Koka effect types (additional papers) | D | only Leijen POPL 2017 resolved (stored above); other Koka material is docs/code (`code-koka`, not collected). |
| Linear IO in QTT | cross-cutting, D | literature probe at collection time; not run. |
| Algebraic effects and handlers | cross-cutting, D | literature probe at collection time; not run. |

**Also:** `hovgaard-2018-defunctionalisation` and `danvy-2001-defunctionalization`
(Specialization) for closure representation; `brady-2021-idris2-qtt` (Types and
quantities) for what quantities mean.

**Snapshots.**
- `code/idris2/src/Core/LinearCheck.idr` (erasure inference),
  `src/Core/Context/Context.idr` (`eraseArgs`/`safeErase`),
  `src/Compiler/{Inline,ANF,LambdaLift,CaseOpts}.idr`, `src/Compiler/RefC/**`.
- `docs/idris2/docs/source/backends/**`,
  `docs/ghc/commentary-compiler-{stg-syn-type,cmm-type,demand}.md`,
  `docs/ghc/commentary-rts.md`.
- `code/mlir/include/mlir/Dialect/LLVMIR/LLVMOps.td` (tail-call and GC attributes;
  cross-cutting), `docs/llvm/docs/{GarbageCollection.md,Statepoints.rst}`.
- MLton (threads D, G): `code/mlton/` (closure conversion, RSSA representation) and
  `docs/mlton/` (including `GarbageCollection.adoc`).

**Read first:** `reinking-2021-perceus`, `lorenzen-2023-fp2`,
`ullrich-2019-counting-immutable-beans`, `code/idris2/src/Core/LinearCheck.idr`; for the
evaluation model, `peytonjones-1992-stg`.

**Claims these settle:** how reference counting with reuse is specified; what QTT
multiplicities do and do **not** imply about heap ownership; what Idris 2 already
implements; the STG evaluation model.

## Specialization

Staging, partial evaluation, supercompilation, fusion (thread C) and defunctionalisation and
inlining (cross-cutting).

| Paper | Title | Authors | Venue / year | Link | Stored | Threads | Licence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [`kovacs-2022-staged`](papers/kovacs-2022-staged/) | Staged Compilation with Two-Level Type Theory | Kovács | ICFP 2022 | https://arxiv.org/abs/2209.09729 | TeX (arXiv 2209.09729) | C | arXiv non-exclusive | stored (resolved-corrected) |
| [`kovacs-2024-closure-free`](papers/kovacs-2024-closure-free/) | Closure-Free Functional Programming in a Two-Level Type Theory | Kovács | ICFP 2024 | https://doi.org/10.1145/3674648 | PDF (author site) | C | ACM CC-BY | stored (OA pass; papers pass: link-only, ACM 403, Chalmers record exposes no PDF) |
| [`sorensen-1996-positive-supercompiler`](papers/sorensen-1996-positive-supercompiler/) | A positive supercompiler | Sørensen, Glück, Jones | JFP 1996 | https://doi.org/10.1017/S0956796800002008 | PDF (Cambridge Core OA) | C | CUP © unknown–verify | stored |
| [`mitchell-2010-rethinking-supercompilation`](papers/mitchell-2010-rethinking-supercompilation/) | Rethinking supercompilation | Mitchell | ICFP 2010 | https://doi.org/10.1145/1863543.1863588 | PDF (author site) | C | ACM © unknown–verify; none stated on the copy | stored (OA pass; papers pass: link-only, ACM 403) |
| [`danvy-2001-defunctionalization`](papers/danvy-2001-defunctionalization/) | Defunctionalization at work | Danvy, Nielsen | PPDP 2001 | https://doi.org/10.7146/brics.v8i23.21684 (PPDP: 10.1145/773184.773202) | PDF (BRICS OA) | cross-cutting | BRICS OA (verify) | stored |
| [`huang-2023-defunctionalization`](papers/huang-2023-defunctionalization/) | Defunctionalization with Dependent Types | Huang, Yallop | PLDI 2023 | https://doi.org/10.1145/3591241 | PDF (author site, accepted version) | cross-cutting | ACM CC-BY | stored (OA pass; unresolved before: DOI to confirm) |
| [`hovgaard-2018-defunctionalisation`](papers/hovgaard-2018-defunctionalisation/) | High-Performance Defunctionalisation in Futhark | Hovgaard, Henriksen, Elsman | TFP 2018 (LNCS 11457, 2019) | https://doi.org/10.1007/978-3-030-18506-0_7 | PDF (futhark-lang.org) | G, cross-cutting | Springer ©; none stated on the copy | stored (OA pass; unresolved before: DOI not verified) |

| Shortname | Title | Authors | Venue / year | Link | Threads | Licence | Status / reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `turchin-1986-supercompiler` | The concept of a supercompiler | Turchin | TOPLAS 1986 | https://doi.org/10.1145/5956.5957 | C | ACM © unknown–verify | link-only (ACM 403; bronze OA only on `dl.acm.org`) |
| `bolingbroke-2010-supercompilation-by-eval` | Supercompilation by evaluation | Bolingbroke, Peyton Jones | Haskell 2010 | https://doi.org/10.1145/1863523.1863540 | C | ACM © unknown–verify | link-only (ACM 403; closed, only CiteSeerX stubs) |
| `wadler-1990-deforestation` | Deforestation: transforming programs to eliminate trees | Wadler | TCS 1990 | https://doi.org/10.1016/0304-3975(90)90147-A | C | Elsevier © unknown–verify | link-only (ScienceDirect PDF returned HTTP 403, contrary to the access record) |
| `gill-1993-short-cut` | A short cut to deforestation | Gill, Launchbury, Peyton Jones | FPCA 1993 | https://doi.org/10.1145/165180.165214 | C | ACM © unknown–verify | link-only (ACM 403; gold OA only on `dl.acm.org`) |
| `coutts-2007-stream-fusion` | Stream fusion: from lists to streams to nothing at all | Coutts, Leshchinskiy, Stewart | ICFP 2007 | https://doi.org/10.1145/1291151.1291199 | C | ACM © unknown–verify | link-only (ACM 403; closed, MSR copy 403) |
| `taha-2000-metaml` | MetaML and multi-stage programming with explicit annotations | Taha, Sheard | TCS 2000 | https://doi.org/10.1016/S0304-3975(00)00053-0 | C | Elsevier © unknown–verify | link-only (ScienceDirect PDF returned HTTP 403, contrary to the access record) |
| `taha-2004-gentle-intro-multistage` | A Gentle Introduction to Multi-stage Programming | Taha | 2004 | https://doi.org/10.1007/978-3-540-25935-0_3 | C | Springer © unknown–verify | link-only (Springer landing not OA) |
| `rompf-2010-lms` | Lightweight modular staging: a pragmatic approach to runtime code generation and compiled DSLs | Rompf, Odersky | GPCE 2010 | https://doi.org/10.1145/1868294.1868314 | C | ACM © unknown–verify | link-only (ACM 403) |
| `wurthinger-2013-one-vm` | One VM to rule them all | Würthinger, Wimmer, Wöß, Stadler, Duboscq, Humer | Onward! 2013 | https://doi.org/10.1145/2509578.2509581 | C | ACM © unknown–verify | link-only (ACM 403) |
| `wurthinger-2017-practical-partial-eval` | Practical partial evaluation for high-performance dynamic language runtimes | Würthinger, Wimmer, Humer, Wöß, Stadler, Seaton | PLDI 2017 | https://doi.org/10.1145/3062341.3062381 | C | ACM © unknown–verify | link-only (ACM 403) |
| `christiansen-2016-elaborator-reflection` | Elaborator reflection: extending Idris in Idris | Christiansen, Brady | ICFP 2016 | https://doi.org/10.1145/2951913.2951932 | C | ACM © unknown–verify | link-only (ACM 403; St Andrews repository returned 503) |
| `reynolds-1972-definitional-interpreters` | Definitional interpreters for higher-order programming languages | Reynolds | ACM 1972 | https://doi.org/10.1145/800194.805852 | cross-cutting | ACM © unknown–verify | link-only (ACM 403; Syracuse page has no direct PDF) |
| `cejtin-2000-defunctionalization` | Flow-Directed Closure Conversion for Typed Languages | Cejtin, Jagannathan, Weeks | ESOP 2000 | https://doi.org/10.1007/3-540-46425-5_4 | cross-cutting | Springer © | link-only (closed; DOI resolved by the OA pass, unresolved before) |
| `secrets-ghc-inliner` | Secrets of the Glasgow Haskell Compiler inliner | Peyton Jones, Marlow | JFP 2002 | https://doi.org/10.1017/S0956796802004331 | cross-cutting | CUP © | link-only (closed; DOI resolved by the OA pass: the earlier candidate `10.1017/S0956796801004270` was an unrelated paper) |

| Unresolved | Threads | Status / reason |
| --- | --- | --- |
| Warm fusion; shortcut fusion | C | no specific canonical paper selected in the plan; confirm the intended references. |
| Futamura, "Partial evaluation of computation process" (1971) | C | classic journal article with no DOI or OA copy located. |
| Christiansen PhD thesis | C | no stable OA URL located. |
| Jones, Gomard, Sestoft, *Partial Evaluation and Automatic Program Generation* (book) | C | free author-hosted PDF; store as pointer or fetch the PDF (`pe-book.md` planned, not written). |

**Also:** `leijen-2017-koka-effects` (Memory); `chen-2018-tvm` and
`ragankelley-2013-halide` (Arrays and scheduling) for schedule-driven code generation.

**Snapshots.**
- `docs/ghc/commentary-compiler-{core-to-core-pipeline,opt-ordering,code-gen,backends}.md`,
  `docs/ghc/users_guide/using-optimisation.html` (`-fspecialise`, `SpecConstr`, the
  inliner); the GHC pointer in `docs/ghc/SNAPSHOT.md`.
- `code/idris2/src/Compiler/{Inline,LambdaLift}.idr`; `code/mlton/mlton/closure-convert/`.

**Read first:** `turchin-1986-supercompiler` and `kovacs-2022-staged` (the two poles of
supercompilation and staging), `coutts-2007-stream-fusion` (fusion in practice),
`mitchell-2010-rethinking-supercompilation`; for defunctionalisation and inlining,
`danvy-2001-defunctionalization`, `huang-2023-defunctionalization`, and
`secrets-ghc-inliner` once obtained.

**Claims these settle:** what supercompilation and fusion actually promise; when staging
resolves overhead; the cost and benefit a report can attribute to each;
defunctionalisation techniques and their typed variants; how GHC's inliner and specialiser
are architected.

## Rewriting

Equality saturation (B), search, superoptimization and cost models (H), and interaction
nets and optimal reduction (J).

| Paper | Title | Authors | Venue / year | Link | Stored | Threads | Licence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [`willsey-2021-egg`](papers/willsey-2021-egg/) | egg: Fast and Extensible Equality Saturation | Willsey, Nandi, Wang, Flatt, Tatlock, Panchekha | POPL 2021 | https://arxiv.org/abs/2004.03082 | TeX (arXiv 2004.03082) | B | arXiv non-exclusive | stored |
| [`zhang-2023-egglog`](papers/zhang-2023-egglog/) | Better Together: Unifying Datalog and Equality Saturation | Zhang, Wang, Flatt, Cao, Zucker, Rosenthal, Tatlock, Willsey | PLDI 2023 | https://arxiv.org/abs/2304.04332 | TeX (arXiv 2304.04332) | B | arXiv non-exclusive | stored |
| [`zhang-2022-relational-ematching`](papers/zhang-2022-relational-ematching/) | Relational E-Matching | Zhang, Wang, Willsey, Tatlock | POPL 2022 | https://arxiv.org/abs/2108.02290 | TeX (arXiv 2108.02290) | B | arXiv non-exclusive | stored |
| [`wang-2020-spores`](papers/wang-2020-spores/) | SPORES: Sum-Product Optimization via Relational Equality Saturation for Large Scale Linear Algebra | Wang, Hutchison, Leang, et al. | arXiv 2020 (VLDB 2020) | https://arxiv.org/abs/2002.07951 | TeX (arXiv 2002.07951) | B | arXiv non-exclusive | stored (resolved-corrected) |
| [`koehler-2021-sketch-eqsat`](papers/koehler-2021-sketch-eqsat/) | Sketch-Guided Equality Saturation: Scaling Equality Saturation to Complex Optimizations of Functional Programs | Koehler, Trinder, Steuwer | OOPSLA 2021 | https://arxiv.org/abs/2111.13040 | TeX (arXiv 2111.13040) | B | arXiv non-exclusive | stored |
| [`wu-2026-slotted-egraphs`](papers/wu-2026-slotted-egraphs/) | Typed Flexible-Arity Slotted E-Graphs: A Soundness Construction and an Alloy Case Study | Wu, Sullivan | arXiv 2026 | https://arxiv.org/abs/2609.03998 | TeX (arXiv 2609.03998) | B | arXiv non-exclusive | stored (future-dated ID verified 200) |
| [`pal-2023-ruler`](papers/pal-2023-ruler/) | Equality Saturation Theory Exploration à la Carte (Ruler) | Pal, Saiki, Tjoa, Richey, Zhu, Flatt, Willsey, Tatlock, Nandi | OOPSLA 2023 | https://doi.org/10.1145/3622834 (arXiv https://arxiv.org/abs/2609.14527) | TeX (arXiv 2609.14527) | B | arXiv non-exclusive (ACM version CC-BY) | stored (arXiv parallel located); resolved-corrected (published title differs from the plan's "Ruler") |
| [`yang-2021-tensat`](papers/yang-2021-tensat/) | Equality Saturation for Tensor Graph Superoptimization (Tensat) | Yang, Phothilimthana, Wang, et al. | arXiv 2021 (MLSys 2021) | https://arxiv.org/abs/2101.01332 | TeX (arXiv 2101.01332) | A, B | arXiv non-exclusive | stored (resolved-corrected) |
| [`panchekha-2015-herbie`](papers/panchekha-2015-herbie/) | Automatically improving accuracy for floating point expressions (Herbie) | Panchekha, Sanchez-Stern, Wilcox, Tatlock | PLDI 2015 | https://doi.org/10.1145/2737924.2737959 | PDF (Herbie project site) | B | ACM © unknown–verify; none stated on the copy | stored (OA pass; papers pass: link-only, ACM 403, author-site guess 404) |
| [`sasnauskas-2017-souper`](papers/sasnauskas-2017-souper/) | Souper: A Synthesizing Superoptimizer | Sasnauskas, Chen, Collingbourne, Ketema, Lup, Taneja, Regehr | arXiv 2017 | https://arxiv.org/abs/1711.04422 | TeX (arXiv 1711.04422) | H | arXiv non-exclusive | stored |
| [`schkufza-2013-stoke`](papers/schkufza-2013-stoke/) | Stochastic superoptimization (STOKE) | Schkufza, Sharma, Aiken | ASPLOS 2013 | https://doi.org/10.1145/2451116.2451150 | PDF (author site) | H | unknown–verify | stored |
| [`mendis-2019-ithemal`](papers/mendis-2019-ithemal/) | Ithemal: Accurate, Portable and Fast Basic Block Throughput Estimation using Deep Neural Networks | Mendis, Renda, Amarasinghe, Carbin | ICML 2019 | https://arxiv.org/abs/1808.07412 | TeX (arXiv 1808.07412) | H | arXiv non-exclusive | stored |

| Shortname | Title | Authors | Venue / year | Link | Threads | Licence | Status / reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `koehler-2024-guided-eqsat` | Guided Equality Saturation | Koehler, Goens, Bhat, Grosser, Trinder, Steuwer | POPL 2024 | https://doi.org/10.1145/3632900 | B | ACM © unknown–verify | link-only (ACM 403); resolved-corrected; the related sketch paper is stored at `koehler-2021-sketch-eqsat` |
| `massalin-1987-superoptimizer` | Superoptimizer: a look at the smallest program | Massalin | ASPLOS 1987 | https://doi.org/10.1145/36206.36194 | H | ACM © unknown–verify | link-only (ACM 403; gold OA only on `dl.acm.org`) |
| `bansal-2006-peephole-superoptimizer` | Automatic generation of peephole superoptimizers | Bansal, Aiken | ASPLOS 2006 | https://doi.org/10.1145/1168918.1168906 | H | ACM © unknown–verify | link-only (ACM 403) |
| `joshi-2002-denali` | Denali: A Goal-directed Superoptimizer | Joshi, Nelson, Randall | PLDI 2002 | https://doi.org/10.1145/512529.512566 | H | ACM © unknown–verify | link-only (ACM 403) |
| `lafont-1990-interaction-nets` | Interaction nets | Lafont | POPL 1990 | https://doi.org/10.1145/96709.96718 | J | ACM © unknown–verify | link-only (ACM 403) |
| `lamping-1990-optimal-reduction` | An algorithm for optimal lambda calculus reduction | Lamping | POPL 1990 | https://doi.org/10.1145/96709.96711 | J | ACM © unknown–verify | link-only (ACM 403; gold OA only on `dl.acm.org`) |
| `lafont-1997-interaction-combinators` | Interaction Combinators | Lafont | Information and Computation 1997 | https://doi.org/10.1006/inco.1997.2643 | J | Elsevier © | link-only (ScienceDirect 403; DOI resolved by the OA pass, unresolved before) |

| Unresolved | Threads | Status / reason |
| --- | --- | --- |
| E-graph extraction (ILP/MaxSAT) work (`extraction-ilp-maxsat`); e-graph extraction cost models (`egraph-extraction-cost`) | B, H | the plan gives no author or title; the literature probe was not run. |
| MLGO / CompilerGym (`mlgo-compilergym`); autotuning and beam-search surveys (`autotuning-surveys`) | H | no specific canonical references selected (`mlgo-compilergym.md` pointer planned, not written). |
| Learned cost models (`learned-cost-models`) | H | references to confirm; the literature probe was not run. |
| Inpla / inets (`inpla-inets`) | J | no specific canonical reference selected (`inpla-inets.md` pointer planned, not written). |
| 2024–2026 POPL/PLDI/ICFP/OOPSLA/CGO + arXiv cs.PL sweep (`sweep-2024-2026`) | J, cross-cutting | cannot be pre-enumerated; to be run as a live sweep recording demonstrated vs claimed; not run. |

**Also:** `bhat-2024-verifying-peephole` (Verification), `lucke-2024-transform-dialect`
(MLIR), `jia-2019-taso` and `chen-2018-tvm` (Arrays and scheduling), and the SSA book
(`docs/ssa-book/`) for rewriting in SSA and PDL.

**Snapshots.**
- `code/mlir/include/mlir/IR/PatternMatch.h`, `code/mlir/include/mlir/Dialect/Transform/**`,
  `code/mlir/include/mlir/Transforms/*` (greedy driver, dialect conversion).
- `docs/mlir/docs/{PatternRewriter,DialectConversion,Canonicalization,DeclarativeRewrites}.md`.
- `code/tinygrad/tinygrad/uop/ops.py` and `codegen/simplify.py` (the rewrite-rule system and
  symbolic simplifier); `code/tinygrad/tinygrad/codegen/opt/{search,heuristic}.py` (BEAM
  search).
- Not vendored: the egg and egglog repositories, DialEgg and MLIR `eqsat` sources, HVM2 and
  Bend (planned; pins in [README.md](README.md#pins)).

**Read first:** `willsey-2021-egg` (e-graphs and rebuilding),
`zhang-2022-relational-ematching` (e-matching), `koehler-2021-sketch-eqsat`
(sketch-guided), `pal-2023-ruler` (ruleset inference); `massalin-1987-superoptimizer`,
`schkufza-2013-stoke`, `mendis-2019-ithemal`, `code/tinygrad/tinygrad/codegen/opt/search.py`;
`lafont-1990-interaction-nets`, `lamping-1990-optimal-reduction`,
`lafont-1997-interaction-combinators`.

**Claims these settle:** e-graph invariants and rebuild cost; e-matching complexity; how
rules are discovered rather than hand-written; where extraction fits; the superoptimizer
lineage; stochastic search; learned vs analytic cost models; a concrete beam-search
implementation to compare against; what interaction nets and combinators actually reduce,
and what optimal reduction costs (claims to be judged demonstrated vs claimed).

## MLIR

MLIR with and without C++ (thread F).

| Paper | Title | Authors | Venue / year | Link | Stored | Threads | Licence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [`lattner-2020-mlir`](papers/lattner-2020-mlir/) | MLIR: A Compiler Infrastructure for the End of Moore's Law | Lattner, Amini, Bondhugula, Cohen, Davis, Pienaar, Riddle, Shpeisman, Vasilache, Zinenko | arXiv 2020 | https://arxiv.org/abs/2002.11054 | TeX (arXiv 2002.11054) | F | arXiv non-exclusive | stored |
| [`bhat-2022-lambda-ultimate-ssa`](papers/bhat-2022-lambda-ultimate-ssa/) | Lambda the Ultimate SSA: Optimizing Functional Programs in SSA | Bhat, Grosser | CGO 2022 | https://arxiv.org/abs/2201.07272 (DOI 10.1109/CGO53902.2022.9741279) | TeX (arXiv 2201.07272) | F, I | arXiv non-exclusive | stored |
| [`lucke-2024-transform-dialect`](papers/lucke-2024-transform-dialect/) | The MLIR Transform Dialect. Your compiler is more powerful than you think | Lücke, Zinenko, Moses, Steuwer, Cohen | arXiv 2024 (CGO 2025-adjacent) | https://arxiv.org/abs/2409.03864 | TeX (arXiv 2409.03864) | F | arXiv non-exclusive | stored |
| [`fehr-2022-irdl`](papers/fehr-2022-irdl/) | IRDL: an IR definition language for SSA compilers | Fehr, Niu, Riddle, Amini, Su, Grosser | PLDI 2022 | https://doi.org/10.1145/3519939.3523700 | PDF (ETH Zurich repository, submitted version) | F | ACM CC-BY-ND | stored (OA pass; papers pass: link-only, ACM 403, ETH repository returned 500) |
| [`ssa-book`](docs/ssa-book/) | SSA-based Compiler Design (book) | Rastello, Bouchez Tichadou (eds.) | Springer 2022 | https://web.archive.org/web/2023id_/https://ssabook.gforge.inria.fr/latest/book.pdf | PDF (Wayback snapshot `20210621194509`), a documentation snapshot | F, B | free book (verify) | stored (the access pass listed it unresolved: store as pointer) |

| Shortname | Title | Authors | Venue / year | Link | Threads | Licence | Status / reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `mlir-cgo-2021` | MLIR: Scaling Compiler Infrastructure for Domain Specific Computation | Lattner, Amini, Bondhugula, Cohen, Davis, Pienaar, Riddle, Shpeisman, Vasilache, Zinenko | CGO 2021 | https://doi.org/10.1109/CGO51591.2021.9370308 | F | IEEE © | link-only (closed; DOI resolved by the OA pass, unresolved before) |

**Also:** `bhat-2024-verifying-peephole` (Verification, lean-mlir).

**Snapshots.**
- `code/mlir/include/mlir/IR/PatternMatch.h` (declares `RewriterBase`), `IR/OpDefinition.h`,
  `Transforms/{DialectConversion,GreedyPatternRewriteDriver,Passes}.*`, `Interfaces/*.td`,
  `Dialect/{PDL,PDLInterp,Transform,LLVMIR}/**`; the un-vendored `lib/` trees and their pin
  in `code/mlir/SNAPSHOT.md`.
- `docs/mlir/**` (100 files, all of `mlir/docs/**`), `docs/llvm/docs/**` (11 files).
- Not collected: Mojo docs, IREE docs, Polygeist (see [README.md](README.md#planned-sources-not-collected)).

**Read first:** `lattner-2020-mlir`, `lucke-2024-transform-dialect`,
`code/mlir/include/mlir/IR/PatternMatch.h`,
`code/mlir/include/mlir/Dialect/Transform/IR/TransformDialect.td`.

**Claims these settle:** MLIR's rewrite and rewriter design; the Transform dialect's
separation of schedule from transform; the dialect-conversion machinery a compiler might
reuse.

## Arrays and scheduling

Tinygrad and first-order dataflow optimizers (A) and arrays and kernels with shape types (G).

| Paper | Title | Authors | Venue / year | Link | Stored | Threads | Licence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [`zheng-2020-ansor`](papers/zheng-2020-ansor/) | Ansor: Generating High-Performance Tensor Programs for Deep Learning | Zheng, Jia, Sun, Wu, Yu, Haj-Ali, Wang, Yang, Zhuo, Sen, Gonzalez, Stoica | OSDI 2020 | https://arxiv.org/abs/2006.06762 | TeX (arXiv 2006.06762) | A, G | arXiv non-exclusive | stored |
| [`chen-2018-tvm`](papers/chen-2018-tvm/) | TVM: An Automated End-to-End Optimizing Compiler for Deep Learning | Chen et al. | OSDI 2018 | https://doi.org/10.5555/3291168.3291211 (arXiv https://arxiv.org/abs/1802.04799) | TeX (arXiv 1802.04799) | A, G | arXiv non-exclusive (preprint) | stored |
| [`jia-2019-taso`](papers/jia-2019-taso/) | TASO: optimizing deep learning computation with automatic generation of graph substitutions | Jia, Padon, Thomas, Warszawski, Zaharia, Aiken | SOSP 2019 | https://doi.org/10.1145/3341301.3359630 | PDF (author site) | A | ACM © unknown–verify; none stated on the copy | stored (OA pass; papers pass: link-only, ACM 403) |
| [`henriksen-2017-futhark`](papers/henriksen-2017-futhark/) | Futhark: purely functional GPU-programming with nested parallelism and in-place array updates | Henriksen, Serup, Elsman, Henglein, Oancea | PLDI 2017 | https://doi.org/10.1145/3062341.3062354 | PDF (author/lab site) | G | unknown–verify | stored |
| [`kjolstad-2017-taco`](papers/kjolstad-2017-taco/) | The tensor algebra compiler (TACO) | Kjølstad, Kamil, Chou, Lugato, Amarasinghe | OOPSLA 2017 | https://doi.org/10.1145/3133901 | 2 PDFs (DSpace@MIT; DSpace submitted version) | G | CC-BY (MIT OA) | stored |
| [`shivers-2019-remora`](papers/shivers-2019-remora/) | Introduction to Rank-polymorphic Programming in Remora (Draft) | Shivers, Slepak, Manolios | arXiv 2019 | https://arxiv.org/abs/1912.13451 | TeX (arXiv 1912.13451) | G | arXiv non-exclusive | stored |
| [`ragankelley-2013-halide`](papers/ragankelley-2013-halide/) | Halide: a language and compiler for optimizing parallelism, locality, and recomputation in image processing pipelines | Ragan-Kelley, Barnes, Adams, Paris, Durand, Amarasinghe | PLDI 2013 | https://doi.org/10.1145/2499370.2462176 | PDF (DSpace@MIT) | G | CC-BY-NC-SA (MIT OA) | stored |
| [`mullapudi-2016-halide-autosched`](papers/mullapudi-2016-halide-autosched/) | Automatically scheduling halide image processing pipelines | Mullapudi, Adams, Sharlet, Ragan-Kelley, Fatahalian | SIGGRAPH 2016 | https://doi.org/10.1145/2897824.2925952 | PDF (CMU project site) | G | ACM © unknown–verify; none stated on the copy | stored (OA pass; papers pass: link-only, ACM 403) |
| [`adams-2019-halide-learning`](papers/adams-2019-halide-learning/) | Learning to optimize halide with tree search and random programs | Adams, Ma, Anderson, Baghdadi, Li, et al. | SIGGRAPH 2019 | https://doi.org/10.1145/3306346.3322967 | 2 PDFs (eScholarship green OA; halide-lang.org) | G | unknown–verify | stored |
| [`ikarashi-2022-exo`](papers/ikarashi-2022-exo/) | Exocompilation for productive programming of hardware accelerators (Exo) | Ikarashi, Bernstein, Reinking, Genc, Ragan-Kelley | PLDI 2022 | https://doi.org/10.1145/3519939.3523446 | 2 PDFs (DSpace@MIT; DSpace submitted version) | G | CC-BY-NC (MIT OA) | stored (resolved-corrected) |

| Unresolved | Threads | Status / reason |
| --- | --- | --- |
| Henriksen PhD thesis | G | no OA URL located (likely `futhark-lang.org` or DIKU). |
| SaC | G | no specific canonical reference selected. |
| Dex papers and index sets (`dex-papers`) | G | specific references to identify; literature probe not run. |
| Halide (PLDI/SIGGRAPH 2012) (`halide-2012`) | G | reference to confirm; literature probe not run. |

**Also:** `yang-2021-tensat` (Rewriting), `hovgaard-2018-defunctionalisation`
(Specialization), `mendis-2019-ithemal` (Rewriting, cost models).

**Snapshots.**
- `code/tinygrad/tinygrad/uop/{ops,upat,spec,symbolic,render,validate}.py`,
  `codegen/simplify.py`, `codegen/opt/search.py`,
  `schedule/{prepare,rangeify,indexing,memory,multi}.py`, `renderer/{cstyle,llvmir}.py`,
  `engine/{realize,jit}.py`; for symbolic shapes, `uop/{spec,symbolic}.py` and
  `schedule/indexing.py`.
- `docs/tinygrad/` (the repository `README.md` and `docs/**`).
- MLton (threads D, G): `code/mlton/`, `docs/mlton/`.
- Not collected: the dex-lang and Futhark sources (pins in [README.md](README.md#pins)).

**Read first:** `code/tinygrad/tinygrad/uop/ops.py` and `codegen/simplify.py`;
`codegen/opt/search.py` (the located BEAM search module); `zheng-2020-ansor` (schedule
search space); `henriksen-2017-futhark`, `kjolstad-2017-taco`, `shivers-2019-remora`,
`ragankelley-2013-halide`.

**Claims these settle:** how tinygrad performs local rewriting and beam search over a
first-order IR; its schedule and indexing algebra; the concrete rule set a report can
compare equality saturation against; rank and shape polymorphism and its lowering; how
array kernels are expressed and scheduled; the cost of separating algorithm from schedule.

## Verification

Proved optimizations (thread I).

| Paper | Title | Authors | Venue / year | Link | Stored | Threads | Licence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [`lopes-2015-alive`](papers/lopes-2015-alive/) | Provably correct peephole optimizations with Alive | Lopes, Menendez, Nagarakatte, Regehr | PLDI 2015 | https://doi.org/10.1145/2737924.2737965 | PDF (author site) | I | unknown–verify | stored |
| [`lopes-2021-alive2`](papers/lopes-2021-alive2/) | Alive2: bounded translation validation for LLVM | Lopes, Lee, Hur, Liu, Regehr | PLDI 2021 | https://doi.org/10.1145/3453483.3454030 | PDF (author site) | I | ACM © unknown–verify; none stated on the copy | stored (OA pass; papers pass: link-only, ACM 403, author-site guess 404) |
| [`leroy-2009-compcert`](papers/leroy-2009-compcert/) | Formal verification of a realistic compiler (CompCert) | Leroy | CACM 2009 | https://doi.org/10.1145/1538788.1538814 | 2 PDFs (HAL green OA; author site) | I | unknown–verify (HAL copy) | stored |
| [`bhat-2024-verifying-peephole`](papers/bhat-2024-verifying-peephole/) | Verifying Peephole Rewriting in SSA Compiler IRs | Bhat, Keizer, Hughes, Goens, Grosser | ITP 2024 | https://doi.org/10.4230/LIPIcs.ITP.2024.9 | PDF (LIPIcs DROPS) | F, I | CC-BY | stored |

| Shortname | Title | Authors | Venue / year | Link | Threads | Licence | Status / reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `pnueli-1998-translation-validation` | Translation validation | Pnueli, Siegel, Singerman | TACAS 1998 | https://doi.org/10.1007/BFb0054170 | I | Springer © unknown–verify | link-only (Springer landing not OA) |
| `certicoq` | Compositional Optimizations for CertiCoq; CertiCoq-Wasm | Paraskevopoulou, Li, Appel (compositional optimizations) | PACMPL 2021 | https://doi.org/10.1145/3473591; https://doi.org/10.1145/3703595.3705879 | I, cross-cutting | CC-BY | link-only (`dl.acm.org` 403; DOIs resolved by the OA pass, unresolved before) |

| Unresolved | Threads | Status / reason |
| --- | --- | --- |
| SMT-based rewrite verification (`smt-rewrite-verification`) | I | references to confirm; literature probe not run. |

**Also:** `bhat-2022-lambda-ultimate-ssa` (MLIR).

**Snapshots.**
- `code/idris2/src/Core/Transform.idr`, `code/idris2/src/TTImp/ProcessTransform.idr`
  (Idris `%transform`).
- `code/mlir/include/mlir/Dialect/Transform/SMTExtension/**`.

**Read first:** `lopes-2021-alive2`, `bhat-2024-verifying-peephole`, `leroy-2009-compcert`,
`code/idris2/src/Core/Transform.idr`.

**Claims these settle:** what translation validation guarantees; how rewrites are proved;
what Idris 2's `%transform` mechanism already checks.

## Types and quantities

Representation from dependent types (thread E): erasure, quantities, pattern matching,
termination, and value representation.

| Paper | Title | Authors | Venue / year | Link | Stored | Threads | Licence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [`brady-2021-idris2-qtt`](papers/brady-2021-idris2-qtt/) | Idris 2: Quantitative Type Theory in Practice | Brady | ECOOP 2021 | https://arxiv.org/abs/2104.00480 | TeX (arXiv 2104.00480) | E | arXiv non-exclusive | stored |
| [`chataing-2024-unboxed-data-constructors`](papers/chataing-2024-unboxed-data-constructors/) | Unboxed Data Constructors: Or, How cpp Decides a Halting Problem | Chataing, Dolan, Scherer, Yallop | POPL 2024 | https://doi.org/10.1145/3632893 | PDF (author site) | E | ACM CC-BY | stored (OA pass; papers pass: link-only, ACM 403); resolved-corrected |
| [`maranget-2008-pattern-matching`](papers/maranget-2008-pattern-matching/) | Compiling pattern matching to good decision trees | Maranget | ML 2008 | https://doi.org/10.1145/1411304.1411311 | PDF (author site, INRIA) | E | ACM ©; none stated on the copy | stored (OA pass; unresolved before: DOI not verified) |
| [`rondon-2008-liquid-types`](papers/rondon-2008-liquid-types/) | Liquid types | Rondon, Kawaguchi, Jhala | PLDI 2008 | https://doi.org/10.1145/1375581.1375602 | PDF (author site) | E | ACM © unknown–verify; none stated on the copy | stored (OA pass; papers pass: link-only, ACM 403) |

| Shortname | Title | Authors | Venue / year | Link | Threads | Licence | Status / reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `brady-2004-inductive-families` | Inductive Families Need Not Store Their Indices | Brady, McBride, McKinna | TYPES 2003 | https://doi.org/10.1007/978-3-540-24849-1_8 | E | Springer © unknown–verify | link-only (Springer landing not OA) |
| `teiiscak-2020-erasure-calculus` | A dependently typed calculus with pattern matching and erasure inference | Tejiščák | ICFP 2020 | https://doi.org/10.1145/3408973 | E | ACM CC-BY | link-only (ACM 403; the St Andrews accepted copy is on an unreachable host) |
| `lee-2001-size-change` | The size-change principle for program termination | Lee, Jones, Ben-Amram | POPL 2001 | https://doi.org/10.1145/360204.360210 | E | ACM © unknown–verify | link-only (ACM 403) |

| Unresolved | Threads | Status / reason |
| --- | --- | --- |
| Brady PhD thesis (2013) | E | hosted at `research-repository.st-andrews.ac.uk`, unreachable (000, then 503). |
| Tejiščák, *Erasure in Dependently Typed Programming* (thesis, 2020) | E | St Andrews repository unreachable. |
| Wadler, efficient compilation of pattern matching (1987) | E | no DOI confirmed; likely in proceedings that are not indexed. |
| Abel, "foetus" termination checker | E | technical report, no DOI; the author's `/foetus/` path returned 404 (`foetus.md` pointer planned, not written). |
| GHC unarisation documentation (`docs-ghc-unarisation`) | E | no `commentary/compiler/unarisation` page exists (HTTP 404); nearest material in `docs/ghc/`. |
| GMP manual; *Modern Computer Arithmetic* (book); Idris `Integer`/`String` | cross-cutting | docs and books; store as documentation or pointers (planned, not collected). |

**Also:** `bernardy-2018-linear-haskell`, `marshall-2022-linearity-uniqueness`,
`marshall-2024-fractional-uniqueness`, `wadler-1990-linear-types` (Memory);
`huang-2023-defunctionalization` (Specialization).

**Snapshots.**
- `code/idris2/src/Core/TT.idr`, `src/Core/TT/{Term,Binder}.idr`,
  `src/Core/Case/{CaseTree,CaseBuilder,Util}.idr`, `src/Compiler/CaseOpts.idr`,
  `src/Core/LinearCheck.idr`.
- `docs/idris2/docs/source/implementation/**`, `docs/ghc/commentary-compiler-data-types.md`.

**Read first:** `brady-2021-idris2-qtt`, `chataing-2024-unboxed-data-constructors`,
`code/idris2/src/Core/Case/CaseTree.idr`, `code/idris2/src/Compiler/CaseOpts.idr`.

**Claims these settle:** that indices need not be stored; how pattern matching is compiled
to decision trees; how unboxed constructors are represented (and the halting-problem
caveat).
