# The plan

This is the only plan. It replaces every earlier plan and research note
(`refactor-and-memory`, `next-plan`, `memory-model`, `concurrency`, the v2
and v3 entry notes, the research briefs); git keeps them. The normative
specification stays in [architecture/](architecture/00-index.md), and its
[roadmap](architecture/15-roadmap.md) records what is done.

Every step below ends at a stop point where the user reviews it, and no
step ends on a promise to fix something later (AGENTS.md, 16).

## 1. Where we are

**Implemented:** profile versions p0 to v3 (`docs/architecture/VERSION`
is `v3`).
- Checked TT, from the stock Idris 2 frontend at the pinned revision,
  becomes full Core.
- `Simplify`, a two-level evaluator, turns full Core into first-order Core
  with join points:
  - one driver: positive supercompilation with a whistle and upward
    generalization, `ELIM-G-19`;
  - choices for static values picked at runtime, `ELIM-G-20`;
  - loops as recursive join points, `CORE-LOOP-1`.
- `Emit` writes the `idr` dialect with `cf` blocks, and the C++ passes
  lower it to LLVM.
- Programs are heap-free: whatever cannot be computed away at compile time
  is rejected with the rule it breaks.

**Benchmarks** (`bench/`, best of 5, seconds; x86-64, 4 CPUs):

| benchmark | this compiler | Idris Chez | MLton | gcc -O2 |
| --- | ---: | ---: | ---: | ---: |
| nbody | 0.342 | 6.409 | 1.351 | 0.340 |
| mandelbrot | 0.358 | 5.459 | 0.516 | 0.369 |
| fib | 0.111 | 3.375 | 0.290 | 0.067 |
| tak | 0.124 | 1.314 | 0.185 | 0.104 |
| collatz | 0.470 | 21.272 | 1.969 | 0.591 |
| ack | 0.002 | 1.027 | 0.089 | 0.039 |
| ackdyn | 0.213 | 1.018 | 0.088 | 0.039 |
| harmonic | 0.256 | 6.655 | 0.641 | 0.258 |

**What stops us.** `Integer`, strings built at runtime, recursive data and
closures have no runtime representation. So:
- Every one of them must be computed away at compile time.
- `Simplify` has had to be an interpreter as well as a specializer:
  - `printLn 'x'` takes 5.7 s to compile, because the Prelude turns `'x'`
    into a `Nat` of 120 constructors and the driver evaluates it;
  - a list whose length depends on input is rejected (`PROF-DATA-3`);
  - so is a runtime `Integer` (`PROF-TYPE-4`).

**Also open from v3:**
- **n-body over `Vect 3 Double`** returns a static value from a runtime
  loop (section 8.1).
- **`main : Int` programs cannot import the Prelude** (`PROF-PROG-1`), and
  the Prelude is never imported implicitly.
- **`Data.Vect.transpose`** takes its length at runtime quantity. It
  compiles once `Nat` exists at runtime.

## 2. Decisions

Settled, and the rest of the plan builds on them:

1. **No language design, and no package of our own.**
   - Programs use Idris's own libraries: the Prelude, base, contrib,
     linear and network.
   - The compiler implements their primitives.
   - Our `idris-mlir-io` package is removed (section 9).
2. **Every value gets a runtime representation** (section 3). After that,
   compile-time evaluation is an optimization, never a requirement.
3. **Memory is reference counting, Lean's way** (section 4):
   - precise counts;
   - borrowing and in-place reuse;
   - a heap per core;
   - move-or-mark where values cross cores.

   A prototype must beat MLton before it is built.
4. **Concurrency is thread-per-core** (section 7). The execution algebras
   are Idris's own libraries: `fork`, `System.Concurrency` and
   `System.Future`.
5. **Everything but the operating system's interface is linked statically**
   (section 5), as Go does.
   - **Linux:** the interface is the kernel's syscalls, so executables are
     fully static on musl. musl and GMP are vendored as pinned git
     submodules, and the toolchain itself (GCC's target, LLVM/MLIR and our
     C++ tools, `idr-jit` included) is built on musl, so compile time and
     runtime share one libc.
   - **macOS** (a later target): the interface is `libSystem`, since Apple
     does not keep the syscall interface stable, so executables link
     `libSystem` dynamically and everything else statically.
6. **Compile-time evaluation is one JIT path** (section 6). It runs the
   compiler's own pipeline and the program's own runtime, and has no
   features of its own.
7. **Semantics are upstream Idris's.** A compiled program means what the
   Idris language and its libraries say it means.
   - The Chez backend is a test oracle, not the definition.
   - What Idris leaves to the implementation stays ours to choose:
     - the exact results of `exp`, `sin` and the other math functions
       (whatever libm the platform uses);
     - scheduling fairness and timing;
     - stack depth (as long as recursion the reference runs, runs).
   - Differential tests against Chez therefore compare everything but those.
8. **The repository has no Python** (section 9). Tests are Idris golden
   tests, as in Idris 2 itself, and the vendored research library is kept
   and reorganized.

## 3. Representations

`Rep` is computed once per monomorphic runtime type, from the flags Idris
computed:

