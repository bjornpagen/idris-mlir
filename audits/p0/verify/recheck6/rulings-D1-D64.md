<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Recheck 6: the owner's rulings D1 to D64 against the tree

HEAD was 9f4889dd at start and 3beee5fd at finish. Between them:
- e72a024f (L12v) and 13b0e15e (C280) touch bufferization and the
  record only;
- 29153f20 (L16em) deletes the frontend's `Acyclic` termination;
- 2d7ee52d (L11z, C279) touches the driver, the pipeline and tests;
- e518e35c records C281, which amends C257's route to D46's deletion;
- d093dbfb (L17bc) touches the checker's case trees and adds `KPlus` to
  its vocabulary;
- 3beee5fd adds recheck 6's report on C131 to C279.

The cited lines in the files those commits touch were read again at
e518e35c and 3beee5fd: `Emit/Bodies.idr`, `Translate/State.idr`, the
record, and the checker (`Core/Context.idr:1001`, the 64 `ITypeOrValue`
sites, no depth pragma). No verdict changed. C281 changes how D46's
remaining work is done, not whether it is done (below). Nothing was
built, typechecked, generated or run.

Every row recheck 5 left not Done was read again in the code, and each
Done row was checked for a regression with one grep or one read line.
None regressed. Two rows are closed since recheck 5:
- D4's record: P0's status and D4's row now carry the approval.
- D32's framing: one predicate in `ProgramGraph`, 0642ef67 (L10z).

D30 with D58 is no longer open with the owner. D129 settled it, and two
of its three parts are in the tree.

Files were read as HEAD's text (`git show HEAD:`, `git grep ... HEAD`).
The working tree holds other lanes' unstaged edits, which this report
does not read. Paths are under `foreign/idr/` unless they start with
another top-level directory. `spec/` is `compiler/spec/IdrisMLIR/Spec/`,
and `p0.md` is `proposals/0000-mlir-native.md` at e518e35c. Owners are
from `ownership.json`, by longest prefix. *read* means the cited line was
opened; *measured* gives the command.

## Not done

### D10, D46: the growth proof's conclusion still checked at run time (L16)

