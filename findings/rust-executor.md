# FutT is one switched-resume handle, polled on main's thread

`Rust (FutT a)` is a switched-resume coroutine handle, `!async.coro.handle`.
The thread that runs `main` resumes it. A `Waker` only posts to that
thread. Tokio's runtime stays `unsupported (rust async)`. The handle is
the MLIR frame. The enter/done cell and `idris_rt_lazy_kept` are that
frame written in C, and they do not grow a second copy for futures.

**(read)** Proposal §4 stages this, and does not put it in v1: "async
Rust driven by the Idris runtime's own futures, once that runtime has
them (§12)" (`proposals/0001-rust-interop.md:138-141`). §12 then says
the runtime has no scheduler, a program is one thread running `main`
(`idris_rt_start`), and the Rust half is an import `Rust (FutT a)`, a
shim the executor polls, and a `Waker` that may run on any thread whose
wake is a post to the owning thread
(`proposals/0001-rust-interop.md:797-808`). Crates that turn on tokio's
`rt`, `net`, or `time` are `unsupported (rust async)`. A tokio island
on its own threads is never in scope
(`proposals/0001-rust-interop.md:816-820`). The same refusal is the
lead and the v1 cut: Rust never hosts the runtime, and async Rust
executed by a Rust runtime is out
(`proposals/0001-rust-interop.md:11-13`,
`proposals/0001-rust-interop.md:130-133`). R5 is that §12 work, and
only once an executor exists (`proposals/0001-rust-interop.md:887`).

## What the handle is

**(read)** `async.coro.id` is a switched-resume coroutine identifier.
`async.coro.handle` is a pointer to the coroutine frame, passed around
to resume or destroy it (`.toolchain/llvm-project/mlir/include/mlir/Dialect/Async/IR/AsyncTypes.td:79-91`).
`async.coro.begin` allocates that frame
(`.toolchain/llvm-project/mlir/include/mlir/Dialect/Async/IR/AsyncOps.td:460-468`).
`async.coro.suspend` sends control to its suspend successor, and a
later resume or destroy sends control to the resume or cleanup
successor
(`.toolchain/llvm-project/mlir/include/mlir/Dialect/Async/IR/AsyncOps.td:507-517`).

**(read)** Under those ops, LLVM's switched-resume ABI (`llvm.coro.id`)
is the object. Resume and destroy function pointers sit in the coroutine
object at offsets fixed for every coroutine. A finished coroutine has a
null resume pointer. `llvm.coro.done` reports completion.
`llvm.coro.resume` continues it. `llvm.coro.destroy` invalidates it,
and destroy is required even after a normal completion. `llvm.coro.promise`
projects storage of a known size and alignment. The frontend resumes
and destroys through those intrinsics. Touching the object while it is
running is undefined
(`.toolchain/llvm-project/llvm/docs/Coroutines.md:63-121`).

**(read)** A Rust future, in the proposal's words, is polled through a
shim until it yields `a` (`proposals/0001-rust-interop.md:804-808`).
That poll is one resume of this handle. Pending is the suspend
successor. Ready stores `a` in the promise and clears the resume
pointer. The shim is the ramp the proposal already asks for. It is not
a new suspension op.

**(read)** The cell we lower today has the same slots, written by hand.
`!idr.lazy<T>` is one cell whose code pointer is the state: the first
force writes the value over the payload and replaces the pointer, and
every later force returns what was written
(`foreign/idr/include/idr/IdrOps.td:104-111`). Lowering says the same
thing (`foreign/idr/lib/Lower/Runtime.cppm:210-212`). The first entry
calls the callee, stores the value, stores the address of the done
entry over the code pointer, and notes a persistent cell with
`idris_rt_lazy_kept`
(`foreign/idr/lib/Lower/Runtime.cppm:272-331`). The done entry loads
that value and returns it
(`foreign/idr/lib/Lower/Runtime.cppm:289-294`,
`foreign/idr/lib/Layout/CodeName.cppm:12-14`). A persistent suspension
that has stored a value is kept until `idris_rt_main_return`, because
a count of 0 is never freed
(`runtime/idris_rt.h:218-223`, `runtime/Rc/Counting.cppm:40-70`,
`runtime/Io/Ending.cppm:41-44`).

