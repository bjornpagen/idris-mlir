<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design: the effect vocabulary

Written 2026-10-21 at e96bb991, for the owner: "now that we have a proper
effect system, we need to think about it and deeply think about and
rename all the effects properly"; and: "if we ever need to handle ooms or
soft/hard memory limits, clearly heap allocation needs to be its own
effect ... any new allocation of new memory into the snmalloc arena".
It keeps `effects.md`'s machinery (one source, one query API, one
derivation, the verifier) and replaces its tree, atoms and rule names and
every name of today's. Held to D9, D10, D12 to D14, D16, D20 to D23
(`proposals/0000-mlir-native.md` §2), AGENTS.md and the
representation-first skill; allocation under D23 alone (relayed while
this was written). Nothing was built or run.

Claims are marked *read* (a path and line: ours at e96bb991, upstream
under `.toolchain/llvm-project`, snmalloc under
`third_party/snmalloc/src/snmalloc`), *recalled*, *conjecture* or
*decision* (a ruling Dn). "Decided here" marks this design's choice: a
proposal for the owner's review, never settled until approved (AGENTS.md:
architectural choices go to the owner before they are recorded). "02
§3.7" is `audits/p0/02-ods-effects.md`, "5.11 M2" is
`audits/p0/wave1/5.11-oom.md`, "effects.md 1.4" is `design/effects.md`.

*Status (2026-10-21):* the tree is settled by D27 and the resources'
names by D28, the atoms' names by D29 (one name per concept:
`runtime_state`, `memo_state`, `divergence`), all in
`proposals/0000-mlir-native.md` §2; 8.2's DP-31 is still the owner's.

## 0. In plain words

- **Twelve resources, ten of them ours.** The outside (`IO`) is one ordered
  state with three run-ending children (`Crash`, under it `Divergence`;
  `Exit`) and the runtime's private tables (`RuntimeState`). The heap is
  the arena's memory (`Heap`: acquired and given back), with what live
  memory holds beneath it (`Contents`, `Count`, `MemoState`). A linear
  value's identity (`Identity`) and upstream's frame stand apart.
- **Allocation is its own effect.** New memory entering snmalloc's arena
  is MLIR's `Allocate` on `idr.heap`, on the op's result. Reusing a
  cell, a stack cell and static data are not. Scratch memory a runtime
  function takes and gives back is a fact of that function. Under D23
  nothing is ordered with an acquisition, so it is deletable, sinkable
  and replaceable; the row still reports it (`alloc`, and `free` for
  memory given back), and idr-expect, a runtime limit (DP-19) and LLVM
  read it.
- **Eleven atoms**, printed as today: `effects<io, crash, alloc>`. Nine
  order calls (`io runtime exit crash diverge read write count memo`);
  two only report (`alloc free`).
- **Four declarations that lie today** (2.6): string builders and
  `handle.string` claim fresh memory but may share, `memo.run` writes
  counts it does not declare, `take` is said to free what it never frees,
  closures build cells they do not declare.
- **For the owner**: one question, put with DP-12 (8.1); three choices
  made here, for review (8.2).

## 1. The states a compiled program has

