# Sources access, reachability, and pins

Scope: this file is the reproducible access record for the first-principles optimization
source corpus (plan step `access`). It records what is reachable, how each host was probed,
the resolved identifier of every paper candidate, and the exact fetch commands the later
collection steps should run. No files are fetched by this file; it is documentation.

All probes and API lookups were run on **2026-09-26**.

---

## 1. Reachability matrix

Probe command used throughout (HTTP status of a `HEAD`-style `GET`, following redirects):

```bash
curl -s -o /dev/null -w "%{http_code}\n" -L --max-time 25 "<url>"
```

### Reachable (HTTP 200)

| Host | Status | What it serves | Notes |
| --- | --- | --- | --- |
| `arxiv.org` (`/abs/<id>`, `/e-print/<id>`) | 200 | Abstract pages and raw TeX/PDF source bundles | Primary paper source. Confirmed for all probed IDs. |
| `export.arxiv.org` (`/api/query`) | 200 | arXiv Atom API for ID/title resolution | Use `https`, not `http` (plain `http` returned empty). |
| `mlir.llvm.org/docs/` | 200 | Rendered MLIR docs | Rendered mirror of the `mlir/docs/**` tree. |
| `raw.githubusercontent.com` | 200 | Raw file tree at any commit/tag | Verified with `llvmorg-23.1.2/mlir/docs/Passes.md`. |
| `api.github.com` | 200 | GitHub REST API (commits, trees, releases) | Used for tree listing and commit SHAs. |
| `github.com` | 200 | Repos: tinygrad, MLton, LLVM, egg, egglog, HVM, Bend, dex-lang, futhark, Idris2 | `git ls-remote` also works. |
| `docs.tinygrad.org` | 200 | tinygrad docs | |
| `egraphs-good.github.io` | 200 | egg/egglog project site | |
| `gitlab.haskell.org` (`/-/wikis/commentary/compiler`) | 200 | GHC compiler commentary wiki | |
| `downloads.haskell.org` (`/ghc/latest/docs/users_guide/`) | 200 | GHC users guide | |
| `www.haskell.org/ghc/` | 200 | GHC landing/docs index | |
| `www.idris-lang.org`, `docs.idris-lang.org` | 200 | Idris 2 docs | |
| `okmij.org/ftp/` | 200 | Oleg Kiselyov's papers (e.g. supercompilation, staging) | Author host. |
| `www.cs.ox.ac.uk` | 200 | Oxford author/lab pages (e.g. Kovács, Orchard, Steuwer) | Author host. |
| `people.mpi-sws.org` | 200 | MPI-SWS author pages (e.g. Daan Leijen / Koka) | Author host. |
| `www.microsoft.com/en-us/research` | 200 | MSR author pages | Author host. |
| `link.springer.com` | 200 | Springer article landing pages | PDFs vary by OA status. |
| `openreview.net` | 200 | OpenReview | |
| `hal.science` | 200 | HAL open archive | |
| `www.semanticscholar.org` | 200 | Semantic Scholar site (web UI only) | |
| `api.openalex.org` | 200 | OpenAlex API | Preferred fallback for DOIs/authors/OA links. |
| `web.archive.org` | 200 | Wayback Machine | Fallback for dead hosts. |
| `iree.dev`, `docs.modular.com/mojo/`, `polygeist.pages.dev` | 200 | IREE, Mojo docs, Polygeist docs | |
| `leanprover.github.io` | 200 | Lean 4 docs site | |

### Blocked / absent, with chosen fallback

| Host | Status | Observed | Chosen fallback |
| --- | --- | --- | --- |
| `dl.acm.org` | 403 | ACM Digital Library blocks direct fetch (including PDF `oa_url`s OpenAlex returns). | Resolve the DOI via OpenAlex; store the *canonical DOI link* and, where a green-OA copy exists (author site, HAL, institutional repository), fetch that instead. Do not attempt to scrape `dl.acm.org`. |
| `mlton.org`, `www.mlton.org` | 000 (no connection) | MLton project site is dead. | Fetch MLton docs/source from the pinned GitHub mirror (`github.com/MLton/mlton`); use `web.archive.org` snapshots only for pages with no GitHub equivalent. |
| `research-repository.st-andrews.ac.uk` | 000 (no connection) | St Andrews repository unreachable (Tejiščák thesis, Brady thesis live here). | Mark those theses UNRESOLVED for this pass; the related peer-reviewed papers were resolved via DOI/OpenAlex instead. |
| `api.semanticscholar.org` | 429 | Graph API rate-limited. | Use OpenAlex (`api.openalex.org`) as the metadata/OA fallback. |

Fallback priority order for any unresolved paper: **arXiv API (by title) → OpenAlex by title → OpenAlex/DOI resolution → author/lab host → HAL/OpenReview → Wayback Machine**.

---

## 2. Pin table

Resolved on 2026-09-26.

