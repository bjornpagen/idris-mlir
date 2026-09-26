# Paper corpus index

Index of every paper attempted in the `papers-arxiv`, `papers-other`, and `papers-index-commit`
steps of the sources-collection pass (fetched 2026-09-26). Identifiers, reachability, pins, and
the exact fetch commands live in `../sources/ACCESS.md`; the full target inventory lives in
`../sources/MANIFEST.md`.

Storage rule: raw LaTeX source is preferred; a PDF is stored only when no TeX source exists.
Each stored paper has its own folder `papers/<shortname>/` containing `README.md` plus the
source (or `paper.pdf`). All stored files are under the 20 MB per-file cap and no generated
LaTeX artifacts remain.

## Summary

| Outcome | Count |
| --- | --- |
| Stored as TeX source (20 arXiv e-prints) | 20 |
| Stored as PDF (no TeX available) | 14 |
| Link-only (DOI recorded; no OA copy obtained) | 37 |
| Unresolved (identifier/OA not located in this pass) | 27 entries |
| **Total entries** | **98** |

All IDs/links below are as resolved in `ACCESS.md` unless marked as a correction in the
"Corrections and discrepancies" section.

## Stored — TeX source (arXiv `e-print`)

| Shortname | Title | Authors | Venue / year | Canonical link | Stored | Thread(s) | License | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `willsey-2021-egg` | egg: Fast and Extensible Equality Saturation | Willsey, Nandi, Wang, Flatt, Tatlock, Panchekha | POPL 2021 | https://arxiv.org/abs/2004.03082 | TeX (arXiv 2004.03082) | B | arXiv non-exclusive | stored |
| `zhang-2023-egglog` | Better Together: Unifying Datalog and Equality Saturation | Zhang, Wang, Flatt, Cao, Zucker, Rosenthal, Tatlock, Willsey | PLDI 2023 | https://arxiv.org/abs/2304.04332 | TeX (arXiv 2304.04332) | B | arXiv non-exclusive | stored |
| `zhang-2022-relational-ematching` | Relational E-Matching | Zhang, Wang, Willsey, Tatlock | POPL 2022 | https://arxiv.org/abs/2108.02290 | TeX (arXiv 2108.02290) | B | arXiv non-exclusive | stored |
| `wang-2020-spores` | SPORES: Sum-Product Optimization via Relational Equality Saturation | Wang, Hutchison, Leang, et al. | arXiv 2020 (VLDB 2020) | https://arxiv.org/abs/2002.07951 | TeX (arXiv 2002.07951) | B | arXiv non-exclusive | stored (resolved-corrected) |
| `zheng-2020-ansor` | Ansor: Generating High-Performance Tensor Programs for Deep Learning | Zheng, Jia, Sun, Wu, Yu, Haj-Ali, Wang, Yang, Zhuo, Sen, Gonzalez, Stoica | OSDI 2020 | https://arxiv.org/abs/2006.06762 | TeX (arXiv 2006.06762) | A, G | arXiv non-exclusive | stored |
| `yang-2021-tensat` | Equality Saturation for Tensor Graph Superoptimization (Tensat) | Yang, Phothilimthana, Wang, et al. | arXiv 2021 (PLDI 2021 Tensat) | https://arxiv.org/abs/2101.01332 | TeX (arXiv 2101.01332) | A, B | arXiv non-exclusive | stored (resolved-corrected) |
| `kovacs-2022-staged` | Staged Compilation with Two-Level Type Theory | András Kovács | ICFP 2022 | https://arxiv.org/abs/2209.09729 | TeX (arXiv 2209.09729) | C | arXiv non-exclusive | stored (resolved-corrected) |
| `koehler-2021-sketch-eqsat` | Sketch-Guided Equality Saturation | Koehler, Trinder, Steuwer | OOPSLA 2021 | https://arxiv.org/abs/2111.13040 | TeX (arXiv 2111.13040) | B | arXiv non-exclusive | stored |
| `ullrich-2019-counting-immutable-beans` | Counting Immutable Beans | Ullrich, de Moura | IFL 2019 | https://arxiv.org/abs/1908.05647 | TeX (arXiv 1908.05647) | D | arXiv non-exclusive | stored |
| `bernardy-2018-linear-haskell` | Linear Haskell | Bernardy, Boespflug, Newton, Peyton Jones, Spiwack | POPL 2018 | https://arxiv.org/abs/1710.09756 | TeX (arXiv 1710.09756) | D | arXiv non-exclusive | stored |
| `brady-2021-idris2-qtt` | Idris 2: Quantitative Type Theory in Practice | Edwin Brady | ECOOP 2021 | https://arxiv.org/abs/2104.00480 | TeX (arXiv 2104.00480) | E | arXiv non-exclusive | stored |
| `lattner-2020-mlir` | MLIR: A Compiler Infrastructure for the End of Moore's Law | Lattner, Amini, Bondhugula, Cohen, Davis, Pienaar, Riddle, Shpeisman, Vasilache, Zinenko | arXiv 2020 | https://arxiv.org/abs/2002.11054 | TeX (arXiv 2002.11054) | F | arXiv non-exclusive | stored |
| `bhat-2022-lambda-ultimate-ssa` | Lambda the Ultimate SSA | Bhat, Grosser | CGO 2022 | https://arxiv.org/abs/2201.07272 | TeX (arXiv 2201.07272) | F, I | arXiv non-exclusive | stored |
| `sasnauskas-2017-souper` | Souper: A Synthesizing Superoptimizer | Sasnauskas, Chen, Collingbourne, Ketema, Taneja, Regehr, et al. | arXiv 2017 | https://arxiv.org/abs/1711.04422 | TeX (arXiv 1711.04422) | H | arXiv non-exclusive | stored |
| `lucke-2024-transform-dialect` | The MLIR Transform Dialect | Lücke, Zinenko, Moses | arXiv 2024 | https://arxiv.org/abs/2409.03864 | TeX (arXiv 2409.03864) | F | arXiv non-exclusive | stored |
| `shivers-2019-remora` | Introduction to Rank-polymorphic Programming in Remora (Draft) | Shivers, Slepak, Manolios | arXiv 2019 | https://arxiv.org/abs/1912.13451 | TeX (arXiv 1912.13451) | G | arXiv non-exclusive | stored |
| `mendis-2019-ithemal` | Ithemal | Mendis, Renda, Amarasinghe, Carbin | ICML 2019 | https://arxiv.org/abs/1808.07412 | TeX (arXiv 1808.07412) | H | arXiv non-exclusive | stored |
| `wu-2026-slotted-egraphs` | Typed Flexible-Arity Slotted E-Graphs | Wu, Sullivan | arXiv 2026 | https://arxiv.org/abs/2609.03998 | TeX (arXiv 2609.03998) | B | arXiv non-exclusive | stored (future ID verified 200) |
| `chen-2018-tvm` | TVM: An Automated End-to-End Optimizing Compiler for Deep Learning | Chen et al. | OSDI 2018 | https://doi.org/10.5555/3291168.3291211 (arXiv https://arxiv.org/abs/1802.04799) | TeX (arXiv 1802.04799) | A, G | arXiv non-exclusive (preprint) | stored |
| `pal-2023-ruler` | Equality Saturation Theory Exploration à la Carte (Ruler) | Pal, Saiki, Tjoa, Richey, Zhu, Flatt, et al. | OOPSLA 2023 | https://doi.org/10.1145/3622834 (arXiv https://arxiv.org/abs/2609.14527) | TeX (arXiv 2609.14527) | B | arXiv non-exclusive (ACM version CC-BY) | stored (arXiv parallel located) |

