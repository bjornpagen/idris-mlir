<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 wave 2, lane 18: runtime

Subsystem: `runtime/` (every `.cpp`, `.h`, `.c`, `CMakeLists.txt`,
`check-archive.sh`, `link_check.c`: `Alloc`, `Big`, `Doubles`, `Io`,
`Numerals`, `Platform`, `Rc`, `Start`, `Strings`, `idris_rt.h`,
`cpu_features.h`, `cpu_aarch64.h`, `cpu_x86_64.h`), and
`third_party/snmalloc` only where `runtime/Alloc` uses it.

Marks: *read* (path:line, commit, proposal section), *measured* (a count,
with its command), *recalled*, *conjecture*.

## 1. Reading notes

Proposal sections are `§N`, finding IDs as each lane writes them. All
*read* from `proposals/0000-mlir-native.md` unless marked.

**§1, §2, §4 (the brief and the bar).**
- §1: P0's scope names "the runtime's C++" beside `foreign/idr` and the
  Idris mirror; the owner asks "start thinking about running out of
  memory ... what the compiler and the runtime should do" (§5.11).
- §2: runtime C/C++ is 5,845 lines at e96bb991 (*read*; my count at
  HEAD is 6,284 lines with `CMakeLists.txt` and the script, §2 below).
  An `Idr_Runtime<"symbol">` trait "ties a primitive op to the runtime
  function that is its one meaning"; ~60 platform ops, "one per OS
  call"; per-signedness word ops; big, string, IO, check ops. Effect
  resources Crash, IO, Divergence, Lin, Reference, MemoState.
- §4: "four targets and nothing per-target outside the target's entry;
  static linking" kept whole; "a budget never rejects a program".

**§5.1 mlir-analysis.** Nothing on the runtime directly. G3
(ownership-based deallocation: function-boundary ABI, residual runtime
conditions) is the compile-time half of the counting runtime's contract;
5.1.5 hands it to rc. QA4/W1-W7 are compiler-side, not runtime.

**§5.2 mlir-ods.**
- A7: "may trap" and "may not end" are speculation
  (`ConditionallySpeculatable`), not memory effects; "must not be deleted
  even if unused (a syscall, a print)" is a `Write` on a resource.
  Bears on how a runtime crash (`idris_rt_crash*`) and every runtime
  call with side effects are declared.
- M7 / row 12: `Idr_Runtime<"symbol">` becomes a `NativeOpTrait`
  injecting `static constexpr StringLiteral getRuntimeSymbol()`, an
  interface `RuntimeFunction`, one interface-rooted lowering, and
  `idris-mlir-tblgen` reading the same record. That is the compiler half
  of "one meaning per primitive"; the runtime half is the C symbol
  table in `idris_rt.h` (§4 below, R-LIST-1).
- M8 / row 23: the ~60 platform ops and per-signedness word ops become
  TableGen families instantiated from one list, each carrying its
  runtime symbol and effect bundle. The runtime's `Platform.h` and
  `idris_rt.h` declarations are the other end of that list.
- Q1 (divergence and crash deletable when dead?), Q3 (resource tree:
  is Crash an ancestor of IO and heap?) touch what a runtime crash
  means; the owner's.

**§5.3 llvm.** I7 (per-node state a dense vector), I8 (a C++ list that
mirrors records is generated: `GenericTable`, `!instances`), B3 (closed
sets: enum + table), E2 (`SearchableTables`). For the runtime: the C
ABI symbol list and the platform-call list are such mirrored lists.
5.3.5 "oom": LLVM bounds analysis memory by laziness, representation
and caps.

**§5.4 modular.** F13 (Modular builds `-fno-rtti -fno-exceptions
-Wthread-safety -Wcovered-switch-default -Werror=global-constructors`),
design 8 (mechanical enforcement in the build). 5.4.5 "oom": Mojo's
compiler installs a bad-alloc handler that prints an actionable message
and exits 1 (`OOMHandler.h:24-37`). AsyncRT is "not to take" (a runtime
dependency). Nothing in §5.4 reads Mojo's own runtime allocator.

**§5.5 cxx26.** The runtime's C++ is judged by it.
- A.2/A.6: concepts, `consteval`, class NTTPs, deducing `this`, pack
  indexing, `= delete("reason")`, `_`, binding packs: all in the pinned
  clang, all work under `-fno-rtti -fno-exceptions`.
- A.5: `std::expected` complete; `inplace_vector`, `move_only_function`
  missing in the pinned libc++; libc++ hardening modes exist.
- D2: closed sums as `std::variant` + one `match`; `holds_alternative`
  and `get_if` banned outside `match`.
- D4b: "a list that exists only in our C++ is one `constexpr` table,
  indexed by its enum and checked at compile time" with
  `consteval indexedByEnum` and `static_assert`. D4a: a list over IR is
  generated from ODS (the runtime symbol, `Idr_Runtime<"symbol">`).
- D8: failure vocabulary; libc++ hardening (extensive in debug/test,
  measured for release) as the bootstrap's `LIBCXX_HARDENING_MODE`.
- 5.5.5 oom: "an allocation failure in libc++ under `-fno-exceptions`
  aborts (*recalled*, to check)".
- Q4 (§8.9's cxx-Q4): libc++ hardening mode for debug/test, release
  measured or unchecked.

**§5.6 ecosystem.** Compiler-side only. 5.6.5 "oom": no project bounds
a solver's memory. Nothing on runtimes.

**§5.7 library.** Compiler-side (sparse analyses, dense ids, frozen
tables). Nothing on the runtime.

**§5.8 dialect-design.** Several rows map onto runtime entry points:
- C6: "an abort is a write": `cf.assert` writes the default resource;
  `ub.unreachable` is a terminator with no effect. EF1: an abort that
  must be kept is an effect.
- EF2: a resource tree `World` with children `Console`, `Files`,
  `Environment`, `Clock`, `Process`; "a crash writes `World`". The
  runtime's own file split (`Io/`, `Platform/Posix/*`) is already that
  tree's shape (§2 below).
- O5: "`io.put_sint %x` is `io.write (str.show_sint %x)`, fused at
  lowering when the runtime has a faster entry point" (the runtime keeps
  or loses `idris_rt_put_sint`-style fused entry points).
- DS4 rows that change the runtime's symbol set: `check.crash`,
  `check.crash_str` -> one terminator `idr.crash` "with a reason or a
  message operand"; `NoReturn` -> crash/exit ops are terminators "after
  a terminating runtime call"; `divs/divu/mods/modu/shrs/shru` ->
  `arith.*` "where the runtime's meaning agrees on every input it
  defines"; `put_sint/put_uint/put_double/put_char` -> show then one
  `io.write`; "six stat-time ops -> one `io.file.stat` with several
  results, mirroring the one OS call" ("five ops, five runtime calls"
  deleted); "eight clock ops -> one `io.clock <kind>`, mirroring
  `clock_gettime`'s clock id"; `Idr_Runtime<"symbol">` kept ("it is the
  op's one meaning").
