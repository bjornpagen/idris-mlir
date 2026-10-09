# Concurrency: thunks, tasks, shards and futures

The design of suspended computation, the runtime that runs it on many cores,
and the future Rust is polled on. It is written against `main` at cb65104
and applies the moves of `substrate.md` (S1 to S6). Nothing here was built,
run or timed. Markers are those of `substrate.md` (**read**, **measured**,
**decision**, **conjecture**). It supersedes the notes `frame.md`,
`copies.md`, `future.md`, `async-dialect.md`, `papers.md`,
`rust-executor.md`, `scheduler.md`, `execution.md`, `shards.md` and
`cross-shard.md` at cb65104. Their readings are cited where they are used;
their corrections are §1.

## 0. The idea

A suspended computation is one of two objects, and the difference between
them is where it was paused.

**Paused before it started: a closure.** What it holds is known in MLIR,
because it is exactly its captures.

- A function value is a closure applied any number of times.
- A thunk (`Lazy`, `Inf`) is a closure with a memo.

Both are first-order data after defunctionalization: an immutable sum for a
function, and a mutable memo sum for a thunk. A thunk's state machine, *not
yet, running, done*, becomes three constructors and a match. The heap then
holds no code pointer at all (§2).

**Paused in the middle: a task frame.** What it holds is the values live
across the pause, which are known precisely only after optimization.

- LLVM's switched-resume coroutine (`llvm.coro.id`) is that frame, and
  CoroSplit computes it.
- Only a computation that waits for an event is paused in the middle, and
  waiting needs the world. So a frame holds a world, the world is quantity 1,
  and the frame is linear by construction (§3).

**One owner for everything.** Every cell, thunk and frame belongs to exactly
one shard: a thread the runtime starts, with its own heap, its own world and
plain counts. Only that shard counts a cell, forces a thunk or resumes a
frame. Values cross shards inside messages, by move, copy or lend. Frames
and worlds never cross (§4).

**The handler is the executor.** Three formulations are the same thing:

- Brady's handler, `handle : res -> (eff : e t res res') -> ((x : t) -> res' x -> m a) -> m a`
  (read: `sources/papers/brady-2014-resource-effects` §3.1);
- McBride's interpreter, which "follows one path in the tree... taking the
  edge determined by reality" (read: `sources/papers/mcbride-2011-kleisli` §7);
- a P2300 receiver.

Each holds a continuation and answers a command. The task frame is the
continuation compiled, CoroSplit is the CPS transform, and a shard's reactor
is the handler. *Pending* is a frame paused at a command nobody has answered
yet (§5).

Why the line falls there:

- **Closures and thunks go to defunctionalization**, in MLIR, where
  ownership, evaluation and inlining see them.
- **Tasks go to CoroSplit**, in LLVM, because only after optimization is the
  set of values live across a wait small and exact.
- **The same rule is applied at both levels.** An LLVM coroutine frame is a
  defunctionalized continuation: its suspend index is the tag, its spills
  are the fields, and its resume function is the match. So the design
  applies one rule, "suspended computation is data", at the level where the
  data is known.

## 1. Corrections

The table first; the full arguments are in the sections it cites.

| Claim | Where | Correction |
|---|---|---|
| `Lazy` should become an LLVM coroutine, deleting `idr.suspend`/`idr.force` and the `Lazy.cc` rules | `frame.md`, `copies.md`, `future.md`, and this note's first draft | No. A thunk is never paused mid-body, so a coroutine adds nothing and costs a test (§2.1). The ops stay as the value-level spelling (`idr.delay` after S1). The rules become S1's two region rules. What goes is the code pointer itself: thunks join defunctionalization (§2.3). |
| A coroutine frame's first word is its resume pointer, which conflicts with the cell header | `frame.md`, `copies.md` | No conflict. The frontend allocates the frame's memory and passes it to `coro.begin`, so the header goes before it (§3.2). |
| The async dialect is a thread pool, so it is out | `async-dialect.md`, `future.md`, `scheduler.md` | The pool is one library. The dialect is out for other reasons (`substrate.md` §4). |
| `Rust (FutT a)` is `!async.coro.handle` | `rust-executor.md` | A Rust future is rustc's own state machine, a foreign value. The Idris frame that polls it is ours (§5.3). |
| `System.Future` is `!idr.lazy` | `future.md` | Refused by name. It is contrib, `%foreign`, and a sequential `Lazy` under a parallel name (§5.1). |
| `Hop : ... -> At n s (On n s' a)` | `shards.md` | That leaves shard `s` holding a pointer into shard `s'`'s heap, which is the `foreign_ptr` the same note rejects. Values cross only in messages; long-lived remote state is a `Local` handle (§4.5). |
| A foreign thread's post is a release-publish on an MPSC queue | `cross-shard.md` | It must also wake a reactor asleep in the kernel: `EVFILT_USER` on macOS, eventfd on Linux (§4.8). |
| The Linux wait is io_uring | `cross-shard.md` | epoll and eventfd. io_uring is a later submission path behind the same operation (§4.8). |
| A count-0 cell is shareable by pointer | `cross-shard.md`, `shards.md` | Not today: a constant suspension is a mutable global. After `substrate.md` S4.2, yes, except a static thunk, which is copied (§4.3). |
| `llvm.coro.save` is the requirement to delete | `scheduler.md`, `shards.md`, `cross-shard.md` | The requirement to delete is a resume from a foreign thread. A save is needed on one thread too (§3.3). |
| The memo is the meaning of `Lazy` | all of them | Stock Chez runs `Delay` call-by-name (`substrate.md` §5). The memo is a complexity guarantee. |
| Thread-per-core needs no change to the threads decision | `shards.md` | It needs a new decision: one world per shard. It is proposed in `README.md`. Base's `System.Concurrency` is to be named under `threads`. Today it falls through to the generic `%foreign` refusal (read: `compiler/src/IdrisMLIR/Registry/Recognized.idr`, which lists only `fork` and `threadWait`). |

## 2. The thunk

### 2.1 Why a thunk is a closure

**read** A force runs the suspended body to the end, on the forcing thread,
every time:

- the suspend verifier rejects a world capture (read:
  `foreign/idr/lib/Dialect/Ops/Lazy.cc`, `SuspendOp::verify`);
- pure code cannot wait.

So a thunk is only ever paused *before* it starts, and its paused state is
exactly its captures. A switched-resume coroutine with no inner suspend is
the same object: the ramp stores the captures, the resume runs the body and
writes the promise, and the final suspend nulls the resume pointer.

The coroutine would add two costs:

- **A test on every force.** Resuming a finished coroutine is undefined, so
  every force must first test the resume pointer for null. STG prefers its
  self-updating model precisely because "in the cell model, either a second
  test must be made... Both methods impose extra overhead" (read:
  `sources/papers/peytonjones-1992-stg`, §3.1.2 and Fig. 2–3).