| Idris type | `Rep` | At runtime |
| --- | --- | --- |
| `Int`, `Bits*`, `Int*`, `Double`, `Char` | `Scalar` | a register; as today |
| `Integer` | `Big` | a 63-bit integer tagged in an `i64`, or a pointer to a GMP integer when it overflows (Lean's scalar `Nat`/`Int`, GHC's `IS`/`IP`) |
| `Nat`-like (`Nat`, `Fin`, …) | `Big`, non-negative | Idris marks such types by constructor flags (`ZERO`/`SUCC`, `Core/CompileExpr.idr`), which its own backends use to represent them as integers; `S`, `Z` and matches become arithmetic |
| `String` | `Str` | UTF-8 bytes with their length in scalars and an ASCII flag, counted, or a literal in `.rodata` (see below) |
| `UNIT`, erased, `%World` | none | nothing |
| enumerations | `Sop` of empty products | a tag |
| non-recursive data, records | `Sop` | unboxed into registers and fields; slots shared by type (`LOW-DATA-1`) |
| `Maybe` of a pointer | the pointer | null is `Nothing` |
| recursive data | `Box` | a counted heap cell; nullary constructors are immediates |
| a closure that must exist at runtime | `Sop` over the lambda labels that reach it, or `Box` | defunctionalized; a finite set is already a choice (`ELIM-G-20`) |
| `Lazy`, `Inf` | a closure | call-by-name, as the reference (no memo cell) |
| `ArrayData a` | `Arr (Rep a)` | struct of arrays: `Arr (Sop [[a, b]])` is two arrays |

**Arrays and strings are Idris's primitives.** They are the ones every
backend implements, so we add no library and no API.

| Primitive | Op |
| --- | --- |
| `prim__newArray n x` | `idr.array.new` |
| `prim__arrayGet a i` | `idr.array.get`, with a trapping bounds check (Idris leaves them unchecked; we never miscompile) |
| `prim__arraySet a i x` | `idr.array.set`, with the same check |
| `prim__getStr` (`getLine`) | `idr.io.get_line` |
| `strLength`, `strHead`, `strTail`, `strIndex`, `strCons`, `strAppend`, `strReverse`, `strSubstr`, `fastPack`, `fastUnpack`, `fastConcat` | `idr.str.*` |

- **Arrays are mutable.** `IOArray` and `Data.Linear.Array` (which is
  `unsafePerformIO` over `IOArray`) write in place always, whatever the
  counts; counts decide only when an array is freed.
- **Array ops carry `MemoryEffects`** on the array resource, so neither
  MLIR nor LLVM reorders a load across a store to the same array.
- **Arrays do not alias across allocation sites.** Arrays from different
  `prim__newArray` calls get distinct alias scopes.
