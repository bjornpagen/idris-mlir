<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0010: a state-of-the-art type checker and elaborator

**Status:** approved with the queue on 2026-10-14 (proposals index).
Written 2026-10-09; trimmed 2026-10-12, when the term arena and the
evaluator (once §2.1, §2.2, T1, T2 and T6) moved to 0007, which builds
them as one array program; decided throughout 2026-10-14, and its fork
citations re-read against the tree at ccaba89c the same day. Nothing
here is built. This proposal builds the checker on 0007's arena and
machine: tabled instance search, the rewrite ladder, the kernel,
parallel checking and, parked, certificates from solvers.

The tree it starts from (*measured*, HANDOFF.md, 0002): the cutover of
0002 is committed and builds on arm64 macOS, where `make test` was
415/415 at 7a27fd34, before the opt-in SCC pipeline that the pipeline
cutover (c7aa7b62, 5d5f3312; its proposal at 484d6403) deleted. x86_64
Linux is NotRun. `make self` has never finished; it waits on the
qualification of the cutover and the representation wave (bfdcac70; its
proposal at 484d6403), coded and integrated but not yet built, which the
owner's machine runs after 0004, integrated typecheck-only
(proposals/README.md). The fork's elaborator is upstream's, and nothing
of it has been measured on this tree.

**Where it sits** (*decision*). T0 is recorded at `make self` (0002 §2
step 5), on the commit 0008's O0 measures, as one record: 0007's A0 is
a ratio to T0's elaboration figure, 0008's O0 takes that figure from
it, and 0007 decides its TTC format on T0's share of TTC loading (0007
§3). A0 needs only `make self` (0007's status). T3 onward builds on
0007's A2 (the fork's checker on the machine), which in the queue
follows sharding's first stages (proposals index). T7 runs definitions on
0005's shards once that framework exists (0006 §12, the owner's
decision); until then elaboration is single-threaded. T8 is parked with 0013.

**Goal.** The fork's elaborator (`compiler/idris`, upstream Idris 2's,
now our code) becomes a type checker that is faster than Lean 4 and F*
on measurable workloads (§4), while implementing Idris 2 fully: the
language does not change (§2.0).

