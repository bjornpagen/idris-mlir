# 0010: a state-of-the-art type checker and elaborator

**Status:** approved with the queue on 2026-10-14 (proposals index).
Written 2026-10-09; trimmed 2026-10-12, when the term arena and the
evaluator (once §2.1, §2.2, T1, T2 and T6) moved to 0007, which builds
them as one array program; decided throughout 2026-10-14. Nothing here
is built. This proposal builds the checker on 0007's arena and machine:
unification, tabled instance search, the rewrite ladder, the kernel,
parallel checking and, parked, certificates from solvers.

The tree it starts from (*measured*, HANDOFF.md, 0002): the cutover of
0002 is committed and builds on arm64 macOS, where `make test` was
415/415 at 7a27fd34, before the opt-in SCC pipeline that 0004's cutover
deletes. x86_64 Linux is NotRun. `make self` has never finished; 0004's
pipeline cutover is what it waits on. The fork's elaborator is
upstream's, and nothing of it has been measured on this tree.

**Where it sits** (*decision*). T0 is recorded at `make self` (0002 §2
step 5), because 0007's A0 and 0008's O0 are ratios to it, and A0
needs only `make self` (0007's status). T3 onward builds on 0007's A2
(the fork's checker on the machine), which in the queue follows
sharding's first stages (proposals index). T7 waits on 0005's shards
for its last step. T8 is parked with 0013.

**Goal.** The fork's elaborator (`compiler/idris`, upstream Idris 2's,
now our code) becomes a type checker that is faster than Lean 4 and F*
on measurable workloads, while implementing Idris 2 fully: the language
does not change (§2.0).

**Sources.** Under `sources/`, topic "Fast dependent type checking and
elaboration"; the reading notes are `sources/notes/type-checking/
elaborators.md` (cited as *elaborators §n*) and `kernels-trust.md`
(*kernels §n*). The fork is read in place.

**Leads, not mandates.** Array programming (0003), flattened data
(0009), a relational core (0012) and SMT were all candidates. This
proposal keeps what the evidence supports and says why for each.

**Claims** are marked: *read* (the path), *measured* (the record),
*recalled*, *conjecture*, *decision*.

## 1. Where the time goes today, and the first step

Nothing of the fork is measured on this tree. *Decision:* stage T0
measures before anything changes, and every target below is a ratio to
its record or to a named external benchmark.

- **What.** The per-phase profile of elaborating base, `libs/`, the
  fork and the frontend: parsing, desugaring, unification, normalisation
  and conversion, instance and auto search, coverage, totality, TTC
  write; with peak resident memory.
- **Where** (*decision*). On the native, self-compiled frontend at
  `make self`, on both targets, because that is the program the later
  stages change and the one 0007's interpreter is written for (0007 §1).
  The same profile on stage 0 (the fork on Chez) is recorded once beside
  it, to show what self-hosting bought; it is not a target.
- **How** (*decision*). The fork's own `logTime` phases
  (`compiler/idris/src/Core/Context/Log.idr:105-160`, *read*) through
  the driver's `--timing` (HANDOFF.md, the stage-0 recipe), and a
  sampling profile by the platform's sampler. No profiler enters the
  tree (0002 D8: profiling is LLVM's time trace through the pass
  manager, which serves the C++ side). The record is committed under
  `bench/profiles/`.

What is known without measuring (*read* through elaborators §11, at the
fork's 2026-10-09 head): values are call-by-name closures, re-evaluated on each
use (`Core/Value.idr:107-113`, `Core/Normalise/Eval.idr:223-226`);
"glued" pairs re-normalize on each `getNF` (`Eval.idr:20-35`);
conversion normalizes both sides before comparing heads
(`Core/Normalise/Convert.idr:430-432`); every unfolding looks its name up
(`Eval.idr:295-312`); postponed constraints are retried by rescanning
every guess (`Core/Unify.idr:1514-1522`); search backtracks with no table
(`Core/AutoSearch.idr:42-150`); and there is no whnf, conversion or
inference cache. Published, Idris 2 was the slowest system on smalltt's
elaboration benchmarks (stlc10k 129.6 s against smalltt's 0.306 s and
Lean's 12.98 s) and ran out of memory on ForceTree22 and 23 (*measured*
by smalltt's author in 2021, `code/smalltt/README.md:652-814`;
elaborators §10). On this tree the fork installs in about 75 s on Chez
(*measured*, HANDOFF.md, 2026-10-10).

## 2. The design, by layer

### 2.0 One language: conversion is upstream's, elaboration may be smarter

*Decision.* The kernel's theory is upstream Idris 2's: conversion, QTT,
erasure, totality and coverage keep their meaning. For every program
upstream accepts, every stage produces upstream's terms, up to the
names it generates (T7), proved by identical TTCs on base, `libs/`, the
fork and the frontend (§5).

*Decision.* The elaborator may succeed where upstream's fails only when
two things hold: what it produces is ordinary TT that the kernel accepts
under upstream's conversion, and the program asked for it (a `rewrite`,
a tactic call, an `auto` argument). It never inserts an equality proof
the program did not write. Reason: 0003 D11 keeps Idris's equality
unchanged because a definitional law changes conversion for every
program and accepts programs upstream refuses; a smarter `rewrite`
changes only how one construct the program wrote is elaborated, and its
output is checked by the one kernel (§2.6). The repository's own Idris
(the fork, the frontend, `libs/`) uses no such extension while stock
Idris builds stage 0 (0002 §2 step 6: Chez hosts stage 0).

Instance search keeps upstream's answers (§2.3).

### 2.1 Terms and evaluation are 0007's (adopted)

The checker's terms are 0007's hash-consed arena, and its evaluator is
0007's wavefront machine with glued values, caches by id and approximate
conversion first. The same machine normalizes the program's static part,
so types, proofs and constants have one evaluator. Coq's
`native_compute` (*read* `papers/gregoire-2002-strong-reduction`,
`papers/boespflug-2011-full-throttle`) is rejected (§5).

The caches follow the rule the Lean kernel states: cache only what is a
function of its key. Conversion results for closed, metavariable-free
terms are kept as success and failure pair sets, not a union-find,
because conversion is not transitive and a closure over successes would
make the answer depend on evaluation order (*read*, elaborators §4:
`code/lean4/src/kernel/type_checker.h:33-41`). Terms with metavariables
get a transient cache dropped when constraints were postponed during the
check (elaborators §4, Lean's elaborator). These caches are 0007's A2.

### 2.2 (moved: the evaluator is 0007's §4)

### 2.3 Unification and instance search (adopted)

- **Unification.** Dynamic pattern unification with postponement (*read*
  `papers/abel-2011-dynamic-pattern-unification`,
  `papers/gundry-2012-dynamic-pattern-unification`, `code/pattern-unify`),
  over the hash-consed terms. *Decision:* smalltt's bounded speculation
  (rigid, flex and full states; at most one backtrack on any path) and
  no approximate meta solutions (*read* `code/smalltt/README.md:327-397`,
  elaborators §5), because an approximate solution changes which
  programs mean what (§2.0; Agda keeps the approximation opt-in, as
  `--lossy-unification`, elaborators §5). Postponed constraints wake only on the
  metas they are blocked on, as a semi-naive delta, which replaces
  `solveConstraints`'s rescans; the store is 0008's O7. A comparison of
  meta-free terms is the kernel's conversion (§2.6): unification adds
  only meta solving, so conversion is written once.
- **Instance and auto search are tabled,** as in Lean 4 (*read*
  `papers/selsam-2020-tabled-typeclass`). A subgoal already in the table
  is answered from it, so a diamond is solved once. *Measured* there: on
  a failing tower of diamonds Lean 3, Coq, Agda and Scala pass 10 s by a
  height of about 10 to 17, while tabled Lean 4 stays near zero to
  height 100 (elaborators §6, machine not stated). Lean 3's mathlib had
  26,401 queries of at least 20 ms, 1,601 s in all (elaborators §2).
  Whether base's hierarchy is deep enough to matter is T0's to show.
- **Tabling never changes an answer** (*decision*). Candidates are tried
  in upstream's order and the first solution is upstream's. The bound is
  upstream's own: `%auto_implicit_depth`, default 50
  (`compiler/idris/src/Core/Options.idr:223`, *read*), counted down per
  nested search (`Core/AutoSearch.idr:103-105`) and read at
  `TTImp/Elab/App.idr:240`. A table entry records the depth its answer
  needed and is reused only where that much depth remains. Reasons: the
  answer is which implementation a program means, so a different answer
  is a different program (§2.0); and the bound is written in the
  program's source, so no compiler budget decides acceptance (0004
  §2.5). It counts, so it is deterministic. No wall clock bounds search:
  the fork's `searchTimeout` (`Core/Options.idr:141`, 1000 ms at `:217`)
  is set by `%search_timeout` and read by nothing since the REPL went
  (`compiler/idris/README.md`, "What was deleted"; *read*: its only
  other use is the setter, `Core/Context.idr:2232-2234`).
- Swift's type checker is the warning: overloads combined with
  constraint solving blow up without bounds (*read* `docs/swift`,
  `papers/benes-2025-simple-essence-of-overloading`). Idris elaborates
  every alternative of an ambiguous name under `catch`
  (`TTImp/Elab/Ambiguity.idr:390-450`, elaborators §11), bounded by
  upstream's `ambigLimit` (default 3, `Core/Options.idr:223`); that bound
  stays upstream's too.

### 2.4 Shape arithmetic and dependent rewrite

- **No polynomial normalisation of `Nat` in conversion** (*decision*).
  This proposal held it open, to be decided with its consequence stated;
  the consequence decides it. A commutative ring law made definitional
  accepts programs upstream refuses and changes conversion for every
  program, which §2.0 and 0003 D11 refuse. Shape arithmetic is 0003's
  library tactic, `Array.Shape.solve`, by elaborator reflection with its
  proof at quantity 0, under 1 s per obligation on the corpus's largest
  shape term (0003 §3.7; Frex is the precedent, under 1 s to size 30,
  *read* there). What this proposal owes the tactic is speed: it runs on
  0007's machine, and T4's proof includes it.
- **Rewrite,** in increasing order of reach:
  - Refl elimination when the rewritten side is a variable;
  - telescope generalisation when it is a term;
  - a search over which occurrences form the motive, with one bitmask per
    candidate, checked cheaply on hash-consed terms;
  - a diagnostic that names the blocking dependency when none fits.

  Upstream abstracts every occurrence of the normalised left side in the
  normalised goal, and fails when the predicate is ill-typed or the
  rewrite changes nothing (`TTImp/Elab/Rewrite.idr:74-102`, *read*). The
  first three rungs succeed where that fails; §2.0 admits them, because
  each elaborates to an ordinary `replace` or a match on `Refl` that the
  kernel checks. The diagnostic changes nothing that is accepted.
  *Read* `papers/mcbride-2000-elimination-motive`,
  `papers/cockx-2016-unifiers-as-equivalences`.

### 2.5 Decision procedures: search outside, checked inside (parked)

A solver never decides a proof. It searches, and the result becomes a term
the kernel checks.
- **Lean's `bv_decide` is the model:** a SAT solver produces an LRAT
  certificate, which a verified checker accepts (*read*
  `papers/cruzfilipe-2017-lrat`, `papers/pollitt-2023-lrat-cadical`,
  `docs/lean-reference-manual`).
- **SMT** with certificates in Alethe or cvc5's proof format,
  reconstructed into terms (*read* `papers/schurr-2021-alethe`,
  `papers/barbosa-2022-proof-production`, `papers/armand-2011-smtcoq`,
  `papers/blanchette-2016-hammering`).
- **F* trusts its solver; this design does not.** F*'s and Dafny's model
  (*read* `papers/swamy-2016-fstar-mumon`, `papers/leino-2010-dafny`) is
  rejected, because a solver's answer is not an Idris term, and trusting it
  would be a `believe_me` in the type checker. Mariposa's measurements of
  solver instability are a second reason (*read* `papers/zhou-2023-mariposa`);
  so are Meta-F*'s: SMT alone proved Poly1305's `poly_multiply` 0.5% of
  the time at the default limit and 24% at 100 times it, and 100% with a
  canonicalizing tactic first (*measured* there, elaborators §9).
- **What it is for** (*decision*). Tactics: an elaborator-reflection
  call whose search runs a solver and whose result is a term. Three uses
  this section once listed are not its: shape inequalities are 0003's
  library tactic with no solver beside the toolchain (0003 D11); bounds
  Presburger cannot decide served `idr-in-bounds`, which 0003's stage 1
  deletes (0004 §6); and verifying the `idr` dialect's rewrites at test
  time (Alive2-style, *read* `papers/lopes-2015-alive`) is a tool of the
  C++ side, not the checker's, and no proposal holds it.
- **How a solver is reached** (*decision*). The checker is Idris; it
  reaches a solver as a Rust crate through 0013's bindings, the one
  foreign world, and never through C, `%foreign` or a subprocess
  (AGENTS.md). MLIR's `smt` dialect and its SMT-LIB export exist in the
  pinned tree (*read*: `include/mlir/Dialect/SMT/IR`,
  `lib/Target/SMTLIB/ExportSMTLIB.cpp`) but are C++, so they are not this
  path. The solver is chosen when T8 starts, among those that emit a
  certificate the reconstruction reads (LRAT for SAT, Alethe or cvc5's
  format for SMT); it is pinned, built from source by the bootstrap,
  linked statically on both targets, and entered in 0001's inventory.
- **Determinism** (*decision*). A solver's limit is a counted resource
  given as an argument of the tactic call in the program's source, so
  whether a proof is found is a property of the program, never of an
  option or a clock. Certificates are cached by the query's content
  hash, so builds stay byte-identical.
- **Parked** (*decision*): T8 waits for 0013, which is parked, and for a
  consumer, which nothing in the queue is; it is taken up when a library
  or corpus proof names a goal family a solver decides and no tactic
  does.

### 2.6 A small kernel, and fast checking (adopted)

- **Kernel and elaborator separate,** by the de Bruijn criterion (*read*
  `papers/pollack-1998-believe-machine-checked-proof`). The kernel checks
  elaborated terms. Today the fork checks as it elaborates, with one
  conversion (`Core/Normalise/Convert.idr`); T5 separates checking the
  elaborated terms and keeps that one conversion.
- **One conversion** (*decision*). The kernel's conversion is the only
  definition of definitional equality; unification calls it on meta-free
  terms and adds only meta solving (§2.3). Lean implements conversion
  twice, in the kernel and in Meta, and the two drift (elaborators §5,
  §13); AGENTS.md's one-representation rule forbids that here.
- **No second checker** (*decision*). An independent re-checker, as
  lean4lean and nanoda are for Lean (*read* `code/lean4lean`,
  `code/nanoda_lib`, `papers/carneiro-2024-lean4lean`), is not built.
  Reason: it would hold every typing rule twice, each new case costing a
  branch in both, which AGENTS.md's one-representation rule forbids; and
  a test whose expected answer is another implementation's is the oracle
  AGENTS.md declines, where a test's committed expected files are its
  specification. The kernel's trust comes from being small and from tests that
  state each rule as a property: a seeded ill-typed term per rule,
  refused by name, as 0008's O8 states laws. "Re-checked in tests"
  (D4) means the kernel re-checks every TTC apart from elaboration.
- **Size and speed** (*decision*). Re-checking a library's TTCs with the
  kernel alone costs under 10% of elaborating it, on the same binary.
  Reason: a checker that does no search, no unification and no
  unfolding heuristics, and costs more than that, is doing
  elaboration's work. The bars that show how small checking can be
  (*measured*, kernels §2): Metamath
  Zero checks set.mm (590 kLOC, over 34,000 proofs) in 195 ± 5 ms against
  smm's 927 ± 28 ms on the same machine
  (`papers/carneiro-2020-metamath-zero`, `code/mm0`); Kontroli's kernel is
  663 lines against Dedukti's 3,470 and checks HOL Light's standard
  library in 219.9 s against 344.5 s (`papers/farber-2022-kontroli`,
  `papers/assaf-2016-dedukti`); lean4lean is 1.21 to 1.40 times slower
  than Lean's C++ kernel on Mathlib (`papers/carneiro-2024-lean4lean`,
  `main.tex:764-778`).

### 2.7 Parallelism (adopted where independent; GPU rejected for now)

- **What runs in parallel.**
  - Definitions whose signatures are known check independently.
  - Modules check in dependency order.
  - Both are maps over the module graph. Today the fork checks a
    package's modules one after another in one process
    (`Idris/ModTree.idr:243-252`, *read*). T7 runs them on processes
    first and on 0005's shards once they exist.
- **Names first** (*decision*). The fork names what it generates (metas,
  case and with blocks, variables) from one counter per module
  (`nextName`, `Core/UnifyState.idr:102, 160-200`), and that counter is
  saved in the TTC (`Core/Binary.idr:347`), *read*. Checking definitions
  in parallel would let the schedule reach names and TTC bytes. So T7
  first derives each generated name from its definition, never from a
  counter shared between definitions (0004 D18's rule). That change
  alters generated names by design, so it is proved by TTCs identical to
  the stage before's up to those names, before any parallelism lands.
- **The evidence** (*measured*, elaborators §8, kernels §2): Isabelle
  3.0 to 3.2 times on 4 cores, under 1.3 for the sequential HOL
  bootstrap (`papers/wenzel-2009-parallel-isabelle`); Coq's latency on
  the Odd Order Theorem from about an hour to 7 minutes on 12 cores with
  proofs deferred (`papers/barras-2015-async-coq`); Kontroli 6.6 times
  with 8 threads where commands are large and 1.4 to 1.5 where they are
  small, while parallel reduction lost to its own synchronization
  (`papers/farber-2022-kontroli`). Newton's parallel type checking is the
  structure (*read* `papers/newton-2016-parallel-type-checking`).
  Quantity-0 proofs are never needed at run time, which is Isabelle's
  "practical proof irrelevance", so checking them late and in parallel
  is open to this checker (*conjecture*, elaborators §12).
- **The array core is used where the work is regular:**
  - constraint generation over a flat syntax tree (0008);
  - size-change composition as a semiring matrix product over
    `Algebra/SizeChange.idr`'s `Smaller | Same | Unknown`, while the
    closure stays a relational fixpoint over the checker's
    `(f, h, graph)` triples, since summing them would merge call paths
    that must stay apart (`Core/Termination/SizeChange.idr:78, 142-180`,
    *read*; 0008 §4.7);
  - batched conversion of hash-consed terms (0007).
- **The relational core** (0012, parked until its first consumer): the
  constraint store and postponement as semi-naive evaluation are 0008's
  O7 on it. E-graph saturation over equalities is offered to tactics
  and returns a proof term the kernel checks; it never extends
  conversion (§2.0). The library is 0012's and is not duplicated here
  (*read* `papers/jordan-2016-souffle`, `papers/madsen-2016-datalog-to-flix`,
  `papers/bembenek-2020-formulog`).
- **Rejected for now: GPU type checking and interaction-net normalisation.**
  The evidence is research-grade: the GPU front ends in Voetter's thesis
  (*read* `papers/voetter-2021-gpu-frontend-thesis`), HVM2 (*read*
  `papers/taelin-2024-hvm2`), and parallel interaction nets (*read*
  `papers/mackie-2016-parallel-interaction-nets`). Revisit when a measured
  case shows elaboration bound by normalisation that the CPU paths cannot
  serve.

## 3. Rules it keeps

- **Idris 2, fully, and one language** (§2.0). QTT, erasure, totality,
  interfaces, auto search and elaborator reflection keep their meaning
  for programs over the upstream prelude and base. The frontend still
  consumes checked TT, with its representation now flat.
- **No trusted oracle and no escape hatch** in the checker: no solver is
  trusted, and no second checker stands in for the kernel's tests.
- **Deterministic, byte-identical outputs** at every worker and shard
  count, with no name taken from a counter shared between definitions
  (0004's determinism rules).
- **No option selects behaviour** (0004 D2); a stage is measured old
  binary against new from the same inputs (0004 §10).
- **Whole-program compilation,** and both targets.

## 4. Staged plan, each stage with its proof

| Stage | Content | Proof |
| --- | --- | --- |
| T0 | per-phase baseline of elaborating base, `libs/`, the fork and the frontend, natively at `make self`, on both targets; stage 0 on Chez once beside it | committed record under `bench/profiles/`; the baseline of 0007's A0 and 0008's O0 |
| T1, T2 | (moved: the arena and the evaluator are 0007's A0 to A2) | |
| T3 | tabled instance search with upstream's answers and depth bound | identical TTCs; instance-heavy files ≥ 2× over 0007's A2; no file slower |
| T4 | the rewrite ladder (§2.4; no `Nat` normalisation) | upstream's rewrite failures listed in tests become passes; 0003's shape-equality corpus elaborates with the library tactic within 0003's 1 s per obligation; identical TTCs where upstream succeeds |
| T5 | the kernel apart from elaboration, holding the one conversion | every TTC of base, `libs/`, the fork and the frontend re-checked by the kernel alone in under 10% of elaborating them on the same binary; a seeded ill-typed term per typing rule refused by name |
| T6 | (moved: the interpreter's array path is 0007's A4) | |
| T7 | parallel elaboration: names per definition, then processes, then 0005's shards | TTCs identical to T5's up to generated names, and identical at 1, 2 and 8 workers; wall time on base ≤ 1.5 / cores of T5's |
| T8 | certificates from SAT/SMT, checked as terms; parked with 0013 (§2.5) | a fixture where the search succeeds and the kernel checks the result |

The headline target, *conjecture until measured*: faster elaboration
than Lean 4, judged first on smalltt's benchmark files translated to
Idris (`code/smalltt/bench`, *read*; elaborators §12), run against
Lean 4 and F* on the same machine on both targets, because they exist
and are comparable; then on base and the frontend, the largest Idris
corpus there is. The limits of that evidence are elaborators §14's:
smalltt's numbers are from 2021 and its language has no inductive types.

## 5. Rejected alternatives

- **Trusting a solver (F*, Dafny):** see §2.5.
- **A solver reached through MLIR's `smt` dialect, C or a subprocess:**
  C interop and process creation are outside the language (AGENTS.md);
  §2.5.
- **Definitional arithmetic in conversion:** §2.4, 0003 D11.
- **A wall-clock search timeout:** the answer would depend on the
  machine; §2.3.
- **An independent second checker:** §2.6.
- **GPU type checking, now:** see §2.7.
- **Rewriting the elaborator from scratch:** it would break Idris 2
  compatibility and lose the corpus proofs. The fork is changed stage by
  stage, each stage proved by identical TTCs.
- **Compiled reduction** (Coq's `native_compute`, a JIT inside the type
  checker): a second compiler inside the first. 0007's array machine is
  the answer to heavy evaluation (its D3).

## 6. Decisions

- D1. Measure first (T0, natively at `make self`); every target is a
  ratio to a recorded baseline.
- D2. The term arena and the evaluator are 0007's; this proposal builds
  the checker on them and keeps no second evaluator.
- D3. Solvers search; the kernel checks; nothing is trusted.
- D4. A separate small kernel, which re-checks every TTC apart from
  elaboration; no independent second checker (§2.6).
- D5. Parallelism by independent definitions and modules, after names
  stop coming from a shared counter; GPU deferred until measured.
- D6. The relational core is proposal 0012's library, not a copy here.
- D7. One language: conversion is upstream's; the elaborator may succeed
  where upstream's fails only with ordinary TT the program asked for
  (§2.0).
- D8. Tabled search keeps upstream's answers, candidate order and
  `%auto_implicit_depth` bound; no wall clock (§2.3).
- D9. No `Nat` normalisation in conversion (§2.4).
- D10. The kernel's conversion is the only conversion; unification calls
  it (§2.6).
- D11. T8 is parked with 0013; a solver is a Rust crate, its limit an
  argument in the program's source (§2.5).

No question is open. The one this file held (§2.4) is D9.
