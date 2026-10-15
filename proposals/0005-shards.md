# 0005: shards

**Status:** proposed, 2026-10-09, against `main` at 651156d4;
reprioritized 2026-10-12; reconciled 2026-10-14 with 0004's pipeline
cutover and with 0006. Nothing here is built, run or timed. Its
Decisions section is decided: D1 is the user's, and D2 to D12 were pinned
on the user's delegation by the rule that single-thread performance wins
the tie ("Rules it keeps"); D13 follows from AGENTS.md.
They stand until the user changes them; no question is left open. The
tree it builds on is the cutover 0002 designed, committed and building
on arm64 macOS: `make build` clean, `make check` 27/27, `make test-idr`
286/286, `make test` 415/415 (*measured* 2026-10-14 at `NCPU=6`, at
552d682a and its file-size split df5d8742, on the rounds, the default;
the opt-in SCC pipeline of 552d682a ran in one lit test only, and 0004
deletes it). x86_64 Linux has not run this tree (0002's G1 is NotRun
there), so P2's epoll half targets a system that has not yet run it.

Sharding follows 0003's stage 1, which follows self-hosting: P1, P2
and P4 are that work, in order. 0006's S0, S1 and S2's first step are
taken by 0004's cutover, before any of it. The compiler's own Idris
half runs on these shards too, by the owner's decision (0006 §5.4, §12):
single-threaded until this framework exists, then on its shards from
stage 1 of `make self`; stage 0 runs on Chez and stays single-threaded.
P3 (asynchronous Rust) is parked with proposal 0013, which it needs. P5
stays on its measurements. Runtime and compiler paths were re-read at
3de67510 on 2026-10-14 and again at ccaba89c, where the code is
unchanged; `M/` and `L/` are the pinned MLIR and LLVM trees under
`.toolchain/build/llvm-project/`, and `SDK/` is the macOS SDK the
pinned clang compiles against on arm64 macOS, the one `xcrun
--show-sdk-path` names (`tools/bootstrap.sh:190`; here
`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`). Claims are
marked: read, measured, recalled, conjecture, decision.

The runtime today runs the program on one runner thread with a
reserved stack, and "one runner runs at a time in a process" (read:
`runtime/idris_rt.h:436-461`). This proposal makes it
many copies of that runtime, one per core, each with its own heap, world
and plain counts, and adds the one thing a copy lacks: a way to pause in
the middle of a computation and be resumed by an event. It is the
concurrency runtime as one design: the task frame, the reactor, shards,
what crosses between them, and the Rust future polled on the reactor.
It holds the concurrency design, the shard decisions and the shard
work.

## What it changes

Each move names the data that changes and the branches it deletes.

- **A computation paused at a wait is a task frame** (§2). Data: LLVM's
  switched-resume coroutine frame behind our cell header, linear, owned by
  a shard's task table; one more effect bit, `wait`. Deleted: any notion
  of a waiting thunk, and a second scheduler. A program that never waits
  lowers as today.
- **Each shard runs a reactor** (§3). Data: a task table, a run queue, an
  MPSC wake queue and one platform waiter behind the runtime's platform layer (`runtime/Platform/Platform.h`). Deleted:
  the one process-wide runner; there is one per shard.
- **A shard is one more copy of the single-threaded runtime** (§4, D1).
  Data: the heap, world, top-level constant cells, handle table and output
  buffer become per shard. Deleted: every question of which thread may
  touch a count, since the answer is always the owner.
- **Values cross only inside messages** (§5, §7). Data: `idr.fork`, an
  `IsolatedFromAbove` region whose operands are the message, and
  `!idr.join<T>` at grade `(1, own)`. Deleted: any pointer from one
  shard's heap into another's.
- **A top-level constant is a `Static i` cell** (§6, D6). Data: one more
  state in a memo sum, an immutable cell in static data naming slot `i` of
  the running shard's constant table. Deleted: the process-wide memo cell
  written at run time, so static data becomes immutable without
  exception, and the detach walk needs no case for static thunks.
- **Rust futures are polled from our task frames** (§10). Data: `Rust
  (FutT a)` as a counted foreign cell, a one-word waker. Deleted: any Rust
  runtime.
- **The library's operations are runtime primitives** (§7.1, D13). Data:
  registry entries keyed by name, with no Idris body. Deleted: a second,
  sequential meaning of each operation written in Idris.

## Rules it keeps

- **Both targets, one design.** The waiter is one operation behind
  the platform layer: kqueue on arm64 macOS, epoll on x86_64 Linux (§3). No
  inline assembly, so frames are stackless coroutines from LLVM's
  intrinsics (§2.4).
- **What Idris proved stays in types.** The join is `!idr.join<T>` at
  `(1, own)`, the shard index is a quantity-0 index on the surface types,
  a lent value is a grade (§5.3), and a frame holds the quantity-1 world.
  No fact of this design lives in a discardable attribute.
- **A linear binder does not imply unique heap ownership.** The detach
  walk consults the count and idr-rc's last use, never quantity (§5.1).
- **No threads, no `%foreign`.** Base's `fork`, `threadWait` and
  `System.Concurrency` stay `unsupported (threads)` (read:
  `compiler/src/IdrisMLIR/Registry/Recognized.idr:150-151`, `threads`).
  Parallelism is `libs/mlir-shard`'s structured fork: five runtime
  primitives beyond base's, as `mlir-linear`'s string iterator declares
  three (`libs/mlir-linear/Linear/String/Iterator.idr:27-29`,
  `%extern`), and the rest plain Idris over them (§7.1, D13).
- **No oracle.** One set of expected files serves every core count (D8).
- **Single-thread performance wins the tie** (the user's, 2026-10-09).
  A cost that appears only
  when a program uses more than one shard is acceptable; a cost on a path
  a single-shard program runs is not, unless it is free there too. Every
  decision below that trades the two says so.
- **Reject what cannot compile.** A value that may not cross is
  `unsupported (send)`, naming the type and the path to it (§7.3).
- **Static linking.** No piece of this is loaded at run time.
- **No option selects behaviour** (0004 D2). `IDRIS_RT_SHARDS` is the
  program's resource, as `IDRIS_RT_STACK` is (read:
  `runtime/idris_rt.h:436-447`): a program whose output its joins
  order prints the same at every count (D8). The compiler gains no
  flag: whether a program waits or forks is in its code and its types.
- **Acceptance is a property of the program** (0004 §1). The one
  refusal this design adds to the C++ side, `unsupported (send)`, reads
  only the sums the whole-program label solve decides before the
  optimizer (§7.3).

## The design

### 1. Three suspended objects

A suspended computation is one of three objects, and the difference is
where it was paused.

| | Closure | Thunk | Task frame |
|---|---|---|---|
| Paused | before start | before start | mid-body, at a wait |
| State | captures | captures, then the value | values live at the wait (LLVM's spills) |
| Representation | immutable sum; apply is a match | memo sum; force is a match and a write | LLVM coroutine frame: suspend index = tag, spills = fields |
| Who runs it | the applier, synchronously | the forcer, synchronously | its shard's reactor, on a wake |
| Grade | any | ω: memo; `excl`: one-shot | linear (it holds the world) |
| Colours its caller | no | no | yes (`wait`) |
| Crosses shards | as a value: copied | as a value: copied | never |

Closures and thunks are done: defunctionalization makes
them sums (read: `foreign/idr/lib/Transforms/Defunctionalize/Pass.cpp`,
`foreign/idr/lib/Conversion/Force.cpp`), and after 0004's cutover it
does so for every closed, monomorphic program, by analysis alone (0004
§2.4). So every value a message can hold has a sum type, a fact this
design's send check reads (§7.3). This proposal adds the third.
The line falls where the data is known: a thunk's paused state is its
captures, known in MLIR; a task's is the values live across a wait, known
exactly only after optimization, so LLVM's CoroSplit computes it. An LLVM
coroutine frame is a defunctionalized continuation, so one rule,
"suspended computation is data", is applied at the level where the data
exists.

Collapsing two columns is a mistake:

- **A thunk is not a task.** Making it one makes every force a possible
  suspension, which colours pure code, or gives every task a memo and a
  waiter list (Seastar's promise/future pair, Chez's mutex).
- **Frames do not cross.** That is what keeps `++count` plain. Every model
  read that let them cross paid an atomic or a collector (§4.1).

The handler is the executor. Brady's `handle` holds a continuation and
answers a command (read: `sources/papers/brady-2014-resource-effects`
§3.1); McBride's interpreter "follows one path in the tree... taking the
edge determined by reality" (read: `sources/papers/mcbride-2011-kleisli`
§7). The task frame is the continuation compiled, CoroSplit is the CPS
transform, and a shard's reactor is the handler. Pending is a frame
paused at a command nobody has answered yet.

