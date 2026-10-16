<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0012: a state-of-the-art type checker and elaborator

**Status:** decided 2026-10-14. On 2026-10-15 it was cut to what remains,
and its fork citations were re-read at b843d8b5 while 0001's wave was in
progress. Nothing is built except T0's first piece of plumbing (§4).
Every stage is **AFTER-SELF**. None is on `make self`'s path, and T0
measures the self-compiled frontend, so it can only follow stage 1.
Where the tree stands is for `proposals/README.md` and HANDOFF.md to say;
this file does not repeat it.

**Goal.** The fork's elaborator (`compiler/idris`) becomes a type checker
that is faster than Lean 4 and F* on measurable workloads (D15) and checks
the same language (D7). It builds on 0009's arena and machine and adds
tabled instance search (T3), the rewrite ladder (T4), a separate kernel
(T5), parallel checking (T7) and, parked, certificates from solvers (T8).

**Where it sits** (*decision*). T0 is recorded at `make self`, on the
commit that 0010's O0 measures, and the two are one record. 0009's A0 is
a ratio to T0's elaboration figure, and 0009 §3 decides its TTC format
from T0's share of TTC loading. T3 onward builds on 0009's A2, which
follows sharding's first stages. T7's shard step waits on 0006's shards
and their plain-Idris layer (§2.7). T8 is parked with 0015. D1: measure
first. Every target is a ratio to T0's record or to a named external
benchmark.

**Sources.** The reading notes are `sources/notes/type-checking/elaborators.md`
(cited as *elaborators §n*) and `kernels-trust.md` (*kernels §n*).
smalltt's sources are under `sources/code/smalltt`; its README, which the
notes read at ea99b0f4, is listed in `SNAPSHOT.md` but not stored. The fork
is read in place.

## 1. The fork it starts from, and T0

The fork is no longer upstream's elaborator unchanged (*read*, 0002 §3.4 at b843d8b5):
- 0002 took out its fuel: `EvalOpts`' fuel and reduce limit,
  `computesType`'s depth, and `%totality_depth`, which is now a parse
  error, with `sizeCompare` memoised by subterm path.
- 0002 made `loopsTerminate` total over `Dense n from to` graphs, and made
  the operations the frontend calls total.
- Four elaborator bugs are fixed as fork code (`upstream/fork-*`, PINS.md).

So the fork accepts some programs the pin refuses: a recursion that
decreases deeper down, a linear `let` over an ambiguous name, and a with
application in a local block. It also refuses two forms the pin accepts:
`%totality_depth`, and a non-method declaration in an interface body,
which the pin silently dropped.

