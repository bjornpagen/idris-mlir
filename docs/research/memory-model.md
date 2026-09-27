# The memory model: reference counting or tracing

Status: direction chosen, details open. The model is design A, reference
counting Lean's way (section 7), refined for a thread-per-core runtime
(`concurrency.md`). Experiments 1–3 of section 5 gate the implementation:
if the prototype does not beat MLton, the choice is reopened. It answers
section 2.1 of `next-plan.md`.

This is the most consequential decision in the compiler after the IR itself.
Once programs rely on it, every other runtime feature is built around it:
- threads, and a scheduler of lightweight tasks;
- `epoll` and asynchronous IO;
- arrays updated in place;
- the compile-time JIT.

It therefore has to be chosen for the runtime we want in the end, not for
M1.

**Sources.** The gold standards are Lean 4 (reference counting) and MLton
(tracing, with MPL as its parallel successor). Go, OCaml 5 and Erlang are
read for how a runtime with many threads meets its memory model. Idris's
own C backend is not used as a reference. Each claim is marked by how it
was read:
- *read*: a paper in this repository;
- *code*: a source file in a local clone:
  - Lean 4 at `e21c2cf`;
  - MLton; MPL (MaPLe);
  - Go (`src/runtime`), OCaml 5 (`runtime`), Erlang/OTP
    (`erts/emulator/beam`), Koka;
  - Idris 2 at the pinned `third_party/Idris2`;
- *literature*: known from the literature but not available here. Such a
  claim is not relied on for a conclusion.

## 1. What the model must support

1. **Every program in the profile.** A rejection must name a real limit,
   never a weakness of the memory model (as `PROF-REG-1` was).
2. **The benchmark table.** Scalar code, and code whose data is unboxed
   (SOP), pays nothing.
3. **Allocation-heavy code.** At least MLton's speed, within reach of Lean
   and Koka, on the standard benchmarks.
4. **Many threads.** The goal is a runtime of lightweight tasks multiplexed
   onto OS threads, with `epoll` underneath: Go's shape, done better. That
   means:
   - tens of thousands of tasks, each with its own stack;
   - values passed between tasks;
   - data shared by all of them;
   - parallelism on every core;
   - no pause that grows with the heap.
5. **Predictability.** No tuning needed to run well; peak memory close to
   the live data.
6. **What we build.** Static executables with the kernel as the only
   interface, LLVM through MLIR for code generation, and a compile-time JIT
   that runs the program's own runtime.

## 2. What Idris programs can do to memory

Checked against the pinned Idris 2 sources.

- **Immutable data, strict evaluation.** Fields exist before their
  constructor, so plain data cannot point at itself.
- **Laziness is call-by-name** in the reference backend: `Delay e` compiles
  to `(lambda () e)` (`src/Compiler/Scheme/Common.idr`, `defaultLaziness`,
  *code*). A `Lazy`/`Inf` value can be a closure with no memo cell, so no
  cycle forms through a thunk.
- **Mutation in four places:** `IORef`, `IOArray`, `Data.Linear.Array` and
  `Buffer`. Only these can form a cycle, or make an old object point at a
  new one.
- **Threads.** Base has `System.Concurrency` (`fork`, channels, mutexes,
  condition variables). The profile does not admit it yet.
- **Quantity 1 is linearity, not uniqueness.** Marshall, Vollmer and
  Orchard, ESOP 2022 (*read*):
  - A linear value may not be copied or discarded *later*; a unique one has
    never been copied *before*. A `(1 x : T)` parameter can receive a
    shared value.
  - What linearity gives is that `x` is used exactly once in the body.
  - A linear API with fresh creation (`Data.Linear.Array`'s `newArray`
    continuation) gives uniqueness: nothing else can hold the array.
- **Our compiler leaves little on the heap.**
  - Whole-program monomorphism, static values and choices mean no boxed
    scalars, few runtime closures, and unboxed non-recursive data.
  - What remains is recursive data, strings, bignums, arrays and escaped
    closures.
  - Neither Lean nor Koka has this; both box polymorphic scalars (Counting
    Immutable Beans, "array", *read*).

## 3. The two families

### 3.1 Reference counting with reuse: Lean 4 and Koka

