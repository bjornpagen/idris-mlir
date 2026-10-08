# Scheduler: upstream `System.Future` and the Rust executor

Upstream `System.Future` is not sufficient for the Rust interop proposal's
executor. This compiler should not implement it as Chez does, and snmalloc
does not justify a multithreaded runtime. A foreign thread may post a
wakeup to the thread that owns the world. That thread resumes. The foreign
thread does not force a thunk and does not share the reference-counted
heap. A later multi-shard design, if one is ever proposed, is explicit
worlds, one world per shard. A pure `Future a` that hides threads would
require changing `findings/decision-threads-pointers.md`. This note leaves
that decision as it stands.

`System.Future` lives in contrib. Contrib is no commitment
(`AGENTS.md` 43–49, `findings/decision-inhouse-linear.md` 8–10). **read.**
The prelude names `fork` and `threadWait` are already refused. The
question here is the proposal's later async line
(`proposals/0001-rust-interop.md` §12 and §14 R5), not a coverage gap.

## What upstream `Future` is

**read** `third_party/Idris2/libs/contrib/System/Future.idr`:

- `fork : Lazy a -> Future a` (16–18) and `await : Future a -> a` (20–22)
  are pure. Neither takes `IO` or a world.
- `pure v = fork v` (30), so the `Applicative` instance starts the same
  primitive for a value that is already computed.
- `performFutureIO` maps `unsafePerformIO` over a `Future (IO a)` (38–40).
  `forkIO` is `performFutureIO $ fork a` (42–44).

The primitives are `%foreign "scheme:blodwen-make-future"` and
`"scheme:blodwen-await-future"` (10–14).

**read** `third_party/Idris2/support/chez/support.ss` 518–533.
`blodwen-make-future` allocates a record `(result ready mutex signal)` and
calls `fork-thread`. The new thread runs `work`, then under the mutex
stores the result, sets ready, and broadcasts. `blodwen-await-future`
takes the mutex and `condition-wait`s until ready, then reads the result.
The work starts when `fork` is called, on that thread, not when `await`
demands the value.

**read** Chez Scheme User's Guide, Thread System,
<https://cisco.github.io/ChezScheme/csug/threads.html> (fetched 2026-10-07;
the bench lock is Chez 10.4.1, `bench/README.md` 30). The thread system is
pthreads except for locks and locked increment and decrement.
`fork-thread` invokes its thunk in a new thread. A thread created by
foreign code must call `Sactivate_thread` before it touches Scheme data.
That is entry into the Scheme heap, not a post that leaves the heap alone.

