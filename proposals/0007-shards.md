<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0007: shards

**Status (2026-10-19, read at 77eaa5b1):** open, nothing built: the
tree has no `idr.wait`, `idr.fork`, reactor or `libs/mlir-shard`
(`git grep`). Every decision is taken and none is open. All of it is
**AFTER-SELF**: the frontend `make self` compiles is single-threaded and
reaches no shard. **First step: P1** (task frames and the `wait`
effect), taken when the queue reaches this proposal, after `make self`
is green and 0005 and 0006 are done; it needs nothing else. P2's epoll
half waits on a Linux target running (none has built anything yet,
0002); P3 is parked with 0020; P4 follows P1 and P2; each item of P5
waits on its measurement. "The cutover's §N" and "the representation
wave's DN" refer to those waves' last texts, at 484d6403. `M/` and `L/`
are the pinned `.toolchain/llvm-project/mlir` and `llvm`; `SDK/` is the
macOS SDK `xcrun --show-sdk-path` names. Claims are marked read,
recalled, conjecture or decision.

The runtime runs a program on one runner thread with a reserved stack,
and "one runner runs at a time in a process" (read: `runtime/idris_rt.h`,
`idris_rt_run_on_stack`). This proposal makes it one copy of that
runtime per core, each with its own heap, world and plain counts, and
adds what a copy lacks: a way to pause mid-computation and be resumed by
an event. It is the concurrency runtime as one design: the task frame,
the reactor, shards, what crosses between them, and the Rust future
polled on the reactor.

## What it changes

Each move names the data that changes and the branches it deletes.

- **A computation paused at a wait is a task frame** (§2): LLVM's
  switched-resume coroutine frame behind our cell header, linear, owned
  by a shard's task table, and one more effect, `wait`. Deleted: any
  waiting thunk, any second scheduler. A program that never waits
  lowers as today.
- **Each shard runs a reactor** (§3): a task table, a run queue, an
  MPSC wake queue, one platform waiter. Deleted: the one process-wide
  runner.
- **A shard is one more copy of the single-threaded runtime** (§4, D1):
  heap, world, top-level constant cells, handle table and output buffer
  per shard. Deleted: every question of which thread may touch a count.
- **Values cross only inside messages** (§5, §7): `idr.fork`, an
  `IsolatedFromAbove` region whose operands are the message, and
  `!idr.join<T>` at `(1, own)`. Deleted: any pointer from one shard's
  heap into another's.
- **A top-level constant is a `Static i` cell** (§6, D6): one more
  constructor role of the memo sum. Deleted: the memo cell written at
  run time, so static data is immutable without exception.
- **Rust futures are polled from our task frames** (§10): `Rust (FutT
  a)` a counted foreign cell, a one-word waker. Deleted: any Rust
  runtime.
- **Effectful operations are runtime primitives; pure fork/join is plain
  Idris** (§7.1, D13, D14). Deleted: a second, sequential meaning of a
  primitive, and any path by which code the stock host runs reaches a
  `%extern`.

## Rules it keeps

- **Every target, one design.** The waiter is one operation behind the
  platform layer, kqueue on macOS and epoll on Linux (§3);
  no inline assembly, so frames are stackless coroutines from LLVM's
  intrinsics (§2).
- **What Idris proved stays in types.** The join is `!idr.join<T>` at
  `(1, own)`, the shard index is quantity 0, a lent value is a grade
  (§5.3), and a frame holds the quantity-1 world. Nothing lives in a
  discardable attribute.
- **A linear binder does not imply unique heap ownership.** The detach
  walk reads the count and idr-rc's last use, never the quantity (§5.1).
- **No threads, no `%foreign`.** Base's `fork`, `threadWait` and
  `System.Concurrency` stay `unsupported (threads)` (read:
  `compiler/src/IdrisMLIR/Registry/Recognized.idr`, `threads`).
  Parallelism is `libs/mlir-shard`'s structured fork (§7.1).
