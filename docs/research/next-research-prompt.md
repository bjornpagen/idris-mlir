# Research brief: optimizing Idris from first principles

## Rules (read first)

This is a research task only. Your outputs are papers, notes, and one
written report.

- Do **not** build, compile, install, or run anything from this repository
  or its dependencies. Do not run `tools/dev.py`, `make`, `cmake`, `ninja`,
  `idris2`, `apt`, `pip`, or any compiler. Do not create or change code,
  tests, build files, or `AGENTS.md`.
- Allowed: reading files in this repo, reading source code online (GitHub),
  web search, and downloading papers. Shell commands are allowed only to
  fetch, unpack, list, and commit paper sources (`curl`, `tar`, `git`).
- If a question can only be settled by an experiment, do not run it. Write
  it down as a proposed experiment, with its pass/fail criterion.
- Work directly on `main` in `bjornpagen/idris-mlir`. Do not create branches.

## 0. Check access

Try fetching https://arxiv.org/abs/2201.07272, https://dl.acm.org/,
https://mlir.llvm.org/, https://docs.tinygrad.org/, and
https://egraphs-good.github.io/. Report which work. If any primary source
is unreachable, say so, and mark every claim you could only get from an
abstract or search snippet.

## 1. Collect the papers first

Before writing the report, collect the primary papers for every thread in
section 4, and anything else you rely on.

- Store each paper under `docs/research/papers/<first-author-year-shortname>/`.
- Prefer the **raw LaTeX source**: for arXiv papers, download
  `https://arxiv.org/e-print/<id>` and unpack it. Only if no source is
  available, store the **PDF**. Skip generated files (`.aux`, `.log`, `.bbl`
  only if the `.bib` is present) and anything over 20 MB.
- Write `docs/research/papers/INDEX.md`: one row per paper with the title,
  authors, venue and year, link, what is stored (TeX or PDF), and which
  threads it serves. List papers you could not obtain, and why.
- Commit and push the papers and the index to `main` **before** writing the
  report (message: "Add research papers for first-principles study").

## 2. Context (read, do not rederive)

Read `AGENTS.md`, `README.md`, `docs/architecture.md`, and
`docs/research/whole-program-compilation.md`. The last one summarizes
conventional practice (MLton, Lean 4, Perceus, CertiCoq, GRIN). Treat it as
the baseline to challenge, not as a conclusion.

Established facts:

- The compiler is written in Idris, as an `mlir` backend registered with the
  stock Idris 2 driver (pinned `1c630e67`). It reads checked TT: signatures
  and compile-time case trees (`treeCT`), with quantities. It translates them
  to our own IR, erases quantity-0 binders in an explicit pass, and emits
  MLIR text (`func`/`arith`/`scf`). The pinned `mlir-opt → mlir-translate →
  opt → llc` (LLVM 23.1.2) plus `cc` produce native code. Supported today:
  first-order fixed-width integer code only.
- Idris hands the whole-program callback `unsafePerformIO main` plus the
  full context. IO is world passing: `PrimIO a = (1 w : %World) -> IORes a`.
