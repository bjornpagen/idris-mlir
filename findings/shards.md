# Shards

Thread-per-core, with the reference counts this runtime already has.
One reactor per core, one heap per reactor, and a typed message when a
value has to change heaps. No collector, and no atomic count on a cell.
Idris 2's dependent types, quantities, and compile-time evaluation are
what make that usable: a computation is indexed by the shard it runs
on, same-shard bind is ordinary do-notation, and a hop is a linear
move whose proof erases and whose destination id does not.

The threads decision stands. User `fork`, `threadWait`, and a pure
`Future a` that hides a second schedule stay outside the language
(`findings/decision-threads-pointers.md` 8–16,
`findings/scheduler.md`, `findings/future.md`). Reactors here are
threads the runtime starts. They are not those names, and they are not
a work-stealing pool, Chez `blodwen-make-future`, or `async.execute`.
No claim in this note was timed or run.

## Why plain counts survive only if the owner is one shard

**read** A counted cell is incremented with `++cell->count`
(`runtime/Rc/Counting.cppm` 13–18). The comment on the header says the
arithmetic is plain because a program is single-threaded
(`runtime/idris_rt.h` 33–34). Live cells are `thread_local` for the
same reason (`runtime/Alloc/Cells.cppm` 15–18,
`runtime/idris_rt.h` 235–238). The heap the decision describes is a dag
of immutable values plus mutable cells that one world orders. A second
thread writing those same cells is what counting cannot see
(`findings/decision-threads-pointers.md` 8–16). The heap stays acyclic,
so release is the counting walk and there is no marking phase
(`findings/decision-acyclic-heap.md` 5–9).

**read** Seastar is the architecture that keeps that fact when there is
more than one core. Har'El and Kivity, *Asynchronous Programming with
Seastar*, `sources/docs/seastar/tutorial.md` (tag `seastar-25.05.0`,
fetched 2026-10-07): memory is divided between cores, each core works
on its own part, and communication is explicit message passing, which
itself uses the machine's shared memory (line 14). An event-driven
server has one thread per CPU (line 27). If that thread blocks, the
core sits idle, so event-handling functions must never block (line 33).
Atomics and fences are much slower than operations on one core's cache
(line 38). The fast path is single-threaded per core (line 42). Each
core runs a cooperative scheduler of short tasks (line 48). Programs
start one engine thread per core, pinned, and will not start more
threads than there are hardware threads (lines 140, 163, 175). Each
thread allocates only from the memory preallocated for it (line 181).
Continuations on an already-ready future run immediately, on the caller
(line 320). Continuations on one thread do not run in parallel, so they
do not need locks or atomics, and they must not block, or they block
the thread (line 1607, still a TODO in the tutorial, and the same rule
as line 33). A Seastar object is used by one CPU, so its count is a
plain integer (line 1052). `seastar::shared_ptr` is that
implementation, `lw_shared_ptr` is the one-word form, and
`std::shared_ptr` is the atomic one the tutorial says not to use in a
sharded application (lines 1054–1056).

**read** `smp::submit_to` is the hop. The shared-nothing page
(`sources/docs/seastar/shared-nothing.html`, fetched 2026-10-07) says
one application thread per core, explicit message passing rather than
shared memory, and `smp::submit_to(cpu, lambda)` runs the lambda on
that cpu and returns a future (lines 116–121). In `smp.hh` at the same
pin, a call whose target is `this_shard_id()` invokes the function on
the caller; any other target goes through the pair of queues
`_qs[t][this_shard_id()]` (`sources/docs/seastar/smp.hh` 344–379). The
remote work item runs the function on the destination and
`respond`s the continuation back to the calling shard; the work item
is deleted on the origin shard (lines 246–258). Kivity's May 2019
slides (`sources/papers/kivity-2019-seastar/slides.pdf`) summarise the
same model: one shared-nothing run-to-completion scheduler per logical
core, point-to-point queues, the shard owns its data, and
`seastar::future` is single-threaded, with embedded state and no locks,
against `std::future`, which is thread-safe, allocated, and locked.