| Component | Pin | Resolved SHA | Source of truth command |
| --- | --- | --- | --- |
| `third_party/Idris2` (git submodule) | pinned commit `1c630e67` | `1c630e67c386629a0fbbc6b78a59176fde7f0a76` | `git submodule status third_party/Idris2` |
| this repo `origin/main` HEAD | `main` | `e37040ac93c9ad244097868e16db482a02fd23ef` | `git ls-remote https://github.com/bjornpagen/idris-mlir.git refs/heads/main` |
| local working HEAD (matches origin/main) | `main` | `e37040ac93c9ad244097868e16db482a02fd23ef` | `git rev-parse HEAD` |
| `tinygrad/tinygrad` | `master` | `b1a9b35bdd89ed2ed3fa69e0786210fbd268b33a` | `git ls-remote https://github.com/tinygrad/tinygrad.git refs/heads/master` |
| `MLton/mlton` | `master` | `aa2fd1ad9b91375903a4253cfcf1ea5ef2754f37` | `git ls-remote https://github.com/MLton/mlton.git refs/heads/master` |
| `llvm/llvm-project` | tag `llvmorg-23.1.2` | `2d56740342c3bd86a7525fb4c147252757589e30` | `git ls-remote https://github.com/llvm/llvm-project.git refs/tags/llvmorg-23.1.2` |
| `egraphs-good/egg` | `main` | `2f31b28e3f9d78e02273b6c6d4201b5b0720b343` | `git ls-remote https://github.com/egraphs-good/egg refs/heads/main` |
| `egraphs-good/egglog` | `main` | `90635860397ce710f8c0a4eeb04154a8ebc3ac05` | `git ls-remote https://github.com/egraphs-good/egglog refs/heads/main` |
| `HigherOrderCO/HVM` | `master` | `7365a56cca56a5853c979755891cb86aa343c42d` | `git ls-remote https://github.com/HigherOrderCO/HVM refs/heads/master` |
| `HigherOrderCO/Bend` | `main` | `574b6d39a235b539eb19a5c532993a0abb3d11ad` | `git ls-remote https://github.com/HigherOrderCO/Bend refs/heads/main` |
| `google-research/dex-lang` | `main` | `25e2e389b90403ae2f8d67fb6d52f47d23c439ee` | `git ls-remote https://github.com/google-research/dex-lang refs/heads/main` |
| `diku-dk/futhark` | `master` | `304c56ff73c48f1842ed3971fe19805a3a85c766` | `git ls-remote https://github.com/diku-dk/futhark refs/heads/master` |

Note: the LLVM pin is a **tag**, not a branch; the resolved SHA
`2d56740342c3bd86a7525fb4c147252757589e30` is the commit the annotated tag dereferences to
for the archive tree. Raw fetches should use the tag name `llvmorg-23.1.2` (stable) or this SHA.

---

## 3. Resolved paper / source table

Legend — **status**: `resolved` (canonical ID or URL confirmed by API/DOI lookup),
`resolved-corrected` (plan's candidate ID/title/attribution was wrong; the corrected value is
given), `unresolved` (could not confirm; reason given). **OA fetch**: recommended raw-source
or PDF URL. Licenses for ACM/Springer items were **not** individually verified from the
publisher; treat `unknown–verify` as "confirm at collection time before redistributing".

### 3a. arXiv-confirmed papers