- **A frame MLIR cannot see.** It would exist only after CoroSplit, so
  ownership, reify, static data and layout could not see inside it.

### 2.2 What is wrong with today's thunk

Four things are wrong with the hand-written thunk, and none of them is
fixed by a coroutine:

1. **It holds a code pointer**, so the heap holds code, and so do
   compile-time results:
   - reify identifies a thunk by its code (read:
     `foreign/idr/lib/Eval/Reify.cppm`);
   - identical code folding must be defeated by a volatile store of the
     label (read: `Lower/Runtime.cppm`, `distinguish`).
2. **It keeps its captures alive while it runs.** `enter` increments every
   capture and holds it until the value is in hand (read:
   `Lower/Runtime.cppm`, `emitSuspension`). A thunk that consumes a list
   therefore keeps the whole list alive, which is STG's space leak (§9.3.3,
   the `last ns` example). Under counting it also blocks in-place reuse of
   that list: the count is at least 2.
3. **A self-force recurses until the stack runs out**, instead of naming the
   loop. That is STG §9.3.3's first reason for the black hole.
4. **A constant suspension is a mutable global,** and `idris_rt_lazy_kept`
   keeps a list of the ones a force wrote (read: `Lower/StaticData.cppm`,
   `runtime/Rc/Counting.cppm`).

### 2.3 The thunk after defunctionalization is a memo sum

**decision** `!idr.lazy<T>` joins defunctionalization. idr-defunctionalize
already finds the labels every closure value may hold, on MLIR's solver, and
turns each key into a sum (read: `foreign/idr/lib/Defunctionalize/`; "in a
whole program that is only a key whose labels the analysis cannot know").
The same analysis follows thunks (`Slots.cppm` already follows `SuspendOp`
and `ForceOp`).

After it, a thunk of key *K* with labels L1..Ln is a box of a memo sum:

```
memo K = Delayed_L1 caps1 | ... | Delayed_Ln capsn   -- not yet run
       | Running                                      -- STG's black hole
       | Forced v                                     -- the value
```

`idr.force` of it becomes one generic lowering, the same for every key:

```
match cell:
  Forced v         -> v (a view; an inc when the use consumes)
  Running          -> crash "a suspension forced itself"
  Delayed_Li caps  -> cell := Running (the captures move out: no inc, no dec)
                      v := call Li(caps)          -- direct: the label is known
                      cell := Forced v
                      v
```

It is SICP's move: the code pointer's state machine is now data, and the
force is a small evaluator over it.

**Problems 1 to 3 disappear structurally:**

- There is no code pointer, so there is no `distinguish`, no code table in
  reify, and no `enter`/`done` pair per label.
- The captures move out at entry, so a consumed list keeps count 1.
- A self-force reaches `Running`, which crashes with a name.

**Things that become possible:**

- A force of a key with one label calls that label directly. LLVM can
  inline it.
- A force of a key whose label set grows past what a branch should hold
  dispatches by one switch per key. That is the indirect jump the code
  pointer was, now visible to upstream passes.

**What it costs.** One tag test per force where the self-updating model had
an indirect call. Over a long-lived memoized stream (`fibs`) the test is
predictable after the first force.

The update is a write into a cell other references can see. That is what a
memo is. **decision**: in the first cut (proposal 0002) the write happens
in the force's lowering, below `idr-rc`, the last pass that reasons about
references, so ownership stays one op's contract (view, owned or `excl`).
An `idr.lazy.settle` op with a write on a memo resource, so that no pass
reorders it with a read of the same cell, comes with phase 2, when passes
that reason about references see the protocol. The constructor fields reserve the larger of the captures and the
value. The `Layout/` code that sizes a suspension today stays, for the sum
(read: `Layout/PlaceClosures.cc`).

### 2.4 Static thunks are per-shard copies of an immutable template

STG solves the same problem for its CAFs. "It allocates a black hole closure
in the heap whose purpose is to receive the subsequent update... and
overwrites the static CAF closure with a three-word CAF-list cell, pointing
to the black hole in the heap, and linked onto the CAF list" (read: STG
§10.8, "Global updatable closures"). `idris_rt_lazy_kept` is that list.

