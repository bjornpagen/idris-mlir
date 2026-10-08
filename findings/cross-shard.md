# Cross-shard

Four questions about a value, a proof, a reactor, and a wakeup that
cross a shard. The architecture is the one `findings/shards.md` already
keeps: one reactor per core, started by the runtime, one heap per
reactor, plain counts. User `fork` stays `unsupported (threads)`
(`findings/decision-threads-pointers.md` 8–16). No claim here was timed
or run.

Papers fetched for this note, and not already in `sources/papers/`, are
listed at the end. Already stored and cited in place: Perceus, Choi,
Ullrich, Johansson, Brady's QTT paper, Brady's resource-effects paper.

## 1. Aliased data, plain counts

**read** A counted cell is incremented with `++cell->count`
(`runtime/Rc/Counting.cppm` 13–18). The header says that arithmetic is
plain because a program is single-threaded (`runtime/idris_rt.h` 33–34).
`idris_rt_is_unique` is one cell whose count is 1 and which is not a
stack cell (`runtime/Rc/Objects.cppm` 28–30,
`runtime/Rc/Counting.cppm` 26–27). A stack cell's memory belongs to its
frame (`runtime/idris_rt.h` 52–58). A count of 0 is persistent: static
data and compile-time results are never counted and never freed, and
everything they point to is persistent (`runtime/idris_rt.h` 28–32).
`idris_rt_inc` and `idris_rt_dec` do nothing for that count
(`runtime/Rc/Objects.cppm` 23–24, 38–40). Allocation comes from the
calling thread's snmalloc heap; free may be called from any thread
(`runtime/idris_rt.h` 175–177, `runtime/Alloc/Classes.cppm` 1–4, 38–40).
Live cells are `thread_local` (`runtime/Alloc/Cells.cppm` 15–18).

**read** Quantity 1 is not a count of 1. Brady, *Idris 2: Quantitative
Type Theory in Practice*, ECOOP 2021
(`sources/papers/brady-2021-idris2-qtt/erasure.tex` 12–16, 34–39):
multiplicity 0 is absent at run time, multiplicity 1 is used exactly
once, and a function that takes a multiplicity-1 argument promises not
to share it in the future, with no requirement that it has not been
shared in the past. `!idr.lin<T>` is that quantity
(`foreign/idr/include/idr/IdrOps.td` 149–157). The heap test is
`idris_rt_is_unique`, which reads one header.

**read** Choi, Shull, and Torrellas, *Biased Reference Counting*, PACT
2018 (`sources/papers/choi-2018-biased-rc/paper.pdf`) is the primary
paper on a split reference count: the owner updates a biased counter
with ordinary arithmetic, every other thread updates a shared counter
with an atomic, and the owner merges them before the object can be
freed (§4.1, as read in `findings/shards.md`). A search on 2026-10-07
did not turn up an earlier paper that splits one object's count that
way. The PACT paper is already stored and was not copied again.

**read** The other non-atomic counts name an owner and pay when a
second thread appears. Perceus §2.7.2
(`sources/papers/reinking-2021-perceus/perceus-tr-v4.pdf`): a reference
several threads share has an atomic count; Koka starts objects unshared
and `tshare` marks the reachable graph when a thread is started.
Ullrich and de Moura
(`sources/papers/ullrich-2019-counting-immutable-beans/threadsafety.tex`
16–64): `markMT` walks the single-threaded graph, and later inc/dec test
the tag. Johansson, Sagonas, and Wilhelmsson, ISMM 2002
(`sources/papers/johansson-2002-heap-architectures/paper.pdf`) §3: each
process has its own heap, and a message is copied onto the receiver's
heap, so the sender's cells are not aliased by the receiver. The
reclamation in that paper is still a copying collector per process.

**read** Clebsch, Blessing, Franco, and Drossopoulou, *Ownership and
Reference Counting based Garbage Collection in the Actor World*,
ICOOOLPS 2015 (`sources/papers/clebsch-2015-pony-orca/paper.pdf`):
Pony-ORCA keeps a reference count at the owning actor, updated by
deferred weighted increments and decrements carried in messages. The
only synchronisation is message send and receive. An actor collects an
object it owns when the object is locally unreachable and that count is
zero (the protocol statement in the introduction, and the well-formedness
conditions WF3–WF6 in §4.3). Clebsch, Franco, Drossopoulou, Yang,
Wrigstad, and Vitek, *Orca: GC and Type System Co-Design for Actor
Languages*, OOPSLA 2017 (`sources/papers/clebsch-2017-orca/paper.pdf`):
local objects are mark-sweep, shared objects are deferred reference
counts, and the collector uses no atomic operations on the objects. The
only memory barrier is the one that enqueues a message, which is what
publishes the writes to a shared object. When the data is immutable,
the paper's own alternative is to copy the message. The type system
that makes the zero-copy case safe is deny capabilities. Clebsch,
Drossopoulou, Blessing, and McNeil, AGERE 2015
(`sources/papers/clebsch-2015-deny-capabilities/paper.pdf`): `val`
denies every write alias, so concurrent readers need no copy and no
lock; `iso` denies local and global read/write aliases, and sending it
is `consume`, after which the sender has no read or write alias; `ref`
is not sendable. Sendable capabilities are `iso`, `val`, and `tag`
(Figure 4).