**read** `third_party/Idris2/support/racket/support.rkt` 483–484.
Racket's support is `(future (lambda () (work '())))` and `(touch future)`.
Same shape: the work is handed to the future runtime, and await blocks in
`touch`. The comment at 486–489 is about Racket's green threads blocking
the runtime on a foreign call. It is a second concurrency mechanism, still
not a post back to an owner.

Prelude `fork` / `threadWait` are a different API and the same fact.
**read** `third_party/Idris2/libs/prelude/Prelude/IO.idr` 125–140:
`prim__fork` is `%foreign "scheme:blodwen-thread" "C:refc_fork"`, and
`blodwen-thread` also `fork-thread`s (`support.ss` 310–313). This compiler
refuses those four names with `unsupported (threads)`. **read**
`compiler/src/IdrisMLIR/Registry/Recognized.idr` 121–127,
`compiler/src/IdrisMLIR/Rule.idr` 24–26,
`compiler/src/IdrisMLIR/Frontend/Profile.idr` 51. `System.Future` is not in
that table. Its primitives are still `%foreign` with no registry hook, so a
reachable use is `unsupported` naming the foreign. **read**
`compiler/src/IdrisMLIR/Frontend/Profile.idr` 252–261,
`findings/decision-threads-pointers.md` 32–40.

## What this runtime is

**read** `runtime/idris_rt.h` 33–34: counts are plain arithmetic because a
program is single-threaded. `idris_rt_inc` is `++cell->count` when the cell
is counted (`runtime/Rc/Counting.cppm` 13–18). Live cells are
`thread_local` so the count is not a data race, and the comment says a
program has one thread (`runtime/Alloc/Cells.cppm` 15–18,
`runtime/idris_rt.h` 235–238).

**read** `runtime/Start/Entry.cppm` 133–146: `idris_rt_start` checks the
page size and the CPU, then runs the program body. The body runs on a
reserved stack (`runtime/idris_rt.h` 340–354). The stack runner creates one
pthread and joins it before returning (`runtime/Platform/Posix/Stacks.cppm`
30–44). One runner at a time (`runtime/Start/Runner.cppm` 16–18). That
pthread is the program's stack. It is not a pool, and it does not run a
second schedule of effects.

**read** `foreign/idr/include/idr/IdrOps.td` 143–146: the world is the IO
token `!idr.world`, quantity 1. Every IO op writes `idr.io`, so a pass
cannot reorder it with other IO (`foreign/idr/include/idr/Idr.h` 56–60).
A trusted `unsafePerformIO` forges a world (`idr.world.new`) that orders
that chain; between chains, the effects order the ops
(`IdrOps.td` 1379–1385, `findings/decision-inhouse-linear.md` 36–42).
User `unsafePerformIO` stays `unsupported (world)`
(`findings/decision-threads-pointers.md` 44–47). Effects of a trusted
library happen where the value is demanded, in program order with every
other effect (`AGENTS.md` 50–53).

**read** `runtime/idris_rt.h` 139–141 and `findings/decision-nat.md` 84–91:
a heap reference this compiler keeps is the cell's address, with no tag
bit. `findings/decision-threads-pointers.md` 8–16: the heap is a dag of
immutable values plus mutable cells that one world orders. A second thread
is a second world writing the same cells. Counting cannot see that, and
the world's order does not sequence it. There is no scheduler and no
shared-memory model to add one later without replacing that heap.

A suspension cannot capture a world. **read**
`foreign/idr/lib/Dialect/Ops/Lazy.cc` 188–190.

## Conflicts with the proposal's executor

The proposal's v1 already excludes a tokio island and a Rust thread that
calls into Idris (`proposals/0001-rust-interop.md` 128–135, 584–596).
**read.** §12 (798–824) is the later line: once the runtime "grows its own
futures (an Idris-side executor over the platform's completion I/O)", a
Rust future imports as `Rust (FutT a)`, the executor polls it, and the
`Waker` vtable "pushes the Idris task back onto its run queue". A `Waker`
may be woken from any thread, and "the wake is a post to the owning
thread". I/O traits are implemented over the runtime's sockets and timers.
Crates that call `tokio::spawn` are rejected. R5 (887) waits until that
executor exists. §8.5 (595–596) says a thread-per-core runtime would keep
Idris values on their core.

`System.Future` supplies none of that surface, and its meaning contradicts
the constraints the proposal says it keeps.

1. **A pure type starts a thread.** `fork` and `await` have no world.
   Chez runs the thunk at `fork`, on a pthread, and `await` blocks the
   caller on a condition variable (`support.ss` 519–533). The decision's
   reason is a second schedule of effects (`decision-threads-pointers.md`
   8–13), which is this, whether or not the name is `Prelude.IO.fork`.
   Demand-order evaluation of a trusted effect
   (`AGENTS.md` 50–53) is the opposite timing: the work runs where the
   value is demanded, on the thread that holds the world.

2. **`forkIO` hides `unsafePerformIO` on the worker.** The IO action runs
   inside `map unsafePerformIO` (`Future.idr` 38–44), on the forked thread,
   not on the caller's `!idr.world` chain. A suspension here cannot even
   capture a world (`Lazy.cc` 189–190). Two OS threads do not become ordered
   by `idr.io` side effects. User code cannot write `unsafePerformIO`; a
   trusted library's forged world still runs where the value is demanded,
   in program order. `forkIO` runs the effect on the other thread before
   `await` returns, concurrently with whatever the caller does.

3. **The result cell is shared mutable state.** Chez's future record is
   written by the worker and read by the awaiter under a mutex
   (`support.ss` 518–533). This runtime's counts have no atomic and no
   mutex (`Counting.cppm` 13–18). Ullrich and de Moura treat a task as a
   different kind from a thunk, and they retag the reachable graph before
   the task is created, because plain reference counts are not safe to
   share. See below. Sharing the RC heap with `fork-thread` replaces the
   heap the decision says counting depends on.

4. **The waker is inverted.** §12's foreign thread posts, and the owning
   thread later polls and resumes. Chez `await` blocks the owner until the
   worker has finished running Idris code. The worker is the one inside
   the heap. Chez's own manual says a foreign thread must
   `Sactivate_thread` before it touches Scheme data (CSUG, Thread System,
   URL above). That is the call the proposal's §3 excludes: Rust calling
   into Idris from another thread.

5. **There is no poll, no completion I/O, and no `FutT`.** `Future a` is
   an external type (`Future.idr` 7) with block-until-ready. It does not
   import a Rust future, it does not implement `AsyncRead` over the
   runtime's sockets, and it does not reject `tokio::spawn`. Using it as
   §12 would also be a second representation of "a value available later":
   a contrib future beside `Rust (FutT a)`.

6. **`pure` and `(>>=)` start threads.** The monad instance is `fork` of
   `await` (`Future.idr` 25–36). An executor that polled those binds would
   create a pthread per bind. §12's continuation runs on the shard that
   owns the task.

## Thunk versus task

**read** Peyton Jones, *Implementing lazy functional languages on stock
hardware: the Spineless Tagless G-machine*, JFP 2(2), 1992,
`sources/papers/peytonjones-1992-stg/paper.pdf` §3.1.2–3.1.3 (printed
135–137). A thunk is a closure for a computation that has not been
evaluated. Forcing it enters it. The self-updating model overwrites the
thunk with its value, in place, when evaluation finishes. A black-hole
code pointer catches re-entry. The same overwrite is how the paper handles
concurrent threads: on entry the code pointer becomes `queue-me`; a second
thread that enters before the update is suspended on a queue attached to
the thunk; the update re-enables that queue. The second thread waits on
the thunk. The thunk does not become a task that runs on a pool. Forcing
is still entering the closure.

**read** Ullrich and de Moura, *Counting Immutable Beans*, IFL 2019,
`sources/papers/ullrich-2019-counting-immutable-beans/`. The value header's
kind is one of `ctor`, `pap`, `array`, `string`, `num`, `thunk`, or `task`
(`array.tex` 1–12). `Task.mk : (Unit -> α) -> Task α` runs the closure in
a separate thread (`threadsafety.tex` 1–14). Thread-safe reference counting
with fences on every decrement was measured by them to hurt the
single-threaded case, so they tag values single-threaded, multi-threaded,
or persistent, and `markMT` walks the single-threaded graph reachable from
the closure before the task is created (`threadsafety.tex` 16–64). Every
later inc/dec tests the tag. A task is not a thunk, and making one share
the heap is a walk plus a test on every count. This runtime's header has
no such tag (`idris_rt.h` 26–39) and `idris_rt_inc` does not test one
(`Counting.cppm` 13–18).

**read** Bhat and Grosser, *Lambda the Ultimate SSA*, CGO 2022,
`sources/papers/bhat-2022-lambda-ultimate-ssa/paper.tex` 1076–1079. Lean's
published pipeline lowers a strict IR to C; "task-based parallelism" is
one of the features "provided by a custom runtime library, `libleanrt`".
It is not an SSA construct. The source's commented lazy discussion
(1028–1066) describes thunks as promises the consumer forces, and as an
optimization barrier, and that discussion is not in the published body.
The published sentence is the one that matters here: a task runtime beside
the IR is a second implementation of "run this later".

This compiler's laziness is the thunk, on the thread that forces it.
**read** `foreign/idr/include/idr/IdrOps.td` 584–610: `idr.suspend` builds
a cell and does not run the function; `idr.force` is the value, computed
on the first force and shared. **read** `Lazy.cc` 1–16: a suspension with
one use is the call, at the force. **read**
`foreign/idr/lib/Lower/Runtime.cppm` 257–331: the cell's code pointer is
`enter` until the first force stores the value and overwrites it with
`done`; a persistent suspension is noted with `idris_rt_lazy_kept`
(`runtime/idris_rt.h` 218–223, `runtime/Rc/Counting.cppm` 51–61) so main's
return can drop the memo. That enter/done pair, the `ForceOfOneUse` and
`ForceOfOneConstant` rewrites, and `idris_rt_lazy_kept` are the homegrown
thunk. They are replaced by one MLIR construct on the forcing thread.
They are not kept beside a task runtime, and `System.Future` is a task
runtime.

## snmalloc is the allocator

**read** `third_party/snmalloc` is the submodule (`.gitmodules`).
`runtime/Alloc/Classes.cppm` 1–4 and 31–40: every `idris_rt_alloc` /
`idris_rt_free` entry is `snmalloc::alloc` / `snmalloc::dealloc`. After LTO
the fast path is a thread-local free-list pop. The x86_64 Linux target
enables CMPXCHG16B because snmalloc needs it (`CMakeLists.txt` 164–167).
`runtime/idris_rt.h` 175–177: allocate from the calling thread's heap; free
a block from any thread.

**read** `third_party/snmalloc/README.md` 7–16. Same-thread free needs no
synchronising operation. A free from another thread takes no lock; it
sends the block back to the allocating allocator by message passing, and
many remote frees become one atomic. That message is a batch of blocks.
It is not a program continuation, not a memory ordering for a counted
cell, and not a place to run Idris. **read**
`foreign/idr/bench/alloc/README.md` 64–69: the bench's explanation of the
cross-core rows is that remote free, `dealloc_local_objects_fast` in
snmalloc's `corealloc.h`. Those rows measure the allocator. They do not
measure a scheduler. The proposal's one-allocator plan
(`proposals/0001-rust-interop.md` 709–716) is this contract: Rust's
`#[global_allocator]` calls `idris_rt_alloc` / `idris_rt_free`, and a raw
block may be freed from any thread. A counted cell is not a raw block.