| Shortname | Title | Authors | Venue/Year | Canonical link | OA fetch (TeX) | License | Thread(s) | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `willsey-2021-egg` | egg: Fast and Extensible Equality Saturation | Willsey, Nandi, Wang, Flatt, Tatlock, Panchekha | POPL 2021 | https://arxiv.org/abs/2004.03082 | https://arxiv.org/e-print/2004.03082 | arXiv non-exclusive | B | resolved |
| `zhang-2023-egglog` | Better Together: Unifying Datalog and Equality Saturation | Zhang, Wang, Flatt, Cao, Zucker, Rosenthal, Tatlock, Willsey | PLDI 2023 | https://arxiv.org/abs/2304.04332 | https://arxiv.org/e-print/2304.04332 | arXiv non-exclusive | B | resolved |
| `zhang-2022-relational-ematching` | Relational E-Matching | Zhang, Wang, Willsey, Tatlock | POPL 2022 | https://arxiv.org/abs/2108.02290 | https://arxiv.org/e-print/2108.02290 | arXiv non-exclusive | B | resolved |
| `wang-2020-spores` | SPORES: Sum-Product Optimization via Relational Equality Saturation for Large Scale Linear Algebra | Wang, Hutchison, Leang, et al. | arXiv 2020 | https://arxiv.org/abs/2002.07951 | https://arxiv.org/e-print/2002.07951 | arXiv non-exclusive | B | resolved-corrected (plan's `2003.02423` is an unrelated physics paper) |
| `zheng-2020-ansor` | Ansor: Generating High-Performance Tensor Programs for Deep Learning | Zheng, Jia, Sun, Wu, Yu, Haj-Ali, Wang, Yang, Zhuo, Sen, Gonzalez, Stoica | OSDI 2020 | https://arxiv.org/abs/2006.06762 | https://arxiv.org/e-print/2006.06762 | arXiv non-exclusive | A, G | resolved |
| `yang-2021-tensat` | Equality Saturation for Tensor Graph Superoptimization | Yang, Phothilimthana, Wang, et al. | arXiv 2021 (PLDI 2021 Tensat) | https://arxiv.org/abs/2101.01332 | https://arxiv.org/e-print/2101.01332 | arXiv non-exclusive | A, B | resolved-corrected (plan's `2011.02043` is an unrelated mapping paper) |
| `kovacs-2022-staged` | Staged Compilation with Two-Level Type Theory | András Kovács | ICFP 2022 | https://arxiv.org/abs/2209.09729 | https://arxiv.org/e-print/2209.09729 | arXiv non-exclusive | C | resolved-corrected (plan's `2204.05653` is Kudasov's "Free Monads…") |
| `koehler-2024-guided-eqsat` | Guided Equality Saturation | Koehler, Goens, Bhat, Grosser, Trinder, Steuwer | POPL 2024 | https://doi.org/10.1145/3632900 | https://arxiv.org/e-print/2111.13040 (related sketch paper; see below) | ACM © unknown–verify | B | resolved-corrected (plan's candidate `2306.07214` is an X-ray astronomy paper) |
| `koehler-2021-sketch-eqsat` | Sketch-Guided Equality Saturation: Scaling Equality Saturation to Complex Optimizations of Functional Programs | Koehler, Trinder, Steuwer | OOPSLA 2021 | https://arxiv.org/abs/2111.13040 | https://arxiv.org/e-print/2111.13040 | arXiv non-exclusive | B | resolved (this is the plan's "sketch-guided equality saturation, ID to confirm") |
| `ullrich-2019-counting-immutable-beans` | Counting Immutable Beans: Reference Counting Optimized for Purely Functional Programming | Ullrich, de Moura | IFL 2019 | https://arxiv.org/abs/1908.05647 | https://arxiv.org/e-print/1908.05647 | arXiv non-exclusive | D | resolved |
| `bernardy-2018-linear-haskell` | Linear Haskell: practical linearity in a higher-order polymorphic language | Bernardy, Boespflug, Newton, Peyton Jones, Spiwack | POPL 2018 | https://arxiv.org/abs/1710.09756 (DOI 10.1145/3158093) | https://arxiv.org/e-print/1710.09756 | arXiv non-exclusive | D | resolved |
| `brady-2021-idris2-qtt` | Idris 2: Quantitative Type Theory in Practice | Edwin Brady | ECOOP 2021 | https://arxiv.org/abs/2104.00480 | https://arxiv.org/e-print/2104.00480 | arXiv non-exclusive | E | resolved |
| `lattner-2020-mlir` | MLIR: A Compiler Infrastructure for the End of Moore's Law | Lattner, Amini, Bondhugula, Cohen, Davis, Pienaar, Riddle, Shpeisman, Vasilache, Zinenko | arXiv 2020 | https://arxiv.org/abs/2002.11054 | https://arxiv.org/e-print/2002.11054 | arXiv non-exclusive | F | resolved |
| `bhat-2022-lambda-ultimate-ssa` | Lambda the Ultimate SSA: Optimizing Functional Programs in SSA | Bhat, Grosser | CGO 2022 | https://arxiv.org/abs/2201.07272 (DOI 10.1109/CGO53902.2022.9741279) | https://arxiv.org/e-print/2201.07272 | arXiv non-exclusive | F, I | resolved |
| `sasnauskas-2017-souper` | Souper: A Synthesizing Superoptimizer | Sasnauskas, Chen, Collingbourne, Ketema, Lup, Taneja, Regehr | arXiv 2017 | https://arxiv.org/abs/1711.04422 | https://arxiv.org/e-print/1711.04422 | arXiv non-exclusive | H | resolved |
| `lucke-2024-transform-dialect` | The MLIR Transform Dialect. Your compiler is more powerful than you think | Lücke, Zinenko, Moses | arXiv 2024 (CGO 2025-adjacent) | https://arxiv.org/abs/2409.03864 | https://arxiv.org/e-print/2409.03864 | arXiv non-exclusive | F | resolved (plan's "Transform Dialect (CGO 2025), ID to confirm") |
| `shivers-2019-remora` | Introduction to Rank-polymorphic Programming in Remora (Draft) | Shivers, Slepak, Manolios | arXiv 2019 | https://arxiv.org/abs/1912.13451 | https://arxiv.org/e-print/1912.13451 | arXiv non-exclusive | G | resolved (plan's "Remora, ID to confirm") |
| `mendis-2019-ithemal` | Ithemal: Accurate, Portable and Fast Basic Block Throughput Estimation using Deep Neural Networks | Mendis, Renda, Amarasinghe, Carbin | ICML 2019 | https://arxiv.org/abs/1808.07412 | https://arxiv.org/e-print/1808.07412 | arXiv non-exclusive | H | resolved |
| `wu-2026-slotted-egraphs` | Typed Flexible-Arity Slotted E-Graphs: A Soundness Construction and an Alloy Case Study | Wu, Sullivan | arXiv 2026 | https://arxiv.org/abs/2609.03998 | https://arxiv.org/e-print/2609.03998 | arXiv non-exclusive | B | resolved (matches plan's "slotted e-graphs / binders, ID to confirm"; ID is future-dated — verify at fetch time) |

### 3b. Non-arXiv papers resolved by DOI (via OpenAlex)