**Mechanism** (Ullrich and de Moura, "Counting Immutable Beans", IFL 2019;
Reinking et al., Perceus, PLDI 2021, both *read*; Lean's `LCNF` passes,
*code*):

- **Ownership.** Each heap object holds a count. A reference is *owned*
  (it holds a count) or *borrowed* (kept alive by an owned one elsewhere).
  Parameters are owned or borrowed per function, inferred over the call
  graph.
  - Lean's `InferBorrow` starts all-borrowed and forces ownership for:
    reset targets, values stored into constructors, and arguments of tail
    calls, so no `dec` ever follows a tail call.
- **Precision.** `inc` and `dec` come from liveness: an object dies at its
  last use, not at the end of its scope. Perceus proves the result garbage
  free (Theorem 4): the heap holds only live data at every step.
- **Reuse.** A cell that dies just before a same-size constructor is built
  is reused for it (`reset`/`reuse`). When the count is 1 at runtime, the
  update is in place.
  - Lean's `ExpandResetReuse` makes a hot path with no `inc` of the fields
    and no store of unchanged fields.
  - Koka's drop and reuse specialization do the same.
  - Pure red-black tree insertion then runs within 10% of C++ `std::map`
    (Perceus, Figure 9). FP² (ICFP 2023, *read*) checks a fragment whose
    functions provably never allocate when their arguments are unique.
- **Arrays** are written in place when their count is 1 (Lean's
  `Array.set`).
- **Freeing is iterative.** Lean's `lean_del_core` threads dying objects
  through an intrusive list, so no stack or extra memory is used
  (`src/runtime/object.cpp`, *code*). A collapse is proportional to what
  dies, and could be made incremental.
- **Threads** (Beans, "thread safety", *read*; `lean.h`, *code*).
  - An object is single-threaded until it is sent to another thread;
    `markMT` then tags it and everything reachable, visiting each object
    at most once.
  - Single-threaded counts are plain increments. Lean encodes the state in
    the sign of the count: positive single-threaded, negative
    multi-threaded (atomic), zero persistent (never counted).
  - Koka copies the scheme (Perceus 2.7.2).
- **Cycles.** Neither collects them. Both argue that only mutable references
  can form them, and leave breaking cycles to the programmer, as Swift does.

**Measured.**
- *Perceus* (Figure 9, *read*):
  - Koka is fastest on `rbtree`, `rbtree-ck`, `deriv`, `nqueens` and `cfold`
    against OCaml, GHC, Swift and Java, except where C++ mutates in place.
  - Peak memory is the lowest except OCaml's on two benchmarks.
  - Reuse halves `rbtree`.
  - Atomic counts on every object cost 5% (`rbtree`) to 59% (`nqueens`).
- *Beans* (*read*; normalized to Lean; i7-3770).

  | benchmark | MLton | MLKit | OCaml | GHC |
  | --- | ---: | ---: | ---: | ---: |
  | `deriv` | 0.98 | 4.22 | 1.51 | 2.23 |
  | `const_fold` | 1.15 | 4.59 | 5.11 | 2.73 |
  | `qsort` | 0.54 | 3.17 | 1.37 | 1.76 |
  | `rbmap` | 3.25 | 6.49 | 1.03 | 2.44 |
  | `rbmap_1` (every tree kept, heavy sharing; Lean itself 4.72) | 4.43 | 15.50 | 9.20 | 14.66 |

  - Lean's own ablations: disabling reuse costs up to 3.2× (`rbmap`),
    disabling borrowing up to 1.16×, and atomic counts everywhere up to
    2.4×.
  - Share of runtime spent freeing or collecting: Lean 3–28%, MLton 21–37%,
    OCaml up to 90%.

### 3.2 Tracing: MLton, and its parallel successor MPL

**MLton** (*code*: `runtime/gc`; the Beans table above).
- **Collectors.** A Cheney copying collector and mark-compact, with a
  generational nursery and card marking. Allocation bumps a pointer.
- **Roots.** MLton manages its own stack with frame layouts. That is how it
  finds and moves roots precisely, without help from a C or LLVM stack.