- **No oracle.** One set of expected files serves every core count (D8).
- **Single-thread performance wins the tie** (the owner's, 2026-10-09).
  A cost paid only when a program uses more than one shard is
  acceptable; a cost on a path a single-shard program runs is not,
  unless it is free there too.
- **Reject what cannot compile.** A value that may not cross is
  `unsupported (send)`, naming the type and the path (§7.3). That one
  refusal reads only the sums the whole-program label solve decides
  before the optimizer runs, so acceptance stays a property of the
  program.
- **No option selects behaviour** (the cutover's D2). `IDRIS_RT_SHARDS`
  is the program's resource; whether a program
  waits or forks is in its code and its types.

## The design

### 1. Three suspended objects

| | Closure | Thunk | Task frame |
|---|---|---|---|
| Paused | before start | before start | mid-body, at a wait |
| State | captures | captures, then the value | values live at the wait (LLVM's spills) |
| Representation | immutable sum; apply is a match | memo sum; force is a call of its dispatch | LLVM coroutine frame: suspend index = tag, spills = fields |
| Who runs it | the applier | the forcer | its shard's reactor, on a wake |
| Grade | any | ω: memo; `excl`: one-shot | linear (it holds the world) |
| Colours its caller | no | no | yes (`wait`) |
| Crosses shards | copied | copied | never |

Defunctionalization makes closures and thunks sums for every closed,
monomorphic program, by analysis alone (read:
`foreign/idr/lib/Transforms/Defunctionalize/`; a force calls its memo
sum's dispatch, `Forces.cpp`), so every value a message can hold has a
sum type, which the send check reads (§7.3). The line falls where the
data is known: a thunk's paused state is its captures, known in MLIR; a
task's is the values live across a wait, known only after optimization,
so LLVM's CoroSplit computes it. A coroutine frame is a defunctionalized
continuation, and the reactor is the handler of Brady's `handle` (read:
`sources/papers/brady-2014-resource-effects` §3.1). A thunk is not a
task, since every force would become a possible suspension and colour
pure code; frames do not cross, which keeps `++count` plain (§4.1).

### 2. The task frame

**decision** A task frame is a computation paused at a wait (a socket
or timer event, a Rust future that returned `Pending`, or a join in a
function that waits for one of those). It is LLVM's switched-resume
coroutine, emitted by idr-lower as `llvm.intr.coro.*`; every intrinsic
it needs, `coro.await.suspend.handle` included, is an op of the pinned
LLVM dialect (read:
`M/include/mlir/Dialect/LLVMIR/LLVMIntrinsicOps.td:938-1072`). Our O3
pipeline (`foreign/idr/lib/Target/Optimize.cpp:63`) already runs every
coroutine pass (read: `L/lib/Passes/PassBuilderPipelines.cpp:1023, 685,
915, 1194`), as will each codegen unit's own O3 after the split before
O3.

In MLIR the wait is `idr.wait`, a terminator with two successors:
**resume**, with the answer and the next world, and **cancel**, which
consumes the live owned values, so idr-rc places their drops there as
any drop, and the frame's destroy function is the cancel path CoroSplit
outlines. The frontend gives the frame its memory (`coro.alloc`,
`coro.begin`), so our header (kind task) goes in front of LLVM's layout
`[resume][destroy][promise][index, spills]`; the promise holds the
task's slot, its awaiter and its result. A frame is linear: its count is
1 and never tested; the task table owns it while suspended and the
running reactor while resumed; its final cleanup frees it, or
`coro.destroy` on cancel, and counting never does. As LLVM requires
(read: `L/docs/Coroutines.md`), only the owning reactor resumes a task
its table holds as suspended, and a wait is registered before the
suspend (`llvm.coro.save`), on one thread (§3.3). No frame ABI crosses
LLVM releases: one pinned LLVM compiles a program and the runtime's
bitcode.

**decision Colouring.** Stackful frames need a stack switch (inline
assembly, or `makecontext`, which POSIX removed in 2008), so the compiler
colours, as little as it can. `wait` is one more case of `Idr_Effect` beside
`io`, `crash` and `diverge` (`foreign/idr/include/idr/IR/IdrAttrs.td`),
solved by the one bottom-up summary
(`foreign/idr/include/idr/Analysis/Effects.h`), never a
second analysis. `idr::bodyEffect` sets it for an op with a `Waits`
trait in ODS (`idr.wait` and the primitives that wait: sockets, timers,
sleep, Rust `await`), as `MayCrashOpInterface` gives `crash`. It only
shrinks under inlining and cleanup; idr-lower reads the final bit, and
only `wait` functions become coroutines. A join adds no bit: in a
`wait` function it lowers to `idr.wait`, elsewhere it is the helping
join.

**The helping join.** A join in a function that waits for nothing else
runs the work arriving on its own shard, on its own stack, until its
reply arrives. Structured fork/join cannot deadlock under it, since a
forked computation's only channel back is the reply, and the stack grows
by the nesting depth, as recursion would. **conjecture**: every parallel
program in `bench/` has this form and runs with no coroutine.

**decision Tail await.** A tail call between two `wait` functions hands
the callee the caller's awaiter, destroys the caller's frame and resumes
the callee by a `musttail` call: C++'s symmetric transfer, keeping the
constant-stack promise. idr-lower writes `coro.await.suspend.handle`;
CoroSplit makes it an indirect call through the frame, `musttail` where
the target allows (read: `L/lib/Transforms/Coroutines/CoroSplit.cpp:125,
1079-1085`). The partition keeps only direct `musttail` calls in one
object (`foreign/idr/lib/Target/Partition.cpp:250`), and an indirect one
reaches any object, so P1's proof runs a tail await within one bin and
across two.

### 3. The reactor

#### 3.1 A shard's runtime

Each shard is a runtime thread holding a reserved stack with a guard and
its own `sigaltstack` (`idris_rt_run_on_stack`, lifted by P4 from one
runner per process to one per shard), a snmalloc allocator (already per
thread), its constant table (§6), a task table of (slot, generation), a
run queue, an MPSC wake queue in snmalloc's shape, and one platform
waiter. A program that never waits and never forks starts no reactor
and runs as today.

#### 3.2 The platform wait

The waiter is one more function of `Platform/Posix`, chosen by the
target's macros (read: `runtime/Platform/Platform.h`):

| Target | Waits on | A post wakes it with |
|---|---|---|
| macOS | `kqueue`/`kevent` (read: `sources/papers/lemon-2001-kqueue`) | `EVFILT_USER` with `NOTE_TRIGGER` (read: `SDK/usr/include/sys/event.h:77, 199-205`) |
| Linux (each of its three entries) | epoll | an eventfd |

A post pushes its token, then kicks the waiter only if the reactor has
set its about-to-sleep flag. A turn of the reactor drains the wake queue
into the run queue, resumes ready tasks until the run queue is empty,
flushes the shard's output (D3), then waits. A resumed task does not
block (read: `sources/papers/belay-2014-ix` §4.1), except on the
standard streams (D3).

#### 3.3 What a foreign thread may touch

**decision** A foreign thread (a Rust thread, a blocking offload thread)
may push a token onto a shard's wake queue and kick it, use memory that
is not an Idris cell, and free raw blocks remotely through snmalloc. It
may not resume a frame, force a thunk, touch a count, hold a reference
to an Idris cell, or hold a world.

### 4. The shard

Plain `++count`, and reuse at count 1, need one thread at a time
touching a count. Three ownership domains keep that:

| Domain | Model | Cost |
|---|---|---|
| the whole heap | M:N work stealing (Go, Tokio, Lean) | every count atomic, tagged or traced (read: `sources/docs/go-scheduler/gc-guide.html`, `sources/docs/tokio/scheduler-2019-10.html`, `sources/papers/ullrich-2019-counting-immutable-beans/threadsafety.tex`) |
| one task | a heap per process (Erlang) | every message a copy, even on one core (read: `sources/papers/johansson-2002-heap-architectures` §3) |
| one core | thread-per-core (Seastar) | plain counts within a core; crossing copies or moves (read: `sources/docs/seastar/tutorial.md`) |

**decision** A heap per core. Idris shares immutable data implicitly, so
a heap per task would copy every value two tasks see, while a heap per
core makes the common case free. snmalloc is built for frees from
another thread, batched through one MPSC queue per allocator (read:
`sources/papers/lietar-2019-snmalloc` §2.2), so a message detached on
one shard and freed on another takes that remote path. The weakness is
balance (D9). Amdahl's serial term grows from contended counts on shared
data (copy or lend, §5.3), distribution from one coordinator (fan out as
a tree, or lend) and imbalance (§5.2, D9); a hop is the one place a core
is named, so the term is visible in the source.

### 5. What crosses, and who owns it

#### 5.1 The detach walk

**decision** A message is detached on the sending shard before it is
enqueued, in one walk of the counted graph it reaches:

| Cell | Treatment | Why it is sound |
|---|---|---|
| count 0 (persistent), `Static i` included | the same pointer | persistent data is immutable and reaches only persistent data |
| count 1, reached only through moved cells, at a send that consumes the last reference (idr-rc decides) | moved | nobody else reaches it; the receiver's free is snmalloc's remote free |
| count above 1, or a stack cell (`idr.con` with `stack`) | copied into a fresh count-1 cell; a forwarding map over cells of count above 1 keeps the DAG's sharing | the sender keeps its aliases and drops them at home (read: `sources/papers/clebsch-2017-orca`) |
| a thunk, `Forced` | copied with its value | a value |
| a thunk at a label | copied unforced, its captures walked | forcing it to send it could diverge where the program would not |
| a thunk, `Running` | impossible | a thunk runs only inside its force, on its own shard |
| a runtime handle, a `Local` | the integer it is | an operation hops home (D4); a `Local`'s home is in its type (§7.1) |
| a task frame, a world, `Here`, a mutable cell, a `Join`, a pipe's stream | never: the send check refuses it (§7.3) | a frame has no source type; a join stays with its forker, which makes the fork structured; a pipe has one consumer (D7) |

A value at the exclusive grade crosses as a move, its region with it,
as Swift's `sending` does (read:
`sources/docs/swift-evolution/proposals/`, SE-0430); 0012's packed
layout reads the same fact. A copy's cells are allocated by the sender
and owned by the receiver, and their frees go home as remote frees. The
live-cell counter is per thread (`runtime/Alloc/Cells.cpp:157`), so zero
live cells is checked on the sum over shards.

#### 5.2 Placement

Placement is a runtime value, a `Fin n` a library computes, so a library
can choose the least-loaded shard. A message nobody has started owns a
detached graph, so an idle shard may take it without breaking one owner
at a time; a started frame cannot migrate, its cells being on its
shard's heap.

#### 5.3 Lending

For a large immutable input a lend replaces the copy. A structured fork
keeps the value alive until the join; the borrower receives it at a new
permission, `lent`, beside `borrow`, `own` and `excl`; idr-rc lowers a
`dup` at `lent` to a deep copy into the local heap and a `drop` to
nothing; forcing a label reached through a lent value copies it first.
"Lives on another shard's heap" is then a grade, which no pass can lose
(read: `sources/papers/marshall-2024-fractional-uniqueness`), with no
count operations at all. D10 decides when it is built.

### 6. Top-level constants per shard

A top-level constant is evaluated at most once per shard that demands it
(D6). Today a memo cell is the one writable global in static data, one
per process, which the release lists, and its force makes what it holds
persistent (read at 77eaa5b1: `foreign/idr/lib/Conversion/StaticData.cpp`,
`staticCell`; `MemoCells.cpp`). That persistence is the cost D6 rejects
for a process-wide cell; P4 starts by reading it against D6 as the
ownership lane leaves static data's lifetime.

**decision** The indirection is a state of the memo sum, not a test
beside it:

```
memo K = label_1 caps | ... | label_n caps | Running | Forced v
       | Static i            -- only in keys that have a top-level constant
```

Static data holds `Static i`, an immutable persistent cell naming slot
`i` of the running shard's constant table, and every reference to the
constant is that cell; `Static` is one more `CtorRole`
(`foreign/idr/include/idr/IR/IdrBase.td`). Each shard's table is one
`thread_local` global whose initial image is the templates (labels with
persistent captures), so the loader gives each shard its copy; it is
defined in one codegen unit and referenced from the others by its
content-derived `__idr.` name. The memo sum's dispatch gains one arm,
`Static i -> force slot i of the running shard's table`, only in keys a
top-level constant reaches, which the label solve finds because the
constant's suspension declares its edge through the flow interface
(`foreign/idr/include/idr/IR/IdrFlow.td`). A shard's end releases its
forced slots through the compiler-made release function. No pointer to
a slot escapes a force, so a slot is never sent. On one shard the cost
is the arm and a thread-local address (D6).

### 7. The surface and the hop

#### 7.1 `libs/mlir-shard`

**decision** A new in-house package with two layers. The effectful
layer, `Shard`, serves programs only: its operations `runShards`,
`fork`, `join`, the `Local` cells and `pipe` are bodiless `%extern`s
(D13), as `mlir-linear`'s iterator's
(`libs/mlir-linear/Linear/String/Iterator.idr`) and `mlir-array`'s
generating set (`libs/mlir-array/Array/Core.idr`, the representation
wave's D5) are, and the rest (`io`, `pure`, bind, `submit`, `forAll`,
`Sharded`) is plain Idris over them. Their sequential reading is their
specification, never code: a fork runs at once, a join returns the
stored result, a `Local` is an `IORef` in a table. `lend` and `forkL`
join them when D10 builds lending. The pure layer, `Shard.Pure`, is
plain Idris with bodies (D14), and is all that code the stock host runs
(the frontend, the fork, the runner) uses of this package.

**decision** A `Local` is a word at run time, a slot of its home
shard's table of local cells, so it crosses as the integer it is
(Pony's `tag`) and its cells never leave their heap. Its home is the
erased index `s`, so the types alone keep a use at home (`getLocal`
needs `Shard n s`).

```idris
module Shard

||| Being on shard s of n: linear, so no closure carries it elsewhere,
||| and empty at runtime, as %World is.
export data Here : (n : Nat) -> (0 s : Fin n) -> Type
||| IO on shard s; bind threads Here as io_bind threads %World.
export data Shard : (n : Nat) -> (0 s : Fin n) -> Type -> Type
export io   : IO a -> Shard n s a
export pure : a -> Shard n s a
||| Starts S k shards (IDRIS_RT_SHARDS, else the processor count, at
||| most 256, §10.2) and runs the body on shard 0.
export runShards : ((k : Nat) -> Shard (S k) FZ a) -> IO a
||| The join is linear, so every fork is joined.
export fork : {n : Nat} -> {0 s : Fin n} -> (s' : Fin n) -> Shard n s' b -> Shard n s (Join n s b)
export join : (1 _ : Join n s b) -> Shard n s b
export submit : {n : Nat} -> {0 s : Fin n} -> (s' : Fin n) -> Shard n s' b -> Shard n s b
export data Local : (n : Nat) -> (0 s : Fin n) -> Type -> Type
export newLocal : a -> Shard n s (Local n s a)
export getLocal : Local n s a -> Shard n s a
export setLocal : Local n s a -> a -> Shard n s ()
||| Evaluate a stream on s' for one consumer here (D7).
export pipe : (s' : Fin n) -> (ahead : Nat) -> Stream a -> Shard n s (Stream a)

module Shard.Pure

||| Both values, computed in parallel where the runtime can. The body is
||| the one meaning: y first, then x.
export
both : Lazy a -> Lazy b -> (a, b)
both x y = let v = force y in (force x, v)
```

The rest of `Shard.Pure` (a parallel map, a divide-and-conquer fold) is
plain Idris over `both`.

#### 7.2 What the types make impossible

Seastar's rules are conventions whose breach is undefined behaviour
(read: the Seastar tutorial, `foreign_ptr`); here each is a type error,
and every proof erases. A key's home shard is in the type:
`lookup : Sharded n place v -> (key : k) -> Shard n (place key) (Maybe v)`
does not type-check on a rigid `s`, so `get m key = submit (place key)
(lookup m key)` is forced (McBride's "at key", read:
`sources/papers/mcbride-2011-kleisli` §5). Lending cannot dangle:
`lend : a -> ({0 l : Region} -> Lent l a -> Shard n s b) -> Shard n s b`
with `forkL : (s' : Fin n) -> Shard n s' r -> Shard n s (Join' l n s r)`
is runST's region on a linear join, so every borrower is joined before
`lend` returns. A fork with no world inside equals its sequential
reading. Shard ids are `Fin n` for the runtime `n`. Protocols between
shards are session types (read:
`sources/papers/brady-2021-idris2-qtt/sessions.tex`), which need the
coroutine path, since a helping join cannot serve a channel. Erased: the
shard index of `Here`, `Shard`, `Join` and `Local`, and every range
proof; `Here` is linear with no runtime component, as the world. At run
time: the `Fin` that selects a queue (an `i64`), `k`, and the message's
bytes.

#### 7.3 The hop in MLIR and the send check

**decision** A fork is `idr.fork`, a region op that is
`IsolatedFromAbove`, whose operands are the message: the destination
shard as an `index`, and the captured values. No use-def chain crosses
an isolation barrier (read:
`sources/papers/lattner-2020-mlir/ir_design.tex`), so crossing is an
operand, and an operand is a message. The grid is upstream's
`shard.grid @cores(shape = ?)` and the running shard
`shard.process_linear_index` (read:
`M/include/mlir/Dialect/Shard/IR/ShardOps.td:31, 140`). The result is
`!idr.join<T>` at `(1, own)`. idr-lower outlines the region, detaches
the operands, posts a function pointer with them, and lowers `idr.join`
to `idr.wait` or the helping join (§2). A fork to the running shard is
a call (read: `sources/docs/seastar/smp.hh`, `submit_to`).

**decision** `idr.fork` and `idr.join` implement the flow interface
(`IdrFlow.td`): a closure or lazy operand reaches the region argument it
binds, and the yield reaches the join's result, so the label solve
follows a closure into forked work with no case of its own. The frontend
writes the region already isolated, so nothing outlines it and inlines
it back before idr-lower. Calls inside it are edges of the enclosing
function in upstream's `CallGraph` (read:
`M/lib/Analysis/CallGraph.cpp:74-97`), so the ready set orders the
forked work's callees first; a fork made a call would be an edge the
inliner had to be told not to inline.

**decision The send check** runs once, right after defunctionalization's
conversion, as a whole-program read of the decided sums, where every
type is first-order. It is one more method of the value-facts type
interface (`foreign/idr/include/idr/IR/IdrInterfaces.td`,
`ValueFactsTypeInterface`, beside `holdsWorld`, `holdsClosure`,
`holdsReferences` and `isCounted`), "may hold what may not cross",
answered once per type: a mutable cell (`IOArray`, `IORef`, `Buffer`), a
world, `Here`, a `Join` and a pipe's ring answer yes, and every other
type answers from its fields. So a memo sum that can hold `pipe_next`
answers yes through the ring its label captures, and the pipe needs no
case of its own. The refusal is `unsupported (send)`, naming the type
and the path, as structured data on the diagnostic. After it,
`idr.fork`'s verifier keeps what it established: an operand that may
hold what may not cross is a broken invariant, and a pass that makes one
is an internal error. The check is not itself a verifier rule, since a
verifier failure after a pass is an internal error, never a user's
refusal.

**decision** Acceptance is judged on the 0CFA sets the label solve
freezes before the optimizer runs, so a label that reaches a fork's
type but never its value is still walked. A change of precision (such
as polyvariance) changes which programs are accepted: a language change,
in a proposal of its own. A runtime handle is an integer and passes; an
`LArray` (0009 §3.8) is exclusive by type and moves.

### 8. Parallel loops

Which loops are parallel, and how they are tiled, is 0009's (§14 there):
at its stage 8 the tile-and-fuse schedule tiles a parallel dimension to
`scf.forall`. **decision** This proposal lowers an `scf.forall` to a
fork per shard and a join, the one lowering of `scf.forall`. The arrays
reach every shard by pointer for the join's duration: the body touches
no count, its elements are words, and each tile writes its own slice.
**decision** "Counts nothing" (an idr-expect property today,
`foreign/idr/lib/Transforms/Expect/CountsNothing.cpp`) becomes an
assertion the lowering makes, never a choice between lowerings: 0009's
structuring makes an `scf.forall` only from a body that counts nothing
(0009 §5, §14), so one whose body counts is an internal error. Neither
`async-parallel-for` nor `convert-scf-to-openmp`: each is a second
runtime.

### 9. Streams across shards

A stream lives on one shard (D7). The pipe is the one stream that spans
two. Its ring holds `ahead` slots outside the Idris heap (§3.3), with a
head and a tail index (the only atomics: release on advance, acquire on
read), a closed flag and a wake token per side. A fork on `s'` owns the
stream: it forces the next element, detaches it (fresh, count 1, so it
moves) and pushes it, and a full ring parks its task. The consumer's
stream is the ordinary memo sum with one more label, `pipe_next ring`,
whose force pops a slot and memoizes `x :: pipe_next ring`. An empty
ring blocks the consumer's shard, since pure code cannot wait; it does
not help, since another task could reach the same thunk while it is
`Running`. Releasing the last `pipe_next` closes the ring: the producer
sees the flag at its next push and ends, and the release frees what is
left as remote frees. Only pipes have the label's arm.

### 10. Async Rust on the reactor

#### 10.1 The executor is the reactor

**decision** The executor is the shard's reactor, and a future is a task
frame. A waiting computation is `IO` or `Shard n s`, which the compiler
colours; a future has no source type. The future-like values a user
holds are `Join n s b` and a Rust `FutT`. `IO a` already does nothing
until it is run (read: `third_party/Idris2/libs/prelude/PrimIO.idr`),
so P2300's `when_all` is fork/join and `set_stopped` is destroying a
task.

#### 10.2 Pending, the waker, completion

**Pending** is a task paused at a command nobody has answered; it is
never a value. **The waker is one word:** shard (8 bits), slot (24) and
generation (32), stored as the `RawWaker`'s data pointer. Clone copies,
drop does nothing, and wake pushes the word onto the shard's wake queue
and kicks: no allocation, no count. A wake for a finished task fails the
generation check. **Completion** is the resume, with the answer and the
shard's world. **Errors** are `Either`; **cancellation** destroys the
task, whose cancel path drops what it owns, a `FutT` included.

#### 10.3 `FutT`

`Rust (FutT a)` is a counted foreign cell (0020 §11.1) holding a pinned
future. `await` is a loop in a `wait` function: poll through the shim
with this task's waker; on `Ready a` return `a`; on `Pending`, `idr.wait`
for a wake of this slot and poll again. Rust futures need not be `Send`,
since they never leave their shard; a one-word `Waker` is `Send + Sync`.
An async Rust import needs P1, P2, runtime-owned sockets and timers
behind Rust's async I/O traits (0020 §15), the waker, and cancellation as
destroy.

#### 10.4 Blocking calls offloaded

Synchronous bindings run on the calling shard, in world order (0020 §9).
With a reactor, a synchronous call that blocks would stall the shard, and
P3 decides how such a call leaves it; no manifest field marks one (0020
§5 has none). An offloaded call runs on a runtime-owned thread that runs
only Rust: its arguments move into Rust's ownership, its completion is
posted to the shard, and user code does not change, its type having been
`IO` all along. A call that takes an Idris callback stays inline, or the
callback would run Idris code on a foreign thread (`IdrisFn` is `!Send`).

## Staged plan

Each stage runs AGENTS.md's checks on every target. All are
**AFTER-SELF**.

**P1. Task frames and the `wait` effect** (§2). **AFTER-SELF**; the
first step, needing only its place in the queue. Change: `idr.wait`, the `Waits` trait and
the `wait` case of `Idr_Effect`, coroutine lowering of `wait` functions
only, tail await. Proof: a waiting loop of 10^7 iterations in constant
memory; two `wait` functions tail-awaiting each other 10^7 times in
constant stack, in one bin and across two bins of a generated program
larger than two bins; a program that never waits lowers byte-identical
to the binary before P1 (the cutover's D22); D11's measurement.

**P2. One reactor** (§3, §10.2). **AFTER-SELF**; after P1, and its epoll
half needs a Linux target running (0002). Change: the
task table, wake queue and kick; kqueue with `EVFILT_USER` and epoll with
an eventfd; sleep; same-shard fork and join. Proof: two tasks' sleeps
overlap, and a post from a foreign thread wakes a sleeping reactor, on
every target.

**P3. Asynchronous Rust** (§10). **AFTER-SELF**; parked with 0020, after
P2 and 0020's foreign cells and shims. Change: the `FutT` loop, the
waker, runtime sockets and timers behind Rust's I/O traits, the blocking
offload. Proof: a hyper client and server on one shard against committed
expected files; cancellation frees the future (`IDRIS_RT_LIVE=1` reports
zero); a crate graph enabling tokio's `rt` fails the generator, naming
the crates (D12).

**P4. Shards** (§4 to §9). **AFTER-SELF**; after P1 and P2. Change:
`libs/mlir-shard`, its `Shard` primitives (D13) and `Shard.Pure` with
its `Faster` hook (D14); `idr.fork` and `idr.join` with the flow
interface, and `shard.grid`; the send check and the detach walk (§7.3,
§5.1); the helping join; the standard streams on every shard and handles
hopping home (D3, D4); process state under the platform lock (D5);
`Static i` and per-shard constant tables (D6); `scf.forall` lowered to
fork and join (§8); and AGENTS.md's `%foreign` paragraph, whose "as
threads" narrows to threads that share one heap (base's `fork`,
`threadWait` and `System.Concurrency` stay outside, D1), approved as D1
is. (AGENTS.md already admits a `libs/` package's own `%extern`
primitives, b843d8b5.) Proof: every shard fixture at `IDRIS_RT_SHARDS=1`
against its expected files and at more shards against the one-shard run
(D8); `Shard.Pure` fixtures, among them a crash in `x` after the
forker's output and a `trace` in `x`, against one set of expected files
at 1, 2 and 8 shards (D14); a reject fixture per `unsupported (send)`
path; zero live cells summed over shards; D6's measurement; D11's
cross-unit frame count beside the bench once 0008's S2 second step has
landed; parallel binary-trees, spectral-norm and mandelbrot against one
shard, with D9's idle-time record.

**P5. On a measurement.** **AFTER-SELF**; each item built when its rule
is met: lending (§5.3, D10); taking unstarted messages (§5.2, D9); pipes
(§9, D7), after P1, P2 and P4; io_uring submission behind the waiter,
when P3's hyper server at saturation spends more than a quarter of its
time in readiness and transfer system calls; SPMD through upstream's
`shard-partition` on 0009's tensor level (0009 §14), replacing P4's
`scf.forall` lowering whole, never beside it, when spectral-norm's best
of five is more than 2% faster with it on every target (the cutover's
§10; 0009 D35, D36), naming what lowers its collectives (0009 rejects
`ShardToMPI`, §17).

## Rejected alternatives

- **M:N work stealing on one heap** (Go, Tokio, Lean): every count
  atomic, tagged or traced, paid on one thread too. **A heap per task**
  (Erlang): every value two tasks on one core see is a copy (§4).
- **Stackful coroutines:** inline assembly, or `makecontext`, removed
  from POSIX in 2008. **A thunk as an LLVM coroutine:** a null test on every force
  (read: `sources/papers/peytonjones-1992-stg` §3.1.2) and a frame MLIR
  cannot see.
- **The async dialect:** a second count and pool, an error channel the
  language lacks, no operand naming where `async.execute` runs, and an
  await that blocks a reactor outside coroutines.
- **contrib's `System.Future`** (read:
  `third_party/Idris2/support/chez/support.ss`, `blodwen-make-future`), a
  thread per fork with a mutex and a forged world; **base's
  `System.Concurrency` and Chez threads**, a second schedule of effects
  on one heap; **a P2300 scheduler whose `start` is a pool**; **Brady's
  effects as a free monad at runtime**, a tree per bind.
- **A hop returning `At n s (On n s' a)`:** shard `s` would hold a
  pointer into `s'`'s heap; remote state is a `Local`.
- **A foreign thread's post that only publishes** (it must wake a
  sleeping reactor, §3.2); **a resume from a foreign thread** (§3.3);
  **io_uring as the wait**, commonly disabled under container seccomp
  profiles (recalled), so a later submission path (P5).