| Shortname | Title | Authors | Venue/Year | Canonical DOI | OA fetch | License | Thread(s) | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `chen-2018-tvm` | TVM: An Automated End-to-End Optimizing Compiler for Deep Learning | Chen et al. | OSDI 2018 | https://doi.org/10.5555/3291168.3291211 | https://arxiv.org/e-print/1802.04799 (arXiv version) | arXiv non-exclusive (preprint) | A, G | resolved |
| `jia-2019-taso` | TASO: optimizing deep learning computation with automatic generation of graph substitutions | Jia, Padon, Thomas, Warszawski, Zaharia, Aiken | SOSP 2019 | https://doi.org/10.1145/3341301.3359630 | (ACM 403) — resolve green OA at collection time | ACM © unknown–verify | A | resolved |
| `reinking-2021-perceus` | Perceus: garbage free reference counting with reuse | Reinking, Xie, de Moura, Leijen | PLDI 2021 | https://doi.org/10.1145/3453483.3454032 | (ACM 403) — Koka repo docs may mirror | ACM © unknown–verify | D | resolved-corrected (plan's `2004.02812` is a math paper) |
| `pal-2023-ruler` | Equality Saturation Theory Exploration à la Carte (tool: **Ruler**) | Pal, Saiki, Tjoa, Richey, Zhu, Flatt, et al. | OOPSLA 2023 | https://doi.org/10.1145/3622834 | (ACM 403) | ACM © unknown–verify | B | resolved-corrected (published title differs from plan's "Ruler"; tool is Ruler) |
| `kovacs-2024-closure-free` | Closure-Free Functional Programming in a Two-Level Type Theory | András Kovács | ICFP 2024 | https://doi.org/10.1145/3674648 | (ACM 403) | ACM © unknown–verify | C | resolved |
| `lorenzen-2024-oxidizing-ocaml` | Oxidizing OCaml with Modal Memory Management | Lorenzen, White, Dolan, Eisenberg, Lindley | ICFP 2024 | https://doi.org/10.1145/3674642 | (ACM 403) | ACM © unknown–verify | D | resolved |
| `lorenzen-2023-fp2` | FP²: Fully in-Place Functional Programming | Lorenzen, Leijen, Swierstra | ICFP 2023 | https://doi.org/10.1145/3607840 | (ACM 403) | ACM © unknown–verify | D | resolved |
| `lorenzen-2022-frame-limited-reuse` | Reference counting with frame limited reuse | Lorenzen, Leijen | ICFP 2022 | https://doi.org/10.1145/3547634 | (ACM 403) | ACM © unknown–verify | D | resolved |
| `fehr-2022-irdl` | IRDL: an IR definition language for SSA compilers | Fehr, Niu, Riddle, Amini, Su, Grosser | PLDI 2022 | https://doi.org/10.1145/3519939.3523700 | (ACM 403) | ACM © unknown–verify | F | resolved |
| `bhat-2024-verifying-peephole` | Verifying Peephole Rewriting in SSA Compiler IRs | Bhat, Keizer, Hughes, Goens, Grosser | ITP 2024 | https://doi.org/10.4230/LIPIcs.ITP.2024.9 | https://drops.dagstuhl.de/ (LIPIcs OA) | CC-BY (LIPIcs default) | F, I | resolved-corrected (OpenAlex mislinks this DOI to a Vasilache MLIR-2 paper; title verified from search + LIPIcs) |
| `mitchell-2010-rethinking-supercompilation` | Rethinking supercompilation | Neil Mitchell | ICFP 2010 | https://doi.org/10.1145/1863543.1863588 | author host / ACM 403 | ACM © unknown–verify | C | resolved |
| `bolingbroke-2010-supercompilation-by-eval` | Supercompilation by evaluation | Bolingbroke, Peyton Jones | Haskell 2010 | https://doi.org/10.1145/1863523.1863540 | author host / ACM 403 | ACM © unknown–verify | C | resolved |
| `panchekha-2015-herbie` | Automatically improving accuracy for floating point expressions (Herbie) | Panchekha, Sanchez-Stern, Wilcox, Tatlock | POPL 2015 | https://doi.org/10.1145/2737924.2737959 | author host / ACM 403 | ACM © unknown–verify | B | resolved |
| `schkufza-2013-stoke` | Stochastic superoptimization | Schkufza, Sharma, Aiken | ASPLOS 2013 | https://doi.org/10.1145/2451116.2451150 | author host / ACM 403 | ACM © unknown–verify | H | resolved |
| `lopes-2021-alive2` | Alive2: bounded translation validation for LLVM | Lopes, Lee, Hur, Liu, Regehr | PLDI 2021 | https://doi.org/10.1145/3453483.3454030 | author host / ACM 403 | ACM © unknown–verify | I | resolved |
| `lopes-2015-alive` | Provably correct peephole optimizations with Alive | Lopes, Menendez, Nagarakatte, Regehr | PLDI 2015 | https://doi.org/10.1145/2737924.2737965 | author host / ACM 403 | ACM © unknown–verify | I | resolved |
| `leroy-2009-compcert` | Formal verification of a realistic compiler (CompCert) | Xavier Leroy | CACM 2009 | https://doi.org/10.1145/1538788.1538814 | author host / ACM 403 | ACM © unknown–verify | I | resolved |
| `marlow-2006-fast-curry` | Making a fast curry: push/enter vs. eval/apply for higher-order languages | Marlow, Peyton Jones | JFP 2006 (ICFP 2004) | https://doi.org/10.1017/S0956796806005995 | Cambridge OA PDF (verified 200) | CUP © unknown–verify | D | resolved |
| `peytonjones-1992-stg` | Implementing lazy functional languages on stock hardware: the Spineless Tagless G-machine | Simon Peyton Jones | JFP 1992 | https://doi.org/10.1017/S0956796800000319 | Cambridge OA PDF (verified 200) | CUP © unknown–verify | D | resolved |
| `brady-2004-inductive-families` | Inductive Families Need Not Store Their Indices | Brady, McBride, McKinna | TYPES 2003 | https://doi.org/10.1007/978-3-540-24849-1_8 | Springer landing | Springer © unknown–verify | E | resolved |
| `lee-2001-size-change` | The size-change principle for program termination | Lee, Jones, Ben-Amram | POPL 2001 | https://doi.org/10.1145/360204.360210 | ACM 403 | ACM © unknown–verify | E | resolved |
| `rondon-2008-liquid-types` | Liquid types | Rondon, Kawaguchi, Jhala | PLDI 2008 | https://doi.org/10.1145/1375581.1375602 | ACM 403 | ACM © unknown–verify | E | resolved |
| `danvy-2001-defunctionalization` | Defunctionalization at work | Danvy, Nielsen | PPDP 2001 | https://doi.org/10.1145/773184.773202 | BRICS report https://doi.org/10.7146/brics.v8i23.21684 | BRICS OA | Cross-cutting | resolved |
| `wurthinger-2017-practical-partial-eval` | Practical partial evaluation for high-performance dynamic language runtimes | Würthinger, Wimmer, Humer, Wöß, Stadler, Seaton | PLDI 2017 | https://doi.org/10.1145/3062341.3062381 | author host / ACM 403 | ACM © unknown–verify | C | resolved |
| `wurthinger-2013-one-vm` | One VM to rule them all | Würthinger, Wimmer, Wöß, Stadler, Duboscq, Humer | Onward! 2013 | https://doi.org/10.1145/2509578.2509581 | author host / ACM 403 | ACM © unknown–verify | C | resolved |
| `teiiscak-2020-erasure-calculus` | A dependently typed calculus with pattern matching and erasure inference | Matúš Tejiščák | ICFP 2020 | https://doi.org/10.1145/3408973 | (ACM 403) | ACM © unknown–verify | E | resolved |
| `chataing-2024-unboxed-data-constructors` | Unboxed Data Constructors: Or, How cpp Decides a Halting Problem | Chataing, Dolan, Scherer, Yallop | POPL 2024 | https://doi.org/10.1145/3632893 | (ACM 403) | ACM © unknown–verify | E | resolved-corrected (plan said "Alexis King, ICFP 2024"; actual authors/venue as shown) |
| `marshall-2022-linearity-uniqueness` | Linearity and Uniqueness: An Entente Cordiale | Marshall, Vollmer, Orchard | ESOP 2022 | https://doi.org/10.1007/978-3-030-99336-8_13 | Springer OA PDF (verified 200) | Springer OA (verify CC-BY) | D | resolved |
| `taha-2000-metaml` | MetaML and multi-stage programming with explicit annotations | Taha, Sheard | TCS 2000 | https://doi.org/10.1016/S0304-3975(00)00053-0 | ScienceDirect PDF (verified 200) | Elsevier © unknown–verify | C | resolved |
| `christiansen-2016-elaborator-reflection` | Elaborator reflection: extending Idris in Idris | Christiansen, Brady | ICFP 2016 | https://doi.org/10.1145/2951913.2951932 | ACM 403 | ACM © unknown–verify | C | resolved |
| `wadler-1990-deforestation` | Deforestation: transforming programs to eliminate trees | Philip Wadler | TCS 1990 | https://doi.org/10.1016/0304-3975(90)90147-A | ScienceDirect PDF (verified 200) | Elsevier © unknown–verify | C | resolved |
| `gill-1993-short-cut` | A short cut to deforestation | Gill, Launchbury, Peyton Jones | FPCA 1993 | https://doi.org/10.1145/165180.165214 | ACM 403 | ACM © unknown–verify | C | resolved |
| `coutts-2007-stream-fusion` | Stream fusion: from lists to streams to nothing at all | Coutts, Leshchinskiy, Stewart | ICFP 2007 | https://doi.org/10.1145/1291151.1291199 | ACM 403 | ACM © unknown–verify | C | resolved |
| `henriksen-2017-futhark` | Futhark: purely functional GPU-programming with nested parallelism and in-place array updates | Henriksen, Serup, Elsman, Henglein, Oancea | PLDI 2017 | https://doi.org/10.1145/3062341.3062354 | ACM 403 | ACM © unknown–verify | G | resolved |
| `ragankelley-2013-halide` | Halide: a language and compiler for optimizing parallelism, locality, and recomputation in image processing pipelines | Ragan-Kelley, Barnes, Adams, Paris, Durand, Amarasinghe | PLDI 2013 | https://doi.org/10.1145/2499370.2462176 | MIT DSpace OA | MIT OA | G | resolved |
| `mullapudi-2016-halide-autosched` | Automatically scheduling halide image processing pipelines | Mullapudi, Adams, Sharlet, Ragan-Kelley, Fatahalian | SIGGRAPH 2016 | https://doi.org/10.1145/2897824.2925952 | ACM 403 | ACM © unknown–verify | G | resolved |
| `adams-2019-halide-learning` | Learning to optimize halide with tree search and random programs | Adams, Ma, Anderson, Baghdadi, Li, et al. | SIGGRAPH 2019 | https://doi.org/10.1145/3306346.3322967 | ACM 403 | ACM © unknown–verify | G | resolved |
| `ikarashi-2022-exo` | Exocompilation for productive programming of hardware accelerators | Ikarashi, Bernstein, Reinking, Genc, et al. | PLDI 2022 | https://doi.org/10.1145/3519939.3523446 | (ACM 403) | ACM © unknown–verify | G | resolved-corrected (plan said ASPLOS 2021) |
| `kjolstad-2017-taco` | The tensor algebra compiler | Kjølstad, Kamil, Chou, Lugato, et al. | OOPSLA 2017 | https://doi.org/10.1145/3133901 | author host / ACM 403 | ACM © unknown–verify | G | resolved |
| `massalin-1987-superoptimizer` | Superoptimizer: a look at the smallest program | Henry Massalin | ASPLOS 1987 | https://doi.org/10.1145/36206.36194 | ACM 403 | ACM © unknown–verify | H | resolved |
| `bansal-2006-peephole-superoptimizer` | Automatic generation of peephole superoptimizers | Bansal, Aiken | ASPLOS 2006 | https://doi.org/10.1145/1168918.1168906 | ACM 403 | ACM © unknown–verify | H | resolved |
| `joshi-2002-denali` | Denali: A Goal-directed Superoptimizer | Joshi, Nelson, Randall | PLDI 2002 | https://doi.org/10.1145/512529.512566 | ACM 403 | ACM © unknown–verify | H | resolved |
| `pnueli-1998-translation-validation` | Translation validation | Pnueli, Siegel, Singerman | TACAS 1998 | https://doi.org/10.1007/BFb0054170 | Springer landing | Springer © unknown–verify | I | resolved |
| `lafont-1990-interaction-nets` | Interaction nets | Yves Lafont | POPL 1990 | https://doi.org/10.1145/96709.96718 | ACM 403 | ACM © unknown–verify | J | resolved |
| `lamping-1990-optimal-reduction` | An algorithm for optimal lambda calculus reduction | John Lamping | POPL 1990 | https://doi.org/10.1145/96709.96711 | ACM 403 | ACM © unknown–verify | J | resolved |
| `reynolds-1972-definitional-interpreters` | Definitional interpreters for higher-order programming languages | John C. Reynolds | ACM 1972 | https://doi.org/10.1145/800194.805852 | ACM 403 | ACM © unknown–verify | Cross-cutting | resolved |
| `turchin-1986-supercompiler` | The concept of a supercompiler | Valentin F. Turchin | TOPLAS 1986 | https://doi.org/10.1145/5956.5957 | ACM 403 | ACM © unknown–verify | C | resolved |
| `sorensen-1996-positive-supercompiler` | A positive supercompiler | Sørensen, Glück, Jones | JFP 1996 | https://doi.org/10.1017/S0956796800002008 | Cambridge OA PDF (verify) | CUP © unknown–verify | C | resolved |
| `taha-2004-gentle-intro-multistage` | A Gentle Introduction to Multi-stage Programming | Walid Taha | 2004 | https://doi.org/10.1007/978-3-540-25935-0_3 | Springer landing | Springer © unknown–verify | C | resolved |
| `rompf-2010-lms` | Lightweight modular staging: a pragmatic approach to runtime code generation and compiled DSLs | Rompf, Odersky | GPCE 2010 | https://doi.org/10.1145/1868294.1868314 | author host / ACM 403 | ACM © unknown–verify | C | resolved |
| `leijen-2017-koka-effects` | Type directed compilation of row-typed algebraic effects | Daan Leijen | POPL 2017 | https://doi.org/10.1145/3009837.3009872 | author host / ACM 403 | ACM © unknown–verify | D | resolved |
| `blackburn-2008-immix` | Immix: a mark-region garbage collector with space efficiency, fast collection, and mutator performance | Blackburn, McKinley | ISMM 2008 | https://doi.org/10.1145/1375581.1375586 | ACM 403 | ACM © unknown–verify | D | resolved |

