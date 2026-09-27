# Next: runtime representations first, then a clean repository

Status: plan, for approval. Supersedes the order of work in
`refactor-and-memory.md` section 6 and its "runtime Integer: not planned".

## 1. The finding that reorders everything

`Integer`, built strings, recursive data and closures have no runtime
representation. So every one of them must be computed away at compile time,
and `Simplify` has had to be an interpreter as well as a specializer:

- the driver runs `fib 15`, `integerToNat 120` and `showLitChar 'x'` one
  unfolding at a time, with all the bookkeeping a residual call needs:
  configurations, the whistle over the path, frames, rollback;
- `Nat` is a chain of `S` constructors, and the whistle's embedding test
  was exponential on `S^120` (fixed today by a dynamic program; it was a
  hang);
- `printLn 'x'` takes 5.7 s to compile;
- the budget must bound both code size and evaluation time, which are
  different things;
- a program that shows a runtime `Integer`, or keeps a list whose length
  depends on input, is rejected (`PROF-TYPE-4`, `PROF-DATA-3`).

Give these four a runtime representation, and compile-time evaluation stops
being load-bearing. It becomes an optimization, and it can then be done
by running compiled code: jitting through our own pipeline.

## 2. Runtime representations (the priority)

`Rep` from `refactor-and-memory.md` 4.4 stays. What changes is that nothing
falls outside it:

| Value | `Rep` | Notes |
| --- | --- | --- |
| `Int`, `Bits*`, `Int*`, `Double`, `Char` | `Scalar` | as today |
| `Integer` | `Big`: an `i64` with a tag bit; a pointer to a heap bignum when it overflows | GHC's `IS`/`IP`, Lean's scalar `Nat`/`Int` with an mpz fallback |
| `Nat`-like (`ZERO`/`SUCC`) | same as `Integer`, non-negative | Idris's own `%builtin Natural`; unbounded, so no overflow rule |
| `String` | `Str`: pointer, length | immutable bytes on the heap; literals in `.rodata` |
| non-recursive data | `Sop` | as today (`LOW-DATA-1`) |
| recursive data | `Box`: pointer to a cell | `Nil`-like constructors are immediates |
| a closure that must exist at runtime | `Sop` over the lambda labels that reach it (defunctionalized), `Box` when the set is recursive | a finite set of known functions is already a `Choice` (ELIM-G-20) |
| `Lazy` that must exist at runtime | a closure plus a memo cell | same mechanism |
| arrays (`prim__newArray` …) | `Arr` | as in 4.6 |

### 2.1 Memory: researched in `memory-model.md`; direction chosen

The direction chosen is Lean's reference counting, refined for a
thread-per-core runtime (`memory-model.md` section 7, `concurrency.md`).
The text below is the brief that research answered.

The region plan (4.5) rejects any partial loop that carries new data
(`PROF-REG-1`). With general lists, strings, bignums and closures, that
covers every REPL that keeps state, so a region discipline cannot be the
whole story. What replaces or complements it is not decided here.

It is the subject of a dedicated research document,
`docs/research/memory-model.md`, written before any memory code. That
document is to answer:

- **The candidates, from their papers and their code:**
  - precise reference counting: Perceus and FBIP (Koka), Lean 4 ("Counting
    Immutable Beans": borrow inference, reset/reuse), Roc (Morphic alias
    analysis), Swift (OSSA and its ARC optimizer), Nim (ORC), Lobster
    (compile-time RC elision), Idris's own RefC backend;
  - regions: the MLKit (regions with a GC underneath), Cyclone, and GNAT's
    secondary stack;
  - static destruction: ASAP (Proust), Micro-Mitten and Mojo;
  - uniqueness and modes: Clean, Linear Haskell, Granule, "Linearity and
    uniqueness: an entente cordiale", fractional uniqueness, OCaml's modes
    ("Oxidizing OCaml"), FP² fully in-place programming, frame-limited
    reuse;
  - tracing and hybrids: MLton, OCaml 5, GHC, Immix, LXR
    (reference counting with a tracing backup);
  - for each, what it guarantees, what it costs per operation, what it
    rejects or leaks, and the numbers its authors report.