**(conjecture)** Once that hand-written cell is the MLIR handle,
`!idr.lazy<T>` and `FutT a` are two states of `!async.coro.handle`.
A lazy force is one resume that stores the promise and sets the resume
pointer to null. A future poll is a resume that may suspend again with
the pointer still set. `ForceOfOneUse` already deletes a suspension
that is forced once and replaces it with the call
(`foreign/idr/lib/Dialect/Ops/Lazy.cc:14-28`). That is the same elision
`CoroElide` exists to do for a frame that does not escape
(`.toolchain/llvm-project/llvm/docs/Coroutines.md:113-116`). A `Waker`
that outlives the poll is an escape, so that future's frame stays.
`idris_rt_lazy_kept` is the persistent cell's substitute for destroy:
the handle's `llvm.coro.destroy`, run on the owning thread when the
last count of the handle drops, releases the promise without a side
list. No second thunk runtime is added beside this handle.

## The thread that resumes it

**(read)** `idris_rt_start` checks the page size and the CPU, then
`idris_rt_run_on_stack(runProgram, …)`. `runProgram` calls `body` and
stores the status `body` returns
(`runtime/idris_rt.h:340-354`, `runtime/Start/Entry.cppm:62-65`,
`runtime/Start/Entry.cppm:133-146`). The runner starts one thread whose
stack is the reserved region, and joins it
(`runtime/Platform/Posix/Stacks.cppm:30-44`). One runner runs at a time
in a process. The compiler's tools and, after a fork, the evaluation
child use the same runner; the child replaces its parent
(`runtime/idris_rt.h:356-366`, `runtime/Start/Runner.cppm:16-18`).

**(read)** That joined thread is the thread the proposal calls "one
thread running `main`". The executor is a loop inside `body` on it.
It does not call `idris_rt_run_on_stack` again, and it does not start
a thread of its own. The threads decision still stands: `fork` is a
second schedule of effects and is `unsupported (threads)`
(`findings/decision-threads-pointers.md:8-16`). The reserved-stack
thread is the program's stack, not a license for a second one.

**(read)** The smallest loop on that thread is: resume the handle; if
the resume pointer is null, the promise is `a`; if the coroutine
suspended, wait until a post is visible, then resume again. The wait
is the platform completion I/O §12 names
(`proposals/0001-rust-interop.md:799-801`). `runtime/` has no
`epoll`, `kqueue`, or `io_uring` entry. Until that I/O exists, the
loop has nothing to wait on, and async Rust stays at R5.

**(read)** The resume is a direct call of the resume pointer on this
thread, which is what the switched-resume frontend is told to emit
(`.toolchain/llvm-project/llvm/docs/Coroutines.md:118-121`). It is not
`async.runtime.resume`, whose summary is "resumes the coroutine on a
thread managed by the runtime"
(`.toolchain/llvm-project/mlir/include/mlir/Dialect/Async/IR/AsyncOps.td:607-615`),
and not `mlirAsyncRuntimeExecute`, which queues that resume on
`llvm::DefaultThreadPool`
(`.toolchain/llvm-project/mlir/include/mlir/ExecutionEngine/AsyncRuntime.h:134-137`,
`.toolchain/llvm-project/mlir/lib/ExecutionEngine/AsyncRuntime.cpp:75`,
`.toolchain/llvm-project/mlir/lib/ExecutionEngine/AsyncRuntime.cpp:395-397`).
It is not `async.runtime.await`, which blocks the caller on a condition
variable
(`.toolchain/llvm-project/mlir/include/mlir/Dialect/Async/IR/AsyncOps.td:596-604`,
`.toolchain/llvm-project/mlir/lib/ExecutionEngine/AsyncRuntime.cpp:369-374`).

**(read)** Because a coroutine object must not be resumed while it is
running (`.toolchain/llvm-project/llvm/docs/Coroutines.md:87-88`), the
`Waker` does not resume. §12's post is the whole of what another thread
may do (`proposals/0001-rust-interop.md:805-808`). The owning thread
reads the post when it is outside the coroutine, then resumes.

## The world

**(read)** The world token is `!idr.world`, grade `(1, ·)`, used at most
once on every path (`foreign/idr/include/idr/IdrOps.td:143-157`). Each
IO op consumes one world and produces the next
(`foreign/idr/include/idr/IdrOps.td:1194-1202`). `idr.suspend` is
rejected if it captures a world: a world passes only as an argument or
a result (`foreign/idr/lib/Dialect/Ops/Lazy.cc:188-190`).

