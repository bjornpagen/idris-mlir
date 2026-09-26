# Open-access locations for the papers corpus

Scope: this file is the OA-acquisition record for the `papers` source corpus. It covers the
targets that `ACCESS.md` listed as **DOI-only** (its §3b table, i.e. no ready OA fetch URL) and
the rows marked **UNRESOLVED** (its §3c table), plus the defunctionalization rows that were
unresolved in the cross-cutting section of `MANIFEST.md`. It records, per target, whether an
authorized open-access copy was found, the best direct URL, host/version/license, and which
API or site surfaced it.

- **Pass run:** 2026-09-26
- **Discovery APIs:** Unpaywall (`/v2/<doi>`), OpenAlex (`/works/doi:<doi>`, `/works?search=`,
  `locations`), Crossref (title resolution only, for DOIs OpenAlex could not find), arXiv `e-print`
  (TeX source) and arXiv Atom API, and publisher/author/lab pages.
- **Downloaded to:** `docs/research/sources/oa-papers/<shortname>/` (per-folder `README.md`).
- **Not attempted:** Sci-Hub, Library Genesis, or any paywall-bypassing / pirate mirror. `dl.acm.org`
  was never scraped; its 403 is recorded as an access barrier, not bypassed. HAL's bot
  challenge (Anubis) was not solved/evaded.
- **Cap:** 20 MB per file; nothing downloaded exceeded it.

## Result summary

- **Targets processed:** 80 rows — 51 DOI-only rows (`ACCESS.md` §3b), 27 UNRESOLVED rows (§3c),
  and 2 defunctionalization rows unresolved in `MANIFEST.md` cross-cutting (`cejtin-2000`,
  `huang-yallop-2023`).
- **OA copies found and downloaded:** **32** (`docs/research/sources/oa-papers/`).
  - **Stored as TeX/source: 1** — `pal-2023-ruler` (arXiv `e-print`, unpacked LaTeX in `src/`).
  - **Stored as PDF: 30.**
  - **Stored as PostScript: 1** — `wadler-linear-types` (`linear.ps`; the author hosts only PS).
- **OA located but not fetchable from this host (blocked/403 or unreachable):** 8
  (`lorenzen-2024`, `teiiscak-2020`, `christiansen-2016`, `taha-2000`, `wadler-1990`,
  `gill-1993`, `lorenzen-2022`, `lafont-1997`; also `massalin-1987`, `lamping-1990`,
  `turchin-1986`, `certicoq` — all publisher gold/bronze at `dl.acm.org` 403).
- **No OA copy found (closed, needs a subscription/author):** the remainder in the tables below.
- **Unresolved rows resolved to a concrete DOI (even where the paper stayed inaccessible):**
  `fractional-uniqueness`, `maranget-2008`, `wadler-linear-types`, `hovgaard-2018`,
  `huang-yallop-2023`, `secrets-ghc-inliner`, `mlir-cgo-2021`, `cejtin-2000`,
  `lafont-1997`, `certicoq`.
- **Unauthorized-mirror check:** none were used. The only borderline hits were **CiteSeerX
  metadata stubs** for some closed ACM papers (e.g. `bolingbroke-2010` 10.1.1.173.1355/5410,
  `reynolds-1972` 10.1.1.110.5892, `lamping-1990` 10.1.1.90.2386, `turchin-1986`
  10.1.1.128.6414). CiteSeerX is a legitimate academic search engine, but these were
  metadata/deposit stubs with no direct authorized PDF; they were **not** downloaded. No
  Sci-Hub/LibGen/pirate copy was ever opened.

---

## 1. DOI-only targets (`ACCESS.md` §3b) — 51 rows

`OA found`: **yes** = authorized copy downloaded to `oa-papers/`; **blocked** = authorized OA
exists but the only host returned 403/unreachable; **no** = closed, no authorized OA located.
`Source` names the API/site that surfaced the copy (Unpaywall / OpenAlex / Crossref / author or
lab site).