**decision** A constant thunk is an immutable template, the constant
`Delayed_L caps` with persistent captures, plus a thread-local cell
initialized from it. In MLIR that is an `llvm.mlir.global` with
`thread_local_`, whose initial image is the template.

- **The loader does the copying.** Every shard (thread) gets its own copy
  from the TLS image, at no cost to the compiler.
- **A force writes the shard's copy in place.**
- **No list is needed.** The compiler emits each module's table of CAF
  cells, and a shard's exit releases the forced ones: one static array, no
  runtime list.
- **Static data becomes immutable without exception** (`substrate.md` S4.2).

**Correction** (proposal 0002). A thread-local cell cannot be referenced
from constant static data. A constant stream's tail is a static thunk, and
a thread-local global's address is not a link-time constant. So the first
cut keeps one memo cell per process, written once and marked by the thunk
kind, with the compiler-made release function in place of the list. The
per-shard copy needs one more indirection, for example static data
holding a CAF index that a force resolves on the running shard. That is
decided with the shards work (W14).
### 2.5 The memo is decided per thunk

Stock Chez memoizes only 0-ary top-level lazy definitions, and every other
`Delay` is call-by-name (`substrate.md` §5). `allschemes/memo002` needs the
CAF memo to finish at all (read: `findings/upstream-idris/lazy-constants.md`).
So the memo is a complexity guarantee this compiler makes, not part of the
program's meaning, and the compiler may choose it per thunk:

| Thunk | What a force does | Decided by |
|---|---|---|
| one force, anywhere below its definition | the body, inlined: no cell | S1 rule 1, before idr-rc |
| forces in disjoint arms of one match | the body in each arm | S1 rule 2 |
| a force of an `excl` cell at its last use | take the captures, call, free the cell; no `Running`, no `Forced`, no write | idr-rc's grade (STG's update flag `n`, read: STG §4.2) |
| shared (ω) | the memo protocol of §2.3 | default |
| a body that forges a world (a trusted `unsafePerformIO`) | never memoized: every force runs it | the body's `io` effect |

The last row keeps a trusted library's effects where the value is
demanded, as often as it is demanded, in program order with every other
effect.

### 2.6 Streams and generators

- **A shared stream** (`fibs`, `stream-share`) is a chain of memo thunks.
  That is essential: sharing needs a memo per tail.
- **A stream consumed once** is a chain of one-shot thunks (row 3 above).
  Fusing it into a loop is the lists note's producer/consumer fusion by
  raising (step 2b at 4cfce76), which needs neither a thunk nor a coroutine.
- **A generator coroutine**, one frame suspended many times, is not needed
  in a pure language that fuses. It would be the fallback where fusion
  fails. **conjecture**: no benchmark needs it.

## 3. The task frame

### 3.1 What it is

A task frame is a computation paused in the middle, at a wait:

- a join of a fork on another shard;
- a socket or timer event;
- a Rust future that returned `Pending`.

**decision** It is LLVM's switched-resume coroutine, emitted by idr-lower as
`llvm.intr.coro.*`. The ops the LLVM dialect does not spell (`coro.done`,
`coro.destroy`, `coro.alloc`) go through `llvm.call_intrinsic` (read:
`mlir/include/mlir/Dialect/LLVMIR/LLVMIntrinsicOps.td:708-770`;
`LLVMOps.td`, `LLVM_CallIntrinsicOp`). CoroSplit and CoroElide already run
in both pipelines we use, because `buildPerModuleDefaultPipeline(O3)`
includes the coroutine passes (read: `foreign/idr/lib/Target/Optimize.cppm`;
`llvm/lib/Passes/PassBuilderPipelines.cpp`, `buildCoroWrapper` and the
CoroSplit/CoroElide additions).

**In MLIR**, the wait is `idr.wait`: a terminator with two successors.

- **resume:** where the task continues with the answer and the next world;
- **cancel:** where its live owned values are dropped.

`async.coro.suspend` has that shape (read: `AsyncOps.td`,
`Async_CoroSuspendOp`), but we spell our own, for the reasons in
`substrate.md` §4. Because the cancel successor consumes the live owned
values, idr-rc places their drops there as it places any drop. The frame's
destroy function is then the cancel path, which CoroSplit outlines.

### 3.2 Layout and ownership

The frontend gives the frame its memory (`coro.alloc`, `coro.begin`), so
the header goes in front of it:

```
cell ─► [count | info]   the runtime header: kind task
         handle ─► [resume ptr][destroy ptr][promise][index, spills ...]   LLVM's layout
```

That frame layout is LLVM's (read: `llvm/lib/Transforms/Coroutines/CoroFrame.cpp`,
`buildFrameLayout`: "Resume function pointer at offset 0... Destroy function
pointer at offset ptrsize... Promise alloca... Suspend/Resume index...
Spilled values"). The promise's offset is fixed by its alignment alone
(read: `CoroEarly.cpp`, `lowerCoroPromise`).

**decision** The promise holds three things:

- the task's slot in its shard's task table;
- its awaiter, the slot to wake when it finishes;
- its result.