## Seastar

Fetched 2026-10-07. **read**

- Tutorial, <https://docs.seastar.io/master/tutorial.html> (Nadav Har'El
  and Avi Kivity; also `doc/tutorial.md` in the Seastar tree). Seastar
  uses futures and continuations for asynchronous events. Share-nothing:
  memory is divided between cores, each core works on its own part, and
  communication is explicit message passing. The server has one thread per
  CPU. Each thread runs its own event loop (the engine) and is pinned to a
  hardware thread. Applications shard memory: each thread allocates only
  from the memory preallocated for it. A continuation is a callback
  attached with `then()` and runs when the future is ready, on that
  engine. An already-ready future runs the continuation immediately, on
  the caller, not on a worker pool.
- SMP, <https://docs.seastar.io/master/group__smp-module.html>. Each
  logical core runs a separate event loop, with its own memory allocator
  and services. Shards communicate by message passing, not by locks and
  condition variables. `shared_ptr` and `lw_shared_ptr` do not use atomic
  reference counts and cannot be used on multiple cores in parallel.
  `foreign_ptr` remembers the core and, on destruction, sends a message so
  the original core destroys the object.
- Shared-nothing overview, <https://seastar.io/shared-nothing/>. One
  application thread per core. `smp::submit_to(cpu, lambda)` runs the
  lambda on that cpu and returns a future. The lambda runs there; the
  caller's core does not share the callee's heap.