| Shortname | Title | DOI | OA found | Best direct URL | Host | Version | License | Source | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `jia-2019-taso` | TASO: optimizing DL computation with graph substitutions | 10.1145/3341301.3359630 | yes | https://cs.stanford.edu/~aiken/publications/papers/sosp19.pdf | author (Aiken, Stanford) | published | ACM © (not stated) | Unpaywall (gold @ACM 403) → author site | downloaded PDF |
| `reinking-2021-perceus` | Perceus: garbage free reference counting with reuse | 10.1145/3453483.3454032 | yes | https://www.microsoft.com/en-us/research/wp-content/uploads/2020/11/perceus-tr-v4.pdf | author (MSR) | TR/submitted | not stated (ACM CC-BY) | Unpaywall (gold @ACM 403) → MSR | downloaded PDF |
| `pal-2023-ruler` | Equality Saturation Theory Exploration à la Carte | 10.1145/3622834 | yes | https://arxiv.org/e-print/2609.14527 | arXiv (Cornell) | submitted (preprint) | arXiv non-exclusive | OpenAlex (Cornell location) | downloaded **TeX** |
| `kovacs-2024-closure-free` | Closure-Free Functional Programming in 2LTT | 10.1145/3674648 | yes | https://andraskovacs.github.io/pdfs/2ltt_icfp24.pdf | author (Kovács) | published | CC-BY (ACM) | Unpaywall (gold) → author site | downloaded PDF |
| `lorenzen-2024-oxidizing-ocaml` | Oxidizing OCaml with Modal Memory Management | 10.1145/3674642 | blocked | https://www.research.ed.ac.uk/files/475247237/LorenzenEtalPACMPL2024OxidizingOCamlWith.pdf | repository (Univ. of Edinburgh) | submitted | CC-BY | Unpaywall / OpenAlex | **not downloaded** (HTTP 403) |
| `lorenzen-2023-fp2` | FP²: Fully in-Place Functional Programming | 10.1145/3607840 | yes | https://dspace.library.uu.nl/server/api/core/bitstreams/41a50ebd-bca0-404a-82de-b07b99327900/content | repository (Utrecht) | submitted | other-oa | Unpaywall | downloaded PDF |
| `lorenzen-2022-frame-limited-reuse` | Reference counting with frame limited reuse | 10.1145/3547634 | blocked | https://dl.acm.org/doi/pdf/10.1145/3547634 | publisher (ACM gold) | published | CC-BY | Unpaywall | **not downloaded** (dl.acm.org 403) |
| `fehr-2022-irdl` | IRDL: an IR definition language for SSA compilers | 10.1145/3519939.3523700 | yes | https://www.research-collection.ethz.ch/server/api/core/bitstreams/793d56b8-3568-4df1-b0ec-1a087c26ce69/content | repository (ETH Zurich) | submitted | CC-BY-ND | Unpaywall | downloaded PDF |
| `bhat-2024-verifying-peephole` | Verifying Peephole Rewriting in SSA Compiler IRs | 10.4230/LIPIcs.ITP.2024.9 | yes | https://drops.dagstuhl.de/storage/00lipics/lipics-vol309-itp2024/LIPIcs.ITP.2024.9/LIPIcs.ITP.2024.9.pdf | publisher (Schloss Dagstuhl / LIPIcs) | published | CC-BY | OpenAlex (Dagstuhl) | downloaded PDF |
| `mitchell-2010-rethinking-supercompilation` | Rethinking supercompilation | 10.1145/1863543.1863588 | yes | https://ndmitchell.com/downloads/paper-rethinking_supercompilation-29_sep_2010.pdf | author (Mitchell) | published | ACM © (not stated) | OpenAlex (closed) → author site | downloaded PDF |
| `bolingbroke-2010-supercompilation-by-eval` | Supercompilation by evaluation | 10.1145/1863523.1863540 | no | — | — | — | ACM © | Unpaywall (closed); only CiteSeerX stubs | **inaccessible** |
| `panchekha-2015-herbie` | Automatically improving accuracy for floating point expressions | 10.1145/2737924.2737959 | yes | https://herbie.uwplse.org/pldi15-paper.pdf | project (UW PLSE / Herbie) | published | ACM © (not stated) | OpenAlex (closed) → project site | downloaded PDF |
| `schkufza-2013-stoke` | Stochastic superoptimization | 10.1145/2451116.2451150 | yes | https://cs.stanford.edu/~aiken/publications/papers/asplos13.pdf | author (Aiken, Stanford) | published | ACM © (not stated) | OpenAlex (closed) → author site | downloaded PDF |
| `lopes-2021-alive2` | Alive2: bounded translation validation for LLVM | 10.1145/3453483.3454030 | yes | https://www.cs.utah.edu/~regehr/alive2-pldi21.pdf | author (Regehr, Utah) | published | ACM © (not stated) | OpenAlex (closed) → author site | downloaded PDF |
| `lopes-2015-alive` | Provably correct peephole optimizations with Alive | 10.1145/2737924.2737965 | yes | https://www.cs.utah.edu/~regehr/papers/pldi15.pdf | author (Regehr, Utah) | published | ACM © (not stated) | OpenAlex (closed) → author site | downloaded PDF |
| `leroy-2009-compcert` | Formal verification of a realistic compiler (CompCert) | 10.1145/1538788.1538814 | yes | https://xavierleroy.org/publi/compcert-CACM.pdf | author (Leroy) | published | ACM © (not stated) | OpenAlex (HAL location) → author site | downloaded PDF |
| `marlow-2006-fast-curry` | Making a fast curry: push/enter vs eval/apply | 10.1017/S0956796806005995 | yes | CUP core-content PDF (see README) | publisher (CUP, bronze) | published | CUP © (not stated) | Unpaywall | downloaded PDF |
| `peytonjones-1992-stg` | Implementing lazy functional languages … STG machine | 10.1017/S0956796800000319 | yes | CUP core-content PDF (see README) | publisher (CUP, bronze) | published | CUP © (not stated) | Unpaywall | downloaded PDF |
| `brady-2004-inductive-families` | Inductive Families Need Not Store Their Indices | 10.1007/978-3-540-24849-1_8 | no | — | — | — | Springer © | Unpaywall (closed) | **inaccessible** |
| `lee-2001-size-change` | The size-change principle for program termination | 10.1145/360204.360210 | no | — | — | — | ACM © | Unpaywall (closed) | **inaccessible** |
| `rondon-2008-liquid-types` | Liquid types | 10.1145/1375581.1375602 | yes | https://goto.ucsd.edu/~rjhala/papers/liquid_types.pdf | author (Jhala, UCSD) | published | ACM © (not stated) | OpenAlex (closed) → author site | downloaded PDF |
| `danvy-2001-defunctionalization` | Defunctionalization at work | 10.1145/773184.773202 | yes | https://tidsskrift.dk/brics/article/download/21684/19120 | repository/publisher (BRICS, Aarhus) | published (BRICS report) | BRICS OA (not stated) | ACCESS/DOI 10.7146/brics.v8i23.21684 | downloaded PDF |
| `wurthinger-2017-practical-partial-eval` | Practical partial evaluation for dynamic language runtimes | 10.1145/3062341.3062381 | no | — | — | — | ACM © | Unpaywall (closed) | **inaccessible** |
| `wurthinger-2013-one-vm` | One VM to rule them all | 10.1145/2509578.2509581 | no | — | — | — | ACM © | Unpaywall (closed) | **inaccessible** |
| `teiiscak-2020-erasure-calculus` | A dependently typed calculus … erasure inference | 10.1145/3408973 | blocked | https://dl.acm.org/doi/pdf/10.1145/3408973; St Andrews accepted copy unreachable | publisher (ACM gold) / repository | published / accepted | CC-BY | Unpaywall / OpenAlex | **not downloaded** (ACM 403; St Andrews host down) |
| `chataing-2024-unboxed-data-constructors` | Unboxed Data Constructors | 10.1145/3632893 | yes | https://www.cl.cam.ac.uk/~jdy22/papers/unboxed-data-constructors.pdf | author (Yallop, Cambridge) | published | CC-BY (ACM) | Unpaywall (gold @ACM 403) → author site | downloaded PDF |
| `marshall-2022-linearity-uniqueness` | Linearity and Uniqueness: An Entente Cordiale | 10.1007/978-3-030-99336-8_13 | yes | https://kar.kent.ac.uk/98024/1/978-3-030-99336-8_13.pdf | repository (Kent); Springer CC-BY | submitted / published | CC-BY | Unpaywall | downloaded PDF |
| `taha-2000-metaml` | MetaML and multi-stage programming … | 10.1016/S0304-3975(00)00053-0 | blocked | https://www.sciencedirect.com/science/article/pii/S0304397500000530/pdf | publisher (Elsevier, bronze) | published | Elsevier © | Unpaywall | **not downloaded** (ScienceDirect 403) |
| `christiansen-2016-elaborator-reflection` | Elaborator reflection: extending Idris in Idris | 10.1145/2951913.2951932 | blocked | https://research-repository.st-andrews.ac.uk/bitstream/10023/9522/1/elab_reflection_paper.pdf | repository (St Andrews) | submitted | ACM © | Unpaywall / OpenAlex | **not downloaded** (St Andrews host unreachable; ACM ft_gateway 403) |
| `wadler-1990-deforestation` | Deforestation: transforming programs to eliminate trees | 10.1016/0304-3975(90)90147-A | blocked | https://www.sciencedirect.com/science/article/pii/030439759090147A/pdf | publisher (Elsevier, bronze) | published | Elsevier © | Unpaywall | **not downloaded** (ScienceDirect 403) |
| `gill-1993-short-cut` | A short cut to deforestation | 10.1145/165180.165214 | blocked | https://dl.acm.org/doi/pdf/10.1145/165180.165214 | publisher (ACM gold) | published | not stated | Unpaywall | **not downloaded** (dl.acm.org 403) |
| `coutts-2007-stream-fusion` | Stream fusion: from lists to streams to nothing at all | 10.1145/1291151.1291199 | no | — | — | — | ACM © | Unpaywall (closed); MSR copy 403 | **inaccessible** |
| `henriksen-2017-futhark` | Futhark: purely functional GPU-programming … | 10.1145/3062341.3062354 | yes | https://futhark-lang.org/publications/pldi17.pdf | project (futhark-lang.org) | published | ACM © (not stated) | OpenAlex (closed) → project site | downloaded PDF |
| `ragankelley-2013-halide` | Halide: a language and compiler … | 10.1145/2499370.2462176 | yes | https://dspace.mit.edu/server/api/core/bitstreams/1a5f6c2d-0e2a-40b8-ad02-e42d553546a4/content | repository (MIT DSpace) | submitted | CC-BY-NC-SA | Unpaywall | downloaded PDF |
| `mullapudi-2016-halide-autosched` | Automatically scheduling halide pipelines | 10.1145/2897824.2925952 | yes | http://graphics.cs.cmu.edu/projects/halidesched/mullapudi16_halidesched.pdf | project/lab (CMU graphics) | published | ACM © (not stated) | OpenAlex (closed) → project site | downloaded PDF |
| `adams-2019-halide-learning` | Learning to optimize Halide with tree search | 10.1145/3306346.3322967 | yes | https://halide-lang.org/papers/halide_autoscheduler_2019.pdf | project (halide-lang.org) | published | ACM © (not stated) | Unpaywall (closed) → project site | downloaded PDF |
| `ikarashi-2022-exo` | Exocompilation for hardware accelerators | 10.1145/3519939.3523446 | yes | https://dspace.mit.edu/server/api/core/bitstreams/bbe349ab-db53-4927-8de9-abe89a744f2e/content | repository (MIT DSpace) | submitted | CC-BY-NC | Unpaywall | downloaded PDF |
| `kjolstad-2017-taco` | The tensor algebra compiler | 10.1145/3133901 | yes | https://dspace.mit.edu/server/api/core/bitstreams/a9a64140-bffe-40fd-87b7-0caa7f76d788/content | repository (MIT DSpace) | submitted | CC-BY | Unpaywall | downloaded PDF |
| `massalin-1987-superoptimizer` | Superoptimizer: a look at the smallest program | 10.1145/36206.36194 | blocked | https://dl.acm.org/doi/pdf/10.1145/36206.36194 | publisher (ACM gold) | published | not stated | Unpaywall | **not downloaded** (dl.acm.org 403) |
| `bansal-2006-peephole-superoptimizer` | Automatic generation of peephole superoptimizers | 10.1145/1168918.1168906 | no | — | — | — | ACM © | Unpaywall (closed) | **inaccessible** |
| `joshi-2002-denali` | Denali: a goal-directed superoptimizer | 10.1145/512529.512566 | no | — | — | — | ACM © | Unpaywall (closed) | **inaccessible** |
| `pnueli-1998-translation-validation` | Translation validation | 10.1007/BFb0054170 | no | — | — | — | Springer © | Unpaywall (closed) | **inaccessible** |
| `lafont-1990-interaction-nets` | Interaction nets | 10.1145/96709.96718 | no | — | — | — | ACM © | Unpaywall (closed) | **inaccessible** |
| `lamping-1990-optimal-reduction` | An algorithm for optimal lambda calculus reduction | 10.1145/96709.96711 | blocked | https://dl.acm.org/doi/pdf/10.1145/96709.96711 | publisher (ACM gold) | published | not stated | Unpaywall | **not downloaded** (dl.acm.org 403) |
| `reynolds-1972-definitional-interpreters` | Definitional interpreters for higher-order PLs | 10.1145/800194.805852 | no | Syracuse `surface.syr.edu/lcsmith_other/13` has no direct PDF | — | — | ACM © | Unpaywall / OpenAlex (closed) | **inaccessible** |
| `turchin-1986-supercompiler` | The concept of a supercompiler | 10.1145/5956.5957 | blocked | https://dl.acm.org/doi/pdf/10.1145/5956.5957 | publisher (ACM bronze) | published | not stated | Unpaywall | **not downloaded** (dl.acm.org 403) |
| `sorensen-1996-positive-supercompiler` | A positive supercompiler | 10.1017/S0956796800002008 | yes | CUP core-content PDF (see README) | publisher (CUP, bronze) | published | CUP © (not stated) | Unpaywall | downloaded PDF |
| `taha-2004-gentle-intro-multistage` | A Gentle Introduction to Multi-stage Programming | 10.1007/978-3-540-25935-0_3 | no | — | — | — | Springer © | Unpaywall (closed) | **inaccessible** |
| `rompf-2010-lms` | Lightweight modular staging … | 10.1145/1868294.1868314 | no | — | — | — | ACM © | Unpaywall / OpenAlex (closed) | **inaccessible** |
| `leijen-2017-koka-effects` | Type directed compilation of row-typed algebraic effects | 10.1145/3009837.3009872 | yes | https://www.microsoft.com/en-us/research/wp-content/uploads/2016/12/algeff.pdf | author (MSR) | published | ACM © (not stated) | OpenAlex (closed) → MSR | downloaded PDF |
| `blackburn-2008-immix` | Immix: a mark-region garbage collector … | 10.1145/1375581.1375586 | no | ANU repository 503; no author copy found | — | — | ACM © | Unpaywall / OpenAlex (closed) | **inaccessible** |

