# Research brief: optimizing Idris from first principles

You are researching, not implementing. Do not change compiler code. Scratch
experiments (running the pinned tools on hand-written inputs) are allowed
and encouraged. Work in the repository at `bjornpagen/idris-mlir`, branch
`main`. Read `AGENTS.md`, `README.md`, `docs/architecture.md`, and
`docs/research/whole-program-compilation.md` first.

## 0. Sanity check network access first

Fetch https://arxiv.org/abs/2201.07272, https://dl.acm.org/,
https://mlir.llvm.org/, https://docs.tinygrad.org/, and
https://egraphs-good.github.io/. Report which ones work. If primary sources
are blocked, say so up front, and mark every claim you could only get from
an abstract or search snippet.

## 1. Where we are (verified; do not rederive)

- The compiler is written in Idris, as an `mlir` backend registered with the
  stock Idris 2 driver (pinned `1c630e67`, the current upstream main). It
  reads checked TT: signatures and compile-time case trees (`treeCT`), with
  quantities. It translates them to our IR, erases quantity-0 binders
  explicitly, and emits MLIR text (`func`/`arith`/`scf`). Pinned
  `mlir-opt → mlir-translate → opt → llc` (LLVM 23.1.2, built under
  `.toolchain/`) plus `cc` produce a native executable. The subset is
  first-order fixed-width integer code, with `main : Int` as the exit status.
- Idris hands the whole-program callback `unsafePerformIO main` plus the
  full context. IO is world passing: `PrimIO a = (1 w : %World) -> IORes a`.
