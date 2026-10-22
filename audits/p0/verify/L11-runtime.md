<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# L11: the runtime: memory, hosts, limits, endings, crash sites

**Lane L11 of the P0 verification swarm.** HEAD `e96bb991` at start
(2026-10-21T21:31Z) and at finish (see the handoff). Review only: no code,
build or test was run. Rulings in scope: D23, D32 (the runner), D35, D36,
D37, D38, C2 (R1), C5, proposal 0017; reread 18, 19 (endings), §5.11, 0017,
0007 §3 and §4.

Marks: *read* (path:line at HEAD), *measured* (how), *recalled* (not in
`sources/`), *conjecture*, *decision* (a ruling Dn or Cn). Classes:
**defect** (confirmed in the source), **incomplete** (structural
incompleteness), **mismatch** (integration mismatch), **unverified**
(behaviour not observed), **simplification** (optional). Paths under
`snmalloc/` are `third_party/snmalloc/src/snmalloc/` at f126f1c (0.7.6).

## 1. Verification

### D23: out of memory is outside the language

**Holds, with three corrections.**

- *No allocation returns a failure; no allocating op carries a crash.*
  Holds (*read*): `rt::alloc::allocate`, `newCell`, `reallocate` end the
  process (`runtime/Alloc/Cells.cpp:163-192`), GMP's hooks too
  (`runtime/Alloc/Gmp.cpp:3-6`); the cell's record names no crash
  (`foreign/idr/include/idr/IR/IdrRuntime.td:61-66`).