### 3c. Unresolved (recorded with reason)

| Plan item | Thread(s) | Reason |
| --- | --- | --- |
| "fractional uniqueness" (OOPSLA 2024) | D | No matching title found via arXiv or OpenAlex title search. Resolve at collection time (possibly a different published title; try author Orchard/Marshall/Vollmer). |
| Brady PhD thesis (2013) | E | Hosted at `research-repository.st-andrews.ac.uk`, which is unreachable (000). |
| Christiansen PhD thesis | C | No stable OA URL located; likely author-hosted. Resolve at collection time. |
| Maranget, "Compiling Pattern Matching to Good Decision Trees" (ML 2008) | E | DOI not verified via OpenAlex title search. Verify via DOI lookup. |
| Wadler, pattern-matching compilation (1987) | E | No DOI confirmed; likely in a conference proceedings not indexed. |
| Abel, "foetus" termination checker | E | No DOI; technical report. Resolve via author host. |
| Wadler, linear types papers ("Linear Types Can Change the World", 1990) | D | No DOI confirmed (IFIP proceedings). Resolve via author host. |
| "Secrets of the GHC inliner" (Peyton Jones & Marlow, JFP 2002) | Cross-cutting | Candidate DOI `10.1017/S0956796801004270` resolves to an unrelated paper. Resolve at collection time. |
| warm fusion; shortcut fusion | C | No specific canonical paper selected in the plan; confirm the intended references. |
| Futamura, "Partial evaluation of computation process" (1971) | C | Classic journal article with no DOI/OA copy located. |
| Garbage Collection Handbook | D | Book; no OA. Store as pointer only. |
| Boehm GC; "precise tracing GC" | D | Tech report / project pages; no single canonical paper in plan. Store pointers. |
| Destination-passing style | D | No specific canonical reference selected. |
| MLIR (CGO 2021) | F | Second MLIR paper; DOI not verified this pass. Resolve via OpenAlex/DOI at collection time. |
| Hovgaard et al., defunctionalisation (TFP 2018) | G | DOI not verified. Resolve via author host / Futhark site. |
| Henriksen PhD thesis | G | No OA URL located; likely `futhark-lang.org` / diku. Resolve at collection time. |
| SaC | G | No specific canonical reference selected. |
| MLGO / CompilerGym; autotuning and beam-search surveys | H | No specific canonical references selected. Resolve at collection time. |
| CertiCoq papers; "Certified Compilation of Coq" | I | No DOI verified. Resolve via author/lab host. |
| Lafont, Interaction Combinators (1997) | J | No DOI verified. Resolve via author host. |
| Inpla / inets | J | No specific canonical reference selected. |
| SSA-based Compiler Design (book) | F | Free PDF; store as pointer (chapter-level PDFs at collection time). |
| Jones/Gomard/Sestoft, Partial Evaluation and Automatic Program Generation (book) | C | Free PDF; author-hosted. Store as pointer / fetch PDF. |
| GMP manual; Modern Computer Arithmetic (book); Idris Integer/String | Cross-cutting | Docs/books; store as docs/pointers. |
| Koka effect types (additional papers) | D | Only Leijen POPL 2017 resolved; other Koka material is docs/code. |
| "e-graph extraction (ILP/MaxSAT) work" | B | Plan gives no author/title; leave as a collection-time literature probe. |
| 2024–2026 POPL/PLDI/ICFP/OOPSLA/CGO + arXiv cs.PL sweep | J, Cross-cutting | Cannot be pre-enumerated; run as a live sweep in the `papers-other` step and record demonstrated-vs-claimed. |