- DD-Q5: "may one op with an enum (`io.clock <kind>`, `idr.check
  <reason>`) map to several runtime functions, selected by a table
  generated from ODS, where `Idr_Runtime<"symbol">` ties one op to one
  function today?" (owner's).
- Wave-2 item: "Which word ops differ from `arith` on inputs the
  runtime defines (division by zero, shift amounts at or past the
  width, rounding of `div` and `mod`), and why `shls` and `shlu` are
  two ops." Answered in §3 below from the runtime side.

**§5.9 mlton.** Compiler-side. Design 6 (footprint per pass as a
report) bears on the compiler's OOM, not the runtime.

**§5.10 rc (read most carefully).** The runtime half of counting:
- A9: Koka's header `scan_fsize:8, field_idx:8, tag:16, refcount:32`;
  count 0 = unique, positive = more same-thread references, negative =
  thread-shared (atomic, counting down). `dup` tests `rc < 0`, `drop`
  tests `rc <= 0` (one test covers unique and shared). Sticky overflow
  band; static data starts stuck (`KK_HEADER_STATIC`).
- A10: freeing is stackless: 0 scan fields freed directly, 1 field (or
  2 with a non-pointer first) by a loop on the child; everything else
  by a parent chain threaded through the first field and the next field
  index in `_field_idx`. The compiler emits `dropn(x, scan)` when the
  scan count is static.
- B6: Lean: `rc > 0` single-threaded, `< 0` shared, `== 0` persistent;
  unique is `rc == 1`, which costs a second compare in `dec` that Koka's
  `rc == 0` does not.
- B7: Lean's dynamic linearity marker (a header bit that panics on a
  copy of a marked object).
- D1: Rust aborts on count overflow rather than freezing.
- F3: AGENTS.md puts threads outside the language, so idris-mlir has
  none of the three concurrency problems to solve "(*conjecture* until
  wave 2 reads the runtime ...)". Answered from the runtime in §3.
- M4: an exclusive operand makes Koka's `is_unique` test constant true;
  "the drop of an exclusive cell needs no load of its count at all".
- M9: "No thread-shared counts, so the runtime's fast path is Koka's
  single compare without the atomic half ... Lean's 'unique = 1'
  encoding costs a second compare in `dec` that Koka's 'unique = 0'
  does not."
- R1.4: `is_unique %x` an op whose folder returns true on an exclusive
  type; R1.5: `dup`/`drop` write the count resource, `is_unique` reads
  it (Swift's ordering hazard, C4).
- **R4 (runtime): "Koka's header without the atomic half. One 32-bit
  count with 0 meaning unique (one compare covers 'free' and 'special'
  in `drop`, A9), negative only for static and overflowed cells (sticky,
  never freed), no atomics (M9); `dropn` with the scan count known
  statically; Koka's stackless free with the parent chain threaded
  through the first field (A10); and, under R1, a drop of an exclusive
  cell that frees its children and itself without reading the count.
  Wave 2 compares this with `runtime/`."** This document's main
  reconciliation (§3 R4).
- Q2 (rc-Q2): how much exclusivity is static; "is a run-time uniqueness
  test an acceptable fallback". Q4 (rc-Q4): "Confirm that no counted
  cell is ever shared between threads, so the runtime needs no atomic
  count and no mark-shared pass".
- **W6 (mine): "The runtime's header and count: encoding of 'unique',
  atomics present or not, overflow, static cells, how a cell is freed
  (recursion, stackless, a known scan count), and whether an exclusive
  drop still reads the count (M9, R4)."** W9: arrays after
  bufferization freed by our code or upstream deallocation (shared
  with lane 11/12).
- 5.10.5 oom: "Koka and Lean freeze an overflowing count (... a
  bounded leak, never a use-after-free); Rust aborts."

**§5.11 oom (read most carefully; subject (B) is this lane's).**
- O2 (from proposals 0017 D7/D9, 0007 §3.1): heap is snmalloc's with
  "no limit of ours"; first 4 GiB of cells in one 4 GiB-aligned region,
  past which "snmalloc grows as it does with no bound"; stack is one
  64 GiB reservation with a guard and an alternate signal stack, shared
  by programs and tools (`idris_rt_run_on_stack`); 0017 D9 plans to fold
  the heap region and the stack top into one reservation.
- O3: shards give each core its own snmalloc allocator and count live
  cells per thread (0007 §5.1, D1).
- M1: snmalloc's failure is a template parameter (`Conts::failure`,
  default sets `errno = ENOMEM` and returns null,
  `mem/corealloc.h:21-61`). M2: backend is a pipe of range types;
  `StatsRange` keeps committed bytes (`get_current_usage`,
  `get_peak_usage`); "a limit ... is one more range type in that pipe".
  M3: release by `MADV_FREE` (Linux), `MADV_FREE_REUSABLE` (Apple);
  Linux reservations `MAP_NORESERVE`. M4: low-memory notification on
  Windows only. M5: the page size is a compile-time constant
  (`SNMALLOC_PAGESIZE`), 4 KiB default on arm64 Linux, 16 KiB on Apple;
  "On arm64 Linux at 16 KiB pages the right value is the target's
  entry's to give". M6: reservations writable unless
  `pal_enforce_access` (only `SNMALLOC_CHECK_CLIENT`).
- K2: under Linux overcommit mode 2 a writable reservation is charged in
  full; `ulimit -v` counts every mapping, so "a 64 GiB stack reservation
  fails every program under any `ulimit -v` below it".
- K6: guard pages catch an overflow only if no frame skips them; LLVM's
  `"probe-stack"="inline-asm"` and `stack-probe-size` (module flags);
  probe size is the target's page size, "a fact of the target's entry".
- (B) reading: OOM is outside the program's meaning; "the runtime's one
  job is to make it a *named* crash"; "The crash flushes the output
  buffer (0007 D3) and must not allocate on its way out". Stack overflow
  "with a correctness edge": without probes "a frame larger than the
  guard skips it and writes into whatever lies below, which 0017 D9
  would make the heap's region. That is a silent miscompile".
- Designs (B): B1 one named crash in the allocator's types (snmalloc
  `Conts::failure`; "Deletes: every null test after an allocation in the
  runtime's C++, if there are any (wave 2)"); B2 stack probes on every
  function, from the target's entry; B3 reserve then commit
  (`PROT_NONE` until used); B4 a limit as one more range (or the
  reservation's size); B5 give stack slack back; B6 a pressure signal
  inside the runtime only. Rejected: OOM as a value/effect; a catchable
  heap-overflow exception; soft limit with a CPU cap; per-shard limits.
- **Wave-2 items (mine): 1** what happens when snmalloc returns null
  (whose `Conts`, which message, which exit status, does the crash path
  allocate); **2** how the runner reserves 64 GiB and how `HeapConfig`
  reserves 4 GiB (`PROT_NONE` or writable, `MAP_NORESERVE`;
  `SNMALLOC_CHECK_CLIENT`/`pal_enforce_access`); **3** whether snmalloc
  is the compiler's own malloc (`peak_memory`, `ru_maxrss`); **4**
  whether lowering sets `probe-stack`, the guard's size, whether an
  overflow is named today; **5** whether `SNMALLOC_PAGESIZE` comes from
  the target's entry; **6** whether an array's byte size is checked for
  overflow before the allocator; 7-9 compiler-side (lane 13).
- 5.11.5 dialect-design: "`MemAlloc` on a constructor must stay free of
  `Crash`, or nothing allocating is pure".

**§8 (owner's questions this lane gives evidence for).** rc-Q2 (static
vs tested exclusivity), rc-Q4 (no counted cell shared between threads),
oom-1 (OOM outside the language), oom-4 (stack probes), oom-5 (a
limit), oom-6 (exit statuses), oom-7 (stack pages back), oom-8
(pressure signal), oom-9 (shards: process-wide limit, drain remote
frees), cxx-Q4 (libc++ hardening). Also touched: DD-Q5 (one op, several
runtime functions), ods-Q1/ods-Q3 (crash deletable / ordered), DD-Q4
(signedness: our runtime's per-signedness entry points).

**§9.** D1-D4: P0 first; honest solvers allowed; no code until the plan
is approved.

**proposals/0003-facts-once.md (the runtime's items, "target lane").**
- "No stack probes against the 1 MiB guard: set
  `"probe-stack"="inline-asm"` on program functions" (0003:340-341).
- "The user address width is a recorded minimum used as a maximum in
  `static_assert`s: record the maximum or check at startup" (0003:342-343).
- "The ending lost: the harness infers return, exit and crash from the
  status and stderr ... One report channel from the runtime"
  (0003:344-346).
- "`idr.crash_str` drops its site; lower it through `Runtime::crash`"
  (0003:336).
- "`idris_rt_memref_copy` re-reads the element layout the compiler had;
  simdutf re-tests the CPU word `idris_rt_start` already has"
  (0003:360-361).
- "Emitted code decodes the small word by hand ... `idris_rt_small_word`
  shows the runtime's own encoding can be called. Owed:
  `idris_rt_word_is_small` and `idris_rt_small_value` callable the same
  way" (0003:412-417).
- "The crash-site count and the crash effect disagree ... `idr.exit`"
  (0003:406-411): an `idr.exit` is a `NoReturn` op that is not a crash;
  the runtime's `idris_rt_exit` and `idris_rt_crash*` are the two ends.
- §1's rule: keep a fact when re-deriving it is a guess; derive it when
  it is a total cheap function of a smaller one source.

## 2. What the subsystem is

### 2.1 Files and sizes (*measured*)

Command: `for d in Alloc Big Doubles Io Numerals Platform Rc Start Strings;
do find runtime/$d -type f -exec cat {} + | wc -l; done`, and
`find runtime -name '*.cpp' -o -name '*.h' -o -name '*.c' | xargs cat |
wc -l` (5,845, the figure of §2), plus `runtime/*.h *.c *.sh
CMakeLists.txt` (867).

| part | lines | files | holds |
| --- | ---: | ---: | --- |
| `Alloc/` | 444 | 4 | snmalloc config (`HeapConfig`), cells, arrays, GMP hooks, live-cell counter |
| `Rc/` | 394 | 3 | inc, dec, is-unique, free-cell, persistence, the dying list |
| `Start/` | 280 | 3 | `idris_rt_start`, CPU test, exit status, the reserved-stack runner |
| `Platform/` | 878 | 14 | `rt::platform` interface; `Posix/` (9 units); `Aarch64/`, `X86_64/` CPU units; `Address.h`, `CpuBits.h` |
| `Io/` | 1,666 | 17 | stdout/stdin buffers, handle table, streams, files, dirs, env, clocks, crash/exit |
| `Strings/` | 627 | 8 | string cells, UTF-8, simdutf selection |
| `Big/` | 701 | 8 | tagged small word, GMP large path |
| `Numerals/` | 192 | 3 | `cast` from String |
| `Doubles/` | 235 | 4 | Ryu printing, fast_float parsing, truncation |
| `idris_rt.h`, `cpu_*.h`, `link_check.c`, `check-archive.sh`, `CMakeLists.txt` | 867 | 7 | the C ABI, CPU feature X-lists, build and archive check |

- **142 C entry points** (*measured*: an awk over every `extern "C"`
  definition in `runtime/**/*.cpp`, following a wrapped line), of which
  **71 are `idris_rt_io_*`**, 25 `idris_rt_str_*`, 21 `idris_rt_big_*`.
  133 are declared by the generated `idris_rt_ops.h` (from
  `IdrRuntime.td` and every `Idr_Runtime<"…">`; the copy in
  `build/typecheck/foreign/idr/include/idr/IR/idris_rt_ops.h` is from
  2026-10-18 and stale: it still declares `idris_rt_caf_release`, deleted
  by da66bd95), 9 are hand-declared in `idris_rt.h:309-317` (the
  "functions lowered code does not call").
- **C++ idioms** (*measured*: `grep -cE` over every runtime `.cpp`/`.h`
  but `cpu_*.h`): `template <` 3, `requires`/`concept` 0, `std::variant`
  0, `std::visit` 0, `switch (` 6, `union` 1, `virtual` 0, `constexpr`
  79, `consteval` 0, `static_assert` 20, `std::atomic` 4 (two objects),
  `thread_local` 1, `if constexpr` 4, `[[gnu::always_inline]]` 24,
  `[[gnu::noinline]]` 16, `reinterpret_cast` 18, `#define` 29,
  `enum class` 4 (+2 plain `enum`).
- **Error channel** (*measured*): 22 `rt::platform` functions return
  `bool` (`grep -cE '^bool [a-zA-Z]+\(' runtime/Platform/Platform.h`);
  25 `saveError()` calls, 5 `fail(E…)` calls, 2 `lastError()` reads in
  `Io/`; 16 `rt::io::Scratch` locals; 8 `return rt::io::nullHandle`.

### 2.2 The facts it holds (*read*)

| fact | where | encoding | readers |
| --- | --- | --- | --- |
| the header | `idris_rt.h:79-82` | `{uint32 count, uint32 info}`, one word | runtime, lowering (`Layout.h`, `CellInfo.cpp`) |
| the count | `idris_rt.h:35-45`, `Rc/Rc.h:21,45` | 0 persistent (static, never freed); 1..UINT32_MAX-1 owned refs, plain arithmetic; UINT32_MAX saturated (sticky, never freed). **Unique = count == 1 and not a stack cell** (`Rc.h:50-53`) | `rt::rc`, lowering (static data writes count 0), 0007's detach |
| the info word | `idris_rt.h:47-73, 104-132` | `tag:16 \| objs:8 << 16 \| kind:7 << 24 \| stack:1 << 31`; `objs == 0xFF` = "wide: the word after the header counts the slots" | freeing reads objs, kind, stack bit, and an array's tag/length (`idris_rt.h:47-50`); compiler builds it through `CellInfo` (`foreign/idr/lib/IR/Layout/CellInfo.cpp:16-49`) |
| kinds | `idris_rt.h:104-113` | box 0, thunk 1, string 2, bignum 3, array 4; stack bit `0x80000000`; checked runtime's freed kind `0x7F` (`Alloc/Alloc.h:29`) | runtime, lowering |
| a string | `idris_rt.h:135-156` | header, `bytes`, `scalars`, UTF-8; ASCII iff `bytes == scalars` (no flag) | runtime, lowering (static strings, `StaticBytes.cpp:105` calls `idris_rt_utf8_count`) |
| a big | `idris_rt.h:158-192` | odd word `2v+1` for v in [-2^62, 2^62-1]; even word = `idris_rt_bignum *` (GMP signed size, limbs inline); one representation per integer | runtime, lowering (`Conversion/Bigs.cpp` decodes the small word by hand, 0003:412-417), ranges |
| an array cell / memref | `idris_rt.h:194-240` | header (tag = element bytes, objs per element), `length` (runtime-only), elements; descriptor prefix `{allocated, aligned, offset}` | runtime (release, copy), lowering |
| a handle | `idris_rt.h:278-290`, `Io/Io.h:46-116`, `Io/Handles.cpp` | `int64`: -1 null, 0-2 std streams, 3 environment string, else a slot of a growable table; slot = `Kind` tag + union | base's pointer ops |
| an OSClock | `Io/Clock.cpp:3-33` | `seconds << 30 \| ns`, -1 invalid | base's clocks |
| errno | `Io/Errors.cpp:18-22` | `savedErrno`, set by `saveError()`/`fail()` after a failing call | base's errno, FileError (`idris_rt_io_file_errno` maps ENOENT/EACCES/EEXIST to 2/3/4, else +5) |
| a crash | `Io/Ending.cpp:66-71`, `Platform/Posix/Files.cpp:103-109`, `idris_rt.h:292-297` | flush stdout, write `idris-mlir: <cause>\n` to fd 2, `_exit(1)`; **every crash is status 1** | harness (infers return/exit/crash from status and stderr, 0003:344-346) |
| the stack | `Start/Runner.cpp:27-96` | one reservation `[alternate 1 MiB \| guard 1 MiB \| stack 64 GiB]`, writable, run on a new pthread; a fault in the guard is "stack exhausted" | programs and idris-mlir's tools (`foreign/idr/include/idr/Support/Stack.h:65-75`) |
| the heap | `Alloc/Cells.cpp:31-125` | snmalloc standard config copied as `HeapConfig`, plus one 4 GiB-aligned 4 GiB region given to the global range at first allocation; past it snmalloc grows without bound | programs, idris-mlir's folders |
| the page size | `Platform/Platform.h:164-178`, `Posix/Memory.cpp:43-59` | `IDRIS_RT_PAGE_SIZE` from the target entry, checked against `sysconf` at start | runtime, snmalloc (`Cells.cpp:146-147`) |
| the user address width | `Platform/Address.h:13` | `IDRIS_RT_USER_ADDRESS_BITS` from the target entry (47, 39, 47, 47: `CMakeLists.txt:205,222,241,273`) | `Freeing.cpp:44-51`, `Cells.cpp:138-141` static_asserts |
| the CPU features | `cpu_aarch64.h`, `cpu_x86_64.h` | X-macro `X(bit, test, name)` (29 and 21 entries) | `Start/Entry.cpp:54-64`, `Platform/CpuBits.h:20-28`, the compiler's `Conversion/Entry.cpp:29` |
| live cells | `Alloc/Cells.cpp:157,190,195,205` | `thread_local uint64_t` ++ on every cell, -- on every free | `IDRIS_RT_LIVE=1` report (`Io/Ending.cpp:17-31`), the harness (`harness/lib/run.sh:14-30`), the folders' leak count (`foreign/idr/lib/IR/Fold/Scope.cpp:21-31`), tests |

### 2.3 State (*read*)

Process-global mutable state, all written by one thread at a time
(programs are single-threaded; the program runs on the runner's thread,
`Start/Runner.cpp:92`): the stdout buffer and its atomic length
(`Io/Output.cpp:35-36`), the stdin buffer and flags
(`Io/Input.cpp:23-30`), the handle table (`Io/Handles.cpp:64-73`),
`savedErrno` (`Io/Errors.cpp:18`), the program's argv
(`Start/Entry.cpp:21-22`), the terminal mode (`Posix/Terminal.cpp:18-19`),
the runner's guard bounds and handler (`Start/Runner.cpp:16-18`), the
fault handler and saved actions (`Posix/Faults.cpp:12-15`), the chosen
simdutf implementation (`Strings/Simd.cpp:20`, relaxed atomic), snmalloc's
pool and init flag (`Cells.cpp:85-87`). Per-thread: `liveCells`
(`Cells.cpp:157`) and snmalloc's allocators.

### 2.4 Who reads it

- **Programs**, through bitcode: idris-mlir prepares the archive's
  bitcode once and joins it to every program module, so every
  `[[gnu::always_inline]]` entry (`idris_rt_cell`, `idris_rt_big_add`,
  the small paths) inlines; a program function past
  `idr::target::inlineCallerInstructions` (4,096 instructions,
  `foreign/idr/include/idr/Target/Target.h:118`) calls the runtime
  instead (`foreign/idr/lib/Driver/LinkRuntime.cpp:127-139`, 0781ed93).
- **idris-mlir**, natively: the folders call string and big entries
  (`foreign/idr/lib/IR/Fold/Scope.cpp:21-45`), the tools run on
  `idris_rt_run_on_stack` (`Support/Stack.h:65-75`), static data calls
  `idris_rt_utf8_count` (`Conversion/StaticBytes.cpp:105`).
- **The lowering's calls** (*read*): `helper::cell`, `isUnique`
  (`Conversion/RuntimeCells.cpp:35,102`), `inc`/`dec` per reference
  (`Conversion/Runtime.cpp:212-218, 285-299`), `freeCell` for a token
  (`Conversion/Counting.cpp:48`, `Elements.cpp:78`), `crash` with a
  compile-time message `"<cause> at file:line:col"`
  (`Conversion/Runtime.cpp:42-50, 189-196`).
- **Tests**: `tests/runtime-api`, `runtime-counting`, `runtime-checked`,
  `heap-region`, `page-size-mismatch`, `runtime-start`, `io-buffer`,
  `runtime-archive-check`, `runtime-prepared` and others (lane 19).

### 2.5 Threading

Counting is plain arithmetic, no atomics (`idris_rt.h:41-42`,
`Rc/Rc.h:79-96`); a program is one thread (plus the main thread blocked
in `pthread_join`, `Posix/Stacks.cpp:39`). In idris-mlir the folders run
runtime string and big operations on worker threads: that is why
`liveCells` is `thread_local` (`Cells.cpp:153-157`) and the simdutf
choice is atomic (`Simd.cpp:18-20`); GMP's memory functions must be set
before any thread starts (`Alloc/Gmp.cpp:25-33`, called from three
places: `Start/Entry.cpp:142`, `Support/Stack.h:65`,
`foreign/idr/unittests/Main.cpp:8`). snmalloc's thread caches are not
returned when a thread ends (`CMakeLists.txt:170-177`).

## 3. Reconciliation with the proposal

### 3.1 Findings and designs that touch the runtime

**§5.10 A9 / M9 / R4 (the count's encoding, the fast path).** *Holds in
part.*
- No atomics, as M9 conjectures: *read*, `idris_rt.h:41-42` ("counted
  with plain arithmetic, since a program is single-threaded"),
  `Rc/Rc.h:79-96`. The only atomics are the stdout length for the
  signal handler (`Io/Output.cpp:29-41`) and the simdutf choice
  (`Strings/Simd.cpp:18-20`).
- Sticky overflow, as Koka and Lean: *read*, saturation at UINT32_MAX,
  never freed (`idris_rt.h:43-45`, `Rc/Counting.cpp:3-5`,
  `Rc.h:44-45, 79-84`).
- Static cells start stuck, as Koka's `KK_HEADER_STATIC`: count 0 is
  persistent, never written, so static data may be read-only
  (`idris_rt.h:35-40, 209-212`).
- **Refuted for the encoding of "unique":** ours is Lean's, `count == 1`
  (`Rc.h:50-53`), not Koka's `0`. So the inlined decrement of a cell is
  two branches on its fast path: `isCounted(count)` (one unsigned
  compare, `count - 1 < UINT32_MAX - 1`, which already folds persistent
  and saturated into one test, `Rc.h:45`) and then `count == 1`
  (`Rc.h:89-95`). Koka's signed encoding (0 unique, positive more,
  negative sticky) makes the non-last decrement one branch and makes
  overflow fall into the sticky band with no saturation test at all
  (`inc` is `if (rc >= 0) ++rc`, and INT32_MAX + 1 is negative). That is
  the measurable half of R4 (§5 T-RC1); the cost is one ABI constant
  (the persistent count: static data's header, `persistHeld`'s write,
  0007's detach table) moving from 0 to the sticky value.
- `is_unique` reads two words, the count and the stack bit
  (`Rc.h:50-53`); the stack bit re-derives a fact the grade holds (no
  value is exclusive and of the frame, da66bd95's message; §4 R-RC-3).

**§5.10 A10 (freeing).** *Holds in part.* Freeing is stackless and
allocation-free, but by Lean's design (`lean_del_core`, named at
`Rc/Rc.h:3-7`), not Koka's: the dying cells form a stack threaded
through their own headers, the next address split over the count (32
bits) and the tag field (16 bits), or an array's length's top 16 bits
(`Rc/Freeing.cpp:16-81`). The first dead cell is released without a
push (`Freeing.cpp:151-159`). There is no `dropn` with a static scan
count: the slots are always read from the header (`Freeing.cpp:91-113`).
The design rests on every heap and stack address fitting 48 bits
(`Freeing.cpp:44-51`), asserted against the target entry's user address
width, which is recorded as a minimum (39 on arm64 Linux 4K,
`CMakeLists.txt:222`) and used as a maximum (0003:342-343).

**§5.10 M4 / R1.4 ("the drop of an exclusive cell needs no load of its
count").** *Refuted for today's code.* An exclusive take moves its
fields out with no test (`Conversion/Counting.cpp:90-96`), but the token
is then freed by `idris_rt_free_cell`, which tests NULL/odd, reads the
count (`isCounted`) and reads the stack bit
(`Rc/Counting.cpp:67-74`). The type knew all three.

**§5.11 O2.** *Holds* (*read*): the 4 GiB region (`Cells.cpp:31-39,
93-105`), past which snmalloc grows from its platform layer; the 64 GiB
stack with a guard and an alternate signal stack (`Runner.cpp:27-44,
71-96`), shared with the tools (`Support/Stack.h:56-75`). Precisions:
the guard is 1 MiB (`Runner.cpp:35-37`), and the alternate stack lies
*below* the guard (`Runner.cpp:71-72`), so a frame that skips the guard
lands first in the writable signal stack. §5.11.2's "whatever lies
below, which 0017 D9 would make the heap's region" is not what D9 lays
out: D9 puts the stack's *top* at the bottom of the heap's region
(proposal 0017, D9), and the stack grows away from it; below the guard
are the signal stack and whatever mapping precedes the reservation.

**§5.11 M1 (snmalloc's failure is a type).** *Holds; not used.* The
runtime calls `snmalloc::alloc(size)` with the default `Uninit`
continuation (`third_party/snmalloc/src/snmalloc/global/globalalloc.h:347-348`,
`mem/corealloc.h:31-61`: `failure` sets `errno = ENOMEM`, returns null)
and then tests null in its own code (`Cells.cpp:168-173`), and does the
same after `snmalloc::libc::realloc` (`Cells.cpp:178-183`). B1's
continuation would delete both tests.

**§5.11 M2-M6.** *Hold, with two additions.*
- M5: `SNMALLOC_PAGESIZE` is the target entry's page
  (`runtime/CMakeLists.txt:34`), asserted equal to snmalloc's
  `OS_PAGE_SIZE` (`Cells.cpp:142-147`), and the runtime's own check
  compares it with `sysconf` at start (`Posix/Memory.cpp:43-59`).
- M6: snmalloc is not built with `SNMALLOC_CHECK_CLIENT`
  (`runtime/CMakeLists.txt:31-35` sets only the header-only build, the
  8-byte step, the page and the vendored STL), so its reservations,
  its flat pagemap's included, are writable from the start
  (`third_party/snmalloc/src/snmalloc/pal/pal_posix.h:337-360`). The
  runtime's own `reserve` is writable too (`Posix/Memory.cpp:65-85`,
  `PROT_READ | PROT_WRITE`, `MAP_NORESERVE` where defined).
- Addition: snmalloc's own fatal errors (pagemap init, entropy) go to
  `PAL::error`, which writes `"\n<msg>\n"`, prints a stack trace and
  `abort()`s **without flushing the program's output**
  (`pal_posix.h:189-201`, its comment says so; called from
  `ds/pagemap.h:66,183,223,248,260,271,343,410`). Our `HeapConfig` uses
  `DefaultPal` (`Cells.cpp:51`), so these are a second crash format and
  a second exit (SIGABRT) beside `idris_rt_crash`.
- Addition: snmalloc is **not** the tools' malloc. Nothing compiles
  `snmalloc/override/*` (`runtime/CMakeLists.txt:51-104`; *measured*:
  `grep -rn 'snmalloc/override' runtime foreign/idr/CMakeLists.txt
  CMakeLists.txt` finds nothing); the runtime uses only `snmalloc::alloc`,
  `dealloc` and `libc::realloc` (*measured*: the `snmalloc::` symbol list
  over `runtime/`). So LLVM's `-track-memory` reads libSystem's or
  glibc's malloc (§5.11 C1) and sees the compiler's own heap, not the
  folders' cells.

**§5.11 K2 (reservations under strict overcommit and `ulimit -v`).**
*Holds for us* (*read*, then *conjecture* on the host behaviour): every
program reserves, writable, the 64 GiB + 2 MiB runner region at start
(`Runner.cpp:76-80`), and at its first allocation the 4 GiB heap region
(`Cells.cpp:94, 107-123`) and snmalloc's flat pagemap (`ds/pagemap.h:102-108,199`: one entry per
2^14-byte chunk over `address_bits`; with 48 bits and two-word entries
that is on the order of 2^34 × 16 B, *conjecture* from the types). On
Linux all carry `MAP_NORESERVE`, which overcommit mode 2 ignores. The
history shows the owner removed the ulimit-derived stack and its
halving search on purpose (1445d894: "IDRIS_RT_STACK, the ulimit-derived
default and its 2^44 ceiling, stackLimit, the runner's halving search
... are gone").

**§5.11 K6 / B2 (stack probes).** *Holds*: no `probe-stack` anywhere
(*measured*: `grep -rn 'probe-stack\|stack-probe' foreign compiler
CMakeLists.txt tools` finds nothing). The claim at `Runner.cpp:35-36`
("a frame larger than this could step over them, and none is") is
checked by nothing. Stack cells are bounded (idr-stack keeps a box of
≤ 256 bytes, ≤ 1024 bytes per frame: proposal 0017, its table row on
the stack), and every other alloca the lowering makes is of fixed size
(`Conversion/Cells.cpp:84-97`, `Memrefs.cpp:51-53`,
`PassThroughMemory.cpp:82`), so a frame past 1 MiB is unlikely but not
unrepresentable. The tools are compiled with `-fstack-clash-protection`
on the three Linux targets and without it on macOS
(`CMakeLists.txt:207,226,242,277`); the runtime's own units on none
(`runtime/CMakeLists.txt:134-141`).

**§5.11 B1-B6.** B1 *holds* as a design and deletes two null tests
(above) and one crash format (snmalloc's). B2 *holds* (above). B3 *holds
in part*: the heap region and the pagemap can be `PROT_NONE` until
snmalloc's `notify_using` commits them (the hook exists:
`backend_helpers/commitrange.h:28-60`), but a pthread stack cannot be
`PROT_NONE` without committing on fault, which the runner's fault
handler could do (`Start/Runner.cpp:22-25`). B4: history shows the
owner tried and reverted a hard heap bound on the same day (07aeb299
"a program's heap is one region that never grows: IDRIS_RT_HEAP's bytes,
else half the physical memory"; 1445d894 "Memory is the machine's ...
no runtime setting or harness bound"). B5, B6: nothing exists today.

**§5.2 M7 / row 12 (`Idr_Runtime<"symbol">`).** *Holds, and the runtime
half is already one source.* `Idr_Runtime` is a `NativeOpTrait` with a
`symbol` field (`IdrBase.td:265-276`), and `IdrRuntime.td:3-12, 54-96`
records the 14 functions no op names; `idris-mlir-tblgen
-gen-runtime-abi-decls` writes `idris_rt_ops.h`, which `idris_rt.h:249-253`
includes inside its `extern "C"`, so a definition that disagrees with its
record fails to compile. The one hand list left is `idris_rt.h:306-317`
(9 native-only prototypes).

**§5.2 M8 / §5.8 DS4 (op families and their runtime functions).**
*Holds in part; three rows are corrected by the runtime.*
- "six stat-time ops ... five ops, five runtime calls": *refuted as
  stated.* The OS call is already one: `idris_rt_io_file_time` does one
  `fstat` into a file-time handle (`Io/FileTimes.cpp:32-44`,
  `Posix/Files.cpp:57-72`), and six functions read six fields of that
  slot (`FileTimes.cpp:48-53`), mirroring base's six getters over a
  pointer. One op with six results would delete `Kind::Times`, the six
  readers and the handle (§5 T-IO3).
- "eight clock ops → one `io.clock <kind>`": the runtime already holds
  one `readClock(Clock)` over an enum (`Platform.h:30-36`,
  `Posix/Clocks.cpp:13-34`); four C names exist only because one op
  names one symbol (DD-Q5). Two of the eight return a constant
  (`Io/Clock.cpp:54-58`, "no collector runs").
- "`put_sint`, `put_uint`, `put_double`, `put_char` → show then one
  `io.write`, fused at lowering": the runtime's fused entries format into
  a stack buffer and copy into the output buffer, allocating nothing
  (`Io/Output.cpp:146-176`); composing allocates a string cell. They are
  O5's "faster entry point" and stay only if the lowering fuses.
- `int_head_s`, `int_head_u`, `double_head` format the whole text to
  return its first character (`Strings/Show.cpp:26-36`,
  `Doubles/Printing.cpp:110-116`): the same fused shape.
- "`check.crash`, `check.crash_str` → one terminator": the runtime has
  `idris_rt_crash(cause, len)` and `idris_rt_crash_str(s)`, the second a
  one-line adapter (`Io/Ending.cpp:73-76`).

**§5.5 D2 (closed sums, one `match`).** *Holds; the runtime has none.* No
`std::variant` (*measured*), but four hand sums: `Slot` (a `Kind` tag
and a union, `Io/Io.h:53-85`), `ByteRead` (`Io.h:131-135`), `Numeral`
(`Numerals/Numerals.h:17-30`), and the `StreamOps` rows chosen by kind
(`Io.h:143-191`, `Handles.cpp:136-154`).

**§5.5 D4b (a C++-only list is one `constexpr` table checked by
`consteval`).** *Holds in part.* The CPU feature lists are X-macros
(`cpu_aarch64.h:16-45`, `cpu_x86_64.h:12-33`) expanded three times
(`Start/Entry.cpp:54-64` twice, `Platform/CpuBits.h:22-26`) and once in
the compiler (`foreign/idr/lib/Conversion/Entry.cpp:85`). The expansion in
`cpuFeatureBits` is essential: `__builtin_cpu_supports` takes a string
literal, which a table element is not (*recalled*, clang's diagnostic).
The other two expansions are names and bits, which a table holds.
`Replacement.cpp:24-32`'s `wellFormed` table is already D4b's shape.

**§5.5 D8 (failure vocabulary).** *Holds*: 22 `bool`-returning platform
calls with the reason in errno (§2.1); `std::expected<T, Errno>` is the
form.

**§5.5 D6/D8, cxx-Q4 (libc++ hardening).** The runtime is compiled with
`-D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_EXTENSIVE` like every
unit (`CMakeLists.txt:324-326`): evidence in §6.

**§5.3 E4 (X-macros are TableGen's poor relation).** *Holds*: the CPU
lists above.

**§5.4 design 8 (`-Wthread-safety`, `-Werror=global-constructors`).**
The runtime already enforces "no static constructors" by an archive
check (`check-archive.sh:73-101`) and links with no C++ library
(`runtime/CMakeLists.txt:305-312`, `link_check.c`); a
`-Werror=global-constructors` would move that check to compile time.

**0003's runtime items.** Each holds (*read*): stack probes
(0003:340-341; above), the address width as a minimum used as a maximum
(0003:342-343; `Freeing.cpp:44-51`, `Cells.cpp:138-141`), the ending lost
(0003:344-346; every crash is status 1, `idris_rt.h:292-297`), the
memref copy re-reading the element layout (0003:360;
`Alloc/Arrays.cpp:122-130`), simdutf re-testing the CPU (0003:361;
`Platform/X86_64/Cpu.cpp:28-44`), the small word decoded by hand
(0003:412-417; the runtime already exposes `idris_rt_word_is_small` and
`idris_rt_small_value` as `constexpr` in `idris_rt.h:171-180`).

### 3.2 Wave-2 questions of §5 answered

**§5.10 W6** ("the runtime's header and count: encoding of 'unique',
atomics present or not, overflow, static cells, how a cell is freed
(recursion, stackless, a known scan count), and whether an exclusive
drop still reads the count"):
- header `{uint32 count, uint32 info}` (`idris_rt.h:79-82`);
- unique = `count == 1 && !(info & IDRIS_RT_STACK_CELL)`
  (`Rc/Rc.h:50-53`, `Rc/Counting.cpp:55-60`);
- no atomics in counting (`Rc.h:79-96`);
- overflow saturates at UINT32_MAX and the cell is never freed
  (`Rc.h:44-45, 79-84`);
- static cells have count 0 and are never written (`idris_rt.h:35-40`);
  a static memo cell's force makes what it holds persistent
  (`Rc/Counting.cpp:76-86`, `Freeing.cpp:161-189`);
- freeing is stackless and allocation-free, a stack of dying cells
  threaded through their headers (`Freeing.cpp:37-81, 137-159`), slots
  always read from the header (no static scan count);
- **an exclusive drop still reads the count**: the token's
  `idris_rt_free_cell` reads NULL/odd, `count` and the stack bit
  (`Counting.cpp:67-74`).

**§5.10 W9** ("whether arrays after bufferization are freed by our code
or could be by upstream's ownership-based deallocation"), the runtime's
part: an array is a counted cell whose header says its element's bytes
and object slots and whose `length` exists so that the runtime can
release every element's slots when the cell dies (`idris_rt.h:194-216`,
`Freeing.cpp:106-112`). Upstream's deallocation would emit
`memref.dealloc`, lowered to a plain `free`, which releases no element
reference and does not decrement the live-cell count: it is correct
only for arrays whose elements hold no object (`objs == 0`) and that no
count ever shared. Lanes 11 and 12 decide.

**§5.11 W1** ("what happens today when snmalloc returns null: whose
`Conts`, which message, which exit status, and does the crash path
allocate"): snmalloc's default `Uninit` continuation (null, errno
ENOMEM); the runtime tests null and calls `outOfMemory()`
(`Cells.cpp:163-173, 178-183`), which is `idris_rt_crash("out of
memory")`: flush stdout, `idris-mlir: out of memory\n` on fd 2,
`_exit(1)` (`Io/Ending.cpp:66-71`, `Posix/Files.cpp:91-109`,
`Posix/Process.cpp:54`). The crash path allocates nothing (a static
buffer, `write`, `_exit`). Two exceptions: snmalloc's own `PAL::error`
(abort, unflushed, above), and libc++ hardening traps (§6 cxx-Q4).

**§5.11 W2** ("how the runner reserves its 64 GiB stack and how
`HeapConfig` reserves its 4 GiB region: `PROT_NONE` or writable,
`MAP_NORESERVE` or not; whether snmalloc is built with
`SNMALLOC_CHECK_CLIENT` or `pal_enforce_access`"): both through
`rt::platform::reserve`, `PROT_READ | PROT_WRITE`, `MAP_PRIVATE |
MAP_ANONYMOUS`, plus `MAP_NORESERVE` where the system defines it
(`Posix/Memory.cpp:65-85`); the guard is then `mprotect(PROT_NONE)`
(`Memory.cpp:87`, `Runner.cpp:83`). snmalloc is built without
`SNMALLOC_CHECK_CLIENT` (`runtime/CMakeLists.txt:31-35`), so
`pal_enforce_access` is off and its reservations are writable too.

**§5.11 W3** ("whether snmalloc is the compiler's own malloc"): no
(above); `peak_memory` reads `wait4`'s `ru_maxrss`
(`tools/host.sh:121-149`), resident size, which misses compressed pages
(lane 13 owns the measure).

**§5.11 W4** ("whether lowering sets `probe-stack`; the guard's size;
whether an overflow is named today"): no probes; the guard is 1 MiB
(`Runner.cpp:35-37`); an overflow that touches the guard is named
"stack exhausted" (`Start/Entry.cpp:77-82`) from the fault handler on
the alternate stack (`Runner.cpp:20-25, 53-57`), after flushing stdout;
the tools name it "`<tool>`: internal error: the stack is exhausted"
(`Support/Stack.h:66-67`).

**§5.11 W5** ("whether `SNMALLOC_PAGESIZE` comes from the target's
entry"): yes (`runtime/CMakeLists.txt:34`), asserted
(`Cells.cpp:142-147`).

**§5.11 W6** ("whether an array's byte size is checked for overflow
before it reaches the allocator"): yes for arrays: `count >
(SIZE_MAX - sizeof(idris_rt_array)) / stride` is a crash "array too
large" (`Alloc/Arrays.cpp:98-103`); a big shift past GMP's limb limit is
"out of memory" (`Big/Bitwise.cpp:39-41`); a string's ill-formed input
checks its room for overflow (`Strings/Replacement.cpp:88-91`); but
`idris_rt_str_alloc(bytes, …)` adds `sizeof(idris_rt_str) + bytes`
unchecked (`Strings/Making.cpp:20-28, 58-60`), trusting the lowering's
first pass.

**§5.8, wave 2, "which word ops differ from `arith` on inputs the runtime
defines"**: the runtime defines **none** of them. `divs`, `divu`,
`mods`, `modu`, `shls`, `shlu`, `shrs`, `shru` carry no `Idr_Runtime`
(`IdrScalarOps.td:23-52, 61-87`); their meaning is written twice in the
compiler, the folder (`foreign/idr/lib/IR/Ops.cpp:205-238`, Euclidean on
`APInt`) and the lowering (`foreign/idr/lib/Conversion/Scalars.cpp:59-82`,
arith plus a fixup), and a third Euclidean division lives in the runtime
for small bigs (`Big/Arithmetic.cpp:17-32`). The runtime's documented
meanings that bear on arith are the bigs': Euclidean `div`/`mod`
(`Arithmetic.cpp:114-139`), shifts as Scheme's `ash`
(`Bitwise.cpp:117-146`), and a double truncated modulo 2^64
(`Doubles/Truncation.cpp:10-26`), where `arith.fptosi` is poison out of
range.

## 4. Issues

Every claim *read* at the cited line unless marked. "T-…" names the
target-design item of §5 that disposes of it.

**The ABI (`idris_rt.h`, `IdrRuntime.td`).**

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| R-ABI-1 | `runtime/idris_rt.h:35-45`; `Rc/Rc.h:21,45,50-53,86-96` | state | "Unique" is `count == 1` (Lean's encoding); persistent 0 and saturated UINT32_MAX are two marks at both ends, so the non-last decrement is two branches and the increment needs a saturation test | T-RC1: Koka's signed encoding without the atomic half, after a measurement |
| R-ABI-2 | `idris_rt.h:104-113` | cpp | kinds and the stack bit are untyped `#define`s; the checked runtime adds a seventh mark by hand (`Alloc/Alloc.h:26-29`) | T-ABI1: a typed enum (C23 `enum : uint8_t`, *recalled* supported by the pinned clang) read by C and C++ |
| R-ABI-3 | `idris_rt.h:127-132`; `foreign/idr/include/idr/IR/Layout.h:52-79`; `foreign/idr/lib/IR/Layout/CellInfo.cpp:16-49` | rederivation | two C++ views of one word: the compiler's typed `CellInfo` builder and the runtime's raw `idris_rt_info_*` accessors | T-ABI1: one header-only `Info` view (builder and reader) shared by runtime and compiler |
| R-ABI-4 | `idris_rt.h:292-297`; `Io/Ending.cpp:66-71`; `Start/Entry.cpp:74`; `Posix/Memory.cpp:58` | list | every ending that is not a return or an exit is status 1 with a free-text cause; the cause is the only thing that names it (oom-6; 0003:344-346) | T-END1: one `Ending` sum, each case its status and message from one table |
| R-ABI-5 | `idris_rt.h:306-317` | list | 9 native-only prototypes hand-written beside the 133 generated from ODS | T-ABI2: records in `IdrRuntime.td` (a class for functions lowered code does not call), generated |
| R-ABI-6 | `idris_rt.h:278-290`; `foreign/idr/include/idr/IR/IdrPlatformOps.td:13-18` | list | the handle and OSClock encodings are stated twice in prose (runtime header and ODS description) | T-ABI2: stated once, in the ODS records' descriptions the header is generated from |
| R-ABI-7 | `idris_rt.h:303-304`; `foreign/idr/lib/Driver/ReadRuntime.cpp:147,184` | attribute | the baseline mark is an `annotate` string the driver matches by text | essential: one `#define` read by both sides; LLVM's annotation is how a source function reaches the driver; keep |
| R-ABI-8 | `Strings/Making.cpp:67-70`; `Big/Words.cpp:34-37` | dead | `idris_rt_str_release` and `idris_rt_big_release` are `idris_rt_dec` under two more names ("It is idris_rt_dec"), for the folders (`Fold/Scope.cpp:25,27`) and C tests | T-RC3: delete; folders call one typed C++ inline over `idris_rt_dec` |

**Allocation (`Alloc/`, snmalloc).**

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| R-AL-1 | `Alloc/Cells.cpp:163-173, 178-183`; `Alloc/Alloc.h:36-45` | upstream | the out-of-memory test is a null test after `snmalloc::alloc` (default `Uninit` continuation) and after `libc::realloc` | T-AL1: snmalloc's `Conts::failure` as a `[[noreturn]]` crash (§5.11 M1, B1); both null tests deleted |
| R-AL-2 | `Alloc/Cells.cpp:47-125` vs `third_party/snmalloc/src/snmalloc/backend/globalconfig.h` (`StandardConfigClientMeta`) | upstream | `HeapConfig` is a line-for-line copy of snmalloc's standard config plus one call (`addRegion`), and drops its metadata-protection branch by `static_assert` (`Cells.cpp:65-66`): a second copy that drifts with every snmalloc release (pinned latest release, AGENTS.md) | T-AL2: an upstream customization point (a seed-range or init-hook parameter of `StandardConfigClientMeta`), patched in `upstream/<n>/snmalloc.patch` with a plan, and the copy deleted |
| R-AL-3 | `Alloc/Cells.cpp:51`; `third_party/snmalloc/src/snmalloc/pal/pal_posix.h:189-201`; `ds/pagemap.h:66,183,223,248,260,271` | upstream | snmalloc's fatal errors use `DefaultPal::error`: a different format, a stack trace, `abort()`, the program's output unflushed | T-AL1: a `Pal` deriving `DefaultPal` whose `error` is the runtime's crash (the PAL is snmalloc's template parameter) |
| R-AL-4 | `Alloc/Cells.cpp:93-105`; `Platform/Posix/Memory.cpp:65-85`; `pal_posix.h:337-360` | per-target (host) | the 4 GiB region, snmalloc's flat pagemap and its chunks are reserved writable; under Linux overcommit mode 2 (`MAP_NORESERVE` ignored) or a `ulimit -v` they are charged or refused at start (§5.11 K2; *conjecture* on the host behaviour) | T-AL3: reserve `PROT_NONE`, commit through snmalloc's `notify_using` (`commitrange.h:28-60`) |
| R-AL-5 | `Alloc/Cells.cpp:153-157, 187-205`; `Io/Ending.cpp:17-31` | state | a `thread_local` live-cell counter is incremented and decremented on every allocation and free of every program, to serve a test protocol (`IDRIS_RT_LIVE`) and the folders' leak count (`Fold/Scope.cpp:21-31`) | T-AL4: count only where it is read (owner's question N2); measure the TLS cost on each target first |
| R-AL-6 | `Alloc/Alloc.h:34`; `Cells.cpp:136-137` | rederivation | `heapAddressBits = 48` restates snmalloc's `DefaultPal::address_bits`, asserted | keep: a check at the one boundary where snmalloc is included (Cells.cpp includes snmalloc alone so its fast paths inline, `Cells.cpp:3-10`) |
| R-AL-7 | `Alloc/Arrays.cpp:122-130` | rederivation | `idris_rt_memref_copy` reads the element's bytes and object slots from the target cell's header, though the lowering knew the element layout (0003:360) | T-AL5: the lowering passes the element (bytes, objs) as constants; the copy specializes (a `memmove` row for `objs == 0`) |
| R-AL-8 | `Alloc/Arrays.cpp:25-28, 98-103`; `Big/Bitwise.cpp:39-41`; `Alloc/Alloc.h:36-37` | list | a request no allocation can meet is "array too large" in one place and "out of memory" in another, though `Alloc.h` defines both as exhausted memory | T-END1: one ending, `OutOfMemory {requested}` |
| R-AL-9 | `Alloc/Arrays.cpp:106-110` | upstream | a new array whose elements hold objects is zeroed by `memset` after allocation | T-AL1: snmalloc's zeroing continuation (`Zero`, `corealloc.h:63-64`), which takes zeroed pages from the OS for large allocations |
| R-AL-10 | `Alloc/Gmp.cpp:25-33`; `Start/Entry.cpp:142`; `foreign/idr/include/idr/Support/Stack.h:65`; `foreign/idr/unittests/Main.cpp:8` | state | GMP's memory functions must be set before any thread; three hosts each call `idris_rt_gmp_init` | T-STK2: the runner sets them (programs and tools share it); the unit tests' main keeps its one call |
| R-AL-11 | `Alloc/Alloc.h:16-24`; `Cells.cpp:196-201`; `Rc/Rc.h:31-34`; `Rc/Freeing.cpp:133-134` | state | the checked runtime is the same sources with `IDRIS_RT_CHECKED=1`, branching at three `if constexpr` sites | essential: a test instrument compiled from the one source; the variant is decided at compile time; keep |

**Counting and freeing (`Rc/`).**

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| R-RC-1 | `Rc/Rc.h:36-40, 100-108`; `Rc/Counting.cpp:45,53`; `foreign/idr/lib/Conversion/Runtime.cpp:285-299`; `Layout.h:81-87` | rederivation | every `idris_rt_inc`/`dec` tests NULL and the odd bit, though the lowering's component type says whether it is a cell pointer, a big's word or a nullable slot of an unboxed sum; the runtime already has the untested `incCell`/`decCell` inside (`Rc.h:79-96`) | T-RC2: one entry per component kind (cell, maybe-cell, big word), the kind in `layout::Component` |
| R-RC-2 | `Rc/Counting.cpp:67-74`; `foreign/idr/lib/Conversion/Counting.cpp:40-53, 87-115` | rederivation | the token of an exclusive take is freed by `idris_rt_free_cell`, which re-tests NULL/odd, `isCounted` and the stack bit; the take's two outcomes (exclusive: the cell; shared: null) are merged by `scf.if` before the drop | T-RC4: `idris_rt_free_exclusive(cell)` that reads nothing, called where the token is known non-null; the typed token of 0003 (`!idr.token<!idr.box<T>, @C>`) carries it (lanes 01, 08, 12) |
| R-RC-3 | `Rc/Rc.h:50-53`; `Rc/Counting.cpp:55-60` | rederivation | `is_unique` tests the stack bit at run time, though no grade is exclusive and of the frame (da66bd95) and a frame value's uniqueness is constant false | T-RC4: `is_unique` reads the count alone; the lowering folds a frame value's test to false (lane 12); the bit stays for freeing (`Freeing.cpp:127-135`) |
| R-RC-4 | `audits/bugs.md:43-53`; `foreign/idr/lib/Conversion/Counting.cpp:63-115`; `Target.h:105-118`; `LinkRuntime.cpp:127-139` | budget | the wide take-apart: one `inc` per moving field and one `dec` per dying field (4,472 + 4,472 calls in one function), which the 4,096-instruction inlining budget exists to keep out of code generation; the runtime has no entry that counts a run of slots, though release already walks them (`Freeing.cpp:91-121`) | T-RC5: `idris_rt_inc_slots`/`idris_rt_dec_slots(first, n)` over contiguous object slots; then the budget's reason is gone (lanes 12, 13 decide the budget) |
| R-RC-5 | `Rc/Freeing.cpp:16-81`; `Platform/Address.h:9-13`; `CMakeLists.txt:205,222,241,273` | per-target | the dying list keeps the next address in 48 bits, asserted against the user address width, which the target entry records as a minimum (39 on arm64 Linux 4K) and the asserts read as a maximum (0003:342-343) | T-PL3: the target entry records the maximum the kernel may map (48 on every target today); essential otherwise (stackless freeing needs the spare bits) |
| R-RC-6 | `Rc/Freeing.cpp:91-113` | cpp | `eachSlot` is an unconstrained template (`template <typename Each>`) | T-CPP1: `std::invocable<Each &, void *&>` |
| R-RC-7 | `Rc/Freeing.cpp:31-35, 98, 127-135` | ladder | kind and stack bit tested in the freeing loop (array vs box, stack vs heap) | essential: the runtime frees any cell without knowing its type (`idris_rt.h:47-50`); three tests of one header, in one file; keep |
| R-RC-8 | `Rc/Counting.cpp:76-86`; `foreign/idr/lib/Conversion/MemoCells.cpp` | rederivation | `idris_rt_persist_held` runs after every force and tests `count == 0`, though whether the memo cell is static data is known when the lowering emits the call (*conjecture*: not checked in MemoCells.cpp) | lane 12: call it only on a static memo cell; the runtime's test stays as the boundary check |
| R-RC-9 | `Rc/Freeing.cpp:161-189` | state | `persistHeld` allocates a growable stack (and may crash out of memory) because a persisted cell's tag must survive | essential: persistence keeps headers; once per static memo cell; keep |

**The stack and the entry (`Start/`).**

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| R-STK-1 | `Start/Runner.cpp:35-37`; no `probe-stack` in `foreign/` (*measured*) | per-target | "a frame larger than this could step over them, and none is": the 1 MiB guard is not enforced; a frame past it skips the guard (oom-4, 0003:340-341) | T-STK1: `"probe-stack"="inline-asm"` and `stack-probe-size` = the target entry's page, as module flags, and `-fstack-clash-protection` in the runtime's profile |
| R-STK-2 | `Start/Runner.cpp:71-72, 76-92` | state | the layout `[alternate stack \| guard \| stack]` puts the writable signal stack right below the guard, so the first thing a guard-skipping frame writes is the handler's stack | T-STK1: a guard below the alternate stack too (`[guard \| alternate \| guard \| stack]`), or the alternate stack in its own reservation |
| R-STK-3 | `Start/Runner.cpp:39-44, 80`; `Posix/Memory.cpp:74` | per-target (host) | the 64 GiB stack is reserved writable; under overcommit mode 2 or a `ulimit -v` below it every program fails to start ("no stack could be reserved", `Entry.cpp:144-147`) (*conjecture* on the host behaviour) | owner's question N3; T-STK3 if the owner wants it: commit on fault through the runner's handler |
| R-STK-4 | `Start/Entry.cpp:79-82, 88-107, 144-147`; `Start/Start.h:19` | list | "stack exhausted", "no stack could be reserved", "main returned N…"/"exit with N…" are crash texts with status 1; `Ending { mainReturned, exited }` is half a sum (no crash, no stack) | T-END1 |
| R-STK-5 | `Start/Entry.cpp:40-75` (`checkCpu`, X-macro at 54-58, 62-64) | list | the processor test's names and bits are expanded from the X-macro twice | T-PL2: a `constexpr` table of (bit, name) checked by `consteval`; the X-macro stays only where `__builtin_cpu_supports` needs a literal (`CpuBits.h:22-26`) |
| R-STK-6 | `Start/Runner.cpp:16-18` | state | the runner's guard bounds and handler are process globals read by the signal handler | essential: a signal handler reads globals; one runner per process (`Runner.cpp:14-15`); keep |
| R-STK-7 | `Start/Entry.cpp:21-22` | state | the program's argv kept in globals | essential; keep |

**The platform layer (`Platform/`).**

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| R-PL-1 | `Platform/Platform.h:36, 59-138, 186-251` (22 `bool` returns); `Io/*.cpp` (25 `saveError()`, 5 `fail(E…)`, 2 `lastError()`) | cpp | the platform's failures are `bool`/null/-1 with the reason left in errno and read after the call: a check whose reason travels beside it | T-PL1: `std::expected<T, Errno>` from every fallible call; Io's adapter saves the error once |
| R-PL-2 | `Platform/Posix/Files.cpp:55-66`; `Platform/Aarch64/Cpu.cpp:19-32`; `Platform/Posix/Memory.cpp:67-72` | per-target | three preprocessor branches inside the platform layer (`__APPLE__` twice, `MAP_NORESERVE` once); the Aarch64 unit mixes the OS axis into the processor file | T-PL4: the target entry picks an OS unit as it picks the CPU unit (`CMakeLists.txt:202,217,236,251`); the branches deleted |
| R-PL-3 | `Platform/Platform.h:46-52`; `Platform/X86_64/Cpu.cpp:23-44`; `Platform/Aarch64/Cpu.cpp:36-38`; `Strings/Simd.cpp:30-37` | rederivation | simdutf's kernel choice re-tests the processor by feature strings, four of which (avx512vbmi, vbmi2, pclmul, vpopcntdq) are not in the target's list, so it cannot read the word `cpuFeatures()` already computed (0003:361) | T-PL2: the kernels' features join the target entry's list; each CPU file holds a `constexpr` table (simdutf name, required feature mask); the choice reads the startup word |
| R-PL-4 | `Platform/Platform.h:52`; `X86_64/Cpu.cpp:30-43` | ladder | a ladder of `name == "icelake"` / `"haswell"` / `"westmere"` / `"fallback"` | T-PL2: the table above; the names are simdutf's, essential at that boundary |
| R-PL-5 | `cpu_aarch64.h:16-45`; `cpu_x86_64.h:12-33`; `foreign/idr/lib/Conversion/Entry.cpp:29, 85` | list | the CPU features are an X-macro read by runtime and compiler | essential for `__builtin_cpu_supports` (a literal per feature); the compiler's and the startup's other readers take a `constexpr` table generated from the same list (T-PL2) |
| R-PL-6 | `Platform/Posix/Clocks.cpp:13-34` | ladder | a switch from `Clock` to `clockid_t` | minor: a `constexpr` array indexed by `Clock`, checked by `consteval` (T-CPP1) |
| R-PL-7 | `Platform/Posix/Process.cpp:28-35` | state | `environmentEntry(i)` walks `environ` from the start per index: listing the environment is quadratic | minor; base asks by index (`prim__getEnvPair`); keep unless measured |
| R-PL-8 | `Platform/Posix/Terminal.cpp:16-19`; `Posix/Faults.cpp:12-15` | state | saved terminal mode; fault handler and saved actions | essential; keep |

**Input and output (`Io/`).**

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| R-IO-1 | `Io/Io.h:53-85` | cpp | `Slot` is a hand tagged union (`Kind` + union), and `Kind` folds two axes: what the slot holds and who frees it (`String` vs `KeptString`; the standard streams) | T-IO1: a `std::variant` of payloads, ownership a separate field or alternative, matched once (§5.5 D2) |
| R-IO-2 | `Io/Handles.cpp:89-110, 136-154, 248-262, 236-240` | ladder | four switches or tests over `Kind` (release, row, free, string) | T-IO1: one `match` per question over the variant, or one `constexpr` table indexed by kind |
| R-IO-3 | `Io/Io.h:137-191`; `Io/Handles.cpp:124-134`; `Io/Input.cpp:75-98`; `Io/Output.cpp:87-125`; `Io/Files.cpp:31-68` | ladder | `StreamOps`, a hand table of 9 function pointers in 5 rows for a closed set, chosen from the slot's kind by `rowOf`: kind and row say one thing twice | T-IO1: the stream is the variant's alternative; operations are one `match` each (IO is cold, so dispatch cost is not the reason; the second copy is) |
| R-IO-4 | `Io/Io.h:129-135`; `Io/Lines.cpp:31-81`; `Io/Files.cpp:46-55` | cpp | `ByteRead { Got got; unsigned char byte; }`: the byte means something only for `Got::Byte` | T-IO1: `std::variant<Byte, End, Failure>` |
| R-IO-5 | `Io/Io.h:26-29`; `tests/io-buffer/run:73` | budget | `IDRIS_RT_IO_BUFFER_SIZE`, a test knob compiled into the runtime's sources | keep as a test seam (audits/config.md's rule at 0124edda) or replace by a test that writes past 4 KiB; owner's (N4) |
| R-IO-6 | `Io/FileTimes.cpp:16-53`; `Io/Io.h:60,79` | ods | one `fstat` into a file-time handle, then six functions read six fields; a `Times` kind exists only for that | T-IO3: with lanes 03/14, one op with six results; deletes `Kind::Times`, `field()`, five functions and the handle |
| R-IO-7 | `Io/Clock.cpp:37-58` | ods | four clock entries over one `readClock(Clock)`; two GC clocks return a constant | T-IO3: one entry taking the `Clock` enum, if DD-Q5 allows one op several functions or one function an enum operand |
| R-IO-8 | `Io/Output.cpp:146-176`; `Strings/Show.cpp:26-36`; `Doubles/Printing.cpp:110-116` | ods | fused entries (`put_char`, `put_int_s/u`, `put_double`; `int_head_s/u`, `double_head`) that format into a stack buffer | keep iff the lowering fuses `io.write(show x)` (§5.8 O5); otherwise delete with the ops (lanes 03, 12) |
| R-IO-9 | `Io/Terminal.cpp:26-27` | dead | `idris_rt_io_term_setup` is an empty function an op calls | T-IO4: delete; the op folds to its world (lane 03) |
| R-IO-10 | `Io/Ending.cpp:17-31, 45-49`; `harness/lib/run.sh:14-30`; `harness/lib/differential.sh:121-166` | state | every program reads the environment variable `IDRIS_RT_LIVE` at main's return; the last runtime setting left after 1445d894, kept as "the live-cell protocol the tests read" (`audits/config.md` at 0124edda:117-118) | T-END1/T-AL4: one report channel (0003:344-346); owner's question N2 |
| R-IO-11 | `Io/Ending.cpp:45-76` | list | three ends written separately (`main_return`, `io_exit`, `crash`), each choosing what it flushes and reports | T-END1 |
| R-IO-12 | `Io/Handles.cpp:233-240` | list | "a pointer read as a string holds none" is a crash text, status 1 | T-END1 |
| R-IO-13 | `Io/Scratch.cpp:20-32` | state | `Scratch::reserve` doubles without an overflow test | minor: every caller passes at most a buffer or a string's length (`Lines.cpp:52-55`, `Scratch.cpp:40-43`); keep |
| R-IO-14 | `Io/Errors.cpp:18-22`; `Io/Io.h:33-42` | state | `savedErrno`, a global the next failing call overwrites | essential: base's errno is "the last failing call's"; keep |

**Strings, numerals, bigs, doubles.**

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| R-ST-1 | `Strings/Making.cpp:20-28, 58-60` | state | `idris_rt_str_alloc(bytes, …)` computes `sizeof(idris_rt_str) + bytes` unchecked (arrays check, `Arrays.cpp:101`) | T-AL1: the size check moves into the one allocation entry (`newCell` takes a checked size), so no caller restates it |
| R-ST-2 | `Strings/Simd.cpp:43-50` | state | the simdutf implementation is chosen lazily on the first string call, a relaxed load on every call | keep: the folders call without `idris_rt_start`; after T-PL2 the choice is a table read |
| R-NU-1 | `Numerals/Numerals.h:17-30`; `Numerals/Machine.cpp:15`; `Big/Digits.cpp:58-60`; `Doubles/Parsing.cpp:33-57` | cpp | `Numeral` is a flat record (`kind`, `negative`, `base`, `digits`, `grouped`) whose fields mean something only for some kinds; three readers test `kind` | T-NU1: `std::variant<None, Integer{negative, base, digits, grouped}, Decimal{…}, Infinity{negative}, NaN>`, one `match` per reader |
| R-BG-1 | `Big/Arithmetic.cpp:17-32`; `foreign/idr/lib/IR/Ops.cpp:205-238`; `foreign/idr/lib/Conversion/Scalars.cpp:59-82`; `IdrScalarOps.td:23-52` | rederivation | Euclidean division three times: the runtime's (small bigs), the word ops' folder and their lowering; the word ops have no runtime function, so their one meaning (AGENTS.md) lives twice in the compiler | T-BG1, with lanes 03/12: word `div`/`mod`/shift either become runtime functions both the folder and the program call, or `arith` with one Idris edge each (DS4); the runtime's `euclidean` serves both |
| R-BG-2 | `Big/Big.h:120-125` | cpp | `binary<Op>` unconstrained | T-CPP1: `std::invocable<Op, mpz_ptr, mpz_srcptr, mpz_srcptr>` |
| R-BG-3 | `Big/Big.h:99-118` | list | twelve hand-declared large paths, one per op | keep: the split (inlined small path, out-of-line large path) is the performance structure (`Big.h:99-106`); a template would not remove the list |
| R-BG-4 | `Big/Digits.cpp:19-30` | state | `bigOfDigits` copies the digits without underscores into a temporary block for `mpz_set_str` | minor; keep |
| R-DB-1 | `Doubles/Printing.cpp:51-67` | upstream | Ryu's digits and exponent are printed by `d2s_buffered_n` and parsed back, because Ryu's `d2d` is internal | minor: an upstream export of Ryu's decimal (third_party/ryu, unmodified) or keep |

**Build and checks.**

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| R-BD-1 | `runtime/CMakeLists.txt:123-142`; `CMakeLists.txt:207,226,242,277` | per-target | the runtime's profile has no stack-clash protection on any target; the tools have it on Linux only (the target entry's flags) | T-STK1: probes from the target entry for programs, runtime and tools alike |
| R-BD-2 | `CMakeLists.txt:324-326` | cpp | the runtime is compiled with libc++'s extensive hardening, whose checks in a program trap (no C++ library linked; *recalled*) rather than name a crash | cxx-Q4 evidence (§6) |
| R-BD-3 | `runtime/check-archive.sh:67-71` | list | a hand regex of C++ runtime symbol prefixes | essential: the property is "no C++ runtime reference"; keep (lane 19) |
| R-BD-4 | `runtime/CMakeLists.txt:305-334`; `check-archive.sh:73-101` | ods | "no static constructors" is checked on the archive after the build | T-CPP1: `-Werror=global-constructors` in the runtime's profile moves it to compile time; the archive check stays for weak C++ references |
| R-BD-5 | `build/typecheck/foreign/idr/include/idr/IR/idris_rt_ops.h` (2026-10-18) | dead | a stale generated header in the tree's build directory declares `idris_rt_caf_release`, which no source defines | none: build output, regenerated by the build |

## 5. Target design

The runtime stays what AGENTS.md makes it: C++ with a C ABI, the one
meaning of every primitive, linked into every program as bitcode and
into idris-mlir natively, nothing per target outside the platform layer
and the target entry. What changes is where each fact lives. Every item
gives its representation, what it deletes, and the skill's one line.

### 5.1 Counting (the hot path)

**T-RC1. Koka's count without the atomic half** (§5.10 R4; R-ABI-1).
`int32_t count`: 0 = one reference (unique), positive = more, negative =
sticky (static and overflowed, never written by a decrement, never
freed). `dec`: `if (count > 0) --count; else if (count == 0) release();`
with the second test out of line; `inc`: `if (count >= 0) ++count;`
(INT32_MAX + 1 is negative, so overflow is sticky by arithmetic);
`is_unique`: `count == 0`. Static data's header and `persistHeld` write
the one sticky constant, `IDRIS_RT_STICKY`. *Deletes:* the saturation
test (`Rc.h:44-45, 82-83`), the `count == 1` second branch of the
non-last decrement (`Rc.h:92-95`). *One line:* the branch deleted: the
non-last decrement is one test, and overflow needs no test because the
sticky band is where it lands. *Gate:* a measurement first (instructions
per `dec` in `tests/runtime-counting`, a bench's run time), since the
cost of the change is the ABI's one constant and every reader of "count
0 is persistent" (static data in the lowering, 0007's detach table).
*Depends on:* lane 12 (static data's header), 0007 (unbuilt).

**T-RC2. One entry per component kind** (R-RC-1). `layout::Component`
gains the kind the lowering already knows: `Cell` (a non-null cell
pointer), `MaybeCell` (a slot of an unboxed sum, possibly NULL), `Big`
(odd word or cell). The ABI exposes `idris_rt_inc_cell`/`dec_cell` (no
test), `idris_rt_inc_maybe`/`dec_maybe` (NULL test), `idris_rt_inc_big`/
`dec_big` (odd test), each declared in `IdrRuntime.td`. *Deletes:*
`rt::rc::isObject` on every count of a cell pointer, the generic
`idris_rt_inc`/`dec` (hard cutover: no generic entry left). *One line:*
the check moved to the boundary: what a word can be is decided by its
type once, at lowering, and never re-tested at run time. *Depends on:*
lane 12 (`Runtime::countEach`, `Layout.h`), lane 01 (the component's
kind from the type).

**T-RC3. No aliases** (R-ABI-8). Delete `idris_rt_str_release` and
`idris_rt_big_release`; the folders hold one typed C++ inline over the
T-RC2 entries in their own header (`Fold/Scope.cpp`), the C tests call
the entries. *One line:* the second and third names of one function are
deleted.

**T-RC4. Exclusivity read from the type, not re-tested** (R-RC-2,
R-RC-3). `idris_rt_free_exclusive(cell)`: `freeCell(cell)` and nothing
else, called only where the token is a counted heap cell (the exclusive
branch of a take, or a token whose type says it). `is_unique` reads the
count alone; the lowering never emits it for a frame value (constant
false) and never for an exclusive one (constant true, §5.10 R1.4).
`idris_rt_free_cell`'s three tests go with it. *One line:* the state
"an exclusive token that might be NULL, persistent or on the stack" is
unrepresentable once the token's type carries its cell (0003's
`!idr.token<!idr.box<T>, @C>`), and the stack test leaves the
uniqueness question. *Depends on:* lanes 01, 08, 12 (the token type, the
take's lowering, the frame lifetime's soundness).

**T-RC5. Count a run of slots** (R-RC-4, `audits/bugs.md:43-53`).
`idris_rt_inc_slots(void *const *first, uint64_t n)` and
`idris_rt_dec_slots(void **first, uint64_t n)`, the loop
`Freeing.cpp:91-121` already runs, with the slot kinds of T-RC2 (a run
is of one kind). `LowerTake`'s shared side calls one per contiguous run
of moving slots, its exclusive side one per run of dying slots.
*Deletes:* 4,472 + 4,472 inlined calls in records-past-the-cell's
largest function; the reason for `inlineCallerInstructions`
(`Target.h:105-118`), which lanes 12 and 13 may then delete. *One line:*
the per-field branch is deleted: a cell's slots are counted where they
are, as one run, as release already walks them.

### 5.2 Allocation and running out

**T-AL1. One out-of-memory continuation, one PAL** (R-AL-1, R-AL-3,
R-AL-9, R-ST-1; §5.11 B1). `rt::alloc::Crash`, an snmalloc continuation
whose `success` is `DefaultConts`'s and whose `failure` is
`[[noreturn]] noexcept`, calling the ending of T-END1 with the request;
`allocate`, `newCell` and the GMP hooks use `snmalloc::alloc<Crash>`;
array cells with object slots use the zeroing variant. `rt::alloc::Pal`
derives `DefaultPal` with `error` routed to the same ending (snmalloc's
PAL is a template parameter of the config). The size of a cell is
checked once, in `newCell`, from `size_t` arithmetic with
`__builtin_add_overflow`. *Deletes:* the two null tests
(`Cells.cpp:170, 180`), `rt::alloc::outOfMemory`, `tooLarge`
(`Arrays.cpp:25-28`), snmalloc's second crash format, the `memset`
(`Arrays.cpp:109-110`). *One line:* the null pointer after an
allocation is unrepresentable: the allocator's type has no failing
return.

**T-AL2. snmalloc's standard config with a seed range, upstream**
(R-AL-2). An `upstream/<n>/snmalloc.patch`: `StandardConfigClientMeta`
takes a policy run in `ensure_init_slow` after the pagemap's init (the
place `addRegion` takes in our copy, `Cells.cpp:121`), defaulting to
nothing; our config is then that template with a policy that reserves
the 4 GiB-aligned region. The patch's plan names snmalloc's repository,
a test beside its fixed-range test, and the reason (Apple's DMP,
proposal 0017). *Deletes:* the copied class (`Cells.cpp:47-125` but the
policy). *One line:* the second copy of snmalloc's config is deleted.
If upstream refuses, the copy stays with a test that diffs its body
against the pinned `globalconfig.h` (essential then: no other hook).

**T-AL3. Reserve, then commit** (R-AL-4; §5.11 B3). `rt::platform::
reserve` maps `PROT_NONE`; a `commit(p, n)` makes pages writable;
snmalloc is built with `pal_enforce_access` (its own `notify_using`
commits, `commitrange.h:28-60`), and the heap region is committed by the
same path. *One line:* the state "reserved and already writable" is
gone: address space and commitment are two states, as Go's are.
*Gate:* the cost of an `mprotect` per chunk, measured on the bench.

**T-AL4. Count live cells only where they are read** (R-AL-5, R-IO-10).
The counter exists in the runtimes that read it: idris-mlir's (the
folders' leak count) and the checked runtime (which every leak test can
link, as `tests/runtime-checked` does). The program runtime has none,
and no environment setting. *Deletes:* the `thread_local` increments in
every program's inlined allocation, `reportLiveCells`, `IDRIS_RT_LIVE`.
*One line:* a test fact leaves the hot path of every shipped program.
*Owner's choice* (N2): the harness's leak check would then run on the
checked runtime, not the shipped one. *Gate:* the TLS cost per
allocation, measured per target.

**T-AL5. The memref copy takes its element** (R-AL-7). `idris_rt_memref_
copy(rank, from, to, bytes, objs)` with constants from the lowering, or
two entries (with and without object slots). *One line:* the check moved
to the boundary: the element is the compiler's fact, passed once.

### 5.3 Endings: one sum, one report

**T-END1. `Ending`** (R-ABI-4, R-AL-8, R-STK-4, R-IO-10-12; 0003:344-346;
oom-6). One closed sum in the runtime, generated as a table (a
TableGen record set read by the runtime and the harness, so the harness
stops parsing stderr text):

```cpp
// the shape, not the names
namespace rt::end {
struct Returned { int64_t status; };          // 0..255, else Unreportable
struct Exited { int64_t status; };
struct Crashed { std::span<const char> cause; };   // the program's crash
struct OutOfMemory { size_t requested; };
struct StackExhausted {};
struct NoStack {};
struct Unreportable { int64_t status; bool exited; };
struct WrongPage { size_t built, system; };
struct MissingCpu { uint64_t missing; };
struct Misuse { enum class What : uint8_t { DeadCell, ReturnedFrame, NotAString } what; };
using Ending = std::variant<Returned, Exited, Crashed, OutOfMemory, StackExhausted,
                            NoStack, Unreportable, WrongPage, MissingCpu, Misuse>;
[[noreturn]] void end(const Ending &);   // flush, write, report, _exit(statusOf(e))
}
```

Each alternative's exit status and message prefix sit in one
`constexpr` table indexed by the variant's index and checked by
`consteval` (§5.5 D4b); `end` is the one place that flushes, writes and
exits, async-signal-safe (no allocation), so the fault handler and the
allocator's continuation call it. The compiler's crashes (guards'
`crashCause` and `idr.crash_str`) are `Crashed`. Whether OOM, stack and
misuse get statuses of their own is oom-6 (the owner's); the sum makes
any answer one table row. *Deletes:* `IDRIS_RT_CRASHED` as the only
status, the ten literal cause strings (§4), `rt::start::Ending` and
`checkStatus`'s text assembly, `idris_rt_main_return`/`io_exit`/`crash`
as three hand-written ends (they become three calls of `end`). *One
line:* the state "a crash whose kind is only its text" is
unrepresentable; the ending is data the harness reads, not stderr it
parses.

### 5.4 The stack

**T-STK1. Probes from the target entry, and a guard under the signal
stack** (R-STK-1, R-STK-2, R-BD-1; §5.11 B2; 0003:340-341; oom-4). The
target entry's page size becomes `stack-probe-size`; idr-lower sets the
module flags `"probe-stack"="inline-asm"` and `stack-probe-size` (lane
12, lane 13 for the entry); the runtime's profile and the tools' take
`-fstack-clash-protection` on every target. The runner's region is
`[guard | alternate | guard | stack]` (or the alternate stack in its own
reservation). *Deletes:* the unchecked claim at `Runner.cpp:35-36`, the
macOS gap at `CMakeLists.txt:277`. *One line:* a frame that skips the
guard is unrepresentable: every frame touches every page it uses.

**T-STK2. The runner owns the process's one-time setup** (R-AL-10).
`idris_rt_run_on_stack` sets GMP's memory functions (it runs before any
thread of programs and tools alike, `Runner.cpp:73-96`,
`Support/Stack.h:56-75`); `idris_rt_start` and `runTool` stop calling
`idris_rt_gmp_init`, which leaves the ABI (the unit tests call the
runner or keep one private call). *One line:* the "call this before any
thread" protocol moves into the one function every host already calls
first.

**T-STK3** (only if the owner wants programs to start under strict
overcommit or `ulimit -v`; N3). The stack reserved `PROT_NONE` but its
top pages; the runner's fault handler commits the next chunk when a
fault lands in the reserved part below the committed one, and names the
exhaustion only at the guard. *One line:* reserved and committed become
two states of the stack, as T-AL3 makes them for the heap.

### 5.5 The platform layer

**T-PL1. `std::expected<T, Errno>`** (R-PL-1; §5.5 D8). Every fallible
`rt::platform` call returns its value or its `Errno` (a typed `int`);
`rt::io` has one adapter, `template <class T> T saved(std::expected<T,
Errno>, T onFailure)`, that writes `savedErrno` once. *Deletes:*
`lastError()`, the 25 `saveError()` and 5 `fail()` call sites as such
(they become the adapter's one write), the "false when …, errno says
why" protocol in 22 comments of `Platform.h`. *One line:* the check's
reason is returned with it, not left in a global to be read after.

**T-PL2. One processor test, one table** (R-PL-3, R-PL-4, R-PL-5,
R-STK-5; 0003:361). The target entry's feature list gains the features
simdutf's kernels are compiled with; `cpuFeatureBits` (the one
expansion `__builtin_cpu_supports` needs) is the only X-macro use; the
names and bits for the startup's message and the compiler's
`Conversion/Entry.cpp` are a `constexpr std::array` generated from the
same list; each CPU unit holds `constexpr` rows `(simdutf name, feature
mask)` and `runsSimdutf` reads the word `idris_rt_start` computed.
*Deletes:* the second `__builtin_cpu_init` and the string ladder
(`X86_64/Cpu.cpp:28-44`), two X-macro expansions (`Entry.cpp:54-64`).
*One line:* the processor is tested once; the kernel choice is a table
read, not a second test.

**T-PL3. The address width is a maximum** (R-RC-5; 0003:342-343). The
target entry records the largest user address the kernel may map (48
bits on the four targets as configured today; *conjecture* until each
target's kernel limits are read), which the dying list's asserts read.
*One line:* the assert checks the fact it relies on.

**T-PL4. The target entry picks the OS unit** (R-PL-2). As
`IDRIS_MLIR_RUNTIME_CPU_TEST` picks the processor unit
(`CMakeLists.txt:202,217,236,251`), an `IDRIS_MLIR_RUNTIME_OS` picks
`Platform/Darwin/` or `Platform/Linux/` for the three functions that
differ (stat's time fields, compiler-rt's CPU init, `MAP_NORESERVE`);
the rest stays `Platform/Posix`. *Deletes:* the three preprocessor
branches. *One line:* the per-target branch is deleted into the target's
entry, the one place AGENTS.md allows it.

### 5.6 Input and output, numerals

**T-IO1. Handles and streams as one sum** (R-IO-1 to R-IO-4).

```cpp
// the shape, not the names
struct Standard { enum class Which : uint8_t { In, Out, Err } which; };
struct OpenFile { rt::platform::File *file; };
struct OpenDirectory { rt::platform::Directory *dir; int64_t entry; };
struct HeldString { const idris_rt_str *s; enum class Owner : uint8_t { Program, Runtime } owner; };
struct Free { int64_t next; };
using Slot = std::variant<Free, Standard, OpenFile, OpenDirectory, HeldString>;
using Read = std::variant<Byte, End, Failure>;
```

A stream is the slot's `Standard` or `OpenFile` alternative; each
operation is one `match` (§5.5 D2) over it, a non-stream handle one
`Failure`. *Deletes:* `Kind`, the union, `StreamOps` and its five rows,
`rowOf`, `notOpen`, the four switches (`Handles.cpp:89-110, 136-154,
248-262`, the test at 236-240), `ByteRead`'s meaningless byte. *One
line:* the state "a slot whose tag and payload disagree", and "a stream
whose row and kind disagree", are unrepresentable; "a switch on a tag in
more than one place" becomes one `match` per question. (`Times` leaves
with T-IO3.)

**T-IO3. Op families the runtime already serves with one function**
(R-IO-6, R-IO-7; DS4, DD-Q5). With lanes 03 and 14: the file's times as
one op with six results over one runtime call (the slot, `Kind::Times`
and six readers go); the clocks as one entry over `Clock` if DD-Q5
allows an enum operand. *One line:* the runtime's one call stays one;
the five extra names are deleted.

**T-IO4.** Delete `idris_rt_io_term_setup` (R-IO-9); its op folds to its
world. *One line:* a call of an empty function is deleted.

**T-NU1. A numeral is a sum** (R-NU-1). `Numeral = std::variant<NoNumber,
Integer{negative, base, digitsAt, grouped}, Decimal, Infinity{negative},
NaN>`; `readNumeral` returns it; `idris_rt_str_to_int`,
`idris_rt_big_from_str`, `idris_rt_str_to_double` each `match` it.
*Deletes:* `Numeral::Kind`, the default-valued fields, three `kind`
tests. *One line:* "a base for a NaN" is unrepresentable.

### 5.7 One meaning per primitive; the ABI's one source

**T-BG1. Euclidean division once** (R-BG-1). With lanes 03 and 12: the
word ops `divs`/`mods` (and the shifts) either gain runtime functions
(`idris_rt_divs`, `[[gnu::always_inline]]`, the folder calling them as
it calls the bigs') or lower to `arith` with their Idris-defined edges
as one `select`/guard each (DS4); either way the runtime's `euclidean`
(`Arithmetic.cpp:17-32`) is the one Euclidean step, called by the bigs'
small path. *One line:* the second and third implementations of one
primitive are deleted (AGENTS.md: "its one meaning is the runtime's").

**T-ABI1. One typed view of the header** (R-ABI-2, R-ABI-3). The kinds
as a typed enum; one header-only `Info` (pack, unpack, `onStack`) in the
runtime's include directory, which `Layout.h`'s `CellInfo` and
`rt::rc`/`Freeing.cpp` both use. *Deletes:* `CellInfo.cpp`'s
re-implementation of the packing, the raw accessors' second view. *One
line:* one representation of the info word.

**T-ABI2. Every C entry point from ODS** (R-ABI-5, R-ABI-6). The 9
native-only functions become `IdrRuntime.td` records of a class the
lowering's table skips; the handle and OSClock encodings are stated in
the records the header is generated from. *Deletes:*
`idris_rt.h:306-317`'s prototypes and the duplicated prose. *One line:*
the ABI is one generated list.

**T-CPP1. The runtime's C++ against §5.5** (R-RC-6, R-BG-2, R-PL-6,
R-BD-4). Concepts on the three templates; the clock map as a `consteval`-
checked table; `-Werror=global-constructors` and `-Wthread-safety` in
the runtime's profile. Nothing virtual exists to remove; the variants of
T-END1, T-IO1, T-NU1 are the runtime's first, each with ≤ 11
alternatives (libc++'s `switch` path) or behind the tree's `match`
(cxx-Q2).

### 5.8 Order and dependencies

1. **Alone, no ABI change:** T-AL1, T-PL1, T-PL2, T-PL4, T-NU1, T-IO1,
   T-CPP1, T-STK2, T-RC3's folder side, T-PL3 (target entry).
2. **With the lowering (lane 12), ABI changes in `IdrRuntime.td`:**
   T-RC2, T-RC5, T-AL5, T-END1 (and the harness, lane 19), T-ABI1,
   T-ABI2, T-STK1 (and lane 13's entry).
3. **With the type of the token and the frame lifetime (lanes 01, 08,
   12):** T-RC4.
4. **With the op redesign (lanes 03, 14):** T-IO3, T-IO4, T-BG1, and
   R-IO-8's fused entries.
5. **Behind a measurement or the owner:** T-RC1 (instructions per
   decrement), T-AL4 (TLS cost; N2), T-AL3 and T-STK3 (N3), T-AL2
   (upstream's answer).

## 6. Evidence for the owner's questions

No answers: what the code says, by question.

**rc-Q2 (how much exclusivity is static; is a run-time uniqueness test
an acceptable fallback).**
- The runtime already serves both halves of R1. Where the grade proves
  exclusivity, the take moves fields out with no runtime call; otherwise
  it calls `idris_rt_is_unique` and branches (*read*:
  `foreign/idr/lib/Conversion/Counting.cpp:87-111`, its comment: "the
  grade is what Idris and counting proved, and a value they proved
  nothing of may still hold the only reference").
- The dynamic test costs two loads (count and info) and two compares
  (`Rc/Rc.h:50-53`); the static path still pays `idris_rt_free_cell`'s
  three tests on the token (`Rc/Counting.cpp:67-74`, R-RC-2).
- The cost of the fallback at scale is on record: records-past-the-cell's
  wide take-aparts, each a uniqueness test with a shared side of one
  increment per moving field, 4,472 increments and 4,472 decrements in
  one function, kept out of code generation by an inlining budget
  (*read*: `audits/bugs.md:43-53`, `Target.h:105-118`, 0781ed93: "LLVM
  stage 121 s -> 11 s").
- Nothing in the runtime specializes by grade (R2): there is one
  `is_unique` and one take-apart path per cell.

**rc-Q4 (no counted cell shared between threads; what shards pass).**
- Counting is plain arithmetic, no atomics (*read*: `idris_rt.h:41-42`,
  `Rc/Rc.h:79-96`); there is no mark-shared walk.
- In idris-mlir, folders run runtime operations on worker threads; each
  fold's cells are released by its `Scope` on the thread that made them
  before the fold returns, and its results are copied into attributes
  (*read*: `foreign/idr/lib/IR/Fold/Scope.cpp:21-58`), so no counted
  cell crosses a thread there (*conjecture*: no fold keeps a cell past
  its scope; the leak count would flag one, `Scope.cpp:28-31`).
- The live-cell counter is per thread because of the folders
  (`Alloc/Cells.cpp:153-157`); proposal 0007 relies on that ("zero live
  cells is checked on the sum over shards", 0007:260-262) and passes
  messages by detach: moved at count 1, copied otherwise, persistent
  cells by pointer (0007:240-262). A cell freed by another thread goes
  back through snmalloc's remote free (*recalled*, 0007:248).

**oom-1 (out of memory outside the language).**
- Today it already is: no entry point returns a failed allocation;
  `rt::alloc::allocate`, `newCell` and `reallocate` end the process
  (*read*: `Alloc/Alloc.h:36-49`, `Cells.cpp:163-183`), GMP's hooks too
  (`Alloc/Gmp.cpp:3-6`: "GMP cannot recover from a failed allocation").
- The crash path allocates nothing and flushes the output first
  (`Io/Ending.cpp:66-71`, `Posix/Files.cpp:91-109`), and is the same
  call the stack's fault handler makes (`Start/Entry.cpp:77-82`).
- The exceptions are snmalloc's own fatal errors, which `abort()`
  unflushed (`pal_posix.h:189-201`), and libc++ hardening traps
  (cxx-Q4 below).
- An allocating op carries no crash fact today: `idris_rt_cell`'s record
  returns a cell (`IdrRuntime.td:61-63`), and `idr.cell.new` lists no
  `Idr_MayCrash` (*read*: `IdrOwnershipOps.td:60, 182`; lane 02 owns
  the effects). So the IR already treats running out as outside the
  program's meaning, as §5.11.2 reads it.

**oom-4 (stack probes on all four targets).**
- No probes anywhere (*measured*: grep, §3.1); the guard is 1 MiB
  (`Start/Runner.cpp:35-37`) and the code's own comment asserts that no
  frame is larger, unchecked.
- Below the guard lies the writable alternate signal stack
  (`Runner.cpp:71-72`), so a skipped guard corrupts the handler's stack
  first (R-STK-2).
- Frames are bounded in practice: stack cells at ≤ 1024 bytes per frame
  (proposal 0017's table on the stack, from idr-stack), every alloca of
  fixed size (`Conversion/Cells.cpp:84-97`, `Memrefs.cpp:51-53`,
  `PassThroughMemory.cpp:82`); the runtime's largest frames are a few
  KiB (`Io/Io.h:208-224`'s 4 KiB `Scratch`, two in
  `idris_rt_io_file_open`, `Io/Files.cpp:82-94`; `checkCpu`'s pieces,
  `Start/Entry.cpp:50-51`).
- The tools have `-fstack-clash-protection` on the three Linux targets,
  none on macOS; the runtime on none (`CMakeLists.txt:207,226,242,277`;
  `runtime/CMakeLists.txt:134-141`).
- The probe size is the target's page, which the entry already holds
  (`IDRIS_MLIR_PAGE_SIZE`, checked at start, `Posix/Memory.cpp:43-59`).

**oom-5 (a memory limit for programs).**
- The owner has ruled on this once in the history: 07aeb299 made the
  heap one region that never grows (`IDRIS_RT_HEAP`'s bytes, else half
  the physical memory, snmalloc's fixed-range config), and 1445d894
  reverted it the same day: "Memory is the machine's ... IDRIS_RT_HEAP,
  the half-of-RAM bound, reserveHeap and byteSetting are gone"; "no
  runtime setting or harness bound" (*read*: the two commits'
  messages).
- The only environment setting a program reads today is
  `IDRIS_RT_LIVE`, a test protocol (`Io/Ending.cpp:17-31`).
- The hook a counter-based limit would use is ours already: the config
  names its `LocalState` (`Cells.cpp:69`, snmalloc's
  `StandardLocalState`, whose pipe holds `StatsRange`, §5.11 M2), so a
  limit is one more range in a type we own; the reservation-sized form
  is what 07aeb299 built and 1445d894 removed.

**oom-6 (exit statuses).**
- Every named ending that is not a return or an exit is status 1
  (`idris_rt.h:292-297`): the program's crash, out of memory, "array too
  large", stack exhausted, no stack reserved, an unreportable status, a
  wrong page, a missing CPU feature, a misused count or handle (ten
  runtime cause texts, §4 R-ABI-4).
- Other statuses reachable today (*read* for the first, *recalled* for
  the signals): snmalloc's `abort()` (128 + SIGABRT), a libc++
  hardening trap, a fault outside the guard re-raised with its previous
  action (`Posix/Faults.cpp:20-23`).
- The harness infers return, exit and crash from status and stderr
  (0003:344-346); T-END1 is the representation an answer would be
  written in, whatever the answer.

**oom-7 (returning the stack's pages).**
- Nothing returns them: the 64 GiB region is released only when the
  runner returns (`Runner.cpp:92-95`); no `madvise` exists in the
  runtime (*measured*: `grep -rn madvise runtime` finds nothing).
- snmalloc's chunks are released through its `CommitRange` (§5.11 M3),
  which our config keeps (`Cells.cpp:69`, `StandardLocalState`).
- Deep recursion is a tested shape (`tests/foldlm-deep` is named in
  e20b5b4a's message; proposal 0017 D9's 1 GiB budget).

**oom-8 (a pressure signal in the runtime).**
- None exists. A program is one thread with no reactor
  (`Start/Runner.cpp`, `Io/`); a signal would need a thread or a poll
  point, neither of which the runtime has. What it could release is
  only slack: snmalloc's caches and the stack's pages (oom-7); the
  runtime holds no cache of its own beyond the handle table and the
  4 KiB IO buffers (`Io/Input.cpp:23`, `Io/Output.cpp:35`).

**oom-9 (shards: process-wide limit; drain remote frees).**
- Shards are not built (0007 status line). The per-thread live counter
  is already the shape 0007 sums (`Cells.cpp:157`); snmalloc's backend
  ranges and pagemap are process-wide statics of our config
  (`Cells.cpp:85-87`), so only a process-wide limit falls out of today's
  representation (as §5.11 says).

**cxx-Q4 (libc++ hardening).**
- Every C++ unit, the runtime's included, is compiled with
  `-D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_EXTENSIVE`
  (*read*: `CMakeLists.txt:324-326`), in every configuration: there is
  no debug/release split today.
- The runtime links no C++ library (`runtime/CMakeLists.txt:3-11`,
  `link_check.c`), and the archive check refuses any `_Z…` reference
  (`check-archive.sh:67-71`), so a hardening path that called libc++'s
  verbose abort would fail the build; that the build passes says the
  runtime's checks trap (*recalled*: libc++'s fast and extensive modes
  trap rather than call the verbose handler; to verify at the pin).
- The runtime uses little of libc++: `<atomic>`
  (`Io/Output.cpp:20`, `Strings/Simd.cpp:12`), `<string_view>`
  (`Platform/Platform.h:24`), `<system_error>` (`Doubles/Parsing.cpp:11`),
  and fast_float's header; simdutf is built with `SIMDUTF_NO_LIBCXX`
  (`runtime/CMakeLists.txt:148-156`). So extensive mode costs the
  runtime nearly nothing, and its failure mode in a program would be a
  trap, not a named crash (T-END1 cannot catch it without a custom
  assertion handler, `_LIBCPP_ASSERTION_HANDLER`, *recalled*).

**Also touched.**
- **DD-Q5** (one op, several runtime functions): the runtime already
  has one function over an enum for clocks (`Posix/Clocks.cpp:13-34`)
  and one call for a file's times (`Io/FileTimes.cpp:32-44`); the many
  C names exist because `Idr_Runtime<"symbol">` names one symbol per op
  (`IdrBase.td:265-276`).
- **ods-Q1 / ods-Q3** (a crash kept, and ordered with IO): the
  runtime's crash flushes standard output before it writes its message
  (`Io/Ending.cpp:66-71`), so in the runtime's meaning a crash observes
  every earlier write; after it, the heap is unobservable.
- **DD-Q4** (signedness): the runtime has per-signedness entries only
  where the text or the conversion differs (`idris_rt_str_show_s/u`,
  `idris_rt_io_put_int_s/u`, `idris_rt_int_head_s/u`,
  `idris_rt_big_from_int_s/u`), never for arithmetic.

### New questions for the owner

- **N1. The count's encoding.** Adopt Koka's signed count without its
  atomic half (0 = unique, negative = sticky), after a measurement, at
  the cost of moving "count 0 is persistent" (static data, 0007's
  detach table) to the sticky constant (T-RC1)?
- **N2. Live cells in shipped programs.** Every program counts every
  allocation in a `thread_local` and reads `IDRIS_RT_LIVE` at exit, for
  the harness's leak check. Move the count to the checked runtime (and
  idris-mlir's folders), so the leak check runs on the checked runtime
  and shipped programs carry neither (T-AL4)?
- **N3. Strict hosts.** Today a program cannot start under Linux
  overcommit mode 2 or a `ulimit -v` below its reservations (64 GiB of
  stack, 4 GiB of heap region, snmalloc's pagemap; *conjecture* on the
  host behaviour). 1445d894 chose one constant knowingly. Should
  programs start there (T-AL3, T-STK3), or is that outside what a
  program promises?
- **N4. Test seams in the runtime's sources.** `IDRIS_RT_IO_BUFFER_SIZE`
  (`Io/Io.h:26-29`) is a knob a test compiles in: keep it as a seam, or
  require the test to work through the shipped buffer?
- **N5. snmalloc's config.** Patch snmalloc upstream for a seed-range
  hook (T-AL2), or accept our copy of its standard config with a test
  that compares it to the pinned one?

## 7. Deletion list

By file and symbol, each with the item that deletes it. Nothing here is
deleted without its replacement in the same change (hard cutover).

| file | symbol or lines | by |
| --- | --- | --- |
| `runtime/Alloc/Cells.cpp` | `rt::alloc::outOfMemory` (163-166), the null tests in `allocate` (168-173) and `reallocate` (178-183) | T-AL1 |
| `runtime/Alloc/Cells.cpp` | `HeapConfig`'s copied body (47-125) but its region policy | T-AL2 |
| `runtime/Alloc/Cells.cpp` | `liveCells` (157), its `++`/`--` (190, 195, 205), `idris_rt_live_cells` (223) in the program runtime | T-AL4 (N2) |
| `runtime/Alloc/Alloc.h` | `outOfMemory` (36-38), `forgetCell` if T-AL4 removes the counter (54-56) | T-AL1, T-AL4 |
| `runtime/Alloc/Arrays.cpp` | `tooLarge` (25-28), the `memset` (106-110), the header read of the element (124-125) | T-AL1, T-AL5 |
| `runtime/Alloc/Gmp.cpp` | `idris_rt_gmp_init` as an ABI entry (33) | T-STK2 |
| `runtime/Rc/Rc.h` | `saturated` and `isCounted` (21, 45) as written; `isObject` on cell paths (36-40, 100-108); the stack test in `isExclusive` (50-53) | T-RC1, T-RC2, T-RC4 |
| `runtime/Rc/Counting.cpp` | `idris_rt_inc`, `idris_rt_dec` (45, 53), `idris_rt_free_cell` (67-74) | T-RC2, T-RC4 |
| `runtime/Strings/Making.cpp` | `idris_rt_str_release` (67-70) | T-RC3 |
| `runtime/Big/Words.cpp` | `idris_rt_big_release` (34-37) | T-RC3 |
| `runtime/idris_rt.h` | `IDRIS_RT_CRASHED` as the one status (292-297); the hand prototypes (306-317); the duplicated handle/OSClock prose (278-290); the kind `#define`s (104-113) | T-END1, T-ABI2, T-ABI1 |
| `runtime/Io/Ending.cpp` | `reportLiveCells` (17-31); `idris_rt_main_return`, `idris_rt_io_exit`, `idris_rt_crash` as three hand-written ends (45-71) | T-END1, T-AL4 |
| `runtime/Start/Start.h`, `Start/Entry.cpp` | `rt::start::Ending`, `checkStatus`'s text assembly (Start.h:19-25, Entry.cpp:88-107); the cause literals (Entry.cpp:44-46, 80, 145); two X-macro expansions (54-64) | T-END1, T-PL2 |
| `runtime/Rc/Counting.cpp`, `Io/Handles.cpp`, `Posix/Memory.cpp` | the literal crash causes (Counting.cpp:31, 36; Handles.cpp:238; Memory.cpp:47-49) as free text | T-END1 |
| `runtime/Platform/Platform.h` | `lastError` (195), the `bool` + errno protocol of 22 functions | T-PL1 |
| `runtime/Platform/X86_64/Cpu.cpp` | the `runsSimdutf` string ladder and its second `__builtin_cpu_init` (28-44) | T-PL2 |
| `runtime/Platform/Posix/Files.cpp`, `Aarch64/Cpu.cpp`, `Posix/Memory.cpp` | the `#if defined(__APPLE__)` branches (Files.cpp:61-66; Cpu.cpp:19-32) and `#ifdef MAP_NORESERVE` (Memory.cpp:67-72) | T-PL4 |
| `runtime/Io/Io.h`, `Io/Handles.cpp` | `Kind` (53-63), the `Slot` union (72-85), `StreamOps` and `Stream` (137-191), `notOpen` and `rowOf` (Handles.cpp:121-154), the switches (Handles.cpp:89-110, 248-262), `ByteRead` (Io.h:129-135) | T-IO1 |
| `runtime/Io/FileTimes.cpp` | `field`, the six readers, `Kind::Times` | T-IO3 (lanes 03, 14) |
| `runtime/Io/Terminal.cpp` | `idris_rt_io_term_setup` (26-27) | T-IO4 (lane 03) |
| `runtime/Numerals/Numerals.h` | `Numeral::Kind` and the default-valued fields (17-30) | T-NU1 |
| `foreign/idr/lib/IR/Layout/CellInfo.cpp` | its own packing (16-49), for the shared `Info` view | T-ABI1 (lane 12 owns the file) |
| `foreign/idr/lib/IR/Ops.cpp`, `Conversion/Scalars.cpp` | the second and third Euclidean divisions (Ops.cpp:205-238; Scalars.cpp:59-82) | T-BG1 (lanes 03, 12) |

## 8. Risks, unknowns, measurements needed

**Risks.**
- **T-RC1 is an ABI change with a reader outside the runtime.** "Count 0
  is persistent" is written by the lowering's static data and read by
  0007's (unbuilt) detach table; a missed writer makes a static cell
  look unique and lets a take reuse read-only memory. The change is one
  constant in one place only if T-ABI1's shared header lands first.
- **T-RC2 and T-RC4 move a run-time test into a static fact.** If the
  lowering's component kind or the token's type is wrong once, the
  runtime dereferences NULL or frees a stack cell. The checked runtime
  (`Rc.h:23-34`) and the program verifier are the net; T-RC4 waits on
  the frame lifetime's soundness (lanes 01, 08).
- **T-AL3 changes snmalloc's commit path** (`pal_enforce_access`), which
  snmalloc ships behind its "check client" mitigations: performance and
  the meaning of its other mitigations must be measured, not assumed.
- **T-AL4 makes the harness's leak check run on a different archive
  from the shipped one** (the checked runtime), as runtime-checked
  already does; a leak that only the shipped build shows would go
  unseen.
- **A skipped guard today** (R-STK-1, R-STK-2) is a silent corruption,
  AGENTS.md's "never miscompile silently", reachable only by a frame
  past 1 MiB; no such frame is known (*conjecture*).
- **Reservations on strict hosts** (R-AL-4, R-STK-3): programs may not
  start under overcommit mode 2 or `ulimit -v` (*conjecture*, not run
  here).

**Unknowns.**
- The size of snmalloc's flat pagemap reservation on each target
  (`ds/pagemap.h:102-108` over `DefaultPal::address_bits`; *conjecture*
  ≈ 2^34 entries of two words with 48-bit addresses).
- Whether each target's kernel may map user addresses past the target
  entry's recorded width (39 on arm64 Linux 4K, `CMakeLists.txt:222`),
  which the dying list's asserts assume it does not (T-PL3).
- Whether libc++'s extensive mode, as the pinned libc++ configures it,
  traps or calls a handler in a unit with no C++ library (cxx-Q4,
  *recalled*).
- Whether `idris_rt_persist_held`'s callers could know the cell is
  static at lowering (R-RC-8, *conjecture*).

**Measurements needed** (no build exists here; each with what it
decides).
- Instructions and branches per inlined `dec` and `inc`, today's
  encoding against T-RC1's, on `tests/runtime-counting` and one bench
  (decides N1).
- The cost of the `thread_local` live-cell increment in the inlined
  allocation path, per target, macOS's TLV access above all (decides
  N2 / T-AL4).
- Code size and LLVM time of records-past-the-cell with T-RC5's
  slot-run entries, with and without `inlineCallerInstructions` (decides
  whether lanes 12/13 delete the budget).
- Program start under `ulimit -v` at 8, 16 and 64 GiB and under
  overcommit mode 2 on the three Linux targets (decides N3).
- `mprotect` cost per committed chunk with `pal_enforce_access` on the
  bench (gates T-AL3).
- The largest frame of the stage-1 frontend and of the bench programs
  (`-fstack-usage` or LLVM's `stack-size` section), against the 1 MiB
  guard (sizes oom-4's risk).

## 9. Sources read

**Documents, in full:** `.claude/skills/representation-first/SKILL.md`;
`AGENTS.md`; `proposals/0000-mlir-native.md` (§0-§9, every lane's
section; §5.10, §5.11, §5.5, §5.4 most carefully); `proposals/0003-facts-once.md`;
`audits/p0/README.md`; `audits/p0/08-counting.md` (head, for the
layout). In part: `PINS.md` (runtime-quarantine, runtime-cx16,
simdutf-dispatch, no-sanitizer-runtimes); `audits/bugs.md:1-70`;
`proposals/0007-shards.md:1-12, 240-270`; `proposals/0017-apple-dmp.md`
(status, the table rows on the heap and the stack, D9);
`audits/config.md` at 91615083^ (lines 110-130).

**The subsystem, line by line:** every file under `runtime/`:
`idris_rt.h`, `cpu_features.h`, `cpu_aarch64.h`, `cpu_x86_64.h`,
`link_check.c`, `check-archive.sh`, `CMakeLists.txt`; `Alloc/{Alloc.h,
Cells.cpp, Arrays.cpp, Gmp.cpp}`; `Rc/{Rc.h, Counting.cpp, Freeing.cpp}`;
`Start/{Start.h, Entry.cpp, Runner.cpp}`; `Platform/{Platform.h,
Address.h, CpuBits.h}`, `Platform/Posix/{Clocks, Directories, Faults,
Files, Memory, Process, Processors, Stacks, Terminal}.cpp`,
`Platform/Aarch64/Cpu.cpp`, `Platform/X86_64/Cpu.cpp`; `Io/{Io.h,
Buffer, Bytes, Clock, Directories, Ending, Errors, Files, FileTimes,
Handles, Input, Lines, Output, Process, Processors, Scratch,
Terminal}.cpp`; `Strings/{Strings.h, Concat, Making, Order, Replacement,
Scalars, Show, Simd}.cpp`; `Numerals/{Numerals.h, Machine.cpp,
Reading.cpp}`; `Big/{Big.h, Arithmetic, Bitwise, Compare, Conversions,
Digits, Operands, Words}.cpp`; `Doubles/{Doubles.h, Parsing, Printing,
Truncation}.cpp`.

**third_party/snmalloc (f126f1c9), where `runtime/Alloc` uses it:**
`src/snmalloc/mem/corealloc.h:15-65`; `global/globalalloc.h:330-366`
(signatures); `backend/globalconfig.h` (whole, against `HeapConfig`);
`pal/pal_posix.h:189-201, 325-365, 380-471` (error, reserve, entropy);
`ds/pagemap.h:60-275` (by search: errors, `required_size`, `init`);
`ds_core/sizeclassconfig.h:53-55`; `backend_helpers/defaultpagemapentry.h`
(by search).

**Compiler code read for the runtime's readers:**
`foreign/idr/include/idr/IR/IdrRuntime.td` (whole);
`foreign/idr/include/idr/IR/IdrBase.td:255-300`;
`foreign/idr/include/idr/IR/IdrPlatformOps.td:1-60`;
`foreign/idr/include/idr/IR/IdrScalarOps.td:1-90`;
`foreign/idr/include/idr/IR/Layout.h:30-130`;
`foreign/idr/lib/IR/Layout/CellInfo.cpp` (whole);
`foreign/idr/lib/IR/Fold/Scope.cpp:1-60`;
`foreign/idr/include/idr/Support/Stack.h:40-90`;
`foreign/idr/lib/Conversion/Counting.cpp` (whole);
`foreign/idr/lib/Conversion/RuntimeCells.cpp:80-105`;
`foreign/idr/lib/Conversion/Runtime.cpp:40-70, 180-230, 285-299`;
`foreign/idr/lib/Conversion/Cells.cpp:65-100`;
`foreign/idr/lib/Driver/LinkRuntime.cpp:100-142`;
`foreign/idr/include/idr/Driver/Runtime.h:40-60`;
`foreign/idr/include/idr/Target/Target.h:100-125`;
`CMakeLists.txt:85-160, 170-330` (the target entries, flags);
`build/typecheck/foreign/idr/include/idr/IR/idris_rt_ops.h` (generated,
stale); `tools/host.sh:121-150`; `harness/lib/run.sh:10-30`,
`harness/lib/differential.sh:120-170` (by search).

**History:** `git log --oneline -- runtime/` (80 commits); messages of
1445d894, 07aeb299, efe0ad36, e20b5b4a, 1c38fff5, da66bd95, a541ec9f,
3fec8a85, 0124edda, 0781ed93.

**Measurements (commands):** part sizes (§2.1); entry points: `for f in
$(find runtime -name '*.cpp'); do awk '/extern "C"/{s=$0; if ($0 !~ /\(/)
{getline; s=s" "$0}; if (match(s, /idris_rt_[a-z0-9_]+\(/)) print
substr(s, RSTART, RLENGTH-1)}' $f; done | sort -u | wc -l` (142; 71 with
`^idris_rt_io_`); idiom counts: `grep -cE` per pattern over
`find runtime \( -name '*.cpp' -o -name '*.h' \) ! -name 'cpu_*'`;
error channel: `grep -rn 'saveError()' runtime` (25), `grep -rn 'fail(E'
runtime` (5), `grep -cE '^bool [a-zA-Z]+\(' runtime/Platform/Platform.h`
(22); probes: `grep -rn 'probe-stack\|stack-probe' foreign compiler
CMakeLists.txt tools` (none); snmalloc override: `grep -rn
'snmalloc/override' runtime foreign/idr/CMakeLists.txt CMakeLists.txt`
(none); `grep -rn madvise runtime` (none); Euclidean division: `grep -rn
-i euclid foreign/idr/lib foreign/idr/include runtime`.