- **What Idris gives us that they lacked:**
  - whole-program monomorphic code;
  - quantities (1 is not uniqueness, but what is it worth for borrowing?);
  - erasure, totality, and `Data.Linear.Array`'s linear API;
  - no mutation outside `IORef`/`IOArray`.
- **Where cycles can come from:** `IORef`, `IOArray`, self-referential
  codata through `Inf` (`ones = 1 :: ones`), and memoized `Lazy`. Can each
  be ruled out, detected, or collected?
- **Threads.** Idris has `fork`: atomic counts, or thread-local heaps with
  sharing marked (as in Lean)? Or keep threads out of the profile?
- **How it lowers:**
  - through `Code Mem` and the `idr` dialect;
  - what LLVM can optimize (count operations as known calls, or as inline
    code);
  - how it interacts with the SOP unboxing of non-recursive data and with
    arrays updated in place.
- **Evidence before commitment.** For each serious candidate, a prototype of
  the decisive part, measured against Koka, Lean, OCaml, MLton and GHC on
  their standard allocation benchmarks (binary trees, `rbtree`, `deriv`,
  `nqueens`, `cfold`, a map over a long list), with peak memory as well as
  time.
- **The recommendation, and what it rejects.** Stated as rules for 02 and
  03, only after the above.

M1 does not start until that document is discussed and approved.

### 2.2 The runtime, and static linking

**Linking.** The approach is Go's: everything except the kernel is linked
statically. On Linux the kernel's syscall interface is the stable
boundary, so an executable has no dynamic dependencies at all: no
`ld.so`, no `libc.so`, no `libgmp.so`.

**The C library.** Three ways to get there:
1. **LLVM's libc (`llvm-project/libc`)**, built in full-build mode from the
   LLVM tree we already pin.
   - It adds no new dependency.
   - Its math functions aim to be correctly rounded, which makes
     `SEM-DBL` results exact and independent of the platform (today they
     are "what `libm` returns", `SEM-DEV-2`).
   - Its full build runs a header generator written in Python. LLVM's own
     build already needs Python, so ours still has none.
   - The risk is maturity: GMP must link against it. That is the first
     experiment.
2. **musl**, as a git submodule, built statically. It is mature, but it is
   another pin, and its `libm` is not correctly rounded.
3. **No libc**, with our own syscall layer as Go has. We would then have to
   write `memcpy`, allocation and `libm` ourselves, and GMP's few libc needs
   would have to be shimmed. It is not worth it while (1) or (2) works.

Recommendation: try (1); fall back to (2) if GMP or the math functions
do not link or pass.

**The runtime** is C, compiled with the pinned toolchain into one static
archive, `runtime/`. It contains:
- allocation and whatever the memory model needs (section 2.1);
- the crash and output paths that are LLVM-dialect helpers today
  (`Lower/Runtime.mlir.inc`, which then shrinks);
- bignums: GMP, as a git submodule under `third_party/gmp`, pinned like
  Idris and LLVM. It is built static with `--disable-shared`, its memory
  functions pointed at our allocator (`mp_set_memory_functions`), and
  linked into the archive. GMP is LGPL: static linking obliges us to let
  users relink, which shipping our object files satisfies. This is noted
  in `PINS.md` and the licence notes.

`TEST-HEAP-1` (only `write`, `read`, `_exit` and `libm`) becomes: the
executable is static, and its only external interface is Linux syscalls
(checked with `readelf`: no `INTERP` and no `DYNAMIC` section).

### 2.3 What changes in the compiler

- **`Types`/`Rep`.**
  - `Rep` is computed per monomorphic type.
  - `VTy` gains `BigT`, `BoxT DataId` and `ClosT`; `value` stops returning
    `Nothing` for them.