### 2. The task frame

#### 2.1 What it is

A task frame is a computation paused at a wait: a socket or timer
event, a Rust future that returned `Pending`, or a join inside a
function that waits for one of those (§2.4).

**decision** It is LLVM's switched-resume coroutine, emitted by idr-lower
as `llvm.intr.coro.*`. Every coroutine intrinsic it needs is an op of
the pinned LLVM dialect, `coro.alloc`, `coro.destroy` and `coro.done`
included, and `coro.await.suspend.handle`, the symmetric transfer tail
await uses (read:
`M/include/mlir/Dialect/LLVMIR/LLVMIntrinsicOps.td:938-1072`), so none
goes through `llvm.call_intrinsic`. This supersedes the earlier claim
that those three were missing. CoroSplit and CoroElide already run
in our pipelines, because `buildPerModuleDefaultPipeline(O3)`
(`foreign/idr/lib/Target/Optimize.cpp:44-59`) includes every coroutine
pass: CoroEarly in the module simplification, CoroElide in the function
simplification, CoroSplit in the inliner's CGSCC pipeline, CoroCleanup
after it (read: `L/lib/Passes/PassBuilderPipelines.cpp:1023, 685, 915,
1194`). `buildCoroWrapper` (`:320`), cited before, is the O0 form. Each
codegen unit's own O3, at 0004 §5.4's second step, runs the same passes.

In MLIR the wait is `idr.wait`, a terminator with two successors:

- **resume**, where the task continues with the answer and the next
  world;
- **cancel**, where its live owned values are dropped.

`async.coro.suspend` has that shape (read: `AsyncOps.td`,
`Async_CoroSuspendOp`); the async dialect is out for the reasons under
"Rejected alternatives". Because the cancel successor consumes the
live owned values, idr-rc places their drops there as it places any drop,
and the frame's destroy function is the cancel path CoroSplit outlines.

#### 2.2 Layout and ownership

The frontend gives the frame its memory (`coro.alloc`, `coro.begin`), so
our header goes in front of it:

```
cell ─► [count | info]   the runtime header: kind task
         handle ─► [resume ptr][destroy ptr][promise][index, spills ...]   LLVM's layout
```

The frame layout is LLVM's (read: `CoroFrame.cpp`, `buildFrameLayout`),
and the promise's offset is fixed by its alignment alone (read:
`CoroEarly.cpp`, `lowerCoroPromise`). The promise holds the task's slot in
its shard's task table, its awaiter (the slot to wake when it finishes)
and its result.

A task frame is linear: its count is always 1 and never tested. The task
table owns it while it is suspended and the running reactor while it is
resumed. Its own final cleanup frees it, or `coro.destroy` when it is
cancelled. Counting never frees it, so the free walk never meets one.

#### 2.3 What the construct really requires

- **Resuming a running or finished coroutine is undefined** (read:
  `llvm/docs/Coroutines.md`, `llvm.coro.resume`). Only the owning reactor
  resumes, and only a task its table holds as suspended.
- **A save precedes an operation that may complete before the suspend
  returns** (read: `Coroutines.md`, `llvm.coro.save`). That is true on one
  thread: register a wait with the reactor, then suspend. What this design
  excludes is a resume from another thread (§3.3).
- **Only the coroutine itself suspends.** Every caller of a function that
  may wait, up to the reactor, is a coroutine too: colouring (§2.4).
- **Not required:** a stable frame ABI across LLVM releases. A program is
  compiled whole by one pinned LLVM, its codegen units (0004 §5) and the
  runtime's bitcode together, so no frame crosses a compiler boundary.

#### 2.4 Colouring, decided by the compiler, avoided where it can be

Stackful frames would not colour, but they need a stack switch: inline
assembly (excluded) or `makecontext`, which musl does not ship. So the
compiler colours, as little as it can.

**decision** The effects fact gains one more bit, `wait`, beside `io`,
`crash` and `diverge` (read: `foreign/idr/include/idr/Transforms/Passes.td:16-43`,
`#idr.effects<io, crash, diverge>`) and the observable-output bit 0004
adds (0004 D34). After 0004's cutover the effects are one bottom-up SCC
summary, callee first: first computed right after the label solve, over
the call graph in which an apply calls every label of its key, then
recomputed once per function when it is final, which can only shrink it, with the call-site `effects` cache
written once from it (0004 §4 stages 4 and 9, D16, D34). `wait` is one
more bit of that summary, never a second analysis, and it shrinks as the
others do: inlining and cleanup can remove a wait and never add one.
idr-lower reads the final bit. It is computed like the others from the
primitives that wait: sockets, timers and sleep, and Rust `await`. A
join adds no bit: in a function that waits for something else it lowers
to `idr.wait`, and in any other it is the helping join (below), so the
join never decides the colour.
This supersedes the earlier "the join of a fork that must interleave
with other tasks", whose "must" no analysis decided. Since 0004 runs
defunctionalization before the optimizer, a closure's effects reach its
caller through the direct calls of its dispatch, with no closure case
(0004 §2.7). Only `wait` functions are lowered as coroutines. The world
stays the quantity-1 token with no runtime components.

**The helping join.** A join in a function that waits for nothing else
does not colour it. While its reply has not arrived, it runs the work that
arrives on its own shard, on its own stack, then returns. Structured
fork/join cannot deadlock under it: a forked computation cannot depend on
its forker's continuation, since the only channel back is the reply, and
the stack grows by the depth of nesting, as recursion would.
**conjecture**: every parallel program in `bench/` is of that form and
runs with no coroutine at all.

**Tail await.** `idr-tail-loops` turns self tail calls into a loop inside
one frame. A tail call from one waiting function to another is a tail
await: the callee's frame takes over the caller's awaiter, the caller's
frame is destroyed, and the callee is resumed by a `musttail` call. That
is C++'s symmetric transfer on switched-resume, and it keeps the
constant-stack promise. idr-lower writes it as
`coro.await.suspend.handle`; CoroSplit lowers that to a call through the
returned frame's resume address (read:
`L/lib/Transforms/Coroutines/CoroSplit.cpp:124-145`) and marks the call
`musttail` where the target supports a tail call for it (`:1079-1086`).
The call is indirect, through the frame, so it has no static callee for
0004's partition to keep beside it: 0004 joins every direct `musttail`
caller to its callee and lets none cross an object (0004 §5.3 item 4,
D33), and an indirect call reaches a function in any object. **decision**
P1's proof includes a tail await on both targets, within one bin and
across two bins of a generated program larger than two bins, 10^7 times
in constant stack. This supersedes the earlier "rests on the check 0004
already owes", since 0004 now keeps every direct `musttail` inside one
unit.

### 3. The reactor

#### 3.1 A shard's runtime

Each shard is a runtime thread holding:

