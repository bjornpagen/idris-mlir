<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Rederivation audit: effects and termination

Family: the effect row on `idr.func` and `idr.call`; divergence and what
proves its absence (Idris's termination checker, its components, the
frontend's `Recursion`, `#idr.terminates`, `idr.may_loop`); crash sites;
`exit`; what LLVM is told. Traced from the checker's totality and its TTC,
through the frontend's boundary, Emit, the specification's effect tables,
the one derivation and its verifier, every pass that reads or writes rows,
to the lowering's attributes.

- HEAD at start: `eedaf5d40a36a5423c2516364871ea901c2aaec7`
- HEAD at finish: `b2aab6e9ba40e43debc690277bf1eeda58adcfac` (8b2cd180 and
  b2aab6e9 landed during the audit; neither touches a site cited here)
- Ground: every site is **read**. Nothing was measured. This machine has
  no built C++ tool, and I did not build the frontend. A cost is the shape
  of the work (per op, per query, per pass, per compile), not a number.
  Where a fix needs a number before it lands (AGENTS.md: no removal on an
  unmeasured claim), the finding says so.
- In flight: an unrelated lane is deleting `idr-constants`
  (`Transforms/Effects/Constants.cpp`, `Analysis/Constants.*`, edits to
  `Transforms/Effects.h`, `Optimize.cpp`, `Settle.cpp`, `Lower.cpp`). None of
  its hunks touches a site below, but the files are held. Each finding
  lists which of its files are modified in the checkout now.

## Where each fact is first known

- **Termination, per definition, transitive.** The checker's
  `calcTerminating` (`compiler/checker/src/Core/Termination/SizeChange.idr:580-601`)
  gives `Terminating = Unchecked | IsTerminating | NotTerminating reason`
  (`Core/TT.idr:316-319`). `reason` keeps own-loop failures (`RecPath`)
  apart from reaching a failure (`BadPath`, `BadCall`) and from positivity
  failures (`NotStrictlyPositive`). The verdict is stored in
  `GlobalDef.totality` and in the TTC (`Core/TTC.idr:1452`). The frontend
  reads it once per definition at the boundary
  (`Frontend/Translate/Boundary.idr:279-289`, `verdictOf`), forcing the
  check for an `Unchecked` definition, into `Defined.ends : Ends`
  (`Translate/State.idr:1056`).
- **Termination, per Idris component, own loops only.** It is computed
  inside the same `calcTerminating`: `components work` (Tarjan,
  `SizeChange.idr:225-232`), then `componentLoops` (`:463-464`, the search
  `loopsTerminate`, `:444-461`) for every component. It is also computed a
  second time by the frontend (finding 2).
- **Coverage.** The checker's `isCovering`, read once at
  `Translate/Programs.idr:144-146`. It decides between `Unreachable` and a
  `NoClauseMatched` crash (`Translate/Cases.idr:242, 276, 532`). It is
  carried with no drop, so it is not a finding.
- **An op's own effects.** Each is declared once in the specification
  (`Spec/Effects/Declaration.idr`), generated, and read through the one
  query API. Crash, exit and `idr.may_loop` are each an op's static effect.
  They are carried with no drop.
- **A function's row.** The one derivation (`Analysis/Effects.h`,
  `IR/Func/Fold.cpp`), written by the one writer
  (`Transforms/Effects/Writer.cpp`), copied onto every call. The call's
  copy is required by AGENTS.md ("a call carries its callee's"), so it is
  not a finding.
- **What LLVM is told.** `effects::told(row)`, a fold over the
  specification's `llvmTable` (`Spec/Effects/LLVM.idr`,
  `IR/Effects/LLVM.h:30-44`). It is written per function by
  `Conversion/Lower/Attributes.cpp:55-69` and per call by `:70-82`.

---

## 1. Divergence of recursion is a per-function component number, re-derived for every cycle by six readers

**The fact.** Whether code may run for ever because it recurses: a cycle
of calls through code Idris did not prove to end.

**Where first known.** The checker decides it per definition
(`SizeChange.idr:580-601`), and the frontend holds it as `Defined.ends`
(`Boundary.idr:279-289`). The frontend also holds the per-component form,
recomputed (finding 2), as `Nature.termination`
(`State.idr:1201-1211, 1408-1414`).