**read** A `foreign_ptr` is not a shared count. Threads can see another
thread's memory and are not supposed to use it (line 2182). When
ownership of an object must move, the wrapper is sent with `submit_to`,
and destroying it sends a message so the original shard runs the
destructor (lines 2187–2189). Methods that touch the home shard's state
still have to `submit_to` that shard (lines 2191–2196). The count, if
the object has one, is touched on the home shard. It does not become
atomic.

**read** snmalloc is the allocator, not this scheduler. Same-thread
free takes no synchronising operation; a free from another thread sends
the block back to the allocating allocator by message passing, and many
remote frees become one atomic (`third_party/snmalloc/README.md` 10–16).
`idris_rt_alloc` takes memory from the calling thread's heap;
`idris_rt_free` may be called from any thread (`runtime/idris_rt.h`
175–177), and the fast path after LTO is a thread-local free-list pop
(`runtime/Alloc/Classes.cppm` 1–4). That message is a batch of blocks.
It is not a program continuation, and it does not make `idris_rt_inc`
safe to call off the owning shard. `findings/scheduler.md` already
separates those two.

**conjecture** A counted cell follows the `foreign_ptr` rule, not the
remote-free rule. `idris_rt_inc` and `idris_rt_dec` run on the shard
that owns the cell. A hop of a linear value does not leave a pointer
the destination increments. The destination's reactor allocates its own
cells from the message, and the sender's reactor releases. That is
Erlang's copy, below, applied to a linear value so the destination's
`On s'` is actually storage on `s'`. A `foreign_ptr`-shaped wrapper, in
which the bytes stay on the sender and only the destructor is posted
home, would make `On s'` a lie about where the cell lives. The queue
that carries the message is the shared memory Seastar already admits
(tutorial line 14). The synchronisation is on that queue, once per
message, not on every cell.

## What M:N would force

**read** Go's scheduler multiplexes goroutines onto operating-system
threads. Vyukov, *Scalable Go Scheduler Design Doc*, 2 May 2012
(`sources/docs/go-scheduler/go11sched.txt`): an M is an OS thread, a P
is a resource required to execute Go code, there are `GOMAXPROCS` Ps,
and when a P's local run queue is empty it steals half the runnable
goroutines from a random other P. The header of `proc.go` at Go 1.25.4
says the same thing in the present tense: the scheduler distributes
ready goroutines over worker threads, and an M must hold a P to execute
Go code (`sources/docs/go-scheduler/proc-comment.go`, the comment at
`proc.go` 23–33). `HACKING.md` at the same tag: a G is a goroutine, an M
is an OS thread, there can be any number of Ms, and there are exactly
`GOMAXPROCS` Ps (`sources/docs/go-scheduler/HACKING.md` 13–38). Any M
that has acquired a P may run a G. The G's pointers are into the one
heap the collector scans.

