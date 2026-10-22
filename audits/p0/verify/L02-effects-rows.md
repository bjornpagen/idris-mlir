<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# L02: effect rows, the derivation, the verifier, upstream and LLVM

Lane L02 of the P0 verification swarm. HEAD `e96bb991` at the start
(21:30Z) and at the finish (recorded at the end). Nothing was built, run
or type-checked; every number is read, derived or labelled as a
measurement to take. Claims are marked *read* (path:line at HEAD; upstream
under `.toolchain/llvm-project` at `7208ba24c`), *recalled*, *conjecture*
or *decision* (a ruling Dn or Cn). The proposal is being edited while this
was written, so it is cited by ruling and section, not by line.

In scope: D9, D10, D22, D29, C2 (R3, R4), §5.1's lowering and C++. Read in
full: the representation-first skill, AGENTS.md, the whole proposal (D1 to
D55, C1 to C8, §4 to §9). Reread: 02 §2, §3.7, §4, §5 T1-T2; 05 §4.2,
T5.1-T5.3, R4, R14; 12 CV-05, CV-14, CV-15, T1, T2, §6; `design/effects.md`
§1.4, §1.8-§1.10, §2.4-§2.5, §3 to §8; `design/effect-vocabulary.md` §0 to
§9 (all of §4.3 to §7 and §8.3); `design/typed-effects.md` whole; §5.1 D2,
D3; §5.3 on `scc_iterator`. Code: listed with each claim.

## 1. Verification

### 1.1 The rulings

| ruling | verdict | the one-line reason |
| --- | --- | --- |
| D9 (one effect system, one place) | holds, with a correction | one query API covers every reader today (1.4); but the derivation as `effects.md` 3.6 writes it loses the reporting atoms at every call (1.3 F3) |
| D10 (no static fact paid at run time) | holds, with corrections | compiled programs test no effect; but three proved facts never reach their reader (a call's speculatability, an exclusive parameter's non-aliasing, the row at the LLVM boundary) and the region-op cache is a pointer-keyed map (1.3 F9, F10, F11) |
| D22 (the summary covers every state a caller orders with, derived, checked per function) | holds, with a correction | the atoms cover every such state (1.2); "a row equals its derivation after every pass" (§5.1) cannot hold under upstream's passes: containment after every pass, equality at every write (1.3 F4) |
| D29 (atom names) | holds; the proposal contradicts it | §5.1 still prints `runtime`, `memo`, `diverge`, and so do `effect-vocabulary.md` §4.3, §7.1 (1.3 F12) |
| C2 R3 (an effect that changes a calling convention lives in the type) | holds, with a correction | it is not future work: D39's allocation into a caller's lifetime is such an effect inside P0, and D39 and D48 contradict each other on it (1.3 F13; owner question 1) |
| C2 R4 (a foreign call's effects from its operands' types) | structural incompleteness | a Rust call also may crash and may not end, frees, and synchronizes; R4 lists none of these (1.3 F14) |
| §5.1, the lowering | refuted in three columns, corrected | the `memory(...)` column turns "no resource" into "no memory access", which is false for immutable memory at the byte level; `willreturn` is claimed for IO; `free` omits argument memory (1.3 F1, F2, F5) |
| §5.1, the C++ | holds, with corrections | concepts read ODS facts only; the dynamic facts list misses one (an upstream effect's resource) and keeps a pointer-keyed cache and a `bool` (1.3 F9, F15) |
| §5.1, upstream | holds, with corrections | DCE, CSE and sinking read the call's declared effects as designed; hoisting never moves a call (no speculatability), and the inliner reads effects only of callables that are not symbols (1.3 F10, 1.5) |

### 1.2 What holds, with its evidence

- **The derivation's shape is already right in the code** (*read*).
  `componentEffects` gives every member of a call-graph component one
  set: its members' own parts and the effects of each call that leaves
  the component (`lib/IR/Func/Func.cpp:204-220`), driven callees first
  (`lib/Analysis/Effects.cpp:36-47`). That is the least solution of
  `row(f) = own(f) ∪ ⋃ row(callee(c))` in one pass per component, since
  every member of a strongly connected component reaches every other
  (2.3 states the proof). D31's "a component's members share one row" is
  this fact (*decision*).
- **What is wrong today is the source of `own`, not the schedule**
  (*read*). `bodyEffect` reads `total`, a world parameter,
  `MayCrashOpInterface`, `WorldNewOp` and `RunsLabelsOpInterface`
  (`Func.cpp:189-202`), never the body's declared effects, and the
  program verifier holds the row to that same rule (`effectsCovered`,
  `lib/IR/Verify/Program.cpp:53-72`, run at `:260`). So 02 §3.7's three
  losses are real: a handle-table read, `exit`'s end of the run, every
  memo and memory write. Defect confirmed in the source.
- **The seed is termination, not totality** (*read*). The frontend writes
  `total` exactly when Idris's termination check returns `IsTerminating`
  (`compiler/src/IdrisMLIR/Frontend/Translate/Closed.idr:459-472`, through
  `host.checkTerminating`); coverage is not asked. That is the right fact
  for `divergence` (a missing case is a `crash` op in the IR, carried by
  its own atom), and it is what D13's licence needs. The attribute's name
  says more than it holds (improvement I12). Inlining clears it through
  `absorb` (`IdrOps.td:181`), defunctionalization sets it on force
  functions (`Transforms/Defunctionalize/Forces.cpp:78`), frames on all
  members (`Transforms/Tail/Frames.cpp:296, 318`); no other writer
  (`grep -rn setTotal`).
- **Every state a caller orders with has an ordering atom** (D22,
  *decision* over `effect-vocabulary.md` §4.3, §4.5): memory its
  arguments reach (`read`, `write`), counts (`count`), memo cells
  (`memo_state`), the outside (`io`), runtime tables (`runtime_state`),
  the three endings (`exit`, `crash`, `divergence`). Acquisition and
  release only report (D23; 2.3 shows why release needs no ordering).
- **Upstream reads the call as designed** (*read*): DCE drops a `Read`
  and an `Allocate` of the op's own result and nothing else
  (`mlir/lib/Interfaces/SideEffectInterfaces.cpp:79-95`); CSE merges an op
  only when every effect is a `Read` (`lib/Transforms/Utils/CSE.cpp:264-268`)
  and stops at a `Write` on a resource that is an ancestor or descendant
  of a read one (`:214-233`, the hierarchy at
  `include/mlir/Interfaces/SideEffectInterfaces.h:138-153`). 1.5 is the
  table per atom.
- **The calling convention is untouched by today's atoms** (*read*,
  `typed-effects.md` 3.3.2 checked): the row is an inherent property of
  `idr.func` and `idr.call` (`IdrOps.td:161-163, 219-220`), a function's
  type is an attribute of its op, and a call must keep a copy because a
  function pass may not read a sibling. Rows on ops, not in value types,
  holds for every atom.
- **No unwinding exists** (*read*): the whole build is
  `-fno-exceptions` (`CMakeLists.txt:326`), a crash is `_exit`
  (`runtime/Io/Ending.cpp:66-71`). `nounwind` on every function and call
  is sound.

### 1.3 Findings