---

## 2. UNRESOLVED rows (`ACCESS.md` §3c, plus cross-cutting) — 29 rows

| Shortname / row | Title | DOI (resolved?) | OA found | Best direct URL | Host | Version | License | Source | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `fractional-uniqueness` | Functional Ownership through Fractional Uniqueness | 10.1145/3649848 (resolved) | yes | https://kar.kent.ac.uk/105880/1/D.%20Orchard%20-%20Functional%20ownership%20through%20fractional%20uniqueness%20-%20PPDF.pdf | repository (Kent) | accepted | ACM CC-BY (published) | Crossref title → Unpaywall | downloaded PDF |
| `maranget-2008-pattern-matching` | Compiling pattern matching to good decision trees | 10.1145/1411304.1411311 (resolved) | yes | http://moscova.inria.fr/~maranget/papers/ml05e-maranget.pdf | author (Maranget, INRIA) | published | ACM © (not stated) | Crossref title → author site | downloaded PDF |
| `wadler-linear-types` | Linear Types Can Change the World! | none (IFIP) | yes | https://homepages.inf.ed.ac.uk/wadler/papers/linear/linear.ps | author (Wadler, Edinburgh) | published | author-hosted | author site | downloaded **PostScript** |
| `hovgaard-2018-defunctionalisation` | High-Performance Defunctionalisation in Futhark | 10.1007/978-3-030-18506-0_7 (resolved) | yes | https://futhark-lang.org/publications/tfp18.pdf | project (futhark-lang.org) | published | Springer © (not stated) | Crossref title → project site | downloaded PDF |
| `huang-yallop-2023-defunctionalization` | Defunctionalization with Dependent Types | 10.1145/3591241 (resolved) | yes | https://www.cl.cam.ac.uk/~jdy22/papers/defunctionalization-with-dependent-types.pdf | author (Yallop, Cambridge) | accepted | CC-BY (ACM) | Crossref/OpenAlex → author site | downloaded PDF |
| `secrets-ghc-inliner` | Secrets of the Glasgow Haskell Compiler inliner | 10.1017/S0956796802004331 (resolved; candidate `…4270` was wrong) | no | — | — | — | CUP © | Crossref title | **inaccessible** |
| `mlir-cgo-2021` | MLIR: Scaling Compiler Infrastructure for Domain-Specific Computation | 10.1109/CGO51591.2021.9370308 (resolved) | no | — | — | — | IEEE © | OpenAlex title | **inaccessible** |
| `cejtin-2000-defunctionalization` | Flow-Directed Closure Conversion for Typed Languages | 10.1007/3-540-46425-5_4 (resolved) | no | — | — | — | Springer © | OpenAlex title | **inaccessible** |
| `lafont-1997-interaction-combinators` | Interaction Combinators | 10.1006/inco.1997.2643 (resolved) | blocked | https://www.sciencedirect.com/science/article/pii/S0890540197926432/pdf | publisher (Elsevier, bronze) | published | Elsevier © | OpenAlex title → Unpaywall | **not downloaded** (ScienceDirect 403) |
| `certicoq` | CertiCoq / Compositional optimizations; CertiCoq-Wasm | 10.1145/3473591, 10.1145/3703595.3705879 (resolved) | blocked | https://dl.acm.org/doi/pdf/10.1145/3473591 | publisher (ACM gold) | published | CC-BY | Crossref title → Unpaywall | **not downloaded** (dl.acm.org 403) |
| `brady-2013-thesis` | Brady PhD thesis (2013) | n/a | no | St Andrews repository unreachable | — | — | — | ACCESS.md | **inaccessible** |
| `christiansen-thesis` | Christiansen PhD thesis | n/a | no | no OA URL located | — | — | — | ACCESS.md | **inaccessible** |
| `teiiscak-2020-erasure-thesis` | Tejiščák thesis (2020) | n/a | no | St Andrews repository unreachable | — | — | — | ACCESS.md | **inaccessible** |
| `henriksen-thesis` | Henriksen PhD thesis | n/a | no | no OA URL located | — | — | — | ACCESS.md | **inaccessible** |
| `abel-foetus` | foetus — termination checker | n/a (tech report) | no | author `/foetus/` path 404 | — | — | — | ACCESS.md | **inaccessible** |
| `futamura-projections` | Partial evaluation of computation process (1971) | none | no | no DOI/OA copy located | — | — | — | ACCESS.md | **inaccessible** |
| `wadler-1987-pattern-matching` | Efficient compilation of pattern matching (1987) | none | no | no DOI/OA copy located | — | — | — | ACCESS.md | **inaccessible** |
| `warm-fusion` / `shortcut-fusion` | warm/shortcut fusion | none | n/a | no canonical paper selected in plan | — | — | — | — | **not applicable** |
| `book-gc-handbook` | Garbage Collection Handbook | n/a (book) | no | paid book | — | — | book © | — | **not fetched** (pointer only) |
| `boehm-gc` / `precise-tracing-gc` | Boehm GC / precise tracing GC | n/a | n/a | project pages | — | — | — | — | **not applicable** (pointer) |
| `destination-passing-style` | destination-passing style | none | n/a | no canonical reference selected | — | — | — | — | **not applicable** |
| `sac-language` | SaC | none | n/a | no canonical reference selected | — | — | — | — | **not applicable** |
| `mlgo-compilergym` / `autotuning-surveys` | MLGO / CompilerGym; surveys | none | n/a | no canonical references selected | — | — | — | — | **not applicable** |
| `extraction-ilp-maxsat` / `egraph-extraction-cost` | e-graph extraction (ILP/MaxSAT) | none | n/a | no author/title given in plan | — | — | — | — | **not applicable** |
| `book-ssa-compiler-design` | SSA-based Compiler Design (free book) | n/a | n/a | free PDF; store as pointer | — | — | free | — | **not fetched** (pointer) |
| `book-pe-jones-gomard-sestoft` | Partial Evaluation and Automatic Program Generation | n/a | n/a | author-hosted free PDF; store as pointer | — | — | free | — | **not fetched** (pointer) |
| `pointers-gmp-manual` / `pointers-modern-computer-arithmetic` | GMP manual; Modern Computer Arithmetic | n/a | n/a | docs/books; pointers | — | — | — | — | **not fetched** (pointer) |
| `code-koka` / `idris-vect-material` / `sweep-2024-2026` | docs/code/sweep rows | n/a | n/a | out of scope for this paper pass | — | — | — | — | **not applicable** |