### 3d. Non-paper source URLs

| Source | Canonical base URL | Pin |
| --- | --- | --- |
| MLIR docs | https://mlir.llvm.org/docs/ | rendered; canonical tree `mlir/docs/**` |
| LLVM/MLIR raw tree | https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-23.1.2/ | tag `llvmorg-23.1.2` (= `2d567403…`) |
| LLVM/MLIR GitHub tree API | https://api.github.com/repos/llvm/llvm-project/git/trees/llvmorg-23.1.2?recursive=1 | tag |
| Idris 2 docs | https://raw.githubusercontent.com/idris-lang/Idris2/1c630e67c386629a0fbbc6b78a59176fde7f0a76/docs/source/ | submodule pin |
| GHC commentary wiki | https://gitlab.haskell.org/ghc/ghc/-/wikis/commentary/compiler | live wiki |
| GHC users guide | https://downloads.haskell.org/ghc/latest/docs/users_guide/ | `latest` |
| MLton guide | https://raw.githubusercontent.com/MLton/mlton/aa2fd1ad9b91375903a4253cfcf1ea5ef2754f37/doc/guide/src/ | `master` patch pin |
| MLton site fallback | https://web.archive.org/web/2023/https://mlton.org/ | Wayback |
| tinygrad docs | https://docs.tinygrad.org/ | live |
| tinygrad repo/README | https://raw.githubusercontent.com/tinygrad/tinygrad/b1a9b35bdd89ed2ed3fa69e0786210fbd268b33a/ | `master` pin |
| egg repo | https://github.com/egraphs-good/egg | `2f31b28e…` |
| egglog repo | https://github.com/egraphs-good/egglog | `90635860…` |
| HVM2 repo | https://github.com/HigherOrderCO/HVM | `7365a56c…` |
| Bend repo | https://github.com/HigherOrderCO/Bend | `574b6d39…` |
| dex-lang repo | https://github.com/google-research/dex-lang | `25e2e389…` |
| Futhark repo | https://github.com/diku-dk/futhark | `304c56ff…` |