What the frontend trusts in the fork is the `Host` record: the evaluator,
the elaborator and `checkTerminating`. That record is moving from
`IdrisMLIR.Frontend.Host` into the fork as `compiler/idris/src/Idris/Host.idr`
(0001's lane I, in progress).

**Where the time goes, known without measuring** (elaborators §11, re-read
here):
- Values are call-by-name closures, re-evaluated on each use
  (`Core/Value.idr`'s `Closure`, `Core/Normalise/Eval.idr`'s
  `evalLocClosure`).
- A glued pair re-normalizes on each `getNF`.
- Conversion normalizes both sides before it compares heads
  (`Core/Normalise/Convert.idr`, `Convert Term`).
- Every unfolding looks its name up (`evalRef`).
- Postponed constraints are retried by rescanning every guess
  (`Core/Unify.idr`, `solveConstraints`).
- Search backtracks with no table (`Core/AutoSearch.idr`).
- Nothing caches weak head normal forms, conversion or inference.

In published measurements, Idris 2 was the slowest system on smalltt's
benchmarks: stlc10k took 129.6 s, against smalltt's 0.306 s and Lean's
12.98 s (*measured* by smalltt's author in 2021, elaborators §10).

**T0 measures before anything changes** (*decision*).
- **What.** The per-phase profile of elaborating base, `libs/`, the fork
  and the frontend: parsing, imports, declarations, coverage, totality and
  TTC write, with CPU time, wall time and peak resident memory.
- **Where.** On the self-compiled frontend at `make self`, on both
  targets. The same profile on stage 0, on Chez, is recorded once beside
  it and is never a target.
- **How (D14).** No profiler enters the tree; LLVM's time trace serves the
  C++. There are two timing records today:
  - The fork's `logTimeWhen` (`Core/Context/Log.idr`) prints `TIMING`
    lines to standard output, in seconds of process CPU time.
  - The driver's `reportTimes` (`Frontend/Program.idr`) writes
    `phase<TAB>ms` lines of monotonic time to the `--timing` file.

  T0 makes them one: `logTime` hands each phase to the record the driver
  writes, so no printed line is read back. T0 also sets the fork's level
  to 3, not the 1 the driver sets now. Level 1 prints only `Elaborating`
  (`Idris/ProcessIdr.idr:361`). Parsing, imports and declarations are
  level 2. Totality and each definition's right-hand side, case tree,
  size-change graphs and coverage are level 3 (`TTImp/ProcessDef.idr`,
  `TTImp/ProcessDecls/Totality.idr`). A sampling profile by the
  platform's own sampler splits declarations into unification,
  normalisation and search, which `logTime` does not bracket.

## 2. The design: the decisions that govern what remains

### 2.0 One language (D7)

**D7.** The kernel's theory is the fork's as T0 finds it. Conversion, QTT,
erasure, totality and coverage keep their meaning. Every stage is proved
by TTCs identical to the stage before's on base, `libs/`, the fork and the
frontend, up to generated names at T7.

The elaborator may succeed where it failed before only when two things
hold. Its output is ordinary TT the kernel accepts, and the program asked
for it by writing a `rewrite`, a tactic call or an `auto` argument. It
never inserts an equality proof the program did not write. Reason: a
definitional law changes conversion for every program (0008 D11). A
smarter elaboration of one written construct changes only that construct,
and the one kernel checks its output.

The repository's own Idris uses no such extension, because it also
compiles under the stock Idris, always (AGENTS.md).

### 2.1–2.2 Terms and evaluation are 0009's (D2)

**D2.** The checker's terms are 0009's hash-consed arena, and its
evaluator is 0009's wavefront machine. That gives one evaluator for types,
proofs and the program's static part.

Caches hold only what is a function of their key:
- Conversion results for closed, metavariable-free terms are kept as
  success and failure pair sets, not a union-find. Conversion is not
  transitive, so a closure over successes would make the answer depend
  on evaluation order (elaborators §4, Lean's kernel).
- Terms with metavariables get a transient cache, which is dropped when
  constraints were postponed during the check.

These caches are 0009's A2 (its D12).

### 2.3 Unification and search (D12, D8, D6)

**D12. Unification stays the fork's**, approximations included. During
search and on a left-hand side it unifies the spines of two applications
of one meta or one name, as Lean and Coq do and as Agda allows behind
`--lossy-unification` (elaborators §5). Removing that or adding more would
change which programs are accepted. A comparison with no meta in it is
already the conversion's: unification calls `convert`.

Unification's speed comes from other proposals, and no stage here changes
it:
- 0009's A1 and A2 bring glued values and approximate conversion. That is
  smalltt's bounded speculation, in place of the eighteen `clearDefs`
  round trips in `Core/Unify.idr`, which try a comparison without
  unfolding and then with it.
- 0010's O7 wakes a constraint only on the metas it is blocked on, in
  place of `solveConstraints`' rescans.

**What the fork's search answers** (*read*, `Core/AutoSearch.idr`):
1. A goal tries the local variables first, then each hint group in order
   (`searchType`).
2. A group whose names may overlap takes the first success (`anyOne`). Any
   other group needs exactly one success, else the search is ambiguous
   (`exactlyOne`).
3. A candidate's arguments are searched right to left, each committing to
   its one answer (`searchName`, `searchIfHole`), so nothing backtracks
   into a solved subgoal.
4. A goal already on the stack is abandoned (`abandonIfCycle`).
5. The depth counts down per nested search from `%auto_implicit_depth`,
   default 50 (read at `TTImp/Elab/App.idr:240`).

So a subgoal's answer is a function of the goal, its environment, the
visible hints, the defaults flag (`tryNoDefaultsFirst`), the remaining
depth and the stack above it.

**D8. Tabling never changes an answer.**
- The table keys a goal by its term and its environment, both ids in
  0009's arena, together with the defaults flag.
- An entry holds an answer or a failure only where that result is a
  function of the key: the goal has no unsolved meta, no branch was
  abandoned against a goal higher on the stack, and no branch was cut by
  the depth bound.
- An entry records the depth its search used, and is reused wherever at
  least that much depth remains.
- The table is emptied when a hint is added or the namespace changes,
  since either changes the visible hints.

With failures tabled under the same rule, a failing tower of diamonds
takes time linear in its height (Lean 4's measurement, elaborators §6).

Two things are not taken. Selsam's consumers, which resume a suspended
goal on a cycle, answer goals the fork abandons. 0014's relational core
(D6) is not used either: the answers are ordered and the ambiguity rule
counts them, which a set-valued fixpoint cannot express. Reason for the
whole rule: the answer is which implementation a program means.

**No wall clock bounds search, and the dead clock goes.** Nothing reads
`searchTimeout` (`%search_timeout`, `setSearchTimeout`). Nothing calls
`startTimer`, so `checkTimer`, which `evalRef` runs on every unfolding,
never throws `Timeout`. All of it is deleted, as `%totality_depth` was.

**The counts that stay** (*decision*, the default for the owner's question
below):
- `%auto_implicit_depth`, default 50.
- `%ambiguity_depth`, `ambigLimit` default 3 (`checkAmbigDepth`,
  `TTImp/Elab/Ambiguity.idr`). Swift's overload blow-up is the warning
  for what happens without it (`docs/swift`).

The totality comparison was made to terminate without its count by a memo.
Search has no structural measure like that: a goal can grow at each step
(`Show (List a)` asking for `Show (List (List a))`), and only the count
stops it.

**The owner's question.** 0002 deleted `%totality_depth` because a count
decided acceptance, and these two counts do the same. The default keeps
them. The alternative replaces the depth with the frontend's request-chain
rule applied to goals: refuse a chain whose goal grows (0013's feature 2).
That would change which programs the fork accepts.

### 2.4 Shape arithmetic and rewrite (D9, T4)

**D9. No polynomial normalisation of `Nat` in conversion.** It would
accept programs the fork refuses, and it would change conversion for every
program. Shape arithmetic is 0008's library tactic `Array.Shape.solve`
(0008 §3.7), which takes under 1 s per obligation. What this proposal owes
it is speed on 0009's machine, checked in T4's proof.

**The rewrite ladder**, in increasing order of reach:
1. Refl elimination when the rewritten side is a variable.
2. Telescope generalisation when it is a term.
3. A search over which occurrences form the motive, with one bitmask per
   candidate, checked cheaply on hash-consed terms.
4. A diagnostic that names the blocking dependency when none fits.

The fork abstracts every occurrence of the normalised left side in the
normalised goal, and fails when the predicate is ill-typed or the rewrite
changes nothing (`TTImp/Elab/Rewrite.idr`). The first three rungs succeed
where that fails, and each elaborates to an ordinary `replace` or a match
on `Refl` (D7). The diagnostic changes nothing about what is accepted.

### 2.5 Solvers search, the kernel checks (D3, D11; parked)

**D3, D11.** A solver searches, and its result becomes a term that the
kernel checks. Nothing is trusted. F*'s and Dafny's model, which trusts
the solver, is rejected for two reasons: a solver's answer is not an Idris
term, and solvers are unstable (elaborators §9).

How a solver is used:
- A tactic reaches it as a pinned, statically linked Rust crate through
  0015. It never goes through C, `%foreign`, MLIR's C++ `smt` dialect or a
  subprocess.
- The solver is chosen at T8, among those that emit a certificate the
  reconstruction reads (LRAT for SAT; Alethe or cvc5's format for SMT).
- Its limit is a counted argument in the program's source.
- Certificates are cached by the query's content hash.

T8 waits for 0015, and for a library or corpus proof that names a goal
family a solver decides and no tactic does.

### 2.6 A small kernel (D4, D10, D13)

**D4.** A small kernel, separate from elaboration by the de Bruijn
criterion (`papers/pollack-1998-believe-machine-checked-proof`),
re-checks every TTC apart from elaboration.

No independent second checker is built (such as lean4lean or nanoda), for
two reasons. It would hold every typing rule twice. And a test whose
expected answer is another implementation's is the oracle AGENTS.md
declines. The kernel is trusted because it is small and because each
typing rule has a seeded ill-typed term that it refuses by name.

**The kernel's bar** (*decision*). Re-checking a library's TTCs with the
kernel alone costs under 10% of elaborating them, on the same binary.
Reason: a checker that does no search, no unification and no unfolding
heuristics, and still costs more than that, is doing elaboration's work.
The measured bars are in kernels §2.

**D10. One conversion.** The kernel's conversion is the only definition of
definitional equality. Unification calls it and adds only meta solving.
Lean holds two conversions, which drift (elaborators §5, §13).

**D13. One termination closure.** The fork still closes size-change graphs
twice:
- `calcTerminating`'s triple closure (`transitiveClosure` in
  `Core/Termination/SizeChange.idr`);
- `loopsTerminate`'s weakest walks, which the frontend calls
  (`Translate/Recursion.idr`).

The triple closure goes, and `loopsTerminate` carries the call path that
the checker's message names. That is 0010's O6; this proposal adds no
stage for it.

**`Host` stays.** No stage here makes the evaluator or the elaborator
provably terminating, since Idris's theory is not strongly normalizing.
When 0009's A1 replaces the evaluator, `Host`'s `normalise` fields name
the machine instead. This is the answer to 0002 §3 item 5.

### 2.7 Parallelism (D5)

**D5** (the owner's, 0007 §12, 2026-10-14). Modules check in dependency
order, then definitions whose signatures are known, on 0006's shards.
Checking is single-threaded until the shards exist, and on Chez for good,
where the shard layer runs sequentially (below).

The fork already builds each module from a cleared context that holds
only its imports, with a fresh unification state (`buildMod` in
`Idris/ModTree.idr`), one module after another (`buildMods`). There is no
process or thread in Idris code: `Process` and `Threads` are
`OutsideLanguage` in `foreign/idr/include/idr/IR/IdrBase.td`.

**Names come from content, first.** The fork names what it generates from
one counter (`nextName`, `Core/UnifyState.idr`). The counter is reset for
each module (`resetNextVar`) and seeded from the last import's TTC, so
modules checked in parallel already leave their TTCs as they are.
Definitions checked in parallel would let the schedule reach names. So
T7 first derives each generated name from its definition, which is the
pipeline cutover's names-from-content rule (its last text is at
484d6403). That step is proved by TTCs identical up to those names.

**How the shard step meets the two hosts** (the coordinator's binding
ruling, 2026-10-15). The fork compiles and runs under the stock Idris and
under idris-mlir, forever, and it reaches no `libs/` `%extern` (0001's
R3). So the fork reaches the shards only through 0006's plain-Idris layer:
definitions with bodies, which Chez runs sequentially. idris-mlir swaps in
0006's runtime through the registry's `Faster` hook, with byte-identical
output. The body is the one meaning, and removing the hook leaves the same
result. T7's shard step waits on that layer as well as on the shards.

**The array core is used where the work is regular**, always through the
libraries' plain-Idris layers, never the `%extern` array ops, which serve
programs only (the same ruling):
- constraint generation over a flat syntax tree (0010);
- size-change composition as a semiring product over
  `Algebra/SizeChange.idr`'s `Smaller | Same | Unknown`, while the closure
  stays a relational fixpoint with subsumption over walks (0010 §4.7);
- batched conversion of hash-consed terms (0009).

GPU type checking and interaction-net normalisation wait for a measured
case where elaboration is bound by normalisation that the CPU paths cannot
serve.

## 3. Rules it keeps

- Idris 2 as the fork checks it, one language (D7). The frontend consumes
  checked TT.
- Two hosts. Every change here is fork code that the stock Idris and
  idris-mlir both compile and run, within the subset idris-mlir compiles.
- No trusted solver, no escape hatch in the checker, and no second
  checker.
- Outputs are byte-identical at every worker and shard count, and no
  generated name comes from a counter shared between definitions.
- No option selects behaviour (`--timing` writes a record and selects
  nothing). A stage is measured old binary against new, from the same
  inputs, best of five.
- No process or thread in Idris code; whole-program compilation; both
  targets.

## 4. Staged plan

**Done:** package commands take `--timing FILE` and turn on the fork's
`logTime` (bfdcac70; `perform (PackageCommand …)` in
`compiler/src/IdrisMLIR/Frontend/Driver.idr`).

| Stage | Content | Proof | Mark |
| --- | --- | --- | --- |
| T0 | §1's profile and plumbing; the headline workloads run once against Lean 4 and F* (D15) | the record under `bench/profiles/`, one with 0010's O0; the baseline of 0009's A0 | AFTER-SELF: `make self`'s first green run |
| T3 | tabled search under D8 | identical TTCs; instance-heavy files at least 2× faster than 0009's A2; a failing diamond tower takes time linear in its height; no file slower by more than 5% (the pipeline cutover's §10 margin) | AFTER-SELF: 0009's A2 |
| T4 | the rewrite ladder (§2.4) | the fork's rewrite failures listed in tests become passes; 0008's shape-equality corpus within 1 s per obligation; identical TTCs where the fork already succeeds | AFTER-SELF: 0009's A2 |
| T5 | the kernel apart from elaboration, holding the one conversion (§2.6) | every TTC of base, `libs/`, the fork and the frontend re-checked in under 10% of the time to elaborate them; a seeded ill-typed term per rule, refused by name | AFTER-SELF: 0009's A2 |
| T7 | names from content, then definitions on 0006's shards (§2.7) | names: TTCs identical to T5's up to generated names; shards: TTCs identical at 1, 2 and 8 shards, and wall time on base at most 1.5 / cores of T5's | AFTER-SELF: T5; the shard step also needs 0006's shards and their plain-Idris layer |
| T8 | certificates from SAT/SMT, checked as terms (§2.5) | a fixture where the search succeeds and the kernel checks the result | parked with 0015 |
| — | the dead clock deleted (§2.3) | the fork builds on both hosts; identical TTCs | AFTER-SELF: nothing |

**D15, the headline** (*conjecture until measured*): faster elaboration
than Lean 4 and F*, on the same machine and on both targets. It is judged
first on smalltt's set, then on base and the frontend.

The workloads:
- smalltt's `bench/conv_eval.idr` and `.lean`;
- `asymptotics.stt` and `stlc_small.stt`, translated to Idris and Lean;
- stlc5k, 10k and 100k, from smalltt's generator at the snapshot's
  revision. That revision was not stored, so T0 stores it with the files;
- `conv_eval` written for F*, which smalltt lacks.

Lean 4 and F* are measuring instruments. They are pinned releases, fetched
under `.toolchain/` by a bootstrap step with each release's SHA-256 in the
lock (as `verify_release` in `tools/bootstrap.sh` checks it), recorded in
PINS.md, run by the bench, and never linked or shipped. The limits of the
evidence: smalltt's numbers are from 2021, and its language has no
inductive types (elaborators §14).

## 5. Rejected alternatives

Rejected where its decision is taken: trusting a solver, or reaching one
through MLIR's `smt` dialect, C or a subprocess (§2.5); definitional
arithmetic in conversion (D9); meta solutions beyond the fork's or fewer
(D12); Selsam's consumers resumed on cycles (D8); a second checker (D4);
threads in the frontend or processes the driver starts (D5); GPU checking,
now (§2.7). Three more:

- **A wall-clock search timeout:** the answer would depend on the machine.
- **Rewriting the elaborator from scratch:** it would break Idris 2
  compatibility and lose the corpus proofs. The fork changes stage by
  stage, each stage proved by identical TTCs.
- **Compiled reduction** (Coq's `native_compute`, a JIT inside the type
  checker): a second compiler inside the first. 0009's array machine is
  the answer to heavy evaluation (its D3).
