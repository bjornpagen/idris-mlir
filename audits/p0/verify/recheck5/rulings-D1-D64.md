<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Recheck 5: the owner's rulings D1 to D64 against the tree

HEAD was 17725fdd at start and cb5cd6fb at finish. Between them,
2bcbd726 and 59dcc964 touch only the queue. 16ac96c4 is D126 round 2b-T
(Tail.h, Tail.cpp, Lower/Functions.cpp, Tail/Frames.cpp,
Lifetimes/Pass.cpp, Trmc.cpp, the inliner), and cb5cd6fb is round 2c-T,
which keeps once, in the program graph, whether a component runs calls
on frames. The rows that read those files were checked again at
cb5cd6fb. Nothing was built, typechecked, generated or run.

Every clause of D1 to D64 was read against the tree. Recheck 3's findings
were each checked again, and the 319 commits since 2026-10-22 12:00
(`git log --since='2026-10-22 12:00'`) were read for regressions of the
rulings recheck 3 found done. None regressed. Six of recheck 3's findings
are closed: D7's `Widths.cpp`, D9's `ResetsUnshared.cpp`, D15's Python
tool, D43's and D60's amendment of 0009, D49's hand stand-ins, and D51's
string ladders. D55's diff is superseded by D118.

Files in the moving tree were read as HEAD's text. A row whose evidence
is in a file a lane is writing says "in flight". Paths are under
`foreign/idr/` unless they start with another top-level directory;
`spec/` is `compiler/spec/IdrisMLIR/Spec/`. Owners are from
`ownership.json`, by longest prefix. *read* means the cited line was
opened; *measured* gives the command.

## Not done

### D10, D46: the growth proof's conclusion still checked at run time (L16, in flight)