**Where dropped.**
- `Emit/Closures.idr:62-79` (`functionOp`) writes one optional attribute
  per function, `#idr.terminates<component N>`
  (`Spec/Functions/Termination.idr:26-71`). The fact Idris proved is about
  its own call graph's cycles. What survives is a function-level number,
  and the code that may loop carries nothing. (`idr.may_loop` is written
  only for repetition inside one function, `Emit/Bodies.idr:513-521`.)
- Divergence through calls is no op's effect, so no carrier goes with the
  code. Every pass that turns calls into loops, or loops into calls, has
  to translate between the attribute form and the op form.
- `Term.idr:1999-2009` (`withRegions`), used at
  `Translate/Programs.idr:425-430`, joins each local definition's own
  verdict into one per function. One unproved local definition removes
  the proof from the whole function and puts `idr.may_loop` on every loop
  in it. A per-region fact is folded into a type too wide to hold it.

**Where re-derived** (each reads `#idr.terminates` and the current call
graph to recover "this cycle may diverge"):
1. `IR/Func/Fold.cpp:37-53` and `Analysis/Effects.h:136-138, 171-175,
   224-229`. Every derivation builds `ownCycle = provedTogether({fn})` and
   compares every `idr.call`'s callee with the function's own symbol
   (`cycleOfOne`). The cost is per call op, per derivation. The verifier's
   `rows::Check` derives every function after every pass, and every writer
   derives every function again.
2. `Transforms/Effects/Writer.cpp:59-70, 102` (`addCycles`) runs on every
   whole-program write. That is 12 call sites
   (`Defunctionalize/Pass.cpp:102`, `InPlace/Writer.cpp:172`,
   `Optimize/Optimize.cpp:90`, `Inline/InlinePass.cpp:70`,
   `Ownership/Exclusive.cpp:205`, `Lifetimes/Pass.cpp:261`,
   `Tail/Trmc.cpp:194`, `Tail/Frames.cpp:304`, `Pipeline.cpp:60` after each
   of the three counting nests, `Conversion/Lower.cpp:255`). Each one walks
   every on-cycle component and calls `provedTogether`.
3. `Transforms/Effects/Component.cpp:108-120` repeats the cycle rule a
   third way, `isCycle` plus `provedTogether`, for each optimizer
   component (`Optimize/Settle.cpp:168`).
4. `Transforms/Contracts/Contracts.cpp:294-323` (`cycle-divergence-kept`)
   runs `addCycles` again after every pass under `--idr-contracts`. Its
   breaker is `:399-452`, with `ExpectProperties.inc:168` and
   `tests/contracts-cycle-divergence-kept/`. The relation exists because
   the representation allows a state no verifier can see: every member of
   a cycle dropping the cycle's divergence together (`IR/Func/Rows.cpp:155-162`).
5. Loop builders read the attribute and write the op:
   `Transforms/Joins/Joins.cpp:144-147, 194-201` (`endingOf`, used by tail
   loops at `:271` and by contification at `Optimize/Contify.cpp:281-287`),
   and `Transforms/Joins.h:60-78, 120, 136` (`Ending`).
6. Loop dissolvers read the op and write the attribute:
   `Transforms/Tail/Dissolve.cpp:153-165` removes `terminates` from a
   lifted function whose region held `idr.may_loop`, then erases the mark.
   `Joins/JoinRules.cpp:245-248` erases marks when a loop becomes a join.
7. The unit test restates the rule as its own oracle:
   `unittests/Rows.cpp:60-230`, `endingOf` and `cyclesOf` over a seed's
   terminations.

**The carrier.** Divergence held by an op wherever the code that may
diverge goes, as crash already is. `idr.may_loop` already has the right
declaration (`Spec/Control/Joins.idr:199-232`: one `Write Divergence`,
never trivially dead, ordered with crashes, exit and output). Emit writes
it at the entry of the body of every function whose code Idris did not
prove to end, and at the entry of each join region of a local
definition, from that definition's own verdict. Then:
- inlining, specialization, contification, tail loops and dissolution move
  the mark with the code, and no builder decides an `Ending`;
- a cycle's divergence is an op of some member's body, so the verifier's
  containment check holds it, and the state "every member dropped it
  together" can no longer be written;
- a self call needs no special reading, since its divergence is the op at
  the function's entry.