- a reserved stack with a guard and its own `sigaltstack`, one runner per
  shard instead of one per process (read: `runtime/idris_rt.h:448-461`,
  `idris_rt_run_on_stack`, whose "one runner runs at a time in a
  process" P4 lifts);
- a snmalloc allocator, already per thread;
- its constant table (§6);
- a task table of (slot, generation);
- a run queue;
- an MPSC wake queue, snmalloc's own shape;
- one platform waiter.

A program that never waits and never forks starts no reactor and runs as
today.

#### 3.2 The platform wait

The waiter is one operation behind the platform layer, which already
keeps every difference between Linux and macOS in one function of
`Platform/Posix` chosen by the target's macros (read:
`runtime/Platform/Platform.h:3-8`); the waiter is one more such
function:

| Target | Waits on | A post wakes it with |
|---|---|---|
| arm64 macOS | `kqueue`/`kevent` (read: `sources/papers/lemon-2001-kqueue`) | `EVFILT_USER` with `NOTE_TRIGGER` (read: `SDK/usr/include/sys/event.h:77, 199-205`; it postdates the paper) |
| x86_64 Linux | epoll | an eventfd |

A post pushes, then kicks the waiter only if the reactor has set its
about-to-sleep flag. A turn of the reactor:

1. drain the wake queue into the run queue;
2. resume ready tasks until the run queue is empty;
3. flush the shard's output (D3), then wait.

A resumed task does not block (read: `sources/papers/belay-2014-ix`
§4.1; Seastar tutorial). The standard streams are the exception, decided
in D3: the batch programs this compiler is measured on read standard
input in a loop, making that a wait would colour every one of them, and a
blocking read stalls only the shard that reads.

#### 3.3 What a foreign thread may touch

**decision** A foreign thread (a Rust thread, a blocking offload thread)
may push a token onto a shard's wake queue and kick it, use memory that
is not an Idris cell, and free raw blocks remotely through snmalloc (read:
`idris_rt.h`, "free a block from any thread"). It may not resume a frame,
force a thunk, read or write a count, hold a reference to an Idris cell,
or hold a world.

### 4. The shard

#### 4.1 Why a heap per core

Plain `++count`, and reuse at count 1, need one thread touching a cell's
count at a time. Three ways keep that, differing in the ownership domain:

| Domain | Model | What it costs |
|---|---|---|
| the whole heap | M:N work stealing (Go, Tokio, Lean tasks) | Any cell may be counted by any thread. Go traces (read: `sources/docs/go-scheduler/gc-guide.html`). Tokio pays an `Arc` per task and per wake (read: `sources/docs/tokio/scheduler-2019-10.html`). Lean walks the graph with `markMT` before each task and tests a tag on every count (read: `sources/papers/ullrich-2019-counting-immutable-beans/threadsafety.tex`); Koka's `tshare` is the same (read: Perceus TR §2.7.2). Biased counting splits every count (read: Choi et al. PACT 2018 §4.1). |
| one task | M:N with a heap per process (Erlang) | Every message between tasks is a copy, even on one core (read: `sources/papers/johansson-2002-heap-architectures` §3). |
| one core | thread-per-core (Seastar) | Tasks on one core share cells freely with plain counts; crossing a core copies or moves (read: `sources/docs/seastar/tutorial.md`). |

**decision** A heap per core. Idris shares immutable data everywhere,
implicitly; a heap per task would turn every value two tasks see into a
copy, and a heap per core makes the common case free. The weakness is
balance, on asymmetric cores most of all; D9 decides it.

snmalloc fits this exactly: it is built for objects "deallocated by a
different thread than the one that had allocated them" (read:
`sources/papers/lietar-2019-snmalloc`, abstract), with a thread-local
fast path and remote frees returned in batches through one MPSC queue per
allocator (read: the same paper, §2.2). Almost every allocation and free
stays on its shard; a
message detached on one shard and freed on another is the batched remote
path.

#### 4.2 Amdahl

The speedup is 1 / ((1 − p) + p/n). Three things move work into the
serial term, and each has its remedy here:

1. **Contended counts on shared read-only data.** On a shared heap n
   readers of one structure bounce its headers between cores. Here a copy
   avoids it at a cost, and a lend at none (§5.3).
2. **Distribution and collection on one coordinator.** k forks from
   shard 0 are k detach walks in series. Fan out as a tree, let workers
   make their own data (as binary-trees does), or lend.
3. **Imbalance.** The parallel time is the slowest shard's. Many small
   messages, placed by queue depth, and taking unstarted ones (D9).

A hop is the one place a core is named, so the serial term is visible in
the source and can be shrunk. A shared heap hides it in coherence
traffic.

### 5. What crosses, and who owns it

#### 5.1 The detach walk

**decision** A message is detached on the sending shard before it is
enqueued, in one walk of the counted graph it reaches:

| Cell | Treatment | Why it is sound |
|---|---|---|
| count 0 (persistent), including a `Static i` constant (§6) | sent as the same pointer | persistent data is immutable and points only at persistent data; the receiver forces its own slot `i` |
| count 1, reached only through moved cells, at a send that consumes the sender's last reference (idr-rc decides) | moved: the pointer is the message | nobody else can reach it; the receiver's free is snmalloc's remote free |
| count above 1, or a stack cell (an `idr.con` whose stack placement is an inherent property after 0004, D19) | copied into a fresh count-1 cell; a forwarding map keyed by address, holding only cells of count above 1, keeps the DAG's sharing | the sender keeps its aliases and drops them on its own shard: Erlang's copy without Erlang's collector (read: `sources/papers/clebsch-2017-orca`, "when data structures are immutable") |
| a thunk, `Forced` | copied with its value | a value |
| a thunk, `Delayed` | copied unforced; its captures are walked | forcing it to send it could diverge where the program would not, and the memo is not semantics |
| a thunk, `Running` | impossible | a thunk runs only on its own shard's stack, inside its force |
| a runtime handle | sent as the integer it is | an operation on it hops to its home shard (D4) |
| a `Local` | sent as the integer it is | a slot of its home shard's table; its home is a quantity-0 index of its type, so only code typed for that shard can use it (§7.1, §7.2) |
| a stream whose memo sum can hold `pipe_next` | never sent | a pipe has one consumer (D7); the send check rejects it |
| a task frame, a world, `Here`, a mutable cell, a `Join` | never sent | the send check rejects it (§7.3); a task frame has no type in the source, so no value holds one, and a join stays with its forker, which is what makes the fork structured (§7.1) |

The cells a copy makes are allocated by the sender's allocator and owned
by the receiver: one owner at a time, with frees going home as remote
frees. The live-cell counter is per thread (read:
`runtime/Alloc/Cells.cpp:17`, `thread_local liveCells`), so the
zero-live-cells property is checked on the sum over shards at exit.

#### 5.2 Placement

Placement is a runtime value, a `Fin n` a library computes, so a library
can choose the least-loaded shard. A message nobody has started owns a
detached graph, so an idle shard may take it without breaking one owner
at a time; a started frame cannot migrate, since its cells are on its
shard's heap.

#### 5.3 Lending

Copying costs serial work on the sender. The alternative for large
immutable inputs is a lend:

- a structured fork guarantees the lender keeps the value alive until it
  joins;
- the borrower receives it at a new permission, `lent`, beside `borrow`,
  `own` and `excl`;
- idr-rc lowers a `dup` at `lent` to a deep copy into the local heap, and
  a `drop` at `lent` to nothing;
- forcing a `Delayed` thunk reached through a lent value copies it first.

"This value lives on another shard's heap" is a grade, where no pass can
lose it. Marshall and Orchard's fractional uniqueness is the theory of the
split (read: `sources/papers/marshall-2024-fractional-uniqueness`). The
lent grade has no count operations at all, which removes Amdahl's item 1.
D10 decides when it is built.

### 6. Top-level constants per shard