- Kivity, *Building efficient I/O intensive applications with Seastar*,
  <https://www.scylladb.com/wp-content/uploads/Avi_Building_efficient_IO_intensive_applications_with_Seastar.pdf>.
  Each logical core runs a shared-nothing run-to-completion scheduler.
  Cores are connected by point-to-point queues. The shard owns its data.
  A continuation runs when its future is ready. `seastar::future` is
  single-threaded, with embedded state and no locks. `std::future` is
  thread-safe, with allocated state and locks.

No separate peer-reviewed Seastar paper turned up in the fetch. The
tutorial and the SMP module are the primary sources of the model.

That model is explicit worlds: one thread, one heap, one event loop, and
a message when something must cross. `seastar::future` is a continuation
on that shard. Chez `Future a` is the `std::future` side of Kivity's
contrast: a mutex, a condition variable, and a thread that shares the
heap. snmalloc's remote-free message is the allocator's batch of blocks.
It does not make this process a Seastar shard, and it does not make a
counted cell safe to send.

Ullrich's `markMT` is what sharing the RC heap would cost, and the
decision says that cost is a different heap. Seastar's non-atomic
`shared_ptr`, destroyed only on its core, is the cost of staying with the
heap we have: a foreign thread does not hold the pointer.

## The path

- Do not implement `System.Future` as Chez does. Do not add
  `blodwen-make-future`, a thread pool, tokio, or `async.execute` as a
  concurrent task. Prelude `fork` / `threadWait` stay `unsupported
  (threads)`. Contrib `fork` / `await` stay `%foreign`, refused by name.
  `decision-threads-pointers.md` stands.