A task frame is linear: its count is always 1 and is never tested. It is
owned by the task table while suspended and by the running reactor while
resumed. It is freed by its own final cleanup, or by `coro.destroy` when it
is cancelled. Counting never frees it, so the free walk never meets one.

### 3.3 Real and unreal forces of the construct

**Real:**

- **Resuming a running or finished coroutine is undefined** (read:
  `llvm/docs/Coroutines.md`, "llvm.coro.resume", "llvm.coro.destroy").
  Only the owning reactor resumes, and only a task the table holds as
  suspended.
- **A save happens before an operation that may complete before the
  suspend returns** (read: `Coroutines.md`, "llvm.coro.save"). That is true
  on one thread: registering a wait with the reactor, then suspending. What
  is excluded is a resume from another thread (§4.9).
- **A suspend happens only in the coroutine itself.** Every caller of a
  function that may wait, up to the reactor, is a coroutine too. This is
  colouring (§3.4).

**Not real:**

- **The header conflict** (§1).
- **ABI instability across LLVM releases.** Every program is one module on
  one pinned LLVM, with the runtime's bitcode linked in.

### 3.4 Colouring, decided by the compiler, and avoided where it can be

A stackless coroutine colours its callers. Stackful frames would not, but
they need a stack switch: inline assembly (excluded by AGENTS.md) or
`makecontext`, which musl does not ship. So the compiler colours, and it
colours as little as it can.

**decision** idr-effects gains a fourth bit, `wait`, beside `io`, `crash`
and `diverge` (read: Passes.td, `idr-effects`). It is computed like the
others, from the primitives that wait:

- sockets, timers and sleep;
- Rust `await`;
- the join of a fork that must interleave with other tasks.

Only `wait` functions are lowered as coroutines.

A join in a function that waits for nothing else does not colour it. It
*helps* instead: while its reply has not arrived, it runs the work that
arrives on its own shard, on its own stack, then returns. For structured
fork/join this cannot deadlock. A computation a fork started cannot depend
on its forker's continuation, because there is no channel back except the
reply. And the stack grows by the depth of nesting, as a recursive call
would. **conjecture**: every parallel program in `bench/` is of that form,
and runs with no coroutine at all.

A program that never waits has no reactor and no task frame, and runs as
today.

**Tail calls between waiting functions** keep the constant-stack promise.
`idr-tail-loops` turns self tail calls into a loop inside one frame. A tail
call from one waiting function to another is a *tail await*:

1. the callee's frame takes over the caller's awaiter;
2. the caller's frame is destroyed;
3. the callee is resumed by a `musttail` call.

That is C++'s symmetric transfer on switched-resume. **conjecture**, to be
tested first: a waiting loop of 10^7 iterations runs in constant memory.

## 4. The shard

### 4.1 Why thread-per-core and not M:N

Plain `++count`, and reuse on a count of 1, need one thread touching a
cell's count at a time. There are three ways to keep that, and they differ
in the size of the ownership domain:

| Domain | Model | What it costs |
|---|---|---|
| the whole heap | M:N work stealing (Go, Tokio, Lean tasks) | Any task may run on any thread, so any cell it reaches may be counted by any thread. Go traces (read: `sources/docs/go-scheduler/gc-guide.html`). Tokio pays an `Arc` per task and per wake (read: `sources/docs/tokio/scheduler-2019-10.html`, "Reducing atomic reference counting"). Lean walks the graph with `markMT` before each task and tests a tag on every count, after fences cost it "even when only one thread is being executed" (read: `sources/papers/ullrich-2019-counting-immutable-beans/threadsafety.tex`). Koka's `tshare` is the same (read: Perceus TR §2.7.2). Biased counting splits every count (read: Choi et al. PACT 2018 §4.1). |
| one task | M:N with a heap per process (Erlang) | One owner at a time even when a process migrates. But every message between tasks is a copy, including between two tasks on one core (read: `sources/papers/johansson-2002-heap-architectures` §3). |
| one core | thread-per-core (Seastar) | Tasks on one core share cells freely, with plain counts; crossing a core copies or moves (read: `sources/docs/seastar/tutorial.md`; `shared_ptr` is non-atomic). |

**decision** A heap per core. Idris shares immutable data everywhere,
implicitly. A heap per task would turn every value two tasks see into a
copy, while a heap per core makes the common case free.

The model's weakness is balance, and the M2 Max makes it concrete: 8
performance cores and 4 efficiency cores. Two remedies:

- **Placement is a runtime value**, so a library can choose the
  least-loaded shard.
- **A message nobody has started yet owns a detached graph** (§4.3), so an
  idle shard may take it without breaking one owner at a time. A started
  frame cannot migrate, because its cells are on its shard's heap.

That is most of what stealing buys, without its shared heap. Whether it is
enough on asymmetric cores is open question 1 in `README.md`.

### 4.2 snmalloc fits this model exactly

snmalloc is "aimed at workloads in which objects are typically deallocated
by a different thread than the one that had allocated them", which it calls
producer/consumer (read: `sources/papers/lietar-2019-snmalloc`, abstract).
Its design has two paths:

- **a thread-local fast path**;
- **remote frees** returned to the owning allocator "in batches without
  taking any locks", through one multi-producer single-consumer queue per
  allocator, with one atomic exchange per batch (read: §2.2).

Thread-per-core hits exactly those two paths:

- almost every allocation and free stays on its shard: the fast path;
- a message detached on one shard and freed on another is the batched
  remote path, the case snmalloc was built for.

M:N stealing scatters frees across threads at random and loses locality,
and its dominant cost, the atomic count, is not snmalloc's to remove.

### 4.3 What crosses, and who owns it

**decision** A message is detached on the sending shard before it is
enqueued, in one walk of the counted graph it reaches.

| Cell | Treatment | Why it is sound |
|---|---|---|
| count 0 (persistent), not a thunk | sent as the same pointer | after S4.2, persistent data is immutable and points only at persistent data |
| a static thunk (the TLS copy of §2.4) | copied as its template, unforced | it is per shard; the destination forces its own copy; the memo is not semantics |
| count 1, reached only through moved cells, at a send that consumes the sender's last reference (idr-rc decides) | moved: the pointer is the message | nobody else can reach it; the destination's later free is snmalloc's remote free |
| count above 1, or a stack cell | copied into a fresh count-1 cell. A forwarding map keyed by address keeps the DAG's sharing; only cells with count above 1 can be reached twice, so only they enter it | the sender keeps its aliases and decrements on its own shard: Erlang's copy without Erlang's collector, and Orca's alternative for immutable data (read: `sources/papers/clebsch-2017-orca`, "when data structures are immutable") |
| a thunk, `Forced` | copied with its value | a value |
| a thunk, `Delayed` | copied unforced; its captures are walked | forcing it to send it could diverge where the program would not; the memo is not semantics |
| a thunk, `Running` | impossible: a thunk is running only on its own shard's stack, inside its force | — |
| a task frame, a world, `Here`, a mutable cell, a `Local` of another shard | never sent | rejected by the send check (§4.6) |

Quantity is not consulted, because a linear binder does not imply unique
heap ownership (read: AGENTS.md). The count decides move against copy, and
idr-rc's last use decides whether the sender still needs the value.

The cells a copy makes are allocated by the sender's allocator and owned by
the receiver. That is one owner at a time, and frees go home as remote
frees. The live-cell counter is per thread today (read:
`runtime/Alloc/Cells.cppm`, `thread_local liveCells`), so the zero-live-cells
property is checked on the sum over shards at exit.

**Lending, later.** Copying costs serial work on the sender (§4.10). The
alternative for large immutable inputs is a lend:

- a structured `fork` guarantees the lender keeps the value alive until it
  joins;
- the borrower receives it at a new permission, `lent`, beside `borrow`,
  `own` and `excl`;
- `idr-rc` lowers a `dup` at `lent` to a deep copy into the local heap, and
  a `drop` at `lent` to nothing;
- forcing a `Delayed` thunk reached through a lent value copies it first.

The fact "this value lives on another shard's heap" is in the grade, where
no pass can lose it (AGENTS.md). Marshall and Orchard's fractional
uniqueness is the theory of exactly this split: a unique value shared out as
read-only fractions and joined back (read:
`sources/papers/marshall-2024-fractional-uniqueness`, abstract: "a Rust-like
ownership model arises as a graded generalisation of uniqueness"). Lending
waits on a measurement, open question 2.

### 4.4 The type of a hop

**decision** The surface is a new in-house package, `libs/mlir-shard`, in
plain Idris over base, as `mlir-linear` is. Read as written, its
definitions are ordinary sequential IO:

- a fork runs its computation to completion at once;
- a join returns the stored result;
- a `Local` is an `IORef` in a table.

```idris
module Shard

||| Being on shard s of n: linear, so no closure can carry it elsewhere,
||| and empty at runtime, as %World is. The index is quantity 0.
export data Here : (n : Nat) -> (0 s : Fin n) -> Type

||| IO on shard s. Same-shard code is ordinary do-notation: bind threads
||| Here as io_bind threads %World. Its (>>=) is Linear.Notation's.
export data Shard : (n : Nat) -> (0 s : Fin n) -> Type -> Type

export io   : IO a -> Shard n s a
export pure : a -> Shard n s a

||| The runtime starts S k shards (IDRIS_RT_SHARDS, else the processor
||| count) and runs the body on shard 0. n is a runtime value: nothing is
||| specialized on it.
export runShards : ((k : Nat) -> Shard (S k) FZ a) -> IO a

||| Start p on s' and return at once. The join is linear, so every fork is
||| joined: concurrency is structured.
export fork : {n : Nat} -> {0 s : Fin n} -> (s' : Fin n) -> Shard n s' b -> Shard n s (Join n s b)
export join : (1 _ : Join n s b) -> Shard n s b

||| A hop: fork and join.
export submit : {n : Nat} -> {0 s : Fin n} -> (s' : Fin n) -> Shard n s' b -> Shard n s b

||| State that lives on one shard. Pony's `tag` (read:
||| `sources/papers/clebsch-2015-deny-capabilities`, Fig. 4): sendable and
||| opaque, usable only on its home shard. Its cells live until that shard
||| ends.
export data Local : (n : Nat) -> (0 s : Fin n) -> Type -> Type
export newLocal : a -> Shard n s (Local n s a)
export getLocal : Local n s a -> Shard n s a
export setLocal : Local n s a -> a -> Shard n s ()
```

What a user writes:

```idris
main : IO ()
main = runShards $ \k => do
  input <- io getLine
  rs <- forAll (allFins k) $ \s' => fork s' (pure (solve s' input))
  io (printLn (sum rs))
```

`forAll` forks all, then joins all.

### 4.5 The hop in MLIR

**decision** A fork is an `idr.fork` region op, `IsolatedFromAbove`, and
its operands are the message: the destination shard as an `index`, and the
captured values. Isolation is the property the MLIR paper defines for
exactly this: "no use-def chains may cross the isolation barriers" (read:
`sources/papers/lattner-2020-mlir/ir_design.tex`). So a pass can never
thread a value of one shard's heap into another's by accident: crossing is
an operand, and an operand is a message.

- **The grid is upstream's.** The grid of shards is
  `shard.grid @cores(shape = ?)`: upstream's own op, whose size may be a
  runtime value (read: `mlir/include/mlir/Dialect/Shard/IR/ShardOps.td`,
  `Shard_GridOp`, "dynamic device assignment").
- **So is the running shard.** It is `shard.process_linear_index on @cores`.
- **The result is linear.** It is `!idr.join<T>` at grade `(1, own)`.
- **Lowering is a message plus a wait.** `idr-lower`:
  1. outlines the region;
  2. detaches the operands (a runtime call);
  3. posts the message: a function pointer and the detached operands;
  4. lowers `idr.join` to `idr.wait` (§3.1) or to the helping join (§3.4).
- **A fork to the running shard is a call.** Seastar does the same
  (read: `sources/docs/seastar/smp.hh`, `submit_to` of `this_shard_id()`).

### 4.6 The send check

The frontend cannot check sendability: the sums of closures do not exist
before idr-defunctionalize, and `Send` is not an Idris interface a user
should have to implement.

**decision** It is part of `CapturingOpInterface`'s isolation (`substrate.md`
S1.3), run by the `idr.program` verifier after defunctionalization. It walks
the types an `idr.fork`'s operands and result reach, and rejects any that
hold:

- a mutable cell (`IOArray`, `IORef`, `Buffer`);
- a world;
- a `Local` whose shard index is not the destination.

The rejection is `unsupported (send)`, naming the type and the path to it.
A linear array (`mlir-linear`) is exclusive by type, so it moves. Sending an
array and getting it back is the data-parallel case.

### 4.7 Effects and order

- **Fork-join of pure work is deterministic,** and equal to the
  sequential run its definitions describe (§4.4).
- **Effects on different shards interleave,** which that run never does.
  **decision**: the standard streams belong to shard 0's world, and another
  shard writes them by hopping to shard 0. Their order is then the order
  shard 0 handles messages. A program whose output depends on that order
  is checked at one shard only.
- **One set of expected files serves every core count,** because the core
  count is a runtime fact: every fixture runs with `IDRIS_RT_SHARDS=1`
  against its expected files, and with more shards against the one-shard
  run where the program is deterministic.
- **The standard streams stay blocking calls on shard 0.** The batch
  programs this compiler is measured on read standard input in a loop.
  Making that a wait would colour every one of them for nothing, and a
  blocking read on shard 0 stalls only shard 0.

### 4.8 The reactor and the platform wait

Each shard is a runtime thread holding:

- a reserved stack with a guard and its own `sigaltstack`: one runner per
  shard instead of one per process (read: `runtime/idris_rt.h`,
  `idris_rt_run_on_stack`);
- a snmalloc allocator, already per thread;
- its TLS CAF cells (§2.4);
- a task table (slot, generation);
- a run queue;
- an MPSC wake queue, snmalloc's own shape;
- one platform waiter.

The waiter is one operation behind `rt.platform` (AGENTS.md: OS calls behind
the platform layer):

| Target | Waits on | A post wakes it with |
|---|---|---|
| arm64 macOS | `kqueue`/`kevent` (read: `sources/papers/lemon-2001-kqueue`) | `EVFILT_USER` with `NOTE_TRIGGER` (recalled; it postdates the 2001 paper) |
| x86_64 Linux | epoll | an eventfd |

io_uring is a later submission path for sockets and files behind the same
operation (read: `sources/papers/axboe-2019-io-uring`, its rings and
barriers). It is not the wait: io_uring is commonly disabled under container
seccomp profiles (recalled).

A post pushes, then kicks the waiter only if the reactor said it is about to
sleep, which is one flag. A turn of the reactor:

1. drain the wake queue into the run queue;
2. resume ready tasks until the run queue is empty;
3. wait.

A resumed task does not block (read: `sources/papers/belay-2014-ix` §4.1,
"elastic threads are expected to not issue blocking calls"; Seastar
tutorial, line 33). The exception is decided in §4.7.

### 4.9 What a foreign thread may touch

**decision** A foreign thread (a Rust thread, a blocking offload thread) may:

- push a token onto a shard's wake queue and kick it;
- use memory that is not an Idris cell;
- free raw blocks remotely through snmalloc (read: `idris_rt.h`, "free a
  block from any thread").

It may not:

- resume a frame;
- force a thunk;
- read or write a count;
- hold a reference to an Idris cell;
- hold a world.

### 4.10 Amdahl

The speedup is 1 / ((1 − p) + p/n). Three things silently move work into the
serial term, and each has its remedy in this design.

**1. Contended counts on shared read-only data.** On a shared heap with
atomic counts, n workers reading one prelude structure increment and
decrement the same headers. Reads become writes to one cache line, which
bounces between cores: the parallel part serializes. Tracing collectors
avoid it, which is why collected languages scale on shared reads. Here a
copy avoids it, at a cost (item 2), and a lend avoids it at none: the lent
grade has no count operations at all.

**2. Distribution and collection on one coordinator.** If shard 0 forks k
tasks, it runs k detach walks, serial work proportional to the data sent,
and receives the k results the same way. Three remedies:

- **Fan out and in as a tree.** Each shard forks the next level, which
  makes distribution logarithmic.
- **Workers make their own data**, as binary-trees does.
- **Lend** what is large and immutable.

**3. Imbalance.** The parallel time is the slowest shard's, which is worse
on asymmetric cores. The remedy is many small messages plus taking
unstarted ones (§4.1). A static partition into exactly n pieces is the
worst case.

Amdahl punishes coordination, not core count. This design keeps
coordination explicit and countable in the source, a hop being the one place
a core is named, so the serial term can be seen and shrunk. A shared heap
hides it in cache-coherence traffic.

### 4.11 How the types make it usable

Seastar's rules are conventions, and breaking one is undefined behaviour:
"don't touch another shard's object", "destroy on the home shard", "don't
let a continuation outlive its data" (read: Seastar tutorial, the
`foreign_ptr` section). Here each is a type error, and every proof erases.

**A key's home shard is in the type.** The type depends on the key:

```idris
||| A map split across n shards; the entry for key k lives on shard (place k).
export data Sharded : (n : Nat) -> (place : k -> Fin n) -> Type -> Type

lookup : Sharded n place v -> (key : k) -> Shard n (place key) (Maybe v)

get : {0 s : Fin n} -> Sharded n place v -> k -> Shard n s (Maybe v)
get m key = submit (place key) (lookup m key)
```

Calling `lookup` on an arbitrary shard `s` does not type-check, because the
rigid `s` does not unify with `place key`; the type forces the hop. Inside
code already running on `place key` it type-checks with no hop. This is
McBride's "at key" (read: `mcbride-2011-kleisli` §5) applied to placement.

**Lending that cannot dangle.** This is runST's region trick, with the
region on the join:

```idris
lend  : a -> ({0 l : Region} -> Lent l a -> Shard n s b) -> Shard n s b
forkL : (s' : Fin n) -> Shard n s' r -> Shard n s (Join' l n s r)   -- the join mentions l
```

- `b` cannot mention `l`, so neither the borrow nor any join that depends
  on it escapes the scope.
- `Join'` is linear, so every borrower is joined before `lend` returns.
- So the type proves the lender outlives every borrower.

**Purity is a determinism guarantee.** A forked computation with no world
inside is deterministic. The type says which parallel code may be compared
against one shard, or reordered.

**Bounds cost nothing.** Shard ids are `Fin n` for the runtime `n`. A
placement function returns `Fin n`, so an out-of-range shard is not
expressible, and `natToFinLT` carries its proof at quantity 0.

**Protocols between shards are session types.** A long-lived conversation
(a service shard and its clients) is Brady's Idris 2 session types:

- linear channel ends;
- each next message's type computed from the last;
- a `fork : ((1 chan : Server p) -> L ()) -> L {use=1} (Client p)` whose
  linear ends must both run to completion (read:
  `sources/papers/brady-2021-idris2-qtt/sessions.tex`).

A request/reply mismatch, or an abandoned conversation, is a compile error.
Such conversations need the coroutine path (§3.4), because a helping join
cannot serve a channel.

**What erases, and what is runtime.**

- Erased: the shard index on `Here`, `Shard`, `Join` and `Local`; `Here`
  itself (its layout is empty); every proof that a `Fin` is in range.
- Runtime: the `Fin` that selects a queue (an `i64` after narrowing; read:
  `findings/decision-nat.md`), `k`, and the bytes of the message.

Compile-time evaluation folds a closed placement function, never the core
count, which is IO.

### 4.12 Parallel loops

A loop over memrefs whose body counts nothing needs no detach.
**decision** It is tiled to `scf.forall` and lowered to a fork per shard,
then a join (`substrate.md` S6). The arrays go to every shard by pointer for
the duration of the join:

- the body touches no count, so the general `lent` permission of §4.3 is not
  needed;
- the elements are words, so their loads and stores are the only access;
- each tile writes its own slice.

The `counts-nothing` property, an `idr-expect` check today, becomes the
precondition the lowering checks.

## 5. The future

### 5.1 Which Idris future is the executor

None of the candidates is, as written:

| Candidate | Steal | Reject |
|---|---|---|
| `System.Future` (contrib) | nothing | a thread at `fork`, a mutex, and `forkIO` forging a world on it (read: `third_party/Idris2/support/chez/support.ss`, `blodwen-make-future`) |
| Chez threads, base's `System.Concurrency` | nothing | a second schedule on one heap |
| P2300 senders | A description that does nothing until started: `IO a` already is one, a function of the world (read: `libs/prelude/PrimIO.idr`). `when_all` becomes fork/join; `set_stopped` becomes destroying a task; the scheduler as data becomes a `Fin n` value. | a scheduler whose `start` is a pool, and a second algebra beside `IO` |
| Brady's indexed effects | the handler with its continuation is the executor; the index computed from the result is the completion; indices erase | the free-monad representation, a tree per bind at runtime |
| McBride's Kleisli arrows | the demonic bind: a hop whose destination the runtime chooses is a post-state the world picks | — |
| Lean's `Task` | the shape of pure fork/join | `markMT` and the tag test on every count |