## Stored — PDF (no TeX source available)

| Shortname | Title | Authors | Venue / year | Canonical link | Stored | Thread(s) | License | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `peytonjones-1992-stg` | Implementing lazy functional languages on stock hardware: the STG-machine | Simon Peyton Jones | JFP 1992 | https://doi.org/10.1017/S0956796800000319 | PDF (Cambridge Core OA) | D, Cross-cutting | CUP © unknown–verify | stored |
| `sorensen-1996-positive-supercompiler` | A positive supercompiler | Sørensen, Glück, Jones | JFP 1996 | https://doi.org/10.1017/S0956796800002008 | PDF (Cambridge Core OA) | C | CUP © unknown–verify | stored |
| `marlow-2006-fast-curry` | Making a fast curry: push/enter vs. eval/apply | Marlow, Peyton Jones | JFP 2006 (ICFP 2004) | https://doi.org/10.1017/S0956796806005995 | PDF (Cambridge Core OA) | D | CUP © unknown–verify | stored |
| `marshall-2022-linearity-uniqueness` | Linearity and Uniqueness: An Entente Cordiale | Marshall, Vollmer, Orchard | ESOP 2022 | https://doi.org/10.1007/978-3-030-99336-8_13 | PDF (Springer OA) | D | CC-BY | stored |
| `danvy-2001-defunctionalization` | Defunctionalization at work | Danvy, Nielsen | PPDP 2001 | https://doi.org/10.7146/brics.v8i23.21684 | PDF (BRICS OA) | Cross-cutting | BRICS OA (verify) | stored |
| `ragankelley-2013-halide` | Halide: a language and compiler for image processing pipelines | Ragan-Kelley, Barnes, Adams, Paris, Durand, Amarasinghe | PLDI 2013 | https://doi.org/10.1145/2499370.2462176 | PDF (DSpace@MIT) | G | CC-BY-NC-SA (MIT OA) | stored |
| `leroy-2009-compcert` | Formal verification of a realistic compiler (CompCert) | Xavier Leroy | CACM 2009 | https://doi.org/10.1145/1538788.1538814 | PDF (HAL green OA) | I | unknown–verify (HAL copy) | stored |
| `kjolstad-2017-taco` | The tensor algebra compiler (TACO) | Kjølstad, Kamil, Chou, Lugato, Amarasinghe | OOPSLA 2017 | https://doi.org/10.1145/3133901 | PDF (DSpace@MIT) | G | CC-BY (MIT OA) | stored |
| `ikarashi-2022-exo` | Exocompilation for productive programming of hardware accelerators | Ikarashi, Bernstein, Reinking, Genc, et al. | PLDI 2022 | https://doi.org/10.1145/3519939.3523446 | PDF (DSpace@MIT) | G | CC-BY-NC (MIT OA) | stored (resolved-corrected) |
| `bhat-2024-verifying-peephole` | Verifying Peephole Rewriting in SSA Compiler IRs | Bhat, Keizer, Hughes, Goens, Grosser | ITP 2024 | https://doi.org/10.4230/LIPIcs.ITP.2024.9 | PDF (LIPIcs DROPS) | F, I | CC-BY | stored |
| `henriksen-2017-futhark` | Futhark: purely functional GPU-programming | Henriksen, Serup, Elsman, Henglein, Oancea | PLDI 2017 | https://doi.org/10.1145/3062341.3062354 | PDF (author/lab site) | G | unknown–verify | stored |
| `adams-2019-halide-learning` | Learning to optimize halide with tree search and random programs | Adams, Ma, Anderson, Baghdadi, Li, et al. | SIGGRAPH 2019 | https://doi.org/10.1145/3306346.3322967 | PDF (eScholarship green OA) | G | unknown–verify | stored |
| `schkufza-2013-stoke` | Stochastic superoptimization (STOKE) | Schkufza, Sharma, Aiken | ASPLOS 2013 | https://doi.org/10.1145/2451116.2451150 | PDF (author site) | H | unknown–verify | stored |
| `lopes-2015-alive` | Provably correct peephole optimizations with Alive | Lopes, Menendez, Nagarakatte, Regehr | PLDI 2015 | https://doi.org/10.1145/2737924.2737965 | PDF (author site) | I | unknown–verify | stored |