**read** Fähndrich, Aiken, Hawblitzel, Hodson, Hunt, Larus, and Levi,
*Language Support for Fast and Reliable Message-based Communication in
Singularity OS*, EuroSys 2006
(`sources/papers/fahndrich-2006-singularity/paper.pdf`) §1.1 and §2.1:
each process has its own heap and its own collector. Data that moves
between processes lives in a separate exchange heap. Every block there
is owned by at most one thread at a time, is transferred by pointer,
and is deleted explicitly. A process may hold a dangling pointer; the
type system rejects a use of a block it does not own. That is ownership
transfer of a unique block. It is not a shared count, and the exchange
heap is not the process's tracing collector.

**read** Liétar, Butler, Clebsch, Drossopoulou, Franco, Parkinson,
Shamis, Wintersteiger, and Chisnall, *snmalloc: A Message Passing
Allocator*, ISMM 2019 (`sources/papers/lietar-2019-snmalloc/paper.pdf`)
§2.1–§2.2: one allocator per thread, small and medium objects owned by
the allocator that created them. A remote free does not update the
owner's metadata. It enqueues a batch on the owner's multi-producer,
single-consumer queue. The owner applies the free when it next
allocates or frees. Push is one atomic exchange; the owner's read of
its queue uses no atomic. On ARM the push has a release fence and the
read an acquire fence.

**conjecture** What this heap can adopt, with the operations it already
has and without a collector and without an atomic count on any cell, is
a walk of the counted graph at the hop.

- A cell with count 0 is sent as the same pointer. Nothing will
  increment or decrement it, and the header comment already requires
  that a persistent cell point only at persistent cells.
- A cell with count 1 that is not a stack cell, and whose counted
  children are in the same case, is moved: the pointer is the message,
  the sender does not decrement it, and the destination is afterwards
  the only writer of those counts. A later free on the destination is
  the remote free snmalloc already implements. Singularity's exchange
  block is this case. Pony's `consume` of an `iso` is this case, with
  the uniqueness in the type rather than in a header read.
- Every other counted cell is copied onto the destination's heap, as a
  new cell with count 1. The sender keeps its own aliases and
  decrements only on its own shard. This is Johansson's copy without
  Johansson's collector, and it is ORCA's immutable-message alternative.
  Prelude `List`, a shared thunk, and a closure whose captures are
  aliased are this case. A closure's code pointer is not a cell; the
  cell is the closure, and its captures are children of the walk.
- A stack cell is copied. Its memory is the sender's frame.
- A thunk the destination will force is not a pointer to the sender's
  thunk. Force writes the cell. The owner forces it and the value is
  sent under the same walk, or the thunk is copied and the destination
  forces the copy.

`idris_rt_is_unique` on the root is not enough. A cons whose own count
is 1 can point at a tail whose count is not. Moving the cons and then
decrementing the tail on the destination would be a foreign
`idris_rt_dec`. The walk is the same shape as Perceus's `tshare` and
Ullrich's `markMT`, and it does not set their flag.

Promoting the object to an atomic count is the choice this header does
not take. Choi's second counter exists so a non-owner thread can store
to the cell. Perceus and Ullrich, once the flag is set, take the atomic
path on every later update of that graph. Either one is a foreign write
of a counted cell. ORCA's deferred count is the studied way to share an
immutable pointer without that write and without an atomic: the owner
applies the increment and decrement when it receives the message, and
the 2017 collector's local half is mark-sweep, which this heap does not
have. Adopting the message-carried count would be a new side structure
beside `count` and `info` (`runtime/idris_rt.h` 69–72) and would make a
destination `idris_rt_dec` into a message. The copy and the unique-graph
move use `idris_rt_inc`, `idris_rt_dec`, `idris_rt_is_unique`, and
`idris_rt_free` as they are.

## 2. The shard index and the world token