- **Measured.** The strongest tracing system on Lean's suite: equal or
  better where sharing dominates (`deriv`, `rbmap_1`) and where arrays of
  unboxed integers dominate (`qsort`). It is 3.25× slower where reuse
  applies (`rbmap`).
- **Threads.** It runs on one core. `MLton.Thread` gives user-level threads
  there.

**MPL** (*code*: `README.md`, `runtime/gc/hierarchical-heap.h` and the
entanglement files; the papers it cites, *literature*):
- MLton extended to multicore, for **fork-join** parallelism (`par`,
  `parfor`, `reduce`).
- **The heap follows the task tree.** Each task allocates into its own leaf
  heap and collects it without synchronizing with other tasks. At a join,
  the child's heap merges into the parent's (hierarchical heaps,
  disentanglement).
- Communication that breaks the tree discipline ("entanglement") is
  detected and handled at extra cost.
- It scales to hundreds of cores and terabyte heaps, but:
  - it generates only C code;
  - its GC is disabled outside parallel sections, so a mostly sequential
    program's memory grows unbounded (README, "Known Issues").
- It is the best parallel functional GC, but it is built for fork-join
  computation, not for many long-lived communicating tasks.

### 3.3 How runtimes with many threads do it

- **Go** (`mgc.go`, `proc.go`, `stack.go`, `netpoll.go`; *code*).
  - **GC.** A concurrent, precise, parallel mark-sweep collector with a
    write barrier; non-generational and non-moving. It has short
    stop-the-world phases and a pacer (`GOGC`: the next cycle at twice the
    live heap by default).
  - **Scheduler.** M:N: goroutines on OS threads through per-processor run
    queues, with an integrated poller (`epoll`) that returns ready
    goroutines to the scheduler.
  - **Stacks** start small and grow by copying (`copystack`), which needs
    precise pointer maps for every frame.
  - The collector must scan every goroutine's stack, and uses about twice
    the live memory by design.
- **OCaml 5** (`minor_gc.c`, `domain.c`, `fiber.c`, `caml/fiber.h`;
  *code*).
  - **Domains** (OS threads) each have a minor heap. The shared major heap
    is marked and swept concurrently.
  - **Minor collections stop every domain** (the `_stw` functions).
  - **Fibers** (for effect handlers) have small stacks that grow by
    reallocation and are scanned through frame descriptors.
- **Erlang** (`erl_gc.c`, `erl_message.c`, `erl_binary.h`; *code*).
  - **A heap per process**, collected by a generational copying collector
    that stops only that process.
  - **Messages are copied** into the receiver's heap (`copy_struct`).
  - **Large binaries live off-heap and are reference counted**
    (`erts_refc_t`), shared rather than copied.
  - Isolation makes collection local and pause-free for everyone else.
    Sending costs the size of the message.

### 3.4 What a scheduler of many tasks needs from memory

