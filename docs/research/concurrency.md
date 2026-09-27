# Concurrency: execution algebras on a thread-per-core runtime

Status: plan, for discussion. It builds on the memory model chosen in
`memory-model.md` (reference counting, Lean's way) and comes after M1–M4 of
`next-plan.md`.

## 1. The shape

The runtime is shaped like Rust's thread-per-core runtimes (Glommio,
monoio, Seastar in C++) and like Lean's tasks, not like Go:

- **One OS thread per core, pinned.** Each owns a scheduler, an `epoll`
  instance, a timer heap, an allocator heap and a run queue.
- **Tasks stay on their core.** A task created on a core runs there until it
  ends. Work does not migrate by default, so almost all data is touched by
  one thread only.
- **Crossing cores is explicit.** A channel to another core's task, a
  parallel future, a value shared at startup: each is a place where the
  runtime knows a value leaves its core. That is exactly where Lean's
  model pays for sharing, and nowhere else.
- **Parallel computation is a separate algebra from IO concurrency.** Pure
  parallel work (futures) is split across cores and may be stolen by idle
  cores. IO tasks are pinned.

A high-performance web server is the reference program:
1. each core accepts on its own `SO_REUSEPORT` listener;
2. each core serves its connections as tasks on its own event loop;
3. CPU-heavy handlers hand pure work to futures, which run in parallel on
   all cores.

## 2. The execution algebras are Idris's own

No language design and no package of ours. Idris already has every piece;
the runtime implements its primitives, and the compiler makes the
combinators free.

| Library (pinned Idris 2) | What it is | What the runtime does |
| --- | --- | --- |
| `Prelude.IO`: `fork : (1 _ : IO ()) -> IO ThreadID`, `threadWait` | concurrent IO threads | a task on the current core; `threadWait` suspends until it ends |
| `System.Concurrency` (base): `Mutex`, `Condition`, `Semaphore`, `Barrier`, `Channel`, thread data | synchronization and message passing | each operation suspends the task, not the OS thread; a channel to a task on another core moves or marks what it sends (section 4) |
| `System.Future` (contrib): `fork : Lazy a -> Future a`, `await`, `Functor`/`Applicative`/`Monad` | pure parallel futures: Lean's `Task` | work items on a per-core deque that idle cores steal from |
| `System.Concurrency.Session` (linear): session-typed channels | protocols checked by linear types | built on `Channel`; linearity means each endpoint has one user |
| `Network.Socket` (network) | sockets | blocking calls register the descriptor with the core's `epoll` and suspend the task |

**The compiler's part.** An execution algebra written in Idris over these
primitives is a static value:
- a monad of futures;
- a user's free monad or applicative of tasks;
- a pipeline of stages;
- a parallel `traverse` over an array.

`Simplify` specializes the interpreter away (`ELIM-G-3`, `ELIM-G-19`,
`ELIM-G-20`), as it already does for IO and state monads. What reaches
code generation is the schedule: spawns, awaits, sends and loops, with no
closures or interpreter left.

This is the payoff of the static-value machinery for concurrency.

## 3. Tasks

**Stackful, on fixed, lazily committed stacks.**
- Each task gets a reserved range of address space (256 KiB by default,
  set by a flag) with a guard page.
- The kernel commits pages only as they are touched, so a task that uses
  8 KiB of stack costs 8 KiB.
- Overflow hits the guard page and crashes with a message, like the main
  stack.
- A context switch saves and restores the callee-saved registers and the
  stack pointer: a few instructions of assembly in the runtime.

Why not the alternatives:
- **Growable stacks (Go)** move frames, so they need a precise map of every
  pointer on every frame. Under reference counting nothing else needs such
  maps. Keeping it that way is worth the fixed reservation, since address
  space is plentiful on 64-bit.