## Link-only (DOI recorded; no open-access copy obtained)

No file stored. Reasons: `dl.acm.org` is blocked (HTTP 403) and the item's only indexed OA
location is on ACM; Elsevier/ScienceDirect PDFs returned HTTP 403; Springer landing pages are
not OA; two green-OA repositories were intermittently unavailable. Do **not** scrape
`dl.acm.org`.

| Shortname | Title | Authors | Venue / year | Canonical link | Stored | Thread(s) | License | Status / reason |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `koehler-2024-guided-eqsat` | Guided Equality Saturation | Koehler, Goens, Bhat, Grosser, Trinder, Steuwer | POPL 2024 | https://doi.org/10.1145/3632900 | link-only | B | ACM © unknown–verify | link-only (ACM 403; related sketch paper stored at `koehler-2021-sketch-eqsat`) |
| `jia-2019-taso` | TASO: optimizing deep learning computation with automatic generation of graph substitutions | Jia, Padon, Thomas, Warszawski, Zaharia, Aiken | SOSP 2019 | https://doi.org/10.1145/3341301.3359630 | link-only | A | ACM © unknown–verify | link-only (ACM 403) |
| `reinking-2021-perceus` | Perceus: garbage free reference counting with reuse | Reinking, Xie, de Moura, Leijen | PLDI 2021 | https://doi.org/10.1145/3453483.3454032 | link-only | D | ACM CC-BY | link-only (CC-BY but only on `dl.acm.org` 403) |
| `kovacs-2024-closure-free` | Closure-Free Functional Programming in a Two-Level Type Theory | András Kovács | ICFP 2024 | https://doi.org/10.1145/3674648 | link-only | C | ACM CC-BY | link-only (ACM 403; Chalmers record exposes no PDF) |
| `lorenzen-2024-oxidizing-ocaml` | Oxidizing OCaml with Modal Memory Management | Lorenzen, White, Dolan, Eisenberg, Lindley | ICFP 2024 | https://doi.org/10.1145/3674642 | link-only | D | ACM CC-BY | link-only (ACM 403; Edinburgh green OA returned 403) |
| `lorenzen-2023-fp2` | FP²: Fully in-Place Functional Programming | Lorenzen, Leijen, Swierstra | ICFP 2023 | https://doi.org/10.1145/3607840 | link-only | D | ACM CC-BY | link-only (ACM 403; Utrecht record exposes no direct PDF) |
| `lorenzen-2022-frame-limited-reuse` | Reference counting with frame limited reuse | Lorenzen, Leijen | ICFP 2022 | https://doi.org/10.1145/3547634 | link-only | D | ACM CC-BY | link-only (ACM 403) |
| `fehr-2022-irdl` | IRDL: an IR definition language for SSA compilers | Fehr, Niu, Riddle, Amini, Su, Grosser | PLDI 2022 | https://doi.org/10.1145/3519939.3523700 | link-only | F | ACM CC-BY-ND | link-only (ACM 403; ETH repository returned 500) |
| `mitchell-2010-rethinking-supercompilation` | Rethinking supercompilation | Neil Mitchell | ICFP 2010 | https://doi.org/10.1145/1863543.1863588 | link-only | C | ACM © unknown–verify | link-only (ACM 403) |
| `bolingbroke-2010-supercompilation-by-eval` | Supercompilation by evaluation | Bolingbroke, Peyton Jones | Haskell 2010 | https://doi.org/10.1145/1863523.1863540 | link-only | C | ACM © unknown–verify | link-only (ACM 403) |
| `panchekha-2015-herbie` | Automatically improving accuracy for floating point expressions (Herbie) | Panchekha, Sanchez-Stern, Wilcox, Tatlock | POPL 2015 | https://doi.org/10.1145/2737924.2737959 | link-only | B | ACM © unknown–verify | link-only (ACM 403; author-site guess 404) |
| `lopes-2021-alive2` | Alive2: bounded translation validation for LLVM | Lopes, Lee, Hur, Liu, Regehr | PLDI 2021 | https://doi.org/10.1145/3453483.3454030 | link-only | I | ACM © unknown–verify | link-only (ACM 403; author-site guess 404) |
| `brady-2004-inductive-families` | Inductive Families Need Not Store Their Indices | Brady, McBride, McKinna | TYPES 2003 | https://doi.org/10.1007/978-3-540-24849-1_8 | link-only | E | Springer © unknown–verify | link-only (Springer landing not OA) |
| `lee-2001-size-change` | The size-change principle for program termination | Lee, Jones, Ben-Amram | POPL 2001 | https://doi.org/10.1145/360204.360210 | link-only | E | ACM © unknown–verify | link-only (ACM 403) |
| `rondon-2008-liquid-types` | Liquid types | Rondon, Kawaguchi, Jhala | PLDI 2008 | https://doi.org/10.1145/1375581.1375602 | link-only | E | ACM © unknown–verify | link-only (ACM 403) |
| `wurthinger-2017-practical-partial-eval` | Practical partial evaluation for high-performance dynamic language runtimes | Würthinger, Wimmer, Humer, Wöß, Stadler, Seaton | PLDI 2017 | https://doi.org/10.1145/3062341.3062381 | link-only | C | ACM © unknown–verify | link-only (ACM 403) |
| `wurthinger-2013-one-vm` | One VM to rule them all | Würthinger, Wimmer, Wöß, Stadler, Duboscq, Humer | Onward! 2013 | https://doi.org/10.1145/2509578.2509581 | link-only | C | ACM © unknown–verify | link-only (ACM 403) |
| `teiiscak-2020-erasure-calculus` | A dependently typed calculus with pattern matching and erasure inference | Matúš Tejiščák | ICFP 2020 | https://doi.org/10.1145/3408973 | link-only | E | ACM CC-BY | link-only (ACM 403) |
| `chataing-2024-unboxed-data-constructors` | Unboxed Data Constructors | Chataing, Dolan, Scherer, Yallop | POPL 2024 | https://doi.org/10.1145/3632893 | link-only | E | ACM CC-BY | link-only (ACM 403) |
| `taha-2000-metaml` | MetaML and multi-stage programming with explicit annotations | Taha, Sheard | TCS 2000 | https://doi.org/10.1016/S0304-3975(00)00053-0 | link-only | C | Elsevier © unknown–verify | link-only (ScienceDirect PDF returned HTTP 403, contrary to ACCESS.md) |
| `christiansen-2016-elaborator-reflection` | Elaborator reflection: extending Idris in Idris | Christiansen, Brady | ICFP 2016 | https://doi.org/10.1145/2951913.2951932 | link-only | C | ACM © unknown–verify | link-only (ACM 403; St Andrews repository returned 503) |
| `wadler-1990-deforestation` | Deforestation: transforming programs to eliminate trees | Philip Wadler | TCS 1990 | https://doi.org/10.1016/0304-3975(90)90147-A | link-only | C | Elsevier © unknown–verify | link-only (ScienceDirect PDF returned HTTP 403, contrary to ACCESS.md) |
| `gill-1993-short-cut` | A short cut to deforestation | Gill, Launchbury, Peyton Jones | FPCA 1993 | https://doi.org/10.1145/165180.165214 | link-only | C | ACM © unknown–verify | link-only (ACM 403) |
| `coutts-2007-stream-fusion` | Stream fusion: from lists to streams to nothing at all | Coutts, Leshchinskiy, Stewart | ICFP 2007 | https://doi.org/10.1145/1291151.1291199 | link-only | C | ACM © unknown–verify | link-only (ACM 403) |
| `mullapudi-2016-halide-autosched` | Automatically scheduling halide image processing pipelines | Mullapudi, Adams, Sharlet, Ragan-Kelley, Fatahalian | SIGGRAPH 2016 | https://doi.org/10.1145/2897824.2925952 | link-only | G | ACM © unknown–verify | link-only (ACM 403) |
| `massalin-1987-superoptimizer` | Superoptimizer: a look at the smallest program | Henry Massalin | ASPLOS 1987 | https://doi.org/10.1145/36206.36194 | link-only | H | ACM © unknown–verify | link-only (ACM 403) |
| `bansal-2006-peephole-superoptimizer` | Automatic generation of peephole superoptimizers | Bansal, Aiken | ASPLOS 2006 | https://doi.org/10.1145/1168918.1168906 | link-only | H | ACM © unknown–verify | link-only (ACM 403) |
| `joshi-2002-denali` | Denali: A Goal-directed Superoptimizer | Joshi, Nelson, Randall | PLDI 2002 | https://doi.org/10.1145/512529.512566 | link-only | H | ACM © unknown–verify | link-only (ACM 403) |
| `pnueli-1998-translation-validation` | Translation validation | Pnueli, Siegel, Singerman | TACAS 1998 | https://doi.org/10.1007/BFb0054170 | link-only | I | Springer © unknown–verify | link-only (Springer landing not OA) |
| `lafont-1990-interaction-nets` | Interaction nets | Yves Lafont | POPL 1990 | https://doi.org/10.1145/96709.96718 | link-only | J | ACM © unknown–verify | link-only (ACM 403) |
| `lamping-1990-optimal-reduction` | An algorithm for optimal lambda calculus reduction | John Lamping | POPL 1990 | https://doi.org/10.1145/96709.96711 | link-only | J | ACM © unknown–verify | link-only (ACM 403) |
| `reynolds-1972-definitional-interpreters` | Definitional interpreters for higher-order programming languages | John C. Reynolds | ACM 1972 | https://doi.org/10.1145/800194.805852 | link-only | Cross-cutting | ACM © unknown–verify | link-only (ACM 403) |
| `turchin-1986-supercompiler` | The concept of a supercompiler | Valentin F. Turchin | TOPLAS 1986 | https://doi.org/10.1145/5956.5957 | link-only | C | ACM © unknown–verify | link-only (ACM 403) |
| `taha-2004-gentle-intro-multistage` | A Gentle Introduction to Multi-stage Programming | Walid Taha | 2004 | https://doi.org/10.1007/978-3-540-25935-0_3 | link-only | C | Springer © unknown–verify | link-only (Springer landing not OA) |
| `rompf-2010-lms` | Lightweight modular staging (LMS) | Rompf, Odersky | GPCE 2010 | https://doi.org/10.1145/1868294.1868314 | link-only | C | ACM © unknown–verify | link-only (ACM 403) |
| `leijen-2017-koka-effects` | Type directed compilation of row-typed algebraic effects | Daan Leijen | POPL 2017 | https://doi.org/10.1145/3009837.3009872 | link-only | D | ACM © unknown–verify | link-only (ACM 403) |
| `blackburn-2008-immix` | Immix: a mark-region garbage collector | Blackburn, McKinley | ISMM 2008 | https://doi.org/10.1145/1375581.1375586 | link-only | D | ACM © unknown–verify | link-only (ACM 403; ANU repository 503, author-site guess 404) |

