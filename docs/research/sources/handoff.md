# Handoff: from sources to the first-principles optimization report

This document is the entry point for the **deferred report pass**. The report itself,
`docs/research/first-principles-optimization.md`, is **not written** in the sources pass; this
pass collected and indexed the material it will need. Everything below is a local path, so
the report author should need **no further fetching** to start.

How the pieces fit together:

- `MANIFEST.md` — inventory of every target (thread, harvest method, storage form, status).
- `ACCESS.md` — reachability matrix, pins, resolved DOIs, exact fetch commands.
- `oa-locations.md` — which link-only papers have an authorized OA copy, and what still blocks.
- `bibliography.bib` — 642 BibTeX entries (596 harvested+deduped, 46 added for INDEX coverage).
- `../papers/` — the paper corpus (`INDEX.md` is its index; each `<shortname>/` holds TeX or PDF).
- `docs/`, `code/`, `pointers/`, `oa-papers/` — documentation snapshots, pinned code excerpts,
  pointers for un-vendored trees, and authorized OA paper copies.

All paths below are relative to `docs/research/` unless noted. Thread labels A–J follow the plan.

> **Pin reminder.** `third_party/Idris2` is **not checked out** in this tree; Idris 2 material
> under `sources/code/idris2/` and `sources/docs/idris2/` was fetched from the pinned raw URLs
> (`1c630e67c386629a0fbbc6b78a59176fde7f0a76`). Run `git submodule update --init` if you need
> to read the submodule in place.

---

## 1. Thread → source map

### Thread A — Tinygrad and first-order dataflow optimizers

| Kind | Local paths |
| --- | --- |
| papers | `papers/zheng-2020-ansor/`, `papers/yang-2021-tensat/`, `papers/chen-2018-tvm/`, `sources/oa-papers/jia-2019-taso/` |
| code | `sources/code/tinygrad/tinygrad/uop/{ops,upat,spec,symbolic,render,validate}.py`, `codegen/simplify.py`, `codegen/opt/search.py`, `schedule/{prepare,rangeify,indexing,memory,multi}.py`, `renderer/{cstyle,llvmir}.py`, `engine/{realize,jit}.py` |
| docs | `sources/docs/tinygrad/` (repo `README.md` + `docs/**`) |

**Read first:** `code/tinygrad/tinygrad/uop/ops.py` and `codegen/simplify.py` (the rewrite-rule
system and symbolic simplifier); `codegen/opt/search.py` (BEAM search — this is the located
module, not a guess); `zheng-2020-ansor` (schedule search space).
**Claims these settle:** how tinygrad performs local rewriting and beam search over a
first-order IR; its schedule/indexing algebra; the concrete rule set a report can compare
equality saturation against.

### Thread B — Equality saturation and rewriting

| Kind | Local paths |
| --- | --- |
| papers | `papers/willsey-2021-egg/`, `papers/zhang-2023-egglog/`, `papers/zhang-2022-relational-ematching/`, `papers/wang-2020-spores/`, `papers/koehler-2021-sketch-eqsat/`, `papers/wu-2026-slotted-egraphs/`, `papers/yang-2021-tensat/`, `papers/pal-2023-ruler/` (TeX), `sources/oa-papers/panchekha-2015-herbie/` |
| code | `sources/code/mlir/include/mlir/IR/PatternMatch.h`, `sources/code/mlir/include/mlir/Dialect/Transform/**`, `sources/code/mlir/include/mlir/Transforms/*` (greedy driver, dialect conversion) |
| docs | `sources/docs/mlir/docs/PatternRewriter.md`, `.../DialectConversion.md`, `.../Canonicalization.md`, `.../DeclarativeRewrites.md` |
| link-only | `koehler-2024-guided-eqsat` (ACM 403) — see §2 |

**Read first:** `willsey-2021-egg` (e-graph/rebuilding), `zhang-2022-relational-ematching`
(e-matching), `koehler-2021-sketch-eqsat` (sketch-guided), `pal-2023-ruler` (ruleset inference).
**Claims these settle:** e-graph invariants and rebuild cost; e-matching complexity; how rules
are discovered rather than hand-written; where extraction fits.

### Thread C — Staging, partial evaluation, supercompilation, fusion