- **Stackless tasks (Rust's `async`)** would compile each function that can
  suspend into a state machine.
  - IO is world-passing, so the transformation exists: split at each
    suspending operation, and make the rest a join point whose live
    variables become a `Box`.
  - But every function that can transitively suspend would be transformed,
    and recursion through suspension needs heap frames.
  - It is the better choice only if the memory per task (about 8 KiB) proves
    too much, and it can be added later without changing any library.

**Scheduling is cooperative.**
- A task runs until it suspends on IO, a channel, a lock, a timer or an
  `await`.
- A task that computes for long blocks its core. The design answer is the
  second algebra: long pure work goes to futures, which run on every core.
- If fairness turns out to be needed, a check can be put on loop back-edges
  (join points), like Go's preemption points. That can be done without a
  signal handler.

**Semantics.**
- In the reference (Chez), `fork` starts an OS thread; here it starts a task.
- The difference is only visible in fairness and timing, which Idris does
  not specify.
- `03` gets a rule saying so: a task blocking its core without suspending is
  the one behaviour that differs from the reference.

## 4. Memory across cores

The memory model is `memory-model.md`'s: precise reference counting,
borrowing and reuse, Lean's way. Thread-per-core refines it:

- **Heaps per core.**
  - Each core allocates from its own heap: size classes, free lists, no
    locks.
  - An object freed on another core goes to its owner's remote-free list,
    which the owner drains, as mimalloc does per page.
- **Counts are non-atomic by default.** A count is positive while an object
  is owned by one core. Lean's sign convention stays: negative means
  shared (atomic), zero means persistent.
- **At every crossing, move or mark.** When a value is sent to a task on
  another core, or captured by a future, or returned by one to its
  awaiter, the runtime walks it once:
  - each object with count 1 is *moved*: it stays non-atomic, now owned by
    the receiver;
  - each object with a higher count is *marked shared*, as Lean's `markMT`
    does, and its counts are atomic from then on.

  The walk visits each object at most once. It stops at objects already
  shared or persistent.
  - A message built for sending (the usual case) moves entirely, with no
    atomics at all.
  - Sending to a task on the same core costs nothing.
- **Data shared by every core** (configuration, routing tables, a cache
  built at startup) is marked shared once. Reading it through borrowed
  references, which borrow inference gives to functions that only
  inspect, costs no count traffic. A core that stores a reference to it
  pays one atomic increment.
- **Mutable cells shared across cores** (`IORef` behind a `Mutex`): writing
  into a shared cell marks the written value shared, which is the store
  barrier Lean describes and what makes it safe.
- **Futures.** The closure a future runs is marked shared when it may be
  stolen, as Lean's `Task.spawn` does. Its result moves to the awaiter
  when it is unique.

## 5. The kernel interface

All of it goes through syscalls, in keeping with static linking:
- threads are created with `clone`, or through the chosen libc's `pthread`
  if it links statically;
- `sched_setaffinity` pins them;
- per core: `epoll` (edge-triggered), an `eventfd` for wake-ups from other
  cores, and the timer heap's deadline as the `epoll_wait` timeout;
- `io_uring` later, as a second back end for files and batching, behind the
  same scheduler.

## 6. What it does not need

- **A collector, stack maps, safepoints, write barriers on immutable data**,
  or a stop-the-world phase: nothing ever scans a stack.
- **A new language feature or a package of ours:** the libraries of section
  2 are the whole surface.
- **Concurrency at compile time.** The JIT (`next-plan.md` section 3) runs
  only closed pure calls. A future inside one runs synchronously there, on
  a one-core scheduler, with the same runtime code.

## 7. Milestones

After M1–M4:

- **C1: tasks on one core.**
  - Deliverables:
    - `fork`/`threadWait`;
    - `System.Concurrency` made task-aware;
    - `Network.Socket` over `epoll`;
    - timers.
  - Test: an echo server and an HTTP plaintext server under load, on one
    core.
- **C2: thread-per-core.**
  - Deliverables:
    - a scheduler per core, pinned;
    - `SO_REUSEPORT` listeners;
    - cross-core channels with move-or-mark;
    - per-core heaps with remote frees.
  - Test: the plaintext server on every core, against Rust (monoio or
    Glommio, and hyper on tokio), Go's `net/http` and Seastar where they can
    be built.
- **C3: parallel futures.**
  - Deliverables: per-core deques with stealing for `System.Future`, and
    granularity control for parallel loops.
  - Test: parallel `binarytrees`, n-body and mandelbrot, against Rayon, MPL
    and Lean's tasks. MPL's automatic parallelism management (POPL 2024,
    *literature*) is the reference for granularity.
- **C4: `io_uring`** behind the same scheduler, if C2's measurements call
  for it.

## 8. Questions

1. **Placing work on cores.** Idris's libraries have no "fork on core k" and
   no "number of cores". The options:
   - **(a) A runtime policy:** tasks forked by `main` are spread over the
     cores, and tasks forked by a task stay on its core. No API, and it
     gives the web server its shape.
   - **(b) Admit a small set of runtime externs** (`%foreign` names of our
     runtime), which is FFI but also an API of ours.

   I recommend (a) until a program needs more.
2. **Cooperative scheduling**, with loop back-edge checks added only if
   fairness proves necessary. Agreed?
3. **Stack reservation:** 256 KiB per task by default, set by a flag?