**read** `PrimIO a` is `(1 x : %World) -> IORes a`, and `IORes` packs the
result with the next world at quantity 1
(`third_party/Idris2/libs/prelude/PrimIO.idr` 8–14). `prim__io_bind`
applies the action to the world and feeds the next world to the
continuation (lines 31–33). `io_bind` is what do-notation calls, and the
world is a lambda argument of that function, not a name in the source
(lines 40–45). The frontend turns the `%MkWorld` literal into a new
world, and only a trusted library forges one
(`compiler/src/IdrisMLIR/Frontend/Translate/Terms.idr` 124–126). A
quantity-0 binder is `Gone` before its type is computed
(`compiler/src/IdrisMLIR/Frontend/Resolve.idr` 163–167), and the
multiplicity in a shape is `Q0`
(`compiler/src/IdrisMLIR/Frontend/Resolve.idr` 195–196).

**read** The world that survives that pass is still quantity 1. `!idr.world`
is grade `(1, ·)` of the world carrier
(`foreign/idr/include/idr/IdrOps.td` 143–157), and the type verifier
rejects any other grade (`foreign/idr/lib/Dialect/Types/QType.cc`
26–28). Layout gives `!idr.erased` and `!idr.world` no runtime
components (`foreign/idr/lib/Layout/Layouts.cppm` 35–38, 259–263). The
LLVM conversion appends those components and no others
(`foreign/idr/lib/Lower/Lowering.cppm` 194–202), so a world operand is
absent from the lowered function. The world is dropped because its
layout is empty. It is not dropped because its quantity is 0.

**read** Atkey, *Parameterised Notions of Computation*, JFP 2009
(`sources/papers/atkey-2009-parameterised-notions/paper.pdf`) §1–§2:
a computation is judged `Γ; S1 ⊢ c : A; S2`, from an input state to an
output state. Definition 1's unit stays in one state, and multiplication
sequences two computations only when the output state of the first is
the input state of the second. Same-state bind is ordinary sequencing.
An operation whose states differ is the same judgement with `S1` and
`S2` distinct. McBride, *Kleisli arrows of outrageous fortune*, 2011
(`sources/papers/mcbride-2011-kleisli/paper.pdf`), the introduction and
§4: a monad on indexed types can make the post-state depend on a value
discovered at run time, which Atkey's indexed monad on ordinary types
does not. McBride then defines `Atkey m i j a` as the fragment whose
post-state is fixed, and says that fragment is Atkey's bind. A file
that might open or fail is the dependent case; a step whose next index
is named in advance is the Atkey case.

**read** Atkey, *Syntax and Semantics of Quantitative Type Theory*,
LICS 2018 (`sources/papers/atkey-2018-qtt/paper.pdf`) §1 and §2.1:
usage 0 is McBride's reading of the semiring zero, a variable with no
run-time presence that is still available in types. Brady's § on
quantities, cited above, is that zero in Idris 2. Brady, *Resource-Dependent
Algebraic Effects*, TFP 2014
(`sources/papers/brady-2014-resource-effects/paper.pdf`) §2, already
read in `findings/shards.md`: `Eff` is indexed by the incoming resource
list and by a function from the result to the outgoing list, and `(>>=)`
threads the first computation's output list into the continuation. An
unchanged resource is the list that bind does not rewrite.

**conjecture** An implicit shard parameter can elaborate so that
do-notation never mentions a core, and the hop is the only index
change. The proof that the running computation is on shard `s` is a
quantity-0 argument, the `Gone` binder `Resolve.idr` already builds, the
same kind of argument as the erased `n` and the erased proof in
`natToFinLT`. It is not a second world token. The world stays quantity
1, one chain per reactor, empty at LLVM. Same-shard bind is Atkey's
multiplication with equal indices, written as `(>>=)`, threading `s`
the way `io_bind` threads `%World`. The hop is the operation whose
indices differ. Its destination is a runtime `Fin`, because that integer
selects the queue, and it is the only place the source names a core.
When the destination is the result of an earlier computation, the
continuation's index depends on that value, which is McBride's bind;
the proof carried into the continuation is still quantity 0. The
receiving reactor is that shard because it dequeued the message, which
is why the index on the received value has no runtime representation.

## 3. The reactor on both targets

**read** The platform surface is `rt.platform`
(`runtime/Platform/Platform.cppm` 1–14): POSIX partitions for memory,
processors, faults, and stacks, and one CPU partition per target
(`runtime/Platform/X86_64/Cpu.cppm`, `runtime/Platform/Aarch64/Cpu.cppm`).
Nothing under `runtime/Platform` names `kqueue`, `kevent`, `epoll`, or
`io_uring`. The calls that can wait are:

- `pthread_create` and `pthread_join` in `runThread`
  (`runtime/Platform/Posix/Stacks.cppm` 33–44). `pthread_join` does not
  return until the new thread does. `idris_rt_run_on_stack` is that
  runner, one at a time (`runtime/idris_rt.h` 356–366).
- `mmap`, `mprotect`, and `munmap`
  (`runtime/Platform/Posix/Memory.cppm` 72–88). Each enters the kernel
  and can wait. `checkPageSize` also `write`s to stderr and `_exit`s
  when the page size disagrees (lines 36–67); a `write` to a full pipe
  waits.
- `sysconf` for the page size and the processor count
  (`runtime/Platform/Posix/Memory.cppm` 37,
  `runtime/Platform/Posix/Processors.cppm` 13–14), `sigaction`
  (`runtime/Platform/Posix/Faults.cppm` 34–44), `sigaltstack` and
  `getrlimit` (`runtime/Platform/Posix/Stacks.cppm` 47–61), and the CPU
  feature reads. Those return a value or install a handler. They are
  not a wait for another thread's event.

**read** Above the platform, on the world a reactor would be running, `read` of
standard input blocks the caller. The comment on `peek` says the program
blocks reading (`runtime/Io/Input.cppm` 55–61). `write` loops until the
bytes are accepted (`runtime/Io/Writing.cppm` 30–38) and waits when the
descriptor is not ready. `rt.io` is those libc calls and `_exit` and
`getenv` (`runtime/Io/Io.cppm` 1–2).

**read** Lemon, *Kqueue: A Generic and Scalable Event Notification
Facility*, USENIX ATC 2001
(`sources/papers/lemon-2001-kqueue/paper.pdf`), the API section and
Figure 1: `kqueue` returns a descriptor; `kevent` registers a change
list and retrieves events. A `NULL` timeout blocks until an event is
ready or the call is interrupted. A zero timeout returns without
sleeping. The read and write filters report that a descriptor can be
read, or written without blocking, and the data field carries how much.
This is the Darwin facility. Axboe, *Efficient IO with io_uring*, 2019
(`sources/papers/axboe-2019-io-uring/paper.pdf`) §4: the kernel and the
application share a submission ring and a completion ring, each a
single-producer single-consumer ring, coordinated by memory ordering
rather than a lock shared with a system call. The application is the
producer on the submission ring and the consumer on the completion
ring. Waiting for completions is `io_uring_enter`; polling the
completion ring's tail observes a completion without that wait. The
document is Linux-specific.

**read** Belay, Prekas, Klimovic, Grossman, Kozyrakis, and Bugnion, *IX:
A Protected Dataplane Operating System for High Throughput and Low
Latency*, OSDI 2014 (`sources/papers/belay-2014-ix/paper.pdf`) §3: a
dataplane runs each packet to completion, on a dedicated hardware
thread, and does not block in order to batch. §4.1: elastic threads are
expected not to issue blocking calls, because a delayed thread delays
packet processing for the flows on that core. §6: applications should
handle events in a quick, non-blocking manner, and work that runs long
belongs off the elastic thread; a long turn blocks further network
processing for that dataplane's flows. Shenango (NSDI 2019) states a
weaker rule, that applications are discouraged from blocking kernel
calls, and its runtime provides blocking sockets, lightweight threads,
and work stealing. That is a different scheduler. IX is the paper that
states the rule this reactor uses. Seastar's statement of the same rule
is already in `sources/docs/seastar/tutorial.md` (line 33, as read in
`findings/shards.md`).

**conjecture** The wait belongs behind `rt.platform`, beside the POSIX
partitions that already exist, with one implementation per target: Lemon's
`kqueue` / `kevent` for arm64 macOS, Axboe's rings for x86_64 Linux
musl. The reactor calls one operation. The names of the two mechanisms
stay in that partition. The reactor may block in that operation when its
queue is empty, which is Lemon's blocking timeout and Axboe's enter, or
it may poll, which is the zero timeout and the completion-ring tail.
A resumed frame does not call `read`, `write`, `pthread_join`, or a
page-faulting `mmap` on the hot path; those are the calls above that
stall a core while other work is ready. Startup — page size, CPU
features, the signal handlers, the stack reservation — stays where it
is and runs before the loop. `pthread_create` in the platform is how
the runtime starts a reactor. `pthread_join` is shutdown of that
thread, not a turn of the loop. User `fork` stays unsupported.

## 4. The wakeup queue