- TTC (Idris's cache) drops runtime case trees and the types of
  machine-generated names. The per-module incremental callback sees fresh
  definitions before TTC is written.
- In `--check` mode, Idris exits non-zero only for errors that carry a
  source location.
- In MLIR 23.1.2: `func.call` cannot request a tail call, while `llvm.call`
  has `tail_call_kind` (`tail`/`musttail`/`notail`). `convert-to-llvm` covers
  arith, cf, func, index, math, memref, ptr, ub, vector, and complex. Generic
  passes include inline, sccp, remove-dead-values, symbol-dce, mem2reg, and
  sroa. No upstream dialect has ADTs, closures, thunks, or reference counting.
- **New and unverified in practice**: the pinned `mlir-opt` accepts
  `--irdl-file` (dialects defined in IRDL text at run time),
  `--transform-interpreter` and `--transform-preload-library` (transform
  dialect scripts), and has the `pdl`/`pdl_interp` dialects. It also offers
  `--load-dialect-plugin` and `--load-pass-plugin`.
- **Verified: text-only dialects are invisible to generic optimization.**
  With `--irdl-file` defining `idr.con : (i64) -> i64`, running
  `--canonicalize --cse --remove-dead-values` neither CSE'd two identical
  `idr.con` ops nor removed a dead one, while a dead `arith.addi` next to
  them was removed. IRDL ops have no traits or interfaces, so MLIR assumes
  unknown side effects.
- **C++ is not ruled out.** The user's position: if MLIR is genuinely better
  with C++ (dialects defined in ODS with traits and interfaces, folders and
  canonicalizers, `TypeConverter`-based dialect conversion, custom passes on
  the dataflow framework, loaded into our own `mlir-opt` or through
  `--load-dialect-plugin`), we should use it. The current "no C++" state is
  a default pending this research, not a principle. Compare, concretely:
  1. All optimization in our Idris IR, emitting upstream dialects only (the
     MLton, Lean, and tinygrad stance: one small IR we own).
  2. An Idris frontend emitting our own C++-defined MLIR dialect(s), where
     optimization uses MLIR's interfaces and passes (the "Lambda the Ultimate
     SSA" stance).
  3. A hybrid: which facts must survive into MLIR to be useful there?
  Include what each costs: build and toolchain weight, the maintenance of a
  second language, and the "parallel types" concern (a lower-level dialect
  does not mirror TT, but something must still stay in sync).
- `docs/research/whole-program-compilation.md` summarizes conventional
  practice (MLton, Lean 4, Perceus, CertiCoq, GRIN). Treat it as the baseline
  to challenge, not as a conclusion.

## 2. The goal

Figure out how this compiler should optimize from first principles, with
zero information loss between checked TT and machine code. The
compiler sees the whole program, QTT quantities (0/1/ω), dependent types
(index relationships, totality, erasure), explicit effects, and MLIR's
infrastructure. Tinygrad gets large wins from a tiny IR, one uniform
graph-rewrite mechanism, symbolic shapes, and search (BEAM) instead of
hand-tuned heuristics. Work out whether and how the same stance applies to a
general-purpose, dependently typed functional language.

Start from a cost model, not from compiler tradition. For a compiled Idris
program, where does runtime go (allocation, indirection, dispatch, closures,
boxing, reference counting or GC, proof/index residue, laziness, bignums,
missed fusion, missed vectorization)? For each cost, which statically
available fact removes it, and which mechanism exploits that fact
soundly?

## 3. Research threads (primary sources; read the papers and code)

A. **Tinygrad.** Read the source (github.com/tinygrad/tinygrad): `UOp`, `Ops`,
   `PatternMatcher`/`UPat`, `graph_rewrite`, scheduling and fusion, symbolic
   shapes, the linearizer and renderers, BEAM search, and the size of the
   whole thing. What exactly makes it work, and which parts depend on
   tensor programs being first-order dataflow over arrays?
B. **Equality saturation and rewriting as the optimizer.** egg (POPL 2021),
   egglog (PLDI 2023), slotted e-graphs (binders), e-graphs with
   lambdas and bindings, extraction (ILP, cost models), guided or
   sketch-guided equality saturation, the MLIR `eqsat` dialect work and
   DialEgg. Can one rewrite engine (e-graph or tinygrad-style) replace a
   hand-ordered pass pipeline for a functional IR with binders?
C. **Staging and partial evaluation with types.** Two-level type theory
   (Kovács, "Staged compilation with two-level type theory", ICFP 2022;
   "Closure-free functional programming in a two-level type theory", ICFP
   2024). Idris elaborator reflection as staging, supercompilation and
   deforestation, and Futamura projections in practice (Truffle/Graal). Can
   quantity 0 plus types give guaranteed specialization, and allocation- or
   closure-free code where the types permit it?
D. **Memory from QTT.** Linearity vs uniqueness (Marshall, Vollmer, Orchard,
   "Linearity and uniqueness: an entente cordiale", ESOP 2022; fractional
   uniqueness, OOPSLA 2024). Perceus (PLDI 2021), frame-limited reuse (ICFP
   2022), FP² fully in-place functional programming (ICFP 2023), OCaml
   modes ("Oxidizing OCaml", ICFP 2024), and Lean's "Counting Immutable
   Beans". What can Idris's quantity 1 soundly give us, and what extra
   analysis or annotation is needed for guaranteed in-place update and no GC?
E. **Using dependent types for representation.** Brady, McBride, McKinna,
   "Inductive families need not store their indices" (2003): forcing,
   detagging, collapsing. Tejiščák's erasure thesis (2020), the Idris 2 QTT
   paper (ECOOP 2021), and what upstream Idris already does
   (`detagabbleBy`, newtype and Nat optimizations). Can proofs such as bounds
   or `Fin n` justify unboxed machine integers, bounds-check removal,
   overflow-freedom, or layout, soundly and without believe_me?
F. **MLIR with and without C++.** Without C++: IRDL, PDL/PDLL, the
   transform dialect (Lücke et al., CGO 2025 and the MLIR docs), and
   bytecode. With C++: ODS dialects, interfaces, the dataflow framework,
   dialect conversion, and plugins. Read "Lambda the Ultimate SSA" (CGO
   2022: functional programs in SSA with regions, in C++ dialects), lean-mlir
   verified peephole rewriting (ITP 2024), and existing functional dialects
   (e.g. Lean's `lz`/`rgn`, any Haskell or OCaml MLIR work). **Run
   experiments**:
   - Extend the IRDL test above (constructors, a case op, lowering through
     PDL or transform scripts to `llvm`/`scf`).
   - Build a minimal C++ dialect as a plugin against the pinned LLVM, with
     one `Pure` constructor op and a canonicalizer, and show which generic
     passes it unlocks.
   Quantify what C++ buys and what it costs.
G. **Arrays and kernels with shape types.** Dex (index sets), Futhark
   (uniqueness, defunctionalization), Remora, Halide/TVM/Ansor/Exo
   (algorithm vs schedule, search), and tinygrad symbolic shapes compared
   with Idris indices. What must a Vect-like library or type carry for
   kernels to reach scf/memref/vector without guessing layout?
H. **Search and cost models.** BEAM and autotuning, superoptimization
   (Souper, STOKE), learned cost models, and e-graph extraction. Where is
   search worth it for general-purpose code, and where for kernels?
I. **Proved optimizations.** Idris can state and check equalities. Can
   rewrite rules carry proofs checked by Idris (versus the unchecked
   `%transform`)? Relate this to Alive2 and translation validation, CompCert,
   and CertiCoq.
J. **Bleeding edge, evaluated critically.** HVM2/Bend and interaction nets
   (optimal reduction, automatic parallelism), plus anything from 2024–2026
   that you find is relevant. Separate demonstrated results from claims.

## 4. Method

- Prefer primary sources: papers, source code, and official docs. Cite each
  claim with a link. Mark each claim as *read in full*, *from abstract*,
  or *from code*.
- Check claims about the pinned MLIR against the tree in
  `.toolchain/llvm-project/mlir` (build it with
  `python3 tools/dev.py bootstrap-llvm` if missing) and by running the tools.
- Reason from the cost model and the available facts. When conventional
  practice disagrees with first principles, say which you trust and why.
- Stay concrete about Idris: check each idea against what checked TT
  actually contains (`third_party/Idris2/src/Core/TT*`,
  `Core/Context/Context.idr`, `Core/Case/CaseTree.idr`).

## 5. Deliverables

1. `docs/research/first-principles-optimization.md`:
   - The cost model, and an inventory of the facts Idris gives us, each
     linked to the cost it removes.
   - For each thread, what exists, what is proven, what applies to us, and
     what does not.
   - The MLIR-without-C++ experiment results, with the actual inputs,
     commands, and outputs.
   - Two or three candidate architectures (IR shape, rewrite mechanism,
     memory model, what MLIR does and what Idris does), with trade-offs.
   - A small set of decisive experiments that choose between them, each
     with a measurable pass/fail criterion and benchmark programs, compared
     against the Idris Chez and RefC backends and hand-written C.
   - Open questions for the user.
2. A short chat summary: the recommendation, the evidence, and what remains
   uncertain.

Do not implement compiler changes. Commit the research document on a new
branch and push it. Do not merge to main.
