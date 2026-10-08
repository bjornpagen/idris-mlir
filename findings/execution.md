# Execution

`Control.Monad.ST` and `std::execution` are different algebras. `ST` is one mutable region, rank-2 so a reference cannot escape, run to completion, and pure outside. A sender is a value that describes work, with three completion channels, that does nothing until `connect` then `start`, and that takes a scheduler as data. The closer Idris spelling is Edwin Brady's indexed effect: the index is the protocol (resources in, resources out, and which completion), and that value is the algebra.

## One spelling, kept in one place

**read** cpp-starter's prime directive is one concept, one primitive. Asynchronous effects are `std::execution` sender/receiver. The forbidden alternatives in that row are `std::async`, raw futures and promises, direct coroutines, detached callbacks, and stdexec task handlers on the reactor (`/Users/bjorn/Documents/cpp-starter/AGENTS.md:29-42`). Versions of the pinned toolchain live only in the CMake configure gate; the top-level README says it deliberately does not duplicate them (`/Users/bjorn/Documents/cpp-starter/README.md:9-10`). Each pinned workaround's essay lives once, in `PINS.md` (`/Users/bjorn/Documents/cpp-starter/PINS.md:1-8`). The public surface is one module, `starter`, whose partitions are listed in CMake (`README.md:104-116`, `src/starter.cc:1-7`).

**read** The sender algebra is quarantined the same way. `foreign/exec.backend.cc` is the one translation unit that includes a stdexec header or spells `stdexec::` / `exec::` (`/Users/bjorn/Documents/cpp-starter/foreign/README.md:10-16`, `PINS.md:75-92`). `foreign/exec.cc` exports concrete functions. Its result type is `optional<expected<int32_t, ExecError>>`: a disengaged optional is the stopped channel, an unexpected value is the error channel (`exec.cc:49-54`). The three completion functions stay behind that boundary (`exec.backend.cc:71-94`). This note does not copy that build, that pin, or `exec::static_thread_pool`.

## What ST is

**read** The pinned Idris 2 tree defines `ST` in `third_party/Idris2/libs/base/Control/Monad/ST.idr`. The module says it provides mutable references as described in *Lazy Functional State Threads* (`ST.idr:1`). `STRef s a` is a mutable `a` bound to a parameter `s`, which the comments call a "thread": every access must happen in `ST s` with the same `s` (`ST.idr:10-15`, `59-64`). `ST s a` is a newtype of `IO a` (`ST.idr:23-24`). `newSTRef`, `readSTRef`, and `writeSTRef` are `newIORef`, `readIORef`, and `writeIORef` under that newtype (`ST.idr:52-70`).

**read** `runST` has type `(forall s . ST s a) -> a` (`ST.idr:28`). The `forall` sits on the argument, so the caller must hand over a computation polymorphic in `s`, and the result type `a` is outside that quantifier. The body instantiates `s` to `()` — the comment says anything will do — unwraps `MkST`, and calls `unsafePerformIO` (`ST.idr:29-31`). `unsafePerformIO` builds a world with `%MkWorld`, runs the action, and destroys the world (`third_party/Idris2/libs/prelude/PrimIO.idr:97-107`). The computation therefore runs as IO to the end, and the value that comes back does not mention `s`.

**read** That is the whole of `ST` in this pin: one region of mutable references, a phantom parameter that keeps those references inside the region, a rank-2 runner, and IO underneath, finished before the pure result is returned. There is no completion signature, no `connect`, no `start`, and no scheduler. The word "thread" in the comments is the state-thread parameter `s`. It is not an operating-system thread and not an execution resource.

**read** The same pin's `Control.App` is still a running computation. `App` is indexed by a `Path` (`MayThrow` or `NoThrow`) and a list of errors, and its representation is a linear function from `%World` to a result paired with the next world (`third_party/Idris2/libs/base/Control/App.idr:17-23`, `53-57`, `99-102`). Bind threads that world (`App.idr:109-118`). The index is which exceptions are in scope and whether the path may throw. It is not a protocol of resources in and resources out, and it is not three completion channels. This pin has `Control/Monad/ST.idr` and `Control/App.idr`. It has no `libs/effects`.

## What a sender is