**read** That heap is collected, not counted. The Go GC guide
(`sources/docs/go-scheduler/gc-guide.html`, fetched 2026-10-07; the page
says it describes the collector as of Go 1.19) says the standard
toolchain ships a garbage collector with every program (the paragraphs
under the introduction), and that the algorithm is mark-sweep: trace
from roots, mark what is reached, then sweep what was not (the
paragraphs beginning "This basic algorithm is common to all tracing
GCs"). A goroutine stolen onto another M can hold a pointer that
another M's collector, or another G, also reaches. A plain `++count` on
that object would be a data race. Go does not add an atomic count. It
traces.

**read** Tokio's work-stealing scheduler is the same shape on a heap
that is reference-counted. Lerche, *Making the Tokio scheduler 10x
faster* (`sources/docs/tokio/scheduler-2019-10.html`, fetched
2026-10-07): each processor has a run queue, and an idle processor
steals from a sibling (the section "Work-stealing scheduler"). The
section "Reducing atomic reference counting" says the usual way to keep
the task alive across the scheduler and its wakers is `Arc`, an atomic
increment on wake and an atomic decrement when the processor finishes
the task. Rust's non-atomic pointer cannot take that path.
`Rc` "uses non-atomic reference counting" and "does not implement
`Send`"; the compiler rejects sending one between threads; the atomic
pointer is `Arc` (`sources/docs/rust-rc/rc.rs` 16–21, and
`impl !Send for Rc` at line 320, tag `1.90.0`). A task a worker can
steal has to be `Send`. Shared ownership of it is atomic, or the task
is not stealable.

**read** The papers that keep a non-atomic count all do it by naming an
owner, and they pay when the owner is no longer the only thread.

Ullrich and de Moura, *Counting Immutable Beans*
(`sources/papers/ullrich-2019-counting-immutable-beans/threadsafety.tex`
16–64, already stored; not copied again): a fence on every decrement
hurt the single-threaded case, so values are tagged single-threaded,
multi-threaded, or persistent. `markMT` walks the single-threaded graph
before a task is created, and every later inc/dec tests the tag. Sharing
is a walk plus a test on every count. This runtime's header has no such
tag (`runtime/idris_rt.h` 26–39) and `idris_rt_inc` does not test one
(`Counting.cppm` 13–18).

Perceus, §2.7.2 (`sources/papers/reinking-2021-perceus/perceus-tr-v4.pdf`):
if several threads share a reference, the count has to be atomic. Koka
follows Ullrich: objects start unshared, `tshare` marks the reachable
graph when a thread is started, and `drop` takes the atomic path only
when the flag is set. The fast path is `b->header.rc--`. The paper's
premise is that the type system knows which values may be shared. An
M:N worker that can be handed any value does not have that premise, so
the flag would be set on the whole heap, which is the atomic path on
every cell.

Choi, Shull, and Torrellas, *Biased Reference Counting*, PACT 2018
(`sources/papers/choi-2018-biased-rc/paper.pdf`) §4.1: most objects are
touched by one thread, so the owner updates a biased counter with
ordinary arithmetic and every other thread updates a shared counter
with an atomic. The owner merges the two before the object can be
freed. §3 records that the Swift they measured uses an atomic for every
count, because a separately compiled caller might share the object.
Their split counter is what you pay if a second thread is allowed to
touch the cell at all. Shipping Swift still has both entry points.
`swift_retain` is the atomic path unless the runtime was built with
`SWIFT_THREADING_NONE`; `swift_nonatomic_retain` calls
`incrementNonAtomic` (`sources/docs/swift-rc/HeapObject.cpp` 439–453,
tag `swift-6.2-RELEASE`). The non-atomic entry is the one a compiler
emits when it already knows the object is not shared. It is not a
licence to share the object and keep the plain increment.

Deutsch and Bobrow, CACM 1976
(`sources/papers/deutsch-bobrow-1976/paper.pdf`): most cells are
referenced exactly once, so a count of one is the default and only a
count of two or more is stored, in a multiple-reference table. That is
the "unary" case people reach for when they say Bacon's unary counting.
Bacon, Cheng, and Rajan, *A Unified Theory of Garbage Collection*,
OOPSLA 2004 (`sources/papers/bacon-2004-unified-gc/paper.pdf`) does not
use that phrase. It shows tracing and reference counting as duals, and
that the collectors people actually run are hybrids of the two. A
search on 2026-10-07 did not turn up a Bacon paper titled as unary
reference counting; the author-copy URLs tried for Bacon and Rajan,
ECOOP 2001, returned 404 and that paper is not stored. The dual is the
relevant Bacon sentence: if the heap is shared across workers, the
design is pushed toward that hybrid, which is a collector, or toward an
atomic count on every cell those workers can reach. Either one replaces
`++cell->count`.

**read** Erlang is the share-nothing predecessor, and it still collects.
Johansson, Sagonas, and Wilhelmsson, *Heap Architectures for Concurrent
Languages using Message Passing*, ISMM 2002
(`sources/papers/johansson-2002-heap-architectures/paper.pdf`) §3: each
process allocates and manages its own heap. Message passing copies the
term from the sender's heap onto the receiver's heap and enqueues a
pointer in the receiver's mailbox. The sender's heap is not aliased by
the receiver, so one process can be collected without scanning the
others. The reclamation in that paper is still a copying collector per
process. The architecture is the predecessor. The collector is not the
thing to take. This heap is a dag and the release is the count
(`decision-acyclic-heap.md` 5–9). The copy is the part that keeps the
count non-atomic.

**read** Lerche's post lists Erlang next to Go and Java as a
work-stealing scheduler. That is a statement about which scheduler runs
a process, not about a shared heap. Johansson's private heap still
copies the message. Stealing a whole process, heap and all, onto
another core is one owner at a time. Stealing a goroutine, or a Tokio
task, whose pointers land in a heap other workers also mutate, is the
shared heap. The second is the one that forces an atomic count on that
heap, or a collector of it. This note does not take it.

## How Idris spells a shard

**conjecture** The term is Brady's indexed computation, with the shard
as the resource that does not change under ordinary bind, and the hop
as the operation that does change it. Same-shard code is do-notation.
A hop consumes a linear value on the sender's shard and produces it on
the destination. The destination's id is runtime data. The proof that
the sender was allowed to send, and that the value now lives on the
destination, is erased.

```idris
||| `n` is the core count `getNProcessors` returned. It is not a
||| constant of the binary. `Fin n` is the shard id.
|||
||| `s` is quantity 0. The reactor that is running already is that
||| shard. A proof that a value is on `s`, and a proof that an id is
||| in range, are the same kind of argument.

data At : (n : Nat) -> (0 s : Fin n) -> Type -> Type where
  Pure : a -> At n s a
  Bind : At n s a -> (a -> At n s b) -> At n s b
  ||| Yield this shard's frame. The same reactor resumes it.
  Wait : At n s a -> At n s a
  ||| Consume `v` here and produce it on `s'`. `s'` selects the queue,
  ||| so it is not erased.
  Hop  : (1 v : a) -> (s' : Fin n) -> At n s (On n s' a)

||| Storage that lives on `s`. The index is erased: after the message
||| has been received, the receiving reactor is `s`, and it allocated
||| the cells.
data On : (n : Nat) -> (0 s : Fin n) -> Type -> Type where
  MkOn : (1 v : a) -> On n s a

||| Same-shard bind. The index does not change, so this is `(>>=)`.
(>>=) : {n : Nat} -> {0 s : Fin n} ->
        At n s a -> (a -> At n s b) -> At n s b
(>>=) = Bind

||| Run `p` on `s'`. `p` is indexed by `s'`, so a linear value of the
||| caller's shard is not a capture of `p`; it has to have been hopped.
||| `s'` is the queue index. The result comes back as a message, which
||| is the same move in the other direction.
submit : {n : Nat} -> {0 s : Fin n} ->
         (s' : Fin n) -> At n s' a -> At n s a
```

**read** That index is the one Brady writes down. *Resource-Dependent
Algebraic Effects*, TFP 2014
(`sources/papers/brady-2014-resource-effects/paper.pdf`) §2: `Eff` is
indexed by the result, the input effects, and a function from the result
to the output effects. `{ eff }` means the list is unchanged.
`{ eff ==> {result} effs' }` means the output list is computed from the
result. `open` is the example: the resource is `()` on the way in, and
on the way out it is an open handle or `()` according to the `Bool`.
The Idris 1 library that implements this, tag `v1.3.3`
(`sources/docs/idris-effects/Effects.idr`): `Effect` is
`(x : Type) -> Type -> (x -> Type) -> Type` (lines 20–21), `MkEff`
pairs a resource with an effect (lines 27–28), and `EffM`'s `EBind`
threads the output list of the first computation into the input list of
the continuation (lines 233–234). `(>>=)` is `EBind` (lines 288–290).
Building the term does not run the effect; `eff` interprets it (lines
347–351). This pin of Idris 2 has no `libs/effects`
(`findings/execution.md`). The spelling above is that algebra with the
shard as the resource. It is not a second copy of `Control.Monad.ST`.

**read** P2300R10 (`sources/papers/dominiak-2024-p2300/p2300r10.html`,
2024-06-28) §1.3 and §4.2: a scheduler is a lightweight handle to an
execution resource, and `schedule` returns a sender that completes on
that resource. §4.1's examples of a resource are a thread pool, a GPU,
or the current thread. The algebra this note keeps is the handle and
the three completions `findings/execution.md` already keeps. The
resource is a shard id, which is `Fin n` for the runtime `n`. It is not
the thread pool in P2300's example, and `schedule` of a shard does not
start a worker. `findings/execution.md`'s `Here` / `ThisWorld`, whose
`start` completes on the caller, is this type at `n = 1`.

**read** What is erased is already how this compiler treats a `Fin`.
`Fin n` is "numbers strictly less than some bound"
(`third_party/Idris2/libs/base/Data/Fin.idr` 13–21). `coerce` takes the
equality at quantity 0 (line 25). `natToFinLT` takes the bound `n` and
the proof `x < n` at quantity 0; the runtime argument is `x` (lines
186–190). `natToFin` is the partial version, a `Maybe` when the proof is
not in hand (lines 199–200). The frontend drops an erased index, and
names `FS`'s index as one of those (`compiler/src/IdrisMLIR/Frontend/Translate/Terms.idr`
80–81). A `Nat`-shaped value, `Fin` included, is a big at runtime
(`foreign/idr/include/idr/IdrOps.td` 127–131). `!idr.erased` is quantity
0 with no carrier (`IdrOps.td` 149–157). So the integer that is the
shard id occupies a register. The proof that it is `< n`, and the index
that says which shard the running computation already is, do not.

**read** The core count is a runtime lookup, and this compiler already
treats it as one. `System.Info.getNProcessors` is `IO (Maybe Nat)`
(`third_party/Idris2/libs/base/System/Info.idr` 25–35). The op is
`idr.io.n_processors`: it takes a world and returns a count and the next
world (`IdrOps.td` 1287–1294). It is not `Pure` and it has no folder.
The runtime reads `sysconf(_SC_NPROCESSORS_ONLN)` when the program asks
(`runtime/Platform/Posix/Processors.cppm` 11–15,
`runtime/Io/Processors.cppm` 12,
`runtime/idris_rt.h` 306–308). A missing answer is `-1`, which becomes
`Nothing`. By contrast `idr.os` is `Pure`, folded, and is the string the
target triple already named (`IdrOps.td` 1296–1303). A shard id is a
`Fin n` for that runtime `n`. It is not a compile-time constant baked
into the binary, and `natToFin` against that `n` is how an out-of-range
id fails closed.

**read** Compile-time evaluation folds a closed pure placement and does
not fold the lookup. `idr-eval` replaces a call whose operands are
constants, of a function with a body that performs no IO, by the
constants it returns (`foreign/idr/include/idr/Passes.td` 102–121). Total
code gets a larger budget than code that may diverge. A placement that
is a closed pure function of its key is that call, and the protocol —
which shard a value is on, and which way the hop changes the index — is
the type, checked before the call is run. `getNProcessors` performs IO,
so a placement that reads `n` from the world is not a candidate. The
folded part is the pure function. The `Fin` is built at runtime against
the `n` the lookup returned.

**read** A required suspend is what the totality checker and the reactor
already agree on, separately. Idris records a function as total when it
covers its inputs, is well-founded, is strictly positive, and calls only
total functions (`sources/docs/idris2/docs/source/tutorial/theorems.rst`
348–359). A `Stream` is productive because the recursive occurrence sits
under `Inf` (`third_party/Idris2/libs/prelude/Prelude/Types.idr`
751–755). A function without `idr.total` may diverge (`IdrOps.td`
269–277). A loop of such a function is marked `idr.may_loop`, because
upstream would otherwise delete a loop with no effects
(`foreign/idr/lib/Tail/Loops.cppm` 31–34, `IdrOps.td` 662–671). In the
JIT, every function counts a tick on entry so a call that does not end
spends its budget (`foreign/idr/lib/Lower/Lowering.cppm` 171–174).

**read** Seastar states the matching rule on the core. A fiber that
computes without a suspension point stalls the reactor (tutorial.md
341–347). Loop primitives insert a preemption point each iteration
(lines 1091–1092). A coroutine yields at `co_await`, and a long loop
that does not await has to `co_await maybe_yield` (lines 587–598). The
word "fiber" in the tutorial is a chain of continuations, not a thread
(lines 1084–1087). The direct style that replaced the callback chain is
the later C++20 coroutine: a function that returns `future<T>` and uses
`co_await` / `co_return`, which the tutorial calls the preferred way to
write new code (lines 349–355). `seastar::thread` is the older direct
style. It allocates a 128KB stack, `get()` on an unready future
suspends that stack, and it still runs on the core it was launched on;
it is not a POSIX thread and it must not make a blocking system call
(lines 2203–2240). The stackful thread is the convenience the tutorial
tells you not to use for thousands of concurrent operations.

**conjecture** The Idris spelling takes the coroutine, not the 128KB
stack. `Wait` is the required suspend: a total `At` between waits is
well-founded, so one turn of a reactor returns to the event loop, and a
busy-wait is not a total `At`. A partial spin is the function that
already lacks `idr.total` and whose loop already carries `idr.may_loop`.
That is the existing mark. It is not a new timer, and it was not
measured here. `do`-notation is same-shard `co_await`. A hop is the
`submit_to` that the type makes explicit, because the continuation that
uses the value is indexed by the destination and the linear value on
the sender does not unify with a capture there.

## Runtime data, and what erases

**read** Runtime, because something in the machine reads it:

- The shard id that selects a queue. It is a `Fin n` value, which this
  compiler lowers like a `Nat`, to a big (`IdrOps.td` 127–131). `Hop`'s
  `s'` and `submit`'s `s'` are that value.
- `n`, from `idris_rt_io_n_processors`, at the moment the program asks
  (`Processors.cppm` 11–15). Not a folded constant (`IdrOps.td`
  1287–1294 against 1296–1303).
- The bytes of a hopped value, in the message, and the cells the
  receiving reactor allocates from them. The count on those cells is
  the plain `++` (`Counting.cppm` 13–18), on that reactor.
- The world token of that reactor. The world is `!idr.world`, quantity
  1 (`IdrOps.td` 143–157). One chain per shard, not one chain for the
  process. A suspension still cannot capture a world
  (`findings/future.md` cites `Lazy.cc` 188–190); each shard's world
  stays the argument of the turn the reactor resumes.

**read** Erased, because the type checker already consumed it:

- The quantity-0 index `s` on `At` and `On`. The reactor is that shard.
  Nothing loads it to choose a queue.
- The proof `x < n` and the bound `n` in `natToFinLT` (`Fin.idr`
  186–190), and `coerce`'s equality (`Fin.idr` 25).
- `FS`'s index (`Terms.idr` 80–81). The runtime payload of the `Fin` is
  the number; the index it is an index of is not stored again.
- Any equality of shard indices the protocol mentions. Quantity 0 has
  no carrier (`IdrOps.td` 149–157).

**conjecture** The message header carries the runtime id and the moved
representation. It does not carry a proof. The receiving reactor
trusts the queue it dequeued from, which is the same fact as `s` being
erased on `On`: the proof was the enqueue.

## The frame

**read** The frame is switched-resume `llvm.coro.id`
(`.toolchain/llvm-project/llvm/docs/Coroutines.md` 63–66). The ramp
returns the handle; `llvm.coro.resume` continues it; `llvm.coro.destroy`
invalidates it (`Coroutines.md` 72–101). Resume is a call, direct when
the compiler can see it (`Coroutines.md` 865–876). Nothing in the
intrinsic starts a thread. `findings/frame.md` and `findings/future.md`
already identify this as the replacement for `idr.suspend` /
`idr.force` / the enter-done pair. This note does not add a second
frame type for a shard.

**read** `Coroutines.md` 1689–1696 allows `llvm.coro.save` before an
`async_op` that may resume the coroutine from the same or a different
thread, possibly before `async_op` returns. Taking that allowance means
a foreign thread calls `llvm.coro.resume` and enters the frame off the
owning shard, which is a foreign `idris_rt_inc` on the cells the frame
holds. That allowance is the one `findings/scheduler.md` deletes. It
stays deleted. The owning shard's reactor calls `llvm.coro.resume`.
Another shard, and any foreign thread, posts a message. The post is not
a resume.

**conjecture** A same-shard `Wait` suspends the frame and the same
reactor resumes it, which is Seastar running an already-ready
continuation on the caller (tutorial.md 320–321) and a not-yet-ready one
when the event arrives. A `Hop` / `submit` does not resume the caller's
frame on the destination. The destination reactor builds, or resumes,
the frame whose type is `At n s'`, on `s'`. The caller's frame stays
suspended on the caller until the reply message is dequeued there. Two
frames, two owners. `start` of a same-shard computation is the resume
on the reactor that holds that shard's world, which is
`findings/execution.md`'s `start` when there is one shard. `start` does
not enqueue the frame onto a pool.

## The smallest runtime

**read** Today the process runs one body. `idris_rt_start` checks the
page size and the CPU, then runs that body
(`runtime/idris_rt.h` 340–354). One stack runner at a time
(`runtime/idris_rt.h` 356–364). The live-cell count and the snmalloc
heap are already per calling thread (`Cells.cppm` 15–18,
`idris_rt.h` 175–177). There is one world (`IdrOps.td` 143–146).

**conjecture** One shard is that process, with the type above at
whatever `n` the lookup returns, including `n = 1`. `Fin 1` has one
value, `FZ` (`Fin.idr` 19–21), so `Hop` to a different shard has no
index to name. The type does not change when a second reactor is added.
Adding a core is another engine thread, another heap, another world,
and a queue in each direction, which is `submit_to` becoming inhabited
for the new `Fin`. The runtime starts those reactors. User code still
has no `fork`. A pure `Future a` still does not hide a schedule. Until
a second reactor exists, the lookup may return a larger `n` and the
program may still run on the one shard `idris_rt_start` already runs;
the type is ready for the other reactors, and they are the whole of the
addition.

## The construct

**read** The highest MLIR construct that applies is switched-resume
`llvm.coro.id`, resumed by `llvm.coro.resume` on the shard that owns
the frame (`Coroutines.md` 63–66, 865–876).

The requirement that construct forces: the resume function runs only on
that shard; a hop is a message carrying a runtime shard id and a moved
value; the destination reactor resumes its own frame; a foreign thread
only posts; `start` does not mean "enqueue onto a pool". That
requirement is not one to delete. It is the one-shard frame
`findings/frame.md` already keeps, with the owner named as a shard.

**read** The next construct up is `async.execute`. Its body can run
concurrently with its successor; a fully sequential run is a legal
execution, not the only one
(`.toolchain/llvm-project/mlir/include/mlir/Dialect/Async/IR/AsyncOps.td`
46–57). It lowers through `async.runtime.resume`, which resumes the
coroutine on a thread the runtime manages (`AsyncOps.td` 607–611), and
`async.runtime.num_worker_threads` reads the pool (`AsyncOps.td`
727–733). That requirement is a shared heap plus a work-stealing or
pooled schedule. Go meets it with a collector. Tokio meets it with
`Arc`. Either one replaces the plain count on every cell a stolen task
can reach. That requirement is one to delete.