## Unresolved (carried over from `ACCESS.md` §3c)

Identifiers/OA copies were not located in this pass; recorded here with their reasons. These
are candidate targets, not yet a stored file or a confirmed DOI in every case.

| Plan item | Thread(s) | Status / reason |
| --- | --- | --- |
| "fractional uniqueness" (OOPSLA 2024) | D | unresolved — no matching title found via arXiv/OpenAlex title search; possibly a different published title (try Orchard/Marshall/Vollmer). |
| Brady PhD thesis (2013) | E | unresolved — hosted at `research-repository.st-andrews.ac.uk`, which is unreachable (returned 503 during this pass). |
| Christiansen PhD thesis | C | unresolved — no stable OA URL located. |
| Maranget, "Compiling Pattern Matching to Good Decision Trees" (ML 2008) | E | unresolved — DOI not verified via OpenAlex title search. |
| Wadler, pattern-matching compilation (1987) | E | unresolved — no DOI confirmed. |
| Abel, "foetus" termination checker | E | unresolved — no DOI; technical report, resolve via author host. |
| Wadler, linear types papers ("Linear Types Can Change the World", 1990) | D | unresolved — no DOI confirmed (IFIP proceedings). |
| "Secrets of the GHC inliner" (Peyton Jones & Marlow, JFP 2002) | Cross-cutting | unresolved — candidate DOI resolves to an unrelated paper. |
| warm fusion; shortcut fusion | C | unresolved — no specific canonical paper selected in the plan. |
| Futamura, "Partial evaluation of computation process" (1971) | C | unresolved — classic article with no DOI/OA copy located. |
| Garbage Collection Handbook | D | unresolved — book; no OA. Store as pointer only. |
| Boehm GC; "precise tracing GC" | D | unresolved — tech report / project pages; no single canonical paper. |
| Destination-passing style | D | unresolved — no specific canonical reference selected. |
| MLIR (CGO 2021) | F | unresolved — second MLIR paper; DOI not verified this pass. |
| Hovgaard et al., defunctionalisation (TFP 2018) | G | unresolved — DOI not verified. |
| Henriksen PhD thesis | G | unresolved — no OA URL located. |
| SaC | G | unresolved — no specific canonical reference selected. |
| MLGO / CompilerGym; autotuning and beam-search surveys | H | unresolved — no specific canonical references selected. |
| CertiCoq papers; "Certified Compilation of Coq" | I | unresolved — no DOI verified. |
| Lafont, Interaction Combinators (1997) | J | unresolved — no DOI verified. |
| Inpla / inets | J | unresolved — no specific canonical reference selected. |
| SSA-based Compiler Design (book) | F | unresolved — free PDF; store as pointer (chapter-level PDFs at collection time). |
| Jones/Gomard/Sestoft, Partial Evaluation and Automatic Program Generation (book) | C | unresolved — free author-hosted PDF; store as pointer / fetch PDF. |
| GMP manual; Modern Computer Arithmetic (book); Idris Integer/String | Cross-cutting | unresolved — docs/books; store as docs/pointers. |
| Koka effect types (additional papers) | D | unresolved — only Leijen POPL 2017 resolved; other Koka material is docs/code. |
| "e-graph extraction (ILP/MaxSAT) work" | B | unresolved — plan gives no author/title. |
| 2024–2026 POPL/PLDI/ICFP/OOPSLA/CGO + arXiv cs.PL sweep | J, Cross-cutting | unresolved — cannot be pre-enumerated; run as a live sweep and record demonstrated-vs-claimed. |