| Kind | Local paths |
| --- | --- |
| papers | `papers/kovacs-2022-staged/`, `papers/sorensen-1996-positive-supercompiler/`, `sources/oa-papers/mitchell-2010-rethinking-supercompilation/` |
| link-only | `bolingbroke-2010-supercompilation-by-eval`, `turchin-1986-supercompiler`, `gill-1993-short-cut`, `coutts-2007-stream-fusion`, `wadler-1990-deforestation`, `kovacs-2024-closure-free`, `taha-2000-metaml`, `taha-2004-gentle-intro-multistage`, `rompf-2010-lms`, `wurthinger-2013-one-vm`, `wurthinger-2017-practical-partial-eval`, `christiansen-2016-elaborator-reflection` |

**Read first:** `turchin-1986-supercompiler` and `kovacs-2022-staged` (the two poles of
supercompilation/staging), `coutts-2007-stream-fusion` (fusion in practice),
`mitchell-2010-rethinking-supercompilation`.
**Claims these settle:** what supercompilation and fusion actually promise; when staging
resolves overhead; the cost/benefit a report can attribute to each.

### Thread D — Memory from QTT

| Kind | Local paths |
| --- | --- |
| papers | `papers/ullrich-2019-counting-immutable-beans/`, `papers/bernardy-2018-linear-haskell/`, `papers/marshall-2022-linearity-uniqueness/`, `sources/oa-papers/reinking-2021-perceus/`, `sources/oa-papers/lorenzen-2023-fp2/`, `sources/oa-papers/marlow-2006-fast-curry/`, `sources/oa-papers/peytonjones-1992-stg/` |
| code | `sources/code/idris2/src/Core/LinearCheck.idr` (erasure inference), `src/Core/Context/Context.idr` (`eraseArgs`/`safeErase`), `src/Compiler/{Inline,ANF,LambdaLift,CaseOpts}.idr`, `src/Compiler/RefC/**` |
| docs | `sources/docs/idris2/docs/source/backends/**`, `sources/docs/ghc/commentary-compiler-{stg-syn-type,cmm-type,demand}.md`, `sources/docs/ghc/commentary-rts.md` |
| link-only | `lorenzen-2022-frame-limited-reuse`, `lorenzen-2024-oxidizing-ocaml` |

**Read first:** `reinking-2021-perceus`, `lorenzen-2023-fp2`,
`ullrich-2019-counting-immutable-beans`, `sources/code/idris2/src/Core/LinearCheck.idr`.
**Claims these settle:** how reference counting with reuse is specified; what QTT multiplicities
do and do **not** imply about heap ownership; what Idris 2 already implements.

### Thread E — Representation from dependent types

| Kind | Local paths |
| --- | --- |
| papers | `papers/brady-2021-idris2-qtt/`, `sources/oa-papers/chataing-2024-unboxed-data-constructors/` |
| code | `sources/code/idris2/src/Core/TT.idr`, `src/Core/TT/{Term,Binder}.idr`, `src/Core/Case/{CaseTree,CaseBuilder,Util}.idr`, `src/Compiler/CaseOpts.idr`, `src/Core/LinearCheck.idr` |
| docs | `sources/docs/idris2/docs/source/implementation/**`, `sources/docs/ghc/commentary-compiler-data-types.md` |
| link-only | `brady-2004-inductive-families`, `teiiscak-2020-erasure-calculus`; the GHC **unarisation** page does not exist (see §3) |

**Read first:** `brady-2021-idris2-qtt`, `chataing-2024-unboxed-data-constructors`,
`sources/code/idris2/src/Core/Case/CaseTree.idr`, `sources/code/idris2/src/Compiler/CaseOpts.idr`.
**Claims these settle:** that indices need not be stored; how pattern matching is compiled to
decision trees; how unboxed constructors are represented (and the halting-problem caveat).

### Thread F — MLIR with and without C++

| Kind | Local paths |
| --- | --- |
| papers | `papers/lattner-2020-mlir/`, `papers/bhat-2022-lambda-ultimate-ssa/`, `papers/lucke-2024-transform-dialect/`, `papers/bhat-2024-verifying-peephole/`, `sources/oa-papers/fehr-2022-irdl/` |
| code | `sources/code/mlir/include/mlir/IR/PatternMatch.h` (declares `RewriterBase`), `IR/OpDefinition.h`, `Transforms/{DialectConversion,GreedyPatternRewriteDriver,Passes}.*`, `Interfaces/*.td`, `Dialect/{PDL,PDLInterp,Transform,LLVMIR}/**` |
| docs | `sources/docs/mlir/**` (100 files incl. all `mlir/docs/**`), `sources/docs/llvm/docs/**` (11 files) |
| pointer | `sources/pointers/mlir-lib-trees.md` (un-vendored `lib/` trees + pin) |
| link-only | `mlir-cgo-2021` |