- **A Rust future as our coroutine handle** (rustc's state machine is a
  foreign value; the polling frame is ours); **a tokio island** (0020
  §3); **Tokio's `Arc` waker** (§10.2).
- **A generator coroutine for streams:** a pure language fuses producer
  and consumer instead (the contiguous-runs work, which has no
  proposal).
- Rejected with their decisions, for the reason given there: the
  standard streams as waits (D3), bodies for the effectful operations
  (D13), the frontend calling `fork` and `join` (D14), the send check as
  a verifier rule or a walk of its own (§7.3), a join as a source of the
  `wait` effect (§2), and a partition that keeps a coroutine with its
  callers (D11).

## Decisions

**D1. One world per shard** (the owner's, 2026-10-09). A shard is a
runtime thread with its own heap, world, plain counts, top-level
constant cells, handle table and output buffer, which only it touches.
Values cross shards inside messages, by move, copy or lend (§5). This
amends AGENTS.md's rule that threads are outside the language: one world
per shard, which P4 writes. Base's `fork`, `threadWait` and
`System.Concurrency` stay `unsupported (threads)`. It is Seastar's model
for the whole runtime (read: `sources/docs/seastar/shared-nothing.html`).

**D2. Effects are causally ordered.** On one shard, in program order.
Across shards, everything a shard did before posting a message (a fork,
a join's reply, a hop) happens before everything the receiver does after
taking it. Effects no message orders interleave, each whole: a `putStr`
is never split by another shard's output, and a line read goes to one
reader. Messages between two shards arrive in posting order (an MPSC
queue keeps each producer's order; read: `lietar-2019-snmalloc` §2.2).
Fork-join of pure work is deterministic and equals the sequential run.

**D3. The standard streams work on every shard.** Output is a buffer per
shard, like today's one (`runtime/Io/Output.cpp`, sized by
`IDRIS_RT_IO_BUFFER_SIZE` in `runtime/Io/Io.h`), with no lock on the
write path; a flush is one `writeAll` under the descriptor's lock, since
POSIX makes a pipe write atomic only up to `PIPE_BUF`, 512 bytes on
macOS (read: `SDK/usr/include/sys/syslimits.h:104`). A shard flushes
when its buffer is full, before it blocks, before it posts any message
(so output is causal) and at its end. Standard error stays unbuffered
(`runtime/Io/Ending.cpp`), each write one `writeAll` under its lock.
Input belongs to shard 0, with today's buffer (`runtime/Io/Input.cpp`)
and no lock; a read elsewhere is a blocking hop to shard 0, the reader
flushing first so a prompt precedes the read, served in arrival order.
Rejected: one locked process-wide output buffer, or a write per `putStr`
(each a cost on every single-shard write); all output owned by shard 0;
one locked input buffer.

**D4. Files and directories.** A handle table per shard (today one per
process, `runtime/Io/Handles.cpp`). A handle stays an `int64_t`: slot
`i` on shard `k` carries `k` above bit 47, so shard 0's handles keep
today's numbers; `0`, `1` and `2` are the standard streams on every
shard, and `-1` is null. An operation on a handle whose home is another
shard is a blocking hop home, so a file opened on one shard can be sent
as its integer and used or closed on another. A string the runtime keeps
is a slot of the calling shard's table. A single-shard program pays one
compare per file operation. A blocking hop is a runtime request, not a
task (the wake queue's entry says which): while waiting for its reply a
shard serves the handle and input requests other shards post and runs
no task, so two shards hopping to each other's handles cannot deadlock.

**D5. Process state.** The environment and current directory belong to
the process; the platform layer serializes `getenv`, `setenv`,
`unsetenv`, `getcwd` and `chdir` under one lock (C does not let `getenv`
race `setenv`; recalled). `exitWith`, or a crash, on any shard ends the
process: that shard flushes its output, writes its message and exits.
Output causally before is written (D3); output another shard buffered
concurrently may be lost. A crash in `Shard.Pure` work is the one
exception: it is held for its join (D14). At a normal end `runShards`
has joined every fork, and each reply flushed its worker.

**D6. Top-level constants are per shard.** Evaluated at most once per
shard that demands it, in that shard's slot (§6); with one shard, once,
as today. Whether a closed call of total code becomes such a constant is
0010's cost rule, computed at its first demand (0010 §2, D3). A `trace`
in one prints once per shard that forces it. Rejected: one process-wide
cell behind a once-guard, whose value, reachable from every shard, would
be persistent and never freed (read: `threadsafety.tex`), with every
thunk inside it forced by a test for sharing on the single-shard path.
**Measurement:** the lazy programs of `bench/` at `IDRIS_RT_SHARDS=1` are
no more than 2% slower, best of five, than the binary before P4, side by
side on each target (the cutover's §10, D22); P4 does not land until
they are. (**conjecture**: a few instructions; on Mach-O a thread-local
is reached through a descriptor.)

**D7. Streams across shards.** A stream lives on one shard, and only it
forces the stream's cells, because a memo is a plain write. By value:
supported, by detach (§5.1); the forced prefix is copied, the unforced
tail as label and captures, and elements both shards force are computed
twice. A shared memo over atomics: not supported, since every form (a
tag tested on every force, as Lean's; values made persistent and never
freed; a second counting regime) costs the single-shard path. A pipe
(§9) is the one stream that spans shards; its specification is `pipe s'
k xs = pure xs`, and it has one consumer, so the send check refuses its
stream. **Measurement:** pipes are built when a `bench/` program spends
at least a quarter of its one-shard time forcing one stream drained by
one consumer, the least share at which a two-stage pipeline saves a
quarter of the run.

**D8. Tests.** One set of expected files serves every core count. Every
fixture runs at `IDRIS_RT_SHARDS=1` against its expected files; one
whose output its joins order causally also runs at more shards against
the one-shard run; one with concurrent writes runs at one shard only.

**D9. Asymmetric cores.** One shard per processor, none pinned: macOS
offers QoS classes on Apple silicon, not affinity (recalled), and a
Linux-only affinity would be a per-target case. A library places work by
queue depth (§5.2). **Measurement:** on 8 performance and 4 efficiency
cores, P4 records the time shards spend idle at their last join, for
parallel binary-trees, spectral-norm and mandelbrot at 12 shards; taking
unstarted messages is built when it exceeds a tenth of shards × wall in
any of them.

**D10. Copy or lend.** Copy first (P4); `lent` when the copy costs.
**Measurement:** for k-nucleotide's sequence and spectral-norm's vector
at 8 shards, the coordinator's time in detach walks; lending is built
when it exceeds 5% of wall, the serial share at which Amdahl caps 8
shards at 5.9×.

**D11. The cost of colouring.** The helping join keeps fork/join
uncoloured, so only functions that really wait pay. **Measurement:**
P1's proof runs 10^7 calls to a `wait` function whose wait completes at
once and counts the frames allocated: zero per call after CoroElide. If
our lowering lets the handle escape, our lowering is fixed; if
CoroElide misses a case it should take, the case is reduced and fixed in
LLVM. Elision needs caller and callee in one LLVM module: until 0008's
S2 second step O3 runs on the whole module, so zero holds everywhere;
from it, zero holds within a unit, and across two units, where elision
is impossible by construction, the frame comes from the size-class fast
path and the per-call count is recorded beside the bench. Keeping a
coroutine with its callers would be a branch in the partition, a pure
function of content (0008 D4); the idr inliner already inlines a small
`wait` function before idr-lower makes it a coroutine (the cutover's
§4.7). If the cross-unit count costs a bench program more than 2%, best
of five, the fix goes into LLVM or our lowering, never the partition.

**D12. Which Rust crates work.** Computed per crate graph, not listed:
a crate works when its graph enables none of tokio's `rt`, `net` or
`time` features and is generic over the async I/O traits the runtime
implements (hyper 1.x, h2, `tokio-postgres` over a provided stream, the
AWS SDK with a provided connector; recalled). Any other graph fails the
generator, naming the crates (0020 §11.5, §15): a generator's failure
stops the build before the compiler runs, so it is no refusal of a
program and no case of the dialect's `Rule` enum. P3's fixture is a
hyper client and server.

**D13. The effectful operations are runtime primitives.** `runShards`,
`fork`, `join`, the `Local` cells and `pipe` are bodiless `%extern`s
whose one meaning is the runtime's (§7.1). Their sequential reading is
their specification: for pure work the runtime meets it exactly (D2),
and where forked effects interleave the runtime's causal order is the
meaning, which no Idris body can state, so a body beside them would be a
second meaning. By AGENTS.md's two hosts (028c6907, b843d8b5), a `libs/`
primitive runs under idris-mlir alone and nothing the stock host runs
reaches one: no program runs these on the stock host, and the compiler's
Idris half never calls them.

**D14. Pure fork/join for code the stock host runs** (the coordinator's
two-hosts ruling, 2026-10-15; lands with P4, **AFTER-SELF**). The
owner's 2026-10-14 ruling (a4e763c7; 0008 §5.4, §12) puts the compiler's
Idris half on these shards from stage 1, and that half must also compile
and run on the stock host, forever, reaching no `%extern`. So it reaches
the shards through `Shard.Pure` (§7.1), plain Idris over base with
bodies, and is single-threaded until that layer exists.

- **The body is the one meaning**, sequential: `both x y` forces `y`,
  then `x`. The stock host runs it so.
- **idris-mlir lowers `both` through a `Faster` hook** of the registry
  (`compiler/src/IdrisMLIR/Registry/Entry.idr`, `Kind`), as it lowers
  `Linear.String.Iterator.scalarBytes`: `x` becomes an `idr.fork` to the
  least-loaded shard (§5.2), `y` runs here, and the helping join awaits
  `x`. Placed on the running shard, `x` is queued, not called as §7.3's
  fork to the running shard is, so the join runs it after `y`, in the
  body's order. Removing the hook changes the time a program takes,
  never its output.
- **What keeps the output identical.** The work is pure, so D2 makes its
  value the body's. A crash in `x` is held as its join's reply, so the
  forker's work before the join, and a crash in `y`, come first, as in
  the body. Work whose force has `io` in its effects summary (a trusted
  library's forged world, `trace`'s included) is placed on the running
  shard and so runs at the await, in program order. `both` has no spawn
  without its join, so no work runs that the body would never evaluate.
- The send check applies to `x`'s captures as to any fork's operands
  (§7.3), and idr-entry starts the shards when the program holds an
  `idr.fork`, a fact of the module (§3.1).

Rejected: a `spawn`/`await` pair, since a dropped handle is work the
body never evaluates, which only a linear type would forbid, while the
shape of `both` makes it unrepresentable.

## The MLIR form owed

From the representation wave's audit of the proposals' MLIR forms (its
last text at 77eaa5b1), checked against the code there; none of it is
built unless it says so.

- A forall forks only when it is mapped: a `#idr.shard`
  `DeviceMappingAttrInterface` written by `tile_using_forall`; every other
  `scf.forall` goes through `scf-forall-to-for`. §8 (and 0009 §14) say "the
  one lowering of scf.forall" and change with it.
- Waiting is a memory effect, `MemWrite<Idr_WaitResource>` on the ops that
  wait, not a `Waits` trait and a fourth `Idr_Effect` bit; `bodyEffect`
  classifies by op kind today and must read resources for it.
- `idr.wait` implements `BranchOpInterface`; `idr::forwardedValues` and
  `declaresFlow` (`include/idr/IR/Flow.h`) read only
  `RegionBranchOpInterface` today and learn the branch form with it.