## Corrections and discrepancies found while fetching

These are places where `ACCESS.md` (or the plan's identifiers) did not match what the live hosts
served. They are recorded here so the report pass does not trust the incorrect row.

1. **`taha-2000-metaml` and `wadler-1990-deforestation` — ScienceDirect is 403, not 200.**
   `ACCESS.md` §3b labelled both "ScienceDirect PDF (verified 200)". Live probes on 2026-09-26
   returned **HTTP 403** (`text/html`) for both; they are recorded as link-only. OpenAlex also
   reports them as OA PDFs on ScienceDirect, so the OA flag itself is unreliable.
2. **`bhat-2024-verifying-peephole` — OpenAlex mislinks the DOI to a different arXiv paper.**
   OpenAlex maps DOI `10.4230/LIPIcs.ITP.2024.9` to `https://arxiv.org/pdf/2202.03293`, but that
   arXiv record is *"Composable and Modular Code Generation in MLIR"*, not the peephole paper.
   The correct OA source is the LIPIcs DROPS PDF
   (`lipics-vol309-itp2024/LIPIcs.ITP.2024.9`), whose title was verified as "Verifying Peephole
   Rewriting in SSA Compiler IRs". Stored from LIPIcs, not arXiv.
3. **`pal-2023-ruler` — an arXiv parallel version exists and yields TeX.**
   `ACCESS.md` only resolved the ACM DOI (`10.1145/3622834`, ACM 403). OpenAlex's location list
   exposed arXiv `2609.14527` ("Equality saturation theory exploration à la carte"), verified via
   the arXiv API, so raw TeX was fetched instead of a link.
4. **`chen-2018-tvm` — fetched as arXiv TeX; a USENIX OA PDF also exists.**
   Listed in §3b as a DOI with an arXiv OA fetch (`1802.04799`); stored as TeX. A USENIX OSDI PDF
   (`https://www.usenix.net/system/files/osdi18-chen.pdf`) is a second OA copy.
5. **`ragankelley-2013-halide` — MIT DSpace `/download` returns 405.**
   The `citation_pdf_url` DSpace exposes (`/bitstreams/<uuid>/download`) returns HTTP 405; the
   file is only retrievable via the DSpace REST content endpoint
   (`/server/api/core/bitstreams/<uuid>/content`). Item metadata confirmed the Halide title.
6. **`brady-2004-inductive-families`, `taha-2004-gentle-intro-multistage`, `pnueli-1998-translation-validation` — Springer "landing" is not OA.**
   `ACCESS.md` listed these as "Springer landing"; none exposes an OA PDF, so they are link-only.
7. **St Andrews repository remains unreachable (now 503).**
   `ACCESS.md` recorded `research-repository.st-andrews.ac.uk` as HTTP 000; during this pass it
   returned **503**, so `christiansen-2016-elaborator-reflection` (St Andrews PDF in OpenAlex)
   and the two St Andrews theses stayed unresolved/link-only.
8. **`wu-2026-slotted-egraphs` future-dated ID resolves.**
   `ACCESS.md` flagged arXiv `2609.03998` as future-dated / "verify at fetch time"; it returned
   HTTP 200 and the raw LaTeX unpacked normally. Likewise `2609.14527` (Ruler parallel) resolved.
9. **`koehler-2024-guided-eqsat` — the §3a "OA fetch" is the sketch paper, already stored.**
   Its OA-fetch column points at arXiv `2111.13040`, which is the *sketch* paper stored under
   `koehler-2021-sketch-eqsat`. The Guided Equality Saturation paper itself (DOI
   `10.1145/3632900`) was not obtained and is recorded link-only to avoid duplicating the sketch
   paper.
10. **Extra green-OA copies located via OpenAlex (beyond ACCESS.md).**
    CompCert (HAL), TACO/Exo/Halide (DSpace@MIT), Futhark (author site), Halide-learning
    (eScholarship), STOKE and Alive (author sites), and Ruler (arXiv) were fetched from sources
    `ACCESS.md` had recorded only as "author host / ACM 403" or "ACM 403". Conversely, some
    green-OA locations OpenAlex reports are not usable here: Edinburgh (403), Utrecht (no direct
    PDF), ETH (500), Chalmers (no PDF), ANU (503), eScholarship PDFs (require a browser User-Agent).