**read** Michael and Scott, *Simple, Fast, and Practical Non-Blocking
and Blocking Concurrent Queue Algorithms*, PODC 1996
(`sources/papers/michael-1996-concurrent-queues/paper.pdf`) §2: the
lock-free queue is a singly linked list with a dummy head. An enqueue
takes effect when a compare-and-swap links the new node
(their line E9); a dequeue takes effect when a compare-and-swap swings
`Head` (their line D13). Both ends are concurrent. The paper is written
against compare-and-swap and load-linked/store-conditional. It does not
state a C or C++ memory order. §1 distinguishes this from Lamport's
queue, which allows one enqueuer and one dequeuer.

**read** snmalloc §2.2, cited above, is the MPSC queue: many threads
push, the owning thread pops, one atomic exchange per batch, no atomic
on the pop, a release fence on the push and an acquire fence on the
read where the hardware does not already provide them. ARM is the case
the paper names. The owner applies the messages on its own metadata. The
producer does not run the owner's allocator.

**read** Seastar's shard-to-shard queue, at the pin in
`sources/docs/seastar/smp.hh`, is `boost::lockfree::spsc_queue` of work
items (lines 191–203), one queue for each ordered pair of shards.
`submit_to` of the local shard runs the function on the caller; any
other shard enqueues (lines 358–379). The header snapshot does not cite
Michael and Scott or a memory-order paper. A single-producer queue is
the special case of snmalloc's queue in which the exchange is
unnecessary. A waker that is not that one peer is the multi-producer
case.

**conjecture** The queue a foreign thread may touch is snmalloc's MPSC,
with the order the paper states so the same source is right on x86_64
and on arm64: the foreign thread writes the wakeup, then release-publishes
it with the atomic exchange; the owning shard acquire-reads it and only
then looks at the payload. The payload is a token that the owner has
work. It is not a frame pointer the producer resumes. The foreign thread
does not call `llvm.coro.resume`, does not enter a thunk, does not call
`idris_rt_inc` or `idris_rt_dec`, and does not write a counted cell.
Michael and Scott's queue is the algorithm in which both ends are
threads that may dequeue. A waker that dequeued, or that resumed, would
be that second consumer. The owner's reactor is the only consumer, and
it is the only thread that resumes.

## Papers added

- `sources/papers/clebsch-2015-pony-orca/`
- `sources/papers/clebsch-2017-orca/`
- `sources/papers/clebsch-2015-deny-capabilities/`
- `sources/papers/lietar-2019-snmalloc/`
- `sources/papers/fahndrich-2006-singularity/`
- `sources/papers/mcbride-2011-kleisli/`
- `sources/papers/atkey-2009-parameterised-notions/`
- `sources/papers/atkey-2018-qtt/`
- `sources/papers/lemon-2001-kqueue/`
- `sources/papers/axboe-2019-io-uring/`
- `sources/papers/belay-2014-ix/`
- `sources/papers/michael-1996-concurrent-queues/`

## Answers

**conjecture** Aliased prelude data is copied onto the destination heap;
a counted graph whose every cell is exclusive is moved, and snmalloc's
remote free returns the blocks; the cell is not promoted to an atomic
count.

**conjecture** An implicit quantity-0 shard proof elaborates like an
erased argument, and do-notation threads it the way `io_bind` threads
`%World`, so a core is named only at the hop; the world token stays the
quantity-1 empty token of that reactor, and the hop's destination `Fin`
stays runtime because it selects the queue.

**conjecture** The reactor's wait is a platform operation, `kqueue` on
arm64 macOS and `io_uring` on x86_64 Linux, and a resumed frame does not
call the blocking `read`, `write`, `pthread_join`, or hot-path `mmap`
that the runtime has today.

**conjecture** A foreign thread release-publishes a wakeup on the owning
shard's MPSC queue and does nothing else; the owning shard acquire-reads
it and is the only thread that resumes a frame or touches a counted cell.

## The construct

**read** The highest MLIR construct that applies is switched-resume
`llvm.coro.id`, resumed by `llvm.coro.resume` on the shard that owns
the frame (`.toolchain/llvm-project/llvm/docs/Coroutines.md` 63–88,
865–876). Resume is a call. Touching the coroutine object while it is
running is undefined (lines 87–88).

The requirement that construct would force is the one in
`Coroutines.md` 1689–1696: `llvm.coro.save` runs before an `async_op`
that may resume the coroutine from the same or a different thread,
possibly before `async_op` returns. Taking that allowance means the
foreign thread calls `llvm.coro.resume` and enters the frame off the
owning shard. That requirement is one to delete. The owning shard's
reactor calls `llvm.coro.resume`. The foreign thread's post is not a
resume.