**Read first:** `lattner-2020-mlir`, `lucke-2024-transform-dialect`,
`sources/code/mlir/include/mlir/IR/PatternMatch.h`,
`sources/code/mlir/include/mlir/Dialect/Transform/IR/TransformDialect.td`.
**Claims these settle:** MLIR's rewrite/rewriter design; the Transform dialect's separation of
schedule from transform; the dialect-conversion machinery the report might reuse.

### Thread G — Arrays and kernels with shape types

| Kind | Local paths |
| --- | --- |
| papers | `sources/oa-papers/henriksen-2017-futhark/`, `sources/oa-papers/kjolstad-2017-taco/`, `papers/shivers-2019-remora/`, `papers/ragankelley-2013-halide/`, `papers/adams-2019-halide-learning/`, `sources/oa-papers/mullapudi-2016-halide-autosched/`, `sources/oa-papers/ikarashi-2022-exo/`, `papers/zheng-2020-ansor/`, `papers/chen-2018-tvm/` |
| code | `sources/code/tinygrad/tinygrad/uop/{spec,symbolic}.py`, `schedule/indexing.py` (symbolic shapes) |
| docs | `sources/docs/tinygrad/docs/**` |

**Read first:** `henriksen-2017-futhark`, `kjolstad-2017-taco`, `shivers-2019-remora`,
`ragankelley-2013-halide`.
**Claims these settle:** rank/shape polymorphism and its lowering; how array kernels are
expressed and scheduled; the cost of separating algorithm from schedule.

### Thread H — Search and cost models

| Kind | Local paths |
| --- | --- |
| papers | `papers/sasnauskas-2017-souper/`, `papers/schkufza-2013-stoke/`, `papers/mendis-2019-ithemal/` |
| code | `sources/code/tinygrad/tinygrad/codegen/opt/{search,heuristic}.py` |
| link-only | `massalin-1987-superoptimizer`, `bansal-2006-peephole-superoptimizer`, `joshi-2002-denali` |

**Read first:** `massalin-1987-superoptimizer`, `schkufza-2013-stoke`, `mendis-2019-ithemal`,
`sources/code/tinygrad/tinygrad/codegen/opt/search.py`.
**Claims these settle:** the superoptimizer lineage; stochastic search; learned vs analytic
cost models; a concrete beam-search implementation to compare against.

### Thread I — Proved optimizations

| Kind | Local paths |
| --- | --- |
| papers | `sources/oa-papers/lopes-2021-alive2/`, `sources/oa-papers/lopes-2015-alive/`, `papers/bhat-2024-verifying-peephole/`, `sources/oa-papers/leroy-2009-compcert/`, `papers/bhat-2022-lambda-ultimate-ssa/` |
| code | `sources/code/idris2/src/Core/Transform.idr`, `src/TTImp/ProcessTransform.idr` (Idris `%transform`), `sources/code/mlir/include/mlir/Dialect/Transform/SMTExtension/**` |
| link-only | `pnueli-1998-translation-validation`, `certicoq` |

**Read first:** `lopes-2021-alive2`, `bhat-2024-verifying-peephole`, `leroy-2009-compcert`,
`sources/code/idris2/src/Core/Transform.idr`.
**Claims these settle:** what translation validation guarantees; how rewrites are proved;
what Idris 2's `%transform` mechanism already checks.

### Thread J — Bleeding edge, evaluated critically

| Kind | Local paths |
| --- | --- |
| link-only | `lafont-1990-interaction-nets`, `lamping-1990-optimal-reduction`, `lafont-1997-interaction-combinators` |
| not vendored | HVM2 (`HigherOrderCO/HVM`) and Bend (`HigherOrderCO/Bend`) sources were `planned` in `MANIFEST.md` but **not** vendored; fetch at their pins (`7365a56c…`, `574b6d39…`) if needed |

**Read first:** `lafont-1990-interaction-nets`, `lamping-1990-optimal-reduction`,
`lafont-1997-interaction-combinators`.
**Claims these settle:** what interaction nets/combinators actually reduce, and what optimal
reduction costs — the report must judge claimed-vs-demonstrated from these.

### Cross-cutting (compiler prior art, defunctionalisation, specialisation, bignums, effects)