- snmalloc does not justify a multithreaded runtime. Scalable allocation
  is the free-list and the remote-free message in the README cited above.
  Resilience to a foreign thread is narrower than that.
- Resilient means: a foreign thread may post a wakeup to the thread that
  owns the world. It does not call `llvm.coro.resume`, does not enter a
  thunk, does not call `idris_rt_inc` or `idris_rt_dec`, and does not
  write a counted cell. The owner, holding the world, resumes. Sockets
  and timers, if they ever complete on another thread, complete by that
  post. The proposal's §12 sentence "the wake is a post to the owning
  thread" is this constraint. A poll loop drained only by that owner,
  resuming switched-resume coroutines in world order, is the same
  schedule, and it is not `System.Future`. This note does not start that
  work. A waker that itself runs the Idris task is the second schedule
  `decision-threads-pointers.md` excludes.
- A later multi-shard design is explicit worlds: one world and one RC heap
  per shard, cross-shard only by a message, as Seastar's `submit_to` and
  `foreign_ptr`. It is not `fork : Lazy a -> Future a`. It would be a new
  decision. This note does not propose that change. Until then the process
  has the one world `idris_rt_start` runs, and the Rust proposal's async
  line stays the rejection it already is in v1 (`unsupported (rust
  async)` in the proposal's §9.5).

## The construct

The highest MLIR construct that applies is LLVM switched-resume:
`llvm.coro.id`, resumed by `llvm.coro.resume` and destroyed by
`llvm.coro.destroy`. **read** `.toolchain/llvm-project/llvm/docs/Coroutines.md`
63–88 and 857–876. Resume is a call. When the compiler can see it, the
intrinsic becomes a direct call to the resume function. The MLIR async
dialect names that identifier `async.coro.id` ("switched-resume coroutine
identifier") and the handle `async.coro.handle`
(`.toolchain/llvm-project/mlir/include/mlir/Dialect/Async/IR/AsyncTypes.td`
79–91). `async.coro.suspend` transfers to the resume successor when the
coroutine is resumed (`AsyncOps.td` 507–517).

The requirement that construct would force us to accept is the one in
`Coroutines.md` 1689–1704: `llvm.coro.save` runs before an `async_op` that
"may trigger resumption of a coroutine from the same or a different
thread", possibly before `async_op` returns. Taking that allowance means
a foreign waker calls `llvm.coro.resume` and enters Idris code on the
foreign thread, which shares the RC heap and forces thunks there. That
requirement is one to delete. The owner calls `llvm.coro.resume`. The
foreign thread's post is not a resume.

The next construct up is `async.execute`. Its body "semantically can be
executed concurrently with the successor", and a fully sequential run is
only "a completely legal execution", not the only one (`AsyncOps.td`
46–57). It lowers through `async.runtime.resume`, "resumes the coroutine
on a thread managed by the runtime" (`AsyncOps.td` 607–611), and
`async.runtime.await` "blocks the caller thread" (596–600).
`async.runtime.num_worker_threads` reads "the number of threads in the
threadpool" (727–733). That requirement, a runtime thread pool and a
second schedule, is one to delete. Switched-resume stays as the
replacement for `idr.suspend` / `idr.force` / enter / done /
`idris_rt_lazy_kept`, resumed by the thread that holds the world.
