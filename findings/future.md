# Future is the one frame

`System.Future` is a pure suspension. Chez runs it as another thread.
The threads decision stands: a second schedule of effects is outside the
language. `await` is a resume of the same frame as `idr.force`, spelled
with the MLIR LLVM coroutine intrinsics. No claim here was timed or run.

## What upstream writes

**read** `third_party/Idris2/libs/contrib/System/Future.idr:8-22`.
`Future` is an external type. `fork : Lazy a -> Future a` and
`await : Future a -> a` are pure. `fork` is
`prim__makeFuture (\_ => force l)` and `await` is `prim__awaitFuture`.
The two primitives are `%foreign` of `scheme:blodwen-make-future` and
`scheme:blodwen-await-future`.

**read** `third_party/Idris2/libs/contrib/System/Future.idr:25-44`.
`map`, `pure` and `(<*>)` are `fork` of an `await`. `forkIO` is the
only place a world appears:

```
performFutureIO = primIO . prim__io_pure . map unsafePerformIO
forkIO a = performFutureIO $ fork a
```

`fork` of an `IO a` builds a `Future (IO a)`. `map unsafePerformIO`
forges a world inside that future and runs the action there.
`forkIO` returns `io (Future a)`: the caller's world is the `io`, and
the forged world is not that token.

**read** `third_party/Idris2/libs/prelude/Prelude/IO.idr:125-140`.
`Prelude.IO.fork : (1 prog : IO ()) -> IO ThreadID` is a different
function. It is `prim__fork`, `%foreign` of `scheme:blodwen-thread` and
`C:refc_fork`, and `threadWait` is `scheme:blodwen-thread-wait`. The
threads decision names these (`findings/decision-threads-pointers.md:6-16`),
and the registry forbids them by those names
(`compiler/src/IdrisMLIR/Registry/Recognized.idr:121-127`).
`System.Future.fork` is not that name and not that type.

**read** `third_party/Idris2/tests/chez/futures001/Futures.idr:39-48`.
A bound `forkIO` prints without `await`. The test sleeps so those
threads can finish before the process exits. The erased `nonbind`
does not run, because its `IO` is never bound (`:36-37`, `:46-47`).
The effects that do run are the forged world, started at the bind,
on a thread the `await` is not.

## What Chez runs

**read** `third_party/Idris2/support/chez/support.ss:518-533`.
`future-internal` is a record of result, ready flag, mutex and
condition. `blodwen-make-future` allocates that record and
`fork-thread`s a procedure that runs `(work '())`, then under the
mutex stores the result, sets ready, and broadcasts. The function
returns the record without waiting. `blodwen-await-future` takes the
mutex, `condition-wait`s while ready is false, and returns the stored
result. A later await finds ready set and returns the same result.

That is a second schedule. The work runs whether or not anyone awaits,
and the await blocks the caller until the other thread publishes.
**read** `third_party/Idris2/support/racket/support.rkt:483-484`.
The Racket support is the same shape: `future` of the work, `touch`
to wait. The `%foreign` names the Chez functions; both supports leave
the caller.

**read** `findings/decision-threads-pointers.md:6-16`. A second thread
is a second world writing the same cells. Counting cannot see it, and
the world's order does not sequence it. There is no scheduler and no
thread-safe runtime. A program that forks is `unsupported (threads)`.
**read** `findings/decision-threads-pointers.md:44-47`.
`unsafePerformIO` stays the escape hatch it already is: a trusted
library's effects happen where the value is demanded, in order with
every other effect. User code may not write it (`unsupported (world)`).

`blodwen-make-future` demands the work at the `fork-thread`, off the
caller's order. That demand is the schedule the decision excludes.
The decision is unchanged.

**read** `runtime/idris_rt.h:236-238`. A program is single-threaded.
The live-cell count is the calling thread's; `idris-mlir-cc` may fold
on its own threads, each counting only itself. **read**
`runtime/idris_rt.h:356-364`. `idris_rt_run_on_stack` runs the program
body on a reserved stack, and one runner runs at a time in a process.
That runner is the program's stack, not a pool of futures.
**read** `runtime/idris_rt.h:340-354` and `runtime/Start/Entry.cppm:133-146`.
`idris_rt_start` checks the page size and the processor, then runs
that one body.

## A second world has no term

**read** `foreign/idr/lib/Verify/Program.cppm:15-37`. The module has
one public root, of type `() -> i64` or `(!idr.world) -> (...)`.
**read** `foreign/idr/include/idr/IdrOps.td:143-146`. The world is the
IO token at grade `(1, ·)`, spelled `!idr.world`. An IO operation
takes that token and returns the next one (`IdrOps.td:1201-1202` is
one such pair). The chain is one token.

**read** `foreign/idr/lib/Dialect/Ops/Lazy.cc:188-190` and `:209-210`.
`idr.suspend` rejects a capture whose type is a world. A world passes
only as an argument or a result, and a world is never a capture.
Every parameter of the suspended function is a capture (`:211-219`),
so the resumed function has no world parameter.