**read** The C++26 draft wording is [exec] (https://eel.is/c++draft/exec), fetched from the working draft. P2300R10 (https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2024/p2300r10.html, 2024-06-28) is the design paper the wording grew from. Where they differ, the draft is the specification.

**read** [exec.async.ops] (https://eel.is/c++draft/exec.async.ops). An asynchronous operation is created explicitly, started at most once, and completes exactly once, in exactly one of three dispositions: value (any number of result datums), error (one datum), or stopped (no datum). A receiver is the three handlers for those dispositions, plus an environment. A sender is a factory for asynchronous operations. Connecting a sender and a receiver creates the operation; the operation state owns the receiver and does not depend on the sender or the receiver staying alive. A sender is started when that operation is started. A completion signature is a function type naming one such completion. A scheduler is an abstraction of an execution resource and a factory for senders whose value completions run on an execution agent of that resource. The same clause's example of an execution resource is the currently active thread, a system-provided thread pool, or an accelerator API. The same clause's note says an operation may instead complete synchronously, during `start`, on the thread that started it.

**read** The three completion functions are `set_value`, `set_error`, and `set_stopped` ([exec.set.value], [exec.set.error], [exec.set.stopped]; https://eel.is/c++draft/exec.set.value). `completion_signatures<...>` is the type that encodes the set ([exec.cmplsig], https://eel.is/c++draft/exec.cmplsig). `connect(sndr, rcvr)` produces an `operation_state` ([exec.connect], https://eel.is/c++draft/exec.connect). Copying or moving a library operation state is ill-formed ([exec.opstate.general], https://eel.is/c++draft/exec.opstate). `start(op)` is ill-formed on an rvalue and is `op.start()`; if that call does not start the operation, the behavior is undefined ([exec.opstate.start], https://eel.is/c++draft/exec.opstate.start).

**read** P2300R10 §1.3.1: a scheduler is a lightweight handle to an execution resource, "such as a thread pool"; `schedule` returns a sender that completes on that scheduler; "a sender describes asynchronous work and sends a signal (value, error, or stopped)". §4.10: sender factories and adaptors are lazy. They are never allowed to submit work before the returned sender is started, and they do not start the input senders passed to them. A consumer such as `this_thread::sync_wait` is what starts a sender. §4.9: cancellation of an in-flight operation is a separate disposition from success and failure; destroying an operation state before `start` is the cancellation of work that has not started. §4.20: a sender adaptor returns a sender and does not itself run the input.

The algebra is that value. `just(v)` does not call `set_value`. `then` does not call the continuation. `let_value` does not call the function. `when_all` does not start its children. `schedule(sch)` does not run on `sch`. Each of those expressions returns a sender. The operation exists after `connect`. It runs after `start`.

## Which algorithms ask for another agent

**read** These complete inside `start` on the thread that called `start`, and they do not name a scheduler:

- `just`, `just_error`, and `just_stopped` complete synchronously in their start operation, by `set_value`, `set_error`, or `set_stopped` ([exec.just], https://eel.is/c++draft/exec.just). The exposition-only `start` is the completion call.
- `then`, `upon_error`, and `upon_stopped` attach an invocable to one disposition and forward the other two unchanged ([exec.then], https://eel.is/c++draft/exec.then). The invocable runs where that disposition is delivered. The adaptor does not schedule.
- `let_value`, `let_error`, and `let_stopped` pass the result datums to a callable that returns a new sender, then `connect` and `start` that sender ([exec.let], https://eel.is/c++draft/exec.let). The parent's `start` starts the predecessor. The callable runs when the chosen disposition arrives. Nothing in that clause creates an execution agent.
- `when_all` completes when every input has completed. Its `start` is `(start(ops), ...)` on the child operation states ([exec.when.all], https://eel.is/c++draft/exec.when.all). The algorithm does not allocate a pool. A child that itself completes on another resource can; the join then uses an atomic count and an atomic disposition because those completions may race. With only synchronous children, the starts run to completion on the caller before `when_all`'s own `start` returns.

**read** A scheduler is data. `schedule(sch)` is `sch.schedule()` and yields a sender ([exec.schedule], https://eel.is/c++draft/exec.schedule). It does not run. What runs, and where, is the scheduler's resource:

- `inline_scheduler` models `scheduler`. `start` on its operation state is `set_value` of the receiver ([exec.inline.scheduler], https://eel.is/c++draft/exec.inline.scheduler). No new agent.
- `run_loop` is a queue. `start` pushes the operation state. `run` is `while (auto* op = pop-front()) op->execute()`, and `execute` is `set_value` or `set_stopped` ([exec.run.loop], https://eel.is/c++draft/exec.run.loop). The thread that calls `run` is the thread that completes the work. `push-back` synchronizes with `pop-front`, so another thread may push. The loop itself is one thread.
- `starts_on(sch, sndr)` requires that `start` start `sndr` on an execution agent of `sch`'s resource ([exec.starts.on], https://eel.is/c++draft/exec.starts.on). `continues_on(sndr, sch)` starts `sndr` on the current agent and runs the completion on an agent of `sch` ([exec.continues.on], https://eel.is/c++draft/exec.continues.on).
- `parallel_scheduler` reports `forward_progress_guarantee::parallel` ([exec.par.scheduler], https://eel.is/c++draft/exec.par.scheduler). That value means the resource's agents provide at least the parallel forward-progress guarantee ([exec.get.fwd.progress], https://eel.is/c++draft/exec.get.fwd.progress). `get_parallel_scheduler()` terminates if no backend is installed. This is the draft's parallel execution resource, the same class of resource as the thread pool in [exec.async.ops]'s example.
- `spawn` and `spawn_future`, on success, eagerly start the input sender and associate it with a scope token ([exec.spawn], [exec.spawn.future]). `this_thread::sync_wait` blocks the current thread until the sender completes, on a `run_loop` ([exec.sync.wait], https://eel.is/c++draft/exec.sync.wait).

**read** cpp-starter's conformance probe uses both sides. `value_chain` is `just | let_value | then` (`exec.backend.cc:214-221`). `error_recovery_chain` is `just_error | upon_error` (`:224-228`). `error_reroute_chain` is `just_error | let_error` (`:231-235`). `ProbeSender::start` calls exactly one of `set_value`, `set_error`, `set_stopped` (`:181-193`). `pool_when_all_sum` constructs `exec::static_thread_pool pool(4)`, takes its scheduler, and joins `starts_on`, `schedule`, and `on` with `when_all` and `continues_on` (`:246-261`). `static_thread_pool` is a stdexec type (`:10-11`, `:31`). It is not a class in the [exec] synopsis. The draft's name for a parallel resource is `parallel_scheduler`.

The pure description is the sender value: factories and adaptors, completion signatures, `connect`, and a `start` that completes on the caller (`just`, `then`, `let_*`, `upon_*`, `when_all` of such senders, `inline_scheduler`, a `run_loop` drained by the thread that calls `run`). The part that requires another thread, or a pool of them, is a scheduler whose execution resource is not that caller: `starts_on` / `continues_on` / `on` onto a pool or a `parallel_scheduler`, `spawn` onto such a resource, and `static_thread_pool`. `schedule` itself is only the factory call.

## Brady's index is the algebra

**read** *Resource-Dependent Algebraic Effects*, Edwin Brady, TFP 2014, https://www.type-driven.org.uk/edwinb/papers/dep-eff.pdf (Springer LNCS 8843, pp. 18–33, https://doi.org/10.1007/978-3-319-14675-1_2). §2: an effectful program's type is indexed by the input effects and a function from the result to the output effects. In full, `Eff : (x : Type) -> List EFFECT -> (x -> List EFFECT) -> Type`. The notation `{ eff }` means the list is unchanged; `{ eff ==> {result} effs' }` means the output list is computed from the result. §2.1's `open` is the example: the `FILE_IO` resource is `()` on the way in, and on the way out it is an open handle or `()` according to the `Bool`. §3.1: `Effect` is the synonym `(result : Type) -> (input_resource : Type) -> (output_resource : result -> Type) -> Type`, and `EFFECT` is `MkEff` of a resource type and an `Effect`. `Get` does not change the resource; `Put` replaces it. A `Handler` receives the resource, the operation, and a continuation that is given the result and the updated resource. The paper says an algebraic effect is an algebraic datatype of the permitted operations, and that the `effects` EDSL embeds that datatype in the host language.

**read** The Idris 1 library that implements this is `Effects.idr` (https://github.com/idris-lang/Idris-dev/blob/master/libs/effects/Effects.idr). `Effect` is `(x : Type) -> Type -> (x -> Type) -> Type`. `data EFFECT` has one constructor, `MkEff : Type -> Effect -> EFFECT`. The language is `EffM`, indexed by the underlying context `m`, the result type, the input list `es`, and `ce : x -> List EFFECT`. Its constructors are the algebra: `Value`, `EBind`, `CallP` (one operation, present in the list), `LiftP`, `New`, and a label. `(>>=)` is `EBind`. `pure` is `Value`. `eff` interprets a term against an environment; `run` sequences that interpretation in `m`; `runPure` interprets it in the identity. The term exists before `run`. Building a `Value` or an `EBind` does not perform the effect.

**read** That index is the protocol: resources in, resources out as a function of the result. The result can carry the branch, as `open`'s `Bool` does, so the output resource in each branch is a different type (`dep-eff.pdf` §2.1). It is not `ST`'s phantom `s` (`ST.idr:14-15`, `28`).

**conjecture** A completion signature is that same index with three results instead of one `Bool`: value, error, and stopped are three ways the output resource is computed, and the term that carries the index is the algebra.

**read** `ST` has no such term. `MkST` holds an `IO` action (`ST.idr:24`). `runST` does not interpret an algebra; it instantiates `s` and calls `unsafePerformIO` (`ST.idr:29-31`). `Control.App` interprets by applying a function to a world (`App.idr:111-118`). Brady's `EffM` is the value that describes the computation. The sender is that kind of value. `ST` is not.

## What to keep, and the requirement to delete

Keep from [exec], as the algebra:

- Completion signatures: one of `set_value`, `set_error`, `set_stopped`, exactly once ([exec.async.ops], [exec.cmplsig]). P2300R10 §4.9 treats stopped as cancellation, a different disposition from failure.
- `let_value` as bind that does not spawn. It returns a sender. `start` of the parent starts the predecessor; the function's sender is connected and started when the value arrives, on the agent where that value was delivered ([exec.let]). No clause in `let_value` creates a thread.
- Structured cancellation as `set_stopped`, including `when_all` requesting stop of the siblings when one child stops or fails ([exec.when.all]). Destroying the operation state before `start` drops work that has not started (P2300R10 §4.9).
- The scheduler as data: a value that `schedule` turns into a sender, not a running pool (P2300R10 §1.3.1, [exec.schedule]). The only resource that fits the decision below is the one whose `start` completes on the caller, which is what `inline_scheduler` specifies ([exec.inline.scheduler]).

Delete, as a requirement: any scheduler whose `start` is a thread. That is `static_thread_pool` (`exec.backend.cc:247-248`), `starts_on` / `continues_on` / `on` onto a resource other than the caller ([exec.starts.on], [exec.continues.on]), `parallel_scheduler` ([exec.par.scheduler]), and `spawn` / `spawn_future` when they start work on such a resource ([exec.spawn]). It is also `async.execute`'s thread pool, cited below.

**read** `findings/decision-threads-pointers.md:9-16`. A second thread is a second schedule of effects and a second world writing the same cells. Counting cannot see it. The world's order does not sequence it. `fork` is rejected with `unsupported (threads)`. That decision stands. This note does not add a thread pool, a second world, or a change to that decision.

## A spelling in which a second thread has no type

**conjecture** The Idris term is Brady's indexed algebra, with the completion as part of the index, and with the only execution resource being the world the root already holds. Building the term allocates nothing and starts nothing. `start` is an operation on that one world: it resumes a switched-resume frame on the thread that called it, which is the thread `idris_rt_start` is running.

```idris
||| One completion, three channels. Which channel was taken is the result.
data Compl : Type -> Type -> Type where
  SetValue   : a -> Compl a e
  SetError   : e -> Compl a e
  SetStopped : Compl a e

||| `r` is the resource on the way in. The function is the resource on the
||| way out, computed from the completion, as Brady's `Eff` computes the
||| output effects from the result. A value of `Alg` is the description.
data Alg : (r : Type) -> (r' : Compl a e -> Type) ->
           (a : Type) -> (e : Type) -> Type where
  Just        : a -> Alg r (\c => r) a e
  JustError   : e -> Alg r (\c => r) a e
  JustStopped : Alg r (\c => r) a e
  Then        : Alg r (\c => r) a e -> (a -> b) -> Alg r (\c => r) b e
  UponError   : Alg r (\c => r) a e -> (e -> b) -> Alg r (\c => r) b e
  LetValue    : Alg r (\c => r) a e ->
                (a -> Alg r (\c => r) b e) ->
                Alg r (\c => r) b e
  WhenAll     : Alg r (\c => r) a e -> Alg r (\c => r) b e ->
                Alg r (\c => r) (a, b) e

||| The only scheduler. `schedule` of it is `Just ()`, completed inside
||| `start` on the caller. There is no constructor whose resource is a pool
||| or another thread, so `starts_on` and `continues_on` onto one are not
||| expressible.
data Here : Type where
  ThisWorld : Here

schedule : Here -> Alg r (\c => r) () e
schedule ThisWorld = Just ()

||| Linear in the world already held by the root. One completion comes back
||| with the next world. A library operation state is not copyable
||| ([exec.opstate.general]); the frame `connect` would build is that
||| linear value, resumed here.
start : (1 w : %World) -> Alg () (\c => ()) a e -> IORes (Compl a e)
```

**read** The world that `start` would take is the one the program already has. `PrimIO` is `(1 x : %World) -> IORes a`, and `IORes` pairs the result with the next world (`PrimIO.idr:8-14`). The root this compiler builds is that function for `main`: one linear world in, the `IORes` out, `%MkWorld` never appearing (`compiler/src/IdrisMLIR/Frontend/Translate/Programs.idr:116-151`). The carrier is `!idr.world`, quantity 1 (`foreign/idr/include/idr/IdrOps.td:143-147`, `166-170`). `idr.world.new` forges a world for `unsafePerformIO`, "the first of a chain of its own", and "has no runtime form" (`IdrOps.td:1379-1390`). Layout gives a world no components (`foreign/idr/lib/Layout/Layouts.cppm:261-263`). IO a function does with a world it takes is read off its type; forging one is a different fact (`foreign/idr/lib/Facts/Infer.cppm:19-21`). The executable root is the function that takes that world (`foreign/idr/lib/Lower/Lowering.cppm:160-164`). `idris_rt_start` checks the processor and runs one body (`runtime/Start/Start.cppm:1-6`, `runtime/Start/Entry.cppm:133-147`).

**read** A second thread is a second schedule on the same cells, which the threads decision excludes (`decision-threads-pointers.md:9-16`). `idr.world.new` is not that schedule: it forges one chain for `unsafePerformIO`, and that chain is still the calling thread (`IdrOps.td:1379-1385`). The spelling above does not call `idr.world.new`. It does not quantify a phantom `s` the way `runST` does. The parameter that keeps the work on one agent is the linear world `start` already receives. `Here` has one constructor, so a pool scheduler is not a value of the scheduler type. `LetValue`'s function returns another `Alg`; it does not return a thread. `WhenAll` is a constructor of the description; it is not `static_thread_pool`.

**conjecture** `connect` is the ramp that builds the switched-resume frame and does not run the body. `start` is `llvm.coro.resume` of that frame, called by the owner of the world. A stopped completion is the destroy path of that frame, taken instead of the value path, still on the same thread. Suspension, if a description must wait, suspends that frame; the same owner resumes it. Nothing in the type is a waker that enters Idris on another thread.

## The construct

**read** The highest MLIR construct that applies is switched-resume: `llvm.coro.id`, resumed by `llvm.coro.resume` (`.toolchain/llvm-project/llvm/docs/Coroutines.md:63-88`, `857-876`). Resume is a call, direct when the compiler can see it, indirect through the pointer in the frame otherwise. The intrinsic does not start a thread. The frame is the operation state: the ramp returns it, `start` resumes it, and destroy is a separate entry (`Coroutines.md:72-85`, `90-101`).

The requirement that construct forces us to accept is that `start` is a resume on the thread that holds the world, the thread `idris_rt_start` runs (`runtime/Start/Entry.cppm:133-147`). The same intrinsic is the standing replacement for the homegrown thunk: the caller resumes, and the resume does not start a thread (`Coroutines.md:865-876`). This requirement is not one to delete. It is the operation state of a sender whose only scheduler is `ThisWorld`.

**read** The next construct up is `async.execute`. Its body can run concurrently with its successor; a fully sequential run is a legal execution, not the only one (`.toolchain/llvm-project/mlir/include/mlir/Dialect/Async/IR/AsyncOps.td:44-57`). It lowers through `async.runtime.resume`, which resumes the coroutine on a thread the runtime manages (`AsyncOps.td:607-611`), and `async.runtime.num_worker_threads` reads the thread pool (`AsyncOps.td:727-733`). That requirement, a pool and a second schedule, is what `static_thread_pool` and `parallel_scheduler` would force. It is one to delete. `decision-threads-pointers.md` stands.