**decision** The executor is the shard's reactor, and a future is a task
frame (§3). In the source a future has no type of its own: a waiting
computation is `IO` or `Shard n s`, and the compiler colours it. The
future-like values a user holds are `Join n s b`, which `fork` returns, and
a Rust `FutT` (§5.3).

### 5.2 Pending, the waker and an effectful completion

- **Pending** is a task paused at a command whose answer has not arrived.
  It is never a value in the source.
- **The waker is one word**, packing shard (8 bits), slot (24 bits) and
  generation (32 bits). It is stored as the `RawWaker`'s data pointer.
  - The vtable's clone is a copy, and drop does nothing.
  - Wake pushes the word onto the shard's wake queue and kicks.
  - There is no allocation and no count: that is the difference from
    Tokio's `Arc` (read: the scheduler post).
  - A wake for a finished task fails the generation check and is dropped.
- **An effectful completion** is the resume: the task continues with the
  answer and its shard's world, as Brady's handler calls `k` with the result
  and the new resource. The completion's type may compute the resource from
  the result, as Brady's `open` computes the file's state from the `Bool`.
  That is an index in the binding's type, and it erases.
- **Errors** are `Either`.
- **Cancellation** is destroying the task (§3.1): its cancel path drops what
  it owns, a `FutT` included.

### 5.3 `FutT` is a foreign value polled from inside our task

`Rust (FutT a)` is a counted foreign cell (proposal 0001 §9.1) holding a
pinned Rust future. The binding's `await` is a loop in a `wait` function:

1. poll through the shim with this task's waker;
2. on `Ready a`, return `a`;
3. on `Pending`, `idr.wait` for a wake of this slot, then poll again.

Rust futures need not be `Send`, because they never leave their shard. That
is stricter than Tokio's multi-thread runtime and looser than its `Send`
bound. `Waker` must be `Send + Sync`, and a one-word waker is.

### 5.4 What must exist before a Rust async import is honest

**Must exist**, all on one shard:

1. the task frame (§3);
2. the `wait` bit and tail await (§3.4);
3. one reactor with its wake queue, kick and platform wait (§4.8);
4. runtime-owned sockets and timers behind Rust's async I/O traits, because
   without an I/O provider a polled future can only compute (proposal 0001
   §12 names the traits);
5. the waker of §5.2;
6. cancellation as destroy.

**Can wait:**

- more than one shard, and hops;
- lending;
- taking unstarted messages;
- io_uring;
- compile-time evaluation of anything that waits (it never can: waiting is
  IO).

### 5.5 Where synchronous Rust stands before then

Proposal 0001 predates the `%foreign` decision of 2026-10-07: it spells
bindings as `%foreign "rust:..." "C:..."` over `GCPtr` with `onCollect`.

**decision** A bound Rust item is a runtime primitive generated from the
surface. `idris-mlir-bind` writes one registry entry per binding from the
same description as the shim, recognized by the definition's name and
origin, as base's foreign functions are (`substrate.md` S5.2).

- **The `%foreign` spec is a label**, the Rust path, which Idris needs on
  a primitive; nothing reads it, and a binding has no Chez or `C:`
  spelling.
- **A foreign cell's drop entry is the kind's release** in the counting
  walk. It is not a user finalizer, so `onCollect` stays refused in user
  code.
- **Calls run synchronously on the calling shard,** in world order. A call
  that blocks blocks that shard, which is what `read` does today.

Once a reactor exists, the manifest marks blocking items, and each becomes
a wait run on a runtime-owned offload thread that runs Rust only:

- the arguments are moved into Rust's ownership, which `IdrisValue: !Send`
  already enforces;
- the completion is posted to the shard;
- user code does not change, because the type was `IO` all along.

A blocking item that takes an Idris callback cannot be offloaded, because
the callback would run Idris code on a foreign thread. It stays inline.

## 6. The essential differences

| | Closure | Thunk | Task frame |
|---|---|---|---|
| Paused | before start | before start | mid-body, at a wait |
| State | captures | captures, then the value | live values at the wait (LLVM's spills) |
| Representation after defunctionalization | immutable sum; apply is a match | mutable memo sum; force is a match and a settle | LLVM coroutine frame (suspend index = tag, spills = fields) |
| Who runs it | the applier, synchronously | the forcer, synchronously | its shard's reactor, on a wake |
| Grade | any | ω: memo; `excl`: one-shot | linear (it holds the world) |
| Colours its caller | no | no | yes (`wait`) |
| Crosses shards | as a value: copied | as a value: copied (`Delayed`/`Forced`) | never |

Collapsing any column into another is a mistake:

- **A thunk is not a closure.** It has a memo, so one representation for
  both would put a state test in every apply.
- **A thunk is not a task.** Making it one makes every force a possible
  suspension, which colours pure code; or it gives every task a memo and a
  waiter list, which is Seastar's promise/future pair and Chez's mutex.
- **Frames must not cross.** That is what keeps `++count` plain. Every
  model in the corpus that let them cross paid an atomic or a collector.

The distinctions that were accidents, and go:

- the closure and the thunk sharing a cell layout (`Layout/PlaceClosures`);
- code pointers in the heap;
- the hand-written enter/done pair;
- one suspend against many (a generator is fusion's fallback);
- `Inf` against `Lazy`, which stay one type.