A top-level constant is evaluated at most once per shard that demands it
(D6). Today there is one memo cell per process, because a constant
stream's tail is a static thunk referenced from static data, and a
thread-local address is not a link-time constant (read:
`foreign/idr/lib/Conversion/StaticData.cpp:246-257`, a memo cell is a
writable `__idr_caf_` global where every other cell is constant, and
`:72`, `@__idr_release_cafs`).

**decision** The indirection is a state of the memo sum, not a test
beside it:

```
memo K = Delayed_L1 caps1 | ... | Delayed_Ln capsn
       | Running
       | Forced v
       | Static i            -- only in keys that have a top-level constant
```

- **Static data holds `Static i`**, an immutable persistent cell naming
  slot `i` of the shard's constant table. Every reference to the
  constant, from code or from static data, is that cell.
- **Each shard's constant table is one `thread_local` global** whose
  initial image is the templates, `Delayed_L caps` with persistent
  captures. The loader gives every shard its copy at no cost to the
  compiler. Under 0004's codegen units it is one definition in one unit,
  referenced from the others as an external hidden `dso_local` symbol
  with its content-derived name under the reserved `__idr.` prefix (0004
  §5.3 item 3), so every unit reaches it the same way; today's memo
  cells are `__idr_caf_` made unique by the symbol table in insertion
  order (`foreign/idr/lib/Conversion/StaticData.cpp:189-191, 246-247`),
  a name 0004's content naming replaces (0004 D18).
- **The force's match gains one arm:** `Static i -> force slot i of the
  running shard's table`. Only keys that have a top-level constant have
  it, as only pipes have `pipe_next` (D7). Which keys those are is the
  label solve's: a top-level constant's suspension names its label and
  declares its edge through 0004's flow interface (0004 D8), so the keys
  it reaches are known when the sums are decided, and `Static i` is one
  more constructor of those sums, never a test beside them.
- **A shard's end releases its table's forced slots**: the compiler-made
  release function, run per shard.

What goes: the memo cell written at run time in static data, so static
data is immutable without exception; and
the detach walk's case for static thunks, since `Static i` is persistent
and crosses as the same pointer. No pointer to a slot ever escapes a
force, so a slot is never sent. The cost on one shard is the arm and a
thread-local address on a top-level constant's force; D6 states the
measurement it must pass.

### 7. The surface and the hop

#### 7.1 `libs/mlir-shard`

**decision** A new in-house package. Its five operations (`runShards`,
`fork`, `join`, the `Local` cells, `pipe`) are runtime primitives of the
registry, keyed by name, with no Idris body, as `mlir-linear`'s string
iterator's are (`libs/mlir-linear/Linear/String/Iterator.idr:27-29`,
`%extern`); everything else in it is plain Idris over them and over
base. Their one meaning is the runtime's (AGENTS.md: "No primitive has
an implementation in Idris"). 0003 D37 goes the other way for arrays,
because base already holds the primitives `LArray` needs; no base
primitive lies under a fork or a join. Their
sequential reading is their specification, never code: a fork runs its
computation to completion at once, a join returns the stored result, a
`Local` is an `IORef` in a table, and for pure work the runtime's
meaning equals that reading (D2). This supersedes the earlier "read as
written, its definitions are ordinary sequential IO", which gave each
operation a second meaning in Idris that differs from the runtime's
wherever forked effects interleave (D13). Everything else in the package
(`io`, `pure`, its bind, `submit`, `forAll`, `Sharded`) is ordinary
Idris over those primitives; `lend` and `forkL` join the primitives when
D10 builds lending.

**decision** A `Local` is a word at run time: a slot of its home shard's
table of local cells, as a runtime handle is a slot of its shard's
handle table (D4). So it crosses as the integer it is, which is what
makes it Pony's `tag`, and its cells never leave their heap. Its home is
the quantity-0 index `s`, erased (§7.2), so no runtime check could read
it; the types are what keep a use on the home shard (`getLocal` needs
`Shard n s`). This supersedes the earlier send-check case for "a
`Local` whose index is not the destination", which read an index the
compiler erases.

```idris
module Shard

||| Being on shard s of n: linear, so no closure can carry it elsewhere,
||| and empty at runtime, as %World is. The index is quantity 0.
export data Here : (n : Nat) -> (0 s : Fin n) -> Type

||| IO on shard s. Bind threads Here as io_bind threads %World.
export data Shard : (n : Nat) -> (0 s : Fin n) -> Type -> Type

export io   : IO a -> Shard n s a
export pure : a -> Shard n s a

||| The runtime starts S k shards (IDRIS_RT_SHARDS, else the processor
||| count) and runs the body on shard 0. n is a runtime value.
export runShards : ((k : Nat) -> Shard (S k) FZ a) -> IO a

||| Start p on s' and return at once. The join is linear, so every fork
||| is joined: concurrency is structured.
export fork : {n : Nat} -> {0 s : Fin n} -> (s' : Fin n) -> Shard n s' b -> Shard n s (Join n s b)
export join : (1 _ : Join n s b) -> Shard n s b

||| A hop: fork and join.
export submit : {n : Nat} -> {0 s : Fin n} -> (s' : Fin n) -> Shard n s' b -> Shard n s b

||| State that lives on one shard: Pony's `tag`, sendable and opaque,
||| usable only on its home shard. Its cells live until that shard ends.
export data Local : (n : Nat) -> (0 s : Fin n) -> Type -> Type
export newLocal : a -> Shard n s (Local n s a)
export getLocal : Local n s a -> Shard n s a
export setLocal : Local n s a -> a -> Shard n s ()

||| Evaluate a stream on s' for one consumer here (D7).
export pipe : (s' : Fin n) -> (ahead : Nat) -> Stream a -> Shard n s (Stream a)
```

A user writes:

```idris
main : IO ()
main = runShards $ \k => do
  input <- io getLine
  rs <- forAll (allFins k) $ \s' => fork s' (pure (solve s' input))
  io (printLn (sum rs))
```

`forAll` forks all, then joins all. The waker packs the shard in 8 bits
(§10.2), so `runShards` caps the count at 256.

#### 7.2 What the types make impossible

Seastar's rules are conventions whose breach is undefined behaviour
(read: Seastar tutorial, the `foreign_ptr` section). Here each is a type
error, and every proof erases.

- **A key's home shard is in the type.**

  ```idris
  export data Sharded : (n : Nat) -> (place : k -> Fin n) -> Type -> Type
  lookup : Sharded n place v -> (key : k) -> Shard n (place key) (Maybe v)
  get : {0 s : Fin n} -> Sharded n place v -> k -> Shard n s (Maybe v)
  get m key = submit (place key) (lookup m key)
  ```

  `lookup` on an arbitrary `s` does not type-check, since the rigid `s`
  does not unify with `place key`; the type forces the hop. This is
  McBride's "at key" (`mcbride-2011-kleisli` §5) applied to placement.
- **Lending cannot dangle.** runST's region trick, with the region on the
  join:

  ```idris
  lend  : a -> ({0 l : Region} -> Lent l a -> Shard n s b) -> Shard n s b
  forkL : (s' : Fin n) -> Shard n s' r -> Shard n s (Join' l n s r)
  ```

  `b` cannot mention `l`, and `Join'` is linear, so every borrower is
  joined before `lend` returns.
- **Purity is determinism.** A forked computation with no world inside is
  deterministic, and equal to the sequential reading of §7.1.
- **Bounds cost nothing.** Shard ids are `Fin n` for the runtime `n`;
  `natToFinLT` carries its proof at quantity 0.
- **Protocols between shards are session types**: Brady's linear channel
  ends whose next message's type is computed from the last (read:
  `sources/papers/brady-2021-idris2-qtt/sessions.tex`). Such a
  conversation needs the coroutine path, since a helping join cannot
  serve a channel.