**Sources.** Under `sources/`, topic "Fast dependent type checking and
elaboration"; the reading notes are `sources/notes/type-checking/
elaborators.md` (cited as *elaborators §n*) and `kernels-trust.md`
(*kernels §n*). The fork is read in place. smalltt's README, which the
notes read at `ea99b0f4`, is listed in `code/smalltt/SNAPSHOT.md` but is
not in the tree; its numbers are cited through elaborators §5 and §10,
and smalltt's sources (`code/smalltt/src`, `code/smalltt/bench`) are
read directly.

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
  fork and the frontend: parsing, reading imports (TTC load),
  declarations (unification, normalisation and conversion, instance and
  auto search), coverage, totality, TTC write; with peak resident
  memory.
- **Where** (*decision*). On the native, self-compiled frontend at
  `make self`, on both targets, because that is the program the later
  stages change and the one 0007's interpreter is written for (0007 §1).
  The same profile on stage 0 (the fork on Chez) is recorded once beside
  it, to show what self-hosting bought; it is not a target.
- **How** (*decision*). Two sources, both already in the tree, and no
  profiler enters it (profiling is LLVM's time trace through
  the pass manager, `tests/spec/time-trace`, which serves the C++ side).
  - The fork's own `logTime` phases (`compiler/idris/src/Core/Context/
    Log.idr:105-213`, *read*): per module, parsing, reading imports,
    declarations, totality and elaboration (`Idris/ProcessIdr.idr:286,
    322, 330-332, 361`), and per definition its right-hand side, case
    tree, size-change graphs, coverage and termination
    (`TTImp/ProcessDef.idr:426, 930, 964, 973`;
    `TTImp/ProcessDecls/Totality.idr:46`). They print only when the
    session's `logTimings` is set (`Core/Options.idr:151`, read at
    `Log.idr:213`), which today only the fork's stock command line sets
    (`Idris/CommandLine.idr:239`, `Idris/SetOptions.idr:328-329`); the
    frontend's driver never does. Its `--timing FILE` records only the
    frontend's own phases (checks, reachable, translate, print, write:
    `compiler/src/IdrisMLIR/Frontend/Program.idr:85-90, 190-199`), and
    only for a program, not for the package commands that elaborate base
    (`Frontend/Driver.idr:17-21, 188`). T0's first change gives
    `--timing FILE` to the package commands too and, given it, sets the
    fork's level to 1 and writes the fork's phase lines into that file
    in the driver's `phase<TAB>ms` form, so one file holds every phase
    of a run. `logTime` reads process CPU time (`Log.idr:131-137`); the
    record also keeps the wall time of the run.
  - A sampling profile by the platform's own sampler, which splits
    declarations into unification (`Core/Unify.idr`), normalisation and
    conversion (`Core/Normalise/`) and search (`Core/AutoSearch.idr`),
    since `logTime` brackets none of them.
  The record is committed under `bench/profiles/`.

What is known without measuring (*read* through elaborators §11, at the
fork's 2026-10-09 head, and re-read in the tree): values are call-by-name
closures, re-evaluated on each use (`Core/Value.idr:121-127`,
`Core/Normalise/Eval.idr:225-228`); "glued" pairs re-normalize on each
`getNF` (`Eval.idr:20-37`); conversion normalizes both sides before
comparing heads (`Core/Normalise/Convert.idr:432-434`); every unfolding
looks its name up (`Eval.idr:297-312`); postponed constraints are
retried by rescanning every guess (`Core/Unify.idr:1516-1523`); search
backtracks with no table (`Core/AutoSearch.idr:44-192`); and there is no
whnf, conversion or inference cache. Published, Idris 2 was the slowest
system on smalltt's elaboration benchmarks (stlc10k 129.6 s against
smalltt's 0.306 s and Lean's 12.98 s) and ran out of memory on
ForceTree22 and 23 (*measured* by smalltt's author in 2021 on an Intel
1165G7, Idris 2 with its PR 2203; through elaborators §10). On this tree
the fork installs in about 75 s on Chez (*measured*, HANDOFF.md,
2026-10-10).

## 2. The design, by layer

### 2.0 One language: conversion is upstream's, elaboration may be smarter

*Decision.* The kernel's theory is upstream Idris 2's: conversion, QTT,
erasure, totality and coverage keep their meaning. For every program
upstream accepts, every stage produces upstream's terms, up to the
names it generates (T7), proved by identical TTCs on base, `libs/`, the
fork and the frontend (§4).

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

Instance search and unification keep upstream's answers (§2.3).

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
check (elaborators §4, Lean's elaborator). These caches are 0007's A2
(its D12).

### 2.2 (moved: the evaluator is 0007's §4)

### 2.3 Unification and instance search (adopted)

- **Unification is upstream's** (*decision*). Dynamic pattern
  unification with postponement (*read*
  `papers/abel-2011-dynamic-pattern-unification`,
  `papers/gundry-2012-dynamic-pattern-unification`, `code/pattern-unify`)
  is what the fork already does, and it keeps its solutions, its
  approximations included: during search and on a left-hand side it
  unifies the spines of two applications of one meta or one name
  (`Core/Unify.idr:976-990, 1019-1031`, *read*), an approximate solution
  of the kind Lean and Coq make and smalltt and Agda refuse (elaborators
  §5; Agda keeps it opt-in, as `--lossy-unification`). Removing upstream's
  would refuse programs upstream accepts, and adding Lean's would accept
  programs it refuses; either changes which programs mean what (§2.0). A
  comparison with no meta in it is already the conversion's: unification
  calls `convert` (`Core/Unify.idr:785, 941-947, 1205, 1248-1267, 1322`),
  so conversion is written once and the kernel keeps it (§2.6).
- **Where unification's speed comes from** (*decision*): no stage here
  changes it. It evaluates on 0007's machine from A1. Its round trips
  through a definition-free context (`clearDefs`, eighteen sites in
  `Core/Unify.idr` between `:178` and `:1659`), which try a comparison
  without unfolding and then with it, are the unbounded form of smalltt's
  rigid, flex and full states (elaborators §11); they become 0007's A2,
  glued values and approximate conversion, which is smalltt's bounded
  speculation: no meta solution in the flex state, at most one backtrack
  on any path (*read* `code/smalltt/src/Common.hs:187-193`,
  `src/Unification.hs:321-382`, its flex guard at `:333`). A solution
  keeps upstream's form, so TTCs stay identical. Postponed constraints
  wake only on the metas they are blocked on, as a semi-naive delta,
  which replaces `solveConstraints`'s rescans (`Core/Unify.idr:1516-1523`);
  that store is 0008's O7.
- **Instance and auto search are tabled,** as in Lean 4 (*read*
  `papers/selsam-2020-tabled-typeclass`). A subgoal already answered is
  answered from the table, so a diamond is solved once. *Measured* there:
  on a failing tower of diamonds Lean 3, Coq, Agda and Scala pass 10 s
  by a height of about 10 to 17, while tabled Lean 4 stays near zero to
  height 100 (elaborators §6, machine not stated). Lean 3's mathlib had
  26,401 queries of at least 20 ms, 1,601 s in all (elaborators §2).
  Whether base's hierarchy is deep enough to matter is T0's to show.
- **What upstream's search answers** (*read*, `Core/AutoSearch.idr`). A
  goal tries the local variables first, then each hint group in order
  (`searchType`, `:528-566`). A group whose names may overlap takes the
  first candidate that succeeds (`anyOne`, `:155-168`); any other tries
  every candidate and needs exactly one success, else the search is
  ambiguous (`exactlyOne`, `:170-192`). A candidate's arguments are
  searched right to left, each committing to its one answer
  (`searchName`, `:384-410`; `searchIfHole`, `:105-130`), so nothing
  backtracks into a solved subgoal. A goal already on the search's stack
  is abandoned (`abandonIfCycle`, `:508-517`). The depth counts down per
  nested search (`:103-105`) from `%auto_implicit_depth`, default 50
  (`Core/Options.idr:223`), read at `TTImp/Elab/App.idr:240`. A
  subgoal's answer is therefore a function of the goal, its local
  environment, the visible hints, the defaults flag (`tryNoDefaultsFirst`,
  `:36-39`), the remaining depth and the stack above it.
- **Tabling never changes an answer** (*decision*). Upstream's candidate
  order, ambiguity rule and depth bound stay. The table keys a goal by
  its term and its environment, both ids of 0007's arena, with the
  defaults flag, and holds an answer, or a failure, only where it is a
  function of that key: the goal has no unsolved meta, no branch of its
  search was abandoned against a goal above it on the stack, and none
  was cut by the depth bound. An entry records the depth its search used
  and is reused where at least that much remains. A goal whose search
  met either cut is searched afresh. The table is emptied when a hint is
  added or the namespace changes, since either changes the visible
  hints. Failures tabled under the same rule are what make a failing
  tower of diamonds linear in its height. Two things are not taken.
  Selsam's consumers, which resume a suspended goal on a cycle: they
  answer goals upstream abandons, which accepts programs upstream
  refuses (§2.0). And 0012's relational core: the answers are ordered
  and the ambiguity rule counts them, which a set-valued fixpoint does
  not express. Reasons for the rule: the answer is which implementation
  a program means, so a different answer is a different program (§2.0);
  the bound is the language's, a program sets it with
  `%auto_implicit_depth`, so no compiler budget decides acceptance (the
  cutover's §2.5); and it counts, so it is deterministic.
- **No wall clock bounds search** (*decision*). The fork's
  `searchTimeout` (`Core/Options.idr:141`, 1000 ms at `:217`) is set by
  `%search_timeout` and read by nothing since the REPL went
  (`compiler/idris/README.md`, "What was deleted"; *read*: its only
  other use is the setter, `Core/Context.idr:2232-2234`).
- Swift's type checker is the warning: overloads combined with
  constraint solving blow up without bounds (*read* `docs/swift`,
  `papers/benes-2025-simple-essence-of-overloading`). Idris elaborates
  every alternative of an ambiguous name under `catch`
  (`TTImp/Elab/Ambiguity.idr:411-462`, through `anyOne` and
  `exactlyOne'`, `TTImp/Elab/Check.idr:611-690`; elaborators §11),
  bounded by upstream's `ambigLimit` (default 3, `Core/Options.idr:223`,
  read at `Ambiguity.idr:330`); that bound stays upstream's too.

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
  deleted (the cutover's §6); and verifying the `idr` dialect's rewrites
  at test time (Alive2-style, *read* `papers/lopes-2015-alive`) is a
  tool of the C++ side, not the checker's, and no proposal holds it.
- **How a solver is reached** (*decision*). The checker is Idris; it
  reaches a solver as a Rust crate through 0013's bindings, the one
  foreign world, and never through C, `%foreign` or a subprocess
  (AGENTS.md). MLIR's `smt` dialect and its SMT-LIB export exist in the
  pinned tree (*read*: `include/mlir/Dialect/SMT/IR`,
  `lib/Target/SMTLIB/ExportSMTLIB.cpp`) but are C++, so they are not
  this path. The solver is chosen when T8 starts, among those that emit
  a certificate the reconstruction reads (LRAT for SAT, Alethe or cvc5's
  format for SMT); it is pinned, built from source by the bootstrap,
  linked statically on both targets, and entered in
  `LICENSES/THIRD-PARTY.md`, the inventory.
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
  terms, as it does today, and adds only meta solving (§2.3). Lean
  implements conversion twice, in the kernel and in Meta, and the two
  drift (elaborators §5, §13); AGENTS.md's one-representation rule
  forbids that here.
- **One termination closure** (*decision*). The fork closes size-change
  graphs twice. The checker's `calcTerminating` closes `(f, g, graph)`
  triples transitively within each component (`Core/Termination/
  SizeChange.idr:77-85, 185-207`, used at `:565`), and the frontend's
  loop verdict reads `loopsTerminate`, which keeps per function only the
  weakest graphs of the walks to it (`:486-580`, called from
  `compiler/src/IdrisMLIR/Frontend/Translate/Recursion.idr:122`),
  *read*. Both decide whether every loop through a function decreases,
  which is one analysis held twice. The checker's goes, and
  `loopsTerminate` carries the call path the checker's message names
  (`:565-574`). That is 0008's O6, which already rewrites the
  composition and proves identical totality verdicts; this proposal adds
  no stage for it.
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

- **What runs in parallel** (*decision*, the owner's, 0006 §12). The
  fork is the compiler's Idris half, and the compiler's Idris half runs
  on 0005's thread-per-core shards, with linear messages, once that typed
  shard framework exists; until then elaboration is single-threaded.
  Stage 0 runs the fork on Chez, where a shard primitive has no meaning
  (0005 D13), so stage 0 stays single-threaded for good.
  - Modules check in dependency order as shard work. The fork already
    builds each module from a cleared context that holds only its imports
    (`buildMod`, `Idris/ModTree.idr:203-204`, a fresh unification state
    at `:223`), and today checks a package's modules one after another in
    one process (`buildMods`, `:243-252`), *read*.
  - Definitions whose signatures are known check independently, as
    shard work, once generated names come from content (below).
- **Who starts what** (*decision*). Nothing starts a process or a thread
  but the runtime's shards: process creation is outside the language
  (the `Process` rule, `foreign/idr/include/idr/IR/IdrBase.td:199`,
  `OutsideLanguage`; AGENTS.md), and so are threads (`Threads`, `:187`),
  which is why elaboration waits for 0005's
  shards, one single-threaded runtime per core, rather than run on
  threads of one process or on processes the C++ driver starts. The
  driver still runs the frontend as one child
  (`foreign/idr/lib/Driver/Compile.cpp:50`, `llvm::sys::ExecuteAndWait`).
- **Names** (*decision*). The fork names what it generates (metas, case
  and with blocks, variables) from one counter (`nextName`,
  `Core/UnifyState.idr:102, 160-200`), saved in the TTC
  (`Core/Binary.idr:347`), *read*. The counter restarts for each module
  (`resetNextVar`, `Idris/ProcessIdr.idr:310`) and then takes the value
  its last import saved (`Core/Binary.idr:545`), so a module's names are
  a function of its inputs and modules checked in parallel leave TTCs
  byte for byte as they are. Definitions checked in parallel inside one
  module would let the schedule reach names and TTC bytes. So T7, before
  its shard step, derives each generated name from its definition, never
  from a counter shared between definitions, before definitions run in
  parallel: the rule of the cutover's §1, names from content and never
  from counters, which holds in the fork as in the pipeline (the
  cutover's D18). That change alters generated names by design, so it is
  proved by TTCs identical to the stage before's up to those names.
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
    `Algebra/SizeChange.idr`'s `Smaller | Same | Unknown` (`:10`), while
    the closure stays a relational fixpoint with subsumption over walks,
    since summing graphs would merge walks whose verdicts differ (§2.6;
    0008 §4.7);
  - batched conversion of hash-consed terms (0007).
- **The relational core** (0012, parked until its first consumer): the
  constraint store and postponement as semi-naive evaluation are 0008's
  O7 on it. E-graph saturation over equalities is offered to tactics
  and returns a proof term the kernel checks; it never extends
  conversion (§2.0). The library is 0012's and is not duplicated here
  (*read* `papers/jordan-2016-souffle`, `papers/madsen-2016-datalog-to-flix`,
  `papers/bembenek-2020-formulog`). Tabled search is not on it (§2.3).
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
  (the cutover's determinism rules).
- **No option selects behaviour** (the cutover's D2); a stage is
  measured old binary against new from the same inputs (the cutover's
  §10). `--timing` writes a record and selects nothing.
- **No process or thread in Idris code** (AGENTS.md); parallelism is
  0005's shards (§2.7).
- **Whole-program compilation,** and both targets.

## 4. Staged plan, each stage with its proof

| Stage | Content | Proof |
| --- | --- | --- |
| T0 | per-phase baseline of elaborating base, `libs/`, the fork and the frontend, natively at `make self`, on both targets; stage 0 on Chez once beside it; the fork's `logTime` phases written through the driver's `--timing`, which the package commands take too (§1); the headline workloads below run once against Lean 4 and F* | committed record under `bench/profiles/`, one with 0008's O0; the baseline of 0007's A0 |
| T1, T2 | (moved: the arena and the evaluator are 0007's A0 to A2) | |
| T3 | tabled instance search with upstream's answers, ambiguity rule and depth bound, under §2.3's reuse rule | identical TTCs; instance-heavy files ≥ 2× over 0007's A2; a failing diamond tower elaborates in time linear in its height; no file slower by more than 5%, best of five (the compile-time margin of the cutover's §10) |
| T4 | the rewrite ladder (§2.4; no `Nat` normalisation) | upstream's rewrite failures listed in tests become passes; 0003's shape-equality corpus elaborates with the library tactic within 0003's 1 s per obligation; identical TTCs where upstream succeeds |
| T5 | the kernel apart from elaboration, holding the one conversion | every TTC of base, `libs/`, the fork and the frontend re-checked by the kernel alone in under 10% of elaborating them on the same binary; a seeded ill-typed term per typing rule refused by name |
| T6 | (moved: the interpreter's array path is 0007's A4) | |
| T7 | parallel elaboration: names derived per definition, then definitions on 0005's shards once they exist (0006 §12, the owner's decision); single-threaded until then | names: TTCs identical to T5's up to generated names; shards: TTCs identical at 1, 2 and 8 shards, wall time on base ≤ 1.5 / cores of T5's |
| T8 | certificates from SAT/SMT, checked as terms; parked with 0013 (§2.5) | a fixture where the search succeeds and the kernel checks the result |

The order within T7 is a *decision*: generated names are derived from
content first (§2.7, "Names"), proved by TTCs identical up to those
names, so the shard step that follows cannot let the schedule reach
names or TTC bytes; the shard step lands when 0005's typed shards
exist, by the owner's decision (0006 §12).

The headline target, *conjecture until measured*: faster elaboration
than Lean 4 and F*, on the same machine on both targets, first on
smalltt's benchmark set and then on base and the frontend, the largest
Idris corpus there is. *Decision* on the workloads (*read*
`code/smalltt/SNAPSHOT.md`, `code/smalltt/bench`): the conversion and
evaluation file exists in smalltt's own Idris 2 and Lean 4 versions
(`bench/conv_eval.idr`, `bench/conv_eval.lean`, beside Coq's `.v`), and
`asymptotics.stt` and `stlc_small.stt` are translated to Idris and Lean
at T0; the generated elaboration files (stlc5k, 10k and 100k) come from
smalltt's generator at the snapshot's revision, which was not stored, so
T0 stores it with the files it writes. smalltt has no F* version of any
file, so T0 writes `conv_eval` for F* and commits it with the record.
Lean 4 and F* are measuring instruments, as the bench's C compiler is:
pinned releases fetched under `.toolchain/` by a step of
`tools/bootstrap.sh` through its locked-release fetch (each release's
SHA-256 in the lock, `tools/bootstrap.sh:751`), as AGENTS.md installs
everything under `.toolchain/` through `make bootstrap`, recorded in
PINS.md, run by the bench and never linked (*decision*; `bench/run.sh`
fetches nothing today, *read*). They are not built or shipped by us, so
the static-linking rule, which covers what we build and link, does not
bind them; T0 adds the step. The limits of that
evidence are elaborators §14's: smalltt's numbers are from 2021 and its
language has no inductive types.

## 5. Rejected alternatives

- **Trusting a solver (F*, Dafny):** see §2.5.
- **A solver reached through MLIR's `smt` dialect, C or a subprocess:**
  C interop and process creation are outside the language (AGENTS.md);
  §2.5.
- **Definitional arithmetic in conversion:** §2.4, 0003 D11.
- **Approximate meta solutions beyond upstream's, or fewer than
  upstream's:** either changes which programs are accepted; §2.3.
- **Selsam's full tabled resolution, with consumers resumed on cycles:**
  it answers goals upstream abandons; §2.3.
- **A wall-clock search timeout:** the answer would depend on the
  machine; §2.3.
- **An independent second checker:** §2.6.
- **Threads in the frontend for parallel checking:** outside the
  language; §2.7.
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
- D5. Parallelism on 0005's shards, by the owner's decision (0006 §12):
  modules, then definitions once names stop coming from a counter shared
  between definitions; single-threaded until the shard framework exists,
  and at stage 0 for good; no process or thread in Idris code; GPU
  deferred until measured (§2.7).
- D6. The relational core is proposal 0012's library, not a copy here;
  tabled search does not use it (§2.3).
- D7. One language: conversion is upstream's; the elaborator may succeed
  where upstream's fails only with ordinary TT the program asked for
  (§2.0).
- D8. Tabled search keeps upstream's answers, candidate order, ambiguity
  rule and `%auto_implicit_depth` bound; an entry is reused only where
  its answer is a function of its key, with no cycle or depth cut and no
  unsolved meta; no wall clock (§2.3).
- D9. No `Nat` normalisation in conversion (§2.4).
- D10. The kernel's conversion is the only conversion; unification calls
  it (§2.6).
- D11. T8 is parked with 0013; a solver is a Rust crate, its limit an
  argument in the program's source (§2.5).
- D12. Unification keeps upstream's solutions, its approximations
  included; its speed is 0007's A1 and A2 and 0008's O7, and no stage
  here changes it (§2.3).
- D13. One termination closure, `loopsTerminate` carrying the call path,
  built as 0008's O6 (§2.6).
- D14. T0 reads the fork's `logTime` through the driver's `--timing`
  and splits declarations by sampling; no profiler enters the tree (§1).
- D15. The headline is judged on smalltt's set, translated where no
  Idris or F* version exists, against pinned Lean 4 and F* releases (§4).

No question is open here. The one this file held (§2.4) is D9; T7's
shard step waits on 0006 §12, whose owner question it shares.