---

## 4. Exact fetch commands (reproducible)

These are documented commands for the later collection steps. They are **not** a script to
execute in this pass. All commands are read-only fetches; nothing here builds or runs repo
code.

### 4.1 arXiv API: resolve an ID or a title

```bash
# Confirm an ID (prints title/authors/date/journal-ref/doi)
curl -s "https://export.arxiv.org/api/query?id_list=2004.03082" \
  | python3 -c "import sys,xml.etree.ElementTree as ET; ns={'a':'http://www.w3.org/2005/Atom'}; [print(e.find('a:id',ns).text, '|', ' '.join(e.find('a:title',ns).text.split())) for e in ET.fromstring(sys.stdin.read()).findall('a:entry',ns)]"

# Resolve an uncertain ID by title
curl -sG "https://export.arxiv.org/api/query" \
  --data-urlencode 'search_query=ti:"Staged Compilation with Two-Level Type Theory"' \
  --data-urlencode 'max_results=3'
```

### 4.2 arXiv `e-print` fetch + unpack (preferred paper form)

```bash
id=2004.03082
shortname=willsey-2021-egg
dest="docs/research/papers/${shortname}"
mkdir -p "$dest"
curl -L --fail -o "/tmp/${id}.src" "https://arxiv.org/e-print/${id}"
file "/tmp/${id}.src"                      # detect: gzip, tar, or single .tex
# Case A: gzip-compressed tar (most common)
tar -xzf "/tmp/${id}.src" -C "$dest"
# Case B: plain gzip (single file)
#   gunzip -c "/tmp/${id}.src" > "$dest/main.tex"
# Case C: uncompressed tar
#   tar -xf "/tmp/${id}.src" -C "$dest"
# Then remove generated files and enforce size:
find "$dest" -name '*.aux' -delete; find "$dest" -name '*.log' -delete
du -sh "$dest"                             # must be < 20 MB
```