- **`Simplify`.**
  - `runtimeTy` stops failing.
  - `reify` builds the runtime value: a closure record, a string
    concatenation, a bignum literal.
  - The `PROF-HEAP`/`PROF-DATA-3`/`PROF-TYPE-4` paths become
    representation choices.
  - The driver's job shrinks to specialization for speed. It never has to
    succeed.
- **`Code Mem`.** The passes that make memory explicit, whatever section
  2.1 chooses: for reference counting, `Inc`/`Dec` and `Reset`/`Reuse` from
  liveness (Lean's `ExplicitRC` and `ResetReuse`, over our join-point IR);
  for regions, `Mark`/`Release`.
- **`idr` dialect.**
  - Ops: `idr.box`, `idr.unbox`, `idr.big.*`, `idr.str.*`,
    `idr.closure`/`apply`, and the memory model's own ops.
  - Lowering to `llvm` calls into the runtime.
  - The data layout stays in C++ (`LOW-DATA-1`).
- **Frontend.** Nothing changes. It already hands `Simplify` checked TT with
  quantities.

### 2.4 Milestones (replace M1–M4)

- **M1 (v4): heap and strings.**
  - The runtime.
  - `Box` for recursive data, and the memory model of section 2.1 on
    `Code Mem`.
  - Runtime strings, and `getLine`.
  - `words`/`lines`/`pack`/`unpack` through the Prelude, unchanged.
  - Reuse, if the model allows it.
- **M2 (v5): Integer and Nat.** Tagged small integers with bignum fallback.
  `SEM-BIG-1` (Integer only at compile time) is withdrawn.
- **M3 (v6): closures and Lazy at runtime.** Defunctionalized where the set
  of lambdas is known, `Box` where it is recursive.
- **M4 (v7): arrays.**
  - The three `prim__array*` externs, `Data.IOArray` and `Data.Linear.Array`.
  - In-place writes where the model proves them unique.
- **M5: frames and regions** as optimizations over proven escape.

The benchmark table must not regress at any step. Scalar code must pay
nothing for memory management, because `Rep` says it has no pointers.

## 3. Compile-time evaluation: one JIT path

**The rule: the server has no features of its own.** It is the compiler's
own pipeline and the program's own runtime, run at compile time:
- A computation can be evaluated at compile time only if the compiler can
  already compile it for runtime.
- The server has no primitive, representation or library that the
  executables lack.
- It never gets ahead of the compiler. `Integer` on the server arrives in
  the same step as `Integer` in executables (M2, GMP in the runtime), and
  not before.
- Anything the compiler cannot yet compile is not evaluated early: it
  stays in the residual program, or is rejected as it is today.

Goal: `Simplify` never evaluates a runtime computation itself. Anything
that computes a value from known inputs (a primitive, a closed call) runs
compiled code, the same code the program runs, in one server process. There
is then one semantics for each primitive, the runtime's:
- no Idris reimplementation of Idris primitives (`Simplify/Fold.idr`);
- no Chez `number->string` standing in for Ryu;
- no Chez bignums standing in for GMP;
- no budget of unfoldings standing in for fuel.

### 3.1 What goes, and what stays

**Goes.**
- `Simplify/Fold.idr`: `foldPrim`, `foldStr` and `foldBig`, the Idris copy
  of every primitive's semantics.
- Driving a call because all its arguments are known (what was
  ELIM-G-16), and the count of unfoldings in a row without code that
  bounds it today.
- `SEM-BIG-1`: `Integer` exists at runtime from M2.
- Compile-time `Nat` as a chain of `S`.

**Stays, because it is specialization and not evaluation.** These work on
open terms, and no amount of running code replaces them:
- beta (G1), known constructor (G2), specialization (G3), static let (G4),
  arity raising (G5), force of delay (G8);
- the driver's unfolding on static structure (G19);
- choices (G20);
- output fusion (G7);
- a string's static *structure*: `Append` trees of pieces, which are what
  make output fusion possible. Joining two literal pieces into one literal
  is data layout, like a linker's string pool; the plan treats it as such.
  If that is not accepted, it is `prim__strAppend` and goes to the server
  like any other primitive.

**Decisions that need a value now.** Static control needs values while
specializing: `if n == 0` with `n` a literal after unfolding decides which
alternative is taken. Those values come from the server too. So the server
must be fast for primitives, microseconds and not milliseconds.

### 3.2 The server

`idr-jit`, a C++ tool in `foreign/idr/tools`. The compiler starts it once
per compilation (Idris's `popen2`) and talks to it over a pipe.

- **At start.**
  - It creates an ORC `LLJIT`.
  - It loads the static runtime archive: the same GMP, libc and runtime
    objects the executable links, through a static-library definition
    generator.
  - It compiles a table of entry points, one per primitive. After that, a
    primitive request is a call and a copy: no code generation.
- **Values on the wire.** A compact encoding of `Rep` values: scalars, byte
  strings, GMP limbs, and constructor trees with a tag and fields. Functions
  and worlds are never on the wire: a closed call of function type is
  deferred anyway (G5), and one that takes the world is not closed.
- **Requests.**
  - `prim op args` calls the entry point.
  - `define module` takes the MLIR of closed specializations from `Emit`,
    runs `idr-lower` and LLVM at `-O1`, and adds them to the JIT.
  - `call f args` runs a defined function.

  Results are cached by configuration for the whole compilation.
- **Crashes and divergence are values, not failures.**
  - `call` runs in a `fork`ed child. The JIT's code pages are shared
    copy-on-write, so this costs about 100 µs.
  - A runtime crash (division by zero, an `idris_crash`), running out of
    fuel, or exceeding a memory cap comes back as `stuck`. The call is
    then residualized, so it crashes or runs at runtime exactly as
    written.
  - Primitives run in-process, and return `stuck` for a crash condition
    they check before acting (a zero divisor).
- **Deterministic fuel, not a wall-clock timeout.** A timeout would make
  the emitted program depend on the machine's speed, and break `FE-DET-1`.
  In JIT mode, `idr-lower` puts a fuel counter in each function's entry
  and on each loop back-edge (join points), and the runtime counts
  allocated bytes. Both limits are flags with fixed defaults, so the same
  input gives the same output everywhere.
- **Same code at compile time and at runtime.** Both use the same runtime
  archive and the same libc/libm, lowered by the same pipeline. The
  compile-time value is therefore the runtime value, which is the whole
  point.
- **Cross-compilation**, later: when the target is not the host, the
  server cannot run the target's code.
  - Idris's integer semantics are fixed-width, so they agree.
  - With a correctly rounded libm, doubles agree too.
  - What would still differ is the pointer width. Until cross-compilation
    exists, host is target.

### 3.3 When it lands

The server needs runtime representations for its results to mean anything:
- `Integer` results need GMP (M2);
- strings need runtime strings (M1);
- data needs `Box` for recursive data (M1).

So:
- **M1:** `idr-jit` with primitives, and closed calls with scalar, string
  and data results. `Fold.idr` loses everything but `Integer`.
- **M2:** `Integer` on GMP in the server. `Fold.idr` and `SEM-BIG-1` are
  deleted, and all compile-time evaluation goes through the server.

The unfolding budget in the driver then bounds code size only.

### 3.4 Costs and risks, stated plainly

- **Start-up.** About 50–100 ms per compilation, to initialize LLVM and
  MLIR and compile the primitive table. This could be cached on disk.
- **Per call.** Round trip for a primitive: about 10–30 µs over a pipe.
  A compilation folds thousands (every `fromInteger 3`), so this adds a
  fraction of a second.
- **Closed calls.** Code generation per defined module: about 5–50 ms.
- **Failure modes.** A bug in the server crashes one compilation, not the
  program, and it shows up as a compiler error, not a miscompile, because
  every request has a checked reply.
- **The compiler depends on a C++ process at compile time.** It already
  depends on `idr-opt` and LLVM for code generation. This makes that
  dependency interactive, not new.

## 4. The repository cleanup (one aggressive pass)

### 4.1 No Python

About 1 900 lines of our own Python, excluding vendored sources:

| File | Lines | Replacement |
| --- | --- | --- |
| `tools/dev.py` | 496 | `Makefile` plus `tools/bootstrap.sh` for the toolchain (gcc, cmake, ninja, LLVM, Idris), which must run before any Idris exists; this is how Idris 2 bootstraps itself. `make build`, `make test`, `make bench`. `compile` goes away: the built `idris-mlir` is the command. |
| `tests/run.py`, `harness.py`, `compiler/suite.py`, `e2e/suite.py`, `e2e/sem.py`, `profile/suite.py`, `native.py`, `mlir/check_pipeline.py` | ~1 000 | `tests/Main.idr` on Idris's own `Test.Golden` (`libs/test`), exactly as `third_party/Idris2/tests/Main.idr`: one pool per directory. |
| `tests/idr/lit.cfg.py`, `status.py` (lit) | | golden tests whose `run` is `idr-opt … \| FileCheck`; FileCheck is an LLVM binary, not Python |
| `tests/tooling/test_spec.py` (rule-to-test traceability) | | `tests/spec/Spec.idr`, a golden test that prints the untested rules |
| `tests/tooling/test_dev.py`, `test_toolchain.py` | | deleted; the Makefile has nothing to test |
| `tools/gen_ryu_tables.py` | | `tools/RyuTables.idr` (Integer arithmetic is native), run by `make` |
| `bench/run.py` | 162 | `bench/Main.idr`, or a 20-line shell script |

**Golden layout.** Each test is a directory holding `run`, `expected` and
its sources. `run` compiles the program, checks the exit status and prints
the artifacts that must exist; for FileCheck tests it pipes the dumps
through FileCheck. So "tests check exit status and artifacts, not just
stdout" (AGENTS.md) holds by construction: all of it is in `expected`.

The pools:

| Pool | Replaces |
| --- | --- |
| `compiler` | `CoreCheck` |
| `accept` / `reject` | `profile/*` |
| `e2e` | |
| `dialect` | `idr` lit |
| `pipeline` | `mlir` |
| `spec` | |
| `determinism` | |

`bootstrap-idris` also installs `libs/test`.

### 4.2 Directories and files to delete

- **`unsafe/` and `src/`.** Empty CMake placeholders from cpp-starter's zone
  layout (`TC-ZONE-2`). Delete them, and `add_subdirectory` goes with them.
  The C runtime of section 2.2 gets `runtime/`, named for what it is.
- **`lib/idris-mlir-io/`, our own IO package.**
  - Idris's Prelude IO already compiles (`prelude-io`, `prelude-input`).
  - The 72 tests that `import IdrisMLIR.IO` move to the Prelude.
  - `DRV-FLOW-2` stops passing `-p idris-mlir-io`.
- **`docs/cpp-profile.md` (1 700+ lines).** Cut it to the rules the 18 C++
  files actually follow; the rest is cpp-starter's general profile.
- **Marker files such as `tests/e2e/v2/double-print-fuzz/oracle-chez`**
  (empty; it tells the Python suite to compare with the Chez backend): the
  test's `run` compiles with `--cg chez` as well and diffs, in plain sight.
- **The research notes (`v2-entry`, `v3-entry`, `starting-point-and-tests`,
  `mlir-and-mojo`, `next-research-prompt`, …).** Fold what is still true
  into the architecture docs, and delete the rest; git keeps them.

### 4.3 The research library: kept, and organized

Everything vendored stays. Today it is split across overlapping trees:
- `docs/research/papers/`: 35 papers with an `INDEX.md`;
- `docs/research/sources/oa-papers/`: 32 more, several of them duplicates
  of the above;
- `docs/research/sources/{code,docs,pointers}/`: snapshots of Idris 2,
  MLIR, MLton, tinygrad, GHC, LLVM and the SSA book;
- three manifests and a `bibliography.bib`.

The new layout:

```
docs/research/
  notes/              our own research documents (this file, refactor-and-memory, memory-model, ...)
  library/
    README.md         what is here, where each item came from, licences (merges ACCESS, MANIFEST, oa-locations, handoff)
    bibliography.bib  one bibliography, every paper and snapshot keyed as <author>-<year>-<slug>
    papers/<key>/     one directory per paper (merged from papers/ and oa-papers/, deduplicated), with the PDF and extracted text
    code/<project>/   source snapshots, each with the upstream commit
    docs/<project>/   documentation snapshots
    INDEX.md          papers and snapshots by topic: memory, specialization and supercompilation, rewriting and e-graphs, MLIR, arrays and scheduling, verification, types and quantities
```

Research documents cite `library/papers/<key>`. The moves are `git mv`, so
history follows the files.

### 4.4 The compiler itself

Carried over from R5/R6, which were not done:
- **Split `Frontend/Translate.idr` (1 381 lines)** into Data, Instances,
  Terms and Trees.
- **`Facts`**: one algebra over the call graph for termination, effects and
  recursion.
- **`Rule.idr` and the rule IDs.** Collapse the ELIM-G-10..18 family into
  ELIM-G-19 (drive) and ELIM-G-20 (choice).

### 4.5 Docs

`docs/architecture` is 16 files and 3 500 lines. After the cleanup:
- one file per compiler boundary;
- rules that no test can check turn into prose;
- `15-roadmap.md` states this plan and nothing else.

## 5. Order

1. **Land the driver cutover** (R1–R4a): whistle, generalization, choices,
   join points; all suites green, benchmarks, docs 06/02/08.
2. **The memory-model research** (section 2.1), discussed with you before
   any memory code.
3. **Cleanup pass** (section 4): no Python, golden tests in Idris, the
   research library reorganized, dead directories deleted, `idris-mlir-io`
   dropped. It changes no compiler behaviour, so the suite before and after
   must agree test for test. It can run alongside step 2, since it touches
   no design.
4. **Static toolchain** (section 2.2): LLVM libc (or musl) and GMP as
   pinned submodules; executables fully static.
5. **M1** with the chosen memory model, and `idr-jit` for primitives and
   closed calls.
6. **M2** (`Integer` on GMP; the Idris-side evaluator deleted), **M3**
   (closures), **M4** (arrays), **M5** (frames and regions, if the model
   still wants them).
7. **C1–C4** (`concurrency.md`): tasks on one core with `epoll`; then
   thread-per-core with move-or-mark across cores; then parallel futures;
   then `io_uring`.

R4b (SOP returns for n-body over `Vect`) fits anywhere after step 1. It is
independent of memory.

## 6. Decided

- **Memory:** reference counting with borrowing and reuse, Lean's way,
  per-core heaps, move-or-mark across cores (`memory-model.md` section 7).
- **Concurrency:** thread-per-core with pinned IO tasks and stealable pure
  futures, built on Idris's own libraries (`concurrency.md`).
- **The JIT has no features of its own** (section 3).
- **Bignums:** GMP, vendored as a git submodule, linked statically.
- **Linking:** fully static on Linux; the kernel is the only interface.
- **Compile-time evaluation:** one path, `idr-jit`. The Idris-side
  evaluator of primitives and closed calls is deleted by M2.
- **The research library** is kept and reorganized, not deleted.

## 7. Open

- **Cycles through mutable cells, and the allocator**
  (`memory-model.md` section 6).
- **Placing work on cores, cooperative scheduling, stack reservation**
  (`concurrency.md` section 8).
- **LLVM libc or musl**, decided by the first experiment of step 4.
- **Joining two literal strings: data layout, or a primitive for the
  server** (section 3.1).