| Kind | Local paths |
| --- | --- |
| papers | `sources/oa-papers/danvy-2001-defunctionalization/`, `sources/oa-papers/huang-yallop-2023-defunctionalization/`, `sources/oa-papers/hovgaard-2018-defunctionalisation/`, `papers/peytonjones-1992-stg/`, `sources/oa-papers/marlow-2006-fast-curry/`, `papers/marshall-2022-linearity-uniqueness/` |
| docs | `sources/docs/ghc/commentary-compiler-{core-to-core-pipeline,opt-ordering,code-gen,backends}.md`, `sources/docs/ghc/users_guide/using-optimisation.html` |
| pointer | `sources/pointers/ghc.md` |
| code | `sources/code/mlir/include/mlir/Dialect/LLVMIR/LLVMOps.td` (tail-call/GC attributes) |
| link-only | `reynolds-1972-definitional-interpreters`, `cejtin-2000`, `secrets-ghc-inliner` |

**Read first:** `danvy-2001-defunctionalization`, `huang-yallop-2023-defunctionalization`,
`peytonjones-1992-stg`, `secrets-ghc-inliner` (once obtained).
**Claims these settle:** defunctionalisation techniques and their typed variants; the STG
evaluation model; how GHC's inliner/specialiser are architected.

---

## 2. What the report still needs

### 2a. Open questions the sources cannot settle (need an experiment or a user decision)

- **Custom MLIR dialect/passes in C++ or not?** `docs/research/next-research-prompt.md` frames
  this as the central open question; the corpus documents MLIR's facilities but cannot decide
  whether this project should add C++. Needs a research recommendation + user sign-off.
- **Does a linear/QTT binder imply unique heap ownership?** The sources (`LinearCheck.idr`,
  Perceus, FP²) show what the type system does; whether *this* backend can exploit it for
  in-place update needs a representation experiment.
- **Are indexed vectors contiguous?** `brady-2004` and `brady-2021` explain erasure of indices;
  contiguous storage is an implementation choice the report must test, not assume.
- **Erased ≠ constant.** Which erased values must still exist at runtime, and at what cost,
  is a per-constructor experiment.
- **Which cost model drives extraction/search?** Hand-written (tinygrad heuristics) vs learned
  (`mendis-2019-ithemal`)? The sources describe both; choosing needs measurement.
- **Do any of these passes pay off on Idris-generated IR?** Fusion, eqsat, supercompilation,
  and transform-dialect schedules are all documented; none is measured on this project's IR.
  The report's claims must be marked *demonstrated* vs *claimed* (per the plan's Thread J rule).
- **204–2026 venue sweep.** `sweep-2024-2026` is a live literature sweep that cannot be
  pre-enumerated; it must be run (and demonstrated-vs-claimed recorded) in the report pass.
- **Destination-passing style, SaC, warm/shortcut fusion, MLGO/CompilerGym, autotuning and
  e-graph-extraction (ILP/MaxSAT) surveys:** no canonical reference was selected in the plan;
  confirm intent before citing.

### 2b. Papers still link-only or unobtainable, and the action each needs

**Authorized OA exists but a host blocks scripted fetch — a browser download obtains it:**

| Target | Where | Action |
| --- | --- | --- |
| `lorenzen-2024-oxidizing-ocaml` | Edinburgh repository PDF (403) | browser download, or author email |
| `teiiscak-2020-erasure-calculus` | `dl.acm.org/doi/pdf/10.1145/3408973` (CC-BY) | browser download via ACM page; or retry St Andrews |
| `christiansen-2016-elaborator-reflection` | St Andrews repository PDF | retry St Andrews when reachable / author email |
| `lorenzen-2022-frame-limited-reuse` | `dl.acm.org/doi/pdf/10.1145/3547634` (CC-BY) | browser download via ACM page |
| `gill-1993-short-cut` | `dl.acm.org/doi/pdf/10.1145/165180.165214` | browser download via ACM page |
| `massalin-1987-superoptimizer` | `dl.acm.org/doi/pdf/10.1145/36206.36194` | browser download via ACM page |
| `lamping-1990-optimal-reduction` | `dl.acm.org/doi/pdf/10.1145/96709.96711` | browser download via ACM page |
| `turchin-1986-supercompiler` | `dl.acm.org/doi/pdf/10.1145/5956.5957` | browser download via ACM page |
| `taha-2000-metaml` | `sciencedirect.com/.../S0304397500000530/pdf` (403) | browser/ScienceDirect access |
| `wadler-1990-deforestation` | `sciencedirect.com/.../030439759090147A/pdf` (403) | browser/ScienceDirect access |
| `lafont-1997-interaction-combinators` | `sciencedirect.com/.../S0890540197926432/pdf` (403) | browser/ScienceDirect access |
| `certicoq` | `dl.acm.org/doi/pdf/10.1145/3473591`, `…/10.1145/3703595.3705879` (CC-BY) | browser download via ACM page |