What exists while a program runs, where it lives, and what can observe
it. An effect exists only for state that changes while something can
observe it; the outside is one ordered state (AGENTS.md: "in program
order with every other effect"); what the outside never sees stands
apart from it, so that it may move (D21).

| # | state | where it lives (read) | observed by | resource |
| --- | --- | --- | --- | --- |
| 1 | standard output and error | one static buffer, `runtime/Io/Output.cpp:35-36`; fds 1, 2 | the outside; flushed at exit and crash (`Io/Ending.cpp:56-71`) | `IO` |
| 2 | standard input | the stdin buffer (`Io/Input.cpp:23-30`, via 18 §2.3); fd 0 | consumed by each read | `IO` |
| 3 | files, directories, the terminal | the OS, through handles | the outside, other processes | `IO` |
| 4 | the environment, the working directory | the process | child processes, later reads | `IO` |
| 5 | clocks, the process id | the OS | each reading: time moves | `IO` (read and write, so two readings never merge) |
| 6 | argv, the OS name, an error number's text | fixed for the run (`Start/Entry.cpp:137-141`; strerror's text "the same at every call", `IdrPlatformOps.td:311-312`) | nothing changes it | none (D20's exact row; effects.md 4.4's audit confirms each) |
| 7 | the handle table, the saved errno | runtime globals (`Io/Handles.cpp:64-73`; `Io/Errors.cpp:18`, via 18 §2.3) | only the program's own ops | `RuntimeState` |
| 8 | memory written in place: array elements, buffer bytes, a cell's fields at its init or through a destination | heap memory | the program's own reads; the outside only through IO ops (D21) | `Contents` |
| 9 | immutable memory: strings, bigs, fields after init | heap or static data | nothing changes it while referenced | none: no effect reads it (`Idr_StrRead` already declares none, `IdrOps.td:18-27`) |
| 10 | reference counts | cell headers (`idris_rt.h:79-82`, via 18 §2.2) | a drop's zero test, `is_unique`, reuse | `Count` |
| 11 | memo state | memo cells | a force; `tag`, `field`, `match` of a memo sum | `MemoState` |
| 12 | the arena: chunks, slabs, free lists, committed bytes | snmalloc, configured in `Alloc/Cells.cpp:47-125` | nothing in the language (D23); the allocator, a limit (DP-19), the OS's footprint, LLVM | `Heap` (Allocate, Free only) |
| 13 | frame cells; the stack's depth | the runner's reservation (`Start/Runner.cpp:27-96`, via 18 §2.2) | frame cells their ops; depth nothing in the language (exhaustion is a machine crash, D23's analogue) | upstream's frame |
| 14 | static data | the binary, count 0 | nothing, but a static memo cell's force (row 11) | none |
| 15 | the run ending normally | `idris_rt_io_exit`, `Io/Ending.cpp:56-61` | the outside: status after flushed output | `Exit` (D14) |
| 16 | the run ending by a crash | `idris_rt_crash`, `Io/Ending.cpp:66-71` | the outside: message and status after flushed output | `Crash` (D13, D21) |
| 17 | the run ending out of memory or stack | the allocator's continuation (18 T-AL1), the guard page | the outside, but at no op (D23) | none |
| 18 | termination | — | the outside: a hang instead of what follows | `Divergence` (D13) |
| 19 | a linear value's identity | compile time only | the linearity verifier; CSE must never merge two | `Identity` |

## 2. Allocation as its own effect (D23)

### 2.1 Where new memory enters snmalloc's arena

Every byte of heap memory a program holds comes through `rt::alloc`
(read): `allocate` (`Cells.cpp:168-173`) and `newCell` over it (`:187-192`,
the header written, `idris_rt_cell` at `:215-217`). Inside snmalloc, in
three layers:
1. **The fast path** pops the thread's free list for the size class
   (`mem/corealloc.h:647-650`): memory a free gave back earlier, already
   the process's.
2. **A refill** takes the slab's free list or the remote frees; failing
   those, `small_refill_slow` takes a new slab chunk from the backend
   (`corealloc.h:838-855`); a large request goes straight to the backend
   (`alloc_not_small`, `:689-723`).
3. **The backend** (`backend/backend.h:89-127`) draws a chunk from the
   thread's buddy cache, then the global one, and below them
   `CommitRange`, which commits pages (`notify_using`,
   `backend_helpers/commitrange.h:28-46`) while `StatsRange` counts the
   committed bytes (`statsrange.h:31-33`; the pipe,
   `backend/standard_range.h:30-41`); under it the platform reserves
   address space, or the 4 GiB region of ours is drawn on
   (`Cells.cpp:93-105`).

New memory enters the arena, in the operating system's sense, only at
layer 3, and only on the slow path of an allocation call. Every op that
calls an allocation entry point may reach it; no other op can. Which
call does is decided at run time by the free lists.

The entry points (read): `newCell` for strings (`Strings/Making.cpp:24`),
bignums (`Big/Operands.cpp:38`), arrays (`Alloc/Arrays.cpp:105`), and
boxes, thunks and closures (`idris_rt_cell`); `memref.alloc` lowers to
`idris_rt_array_new` (`foreign/idr/lib/Conversion/Arrays.cpp:54`); raw
blocks for GMP (`Alloc/Gmp.cpp:17-19`), a big's digits
(`Big/Digits.cpp:20`), IO scratch (`Io/Scratch.cpp:26`), the handle
table's growth (`Io/Handles.cpp:77`) and the persist walk's stack
(`Rc/Freeing.cpp:168-181`). A release acquires nothing: its list is
threaded through the dying cells (`Rc/Freeing.cpp:138-157`).

### 2.2 The sources of a value's memory

| source | ops | declared | acquires |
| --- | --- | --- | --- |
| the arena | `cell.new`; before idr-rc, `con` of a box and `closure`, `suspend`, `delay`; the runtime builders (`str.*`, `big.*` results, `io.get_line`, `io.arg`); `array.new`; `memref.alloc` | `Allocate` on `idr.heap`, on the result | yes |
| reuse | `cell.recycle` of a token that holds its cell | the token consumed; `Allocate` on `idr.identity`, on the result | no |
| reuse or the arena | `cell.recycle` of a token that may be null (the take of a shared box, `IdrOwnershipOps.td:215-231`) | `Allocate` on `idr.heap`, on the result | maybe; the token's type says which (18 T-RC4) |
| the frame | `cell.stack`, `memref.alloca` | `Allocate` on upstream's frame | no |
| static data | `idr.constant` of a string or a box | nothing | no |
| scratch | GMP's temporaries, IO scratch, the handle table, the persist walk | the runtime function's `Scratch` fact (2.3) | yes, and gives it back |
| a share | `str.append` with an empty side; `handle.string` | a new reference to old memory (2.6 F1) | no |

```mlir
// acquires: new memory from the arena
%c = idr.cell.new : !idr.cell<!idr.box<!L>, @Cons>
//   remark: found an instance of 'allocate' on op result 0, on resource 'idr.heap'
// reuse: the token's own cell, a new identity on old memory
%d = idr.cell.recycle %t : !idr.own<!idr.token<!idr.box<!L>, @Cons>> -> !idr.cell<!idr.box<!L>, @Cons>
//   (a token typed as holding its cell; one that may be null: 'idr.heap')
//   remark: found an instance of 'read' on op operand 0, on resource 'idr.count'
//   remark: found an instance of 'free' on op operand 0, on resource 'idr.count'
//   remark: found an instance of 'allocate' on op result 0, on resource 'idr.identity'
// the frame
%e = idr.cell.stack : !idr.cell<!idr.box<!L>, @Cons, frame>
//   remark: found an instance of 'allocate' on op result 0, on resource 'AutomaticAllocationScope'
// static data: no effect at all
%s = idr.constant "hello" : !idr.str
```

(The remark text is upstream's test pass's, `mlir/test/lib/IR/TestSideEffects.cpp:43-65`, read.)

### 2.3 How it is declared, and how upstream reads it

**`Allocate` on `idr.heap`, on the result.** Upstream reads it exactly as
D23 asks (read):
- `wouldOpBeTriviallyDead` drops an effect on a result the op allocates
  (`lib/Interfaces/SideEffectInterfaces.cpp:43-110`): an unused
  acquisition is dead, the canonicalizer and CSE delete it.
- CSE merges only ops whose every effect is a `Read`
  (`lib/Transforms/Utils/CSE.cpp:268`): two acquisitions stay two cells,
  each with its own count.
- LICM hoists only `isPure` ops (`LoopInvariantCodeMotionUtils.cpp:117`),
  upstream's sink only effect-free ones (`ControlFlowSink.cpp:46`); our
  sinking (`Canon/Sink.cpp`) moves acquisitions, by "only allocates".
- Local alias analysis takes an allocated result as fresh
  (`LocalAliasAnalysis.cpp:264`) and skips allocation and free effects in
  mod-ref (`:511`); hence a result may be declared allocated only if it
  is fresh (2.6 F1).
- It carries no `Crash`, no `IO`: an acquisition moves across output,
  guards, crashes and other acquisitions (D23).

**Never a value-less `Allocate` on `idr.heap`.** Upstream keeps an op that
has one (5.2 A6), so an acquisition with no result to name would make a
pure op undeletable. Scratch memory a runtime function takes and gives
back before it returns is therefore not an MLIR effect, as upstream
counts an allocation "part of computing a result" (effects.md 1.4): it
is a fact of the function, `Scratch` on its meaning (6), which the row
and the lowering read and upstream never sees. The specification makes
the other form unwritable (6, law L6).

**`Free` on `idr.heap`, on the operand**: memory given back, by a `drop`
(its cell and what it held) or a token's free; upstream keeps every such
op (5.2 A6).

### 2.4 What it buys, and what it does not mark

1. **Allocation-free is a bit of the row.** idr-expect's
   `no-heap-allocation` walks every op and keeps three exceptions:
   closures and suspensions that declare nothing, `LinResource` and the
   frame (`lib/Transforms/Expect/Allocation.cpp:26-44`, read). It becomes
   "the row lacks `alloc`", read in O(1) per function, its exceptions
   gone with the declarations that needed them. This is the heap-free
   check AGENTS.md names.
2. **The exact places a limit or the allocator's refusal can act.** A
   memory limit (DP-19) is one more range in snmalloc's pipe at layer 3
   (5.11 M2, B4), reached only from an op with an acquisition or a
   `Scratch` fact; a function whose row lacks `alloc` can never meet it.
3. **LLVM is told** (7): a function that neither acquires nor writes is
   `memory(read)` at most, so LLVM may merge, hoist and delete its calls.
4. **A later change is one edit**: a handled failure, if one ever enters
   (proposal 0020's Rust, *conjecture*), makes `alloc` an ordering atom.

What it does not mark: under overcommit the OS kills at a page's first
touch (5.11 K1, K3), which may be the write filling a fresh cell or a
call growing the stack; stack exhaustion likewise. Neither is an op's
effect (D23); the named ending is the runtime's (18 T-END1).

### 2.5 D10

- Whether an op acquires is a constant of its class, but for two typed
  rules read off types (a cell result; a token that may be null).
- Nothing is added to compiled code: a limit acts at layer 3, on the slow
  path, where `StatsRange` counts already. The live-cell counter on every
  allocation (`Cells.cpp:157, 190`), a test fact, goes (18 T-AL4).
- What the compiler knows reaches LLVM (7), so a pure or read-only call
  is no longer paid for at every site.

### 2.6 Four declarations that lie today (read)

- **F1. A share declared as an allocation.** `idris_rt_str_append` gives
  back the other string "with one more reference" when one side is empty
  (`Strings/Concat.cpp:29-35`; likewise `Strings/Scalars.cpp:119, 162`);
  `handle.string` gives "the string a string handle holds, with a
  reference of its own" (`IdrPlatformOps.td:363-374`). Both declare
  `MemAlloc` on the result, a claim of fresh memory that alias analysis
  trusts, and the new reference is a count write nobody declares.
  Decided here: `handle.string` declares what it does (`Read` on
  `RuntimeState`, `Write` on `idr.count` from the owned stage); the
  string builders become exact by the runtime's meaning, building a new
  string in the rare empty case (one copy, measured first), since a
  share cannot name its acquisition on a fresh result and a value-less
  one is unwritable (L6), so the row would lose it (L5). The runtime
  audit (effects.md 4.4) owns the full list.
- **F2.** `memo.run`'s lowering calls `idris_rt_persist_held`
  (`lib/Conversion/MemoCells.cpp:98`), which writes count 0 into what a
  static memo cell holds (`runtime/Rc/Counting.cpp:81-86`) and allocates
  its walk's stack (`Rc/Freeing.cpp:168-181`); `memo.run` declares only
  memo state. It gains a `Write` on `idr.count` of its cell and the
  `Scratch` fact.
- **F3.** `take` never gives memory back: an exclusive box becomes the
  token, a shared one loses one of at least two references
  (`IdrOwnershipOps.td:304-318`). effects.md 1.7 gives it `MemFree<Heap>`;
  it is consumption and a count write, nothing on `idr.heap`.
- **F4.** `closure`, `suspend` and `delay` build a cell and declare none
  (`IdrClosureOps.td:37, 54, 72`), the reason for two of 2.4's exceptions.
  The `alloc` atom cannot be exact without their `Allocate`: DP-31's
  option B is forced.

## 3. Each effect, precisely

Upstream's four kinds and nothing else. The facts that are not memory
are stated so that upstream passes read them right:
- **may crash** (D13: kept where evaluation reaches it): a `Write` on
  `Crash`, and not speculatable (an op without `ConditionallySpeculatable`
  is not, to MLIR). A guard returns its operand refined, which the total
  op reads, so the total op stays below it by data dependence (D21).
- **may not end** (D13): a `Write` on `Divergence` (`may_loop` in the
  loops of a function without `total`); a function's own loops, through
  the row's seed (4.4).
- **ends the run normally** (D14): `io.exit` is an IO action, a
  terminator with no successor, and a `Write` on `Exit`.
- **runs unknown code** (`apply`, `force`): every atom, by one
  declaration (`RunsUnknown`).

| family | ops | effects | speculation |
| --- | --- | --- | --- |
| IO actions | `io.put_*`, `io.get_*`, files, directories, environment, clocks, terminal, process, `io.read_bytes`, `io.write_bytes` | `Read`, `Write` on `IO`; a string result `Allocate` on `idr.heap`; a buffer `Read` or `Write` on `Contents`; `Scratch` where the runtime grows scratch | never |
| IO observing nothing that changes | `io.arg`, `io.arg_count`, `os`, `io.strerror` (each confirmed by effects.md 4.4's audit) | none but the result's `Allocate` | always |
| runtime state | `io.errno`; `handle.string` (F1) | `Read` on `RuntimeState` | never |
| the run's end | `io.exit` | `Read`, `Write` on `IO`, `Write` on `Exit`; terminator, no successor | — |
| crashes | `crash`, `crash_str` (one terminator, 03 R4) | `Write` on `Crash` | — |
| guards | `check.nonzero`, `.in_bounds`, `.nonempty`, `.finite`, `.range` | `Write` on `Crash`; result is the operand refined | never |
| guarded total ops | words, doubles, the total halves of `big.*`, `str.*` | none; a big or string result `Allocate` on `idr.heap` | `GuardedOp`: when its guard feeds it |
| loop marker | `may_loop` | `Write` on `Divergence` | never |
| values | `con` | rules `Consumes fields`, `AcquiresCell result` | not, if its result is a cell or a field is owned |
| | `field`, `tag`, `match` | rule `ReadsMemo` on the value or scrutinee | `field` not, on a cell |
| | `constant`, `borrow`, `own.adopt` | `Pure` | always |
| closures | `closure`, `suspend`, `delay` | rules `Consumes captures`; `Allocate` on `idr.heap` of the result (F4) | always |
| running a label | `force`, `apply` | `RunsUnknown` | never |
| memo | `memo.run` | `Read`, `Write` on `MemoState` and `Write` on `idr.count`, of its cell (F2); `Scratch`; its body | recursive |
| counting | `dup` | `Read`, `Write` on `idr.count` of the value | — |
| | `drop` | `Read`, `Write` on `idr.count`, `Free` on `idr.heap`, of the value (an exclusive drop: no `Read`, D10) | — |
| | `is_unique` (08 T8) | `Read` on `idr.count` | folds on an exclusive type |
| | `take` | `Read`, `Write`, `Free` on `idr.count` of the box (F3) | — |
| | `share`, `unpack`, `own.give`, `nat.to_big`, `return`, `yield` | rule `Consumes` | as today |
| cells | `cell.new` | `Allocate` on `idr.heap` of the result | — |
| | `cell.stack` | `Allocate` on the frame of the result | — |
| | `cell.recycle` | rules `Consumes token`; `Recycles result`: `Allocate` on `idr.identity` when the token holds its cell, on `idr.heap` when it may be null (`IfMayBeNull`) | — |
| | `cell.init`, `dest.write` | `Write` on `Contents` of the cell or destination; rule `Consumes fields` | — |
| linear | `lin.enter`, `lin.use` | `Allocate` on `idr.identity` of the result | always |
| arrays | `array.new` | `Allocate` on `idr.heap` of the result | — |
| | `array.get` | `Read` on `Contents`, `Write` on `idr.count` (the element's own reference), of the array | — |
| | `array.set`; `array.update` (recursive) | `Read`, `Write` on `Contents` of the array | — |
| buffers | `io.buffer_load`, `_store`, `_copy`, `_set_string`, `_get_string` | `Read` or `Write` on `Contents` of each buffer; `_get_string`'s result `Allocate` | — |
| calls | `call` | rules `Summarized`, `Consumes args`, `NewIdentity results` | — |
| definitions | `func`, `program` | none: never executed | — |
| trusted IO | `io.unsafe_run` (D20, replacing `world.new`) | its body's | recursive |
| upstream | `memref`, `scf`, `arith`, `linalg` | upstream's own; projected (4.4) | upstream's |

The world operands and `world.new` are gone, `tabulate_io` and
`element.update` merged (D20).

## 4. The tree, and the row

### 4.1 The tree

```
DefaultResource            upstream root, addressable       any memory; another dialect's op
├── AutomaticAllocationScope   upstream, addressable         the frame: stack cells
├── idr.heap               addressable    Allocate, Free     the arena: memory acquired and given back
│   ├── idr.contents       addressable    Read, Write        memory written in place
│   ├── idr.count          addressable    Read, Write, Free  reference counts
│   └── idr.memo_state     addressable    Read, Write        memo cells' state
├── idr.identity           addressable    Allocate           a linear value's identity
└── idr.io                 opaque         Read, Write        what the outside observes and supplies
    ├── idr.runtime_state  opaque         Read               the handle table, the saved errno
    ├── idr.exit           opaque         Write              the run ending normally
    └── idr.crash          opaque         Write              the run ending by a crash
        └── idr.divergence opaque         Write              the run never ending
```

Two resources conflict only when one is an ancestor of the other
(`SideEffectInterfaces.h:149-153`, read); a value effect needs an
addressable resource (`:338-343`), and an addressable resource may not
sit under an opaque one (`:160-173`).

### 4.2 Why each placement

- **`IO` is not split.** Console, files and clocks as siblings would let
  a clock reading move past output, which AGENTS.md forbids (effects.md
  1.2).
- **`Crash` under `IO`, `Heap` beside it** (D21): output before a crash
  comes first (the runtime flushes, `Ending.cpp:66-71`); nothing reads
  program memory after it, so heap effects move across crashes and
  guards.
- **`Divergence` under `Crash`.** Eager evaluation (D13) runs a loop that
  may not end before the crash after it; swapped, the program crashes
  instead of hanging.
- **`Exit` under `IO`, beside `Crash`, and no chain is needed.** Every
  pair of `crash`, `exit` and `diverge` must conflict, and in a tree only
  a chain does that. `io.exit` writes `IO` itself (D14: an IO action), an
  ancestor of `Crash` and `Divergence`, so a guard can never move above a
  call that may exit. The specification states it (law L8: whatever
  writes `Exit` writes `IO`). `Exit` exists so the row can say "may end
  the run" apart from `io` (D14).
- **`RuntimeState` under `IO`, read only** (eff-Q4 (b), decided here,
  8.2): every op that changes the table or errno writes `IO`, an ancestor
  (law L9), so a read stays after the change and moves across heap
  effects, guards and other reads.
- **`Heap` carries only `Allocate` and `Free`; its children carry the
  rest.** An array write does not conflict with a count read, nor a memo
  write with either; a release (a `Free` on `Heap`) conflicts with every
  access below it, which is the order a use of freed memory must keep.
  `Allocate` names a fresh result no other access reaches, so the query
  API counts it in no conflict, as CSE reads writes only (`CSE.cpp:214-233`).
- **`Identity` apart from `Heap`**: a new linear value is not memory, so
  "acquires" needs no exception for it (today's `isa<LinResource>`,
  `Allocation.cpp:38`, `Ownership/Reshape.cpp:302`).
- **The frame is upstream's** (`SideEffectInterfaces.h:196-202`), as
  `cell.stack` uses today (`IdrOwnershipOps.td:211`).

### 4.3 The atoms

An atom is one bit of a function's row, on one resource. An *ordering*
atom is one a caller orders with (D22): a call that holds it declares
its call effects, so upstream and our passes read the call right. A
*reporting* atom is one nothing orders with: an acquisition by D23, a
release because a callee gives back only what it was handed owned, which
the call's consumption already declares (the owned verifier holds it).
The call declares nothing for it; the row carries it for idr-expect, a
limit's places and LLVM.

| atom | resource | summarizes | use | stops a return |
| --- | --- | --- | --- | --- |
| `io` | `IO` | `Read`, `Write` | orders: `Read`, `Write` on `IO` | no |
| `runtime` | `RuntimeState` | `Read` | orders: `Read` on `RuntimeState` | no |
| `exit` | `Exit` | `Write` | orders: `Write` on `Exit` | yes |
| `crash` | `Crash` | `Write` | orders: `Write` on `Crash` | yes |
| `diverge` | `Divergence` | `Write` | orders: `Write` on `Divergence` | yes, and no progress |
| `read` | `Contents` | `Read` | orders: `Read` on `Contents` | no |
| `write` | `Contents` | `Write` | orders: `Write` on `Contents` | no |
| `count` | `Count` | `Read`, `Write` | orders: `Read`, `Write` on `Count` | no |
| `memo` | `MemoState` | `Read`, `Write` | orders: `Read`, `Write` on `MemoState` | no |
| `alloc` | `Heap` | `Allocate`, and `Scratch` | reports | no |
| `free` | `Heap` | `Free`, and `Scratch` | reports | no |

Not summarized: `Free` on `Count` (consumption, which the call declares
on its own operands by its rule, effects.md 1.4); `Allocate` on
`Identity` or the frame (local to the function).

```mlir
idr.func effects<read> @sum(%a: memref<?xi64>) -> i64 attributes {total}
idr.func effects<alloc> @replicate(%n: i64, %x: i64) -> !idr.box<!L> attributes {total}
idr.func effects<count, alloc, free> @mapInc(%xs: !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>> attributes {total}
idr.func effects<io, crash, diverge, read, alloc, free> @main()
idr.call @replicate(%n, %x) effects<alloc> : (i64, i64) -> !idr.box<!L>
//   to MLIR: nothing from its row (alloc reports); its rules add owned
//   arguments' consumption, owned or linear results' new identity
```

The verifier speaks the same words (V1, V2 of effects.md 4.1):

```
error: 'idr.func' op @replicate's effects<none> lack 'alloc', which 'idr.con' (at list.idr:3:5) acquires
error: 'idr.call' op effects<read> differ from @f's effects<read, alloc>
```

### 4.4 Projection: from an op's effects to the row

| an op's effect | summarized as |
| --- | --- |
| `Read`, `Write` on `IO` | `io` |
| `Read` on `RuntimeState` | `runtime` |
| `Write` on `Exit`, `Crash`, `Divergence` | `exit`, `crash`, `diverge` |
| `Read`, `Write` on `Contents` | `read`, `write` |
| `Read`, `Write` on `Count` | `count` |
| `Read`, `Write` on `MemoState` | `memo` |
| `Allocate`, `Free` on `Heap` | `alloc`, `free` |
| `Free` on `Count`; `Allocate` on `Identity` or the frame | nothing (consumption; local) |
| any kind on the root, naming a value | as on `Contents` or `Heap`: `Read` gives `read`, `Write` gives `write`, `Allocate` gives `alloc`, `Free` gives `free` |
| any kind on the root, naming no value | each atom of that kind |
| an op's `Scratch` | `alloc`, `free` |
| `RunsUnknown`; an op of another dialect with no declaration | every atom |
| a call | its row (the `Summarized` rule: each ordering atom's call effects project back to it, law L4) |
| the seed: a function without `total` (Idris proved its own loops end, `IdrOps.td:131-138`) | `diverge` |

`Read` and `Write` never land on `Heap` itself, nor `Allocate` on
`Contents`: each resource admits only the kinds of 4.1's column, by type
(law L3), so the table is total over what can be written. The root's
value row is exact, not a guess: the ops of another dialect a function
holds are upstream's (`memref`, `scf`, `linalg`, `arith`), whose effects
on the root name a memref, whose memory is array elements (*conjecture*,
checked by the cutover's gate over every upstream op the pipeline
creates); counts and memo cells are ours alone, touched only by `idr`
ops (law L5). So 4.3's `@sum`, a loop of `memref.load`s, is
`effects<read>`, not `read, count, memo` as effects.md 1.4's root rule
gave.

### 4.5 D22, checked

Every state a caller must order with has an ordering atom: memory its
arguments reach (`read`, `write`), counts (`count`), memo state (`memo`),
IO and runtime state (`io`, `runtime`), the run's ends (`crash`, `exit`,
`diverge`); so are 02 §3.7's three losses (`runtime`, `exit`, `memo` and
`write`). The arena is reported, not ordered, by D23.

## 5. Names

### 5.1 The scheme

1. **A resource is named as the state it is**, a noun, in the dialect's
   words (`Heap` is where a heap cell's memory comes from, as the frame is
   for a frame cell: `Idr_HeapCell`, `IdrOwnershipOps.td:173-178`), never
   for a reader's question ("may crash") or a mechanism ("reference").
2. **Effects are MLIR's four kinds**, never added to: consuming is `Read`
   with `Free`, acquiring is `Allocate` on `Heap`, ending is a `Write` on
   a run-ending resource.
3. **Printed resource names follow upstream's dialect form**,
   `transform.mapping` and `transform.payload_ir`
   (`TransformInterfaces.h:1278, 1289`, read): `idr.` and the noun in
   snake case, flat, the parent left to the tree.
4. **Atoms are lowercase single words, as printed today** (`io`, `crash`,
   `diverge`, `IdrAttrs.td:200-209`): an atom is named by its resource
   when it covers every kind it summarizes there (`io`, `runtime`,
   `exit`, `crash`, `count`, `memo`), and by the kind when a resource has
   two atoms (`read`, `write` on `Contents`; `alloc`, `free` on `Heap`,
   LLVM's own words for the two, `allockind("alloc")` and `("free")`).
   `diverge` keeps its spelling, the verb of `Divergence`.
5. **Rules are named by the effect, then the group**: `Consumes args`,
   `AcquiresCell result`, `ReadsMemo value`, `NewIdentity results`;
   conditions by what the type says (`IfOwned`, `IfCellPointer` as the
   type interface's `isCellPointer`, `IfMemoSum`, `IfOwnedOrLinear`,
   `IfMayBeNull`). `Consumes`, not effects.md's `Takes`: `take` is an op,
   and the dialect's descriptions say "consumes".
6. **C++**: classes in `idr::effects`, no `Resource` suffix (the
   namespace says it); the enum `ResourceId` (not to shadow
   `mlir::SideEffects::Resource`); `Row`, its bits `Atom`; generated
   TableGen records are `Idr_` and the Idris name.

### 5.2 Resources

| Idris (`Spec.Effects.Resource`) | C++ | printed | parent | reach |
| --- | --- | --- | --- | --- |
| `Root` | `mlir::SideEffects::DefaultResource` | `<Default>` | — | addressable |
| `Frame` | `mlir::SideEffects::AutomaticAllocationScopeResource` | `AutomaticAllocationScope` | `Root` | addressable |
| `Heap` | `idr::effects::Heap` | `idr.heap` | `Root` | addressable |
| `Contents` | `idr::effects::Contents` | `idr.contents` | `Heap` | addressable |
| `Count` | `idr::effects::Count` | `idr.count` | `Heap` | addressable |
| `MemoState` | `idr::effects::MemoState` | `idr.memo_state` | `Heap` | addressable |
| `Identity` | `idr::effects::Identity` | `idr.identity` | `Root` | addressable |
| `IO` | `idr::effects::IO` | `idr.io` | `Root` | opaque |
| `RuntimeState` | `idr::effects::RuntimeState` | `idr.runtime_state` | `IO` | opaque |
| `Exit` | `idr::effects::Exit` | `idr.exit` | `IO` | opaque |
| `Crash` | `idr::effects::Crash` | `idr.crash` | `IO` | opaque |
| `Divergence` | `idr::effects::Divergence` | `idr.divergence` | `Crash` | opaque |

`Heap`, not `Arena`, though D23 says "the arena": the dialect already
calls the lifetime `heap`, and snmalloc's `Arena` means address-space
authority (`capptr::Arena`, `Cells.cpp:97`, read), a third sense in code
we read. One word per concept; the doc line of `Heap` says it is the
arena of D23 (decided here, 8.2).

### 5.3 Every current name, and what becomes of it

| today (read) | becomes | why |
| --- | --- | --- |
| `Idr_IOResource` (`IdrInterfaces.td:88`), addressable, a sibling | `IO`, opaque, the outside's root | no effect on it names a value (02 E2); its run-ending children replace the double writes (02 E1) |
| `Idr_CrashResource` (`:87`) | `Crash`, under `IO` | named as the state; under `IO` by D21, so the crash family's second write of `IOResource` goes |
| `Idr_DivergenceResource` (`:89`) | `Divergence`, under `Crash` | D13 keeps it; the chain keeps a loop before the crash after it; `may_loop`'s second write goes |
| `Idr_LinResource` (`:90`) | `Identity` | it stands for a new value's identity, not linearity's rules: the call's owned results use it too |
| `Idr_ReferenceResource` (`:91`) | deleted | consumption is `Read` and `Free` on `Count`, the one resource every count op shares (08 T7, 5.10 R1.5) |
| `Idr_MemoStateResource` (`:92`) | `MemoState`, under `Heap` | memo cells are heap memory; its writes reach the row (02 §3.7) |
| `DefaultResource` on 51 ops (effects.md 1.7) | `Heap`, `Contents` or `Count`, named | the root conflicts with IO and crashes; each effect names its state |
| `Idr_MayCrashOpInterface` (`:105-111`) | deleted | `getCrashCause` is called through it nowhere (02 E15); "may crash" is a `Write` on `Crash`, the cause the op's own accessor |
| `Idr_MayCrash` (`:116-117`) | the bundle `MayCrash` = `Write` on `Crash` | the same name, now one effect: the interface and the `IOResource` write go |
| `Idr_PerformsIO` (`:295-297`) | deleted | "takes a world" (80 = 80, 02 F1), gone with the world (D20); Idris's sequencing is the primitive's Idris type in the specification, never an effect |
| `Idr_ObservableIO` (`:306-308`) | deleted | it is "writes `IO`"; D20's exact row gives `io.strerror` its due by its effects; its one reader asks the row (`io`) |
| `Idr_ConsumesOperands`, `Idr_ConsumesOnly` (`:314-316`) | the rule `Consumes g`; ops list `AlwaysSpeculatable` themselves | a typed rule from the one source (effects.md 1.6); the flow-edge rebuild per query goes (02 E53, E54) |
| `CallsRuntime` (`Idr_Runtime<"sym">`, `IdrBase.td:272-275`) | the op's `meaning = Runtime sym scratch` | not an effect (02 E69); its effect-bearing part is the new `Scratch` fact |
| `Idr_Primitive` (`IdrInterfaces.td:320`) | a field of the op | not an effect (02 E70) |
| `Idr_NoReturn` (`IdrCheckOps.td:19`) | deleted | a terminator with no successor (03 R4) whose `Leaves = Stops atom` names `crash` or `exit` (law L7) |
| `Idr_TakesReference` (`IdrBase.td:282-287`) | a `Write` on `Count` of the operand | the count write it restates (02 E59) |
| `Idr_BuildsValue` (`IdrBase.td:289-293`) | `Allocate` on `Heap` of the result | F4 |
| `may_loop`'s `MemWrite<Idr_IOResource>` (`IdrCheckOps.td:46-47`) | deleted; `MayDiverge` = `Write` on `Divergence` | the tree orders it with output |
| `force`'s three writes, `apply`'s nothing (`IdrClosureOps.td:101-103, 124`) | `RunsUnknown` on both | one declaration of "anything" (02 E31, E32) |
| `Idr_Effect` and its bits `io`, `crash`, `diverge` (`IdrAttrs.td:200-209`) | `Row`, generated from the eleven atoms; the bits keep their spelling | the atoms are the enum; `io` is D20's carrier, `crash` and `diverge` now mean exactly their resource's write |
| `anyEffect` | `Row::all` | generated |
| `bodyEffect`, `componentEffects`, `writeEffects`, `effectsCovered`, `rows` (`Func.cpp:189-266`, `Verify/Program.cpp:58-69`) | `derive`, `write`, V1, the generated projection | effects.md 3.6, 4.1 |
| effects.md's `Halt`, `Fresh`, `Idr_Takes`, `Idr_BuildsCell`, `Idr_FreshIfLinear`, `reads`, `writes`, `Idr_AnyEffect`, `Summary` | `Crash`, `Identity`, `Consumes`, `AcquiresCell`, `NewIdentity`, `read`, `write`, `RunsUnknown`'s row, `Row` | D14 split exit from crash; 5.1's rules |
| `world.new`, `Idr_Forge` | deleted; `io.unsafe_run` | D20 |
| `check.may_loop` (03's proposed spelling of `may_loop`) | kept, effect `MayDiverge` | D13 keeps the loop; its spelling is the op table's (03) |

## 6. In the Idris specification (D16)

The module `IdrisMLIR.Spec.Effects`, in the subset both hosts compile:
closed sets are enums with total functions over them, proofs at quantity
0 (one-source.md 4.1). A sketch, not compiled:

```idris
module IdrisMLIR.Spec.Effects
%default total

||| The states an op acts on: upstream's root and frame, and ours.
public export
data Resource = Root | Frame | Heap | Contents | Count | MemoState | Identity
              | IO | RuntimeState | Exit | Crash | Divergence

public export
data Reach = Addressable | Opaque

||| A child's reach under its parent's: never addressable under opaque.
public export
data Fits : (child, parent : Reach) -> Type where
  OpaqueUnderAny : Fits Opaque r
  BothAddressed  : Fits Addressable Addressable

rank  : Resource -> Nat     -- its place in the declaration order above
reach : Resource -> Reach

||| The root has no parent; any other resource's parent is declared before
||| it and admits its reach, so a cycle, a later parent and an addressable
||| resource under an opaque one do not type-check.
public export
data Parent : Resource -> Type where
  IsRoot : Parent Root
  Under  : (p : Resource) -> {auto 0 earlier : LT (rank p) (rank r)}
        -> {auto 0 fits : Fits (reach r) (reach p)} -> Parent r

parent : (r : Resource) -> Parent r
parent Root = IsRoot
parent Frame = Under Root
parent Heap = Under Root
parent Contents = Under Heap
parent Count = Under Heap
parent MemoState = Under Heap
parent Identity = Under Root
parent IO = Under Root
parent RuntimeState = Under IO
parent Exit = Under IO
parent Crash = Under IO
parent Divergence = Under Crash

public export
data Kind = Read | Write | Allocate | Free   -- upstream's four

||| The kinds a resource admits: 4.1's column.
data Admits : Resource -> Kind -> Type where
  HeapAllocate : Admits Heap Allocate
  HeapFree     : Admits Heap Free
  ContentsRead : Admits Contents Read
  -- ... one constructor per pair of 4.1

||| An effect of an op whose groups are `gs`: on the op, or on one group's
||| values. Allocate on the heap must name a result (L6); a value only on
||| an addressable resource.
public export
data Effect : (gs : List Group) -> Type where
  OnOp    : (k : Kind) -> (r : Resource) -> {auto 0 ok : Admits r k}
         -> {auto 0 notAcquire : Not (k = Allocate, r = Heap)} -> Effect gs
  OnGroup : (k : Kind) -> (r : Resource) -> {auto 0 ok : Admits r k}
         -> (g : Group) -> {auto 0 has : Elem g gs}
         -> {auto 0 addr : reach r = Addressable} -> Effect gs

||| What a runtime function does with memory that never leaves it.
public export
data Scratch = NoScratch | TakesScratch

public export
data Meaning = Runtime Symbol Scratch | HandFolder | NoFold

||| Exactly one form of declaration (effects.md 1.6, 1.10 a to c).
public export
data Effects : List Group -> Type where
  Static      : List (Effect gs) -> Effects gs          -- [] is Pure
  Typed       : List1 (Rule gs) -> Effects gs
  Recursive   : List (Effect gs) -> Effects gs          -- its own and its bodies'
  RunsUnknown : Effects gs
  Definition  : Effects gs

public export
data Atom = AIO | ARuntime | AExit | ACrash | ADiverge
          | ARead | AWrite | ACount | AMemo | AAlloc | AFree

public export
data Use = Orders (List1 (Kind, Resource)) | Reports

public export
data Stops = Returns | StopsReturn | StopsProgress   -- diverge: no mustprogress either

public export
record AtomFacts where
  constructor MkAtom
  resource : Resource
  kinds    : List1 Kind
  use      : Use
  stops    : Stops
  llvm     : List (Location, ModRef)                 -- section 7

atom : Atom -> AtomFacts
atom AAlloc = MkAtom Heap [Allocate] Reports Returns [(Other, ReadWrite)]
atom ACrash = MkAtom Crash [Write] (Orders [(Write, Crash)]) StopsReturn
                     [(Other, Read), (Inaccessible, ReadWrite)]
-- ... one line per atom, 4.3's table

project : Kind -> Resource -> Naming -> List Atom    -- 4.4's table, total
```

The laws, each a type or a decision the checker evaluates beside the
lemma that makes it a proof (one-source.md 4.1), so a source that breaks
one does not build:

| law | statement | held by | deletes |
| --- | --- | --- | --- |
| L1 | the tree is well founded: one root, every parent earlier | `Parent`'s erased `earlier`; `ancestors` recurses on `rank`, structurally | effects.md 1.10 (d); compile-time-cpp's `parentsPrecede` |
| L2 | no addressable resource under an opaque one | `Fits` | the abort under `EXPENSIVE_CHECKS` (`SideEffectInterfaces.h:160-173`) |
| L3 | a resource takes only its kinds; a value effect only on an addressable one | `Admits`, `addr` | upstream's run-time abort (`:338-343`) |
| L4 | round trip: an ordering atom's call effects project back to it alone | `0 roundTrip : (a : Atom) -> IsOrders (atom a).use -> projectAll (callEffects a) = [a]`, one `Refl` per atom | effects.md 2.4's `static_assert` |
| L5 | a row never loses an op's effect: every (kind, resource) any op declares projects to an atom, or is consumption or local; only `idr` ops touch `Count` and `MemoState`, so the root's value row (4.4) is exact | a decision over `allOps`, and `sound : Checked p -> Reaches p f op -> Sub (projectOp op) (row f)` over typed-effects.md 3.3.4's model | effects.md 1.10 (f); 4.1's argument in prose |
| L6 | an acquisition names its result; scratch is the function's | `OnOp`'s `notAcquire`; `Scratch` only on `Runtime` | the undeletable pure op; 2.4's exceptions |
| L7 | every op declares its effects, and a terminator with no successor stops on `crash` or `exit` and writes its resource | the `effects` field of `Op` has no "unknown"; `Leaves = Stops Atom` with an erased proof | effects.md 1.10 (b, e) |
| L8 | whatever writes `Exit` writes `IO` | a decision over `allOps` | the chain 4.2 avoids |
| L9 | whatever writes the handle table or errno writes `IO`; nothing writes `RuntimeState` | `Admits RuntimeState Read` alone | effects.md 1.10 (h) |
| L10 | an acquisition carries no crash (D23) | `Admits Heap` has no `Write`; `AcquiresCell`'s effects are one `Allocate` | a crash on every constructor (5.11 §5.11.2) |
| L11 | a row has no error case; it never refuses a program | `Row` is the atom set | — |

The trust point stays typed-effects.md's: the proofs are about the
specification's model; the generator and `derive` on real IR implement
it, and V1, V2 run on the real IR after every pass.

## 7. The lowering

### 7.1 Each atom, to LLVM

A function's row gives its attributes, written on `llvm.func`'s inherent
attributes by the step that makes it (effects.md 2.5; the LLVM dialect has
`memory_effects`, `will_return`, `no_unwind` and `passthrough`,
`LLVMOps.td`, read). A row names no value, so a heap atom covers both
`argmem` and `other`.

| atom | `memory(...)` it contributes | other attributes |
| --- | --- | --- |
| `io` | `inaccessiblemem`, `errnomem`, `other`: readwrite (the runtime's buffers become module globals once its bitcode is joined, `LinkRuntime.cpp:127-139` via 18 §2.4; libc calls are inaccessible) | — |
| `runtime` | `other`: read | — |
| `exit` | (with `io`, law L8) | no `willreturn` |
| `crash` | `other`: read (the flush reads the output buffer), `inaccessiblemem`: readwrite | no `willreturn` |
| `diverge` | — | no `willreturn`, no `mustprogress` |
| `read` / `write` | `argmem`, `other`: read / write | — |
| `count`, `memo` | `argmem`, `other`: readwrite | — |
| `alloc` | `other`: readwrite (snmalloc's thread-local free lists and globals, joined with the runtime) | — |
| `free` | `other`: readwrite | without it, `nofree` |

Always: `nounwind` (no unwinding exists: a crash is `_exit`,
`Ending.cpp:66-71`); `nosync` (one thread: threads are outside the
language, AGENTS.md; *conjecture* until proposal 0007's shards, and the
runtime's two atomics are signal fences and a relaxed choice, 18 §2.5).
`willreturn` unless `exit`, `crash` or `diverge`; `mustprogress` (through
`passthrough`) unless `diverge` (D13: LLVM deletes an effect-free endless
loop only where Idris proved there is none). The locations are
*conjecture* until the runtime audit (effects.md 4.4) reads LLVM's own
inference on the joined bitcode.

`alloc` reports in MLIR and writes in LLVM, and both are right: before
idr-rc values are uncounted and immutable, so two calls that build equal
values may merge or vanish (D23); in LLVM, after counting, two cells are
two objects whose counts are written, and the allocator's free lists are
memory the call writes. That is why `alloc` must keep a call from being
`readonly`.

### 7.2 A runtime call

Each runtime op's attributes are a compile-time constant of its class
(effects.md 2.5): an effect naming an operand goes to `argmem`, an
op-level one to its atom's locations, `Scratch` to `other`: readwrite,
plus `willreturn` unless it stops and `nounwind`. The allocation entry
points (`idris_rt_cell`, `idris_rt_array_new`, `idris_rt_str_alloc`) may
add `allockind("alloc,uninitialized")`, `allocsize(0)`,
`"alloc-family"="idris_rt"` and a `noalias` result, `idris_rt_free_cell`
`allockind("free")`, through `passthrough` (integer attributes by name,
`ModuleTranslation.cpp:1133-1146`, read). Their worth is *conjecture*:
`idris_rt_cell` is always inlined once the bitcode is joined
(`Cells.cpp:1-10`), which drops a callee's attributes; measured first.

### 7.3 What LLVM may then do

```llvm
; idr.func effects<read> @sum(...) attributes {total}
define i64 @sum(ptr %a) #0
attributes #0 = { memory(argmem: read, other: read) willreturn nounwind nosync nofree mustprogress }
```

With these, LLVM deletes an unused call of `@sum`, merges two with no
write between, hoists one out of a loop that writes nothing it reads,
and keeps a pointer dereferenceable across it (`nofree`); none of this
happens today, since no attribute is written (12 CV-05, CV-14). A
function with `alloc` stays out of all four, as it must. MLIR's own
canonicalize and CSE after the lowering read none of it until `llvm.call`
implements `MemoryEffectOpInterface` (effects.md 7.2 U1); the
attributes reach LLVM without it.

## 8. For the owner

### 8.1 The one question, to be put with DP-12

**Does any promise to users mention allocation?** The rulings make the
row internal: no program is accepted or refused by it (L11), and D23
promises nothing about where memory runs out. One promise could use it:
`mlir-array`'s in-place update, whose refusal DP-12 asks how to define.
- *(a) No promise mentions allocation* (recommended). The in-place
  promise stays defined by DP-12 on its own terms; `alloc` serves
  idr-expect, limits and LLVM only. Costs nothing.
- *(b) The in-place promise is "the update acquires no memory"*, read off
  the row of the promised region after counting. It buys a declarative
  rule stated in the vocabulary. It costs acceptance's independence from
  the optimizer: whether an update acquires depends on reuse, an
  optimization, unless reuse becomes mandatory for promised updates,
  which turns an optimization into part of the language (AGENTS.md:
  acceptance is a property of the program).

Put it when DP-12 is put, not before: alone it has no consequence.

Settled without a question (2026-10-21): D24 defines the in-place promise
by a rule read off the program before counting, which excludes (b); D26's
space promise is about memory held, at allocations, and names no op that
acquires. So (a): no promise to users mentions allocation.

### 8.2 Decided here, for the owner's review

- **eff-Q4 (b): runtime state is a read-only child of `IO`**, not IO
  itself. Reason: it orders `handle.string` and `io.errno` after the IO
  that changes them, as (a) would, and lets them move across heap
  effects and merge with each other; no program's meaning differs
  (D12: base's `getString` stays pure to Idris; we only order it more
  correctly). Proposal §4 lists eff-Q4 among the owner's; it decides no
  meaning or promise, so it is decided here and offered back.
- **DP-31 (B): a closure acquires its cell.** Forced by an exact `alloc`
  (F4); it costs CSE of two identical closure constructions in one block
  (*conjecture*: rare; idr-deduplicate shares functions, not values).
- **`Heap`, not `Arena`** (5.2): one name, the dialect's, for where a heap
  cell's memory comes from.

Settled by rulings, so not asked: D13, D14, D20 to D23. Memory limits
(DP-19) and crash statuses (DP-18) come later and need nothing more of
this vocabulary.

## 8.3 Stress test: a sharded io_uring server, and Rust (2026-10-21)

The owner: "everything should be sequential, and if we ever want to bring
asynchrony back, we use futures ... imagine iouring webserver, sharded
... and think about the down the line rust ffi proposal too". Read
against proposal 0007 (shards), 0020 (Rust), `sources/docs/seastar/`
and `sources/papers/kivity-2019-seastar/`. No change to the tree's
shape; five rules, and stale text in 0007 and 0020.

- **Per shard, the whole tree** (*read*: 0007 D1, D2, §6). A shard is a
  copy of the single-threaded runtime: its heap, output buffer, handle
  table and top-level constants (`Static i`, so static data is immutable
  without exception). No mutable memory is shared between shards, so
  each runs this tree alone; across shards, order is causal through
  messages, an IO op at each end. Fork/join of pure work equals the
  sequential run.
- **R1. Memory the kernel touches is held by ownership, not by a
  resource** (*decision*, offered back). A completion-based read
  (io_uring recv) consumes an exclusive buffer into the operation in
  flight and its completion returns it; a zero-copy send holds an owned
  reference to immutable bytes until its notification (static data needs
  no count at all). No op can reach a buffer the kernel holds, so the
  kernel's writes need no effect, as a guard's refined result holds D21's
  hazard by data dependence. A task cancelled with an operation in flight
  does not own its buffer any more: the reactor drops it at the
  operation's completion (*recalled*: io_uring may write a buffer after a
  cancel is submitted, until the cancelled request completes).
- **R2. `Heap` names where any cell's memory comes from**: snmalloc's
  arena, a ring of kernel-provided buffers, a foreign object's
  allocation. A buffer returned to the kernel's ring at its release is a
  `Free`, ordered after every access by the same rule. This decides 8.2's
  third item: `Heap`, not `Arena`.
- **R3. An effect that changes a calling convention lives in the
  function's type.** D20 put rows on ops because none of today's
  effects changes a convention. 0007's `wait` would be the first (a
  waiting function is lowered as a coroutine); when 0007 lands, a
  waiting function's type says so. Its ordering needs no resource: a wait
  and the helping join run other tasks' code on the shard, so they
  declare `RunsUnknown`, as `apply` does.
- **R4. A foreign call's effects come from its operands' types and
  grades.** Under D20 and D21, IO no longer orders heap memory, so "every
  shim call takes and gives the world, so it is ordered with every other
  effect" (0020 §9, §11.2) no longer holds: a Rust call writes `IO` and
  also reads the contents of a buffer it borrows (`&`), writes one it
  borrows mutably (`&mut`), consumes what it takes by value, acquires
  memory when it allocates, and carries the summary of the Idris
  callbacks it may run (their labels are known after
  defunctionalization). Each is a rule of the specification, never a
  hand declaration.
- **R5. Releasing a foreign object may do IO.** A Rust destructor may
  flush a `BufWriter` or close a socket, so a drop of a value whose type
  may reach a foreign cell writes `IO`, read off the type (every type is
  monomorphic), and keeps its place among the program's output.
- **D26 under ten thousand suspended tasks**: a suspended task's frame is
  an active frame, so frame-limited holds; a reuse token carried across a
  wait would be held for an IO's duration, so C1's walk drops it before
  the wait (0007 P1's to build).
- **Stale in 0007, for when it is taken**: "one world per shard" and the
  world in `Here`, task frames and completions (D20 removed the world);
  `idr.wait` as a terminator with two successors (D19: a region op, its
  cancel region consuming the live owned values and ending the task);
  `wait` as a case of `Idr_Effect` (R3). **Stale in 0020**: §9's and
  §11.2's ordering by the world (R4); destructors' effects (R5).
- **What Seastar keeps as convention and we make types** (*read*:
  tutorial "Lifetime management", `foreign_ptr`; 0007 §7.2): objects
  kept alive for an asynchronous operation (`do_with`, "a serious
  use-after-free bug" when broken), data touched only on its home core,
  futures single-threaded. Here: grades and moves (R1), a home shard in
  the type (`Shard n s`, `Local n s a`), the send check.
- **Not the tree's**: fairness. Seastar yields at preemption points with
  a 500 µs task quota; a yield the compiler inserted in a loop would be a
  wait, `RunsUnknown`, and cost the loop its optimizations. It is 0007's
  to decide.

## 9. Sources read

**In full:** the representation-first skill; AGENTS.md (working tree);
`proposals/0000-mlir-native.md` §2 (D1 to D23); `design/effects.md`,
`design/typed-effects.md`; `wave1/5.11-oom.md`; `IdrInterfaces.td`;
`runtime/Alloc/Alloc.h`, `Cells.cpp`. **In part:** `design/one-source.md`
§4, §5; `design/compile-time-cpp.md` §2.3 (d); 02 §2, §3.6, §3.7, §4; 18
§2, §5.1 to §5.4; 5.2 A1 to A9; 5.8 EF1 to EF5; synthesis A §2.2, §5.1 to
§5.5; 03 §5.3; 08 T7, C-41, C-76; 12 CV-05, CV-14, T2 (lane 5.10 only
through 02's and 08's R1.5). **Our code** at the lines cited, among them
`IdrOwnershipOps.td`, `IdrCheckOps.td`, `IdrPlatformOps.td`,
`IdrIOOps.td`, `IdrClosureOps.td`, `IdrOps.td`, `IdrAttrs.td`,
`Expect/Allocation.cpp`, `Transforms/Pipeline.cpp`,
`Conversion/MemoCells.cpp`, `runtime/Rc/`, `runtime/Io/`,
`runtime/Strings/`. **Upstream:** MLIR's `SideEffectInterfaces.{h,cpp}`,
`CSE.cpp`, `LocalAliasAnalysis.cpp`, `LoopInvariantCodeMotionUtils.cpp`,
`ControlFlowSink.cpp`, `TransformInterfaces.h`, `OpenACC.h`,
`LLVMOps.td`, `ModuleTranslation.cpp`, `TestSideEffects.cpp`; LLVM's
`Attributes.td` and `ModRef.h:60-76`; snmalloc's `mem/corealloc.h`,
`backend/backend.h`, `backend_helpers/{commitrange,statsrange,palrange}.h`,
`backend/standard_range.h`.