**read** `compiler/src/IdrisMLIR/Registry/Recognized.idr:31-33` and
`:144-146`. `unsafePerformIO`, `unsafeCreateWorld` and
`unsafeDestroyWorld` are `Forbidden` `WorldUse`, and only the program
root may reach them. **read**
`compiler/src/IdrisMLIR/Frontend/Profile.idr:267-274`. User code that
reaches a forbidden name, or whose tree mentions `%MkWorld`, is
rejected. **read** `compiler/src/IdrisMLIR/Registry/Libraries.idr:14-16`
and `:85-95`. contrib is not prelude, base, or `mlir-linear`. A module
from any other installed package is `Untrusted`, loaded and not
reached (`:31-32`). `System.Future` is that package. Its
`%foreign` specs are not registered primitives; an unregistered
`%foreign` is `unsupported` and the message names `%foreign`
(`compiler/src/IdrisMLIR/Frontend/Profile.idr:257-261`).

`forkIO` needs a world inside the suspension: `map unsafePerformIO`
forges one where the future runs. The suspension cannot capture the
caller's token, and the forge is root-only. `await` returns `a`, so
the forged token is not a result the caller threads onward either.
The frame's type has nowhere to put a second world. That is what
makes the second world unrepresentable. It is the existing world
check and the existing suspend verifier, not a new exclusion and not
a change to the threads decision.

**read** `tests/upstream-idris/common.sh:68-90`. The upstream-test
scan treats the identifiers `fork`, `forkIO`, `threadWait`,
`prim__fork` and `prim__threadWait` as the threads skip. That scan
cannot see that `System.Future.forkIO` forges a world and
`Prelude.IO.fork` returns a `ThreadID`. Both stay outside. The scan
is not a reason to give either a runtime.

## The frame await resumes

**read** `foreign/idr/include/idr/IdrOps.td:104-110`. `!idr.lazy<T>`
is one cell. Its code pointer is the state: the first force writes
the value over the payload and replaces that pointer, and every later
force returns what was written. **read** `IdrOps.td:91-93`. A
suspension is this cell, not `!idr.fn`. Defunctionalization would turn
a function into a sum, and the cell would no longer be the one that
was forced. `Future a` does not grow a third type beside those two.

**read** `foreign/idr/include/idr/IdrOps.td:584-610`. `idr.suspend`
builds the cell and does not run the function. `idr.force` is the
value, computed on the first force and shared. An unused force is
erased; a force is not speculatable, so it is not hoisted onto a path
that did not force. **read** `foreign/idr/lib/Dialect/Ops/Lazy.cc:14-16`
and `:243-247`. A shared suspension stays a cell. The write that
shares the value is the lowering of `idr.force`, not a second effect.

**read** `foreign/idr/lib/Lower/Runtime.cppm:210-212` and `:272-332`.
Lowering writes that protocol by hand. `emitSuspension` defines two
private functions, `enter` and `done` (`layout::codeName`,
`layout::lazyDoneName`). `done` loads the stored value and returns it
(`:290-294`). `enter` calls the callee, stores the value, stores
`done`'s address over the code pointer (`:319-325`), and returns the
value. **read** `foreign/idr/lib/Layout/CodeName.cppm:12-14`. The done
entry is the pointer a forced cell holds. **read** `runtime/idris_rt.h:218-223` and
`runtime/Rc/Counting.cppm:40-69`. `idris_rt_lazy_kept` records a
persistent cell that has stored its value.
`idris_rt_release_persistent` walks that list and drops what the cells
own. **read** `runtime/Io/Ending.cppm:41-43`. `idris_rt_main_return`
calls that release. Counted cells need no note: freeing them releases
what they stored (`idris_rt.h:221-222`).

That enter/done pair is a switched-resume frame written out as two
functions and a pointer swap. `await` of a pure `Future a` is one
resume of it: the first resume runs the body and leaves the value,
and every later await reads the value. Chez's mutex, condition and
`fork-thread` are a second runtime beside this, and `Future` does not
get one. The enter/done pair itself is the homegrown thunk. It becomes
the coroutine intrinsics below, for `Lazy` and for `Future` together,
so the pointer swap is not kept as a dialect of its own next to
`llvm.coro`.

**conjecture** `Future.idr:16-22`, `IdrOps.td:584-605`,
`Runtime.cppm:319-325`. `Future a` is `!idr.lazy<a>`. `fork` is
`idr.suspend` of the forced lazy: the cell exists and the body has
not run. `await` is `idr.force`. A future nothing awaits does not run,
because a force is not hoisted and suspend does not call. The first
await resumes on the caller and stores the value. A later await reads
the store. Pure `map` and `pure` are the same cell, since upstream
defines them as `fork` of an `await`. Effects inside a trusted
`unsafePerformIO` happen at that resume, in the one world's order,
which is the demand point the decision already states. Chez demands
them on the forked thread at `blodwen-make-future` instead
(`support.ss:521-526`). That difference is the excluded schedule.

## What sits above the frame