- **D46, as D68 and D128 complete it: the run-time re-check of every
  request goes** — **Partial**.
  - At HEAD, `compiler/src/IdrisMLIR/Frontend/Finite.idr:171-172` is
    `unsound`, an internal error. `:180-185` is `heightWithin` and
    `:190-194` is `sizedWithin`. `judge` runs both on every request at
    `:215-216`.
  - `Frontend/Translate/Types.idr:601-606` is `boundsHold`, called at
    `:906`, with `sizedWithin` again at `:907`. (read)
  - L16ee (cc71ed8b) landed C257's obligation 2 and D128's walk of a
    settled form as written. It says itself that obligations 4 to 6 and
    the reading lemma are not done.
  - C281 (`p0.md:2663`, 2026-10-23, for the owner's review) changes the
    route. The growth model's walk decides every request and records it
    in its tree, and the translation folds that tree. With the lemma's
    induction over the model's walk alone, that deletes `unsound`,
    `heightWithin`, `sizedWithin`, `boundsHold` and the translation's own
    request computation.
  - `audits/p0/verify/handoffs/L16-threading-design.md` §8 and §9 are the
    same deletion list, written before C281.
  - **Owner** L16 (`compiler/src`). **Waits on** the fresh lane that
    carries C281 (L16em stopped on it, e518e35c). **Remaining:**
    1. Build C281's annotated tree. Each node holds its decided request:
       the callee, the keyed arguments, `DrawnFrom` and `HeldAs`.
    2. Fold it in the translation.
    3. Prove the lemma's induction over the model's walk (the steps
       listed in Covers' header).
    4. Delete `Finite.idr:171-194`, the judging of bounds at `:215-216`,
       `Types.idr:601-606` and its call at `:906-907`, and `TS.bounds`
       and `TS.sizes`, keeping the universe at quantity 0.

    A request then carries its `Inside b l` from the proof.
- **D10** — **Partial**: one fact is still paid for after it is known,
  D46's above. The framing half recheck 5 named is closed (D32, below).

### D30, D58: a tail call's data result layout (D129: two parts in, the array case in flight)

- **D30 with D58, as D129 settles it (B\*)** — **Partial**, in flight.
  - The owner ruled on 2026-10-23 (`p0.md:1917`; §4 reads "Open: none",
    `p0.md:5504`).
  - **The verifier half is done.** `lib/IR/Func/Call.cpp:281-289` runs
    `tail::verifyLayouts` on every tail call beside the given-back
    results. `lib/IR/Tail.cpp:378-394` reports a residual mismatch as an
    internal error. `verify(FuncOp)` reports a tail lost to a re-pack,
    once layouts agree (`Tail.cpp:329-346`). They agree from Graded on,
    a stage fact (`:267-269`, C265). (read)
  - **The specializer's half is done for data results** (39a38d24, L18y;
    8b218c36, L04x for D130's mark). `lib/Transforms/Specialize/Requests.cpp:192`
    marks a tail call `TailStanding::LostToLayout`, and
    `Specialize/Open.cpp:111-115` gives the copy's result type with
    `LayoutMark::Open`. (read)
  - **The array case, which D129 calls C262's case of the same rule, is
    not done.** The queue's L04v item (`L16-queue.md`, "From L04v") says
    an array result whose element re-packs at a tail call is an internal
    error before bufferization. "L18x (D129 for array results ...)" is
    dispatched ("Dispatched after INT-23"). (read)
  - **Owner** L18 (`lib/Transforms/Specialize/`), in flight under L18x.
    **Remaining:** the copy keyed to the caller's element layout, marked
    open where an index stays unwritten, for an array result whose
    element re-packs. Then the internal error has no program that reaches
    it.

### D30, D32, D33, D58: the measurements the rulings order (INT, owner's machine)

All four rows are unchanged since recheck 5.
- **D30, the cost of `tailcc` on every function of the program** —
  **Partial**.
  - No measurement is recorded: `grep -rln tailcc audits/` outside the
    recheck reports finds only design and audit text.
    `lib/Conversion/Lower/Functions.cpp:175, 225, 307-310` lowers every
    program function and call under `tailcc`. (read, measured)
  - **Owner** INT. **Waits on** the owner's machine (the LLVM build).
    **Remaining:** measure stage 1 with and without `tailcc` on functions
    only the module's calls reach. Record the number with its build and
    input. The ruling forbids weakening it on the result.
- **D32 and D33, the tools' stacks and the outside code's margin** —
  **Partial**.
  - `CMakeLists.txt:177-215` says what is measured. Every target entry
    still calls `idris_mlir_unmeasured_stacks()` (`:262, 279, 297, 330`),
    which refuses to configure without the three numbers (`:216-223`).
    (read)
  - D33's other half stands: `upstream/10-recursive-attribute-parser/`
    holds `llvm.patch`, and patches 80 to 93 make MLIR's walks iterative.
    (measured: `ls upstream`)
  - **Owner** INT. **Waits on** the owner's machines. **Remaining:** on
    each of the four targets, measure `IDRIS_MLIR_TOOL_STACK_BYTES`,
    `IDRIS_MLIR_TOOL_SIGNAL_BYTES` and `IDRIS_MLIR_OUTSIDE_STACK_BYTES`
    as `CMakeLists.txt:177-215` says. The runs include MLIR's deepest
    recursion on the stage-1 module and `tests/scale-nesting*` (D33).
    Replace each entry's call with the numbers, their build and input.
- **D58, the shape budget** — **Partial**.
  - `spec/Families/Layout.idr:89-99` has `shapeBudget = 16`, with its doc
    saying it is to be measured before it is fixed. It is generated as
    `include/idr/IR/Generated/Families.h.inc:218`. (read)
  - **Owner** INT (the measurement); L04 owns the number. **Waits on**
    the owner's machine. **Remaining:** measure on stage 1 where the
    copies stop paying. Write the value into `Layout.idr` with its
    measure, build and input.

### D7: the ladders (D126, in flight)

- **D7, a ladder over our own types or over ops is an interface, an
  overload set or one fold** — **Partial**, in flight under D126.
  - Callbacks are template parameters: there is no `std::function` in
    `lib/`, `include/` or `tools/`, and `TypeSwitch` is unused
    (`include/idr/Support/Match.h:18`).
  - There are 595 `isa`/`dyn_cast` sites outside `Generated/`, against
    recheck 5's 591. (measured: `git grep -nE '(isa|dyn_cast)<' HEAD --
    foreign/idr/lib foreign/idr/include foreign/idr/tools
    ':!foreign/idr/include/idr/IR/Generated' | wc -l`)
  - The two `isa<A, B>` lists of upstream op classes recheck 3 judged
    structural remain: `lib/Transforms/Expect/Vectorized.cpp:23` and
    `Narrow/Widths.cpp:50`. Every other multi-class `isa` names upstream
    interfaces or types, which D126 admits. (read)
  - Not in recheck 5: five `if constexpr (std::is_same_v<OpT, …Op>)`
    branches in templates over ops. Each names one op class where an
    ODS fact would answer, the form D7's "a concept ... never lists ops"
    excludes. All predate recheck 5 (git blame: 2026-10-15 to 2026-10-22).
    - `include/idr/IR/IdrDialect.h:173-187` (`ProgramOp`, `ModuleOp`; L03);
    - `lib/Transforms/Columns/ArrayOps.cpp:45` (`ArrayScanLastOp`, to
      reset its `operandSegmentSizes`; L12);
    - `lib/Transforms/StructureLoops/Linalg.cpp:151` (`ArrayScanLastOp`; L12);
    - `lib/Transforms/Narrow/Ops.cpp:125-133` (`arith::CmpIOp`, `TruncIOp`,
      `MaxSIOp`; L12).
  - **Owner** D126's lanes: L03 for `IdrDialect.h`, L12 for the other
    three. **Remaining:** D126's queue, plus the five sites above, each
    asking the trait or interface the branch stands for:
    `AttrSizedOperandSegments` for the scan's segment sizes, a
    specification-declared method elsewhere.

### D44: 0011's O3 and O8 not on 0015's layer (L16, L20; one reading for the coordinator)

- **D44, 0011 whole on 0010's A0 and 0015's R1 and R2** — **Partial**,
  unchanged.
  - `compiler/idris-mlir.ipkg:7` depends on `idris-mlir-checker`,
    `idris-mlir-spec` and `mlir-hash`, not `mlir-relational`. No module
    of `compiler/` or `harness/` imports `Relational.*`. (measured:
    `git grep -nE '^import (public )?Relational' HEAD -- compiler harness`,
    0 hits)
  - The translation's semi-naive worklist is still written in the
    frontend (`Frontend/Finite.idr:23-32`), though R2's fixpoint exists
    (`libs/mlir-relational/Relational/Fixpoint.idr`) and C175
    (`p0.md:4887`) puts the translation on it.
  - O8, the laws as queries on every compilation, is absent. (measured:
    `git grep -n -i -E '\blaws?\b' HEAD -- compiler/src/IdrisMLIR/Frontend
    compiler/src/IdrisMLIR/Emit`, 0 hits)
  - `proposals/0011-data-oriented-frontend.md:415` still stands O8 on
    0015's R1. D125 (`p0.md:1865`) builds no part of R1 in P0 for O5,
    so O8 has no layer under it in P0 as written.
  - **Owner** L16 (`compiler/`), L20 (`libs/mlir-relational`). **Waits
    on** C281's lane, which rewrites `Finite.idr`, and on one reading by
    the coordinator. C281's fold of the model's tree must leave C175's
    shape of the translation, a fixpoint over the instance table, as it
    is; or the coordinator states which shape stands. **Remaining:**
    1. Add `mlir-relational` to the frontend's `depends`.
    2. Run the instance table's generations as R2's fixpoint and delete
       the hand worklist.
    3. Write O8's laws as queries on R2, or bring the coordinator a
       narrowing of O8's dependency on R1.

### D49, D51: the upstream dialects' Idris modules (INT, on this machine; L16 owns the files)

- **D49 as D67 and C229 apply it to D51's outputs: no stamp** —
  **Partial**, unchanged.
  - Thirteen committed modules end with a stamp, e.g.
    `compiler/src/IdrisMLIR/Syntax/Arith.idr`. (measured: `git grep -l
    'fingerprint:' HEAD -- compiler`, 13 files: `Syntax/` and `Dialect/`
    for Arith, Builtin, Math, MemRef, Tensor and UB, and
    `Encoding/Builtin.idr`)
- **D51, the modules of every dialect the specification lists, holding
  the admitted ops alone** — **Partial**. Worse than recheck 5 said: the
  committed modules are stale in substance as well as in their stamps.
  - `include/idr/IR/Generated/WrittenDialects.txt:13-15` lists `linalg`,
    `bufferization` and `scf`. `compiler/idris-mlir.ipkg:28-30, 42-44`
    names their modules. `Emit/Tensors.idr:22` and
    `SyntaxSamples.idr:31, 49` import them. None of the six is committed.
    (measured: `git ls-tree --name-only HEAD compiler/src/IdrisMLIR/Dialect/
    compiler/src/IdrisMLIR/Syntax/`)
  - INT already generates all eighteen on this machine with the typecheck
    build's `idris-mlir-tblgen` (`build/typecheck/foreign/idr/idris-mlir-tblgen`,
    D120). It writes them under `build/int14/dialects/` and copies them
    into each export: `build/int22/dialects-copied.txt` reads "new
    compiler/src/IdrisMLIR/Dialect/Linalg.idr" and "overwrites ...
    Dialect/Arith.idr". It never commits them.
  - The committed modules differ from INT's in substance. HEAD's
    `Dialect/Arith.idr` against `build/int14/.../Dialect/Arith.idr`
    differs by 257 lines: the committed one predates the admitted-ops cut
    and holds builders of every op. `Dialect/Tensor.idr` differs by 98
    lines. (measured: `diff <(git show HEAD:$f) build/int14/dialects/$f | grep -c '^[<>]'`)
  - The binary predates the generator's last change: it was built
    2026-10-22 15:00, and `foreign/idr/tools/idris-mlir-tblgen.cpp` last
    changed at 04d7cfcc, 20:21 the same day. Spec round 4 (653608e8)
    changed admitted records since. So the modules must be generated
    again, not copied from `int14`.
  - The queue files this item under "INT, on the owner's machine". It
    needs no LLVM build: `tools/dialects.sh generate typecheck`
    (`tools/dialects.sh:29-33`, L06u's f28d6e62) and D120's typecheck
    build run here.
  - **Owner** INT (the run), L16 (the files). **Remaining:**
    1. Rebuild the typecheck build's `idris-mlir-tblgen`.
    2. Run `tools/dialects.sh generate typecheck`.
    3. Commit the eighteen modules: thirteen rewritten without stamps and
       with the admitted ops alone, and `Syntax/` and `Dialect/` for
       Linalg, Bufferization and SCF.

## Closed since recheck 5

- **D4, no code until the whole plan is approved** — **Done** (a record
  only).
  - `p0.md:5-10`: "The owner approved the plan on 2026-10-21 (D4) and the
    cutover started that night from 28ef777e".
  - D4's row (`p0.md:185-189`) quotes the owner ("i want you to
    personally update the entire verificatino swarm to BE the swarm
    cutover. then we'll start it tonight") and says C153 was approved
    with the plan. (read; 7aefe545)
  - A wording nit, not an obligation: three mentions still read "for the
    owner's review in the plan's approval", C153's own row (`p0.md:4670-4671`)
    and §4 (`:5509`, `:5601`). §4's "Settled" list names no D4. The
    coordinator may point them at D4's row and D123.
- **D32, a non-tail call on its caller's cycle pushes its rest as a frame:
  which call does, decided once** — **Done** (0642ef67, L10z).
  - The predicate is written once:
    - `include/idr/Analysis/Solver/ProgramGraph.h:145-159` (`runsOnFrame`,
      its doc naming every asker);
    - `lib/Analysis/Solver/ProgramGraph.cpp:168-170`
      (`returnsToCaller(kind) && sccOf(callee) == from`).
  - The per-component fact `runsCallsOnFrames` (`ProgramGraph.h:165`) is
    laid from the predicate at `ProgramGraph.cpp:175-181`.
  - Every caller asks it:
    - `include/idr/Transforms/Tail/Frames.h:140`;
    - `lib/Analysis/Ownership/Borrows.cpp:182, 313`;
    - `lib/Transforms/Lifetimes/Lend.cpp:152` and `Read.cpp:229`.

    `Decide.cpp:49` asks the neighbouring `onFrameStack`
    (`ProgramGraph.h:171-173`), defined on the same fact.
  - `continuesOnFrame` and Borrows' `framed` are gone. The remaining
    `sccOf(callee) == …` comparisons (`Ranges.cpp:274`,
    `Contracts.cpp:290, 325`, `Writer.cpp:115`, `Inline.cpp:70`,
    `Decide.cpp:258`) ask whether a callee shares the caller's component
    for other purposes (ranges, the cycle contract, amounts, inlining),
    not whether a call runs on a frame. (measured: `git grep -n 'sccOf('
    HEAD -- foreign/idr/lib foreign/idr/include`; read)

## Superseded parts

Unchanged from recheck 5:
- **D40, the printed grade `!idr.q<1, own, T, ρ>`** — **Superseded** by
  D63 and D88 to D90. (measured: `git grep -n '!idr\.q<\|locality' HEAD --
  foreign compiler/spec tests`, 0 hits)
- **D45, "each change lives in the fork ... `pull-request.diff`"** —
  **Superseded** by D118 and D119.
- **D55, the tuple's `upstream/fork-*/pull-request.diff` and PINS entry**
  — **Superseded** by D118 and D119. The design is in the checker
  (`ITypeOrValue`, 64 sites, measured).
- Read beside them, not counted: D62's coordinates, "quantity ×
  permission × lifetime", are superseded by D88 (`p0.md:1290-1292`) and
  D90. D62's rule, no grade richer than Idris's with its laws proven in
  the specification, is Done below.

## Done

Each row was checked at HEAD by the read or count given. None regressed.
- **D1, D3, D5, D6, D8, D11, D12, D17, D18** — Done; process or meaning,
  no code of their own.
- **D2** — Done. `lib/Analysis/Solver/` holds six entries. (measured)
- **D9** — Done, and better than at recheck 5. Outside `Effects/`, the
  only reader of MLIR's effect instances is a transform op's own
  declaration (`lib/Target/Schedules.cpp:304`). Outline's `isPure`
  assertion now asks the one API (7878bda0). (measured:
  `git grep -ln 'MemoryEffectOpInterface\|getEffects(' HEAD`;
  `git grep -n 'isPure('`, 0 hits)
- **D13, with D102** — Done. `spec/Effects/LLVM.idr` withholds
  `WillReturn` and `MustProgress` for `Divergence` and `WillReturn` for
  `Crash` (`withholds`). C65's `idr.may_loop` and L02x/L02y keep a
  function Idris did not prove divergent by its ops and its cycles.
- **D14** — Done. `include/idr/IR/Generated/IdrOps.td:2009-2012`:
  `idr.io.exit` is a `Terminator` writing `Idr_ExitResource`; `withholds
  Exit = [WillReturn, NoFree]`.
- **D15** — Done. No `.py`, `.yaml`, `.awk` or similar file of ours is
  tracked. The 39 hits are upstream snapshots under `sources/`. (measured:
  `git ls-files | grep -vE '^(third_party|sources)/' | grep -E
  '\.(py|yaml|yml|rb|pl|awk|js|lua)$'`, 0 hits)
- **D16** — Done. No `.td` of ours outside `include/idr/IR/Generated/`.
  (measured: 0)
- **D19** — Done. `spec/Pipeline/Pipeline.idr:51, 68`
  (`SCFToControlFlow`). `cf` ops are built only in
  `lib/Conversion/Matches.cpp:350, 360`. (measured: `git grep -nE
  '(^|[^s])cf::[A-Za-z]+Op'`)
- **D20** — Done. No world type, `world.new` or `!idr.world` in `spec/`,
  `Generated/` or `lib/` (measured: 0). Emit drops the world at its
  boundary (`Emit/Bodies.idr:118`, read at e518e35c).
- **D21** — Done. `idr.check.nonzero` returns `checked` typed as its
  operand and writes only `Idr_CrashResource` (`IdrOps.td:1822-1823`).
- **D22** — Done. `lib/IR/Func/Rows.cpp` and
  `lib/Transforms/Effects/Writer.cpp` stand.
- **D23** — Done. `spec/Runtime/Endings.idr:226` (status 111).
- **D24, with D70 to D72, D110 and D122** — Done.
  `tests/uniqueness-shared-rebuild/` holds `near/`.
  `lib/Transforms/Optimize/Demand.cpp` is unread-parameter dropping.
- **D25, with D76 and D82** — Done.
  - `upstream/65-early-exits` to `71-early-exit-index-switch` and their
    seven `tests/upstream-early-exit*` exist, with `PINS.md:566-588`.
  - `idr.join` and `idr.loop` implement `HasBreakingControlFlowOpInterface`
    (`IdrOps.td:644, 677`).
  - No `!idr.cont`. The last fast-forward (b9c0b2bb, 2026-10-21) is
    within the week. (measured)
- **D26** — Done. `tests/runtime-frame-bound`.
- **D27, D28, D29** — Done. No C++ class named `IOResource` and kin
  (measured: 0); the atoms are `Spec.Effects.Atom`'s.
- **D30, the one fact and its verifier** — Done.
  - `include/idr/IR/Tail.h` holds the one reading (`tailsOf`,
    `:67-75`).
  - `lib/IR/Tail.cpp:298-374` reports a missed, misplaced or lost tail
    call as an internal error.
  - `TailPosition.cpp`, `TailCallPlan.cpp`, the cycle deciders,
    `numFrameBound` and the decider's climb `inTailPosition` are gone.
    (measured: `git ls-files | grep -E 'TailPosition|TailCallPlan|Recursion\.cpp'`,
    0; `git grep inTailPosition`, 0)
- **D31** — Done. `include/idr/IR/Families/Declaration.h:104-113`.
- **D32, the static bound and the guard** — Done.
  `lib/Driver/StackBound.cpp`, and no 64 GiB reservation (measured: 0).
- **D34** — Done. `Idr_DestType` (`IdrTypes.td:216`) and `modulo_context`
  (`IdrBase.td:218`). A call modulo a context left `nontail` is an
  internal error (`Tail.cpp:301-307`).
- **D35, D66** — Done. `runtime/Alloc/Cells.cpp:35-44`: aligned, nothing
  reserved before use.
- **D36, D65** — Done. `runtime/Platform/Posix/Cgroups.cpp:279-292`. The
  only `getenv` is the program's own `getEnv` primitive
  (`runtime/Io/Process.cpp:41`).
- **D37, D64, D81** — Done.
  - `spec/Runtime/Endings.idr:200` (`Unreportable`), `:255` (`Abort |
    BrokenPipe`).
  - `runtime/End/End.cpp:133`.
  - No `mainReturned` (measured: 0).
  - The harness writes expected stderr and parses none
    (`harness/Sem.idr:371`).
- **D38, D80** — Done. `runtime/Generated/idris_rt_ops.h:285`;
  `lib/Conversion/Runtime.cpp:190` calls it cold.
- **D39, D63, D78** — Done.
  - `!idr.lifetime` (`IdrTypes.td:73`).
  - No `isStatic` of ours: the two hits are upstream's
    `isStaticShapeAndContiguousRowMajor` and `isStaticAlloca`.
  - `include/idr/Transforms/Counting/Placement.h:41-52` makes an element
    read `Owned` only where something may overwrite it.
- **D40** — Done, its printed grade superseded (above).
- **D41** — Done. `include/idr/IR/Numeric/` (nine headers).
  `runtime/Big/Arithmetic.cpp:7-8, 22, 113, 121` includes and
  `static_assert`s the one `euclid`.
- **D42** — Done. `libs/mlir-array/Array/Core.idr`: 13 `%extern`s.
- **D43** — Done. Four `DestinationStyleOpInterface` ops; upstream 27
  and 64 stand. `GeneratingOpInterface`, `Idr_Iteration`, `StoreModel`,
  `HeapReadModel`, `heldType` and `DataRemap` are gone (measured: 0).
- **D45, with D53 to D55** — Done, its fork clause superseded.
  `GrowingSearch` (`compiler/checker/src/Core/Context.idr:1001`). No
  `%auto_implicit_depth`, `%ambiguity_depth` or depth count in the
  checker's source (measured).
- **D47** — Done. `.claude/skills/representation-first/SKILL.md:104-105`.
- **D48** — Done. `Idr_FamilyAttr` (`IdrTypes.td:334`); no
  `Idr_DataTableAttr`, `MutableType`, `!idr.box` or `#idr.types`
  (measured: 0).
- **D49, the specification's outputs** — Done.
  `foreign/idr/generated.manifest:64-66` holds `Dialect/Idr.idr`,
  `Encoding/Wire.idr` and `Encoding/Idr.idr`. `tests/spec-current`
  stands.
- **D50** — Done. No `IdrRules.txt`, `IdrPassRoles.txt` or
  `IdrPassStages.txt` (measured: 0).
- **D52** — Done. No `Double`, `SortedMap`, environment, clock or
  directory read in `spec/Generator/` (measured: 0); `tests/spec-self`.
- **D56, with D111 and D120** — Done.
  - INT builds the Idris half and the typecheck build. The lanes' own
    runs of the frontend over the fixtures (cc71ed8b, 1bc9c325: 429
    fixtures) rest on the owner's 2026-10-22 word, "you can build
    everything except for llvm proper". The coordinator's memory records
    it; P0 does not.
  - Recording it beside D111 would ground those runs. That is a record
    item for the coordinator, not a violation.
- **D57, with D123** — Done. The engine links classes by a union-find
  (`include/idr/Transforms/EGraph/Engine.h:39, 111`).
- **D59** — Done. `!idr.nat` carries `IndexTerms` (`IdrTypes.td:132-134`).
- **D60** — Done, as C239 and C262 narrow it.
  `lib/IR/Families/Substitute.cpp:233` (`mapSignature`). The frontend's
  `extentDim` is gone (measured: 0).
- **D61** — Done. `spec/Effects/LLVM.idr:155` (`parameterAccess`).
- **D62** — Done, its coordinates superseded by D88 (above).
  `spec/Grades/Grade.idr` has no affine, borrow or fractional part
  (measured: 0).
- **D63, D64** — Done (with D39 and D37 above).

## Count

By ruling, each at its least-done row:

| Verdict | Recheck 6 | Recheck 5 |
| --- | --- | --- |
| Done | 54 | 53 |
| Partial | 10: D7, D10, D30, D32, D33, D44, D46, D49, D51, D58 | 10: D4, D7, D10, D32, D33, D44, D46, D49, D51, D58 |
| Open-owner | 0 | 1: D30 |
| Missing | 0 | 0 |
| Regressed | 0 | 0 |

D4 moved to Done. D30 moved from Open-owner to Partial: D129 is the
ruling, and its array case is in flight.

By row: 11 not done (recheck 5: 13), all Partial. They are D7, D10,
D30's measurement, D30/D58's tail layout, D32's measurement, D33, D44,
D46, D49, D51 and D58's budget. Closed: D4's record and D32's framing.
Superseded parts: three, as recheck 5 (D40, D45, D55).

Of the 11:
- four await only a measurement on the owner's machine (D30, D32, D33,
  D58);
- two await only a generator run on this machine and a commit (D49,
  D51);
- two are in flight (D7 under D126, D30/D58's array case under L18x);
- two wait on C281's lane (D46, so D10);
- one waits on that lane and a coordinator reading (D44).

## Dispatchable items, by owner

**INT**
1. *D49, D51* (this machine, no LLVM build). Rebuild the typecheck
   build's `idris-mlir-tblgen` (built 2026-10-22 15:00, before 04d7cfcc),
   run `tools/dialects.sh generate typecheck`, and commit the eighteen
   modules under `compiler/src/IdrisMLIR/{Syntax,Dialect,Encoding}/`:
   thirteen rewritten without stamps and with the admitted ops alone,
   and six new for Linalg, Bufferization and SCF. L16 owns the files and
   takes the commit. Evidence: 13 stamped files; `build/int22/dialects-copied.txt`;
   257 lines of `Dialect/Arith.idr` differ.
2. *D30* (owner's machine). Measure stage 1 with and without `tailcc` on
   module-internal functions, and record the number with build and input
   (`Lower/Functions.cpp:175, 225, 307-310`).
3. *D32, D33* (owner's machines, four targets). Measure the three stack
   numbers per `CMakeLists.txt:177-215` and replace each target entry's
   `idris_mlir_unmeasured_stacks()` call (`:262, 279, 297, 330`) with
   them.
4. *D58* (owner's machine). Measure `shapeBudget` on stage 1. L04 writes
   it into `spec/Families/Layout.idr:98-99`.

**L16**
5. *D46, D10*. C281's tree and fold, the lemma's induction over the
   model's walk, then delete `Finite.idr:171-194, 215-216`,
   `Types.idr:601-606, 906-907`, `TS.bounds` and `TS.sizes`. **Waits on**
   C281's lane being dispatched (L16em stopped on it).
6. *D44*. Add `mlir-relational` to `compiler/idris-mlir.ipkg:7`, run the
   generations of `Finite.idr` on R2's fixpoint (C175), and delete the
   hand worklist. **Waits on** item 5's lane, which rewrites `Finite.idr`,
   and item 11.

**L18**
7. *D30/D58 with D129*. The array result whose element re-packs at a tail
   call keys its callee's copy to the caller's element layout, opened
   where an index stays unwritten (`lib/Transforms/Specialize/`). In
   flight under L18x.

**L20 with L16**
8. *D44, O8*. Write 0011's laws as compiled queries on R2, or bring item
   11's narrowing.

**L12, L03 (D126's lanes)**
9. *D7*. Replace the `is_same_v` op branches with the ODS fact each
   stands for:
   - `Columns/ArrayOps.cpp:45`, `StructureLoops/Linalg.cpp:151` and
     `Narrow/Ops.cpp:125-133` (L12);
   - `include/idr/IR/IdrDialect.h:173-187` (L03).

   The rest of D7 is D126's queue.

**Coordinator**
10. *D56*. Record the owner's 2026-10-22 build word ("you can build
    everything except for llvm proper") beside D111, which grounds the
    lanes' frontend runs.
11. *D44*.
    - State whether C281's fold of the growth model's tree leaves C175's
      fixpoint over the instance table as the translation's shape.
    - Settle O8's layer: `0011:415` stands it on R1, which D125 does not
      build in P0.
12. *D4*, optional wording. Point C153's "for the owner's review in the
    plan's approval" (`p0.md:4670-4671, 5509, 5601`) at D4's row and
    D123, and list D4 in §4's "Settled".

## Queue items found done (strike them)

In `audits/p0/verify/handoffs/L16-queue.md`:
- "Dispatched from recheck 5: L10z (§4's tail-layout check, D32's frame
  decision once)". Done by 0642ef67: `Call.cpp:281-289`,
  `Tail.cpp:378-394`, `ProgramGraph.h:145-165`.
- "N1, the tail decider's climb (`inTailPosition` ...)". Done: 0 hits
  (f46fe91d).
- "N2, the cycle rule written in four places". Done by fc6fb0f8 (L14w):
  one `isCycle` (`Analysis/Solver/Components.h:50`), asked by
  `ProgramGraph.h:142`, `Effects/Component.cpp:118` and
  `Optimize/Settle.cpp:193`.
- D126 round 2c, "`Frames.cpp:154-164` and `framingOf` ask one question
  twice". Done: `runsCallsOnFrames` (`ProgramGraph.h:165`), asked at
  `Tail/Frames.cpp:158`.
- D126 round 2c, `getRunTimeWords`. Done: declared at
  `spec/Core/Types.idr:365`, generated at `IdrInterfaces.td:19`.
  `Components.cpp`'s `wordsOf` and `Lower/Functions.cpp`'s `DestType`
  test are gone (measured: 0).
- D126 second round:
  - Unit A: `extentOf` and `packedOf` ask `DerivesLifetimeOpInterface`
    and `PerLevelOpInterface` (`IR/Lifetimes/Ops.cpp:47-62`).
  - Unit B: no two-way closure-or-constructor cast in `Convert.cpp` or
    `LabelSites.cpp`, and no `"site"` string in `lib/`.
  - Unit D: `verifyKeys` hashes the keys (`IR/Control/MatchFamily.h:118-127`).
  - Unit E: no `SelfType` test in `TypeGraph.cpp`, no `LifetimeType` in
    `Lower/Functions.cpp`.
  - Unit F: no `is_same_v<OpT, StrPackOp>` in `Strings.cpp`.
  - Unit G: `Rule.h:184-189`'s `Demand` holds `results`, not a `CallOp`.

  Measured by grep at HEAD. The D65 to D128 auditor confirms each
  against D126.
- Spec round 4 and L02x, `Termination`'s `Acyclic`. Done by 29153f20:
  `Acyclic` survives only as `families::Containment::Acyclic`
  (`IR/Families/Declaration.h:200`), a different fact.
- Corrected, not done: "INT, on the owner's machine: ... D49 and D51's
  dialect modules". It runs on this machine (item 1).

## Seen outside the range

- Recheck 5's two notes are closed:
  - `proposals/0009-typed-apl/README.md:565-571` says `unique self`
    (D122).
  - `proposals/0010-array-interpreter.md:12-13` names the checker's
    arena.
- D129's specializer half and D130's mark are in the tree (above). No
  recheck range lists D129 to D131 as its own. The coordinator may want
  them read whole by the D65 to D128 auditor or the next recheck.