---

## 3. Remaining inaccessible targets and what it would take to obtain each

Publisher-paywalled with **no authorized OA copy found** (institutional subscription or author
request required):

| Target | Barrier | What it would take |
| --- | --- | --- |
| `bolingbroke-2010-supercompilation-by-eval` | ACM ©, closed; only CiteSeerX stubs | ACM subscription / interlibrary loan / author email (Bolingbroke, Peyton Jones) |
| `brady-2004-inductive-families` | Springer ©, closed | Springer institutional subscription / author email (Brady) |
| `lee-2001-size-change` | ACM ©, closed | ACM subscription / author email (Ben-Amram) |
| `wurthinger-2017-practical-partial-eval` | ACM ©, closed | ACM subscription / author email (Würthinger) |
| `wurthinger-2013-one-vm` | ACM ©, closed | ACM subscription / author email |
| `coutts-2007-stream-fusion` | ACM ©, closed; MSR PDF 403 | ACM subscription / author email (Coutts) |
| `bansal-2006-peephole-superoptimizer` | ACM ©, closed | ACM subscription / author email (Aiken) |
| `joshi-2002-denali` | ACM ©, closed | ACM subscription / interlibrary loan |
| `pnueli-1998-translation-validation` | Springer ©, closed | Springer subscription / author email / Weizmann report |
| `lafont-1990-interaction-nets` | ACM ©, closed | ACM subscription / author email (Lafont) |
| `reynolds-1972-definitional-interpreters` | ACM ©, closed; Syracuse page has no direct PDF | ACM subscription / Syracuse repository direct request |
| `taha-2004-gentle-intro-multistage` | Springer ©, closed | Springer subscription / author email (Taha) |
| `rompf-2010-lms` | ACM ©, closed | ACM subscription / author email (Rompf) |
| `blackburn-2008-immix` | ACM ©, closed; ANU repository returned HTTP 503 | ACM subscription / retry ANU Open Research repository / author email (Blackburn) |
| `secrets-ghc-inliner` | CUP ©, closed (JFP 2002) | CUP subscription / interlibrary loan / MSR author copy request |
| `mlir-cgo-2021` | IEEE ©, closed (CGO 2021) | IEEE Xplore subscription / author email |
| `cejtin-2000-defunctionalization` | Springer ©, closed (ESOP 2000) | Springer subscription / interlibrary loan |
| `futamura-projections` | no DOI; 1971 journal scan | library scan / interlibrary loan |
| `wadler-1987-pattern-matching` | no DOI; 1987 proceedings | library scan / author email (Wadler) |
| `abel-foetus` | technical report, no stable OA URL | author email (Abel) |
| `brady-2013-thesis`, `christiansen-thesis`, `teiiscak-2020-erasure-thesis`, `henriksen-thesis` | theses; St Andrews host unreachable / no URL | author email; retry St Andrews repository when reachable; Wayback of author page |

