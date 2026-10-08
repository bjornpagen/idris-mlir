# Findings

The notes below are the map. The code is the specification, and a note
becomes work only when a plan picks it up. They agree on one replacement:
the homegrown lazy thunk (`idr.suspend`, `idr.force`, the enter/done
pair, the `Lazy.cc` rewrites, and `idris_rt_lazy_kept`) is replaced by
MLIR and LLVM, not kept beside it. The construct is switched-resume
`llvm.coro.id`, which the MLIR LLVM dialect spells `llvm.intr.coro.id`.
The caller resumes it with `llvm.coro.resume`, the value sits in the
promise, a finished frame has a null resume, destroy is separate from
completion, CoroSplit outlines the frame, and CoroElide removes one that
does not escape. No note recommends `async.execute` on a thread pool, a
Chez future thread (`blodwen-make-future` / `fork-thread`), or a change
to the threads decision. Those three are requirements the notes delete.

`frame.md` decides the suspension is that intrinsic. `Inf` is the same
frame with another suspend; a shared tail stays switched-resume, because
yield-once (`llvm.coro.id.retcon.once`) cannot be entered again and this
dialect does not spell it. `!idr.fn` stays the closure
defunctionalization already turns into a sum. `async.execute` is the
concurrent task above the frame, and `async.runtime.resume` would run
the coroutine on a runtime thread. That requirement is deleted.

`async-dialect.md` decides `async.execute` and `!async.value` are a
task. The lowering that exists outlines every execute, calls
`async.runtime.resume`, and the runtime queues that resume on
`llvm::DefaultThreadPool`. A sequential run is a legal schedule of the
op and is still that pool. `async.coro.*` is emitted with those runtime
ops, and `async.coro.begin` allocates outside the counted heap. Upstream
`fork` / `await` through `blodwen-make-future` is the same shape: a side
object, a mutex, and a worker. The thunk lowers through `llvm.coro` on
the caller. The pool is deleted.

`future.md` decides `System.Future` is the same pure suspension as
`Lazy`. Chez demands the work at `fork-thread`, off the caller's order.
That is the schedule `decision-threads-pointers.md` excludes, and the
decision is unchanged. `fork` is the ramp and `await` is the force, both
on the caller, so a future nothing awaits does not run. `forkIO` forges
a world inside the suspension; a suspension cannot capture `!idr.world`,
and the forge is root-only, so a second world has no term.
`async.execute` would make the memo a second `!async.value` and resume
on a worker. That requirement is deleted.

`rust-executor.md` decides `Rust (FutT a)` is one switched-resume handle
the thread `idris_rt_start` runs polls. Pending is a suspend; ready
stores the value and clears the resume pointer. A `Waker` posts to that
thread and does not resume, count, or destroy. Tokio (`rt`, `net`,
`time`, `spawn`) and `async.execute` through `mlirAsyncRuntimeExecute`
onto `llvm::DefaultThreadPool` stay `unsupported (rust async)`. The note
names the handle `async.coro.handle` and deletes the runtime-thread
requirement those ops were added to carry. The resume it keeps is a
direct call on the owning thread. The threads decision stands.

`papers.md` decides three protocols stay separate. Peyton Jones's shared
thunk, STG update flag `u`, is `llvm.coro.id`: the first entry stores
the promise and a later entry loads it. The at-most-once thunk, flag
`n` and Bhat's value-semantics force, is `llvm.coro.id.retcon.once`,
which this dialect does not spell, so the canonicalizer's direct call
remains that path. Ullrich's `task` and STG's queue-me pointer are a
thread. A thread is not a coroutine identity emitted for a thunk, and
the threads decision stands.

`copies.md` decides the thunk is spelled more than once, and each
spelling is one piece of the `llvm.coro.id` object: `!idr.lazy` beside
`!idr.fn` (the closure `idr.apply` still calls), `Term.Suspend` and
`Term.Resume` beside the dialect ops, the outlined `__idr_code_` /
`__idr_lazy_` pair and the `idris_rt_lazy_kept` side list, and the four
`Lazy.cc` patterns, which are CoroElide. `IOOp` is a world-consuming
primitive, not one of those copies. `async.execute` is deleted, and the
threads decision stands.

`scheduler.md` decides upstream `System.Future` is not the executor in
the Rust interop proposal. Chez starts the thunk on `fork-thread` and
publishes under a mutex; this compiler does not implement that, and
snmalloc's remote-free message does not make a counted cell safe to
share. A foreign thread may post a wakeup to the thread that owns the
world. That thread, holding the world, calls `llvm.coro.resume`. The
foreign thread does not. Prelude `fork` and `threadWait` stay
`unsupported (threads)`; contrib `fork` and `await` stay `%foreign`. A
pure `Future a` that hid threads would require changing
`decision-threads-pointers.md`. This note leaves that decision as it
stands. A later multi-shard design would be a new decision, explicit
worlds with one world per shard. This note does not propose it.