- **Strings are sequences of Unicode scalar values** (`SEM-STR-1`).
  `strLength` counts scalars and `strIndex` indexes by scalar, as Chez does.
  The layout trades these against output, which is UTF-8 (`SEM-IO-2`):

  | Layout | Output | `strLength` | `strIndex` | Memory |
  | --- | --- | --- | --- | --- |
  | UTF-32 | transcode | O(1) | O(1) | 4 bytes per scalar |
  | UTF-8 alone | as is | O(n) | O(n); the Prelude's `unpack` loops over `strIndex`, so O(n²) | 1–4 bytes |
  | **UTF-8, scalar count, ASCII flag** (chosen) | as is | O(1) | O(1) when ASCII; otherwise through breadcrumbs, a byte offset every 64 scalars built on first index (Swift's scheme, *literature*) | 1–4 bytes, +1/16 for indexed non-ASCII strings |

- **Strings are immutable.** When the left string of `strAppend` is unique
  and has room, the append can extend it in place (Lean's `String.append`).
- **One world.**
  - Every effectful op consumes and produces the world (`CORE-INV-9`).
  - `unsafePerformIO` in library code takes the current world where it is
    evaluated, so it is sequenced in strict left-to-right order.
  - A function that reaches an IO primitive is *effectful* (section 8.3).
  - Calls to an effectful function are never deferred, duplicated,
    dropped or evaluated at compile time.
- **Indexed vectors do not imply contiguous storage.** `Vect` is a list:
  `Sop` when its shape is static, `Box` when not.

## 4. Memory management

### 4.1 Why reference counting

The full comparison is recorded in git (`docs/research/memory-model.md`
at `a4eae0a`). In short:
- **Measured best on functional code.**
  - Lean 4 against MLton, OCaml and GHC (Counting Immutable Beans, IFL
    2019, and its tables):
    - Lean beats MLton 3.25× on red-black tree updates;
    - MLton matches Lean or beats it only where sharing or arrays of
      unboxed integers dominate;
    - MLton spends 21–37% of its time in GC and OCaml up to 90%, against
      Lean's 3–28% freeing.
  - Koka (Perceus, PLDI 2021) is fastest on all five allocation benchmarks
    against OCaml, GHC, Swift and Java, within 10% of C++ `std::map`, with
    the lowest peak memory.
  - Appendix A has the tables.
- **Nothing scans a stack.**
  - No stack maps through LLVM, no safepoints, no stop-the-world.
  - This makes stackful tasks, the JIT and `epoll` integration simple.
  - Tracing would need MLton's own frames or LLVM statepoints, and a
    concurrent collector.
- **A thread-per-core runtime makes almost every count non-atomic.**
  Sharing is paid only where values cross cores, which the runtime sees
  (section 7). Tracing's advantages (free sharing, cycles) matter least
  here.
- **Cycles can only form through mutable cells** (`IORef`, `IOArray`,
  `Buffer`):
  - Idris data is immutable and strict;
  - laziness is call-by-name in the reference backend, so there are no memo
    cells;
  - how to treat them is open (section 12).

### 4.2 The compiler side

Lean's impure pipeline (its `LCNF` passes, which are A-normal form with join
points like ours), ported to `Code Mem`, in Lean's order:

1. **Counting follows `Rep`.** Only `Box`, `Str`, `Big` above the small
   range, `Arr`, and escaped closures carry a count. Scalars and SOP
   values never do, so today's benchmarks pay nothing.
2. **`insertResetReuse`.** A cell that dies before a same-size constructor
   is built is reused for it (Beans' `R`/`D`/`S`, with join points).
3. **`inferBorrow`.** Parameters are owned or borrowed, by a dataflow over
   the call graph.
   - Ownership is forced for: reset targets, values stored into
     constructors, and tail-call arguments, so no `dec` ever follows a
     tail call.
   - QTT seeds it: a quantity-1 parameter never needs a `dup` in its
     callee, and a quantity-0 one is never counted.
   - Soundness never depends on quantities. Liveness decides every count,
     and quantities only choose where inference starts.
4. **`explicitRc`.** `inc`/`dec` from liveness, with derived borrows (a
   projection of a borrowed value is borrowed). The result is garbage
   free: the heap holds only live data (Perceus, Theorem 4).
5. **`expandResetReuse`.** Hot and cold paths: on the hot path, no
   increments of the fields and no stores of unchanged fields.
6. **`coalesceRC`.** Increments and decrements are merged per block.
7. **Drop specialization** (Koka). A `dec` is inlined, specialized to the
   constructor, where its fields are used.

### 4.3 The runtime side

- **An 8-byte header**: a 32-bit count, then the kind and the constructor
  tag. The count's sign is the sharing state, as in Lean:
  - positive: owned by one core, plain arithmetic;
  - negative: shared, atomic;
  - zero: persistent, never counted;
  - a count that overflows sticks, and its object is never freed.
- **A heap per core**: size classes and free lists with no locks. A remote
  free goes to the owner's queue, which the owner drains.
- **Freeing is iterative**, through an intrusive list of dying objects
  (Lean's `lean_del_core`). It uses no stack, and a large free can be
  spread over time.
- **Persistent static data.** Literals, constants and compile-time results
  live in `.rodata`/`.data` with count 0.
- **Move-or-mark at crossings.** Where a value crosses cores (section 7.4),
  one walk:
  - moves each object whose count is 1: it stays non-atomic, now owned by
    the receiver;
  - marks shared each object with a higher count, as Lean's `markMT` does.

  Sending on the same core costs nothing.

  This is as sound as the counts themselves. A count of 1 means the
  reference being sent is the only one. Anything the sender still uses
  after the send (including a field it projected) was counted separately by
  the same liveness that makes single-threaded code correct, so it has a
  count of 2 or more and is marked, not moved.

### 4.4 The gate: a prototype before the compiler work

1. **The benchmark suite, in Idris.** Port Lean's and Koka's allocation
   benchmarks (`rbtree`, `rbtree-ck`, `deriv`, `nqueens`, `cfold`,
   `binarytrees`, `qsort`, `unionfind`) into `bench/`, next to SML and C
   versions. Run them on the Chez backend as a baseline.
2. **Hand-lowered code.** For `rbtree`, `deriv` and `binarytrees`, write
   the `llvm` dialect our lowering would emit (header, counts, reset/reuse
   hot and cold paths, iterative free) on the per-core allocator.
   - **Pass:** faster than MLton on each, within 1.2× of Lean's or Koka's
     generated C, with peak memory at most MLton's.
3. **Threads.** The same prototype with move-or-mark, on three programs:
   - a parallel `binarytrees` (nothing shared);
   - a shared read-mostly map read by every core;
   - a pipeline passing trees between cores.
   - **Pass:** atomics appear only on genuinely shared data, and each
     program is no slower than Go's version.

If the gate fails, the memory decision is reopened with the numbers.

## 5. Runtime and linking

### 5.1 Static except the OS interface

On Linux there is no `ld.so` and no shared library; the kernel's syscalls
are the only interface, as with Go. (On macOS the interface is `libSystem`,
section 5.5.) `TEST-HEAP-1` (only `write`, `read`,
`_exit` and libm) becomes a check that every executable has no `INTERP` and
no `DYNAMIC` section. Executables are static-PIE (musl's `rcrt1.o`), so
they keep address-space randomization.

### 5.2 The C library: musl

Chosen over LLVM's libc, from both sources. A libc is a Linux-only choice:
on macOS the C library is `libSystem`, whichever we pick here.

| | musl 1.2.6 (clone of a GitHub mirror) | LLVM libc (the pinned `llvm-project/libc`) |
| --- | --- | --- |
| Status on Linux | mature: Alpine; the static Linux targets of Rust and Zig | its own docs, `full_host_build.md`: "missing many critical functions needed to build non-trivial applications … we recommend sticking with your system libc" |
| What our runtime needs | all present: `clone`, `epoll`, `eventfd`, `timerfd`, `sched_setaffinity`, pthreads, sockets, `getaddrinfo` | `epoll`, sockets and pthreads present; no `eventfd`, `timerfd`, `clone` or `getaddrinfo` wrappers |
| C++ on top | GCC targets `x86_64-linux-musl`, and libstdc++ and LLVM build on it | libstdc++ does not support it; it is built with Clang, and we build with GCC |
| DNS when static | works (reads `/etc/resolv.conf`; no NSS) | no `getaddrinfo` |
| Math (double) | `exp`, `log`, `pow`: ARM's optimized routines, the code glibc uses; `sin`, `cos`, `tan`, `asin`, `acos`, `atan`: FreeBSD's msun, not correctly rounded | correctly rounded in every rounding mode for `exp`, `log`, `sin`, `cos`, `tan`, `asin`, `acos`; `pow` and `atan` within 1 ULP (`docs/headers/math/index.rst`) |
| Licence | MIT | Apache 2.0 with LLVM exception |

The C++ row decides it. The JIT server must run the program's own runtime
on the program's own libc (section 6), so its process (LLVM, MLIR, our
C++) must be built on that libc. With musl the whole toolchain can be; with
LLVM's libc it cannot.

**Math is not a criterion.** The results of the math functions are
implementation-defined (decision 7). musl's are deterministic across x86-64
machines (plain C on SSE), which is all the JIT needs: compile time and
runtime run the same code.

**What musl costs:**
- **`memcpy` is a simple `rep movsq`**, slower than glibc's vector copies
  on large blocks. Our generated code copies little, and a measured
  problem would be met by a better `memcpy` in the runtime.
- **Its `malloc` (mallocng) is slow.** We use our own allocator
  (section 4.3); musl's only serves musl itself.

**The toolchain becomes musl-based.**
- `bootstrap` builds musl, then a GCC that targets `x86_64-linux-musl`
  (GCC supports it upstream; `musl-cross-make` is the reference recipe).
- LLVM/MLIR and our C++ tools are rebuilt with it, static.
- The Idris compiler itself still runs on Chez, on the host's libc: it is a
  host program and never links into an executable.
- **Cost:** one more GCC build in the bootstrap, and an LLVM rebuild.

**The pin.** musl's official repository (`git.musl-libc.org`) is
unreachable from this environment; `github.com/kraj/musl` mirrors it and
is reachable. The submodule is pinned to a release tag by commit, and the
tag's hash is checked against the official release tarball's signature
where that can be fetched.

### 5.3 Bignums: GMP

- **GMP** is a git submodule under `third_party/gmp` from a GitHub mirror
  (gmplib.org, and its Mercurial repository, are unreachable here), pinned
  to a release. It is built with `--disable-shared` against musl, with its
  memory functions pointed at our allocator.
- **Nothing in LLVM replaces it.**
  - `APInt` has a fixed width, and its multiply and divide are schoolbook.
  - `DynamicAPInt` is arbitrary-precision with a 64-bit fast path, but it
    is a C++ compiler-internal class built on `APInt`, and it would bring
    libstdc++ into every executable.
  - LLVM libc's `BigInt` has a width fixed at compile time; it serves its
    printf and math internals.
- **mini-gmp** (GMP's one-file subset) is quadratic, and Lean's own `mpn`
  fallback is a C++ reimplementation. GMP has assembly kernels for x86-64
  and asymptotically fast multiplication.
- **Licence.** GMP is LGPL v3 (or GPL v2). A static executable must be
  relinkable against another GMP; shipping our object files satisfies
  that. `PINS.md` and the licence notes say so.

### 5.4 The runtime

The runtime is C, compiled by the musl GCC into one static archive in
`runtime/`. It contains:
- the allocator and counts (section 4.3);
- bignums over GMP;
- strings (section 3);
- the scheduler, stacks, `epoll`, timers and the blocking pool (section 7);
- the crash, output and number-printing paths that are LLVM-dialect
  helpers today (`Lower/Runtime.mlir.inc`, which shrinks accordingly).

**The allocator:** vendored mimalloc (per-thread heaps and remote frees are
what section 4.3 needs), or our own size classes (section 12).

### 5.5 Platforms

The runtime is written against a narrow OS layer, so that macOS is a port
of that layer and not a redesign:

| Need | Linux (first) | macOS (later) |
| --- | --- | --- |
| The OS interface | syscalls, through static musl | `libSystem`, linked dynamically |
| Executable | static-PIE ELF | Mach-O, PIE |
| Readiness | `epoll`; `eventfd` for wake-ups; the timer heap's deadline as the timeout | `kqueue`; `EVFILT_USER` for wake-ups; `EVFILT_TIMER` or the same deadline |
| Files and DNS | the blocking pool, then `io_uring` | the blocking pool |
| Threads | `clone` or musl's pthreads; `sched_setaffinity` pins them | pthreads; no hard affinity (affinity tags are hints), so "per core" means one scheduler per CPU, unpinned |
| Per-thread data (the stack limit, the core's scheduler) | static TLS | thread-local variables (TLV) |
| JIT memory | `mmap` read-write, then read-execute | `MAP_JIT`, toggled with `pthread_jit_write_protect_np` on Apple silicon |
| Toolchain | the musl GCC; LLVM/MLIR static on musl | Apple's SDK and linker; LLVM/MLIR on `libSystem` |
| Bignums | GMP, static | GMP, static |

- **The one-libc rule still holds on macOS:** `idr-jit` and the executables
  both use `libSystem`.
- **What macOS loses:** hard pinning of threads to cores, and `io_uring`.
  Thread-per-core becomes one scheduler per CPU that the OS may move.

## 6. Compile-time evaluation: one JIT path

**The rule: the server has no features of its own.** It is the compiler's
own pipeline and the program's own runtime, run at compile time.
- A computation can be evaluated at compile time only if the compiler can
  already compile it for runtime.
- The server gets `Integer` in the same step as executables do, and not
  before.
- What the compiler cannot compile yet is never evaluated early.

**What goes.**
- `Simplify/Fold.idr`, the Idris copy of every primitive's semantics:
  - Chez's `number->string` standing in for our Ryu printer;
  - Chez's bignums standing in for GMP.
- Driving a call because all its arguments are known.
- The count of unfoldings in a row without code that bounds that today.
- `SEM-BIG-1` (Integer at compile time only).
- `Nat` as a chain of `S` at compile time.

**What stays, because it is specialization, not evaluation.**
- Beta (G1), known constructor (G2), specialization (G3), static let (G4),
  arity raising (G5) and force of delay (G8).
- The driver's unfolding on static structure (G19), choices (G20) and
  output fusion (G7).
- A string's static structure: `Append` trees of pieces.
- Whether joining two literal pieces is data layout or a primitive for the
  server is open (section 12).

**The server**, `idr-jit`, a C++ tool in `foreign/idr/tools`:
- **One libc.** It is a static musl executable like the programs, with the
  runtime archive linked into it.
  - JIT'd code calls only runtime entry points, and they are bound to the
    server's own copies through an absolute-symbol table generated at
    build time.
  - Loading a second copy of the runtime or of libc into the process would
    duplicate the allocator, `errno` and stdio state.
- **Start-up.** The compiler starts it once per compilation (Idris's
  `popen2`). It creates an ORC `LLJIT` with no compile threads (it forks,
  and a process with threads must not), and compiles one entry point per
  primitive.
- **Requests.**
  - `prim op args`: a call, no code generation, about 10–30 µs a round
    trip.
  - `define module`: the MLIR of closed specializations, lowered by our own
    pipeline at `-O1`, about 5–50 ms.
  - `call f args`: runs a defined function, in a forked child
    (copy-on-write pages, about 100 µs).
- **Values on the wire.** Scalars, bytes, GMP limbs, and constructor trees
  are encoded compactly. Functions and worlds never cross: a closed call of
  function type is deferred anyway (G5), and a call that takes the world is
  not closed.
- **Crashes and divergence are values.**
  - A runtime crash, running out of fuel, or exceeding a memory cap returns
    `stuck`, and the call stays in the residual program, where it crashes or
    runs as written.
  - Fuel is deterministic, not a timeout: in JIT mode, `idr-lower` counts at
    function entries and loop back-edges, and the runtime counts allocated
    bytes. The same input therefore gives the same output everywhere
    (`FE-DET-1`).
- **Results are cached** per configuration for the compilation.
- **Cross-compilation** (later) cannot run target code on the host.
  - Integer semantics are fixed-width. Math function results are
    implementation-defined, so a host libm is acceptable there, but
    compile time and runtime would no longer run the same code.
  - Until cross-compilation exists, host is target.

It lands in two steps:
- **M1:** primitives, and closed calls with scalar, string and data
  results. `Fold.idr` keeps only `Integer`.
- **M2:** `Integer` on GMP; `Fold.idr` and `SEM-BIG-1` are deleted.

## 7. Concurrency

### 7.1 The shape

The model is Rust's thread-per-core runtimes (Glommio, monoio, Seastar)
and Lean's tasks, not Go's migrating goroutines on a shared heap.
- **One OS thread per core, pinned.** Each has its own scheduler, `epoll`,
  timer heap, allocator heap and run queue.
- **IO tasks stay on their core.**
- **Pure parallel work** (futures) is spread over all cores, and idle cores
  steal it.
- **The reference program is a web server:**
  - each core accepts on its own `SO_REUSEPORT` listener;
  - each core serves its connections as tasks;
  - heavy computation goes to futures.

### 7.2 The execution algebras are Idris's

| Library | Runtime |
| --- | --- |
| `Prelude.IO`: `fork : (1 _ : IO ()) -> IO ThreadID`, `threadWait` | a task on the current core |
| base `System.Concurrency`: `Mutex`, `Condition`, `Semaphore`, `Barrier`, `Channel`, thread data | each operation suspends the task, not the OS thread |
| contrib `System.Future`: `fork : Lazy a -> Future a`, `await`, `Monad Future` | stealable work items: Lean's `Task` |
| linear `System.Concurrency.Session`: session-typed channels | on `Channel` |
| network `Network.Socket` | blocking calls register with the core's `epoll` and suspend the task |

**The primitives are the libraries' own externs.** `System.Concurrency`
and `System.Future` declare theirs for Chez only
(`%foreign "scheme:blodwen-make-mutex"`, `"scheme:blodwen-make-future"`,
and so on), `Prelude.IO` declares `fork` for Chez and RefC, and
`Network.Socket` names the C support functions `idrnet_*`. Our backend
implements those names in the runtime, as it implements the `prim__`
externs today. The profile admits these modules, and not `%foreign` in
general.

**What the compiler contributes.** An execution algebra built from these
(a monad of futures, a free monad of tasks, a pipeline, a parallel
`traverse`) is a static value. `Simplify` specializes its interpreter away,
as it does for IO and state monads today, so only spawns, awaits, sends and
loops reach code generation.

### 7.3 Tasks and their stacks

**Deep recursion is the constraint.**
- Chez's stacks are segmented and never overflow. Functional code relies on
  that: the Prelude's `map` on lists is not tail-recursive, so mapping over
  a million-element list recurses a million deep.
- musl gives a thread 128 KiB of stack by default.
- Stack depth is implementation-defined (decision 7), but recursion that
  upstream Idris runs must run: a program must not crash on a depth the
  reference handles.

The candidates:

| Stacks | Deep recursion | Tasks | Cost |
| --- | --- | --- | --- |
| Fixed reservation per task with a guard page | up to the reservation (e.g. 64 MiB, committed only when touched) | each stack plus its guard is two kernel mappings, and `vm.max_map_count` defaults to 65 530: about 32 000 tasks | simplest |
| Growable by copying (Go) | unbounded | unbounded | moving frames needs a pointer map of every frame; nothing else in our design needs one |
| LLVM's split stacks | unbounded | unbounded | its prologue reads the limit from `fs:0x70`, glibc's reserved slot; in musl's `struct pthread` that offset is the `result` field, so it cannot be used |
| **Segmented, checked by our own prologue** (chosen) | unbounded, like Chez | unbounded; segments come from pooled mappings, with no guard pages | a compare and a rarely taken branch per function entry |

**How the chosen design works:**
- **The prologue.** `idr-lower` emits it on every Idris function: compare
  the stack pointer with the current segment's limit, kept in a slot of our
  own per-thread data, not the TCB.
- **The slow path** links a new segment and continues there. Frames never
  move, so no pointer maps are needed.
- **Hot splitting** (a call in a loop at a segment boundary, the problem
  that made Rust and Go drop segmented stacks) is damped: each task keeps
  one spare segment instead of freeing it at once.
- **C code has no prologue.** Calls into the runtime, GMP and musl
  therefore switch to a per-core system stack of fixed, ample size, as Go
  does for C calls.
- **Tail recursion modulo cons** (Leijen and Lorenzen, *literature*) turns
  `map`, `filter` and `append` into loops that fill a hole in the last
  cell. This removes most deep recursion before stacks are involved, and
  it combines with reuse, since the cell is written once.
- **Experiment first (C0).** Measure the prologue on the benchmark table
  (target: within noise) and the hot-split case, against fixed
  reservations. Only then build it.

**Scheduling is cooperative.**
- A task runs until it suspends on IO, a channel, a lock, a timer or an
  `await`. Long pure work belongs in futures.
- The stack prologue gives a free preemption point. A flag checked on its
  slow path (set by a timer to force the limit check to fail) adds
  fairness later without signals.

**Semantics.**
- The reference's `fork` starts an OS thread; ours starts a task. Only
  fairness and timing differ, which Idris does not specify. `03` states it.

### 7.4 Memory across cores

Section 4.3's move-or-mark applies at each crossing:
- a channel send to a task on another core;
- the closure a future may run elsewhere;
- a future's result returned to its awaiter;
- a write into a mutable cell shared across cores.

Consequences:
- A message built for sending moves with no atomics at all.
- Data built at startup and read by every core is marked once, and reads
  through borrowed references cost no count traffic.

### 7.5 The kernel interface

This is Linux; macOS maps each item to `kqueue` and pthreads (section 5.5).

- Threads are created with `clone` (or the libc's `pthread`) and pinned
  with `sched_setaffinity`.
- Each core has an edge-triggered `epoll`, an `eventfd` for wake-ups from
  other cores, and the timer heap's next deadline as the `epoll_wait`
  timeout.
- **`epoll` cannot wait on regular files** (they are always ready), and
  `getaddrinfo` blocks. Both go to a small pool of blocking threads that
  completes a task's request and wakes its core (tokio's
  `spawn_blocking`), until `io_uring` replaces the pool for files.
- `io_uring` later, behind the same scheduler.

## 8. Compiler work not tied to memory

### 8.1 Static results from runtime loops (SOP returns)

A residual function whose alternatives return static values of one shape
returns that shape's atoms, and the caller rebuilds the value (CPR; Lean's
`struct` returns).
- The shape is the least fixpoint of the join (`⊔`) over the function's
  alternatives: start from the non-recursive ones and iterate, with the
  whistle as widening.
- Several summands return a tag plus the union of their atoms, and the
  caller switches on the tag into its join points.
- This compiles n-body over `Vect 3 Double` to scalars, as the record
  version already does.

### 8.2 Compile time

`printLn 'x'` takes 5.7 s:
- The Nat of 120 constructors goes away with runtime `Nat` (M2) and the JIT
  (section 6).
- The driver's own cost per call (configurations, the path walk, state
  copies at each unfolding) should also be measured and cut: hash-consed
  configurations, and memoized embedding checks.
- **Target:** every e2e fixture compiles in under a second.

### 8.3 One algebra of facts

`needsV1`/`needsV2`/`needsV3` and the scattered call-graph walks become one
record of facts per function, computed once and joined over the call graph:
- `features`: the contract version is its maximum;
- `effectful`;
- `allocates`;
- `terminating`.

### 8.4 The frontend

- `Frontend/Translate.idr` (1 381 lines) splits into `Data`, `Instances`,
  `Terms` and `Trees`, with one `ParamInfo` per parameter.
- **`main : Int` with the Prelude** (`PROF-PROG-1`): compile such programs
  whole, as IO programs are, instead of per module.
- **Implicit Prelude import:** admitted once the heap exists, since the
  whole Prelude then compiles.

### 8.5 Later

Proved rewrites ([07](architecture/07-proved-rewrites.md)),
constructor-set analysis, and forcing/detagging/collapsing
(`ELIM-FORCE-1`).

## 9. Repository cleanup

One pass, before M1, which changes no compiler behaviour: the suite before
and after must agree test for test.

- **No Python** (about 1 900 lines of ours):
  - **`tools/dev.py`** becomes a `Makefile` plus `tools/bootstrap.sh`: the
    toolchain must build before any Idris exists, which is how Idris 2
    bootstraps itself. `make build`, `make test` and `make bench`; the built
    `idris-mlir` is the compile command.
  - **The test harness** (`tests/*.py`, `lit.cfg.py`) becomes
    `tests/Main.idr` on Idris's own `Test.Golden`, exactly as
    `third_party/Idris2/tests/Main.idr` does.
    - Each test is a directory with a `run` script, an `expected` file and
      its sources.
    - `run` compiles, prints the exit status and the artifacts that must
      exist, and pipes dumps through FileCheck (an LLVM binary). So
      "check exit status and artifacts" holds by construction.
    - The pools: `compiler`, `accept`, `reject`, `e2e`, `dialect`,
      `pipeline`, `spec`, `determinism`.
    - The Chez oracle becomes an explicit second compile inside `run`.
  - **`tests/tooling/test_spec.py`** becomes a golden test in Idris that
    prints the untested rules.
  - **`tools/gen_ryu_tables.py`** becomes an Idris program run by `make`.
  - **`bench/run.py`** becomes `bench/Main.idr` or a short shell script.
  - `bootstrap` installs Idris's `libs/test`.
- **Deleted:**
  - `unsafe/` and `src/`: empty CMake placeholders from cpp-starter's
    zones. The runtime gets `runtime/`.
  - `lib/idris-mlir-io`: the 72 tests that import `IdrisMLIR.IO` move to
    the Prelude, and `DRV-FLOW-2` stops passing `-p idris-mlir-io`.
- **`docs/cpp-profile.md`** (1 700 lines) is cut to the rules our C++
  follows.
- **The research library is kept and organized** under
  `docs/research/library/`:
  - `papers/<author>-<year>-<slug>/`, merging today's `papers/` and
    `sources/oa-papers/` without duplicates;
  - `code/<project>/` and `docs/<project>/` snapshots, each with its
    upstream revision;
  - one `bibliography.bib`;
  - one `README.md` for provenance and licences;
  - an `INDEX.md` by topic: memory, specialization, rewriting, MLIR, arrays
    and scheduling, verification, types and quantities.

  The moves are `git mv`.
- **`docs/architecture`**: one file per compiler boundary. Rules that no
  test can check become prose.

## 10. Milestones

Each milestone requires:
- all suites green;
- no benchmark regression beyond noise;
- its own exit criteria, below.

| # | Milestone | Exit criteria |
| --- | --- | --- |
| 0 | **Driver cutover** (done: `5fbc601`) | G19/G20 in the spec; 189 tests; benchmarks at baseline |
| 1 | **Cleanup** (section 9) | no Python; golden runner green with the same tests; library organized; `idris-mlir-io` gone |
| 2 | **Memory gate** (section 4.4) | the three experiments pass, or the decision is reopened with the numbers |
| 3 | **Static toolchain on musl** (section 5) | musl and GMP pinned as submodules; a GCC targeting `x86_64-linux-musl`; LLVM/MLIR and our C++ tools rebuilt static on it; a `runtime/` archive; every executable static-PIE (no `INTERP`, no `DYNAMIC`); GMP's own tests pass; the differential tests compare math function results within a tolerance, since they are implementation-defined |
| 4 | **M1 (v4): heap and strings** | `Rep`; `Box` for recursive data; reference counting on `Code Mem` (section 4.2); runtime strings and `getLine`; `words`/`lines`/`pack`/`unpack` through the Prelude; `idr-jit` with primitives and closed calls; `PROF-DATA-3` and `PROF-HEAP-3` withdrawn for runtime values; the allocation suite in `bench/` within the gate's targets |
| 5 | **M2 (v5): `Integer` and `Nat`** | small integers with GMP fallback; `Nat` as `Big`; the server's `Integer`; `Fold.idr` and `SEM-BIG-1` deleted; `transpose` compiles; `printLn 'x'` compiles in under a second |
| 6 | **M3 (v6): closures and `Lazy`** | defunctionalized where the set is known, boxed otherwise; `PROF-HEAP-1/2/4` withdrawn for runtime values |
| 7 | **M4 (v7): arrays** | the three array primitives; `IOArray`; `Data.Linear.Array`; bounds traps; the array benchmarks (sieve, quicksort, matrix multiply) beat MLton |
| 8 | **C0: stacks** (section 7.3) | the segment check in `idr-lower` and the system-stack switch, measured: the benchmark table within noise, and the hot-split case bounded; a million-deep non-tail recursion runs |
| 8a | **C1: tasks on one core** | `fork`, `threadWait`, `System.Concurrency` task-aware, `Network.Socket` over `epoll`, timers; an echo server and an HTTP plaintext server under load |
| 9 | **C2: thread-per-core** | a pinned scheduler per core; `SO_REUSEPORT`; move-or-mark across cores; heaps per core with remote frees; the plaintext server against Rust (monoio or Glommio, hyper on tokio), Go and Seastar |
| 10 | **C3: parallel futures** | stealable `System.Future` work; granularity control; parallel `binarytrees`, n-body and mandelbrot against Rayon, MPL and Lean |
| 11 | **C4: `io_uring`** | behind the same scheduler, if C2's numbers call for it |
| 12 | **macOS** (section 5.5) | the OS layer on `libSystem` and `kqueue`; Mach-O output; `idr-jit` with `MAP_JIT`; every suite green on macOS (arm64 and x86-64) |

- **Anywhere after 0:** SOP returns (8.1), the facts algebra (8.3) and the
  frontend split (8.4).
- **After M1:** frames and regions (`alloca` and loop regions for values
  that provably do not escape), as optimizations.

**Contract changes these need**, each written into the architecture docs
in its milestone:
- **02:** admit the Prelude, base, contrib and linear modules that become
  compilable, `prim__getStr`, the array externs, `System.Concurrency`,
  `System.Future` and `Network.Socket`; withdraw the heap rejections as
  their values gain representations.
- **03:**
  - the results of the math functions are implementation-defined
    (replacing "what `libm` returns"), and semantics are upstream Idris's,
    with Chez as a test oracle only;
  - `Integer` and `Nat` at runtime;
  - strings built at runtime;
  - the one-world rule for `unsafePerformIO`;
  - tasks in place of OS threads, with fairness unspecified;
  - bounds traps on arrays.
- **08:** the `idr.box`, `idr.str.*`, `idr.big.*`, `idr.array.*` and
  `idr.io.get_line` ops and the count operations, with their memory
  effects.
- **10:** the `Rep` layouts and struct-of-arrays; the runtime calls.
- **11:** the static toolchain, GMP, the libc, `runtime/`.

## 11. Tradeoffs

For each decision: what it buys, what it costs, and what evidence would
reverse it.

| Decision | Buys | Costs | Reversed if |
| --- | --- | --- | --- |
| Runtime representations for everything (3) | every profile program compiles; compile-time evaluation becomes optional | a runtime, a heap, and code for boxed values where specialization used to remove them | never: without it the profile stays heap-free |
| Reference counting (4) | the best measured speed on functional code; peak memory close to live data; in-place reuse; no stack scanning, so tasks, the JIT and `epoll` stay simple | counts in the code (removed by borrowing, reuse and QTT, not by the model); atomic counts on data shared across cores; cycles through mutable cells | the gate fails: slower than MLton, or atomics dominate a thread-per-core workload |
| Heaps per core, move-or-mark (4.3) | messages built for sending cross cores with no atomics | a walk over each crossing value; remote frees | the walk costs more than copying (Erlang) on real messages |
| Thread-per-core, IO tasks pinned (7) | core-local data; no migration; almost all counts non-atomic | no automatic balancing of IO tasks across cores; a long computation in a task blocks its core | real servers need IO-task migration for load balance |
| Idris's libraries as the concurrency API (7.2) | no language design; programs run on Chez too | no "fork on core k" (a runtime policy stands in) | a program cannot be written without placement control |
| Segmented stacks with our own check (7.3) | unbounded recursion like the reference; unbounded tasks; no pointer maps | a check per function entry; a system-stack switch per C call; the hot-split case | C0 shows the check is not within noise, or hot splits are common |
| musl on Linux, `libSystem` on macOS (5.2, 5.5) | a complete, mature Linux libc on which the whole toolchain, the JIT included, can be static; the same OS-layer shape on macOS | a simple `memcpy`; one more GCC build; two OS layers to maintain | a supported platform offers no static libc and no stable dynamic one (not the case for Linux or macOS) |
| GMP (5.3) | the fastest bignums, with assembly kernels | LGPL obligations for static executables; a build dependency | licensing forbids it for a user; a permissive library of comparable speed appears |
| One JIT path (6) | one semantics per primitive; no Idris copy of the runtime; native speed at compile time | a C++ server process per compilation; start-up time; `fork` per call | start-up dominates small compilations and cannot be cached |
| UTF-8 strings with scalar counts (3) | output without transcoding; compact storage; O(1) for ASCII | breadcrumbs for indexing non-ASCII strings | programs index non-ASCII strings heavily enough that UTF-32 wins |
| No Python; golden tests in Idris (9) | one language in the repository; Idris's own test tooling | rewriting about 1 900 lines of harness | nothing foreseeable |

## 12. Open questions

1. **Cycles through `IORef`/`IOArray`:**
   - leak (Lean, Koka and Swift do);
   - reject statically: a mutable cell whose content type can reach a
     mutable cell; or
   - collect only among mutable cells?

   A census of the libraries and benchmark programs informs it.
2. **The allocator:** vendored mimalloc, or our own size classes?
3. **Placing work on cores.** Idris has no "fork on core k". Recommended: a
   runtime policy where `main`'s forks spread over cores and nested forks
   stay local. The alternative is a few runtime externs through Idris's
   FFI.
4. **Scheduling:** cooperative, with back-edge checks only if fairness
   needs them?
5. **Joining two literal strings:** data layout (kept in `Simplify`) or a
   primitive for the server?

## Appendix A: evidence for the memory decision

Counting Immutable Beans (Ullrich and de Moura, IFL 2019), wall time
normalized to Lean (i7-3770):

| benchmark | MLton | MLKit | OCaml | GHC |
| --- | ---: | ---: | ---: | ---: |
| `deriv` | 0.98 | 4.22 | 1.51 | 2.23 |
| `const_fold` | 1.15 | 4.59 | 5.11 | 2.73 |
| `qsort` | 0.54 | 3.17 | 1.37 | 1.76 |
| `rbmap` | 3.25 | 6.49 | 1.03 | 2.44 |
| `rbmap_1` (heavy sharing; Lean 4.72) | 4.43 | 15.50 | 9.20 | 14.66 |

Lean's own ablations, normalized to Lean with all optimizations:
- without reuse: up to 3.2× (`rbmap`);
- without borrowing: up to 1.16× (`deriv`);
- with every count atomic: up to 2.3× (`unionfind`).

Perceus (Reinking et al., PLDI 2021), Figure 9:
- Koka is fastest on `rbtree`, `rbtree-ck`, `deriv`, `nqueens` and
  `cfold` against OCaml 4.08, GHC 8.6, Swift 5.3 and Java 15, and within
  10% of C++ `std::map` on `rbtree`.
- Reuse halves `rbtree`.
- Atomic counts everywhere cost 5–59%.

**How other runtimes meet many threads** (read from their sources):
- **Go:** concurrent, precise, non-moving, non-generational mark-sweep with
  a write barrier. M:N goroutines, stacks that grow by copying (which
  needs pointer maps of every frame), and an integrated `epoll` poller.
- **OCaml 5:** a minor heap per domain, but every minor collection stops
  all domains. A concurrently marked shared major heap. Fibers with small
  stacks that grow by reallocation, scanned through frame descriptors.
- **Erlang:** a heap per process with its own copying collection. Messages
  are copied; large binaries are shared by reference count.
- **MPL** (parallel MLton): heaps that follow the fork-join task tree and
  collect without synchronizing. Built for fork-join, not long-lived
  communicating tasks; C code generation only.

## Appendix B: sources

- **Papers**, in `docs/research/papers/` and
  `docs/research/sources/oa-papers/`, to be merged into
  `docs/research/library/` (section 9):
  - Counting Immutable Beans;
  - Perceus;
  - FP²;
  - Linearity and Uniqueness;
  - Fractional Uniqueness;
  - Linear Haskell;
  - Futhark;
  - Kovács's staged and closure-free papers;
  - Sørensen's positive supercompiler;
  - Maranget's pattern matching.
- **Source clones read for this plan:**
  - Lean 4 at `e21c2cf` (`src/Lean/Compiler/LCNF`, `src/runtime`,
    `src/include/lean/lean.h`);
  - Koka (`src/Backend/C/Parc*.hs`);
  - MLton and MPL (`runtime/gc`);
  - Go (`src/runtime`);
  - OCaml (`runtime`);
  - Erlang/OTP (`erts/emulator/beam`);
  - Idris 2 at the pinned revision (`libs/`, `src/Compiler/Scheme`,
    `src/Core/CompileExpr.idr`);
  - musl 1.2.6 (`src/internal/pthread_impl.h`, `src/math`, `src/linux`,
    `crt/rcrt1.c`) from `github.com/kraj/musl`;
  - LLVM libc and LLVM in the pinned `llvm-project` (`libc/docs`,
    `libc/config/linux/x86_64/entrypoints.txt`,
    `llvm/include/llvm/ADT/DynamicAPInt.h`,
    `llvm/lib/Target/X86/X86FrameLowering.cpp`).