Publisher gold/bronze OA that exists but is **not fetchable** (host blocks or is down) — the copy
is authorized, so a browser download or a different host would obtain it:

| Target | Authorized OA URL | Barrier | What it would take |
| --- | --- | --- | --- |
| `lorenzen-2024-oxidizing-ocaml` | Edinburgh repository PDF | HTTP 403 for scripted fetch | browser download of the Edinburgh PDF, or author email |
| `teiiscak-2020-erasure-calculus` | `dl.acm.org/doi/pdf/10.1145/3408973` (CC-BY); St Andrews accepted copy | dl.acm.org 403; St Andrews host down | browser download via ACM CC-BY page, or retry St Andrews |
| `christiansen-2016-elaborator-reflection` | St Andrews repository PDF (submitted) | host unreachable; ACM ft_gateway 403 | retry St Andrews repository / author email |
| `lorenzen-2022-frame-limited-reuse` | `dl.acm.org/doi/pdf/10.1145/3547634` (CC-BY) | dl.acm.org 403 | browser download via ACM CC-BY page |
| `gill-1993-short-cut` | `dl.acm.org/doi/pdf/10.1145/165180.165214` (gold) | dl.acm.org 403 | browser download via ACM page |
| `massalin-1987-superoptimizer` | `dl.acm.org/doi/pdf/10.1145/36206.36194` (gold) | dl.acm.org 403 | browser download via ACM page |
| `lamping-1990-optimal-reduction` | `dl.acm.org/doi/pdf/10.1145/96709.96711` (gold) | dl.acm.org 403 | browser download via ACM page |
| `turchin-1986-supercompiler` | `dl.acm.org/doi/pdf/10.1145/5956.5957` (bronze) | dl.acm.org 403 | browser download via ACM page |
| `taha-2000-metaml` | `sciencedirect.com/.../S0304397500000530/pdf` (bronze) | ScienceDirect 403 | browser/ScienceDirect access |
| `wadler-1990-deforestation` | `sciencedirect.com/.../030439759090147A/pdf` (bronze) | ScienceDirect 403 | browser/ScienceDirect access |
| `lafont-1997-interaction-combinators` | `sciencedirect.com/.../S0890540197926432/pdf` (bronze) | ScienceDirect 403 | browser/ScienceDirect access |
| `certicoq` (Compositional optimizations; CertiCoq-Wasm) | `dl.acm.org/doi/pdf/10.1145/3473591`; `…/10.1145/3703595.3705879` (CC-BY) | dl.acm.org 403 | browser download via ACM CC-BY page |

Note on HAL: `leroy-2009-compcert` also has an author HAL deposit
(`https://inria.hal.science/inria-00415861`, version 1). HAL serves an **Anubis** bot-protection
challenge to scripted clients; that challenge was intentionally not solved/evaded, so the
author's own site copy was used instead. Any future automated HAL fetch would require solving
the challenge through a real browser session.