| need | reference counting | tracing |
| --- | --- | --- |
| **Roots on task stacks** | None: nothing scans stacks. Stacks can be fixed-size `mmap`s with guard pages (committed lazily, so 10⁵ tasks cost address space, not memory), segmented, or stackless state machines. | Every stack must be scanned: precise stack maps through LLVM (statepoints) or MLton-style frames of our own, and a way to stop or cooperate with each task. Growable stacks (Go) need the same maps to move frames. |
| **A value sent to another task** | Lean: marked multi-threaded once, at the send; atomic counts on it from then on. Or Erlang-style: copied, and counts stay non-atomic. | Free with a shared heap (Go); a copy with per-task heaps (Erlang); a promotion in MPL. |
| **Data read by all tasks** | Read through borrowed references it costs no count traffic; owned references mean atomic operations on a shared cache line. | Free to read; the collector traces it on every cycle. |
| **Parallel allocation** | Per-thread allocator caches, as mimalloc has. | Per-thread nurseries or allocation buffers. |
| **Pauses** | None global. A task freeing a large structure pays for it, and can do so incrementally. | Stop-the-world phases (short in Go, per-minor-collection in OCaml 5), plus concurrent marking whose cost is spread over the program. |
| **Cycles** | Only through mutable cells (section 2); leak, forbid, or collect them there. | Free. |
| **In-place update of immutable data** | At runtime, when the count is 1 (FBIP, arrays). | Only with uniqueness proved statically: linear arrays, or copy. |
| **Engineering** | Compiler passes (Lean's order exists and ports to our IR) and a small runtime. | A generational or concurrent collector, precise roots through LLVM, and pacing. Go's took years. |
| **The compile-time JIT** | Runs the runtime in-process; nothing to register. | Must register the JIT's frames with the collector. |

## 4. Three designs

**A. Reference counting everywhere, Lean's way.**
- Non-atomic counts. An object is marked multi-threaded (negative count,
  atomic) when it is sent to a task on another thread or written into a
  shared mutable cell.
- Persistent objects (literals, constants, compile-time results) are never
  counted.
- Borrowing and reuse as in Lean. Tasks are stackful, on fixed `mmap`
  stacks.
- *For:*
  - it is the best measured on sequential functional code;
  - no roots or stack maps, which makes tasks, the JIT and `epoll`
    integration simple;
  - prompt, predictable reclamation, and in-place updates for free.
- *Against:*
  - data shared across threads pays atomic counts, and a hot shared object
    is a contended cache line;
  - cycles through mutable cells;
  - the code carries count operations.

**B. A heap per task, with reference counting inside (Erlang's topology,
Lean's mechanism).**
- Counts are never atomic.
- Sending copies the value into the receiver's heap, or moves it when its
  whole graph is uniquely owned.
- Truly shared data lives in an explicit shared region with atomic counts
  (Erlang's off-heap binaries), for large strings and arrays.
- *For:*
  - no atomic operations and no contention by construction;
  - a task's memory dies with it;
  - it matches immutable semantics (a copy is indistinguishable).
- *Against:*
  - sending costs the message's size;
  - large shared read-mostly structures need the explicit region;
  - it is further from Go's model of shared memory.

**C. Tracing, MLton's way, extended for threads.**
- A generational copying collector per thread (nursery), with a shared
  mature heap marked concurrently (OCaml 5 / Go).
- Precise roots through LLVM statepoints, or our own frames.
- *For:*
  - cycles are free;
  - sharing costs nothing at runtime;
  - no count operations in the code;
  - MLton's measurements on sharing-heavy code.
- *Against:*
  - the largest runtime by far (concurrent marking, write barriers for
    mutable cells, pacing);
  - stack maps through LLVM;
  - the collector must stop or cooperate with every task;
  - pauses and a memory multiple;
  - no in-place update of immutable data without static uniqueness;
  - 3× slower than reference counting with reuse on update-heavy code
    (`rbmap`).

**Where the evidence points.**
- For the sequential core: A or B. Their mechanism is the same, and it is
  the one measured best.
- For many threads, the question between A and B is whether our programs
  share big data across threads (then A) or mostly pass messages (then B).
- C buys cycles and free sharing at the cost of the hardest runtime to
  build and the loss of reuse.

A and B can also be combined: per-task heaps with non-atomic counts by
default, and Lean's marking for the objects that are genuinely shared, so
sharing is paid for only where it happens.

The choice (section 7) is A, refined by B's topology where the runtime's
shape makes it free: heaps per core, and move instead of mark when a value
crossing cores is unique.

## 5. Experiments that decide it

With the direction chosen (section 7), experiments 4 and 5 are no longer
needed. Experiments 1–3 gate the implementation, and 6 decides cycles.

Each has a measurable pass criterion. MLton is in `.toolchain/mlton`.
- Git clones from GitHub work in this container: Lean, Koka, MPL, OCaml,
  Go and OTP are cloned.
- Their prebuilt toolchains have not been tried; building from source may
  be needed.
- Idris's Chez backend gives a baseline for everything.

1. **The sequential suite, in Idris.**
   - Port `rbtree`, `rbtree-ck`, `deriv`, `nqueens`, `cfold`,
     `binarytrees`, `qsort` and `unionfind` (Lean's and Koka's suites) into
     `bench/`, next to SML (MLton) and C versions.
2. **A hand-lowered prototype of A.**
   - For `rbtree`, `deriv` and `binarytrees`, write the `llvm` dialect our
     lowering would emit: the header, `inc`/`dec`, reset/reuse with hot and
     cold paths, the iterative free, and a per-thread size-class allocator
     (or mimalloc).
   - **Pass:** faster than MLton on each, within 1.2× of Lean's or Koka's
     C, with peak memory at most MLton's.
3. **The cost of threads under A.**
   - The same prototype with multi-threaded marking, on three programs:
     - a parallel `binarytrees` (work split across threads, nothing shared);
     - a read-mostly shared map read by every thread;
     - a pipeline of tasks passing trees through channels.
   - Measure the time lost to atomic counts and contention against the
     single-threaded version.
   - **Pass:** no worse than Go on the same programs. Go is the bar we
     claim to beat.
4. **B's send cost.** The pipeline of experiment 3 with copying and with
   unique moves. Measure throughput against message size.
5. **C's price.**
   - Build MLton-style precise roots on a small LLVM program through
     statepoints.
   - Measure code size and speed against the same program without them.
   - This tells us what C costs before a collector is written.
6. **Cycle census.** In Idris 2's base and contrib libraries, and in the
   programs of 1–4, which mutable cells can hold a value that reaches a
   mutable cell of the same type? This is a type-graph question, answered
   statically.

## 6. Questions still open

1. **Cycles through `IORef`/`IOArray`:**
   - leak (as Lean, Koka and Swift do);
   - reject statically (a mutable cell whose content type can reach a
     mutable cell); or
   - collect only among mutable cells?

   Experiment 6 informs this.
2. **The allocator:**
   - vendor mimalloc (a submodule, MIT, per-thread heaps with remote frees,
     which is what `concurrency.md` needs); or
   - write a size-class allocator in the runtime.

## 7. The direction: Lean's model, for a thread-per-core runtime

Chosen: design A.
- **Why.** The target runtime is thread-per-core with explicit execution
  algebras (`concurrency.md`), not Go's shared heap with migrating
  goroutines. In it, almost every object is touched by one core, so
  counts are non-atomic almost everywhere. Sharing is paid only at
  explicit crossings.
- **Not tracing (C).** Tracing's advantages (free sharing, cycles) matter
  least in this runtime, and its costs (stack maps through LLVM, a
  concurrent collector, losing reuse) are the highest.
- **Not B alone.** B's copying is replaced by move-or-mark: a unique value
  moves across cores untouched, and only genuinely shared data becomes
  atomic.

**The compiler side** (Lean's `LCNF` impure pipeline, ported to `Code Mem`;
`Passes.lean`, *code*):
1. **Rep first.** Only `Rep`s with pointers carry a count: `Box`, `Str`,
   `Big` above the small range, `Arr`, and an escaped closure. SOP values
   and scalars never do.
2. **`insertResetReuse`** (Beans' `R`/`D`/`S`, with join points), before
   counts exist.
3. **`inferBorrow`**, Lean's dataflow over the call graph, seeded by QTT:
   - a quantity-1 parameter never needs a `dup` in its callee, and is
     owned when its one use consumes it;
   - a quantity-0 parameter is erased and never counted.
4. **`explicitRc`**: `inc`/`dec` from liveness, with derived borrows
   (projections of a borrowed value are borrowed).
5. **`expandResetReuse`**: hot and cold paths, no field increments or
   stores of unchanged fields on the hot path.
6. **`coalesceRC`**: merge increments and decrements per block.
7. **Drop specialization** (Koka): an inlined `dec` specialized to the
   constructor where the fields are used.

**The runtime side:**
- An 8-byte header: a 32-bit count (sign for the sharing state, 0 for
  persistent), then the kind and constructor tag.
- Per-core heaps and move-or-mark at crossings (`concurrency.md` section 4).
- Iterative freeing through an intrusive list (Lean's `lean_del_core`).
- Arrays written in place when their count is 1.
  `Data.Linear.Array` writes skip the check, since its API creates the
  array fresh inside a linear continuation (section 2).
- Persistent static data for literals, constants and compile-time results.
- `Lazy` stays call-by-name, as in the reference.

**What is checked before it is built:** experiments 1–3 of section 5. The
prototype must be faster than MLton on `rbtree`, `deriv` and
`binarytrees`, within 1.2× of Lean's or Koka's C, and experiment 3 (now:
per-core heaps, move-or-mark, a pipeline across cores and shared
read-mostly data) must show atomics only where values are genuinely
shared.