**read** `.toolchain/llvm-project/mlir/include/mlir/Dialect/Async/IR/AsyncOps.td:46-57`.
`async.execute`'s body can run concurrently with its successor.
Fully sequential execution is a legal run, and an implicit dependency
through shared state is illegal: dependencies are `async.token` and
`async.value` operands. **read** `AsyncTypes.td:36-41`. `!async.value`
is a value that may be unavailable now and becomes available later.
The memo cell is a shared write of the value into the frame
(`Runtime.cppm:323-324`). That write is the dependency
`async.execute` will not accept unless it is reified as another
`!async.value`, which is a second representation of the same cell.

**read** `AsyncOps.td:596-615` and `:727-733`. The lowering's
`async.runtime.await` blocks the caller until the operand is ready.
`async.runtime.resume` resumes the coroutine on a thread the runtime
manages. `async.runtime.num_worker_threads` reads that pool. This is
`blodwen-make-future`'s mutex and `fork-thread` as an MLIR runtime.
**read** `AsyncTypes.td:71-83` and `AsyncOps.td:437-445`. `async.coro.*`
is the switched-resume intrinsic spelled so that `async.execute` can
lower, first to those ops plus the runtime API, then to LLVM. The
types are "for lowering to LLVM + Async Runtime". The spelling carries
the pool.

**read** `.toolchain/llvm-project/llvm/docs/Coroutines.md:63-111`.
`llvm.coro.id` switched-resume stores the resume and destroy pointers
at fixed offsets. A completed coroutine has a null resume function.
The promise is storage of a known size and alignment (`:82-85`).
Resume is `llvm.coro.resume`: a direct call of the resume function, or
an indirect call through the pointer in the frame (`:865-876`). The
caller resumes. Nothing in that intrinsic starts a thread.
**read** `Coroutines.md:87-88` and `:876`. Interacting with the frame
while it is running, or resuming a coroutine that is not suspended, is
undefined. On the one thread that is a self-force while `enter` is
still the pointer. **read** `Coroutines.md:78-80`. Destroy runs
separately, including after normal completion. The cell's release is
that destroy. **read** `Coroutines.md:2078-2096`. `CoroSplit` builds
the frame and outlines resume and destroy. `CoroElide` replaces the
heap frame with the caller's slot when the inlined coroutine allows
it, and turns resume and destroy into direct calls. A one-use force
already becomes the call (`Lazy.cc:14-28`); elision is that rewrite
as the coroutine pass.

**read** `Coroutines.md:125-152`. Returned-continuation
(`llvm.coro.id.retcon`, `llvm.coro.id.retcon.once`) yields a
continuation pointer. Yield-once returns ordinary results from that
continuation and does not leave a null resume plus a promise for a
second await to read. A later `await` has to read the stored value
(`support.ss:533`, `IdrOps.td:104-107`). The id that holds a promise
is `llvm.coro.id`.

**read** `.toolchain/llvm-project/mlir/include/mlir/Dialect/LLVMIR/LLVMIntrinsicOps.td:704-771`.
The MLIR LLVM dialect spells `llvm.coro.id`, `llvm.coro.begin`,
`llvm.coro.size`, `llvm.coro.align`, `llvm.coro.save`,
`llvm.coro.suspend`, `llvm.coro.end`, `llvm.coro.free`,
`llvm.coro.resume` and `llvm.coro.promise`. The arguments of
`llvm.coro.id` are align, promise, coroaddr and fnaddrs, which are
`llvm.coro.id`'s (`Coroutines.md:1253-1254`), not `retcon`. A search of
`.toolchain/llvm-project/mlir/include` finds no `coro.done`,
`coro.destroy`, or `coro.id.retcon`. Completion in the document is the
null resume pointer (`Coroutines.md:109-111`), which an await can test
before `llvm.coro.resume`. Destroy is the outlined destroy function
and the cell's release. Filling a missing intrinsic is an op in that
dialect. It is not a new runtime entry beside `idr.force`.

## The construct

`llvm.coro.id` switched-resume, as the MLIR LLVM dialect spells it
(`LLVM_CoroIdOp`, `LLVM_CoroResumeOp`, `LLVM_CoroPromiseOp`), outlined
by `CoroSplit` and elided by `CoroElide`.

The requirement it forces: `await` is `llvm.coro.resume` of this one
frame on the caller; the value is the promise; a finished frame stores
a null resume, so a later await loads the promise and does not resume;
the body has no world operand, because a suspension cannot capture one
and a forged world is root-only. `fork` is the ramp that suspends
before the body. `Lazy` and `Future` are that frame.

That requirement is not one to delete. Deleting the null resume and
the promise would make a second await rerun the body or read a side
table. Deleting the caller resume would be the worker thread.

The requirements above this construct are the ones to delete.
`async.execute` / `!async.value` force a concurrent task whose shared
memo is an illegal implicit dependency, and whose lowering resumes on
a runtime thread (`async.runtime.resume`,
`async.runtime.num_worker_threads`). `async.coro.*` is that lowering's
spelling of the same intrinsics. `blodwen-make-future`'s `fork-thread`
is the same requirement in Chez. None of them is a representation of
`fork` / `await`.