- TTC (Idris's module cache) drops runtime case trees and the types of
  machine-generated names. The per-module callback sees fresh definitions
  before TTC is written.
- In MLIR 23.1.2: `func.call` cannot request a tail call, while `llvm.call`
  has `tail_call_kind` (`tail`/`musttail`/`notail`). `convert-to-llvm` covers
  arith, cf, func, index, math, memref, ptr, ub, vector, and complex. Generic
  passes include inline, sccp, remove-dead-values, symbol-dce, mem2reg, and
  sroa. No upstream dialect has ADTs, closures, thunks, or reference counting.
- The pinned `mlir-opt` accepts `--irdl-file` (dialects defined as IRDL text
  at run time), `--transform-interpreter`, and `--transform-preload-library`,
  and has the `pdl`/`pdl_interp` dialects, `--load-dialect-plugin`, and
  `--load-pass-plugin`.
- Observed: ops defined only in IRDL text are opaque to generic
  optimization. Two identical IRDL ops were not CSE'd and a dead one was not
  removed under `--canonicalize --cse --remove-dead-values`, while a dead
  `arith.addi` beside them was removed. IRDL ops carry no traits or
  interfaces, so MLIR assumes unknown side effects.
- **C++ is an open question, not a taboo.** If MLIR is genuinely better with
  C++ (ODS dialects with traits and interfaces, folders, canonicalizers,
  `TypeConverter`-based conversion, passes on the dataflow framework), we
  should use it. Compare concretely:
  1. All optimization in our own Idris IR, emitting upstream dialects only
     (the MLton, Lean, and tinygrad stance: one small IR we own).
  2. An Idris frontend emitting our own C++-defined MLIR dialect(s),
     optimized with MLIR's interfaces and passes (the "Lambda the Ultimate
     SSA" stance).
  3. A hybrid: which facts must survive into MLIR to be useful there?
  Weigh build and toolchain cost, a second implementation language, and what
  must stay in sync between the Idris side and a dialect.

## 3. The goal

Work out how this compiler should optimize from first principles, with zero
information loss between checked TT and machine code. The compiler sees the
whole program, QTT quantities (0/1/ω), dependent types (index relationships,
totality, erasure), explicit effects, and MLIR. Tinygrad gets large wins from
a tiny IR, one uniform graph-rewrite mechanism, symbolic shapes, and search
(BEAM) instead of hand-tuned heuristics. Work out whether and how that stance
applies to a general-purpose, dependently typed functional language.

Start from a cost model, not compiler tradition. For a compiled Idris
program, where does runtime go (allocation, indirection, dispatch, closures,
boxing, reference counting or GC, proof and index residue, laziness,
bignums, missed fusion, missed vectorization)? For each cost, which
statically available fact removes it, and which mechanism exploits that fact
soundly?

## 4. Research threads

A. **Tinygrad** (read the source on GitHub): `UOp`, `Ops`,
   `PatternMatcher`/`UPat`, `graph_rewrite`, scheduling and fusion, symbolic
   shapes, the linearizer and renderers, BEAM search, and overall size. What
   makes it work? Which parts depend on tensor programs being first-order
   dataflow over arrays?
B. **Equality saturation and rewriting as the optimizer**: egg (POPL 2021),
   egglog (PLDI 2023), slotted e-graphs (binders), e-graphs with lambdas,
   extraction (ILP, cost models), guided or sketch-guided saturation, the
   MLIR `eqsat` dialect work, and DialEgg. Can one rewrite engine replace a
   hand-ordered pass pipeline for a functional IR with binders?
C. **Staging and partial evaluation with types**: two-level type theory
   (Kovács, ICFP 2022; "Closure-free functional programming in a two-level
   type theory", ICFP 2024), Idris elaborator reflection as staging,
   supercompilation, deforestation, and Futamura projections in practice
   (Truffle/Graal). Can quantity 0 plus types give guaranteed specialization,
   and allocation- or closure-free code where the types permit it?
D. **Memory from QTT**: linearity vs uniqueness (Marshall, Vollmer, Orchard,
   ESOP 2022; fractional uniqueness, OOPSLA 2024), Perceus (PLDI 2021),
   frame-limited reuse (ICFP 2022), FP² fully in-place programming (ICFP
   2023), OCaml modes ("Oxidizing OCaml", ICFP 2024), and "Counting Immutable
   Beans" (IFL 2019). What does Idris's quantity 1 soundly give us? What
   more is needed for guaranteed in-place update and no GC?
E. **Representation from dependent types**: Brady, McBride, McKinna,
   "Inductive families need not store their indices" (2003); Tejiščák's
   erasure thesis (2020); the Idris 2 QTT paper (ECOOP 2021); and what
   upstream Idris already does (read `third_party/Idris2/src`, e.g.
   `detagabbleBy`, newtype and Nat handling). Can proofs such as bounds or
   `Fin n` soundly justify unboxed machine integers, bounds-check removal,
   overflow-freedom, or layout?
F. **MLIR with and without C++**: without C++, IRDL, PDL/PDLL, the transform
   dialect (Lücke et al., CGO 2025), and bytecode. With C++, ODS, interfaces,
   the dataflow framework, dialect conversion, and plugins. Also "Lambda the
   Ultimate SSA" (Bhat and Grosser, CGO 2022), lean-mlir verified peephole
   rewriting (ITP 2024), and any existing functional-language dialects.
   Answer from documentation and source code; propose (do not run) the
   experiments that would settle what remains open.
G. **Arrays and kernels with shape types**: Dex (index sets), Futhark
   (uniqueness, defunctionalization), Remora, Halide/TVM/Ansor/Exo
   (algorithm vs schedule, search), and tinygrad symbolic shapes compared
   with Idris indices. What must a Vect-like type carry for kernels to reach
   scf/memref/vector without guessing layout?
H. **Search and cost models**: BEAM and autotuning, superoptimization
   (Souper, STOKE), learned cost models, e-graph extraction. Where does
   search pay off for general code, and where for kernels?
I. **Proved optimizations**: can rewrite rules carry proofs checked by Idris
   (versus the unchecked `%transform`)? Relate to Alive2, translation
   validation, CompCert, and CertiCoq.
J. **Bleeding edge, evaluated critically**: HVM2/Bend and interaction nets,
   plus anything relevant from 2024–2026. Separate demonstrated results from
   claims.

## 5. Method

- Primary sources only for load-bearing claims: papers, source code, and
  official docs. Cite each claim with a link. Mark it *read in full*, *from
  abstract*, or *from code*.
- For MLIR details, read the `llvmorg-23.1.2` tag of `llvm/llvm-project` on
  GitHub (for example `mlir/include/mlir/...`), not a local build.
- Reason from the cost model. When convention and first principles
  disagree, say which you trust and why.
- Check each idea against what checked TT actually contains
  (`third_party/Idris2/src/Core/TT*`, `Core/Context/Context.idr`,
  `Core/Case/CaseTree.idr`).

## 6. Deliverables

1. `docs/research/papers/` and `docs/research/papers/INDEX.md`, committed and
   pushed first.
2. `docs/research/first-principles-optimization.md`:
   - The cost model, and an inventory of the facts Idris provides, each
     linked to the costs it can remove.
   - Per thread: what exists, what is proven, what applies to us, and what
     does not.
   - Two or three candidate architectures (IR shape, rewrite mechanism,
     memory model, the split between Idris and MLIR, C++ or not), with
     trade-offs.
   - A short list of decisive experiments for later, each with a measurable
     pass/fail criterion and benchmark programs to compare against the Idris
     Chez and RefC backends and hand-written C. Do not run them.
   - Open questions for the user.
3. Commit the report to `main` and push ("Add first-principles optimization
   research"). Then give a short chat summary: the recommendation, the
   evidence, and what remains uncertain.