### 4.3 OpenAlex fallback (by title, then by DOI)

```bash
# Title search
curl -sG "https://api.openalex.org/works" \
  --data-urlencode "search=Perceus garbage free reference counting with reuse" \
  --data-urlencode "per-page=3" --data-urlencode "mailto=research@example.org"

# Batch DOI resolution (authors, year, venue, OA URL)
curl -sG "https://api.openalex.org/works" \
  --data-urlencode "filter=doi:10.1145/3453483.3454032|10.1145/3632900" \
  --data-urlencode "per-page=50" --data-urlencode "mailto=research@example.org"
```

### 4.4 LLVM / MLIR raw fetch at the pinned tag

```bash
tag=llvmorg-23.1.2
base="https://raw.githubusercontent.com/llvm/llvm-project/${tag}"

# Single file
curl -L --fail -o /tmp/PatternMatch.h "${base}/mlir/include/mlir/IR/PatternMatch.h"

# Full tree listing (to enumerate mlir/docs/**), then fetch each path
curl -s "https://api.github.com/repos/llvm/llvm-project/git/trees/${tag}?recursive=1" \
  > /tmp/llvm-tree.json
```

### 4.5 Idris 2 raw fetch at the submodule pin

```bash
pin=1c630e67c386629a0fbbc6b78a59176fde7f0a76
base="https://raw.githubusercontent.com/idris-lang/Idris2/${pin}"
curl -L --fail -o /tmp/TT.idr "${base}/src/Core/TT.idr"
```

### 4.6 GHC commentary wiki + users guide

```bash
curl -L --fail -o /tmp/ghc-commentary.html \
  "https://gitlab.haskell.org/ghc/ghc/-/wikis/commentary/compiler"
curl -L --fail -o /tmp/ghc-users-guide.html \
  "https://downloads.haskell.org/ghc/latest/docs/users_guide/index.html"
```

### 4.7 MLton docs/source (GitHub mirror) and dead-site fallback

```bash
mltonpin=aa2fd1ad9b91375903a4253cfcf1ea5ef2754f37
curl -L --fail -o /tmp/CompilerOverview.adoc \
  "https://raw.githubusercontent.com/MLton/mlton/${mltonpin}/doc/guide/src/CompilerOverview.adoc"

# If a legacy mlton.org page is needed and GitHub has no equivalent:
curl -L --fail -o /tmp/mlton-legacy.html \
  "https://web.archive.org/web/2023/https://mlton.org/<path>"
```

### 4.8 tinygrad docs/README at the pinned commit

```bash
tpin=b1a9b35bdd89ed2ed3fa69e0786210fbd268b33a
curl -L --fail -o /tmp/tinygrad-README.md \
  "https://raw.githubusercontent.com/tinygrad/tinygrad/${tpin}/README.md"
curl -L --fail "https://docs.tinygrad.org/" -o /tmp/tinygrad-docs-index.html
```

### 4.9 Pinned-repo SHAs (re-verify before vendoring)

```bash
git ls-remote https://github.com/egraphs-good/egg refs/heads/main
git ls-remote https://github.com/egraphs-good/egglog refs/heads/main
git ls-remote https://github.com/HigherOrderCO/HVM refs/heads/master
git ls-remote https://github.com/HigherOrderCO/Bend refs/heads/main
git ls-remote https://github.com/google-research/dex-lang refs/heads/main
git ls-remote https://github.com/diku-dk/futhark refs/heads/master
```