**(read)** The executor is that argument and result. Polling is a use
of the one world the thread already holds, and the next world is the
poll's result, in order with every other effect. `FutT` does not close
over the world, so a `Waker` on another thread has no world to use.
That keeps the threads decision's point: a second thread running Idris
would be a second world writing the same cells
(`findings/decision-threads-pointers.md:8-14`).

**(conjecture)** The post is a word the platform wait already shares
with the owning thread. It is not an `idris_rt_header` and not a capture
of `!idr.world`.

## The counts

**(read)** A cell's count is plain arithmetic because a program is
single-threaded: `idris_rt_inc` does `++cell->count` on a counted
object, and a count that would reach `UINT32_MAX` saturates
(`runtime/idris_rt.h:27-37`, `runtime/idris_rt.h:206-208`,
`runtime/Rc/Counting.cppm:13-18`). `idris_rt_dec` releases at 0
(`runtime/idris_rt.h:210-216`). Live cells are counted by the calling
thread, with no atomic on the allocation path
(`runtime/idris_rt.h:235-238`). The allocator is the exception the
header already states: `idris_rt_free_S` frees a block from any thread
(`runtime/idris_rt.h:175-177`). Proposal §8.5 and §9.4 rely on that
split. Rust may allocate on its own threads. `IdrisValue` and `IdrisFn`
are `!Send`, and handles are `!Send`, so an Idris value does not move
to those threads (`proposals/0001-rust-interop.md:585-596`,
`proposals/0001-rust-interop.md:709-716`).

**(read)** The async runtime's count is a different one.
`mlirAsyncRuntimeAddRef` / `DropRef` are atomic, and every async token,
value, and group is freed when that count hits zero
(`.toolchain/llvm-project/mlir/include/mlir/ExecutionEngine/AsyncRuntime.h:60-70`,
`.toolchain/llvm-project/mlir/include/mlir/Dialect/Async/IR/AsyncOps.td:675-693`,
`.toolchain/llvm-project/mlir/lib/ExecutionEngine/AsyncRuntime.cpp:124-143`).
`FutT`'s handle, when it is a heap cell, uses `idris_rt_inc` and
`idris_rt_dec` on the owning thread. Destroy of the frame runs there,
with the last decrement. The `Waker` does not increment, decrement, or
destroy. A post that only stores a word stays on the allocator side of
the split the header already draws.

## What stays unsupported

**(read)** These stay `unsupported (rust async)`, as §12 writes them:
a graph that enables tokio's `rt`, `net`, or `time`; `tokio::spawn`,
`tokio::net`, `tokio::time`; a tokio island
(`proposals/0001-rust-interop.md:816-820`). With them, the MLIR
runtime that has the same shape: `async.execute` lowered through
`mlirAsyncRuntimeExecute` onto `llvm::DefaultThreadPool`,
`async.runtime.await` blocking a caller, and
`async.runtime.num_worker_threads`
(`.toolchain/llvm-project/mlir/include/mlir/Dialect/Async/IR/AsyncOps.td:727-733`,
`.toolchain/llvm-project/mlir/lib/ExecutionEngine/AsyncRuntime.cpp:439-440`).
Rust calling into Idris from another thread is already out
(`proposals/0001-rust-interop.md:132-133`).

## The construct

`async.execute` / `!async.value` is the higher construct, and it does
not apply. **(read)** Its body may legally run to completion before
the successor starts, but the type is a task that can run concurrently,
dependencies have to be tokens and values, and the lowering executes
the coroutine on a thread the runtime manages
(`.toolchain/llvm-project/mlir/include/mlir/Dialect/Async/IR/AsyncOps.td:46-60`,
`.toolchain/llvm-project/mlir/include/mlir/Dialect/Async/IR/AsyncOps.td:437-448`).
The requirement that would force, a pool thread plus the async
runtime's atomic count, is one to delete.

The highest MLIR construct that applies is `async.coro.handle`
(switched-resume, identified by `async.coro.id`). **(read)** Those ops
were added so `async.execute` could lower onto the async runtime, and
`async.runtime.resume` resumes the handle on a thread that runtime
manages
(`.toolchain/llvm-project/mlir/include/mlir/Dialect/Async/IR/AsyncOps.td:437-448`,
`.toolchain/llvm-project/mlir/include/mlir/Dialect/Async/IR/AsyncOps.td:607-615`).
That requirement is one to delete. The handle stays. The thread
`idris_rt_start` runs calls its resume pointer and, on the last
`idris_rt_dec`, its destroy pointer.