`execution.md` decides `ST` is one mutable region. `std::execution` is a
sender with three completion channels that runs at `connect` and
`start`. Brady's indexed effect is the closer Idris spelling.
Switched-resume `llvm.coro` is the frame. A work-stealing pool or a Chez
`fork-thread` remains a requirement to delete. The one-thread reading of
"start on the caller" is the single-shard case of one reactor per core,
plain reference counts, a hop is a typed move, and the core count is a
runtime lookup. That reading is not a ban on a reactor per core. The
threads decision stands.

`shards.md` decides thread-per-core: one reactor per core, plain
reference counts on that core's heap, no garbage collector. Same-shard
bind keeps an erased shard index, so do-notation stays on the reactor.
A hop is not bind: it consumes a linear value on `s` and returns it
indexed by `s'`. The `Fin` that selects the destination queue is
runtime data, from `Fin n` where `n` is the runtime processor count.
The proof that the value lives on `s'` is quantity 0 and erases. The
sender posts the id and the moved representation and suspends its own
frame. The destination reactor resumes a frame it owns. Neither side
calls `llvm.coro.resume` on the other's frame. A work-stealing pool,
atomic counts on the whole heap, and a Chez `fork-thread` stay
requirements to delete. The threads decision
(`decision-threads-pointers.md`) still stands: reactors the runtime
starts, not user-level `fork`.

`cross-shard.md` decides aliased prelude data is copied onto the
destination heap. A counted graph whose every cell is exclusive is
moved and freed remotely through snmalloc. The cell is not promoted
to an atomic count, and there is no tracing GC. A quantity-0 shard
proof elaborates like an erased argument. Do-notation threads it the
way `io_bind` threads the world token, so a core is named only at the
hop. The world token stays the quantity-1 empty token. The hop's
destination `Fin` stays runtime because it selects the queue. The
reactor wait is a platform operation: `kqueue` on arm64 macOS,
`io_uring` on x86_64 Linux. A resumed frame does not call the blocking
`read`, `write`, `pthread_join`, or hot-path `mmap` the runtime has
today. A foreign thread release-publishes a wakeup on the owning
shard's MPSC queue and does nothing else. The owning shard
acquire-reads it and is the only thread that resumes a frame or
touches a counted cell. The highest construct is switched-resume
`llvm.coro.id`, resumed on the owning shard. `llvm.coro.save` so
another thread can resume the frame is a requirement to delete. The
threads decision still stands: reactors the runtime starts, not
user-level `fork`.

## Decisions that stand

`decision-threads-pointers.md`. Threads, collector finalizers, raw
pointers, `%foreign` and the C ABI are outside the language. `fork`,
`threadWait` and the primitives they call (`prim__fork`,
`prim__threadWait`) start another schedule of effects and share mutable
state between them. The heap is a dag of immutable values plus mutable
cells that one world orders. A second thread is a second world writing
the same cells, which counting cannot see and which the world's order
does not sequence. There is no scheduler, no thread-safe runtime and no
shared-memory model to add one later without replacing that heap. A
program that forks is rejected with `unsupported (threads)`, naming the
definition. `onCollect` and `onCollectAny` are `unsupported
(finalizer)`. The raw-pointer primitives, and `System.getEnv` through
`prim__getString`, are `unsupported (raw pointer)`. A `%foreign` spec,
`%extern` as a C export, a C calling convention, libffi, and a C symbol
declared or called from user code are `unsupported`, and the message
names `%foreign` or the extern. `unsafePerformIO` stays the escape hatch
it already is: a trusted library's effects happen where the value is
demanded, in order with every other effect. User code is `unsupported
(world)`.

`decision-acyclic-heap.md`. The heap stays acyclic. A type that can knot
a mutable cell (`IOArray`, and `IORef` or `Buffer` when they land) is
`unsupported (cycle)`, naming the types on the cycle. Counting stays
exact because a new object only points at objects that already exist.

`decision-nat.md`. A `Nat` or `Integer` proved to fit a machine word is
a plain `i64`. An unproved value stays `Integer`'s tagged form: a small
signed value in the low bits, or a pointer to a GMP cell whose limbs sit
in the cell. Heap references stay raw, untagged addresses.

`decision-primitive-semantics.md`. A primitive's one meaning is the
runtime. It comes from Idris's own definition, then the standard the
primitive implements, then a decision written in that note. Chez is the
oracle that catches bugs. It is not the specification.

`decision-linear-libraries.md`. The Idris 2 language does not change.
The contrib `LinArray` leak is a library bug, reported upstream.
Soundness is the compiler's own exclusivity proof, and a leaking program
is copied or rejected with `unsupported (uniqueness)`. Superseded in
part by the next decision, which ships `libs/mlir-linear`. The points on
the language and on soundness stand.

`decision-inhouse-linear.md`. The compiler implements Idris 2 fully for
programs over the upstream prelude and base. `contrib`, `linear`,
`network` and `test` are no commitment. Linear arrays and linear
notation come from `libs/mlir-linear`, plain Idris over base, so the
stock Chez backend remains the oracle. A linear array is `memref`. A
trusted library's `unsafePerformIO` forges a world whose effects run
where the value is demanded. User `%MkWorld` is `unsupported (world)`.