**F1. The `memory(...)` column is unsound for immutable memory.** Defect
in the design (no code emits these attributes yet).
- The tree gives immutable memory no resource ("fields after init ...
  nothing changes it while referenced", `effect-vocabulary.md` §1 row 9);
  `field`, `tag`, `match` and the string readers declare nothing for it
  (§3's table). The LLVM column then maps a row with no heap atom to no
  location at all (§7.1: "A row names no value, so a heap atom covers
  both argmem and other"; no atom, no location): a function that only
  reads cells is `memory(none)`.
- At the byte level that memory is not immutable over the address's
  life. An exclusive take gives back the cell itself as the token, and a
  recycle of an exclusive token is the token, so the rebuilt cell is the
  *same pointer* (*read*: `lib/Conversion/Counting.cpp:86`, `Value token = cell`, "the
  cell is the token, with no test"; `lib/Conversion/Cells.cpp:123-125`,
  `rewriter.replaceOp(op, token)`), and `cell.init` stores the new fields
  into it (`Cells.cpp:150-172`).
- LLVM reads `memory(none)` as "a function of its arguments only": two
  calls with the same pointer merge across any store (*recalled*:
  EarlyCSE and GVN treat a call that accesses no memory as a pure value).
  LLVM's own inference cannot repair a wrong claim: it intersects what it
  infers with what is declared (`llvm/lib/Transforms/IPO/FunctionAttrs.cpp:297-302`,
  `NewME = ME & OldME`).
- The same hole breaks the `write` column: LLVM's `write` access kind
  means "reading the location before writing it results in a poison
  value" (`llvm/docs/LangRef.md:2326-2329`, *read*), so a function whose
  row is `{write}` and which reads a field of an argument before writing
  a destination reads poison.
- And the IO column: `put_str` reads its string through its pointer
  argument while §7.1 gives `io` no `argmem`, which LangRef makes
  undefined (`LangRef.md:2330-2333`).
Correction: improvement I1.

**F2. `willreturn` is claimed for IO.** Defect in the design. §5.1 and
`effect-vocabulary.md` §7.1 write `willreturn` unless `exit`, `crash` or
`divergence`, and `effects.md` 1.9 does the same for runtime calls. LLVM:
a `willreturn` call that does not return is undefined behaviour
(`LangRef.md:2522-2534`). An IO action may block for ever on input, and
the runtime installs no `SIGPIPE` handler (*read*: no `SIGPIPE` in
`runtime/`; `writeAll` loops on `write`, `runtime/Platform/Posix/Files.cpp:91-101`),
so a write to a closed pipe ends the process inside the call. LLVM's own
library table gives `read` and `write` no `willreturn` and no `nounwind`
(`llvm/lib/Transforms/Utils/BuildLibCalls.cpp:688-692, 721-726`, *read*).
Correction: improvement I2.

**F3. The derivation, as `effects.md` 3.6 writes it, loses `alloc` and
`free` at every call.** Integration mismatch between `effects.md` (whose
machinery the vocabulary keeps) and the vocabulary's reporting atoms.
`effects.md` 3.6: "`derive` never asks `isa<CallOp>`: a call's own set is
its summary's call effects ..., which project back to the summary (2.4's
round trip)". Written before reporting atoms existed; a reporting atom
has no call effects (`effect-vocabulary.md` §4.3), so the round trip
gives nothing for it, and a caller of an allocating function derives no
`alloc`. The vocabulary's own table (§4.4, "a call | its row") is right;
the two documents disagree. Correction: improvement I9.

**F4. "A row equals its derivation after every pass" cannot hold.**
Integration mismatch: §5.1 says equality; `effects.md` 4.1 and 6.8 say
containment after every pass, equality at every write, and list the
choice as the owner's, which §4 never raised. Upstream passes delete
effectful ops and cannot call our writer: canonicalize's known-case
inlining drops a match's other cases, crashes included
(`mlir/lib/Interfaces/ControlFlowInterfaces.cpp:1224-1240`, *read* via
`effects.md` 4.1), and CSE erases trivially dead reads
(`CSE.cpp:303`, *read*). A nested function pass may not write its
callers' calls (`effects.md` 4.1 item 2). So equality would need a
program-level writer after every canonicalize and CSE, a barrier between
parallel function groups. Correction: improvement I3.

**F5. Three more LLVM columns are wrong against LLVM's semantics.**
Defects in the design.
- `free` gives only `other`: readwrite. snmalloc threads its free list
  through the dying cells (*read*: `runtime/Rc/Freeing.cpp:138-157`, via
  `effect-vocabulary.md` §2.1), which writes memory based on the
  argument pointer: `argmem`. An exclusive drop with no counted field
  has row `{free}` alone (no `count`, D10's exclusive drop), so nothing
  else supplies `argmem`.
- `alloc` and `free` omit `inaccessiblemem` and `errnomem`: the slow
  path commits pages (`mmap`, `madvise`), which LLVM models as
  inaccessible memory and which may set `errno`; LLVM's own `malloc` is
  declared exactly so (`BuildLibCalls.cpp:551-563`, "inaccessible or
  errno memory").
- `crash` gives `other`: read, but the crash entry flushes through
  `idris_rt_flush`, which stores 0 into the output length
  (`runtime/Io/Output.cpp:134-139`; called from `Io/Ending.cpp:66-68`),
  a module global once the runtime is joined: a write to `other`. The
  call never returns, so no caller observes it (*conjecture*: not
  exploitable), but LangRef makes a write under `read` immediately
  undefined (`LangRef.md:2323-2325`). Unverified behaviour; the
  correction is the runtime's (seam with L11): the ending path writes no
  module memory, since it never returns.
- `exit` frees: `idris_rt_io_exit` releases the handle table
  (`Io/Ending.cpp:56-61`), so `nofree` must also be withheld under
  `exit` (no cost: `exit` implies `io`).
Correction: I1's table.

**F6. `nosync` does not survive 0007 as "always".** Unverified
behaviour today (sound: one thread), structural incompleteness for 0007.
LLVM's `nosync` forbids any synchronizes-with edge (`LangRef.md:2536-2550`).
Today the runtime's atomics are a relaxed load and store kept in order by
a signal fence (`runtime/Io/Output.cpp:30-41, 134-139`), which LLVM's
inference counts as no synchronization (*recalled*: a single-thread
fence and monotonic accesses do not break `nosync`). Under 0007 a shard
is a thread; a release frees a cell of another shard through snmalloc's
remote queue, an allocation drains that queue, and wake queues and pipes
use release and acquire (*read*: `proposals/0007-shards.md:183-187,
229-231, 471`). So once shards exist, `alloc`, `free` and `io` each
withhold `nosync`. Correction: the specification's `nosync` column per
atom (I1), edited once when 0007 lands; no reader changes.

**F7. Consumption declared as `Read` and `Free` on `count` puts `count`
in rows that touch no count.** Integration mismatch between §5.1 ("consuming
is `Read` and `Free` on `count`", also `effect-vocabulary.md` §5.1 item 2)
and the projection (§4.4 exempts only `Free` on `count`). Every function
that passes an owned value to a consuming op (a `con`, a call) would gain
`count`: its calls become never deletable or mergeable (a `Write` on
`count` in their call effects) and LLVM sees `argmem: readwrite`. Nothing
at run time reads a count when a reference moves (*read*: `LowerCon`,
`Cells.cpp:181`, stores the pointer). The `Read` buys nothing upstream:
a `Free` already keeps the op alive (`SideEffectInterfaces.cpp:79-95`) and
already blocks CSE (`CSE.cpp:268`). Correction: improvement I4 (seam with
L01, which owns the op table).

**F8. The projection is total only over our resources.** Structural
incompleteness. `effect-vocabulary.md` §4.4 covers ours, the root with and
without a value, and "an op of another dialect with no declaration". It
has no row for an upstream op that declares an effect on a resource
outside the tree (MLIR's resources are an open set of singletons,
`SideEffectInterfaces.h:80-135`), nor for kinds other than `Allocate` on
upstream's frame, nor for a value-less `Free` on the root. Correction: 2.2's
table adds those rows.

**F9. The region-op cache is a pointer-keyed map, and `EffectSet`
carries a `bool`.** Defect in the design against AGENTS.md's C++ rules
("no pointer-keyed map holds per-node state"; "a choice is a type or an
enum case, never a `bool`"). `effects.md` 3.3's `Cache::of(Operation
*regionOp)` keys per-op state by pointer; 3.1's `EffectSet { ...; bool
unknown; }` keeps "declares nothing" as a flag beside `everything()`,
which means the same. Correction: improvement I7.

**F10. A call is never speculatable, so upstream's hoisting never moves
one.** Defect confirmed in the source and kept by the design. LICM hoists
only `isPure` ops (`mlir/lib/Transforms/Utils/LoopInvariantCodeMotionUtils.cpp:117`),
and `isPure` requires `ConditionallySpeculatable`
(`SideEffectInterfaces.cpp:377-405`), which `idr.call` does not declare
(`include/idr/IR/IdrOps.td:210-214`). A call of a function Idris proved
terminating, whose row holds no ending atom and no ordering atom, is as
safe to hoist as an `arith` op; the row knows it (D10). §5.1's "hoisting
... read the declared effects" is vacuous for calls. Correction:
improvement I10.

**F11. The row has no inherent carrier between `idr.func` and
`llvm.func`.** Integration mismatch, unfixed seam. Phase 0 of the lowering
turns `idr.func` into `func.func` and drops every fact
(`lib/Conversion/FuncToFunc.cpp:3-5, 35-45`; 12 CV-05); about twelve
upstream passes then run on `func.func` (`lib/Transforms/Pipeline.cpp:140-196`)
before `convert-to-llvm` makes `llvm.func`. `func.func` has no inherent
slot for the facts; `llvm.func` has `memory_effects`, `will_return`,
`no_unwind` and `passthrough` (`mlir/include/mlir/Dialect/LLVMIR/LLVMOps.td`,
`LLVM_LLVMFuncOp`'s arguments; `passthrough` names reach LLVM as enum
attributes, `mlir/lib/Target/LLVMIR/ModuleTranslation.cpp:1132-1151`).
`effects.md` 2.5 left it "a dependency on lane 12"; the proposal fixes
nothing. A discardable `llvm.*` attribute on `func.func` is what AGENTS.md
forbids. Correction: improvement I5.

**F12. Stale atom names.** Integration mismatch. D29 renames `runtime`,
`memo`, `diverge` to `runtime_state`, `memo_state`, `divergence`, "with
no alias"; §5.1's row line and LLVM line, `effect-vocabulary.md` §4.3's
table, §4.3's examples and §7.1 still use the old ones. The coordinator's
fold should restate them.

**F13. R3 has P0 cases, and D39 contradicts D48 on one.** Integration
mismatch between two rulings. D39: "A scope parameter is a handle at run
time, so it is part of the function's type (C2 R3)"; D48: "index
variables and lifetime variables (D39, D40) are quantity-0 parameters ...
passed at calls at compile time only". A lifetime used only for views
needs no handle; a callee that "can build its result in the caller's
scope" (D39) needs the caller's arena at run time. That allocation is
Tofte and Talpin's `put(ρ)` effect (*recalled*: their arrow types carry
latent `get`/`put` effects on regions), and it changes the calling
convention, so R3 puts it in the type. Owner question 1. Two other R3
cases are already typed or are another lane's: D34's destinations are a
parameter type (`!idr.dest`); D31's frame stacks change how a call on a
cycle returns, which R3 puts in the type only if a caller outside the
component can see it (seam with L10).

**F14. R4 omits four facts of a foreign call.** Structural
incompleteness (0020). A Rust function proves neither termination nor
the absence of a panic (an abort across the C boundary: *recalled*), so a
foreign call holds `crash` and `divergence`; it releases memory it was
handed by value or allocated (R2 makes a foreign allocation `heap`), so
`free`; and it may synchronize with Rust threads (0007 §3.3 lets foreign
threads post to wake queues, *read*), so it is never `nosync`,
`willreturn` or `mustprogress`. Correction: improvement I11.

**F15. The dynamic facts list misses one.** Structural incompleteness.
`effects.md` 3.7 lists eight dynamic facts. The untyped path also needs to
know which resource an upstream effect names (`Default`,
`AutomaticAllocationScope`, one of ours, or another dialect's): MLIR's
resource set is open, so this is a `TypeID` compare per effect, justified
like the one interface dispatch.

**F16. Two upstream patches of `effects.md` 7.2 change status.**
- U4 (an ODS effect keeps its resource record) existed so a C++ TableGen
  backend could recover a resource's parent from an effect. Under D16 the
  Idris specification writes both the ODS effects and the C++ resource
  classes, and D51 keeps one C++ backend that reads only upstream's
  records: nothing reads our effects back from ODS. U4 goes from the plan
  (optional simplification).
- U2 (`ub.unreachable` declares no effects; still `[Terminator]` only,
  `mlir/include/mlir/Dialect/UB/IR/UBOps.td:73`) is needed only if
  `ub.unreachable` survives the cutover. Under §5.3, `crash`, `crash_str`
  and `exit` become terminators with no successor, which is where
  `ub.unreachable` comes from today (02 E18). If none remains, the external
  model `NeverRuns` (`lib/IR/FlowOps.cpp:344-346, 365`) goes with no patch
  (AGENTS.md: a patch goes when nothing reaches the bug). Seam with L09
  and L13.

**F17. V0 is redundant.** Optional simplification. `effects.md` 4.1's V0
("before the first solve, every function and call holds the default
exactly") checks nothing V1 and V2 do not: the default row is every atom,
which contains any derivation (V1) and equals itself at every call (V2).
Delete V0 and its stage fact.

### 1.4 The deletions the lane must verify

| symbol (read at HEAD) | callers | replaced by |
| --- | --- | --- |
| `bodyEffect`, `Func.h:28-35`, `Func.cpp:185-202` | `componentEffects`, `effectsCovered` | the derivation's `own`, a fold over declaration forms (2.3) |
| `componentEffects`, `Func.h:37-44`, `Func.cpp:204-220` | `Analysis/Effects.cpp:43`, `Optimize/Component.cpp:215` | the writer's join over the program graph's components |
| `writeEffects`, `Func.h:46-51`, `Func.cpp:222-230` | `Analysis/Effects.cpp:45`, `Contracts/Contracts.cpp:202, 246` | the writer; the contracts test plants a violation by changing IR, never a row |
| `effectsCovered`, `Verify/Program.cpp:53-72, 260` | the program verifier | V1 in each function's region verifier (2.4) |
| `Row`, `rows`, `appendEffect`, `effectInstances`, `Func.h:53-59`, `Func.cpp:232-265` | `Call.cpp:67` | the call effects generated per atom |
| `solveEffects`, `observableRuns`, `LabelsRun`, `Analysis/Effects.h`, `lib/Analysis/Effects.cpp` | `Transforms/Effects/Effects.cpp:31`, `Defunctionalize/Pass.cpp:110-115` | the writer pass; `by_name` through the derivation with the label solve's filter (seam with L18, F DP-50) |
| MoveOut's `Does`, `doesOf`, `usesWorld`, `Canon/MoveOut.cpp:55-113` | MoveOut | the one classifier with MoveOut's question as its template parameter; the world goes (D20) |
| `Does`, `classify`, `onlyAllocates`, `performsIO`, `include/idr/IR/Flow.h:83-98`, `lib/IR/Effects.cpp:107-142` | Sink, CaseOfCase, Force, Bufferize, IdentitiesRecord, Consumer, Expect | the query API (2.5) |
| `mayRunAt`'s `call.getEffects() == Effect::none` and `isa<IOResource>`, `Effects.cpp:161-184` | Raise, TRMC | a conflict test of the call's effect set against each op between |
| `anyEffect`, `IdrDialect.h:56`; `Idr_Effect`, `IdrAttrs.td:186-209`; the parse and print, `Func.cpp:141-147, 169-170` | everywhere | `Row` and its atoms, generated (D29) |
| the call's containment check and hand `getEffects`, `Call.cpp:52-58, 61-72` | MLIR | V2 equality; the call's typed rules (`Summarized`, `Consumes`, `NewIdentity`) |
| hand readings of the bits: `IdentitiesRecord.cpp:160` (`returns = !diverge`), `Specialize/Consumer.cpp:59-62`, `Contracts.cpp:169-174, 186, 234`, `Transforms/Effects/Effects.cpp:33-36`, `Expect/SolvedEffects.cpp:29-33`, `Expect/Arguments.cpp:295-298`, `Tail/FramesPlan.cpp:158`, `Tail/Frames.cpp:320`, `Specialize/Specialization.cpp:36`, `Specialize/Raise.cpp:111` (`setEffects(anyEffect)`), `Optimize/Component.cpp:73-84, 213-215`, `Optimize/Waves.cpp:281-292` | | the API's row questions; a clone copies its source's row (its body does no more), never `anyEffect` |
| `unittests/Verify.cpp:33`, `unittests/Identities.cpp:39, 70, 76`; 15 test files with `effects<` text (*measured*: `grep -rln 'effects<' tests | wc -l`) | | the atoms' new spellings (D29) |

Every current reader is in the table (*measured*: `grep -rn` for the bit
names, `getEffects()`, `setEffects(`, `bitEnumContains` over `lib include
tools unittests`, every hit read). Nothing on the Idris side reads or
writes a row (the frontend writes none; `IdrOps.td:143-150`).

### 1.5 Each upstream reader, per atom

What each pass does with a call whose row holds the atom (the call's
effects are the atom's call effects, plus `Free` on `count` of each owned
argument and `Allocate` on `identity` of each owned or linear result).

| atom | DCE: `wouldOpBeTriviallyDead`, `SideEffectInterfaces.cpp:79-95` (greedy driver `GreedyPatternRewriteDriver.cpp:486`, region DCE `RegionUtils.cpp:385, 541`, SCCP `SCCP.cpp:95`) | CSE: candidacy `CSE.cpp:264-268`, blocking `:214-233` | LICM `LoopInvariantCodeMotionUtils.cpp:117`; control-flow sink `ControlFlowSink.cpp:46` |
| --- | --- | --- | --- |
| `io` | kept (a `Write`) | never merged; blocks reads of `io` and its children | never |
| `runtime_state` | dead if unused (a `Read`) | merged; blocked by any `io` write (an ancestor) | never (not effect-free) |
| `exit` | kept | never merged | never |
| `crash` | kept (D13) | never merged; blocks reads of `io`, `divergence` | never |
| `divergence` | kept (D13) | never merged | never |
| `read` | dead if unused | merged; blocked by a write on `contents`, `heap` or the root, with or without a value (CSE compares resources, never values) | never |
| `write` | kept | never merged; blocks reads of `contents` | never |
| `count` | kept | never merged | never |
| `memo_state` | kept | never merged | never |
| `alloc` | nothing declared: dead if unused | merged when nothing else is declared (C3's hash-consing before counting); an owned result's `identity` allocation stops it after counting | sinkable into a case (effect-free); never hoisted until I10 |
| `free` | nothing declared; an owned argument's consumption (`Free`) keeps it | never merged (the consumption is not a `Read`) | never |

The inliner reads effects only to drop an unused callable that is not a
symbol (`lib/Transforms/Utils/Inliner.cpp:192-207`); every `idr.func` is a
symbol, so no atom matters to it, and our optimizer inlines. Local alias
analysis skips `Allocate` and `Free` in mod-ref (`LocalAliasAnalysis.cpp:511`)
and takes an allocated value as fresh (`:264`): a call's `NewIdentity`
result is then "fresh" to it even when the callee rebuilt its argument in
place (D24), so no pass of ours may ask alias analysis about an owned
call result (*conjecture* that none does today; seam with L08).

## 2. Boundaries

### 2.1 The end state

- **`Row`**: the eleven atoms of D29 as one generated bit enum (12 bits
  spare in a `uint16_t`), printed `effects<...>`, its default every atom.
  Inherent property of `idr.func` and `idr.call`, never discardable.
  Generated from `Spec.Effects.Atom` (L03).
- **`AtomFacts`** per atom, generated: resource, kinds, ordering or
  reporting, the call effects (ordering atoms only), what it stops
  (returning; progress), and the LLVM columns of 2.6.
- **The projection** `P`, a generated `constexpr` table (2.2), proved
  total and sound in the specification (2.3).
- **The derivation**: one function, `own(f)`, a fold over each op's
  declaration form; the writer joins `own` over the program graph's
  components (2.3).
- **The verifier**: V1 in `FuncOp::verifyRegions`, V2 in
  `CallOp::verifySymbolUses` (2.4).
- **The query API**: `include/idr/IR/Effects.h`, `lib/IR/Effects/` (2.5).
- **The lowering's facts**: one generated function from a row to
  `llvm.func`'s `memory_effects`, `will_return`, `no_unwind` and
  `passthrough` (`mustprogress`, `nofree`, `nosync`), and the same per
  runtime op class to `llvm.call` (2.6).
- **Invariants**: a function's row contains `own` of its body and the row
  of each call in it (V1); a call's row equals its callee's (V2); only
  the writer and a clone (copying its source's row) write a row; the row
  never refuses a program (law L11); what LLVM is told equals the
  derivation (the writer runs last before the lowering).

### 2.2 The projection, total

`P : Kind × Resource × Naming → set of atoms`, with `Resource` the twelve
of D27 plus `Foreign` (any other MLIR resource). Kinds a resource of ours
does not admit (law L3) are unwritable for our ops, and upstream ops
cannot name our resources, so the table is total on what can occur:

| effect | `P` |
| --- | --- |
| `Read`, `Write` on `io` | `io` |
| `Read` on `runtime_state` | `runtime_state` |
| `Write` on `exit`, `crash`, `divergence` | `exit`, `crash`, `divergence` |
| `Read`, `Write` on `contents` | `read`, `write` |
| `Read`, `Write` on `count` | `count` |
| `Free` on `count` (consumption, declared on the operand by the call's own rule) | nothing |
| `Read`, `Write` on `memo_state` | `memo_state` |
| `Allocate`, `Free` on `heap` | `alloc`, `free` |
| `Allocate` on `identity`; any kind on upstream's frame | nothing (local to the function) |
| a kind on the root naming a value (a memref: array memory, law L5) | `Read` `read`, `Write` `write`, `Allocate` `alloc`, `Free` `free` |
| `Read`, `Write`, `Allocate` on the root naming no value, or on `Foreign` | every atom whose kinds hold it |
| `Free` on the root naming no value, or on `Foreign` | every ordering atom of kind `Write`, and `free` (an unknown release) |
| an op's `Scratch` fact | `alloc`, `free` |
| `RunsUnknown`; another dialect's op that declares nothing and is not recursive | every atom |
| a `Summarized` rule (a call) | the call's row |
| the seed: a function Idris did not prove terminating | `divergence` |

The specification states it with the admission proof as an erased
argument (`project : (k : Kind) -> (r : Resource) -> {auto 0 _ : Admits r k}
-> Naming -> List Atom`, `Foreign` and the root admitting every kind), so
Idris's coverage check is the totality proof; the C++ table is computed
from it (D16).

### 2.3 The derivation, fixed

**`own(f)`**, one pre-order walk of `f`'s body. Each op contributes by
its declaration form, a closed sum, one fold, no `isa` over ops:
- static, or another dialect's declared effects: `⋃ P(e)`;
- typed rules: `⋃ P(e)` over the rules' effects, but `Summarized`
  contributes the call's row (F3);
- recursive: its own effects projected, and the walk enters its regions
  (`RecursiveMemoryEffects`: matches, joins, `memo.run`,
  `io.unsafe_run`, `scf` ops);
- runs unknown code, or another dialect's op with no declaration and no
  recursion: every atom;
- definition: nothing.
Plus `alloc` and `free` for an op whose runtime meaning has `Scratch`, and
`divergence` if `f` is not proved terminating.

**The writer**, `write(graph)`, a program-level step:
1. `own(f)` for every function, in parallel (each worker reads one body);
   kept in an `IndexVector<FunctionId, Row>` for the step's life.
2. For each component `C` of the program graph, callees first (its
   components are id ranges, L14's T5.1): `row(C) = ⋃ own(f), f ∈ C ∪ ⋃
   row(D), D a component called from C`. Bitwise ors over the graph's
   compressed rows: `O(functions + call edges)`.
3. In parallel per function: its row is its component's; each call in
   its body takes its callee's component's row (the graph's call-site
   list, so no second walk).

Why one pass is exact: the system `row(f) = own(f) ∪ ⋃ row(callee(c))`
is monotone over a finite lattice; in a strongly connected component
every member reaches every other through calls, so the least solution
gives every member the union of the members' `own` and of the rows of the
components it calls; callees-first order makes those final when read.
No iteration, no round count (AGENTS.md).

**Where it runs** (pipeline at HEAD, `lib/Transforms/Pipeline.cpp`):
after `idr-defunctionalize`, as `idr-effects` does today (`:77`; before
it, closures run unknown code and the default holds); inside
`idr-optimize`, per component as it finishes (the program graph's one
dynamic client); at the end of every program pass that adds effects:
`idr-bufferize` (`:113`, stores and allocations), `idr-frames` (`:125`),
each counting pass (`:128`, counts, cells, releases), `idr-trmc` (`:131`,
destination writes); and last before `idr-lower` (`:140`). The nested
function passes (canonicalize, CSE, structure loops, tail loops) only
remove effects or add `divergence` where the seed already holds it, so V1
holds after them without a writer.

**Its cost**: one walk of the program in parallel, `O(functions +
edges)` serial, `O(calls)` writes in parallel; the same order as one
verification, which already runs after every pass. Measurement to take:
`-mlir-timing` of each writer run on the stage-1 module, against the
verifier's own time.

**Before defunctionalization** nothing reads a row. The refinement that
decides `by_name` (F DP-50) is the derivation with a filter that reads a
label runner as calls of its labels (`effects.md` 3.6); it lives in the
label solve (L18), never in an op's declaration.

### 2.4 The verifier's two checks

- **V1**, per function, after every pass, in `FuncOp::verifyRegions`, run
  in parallel over isolated functions (upstream's verifier, *read* via
  5.2 H1): `own(f) ∪ ⋃ row(c) ⊆ row(f)`, calls read by their property.
  Cost: one walk per function, per op one interface dispatch and a
  generated constant (a typed rule reads its operand types; a call its
  property), then one compare. It replaces `effectsCovered`'s serial walk
  of the whole program (`Program.cpp:61-72`).
- **V2**, per call, in `CallOp::verifySymbolUses`: `row(c) = row(callee)`.
  Cost: one compare after the symbol lookup the type check already does
  (`Call.cpp:29-51`), serial, `O(calls)`.
- **Together they prove every reader safe.** If V1 holds for every
  function and V2 for every call, then for every op `o` reachable from
  `f`, `own(o) ⊆ row(f)`. Induction on the reach: `o` in `f`'s body,
  `own(o) ⊆ row(f)` by V1; `o` reachable through a call `c` in `g` to
  `h`, `own(o) ⊆ row(h) = row(c) ⊆ row(g)` by the hypothesis, V2 and V1.
  A reach is a finite path, so cycles need nothing. Both checks are
  local, which is what makes them parallel.
- **Equality** holds at every writer run (asserted, test-only) and at the
  lowering (the writer runs last). V0 goes (F17).
- **Failure** is an internal error naming the function, the missing atom
  and the op that needs it (`effect-vocabulary.md` §4.3's messages); never
  a refusal of the program.

What the ordering proof rests on, beyond V1 and V2 (2.3's soundness in
order terms): an ordering atom's call effect is the same kind on the same
resource as the op effect it stands for, but with no value, so it
conflicts with at least what the op effect did (CSE's addressability
exemptions only remove conflicts of effects naming values,
`CSE.cpp:226-228`); a root effect naming a memref conflicts only with
array memory in fact (law L5, a decision over every upstream op the
pipeline creates, which D51's admitted list makes checkable for the ops
the frontend writes and the pass inventory must extend for the ops passes
create; seam with L03); acquisitions order nothing (D23); a release frees
only what the function acquired or was handed owned, and every use of a
handed value precedes its consumption by the lifetime rules (D39), not
by effects. That last line is the boundary between the effect system and
the ownership system: effects order states; ownership orders a value's
uses against its consumption.

### 2.5 The query API

`include/idr/IR/Effects.h`, `lib/IR/Effects/`, per `effects.md` 3, with
these corrections:
- **Values**: `EffectSet` (per kind, the set of resources; "declares
  nothing" is `EffectSet::everything()`, no flag); `Effect` (kind,
  resource, value); `Row`.
- **Concepts**: `Declared<OpT>` (reads the generated trait, never an op
  list); `StaticEffects<OpT>`; `When` (a typed rule's type condition);
  `Question` (a predicate over one `Effect`, for the one classifier);
  `CallFilter` (for the label-refined derivation). Every callback a
  constrained template parameter (D7).
- **Questions**: `of(op)`, `forEach(op, visit)`, `classify<Q>(op, q)`,
  `conflicts(a, b)`, `writes(op, value)`, `allocates(op, value)`,
  `consumes(operand)`, `row(fn)`, `row(call)`, `stops(row)`,
  `speculatable(row)` (I10), and the derivation's `own(fn, filter)`.
- **The dynamic facts**, each with its reason: which op an `Operation *`
  is (one interface dispatch: MLIR's open op set); which typed rule fires
  (the operand and result types, a bit each type computed when made);
  a call's row and a function's row (properties, read in O(1), written by
  the writer, verified); a region op's set (its body is rewritten IR:
  folded bottom-up by the walk that needs it, random access through the
  function's one op numbering, never a pointer-keyed map; seam with L15);
  which resource an upstream effect names (a `TypeID` compare: MLIR's
  open resource set; F15); which operand a value question asks about;
  a guarded op's speculatability (def-use, unchanged); whether A may move
  past B (the two sets).
- **Compile-time constants**: the tree, the atoms, `P`, the LLVM columns,
  every static op class's set, and the `static_assert`s of 2.3: each
  ordering atom's call effects project back to it alone; every
  (kind, resource) an op declares projects to an atom or is consumption or
  local; the seed's atom stops returning.

### 2.6 Each atom to LLVM

The memory attribute of a function is the default `read` (I1's floor)
joined with each atom's column; the other attributes are rules over the
row. Checked against LangRef at the pin.

| atom | `memory(...)` beyond the `read` floor | `willreturn` | `mustprogress` | `nofree` | `nosync` today / with 0007 |
| --- | --- | --- | --- | --- | --- |
| `io` | `inaccessiblemem`, `errnomem`, `other`: readwrite | withheld (F2) | kept: IO is progress (`LangRef.md:2941-2954`) | kept / withheld | kept / withheld |
| `runtime_state` | nothing (the floor reads `other`) | kept | kept | kept | kept / kept |
| `exit` | as `io` (law L8) | withheld | kept | withheld (it releases the handle table) | as `io` |
| `crash` | `inaccessiblemem`, `errnomem`: readwrite, if the ending path writes no module memory (F5; else `other`: readwrite) | withheld | kept | kept | kept / kept |
| `divergence` | nothing | withheld | withheld | kept | kept / kept |
| `read` | nothing (the floor) | kept | kept | kept | kept / kept |
| `write` | `argmem`, `other`: write (readwrite with the floor) | kept | kept | kept | kept / kept |
| `count`, `memo_state` | `argmem`, `other`: readwrite | kept | kept | kept | kept / kept |
| `alloc` | `other`, `inaccessiblemem`, `errnomem`: readwrite | kept (D23: running out is outside the language; *conjecture* that no LLVM transform at the pin prunes a path that does not return inside a `willreturn` function; none of the `willReturn()` readers in `llvm/lib/Transforms` does, *read* by grep) | kept | kept | kept / withheld |
| `free` | `argmem`, `other`, `inaccessiblemem`, `errnomem`: readwrite | kept | kept | withheld | kept / withheld |

Always `nounwind` (1.2). Runtime call sites take the same columns from
their op class's set, a `consteval` per class (`effects.md` 2.5), an
effect on an operand going to `argmem`, at the call (linking replaces a
declaration's attributes by the definition's,
so the call carries them, as `noreturn` already is,
`Runtime.cpp:140-141`, 12 CV-15).

**What the row buys from LLVM, honestly.** LLVM's O3 pipeline runs on
the program joined with the runtime's bitcode (`lib/Driver/Run.cpp:203,
216`; `lib/Target/Optimize.cpp:48-64`), and its attribute inference
derives `memory`, `nofree`, `nosync` and `nounwind` from every body it can
see, component by component (`FunctionAttrs.cpp:273-310`). It cannot
infer `mustprogress` at all, and infers `willreturn` only for a function
with no loop and no recursion, or for a `mustprogress` one that only reads
(`FunctionAttrs.cpp:2159-2186`); it deletes a possibly endless loop only
under `mustprogress` (`llvm/lib/Transforms/Scalar/LoopDeletion.cpp:116-129`).
GMP and the C library are linked natively, not as bitcode
(`runtime/CMakeLists.txt:239-240`), so a call into them is opaque. So the
row's real contribution is `mustprogress` and `willreturn` on looping and
recursive functions Idris proved terminating, plus `memory` on calls whose
callee reaches GMP or the C library. That is also why the floor costs
nothing where LLVM can see the body: it intersects its inference with the
declared attribute (`FunctionAttrs.cpp:297-302`). Measurement to take: on
each benchmark's joined module, strip our attributes, run `opt
-passes=function-attrs`, and count per function (a) LLVM's inference not
contained in ours (a soundness failure, expected zero), (b) ours strictly
stronger, (c) `mustprogress` and `willreturn` that only ours give.

### 2.7 Constructor provenance

| fact | constructed by | who alone may |
| --- | --- | --- |
| an op class's effect set | the generator, from `Spec.Effects` (L03) | the generator |
| a typed op's effects | the generated rules, over operand and result types | the rules |
| the seed (terminating) | the frontend from Idris's termination check (`Closed.idr:459-472`); `absorb` on inlining and contification; defunctionalization's force functions; frames' members | those four |
| a function's row | the writer; a clone copies its source's row (specialization, raising, frames' resume) | the writer and clones |
| a call's row | the writer; `CallOp::build(callee)` copies the callee's (`Call.cpp:23-27`) | the writer and the builder |
| the projection, the LLVM columns | the generator | the generator |
| the components and call sites | the program graph (L14) | the graph and the passes that edit it |
| exclusivity (for `noalias`, QTT) | the exclusivity analysis, as `!idr.excl` types (L08) | that analysis |
| a lifetime parameter and any arena handle | lifetime inference (L05; owner question 1) | that inference |
| `llvm.func`'s attributes | the one lowering step that makes `llvm.func` (I5) | that step |

### 2.8 Consumers, errors, cleanup

- **Consumers**: upstream's DCE, CSE, sinking and (after I10) hoisting,
  through the call's declared effects; our passes through the API
  (optimizer, specialization's consumer check, identities' "reaches
  nothing unproved", idr-expect's heap-free check as "the row lacks
  `alloc`", frames' plan, MoveOut, Sink, TRMC and raising through
  `conflicts`); LLVM through 2.6.
- **Errors**: V1 and V2 failures are internal errors of the pass that
  broke them, run after every pass, so the pass is named. A row never
  refuses a program.
- **Cleanup**: a function SymbolDCE erases takes its calls with it;
  rows of erased functions vanish with the op; the program graph is
  edited by the pass that erases (L14).

### 2.9 Essential distinctions that remain

Ordering against reporting atoms (D22, D23); stopping a return
(`exit`, `crash`) against stopping progress (`divergence`, D13); `io`
against `runtime_state` (D27); `exit` against `crash` (D14); value
effects against value-less ones (addressable against opaque); the seed,
the one input that is not an op (Idris's proof); region ops whose effects
are their bodies'.

### 2.10 Seams

| with | the declaration both sides write against | state |
| --- | --- | --- |
| L01 | each op's declaration form and effects; consumption as `Free` on `count` alone (I4); `Free` on `heap` on every op that may release, runtime ops that consume owned operands included (the `free` atom and `nofree` rest on it) | consumption unfixed (F7) |
| L03 | `Spec.Effects.Atom`'s record: resource, kinds, use, stops, LLVM columns including `nosync` per atom; `project` with `Foreign`; law L5 over the passes' upstream ops | columns to add (I1, I2) |
| L05 | lifetime variables at quantity 0, an arena handle where a function allocates into a caller's lifetime; `idr.lifetime`'s end as a local release | owner question 1 |
| L08 | `!idr.excl` on owned pointer parameters (for `noalias`); no pass asks alias analysis about an owned call result | open |
| L09, L13 | where `llvm.func` is made (I5); whether `ub.unreachable` survives (F16) | unfixed |
| L10 | the resource of D31's frame-stack push and pop (none in D27's tree: a push has no result and must not be dead, a pop must not merge); whether the frame convention is visible outside a component | unfixed |
| L11 | the ending path writes no module memory (F5); the `SIGPIPE` ending, which D37's table lacks | open |
| L12 | a consumed memref operand's `Free` on `count` read by upstream buffer deallocation, if ever run | open |
| L14 | the program graph's components as id ranges and call sites per function; one schedule for rows and for lifetime parameters (D39: "inferred bottom-up over the call graph's SCCs as the effect rows are") | fixed by T5.1, T5.3 |
| L15 | one op numbering per function for region-op sets | open |
| L18 | the label-refined derivation for `by_name` | fixed (`effects.md` 3.6) |
| L19 | the counterexample programs of section 4 and the attribute soundness check of 2.6 | to write |

## 3. QTT

**Where quantities enter, and what happens to them.**
- *Quantity 0.* An erased index or proof is no value (AGENTS.md), so no
  op touches it and no row mentions it; D48's index variables and
  lifetime variables are compile-time parameters, which change no calling
  convention and so are not effects. Idris's termination proof, an
  erased fact about a definition, enters as the seed (`total`, really
  "terminating", 1.2) and is the only proof the row reads; it reaches
  LLVM as `mustprogress` and `willreturn`, which no other source can give
  (2.6). It is kept by copies, cleared only by `absorb`.
- *Quantity 1.* A linear result takes a fresh identity (`Allocate` on
  `identity`), so CSE never merges two calls that each give one
  (`CSE.cpp:268`: not a single read) and DCE may still drop an unused one
  (`SideEffectInterfaces.cpp:79-90`); the linearity verifier is affine
  ("used at most once", `lib/IR/Verify/Linearity.cpp:3-4`), so dropping a
  pure, terminating call that was a linear value's one use is legal, as
  D13 allows. A call that consumes a linear argument declares nothing for
  it before counting (nothing is owned, `lib/IR/Effects.cpp:96-99`) and
  `Free` on `count` of it after; the row is untouched either way. A
  linear binder does not imply unique ownership (AGENTS.md), so linearity
  alone refines no row.
- *Exclusivity* (`!idr.excl`, proved after counting) is the quantity fact
  that does refine: a write through an exclusive owned value is visible
  to no one but the holder of that value, by Idris's value semantics
  (no shared value is ever mutated; a write in place happens only where
  the reference is unique).
- *Quantity ω.* Shared values: effects on them are the value-less atoms.

**Facts a quantity proves that the design still pays for.**
1. *An exclusive owned pointer parameter is not marked `noalias`.* LLVM
   never infers `noalias` on a parameter in its default pipeline
   (`FunctionAttrs.cpp` infers it on returns only, *recalled*), so the
   proof that no other reference exists during the call never reaches
   the alias analysis that would keep loads of other memory across stores
   to the exclusive cell. Paid at run time in every in-place loop (D10).
   Sound by LangRef's definition when the callee does not reload the
   pointer from memory it stored it into during the same call
   (*conjecture* that no lowered body does; checked by the measurement
   of I6).
2. *A write in place on an exclusive owned parameter is a value-less
   `write` at every call.* Upstream's CSE and DCE compare resources, never
   values (`CSE.cpp:214-233`), so for them a value-carrying write is as
   strong a barrier as a value-less one: nothing is lost by carrying the
   value, and soundness holds. What is gained: a caller that passes
   memory it acquired itself loses the atom entirely (the write is to its
   own fresh memory), so an array-building function becomes deletable and
   mergeable after counting, as it is before; and LLVM learns the write is
   argument memory only. This needs a per-parameter part of the row:
   owner question 2.
3. *An effect on memory the function acquired itself is projected as if a
   caller could see it.* After bufferization, the stores that fill a
   fresh array are `Write` on the root naming a memref
   `memref.alloc` made in the same function; `P` makes them `write`.
   Upstream already reads the fact one hop away (`LocalAliasAnalysis.cpp:240-300`,
   `getAllocEffectFor`). I8 makes such effects local.

**Representations that make a misuse of a quantity unwritable.** The
`Summarized` rule and V2 make a call that claims less than its callee
unwritable past verification; `Allocate` on `identity` makes merging two
linear values unwritable for upstream's CSE; I6's `noalias` is written
only from the `!idr.excl` type, so it cannot be written on a value the
exclusivity analysis did not prove; owner question 2's per-parameter part
would be indexed by the parameter's grade, so a value-carrying write on a
shared parameter could not be stated.

## 4. Improvements

**I1. A `read` floor on every function's and every runtime call's
memory attribute, and the corrected columns of 2.6.** *Coordinator.*
- Evidence: F1, F5 (read at the lines cited there).
- Counterexample (*conjecture* of LLVM's merge, *read* for the lowering):
  ```idris
  data P = MkP Int Int
  fst' : P -> Int                  -- total, not inlined: row {} under 7.1, memory(none)
  bump : (1 _ : P) -> P
  bump (MkP a b) = MkP (a + 1) b   -- rebuilt in place on an exclusive cell
  main : IO ()
  main = let p = MkP 1 2 ; x = fst' p ; q = bump p in printLn (x + fst' q)
  ```
  `p` is fresh and only borrowed before `bump`, so it is exclusive there;
  the take's token is the cell and the recycle returns it, so `q` is `p`'s
  pointer; LLVM merges `fst' q` with `fst' p` across the stores
  (`memory(none)`), printing 2 instead of 3.
- Root cause: "no resource" (a value-level fact) read as "no memory access"
  (a byte-level claim); reuse makes the bytes behind a pointer change.
- Correction: the specification's LLVM columns are 2.6's: the default
  location kind is `read`, never `none`; `write` joins to readwrite;
  `free` adds `argmem`; `alloc`, `free` and `crash` add `inaccessiblemem`
  and `errnomem`; `exit` withholds `nofree`; `nosync` is a per-atom column
  (all today; `io`, `alloc`, `free` withheld with 0007). LLVM intersects
  with its own inference, so nothing is lost where it sees the body.
- Deletes: the `memory(none)` outcome; the `read` and `runtime_state`
  columns (subsumed).
- Discrimination: the program above, its output its specification, on all
  four targets; and 2.6's measurement as a test generated from the
  records (LLVM's inference contained in ours for every function it can
  analyze), extending `effects.md` 4.4's `tests/runtime-effects` to
  program functions.

**I2. `willreturn` withheld under `io`.** *Coordinator.*
- Evidence: F2.
- Counterexample: `main = do l <- getLine ; putStrLn l` run as `sleep inf
  | prog` blocks in `getLine` inside a function the attributes promise
  returns; run as `prog | true`, the write after `true` exits ends the
  process by `SIGPIPE` inside such a function. Both are undefined
  behaviour to LLVM (`LangRef.md:2522-2534`); *conjecture* that no
  transform at the pin exploits it today, which is luck, not construction.
- Root cause: "stops returning" was read off the program's own endings
  alone; the environment can stop an IO action too.
- Correction: the atom record's `stops` column gives `io` "may not
  return" (it still makes progress), so `willreturn` requires the row to
  hold none of `io`, `exit`, `crash`, `divergence`; runtime IO calls carry
  no `will_return`. It costs nothing: a call holding `io` is never deleted,
  merged or hoisted anyway.
- Deletes: nothing.
- Discrimination: a law in the specification (every atom whose call may
  be ended or held by the environment stops `willreturn`), evaluated when
  the generator is built.

**I3. V1 is containment after every pass, equality at every write; V0
goes.** *Coordinator* (`effects.md` 6.8 listed it for the owner, but it
decides no meaning, promise or scope: both forms keep one writer and the
same soundness, and containment is the standard subsumption rule,
`typed-effects.md` 3.3.7).
- Evidence: F4, F17.
- Counterexample: a match on a known constructor whose other case
  crashes; canonicalize inlines the known case and deletes the crash;
  `own(f)` loses `crash`, the stored row keeps it; under equality the
  verifier rejects a correct canonicalization, an internal error on a
  valid program, unless a program-level writer runs after every
  canonicalize and CSE of the nested groups.
- Root cause: §5.1's restatement of D22 dropped `effects.md`'s
  distinction.
- Correction: 2.4. The coordinator restates §5.1's sentence.
- Deletes: V0 and its stage fact; any thought of a writer after every
  pass.
- Discrimination: a verifier unit test (a row strictly larger than its
  derivation passes; one missing an atom fails, naming it).

**I4. Consumption is `Free` on `count` alone.** *Coordinator* (seam with
L01).
- Evidence: F7.
- Counterexample: after counting, `wrap : (1 xs : List Int) -> Maybe (List Int) ;
  wrap xs = Just xs` is a `con` consuming owned `xs`; with the `Read`,
  its row is `{count}` (and `alloc` once the cell is made): every call of
  it declares a `Write` on `count`, so an unused call is never dropped and
  LLVM sees `argmem: readwrite` for a function that only stores a
  pointer.
- Root cause: one fact (a reference ends) declared as two effects, one of
  which projects.
- Correction: the `Consumes` rule declares exactly `Free` on `count` of
  the operand; `P` gives it nothing; `take` and `drop` keep their own
  count reads, which are real.
- Deletes: the `Read` from every consuming op's declaration.
- Discrimination: over the counted test corpus, no function's row holds
  `count` unless an op that really touches a count (`dup`, `drop`,
  `take`, `is_unique`, `array.get`, `memo.run`) is reachable from it;
  measurement to take: the number of functions whose row changes.

**I5. `llvm.func` is made by the step that leaves `idr.func`, carrying
the row's attributes.** *Coordinator* (AGENTS.md forbids the discardable
carrier; D18's lossless rule forbids dropping the fact). Seam with L09,
L13.
- Evidence: F11.
- Counterexample: today a terminating recursive function reaches LLVM
  with no `mustprogress` and no `willreturn` (CV-05), so LLVM keeps every
  endless-looking loop and every unused call of it; carrying the facts on
  `func.func` as discardable `llvm.*` attributes across twelve passes
  would let any of them drop the facts silently.
- Root cause: phase 0 builds an intermediate op with no slot for the fact.
- Correction: phase 0 builds `llvm.func` (and `llvm.call`,
  `llvm.return`) directly, writing `memory_effects`, `will_return`,
  `no_unwind` and the `passthrough` names from the row by the one
  generated function; the post-lowering upstream passes, each of which
  reads any op (canonicalize, CSE, the linalg, vector, affine, strided
  metadata and scf conversions), nest on `llvm.func` instead of
  `func.func`. Their bodies only remove effects or rewrite array accesses
  the row already covers, so the attributes stay true.
- Deletes: `FuncToFunc.cpp`'s `LowerFunc`, `LowerCall`, `LowerReturn` and
  the `func.func` stage of the lowered program.
- Discrimination: 2.6's measurement (c) is non-zero on the benchmarks; the
  loop-deletion case (an effect-free loop in a terminating function whose
  result is unused) is gone from the emitted program.

**I6. `noalias` on every exclusive owned pointer parameter.**
*Coordinator* (a proved fact not reaching its reader, D10). Seam with
L08, L11.
- Evidence: section 3, item 1.
- Counterexample: an in-place loop over an exclusive array that also
  reads a borrowed table reloads the table's words after every store to
  the array and does not vectorize, though the types prove they never
  alias.
- Root cause: exclusivity lives in the type and stops at the lowering.
- Correction: the lowering's parameter attributes write `noalias` where
  the parameter's type is `!idr.excl` and owned and lowers to a pointer.
- Deletes: nothing; it is a fact delivered.
- Discrimination: a benchmark of such a loop, run time measured before
  and after on all four targets; and a check that no lowered body stores
  an exclusive parameter and reloads it within the call (the conjecture
  `noalias` rests on).

**I7. Region-op sets without a pointer-keyed map; `EffectSet` without a
`bool`.** *Coordinator* (AGENTS.md's C++ rules).
- Evidence: F9.
- Counterexample: a 30,000-case match (S1's fixture) queried by MoveOut
  and Sink: a `DenseMap<Operation *, EffectSet>` per function is the
  per-node pointer map the rules forbid, and a stale entry after a
  rewrite is a wrong answer.
- Root cause: random access keyed by identity instead of by a numbering.
- Correction: each reader folds region sets bottom-up in its own walk;
  random access goes through the function's one op numbering (L15);
  "declares nothing" is `EffectSet::everything()`.
- Deletes: `effects.md` 3.3's `Cache` and 3.1's `unknown`.
- Discrimination: the S1 fixture's time and peak memory in MoveOut and
  Sink, measured.

**I8. An effect on memory the function acquired itself is local.**
*Coordinator* (upstream's own reading, `SideEffectInterfaces.cpp:79-95`
and `LocalAliasAnalysis.cpp:240-300`, extended from one op to one
function).
- Evidence: section 3, item 3.
- Counterexample: `replicate : Nat -> Int -> Array Int` built by a fill
  loop on a fresh buffer has row `{alloc, write}` after bufferization, so
  `sum (replicate n 1)` computed twice is not merged and an unused one is
  not dropped, though before bufferization both were (C3).
- Root cause: `P` reads the effect's resource but not where its value's
  memory came from.
- Correction: in `own`, an effect naming a value whose underlying object
  (through views, upstream's `collectUnderlyingAddressValues`) is the
  result of an `Allocate` on `heap` or on the frame in the same function
  projects to nothing; a value-less `Free` at an `idr.lifetime`'s end is
  local the same way. Bounded walk per value-carrying effect, in the
  same parallel walk.
- Deletes: the `write` atom from functions that only fill what they built.
- Discrimination: the program above with its output, and the
  measurement of rows that lose `write` on the array suite.

**I9. The derivation is a fold over declaration forms; a call
contributes its row.** *Coordinator.*
- Evidence: F3.
- Counterexample: `mk : Int -> Box` allocates (row `{alloc}`); `g n = (mk
  n, mk n)`; deriving `g` through `mk`'s call effects (none) gives `g` no
  `alloc`; idr-expect's heap-free check passes `g`, and LLVM is told `g`
  writes no `other` memory, so it may merge two calls of `g` into one
  allocation that two owners then each release: a double free.
- Root cause: `effects.md`'s round trip, written before reporting atoms.
- Correction: 2.3's `own`.
- Deletes: the claim "`derive` never asks `isa<CallOp>`" (it asks the
  declaration form, a closed sum, through one fold).
- Discrimination: the program above (`no-heap-allocation` must fail on
  `g`); a `static_assert` that every reporting atom has no call effects,
  beside one that `own` reads `Summarized`.

**I10. A call is speculatable exactly when its row allows it.**
*Coordinator.*
- Evidence: F10.
- Counterexample: `for i in [0..n] (a[i] := f k)` with `f` terminating
  and its row empty after counting: upstream's LICM never hoists `f k`,
  so it runs n times.
- Root cause: `idr.call` declares no `ConditionallySpeculatable`.
- Correction: `idr.call` implements it from the row: speculatable when
  the row holds no `io`, `exit`, `crash` or `divergence` (a generated
  predicate over the atoms' `stops` column); LICM still requires the call
  to be free of declared effects (`isPure`), so only empty or
  reporting-only rows with no owned argument and no linear result move.
  D23 allows hoisting an allocation.
- Deletes: nothing.
- Discrimination: the loop above, run time measured; a property test
  that a speculatable call's row holds no stopping atom.

**I11. A foreign call holds `crash`, `divergence` and `free`, and is
never `nosync`, `willreturn` or `mustprogress`.** *Coordinator* (for
0020; C2's text amended).
- Evidence: F14.
- Counterexample: a Rust function that panics (an abort) called from a
  function whose row lacks `crash` is given `willreturn`; one that loops
  waiting on a Rust thread is given `mustprogress` and `nosync`.
- Root cause: R4 lists what the operands' types say and forgets what Rust
  does not prove.
- Correction: R4's rule set adds the four facts, as rules of the
  specification.
- Deletes: nothing in P0.
- Discrimination: 0020's own tests, when taken.

**I12. `total` on `idr.func` is renamed `terminates`.** *Coordinator*
(D40's maximal naming; the code already holds termination).
- Evidence: 1.2 (the frontend reads `checkTerminating`).
- Counterexample: a reader taking `total` for "covering and terminating"
  would drop the crash of a terminating partial function.
- Root cause: a name that says more than the fact.
- Correction: rename in the specification; D13's licence reads
  "termination, as Idris's checker proves it" (an assertion of
  totality counts, as upstream's checker counts it; a false one is the
  programmer's broken promise, consistent with D13 and D12).
- Deletes: the word.
- Discrimination: none needed beyond the build.

**I13. `may_loop` lowers to nothing.** *Optional simplification.*
- Evidence: LLVM deletes a possibly endless loop only under
  `mustprogress` (`LoopDeletion.cpp:116-129`, `LoopInfo.cpp:1219-1229`),
  which a function holding `divergence` never gets once I5 lands; the
  `llvm.sideeffect` marker (`lib/Conversion/Runtime.cpp:205-210`) then
  guards nothing. `may_loop` stays in MLIR, where it keeps a pure loop
  from upstream's DCE.
- Deletes: `Runtime::mayLoop`.
- Discrimination: the semantics test of an endless loop in partial code
  still hangs (with a timeout as its expected result).

## 5. Work units

**WU1. The row, the derivation, the writer, the verifier.**
- Write set: `foreign/idr/include/idr/IR/Effects.h` (new),
  `foreign/idr/lib/IR/Effects/` (new), `foreign/idr/include/idr/IR/Func.h`,
  `foreign/idr/lib/IR/Func/Func.cpp`, `foreign/idr/lib/IR/Func/Call.cpp`,
  `foreign/idr/lib/IR/Verify/Program.cpp`, the function verifier in
  `foreign/idr/lib/IR/Verify/`, `foreign/idr/lib/Transforms/Effects/Effects.cpp`;
  deletes `foreign/idr/include/idr/Analysis/Effects.h`,
  `foreign/idr/lib/Analysis/Effects.cpp`.
- Outcome: 2.1 to 2.5; the writer at 2.3's insertion points.
- Deletes: 1.4's first seven rows.
- Must not: read a resource or atom by name outside the generated
  tables; keep a pointer-keyed map; write a row outside the writer and
  clones.
- Acceptance: every program test passes unchanged on four targets; V1 and
  V2 hold after every pass of the suite; the three programs of 02 §3.7
  (`effects.md` 8.3 G3) behave as specified; the writer's and V1's time
  on the stage-1 module recorded.

**WU2. Every reader through the API.**
- Write set: the files of 1.4's last three rows and of `effects.md` 5.3,
  5.4 (MoveOut, Sink, CaseOfCase, Force, Bufferize, IdentitiesRecord,
  Consumer, Contracts, Expect, Frames, FramesPlan, Specialization, Raise,
  Component, Waves, Tail).
- Outcome: one classifier, one row question per reader; clones copy their
  source's row.
- Deletes: every hand reading of the bits; MoveOut's second classifier.
- Must not: change a pass's decision except where the old reading was
  wrong (a callee that may exit, a row with memory atoms).
- Acceptance: the program suite's outputs unchanged; idr-expect's
  properties restated over the API by L19 pass.

**WU3. Rows to LLVM.**
- Write set: `foreign/idr/lib/Conversion/FuncToFunc.cpp` (replaced by
  the step of I5), `foreign/idr/lib/Conversion/Runtime.cpp`,
  `foreign/idr/lib/Conversion/RuntimeCalls.cpp`, the pipeline's
  post-lowering nesting in `foreign/idr/lib/Transforms/Pipeline.cpp`
  (shared with L09/L13's units), the generated LLVM columns.
- Outcome: 2.6 on every function and runtime call; I6's `noalias`; I13.
- Deletes: the `func.func` stage; `Runtime::mayLoop`.
- Must not: write any attribute a row does not imply; write a discardable
  attribute.
- Acceptance: 2.6's measurement with (a) zero; I1's and I2's programs on
  four targets; benchmarks' run time recorded.

**WU4. The op side of the row** (with L01's unit): consumption as `Free`
alone (I4); `Free` on `heap` on every releasing runtime op; I10's
speculatability on `idr.call`; I8's locality in `own`.
- Write set: the generated op declarations (through the specification,
  L03), `foreign/idr/lib/IR/Effects/`.
- Acceptance: I4's and I8's measurements; I10's loop.

**WU5. The upstream patches that remain.** U1 (`llvm.call` reports
`memory_effects`), alone after WU3, `upstream/<id>/llvm-project.patch`
with its test; U2 only if `ub.unreachable` survives (F16); U4 dropped.
- Acceptance: `tests/upstream-<bug>` per patch; PINS.md entries.

**WU6. The tests** (L19's units): the programs of I1, I2, I4, I8, I9,
I10 with their outputs; the attribute soundness check generated from the
records.

## 6. Owner questions

**Q1. Is a lifetime parameter a run-time handle (D39) or a compile-time
binder (D48)?** The two rulings say both.
- (A) Always a handle, as D39 says: every function with a lifetime
  parameter takes an argument at run time, even one that only takes
  views. Costs a register and a move per call for a fact the compiler
  knows needs nothing (D10). Buys simplicity.
- (B) Always erased, as D48 says: no callee can allocate into its
  caller's lifetime, so D39's "a callee can build its result in the
  caller's scope" is lost, or needs a dynamic "current lifetime".
- (C) The variable is erased (D48), and a function that allocates into a
  lifetime parameter takes that lifetime's arena as a run-time
  parameter, its presence derived over the components with the rows and
  verified, the allocation effect living in the type as C2 R3 requires.
  Costs one more inference over the same schedule. Buys both rulings.
- Recommendation: (C).

**Q2. Does the row gain a part per parameter, for writes through
exclusive owned parameters?** D29 fixes the row as eleven atoms.
- (A) Eleven atoms only: every write in place is a value-less `write` at
  the call. Costs: array-building and in-place functions stay
  undeletable and unmergeable after counting at every caller, and LLVM
  never learns the write is argument memory only.
- (B) A per-parameter part, indexed by the parameter's grade (only an
  exclusive owned parameter has one): the call declares the write on that
  operand, and a caller passing memory it acquired loses the atom (I8).
  Costs a wider property and a per-parameter join in the writer. Buys the
  in-place promise's (D24) and arrays' (D43) common case, and is QTT
  carried into the row.
- Recommendation: (B).

HEAD at the start: `e96bb991`. HEAD at the finish: `e96bb991`.
