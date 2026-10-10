# Research library index

Every paper the library holds or catalogues, by topic, with the code and documentation
snapshots each topic draws on. Topics: [Memory](#memory),
[Specialization](#specialization), [Rewriting](#rewriting), [MLIR](#mlir),
[Arrays and scheduling](#arrays-and-scheduling), [Verification](#verification),
[Types and quantities](#types-and-quantities),
[Array languages and typed array programming](#array-languages-and-typed-array-programming).

Each paper appears once, under its main topic; a topic's "Also" line names papers filed
elsewhere that serve it too. Per entry: the folder (or shortname when nothing is stored),
title, authors, venue and year, canonical link, what is stored, the collection threads,
licence and status. The provenance of each stored copy is in its folder's `README.md`;
identifiers, access, pins, licences, and the record for papers not stored are in
[README.md](README.md). Paths below are relative to this folder.

Storage rule: raw LaTeX source is preferred; a PDF (or PostScript) is stored only when no
TeX source exists, and an author's or project's web edition (HTML) or a repository's text
extraction only when neither TeX nor a PDF under the cap exists. Every stored file is under the 20 MB per-file cap and no generated LaTeX
artefacts remain. Licences marked `unknown–verify` were not confirmed from the publisher:
confirm before redistributing.

## Summary

| Outcome | Count |
| --- | --- |
| Stored as TeX source (arXiv e-prints) | 26 |
| Stored as TeX source (author repository) | 1 |
| Stored as PDF | 55 |
| Stored as PostScript | 3 |
| Stored as HTML (author or project web edition) | 7 |
| Stored as repository text extraction (the PDF is over the cap) | 1 |
| **Papers stored** | **93** |
| Book stored as a documentation snapshot (`docs/ssa-book/`) | 1 |
| Link only (identifier known, no copy stored) | 36 |
| Unresolved (no identifier or copy located, or no canonical reference chosen) | 23 rows |

The array-languages passes of 2026-10-09 added 42 stored papers (6 arXiv TeX, 1 author TeX,
25 PDF, 2 PostScript, 7 HTML, 1 text extraction), 6 link-only rows, and resolved 3
unresolved rows (`henriksen-thesis`, `sac-language`, `dex-papers`); all are under
[Array languages and typed array programming](#array-languages-and-typed-array-programming).

Six paper folders hold two copies that differ (other host or version):
`adams-2019-halide-learning`, `ikarashi-2022-exo`, `kjolstad-2017-taco`,
`leroy-2009-compcert`, `marshall-2022-linearity-uniqueness`, `slepak-2014-remora` (the LNCS
version and the full version with appendices).

These counts are of the papers this index lists. Nineteen folders added to `papers/` on
2026-10-07 (commit `cb65104d`) are not indexed yet: `atkey-2009-parameterised-notions`,
`atkey-2018-qtt`, `axboe-2019-io-uring`, `bacon-2004-unified-gc`, `belay-2014-ix`,
`brady-2014-resource-effects`, `choi-2018-biased-rc`, `clebsch-2015-deny-capabilities`,
`clebsch-2015-pony-orca`, `clebsch-2017-orca`, `deutsch-bobrow-1976`, `dominiak-2024-p2300`,
`fahndrich-2006-singularity`, `johansson-2002-heap-architectures`, `kivity-2019-seastar`,
`lemon-2001-kqueue`, `lietar-2019-snmalloc`, `mcbride-2011-kleisli`,
`michael-1996-concurrent-queues`.

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
| `apl-lineage` | The APL family: array model, rank operator, modern APLs, Co-dfns | Array languages and typed array programming |
| `typed-rank` | Typed rank polymorphism (Remora), size and dependent types for arrays, type-level Nat solvers | Array languages and typed array programming |
| `dataparallel` | Data-parallel functional array compilers (Futhark, Dex, Accelerate, SaC, Lift/RISE) | Array languages and typed array programming |
| `dependent-equality` | Dependent equality, `with` and `rewrite`, unification, arithmetic decision procedures | Array languages and typed array programming |
| `mlir-stack` | MLIR's array dialects as the lowering target; JAX, Mojo and Triton on MLIR | Array languages and typed array programming |

The last five threads are the passes of 2026-10-09 (proposal 0004); their rows also carry the
letter threads they serve.

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
| Garbage Collection Handbook (`book-gc-handbook`) | D | book (paid); no OA. Pointer only (`gc-handbook.md` was planned and not written). |
| Boehm GC; "precise tracing GC" (`boehm-gc`, `precise-tracing-gc`) | D | tech report / project pages; no single canonical paper selected. Pointers only (`boehm-gc.md` planned, not written). |
| Destination-passing style (`destination-passing-style`) | D | no specific canonical reference selected. |
| Koka effect types (additional papers) | D | only Leijen POPL 2017 resolved (stored above); other Koka material is docs/code (`code-koka`, not collected). |
| Linear IO in QTT (`linear-io-qtt`) | cross-cutting, D | literature probe at collection time; not run. |
| Algebraic effects and handlers (`algebraic-effects-handlers`) | cross-cutting, D | literature probe at collection time; not run. |

**Also:** `hovgaard-2018-defunctionalisation` and `danvy-2001-defunctionalization`
(Specialization) for closure representation; `brady-2021-idris2-qtt` (Types and
quantities) for what quantities mean; `munksgaard-2022-memory-optimizations` (Array
languages) for array memory reuse and short-circuiting.

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
| Warm fusion; shortcut fusion (`warm-fusion`, `shortcut-fusion`) | C | no specific canonical paper selected in the plan; confirm the intended references. |
| Futamura, "Partial evaluation of computation process" (1971) (`futamura-projections`) | C | classic journal article with no DOI or OA copy located. |
| Christiansen PhD thesis (`christiansen-thesis`) | C | no stable OA URL located. |
| Jones, Gomard, Sestoft, *Partial Evaluation and Automatic Program Generation* (book) (`book-pe-jones-gomard-sestoft`) | C | free author-hosted PDF; store as pointer or fetch the PDF (`pe-book.md` planned, not written). |

**Also:** `leijen-2017-koka-effects` (Memory); `chen-2018-tvm` and
`ragankelley-2013-halide` (Arrays and scheduling) for schedule-driven code generation;
`henriksen-2013-t2-fusion` and `mcdonell-2013-accelerate-optimising` (Array languages) for
array fusion.

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
(`docs/ssa-book/`) for rewriting in SSA and PDL; `steuwer-2015-lift`,
`hagedorn-2020-elevate`, `cockx-2020-type-theory-unchained` and
`allais-2013-new-equations-neutral-terms` (Array languages) for rewrite rules over array
programs and inside a type theory.

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

**Also:** `bhat-2024-verifying-peephole` (Verification, lean-mlir);
`vasilache-2022-structured-codegen`, `bik-2022-sparse-mlir` (Array languages, lowering
target).

**Snapshots.**
- `code/mlir/include/mlir/IR/PatternMatch.h` (declares `RewriterBase`), `IR/OpDefinition.h`,
  `Transforms/{DialectConversion,GreedyPatternRewriteDriver,Passes}.*`, `Interfaces/*.td`,
  `Dialect/{PDL,PDLInterp,Transform,LLVMIR}/**`; the un-vendored `lib/` trees and their pin
  in `code/mlir/SNAPSHOT.md`.
- `docs/mlir/**` (100 files, all of `mlir/docs/**`), `docs/llvm/docs/**` (11 files).
- `code/mlir/` addendum: the ODS of the Linalg, Tensor, Bufferization, Vector, SparseTensor,
  Shard and SCF dialects (Array languages, lowering target).
- Five Mojo documentation pages on inline MLIR and parameters in `docs/mojo/` (Array
  languages, lowering target). Not collected: the rest of the Mojo docs, IREE docs, Polygeist
  (see [README.md](README.md#planned-sources-not-collected)).

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
| Halide (PLDI/SIGGRAPH 2012) (`halide-2012`) | G | reference to confirm; literature probe not run. |

Resolved on 2026-10-09 and filed under [Array languages and typed array
programming](#array-languages-and-typed-array-programming): `henriksen-thesis` →
`henriksen-2017-futhark-thesis`; `sac-language` → `grelck-2006-sac`; `dex-papers` →
`paszke-2021-dex`.

**Also:** `yang-2021-tensat` (Rewriting), `hovgaard-2018-defunctionalisation`
(Specialization), `mendis-2019-ithemal` (Rewriting, cost models); the whole of [Array
languages and typed array programming](#array-languages-and-typed-array-programming) for
rank polymorphism, size types and the data-parallel array compilers.

**Snapshots.**
- `code/tinygrad/tinygrad/uop/{ops,upat,spec,symbolic,render,validate}.py`,
  `codegen/simplify.py`, `codegen/opt/search.py`,
  `schedule/{prepare,rangeify,indexing,memory,multi}.py`, `renderer/{cstyle,llvmir}.py`,
  `engine/{realize,jit}.py`; for symbolic shapes, `uop/{spec,symbolic}.py` and
  `schedule/indexing.py`.
- `docs/tinygrad/` (the repository `README.md` and `docs/**`).
- MLton (threads D, G): `code/mlton/`, `docs/mlton/`.
- The dex-lang and Futhark sources, as excerpts at the library's pins: `code/dex/`,
  `code/futhark/`, `docs/futhark/` (Array languages, data-parallel compilers).

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
| Brady PhD thesis (2013) (`brady-2013-thesis`) | E | hosted at `research-repository.st-andrews.ac.uk`, unreachable (000, then 503). |
| Tejiščák, *Erasure in Dependently Typed Programming* (thesis, 2020) (`teiiscak-2020-erasure-thesis`) | E | St Andrews repository unreachable. |
| Wadler, efficient compilation of pattern matching (1987) (`wadler-1987-pattern-matching`) | E | no DOI confirmed; likely in proceedings that are not indexed. |
| Abel, "foetus" termination checker (`abel-foetus`) | E | technical report, no DOI; the author's `/foetus/` path returned 404 (`foetus.md` pointer planned, not written). |
| GHC unarisation documentation (`docs-ghc-unarisation`) | E | no `commentary/compiler/unarisation` page exists (HTTP 404); nearest material in `docs/ghc/`. |
| GMP manual; *Modern Computer Arithmetic* (book); Idris `Integer`/`String` (`pointers-gmp-manual`, `pointers-modern-computer-arithmetic`, `code-idris-integer-string`) | cross-cutting, E | docs and books; store as documentation or pointers (planned, not collected). |

**Also:** `bernardy-2018-linear-haskell`, `marshall-2022-linearity-uniqueness`,
`marshall-2024-fractional-uniqueness`, `wadler-1990-linear-types` (Memory);
`huang-2023-defunctionalization` (Specialization); `mcbride-2000-elimination-motive`,
`goguen-2006-eliminating-dependent-pattern-matching`,
`cockx-2017-dependent-pattern-matching-thesis`, `xi-2007-dependent-ml` and
`allais-2025-frex` (Array languages) for dependent pattern matching, equality and
type-level arithmetic.

**Snapshots.**
- `code/idris2/src/Core/TT.idr`, `src/Core/TT/{Term,Binder}.idr`,
  `src/Core/Case/{CaseTree,CaseBuilder,Util}.idr`, `src/Compiler/CaseOpts.idr`,
  `src/Core/LinearCheck.idr`.
- `docs/idris2/docs/source/implementation/**`, `docs/ghc/commentary-compiler-data-types.md`.
- `code/idris2/` addendum: `src/TTImp/Elab/Rewrite.idr`, `src/TTImp/ProcessDef.idr` and
  `src/TTImp/WithClause.idr` (how `rewrite` and `with` are elaborated; Array languages,
  dependent equality).

**Read first:** `brady-2021-idris2-qtt`, `chataing-2024-unboxed-data-constructors`,
`code/idris2/src/Core/Case/CaseTree.idr`, `code/idris2/src/Compiler/CaseOpts.idr`.

**Claims these settle:** that indices need not be stored; how pattern matching is compiled
to decision trees; how unboxed constructors are represented (and the halting-problem
caveat).

## Array languages and typed array programming

Prior art for typed array programming at every rank, lowered to MLIR: the APL family's array
model and its rank operator, typed rank polymorphism (Remora) and size and dependent types for
arrays, the data-parallel functional array compilers, the dependent-equality problem that
shape arithmetic raises in a dependently typed host, the solvers for type-level arithmetic, and
MLIR's own array stack as the lowering target. Collected on 2026-10-09 for proposal 0004
(`proposals/0004-typed-apl/README.md`) by five passes, whose names are the threads below:
`apl-lineage`, `typed-rank`, `dataparallel`, `dependent-equality` and `mlir-stack`. Every
entry here is new on that date; existing entries that serve the topic are cross-linked in the
"Also" lines and not stored again.

**Read first, for the topic as a whole:** `bernecky-1983-satn45-rank-operator` and
`hui-1995-rank-uniformity` (what rank, frame and cell mean, and which primitives are uniform);
`slepak-2019-semantics` with `slepak-2020-dissertation` (rank polymorphism typed and
elaborated); `henriksen-2021-size-types` and `paszke-2021-dex` (sizes and index sets as types
in a compiler that ships); `schenck-2024-automap` (rank polymorphism as call-site
elaboration); `mcbride-2000-elimination-motive` and `allais-2025-frex` (why shape equations
break `rewrite`, and a dependently typed simplifier for them, in Idris); and
`vasilache-2022-structured-codegen` (the MLIR structured-ops stack these lower onto).

### APL lineage and modern APLs

The array model (rank, frames and cells, the leading axis, depth, nested versus flat arrays,
fills), its operators (reduce, scan, outer and inner product, each, rank, under), and Hsu's
data-parallel tree representation. Most texts are Jsoftware's web editions, stored as HTML;
no TeX or open PDF exists for them.

| Paper | Title | Authors | Venue / year | Link | Stored | Threads | Licence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [`iverson-1962-programming-language`](papers/iverson-1962-programming-language/) | A Programming Language (preface, Ch. 1, part of Ch. 3) | Iverson | Wiley 1962 | https://www.jsoftware.com/papers/APL.htm (no DOI) | HTML (Jsoftware transcription, partial) + 171 glyph images | apl-lineage | © Wiley/Iverson, no licence stated (verify) | stored (partial: Chapters 2 and 4–7 are not transcribed on the host) |
| [`iverson-1980-notation-tool-of-thought`](papers/iverson-1980-notation-tool-of-thought/) | Notation as a Tool of Thought | Iverson | CACM 23(8) 1980 (1979 Turing lecture) | https://doi.org/10.1145/358896.358899 | HTML (Jsoftware transcription) | apl-lineage | ACM ©; none stated on the copy (verify) | stored (the ACM PDF returned 403) |
| [`bernecky-1980-operators-enclosed-arrays`](papers/bernecky-1980-operators-enclosed-arrays/) | Operators and Enclosed Arrays | Bernecky, Iverson | APL Users Meeting 1980 | https://www.jsoftware.com/papers/opea.htm (no DOI) | HTML (Jsoftware) | apl-lineage | none stated (verify) | stored |
| [`bernecky-1983-satn45-rank-operator`](papers/bernecky-1983-satn45-rank-operator/) | SATN-45: Language Extensions of May 1983 (the rank operator) | Bernecky, Iverson, McDonnell, Metzger, Schueler | SHARP APL Technical Note 45, 1983 | https://www.jsoftware.com/papers/satn45.htm (no DOI) | HTML (Jsoftware) | apl-lineage | none stated (verify) | stored |
| [`iverson-1987-dictionary-of-apl`](papers/iverson-1987-dictionary-of-apl/) | A Dictionary of APL | Iverson | APL Quote Quad 18(1) 1987 | https://doi.org/10.1145/36983.36984 | HTML (Jsoftware) | apl-lineage | ACM ©; none stated on the copy (verify) | stored |
| [`hui-1995-rank-uniformity`](papers/hui-1995-rank-uniformity/) | Rank and Uniformity | Hui | APL95, APL Quote Quad 25(4) 1995 | https://www.jsoftware.com/papers/rank.htm (DOI not resolved) | HTML (Jsoftware) | apl-lineage | ACM ©; none stated on the copy (verify) | stored |
| [`hui-2009-rank-operator`](papers/hui-2009-rank-operator/) | Rank Operator: An Idea Worth Stealing Borrowing | Hui | Dyalog '09 talk, 2009 | https://www.jsoftware.com/papers/rank/index.htm (no DOI) | HTML slides (14 pages) | apl-lineage | none stated (verify) | stored |
| [`hsu-2019-data-parallel-compiler`](papers/hsu-2019-data-parallel-compiler/) | A Data Parallel Compiler Hosted on the GPU | Hsu | PhD dissertation, Indiana University 2019 | https://hdl.handle.net/2022/24749 | repository text extraction (`hsu-dissertation.pdf.txt`); the PDF (30.7 MB) is over the cap | apl-lineage | repository: "may be protected by copyright" (verify) | stored (text only; the PDF is link-only) |

| Shortname | Title | Authors | Venue / year | Link | Threads | Licence | Status / reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `hui-2020-apl-since-1978` | APL since 1978 | Hui, Kromberg | PACMPL 4(HOPL) 69, 2020 | https://doi.org/10.1145/3386319 | apl-lineage | CC-BY 4.0 (Crossref; OpenAlex says CC-BY-SA) | link-only (gold OA only on `dl.acm.org`, 403; no other host found) |
| `bernecky-1988-function-rank` | An introduction to function rank | Bernecky | APL88, pp. 39–43, 1988 | https://doi.org/10.1145/55626.55632 | apl-lineage | ACM © | link-only (closed; OpenAlex has no OA location) |

**Also:** `shivers-2019-remora` (Arrays and scheduling): typed rank polymorphism, introduced
through the APL model.

**Snapshots.**
- `docs/j/help/dictionary/` (51 pages of the *J Dictionary*: grammar, nouns, verbs and rank,
  adverbs and conjunctions, trains, `"` rank, `&.` under, `/` insert and table, the
  structural verbs) and `docs/j/help/jdoc.css` ([SNAPSHOT](docs/j/SNAPSHOT.md)).
- `docs/bqn/` (BQN `5abbab96`: `doc/` on the array model, leading axis, rank, depth, fill,
  under, based arrays and 34 other pages; `commentary/`; `implementation/codfns.md`,
  `implementation/compile/`) ([SNAPSHOT](docs/bqn/SNAPSHOT.md)).
- `code/co-dfns/` (Co-dfns `07363409`, v5.7.1: `cmp/*.apl`, the parser, tree
  transformations and code generation; `docs/`); AGPL-3.0, for study only
  ([SNAPSHOT](code/co-dfns/SNAPSHOT.md)).

**Read first:** `bernecky-1983-satn45-rank-operator` (the rank operator's definition),
`hui-1995-rank-uniformity` (the rank model, integrated rank support, uniform verbs and shape
calculators), `docs/bqn/doc/leading.md` and `docs/bqn/doc/rank.md` (leading-axis agreement;
`F⎉k x ←→ >F¨<⎉k x`), `docs/bqn/doc/based.md`, and `hsu-2019-data-parallel-compiler` with
`code/co-dfns/cmp/TT.apl` (the parent-vector tree idioms).

**Claims these settle:** what rank, frame, cell, major cell, depth and fill mean in the APL
family, and how each dialect assembles results and treats empty frames; why the leading axis
and prefix agreement compose with the rank operator; which primitives are uniform (have shape
calculators); how inner, outer and batched products derive from rank; the cost of building
cells against integrated rank support; how trees and nested data are kept flat and
transformed with data-parallel primitives, and how that measured against nanopass.

### Typed rank polymorphism

Remora and its relatives: shapes in types, cells declared by each function, the principal
frame found by prefix join, elaboration to `map` and `rep`, and the Naperian-functor view of
the same idea in Haskell.

| Paper | Title | Authors | Venue / year | Link | Stored | Threads | Licence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [`slepak-2014-remora`](papers/slepak-2014-remora/) | An Array-Oriented Language with Static Rank Polymorphism | Slepak, Shivers, Manolios | ESOP 2014 (LNCS 8410) | https://doi.org/10.1007/978-3-642-54833-8_3 | 2 PDFs (LNCS version; full version with appendices), author site | typed-rank, G | Springer © unknown–verify; none stated on the copies | stored |
| [`slepak-2019-semantics`](papers/slepak-2019-semantics/) | The Semantics of Rank Polymorphism | Slepak, Shivers, Manolios | arXiv 2019 | https://arxiv.org/abs/1907.00509 | TeX (arXiv 1907.00509) | typed-rank, G | arXiv non-exclusive | stored |
| [`slepak-2018-constraint`](papers/slepak-2018-constraint/) | Rank Polymorphism Viewed as a Constraint Problem | Slepak, Manolios, Shivers | ARRAY 2018 | https://doi.org/10.1145/3219753.3219758 | PDF (author site) | typed-rank, G | ACM © unknown–verify; none stated on the copy | stored |
| [`slepak-2020-dissertation`](papers/slepak-2020-dissertation/) | A Typed Programming Language: The Semantics of Rank Polymorphism | Slepak | PhD dissertation, Northeastern University 2020 | https://www.khoury.northeastern.edu/~jrslepak/Dissertation.pdf (no DOI) | PDF (author site) | typed-rank, G | © author, none stated (verify) | stored |
| [`gibbons-2017-naperian`](papers/gibbons-2017-naperian/) | APLicative Programming with Naperian Functors | Gibbons | ESOP 2017 (LNCS 10201) | https://doi.org/10.1007/978-3-662-54434-1_21 | PDF (accepted manuscript) + companion `aplicative.hs`, author site | typed-rank, G | Springer © unknown–verify; none stated on the copy | stored |

**Also:** `shivers-2019-remora` (Arrays and scheduling), the Remora tutorial draft;
`schenck-2024-automap` (Data-parallel functional array compilers below), rank polymorphism
inferred by integer linear programming.

**Snapshots.**
- `code/remora/` (`jrslepak/Remora` at `1a831dec`): the Redex models
  `semantics/{language,dependent-lang,typed-reduction,redex-utils}.rkt` and
  `semantics/Readme.md`, the dynamic implementation `remora/dynamic/lang/{semantics,syntax}.rkt`,
  `remora/scribblings/{application,arrays,boxes}.scrbl`, `remora/Readme.md`,
  `notes/composition.txt`; no licence ([SNAPSHOT](code/remora/SNAPSHOT.md)).
- `code/revised-remora/` (`jrslepak/Revised-Remora` at `0b7b8ad3`): the whole repository
  (12 files); no licence ([SNAPSHOT](code/revised-remora/SNAPSHOT.md)).
- `code/remorac/` (`jrslepak/remorac` at `9bfe4ac3`): `typechecker`, `frame_notes`,
  `erased_ast`, `map_replicate_ast` (`.ml`/`.mli`), `basic_ast.mli`, `annotation.mli`,
  `design.txt`, `README.md`, `License.txt`; BSD-3-Clause ([SNAPSHOT](code/remorac/SNAPSHOT.md)).
- `code/makanin-algo/` (`jrslepak/makanin-algo` at `64e3ac61`): the string-equation solver
  the revised Remora type checker calls; no licence ([SNAPSHOT](code/makanin-algo/SNAPSHOT.md)).

**Read first:** `slepak-2019-semantics` (`formalism.tex`, `figs.tex`: the index theory and
T-App), `slepak-2020-dissertation` chapters 7 and 11,
`code/remora/remora/dynamic/lang/semantics.rkt` (`apply-rem-array`), `gibbons-2017-naperian`
§§3, 6–8.

**Claims these settle:** how shapes enter types (index languages, type-level lists); how rank
polymorphism is typed (cells declared, the principal frame found by prefix join) and
elaborated (`map` and `rep`, partial erasure to shapes); which shape theories are decidable
and at what cost (string equations for shapes, by Makanin's algorithm); how far a typeclass
encoding (Naperian functors) gets without a dedicated type system.

### Dependent and size types for arrays

Array bounds and shapes decided by dependent or size types in languages that compile them:
DML's bounds-check elimination, Qube's dependently typed arrays, Futhark's size types.

| Paper | Title | Authors | Venue / year | Link | Stored | Threads | Licence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [`xi-1998-dml-bounds`](papers/xi-1998-dml-bounds/) | Eliminating Array Bound Checking Through Dependent Types | Xi, Pfenning | PLDI 1998 | https://doi.org/10.1145/277650.277732 | PDF (author site, CMU) | typed-rank, E | ACM © unknown–verify; none stated on the copy | stored |
| [`trojahner-2009-qube`](papers/trojahner-2009-qube/) | Dependently typed array programs don't go wrong | Trojahner, Grelck | JLAP 78(7) 2009 | https://doi.org/10.1016/j.jlap.2009.03.002 | PDF (UvA-DARE, published version with the repository cover sheet) | typed-rank, G | Elsevier ©; UvA-DARE terms: personal use only, do not redistribute without consent | stored (personal use) |
| [`henriksen-2021-size-types`](papers/henriksen-2021-size-types/) | Towards Size-Dependent Types for Array Programming | Henriksen, Elsman | ARRAY 2021 | https://doi.org/10.1145/3460944.3464310 | PDF (futhark-lang.org) | typed-rank, G | ACM © unknown–verify; none stated on the copy | stored |
| [`bailly-2023-size-dependent`](papers/bailly-2023-size-dependent/) | Shape-Constrained Array Programming with Size-Dependent Types | Bailly, Henriksen, Elsman | FHPNC 2023 | https://doi.org/10.1145/3609024.3609412 | PDF (futhark-lang.org) | typed-rank, G | ACM © unknown–verify; none stated on the copy | stored |

**Also:** `henriksen-2017-futhark` (Arrays and scheduling); `rondon-2008-liquid-types` (Types
and quantities), refinements decided by SMT; `brady-2021-idris2-qtt` (Types and quantities),
quantity 0 for shapes and proofs; `xi-2007-dependent-ml` (Solvers below), the journal account
of DML.

**Snapshots.** `code/futhark/src/Futhark/Internalise/AccurateSizes.hs`,
`Language/Futhark/TypeChecker/{Consumption,TySolve,Unify}.hs` and `Terms/Unsized.hs`
(Data-parallel functional array compilers below).

**Read first:** `henriksen-2021-size-types` §6, `bailly-2023-size-dependent`,
`xi-1998-dml-bounds`, `trojahner-2009-qube`.

**Claims these settle:** how size bookkeeping can be automated (existentials, witnesses, size
inference); which bounds checks a dependent index removes; what a dependently typed array
language with full rank and shape polymorphism has to check, and where it falls back to
run-time checks.

### Data-parallel functional array compilers

Fusion, flattening of nested parallelism, in-place update licensed by uniqueness, index sets
as types, pointful against point-free compilation, and scheduling as a separate language.

| Paper | Title | Authors | Venue / year | Link | Stored | Threads | Licence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [`henriksen-2013-t2-fusion`](papers/henriksen-2013-t2-fusion/) | A T2 Graph-Reduction Approach to Fusion | Henriksen, Oancea | FHPC 2013 | https://doi.org/10.1145/2502323.2502328 | PDF (futhark-lang.org) | dataparallel, G | ACM © unknown–verify; author copy | stored |
| [`henriksen-2017-futhark-thesis`](papers/henriksen-2017-futhark-thesis/) | Design and Implementation of the Futhark Programming Language (Revised) | Henriksen | PhD thesis, University of Copenhagen 2017 | https://futhark-lang.org/publications/troels-henriksen-phd-thesis.pdf (no DOI) | PDF (futhark-lang.org) | dataparallel, G | none stated (verify) | stored (resolves the unresolved row `henriksen-thesis`) |
| [`henriksen-2019-incremental-flattening`](papers/henriksen-2019-incremental-flattening/) | Incremental Flattening for Nested Data Parallelism | Henriksen, Thorøe, Elsman, Oancea | PPoPP 2019 | https://doi.org/10.1145/3293883.3295707 | PDF (futhark-lang.org) | dataparallel, G | ACM © unknown–verify; author copy | stored |
| [`munksgaard-2022-memory-optimizations`](papers/munksgaard-2022-memory-optimizations/) | Memory Optimizations in an Array Language | Munksgaard, Henriksen, Sadayappan, Oancea | SC 2022 | https://futhark-lang.org/publications/sc22-mem.pdf (DOI not recorded) | PDF (futhark-lang.org) | dataparallel, G, D | IEEE © unknown–verify; author copy | stored |
| [`schenck-2024-automap`](papers/schenck-2024-automap/) | AUTOMAP: Inferring Rank-Polymorphic Function Applications with Integer Linear Programming | Schenck, Hinnerskov, Henriksen, Madsen, Elsman | OOPSLA 2024 | https://doi.org/10.1145/3689774 | PDF (futhark-lang.org) | dataparallel, typed-rank, G | CC-BY-SA 4.0 | stored |
| [`paszke-2021-dex`](papers/paszke-2021-dex/) | Getting to the Point: Index Sets and Parallelism-Preserving Autodiff for Pointful Array Programming | Paszke, Johnson, Duvenaud, Vytiniotis, Radul, Johnson, Ragan-Kelley, Maclaurin | ICFP 2021 | https://arxiv.org/abs/2104.05372 (DOI 10.1145/3473593) | TeX (arXiv 2104.05372) | dataparallel, G | arXiv non-exclusive; ACM version CC-BY | stored (resolves the unresolved row `dex-papers`) |
| [`chakravarty-2011-accelerate`](papers/chakravarty-2011-accelerate/) | Accelerating Haskell Array Codes with Multicore GPUs | Chakravarty, Keller, Lee, McDonell, Grover | DAMP 2011 | https://doi.org/10.1145/1926354.1926358 | PDF (co-author site) | dataparallel, G | ACM © unknown–verify; author copy | stored |
| [`mcdonell-2013-accelerate-optimising`](papers/mcdonell-2013-accelerate-optimising/) | Optimising Purely Functional GPU Programs | McDonell, Chakravarty, Keller, Lippmeier | ICFP 2013 | https://doi.org/10.1145/2500365.2500595 | PDF (author site) | dataparallel, G, C | ACM © unknown–verify; author copy | stored |
| [`grelck-2006-sac`](papers/grelck-2006-sac/) | SAC — A Functional Array Language for Efficient Multi-threaded Execution | Grelck, Scholz | IJPP 34(4), 2006 | https://doi.org/10.1007/s10766-006-0018-x | PDF (author page, through the Wayback Machine) | dataparallel, G | Springer © (verify) | stored (resolves the unresolved row `sac-language`) |
| [`steuwer-2015-lift`](papers/steuwer-2015-lift/) | Generating Performance Portable Code using Rewrite Rules | Steuwer, Fensch, Lindley, Dubach | ICFP 2015 | https://doi.org/10.1145/2784731.2784754 | PDF (author site) | dataparallel, G, B | ACM © unknown–verify; author copy | stored |
| [`hagedorn-2020-elevate`](papers/hagedorn-2020-elevate/) | Achieving High-Performance the Functional Way (RISE/ELEVATE) | Hagedorn, Lenfers, Kœhler, Qin, Gorlatch, Steuwer | ICFP 2020 | https://doi.org/10.1145/3408974 | PDF (Glasgow eprints) | dataparallel, G, B | CC-BY (ACM); the Glasgow copy CC-BY-SA per OpenAlex (verify) | stored |

**Also:** `henriksen-2017-futhark`, `ragankelley-2013-halide` (Arrays and scheduling);
`hovgaard-2018-defunctionalisation` (Specialization); `lucke-2024-transform-dialect` (MLIR);
`koehler-2021-sketch-eqsat` (Rewriting); `henriksen-2021-size-types`,
`bailly-2023-size-dependent` (Dependent and size types above).

**Snapshots.**
- `code/futhark/` (20 files at the library's Futhark pin `304c56ff`): `src/Futhark/Passes.hs`,
  `IR/SOACS/SOAC.hs`, `IR/SegOp.hs`, `IR/TypeCheck.hs`, `Optimise/Fusion.hs` and `Fusion/*`,
  `Pass/Flatten.hs`, `Flatten/{Incremental,Distribute}.hs`,
  `Optimise/ArrayShortCircuiting.hs`, `Internalise/AccurateSizes.hs`,
  `Language/Futhark/TypeChecker/{Consumption,TySolve,Unify}.hs`, `Terms/Unsized.hs`
  ([SNAPSHOT](code/futhark/SNAPSHOT.md)).
- `docs/futhark/` (5 files, same pin): `docs/{language-reference,performance,glossary,versus-other-languages}.rst`
  ([SNAPSHOT](docs/futhark/SNAPSHOT.md)).
- `code/dex/` (13 files at the library's dex-lang pin `25e2e389`): `lib/prelude.dx`,
  `src/lib/{Types/Core,Simplify,Linearize,Transpose,Lower,Vectorize,Imp,Types/Imp}.hs`,
  `src/old/MLIR/Lower.hs`, `src/old/Parallelize.hs` ([SNAPSHOT](code/dex/SNAPSHOT.md)).

**Read first:** `paszke-2021-dex` (`main.tex` §3.4, index sets; §6, fusion as inlining and
type-directed compilation); `henriksen-2017-futhark-thesis` §2.5.1, §5.3, §7;
`henriksen-2019-incremental-flattening`; `schenck-2024-automap` §2; `grelck-2006-sac` §2.4
and §3.

**Claims these settle:** how a closed combinator set is fused without duplicating work; how
nested regular parallelism is mapped to hardware levels with run-time version selection; how
uniqueness typing licenses in-place updates and how the IR re-checks it; how expressive size
types are in practice; index sets as types and reshape as currying; rank polymorphism as
call-site elaboration; producer and consumer fusion over delayed arrays; specialisation along
a shape hierarchy; the separation of algorithm and schedule by rewrite rules and a strategy
language.

### Dependent equality and the rewrite problem

Why abstracting a shape equation out of a goal produces ill-typed motives, how `with` and
`rewrite` are elaborated, what unification does with arithmetic it cannot decide, and which
equations can be made definitional.

| Paper | Title | Authors | Venue / year | Link | Stored | Threads | Licence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [`mcbride-2000-elimination-motive`](papers/mcbride-2000-elimination-motive/) | Elimination with a Motive | McBride | TYPES 2000 (LNCS 2277, 2002) | https://doi.org/10.1007/3-540-45842-5_13 | PostScript (author site, `elim.ps`) | dependent-equality, E | Springer © unknown–verify; none stated on the copy | stored |
| [`mcbride-2004-view-from-left`](papers/mcbride-2004-view-from-left/) | The view from the left | McBride, McKinna | JFP 14(1) 2004 | https://doi.org/10.1017/S0956796803004829 | PostScript (author preprint, `view.ps`) | dependent-equality, E | CUP © unknown–verify; none stated on the copy | stored (preprint) |
| [`goguen-2006-eliminating-dependent-pattern-matching`](papers/goguen-2006-eliminating-dependent-pattern-matching/) | Eliminating Dependent Pattern Matching | Goguen, McBride, McKinna | Algebra, Meaning, and Computation (LNCS 4060) 2006 | https://doi.org/10.1007/11780274_27 | PDF (author site) | dependent-equality, E | Springer © unknown–verify; none stated on the copy | stored |
| [`cockx-2014-overlapping-patterns`](papers/cockx-2014-overlapping-patterns/) | Overlapping and Order-Independent Patterns: Definitional Equality for All | Cockx, Piessens, Devriese | ESOP 2014 (LNCS 8410) | https://doi.org/10.1007/978-3-642-54833-8_6 | PDF (author site) | dependent-equality, E | Springer © unknown–verify; none stated on the copy | stored |
| [`cockx-2016-unifiers-as-equivalences`](papers/cockx-2016-unifiers-as-equivalences/) | Unifiers as Equivalences: Proof-Relevant Unification of Dependently Typed Data | Cockx, Devriese, Piessens | ICFP 2016 | https://doi.org/10.1145/2951913.2951917 | PDF (authors' version, author site) | dependent-equality, E | ACM ©; the copy is marked "personal use. Not for redistribution" | stored (personal use) |
| [`cockx-2017-dependent-pattern-matching-thesis`](papers/cockx-2017-dependent-pattern-matching-thesis/) | Dependent Pattern Matching and Proof-Relevant Unification | Cockx | PhD thesis, KU Leuven 2017 | https://jesper.cx/files/thesis-final-digital.pdf (no DOI) | PDF (author site) | dependent-equality, E | © KU Leuven, "All rights reserved" (verify) | stored |
| [`cockx-2020-type-theory-unchained`](papers/cockx-2020-type-theory-unchained/) | Type Theory Unchained: Extending Agda with User-Defined Rewrite Rules | Cockx | TYPES 2019 (LIPIcs 175, 2020) | https://doi.org/10.4230/LIPIcs.TYPES.2019.2 | PDF (Dagstuhl DROPS) | dependent-equality, B | CC-BY | stored |
| [`allais-2013-new-equations-neutral-terms`](papers/allais-2013-new-equations-neutral-terms/) | New Equations for Neutral Terms: A Sound and Complete Decision Procedure, Formalized | Allais, McBride, Boutillier | DTP 2013 | https://doi.org/10.1145/2502409.2502411 (arXiv https://arxiv.org/abs/1304.0809) | TeX (arXiv 1304.0809) | dependent-equality, B | arXiv non-exclusive | stored |

| Shortname | Title | Authors | Venue / year | Link | Threads | Licence | Status / reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `cockx-2021-taming-rew` | The Taming of the Rew: A Type Theory with Computational Assumptions | Cockx, Tabareau, Winterhalter | POPL 2021 (PACMPL 5) | https://doi.org/10.1145/3434341 | dependent-equality | ACM, gold OA (verify) | link-only (HAL served an Anubis challenge, not solved; `dl.acm.org` 403) |
| `cockx-2016-without-k` | Eliminating dependent pattern matching without K | Cockx, Devriese, Piessens | JFP 26, 2016 | https://doi.org/10.1017/S0956796816000174 | dependent-equality | CUP © | link-only (fetched, not stored: revised as chapters 2 and 4 of `cockx-2017-dependent-pattern-matching-thesis`) |
| `cockx-2018-proof-relevant-unification` | Proof-relevant unification: Dependent pattern matching with only the axioms of your type theory | Cockx, Devriese | JFP 28, 2018 | https://doi.org/10.1017/S095679681800014X | dependent-equality | CUP © | link-only (fetched, not stored: revised as chapter 3 of the thesis) |

**Also:** `brady-2021-idris2-qtt` (Types and quantities), quantity 0 for proofs and shapes;
`willsey-2021-egg`, `zhang-2023-egglog`, `wu-2026-slotted-egraphs` (Rewriting), equality
saturation, which is not a type-level decision procedure; `maranget-2008-pattern-matching`
(Types and quantities).

**Snapshots.**
- `code/idris2/` addendum at the `third_party/Idris2` pin `1c630e67` (8 files, byte-identical
  to the checkout): `src/TTImp/Elab/Rewrite.idr`, `src/Core/Normalise.idr`,
  `src/Core/GetType.idr`, `src/TTImp/ProcessDef.idr`, `src/TTImp/Elab/Utils.idr`,
  `src/TTImp/WithClause.idr`, `libs/prelude/Builtin.idr`, `libs/base/Data/Nat.idr`
  ([addendum](code/idris2/SNAPSHOT.dependent-equality.md), to merge into
  `code/idris2/SNAPSHOT.md`).
- `code/lean4/` (`leanprover/lean4` at `7cd10322`): `src/Lean/Meta/KAbstract.lean`,
  `src/Lean/Meta/Tactic/{Rewrite,Subst,Generalize}.lean`, `src/Lean/Elab/Tactic/Rewrite.lean`,
  `src/Init/Tactics.lean`, `LICENSE`; Apache-2.0 ([SNAPSHOT](code/lean4/SNAPSHOT.md)).
- `docs/agda/` (`agda/agda` at `83f3fcce`):
  `doc/user-manual/language/{with-abstraction,rewriting,without-k}.lagda.rst`, `LICENSE`
  ([SNAPSHOT](docs/agda/SNAPSHOT.md)).
- `docs/rocq/` (`rocq-prover/rocq` at `29f5238e`):
  `doc/sphinx/proofs/writing-proofs/{equality,reasoning-inductives}.rst`,
  `doc/sphinx/proof-engine/tactics.rst`, `doc/sphinx/addendum/{ring,micromega}.rst`,
  `doc/LICENSE` ([SNAPSHOT](docs/rocq/SNAPSHOT.md)).
- `docs/idris2/docs/source/tutorial/{theorems,views}.rst` (already stored): proofs and views in
  the Idris 2 tutorial.

**Read first:** `docs/agda/doc/user-manual/language/with-abstraction.lagda.rst` lines
888–1095 (the translation, and ill-typed abstraction); `code/lean4/src/Lean/Meta/Tactic/Rewrite.lean`
lines 28–90; `code/idris2/src/TTImp/Elab/Rewrite.idr` lines 65–154;
`mcbride-2000-elimination-motive` §5 and §8; `cockx-2017-dependent-pattern-matching-thesis`
§5.1; `allais-2013-new-equations-neutral-terms`, section "Scaling up to Type Theory".

**Claims these settle:** why abstraction produces ill-typed motives and how Idris, Agda, Lean
and Rocq each detect or avoid it; that unification has a third, "stuck" outcome on
arithmetic; which equations can be made definitional (constructor clauses, oriented rewrite
rules, ν-rules for neutral terms) and which cannot (commutativity).

### Solvers for type-level Nat and shape arithmetic

Decision procedures for the semiring and linear fragments of size arithmetic, inside the type
checker (GHC plugins, DML's constraint solver) or as reflective, evidence-producing libraries
(Frex, Rocq's `ring` and `lia`).

| Paper | Title | Authors | Venue / year | Link | Stored | Threads | Licence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [`allais-2025-frex`](papers/allais-2025-frex/) | Frex: Dependently Typed Algebraic Simplification | Allais, Brady, Corbyn, Kammar, Yallop | PACMPL 9 (ICFP) 2025, Article 237 | https://doi.org/10.1145/3747506 (arXiv https://arxiv.org/abs/2306.15375) | TeX (arXiv 2306.15375 v2) | dependent-equality, E | arXiv non-exclusive; the authors' CC BY on the accepted manuscript | stored |
| [`xi-2007-dependent-ml`](papers/xi-2007-dependent-ml/) | Dependent ML: An Approach to Practical Programming with Dependent Types | Xi | JFP 17(2) 2007 | https://doi.org/10.1017/S0956796806006216 | PDF (author preprint, hwxi.github.io) | dependent-equality, E | CUP © unknown–verify; none stated on the copy | stored (preprint) |
| [`diatchki-2015-smt`](papers/diatchki-2015-smt/) | Improving Haskell Types with SMT | Diatchki | Haskell Symposium 2015 | https://doi.org/10.1145/2804302.2804307 | TeX (author source, from `yav/type-nat-solver` `docs/`) | typed-rank, E | ACM © for the published version; repository BSD-3-Clause (verify that it covers the text) | stored (author source; the camera-ready text is not verified) |

| Shortname | Title | Authors | Venue / year | Link | Threads | Licence | Status / reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `gregoire-2005-ring` | Proving Equalities in a Commutative Ring Done Right in Coq | Grégoire, Mahboubi | TPHOLs 2005 (LNCS 3603) | https://doi.org/10.1007/11541868_7 | dependent-equality | Springer © | link-only (HAL copy behind the Anubis challenge, not attempted; the algorithm is documented in `docs/rocq/doc/sphinx/addendum/ring.rst`) |

**Also:** `xi-1998-dml-bounds`, `henriksen-2021-size-types`, `bailly-2023-size-dependent`
(Dependent and size types above); `rondon-2008-liquid-types` (Types and quantities).

**Snapshots.**
- `code/type-nat-solver/` (`yav/type-nat-solver` at `4218b52e`): `src/TypeNatSolver.hs`,
  `docs/Examples.hs`, `README.mkd`, `LICENSE`; BSD-3-Clause
  ([SNAPSHOT](code/type-nat-solver/SNAPSHOT.md)).
- `code/ghc-typelits-natnormalise/` (`clash-lang/ghc-typelits-natnormalise` at `44c1a880`):
  `src/GHC/TypeLits/Normalise.hs`, `Normalise/{SOP,Unify}.hs`,
  `doc/ghc-typelits-natnormalise-hcar.tex`, `README.md`, `LICENSE`; BSD-2-Clause
  ([SNAPSHOT](code/ghc-typelits-natnormalise/SNAPSHOT.md)).
- `docs/rocq/doc/sphinx/addendum/{ring,micromega}.rst` (above).

**Read first:** `allais-2025-frex` (`new-intro.tex`, `reflection.tex`, `evaluation.tex`),
`code/ghc-typelits-natnormalise/src/GHC/TypeLits/Normalise/SOP.hs`, `diatchki-2015-smt`,
`xi-2007-dependent-ml`.

**Claims these settle:** which decision procedures cover the semiring and linear fragments of
shape arithmetic, and whether they produce evidence the type checker can use; how far
sum-of-products normalisation and plain unification go before a solver is needed; how an
SMT solver is driven from a type checker, and at what cost.

### Lowering target: the MLIR array stack

Structured ops, tensors, bufferization, the Transform dialect, vectors, sparse tensors and
sharding: the MLIR dialects a typed array language lowers onto, with JAX's shape polymorphism,
Mojo's inline MLIR and Triton's dialects as other front ends that target them.

| Paper | Title | Authors | Venue / year | Link | Stored | Threads | Licence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [`vasilache-2022-structured-codegen`](papers/vasilache-2022-structured-codegen/) | Composable and Modular Code Generation in MLIR: A Structured and Retargetable Approach to Tensor Compiler Construction | Vasilache, Zinenko, Bik, Ravishankar, Raoux, Belyaev, Springer, Gysi, Caballero, Herhut, Laurenzo, Cohen | arXiv 2022 | https://arxiv.org/abs/2202.03293 | TeX (arXiv 2202.03293) | mlir-stack, F, G | CC-BY 4.0 (arXiv record) | stored |
| [`bik-2022-sparse-mlir`](papers/bik-2022-sparse-mlir/) | Compiler Support for Sparse Tensor Computations in MLIR | Bik, Koanantakool, Shpeisman, Vasilache, Zheng, Kjolstad | ACM TACO 19(4), 2022 | https://doi.org/10.1145/3544559 (arXiv https://arxiv.org/abs/2202.04305) | TeX (arXiv 2202.04305) | mlir-stack, F, G | CC-BY 4.0 (arXiv version) | stored |
| [`tillet-2019-triton`](papers/tillet-2019-triton/) | Triton: An Intermediate Language and Compiler for Tiled Neural Network Computations | Tillet, Kung, Cox | MAPL 2019 | https://doi.org/10.1145/3315508.3329973 | PDF (author site, Harvard) | mlir-stack, G | ACM © unknown–verify; author copy, none stated | stored |

**Also:** `lattner-2020-mlir` and the link-only `mlir-cgo-2021`, `lucke-2024-transform-dialect`
(MLIR); `kjolstad-2017-taco` (Arrays and scheduling), the sparse formats MLIR's sparse
compiler adopts.

**Snapshots.**
- `code/mlir/` addendum (38 files at the LLVM pin `7208ba24`, taken from the bootstrap's
  clone): the ODS of `Dialect/{Linalg,Tensor,Bufferization,Vector,SparseTensor,Shard,SCF}/...`
  and `python/mlir/dialects/linalg/opdsl/ops/core_named_ops.py`
  ([addendum](code/mlir/SNAPSHOT.addendum.md), to merge into `code/mlir/SNAPSHOT.md`).
- `docs/mlir/docs/{Dialects/Linalg/_index.md, Dialects/Linalg/OpDSL.md,
  Rationale/RationaleLinalgDialect.md, Bufferization.md, OwnershipBasedBufferDeallocation.md,
  Dialects/Transform.md, Dialects/Vector.md, Dialects/Shard.md, Dialects/ShapeDialect.md,
  Traits/Broadcastable.md}` (already stored).
- `docs/jax/docs/501/{shape-polymorphism,export}.md` and
  `code/jax/jax/_src/export/{shape_poly,shape_poly_decision}.py` (`jax-ml/jax` at
  `40a35abd`; Apache-2.0) ([docs](docs/jax/SNAPSHOT.md), [code](code/jax/SNAPSHOT.md)).
- `docs/mojo/Mojo/docs/{site/reference/inline-mlir.mdx, stdlib/internal/pop_dialect.md,
  stdlib/internal/mlir.md, site/manual/parameters/index.mdx, site/faq.md}`
  (`modular/modular` at `135c332f`; Apache-2.0 WITH LLVM-exception)
  ([SNAPSHOT](docs/mojo/SNAPSHOT.md)).
- `code/triton/include/triton/Dialect/{Triton/IR/TritonOps.td, Triton/IR/TritonTypes.td,
  TritonGPU/IR/TritonGPUAttrDefs.td}` (`triton-lang/triton` at `11523f38`; MIT)
  ([SNAPSHOT](code/triton/SNAPSHOT.md)).

**Read first:** `vasilache-2022-structured-codegen`;
`docs/mlir/docs/Rationale/RationaleLinalgDialect.md`; `docs/mlir/docs/Bufferization.md`;
`code/mlir/include/mlir/Dialect/Linalg/IR/LinalgStructuredOps.td` and
`code/mlir/include/mlir/Dialect/Tensor/IR/TensorOps.td`; `bik-2022-sparse-mlir`;
`docs/jax/docs/501/shape-polymorphism.md`.

**Claims these settle:** what `linalg.generic` and the named structured ops express, and how
tiling, fusion and vectorization act on them; how dynamic shapes are carried by `tensor` and
resolved by bufferization; what sparse encodings and sharding add to the same ops; how JAX
decides symbolic-dimension constraints at export; how Mojo and Triton expose MLIR to a
language with shape parameters.


## Additions of 2026-10-09: flattened data, type checking, Swift

### Flattened data: packed, columnar and nested layouts — columnar

New topic **Flattened data: packed, columnar and nested layouts**, subtopic **Columnar layouts
of nested and algebraic data** (how a flat layout is derived from a type: products as columns,
sums as tag columns with dense or sparse children, optionality as validity bitmaps or definition
levels, lists as offsets or repetition levels; structure-of-arrays derived from types; indices
instead of pointers in a self-hosted compiler; hash-consing).

| Paper | Title | Authors | Venue / year | Link | Stored | Threads | Licence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [`melnik-2010-dremel`](papers/melnik-2010-dremel/) | Dremel: Interactive Analysis of Web-Scale Datasets | Melnik, Gubarev, Long, Romer, Shivakumar, Tolton, Vassilakis | PVLDB 3(1–2), pp. 330–339, VLDB 2010 | https://doi.org/10.14778/1920841.1920886 | PDF (Google Research archive, pub 36632) | columnar | © VLDB Endowment; personal/classroom permission notice on the copy, no open licence (verify) | stored (OpenAlex: closed; `vldb.org` served an HTML shell) |
| [`filliatre-2006-hash-consing`](papers/filliatre-2006-hash-consing/) | Type-Safe Modular Hash-Consing | Filliâtre, Conchon | ML Workshop 2006, pp. 12–19 | https://doi.org/10.1145/1159876.1159880 | PDF (author site) | columnar | ACM © (stated on the copy); author copy, no open licence (verify) | stored (OpenAlex: closed; author copy) |

**Snapshots.**
- `docs/arrow/` (Apache Arrow `apache-arrow-26.0.0` = `44616716`: `docs/source/format/Columnar.rst`
  (format 1.5), `Intro.rst`, `Glossary.rst`, `Versioning.rst`, `index.rst`, 17 layout diagrams,
  `format/Schema.fbs`, `format/Message.fbs`); Apache-2.0; [SNAPSHOT](docs/arrow/SNAPSHOT.md).
- `docs/arrow-site/` (`apache/arrow-site` `bf8285be`: the three "Arrow and Parquet" posts of
  October 2022 on structs, lists and their Parquet encoding); Apache-2.0;
  [SNAPSHOT](docs/arrow-site/SNAPSHOT.md).
- `docs/parquet-format/` (`apache-parquet-format-2.14.0` = `04d56f29`: `README.md`,
  `LogicalTypes.md`, `Encodings.md`, `VariantShredding.md`, `VariantEncoding.md`,
  `src/main/thrift/parquet.thrift`); Apache-2.0; [SNAPSHOT](docs/parquet-format/SNAPSHOT.md).
- `docs/parquet-site/` (`apache/parquet-site` `14a99121`: nested encoding, nulls and file-format
  pages); Apache-2.0; [SNAPSHOT](docs/parquet-site/SNAPSHOT.md).
- `code/zig/` (Zig `0.15.2` = `e4cbd752`: `lib/std/multi_array_list.zig`, `lib/std/zig/Ast.zig`,
  `lib/std/zig/Zir.zig`, `src/InternPool.zig`); MIT; [SNAPSHOT](code/zig/SNAPSHOT.md).
- `code/structarrays/` (StructArrays.jl `v0.7.3` = `4a1e2710`: `docs/src/*.md` and the core
  `src/*.jl`); MIT; [SNAPSHOT](code/structarrays/SNAPSHOT.md).
- `code/vector/` (`vector-0.13.2.0` = `d9d0d466`: `Data/Vector/Unboxed.hs`, `Unboxed/Base.hs`,
  the generated tuple instances and their generator, the generic base classes); BSD-3-Clause;
  [SNAPSHOT](code/vector/SNAPSHOT.md).
- `code/ocaml-hashcons/` (`1.4.0` = `9d6a7855`: `hashcons.mli`, `hashcons.ml`); LGPL-2.1 with
  the OCaml linking exception (study only); [SNAPSHOT](code/ocaml-hashcons/SNAPSHOT.md).

**Also:** `reinking-2021-perceus`, `lorenzen-2023-fp2`, `ullrich-2019-counting-immutable-beans`
(Memory), for reuse of cells and what replaces it for columns;
`chataing-2024-unboxed-data-constructors` (Types and quantities), for when unboxing a constructor
would confuse two values; `kjolstad-2017-taco` (Arrays and scheduling), for per-level formats
whose compressed level is Arrow's offsets-into-child; and, from the array-languages topic being
committed from the `apl` staging tree, `hsu-2019-data-parallel-compiler` with `code/co-dfns/`
(trees as parent vectors), `henriksen-2019-incremental-flattening` and `bik-2022-sparse-mlir`.
Within this topic, the packed-trees cluster staged beside this one (`vollmer-2017-packed-tree-transforms`,
`vollmer-2019-local`, `koparkar-2021-efficient-tree-traversals`, `koparkar-2024-mostly-serialized-gc`,
`yang-2015-compact-normal-forms`, `allais-2023-serialised-data`, `singhal-2024-marmoset`,
`code/gibbon/`, `code/ghc/`) covers the recursive case these sources leave out: trees flattened
into serialized buffers.

**Read first:** `docs/arrow/docs/source/format/Columnar.rst` (sections Struct Layout, Union
Layout, Variable-size List Layout, Validity bitmaps, and the RecordBatch message's pre-order
flattening), `melnik-2010-dremel` §4.1 and Appendices A–C (repetition and definition levels,
shredding and assembly), `code/zig/lib/std/multi_array_list.zig` (lines 9–231) with
`code/zig/lib/std/zig/Ast.zig` (`Node`, `Data`, `extraData`), and
`filliatre-2006-hash-consing` §2–3.

**Claims these settle:** how Arrow derives a physical layout for each nested type (struct,
list, large list, list view, fixed-size list, dense and sparse union, map, dictionary, run-end
encoded) and what each costs per value; that Arrow and Parquet have no layout for recursive
types and Parquet has no union; how definition and repetition levels encode optional and
repeated fields losslessly in leaf columns, and what record assembly costs as measured in
Dremel; how Zig derives a structure of arrays from a struct or tagged union at compile time and
builds its self-hosted compiler's AST, ZIR and intern pool from index-based tables; what
StructArrays.jl and `Data.Vector.Unboxed` decide by type and leave to the programmer; what
hash-consing gives (constant-time equality and hashing, memoization) and costs, as measured.

Summary-table deltas: +2 papers stored (2 PDF); +0 link-only; +8 snapshots (4 `docs/`, 4
`code/`). The Summary table needs the new topic in the topic list at the top of `INDEX.md`.


### Flattened data: packed, columnar and nested layouts — flattening

Topic **Flattened data: packed, columnar and nested layouts**, subtopic **Flattening nested
data parallelism** (segmented representations, the flattening transformation and its typing,
recursive and sum types, the costs of replication and conditionals, DPH against Futhark).

| Paper | Title | Authors | Venue / year | Link | Stored | Threads | Licence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [`blelloch-1990-vector-models`](papers/blelloch-1990-vector-models/) | Vector Models for Data-Parallel Computing | Blelloch | MIT Press, 1990 | https://www.cs.cmu.edu/~guyb/papers/Ble90.pdf | PDF (author page) | flattening, G | MIT Press © unknown–verify; author copy | stored |
| [`blelloch-1994-portable-nesl`](papers/blelloch-1994-portable-nesl/) | Implementation of a Portable Nested Data-Parallel Language | Blelloch, Chatterjee, Hardwick, Sipelstein, Zagha | JPDC 21(1), 1994 (PPoPP 1993; CMU-CS-93-112) | https://doi.org/10.1006/jpdc.1994.1038 | 2 copies: PDF scan of the article (author page); PostScript of the technical report (CMU archive) | flattening | Academic Press © unknown–verify; TR none stated | stored |
| [`blelloch-1995-nesl`](papers/blelloch-1995-nesl/) | NESL: A Nested Data-Parallel Language (Version 3.1) | Blelloch | CMU-CS-95-170, 1995 | http://reports-archive.adm.cs.cmu.edu/anon/1995/CMU-CS-95-170.pdf | PDF (author page, typeset) | flattening | CMU TR, none stated (verify) | stored |
| [`blelloch-1996-programming-parallel-algorithms`](papers/blelloch-1996-programming-parallel-algorithms/) | Programming Parallel Algorithms | Blelloch | CACM 39(3), 1996 | https://doi.org/10.1145/227234.227246 | HTML (author's online version, 68 files) | flattening | ACM ©, personal-use notice; author copy (verify) | stored |
| [`keller-1998-flattening-trees`](papers/keller-1998-flattening-trees/) | Flattening Trees | Keller, Chakravarty | Euro-Par 1998, LNCS 1470 | https://doi.org/10.1007/BFb0057920 | PostScript (author page via Wayback) | flattening | Springer © unknown–verify; preprint | stored |
| [`chakravarty-2000-more-types`](papers/chakravarty-2000-more-types/) | More Types for Nested Data Parallel Programming | Chakravarty, Keller | ICFP 2000 | https://doi.org/10.1145/351240.351249 | PostScript (author page via Wayback) | flattening, E | ACM © unknown–verify; camera-ready | stored |
| [`leshchinskiy-2006-higher-order-flattening`](papers/leshchinskiy-2006-higher-order-flattening/) | Higher Order Flattening | Leshchinskiy, Chakravarty, Keller | PAPP 2006, LNCS 3992 | https://doi.org/10.1007/11758525_122 | PostScript (author page via Wayback) | flattening, cross-cutting | Springer © unknown–verify; preprint | stored |
| [`chakravarty-2007-dph-status`](papers/chakravarty-2007-dph-status/) | Data Parallel Haskell: a status report | Chakravarty, Leshchinskiy, Peyton Jones, Keller, Marlow | DAMP 2007 | https://doi.org/10.1145/1248648.1248652 | PDF (Microsoft Research) | flattening | ACM © unknown–verify; author copy | stored |
| [`peytonjones-2008-harnessing-multicores`](papers/peytonjones-2008-harnessing-multicores/) | Harnessing the Multicores: Nested Data Parallelism in Haskell | Peyton Jones, Leshchinskiy, Keller, Chakravarty | FSTTCS 2008, LIPIcs 2 | https://doi.org/10.4230/LIPIcs.FSTTCS.2008.1769 | PDF (Dagstuhl DROPS) | flattening, cross-cutting | CC-BY-NC-ND | stored |
| [`lippmeier-2012-work-efficient-vectorisation`](papers/lippmeier-2012-work-efficient-vectorisation/) | Work Efficient Higher-Order Vectorisation | Lippmeier, Chakravarty, Keller, Leshchinskiy, Peyton Jones | ICFP 2012 | https://doi.org/10.1145/2364527.2364564 | PDF (Microsoft Research) | flattening | ACM © unknown–verify; author copy | stored |
| [`keller-2012-vectorisation-avoidance`](papers/keller-2012-vectorisation-avoidance/) | Vectorisation Avoidance | Keller, Chakravarty, Leshchinskiy, Lippmeier, Peyton Jones | Haskell Symposium 2012 | https://doi.org/10.1145/2364506.2364512 | PDF (author page via Wayback, preprint) | flattening | ACM © unknown–verify; preprint states none | stored |
| [`bergstrom-2013-data-only-flattening`](papers/bergstrom-2013-data-only-flattening/) | Data-Only Flattening for Nested Data Parallelism | Bergstrom, Fluet, Rainey, Reppy, Rosen, Shaw | PPoPP 2013 | https://doi.org/10.1145/2442516.2442525 | PDF (Manticore project site, preprint) | flattening | ACM © unknown–verify; preprint states none | stored |
| [`larsen-2017-segmented-reductions`](papers/larsen-2017-segmented-reductions/) | Strategies for Regular Segmented Reductions on GPU | Larsen, Henriksen | FHPC 2017 | https://doi.org/10.1145/3122948.3122952 | PDF (futhark-lang.org) | flattening, G | ACM © unknown–verify; project copy | stored |
| [`elsman-2019-flattening-by-expansion`](papers/elsman-2019-flattening-by-expansion/) | Data-Parallel Flattening by Expansion | Elsman, Henriksen, Serup | ARRAY 2019 | https://doi.org/10.1145/3315454.3329955 | PDF (futhark-lang.org) | flattening, G | ACM © unknown–verify; project copy | stored |
| [`hashemi-2026-full-flattening`](papers/hashemi-2026-full-flattening/) | Full Flattening of Nested Data Parallelism in the Futhark Compiler | Hashemi | MSc thesis, Aalto University and DTU, 2026 | https://futhark-lang.org/student-projects/amir-msc-thesis.pdf | PDF (futhark-lang.org) | flattening, G | CC-BY-NC-SA 4.0 | stored |

| Shortname | Title | Authors | Venue / year | Link | Threads | Licence | Status / reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `blelloch-1990-collection-oriented` | Compiling collection-oriented languages onto massively parallel computers | Blelloch, Sabot | JPDC 8(2):119–134, 1990 | https://doi.org/10.1016/0743-7315(90)90087-6 | flattening | Elsevier © | link-only (closed; not on the author's publications page, no OA copy found; the book `blelloch-1990-vector-models` Ch. 10–11 covers the transformation) |
| `blelloch-1990-prefix-sums` | Prefix Sums and Their Applications | Blelloch | in *Synthesis of Parallel Algorithms*, Morgan Kaufmann, 1991 (CMU-CS-90-190) | https://www.cs.cmu.edu/~guyb/papers/Ble93.pdf | flattening | author copy, verify | link-only (open on the author page, HTTP 200, 311,166 bytes; not taken: segmented scans are covered by `blelloch-1990-vector-models` §3–4, §13) |
| `blelloch-1996-provable-nesl` | A provable time and space efficient implementation of NESL | Blelloch, Greiner | ICFP 1996 | (DOI not resolved; ACM DL) | flattening | ACM © | link-only (no author PDF on the publications page; cited by `chakravarty-2000-more-types`) |
| `keller-1998-flattening-trees-tr` | Flattening trees (unabridged) | Keller, Chakravarty | TU Berlin Forschungsbericht 98-6, 1998 | (none located) | flattening | unknown | unresolved (cited in `keller-1998-flattening-trees`; no copy located) |
| `keller-1999-thesis` | Transformation-based Implementation of Nested Data Parallelism for Distributed Memory Machines | Keller | PhD thesis, TU Berlin, 1999 | (none located) | flattening | unknown | unresolved (not searched beyond citations) |
| `leshchinskiy-2005-thesis` | Higher-Order Nested Data Parallelism: Semantics and Implementation | Leshchinskiy | PhD thesis, TU Berlin, 2005 | https://depositonce.tu-berlin.de/items/3a5f106d-4c15-4e5e-8610-7b7fb81b372f (URN urn:nbn:de:kobv:83-opus-12865) | flattening | repository OA, verify | link-only (open on DepositOnce; not fetched in this pass) |
| `lippmeier-2012-work-efficient-tr` | Work efficient higher-order vectorisation (unabridged) | Lippmeier et al. | UNSW-CSE-TR-201208, 2012 | (UNSW host 403) | flattening | unknown | link-only (cited by the ICFP paper; UNSW host blocks scripted fetches) |
| `bergstrom-2012-nesl-gpu` | Nested data-parallelism on the GPU | Bergstrom, Reppy | ICFP 2012 | (DOI not resolved) | flattening | ACM © | link-only (not searched; cited by `hashemi-2026-full-flattening` and `vect-avoid`) |
| `sevald-krause-2023-flattening` | Flattening Irregular Nested Parallelism in Futhark | Sevald-Krause | BSc thesis, DIKU, 2023 | https://futhark-lang.org/student-projects/cornelius-bsc-thesis.pdf | flattening | none stated (verify) | link-only (HTTP 200, 506,124 bytes; superseded by `hashemi-2026-full-flattening`) |

**Also** (filed elsewhere, serve this subtopic): `henriksen-2017-futhark` (Arrays and
scheduling); staged by the data-parallel cluster: `henriksen-2019-incremental-flattening`,
`henriksen-2017-futhark-thesis`, `chakravarty-2011-accelerate`, `mcdonell-2013-accelerate-optimising`;
staged by the apl-lineage cluster: `hsu-2019-data-parallel-compiler` (trees as parent vectors);
`shivers-2019-remora` (rank polymorphism).

**Snapshots.**
- `code/nesl/` (22 files, NESL 3.1.0 of 1995-12-20, no VCS; each file pinned by SHA-256): the
  flattening (`neslsrc/ptrans.lisp`), `partition`/`flatten`, the sequence-as-record type, the
  serial CVL segment descriptor and segmented scans.
- `docs/nesl/` (2 files, same release): `doc/cvl.ps` (CVL manual 2.1), `doc/vcode-ref.ps` (VCODE
  reference 2.0).
- `code/dph/` (20 files at `ghc/packages-dph` `64eca669f13f4d216af9024474a3fc73ce101793`): the
  three-layer segment descriptors, nested, sum and tuple `PData`, closures, the README's verdict on
  the copying representation.
- `code/ghc-vectoriser/` (11 files at `ghc/ghc` `13a86606e51400bc2a81a0e04cfbb94ada5d2620`, the
  parent of the vectoriser's removal `faee23bb`): vectorisation avoidance, the generic
  representation description, type classification.
- `docs/ghc-dph/` (15 GHC wiki pages, live, fetched 2026-10-09): project status, the replicate
  blow-up, the December 2010 benchmark status.

**Read first:** `papers/blelloch-1990-vector-models/Ble90.pdf` §4.3 and Ch. 10;
`papers/chakravarty-2000-more-types/pure-funs.ps` §4–6;
`papers/peytonjones-2008-harnessing-multicores/LIPIcs.FSTTCS.2008.1769.pdf` §4–6 (Figure 6);
`papers/lippmeier-2012-work-efficient-vectorisation/icfp60-lippmeier.pdf` §2–4;
`papers/hashemi-2026-full-flattening/amir-msc-thesis.pdf` §2.2.3, §3.5, Ch. 4, Ch. 7;
`docs/ghc-dph/data-parallel-benchmark-status.md`.

**Claims these settle:** what a segment descriptor must hold (lengths and offsets, not flags
alone; empty segments); that nesting depth d costs d descriptors or, after collapsing, one;
how products, sums, recursive types and closures flatten, and the type translation that
commutes with lifting; the replicating theorem's bounds and its containment condition; that the
contiguous representation makes replication copy and so breaks work complexity, and how virtual
segments or offset indirection fix it; the cost of flattening conditionals and of materialised
intermediates, and what vectorisation avoidance recovers; what DPH's own records show about
why it stalled, and how Futhark's restricted, regular-first, run-time-versioned approach
reached full flattening.


### Flattened data: packed, columnar and nested layouts — packed-trees

Topic **Flattened data: packed, columnar and nested layouts**, subtopic **Packed and serialized
trees** (pointer-free pre-order trees, location calculi, end witnesses and destination cursors,
offsets and indirections for random access, parallel allocation into packed regions, memory
management of serialized heaps, compact regions, layout selection from access patterns).

| Paper | Title | Authors | Venue / year | Link | Stored | Threads | Licence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [`vollmer-2017-packed-tree-transforms`](papers/vollmer-2017-packed-tree-transforms/) | Compiling Tree Transforms to Operate on Packed Representations | Vollmer, Spall, Chamith, Sakka, Koparkar, Kulkarni, Tobin-Hochstadt, Newton | ECOOP 2017 (LIPIcs 74) | https://doi.org/10.4230/LIPIcs.ECOOP.2017.26 | PDF (Dagstuhl DROPS) | flat, D | CC-BY 3.0 | stored |
| [`vollmer-2019-local`](papers/vollmer-2019-local/) | LoCal: A Language for Programs Operating on Serialized Data | Vollmer, Koparkar, Rainey, Sakka, Kulkarni, Newton | PLDI 2019 | https://doi.org/10.1145/3314221.3314631 | 2 PDFs (PLDI version, NSF PAR; extended TR741, IU ScholarWorks) | flat, D | ACM © (verify); none stated on the copies | stored |
| [`koparkar-2021-efficient-tree-traversals`](papers/koparkar-2021-efficient-tree-traversals/) | Efficient Tree-Traversals: Reconciling Parallelism and Dense Data Representations | Koparkar, Rainey, Vollmer, Kulkarni, Newton | ICFP 2021 (PACMPL 5) | https://doi.org/10.1145/3473596 (arXiv 2107.00522) | TeX (arXiv 2107.00522, extended version) | flat, D | CC-BY 4.0 (arXiv and ACM) | stored |
| [`koparkar-2024-mostly-serialized-gc`](papers/koparkar-2024-mostly-serialized-gc/) | Garbage Collection for Mostly Serialized Heaps | Koparkar, Singhal, Gupta, Rainey, Vollmer, Pelenitsyn, Tobin-Hochstadt, Kulkarni, Newton | ISMM 2024 | https://doi.org/10.1145/3652024.3665512 | PDF (NSF PAR, published version) | flat, D | CC-BY-ND 4.0 | stored |
| [`yang-2015-compact-normal-forms`](papers/yang-2015-compact-normal-forms/) | Efficient Communication and Collection with Compact Normal Forms | Yang, Campagna, Ağacan, El-Hassany, Kulkarni, Newton | ICFP 2015 | https://doi.org/10.1145/2784731.2784735 | PDF (author's version, ezyang.com) | flat, D | ACM © (verify); copy says "Not for redistribution" | stored |
| [`singhal-2024-marmoset`](papers/singhal-2024-marmoset/) | Optimizing Layout of Recursive Datatypes with Marmoset | Singhal, Koparkar, Zullo, Pelenitsyn, Vollmer, Rainey, Newton, Kulkarni | ECOOP 2024 (LIPIcs 313) | https://doi.org/10.4230/LIPIcs.ECOOP.2024.38 (arXiv 2405.17590) | TeX (arXiv 2405.17590v3) | flat, D | CC-BY 4.0 (arXiv and LIPIcs) | stored |
| [`allais-2023-serialised-data`](papers/allais-2023-serialised-data/) | Seamless, Correct, and Generic Programming over Serialised Data | Allais | preprint 2023/2024, submitted to JFP | https://arxiv.org/abs/2310.13441 | TeX (arXiv 2310.13441v2) with Idris 2 sources as Katla TeX and benchmark CSVs | flat, D | CC-BY 4.0 | stored |

**Also** (filed elsewhere, serve this subtopic): `bernardy-2018-linear-haskell` (Types and
quantities; its section "Computing directly with serialised data" gives the linear `Needs`
write-pointer API), `reinking-2021-perceus` and `lorenzen-2023-fp2` (Memory; the in-place reuse a
packed representation competes with), `johansson-2002-heap-architectures` (Memory; copying
messages between heaps), `peytonjones-1992-stg` (CNF's semantics is stated over STG).

**Snapshots.**
- `code/gibbon/` (28 files at `41e650f14f2a815bcc78ec466a05bae6a33a7a11`): the packed pipeline in
  `gibbon-compiler/src/Gibbon/Compiler.hs`; IRs `L2/Syntax.hs`, `L2/Typecheck.hs`,
  `NewL2/{Syntax,FromOldL2}.hs`, `L3/Syntax.hs`, `LocExp.hs`; passes
  `Passes/{InferLocations,RegionsInwards,InferRegionScope,InferEffects,AddTraversals,AddRAN,RemoveCopies,FindWitnesses,RouteEnds,FollowPtrs,ParAlloc,ThreadRegions2,InferFunAllocs,Cursorize}.hs`;
  runtime `gibbon-rts/rts-c/gibbon_rts.{h,c}`, `gibbon-rts/rts-ng/src/{gc.rs,notes.md}`; the
  root and compiler READMEs.
- `code/ghc/` (7 files at tag `ghc-9.14.1-release`, `902339d332fb4ce2b3c87dcac1ee6495d41ad886`):
  `rts/sm/CNF.{c,h}`, `libraries/ghc-compact/GHC/Compact.hs`,
  `libraries/ghc-compact/GHC/Compact/Serialized.hs`, `ghc-compact.cabal`, both `LICENSE` files.

**Read first:** `papers/vollmer-2019-local/TR741.pdf` §3–4 and App. C (the calculus, the compiler
stages, the region runtime); `papers/vollmer-2017-packed-tree-transforms` §4 (effects, end
witnesses, cursor types); `papers/koparkar-2021-efficient-tree-traversals/ms.tex` §3 and §4.1,
§4.5 (parallel regions, granularity, region-upon-steal); `papers/koparkar-2024-mostly-serialized-gc`
§2–3; `papers/allais-2023-serialised-data/desc.tex`, `hexdump.tex`, `poking.tex` (the Idris 2
version).

**Claims these settle:** when a tree can be packed (unique destinations, no sharing without an
indirection, in-order traversal and allocation, acyclic, whole program); how traversals compile
(traversal effects by shrinking fixpoint, end witnesses as extra returns, destination cursors,
dilated start/end pairs, a type-checked IR between passes); the space/time trade-off of offsets,
indirections and dummy traversals, and of reordering fields instead; how parallel construction
fragments a packed heap and how to bound it; how serialized heaps are managed (chunked regions
with footers, region reference counts with outsets, a generational copying collector with
burning and forwarding, compact regions as one GC object); measured speedups and their limits.

**Unresolved rows this cluster closes:** none recorded in sources/README.md for these papers.
Not stored: the authors' PhD theses (Vollmer, Indiana University; Koparkar, Indiana University),
searched for and not located in an open repository on 2026-10-09; the Marmoset DARTS artifact
(https://doi.org/10.4230/DARTS.10.2.21), not fetched.


### Fast dependent type checking and elaboration — elaborators

Topic: **Fast dependent type checking and elaboration**.

### Subtopic: Elaborators and kernels, and how fast they are

| Paper | Title | Authors | Venue / year | Link | Stored | Threads | Licence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [`demoura-2021-lean4`](papers/demoura-2021-lean4/) | The Lean 4 Theorem Prover and Programming Language | de Moura, Ullrich | CADE-28 2021 (LNAI 12699) | https://doi.org/10.1007/978-3-030-79876-5_37 | PDF (KIT repository; published text) | elaborators | CC-BY 4.0 | stored |
| [`selsam-2020-tabled-typeclass`](papers/selsam-2020-tabled-typeclass/) | Tabled Typeclass Resolution | Selsam, Ullrich, de Moura | arXiv 2020 | https://arxiv.org/abs/2001.04301 | TeX (arXiv 2001.04301 v2) with `anc/` data | elaborators | arXiv non-exclusive | stored |
| [`carneiro-2024-lean4lean`](papers/carneiro-2024-lean4lean/) | Lean4Lean: Verifying a Typechecker for Lean, in Lean | Carneiro | arXiv 2024, v3 2025 (submitted to CPP 2026) | https://arxiv.org/abs/2403.14064 | TeX (arXiv 2403.14064 v3) | elaborators | arXiv non-exclusive | stored |
| [`boespflug-2011-full-throttle`](papers/boespflug-2011-full-throttle/) | Full Reduction at Full Throttle | Boespflug, Dénès, Grégoire | CPP 2011 (LNCS 7086) | https://doi.org/10.1007/978-3-642-25379-9_26 | PDF (author site) | elaborators | Springer © unknown–verify; none stated on the copy | stored |
| [`wenzel-2009-parallel-isabelle`](papers/wenzel-2009-parallel-isabelle/) | Parallel Proof Checking in Isabelle/Isar | Wenzel | PLMMS 2009 | https://www21.in.tum.de/~wenzelm/papers/parallel-isabelle.pdf | PDF (author site) | elaborators | none stated (verify) | stored (DOI unresolved) |
| [`wenzel-2013-read-eval-print`](papers/wenzel-2013-read-eval-print/) | READ-EVAL-PRINT in Parallel and Asynchronous Proof-checking | Wenzel | UITP 2012, EPTCS 118 (2013) | https://doi.org/10.4204/EPTCS.118.4 | TeX (arXiv 1307.1944) | elaborators | CC BY-NC-ND (EPTCS); arXiv non-exclusive | stored |
| [`barras-2015-async-coq`](papers/barras-2015-async-coq/) | Asynchronous Processing of Coq Documents: From the Kernel up to the User Interface | Barras, Tankink, Tassi | ITP 2015 (LNCS 9236) | https://doi.org/10.1007/978-3-319-22102-1_4 | TeX (arXiv 1506.05605) | elaborators | arXiv non-exclusive | stored |
| [`swamy-2016-fstar-mumon`](papers/swamy-2016-fstar-mumon/) | Dependent Types and Multi-Monadic Effects in F* | Swamy, Hriţcu, Keller, Rastogi, Delignat-Lavaud, Forest, Bhargavan, Fournet, Strub, Kohlweiss, Zinzindohoue, Zanella-Béguelin | POPL 2016 | https://doi.org/10.1145/2837614.2837655 | PDF (F* project site) | elaborators | ACM © unknown–verify; none stated on the copy | stored |
| [`martinez-2019-meta-fstar`](papers/martinez-2019-meta-fstar/) | Meta-F*: Proof Automation with SMT, Tactics, and Metaprograms | Martínez, Ahman, Dumitrescu, Giannarakis, Hawblitzel, Hriţcu, Narasimhamurthy, Paraskevopoulou, Pit-Claudel, Protzenko, Ramananandro, Rastogi, Swamy | ESOP 2019 (LNCS 11423) | https://doi.org/10.1007/978-3-030-17184-1_2 | TeX (arXiv 1803.06547) | elaborators, SMT | arXiv non-exclusive | stored |
| [`gross-2024-scalable-proof-engine`](papers/gross-2024-scalable-proof-engine/) | Towards a Scalable Proof Engine: A Performant Prototype Rewriting Primitive for Coq | Gross, Erbsen, Philipoom, Agrawal, Chlipala | JAR 68 (2024), art. 19 | https://doi.org/10.1007/s10817-024-09705-6 | TeX (arXiv 2305.02521, accepted manuscript) | elaborators | arXiv non-exclusive | stored |

**Also:** `gregoire-2002-strong-reduction` (kernels cluster, this topic): Coq's bytecode
strong reducer; `brady-2021-idris2-qtt` (Types and quantities): the Idris 2 elaborator and
its 90 s self-build; `ullrich-2019-counting-immutable-beans` (Memory): the Lean 4 compiler's
reference counting; `kovacs-2022-staged`, `kovacs-2024-closure-free` (Specialization): the
author of smalltt on staging; `abel-2011-dynamic-pattern-unification`,
`gundry-2012-dynamic-pattern-unification` (this topic, unification cluster);
`farber-2022-kontroli` (this topic, kernels cluster): concurrent proof checking;
`zhou-2023-mariposa` (SMT cluster): SMT instability.

**Snapshots.**
- `code/smalltt/` (`AndrasKovacs/smalltt` at `ea99b0f4`): README with every benchmark table,
  `bench/README.md` and the conversion/asymptotics sources, the evaluator, unifier,
  elaborator, meta context; MIT.
- `code/elaboration-zoo/` (`AndrasKovacs/elaboration-zoo` at `9626d6c7`): `GluedEval.hs`,
  `05-pruning/`, `03-holes/pattern-unification.txt`; BSD-3-Clause style.
- `code/lean4lean/` (`digama0/lean4lean` at `8223d223`): `TypeChecker.lean`,
  `EquivManager.lean`, `Instantiate.lean`, `PtrEq.lean`, `Expr.lean`, `Main.lean`, README,
  `bugs-found.md`; Apache-2.0.
- `code/nanoda_lib/` (`ammkrn/nanoda_lib` at `3a240721`, crate 0.4.19): `tc.rs`, `expr.rs`,
  `util.rs`, `union_find.rs`, `unique_hasher.rs`, `main.rs`, `Cargo.toml`, README; Apache-2.0.
- `code/lean4/` addendum (`leanprover/lean4` at `7cd10322`, the pin the other clusters use):
  kernel `type_checker.{h,cpp}`, `instantiate.{h,cpp}`, `expr.{h,cpp}`, `expr_eq_fn.cpp`,
  `abstract.cpp`, `replace_fn.cpp`, `environment.cpp`; `runtime/sharecommon.{h,cpp}`;
  `library/instantiate_mvars.cpp`; `Lean/Meta/{ExprDefEq,WHNF,SynthInstance}.lean`;
  `Lean/Language/Lean.lean`, `Lean/Elab/Frontend.lean`; merge
  `code/lean4/SNAPSHOT.elaborators.md` into `code/lean4/SNAPSHOT.md` (+18 files).
- `docs/lean-reference-manual/` (`leanprover/reference-manual` at `349244b4`): release notes
  4.8, 4.17, 4.18, 4.19, 4.23 (parallel elaboration), `LICENSE`; Apache-2.0.
- `docs/agda/` addendum (`agda/agda` at `83f3fcce`): `tools/performance.rst`,
  `language/lossy-unification.lagda.rst`, `language/opaque-definitions.lagda.rst`; merge
  `docs/agda/SNAPSHOT.elaborators.md` (+3 files).
- `docs/pop-in-fstar/` addendum (`FStarLang/PoP-in-FStar` at `958d86f2`): `book/intro.rst`,
  `book/part3/part3_typeclasses.rst`, `book/part5/part5_meta.rst`; merge
  `docs/pop-in-fstar/SNAPSHOT.elaborators.md` (+3 files).
- Read in place, not snapshotted: this repository's Idris 2 fork, `compiler/idris/src/Core/{Value,Normalise/Eval,Normalise/Convert,Unify,AutoSearch,Context}.idr`,
  `compiler/idris/src/TTImp/Elab/{Delayed,Ambiguity}.idr`.

**Read first:** `code/smalltt/README.md` (design and benchmarks),
`code/lean4/src/kernel/type_checker.h` and `type_checker.cpp` 962–1210,
`papers/selsam-2020-tabled-typeclass/typeclass.tex` 353–614,
`papers/carneiro-2024-lean4lean/main.tex` 416–554 and 753–779,
`papers/wenzel-2009-parallel-isabelle/` §§1.3 and 5, `papers/barras-2015-async-coq/full.tex`
887–946, `papers/martinez-2019-meta-fstar/paper.tex` 5360–5590.

**Claims these settle:** that NbE with glued heads and bounded speculative unification beat
every production elaborator on 2021 synthetic benchmarks by one to two orders of magnitude,
Idris 2 being the slowest; which kernel caches are sound (defeq pair sets, not union-find)
and why; that tabled instance search removes diamond blow-up; what compiled normalization
buys (2–45x) and costs (trusted compiler); what parallel proof checking buys (3x on 4 cores,
latency 1 h to 7 min) and what it rests on (proof irrelevance); that raw SMT on nonlinear
goals is unstable while normalize-then-SMT is robust. They do not settle current
cross-system speeds, nor any speedup of Lean's parallel elaboration (none is published).


### Fast dependent type checking and elaboration — kernels-trust

Topic **Fast dependent type checking and elaboration**, subtopic **Small trusted kernels,
proof-checking speed and reflection** (the de Bruijn criterion and independent checking;
how small and how fast a checker can be, measured; certificate formats that make checking
linear; proof by reflection and compiled conversion; dynamic pattern unification as the
elaborator's untrusted half).

| Paper | Title | Authors | Venue / year | Link | Stored | Threads | Licence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [`pollack-1998-believe-machine-checked-proof`](papers/pollack-1998-believe-machine-checked-proof/) | How to Believe a Machine-Checked Proof | Pollack | in *Twenty Five Years of Constructive Type Theory*, OUP 1998 (BRICS RS-97-18, 1997) | https://doi.org/10.1093/oso/9780198501275.003.0013 | PDF (BRICS report version) | kernels-trust | © BRICS 1997, reproduction for research use with notice | stored (report, not the OUP text) |
| [`barendregt-2005-challenge-computer-mathematics`](papers/barendregt-2005-challenge-computer-mathematics/) | The Challenge of Computer Mathematics | Barendregt, Wiedijk | Phil. Trans. R. Soc. A 363(1835), 2005 | https://doi.org/10.1098/rsta.2005.1650 | TeX (author page) | kernels-trust | © Royal Society; author source, none stated (verify) | stored |
| [`wiedijk-2012-pollack-inconsistency`](papers/wiedijk-2012-pollack-inconsistency/) | Pollack-inconsistency | Wiedijk | UITP 2010, ENTCS 285, 2012 | https://doi.org/10.1016/j.entcs.2012.06.008 | TeX (author page) | kernels-trust | ENTCS; author source, none stated (verify) | stored |
| [`carneiro-2020-metamath-zero`](papers/carneiro-2020-metamath-zero/) | Metamath Zero: Designing a Theorem Prover Prover | Carneiro | CICM 2020 (arXiv extended version) | https://arxiv.org/abs/1910.10703 (https://doi.org/10.1007/978-3-030-53518-6_5) | TeX (arXiv 1910.10703v3) | kernels-trust | arXiv non-exclusive | stored |
| [`carneiro-2022-metamath-zero-thesis`](papers/carneiro-2022-metamath-zero-thesis/) | Metamath Zero: From Logic, to Proof Assistant, to Verified Compilation | Carneiro | Ph.D. dissertation, CMU, PDF of 2022-06-06 | https://digama0.github.io/mm0/thesis.pdf | PDF (project site) | kernels-trust | none stated (verify) | stored (deposited version not confirmed) |
| [`assaf-2016-dedukti`](papers/assaf-2016-dedukti/) | Dedukti: a Logical Framework based on the λΠ-Calculus Modulo Theory | Assaf, Burel, Cauderlier, Delahaye, Dowek, Dubois, Gilbert, Halmagrand, Hermant, Saillard | manuscript 2016, arXiv 2023 | https://arxiv.org/abs/2311.07185 | TeX (arXiv 2311.07185v1) | kernels-trust | arXiv non-exclusive | stored |
| [`farber-2022-kontroli`](papers/farber-2022-kontroli/) | Safe, Fast, Concurrent Proof Checking for the lambda-Pi Calculus Modulo Rewriting | Färber | CPP 2022 | https://arxiv.org/abs/2102.08766 (https://doi.org/10.1145/3497775.3503683) | TeX + raw evaluation data (arXiv 2102.08766v3) | kernels-trust | arXiv non-exclusive | stored |
| [`gonthier-2010-small-scale-reflection`](papers/gonthier-2010-small-scale-reflection/) | An introduction to small scale reflection in Coq | Gonthier, Mahboubi | J. Formalized Reasoning 3(2), 2010 | https://doi.org/10.6092/issn.1972-5787/1979 | PDF (journal) | kernels-trust | CC-BY 3.0 | stored |
| [`gregoire-2002-strong-reduction`](papers/gregoire-2002-strong-reduction/) | A Compiled Implementation of Strong Reduction | Grégoire, Leroy | ICFP 2002 | https://doi.org/10.1145/581478.581501 | PDF (author site) | kernels-trust | ACM © (author copy, verify) | stored |
| [`abel-2011-dynamic-pattern-unification`](papers/abel-2011-dynamic-pattern-unification/) | Higher-Order Dynamic Pattern Unification for Dependent Types and Records | Abel, Pientka | TLCA 2011 | https://doi.org/10.1007/978-3-642-21691-6_5 | 2 PDFs (conference, extended) + author errata | kernels-trust | Springer © (author copies, verify) | stored |
| [`gundry-2012-dynamic-pattern-unification`](papers/gundry-2012-dynamic-pattern-unification/) | A tutorial implementation of dynamic pattern unification | Gundry, McBride | unpublished draft, 2012 | http://adam.gundry.co.uk/pub/pattern-unify/ | PDF + thesis errata; code in `code/pattern-unify/` | kernels-trust | none stated (verify) | stored |

| Link only | Title | Authors | Venue / year | Link | Threads | Licence | Status / reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `boutin-1997-reflection` | Using reflection to build efficient and certified decision procedures | Boutin | TACS 1997, LNCS 1281, pp. 515–529 | https://doi.org/10.1007/BFb0014565 | kernels-trust | Springer © | link-only: no open copy found (web search 2026-10-09); OpenAlex/Unpaywall not queried (OpenAlex daily budget exhausted, HTTP 429) |
| `gonthier-2008-ssreflect-manual` | A Small Scale Reflection Extension for the Coq system | Gonthier, Mahboubi, Tassi | INRIA RR-6455, 2008 (revised to 2016) | https://inria.hal.science/inria-00258384 | kernels-trust | HAL deposit (verify) | link-only: HAL served its bot challenge (HTTP 200 HTML), not evaded; the methodology paper `gonthier-2010-small-scale-reflection` is stored instead |
| `gonthier-2008-four-colour` | Formal Proof—The Four-Color Theorem | Gonthier | Notices of the AMS 55(11), 2008 | https://www.ams.org/notices/200811/tx081101382p.pdf | kernels-trust | AMS (free to read) | link-only: `www.ams.org` returned HTTP 403 to scripted fetch |

**Also** (filed elsewhere, serve this subtopic): staged by sibling tc clusters:
`boespflug-2011-full-throttle` (native compilation of conversion in Coq, the successor of
`gregoire-2002-strong-reduction`), `carneiro-2024-lean4lean` and `code/lean4lean/` (a second
Lean kernel, measured on Mathlib), `code/nanoda_lib/` (an independent Lean 4 checker in
Rust); in the library: `brady-2021-idris2-qtt` (Types and quantities),
`christiansen-2016-elaborator-reflection` (link-only), `leroy-2009-compcert`,
`lopes-2021-alive2`, `bhat-2024-verifying-peephole` (Verification: translation validation as
the alternative to trusting a compiler); staged by the apl clusters: `allais-2025-frex`
(reflection for free extensions), the `cockx-*` unification papers.

**Snapshots.**
- `code/mm0/` (Metamath Zero `0d414c0b`: the verifier `mm0-c/*.c` and its README, the `.mmb`
  format `mm0-c/mmb.md`, the `.mm0` language `mm0.md`); [SNAPSHOT](code/mm0/SNAPSHOT.md).
- `code/dedukti/` (Dedukti `f3c0eba8`: the whole `kernel/`, 29 files: abstract machine,
  decision trees, matching, typing of rewrite rules, conversion); [SNAPSHOT](code/dedukti/SNAPSHOT.md).
- `code/kontroli/` (Kontroli `c980688b`, the revision measured in `farber-2022-kontroli`:
  `kontroli/src/kernel/*.rs`, 9 files); [SNAPSHOT](code/kontroli/SNAPSHOT.md).
- `code/pattern-unify/` (Gundry and McBride's literate Haskell, 2012-07-10 tarball, 7 files);
  [SNAPSHOT](code/pattern-unify/SNAPSHOT.md).
- `docs/metamath/` (the Metamath book's LaTeX at `metamath-book` `a54c7159`, the
  metamath-knife README at `76fc9f7f`, the Metamath site's list of verifiers);
  [SNAPSHOT](docs/metamath/SNAPSHOT.md).

**Read first:** `carneiro-2020-metamath-zero` (§1.2, §3), `code/mm0/mm0-c/verifier.c`,
`farber-2022-kontroli` (§7–8 and `eval/`), `pollack-1998-believe-machine-checked-proof`
(§1.1, §3.2.1, §4.1), `gregoire-2002-strong-reduction` (§2–6), `abel-2011-dynamic-pattern-unification`
errata.

**Claims these settle:** how small a checker can be and what each line count includes; which
proof-checking speeds are measured (machine, input, method) and which are not; how a
certificate format can make checking linear and equality O(1); where parallelism in a
checker pays (declarations) and where it does not (reduction, parsing through a channel);
what compiling conversion buys for proofs by reflection and what it adds to the trusted base;
why unification belongs outside the kernel.


### Swift: ownership, ARC and the compiler

| Entry | What it is |
| --- | --- |
| [`docs/swift`](docs/swift/) | Snapshot addendum: Swift SIL, ownership SSA, ARC and copy-on-write (cluster `sil-arc`) |
| [`docs/swift-embedded-examples`](docs/swift-embedded-examples/) | Snapshot: Embedded Swift documentation (DocC catalog) |
| [`docs/swift-evolution`](docs/swift-evolution/) | Snapshot addendum: Swift Evolution vision for Embedded Swift (cluster `sil-arc`) |
| [`docs/swift-forums`](docs/swift-forums/) |  |
| [`docs/swift-org`](docs/swift-org/) | Snapshot: Swift.org blog posts on Embedded Swift |
| [`code/swift`](code/swift/) | Snapshot addendum: Swift ownership verifier, semantic ARC and COW sources (cluster `sil-arc`) |
| [`papers/benes-2025-simple-essence-of-overloading`](papers/benes-2025-simple-essence-of-overloading/) |  |
| [`papers/milano-2022-fearless-concurrency`](papers/milano-2022-fearless-concurrency/) |  |


## Reading notes

`notes/` holds the deep-dive notes written while these sources were read (array-languages, flattened-data, type-checking): what each source says and what idris-mlir should take from it, cited to the stored files. Proposals 0004, 0006 and 0007 build on them.