Erased (quantity 0, so no value of the module): the shard index on
`Here`, `Shard`, `Join` and `Local`, and every proof that a `Fin` is in
range. `Here` is linear, so it is a value of the module with no runtime
component, as the world is; the send check therefore sees its type
(§7.3). Runtime: the `Fin` that selects a queue (an `i64` after Nat
narrowing), `k`, and the message's bytes. Static normalization folds a closed
placement function of total code (0007), never the core count, which is
IO.

#### 7.3 The hop in MLIR and the send check

**decision** A fork is an `idr.fork` region op, `IsolatedFromAbove`,
whose operands are the message: the destination shard as an `index`, and
the captured values. "No use-def chains may cross the isolation barriers"
(read: `sources/papers/lattner-2020-mlir/ir_design.tex`), so no pass can
thread a value of one heap into another: crossing is an operand, and an
operand is a message.

- The grid is upstream's `shard.grid @cores(shape = ?)`, whose size may
  be a runtime value (read: `M/include/mlir/Dialect/Shard/IR/ShardOps.td:31`,
  `Shard_GridOp`), and the running shard is `shard.process_linear_index`
  (`:140`).
- The result is `!idr.join<T>` at `(1, own)`.
- idr-lower outlines the region, detaches the operands (a runtime call),
  posts a function pointer and the detached operands, and lowers
  `idr.join` to `idr.wait` (§2.1) or to the helping join (§2.4).
- A fork to the running shard is a call (read:
  `sources/docs/seastar/smp.hh`, `submit_to` of `this_shard_id()`).
- **decision** `idr.fork` and `idr.join` implement 0004's one flow
  interface (0004 D8): a closure or lazy operand of the fork reaches the
  region argument it binds, and the region's yield reaches the join's
  result. So the label solve follows a closure into the forked work
  with no case of its own, and the verifier, which refuses a closure- or
  lazy-typed operand on an op without the interface, admits the fork.
  The region is written isolated by the frontend, its operands already
  the message, so there is no outlining round trip of the kind 0004
  deletes with `idr-isolate` (0004 §4 stage 1). The calls inside the
  region are edges of the enclosing function in upstream's `CallGraph`,
  which attributes a call nested in any region that is not a callable to
  the enclosing callable (read: `M/lib/Analysis/CallGraph.cpp:74-97`), so
  0004's ready set orders the forked work's callees before the forker.
  That is why the fork keeps a region where 0004 gives closures the
  symbol form (0004 §4.1): a function named by an op that is no call is
  an edge the call graph does not see, the gap 0004 §2.7 closes for
  closures by making every apply a direct call, and a fork made a call
  would be a call the inliner had to be told not to inline. Its region
  lives until idr-lower outlines it, which is lowering, not a round
  trip.