- **D46, the run-time re-check of every request** — **Partial**, in
  flight.
  - At HEAD, `compiler/src/IdrisMLIR/Frontend/Finite.idr:171-172`
    defines `unsound`, an internal error. `:180-185` is `heightWithin`
    and `:190-194` is `sizedWithin`. `:215-216` runs both on every
    request. `Frontend/Translate/Types.idr:601-606` is `boundsHold`,
    called at `:904`. L16ec (404ff2c9) closed two gaps in the growth
    model so the check no longer fires on them, but the check stands.
    (read)
  - **Owner** L16 (D68's proof). **Remaining:** once the derivation built
    at quantity 0 covers every request, delete `unsound`, `heightWithin`,
    `sizedWithin` and the loop at `Finite.idr:213-224`, and delete
    `boundsHold` and its call at `Types.idr:904`. A request then carries
    its `Inside b l` from the proof. No run-time comparison of heights or
    sizes stays.
- **D10** — **Partial**: two facts are still paid for after they are
  known. The first is this row; the second is the framing row under D32.

### D30, D58: a tail call's data result layout (§4)

- **D30 with D58, a callee whose result layout differs from its
  caller's at a tail call** — **Open-owner**.
  - `proposals/0000-mlir-native.md:5183-5220`, §4's one open question
    (A, B\*, D2 or C; B\* recommended).
  - At HEAD, `lib/IR/Tail.cpp:189-212` (`verify(FuncOp)`, in flight
    under 2b-T) has no check that a tail call's result layout is its
    caller's. The reindex after the call passes through `tailSource`.
    (read)
  - §4 says "the verifier check lands first whatever is chosen", so that
    check can be written before the ruling. It would sit beside
    `givenBack` and report any residual as an internal error. The owner
    for that check is L10 (`lib/IR/Tail.cpp`).

### D30, D32, D33, D58: the measurements the rulings order (INT, needs a build)

- **D30, the cost of `tailcc` on every function of the program** —
  **Partial**. No measurement is recorded. `lib/Conversion/Lower/Functions.cpp:164-216`
  lowers every call of the program under `tailcc`, and a call in tail
  position `musttail`. (read)
  - **Owner** INT. **Remaining:** measure stage 1 with and without
    `tailcc` on functions only the module's calls reach, and record the
    number with its build and input. The ruling forbids weakening it on
    the result.
- **D32 and D33, the tools' stacks and the outside code's margin** —
  **Partial**.
  - `CMakeLists.txt:177-223`: no target entry sets
    `IDRIS_MLIR_TOOL_STACK_BYTES`, `IDRIS_MLIR_TOOL_SIGNAL_BYTES` or
    `IDRIS_MLIR_OUTSIDE_STACK_BYTES`. `idris_mlir_unmeasured_stacks`
    (`:216-223`) refuses to configure. (read)
  - D33's other half is done. `upstream/10-recursive-attribute-parser/`
    now holds `llvm.patch`, its reproducer and its submission, and
    patches 80 to 93 make `walk`, the walkers, clone, destruction, slice,
    region DCE and the rest iterative, each with its
    `tests/upstream-*`. (measured: `ls upstream`, `ls tests | grep '^upstream-'`)
  - **Owner** INT. **Remaining:** on each of the four targets, measure
    the three numbers as `CMakeLists.txt:187-215` says. That includes
    MLIR's deepest recursion on the stage-1 module and the deep-nesting
    fixtures (D33). Write each number into its target's entry with the
    build and the input.
- **D58, the shape budget** — **Partial**.
  - `spec/Families/Layout.idr:85-88` has `shapeBudget = 16`, with its
    doc saying it is to be measured before it is fixed. That is generated
    as `include/idr/IR/Generated/Families.h.inc:214`. The specialization
    by layout class itself is in: `lib/Transforms/Specialize/Consumer.cpp:267`
    (`families::classesUnder`), and `idr.data.reindex`. (read)
  - **Owner** INT (measurement); L04 owns the number. **Remaining:**
    measure on stage 1 where the copies stop paying, and write the
    measured value into `Layout.idr` with its measure, build and input.

### D32, D10: which call goes on a frame, decided in three places (L10, L05, L08)

- **D32, a non-tail call on its caller's cycle pushes its rest as a
  frame** — **Partial**.
  - Since cb5cd6fb the per-component half is one fact:
    `include/idr/Analysis/Solver/ProgramGraph.h:150`
    (`runsCallsOnFrames`). Both `lib/Transforms/Tail/Frames.cpp:155-158`
    and `lib/Transforms/Lifetimes/Pass.cpp:141-142` ask it.
  - The per-call fact is still written three times, each as
    `!lastActOf(call)` and the callee's SCC equal to the caller's:
    - `include/idr/Transforms/Tail/Frames.h:134-140` (`isMember`, `frames`);
    - `include/idr/Transforms/Lifetimes/Plan.h:363-368` (`continuesOnFrame`);
    - `lib/Analysis/Ownership/Borrows.cpp:159-164` (`framed`).
  - `lib/Transforms/Lifetimes/Decide.cpp:44-49` restates it over the
    graph's rows. `continuesOnFrame` is also asked by
    `Lifetimes/Lend.cpp:113` and `Lifetimes/Read.cpp:229`. Three passes
    therefore have to agree on which calls idr-frames splits at. This is the shape AGENTS.md's never-line names:
    "tail position decided in four places, two of which had to agree".
    (read; measured: `git grep -n sccOf -- foreign/idr/lib foreign/idr/include`)
  - **Owner** L10 for the predicate (`Tail/Frames.h`), with L05
    (`Lifetimes/Plan.h`, `Decide.cpp`) and L08 (`Analysis/Ownership/Borrows.cpp`)
    for the callers. **Remaining:** declare one predicate beside
    `runsCallsOnFrames` or in `Tail/Frames.h`, with an overload over a row's
    `solver::Call` for `Decide.cpp`. Delete `continuesOnFrame`, Borrows'
    `framed`, `Frames.h`'s own test and the inline test in `Decide.cpp:48`,
    and have each caller ask the one predicate (`Lend.cpp:113` and
    `Read.cpp:229` included).

### D7: the ladders (D126's lanes, in flight)

- **D7, a ladder over our own types or over ops is an interface, an
  overload set or one fold** — **Partial**, in flight under D126.
  - Recheck 3's item is closed: `lib/Transforms/Narrow/Widths.cpp:84`
    now reads `isa<CastOpInterface, SelectLikeOpInterface>`. (read)
  - Callbacks are template parameters: no `std::function` in `lib/`,
    `include/` or `tools/`. The 30 `function_ref`s are upstream's
    `verify(emitError)` signatures and interface methods. `TypeSwitch` is
    unused (`include/idr/Support/Match.h:18`).
  - Two `isa<A, B>` lists of op classes remain, both judged structural
    by recheck 3: `lib/Transforms/Expect/Vectorized.cpp:23` and
    `Narrow/Widths.cpp:50`.
  - There are 591 `isa`/`dyn_cast` sites outside `Generated/`, the count
    D126 is driving down (bb8ce09c recorded 590).
  - (measured: `git grep -nE '(isa|dyn_cast)<' -- lib include tools ':!include/idr/IR/Generated' | wc -l`
    from `foreign/idr`; `git grep -c 'std::function'`; `git grep -n function_ref`)
  - **Owner** D126 round 2c and its per-file lanes. **Remaining:** D126's
    queue (`audits/p0/verify/handoffs/`, round 2c). Each site that tells
    our types or ops apart becomes a method declared in
    `spec/Core/Interfaces.idr`, and its ladder is deleted. Nothing beyond
    D126 is owed for D7.

### D44: 0011's O3 and O8 not on 0015's layer (L16, L20)

- **D44, 0011 whole on 0010's A0 and 0015's R1 and R2** — **Partial**.
  - `compiler/idris-mlir.ipkg:7` depends on `idris-mlir-checker`,
    `idris-mlir-spec` and `mlir-hash`, not `mlir-relational`. No module of
    `compiler/` or `harness/` imports `Relational.*` (measured:
    `grep -rnE '^import (public )?Relational' compiler harness`, 0 hits).
  - The translation's semi-naive worklist is still written in the
    frontend (`Frontend/Finite.idr:23-32`). C175 says it runs on R2's
    fixpoint (`libs/mlir-relational/Relational/Fixpoint.idr`).
  - O8, the laws as queries on every compilation, is absent (measured:
    `grep -rn -i '\blaws\?\b' compiler/src/IdrisMLIR/Frontend compiler/src/IdrisMLIR/Emit`,
    0 hits).
  - D125 took R1's join out of P0 for O5, so only R2 has a planned
    reader.
  - 0010's A0 is written: the arena is `compiler/checker/src/Core/TT/Stored.idr`.
    0003's 62 items were not re-enumerated here: C136 places them, and
    `proposals/0003-facts-once.md` keeps no per-item status. (read, measured)
  - **Owner** L16 (the frontend), L20 (`libs/mlir-relational`).
    **Remaining:** add `mlir-relational` to the frontend's `depends`, and
    run `Finite.idr`'s generations as R2's fixpoint over the instance
    table (C175), deleting the hand worklist. Then write O8's laws as
    queries, or bring a narrowing of O8 to the coordinator.

### D49, D51: the upstream dialects' Idris modules (INT runs the generator; L16 owns the files)

- **D49 as C229 applies it to D51's outputs: no stamp** —
  **Partial**.
  - Thirteen committed modules still end with a stamp, e.g.
    `compiler/src/IdrisMLIR/Syntax/Arith.idr:275`
    (`-- fingerprint: 4113087857-1021516 ...`). They were last written
    2026-10-20 (b9d4d592). (measured: `git grep -l 'fingerprint:' -- compiler`,
    13 files under `Syntax/`, `Dialect/`, `Encoding/Builtin.idr`)
  - Neither `tools/dialects.sh` nor `foreign/idr/tools/idris-mlir-tblgen.cpp`
    writes a stamp any more (`tools/dialects.sh:38-43`: "A module carries
    no stamp"). So `tools/dialects.sh check`, which
    `tests/dialects-current/run` runs in `test-mlir-tools`, would find
    all thirteen stale. (read)
  - **Owner** INT (the run), L16 (the files). **Remaining:** run
    `tools/dialects.sh generate` with the built `idris-mlir-tblgen` and
    commit the thirteen rewritten modules.
- **D51, the modules of every dialect the specification lists** —
  **Partial**.
  - `include/idr/IR/Generated/WrittenDialects.txt` lists `linalg`,
    `bufferization` and `scf`. `compiler/idris-mlir.ipkg:28-30,42-44`
    lists their `Syntax` and `Dialect` modules, and
    `compiler/src/IdrisMLIR/Emit/Tensors.idr:22` imports
    `IdrisMLIR.Dialect.Linalg`.
  - None of the six files is committed: `compiler/src/IdrisMLIR/Dialect/`
    holds only Arith, Builtin, Idr, Math, MemRef, Tensor and UB. (measured:
    `ls compiler/src/IdrisMLIR/Dialect compiler/src/IdrisMLIR/Syntax`)
  - The rest of D51 holds. Recheck 3's string ladders are gone:
    `tools/idris-mlir-tblgen.cpp:470-509` reads an attribute's kind off
    upstream's record (`attrRows`, each record named once and resolved
    once, `:520-543`), and `:925-956` keeps one table of C++ parameter
    spellings, each written once. That is 14 T06's remedy. (read)
  - **Owner** INT (the run), L16 (the files). **Remaining:** the same
    `tools/dialects.sh generate` run writes `Syntax/{Linalg,Bufferization,SCF}.idr`
    and `Dialect/{Linalg,Bufferization,SCF}.idr`; commit them.

### D4: the plan's approval is not recorded (coordinator)

- **D4, no code until the whole plan is approved** — **Partial**, a
  record only.
  - `proposals/0000-mlir-native.md:5-9` still reads "the plan, being
    settled with the owner ... No code is written until the owner
    approves the whole plan (D4)". C153 is still "for the owner's review
    in the plan's approval" (`:4386`, `:5312`).
  - Yet the cutover has been written on main since 28ef777e, and D123
    has since amended C153. P0 has no dated line saying when the whole
    plan was approved. (read)
  - **Owner** coordinator. **Remaining:** put the approval's date and the
    owner's words in §0's status and §4's "Settled", and re-point C153's
    two mentions to D123.

## Superseded parts

- **D40, the printed grade `!idr.q<1, own, T, ρ>`** — **Superseded**
  by D63 (lifetimes leave the type) and D88 to D90
  (`!idr.graded<uses, hold, T>`). The concept's name stands: "lifetime"
  is the code's word, `locality` is gone, and the `counted` hold
  replaces the `heap` constant (measured: `git grep -n '!idr\.q<\|locality'`
  over `foreign`, `compiler/spec` and `tests`, 0 hits).
- **D45, "each change lives in the fork ... `upstream/<bug>/pull-request.diff`"**
  — **Superseded** by D118 and D119: the checker is our code
  (`compiler/checker`) and tracks no upstream. Its mechanisms are D53 to
  D55's (below).
- **D55, the tuple's `upstream/fork-*/pull-request.diff` and PINS entry**
  (recheck 3's finding) — **Superseded** by D118 and D119, as above.
  The design itself is in the checker (`compiler/checker/README.md:657-670`,
  `ITypeOrValue`).

## Done

- **D1, D3, D5, D6, D8, D11, D17** — Done; process, no code.
- **D2** — Done. The solver layer is `lib/Analysis/Solver/` and
  `include/idr/Analysis/Solver/`. (measured: `ls`)
- **D9** — Done. Recheck 3's finding is closed:
  `lib/Transforms/Expect/ResetsUnshared.cpp:33-41` now asks
  `effects::eachOwnEffect`. Outside `Effects/`, the only readers of
  MLIR's effect instances are `include/idr/IR/Effects/Classify.h`,
  `lib/IR/Effects.cpp` and a transform op's own declaration at
  `lib/Target/Schedules.cpp`. One assertion asks upstream's `isPure`
  (`lib/Transforms/Tail/Outline.cpp:134`, L10), which agrees with the one
  API on an op that declares nothing. (measured: `git grep -ln 'MemoryEffectOpInterface\|getEffects('`)
- **D12, D18** — Done; there is no code of their own. The checker keeps
  upstream's flags and pragmas, and D18's form is D19's.
- **D13** — Done. `spec/Effects/LLVM.idr:139-143` withholds `willreturn`
  and `mustprogress` per atom. `lib/IR/OpsChecks.cpp:134-141` decides a
  constant divisor.
- **D14** — Done. `include/idr/IR/Generated/IdrOps.td:1988-1997`:
  `idr.io.exit` is a `Terminator` with no result, writing `Idr_ExitResource`.
  `spec/Effects/LLVM.idr:141` withholds `willreturn` from `exit`.
- **D15** — Done. `tools/check-units.py` is gone, and no
  `.py`/`.yaml`/`.awk` file of ours is tracked. (measured: `git ls-files | grep -E '\.(py|yaml|yml|rb|pl|awk|js|lua)$'`
  outside `third_party/`, 0 hits)
- **D16** — Done. Every `.td` of ours is under
  `include/idr/IR/Generated/`, in `foreign/idr/generated.manifest`.
  (measured: `git ls-files 'foreign/**.td'`)
- **D19** — Done. `spec/Pipeline/Pipeline.idr:51,95` runs
  `SCFToControlFlow` at the lowering. `cf` ops are built only in
  `lib/Conversion/Matches.cpp`.
- **D20** — Done. No world type, `world.new` or world operand is in
  `spec/`, `Generated/` or `lib/`. Emit drops the world at its boundary
  (`compiler/src/IdrisMLIR/Emit/Bodies.idr:110-118`, `present` filters
  `WorldT`).
- **D21** — Done. `idr.check.nonzero` returns `$checked`, its operand
  refined (`IdrOps.td:1800-1811`), and writes only `Idr_CrashResource`.
- **D22** — Done. `lib/IR/Func/Rows.cpp:3-7` holds the row to the one
  derivation per function. `lib/Transforms/Effects/Writer.cpp:81`
  derives it.
- **D23** — Done. The `alloc` and `free` atoms are on the heap
  (`spec/Effects/Atom.idr:88-89`), and out of memory is status 111
  (`spec/Runtime/Endings.idr:226`).
- **D24** — Done. `tests/uniqueness-shared-rebuild/` and its `near/`
  exist. `idr-demand` is gone: `lib/Transforms/Optimize/Demand.cpp` is
  unread-parameter dropping, not the promise.
- **D25** — Done.
  - `upstream/65-early-exits` to `71-early-exit-index-switch` each have
    a test. PINS.md:579 has the entry.
  - `idr.join` implements `HasBreakingControlFlowOpInterface`
    (`IdrOps.td:637`), and `data.match`, `lit.match`, `join`, `loop`,
    `index.assume` and `io.unsafe_run` carry `PropagateControlFlowBreak`.
  - The last fast-forward was b9c0b2bb (2026-10-21).
  - The checkouts of `modular` and `simdutf` differ from their gitlinks
    in the working tree only.
- **D26** — Done. `tests/runtime-frame-bound/`.
- **D27, D28, D29** — Done.
  - The tree and names are in `spec/Effects/Resource.idr:81-` and
    `Atom.idr:79-89`, and the atoms print `runtime_state`, `memo_state`
    and `divergence`.
  - The 36 hits for `IOResource` and kin are generated record names
    `Idr_<Name>Resource`, uniform over all ten resources
    (`IdrBase.td:356-365`). That is ODS's naming of a `Resource` record,
    not the deleted C++ classes, which are `idr::effects::IO` and kin.
  - (measured: `git grep -nE 'IOResource|...'`; read)
- **D30, the one fact and its verifier** — Done, in flight (2b-T).
  - `include/idr/IR/Tail.h:3-22` holds it. `lib/IR/Tail.cpp:153-218`
    reports a missed or misplaced tail call as an internal error.
  - `lib/Conversion/Lower/Functions.cpp:216` sets `MustTail`.
  - `TailPosition.cpp`, `TailCallPlan.cpp`, the cycle deciders and
    `numFrameBound` are gone. Today's `frameBound` is D26's bound
    (`lib/Transforms/Counting/Bound.cpp:295`).
  - (measured: `git ls-files | grep -E 'TailPosition|TailCallPlan|Recursion\.cpp'`, 0)
- **D31** — Done. The frame stack is a family member, linear and never
  counted, one per awaited result (`include/idr/IR/Families/Declaration.h:103-112`).
- **D32, the static bound and the guard** — Done.
  - `lib/Driver/StackBound.cpp` weighs the call graph by code
    generation's frame sizes.
  - `runtime/Start/Runner.cpp:50-56` makes reaching the guard an
    internal error.
  - There is no 64 GiB reservation. (measured: `git grep -n -i '64 GiB\|<< 36'`
    over `runtime`, `foreign/idr` and `tools`: only rewrite literals)
- **D34** — Done, `Trmc.cpp` in flight. `!idr.dest`
  (`IdrTypes.td:191`) and the `modulo_context` case (`IdrBase.td:213`).
- **D35** — Done. `runtime/Alloc/Cells.cpp:36-43`: the span is aligned
  for the prefetcher, and nothing is reserved before it is used.
- **D36** — Done. `runtime/Platform/Posix/Cgroups.cpp:279-292` reads the
  cgroup's `memory.max` and, by D65, `memory.swap.max`.
  `runtime/Alloc/Cells.cpp:172-179` counts in `StatsRange`. No variable
  of ours is read from the environment.
- **D37** — Done. `spec/Runtime/Endings.idr`: the closed sets and the
  statuses 111 and 126, and `Signal = Abort | BrokenPipe`. The message
  form is at `runtime/End/End.cpp:74-77`, and `mainReturned` is gone. The
  harness writes expected stderr; it parses none
  (`harness/Sem.idr:371`).
- **D38** — Done. `idris_rt_crash_at`
  (`runtime/Generated/idris_rt_ops.h:285`, `runtime/End/End.cpp:293`) is
  called cold from `lib/Conversion/Runtime.cpp:190`.
- **D39** — Done, as D63 amends it. The lifetime ops are
  `IdrOps.td:313-498`, and `isStatic` and the owned verifier are gone.
  An element read is `Owned` only where something may overwrite its
  memory (`include/idr/Transforms/Counting/Placement.h:41-50`).
- **D40** — Done, with its printed grade superseded (above). The
  concept is a lifetime throughout, and `locality` is gone.
- **D41** — Done. `include/idr/IR/Numeric/` holds the templates.
  `runtime/Big/Arithmetic.cpp:7-8,19-22,113-121` includes the one
  `euclid` and `static_assert`s it.
- **D42** — Done. `libs/mlir-array/Array/Core.idr`'s 13 `%extern`s are
  the generating set of `spec/Arrays/Generating.idr`.
- **D43** — Done.
  - `array.tabulate`, `fold_last` and `scan_last` carry
    `DestinationStyleOpInterface` and `TilingInterface`
    (`IdrOps.td:710-800`).
  - `upstream/27-one-shot-tensor-like-copy` and
    `64-tensor-like-per-instance` have their tests and PINS entries
    (`PINS.md:1139-1160`).
  - `GeneratingOpInterface`, `Idr_Iteration`, `StoreModel`,
    `HeapReadModel`, `heldType` and `DataRemap` are gone (measured, 0 hits).
  - Recheck 3's finding is closed: 0009 is amended in its body
    (`proposals/0009-typed-apl/README.md:573-574`).
- **D45** — Done, as D53 to D55 amend it, with its fork clause
  superseded (above). No elaborator count refuses a program.
- **D47** — Done. `.claude/skills/representation-first/SKILL.md:104-105`.
- **D48** — Done. `Idr_FamilyAttr` (`IdrTypes.td:305`).
  `Idr_DataTableAttr`, `DataBody.cpp`, `MutableType`, `!idr.box` and
  `#idr.types` are gone. (measured, 0 hits)
- **D49, the specification's outputs** — Done. Recheck 3's finding is
  closed.
  - `compiler/src/IdrisMLIR/Dialect/Idr.idr`, `Encoding/Wire.idr` and
    `Encoding/Idr.idr` are specgen's, in `foreign/idr/generated.manifest:62-64`.
  - `tests/spec-current` (suite `check`) regenerates every output and
    the manifest and compares them.
- **D50** — Done. `IdrRules.txt`, `IdrPassRoles.txt` and
  `IdrPassStages.txt` are gone. The frontend imports
  `Spec.Runtime.Endings`, `Spec.Core.Rules`, `Spec.Runtime.Clocks`,
  `Spec.Grades.Grade` and `Spec.Pipeline.Stage`. (measured: `git grep -hE '^import ... Spec'`)
- **D52** — Done. There is no `Double`, `SortedMap`, environment, clock
  or directory read in `spec/Generator/`. `tests/spec-self` reproduces
  the outputs under idris-mlir. (measured)
- **D53, D54** — Done.
  - `compiler/checker/README.md:645-656` describes the path rule and
    `GrowingSearch` (`compiler/checker/src/Core/Context.idr:1047`).
  - The pragmas are unknown to the parser (`README.md:96-99`).
  - There is no depth in `Core/AutoSearch.idr`.
- **D55** — Done. `%ambiguity_depth` is gone, and `ITypeOrValue` has
  64 sites. Its diff clause is superseded, above.
- **D56** — Done. There is no violation: INT's builds are the Idris half
  (D111) and the typecheck build (D120). The lane commits read for this
  report each end "Nothing was built".
- **D57** — Done, in flight (L14x).
  - At HEAD the graph is a true one: a union-find
    (`include/idr/Transforms/EGraph/Engine.h:29-57`, D123).
  - Its rounds end by construction (`:46`), and a budget leaves code
    less optimized and refuses nothing.
- **D59** — Done. `!idr.nat` carries its index term
  (`IdrTypes.td:120-122`).
- **D60** — Done, as C239 and C262 narrow it: only an input's axis
  becomes static.
  - `lib/IR/Families/Substitute.cpp:175-183` (`mapSignature`, the one
    substitution).
  - The frontend's `extentDim` is gone (ab02104e).
  - 0009 is amended (`proposals/0009-typed-apl/README.md:330-340`).
- **D61** — Done. `spec/Effects/LLVM.idr:151-159`: a write through an
  exclusive owned parameter is `argmem` read-write, everything else read
  only.
- **D62** — Done. `spec/Grades/Grade.idr` proves the laws by case
  split, and `Declarations.idr` prints the tables. There is no affine,
  borrow or fractional part.
- **D63** — Done. `!idr.lifetime` (`IdrTypes.td:72`), `idr.lifetime` and
  its siblings by source. There are no lifetime variables in types.
- **D64** — Done. `spec/Runtime/Endings.idr:200,307,318`:
  `Crashed Unreportable` exits with the crash status.
  `runtime/End/End.cpp:131-136` writes `exit status N cannot be
  reported` at the site, which `idr.io.exit` holds (`IdrOps.td:1994`).

## Count

By ruling, each at its least-done row:

| Verdict | Rulings |
| --- | --- |
| Done | 53 |
| Partial | 10: D4, D7, D10, D32, D33, D44, D46, D49, D51, D58 |
| Open-owner | 1: D30, whose measurement row is Partial |
| Missing | 0 |
| Regressed | 0 |

Superseded parts: three, in D40, D45 and D55, whose rulings are counted
Done.

By row: 13 not done, and 3 Superseded.
- Partial, 12: D4, D7, D10, D30's measurement, D32's measurement, D32's
  framing, D33, D44, D46, D49, D51, D58.
- Open-owner, 1: D30 with D58.
- Superseded, 3: D40's, D45's and D55's parts. Of these, D55's was
  recheck 3's open finding.

Of the 13, four await only a measurement on a build (D30, D32, D33,
D58), and two only a generator run on a built toolchain (D49, D51).

## Seen outside the range

- **D122.** `proposals/0009-typed-apl/README.md:566-568` still says a
  field's buffer is writable only where its cell is `unique deep`
  (C105). D122 gives `unique self` over a held buffer's storage.
- **0010's status.** `proposals/0010-array-interpreter.md:12-14` says
  there is "no term arena" in `compiler/checker/src`, but
  `compiler/checker/src/Core/TT/Stored.idr` is one.