**Closed — needs a subscription, interlibrary loan, or author email:**

| Target | Barrier | Action |
| --- | --- | --- |
| `bolingbroke-2010-supercompilation-by-eval` | ACM ©, closed | ACM subscription / ILL / author email |
| `brady-2004-inductive-families` | Springer ©, closed | Springer subscription / author email |
| `lee-2001-size-change` | ACM ©, closed | ACM subscription / author email (Ben-Amram) |
| `wurthinger-2017-practical-partial-eval`, `wurthinger-2013-one-vm` | ACM ©, closed | ACM subscription / author email |
| `coutts-2007-stream-fusion` | ACM ©, closed | ACM subscription / author email (Coutts) |
| `bansal-2006-peephole-superoptimizer` | ACM ©, closed | ACM subscription / author email (Aiken) |
| `joshi-2002-denali` | ACM ©, closed | ACM subscription / ILL |
| `pnueli-1998-translation-validation` | Springer ©, closed | Springer subscription / author email / Weizmann report |
| `lafont-1990-interaction-nets` | ACM ©, closed | ACM subscription / author email (Lafont) |
| `reynolds-1972-definitional-interpreters` | ACM ©, closed | ACM subscription / Syracuse repository request |
| `taha-2004-gentle-intro-multistage` | Springer ©, closed | Springer subscription / author email (Taha) |
| `rompf-2010-lms` | ACM ©, closed | ACM subscription / author email (Rompf) |
| `blackburn-2008-immix` | ACM ©, closed; ANU repo 503 | ACM subscription / retry ANU Open Research / author email |
| `secrets-ghc-inliner` | CUP ©, closed (JFP 2002) | CUP subscription / ILL / MSR author copy |
| `mlir-cgo-2021` | IEEE ©, closed (CGO 2021) | IEEE Xplore subscription / author email |
| `cejtin-2000` | Springer ©, closed (ESOP 2000) | Springer subscription / ILL |
| `futamura-projections` | no DOI; 1971 journal scan | library scan / ILL |
| `wadler-1987-pattern-matching` | no DOI; 1987 proceedings | library scan / author email (Wadler) |
| `abel-foetus` | technical report, no stable URL | author email (Abel) |
| `brady-2013-thesis`, `christiansen-thesis`, `teiiscak-2020-erasure-thesis`, `henriksen-thesis` | theses; St Andrews down / no URL | author email; retry St Andrews; Wayback of author page |

**Accept the gap (no canonical reference exists to fetch):** warm/shortcut fusion,
destination-passing style, SaC, MLGO/CompilerGym, autotuning surveys, e-graph extraction
(ILP/MaxSAT) — the plan names no author/title, so the report must either pick references or
state the gap explicitly.

---

## 3. Known holes in this corpus

- **Empty `third_party/Idris2` submodule.** Not checked out; Idris 2 snapshots came from pinned
  raw URLs. Run `git submodule update --init` to read it locally (this does not change the corpus).
- **GHC `unarisation` gap (`docs-ghc-unarisation`).** No `commentary/compiler/unarisation` page
  exists (HTTP 404); nearest captured material is `docs/ghc/commentary-compiler-code-gen.md`,
  `...-backends.md`, `...-data-types.md`.
- **Dead `ssabook.gforge.inria.fr`.** The SSA book PDF was fetched via the Wayback Machine
  (snapshot `20210621194509`); see `pointers/ssa-book.md`.
- **Hosts that block or fail scripted fetches:** `dl.acm.org` (403), `sciencedirect.com` (403),
  `research.ed.ac.uk` (403), `research-repository.st-andrews.ac.uk` (503/unreachable),
  `research-collection.ethz.ch` (500), ANU Open Research (503), and HAL (Anubis bot challenge —
  not solved/evaded). Affected papers are in §2b.
- **Correction: ScienceDirect returned 403, not the 200 `ACCESS.md` recorded** for
  `taha-2000-metaml` and `wadler-1990-deforestation`; both are link-only.
- **Un-vendored source trees:** egg, egglog, HVM, Bend, dex-lang, Futhark, and GHC sources were
  `planned`/pointer-only in `MANIFEST.md`; only their pins and URL patterns are recorded
  (`ACCESS.md`, `pointers/ghc.md`). Fetch on demand if the report needs exact code.
- **No `mlir/include/mlir/IR/RewriterBase.h`** at the pin: `RewriterBase` lives in
  `PatternMatch.h` (vendored). Likewise several dialect docs exist only as ODS-generated
  content covered by the full `docs/mlir/**` snapshot.