The frontend cannot check sendability: closure sums do not exist before
idr-defunctionalize, and `Send` is not an interface a user should
implement. **decision** The send check runs once, right after
defunctionalization's conversion (0004 §4 stage 4), as a whole-program
read of the decided sums, in the stage where 0004 already computes the
first effects summary (0004 D34). There every type is first-order, so one
walk of the types an `idr.fork`'s operands and result reach sees every
path a message can take. It rejects a mutable cell (`IOArray`, `IORef`,
`Buffer`), a world, `Here`, a `Join`, and a lazy key whose memo sum can
hold `pipe_next`. The walk is one more question of the type graph that
`Holds` already answers per declaration ("may hold a world", "may hold a
closure", two bits computed once and read from any thread; read:
`foreign/idr/include/idr/Analysis/Holds.h:3-6, 19-30`): a third bit,
"may hold what may not cross", so the type graph is walked by one
analysis, never by a second one of the send check's own. The rejection
is `unsupported (send)`, naming the type and the path, as structured
data on the diagnostic that the driver reads (0004 §6 deletes the
driver's match on the message prefix). After the check, `idr.fork`'s
verifier keeps what it established: an operand whose type may hold
what may not cross is a broken invariant, and a pass that makes one is
an internal error (0004 §2.5). The check is not part of the conversion,
which accepts every verified module (0004 §2.4). This supersedes two
earlier forms: "part of `CapturingOpInterface`'s isolation", since no
such interface exists (read:
`foreign/idr/include/idr/IR/IdrInterfaces.td:40, 61, 91`, which defines
`MayCrashOpInterface`, `GuardOpInterface` and `ConsumingOpInterface`) and
the flow interface is where 0004 puts closure flow; and "a verifier rule
in force from the stage after defunctionalization", since 0004 makes a
verifier failure after a pass an internal error, never `unsupported`
(0004 §2.5), so a user's refusal cannot be one.

Whether a fork is accepted is a property of the program, never of the
optimizer: the sums the check walks are the label solve's, decided on
the whole program before the optimizer runs and total by analysis (0004
§2.4, §2.7). Their precision is 0CFA's: a label that reaches a fork's
type but never its value at run time is still walked. **decision**
Acceptance is judged on the 0CFA sets 0004 freezes. A change of
precision (MLton's polyvariance, which 0004 does not build) changes
which programs are accepted, so it is a language change, in a proposal
of its own judged by acceptance, never by 0004 D35's bench rule, which
judges speed (0004 D35 says the same). A runtime handle is an integer
and passes. A linear array (0003's `LArray`, §3.8 there) is exclusive by
type, born fresh and leaving only by `freeze`, so it moves; sending an
array and getting it back is the data-parallel case.

### 8. Parallel loops

A loop whose body counts nothing needs no detach. Which loops are
parallel, and how they are tiled, is 0003's (§14 there): at 0003's
stage 8, which needs P4, a parallel dimension of a structured generic
is tiled to `scf.forall` by the tile-and-fuse schedule (0003 §14, D27,
D29; the schedule itself lands at 0003's stage 3).
**decision** This proposal lowers an `scf.forall` to a fork per shard
and a join, and it is the one lowering of `scf.forall` (0003 §14).
`shard.grid` supplies only the grid and the running index (§7.3). The
arrays reach every shard by pointer for the duration of
the join: the body touches no count, its elements are words, and each
tile writes its own slice, so the general `lent` grade is not needed.
**decision** The `counts-nothing` property, an `idr-expect` check today
(read: `foreign/idr/include/idr/Transforms/Passes.td:769-800`,
`counts-nothing=@f`), becomes an assertion the lowering makes, never a
choice between lowerings: 0003's structuring makes an `scf.forall` only
from a body that counts nothing (0003 §5, §14), so a forall whose body
counts is a broken invariant and an internal error (0004 §2.5). It
goes neither through `async-parallel-for` nor `convert-scf-to-openmp`,
each a second runtime.

### 9. Streams across shards

A lazy stream is a cons cell whose tail is an `Inf` thunk: a memo sum
forced with plain writes and plain counts. D7 decides how one stream
lives on two shards; the mechanisms are §5.1 (by value) and the pipe:

- **Representation.** A ring of `ahead` slots in memory that is not an
  Idris cell (§3.3), a head and a tail index, a closed flag, and a wake
  token for each side. The two indices are the only atomics: the side
  that advances one stores it with release, the other loads it with
  acquire.
- **Producer.** A fork on `s'` owns the stream. It forces the next
  element, detaches it (a fresh element is at count 1, so it moves and its
  pointer is the slot), and pushes it. A full ring parks the producer's
  task.
- **Consumer.** Its stream is the ordinary memo sum with one more label,
  `pipe_next ring`, whose force pops one slot and memoizes
  `x :: pipe_next ring` as any force memoizes. An empty ring blocks the
  consumer shard, since pure code cannot wait. It does not help as a join
  does: another task on the shard could reach the same thunk while it is
  `Running`.
- **Lifetime.** Releasing the last `pipe_next` thunk closes the ring. The
  producer sees the flag at its next push, drops its stream and ends, and
  the runtime joins it. Elements still in the ring are freed by the
  release and go home as remote frees.

The consumer's forces, counts and memo stay plain, and no other thunk
changes; the cost is the label's arm in the force's switch, and only
pipes have it.

### 10. Async Rust on the reactor

#### 10.1 The executor is the reactor

**decision** The executor is the shard's reactor, and a future is a task
frame. A waiting computation is `IO` or `Shard n s`, and the compiler
colours it; a future has no type of its own in the source. The
future-like values a user holds are `Join n s b` and a Rust `FutT`. What
the alternatives lend: P2300's description that does nothing until
started (`IO a` already is one, read: `libs/prelude/PrimIO.idr`), with
`when_all` as fork/join and `set_stopped` as destroying a task; Brady's
handler as the executor, with indices that erase; Lean's `Task` as the
shape of pure fork/join.

#### 10.2 Pending, the waker, completion

- **Pending** is a task paused at an unanswered command. It is never a
  value in the source.
- **The waker is one word:** shard (8 bits), slot (24 bits), generation
  (32 bits), stored as the `RawWaker`'s data pointer. Clone is a copy,
  drop does nothing, and wake pushes the word onto the shard's wake queue
  and kicks. No allocation and no count, unlike Tokio's `Arc`. A wake for
  a finished task fails the generation check and is dropped.
- **An effectful completion** is the resume: the task continues with the
  answer and its shard's world, as Brady's handler calls `k` with the
  result and the new resource. The completion's type may compute the
  resource from the result, an index that erases.
- **Errors** are `Either`. **Cancellation** is destroying the task: its
  cancel path drops what it owns, a `FutT` included.

#### 10.3 `FutT`

`Rust (FutT a)` is a counted foreign cell (proposal 0013 §9.1) holding a
pinned Rust future. The binding's `await` is a loop in a `wait` function:
poll through the shim with this task's waker; on `Ready a`, return `a`;
on `Pending`, `idr.wait` for a wake of this slot, then poll again. Rust
futures need not be `Send`, since they never leave their shard; `Waker`
must be `Send + Sync`, and a one-word waker is.

Before a Rust async import is honest, one shard needs the task frame,
the `wait` bit and tail await, a reactor with its wake queue, kick and
platform wait, runtime-owned sockets and timers behind Rust's async I/O
traits (proposal 0013 §12 names them), the waker, and cancellation as
destroy. More shards, lending, taking unstarted messages and io_uring can
wait. Static normalization covers only total, pure code (0007); waiting
is IO, so nothing that waits is normalized.

#### 10.4 Blocking calls offloaded

Synchronous bindings are generated runtime primitives that run on the
calling shard, in world order (proposal 0013 §9.2). Once a reactor
exists, the manifest marks blocking items in its `[blocking]` table,
which arrives with P3 (0013 §5), and each becomes a wait run on
a runtime-owned offload thread that runs Rust only: the arguments move
into Rust's ownership (`IdrisValue: !Send` already enforces it), the
completion is posted to the shard, and user code does not change, since
the type was `IO` all along. A blocking item that takes an Idris callback
stays inline: the callback would run Idris code on a foreign thread.


### Lessons from Swift's concurrency model

Swift reached data-race safety in a shared-memory language step by step.
Its evolution proposals are stored under `sources/docs/swift-evolution/proposals/`.
The send check here answers the same question per message, not per thread:
- **`Sendable`** (0302): a type-level "may cross". It is what our send check
  is.
- **Region-based isolation** (0414) and **`sending`** (0430) let a
  non-Sendable value cross when the compiler proves its whole region is
  disconnected from the sender. That is the precise form of a move: a value
  the sender's ownership grade proves exclusive crosses without a copy,
  because nothing on the sender can reach it.

  Decision: the send check accepts a value at the exclusive grade as a
  move, and its region goes with it. That is the same fact 0009's packed
  layout relies on. Everything else crosses by copy, as decided above.
- **Noncopyable types and `borrowing`/`consuming`** (0377, 0390, 0427):
  ownership added to a language after the fact. Idris's quantities have
  had this from the start; Swift shows where the ergonomics need help.

## Staged plan

Each stage runs AGENTS.md's checks on both targets. P1, P2 and P4 are in
order; P3 follows P2 and can run beside P4; each item of P5 waits on its
measurement.

**P1. Task frames and the `wait` bit** (§2).

- **Change:** `idr.wait`; the `wait` bit in 0004's one effects summary
  (§2.4); coroutine lowering of `wait` functions only; tail await as
  `coro.await.suspend.handle`.
- **Proof:**
  - a waiting loop of 10^7 iterations runs in constant memory;
  - two waiting functions that tail-await each other 10^7 times run in
    constant stack, on both targets, in one bin and in two bins of a
    generated program larger than two bins (§2.4);
  - a program that never waits lowers to IR byte-identical to the
    binary's before P1, compared binary against binary (0004 D22);
  - the colouring measurement of D11 passes.

**P2. One reactor** (§3, §10.2).

- **Change:** the task table, wake queue and kick; kqueue with
  `EVFILT_USER` and epoll with eventfd behind the platform layer; sleep;
  same-shard fork and join.
- **Proof:** two tasks' sleeps overlap; a post from a foreign thread
  wakes a sleeping reactor; both targets.

**P3. Asynchronous Rust** (§10). After P2.

- **Change:** the `FutT` loop, the one-word waker, runtime sockets and
  timers behind Rust's I/O traits, and the blocking offload, driven by
  the manifest's `[blocking]` table (0013 §5, §10.4).
- **Proof:** a hyper client and server on one shard against their
  committed expected files; cancellation frees the Rust future
  (`IDRIS_RT_LIVE=1` reports zero); a crate graph enabling tokio's `rt`
  is rejected (D12).

**P4. Shards** (§4 to §9).

- **Change:** `libs/mlir-shard`, its operations registry primitives
  (D13), `Local` a word naming a slot (§7.1); `idr.fork` and `idr.join`
  with 0004's flow interface; `shard.grid`; the send check right after
  defunctionalization, as `Holds`' third bit, and the detach walk
  (§7.3, §5.1); the helping join; the standard streams on every shard
  and handles hopping home (D3, D4); process state under the platform
  lock (D5); `Static i` and the per-shard constant tables (D6);
  `scf.forall` lowered to fork and join (§8); and, approved by the
  owner as D1 already is, the two sentences of AGENTS.md this design
  amends, in the same change: the `%foreign` paragraph's "as threads"
  narrowed to threads that share one heap (base's `fork`, `threadWait`
  and `System.Concurrency` stay outside, D1), and the `libs/` sentence
  admitting a package's own runtime primitives beside base's, which
  `mlir-linear`'s string iterator already has (D13).
- **Proof:**
  - every shard fixture at `IDRIS_RT_SHARDS=1` against its expected
    files, and at more shards against the one-shard run (D8);
  - a reject fixture for each `unsupported (send)` path;
  - zero live cells summed over shards at exit;
  - D6's measurement passes;
  - from 0004 §5.4's second step, D11's cross-unit frame count recorded
    beside the bench;
  - parallel binary-trees, spectral-norm and mandelbrot measured against
    one shard, with D9's idle-time record.

**P5. On a measurement.** Each is built when its rule is met, and not
before:

- lending (§5.3), by D10;
- taking unstarted messages (§5.2), by D9;
- pipes (§9), by D7;
- io_uring submission behind the waiter's operation, when P3's hyper
  server at saturation spends more than a quarter of its time in
  readiness and transfer system calls;
- SPMD through upstream's `shard-partition`, after pure array programs
  are tensors (`proposals/0003-typed-apl/README.md` §14): it replaces
  P4's `scf.forall` lowering whole, never beside it, when
  spectral-norm's best of five is more than 2% faster with it on both
  targets (0004 §10's runtime margin; 0003 D35, D36), and the change
  that takes it names what lowers its collectives, since 0003 rejects
  `ShardToMPI` (0003 §18).

## Rejected alternatives

- **M:N work stealing on one heap** (Go, Tokio, Lean tasks): every count
  becomes atomic, tagged or traced, paid by every single-threaded count
  (§4.1).
- **A heap per task** (Erlang): every value two tasks on one core see
  becomes a copy (§4.1).
- **Stackful coroutines:** inline assembly, or `makecontext`, which musl
  does not ship (§2.4).
- **A thunk as an LLVM coroutine:** a thunk is never paused mid-body, so a
  coroutine with no inner suspend adds a null test on every force (read:
  `sources/papers/peytonjones-1992-stg` §3.1.2) and a frame MLIR cannot
  see. The compiler makes it a memo sum instead.
- **The async dialect:** a second reference count and a pool beside ours,
  an error channel the language does not have, no operand that says where
  an `async.execute` runs, and an await that blocks a reactor outside
  coroutines.
- **contrib's `System.Future`:** a thread at `fork`, a mutex, and
  `forkIO` forging a world (read: `third_party/Idris2/support/chez/support.ss`,
  `blodwen-make-future`); it is contrib and `%foreign`, and `Lazy` under a
  parallel name.
- **Base's `System.Concurrency` and Chez threads:** a second schedule of
  effects on one heap. They stay `unsupported (threads)`.
- **A P2300 scheduler whose `start` is a pool,** and a second algebra
  beside `IO` (§10.1).
- **Brady's effects as a free monad at runtime:** a tree per bind; the
  handler survives as the reactor.
- **A hop returning `At n s (On n s' a)`:** it leaves shard `s` holding a
  pointer into shard `s'`'s heap. Long-lived remote state is a `Local`
  (§7.1).
- **A foreign thread's post that only publishes:** it must also wake a
  reactor asleep in the kernel (§3.2).
- **io_uring as the wait:** it is commonly disabled under container
  seccomp profiles (recalled). It is a later submission path behind the
  same operation (P5).
- **A resume from a foreign thread** (§3.3). The `llvm.coro.save`
  requirement is real on one thread and is kept (§2.3).
- **A Rust future as our coroutine handle:** rustc compiles a future into
  its own state machine, a foreign value; the frame that polls it is ours
  (§10.3).
- **A tokio island** on threads of its own (proposal 0013 §3).
- **Tokio's `Arc` waker:** an allocation and an atomic count per task
  and wake, where one word does (§10.2).
- **The standard streams as waits:** it colours every batch program that
  reads standard input in a loop (§3.2).
- **The library's operations as Idris definitions** whose sequential
  bodies the compiler replaces: a second meaning of each primitive in
  Idris (D13).
- **The send check as a verifier rule:** after a pass a verifier failure
  is an internal error, never a user's refusal (0004 §2.5); the check
  runs once after defunctionalization and the verifier keeps its result
  (§7.3).
- **A walk of its own for the send check:** the type graph already has
  one analysis, `Holds`, and the check is its third bit (§7.3).
- **A `Local` checked against the destination when it is sent:** its
  index is quantity 0 and erased, so nothing at run time could read it;
  it crosses as the integer it is and its types keep its uses home
  (§7.1).
- **A join as a source of the `wait` bit:** whether a join must
  interleave is no fact an analysis decides; it lowers by the colour its
  function already has (§2.4).
- **A partition that keeps a coroutine with its callers,** so that
  elision works across codegen units: a branch in a pure function of
  content (D11).
- **A generator coroutine,** one frame suspended many times, as a
  representation of streams: a pure language fuses producer and consumer
  instead (the contiguous-runs work). It would reuse P1's lowering
  if fusion leaves a benchmark that needs it, and is not part of this
  proposal.

## Decisions

### D1. One world per shard (the user's, 2026-10-09)

A shard is a runtime thread with its own heap, its own world, plain
counts, its own top-level constant cells, its own handle table and its
own output buffer. Only that shard touches any of them. Values cross
shards inside messages, by move, copy or lend (§5). This amends the
decision that threads are outside the language (AGENTS.md), whose "one
world" becomes one per shard. What it excludes stays excluded: base's `fork`,
`threadWait` and `System.Concurrency` start a second schedule of effects
on one heap and are `unsupported (threads)`. Parallelism is
`libs/mlir-shard`'s structured fork, whose join is linear.

This is Seastar's model applied to the whole runtime: "Any sharing of
resources across cores must be handled explicitly... one CPU must
explicitly forward the request to the other" (read:
`sources/docs/seastar/shared-nothing.html`).

### D2. Effects are causally ordered

Effects on one shard happen in program order. Across shards, everything a
shard did before it posted a message (a fork, a join's reply, a hop)
happens before everything the receiver does after it takes the message.
Effects no message orders interleave, and each is whole: a `putStr` is
never split by another shard's output, and a line read goes to one
reader. Messages between two shards arrive in the order they were posted,
since a wake queue is an MPSC queue that keeps each producer's order
(read: `sources/papers/lietar-2019-snmalloc` §2.2). Fork-join of pure
work is deterministic and equal to the sequential run its definitions
describe.

### D3. The standard streams work on every shard

- **Output: a buffer per shard.** Each shard writes standard output into
  a buffer of its own, as the single-threaded runtime does today (read:
  `runtime/Io/Output.cpp`, one 4 KiB buffer a flush writes). No lock is
  on the write path. A flush writes the whole buffer with one `writeAll`
  under the descriptor's lock, so two shards' flushes never interleave,
  whatever the descriptor is: POSIX makes a pipe write atomic only up to
  `PIPE_BUF`, 512 bytes on macOS (read:
  `SDK/usr/include/sys/syslimits.h:104`).
- **A shard flushes** when its buffer is full; before it blocks (a read, a
  blocking hop, its reactor going to sleep); before it posts any message;
  and at its end. Flushing before a post makes output causal: shard A's
  line is in the kernel before shard B can act on A's message.
- **Standard error** is written unbuffered today (read:
  `runtime/Io/Ending.cpp`, `writeAll(2, ...)`), so each write is one
  `writeAll` under standard error's lock.
- **Input belongs to shard 0,** with the single-threaded runtime's buffer
  (read: `runtime/Io/Input.cpp`) and no lock on shard 0's read path. A
  read on another shard is a blocking hop to shard 0: the reader flushes
  its output (so a prompt precedes the read), posts the request, and
  blocks until shard 0 replies with the line, the bytes or the end.
  Requests are served in arrival order, so lines go to readers whole.

Rejected: one process-wide output buffer behind a lock, or a write call
per `putStr`, each a cost on every single-shard write; all output owned
by shard 0, which makes every other shard's write a message and puts
shard 0's work in front of every line, for the causal order per-shard
buffers give without either; one process-wide input buffer behind a
lock, which locks shard 0's every read.

### D4. Files and directories

Each shard has its own handle table (read: `runtime/Io/Handles.cpp`,
one table per process today). A handle stays an `int64_t`; slot `i` on
shard `k` carries `k` above bit 47, so shard 0's handles are today's
numbers. `0`, `1` and `2` are the standard streams on every shard (D3),
and `-1` is null. An operation on a handle whose home is another shard
is a blocking hop to its home, which performs it and replies, so a file
opened on one shard can be sent as the integer it is and used or closed
on another. A string the runtime keeps (an environment value, a
directory's last entry) is a slot of the calling shard's table. A
single-shard program pays one compare per file operation, beside a
system call.

A blocking hop is a runtime request, not a task: the wake queue's entry
says which. While a shard waits for a hop's reply it serves the handle
and input requests other shards post to it, and runs no task. So two
shards hopping to each other's handles cannot deadlock, and no user code
interleaves with the blocked one.

### D5. Process state

The environment and the current directory belong to the process, as the
kernel and the C library have them. The platform layer serializes
`getenv`, `setenv`, `unsetenv`, `getcwd` and `chdir` with one lock: C
does not let `getenv` race `setenv` (recalled), and these calls are rare.
A relative path resolves against the directory current at the call.

`exitWith`, or a crash, on any shard ends the process: that shard flushes
its output, writes its message and exits with its status. Output causally
before the exit is already written (D3); output another shard buffered
concurrently may be lost, as any effect concurrent with an exit may not
happen. At a normal end `runShards` has joined every fork, and every
join's reply flushed its worker, so every line is out.

### D6. Top-level constants are per shard

A top-level constant is evaluated at most once per shard that demands it,
in that shard's slot (§6). With one shard it is evaluated once, as today.
Whether a closed call of total code becomes such a constant is 0007's
cost rule, and 0007 computes it at its first demand, never at startup
(0007 §2, D3). This decision is only that the shard which demands the
constant computes it. A `trace` in a top-level constant prints once per
shard that forces it. This amends the reason a static constant
memoizes, that a top-level constant names one value evaluated once:
once per shard, not once.

Rejected: one process-wide cell per constant, forced once behind a
once-guard. The forced value is then reachable from every shard, so it
would have to be persistent, never counted and never freed ("from
persistent values, we can only reach other persistent values"; read:
`threadsafety.tex`), and every thunk inside it would need a force that
tests whether it is shared, on the single-shard path.

**Measurement.** The force through `Static i` is a thread-local address
on a single-shard path (**conjecture**: a few instructions; on Mach-O a
thread-local variable is reached through a descriptor). Rule: the lazy
programs of `bench/` at `IDRIS_RT_SHARDS=1` are no more than 2% slower,
best of five, than the binary before P4, run beside it under identical
conditions on each target (0004 §10, D22; 0003 D35 measured the
five-run spread at up to 97%, so a spread bounds nothing). P4 does not
land until they are.

### D7. Streams across shards

A stream lives on one shard, and only that shard's code forces its
cells: every stream, finite or infinite, is single-reactor. That is what
is supported, and the reason is that a memo is a plain write
(single-thread performance wins the tie).

- **By value: supported.** A send detaches a stream as any value (§5.1):
  the forced prefix is copied with its values, the unforced tail as its
  label and captures. Afterwards each shard has its own stream and forces
  it alone. An infinite stream crosses in time proportional to its forced
  prefix and its captures; elements both shards force are computed twice.
  Nothing changes on one shard.
- **A shared memo over atomics: not supported.** One thunk every shard
  sees needs an atomic state, a force that knows whether its thunk is
  shared, and counts on everything the forced value reaches that two
  shards can drop. Every way to have them costs the single-shard path or
  adds a second counting regime: a tag tested on every force and count
  (Lean's `markMT`, whose test "does not require any synchronization" but
  is still paid by every single-threaded force; read:
  `threadsafety.tex`); persistent values, never freed, so an infinite
  stream forced without end is memory without end; or atomic counts on a
  kind of cell of their own, a second reference count beside ours.
- **A pipe: the one cross-shard stream, with atomics only in its ring**
  (§9). Its specification, the sequential reading of D13, is
  `pipe s' k xs = pure xs`, so the consumer sees
  the same values deterministically, and only where and how far ahead
  they are computed changes. A pipe has one consumer, so the send check
  rejects any value whose lazy keys can hold `pipe_next`. It needs P1,
  P2 and P4. **Measurement:** it is built when a program in `bench/`
  spends at least a quarter of its one-shard time in the forces of one
  stream drained by one consumer, the least share at which a two-stage
  pipeline saves a quarter of the run.

### D8. Tests

One set of expected files serves every core count. Every fixture runs at
`IDRIS_RT_SHARDS=1` against its expected files. A program whose output is
causally ordered (it prints after its joins, or its prints are ordered by
them) is deterministic at any count and runs at more shards against the
one-shard run. A program whose output has concurrent writes is checked at
one shard only.

### D9. Asymmetric cores

`runShards` starts one shard per processor (`IDRIS_RT_SHARDS` overrides
it) and pins none: macOS offers no core affinity on Apple silicon, only
QoS classes (recalled), and an affinity on Linux alone would be a
per-target case. A library places work by queue depth (§5.2).
**Measurement:** on 8 performance and 4 efficiency cores, P4 records,
for parallel binary-trees, spectral-norm and mandelbrot at 12 shards, the
time shards spend idle at their last join. Taking unstarted messages is
built when that idle time exceeds a tenth of shards × wall time in any of
them.

### D10. Copy or lend

Copy is built first (P4); `lent` is a grade and a scoped surface, built
when the copy costs. **Measurement:** for k-nucleotide's sequence and
spectral-norm's vector at 8 shards, the time the coordinator spends in
detach walks. Lending is built when it exceeds 5% of wall time, the
serial share at which Amdahl caps 8 shards at 5.9×.

### D11. The cost of colouring

The helping join keeps fork/join uncoloured (§2.4), so colouring is paid
only by functions that really wait. **Measurement:** P1's proof runs a
loop of 10^7 calls to a `wait` function whose wait completes at once, and
counts the frames allocated. The threshold is zero frames per call after
CoroElide. If our lowering lets the handle escape, our lowering is fixed;
if CoroElide misses a case it should take, the case is reduced and fixed
in LLVM, as AGENTS.md requires.

Elision inlines the coroutine's ramp into its caller, so it needs both
bodies in one LLVM module. After 0004's cutover a program is several
codegen units (0004 §5). At 0004 §5.4's first step O3 still runs on the
whole module before the split, so elision crosses bins; from its second
step each unit runs its own O3 with no importer of bodies from another
unit (0004 D21). So from the second step the fixture runs twice: caller
and callee in one unit, and in two (a generated program larger than two
bins, as for tail await, §2.4). **decision** The threshold of zero holds
at the first step and within a unit at the second. Across two units at
the second step elision is impossible by construction, the frame is allocated
from the shard's size-class fast path (§3.1), and the per-call count is
recorded beside the bench. Reason: making the partition keep a
coroutine with its callers would be a branch in a pure function of
content (0004 §5.3, 0006 D4), and the idr-level inliner already inlines
a small wait function before idr-lower makes it a coroutine (0004
§4.7). If the recorded cross-unit count shows on a bench program's
runtime by more than 2%, best of five (0004 §10), the fix is reduced to LLVM as above or made
in our lowering, never in the partition.

### D12. Which Rust crates work

The rule is computed per crate graph, not listed: a crate works when its
graph enables none of tokio's `rt`, `net` or `time` features, and is
generic over the async I/O traits the runtime implements (hyper 1.x, h2,
`tokio-postgres` over a provided stream, the AWS SDK with a provided
connector; recalled). The generator rejects any other graph as
`unsupported (rust async)` (proposal 0013 §12). P3's fixture is a hyper
client and server.

### D13. The library's operations are runtime primitives

`libs/mlir-shard`'s `runShards`, `fork`, `join`, `Local` cells and
`pipe` are runtime primitives of the registry with no Idris body, as
`mlir-linear`'s string iterator's are (§7.1). Their
sequential reading is their specification: for pure work the runtime
meets it exactly (D2), and where forked effects interleave the runtime's
causal order is the meaning. Reason: AGENTS.md gives a primitive one
meaning, the runtime's, and an Idris body beside it would be a second
meaning that differs wherever effects interleave. Consequence: no
program runs these operations on a host without this runtime, Chez
included, which AGENTS.md already says no feature is shaped for. The
compiler's own Idris half is therefore single-threaded until these
shards exist and then runs on them, from stage 1 of `make self`; stage
0, on Chez, stays single-threaded (0006 §5.4, §12, the owner's
decision).