- *A named ending, output flushed, nothing allocated on the way down.*
  Holds for the runtime's own path (static buffer, `write`, `_exit`:
  `runtime/Io/Ending.cpp:66-71`, `runtime/Platform/Posix/Files.cpp:91-109`),
  with four exceptions:
  - **defect**: snmalloc's `PAL::error` writes another format, a stack
    trace and `abort()`s with the program's output unflushed
    (`snmalloc/pal/pal_posix.h:189-201`; the comment says so), and the
    runtime's config uses that PAL (`runtime/Alloc/Cells.cpp:51`). It is
    reached exactly on the strict hosts D35 names: the first allocation
    reserves snmalloc's whole page map (`snmalloc/ds/pagemap.h:213`) and
    calls `PAL::error("Failed to initialise snmalloc.")` when the system
    refuses it (`:221-224`). Under a `ulimit -v` below 256 GiB a program
    therefore dies by `SIGABRT`, unflushed, at its first allocation
    (*read*; the host refusal *recalled*, and the web confirms that
    Linux counts `PROT_NONE` mappings against `RLIMIT_AS`: [LKML, Go and
    PROT_NONE](https://lkml.iu.edu/hypermail/linux/kernel/1102.1/00738.html)).
  - **defect**: out of memory is status 1 with free text
    (`runtime/idris_rt.h:292-297`), and the same exhaustion is spelt three
    ways: "out of memory" (`Cells.cpp:163-166`; `Big/Bitwise.cpp:39-41`;
    `Strings/Replacement.cpp:88-91`) and "array too large"
    (`Alloc/Arrays.cpp:25-28, 98-103`).
  - **unverified**: a libc++ hardening check in the runtime traps
    (*recalled*: extensive mode traps when no verbose handler is linked);
    that is a third format and another signal. DP-75 (synthesis G) routes
    it; it is not yet in P0 §3.
  - **mismatch**: snmalloc reports one memory failure through
    `PAL::error` rather than a null: a thread allocator's first metadata
    (`snmalloc/mem/corealloc.h:1585-1590`). Routed to our PAL it reads as
    an internal error; §2.1 forces it at the runner's start so that it
    can only occur before the program runs.
- *Allocations unordered for the sake of failing; the acquisition
  deletable when unused.* The runtime's side holds: a limit or a refusal
  acts only where snmalloc commits a chunk (`snmalloc/backend_helpers/
  commitrange.h:28-49`, `statsrange.h:31-45`), which only an allocation
  entry reaches (`audits/p0/design/effect-vocabulary.md` §2.1, *read*).
  The effect itself is L01's.
- *"A named crash of the machine as a stack overflow is."* **mismatch**
  (wording): under D32 compiled code cannot exhaust the stack, and D37
  makes reaching the guard an internal error (`SIGABRT`), not a crash.
  The analogy should read "outside the language, as the machine's
  failures are"; out of memory has its own ending (111).

### D32 (the runner): a small, static stack the runner reserves

**Holds as a target, with four corrections.**

- *Replaces the 64 GiB reservation.* Today: one writable region of 1 MiB
  signal stack, 1 MiB guard and 2^36 bytes of stack
  (`runtime/Start/Runner.cpp:33, 37, 44, 76-92`;
  `runtime/Platform/Posix/Memory.cpp:74`, `PROT_READ | PROT_WRITE`).
  *Read.*
- *"The runner reserves that."* **incomplete**: no entry carries a size.
  `idris_rt_start(body, cpu, argc, argv)`
  (`foreign/idr/include/idr/IR/IdrRuntime.td:94-96`) and
  `idris_rt_run_on_stack(fn, arg, exhausted)` (`runtime/idris_rt.h:311`)
  take none. The seam is the program record of §2.2.
- *"A margin for the runtime's and the C library's own frames."*
  **mismatch**: part of the runtime's depth is GMP's, which the bootstrap
  builds with `CFLAGS=-O2 -pipe -ffp-contract=off` (`tools/bootstrap.sh:
  1063-1064`): no probes, and GMP's temporaries go on the stack with
  `alloca` up to a threshold of about 32 KiB each (*recalled*:
  `gmp-impl.h`'s `TMP_ALLOC`), at every level of a Toom multiplication's
  recursion. That term dominates a musl-sized margin (I8).
- *"No frame is larger than the guard, checked when built."* With
  inline probes on every function (C §5.5, DP-80), a frame larger than a
  one-page guard touches the guard as it grows (*read*: 5.11 K6 on the
  pinned LLVM), so the build-time comparison is a second mechanism for
  one fact (I11; it amends D32's wording, so *owner*).
- *"Reaching the guard is an internal error."* Today it is the crash
  "stack exhausted", status 1 (`runtime/Start/Entry.cpp:79-82`). The
  target is D37's internal error.
- **mismatch**: `tests/runtime-start`'s "million" case (a C recursion a
  million frames deep on the runner, expected `million: exit 0`,
  `tests/runtime-start/run:24-25`, `expected:1-2`) tests the property D32
  deletes; the case goes with the 64 GiB stack.

### D35: programs start on strict hosts

**Holds as a target; today it is refuted (expected), with four
precisions.**

- Today a program reserves, writable, 64 GiB + 2 MiB at start
  (`Runner.cpp:76-80`), then at its first allocation 4 GiB
  (`Cells.cpp:94`) and the page map (`pagemap.h:213` through
  `pal_posix.h:333-360`, writable because `pal_enforce_access` is off,
  `runtime/CMakeLists.txt:31-35`): about 324 GiB of address space
  (*derived*). Overcommit mode 2 ignores `MAP_NORESERVE` and charges a
  writable private mapping in full (5.11 K1, K2, *read* from the kernel
  documentation); `RLIMIT_AS` counts every mapping (LKML above). So no
  program starts on either host (the host refusal *conjecture*, not run).
- **The page map's size is now read, not conjectured.** It is
  2^(address_bits − MIN_CHUNK_BITS) entries of two words:
  `address_bits` = 48, the 64-bit default no POSIX or Apple PAL overrides
  (`snmalloc/aal/aal.h:122-125`, `pal/pal_posix.h:155`);
  `MIN_CHUNK_BITS` = 14 (`ds_core/sizeclassconfig.h:55`); an entry is
  two `uintptr_t` (`mem/metadata.h:75, 82`); so 2^34 × 16 B = 2^38 B =
  256 GiB on all four targets (`ds/pagemap.h:101-109`). On arm64 Linux
  with 4 KiB pages, whose entry records 39 user address bits
  (`CMakeLists.txt:222`), that is half of a 39-bit user space
  (**defect** against the host's limits, the host *conjecture*).
- **"Commits no memory before it uses it" needs snmalloc's commit to
  report failure.** With `pal_enforce_access` the reservation is
  `PROT_NONE` and `notify_using` makes it writable, but both POSIX and
  Apple PALs ignore `mprotect`'s result and return true
  (`pal/pal_posix.h:244-253`; `pal/pal_apple.h:214-228`). On a strict
  host the commit is exactly what fails (mode 2's commit limit; Linux's
  `RLIMIT_DATA`, *recalled*: checked by `mprotect` since 4.7), so snmalloc
  would hand out `PROT_NONE` memory and the program's first store would
  fault outside the guard, re-raised unnamed (`Posix/Faults.cpp:20-23`).
  **defect** (latent today, reached by D35's design). I2.
- **A third strict limit.** `RLIMIT_DATA` (`ulimit -d`) counts private
  writable mappings on Linux (*recalled*). Reserve-then-commit meets it,
  and it is the one strict limit an unprivileged test can set, unlike
  mode 2 (I2's discriminator).
- **macOS.** `RLIMIT_AS` is an alias of `RLIMIT_RSS` there
  (`sys/resource.h:451-453` of the SDK, *read*), and XNU does not enforce
  it on mappings (*recalled*): D35's `ulimit -v` is Linux's case.
  **unverified** (measurement M2).

### D36: the host's memory limit, read and kept, no setting

**Holds, with four corrections.**

- *"Reads the cgroup's `memory.max`."* The effective limit is the
  smallest along the cgroup's path to its mount root: a v2 leaf whose own
  `memory.max` is `max` under a limited ancestor reports no limit
  (*recalled*; v1 exposes `hierarchical_memory_limit` in `memory.stat`,
  v2 has no such file). Reading the leaf alone misses the limit that
  kills. **incomplete**. I9.
- *"When committed memory would cross it ... before the kernel's
  killer."* Two gaps, both *recalled*: (a) v2's `memory.max` reclaims to
  swap while `memory.swap.max` allows it, so the kill point is
  `memory.max` plus the swap the cgroup may use (v1: `memsw.limit_in_bytes`
  when set); (b) the cgroup also holds what the heap's count does not: the
  program's image and stack, page tables (8 bytes per page, *recalled*),
  kernel memory, other processes. Ending when the heap's committed bytes
  reach `memory.max` would let the kernel kill first. **incomplete**.
  I9; the swap half changes the ruling's text (Q2).
- *"Committed bytes are counted in snmalloc's chain of ranges, a type the
  runtime owns (`Cells.cpp:69`, `StatsRange`)."* `Cells.cpp:69` names
  snmalloc's `StandardLocalState`, whose `Stats` pipe is fixed inside it
  (`snmalloc/backend/standard_range.h:30-41`). A limit range needs our
  own composition of that pipe, which snmalloc's configs are written to
  allow (`backend/fixedglobalconfig.h:15-50` composes its own). Holds
  with that correction; no patch is needed for it.
- *"No environment variable."* Holds as a target; the one a program reads
  today, `IDRIS_RT_LIVE` (`runtime/Io/Ending.cpp:17-31`), goes with the
  live-cell counter (I5).
- Precision: the limit is a program's, read in `idris_rt_start`; the
  tools' memory is the C library's malloc (snmalloc is not their malloc,
  18 §3.1, *read*), so the shared runner does not read it.

### D37: one status per ending

**Holds, with five corrections.**

- Today every ending but a return and an exit is status 1
  (`runtime/idris_rt.h:297`), and every program prefixes its messages
  `idris-mlir: ` (`Posix/Files.cpp:104`), the compiler's name, not the
  program's (**defect**, user-facing). *Read.*
- *Upstream "is no guide".* Holds (*read*): Chez's error quit displays
  the message and exits 1 (`third_party/Idris2/support/chez/support.ss:
  200-204`); RefC prints `ERROR: ` to standard output and calls
  `exit(-1)`, status 255 (`support/refc/prim.c:61-65`);
  `ExitFailure : (errNo : Int) -> So (not (errNo == 0)) => ExitCode`
  (`libs/base/System.idr:295`), so `exitWith (ExitFailure 256)` is a valid
  program (that it reads as success upstream is *recalled*: a parent sees
  the low 8 bits).
- *"A status no parent can read ends as an internal error."* **mismatch**
  with the table's own rows: internal error is "the compiler's or the
  runtime's bug", and "a failed guard" is a crash. Making the status a
  byte by a guard in the IR (the representation of §2.4) puts the check at
  the exit's site and folds it away for a constant status; its failure is
  then a crash. The ruling's row is the owner's: Q1.
- *"Returned: 0."* The program entry admits a `Status` root
  (`() -> i64`, `foreign/idr/include/idr/IR/Func.h:118-127`,
  `foreign/idr/lib/Conversion/Entry.cpp:90-98`) returning any status, and
  `idris_rt_start` checks it (`runtime/Start/Entry.cpp:148`). No Idris
  `main` has that type; under D37 the root goes (fixtures use `exit`).
  **incomplete**. I6.
- *"One generated table ... read by the runtime, the harness."* The
  harness reads three hand copies today (`harness/lib/run.sh:13-39`,
  `harness/lib/e2e.sh:153-187`, `harness/lib/differential.sh:111-174`).
  Precision: `exit 1` and a crash share status 1, `exit 111` and out of
  memory share 111, so the table cannot be read off the status alone; the
  harness compares (status, committed standard error), which is a byte
  comparison, not parsing.
- *Crashes and files.* `idris_rt_crash` flushes standard output's buffer
  only (`Ending.cpp:66-71`); `idris_rt_io_exit` also closes the handle
  table's files, writing their pending bytes (`Ending.cpp:56-60`). A
  program that writes a file and then crashes loses what libc still
  buffers, though D21 orders that write before the crash. RefC's
  `exit(-1)` flushes C streams (*recalled*). **defect** against D21's
  intent. I10.
- Precision: the "cannot run" writer runs before the processor test, so
  the ending function that writes it stays compiled for the target's
  baseline (`IDRIS_RT_BASELINE`, `runtime/idris_rt.h:299-304`).

### D38: a crash site reaches the runtime as data

**Holds, with four corrections.**

- Today each site writes its own message global, `"<cause> at
  file:line:col"`, built on a worker (`foreign/idr/lib/Conversion/
  Runtime.cpp:39-50, 189-196`; `StaticBytes.cpp:30`), and `crash_str`
  lowers through the generic call and loses its site (12 CV-16, CV-17).
  *Read.*
- *"One global per cause."* Causes are a closed set the specification
  generates (`audits/p0/design/compile-time-cpp.md` (h): a generated
  `CrashCause` enum and its message table). A cause passed as a global
  per program restates that table's text in every program; passed as the
  enum's immediate, the runtime holds the one table. Lane 12's T9 passes
  the cause as text (`audits/p0/12-conversion.md:630-635`). I4.
- **mismatch** (L16): four committed crashes have no site at all:
  `tests/buffer-range/cases/{below-zero,no-input,3,9}/expected-crash` hold
  "a byte range outside the buffer", because the guard comes from a
  primitive's expansion with no location. Under D38 every crash op needs
  a place; the frontend gives the call's.
- **mismatch**: the runtime crashes on the program's behalf with no site:
  base's `getString` of a handle that holds no string
  (`runtime/Io/Handles.cpp:233-243`). I3 moves it to a guard at the call.
- Precision: a missing case's message names the function today
  (`unhandled input for Main.name at Main.idr:10:1`, among the committed
  `expected-crash` files, *measured*: `cat tests/*/cases/*/expected-crash
  | sort | uniq -c`). D38's (cause, file, line, column) drops the name;
  the location identifies the clause. The expected files change with it.

### C2, R1: memory the kernel touches is held by ownership

**Holds as a rule; three runtime consequences are unstated.**

- A buffer the kernel writes must be a cell of the counted lifetime: a
  frame cell or a lexical lifetime's cell (D39, D40) dies at its scope's
  end while the kernel may still write it; static data cannot be written.
  A zero-copy send may hold counted or static bytes. **incomplete**: the
  operand's type must say so (§3).
- An exclusive buffer consumed into an operation in flight is never
  counted: no increment at submission, no test at completion, and a
  cancelled one is released with no count read (the exclusive release of
  §2.6). Holds with the typed entries.
- **incomplete** (for 0007, unbuilt): R2 makes giving a kernel-ring
  buffer back a `Free`, but the runtime frees any cell without knowing its
  type, by the header's kind (`runtime/Rc/Freeing.cpp:98, 127-135`;
  `runtime/idris_rt.h:47-50`). A ring buffer's release has to return it
  to its ring, so the header needs a kind for it, or such a cell never
  reaches the type-blind free.
- **mismatch**: 0007 §5.1 checks "zero live cells ... on the sum over
  shards" through the per-thread counter (`Cells.cpp:157`); DP-81 and I5
  remove that counter from shipped programs.

### C5: every size the program's or the host's

**Holds as a principle; four of its five values are corrected.**

- *The stack.* "Tens to hundreds of KiB" is *conjecture*. "The runtime's
  own units take `-fstack-clash-protection`, since GMP's temporaries use
  `alloca`": **mismatch**: GMP is not one of the runtime's units; it is
  the bootstrap's (`tools/bootstrap.sh:1060-1066`). I8.
- *The guard.* "One page, or the largest frame rounded up": with probes,
  one page (I11).
- *The signal stack.* "The target's `SIGSTKSZ`": on Linux the minimum is
  the host's, not the target's: the kernel reports it in the auxiliary
  vector because AVX-512 and AMX frames outgrew glibc's constant
  (*recalled*: `AT_MINSIGSTKSZ`, Linux 5.14 on x86); on macOS the SDK's
  constants are 32 KiB minimum and 128 KiB recommended
  (`sys/signal.h:341-342`, *read*). Today's 1 MiB lies directly below the
  guard (`Runner.cpp:33, 71-72`), so a frame that skips the guard writes
  the handler's stack first (18 R-STK-2). I7.
- *The heap.* Holds as intent; I1 makes it stronger: no window is
  reserved, the 4 GiB alignment is where the heap's cursor starts, and
  "under a `ulimit -v` the window shrinks" holds without a rule, since
  nothing is reserved before it is used.
- *The page map.* The conjecture is now *read* (D35 above). "Harmless
  under strict overcommit once `PROT_NONE`": with `pal_enforce_access`
  the whole map is made `PROT_READ` at start (`ds/pagemap.h:254-262`),
  which a private mapping is not charged for (*recalled*); holds. "Fatal
  under `ulimit -v`": holds. The replacement, bounded or grown, is I1's.

### Proposal 0017 (the heap as Apple's prefetcher reads it)

**Holds, with D9 overtaken.**

- D7 (the heap's first 4 GiB in one aligned region) is built
  (`Cells.cpp:31-39, 93-105`; `tests/heap-region/region.c`). *Read.*
- D9 (the stack's top in the heap's region, a 1 GiB budget, a 64 GiB
  stack) is **overtaken** by D31 and D32: the native stack holds only the
  acyclic call depth, so the whole of it fits in the region, and deep
  recursion lives on D31's frame stacks. Those keep the prefetcher's
  benefit only if their chunks come from the runtime's allocator, in the
  heap's span. The budget, the 64 GiB text of §2's table and P1's plan go
  (I12).
- D6 (never set DIT, never lower the thread's QoS): the program runs on
  the runner's thread (`Runner.cpp:92`; `Posix/Stacks.cpp:29-41`), whose
  QoS on macOS against the main thread's is **unverified** (M9).

### Proposal 0007 §3 and §4

- "One runner runs at a time in a process" holds (`Runner.cpp:14-18`);
  P4's runner per shard needs the guard's bounds per thread, since the
  handler reads process globals today (`Runner.cpp:16-18`).
  **incomplete** (for 0007).
- "A snmalloc allocator (already per thread)" holds; the backend, and so
  the span and the limit of §2.1, are process-wide, so only a process-wide
  limit exists (DP-84, holds).

### The deletion list to verify

| what | verdict | evidence |
| --- | --- | --- |
| per-site crash strings | holds | `Conversion/Runtime.cpp:39-50, 189-196`; `StaticBytes.cpp:30` |
| NULL and odd-bit tests on typed words | holds, corrected | `Rc/Rc.h:36-40, 100-108`; `Rc/Counting.cpp:45, 53, 67-74`. Two corrections: an in-place sum's shared slot may hold a cell in one constructor and a big in another, and null in a third (`foreign/idr/include/idr/IR/Layout.h:166-170`), so the kinds form a lattice whose top keeps both tests (§3); and the type-blind free keeps its test (essential, 18 R-RC-7) |
| live-cell counter in shipped programs | holds, widened | `Cells.cpp:153-157, 187-205`; idris-mlir's folders read it too (`foreign/idr/lib/IR/Fold/Scope.cpp:21-31`), a test fact paid in every compilation (I5) |
| the half-sum `Ending` | holds | `runtime/Start/Start.h:19`; `Entry.cpp:88-107` |
| the 1 MiB signal stack and guard | holds | `Runner.cpp:33, 37` |

## 2. Boundaries

The end state of the runtime's memory, start, limits and endings as this
lane designs it on the rulings. Shapes are the C ABI and the runtime's
typed C++; names are proposals, the specification's to generate (D16).

### 2.1 The heap's span and the allocator

**The span.** One range of address space `[H, H + R)`, `H` aligned to
4 GiB, from which every heap chunk is reserved, in address order, as the
heap grows. Nothing in it is reserved before snmalloc asks for a chunk.
- `R`, the span's length, is the address space the host leaves: under a
  finite `RLIMIT_AS`, that limit; otherwise up to the top of the user
  address space, which the platform's OS unit reads at start (Linux: the
  initial stack, which the kernel places at the top of its mapping
  window; Darwin: `MACH_VM_MAX_ADDRESS`, `CMakeLists.txt:272`; both
  *conjecture* until M2 and M8).
- The heap's first 4 GiB lie in one 4 GiB region because the cursor
  starts at `H`: 0017 D7 by coordinate, with no region reserved
  (`heapRegion` and `addRegion`, `Cells.cpp:39, 93-105`, go).
- The runner's stacks lie at the span's start (§2.2), in the heap's first
  region: 0017 D9 for free.

**The page map.** snmalloc's bounded flat map (`ds/pagemap.h:11-187`,
`has_bounds = true`, as `backend/fixedglobalconfig.h:27-30` uses it),
covering the span: one 16-byte entry per 16 KiB chunk, so its storage is
`R / 1024` bytes (*derived*: 8 MiB for an 8 GiB limit; at most 128 GiB of
`PROT_NONE` for a 47-bit space with no limit, against 256 GiB writable
today). Its storage is reserved at start, `PROT_NONE`, just below `H`
(upstream's `init(b, s)` places it at the range's head, so `b` is chosen
as `H − R/1024`), and committed page by page as chunks register
(`ds/pagemap.h:58-91`). One carried patch (I1): its range tests on the
fast path run only under snmalloc's `sanity_checks` mitigation, which is
off; the freed pointer lying in the heap is a fact the runtime's types
prove (D10). The lookup stays the flat map's one load and a subtraction
of the span's base, a fact the OS chooses at start.

**The configuration** (`runtime/Alloc/Cells.cpp`, ours, composed from
snmalloc's parts as its own configs are):
```cpp
namespace rt::alloc {
// snmalloc's POSIX or Apple PAL; its fatal errors end the program as the
// runtime's internal error (§2.4), with snmalloc's text.
struct Pal : snmalloc::DefaultPal { [[noreturn]] static void error(const char *text) noexcept; };
// Chunks from the span, at fixed addresses, in order; a chunk the system
// refuses (the limit, the end of the address space) is a null.
struct SpanRange { /* alloc_range(size): reserveAt(cursor aligned to size); Aligned = true */ };
// Committed bytes held under the host's commit limit (§2.3): a commit
// past it is a null. No limit is the largest size_t, so the test is the
// one comparison and no flag says whether there is a limit.
struct LimitRange { /* alloc_range(size): Stats::current + size > limit ? null : parent */ };
class HeapConfig final : public snmalloc::CommonConfig {
  using ConcretePagemap = snmalloc::FlatPagemap<snmalloc::MIN_CHUNK_BITS, Entry, Pal, true>;
  using Base = snmalloc::Pipe<SpanRange, snmalloc::PagemapRegisterRange<Pagemap>>;
  // snmalloc's standard ranges, with LimitRange after StatsRange.
  using Stats = snmalloc::Pipe<GlobalR, snmalloc::CommitRange<Pal>, snmalloc::StatsRange, LimitRange>;
  static void init(Span span, size_t limit);   // explicit, by the runner (§2.2)
};
// Every allocation's continuation: no failing return exists.
struct OutOfMemory {
  static void *success(void *p, size_t size, bool secondary) { return p; }
  [[noreturn]] static void *failure(size_t requested) noexcept;   // §2.4's OutOfMemory
};
}
```
- snmalloc is compiled with `SNMALLOC_CHECK_CLIENT_MITIGATIONS=
  pal_enforce_access`: exactly that mitigation and no other
  (`snmalloc/mitigations/mitigations.h:211, 222-224`), a configuration
  upstream builds and tests alone (`third_party/snmalloc/CMakeLists.txt:
  845-868`). Reservations are `PROT_NONE` (`pal/pal_posix.h:337-338`;
  `pal/pal_apple.h:255-257`), a commit is `notify_using`, a release
  `MADV_FREE` then `PROT_NONE` (`pal/pal_linux.h:128-144`). With the
  second carried patch (I2) a refused commit is a null, which
  `CommitRange` already turns into a null range (`commitrange.h:36-46`).
- Initialisation is explicit, in the runner, before anything allocates
  (`FixedRangeConfig`'s shape: snmalloc calls `ensure_init` only if the
  config defines one, `snmalloc/mem/corealloc.h:1546-1571`). The lazy
  check on every slow path and its two flags (`Cells.cpp:76-87, 107-124`)
  go: that initialisation precedes use is fixed by the start's order.
- `allocate`, `newCell`, GMP's hooks and the persist walk use
  `snmalloc::alloc<OutOfMemory>`; an array whose elements hold objects
  uses the zeroing form (18 R-AL-9). `reallocate` keeps a block whose
  size class fits and otherwise allocates, copies and frees, so it has no
  null test either. A cell's size is computed once, checked with
  `__builtin_add_overflow` in `newCell` (18 T-AL1).

**Invariants.** (1) Every heap chunk lies in the span, and every address
the page map is asked about is a heap address. (2) Committed bytes, as
`StatsRange` counts them, never exceed the limit after a commit returns.
(3) No allocation entry returns null. (4) Address space reserved =
the stacks + the map's storage + the chunks snmalloc took; nothing is
reserved in advance of use beyond the map's storage.

### 2.2 The runner and the stack

```c
/* The program's static facts, one constant @main passes (D10). */
typedef struct idris_rt_text { uint32_t length; char bytes[]; } idris_rt_text;
typedef struct idris_rt_program {
  void (*body)(void);              /* the IO root; the Status root is gone (I6) */
  uint64_t cpu_features;           /* the IDRIS_RT_CPU_FEATURES bits it needs */
  uint64_t stack_bytes;            /* D32: its own frames on the longest acyclic path (L10) */
  const idris_rt_text *name;       /* <program> in every message (D37) */
} idris_rt_program;
IDRIS_RT_NORETURN void idris_rt_start(const idris_rt_program *program, int argc, char **argv);

/* The tools' runner: their stack is their build's (D33, L10). */
enum idris_rt_ran : uint8_t { IDRIS_RT_RAN, IDRIS_RT_NO_STACK };
enum idris_rt_ran idris_rt_run_on_stack(void (*fn)(void *), void *arg, uint64_t stack_bytes,
                                        void (*exhausted)(void));
```
- **Order at start**, in `idris_rt_start`: the page-size and processor
  checks (cannot run, 126); the host's facts (§2.3); the span and the
  page map's storage; snmalloc's `init`; one allocation on the runner's
  thread, so a thread allocator's creation (`corealloc.h:1585-1590`)
  happens before the program runs; GMP's hooks (18 T-STK2); the body;
  then the `Returned` ending (§2.4). `idris_rt_main_return`
  (`Ending.cpp:45-49`) merges into that epilogue, so every ending is one
  call of `end`.
- **The layout**, at the span's start, each a whole number of pages:
  `[guard | stack | guard | signal stack]`. The stack grows down to its
  guard; the signal stack has its own guard below it (18 R-STK-2).
- **Sizes**: stack = `stack_bytes` + the runtime's own depth, a constant
  of the runtime's build (its deepest entry path, GMP's included, I8,
  plus the target entry's margin for its C library, which is the host's
  code and measured per target: M7), rounded to pages. Guard = one page
  of the target entry's size: inline probes make it enough (I11). Signal
  stack = the host's minimum (§2.3) + the handler path's frames, rounded
  to pages.
- **Committed at start**: the stack and the signal stack are small, so
  they are made writable whole (18 T-STK3's commit-on-fault design is
  unnecessary); refused, that is out of memory (111), not "no stack"
  status 1 (`Entry.cpp:144-147`).
- **The fault handler**: a fault in either guard is
  `InternalError{StackExhausted}`; any other fault keeps its previous
  action (`Posix/Faults.cpp:20-23`). Process globals today
  (`Runner.cpp:16-18`); per thread when 0007 has a runner per shard.

### 2.3 The host's facts, behind the platform layer

| function | Linux (OS unit) | Darwin (OS unit) | read |
| --- | --- | --- | --- |
| `reserve(size)` → `PROT_NONE` region | `mmap` `PROT_NONE`, `MAP_NORESERVE` | `mmap` `PROT_NONE` | at start, and by `SpanRange` |
| `reserveAt(address, size)`, never clobbering | `MAP_FIXED_NOREPLACE`, checked | `mach_vm_allocate` without `VM_FLAGS_ANYWHERE` | per chunk |
| `commit(p, n)`, `protect(p, n)` | `mprotect`, result returned | `mprotect`, result returned | start (stacks) |
| `userAddressTop()` | the initial stack's top, rounded up to a power of two (*conjecture*) | `MACH_VM_MAX_ADDRESS` | once |
| `addressLimit()` | `getrlimit(RLIMIT_AS)` | none enforced (*recalled*) | once |
| `commitLimit()` | the cgroup's kill point less its working set at start (I9) | none | once, programs only |
| `signalStackMinimum()` | `getauxval(AT_MINSIGSTKSZ)`, else `MINSIGSTKSZ` | `SIGSTKSZ` (128 KiB) | once |

- The cgroup: `/proc/self/cgroup` names the process's cgroup (v2 `0::`,
  v1's `memory` controller); `/proc/self/mountinfo` its mount. v2: the
  smallest `memory.max` from the cgroup to the mount's root, plus the swap
  `memory.swap.max` lets it use (Q2); working set `memory.current` less
  `memory.stat`'s `inactive_file`. v1: `memory.stat`'s
  `hierarchical_memory_limit` (or `hierarchical_memsw_limit` when swap is
  accounted), working set `memory.usage_in_bytes` less
  `total_inactive_file`. All *recalled*; the kernel's text is parsed once
  at the boundary into a byte count. No file, no controller, `max`: no
  limit, the largest `size_t`.
- The `#ifdef MAP_NORESERVE` (`Posix/Memory.cpp:67-72`) is not a
  per-target branch on our targets: the macOS SDK defines the flag
  (`sys/mman.h:120`, *read*), so it is always taken; with `PROT_NONE`
  reservations it moves into the Linux unit or goes (**simplification**).
- The OS units are 18 T-PL4's, chosen by the target entry beside its
  processor unit (`CMakeLists.txt:202, 217, 236, 251`).

### 2.4 Endings

**The specification** (`compiler/spec/`, C7; imported by the frontend and
the harness, D50):
```idris
module IdrisMLIR.Spec.Endings
public export data Cause = DivisionByZero | IndexOutOfBounds | ByteRangeOutsideBuffer
                         | HeadOfEmptyString | TailOfEmptyString | StringIndexOutOfRange
                         | NonFiniteCast | UnhandledInput | NotAString | ...   -- every guard's, one list
public export data Site : Type where MkSite : (file : FileId) -> (line, column : Nat) -> Site
public export data Refused = BySystem | ByCgroup
public export data Why = MissingFeatures Bits64 | WrongPage Nat Nat
public export data Internal = StackExhausted | Leaked Nat | DeadCell | ReturnedFrame
                            | AllocatorSaid String | LibrarySaid String
public export data Ending : Type where
  Returned      : Ending
  Exited        : Fin 256 -> Ending            -- a status a parent can read, by construction
  Crashed       : Site -> Cause -> Ending      -- no crash without its site
  CrashedWith   : Site -> Ending               -- idris_crash: the program's own text
  OutOfMemory   : Refused -> Ending            -- no site: D23 names no allocation
  CannotRun     : Why -> Ending
  InternalError : Internal -> Ending
public export data Status = Code (Fin 256) | Abort
public export status : Ending -> Status
status Returned = Code 0;        status (Exited n) = Code n
status (Crashed _ _) = Code 1;   status (CrashedWith _) = Code 1
status (OutOfMemory _) = Code 111; status (CannotRun _) = Code 126
status (InternalError _) = Abort
```
with, as an erased proof, the fixed codes pairwise distinct, and the
message form per constructor: `<program>: fatal: <file>:<line>:<col>:
<cause>`, `... fatal: out of memory` (with which limit refused),
`... fatal: internal error: <what>`; none for `Returned` and `Exited`.

**The runtime** (generated variant, hand `end`):
```cpp
namespace rt::end {
using Ending = std::variant<Returned, Exited, Crashed, CrashedWith, OutOfMemory,
                            MissingFeatures, WrongPage, InternalError>;   // 8 alternatives
[[noreturn]] IDRIS_RT_BASELINE void end(const Ending &) noexcept;
}
```
`end` is the one place that ends the process: flush standard output's
buffer; for every ending but an internal error, close the handle table's
files as exit does today (I10); write the message from the table;
`_exit(code)`, or `abort()` for `Abort` (with `SIGABRT`'s default
action). It allocates nothing and takes no lock; from the fault handler
it is reached only as an internal error, which touches no libc stream.

**The C entries** (records of the specification, D16):
```c
enum idris_rt_cause : uint8_t { /* Spec.Endings.Cause, in order */ };
IDRIS_RT_NORETURN void idris_rt_crash_at(enum idris_rt_cause cause, const idris_rt_text *file,
                                         uint32_t line, uint32_t column);
IDRIS_RT_NORETURN void idris_rt_crash_message_at(const idris_rt_str *message,
                                                 const idris_rt_text *file,
                                                 uint32_t line, uint32_t column);
IDRIS_RT_NORETURN void idris_rt_exit(uint8_t status);
```
Two crash entries because their data differ: a cause of the closed set,
or the program's string (D38's "`idris_crash` keeps its site"). The
status operand of exit is a byte: the guard before it (Q1) or nothing.

### 2.5 Crash sites in the program

- Each crash op lowers to a cold call with the cause's immediate, a
  pointer to one static `idris_rt_text` per source file, and the line and
  column as immediates (D38). No per-site datum; nothing built on a
  worker (12 CV-16).
- The site is the innermost source place of the op's location
  (`FileLineColRange` inside a call-site or fused location). An op whose
  location holds none is a compile-time internal error at the lowering,
  never a run-time branch; the frontend gives every crash op the call's
  place (§1, D38, L16).
- The runtime's own program crashes leave the runtime: base's `getString`
  of a non-string handle becomes a guard at the call (cause
  `NotAString`), the runtime's entry total on what passes it.
- Out-of-memory conditions found before an allocation (an array's byte
  count past `size_t`, a big shift past GMP's limb count, a string's room
  overflowing: `Arrays.cpp:98-103`, `Bitwise.cpp:39-41`,
  `Replacement.cpp:88-91`) call the `OutOfMemory` ending through the
  allocation path's checked size, with no site. A constant size folds the
  check away where the runtime's bitcode is inlined.

### 2.6 Counting entries (the runtime's half only)

The kinds of a counted word, a lattice the layout computes from the type:
`Cell` (never null, never small) ⊑ `MaybeCell` (null or a cell) and `Cell`
⊑ `Big` (small or a cell); `MaybeCell ⊔ Big = Any` (null, small or a
cell), the kind of an in-place sum's slot shared by a cell and a big
(`Layout.h:166-170`). One instantiation each of `inc` and `dec`, its tests
exactly the kind's (C §2's table; `compile-time-cpp.md` (e)), plus
`release_exclusive` (no count read, 18 T-RC4), `is_unique` (count only),
runs of slots (18 T-RC5). `layout::Component`'s `bool counted`
(`Layout.h:85-88`) becomes the kind. L07 owns the counting design; this
is the ABI seam.

### 2.7 D41's headers and static linking

- D41's templates (Euclidean division, the total shifts, the scalar test,
  the char conversions) live under `runtime/` (AGENTS.md: a primitive's
  one meaning is the runtime's) and include only freestanding headers
  (`<concepts>`, `<cstdint>`, `<bit>`, `<type_traits>`), so they compile
  under the runtime's profile (no exceptions, no RTTI, no C++ library at
  link: `runtime/CMakeLists.txt:1-11`, `check-archive.sh`) and under the
  tools'. The runtime instantiates them over its machine integers, its
  edge cases `static_assert`ed in its own build too; the compiler's
  domains (`APInt`, intervals, the builder) stay in `foreign/idr`.
  Both builds are C++26 (`CMakeLists.txt:317`).
- Nothing in §2.1 to §2.6 adds a shared dependency: the cgroup reader
  uses `open`/`read`, `getrlimit`, `getauxval` (glibc), `mach_vm_allocate`
  (libSystem); the patched snmalloc is header-only and compiled in; GMP
  stays the sysroot's static archive. `tests/static-linking` is unchanged.

### 2.8 Constructor provenance

| fact | constructed by | who alone may | consumed by |
| --- | --- | --- | --- |
| the program's stack bound | L10's analysis over code generation's frame sizes (D32) | the driver, into the program record | the runner |
| the runtime's own depth | the runtime's build (stack usage of the archive, GMP's configuration, the entry's libc margin) | `runtime/CMakeLists.txt` | the runner |
| page size, probe size, guard | the target entry (`IDRIS_MLIR_PAGE_SIZE`) | `CMakeLists.txt`'s entry | runtime (checked against the system at start), lowering's probe flags, snmalloc |
| user address top, address limit, commit limit, signal minimum | the host, read once at start | the platform's OS unit | the span, `LimitRange`, the runner |
| the span `[H, H+R)` | the runner at start | `rt::alloc::HeapConfig::init` | `SpanRange`, the page map |
| committed bytes | snmalloc's `StatsRange` | snmalloc | `LimitRange`, nothing else |
| crash cause | the spec's `Cause`; the op's cause property (frontend, guards) | the specification | lowering → `idris_rt_crash_at`; harness |
| crash site | the op's location (frontend, from the TTC) | the frontend; passes keep locations | lowering |
| the program's name | the driver (the executable's name as built) | the driver | every message |
| CPU feature word | the target entry and the module's target | the lowering | `idris_rt_start` |
| a word's counted kind | the layout, from the type | `layout::Layouts` | the lowering's choice of instantiation |
| an exclusive cell | the grade (`!idr.excl`, the typed token) | exclusivity and counting (L08, L07) | `release_exclusive`, reuse |
| the ending | `rt::end::end` | the runtime alone | the parent, the harness |

### 2.9 Consumers, errors, cleanup

- **Out of memory**: from `SpanRange` (address space), `CommitRange`
  (commit), `LimitRange` (the cgroup), a checked size, GMP's hooks, D31's
  frame stacks (their chunks come from `rt::alloc`) → `OutOfMemory::
  failure` → `end(OutOfMemory{by})`.
- **Internal errors**: the guards' fault; our PAL's `error`; the checked
  runtime's misuse (`Rc/Counting.cpp:29-39`) and leak (I5); libc++'s
  handler (DP-75) → `end(InternalError{...})` → `SIGABRT`.
- **Cleanup**: at `Returned`, `Exited`, `Crashed`, `CrashedWith` and
  `OutOfMemory` the handle table is released (files closed, written);
  memory is never freed on the way out (the OS takes it).

### 2.10 What goes

| path | symbols or lines | by |
| --- | --- | --- |
| `runtime/Alloc/Cells.cpp` | `heapRegion`, `addRegion`, `initialise`, `ensure_init`, `initialised`, `initialising`, `is_initialised` (39, 76-124); `outOfMemory` and both null tests (163-183); `liveCells`, its `++`/`--`, `forgetCell`, `idris_rt_live_cells` in the shipped runtime (153-157, 190, 195, 205, 223) | I1, I13, I3, I5 |
| `runtime/Alloc/Alloc.h` | `outOfMemory` (36-38); `forgetCell` (54-56, shipped) | I3, I5 |
| `runtime/Alloc/Arrays.cpp` | `tooLarge` (25-28); the `memset` (106-110) | I3, 18 T-AL1 |
| `runtime/Start/Runner.cpp` | `alternateSize`, `guardSize`, `stackSize` (33-44); the one-guard layout (71-72) | I7, I11, D32 |
| `runtime/Start/Entry.cpp`, `Start.h` | `rt::start::Ending`, `checkStatus` (Start.h:19-25, Entry.cpp:88-107); "stack exhausted", "no stack could be reserved" texts (79-82, 144-147); `exitProcess(IDRIS_RT_CRASHED)` (74) | I3, I6 |
| `runtime/Io/Ending.cpp` | the file: `reportLiveCells`, `idris_rt_main_return`, `idris_rt_io_exit`, `idris_rt_crash`, `idris_rt_crash_str` (17-76) | I3, I5, I6 |
| `runtime/idris_rt.h` | `IDRIS_RT_CRASHED` (292-297); `idris_rt_live_cells`, `idris_rt_gmp_init` prototypes (309, 317) | I3, I5, 18 T-STK2 |
| `runtime/Platform/Posix/Files.cpp` | `writeCrash`'s `idris-mlir: ` prefix (103-109) | I6 |
| `runtime/Platform/Posix/Memory.cpp` | writable `reserve`, `#ifdef MAP_NORESERVE` (65-85) | I1 |
| `runtime/Io/Handles.cpp` | `idris_rt_handle_string`'s crash (236-240) | I3 |
| `foreign/idr/lib/Conversion/Runtime.cpp`, `StaticBytes.cpp` | `crashMessage` (39-50), `StaticData::message` (30) | I4, D38 |
| `foreign/idr/include/idr/IR/Func.h`, `lib/IR/Func/Func.cpp`, `lib/Conversion/Entry.cpp` | `RootKind::Status` | I6 |
| `foreign/idr/lib/IR/Fold/Scope.cpp` | the leak count and `countFoldLeak` (21-31) | I5 |
| `harness/lib/run.sh`, `e2e.sh`, `differential.sh` | the three ending protocols and `IDRIS_RT_LIVE` | I3, I5 (L19) |
| `tests/runtime-start` | the "million" case | D32 |
| proposal 0017 | D9's budget and 64 GiB text, P1 | I12 |

### 2.11 Essential distinctions that stay

- Crashed (the program's partial code, status 1) and internal error (our
  bug, `SIGABRT`): a parent and a bug report must tell them apart.
- The two crash entries: a cause of the closed set and the program's
  string are different data.
- Address space and commitment: two limits, two refusals, one ending.
- The checked runtime and the shipped one: a compile-time variant of the
  same sources (18 R-AL-11).
- The type-blind free and the typed entries: a dying cell's slots are
  known only by its header (18 R-RC-7).

### 2.12 Seams

| with | the declaration both sides write against | state |
| --- | --- | --- |
| L10 (stack bound, frames) | `idris_rt_program.stack_bytes`, the program's frames only; D31's frame-stack chunks from `rt::alloc` | fixed here; the bound's computation is L10's |
| L10 (tools, D33) | `idris_rt_run_on_stack`'s `stack_bytes` | unfixed: the tools' measured value |
| L13 (lowering) | `idris_rt_crash_at`/`_message_at`, the program record, probe flags from the entry's page | fixed here |
| L01, L02 (effects) | the runtime functions' rows: crash entries write `crash` (under `io`), `exit` writes `exit`, allocation entries acquire on `heap` with no crash | fixed by D27, D23 |
| L07, L08 (counting, exclusivity) | the kind lattice of §2.6; `release_exclusive` | ABI fixed here; placement theirs |
| L05 (lifetimes) | counted-lifetime cells only reach `dec`/`release`; a lexical lifetime's cells have no count word and never reach the type-blind free; their chunks come from `rt::alloc` | contract fixed; arenas theirs |
| L16 (frontend) | every crash op carries a source place, a primitive's guard the call's | unfixed (§1 D38) |
| L03 (spec, generator) | `Spec.Endings`, the runtime records | content here; generation theirs |
| L19 (harness) | a case's ending as `Spec.Endings.Ending`; leaks as the checked runtime's internal error | fixed here; the harness's shape theirs |
| L15 (C++) | DP-75's libc++ handler → `end(InternalError{LibrarySaid})` | unfixed until DP-75 is folded |
| 0007, 0020 (unbuilt) | per-thread guard bounds; a ring buffer's cell kind; a foreign cell's release | named, not designed |

## 3. QTT

**Where quantities and lifetimes reach the runtime.** The runtime never
reads a quantity; the lowering reads the type and picks an entry.
- *Quantity 0*: no word exists. An erased field has no slot (D48), so no
  cell carries it and no entry sees it. Nothing to pay.
- *Quantity 1*: linearity is not exclusivity (AGENTS.md); exclusivity,
  proved (`!idr.excl`, D24), selects the entries that read no count:
  `release_exclusive`, reuse with no test, `is_unique` folded to true
  (18 T-RC4), and R1's buffers consumed into the kernel.
- *Quantity ω*: counted; `inc`/`dec` instantiated per kind (§2.6).
- *Lifetimes* (D39, D40): `static` cells are never counted and never
  written by an entry; `frame` cells are released at count 0 without
  freeing; `counted` cells are freed at count 0; a lexical lifetime's
  cells carry no count word.

**Paid today though the type knew** (each a D10 violation, *read*):
- `idris_rt_inc`/`dec` test null and the odd bit on every word
  (`Rc/Rc.h:36-40, 100-108`), whatever its kind.
- `idris_rt_free_cell` tests null, the odd bit, the count and the stack
  bit on a token the take proved exclusive (`Rc/Counting.cpp:67-74`).
- `is_unique` tests the stack bit (`Rc/Rc.h:50-53`), though no frame
  value is exclusive (da66bd95).
- `idris_rt_persist_held` tests `count == 0` after every force
  (`Rc/Counting.cpp:81-86`), though whether the memo cell is static data
  is its lifetime, `static` in its type under D40: called only for a
  static memo cell, it tests nothing.
- `freeDead` tests the stack bit for every dying cell
  (`Rc/Freeing.cpp:127-135`). Under D40's order a counted cell holds only
  static and counted references, so a release that starts from a counted
  cell never meets a frame cell: `release<Counted>` has no stack test;
  only `release<Frame>`, whose cells may hold frame cells of the same
  frame, keeps it. The stack bit's run-time readers shrink to that path
  and the checked runtime.
- The exit status is tested inside the runtime (`Entry.cpp:88-107`); a
  `Fin 256` operand makes the test a guard at the site, folded for a
  constant.

**Representations that make a misuse unwritable.**
- R1's operands: a recv's buffer typed `!idr.q<1, excl, Buffer,
  counted>`, a zero-copy send's `own` at `counted` or `static`. A frame
  or lexical-lifetime buffer handed to the kernel fails the op's verifier
  (generated from the specification), so no scope can end under the
  kernel's write.
- The reactor's in-flight table holds move-only handles
  (`rt::Exclusive<Counted>`, copy deleted): an entry is handed back once
  at completion or released once at cancellation.
- The ending's type: `Crashed` takes a `Site` (no crash without one);
  `OutOfMemory` takes none (D23's "promises nothing about which
  allocation" is unwritable to break); `Exited` takes `Fin 256`.
- The component lattice: the generic null-and-odd test is the type `Any`,
  chosen only for a slot the layout says may hold all three, never the
  default for an unknown word.
- The specification's own laws, at quantity 0: distinct fixed statuses,
  every `Cause` with a message, every `Internal` mapped to `Abort`.

## 4. Improvements

**I1. The heap's span: the 4 GiB region becomes a coordinate, the page map
is bounded to the span.** *Coordinator* (C5 leaves "bounded or grown"
open, to be designed from snmalloc's source).
- Evidence: §1 D35 (324 GiB of address space, 256 GiB of it the page
  map), `Cells.cpp:93-105` (a 4 GiB reservation), `ds/pagemap.h:101-109,
  213`.
- Counterexample: `ulimit -v 2097152; ./hello` on any Linux target. Today
  the 64 GiB stack reservation fails and the program ends "no stack could
  be reserved", status 1; with only a small stack, snmalloc's first
  allocation reserves 256 GiB, fails, and the program dies by `SIGABRT`
  with "Failed to initialise snmalloc.", its output lost.
- Root cause: reservations sized by constants of the code, not by use or
  by the host.
- Correction: §2.1. The span's cursor reserves each chunk at a fixed
  address as snmalloc asks for it; the page map is snmalloc's bounded
  flat map covering only the span (storage `R/1024`), with one carried
  patch gating its fast-path range tests behind `sanity_checks`. The
  grown alternative, a two-level map with a leaf per 4 GiB region, was
  rejected: it adds a dependent load to every free and lookup, paid by
  every program for the strict-host case.
- Deletes: `heapRegion`, `addRegion`, the unbounded map's 256 GiB, the
  writable `reserve`.
- Discrimination: a test that runs a program under `ulimit -v` at the
  image plus a few MiB, plus 256 MiB, plus 1 GiB on the three Linux
  targets: it starts, and ends 111 with its output flushed exactly when
  its heap outgrows the limit; `tests/heap-region` keeps its placement
  property (cells of a heap under 4 GiB share one region).

**I2. snmalloc's commit reports failure; `pal_enforce_access` exactly.**
*Coordinator* (AGENTS.md: an upstream bug is fixed by a carried patch).
- Evidence: `pal/pal_posix.h:244-253`, `pal/pal_apple.h:214-228` ignore
  `mprotect`; `commitrange.h:36-46` already handles a false.
- Counterexample: a program on Linux with `ulimit -d` (`RLIMIT_DATA`) set
  just above its start: with `pal_enforce_access` and no patch, a chunk's
  `mprotect` returns `ENOMEM`, snmalloc hands out `PROT_NONE` memory, the
  first store faults outside the guard and the process dies by `SIGSEGV`
  with no message.
- Root cause: a refused commit returned as success.
- Correction: `upstream/<n>-snmalloc-commit-failure/snmalloc.patch`
  (`notify_using` returns `mprotect(...) == 0` in both PALs), with its
  report, plan (microsoft/snmalloc, a test beside its PAL tests) and
  `tests/upstream-snmalloc-commit-failure`; snmalloc becomes a patch
  project, which it is not today (`tools/patches.sh:22`: `llvm chez
  idris`; PINS.md:948-949); the runtime compiles the patched copy with
  `SNMALLOC_CHECK_CLIENT_MITIGATIONS=pal_enforce_access`.
- Deletes: the writable reservations (`pal_posix.h:337-338` takes the
  `PROT_NONE` branch).
- Discrimination: the upstream test, a C program over snmalloc alone
  under `RLIMIT_DATA`: with the patch the allocation returns null (errno
  `ENOMEM` under snmalloc's default continuation); without it, `SIGSEGV`.

**I3. One ending, generated; every program crash at an IR site.**
*Coordinator* (D37's table and D38's ABI as ruled; Q1 is the one row in
question).
- Evidence: ten free-text causes, status 1 (18 R-ABI-4); the harness's
  three copies (19 S3); `Handles.cpp:233-243`; `tests/buffer-range`'s
  site-less crashes.
- Counterexample: `tests/buffer-range` with input `3` today exits 1 with
  `idris-mlir: a byte range outside the buffer`, naming neither the
  program nor the site; a program calling `getString` on a directory
  entry's handle after the directory closed crashes inside the runtime
  with no site at all.
- Root cause: the kind of an ending held only as its text; crashes
  raised where the site is no longer known.
- Correction: §2.4 and §2.5: `Spec.Endings` and its generated variant;
  `end` the one exit; `getString`'s check a guard at the call; the
  pre-allocation size checks the `OutOfMemory` ending.
- Deletes: `IDRIS_RT_CRASHED`, `rt::start::Ending`, `checkStatus`,
  `idris_rt_crash`, `idris_rt_crash_str`, `idris_rt_main_return`,
  `idris_rt_io_exit` (replaced by `idris_rt_exit(uint8_t)`), the ten
  texts, `outOfMemory`, `tooLarge`, the harness's three protocols.
- Discrimination: the C variant has no `Crashed` without a `Site` (a
  type); `tests/runtime-start` rewritten to drive each ending and compare
  status and standard error; every committed crash names a site.

**I4. A crash's cause is an enum's immediate; the runtime holds the one
message table.** *Coordinator* (D38's meaning kept: a site as data).
- Evidence: `compile-time-cpp.md` (h) (a generated `CrashCause`);
  12 T9 passes the cause as text.
- Counterexample: a program with 40 guards of four causes in three files
  carries, under D38 as written, seven globals (four causes, three
  files); with the enum it carries three, and its cause texts cannot
  disagree with the specification's.
- Root cause: a kind spelt as text (AGENTS.md: "a name is text for a
  human").
- Correction: `idris_rt_crash_at(enum idris_rt_cause, file, line,
  column)`; the message table generated into the runtime.
- Deletes: per-program cause strings; the cause `StrAttr` on crash ops
  (`IdrCheckOps.td:22-26`, `IdrBase.td:304-308`), with L13.
- Discrimination: a program's object holds one datum per source file
  with a crash site and none per cause (a property of the produced
  artifact).

**I5. A leak is the checked runtime's internal error; the counter leaves
shipped programs and the compiler.** *Coordinator* (refines DP-81).
- Evidence: `Cells.cpp:153-157, 187-205`; `Ending.cpp:17-31`;
  `run.sh:13-39`; `Fold/Scope.cpp:21-31`.
- Counterexample: every shipped program pays a thread-local increment per
  allocation and a decrement per free; `exitWith ExitSuccess` reads as a
  return "whose count is missing" (`run.sh:23-25`); every compilation
  counts the folders' cells to report a runtime bug.
- Root cause: a test fact on every program's and every compilation's
  path.
- Correction: the counter exists only in the checked runtime
  (`IDRIS_RT_CHECKED`); at `Returned` it ends a run with cells live as
  `InternalError{Leaked n}`; the harness's leak runs link the checked
  runtime and compare endings; the primitives' ownership is tested by
  unit tests on the checked runtime, and the folders count nothing.
- Deletes: `liveCells` and `forgetCell` (shipped), `idris_rt_live_cells`,
  `reportLiveCells`, `IDRIS_RT_LIVE`, `countFoldLeak`, the harness's count
  parsing.
- Discrimination: the shipped archive defines no live-cell symbol (the
  archive check); a planted leak in a test program ends `SIGABRT` with
  `internal error: 1 cell live at the end` under the checked runtime.
  Cost to measure: one more link per program test (M10).

**I6. The program's static facts are one record; the Status root goes.**
*Coordinator*.
- Evidence: `IdrRuntime.td:80-96`; `Func.h:118-127`; `Posix/Files.cpp:104`.
- Counterexample: a program `wc` crashing prints `idris-mlir: ...`; under
  D32 its stack bound has no way into the runtime.
- Root cause: static facts passed as separate arguments or not at all.
- Correction: `idris_rt_program {body, cpu_features, stack_bytes, name}`
  (§2.2), `idris_rt_start` noreturn, ending in `Returned`; the name the
  driver gives the executable, compiled in (deterministic messages,
  skarnet's `PROG`), not `argv[0]`.
- Deletes: `idris_rt_main_return`, `RootKind::Status`, the hard prefix.
- Discrimination: a program built as `wc` crashes with `wc: fatal: ...`
  however it is invoked.

**I7. The signal stack is the host's minimum plus the handler's frames,
with its own guard.** *Coordinator* (corrects C5).
- Evidence: `Runner.cpp:33, 71-72`; the SDK's `sys/signal.h:341-342`;
  `AT_MINSIGSTKSZ` (*recalled*).
- Counterexample: an x86_64 host with AMX, whose signal frame exceeds
  glibc's legacy 8 KiB `SIGSTKSZ` (*recalled*): a compile-time constant
  gives 8 KiB, the guard's fault overflows the alternate stack into the
  page below, and the handler faults: `SIGSEGV`, no message.
- Root cause: a host fact taken for a target constant.
- Correction: §2.2's layout and §2.3's `signalStackMinimum()`.
- Deletes: `alternateSize` and its comment's guesses.
- Discrimination: a test reaching the guard on each target ends with the
  internal error's message and `SIGABRT`.

**I8. GMP's temporaries leave the stack.** *Coordinator* (corrects C5).
- Evidence: `tools/bootstrap.sh:1063-1064`; GMP's `TMP_ALLOC` (*recalled*).
- Counterexample: multiplying two Integers of a million digits each
  descends GMP's Toom recursion with tens of KiB of `alloca` per level; on
  a stack sized by D32's bound and a musl-sized margin it reaches the
  guard: an internal error on a valid program.
- Root cause: GMP's stack use outside the runtime's margin.
- Correction: GMP configured `--enable-alloca=malloc-reentrant` in
  `args_gmp`, so its temporaries come from the runtime's allocator
  (through the hooks, out of memory included), and built with
  `-fstack-clash-protection`; the runtime's own units take it too.
- Deletes: GMP's unbounded stack term.
- Discrimination: the runtime's depth constant computed from its build
  holds GMP's frames; the big-integer benchmarks measure the cost (M7).

**I9. The commit limit is where the cgroup kills.** *Coordinator* for the
hierarchy and the working set; the swap half is Q2.
- Evidence: §1 D36.
- Counterexample: a program in `/a/b` where `/a` has `memory.max = 512M`
  and `/a/b` has `max`: the leaf reads no limit and the kernel kills at
  512 MiB unnamed. Or a cgroup at 512 MiB holding 40 MiB of other
  processes: the heap's count reaches 480 MiB, the kernel kills first.
- Root cause: the limit read as one file's number, not as the kill point.
- Correction: §2.3: the smallest limit on the path, less the working set
  at start; held in `LimitRange`.
- Deletes: nothing (new).
- Discrimination: on each Linux target, in a v2 and a v1 cgroup, nested
  under a limited ancestor, a growing program ends 111 with its output,
  not `SIGKILL`.

**I10. Every ending but an internal error writes the program's files.**
*Coordinator* (D21 orders a file's writes before the crash).
- Evidence: `Ending.cpp:56-71`.
- Counterexample: `writeFile "log" "started"` buffered by libc, then
  `1 `div` 0`: today the crash loses "started"; `exitWith` would have
  written it.
- Root cause: the crash path releases standard output's buffer only.
- Correction: `end` closes the handle table at `Crashed`, `CrashedWith`,
  `OutOfMemory`, `Exited`, `Returned`; not at an internal error, which
  may be in a signal handler.
- Discrimination: that program's file holds "started" after its crash.

**I11. Probes make the guard one page and subsume D32's frame check.**
*Owner* (amends D32's wording "no frame is larger than the guard, checked
when built").
- Evidence: 5.11 K6; DP-80; `CMakeLists.txt:277` (no probes in the macOS
  tools).
- Counterexample: none against probes; against the check alone: a frame
  of the C library or GMP is never in the compiler's frame sizes, so the
  check cannot see it, while probes in GMP and the runtime catch it.
- Correction: probes everywhere (programs by module flags from the
  entry's page, runtime, GMP, tools); the guard one page; the build-time
  frame check deleted.
- Discrimination: a C function with a frame of four pages reaching the
  guard ends as an internal error, on each target.

**I12. 0017 D9 is free; D31's frame stacks live in the span.**
*Coordinator* (0017 amended in the same change).
- Evidence: 0017 D9, §2's table; D31, D32.
- Counterexample: a deep `foldlM` under D31 whose frame-stack chunks were
  mapped by a mechanism of their own would lie outside the heap's region,
  and the prefetcher would follow none of their references (0017 §3's
  1.20 to 1.28×, measured in a guest).
- Correction: frame-stack chunks from `rt::alloc`; the native stack at the
  span's start; D9's budget, its 64 GiB and P1's plan deleted.
- Discrimination: `tests/heap-region` extended: a frame, a frame-stack
  chunk and a cell share bits 32 and up.

**I13. The heap is initialised once, by the runner.** *Coordinator*.
- Evidence: `Cells.cpp:76-87, 107-124`; `Gmp.cpp:25-33` and its three
  callers (18 R-AL-10).
- Counterexample: none of behaviour; every slow path pays an acquire load
  for a fact the start's order fixes.
- Correction: `HeapConfig::init` from the runner (FixedRangeConfig's
  shape); GMP's hooks there.
- Deletes: `ensure_init`, two flags, `idris_rt_gmp_init` as an ABI entry.
- Discrimination: the unit tests and every host call the runner first; a
  runtime call before it is unrepresentable through the ABI.

## 5. Work units

Drafts for the implementation swarm; none dispatched here.

**WU1. The build and the carried patches.**
- Writes: `upstream/<n>-snmalloc-commit-failure/`,
  `upstream/<n+1>-snmalloc-bounded-pagemap-checks/` (README, patch,
  plan), `upstream/README.md`'s table, `tests/upstream-snmalloc-commit-
  failure/`, `tools/patches.sh`, `tools/bootstrap.sh` (`args_gmp` only),
  `runtime/CMakeLists.txt`, `CMakeLists.txt` (the target entries' OS
  unit, libc margin, macOS tools' probes), `PINS.md`.
- Outcome: snmalloc a patch project whose patched copy the runtime
  compiles with exactly `pal_enforce_access`; GMP malloc-reentrant and
  probed; the runtime profile probed; the OS units selected by the entry.
- Deletes: the writable reservation path's use; the macOS tools' probe
  gap.
- Must not: edit `third_party/snmalloc` in place; move a pin.
- Acceptance: the upstream test fails without the patch and passes with
  it, on the three Linux targets; the four targets build and pass the
  suites; `make check` regenerates and compares.

**WU2. The allocator and the span.**
- Writes: `runtime/Alloc/Alloc.h`, `runtime/Alloc/Cells.cpp`,
  `runtime/Alloc/Arrays.cpp`, `runtime/Alloc/Gmp.cpp`,
  `tests/heap-region/`.
- Outcome: §2.1: `HeapConfig` with the bounded map, `SpanRange`,
  `LimitRange`, `OutOfMemory`, our PAL; explicit init; the counter in the
  checked runtime only.
- Deletes: §2.10's `Alloc/` rows.
- Must not: touch `Platform/`, `Start/` or the counting entries (L07).
- Acceptance: a program under `ulimit -v` and `ulimit -d` starts and ends
  111, output flushed, exactly when its heap outgrows the limit (Linux);
  the heap-region property; the shipped archive has no live-cell symbol.

**WU3. The host's facts.**
- Writes: `runtime/Platform/Platform.h`, `runtime/Platform/Posix/
  Memory.cpp`, new `runtime/Platform/Linux/` and `runtime/Platform/
  Darwin/` units (memory, limits, signals).
- Outcome: §2.3's functions; T-PL4's OS units.
- Deletes: the writable `reserve`; `#ifdef MAP_NORESERVE`.
- Must not: read a fact anywhere but at start; add a setting.
- Acceptance: in a v1 and a v2 cgroup on each Linux target, nested under
  a limited ancestor and with swap allowed and not, a growing program
  ends 111 with its output (not `SIGKILL`); no limit read on macOS.

**WU4. The runner and the endings.**
- Writes: `runtime/Start/`, `runtime/Io/Ending.cpp` (deleted, replaced by
  `runtime/End/`), `runtime/idris_rt.h`, `runtime/Io/Handles.cpp`
  (`getString`), `runtime/Rc/Counting.cpp` (`checkLive`'s endings only;
  sequenced with L07's unit), `compiler/spec/IdrisMLIR/Spec/Endings.idr`,
  `tests/runtime-start/`.
- Outcome: §2.2 and §2.4: the program record, the layout, `end`, the
  crash and exit entries, `SIGABRT` for internal errors.
- Deletes: §2.10's `Start/`, `Io/Ending.cpp`, `idris_rt.h` rows.
- Must not: compute the stack bound (L10); add an ending outside the
  specification.
- Acceptance: a C test drives every ending and compares status and
  standard error; a recursion past the record's stack ends `SIGABRT`
  with its output flushed, on each target; a page-size mismatch and a
  missing feature end 126.

**WU5. The lowering's side.**
- Writes: `foreign/idr/lib/Conversion/Entry.cpp`, `Runtime.cpp` (crash
  calls), `StaticBytes.cpp`, `foreign/idr/include/idr/Conversion/
  StaticData.h`, `foreign/idr/include/idr/IR/Func.h`,
  `foreign/idr/lib/IR/Func/Func.cpp` (sequenced with L13).
- Outcome: §2.5: the record, the crash entries, per-file statics, probe
  flags from the entry's page.
- Deletes: `crashMessage`, `StaticData::message`, `RootKind::Status`.
- Must not: decide a cause's text (the specification's).
- Acceptance: every program test's endings hold; a produced object holds
  one datum per source file with a crash, none per site.

**WU6. The harness reads the ending.**
- Writes: `harness/lib/run.sh`, `harness/lib/e2e.sh`,
  `harness/lib/differential.sh`, the Idris harness's case reader,
  `tests/*/cases/*/expected-{exit,crash}` (to one `ending` each).
- Outcome: one record per case read into `Spec.Endings.Ending`; leaks run
  on the checked runtime as endings.
- Deletes: three protocols, `IDRIS_RT_LIVE`, the exit-beside-crash
  refusal (`e2e.sh:107-109`).
- Must not: parse the runtime's text beyond comparing bytes.
- Acceptance: every program test passes with its committed endings;
  `%differential` compares endings whole (19 S9).

## 6. Owner questions

**Q1. `exitWith` a status outside 0 to 255: an internal error or a
crash?** D37 rules "ends as an internal error naming it" (`SIGABRT`), but
its own rows define internal error as the compiler's or the runtime's bug
and a failed guard as a crash, and `ExitFailure 256` is a valid Idris
program (`System.idr:295`).
- *Internal error (as ruled)*: no change; costs a parent and a bug
  reporter a false "compiler bug", and the runtime keeps the test.
- *A crash at the exit's site* (status 1): the status becomes a byte by a
  guard in the IR, its failure the crash `exit status not 0 to 255` at the
  call; a constant status folds the guard away; the runtime's exit takes
  `uint8_t`, so an unreportable status is unrepresentable there. Costs the
  ruling's row.
- Recommendation: the crash.

**Q2. In a cgroup that may swap, where does a program end?** D36 names
`memory.max`; under cgroup v2 the kernel reclaims to swap past it while
`memory.swap.max` allows, and kills only when it cannot (*recalled*).
- *At `memory.max` (as written)*: a program ends, named, while the kernel
  would have kept it running, swapping; simple.
- *At the kill point* (`memory.max` plus the swap the cgroup may use;
  v1's memory-and-swap limit): the program ends exactly where the kernel
  would have killed it, which is the ruling's stated reason; costs one
  more file read at start and a slower program near its limit.
- Recommendation: the kill point.

## Measurements owed (none taken; no build exists here)

- **M1**: program start time on each target with today's reservations
  against §2's (`hyperfine` on a program that prints one line); the
  0.2 ms per 64 GiB on Darwin is 1445d894's, method unrecorded (debt).
- **M2**: start and ending under `ulimit -v` at the image plus 16 MiB,
  256 MiB, 1 GiB and 4 GiB on the three Linux targets; whether macOS
  enforces `RLIMIT_AS` on mappings.
- **M3**: the same under `ulimit -d`, and under overcommit mode 2 in a VM.
- **M4**: the cost of `pal_enforce_access`'s `mprotect` per chunk on the
  benchmarks.
- **M5**: a growing program in v1 and v2 cgroups, nested, with and
  without swap: named 111 against `SIGKILL`.
- **M6**: `AT_MINSIGSTKSZ` on each Linux target.
- **M7**: the runtime's deepest stack path (stack usage over the archive
  and a call graph of its functions), GMP's with malloc-reentrant, and the
  big-integer benchmarks under it.
- **M8**: chunks the span's cursor skips for foreign mappings, per target,
  on the benchmarks; the user address top each OS unit reads.
- **M9**: the runner thread's QoS against the main thread's on macOS.
- **M10**: the harness's time with a second, checked link per program test.