The verdict the marks come from needs a ruling, which is why this waits
(see "waits on"):
- **(a) Keep C74's per-component verdict.** Marks go on functions whose own
  component is endless. C74's rule for cycles a pass makes across
  components stays in `addCycles`, now reading only "members span more
  than one component, or include a function with no definition". Deleted:
  readers 1, 5 and 6, `withRegions`, and `Ending`.
- **(b) Use the transitive verdict the frontend already holds
  (`Defined.ends`).** This is the further deletion. Every cycle through
  code whose verdict is `IsTerminating` ends, by Idris's own soundness
  argument (size change plus positivity). Code with any other verdict
  carries its mark. Dispatches, the root and application forms have no
  loops of their own and carry none. C74's motivating program,
  `data D = MkD (D -> Nat)`, is covered: a function referencing `MkD`
  gets `NotTerminating (BadCall …)` from `totRefs`
  (`Termination/References.idr:82-98`), because positivity is decided for
  every type constructor at each module's end
  (`TTImp/ProcessDecls/Totality.idr:25-29`, upstream #524). That is the
  precondition (b) rests on; it is read, not tested. Under (b), nothing in
  the C++ reads a termination proof, so the attribute goes, and so does
  finding 2 with no checker change. The cost: a function whose own loops
  decrease but which references a partial function carries divergence even
  after an optimization removes that reference. Today its divergence comes
  only through the callee's row. That is a precision loss in a rare case,
  and never a soundness loss.
- A detail for whoever implements it: a mark at a function's entry stands
  for "code Idris did not prove", not for repetition. `LoopToJoin`
  (`JoinRules.cpp:245-248`) must not erase it. Tail loops should leave the
  entry mark outside the loop they build, or nothing should erase marks.

**What the fix deletes.**
- Under (a), about 100 lines:
  - `Fold.cpp:37-53`, the ownCycle initializer and `cycleOfOne`;
  - `Effects.h:16-25` (the comment), `136-138`, `171-175` and `226-229`;
  - `Joins.cpp:144-147, 194-201` and the `Ending` arguments at `:150, 239,
    271`, `Contify.cpp:281-287`, `CaseOfCase.cpp:195`, `JoinLoops.cpp:50`;
  - `Joins.h:60-78`;
  - `Dissolve.cpp:153-165`;
  - `Term.idr:1999-2009` and its use at `Programs.idr:430`;
  - the cycle-of-one cases in `unittests/Rows.cpp`.
- Under (b), about 700 lines. On top of (a):
  - `Writer.cpp:57-70, 102` and `Transforms/Effects.h:103, 134`;
  - `Component.cpp:108-120`;
  - `Effects.h:86-101` (`provedTogether`);
  - `Contracts.cpp:294-323, 399-452`, the relation's row in
    `ExpectProperties.inc`, and `tests/contracts-cycle-divergence-kept/`;
  - `IR/Func.h:58-80` (`Termination`, `InComponent`, `Unproved`);
  - `IR/Func/Values.cpp:22-46` (proof parse, print, hash and
    `getTermination`);
  - `Spec/Functions/Termination.idr` (71 lines) and the `terminates` slot in
    `Spec/Functions/Declarations.idr:98-99, 214, 386`, with what is
    generated from them;
  - `Encoding/Idr.idr`'s `TerminatesAttr` (`:49, 97, 254-262, 435, 473`),
    `MLIR/Bytecode.idr:716` and `SyntaxSamples.idr:189, 370`;
  - `Emit/Closures.idr:62-79`'s `terminates`;
  - `Term.idr:1666-1676` (`Termination`);
  - `Nature.termination` and `natureFrom`'s `proved`
    (`State.idr:1201-1211, 1405-1414`);
  - all of finding 2;
  - the termination seed and oracle in `unittests/Rows.cpp`.

**Owner.**
- L02: `Analysis/Effects.h`, `IR/Func/*`, `IR/Func.h`,
  `Transforms/Effects/*`, `Spec/Functions/`.
- L09: `Transforms/Joins/*`, `Transforms/Joins.h`.
- L10: `Tail/TailLoops.cpp`, `Tail/Dissolve.cpp`.
- L18: `Optimize/Contify.cpp`, `Optimize/Settle.cpp`.
- L19: `Contracts.cpp`, `ExpectProperties.inc`, the test.
- L15: `unittests/Rows.cpp`.
- L16: Emit, `Term.idr`, `State.idr`, `Programs.idr`, Encoding.
- INT: the generated `.td` files.

**Waits on.**
- A ruling on which op holds the fact. That is an architectural choice:
  (a) amends C74's threading, and (b) amends C74 itself. It goes to the
  owner.
- Files modified now: `Emit/Bodies.idr`, `Translate/State.idr`,
  `Translate/Boundary.idr`, `Translate/Programs.idr` (L16) and
  `Optimize/Settle.cpp`.

**Confidence.** Read for every drop and re-derivation site. Conjecture for
(b)'s soundness argument, which rests on the positivity precondition
above.

---

## 2. The checker computes each component's loop verdict and drops it; the frontend runs Tarjan and the size-change search again on every compile

**The fact.** For each definition: the Idris component it lies in, and
whether every loop of that component decreases. This is C74's
`Terminates ComponentId | MayDiverge`.

**Where first known.** In `calcTerminating`,
`SizeChange.idr:591`: `reported (concatMap componentLoops (components work))`
holds every component of the unchecked part the definition reaches and
each member's `Loops` verdict.

**Where dropped.**
- `SizeChange.idr:591-600` keeps three things: `RecPath` for the one
  reported function (the greatest name), `BadPath` for the path to it, and
  `IsTerminating` for the functions `settle` can close
  (`:511-560`). Each component's identity is dropped, along with every
  other member's own-loop verdict. A member whose own component decreases
  but which reaches a failure is stored as `BadPath`, which loses the
  fact that its own loops decrease.
- The TTC (`Core/TTC.idr:1452`) stores only `totality`. For every
  definition checked when its library was built (most of prelude and base,
  stored `IsTerminating`), no component reaches the compile at all.

**Where re-derived.**
- `Frontend/Translate/Recursion.idr:1-162` (`loopsOf`, called at
  `Boundary.idr:1190`). It holds a second Tarjan of its own
  (`visit`/`successors`, `:69-112`) over the same `sizeChange` graphs the
  TTC stores. It then calls the checker's own `loopsTerminate` per
  component (`:131-145`) for every definition `main` reaches. The cost is
  per compile, over the whole reached program, library code included,
  whose verdicts were proved when the library was built.
- In the same run, `verdictOf` (`Boundary.idr:279-289`) forces
  `host.checkTerminating` for every `Unchecked` definition. That runs the
  checker's own Tarjan and search over the same graphs. Every unchecked
  component is therefore searched twice per compile: once for `ends`, once
  for `termination`.
- The result is threaded as `proved : SortedMap Address ComponentId` and
  looked up per definition: `TypeConstructors.idr:595-609` (`readWhole`)
  and `State.idr:1405-1414` (`natureFrom`).

**The carrier.**
- Under C74 as recorded: the checker's `Totality` gains the own-loop fact,
  for example
  `ownLoops : LoopsUnsearched | LoopsDecrease ComponentKey | LoopsEndless`.
  `calcTerminating` writes it for every member of every component it
  searches. It must also search the definition's own component on the
  early `BadPath`/`BadCall` returns (`:587-590`, `addFunctions`'
  `Left`), which today return before any search. The TTC keeps it
  (AGENTS.md: "The TTC keeps every fact a reader would otherwise
  rebuild"). The frontend reads it once in `readDefinition` beside
  `ends`, interning the key (the component's first member's resolved
  name) into `ComponentId`.
- Under finding 1(b): no carrier at all. `ends` is the one fact.

**What the fix deletes.**
- `Recursion.idr`, all 162 lines.
- `Boundary.idr:1190` and the `proved` argument of `readWhole`
  (`TypeConstructors.idr:595-609`).
- `natureFrom`'s `proved` lookup (`State.idr:1405-1414`).
- One of the two size-change searches per unchecked component per
  compile, and the whole search over library code.
- Added under C74: one field in `Core/TT.idr`'s `Totality`, its TTC
  encoding, and the writes in `calcTerminating`.

**Owner.**
- L17: `compiler/checker/src/Core/Termination/SizeChange.idr`,
  `Core/TT.idr`, `Core/TTC.idr`, `Core/Binary.idr`.
- L16: `Recursion.idr`, `Boundary.idr`, `State.idr`,
  `TypeConstructors.idr`.

**Waits on.**
- L17's in-flight edits to `Core/TTC.idr`, `Core/Binary.idr`,
  `Core/Context.idr` and `Core/Termination/CallGraph.idr`, all modified now.
- L16's in-flight edits to `Boundary.idr`, `State.idr` and
  `TypeConstructors.idr`, all modified now.
- Finding 1's ruling. Under 1(b) this needs no checker change and is a
  pure deletion.
- The cost per compile is not measured. Measure it before claiming a
  speedup; the representation case stands without a number.

**Confidence.** Read.

---

## 3. Every whole-program row write re-derives every function's own part, though C64 records a writer seeded by the functions that changed

**The fact.** Which functions' bodies a pass changed, and which atoms its
new ops add. The second is static: `Spec/Pipeline/Pipeline.idr:347, 375,
398, 405` declare `[Count, Alloc, Free]`.

**Where first known.** In the pass that edits. Every program pass that
calls the writer holds its own edit set. `solver::Editor` already
records, per function, a row of calls replaced whole
(`Analysis/Solver/ProgramGraph.h:23-27`).

**Where dropped.** At each call of `rows::write(program, graph, work)`.
The signature takes no edit set (the 12 call sites listed in finding 1,
item 2).

**Where re-derived.** `Writer.cpp:76-82` derives every function of the
program from scratch, in parallel. Then `:84-104` re-marks the writes and
re-joins callees first. This happens 12 times per compile. The verifier's
`rows::Check` already re-derives every function after every pass, so the
writes are a second full derivation stacked on the verifier's.

C64 (`proposals/0000-mlir-native.md:3855-3875`) records the writer as "an
incremental decide step seeded by the functions whose row shrank". The
code is not that.

**The carrier.** The edit set the pass already holds: the functions it
rewrote, passed to the writer. Each function's own part is kept between
writes, either in the analysis manager (preserved for functions the pass
did not touch) or recomputed only for the seeded functions. The callees-
first join is re-run from the seeds. This fits MLIR's grain: an analysis
kept and invalidated by what changed, as AGENTS.md's "an analysis lives in
the analysis manager and survives every pass that does not change it"
requires.

**What the fix deletes.** Per write, the derivation of every unedited
function. The code shrinks little (`Writer.cpp:76-82` takes a seed set);
the work per compile drops from 12 whole-program derivations to the
edited functions'. The three counting nests touch every function, so
their three writes keep full derivations; the other nine program passes
(TRMC, frames, lifetimes, exclusivity, in-place, inline and the rest)
touch a subset.

**Owner.** L02 (`Writer.cpp`, `Transforms/Effects.h`). Call sites:
- L18: Defunctionalize, Inline, Optimize;
- L08: InPlace, Exclusive;
- L05: Lifetimes;
- L10: Frames, Trmc;
- L21: Lower;
- L03: `Pipeline.cpp`.

**Waits on.**
- `Transforms/Effects.h`, `Optimize/Optimize.cpp` and `Conversion/Lower.cpp`
  are modified now (the idr-constants cull).
- A measurement of the writer's share of compile time before anyone claims
  a speedup.

**Confidence.** Read for the drop. Conjecture for the payoff.

---

## 4. Loop progress at the lowering: the call's row is dropped at phase 2 and re-read from LLVM's `willreturn` at phase 3

**The fact.** Whether a loop's body may diverge. That is the divergence
atom of the effects of its repeating regions: `idr.may_loop` and the rows
of the calls inside.

**Where first known.** The rows of the `idr.call` ops in the loop, and
the marks.

**Where dropped.** Phase 2 lowers each `idr.call` to `llvm.call`.
`tellCall` (`Lower/Attributes.cpp:75-82`) keeps only `willreturn`, which
IO, exit and crash withhold as well as divergence (`Spec/Effects/LLVM.idr:138-149`).

**Where re-derived.**
- `Conversion/Matches.cpp:405-415` (`keepsFromEnding`) reads a call's
  `getWillReturn()`. A call that may crash, do IO or exit is then counted
  as one that may keep the loop from ending (`Keeps::MayNotReturn`), so a
  loop that calls any guarded function is never told it makes progress.
- `tellProgress` (`:431-471`) also re-derives "this function's row
  withholds `mustprogress`" by counting `idr.may_loop` ops (`diverging`).
  It does not read the row. So a function whose divergence comes only
  through a call gets no loop annotations at all.
- The reader is a classifier of its own over a lowered form, which
  AGENTS.md forbids: "Nothing else … reads effects its own way".

**The carrier.** The rows, still on `idr.call`, read through the one
query before phase 2: `effects::own(op).on(Write, Divergence)` covers a
call (through `rowSet`) and `idr.may_loop` alike. The function's own
condition is `row.contains(divergence)`. Decide the latches' annotation in
phase 1, while calls are ours, and store it in the latch's discardable
attribute as today.

**What the fix deletes.** The `LLVM::CallOp` arm and `Keeps::MayNotReturn`
(`Matches.cpp:405-415`), and the may_loop count standing in for the row
(`:432-460`). About 15 lines, and the conflation with crash and IO goes
with them.

**Owner.** L09 (`Conversion/Matches.cpp`, not modified).

**Waits on.** Nothing. If finding 1 lands, marks at a function's entry
count toward the row's divergence the same way.

**Confidence.** Read.

---

## 5. A local definition's termination is joined into its function's

**The fact.** Each local definition's own verdict (`TFn.termination` of
the group's members).

**Where first known.** `Translate/Programs.idr:182` (each definition's
`nature.termination`).

**Where dropped.** `Term.idr:1999-2009` (`withRegions`), at
`Programs.idr:425-430`. If any member is `MayDiverge`, the function
becomes `MayDiverge`.

**Where re-derived.** Emit then writes `idr.may_loop` in every loop
region of the function (`Bodies.idr:513-521` reads the function's one
verdict) and drops `#idr.terminates`. Every C++ reader of finding 1 then
treats every cycle through the function as unproved, including cycles
through its proved parts.

**The carrier.** Per join region, the mark from that region's own
definition, as finding 1 places it.

**What the fix deletes.** `withRegions` (11 lines). The per-function join
of verdicts goes.

**Owner.** L16 (`Term.idr` not modified; `Programs.idr` modified now).

**Waits on.** Finding 1, which subsumes this.

**Confidence.** Read.

---

## 6. The specializer's raise restates the resource tree's order from a row's atoms

**The fact.** Whether the consumer's effects may run before the callee's
remaining effects: the tree's conflict relation (`Spec/Effects/Resource.idr`).

**Where first known.** The specification's tree, asked through
`effects::mayMoveAcross`. The same function already asks it for the ops
between the call and its consumer (`Specialize/Consumer.cpp:108-112`).

**Where dropped.** `Consumer.cpp:113-118` reads the call's row as bare
atoms.

**Where re-derived.** The same lines restate the tree by hand: crash or io
in the callee's row refuses, and divergence beside io in the dispatch's
row refuses. That is a second classifier of the order. It is also coarser
than the tree: a pure consumer is refused beside a callee that may crash,
which the tree lets move.

**The carrier.** The one query, applied to the consumer and the call.

**What the fix deletes.** `Consumer.cpp:113-118` (6 lines).

**Owner.** L18 (`Specialize/Consumer.cpp`, not modified).

**Waits on.** Nothing.

**Confidence.** Read. That the tree's answer is the order the raise needs
is my reading of the comment at `:103-107`; L18 should confirm it.

---

## 7. `exit` declares a crash on every status, a constant in range included; the lowering tests at run time and LLVM folds the test

**The fact.** A status outside 0 to 255 crashes at the exit's site. That
is statically false for a constant in range, which is the common
`exitSuccess`/`exitWith (ExitFailure 2)`.

**Where first known.** The constant operand, at Emit
(`Emit/Operations.idr:594`).

**Where dropped.** `Spec/Ops/IO.idr:153-178`: `io.exit` declares
`Write Crash` statically, whatever its status. Every row above an exit
holds `crash`. The specification's own rule for partial primitives is not
followed here: "a partial primitive is a guard and a total op … a proof
is the absence of the guard" (`Spec/Ops/Checks.idr:13-17`).

**Where re-derived.** `Conversion/RuntimeCalls.cpp:200-231` (`LowerExit`)
emits the range test at the lowering, and upstream or LLVM folds it for a
constant. The compiler's own rows never learn the fact. The
crash-sites contract counts the site (`Expect/CrashSites.cpp:31-44`). The
effect on optimization is small, because exit's io and exit atoms already
pin the call. The row still says something false.

**The carrier.** A guard of the status (C285's one `decide`, which the
e-graph folds over constants) and a total `io.exit` without `Write Crash`.

**What the fix deletes.**
- The test in `LowerExit` (`:213-224`).
- The crash on every exit's row.
- `io.exit`'s `crashSiteInterface` and site slot, which move to the guard.

**Owner.**
- L13: `Spec/Ops/IO.idr`, `Spec/Ops/Checks.idr`.
- L21: `Conversion/RuntimeCalls.cpp`.
- L11: the runtime's `unreportable_at` and `Spec/Runtime/Endings.idr`'s
  `EndsUnreportable`.

**Waits on.** Nothing (none of these files is modified). Splitting an op
is "which op holds a fact"; the specification's own guard rule settles
it, and the coordinator records it.

**Confidence.** Read.

---

## Held twice by a rule, not findings

- **The call's copy of its callee's row, write part and `lives_in`.**
  Built by `Call.cpp:54-66, 70-78` and held equal by the symbol-use
  verifier (`Call.cpp:268-273`). AGENTS.md requires it: "a call carries its
  callee's"; "A computation's row lives on its op (`idr.func`, `idr.call`)".
- **The verifier's per-pass derivation of every function** (`rows::Check`).
  AGENTS.md requires it: "held to it by the verifier, per function".
- **The write part as untouched positions among write-admitting
  parameters.** `forEachWritten` (`IR/Func.h:368-383`) recomputes
  `admitsWrite` per call operand per effect query to decode the
  positions, and `rows::told` (`Rows.cpp:113-121`) rebuilds
  `ParameterParts` to recover "writes through some parameter". The
  complement form keeps the conservative state an absent attribute
  (`widen`), which a positive list could not. That is a cost trade, not a
  dropped fact.

## Table

| # | Fact | Drop site | Re-derive sites | Carrier | Lines deleted | Owner | Waits on |
|---|------|-----------|-----------------|---------|---------------|-------|----------|
| 1 | Divergence of recursion | `Emit/Closures.idr:62-79` (component number per function); `Term.idr:1999-2009` | `Fold.cpp:37-53`; `Writer.cpp:59-70` ×12 writes; `Component.cpp:108-120`; `Contracts.cpp:294-323, 399-452`; `Joins.cpp:144-147, 194-201`; `Contify.cpp:281-287`; `Dissolve.cpp:153-165`; `JoinRules.cpp:245-248`; `unittests/Rows.cpp` | `idr.may_loop` at the entry of unproved code, carried with it; verdict per C74 (a) or `Defined.ends` (b) | ~100 (a); ~700 (b) | L02, L09, L10, L18, L19, L15, L16, INT | owner's ruling on C74; L16 files modified now; `Settle.cpp` modified now |
| 2 | Component and own-loop verdict | `SizeChange.idr:591-600`; TTC `totality` only | `Recursion.idr:1-162` (Tarjan + `loopsTerminate`, per compile); `verdictOf`'s second search; `TypeConstructors.idr:595-609`; `State.idr:1405-1414` | `Totality.ownLoops` in GlobalDef and TTC (C74), or none under 1(b) | ~180 Idris | L17, L16 | L17 and L16 files modified now; finding 1's ruling |
| 3 | Which functions a pass changed | `rows::write` signature (12 call sites) | `Writer.cpp:76-104`, all functions, per write | the pass's edit set, own parts kept as an analysis (C64's seeded writer) | small code; 12 whole-program derivations per compile → edited functions only | L02 (+ callers L18, L08, L05, L10, L21, L03) | `Effects.h`, `Optimize.cpp`, `Lower.cpp` modified now; a measurement |
| 4 | A loop's divergence | phase 2: `Attributes.cpp:75-82` (row → `willreturn`) | `Matches.cpp:405-415, 431-471` | rows through the one query, decided before phase 2 | ~15 | L09 | nothing |
| 5 | A local definition's own verdict | `Term.idr:1999-2009` | `Bodies.idr:513-521` and every reader of finding 1 | per-region mark | 11 | L16 | finding 1 (subsumes) |
| 6 | Order of a raise against the callee | `Consumer.cpp:113-118` (atoms) | the same lines, restating the tree | `effects::mayMoveAcross` | 6 | L18 | nothing |
| 7 | Exit status within 0–255 | `Spec/Ops/IO.idr:153-178` (static `Write Crash`) | `RuntimeCalls.cpp:213-224`; every row above an exit | status guard and total exit | ~12, plus the crash on every exit's row | L13, L21, L11 | nothing |
