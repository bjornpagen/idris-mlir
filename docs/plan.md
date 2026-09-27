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
   - borrowing and in-place reuse, guaranteed where quantities promise it
     (decision 10);
   - ownership as types and ops in the `idr` dialect, checked by its
     verifier after every pass;
   - a heap per core;
   - move-or-mark where values cross cores.

   A prototype must beat MLton before it is built.
4. **Concurrency is thread-per-core** (section 7). The execution algebras
   are Idris's own libraries: `fork`, `System.Concurrency` and
   `System.Future`.
5. **Everything but the operating system's interface is linked statically**
   (section 5), as Go does.
   - **Linux:** the interface is the kernel's syscalls, so executables are
     fully static on musl. musl, GMP, simdutf, fast_float and the
     allocator (snmalloc) are vendored as pinned git submodules.
   - The toolchain is LLVM alone: clang, lld, libc++ and compiler-rt from
     the pinned llvm-project, with no GCC. It is built on musl, together
     with LLVM/MLIR and our C++ tools (`idr-jit` included), so compile time
     and runtime share one libc.
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
9. **Everything is whole-program and full LTO, from day one** (section
   5.7).
   - A program, its runtime and every vendored library it links are
     optimized as one LLVM module.
   - Our C++ tools are built with LTO too.
   - Optimization is as aggressive as semantics allow, and never beyond:
     no fast-math, no FP contraction, and no assumption the types do not
     prove.
10. **Quantities are performance guarantees, not hints** (section 4.2).
    - A boxed value bound at quantity 1, matched, and rebuilt at the same
      size on that path is updated in place, with no runtime test. If the
      compiler cannot prove that, compilation fails with a named rule
      (`MEM-LIN-1`).
    - An index typed `Fin n` into an array whose type fixes its length at
      `n` is not bounds-checked. If the compiler cannot prove that,
      compilation fails (`ELIM-FIN-1`).
    - This is the stance of the heap-free rejections: we would rather not
      compile a program than silently miss what its types promise.
    - It is what Lean cannot offer (README), and the reason this compiler
      exists. Lean's passes remain the best effort everywhere else.

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
- **Strings are UTF-8, and their operations count scalar values.**
  - Upstream Idris is UTF-8 at every boundary: source files, IO and C
    strings. We store UTF-8 only, with no UTF-16 or UTF-32 anywhere.
  - Idris's own typechecker defines what the string primitives mean: it
    reduces `strLength s` to `length s` over its own strings, which count
    characters (`src/Core/Primitives.idr`). The Chez backend agrees
    (`string-length`).
  - So `strLength` counts scalars and `strIndex` indexes by scalar
    (`SEM-STR-1`). A runtime length must equal the length a proof computed
    in a type.
  - Two upstream backends deviate: RefC counts bytes
    (`stringLength` is `strlen`, and its `Char` is a byte) and JavaScript
    counts UTF-16 code units. Those are their bugs, not the semantics.
  - The layout trades scalar indexing against UTF-8 output
    (`SEM-IO-2`):

  | Layout | Output | `strLength` | `strIndex` | Memory |
  | --- | --- | --- | --- | --- |
  | UTF-32 | transcode | O(1) | O(1) | 4 bytes per scalar |
  | UTF-8 alone | as is | O(n) | O(n); the Prelude's `unpack` loops over `strIndex`, so O(n²) | 1–4 bytes |
  | **UTF-8, scalar count, ASCII flag** (chosen) | as is | O(1) | O(1) when ASCII; otherwise through breadcrumbs, a byte offset every 64 scalars built on first index (Swift's scheme, *literature*) | 1–4 bytes, +1/16 for indexed non-ASCII strings |

- **simdutf does the byte work**: a git submodule, dual Apache 2.0/MIT.
  - It is built with `SIMDUTF_NO_LIBCXX`, so the static runtime needs no
    C++ standard library, and called through its C++ API from the runtime,
    which is C++ (section 5.4).
  - It selects AVX2, AVX-512 or NEON at first use. With a fixed target CPU
    (section 5.7), the kernels that CPU cannot run are compiled out
    (`SIMDUTF_IMPLEMENTATION_*` set to 0). Whether the dispatch then
    disappears, so that LTO can inline the remaining kernel, is checked in
    milestone 3.
  - It provides:
    - validation of every byte sequence that becomes a `String`
      (`getLine`, files, sockets): invalid sequences become U+FFFD, since a
      `String` holds only scalar values;
    - `count_utf8` for the scalar count;
    - `validate_ascii` for the ASCII flag;
    - UTF-8↔UTF-32 conversion for `fastPack`, `fastUnpack` and building
      breadcrumbs.
  - Its build without a C++ standard library is marked experimental
    upstream, so the pin is to a release, and our string tests exercise
    every function we call.
- **fast_float parses numbers**: `cast` from `String` to `Double`, and to
  the fixed-width integer types. It is a git submodule and header-only C++,
  under MIT, Apache 2.0 or BSL.
  - Its algorithm (Lemire) is the one behind GCC's `from_chars` since
    GCC 12 and in LLVM's libraries (README).
  - We call `fast_float::from_chars` and test its result the C++26 way:
    `if (auto r = fast_float::from_chars(first, last, x))`, through the
    result's `explicit operator bool` (P2497, `float_common.h`).
- **Which strings are numbers is ours to define.**
  - Idris defines the frame: the whole string is read, and a string that is
    not a number casts to 0. Its support code does this (`cast-num` in
    `support/chez/support.ss`).
  - Which strings are numbers, Idris leaves to the host. Its typechecker
    reduces `cast` on a literal through the host's own `cast`
    (`castDouble` in `src/Core/Primitives.idr`). So we define the grammar,
    as decision 7 allows, and write it into 03:
    - the whole string must be fast_float's `general` format: an optional
      sign (with `allow_leading_plus`), digits with an optional point and
      an optional exponent (`.5` and `5.` included), or `inf`, `infinity`
      or `nan` in any case;
    - the value is correctly rounded to nearest-even. An exponent out of
      range gives ±infinity or ±0, the value fast_float stores alongside
      its range error;
    - anything else is 0, including surrounding spaces, `1d3`, `1/2`,
      `0x10` and `1_000`.
  - What fast_float accepts was checked on a corpus of such strings.
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

Two layers: guarantees where the types promise something (decision 10),
and Lean's passes as the best effort everywhere else.

**Quantities are guarantees.** In Lean, reuse happens when a runtime test
finds a cell unshared. One more reference anywhere, and an in-place update
silently becomes a copy: a performance cliff nothing in the program shows.
Idris states linearity in its types, and this compiler sees the whole
program, so it can prove the property and promise it.

- **`MEM-LIN-1`: guaranteed in-place reuse.**
  - **The condition.** A function binds a value of a `Box` type at
    quantity 1 and matches it against a constructor. On that path, after
    the value's last use, it builds a constructor whose cell has the same
    size.
  - **The promise.** The new value is written into the old cell:
    - no allocation and no free;
    - no count is tested or changed;
    - fields that do not change are not stored again.
  - **Why it can be proved.** It takes two halves: linearity constrains
    the future, uniqueness the past (Marshall, Vollmer and Orchard,
    "Linearity and uniqueness: an entente cordiale", ESOP 2022, in the
    library).
    - **Linearity (the callee).** Idris's checker proves that the function
      uses the value exactly once, so it cannot duplicate it.
    - **Uniqueness (the callers).** Idris lets a shared value be passed to
      a quantity-1 parameter. With `f : (1 x : T) -> T`, the definition
      `g y = (f y, y)` typechecks on the pinned Idris (checked). So a linear
      binder alone does not imply a unique cell (AGENTS.md).
    - The whole-program analysis supplies this half. It proves that every
      call passes a value with count 1: one built there, a quantity-1
      binder itself, or a variable whose other uses are all dead at the
      call. A value read out of a shared structure never qualifies.
    - Brady makes the same two-part argument for linear arrays (ECOOP
      2021, section 5): linear use, plus a construction that only a linear
      continuation receives.
    - **Koka's `fip` stops at the callee half.** Koka's fully in-place
      functions (FP², ICFP 2023, in the library) check the function body
      statically. For calls, the authors write that "deciding which calls
      to fip functions can be safely executed using destructive updates
      requires further information about how arguments are shared at call
      sites". Koka decides that at runtime, and falls back to allocating
      when an argument is shared.
    - We decide the caller half statically, as Clean's uniqueness types
      do. The paper names the cost, and it is ours too: a function wanted
      both in place and on shared data must exist twice. Compiling a
      copying version automatically would bring back the silent cliff, so
      the compiler does not.
  - **Otherwise, rejection.** When either half fails, compilation fails
    with `MEM-LIN-1`. The error names the binder, the call that may pass a
    shared value, and the reason:
    - the value is used again after the call;
    - it was read from a shared field;
    - it went through `assert_linear` or `believe_me` (`%unsafe` in
      `Builtin.idr`).
  - **Where it applies.** Quantity 1 is rare in the stock libraries: 27
    binders in the Prelude and 38 in base, mostly worlds, which are not
    boxed (*code*). So a program asks for the guarantee by writing `1`,
    and the libraries rarely trigger it by accident. The census of section
    12.2 checks the rest.
- **`ELIM-FIN-1`: guaranteed bounds-check elision.**
  - **The condition.** An array access whose index has type `Fin n`, into
    an array whose type is indexed by the same `n`, where the whole program
    establishes the invariant: every construction of that array type
    allocates exactly `n` elements.
  - **The promise.** No bounds test is emitted. This is not "LLVM may drop
    it given a range".
  - **Otherwise, rejection** with `ELIM-FIN-1`, naming the access and the
    construction that breaks the invariant.
  - **Scope.** The stock arrays (`IOArray`, `Data.Linear.Array`) index by
    `Int` and check in the library, so the guarantee applies where a
    program's own types tie an index to a length. Erased does not mean
    constant: `n` is erased at runtime and known only as the relation the
    types state. Indexing a `Vect` by `Fin n` needs no check to begin
    with: it is a walk that the types make total.
- **Soundness.** No memory safety rests on an unproved quantity.
  - A guaranteed reuse happens only with both halves proved, and a failed
    proof rejects the program.
  - Everywhere else, liveness decides every count.
- **Checked on the output.** The tests of each rule inspect the emitted
  code: no allocation, no count operation and no bounds test at the
  guaranteed sites, and a rejection where the proof fails.

**Ownership lives in the `idr` dialect, and its verifier checks it.** The
guarantees above must be checked by the IR, not trusted from the frontend.
That is what MLIR offers over emitting C, as Lean and Koka do.
- **What exists elsewhere** (*code* unless marked):
  - **Lean** inserts its counts into λRC and compiles that to C. Its IR
    checker (`src/Lean/Compiler/IR/Checker.lean`) checks only that `inc`,
    `dec`, `reset` and `reuse` name bound variables of object type.
    Nothing checks that counts balance, that a value is consumed once, or
    that a reuse fits.
  - **"Lambda the Ultimate SSA"** (Bhat and Grosser, CGO 2022, in the
    library) put Lean into MLIR as the `lp` dialect:
    - one erased type, `!lp.t`, for every boxed value;
    - `lp.inc` and `lp.dec` as ops;
    - reset and reuse commented out of the paper;
    - no ownership in the types and no verifier for it.
  - **Mojo** puts ownership in its language: argument conventions `read`,
    `mut` (with argument exclusivity enforced), `var` with the `^`
    transfer sigil, `out` and `deinit`, and compiler-created *origins* for
    references (`Mojo/docs/site/manual/values/ownership.mdx` and
    `lifetimes.mdx` in `modular/modular` at `ce67c4b`).
    - A `var` parameter silently copies when the caller omits `^`, unless
      the type is not `Copyable`, in which case the copy is a compile
      error. That is the pattern of our guarantee: a hidden copy becomes a
      compile error.
    - That Mojo's checker runs on its own MLIR dialects is Modular's
      public account, not verified here. The lesson stands either way:
      ownership belongs in the IR, not bolted on after lowering.
  - **MLIR itself** has no linear or affine values. SSA values may be used
    any number of times, and generic passes duplicate, merge and delete
    uses freely.
    - The closest mechanisms are these (`docs/` in the pinned tree):
      - the builtin `token` type, which may not be forwarded
        (`LangRef.md`, "Token Type");
      - the transform dialect's consumed handles, checked by
        `transform-dialect-check-uses`;
      - ownership-based buffer deallocation, whose ownership is a
        runtime `i1` per buffer.
    - None of them is a static, verified ownership discipline for values.
- **Quantities become ownership modes in the types.** Quantity 0 is already
  `!idr.erased`. A boxed value's type records how it is held:

  | Mode | Meaning | From |
  | --- | --- | --- |
  | `unique` | holds the only reference: count 1, not shared | quantity 1, where `MEM-LIN-1` proved it; `idr.con`; `idr.reuse` |
  | `owned` | holds one count; may be shared | quantity ω |
  | `borrowed` | holds no count; valid while its owner lives | borrow inference |

  Because the mode is part of the type, uniqueness at a call is ordinary
  type matching. `func.call` already rejects an operand whose type
  differs from the callee's parameter ("operand type mismatch",
  `FuncOps.cpp`). The whole-program property is thereby checked one call
  at a time.
- **Counting operations are ops:**
  - `idr.dup` takes an owned or borrowed value to an owned one. A unique
    value cannot be duplicated; `idr.share` gives up uniqueness first,
    explicitly.
  - `idr.drop` consumes an owned or unique value.
  - `idr.borrow` lends a value for a scope.
  - `idr.reset` takes a unique cell to a reuse token `!idr.cell<N>` of its
    size, with no runtime test.
  - `idr.reset.dyn` is the best-effort form: it tests the count at
    runtime, as Lean's reset does.
  - `idr.reuse` builds a constructor into a token of exactly its size.
  - Allocation (`idr.box`) carries a `MemAlloc` effect, so CSE never merges
    two cells.
- **The verifier enforces the rules** (`IDR-OWN-*`, written into 08 in M1):
  - **Consumed once.** A unique or owned value is consumed exactly once on
    every path: dropped, reset, passed to an owned or unique parameter,
    returned, or stored into a field. This extends today's check that a
    world is used at most once on each path (`IDR-WORLD-1`). Leaks and
    double frees become verifier errors.
  - **Borrows end in time.** No use of a borrowed value may follow, on any
    path, the consumption of its owner.
  - **Uniqueness has a source.** A unique value comes only from `idr.con`,
    `idr.reuse`, a unique parameter or block argument, or a quantity-1
    field of a consumed unique cell. Storing into a quantity-1 field needs
    a unique value. Nothing turns a shared value into a unique one
    statically.
  - **Tokens fit.** `idr.reuse` takes a token of exactly its constructor's
    size, so a guaranteed reuse cannot allocate.
  - **Quantities hold.** A quantity-1 parameter (`idr.quantity`) is used
    exactly once. Idris checked this on TT; the verifier checks it again
    after every transformation.
- **Checked after every pass.** Function-level rules hook into the
  dialect's attribute verifiers (`verifyOperationAttribute` on functions
  that carry `idr.name`, and `verifyRegionArgAttribute` for
  `idr.quantity`). MLIR's `PassManager` runs the verifier after every pass
  by default (`verifyPasses(true)`, `lib/Pass/Pass.cpp`). So every
  transformation, ours and MLIR's (inlining, SCCP, canonicalization, CSE),
  is checked, not just the frontend's output.
  - A generic pass that breaks a rule is a compiler bug, and fails as an
    internal error with the rule. An example is canonicalization turning an
    `scf.if` over owned values into an `arith.select`, which consumes both.
  - A user program that cannot satisfy a guarantee is a `MEM-LIN-1`
    rejection at its source location, before any pass runs.
- **Where the work happens:**
  - **Idris** supplies what only it knows:
    - quantities on parameters, block arguments and constructor fields;
    - the uniqueness inference behind `MEM-LIN-1`, which becomes `unique`
      in the emitted types, or a rejection.
  - **C++ passes** over the dialect do the operational work: Lean's passes
    below, on MLIR's `Liveness`, `CallGraph` and dataflow framework, after
    the generic value-level passes.
  - **The verifier** checks the result of both.
- **The contract changes.** Today `idr` is heap-free and every value is
  plain SSA (`IDR-TY-*`). M1 adds the modes, the ops and `IDR-OWN-*` to
  08. The rejection `MEM-LIN-1` joins the user-facing rules of 02.

**Lean's passes, the best effort.** Lean's impure pipeline (its `LCNF`
passes, which are A-normal form with join points like ours), as C++ passes
over the `idr` dialect, in Lean's order:

1. **Counting follows `Rep`.** Only `Box`, `Str`, `Big` above the small
   range, `Arr`, and escaped closures carry a count. Scalars and SOP
   values never do, so today's benchmarks pay nothing.
2. **`insertResetReuse`.** A cell that dies before a same-size constructor
   is built is reused for it (Beans' `R`/`D`/`S`, with join points).
   Where `MEM-LIN-1` holds, the reuse carries no runtime test; elsewhere
   it tests the count, as in Lean.
3. **`inferBorrow`.** Parameters are owned or borrowed, by a dataflow over
   the call graph.
   - Ownership is forced for: reset targets, values stored into
     constructors, and tail-call arguments, so no `dec` ever follows a
     tail call.
   - QTT seeds it: a quantity-1 parameter is owned, and proved unique
     where `MEM-LIN-1` applies; a quantity-0 one is never counted.
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
- **A heap per core**: snmalloc's allocator for the core's thread (section
  5.6). It has size classes and free lists with no locks.
  - A remote free is batched by the freeing core with plain stores.
  - A batch goes to the owning core as one message, with one atomic
    operation.
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
   - The allocator is already chosen, from `foreign/idr/bench/alloc` (section 5.6).
     These programs measure the whole runtime on it.

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
| C++ on top | libc++ supports it (`LIBCXX_HAS_MUSL_LIBC` in `libcxx/CMakeLists.txt`), and LLVM builds on it | not the deciding row |
| DNS when static | works (reads `/etc/resolv.conf`; no NSS) | no `getaddrinfo` |
| Math (double) | `exp`, `log`, `pow`: ARM's optimized routines, the code glibc uses; `sin`, `cos`, `tan`, `asin`, `acos`, `atan`: FreeBSD's msun, not correctly rounded | correctly rounded in every rounding mode for `exp`, `log`, `sin`, `cos`, `tan`, `asin`, `acos`; `pow` and `atan` within 1 ULP (`docs/headers/math/index.rst`) |
| Licence | MIT | Apache 2.0 with LLVM exception |

The first two rows decide it:
- LLVM's libc lacks functions the runtime needs, and its own docs advise
  against a full build.
- The JIT server must run the program's own runtime on the program's own
  libc (section 6), so its process (LLVM, MLIR, our C++) must be built on
  that libc, and on musl the whole toolchain can be.

**Math is not a criterion.** The results of the math functions are
implementation-defined (decision 7). musl's are deterministic across x86-64
machines (plain C on SSE), which is all the JIT needs: compile time and
runtime run the same code.

**What musl costs:**
- **`memcpy` is a simple `rep movsq`**, slower than glibc's vector copies
  on large blocks. Our generated code copies little, and a measured
  problem would be met by a better `memcpy` in the runtime.
- **Its `malloc` (mallocng) is slow.** The runtime allocates through
  snmalloc (section 5.6), so musl's `malloc` serves only musl and C
  libraries, unless snmalloc replaces it too (section 12.2).

**The toolchain becomes LLVM on musl, and GCC goes.**
- **Why GCC existed:** GCC was pinned only because cpp-starter's profile
  uses C++26 reflection, which GCC 16 has. Our C++ (about 1 700 lines in
  `foreign/idr`) uses no reflection, contracts or `import std`. Only the
  `-freflection` flag in `CMakeLists.txt` remains.
- **The pinned clang's reflection is a stub.**
  - It has the `-freflection` option
    (`clang/include/clang/Options/Options.td`).
  - `^^` parses only for builtin types:
    `clang/lib/Parse/ParseReflect.cpp` is 52 lines, with a TODO for the
    rest.
  - There are no splices, and libc++ has no `<meta>`.
  - So there is nothing yet to turn on. We turn `-freflection` on again
    when a pin of llvm-project implements P2996. Until then the C++ uses
    concepts and templates. Each op's lowering facts (helper, crash cause,
    minimum version) are declared once, and the passes derive the rest
    from them.
- **The bootstrap, in two stages**, as LLVM's own bootstrap builds do:
  1. The host's C++ compiler builds a stage-1 `clang` and `lld`, and
     nothing else. Today it builds GCC.
  2. Stage 1 builds musl, then the LLVM runtimes for
     `x86_64-linux-musl`:
     - compiler-rt's builtins, replacing libgcc;
     - libunwind;
     - libc++abi;
     - libc++, with `LIBCXX_HAS_MUSL_LIBC`.
  3. Stage 1 builds the stage-2 LLVM/MLIR, `clang`, `lld` and
     `clang-tidy`: static, on musl and libc++, with LTO (section 5.7).
  4. Stage 2 builds our C++ tools and the runtime.
- **What goes:** `bootstrap-gcc` and `.toolchain/gcc`, with libstdc++,
  libgcc and GCC's own LTO. The final link of every executable moves from
  the pinned `gcc` to `lld`.
- **What comes back:** clang and `clang-tidy` are built at last, which
  retires `PINS.md` `lint-graph-unbuilt`. The lint graph then enforces
  the rules that GCC's warnings stand in for today.
- **The Idris compiler** still runs on Chez: it is a host program and never
  links into an executable. Its C support library is compiled with our
  stage-2 `clang`.
- **The cpp-starter profile changes:**
  - clang instead of GCC;
  - libc++ instead of libstdc++;
  - no `-freflection`.

  `docs/architecture/11-toolchain.md` and `PINS.md` record it in
  milestone 3. Pins that exist only for GCC are retired with it; the
  `no-stdexec` entry cites `gcc-gmf-stdexec-ice`.
- **Cost:**
  - A two-stage LLVM build that includes clang, on a machine where
    building clang once did not fit "in reasonable time" (`PINS.md`,
    4 cores and 15 GB).
  - Milestone 3 measures the time and the peak memory, and states them.

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

The runtime is C++ in `runtime/`, compiled by our stage-2 clang for musl.
- It is a restricted C++: no exceptions, no RTTI, and no C++ standard
  library at link time (`-nostdlib++`). Headers come from the pinned
  llvm-project's libc++, for their templates only.
- A link check fails the build if any C++ runtime symbol is referenced.
- It is built as fat objects (`-ffat-lto-objects`): each object carries
  LLVM bitcode, which joins every program's LTO module (section 5.7), and
  native code, which links into `idr-jit`.
- Our tools link libc++; the runtime links no C++ library. It is the one
  place with that rule, because every program links it.

It contains:
- the allocator and counts (section 4.3);
- bignums over GMP;
- strings (section 3), with simdutf, and number parsing, with fast_float;
- the scheduler, stacks, `epoll`, timers and the blocking pool (section 7);
- the crash, output and number-printing paths that are LLVM-dialect
  helpers today (`Lower/Runtime.mlir.inc`, which shrinks accordingly).

The allocator underneath is vendored, not written (section 5.6).

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
| Toolchain | LLVM/MLIR, `clang`, `lld` and libc++, static on musl | LLVM/MLIR, `clang` and libc++ on `libSystem`, with Apple's SDK and linker; the same LTO pipeline (section 5.7) |
| Bignums | GMP, static | GMP, static |
| Allocator | snmalloc, in the LTO module | snmalloc, in the LTO module |

- **The one-libc rule still holds on macOS:** `idr-jit` and the executables
  both use `libSystem`.
- **What macOS loses:** hard pinning of threads to cores, and `io_uring`.
  Thread-per-core becomes one scheduler per CPU that the OS may move.

### 5.6 The allocator: vendored snmalloc

We vendor an allocator; we do not write one. snmalloc is chosen, from
measurements of our own allocation shapes (`foreign/idr/bench/alloc`).

**What section 4.3 asks of the allocator:**
- a fast path with no atomics, for sizes known at compile time;
- remote frees that take no lock and do not slow the owner.
  - After move-or-mark, a moved structure's nodes still belong to the
    sender's heap, so the receiver frees each of them remotely.
  - A future's result is built on the worker and dropped on the core that
    awaits it.
  - A shared object is freed by whichever core drops the last count.
- source that joins the program's LTO module (section 5.7), with no C++
  library at link time;
- Linux now, macOS later;
- control over when memory goes back to the kernel;
- safety in the JIT server, which is single-threaded and forks per call;
- a way to run on our segmented stacks (below).

**The candidates** (clones read for this plan, *code* unless marked):

| | snmalloc 0.7.5 | mimalloc 3.5.3 | rpmalloc | jemalloc | tcmalloc |
| --- | --- | --- | --- | --- | --- |
| Language, size | C++ header-only, ~22k lines | C, ~26k | C, ~4.4k | C, ~61k | C++, ~59k, plus abseil |
| Licence | MIT | MIT | Unlicense or MIT | BSD-2 | Apache 2.0 |
| Remote free | batched by the freeing core with plain stores, per slab and per owner; one atomic operation sends a batch; the owner splices each slab's batch in constant time | one atomic push per block onto the page's list; the owner later walks the list block by block (`src/page.c`) | an atomic push onto the page's deferred list | into the freeing thread's cache, then back to the owning bin under the bin's lock (`bin.c`) | per-CPU caches through `rseq` (Linux only) |
| Size known at compile time | `snmalloc::alloc<S>()`, a template on the size | `mi_malloc_small`, `mi_free_csize` | none | `sdallocx` | sized free |
| Configuration | compile time only (`Config`, `mitigations`); reads no environment variables | options and `MIMALLOC_*` variables | build options | options and `MALLOC_CONF` | flags |
| Returning memory | `MADV_FREE` | purges after a delay (1 s by default) | configurable | decay-based purging | background release |
| macOS | yes | yes | yes | yes | Linux first |
| Functional runtimes using it | none found | Lean, Koka | none found | none found | none found |

**The measurement** (`foreign/idr/bench/alloc/README.md`: 4 cores, medians of 5, in
seconds):

| workload | mimalloc | mimalloc tuned | snmalloc |
| --- | ---: | ---: | ---: |
| binarytrees, one core | **4.76** | 7.85 | 5.82 |
| six sizes, random lifetimes, one core | **3.58** | 3.90 | 4.25 |
| thread per core, nothing crosses | **1.16** | 1.25 | 1.30 |
| thread per core, 1 in 20 trees crosses | 0.51 | 0.47 | **0.46** |
| thread per core, 1 in 2 crosses | 1.88 | 1.08 | **0.92** |
| pipeline, every free remote | 1.78 | 1.09 | **0.63** |
| pipeline of small trees | 1.36 | 1.16 | **0.27** |
| futures: fan-out, fan-in | 4.80 | 4.86 | **3.13** |

- mimalloc is 12–22% faster on work that stays on one core.
- snmalloc is 1.5–5× faster on work that crosses cores, and its lead grows
  with the share that crosses.
- Peak memory is within a few MiB between the two.
- mimalloc's two most helpful options narrow the cross-core gap, but cost
  65% on binarytrees.

**Why snmalloc: this compiler's residue is the cross-core case.**
- **The compiler removes local allocation.** Reuse, borrowing,
  specialization, unboxing and static data remove most allocate-free pairs
  that stay on one core. In Lean, reuse alone is worth up to 3.2×
  (Appendix A).
- **It cannot remove traffic between cores.**
  - A future's result is built on the worker and dropped where it is
    awaited.
  - A moved message is freed by its receiver.
  - Reuse cannot help either case: the receiver's free returns memory that
    the sender's heap owns.
- **So what the compiler leaves behind crosses cores.** The better the
  compiler, the larger the share of the remaining allocator time that
  crosses cores. Thread-per-core with parallel futures (section 7) is the
  limit case of Amdahl's law, where snmalloc is several times faster.
  mimalloc's 12–22% lead is on the traffic the compiler shrinks.
- **Precedent.** Seastar, the thread-per-core reference, pays one atomic
  per cross-core free onto a single list per CPU (`free_cross_cpu` in
  `src/core/memory.cc`, *code*). It assumes crossings are rare. Futures
  make them structural here.

**It fits whole-program compilation.**
- `snmalloc::alloc<S>()` fixes the size class at compile time.
  - The runtime exports one allocate and one free entry per size class.
  - After LTO (section 5.7), the allocation fast path inlines into
    generated code as six instructions: a TLS load, a pop and a prefetch
    (disassembled, GCC 13).
  - The free path is a pagemap lookup, an owner comparison and a push onto
    the slab's list.
- All configuration is compile time, so behaviour does not depend on the
  environment.
- **Size classes step by 8 bytes.** snmalloc's default step at the bottom
  is 16 bytes, which rounds 24 to 32. Our cells are an 8-byte header plus
  8-byte fields, so a cons cell of 24 bytes would waste a third.
  `SNMALLOC_MIN_ALLOC_STEP_SIZE=8` gives exact classes of 16, 24, 32, 40,
  48 and 56. It showed no clear cost on `foreign/idr/bench/alloc` (three runs each; the
  fan-out test varies by ±20% run to run on this machine).

**What it costs, and the risks:**
- **No functional runtime uses it.** Lean and Koka use mimalloc. Our shapes
  are measured, not borrowed, and the memory gate (section 4.4) measures
  them again inside the real runtime.
- **Its CI has no musl job.** It runs on glibc Linux, macOS and FreeBSD,
  among others (`.github/workflows/main.yml`). Milestone 3 runs its test
  suite on our musl build.
- **When remote frees are processed.**
  - The owner processes remote batches when it refills a free list
    (`handle_message_queue` on the allocation slow path), so a core that
    stops allocating holds memory others freed for it.
  - The freeing core holds up to 16 KiB of unsent frees (`REMOTE_CACHE`).
  - The scheduler therefore flushes at the end of a turn and when idle.
    `flush` and `cleanup_unused` exist in `global/`; the exact hook is
    settled in milestone 3.
- **Project health, from the clones:**

  | | snmalloc | mimalloc |
  | --- | --- | --- |
  | Commits since 2019 | 1 495 | 4 552 |
  | Author names in the log | 61 | 126 |
  | Top authors | three at Microsoft Research Cambridge (Parkinson, Chisnall, Filardo) | one author, about 94% of commits |
  | Commits in the last year | 68 | 1 457 |
  | Current line | 0.7.x | v3, 20 months old; 3.5.3, eleven days ago, fixed a "critical bug" |

  snmalloc changes less and has more maintainers; mimalloc has more users.

**The rest were not chosen:**
- **mimalloc** is faster on one core, but loses where this compiler's
  residue is (above).
- **rpmalloc** is small and fast, but no functional runtime uses it, and it
  has no API for sizes known at compile time.
- **jemalloc** returns remote frees through bins that take a lock.
- **tcmalloc** needs abseil and libstdc++, and its per-CPU caches rely on
  Linux's `rseq`.

**What our design adds around it:**
- **Stacks.** Allocation runs on a task's segment (section 7.3). Switching
  to the system stack on every allocation would cost too much, so each
  segment keeps a reserve above the prologue's limit for the allocator's
  deepest path: a slab refill, remote batches, or a chunk from the OS.
  - The reserve is measured with clang's `-fstack-usage` and checked in CI.
  - Only allocation, freeing and the count helpers may use the reserve
    without a check (Go's `nosplit` functions and their guard).
  - Every other C call switches stacks.
- **A heap per thread is a heap per core.** Each scheduler is one pinned
  thread, and all tasks on a core share its allocator, as section 4.3
  wants.
  - A stolen future allocates from the thief core's heap.
  - Threads in the blocking pool get their own. They allocate rarely.
- **Freeing stays ours.** The iterative to-do list runs through object
  headers, as in Lean, and snmalloc sees only the final free. Persistent
  static objects (count 0) never reach it.
- **Hardening only in the debug runtime.** Release builds use snmalloc's
  default of no mitigations (`mitigations.h`). The debug runtime used by
  the test suites defines `SNMALLOC_CHECK_CLIENT`, which checks free-list
  integrity and invalid and double frees. Those are what a counting bug in
  the passes of section 4.2 looks like.
- **GMP** allocates through it (`mp_set_memory_functions`).
- **The JIT.** The server is single-threaded, so a forked child inherits a
  consistent heap. `SNMALLOC_PTHREAD_FORK_PROTECTION` stays off. The child
  exits with `_exit` and frees nothing.
- **An idea for the gate, not yet measured:** send a dead root home.
  - When the last count of a structure owned by another core drops, the
    runtime sends the root to its owner, which drops the whole structure
    locally.
  - That is one message per structure instead of one free per node, and it
    works on top of snmalloc.
  - A benchmark for it was written but not run.

### 5.7 Whole-program LTO, and optimizing as hard as semantics allow

**Where we are.**
- A program is already one module. `idris-mlir-cc` lowers it in-process
  and runs LLVM's O2 pipeline for the CPU `generic`
  (`foreign/idr/tools/idris-mlir-cc.cc`). Then the pinned `gcc` links it
  with `-lm`.
- The runtime helpers are LLVM-dialect functions in the same module
  (`Lower/Runtime.mlir.inc`).
- Our C++ is built with GCC's LTO in the Release configuration
  (`CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE`); LLVM/MLIR are not.

**Programs: one module, full LTO.**
- **Bitcode at toolchain build time.** The runtime and the vendored
  libraries we build from source (snmalloc, simdutf, fast_float) are
  compiled to bitcode when the toolchain is built, in the fat objects of
  section 5.4.
- **Our driver does the LTO.** `idris-mlir-cc`:
  1. links the program's module with that bitcode (`llvm::Linker`);
  2. internalizes every symbol but the entry point;
  3. drops what is unreachable;
  4. runs the O3 pipeline over the whole program, then code generation.

  This is monolithic ("full") LTO done in our own driver, and the linker
  receives one object. There is no ThinLTO: a program is small next to
  what monolithic LTO handles, and monolithic LTO inlines across
  everything.
- **What it buys:**
  - the allocator's fast path (section 5.6), the count operations, and the
    string and number helpers inline into generated code;
  - interprocedural constant propagation, function specialization and
    dead-argument elimination run across program and runtime together;
  - runtime code a program does not use is not in its executable.
- **What stays outside the module:** musl and GMP, as native archives.
  - musl has no LTO support upstream (neither `configure` nor `WHATSNEW`
    mentions it), and its entry, TLS setup and syscall glue are assembly.
  - GMP's speed is in its assembly `mpn` kernels. `Big`'s small-integer
    fast path is ours, in the runtime, so it is inside the module.
- **The link:** `lld`, static-PIE, `--gc-sections`, `--icf=all`.
- **Compile time:** the whole runtime goes through O3 on every compile.
  Internalizing first removes what a program does not use (simdutf
  kernels; the scheduler, for a program that never forks). The cost is
  measured against the target of section 8.2.

**The target CPU.** Today it is `generic`.
- The default becomes `x86-64-v3`: AVX2 and BMI2, which every x86-64 CPU
  since Haswell (2013) and AMD's Zen has.
- `--cpu=native` targets the build machine, and `--cpu=x86-64` the
  baseline. Apple silicon targets `apple-m1`.
- simdutf is compiled for the same CPU (section 3).
- The JIT always targets its host, which is where it runs.

**Aggressive, but never beyond the semantics:**
- No fast-math anywhere: `arith` ops carry no fast-math flags, and LLVM
  gets none.
- No floating-point contraction (`-ffp-contract=off`, and none in the
  lowering). Fusing `a*b+c` into one FMA changes a result that IEEE
  arithmetic defines. The math functions are implementation-defined
  (decision 7); `+` and `*` are not.
- `nsw`, `nuw`, `noalias`, `nonnull`, `dereferenceable` and value ranges
  are emitted only where 03's semantics or a fact the compiler has proved
  allows them. Whole-program types supply many such facts: a `Box` is
  non-null and dereferenceable for its size, and a `Fin n` is below `n`
  (section 8.3).

**Later: profiles and post-link optimization.**
- **PGO:** `--profile-generate` instruments a program (compiler-rt's
  profile runtime), and `--profile-use` feeds the profile back.
- **BOLT** (in the pinned llvm-project, `bolt/`) reorders the final static
  executable, which is linked with `--emit-relocs` for it.
- Both come after M1, once there is heap code to profile, and are measured
  on `bench/`.

**Our tools use LTO too.**
- Stage 2 builds LLVM/MLIR, `clang` and `lld` with `LLVM_ENABLE_LTO=Full`,
  and our C++ tools with `-flto=full`. With GCC gone, this is one LTO
  domain.
- PGO for clang and `lld` themselves, as LLVM's bootstrap supports, comes
  later.
- **Risk: memory.** A full-LTO link of LLVM and MLIR into
  `idris-mlir-cc` may not fit in 15 GB. If it does not, the measured
  numbers go into `PINS.md` as a deviation for LLVM's own libraries only,
  as `lint-graph-unbuilt` records clang today.

**From day one.** Before milestone 3 brings clang, `idris-mlir-cc`
changes in milestone 1:
- O3 instead of O2;
- `x86-64-v3` instead of `generic`;
- every symbol but `main` internalized;
- each change measured on `bench/`.

The runtime's bitcode, `lld` and stage-2 LTO come with milestone 3, the
first milestone that has a runtime to link.

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
  - The exception is allocation, freeing and the count helpers, which are
    too frequent to switch. They run in a measured reserve at the top of
    each segment (section 5.6).
- **Tail recursion modulo cons** (Leijen and Lorenzen, *literature*) turns
  `map`, `filter` and `append` into loops that fill a hole in the last
  cell. This removes most deep recursion before stacks are involved, and
  it combines with reuse, since the cell is written once.
- **Experiment first (C0).** Measure the prologue on the benchmark table
  (target: within noise) and the hot-split case, against fixed
  reservations. Only then build it.

**Scheduling is cooperative, with preemption at function entries.**
- A task runs until it suspends on IO, a channel, a lock, a timer or an
  `await`. Long pure work belongs in futures.
- **Cooperation alone is not enough.** A task that spin-waits on an
  `IORef` which another forked task sets finishes under the reference's
  preemptive threads and hangs forever on one cooperative core. That is a
  legitimate Idris program.
- **The stack prologue gives preemption for free.** A timer sets the task's
  segment limit to a value above any stack pointer, so the next function
  entry takes the slow path and yields. This is Go's `stackPreempt`
  (`runtime/stack.go`, *code*).
- Loops are join points and contain no call, so `idr-lower` puts the same
  check on loop back-edges.

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
| 1 | **Cleanup** (section 9), **and optimization from day one** (5.7) | no Python; golden runner green with the same tests; library organized; `idris-mlir-io` gone; `idris-mlir-cc` at O3 for `x86-64-v3` with every symbol but `main` internalized, and `bench/` no slower |
| 2 | **Memory gate** (section 4.4) | the three experiments pass, or the decision is reopened with the numbers |
| 3 | **LLVM-only static toolchain on musl, with full LTO** (section 5) | musl, GMP, simdutf, fast_float and snmalloc pinned as submodules; the two-stage LLVM bootstrap (5.2) with its build time and peak memory stated; no GCC left in `.toolchain/` or `tools/dev.py`; LLVM/MLIR, `clang`, `lld` and our C++ tools static on musl and libc++, with LTO; `lint-graph-unbuilt` retired; snmalloc's own tests pass on musl; a `runtime/` archive of fat objects with no C++ runtime symbol referenced; programs linked into one LTO module (5.7); every executable static-PIE (no `INTERP`, no `DYNAMIC`); GMP's own tests pass; the differential tests compare math function results within a tolerance, since they are implementation-defined |
| 4 | **M1 (v4): heap and strings** | `Rep`; `Box` for recursive data; ownership modes, counting ops and the `IDR-OWN-*` verifier in the `idr` dialect, Lean's passes over it (section 4.2); `MEM-LIN-1` enforced, with tests that inspect the emitted code (no allocation, no count operation at guaranteed sites) and tests that are rejected; runtime strings and `getLine`; `words`/`lines`/`pack`/`unpack` through the Prelude; `idr-jit` with primitives and closed calls; `PROF-DATA-3` and `PROF-HEAP-3` withdrawn for runtime values; the allocation suite in `bench/` within the gate's targets |
| 5 | **M2 (v5): `Integer` and `Nat`** | small integers with GMP fallback; `Nat` as `Big`; the server's `Integer`; `Fold.idr` and `SEM-BIG-1` deleted; `transpose` compiles; `printLn 'x'` compiles in under a second |
| 6 | **M3 (v6): closures and `Lazy`** | defunctionalized where the set is known, boxed otherwise; `PROF-HEAP-1/2/4` withdrawn for runtime values |
| 7 | **M4 (v7): arrays** | the three array primitives; `IOArray`; `Data.Linear.Array`; bounds traps; `ELIM-FIN-1` enforced, with tests that find no bounds test at guaranteed sites and tests that are rejected; the array benchmarks (sieve, quicksort, matrix multiply) beat MLton |
| 8 | **C0: stacks** (section 7.3) | the segment check in `idr-lower` and the system-stack switch, measured: the benchmark table within noise, and the hot-split case bounded; a million-deep non-tail recursion runs |
| 8a | **Debugging and profiling** (12.5) | crash backtraces with source locations; DWARF from MLIR locations; `perf` and `gdb` through segments and system-stack switches |
| 8b | **C1: tasks on one core** | `fork`, `threadWait`, `System.Concurrency` task-aware, `Network.Socket` over `epoll`, timers; an echo server and an HTTP plaintext server under load |
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
- **02:** the guarantees `MEM-LIN-1` and `ELIM-FIN-1` and their
  rejections; admit the Prelude, base, contrib and linear modules that become
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
  - bounds traps on arrays;
  - the grammar of `cast` from `String` to `Double` and to the fixed-width
    integers (section 3).
- **05:** `Code Mem`'s `Mark` and `Release` give way to the dialect's
  counting ops (section 4.2). `Code` keeps quantities on binders and
  fields, for emission as ownership modes.
- **08:** the ownership modes, the counting ops (`idr.dup`, `idr.drop`,
  `idr.borrow`, `idr.share`, `idr.reset`, `idr.reset.dyn`, `idr.reuse`) and
  the `IDR-OWN-*` verifier rules; the `idr.box`, `idr.str.*`, `idr.big.*`, `idr.array.*` and
  `idr.io.get_line` ops and the count operations, with their memory
  effects.
- **10:** the `Rep` layouts and struct-of-arrays; the runtime calls.
- **11:** the LLVM-only static toolchain and its cpp-starter deviations
  (clang, libc++, no reflection yet), full LTO, GMP, the libc, `runtime/`.

## 11. Tradeoffs

For each decision: what it buys, what it costs, and what evidence would
reverse it.

| Decision | Buys | Costs | Reversed if |
| --- | --- | --- | --- |
| Runtime representations for everything (3) | every profile program compiles; compile-time evaluation becomes optional | a runtime, a heap, and code for boxed values where specialization used to remove them | never: without it the profile stays heap-free |
| Quantities as guarantees (decision 10, 4.2) | performance the types promise cannot silently degrade: a linear update is in place or the program does not compile; the one thing Lean does not offer | programs that pass a possibly shared value to a quantity-1 parameter are rejected; a whole-program uniqueness analysis to build and to explain in its errors | its rejections land often on code people reasonably write |
| Ownership in the `idr` dialect, verified (4.2) | the guarantees are checked by the IR after every pass, not trusted from the frontend; uniqueness at calls is plain type matching; leaks and double frees are verifier errors | a larger dialect and verifier; generic MLIR passes are not linearity-aware, so some of their rewrites must be kept away from owned values; verification time after every pass | the verifier's cost dominates compile time, or keeping generic passes linear costs more optimization than it saves |
| Reference counting (4) | the best measured speed on functional code; peak memory close to live data; in-place reuse; no stack scanning, so tasks, the JIT and `epoll` stay simple | counts in the code (removed by borrowing, reuse and QTT, not by the model); atomic counts on data shared across cores; cycles through mutable cells | the gate fails: slower than MLton, or atomics dominate a thread-per-core workload |
| Heaps per core, move-or-mark (4.3) | messages built for sending cross cores with no atomics | a walk over each crossing value; remote frees | the walk costs more than copying (Erlang) on real messages |
| Thread-per-core, IO tasks pinned (7) | core-local data; no migration; almost all counts non-atomic | no automatic balancing of IO tasks across cores; a long computation in a task blocks its core | real servers need IO-task migration for load balance |
| Idris's libraries as the concurrency API (7.2) | no language design; programs run on Chez too | no "fork on core k" (a runtime policy stands in) | a program cannot be written without placement control |
| Segmented stacks with our own check (7.3) | unbounded recursion like the reference; unbounded tasks; no pointer maps | a check per function entry; a system-stack switch per C call; the hot-split case | C0 shows the check is not within noise, or hot splits are common |
| musl on Linux, `libSystem` on macOS (5.2, 5.5) | a complete, mature Linux libc on which the whole toolchain, the JIT included, can be static; the same OS-layer shape on macOS | a simple `memcpy`; libc++ and compiler-rt built for it in the bootstrap; two OS layers to maintain | a supported platform offers no static libc and no stable dynamic one (not the case for Linux or macOS) |
| Vendored snmalloc (5.6) | 1.5–5× faster than mimalloc on cross-core frees, which are what the compiler cannot remove; size classes fixed at compile time and inlined by LTO; configuration only at compile time; no allocator of our own to write or debug | 12–22% slower than mimalloc on one core; no functional-runtime precedent; no musl CI upstream; remote frees wait for the owner's next refill or the scheduler's flush | the memory gate shows the one-core cost dominating real programs, or cross-core traffic stays rare even with futures |
| Full LTO everywhere, as aggressive as semantics allow (5.7) | the runtime's fast paths inline into generated code; interprocedural optimization over program and runtime; dead runtime code gone; the same for our tools | the whole runtime through O3 on every compile; memory for LTO links of LLVM; a `x86-64-v3` default that pre-2013 CPUs cannot run | compile time misses section 8.2's target even after internalizing, or LTO links of LLVM do not fit the build machine |
| LLVM only, no GCC (5.2) | one compiler, one LTO domain, one C++ library (libc++); clang and `clang-tidy` finally built | a two-stage LLVM bootstrap on a small machine; cpp-starter's GCC profile replaced | a needed C++ feature that only GCC has |
| fast_float, and our own number grammar (3) | correctly rounded parsing with the algorithm behind GCC's and LLVM's `from_chars`; one written grammar | strings some hosts accept (`1d3`, `1/2`) give 0 | nothing foreseeable |
| GMP (5.3) | the fastest bignums, with assembly kernels | LGPL obligations for static executables; a build dependency | licensing forbids it for a user; a permissive library of comparable speed appears |
| One JIT path (6) | one semantics per primitive; no Idris copy of the runtime; native speed at compile time | a C++ server process per compilation; start-up time; `fork` per call | start-up dominates small compilations and cannot be cached |
| UTF-8 strings with scalar counts, via simdutf (3) | upstream's encoding at every boundary; output without transcoding; compact storage; O(1) for ASCII; SIMD validation and counting | breadcrumbs for indexing non-ASCII strings; a C++ dependency built without a C++ library at link time, a mode marked experimental | programs index non-ASCII strings heavily enough that UTF-32 wins, or that mode breaks and a small validator replaces it |
| `believe_me` is the identity only between equal `Rep`s (12.1) | library casts keep their meaning where representations agree; everything else is a named rejection, never a miscompile | a library cast between differing `Rep`s that a program needs is rejected | the census finds such a cast on a common path |
| Idris's C support library, behind one IO layer (12.1) | base's IO without rewriting it; defined ordering of output | wrapping or replacing its blocking calls | its `FILE*` model cannot be made to share descriptors safely with the scheduler |
| No Python; golden tests in Idris (9) | one language in the repository; Idris's own test tooling | rewriting about 1 900 lines of harness | nothing foreseeable |

## 12. What we still need to understand

The final pass over the plan and the sources. Each item says what is known,
what is not, and what settles it. "Leaning" is a recommendation, not a
decision.

### 12.1 Semantics and the libraries

1. **`believe_me` under non-uniform representations.**
   - **Known:** the libraries use it 31 times:
     - `prelude` 6, `base` 21, `contrib` 3, `linear` 1;
     - most sites cast proofs (erased), casts between `PrimIO` types, or
       views over primitives;
     - one is load-bearing: the Prelude's `prim__integerToNat i` is
       `believe_me i`, which relies on `Nat` and `Integer` having the same
       runtime form.
   - **Unknown:** whether any reachable site casts between types whose
     `Rep`s differ.
   - **Settles it:** a rule that a `believe_me` is the identity when both
     sides have the same `Rep`, is erased when both are erased, and is
     otherwise rejected with a named rule; then a census of every site
     reachable from the test programs.
   - **Leaning:** that rule; `Nat` and `Integer` must share `Big` exactly
     (section 3).
2. **Idris's C support library.**
   - **Known:** `base` has 145 `%foreign` declarations and `network` 41.
     Most name `libidris2_support`: about 1 500 lines of BSD-3 C built on
     stdio `FILE*`, covering files, directories, environment, clock,
     buffers, signals and sockets.
   - **Unknown:** whether to link it (built on musl) or to reimplement what
     programs use.
   - **Two hazards if linked:**
     - its reads and `accept` block the core;
     - output through stdio buffers can be reordered against our own direct
       writes to the same descriptor.
   - **Leaning:** link it for the non-blocking functions; route every
     descriptor operation (stdout included) through one runtime IO layer,
     so ordering is defined and blocking calls go to the scheduler or the
     blocking pool.
3. **Invalid UTF-8 at input.** Chez decodes console input with its
   transcoder, whose R6RS default replaces invalid sequences
   (*literature*). We replace with U+FFFD (section 3).
   - **Unknown:** whether Idris's Chez setup changes that mode.
   - **Settles it:** a differential test with invalid bytes on stdin.
4. **Progress under cooperative scheduling.** Settled above (7.3):
   preemption at function entries and loop back-edges.

### 12.2 Memory

5. **Cycles through `IORef`, `IOArray` and `Buffer`.**
   - **Known:** these are the only sources (section 4.1). Lean, Koka and
     Swift leak them.
   - **Unknown:** how often real Idris code builds them.
   - **Settles it:** a census, then one of: leak; reject statically (a
     mutable cell whose content type can reach a mutable cell); or trial
     deletion restricted to mutable cells.
   - **Leaning:** reject statically. It is conservative, has no runtime
     cost, and names the rule.
6. **Pauses from freeing large structures.**
   - **Known:** freeing is proportional to what dies, not to the heap, and
     Lean's to-do list makes it iterative.
   - **Unknown:** the latency this adds to a server request that drops a
     large structure.
   - **Leaning:** bound the work per scheduler turn, and continue freeing
     at the next yield.
7. **Marking futures' captures.**
   - **Known:** Lean marks a task's closure shared when the task is
     spawned. Marking at the moment of a steal would race with the owner
     core, which may still be changing those counts non-atomically.
   - **The cost:** captures of futures that are never stolen pay atomic
     counts anyway.
   - **Settles it:** experiment 3 of the gate, with and without a handshake
     at steal time.
8. **The allocator's open parameters.** Section 5.6 chooses snmalloc.
   - **Unknown:**
     - how large a reserve snmalloc's slow path needs on a segment;
     - where the scheduler flushes remote batches (end of turn, idle), and
       how much memory an idle core holds meanwhile;
     - whether sending a dead root home beats per-node remote frees
       (section 5.6);
     - whether snmalloc should also replace `malloc` (its
       `override/malloc.cc`) for musl, GMP and the C support library in
       executables, and in our tools, LLVM included.
   - **Settles it:**
     - `-fstack-usage` over the runtime's allocation entry points;
     - gate experiment 3, with and without the flush points and with
       dead roots sent home;
     - for replacing `malloc`: a build of `idr-jit` with and without the
       replacement. musl supports the replacement: its `WHATSNEW` says
       "replacement of malloc is now allowed/supported", and allocations
       inside musl that must stay musl's call `__libc_malloc` (*code*).
9. **Strings in loops.** `s ++ x` in a loop is quadratic unless the append
   extends a unique `s` in place (Lean's `String.append`). Small strings
   could live inline in the value instead of on the heap (Swift). Measured
   on the string benchmarks of M1.
10. **Constant data.**
    - **Known:** with a heap, a large constant list (`[1 .. 10000]`) should
      be one static object in `.rodata`, not code that builds it. Lean
      extracts closed terms (`extractClosed`, `SimpleGroundExpr`, *code*).
    - **Settles it:** a threshold on the size of static data the driver
      builds as code.

11. **How precise the uniqueness analysis must be** (`MEM-LIN-1`).
    - **Known:** its cases are values built at the call, quantity-1
      binders, variables whose other uses are dead, and fields of a unique
      value that is consumed.
    - **Unknown:** closures that capture a linear value, values that cross
      cores (count 1 after a move is still unique), and code the driver
      duplicates into branches.
    - **Settles it:** the census below, then M1's tests. Every rejection
      must name a call and a reason a person can act on.
12. **Quantity 1 in the libraries.**
    - **Known:** 27 binders in the Prelude, 38 in base, 16 in contrib, 15
      in linear, and 13 in network, mostly worlds (*code*).
    - **Unknown:** whether any library function takes a boxed value at
      quantity 1 and is called with a shared one. The guarantee would then
      reject programs that only call that library.
    - **Settles it:** a census of those binders and their call sites in the
      libraries.
    - **Leaning:** the guarantee holds for library code too. A library
      site that breaks it is reported upstream, not exempted.

13. **Generic MLIR passes and linear values.**
    - **Known:** MLIR has no linear values, and its passes may duplicate
      or merge uses. With owned values in the IR:
      - allocation must carry an effect, so CSE cannot merge cells;
      - canonicalization's `scf.if` to `arith.select` rewrite consumes both
        operands, which the verifier rejects.
    - **Unknown:** which upstream patterns fire on owned values in
      practice, and whether running them before counts are explicit (as
      Lean does) avoids all of them.
    - **Settles it:** M1 runs the full pipeline with the verifier after
      every pass on the whole suite. Each violation is fixed by ordering or
      by an op's traits, never by relaxing the verifier.

### 12.3 The driver and compile time

14. **Does supercompilation scale?**
    - **Known:** Mitchell's supercompiler (Haskell, 2010, *read*) was
      measured on programs of at most 148 lines, compiling in under four
      seconds; his earlier version took up to five minutes. Whether
      supercompilation scales to large programs is the technique's known
      open problem.
    - Our driver runs over the Prelude and base with every program.
      Today's fixtures compile in seconds, and `printLn 'x'` in 5.7 s.
    - **Settles it:**
      - a compile-time benchmark on the largest programs we can write
        against base and contrib;
      - hash-consed configurations and incremental embedding checks;
      - the target of section 8.2.
15. **Code size.** Choices, specializations and literal unfolding can each
    grow code. The whistle bounds them, but no budget is set on the result.
    - **Settles it:** a code-size column in `bench/` and in the compile-time
      benchmark, with a per-function limit if growth appears.
16. **What goes to the JIT.** Every primitive fold becomes a request,
    thousands per compilation.
    - **Unknown:** whether a pipe round trip per fold is small next to the
      driver's own cost.
    - **Settles it:** measure. Batch the folds of one step if needed.

17. **Joining two literal strings:** data layout (kept in `Simplify`), or a
    primitive fold for the server? Leaning: data layout, since it is the
    same concatenation a linker performs on literal pools.

### 12.4 Concurrency

18. **Placing work on cores.**
    - **Leaning:** a runtime policy: tasks forked by `main` spread over
      cores, and nested forks stay local.
    - **The alternative:** a few runtime externs through Idris's FFI.
19. **Signals.** A thread-per-core runtime needs one owner for signals:
    - `SIGPIPE` ignored, with `MSG_NOSIGNAL` on sends;
    - `SIGINT` and `SIGTERM` delivered through a `signalfd` on one core;
    - Idris's `System.Signal` implemented on top.
20. **`io_uring` versus the blocking pool.** Glommio and monoio use
    `io_uring`; tokio uses `epoll` with a blocking pool. C2's measurements
    decide.

### 12.5 Toolchain and platform

21. **LLVM on musl.** LLVM raises its threads' stacks to 8 MiB only on
    Apple and AIX; elsewhere it takes the libc default, and musl's is
    128 KiB (`lib/Support/Threading.cpp`, *code*).
    - MLIR's multithreaded pass manager could overflow on it.
    - Our tools must link with `-Wl,-z,stack-size=…`, which musl reads as
      its thread default, or run MLIR single-threaded.
    - **Settles it:** the toolchain milestone's test suite on the musl
      build.
22. **GMP's licence reaches every user's binary.** A statically linked GMP
    obliges whoever distributes a program to let its users relink it
    against another GMP.
    - This concerns every program that uses `Integer` at runtime, not just
      us.
    - **Unknown:** whether that is acceptable for the programs you want to
      compile.
    - **The alternative:** a permissively licensed bignum, slower on large
      numbers.
23. **Provenance of mirrors.** musl and GMP come from GitHub mirrors,
    because their official hosts are unreachable here. Each pin should be
    checked once against the official release's signature from a machine
    that can reach it.
24. **Debugging and profiling** (milestone 8a, new in this pass).
    - Crash backtraces, DWARF from MLIR locations, and `perf` through
      segmented stacks and system-stack switches.
    - Segments break the unwinder's assumption of one contiguous stack,
      unless each segment's first frame records the link to the previous
      one, as Go does for its stacks.
    - **Settles it:** milestone 8a, after C0.
25. **macOS JIT.** `fork` per call and `MAP_JIT` under the hardened
    runtime. Checked when macOS starts (milestone 12).
26. **Full LTO's compile time and memory** (section 5.7).
    - **Unknown:**
      - how long O3 over program plus runtime takes per compile;
      - whether full-LTO links of LLVM and MLIR fit in 15 GB.
    - **Settles it:** milestone 3 measures both, with and without
      internalizing first.
27. **Frame pointers.**
    - Omitting them frees a register.
    - Keeping them makes `perf` and crash backtraces cheap and reliable
      across our stack segments. Go keeps them for its tracer.
    - **Settles it:** milestone 8a measures the cost on `bench/`.
    - **Leaning:** keep them, if the cost is within noise.
28. **The `x86-64-v3` default** leaves out x86-64 CPUs from before 2013.
    - **Leaning:** keep it for executables, with `--cpu=x86-64` a flag
      away.
29. **Number casts in types.** The typechecker reduces `cast` on a literal
    string through its host (section 3). For a string outside our grammar,
    such as `"1d3"`, a type could compute 1000.0 while the runtime gives 0.
    - This is the same class of question as `strLength` (section 3):
      a proof about a runtime value.
    - **Settles it:** a census of the library for `cast` from `String` in
      types. A literal cast outside our grammar that reaches a type could
      be rejected with a named rule.

### 12.6 Evidence we cannot produce here yet

30. **The comparisons need toolchains we have not installed:** Koka and
    Lean for the memory gate; Go and Rust (monoio or Glommio, hyper,
    tokio) and Seastar for C2; MPL for C3.
    - GitHub clones work in this container; release downloads and package
      servers are untested.
    - **Leaning:** build from source where the network allows it, and say
      plainly which comparisons are missing when it does not.

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
  - simdutf at `152a5fe` (`include/simdutf_c.h`, `README.md`);
  - Go's `runtime/stack.go` (`stackPreempt`), LLVM's
    `lib/Support/Threading.cpp` (thread stack sizes);
  - Idris 2's C support library (`support/c/`) and the `%foreign` and
    `believe_me` sites in `libs/`;
  - Mitchell, "Rethinking supercompilation" (ICFP 2010), and Brady,
    "Idris 2: Quantitative Type Theory in practice" (ECOOP 2021), from the
    research library;
  - Idris 2's string primitives in every backend
    (`src/Core/Primitives.idr`, `src/Compiler/Scheme/Common.idr`,
    `src/Compiler/RefC/RefC.idr`, `support/refc/stringOps.h`,
    `src/Compiler/ES/Codegen.idr`);
  - the allocators, cloned from GitHub:
    - mimalloc 3.5.3 (`include/mimalloc.h`, `readme.md`, `src/free.c`,
      `src/page.c`, `CMakeLists.txt`);
    - snmalloc 0.7.5-15-ge9f7b2e (`README.md`, `snmalloc.pdf`: Liétar et
      al., "snmalloc: a message passing allocator", ISMM 2019;
      `src/snmalloc/mem/corealloc.h`, `mem/remotecache.h`,
      `mitigations/allocconfig.h`, `mitigations/mitigations.h`,
      `ds_core/sizeclassconfig.h`, `pal/pal_linux.h`,
      `.github/workflows/main.yml`);
    - rpmalloc (`rpmalloc/rpmalloc.c`);
    - jemalloc (`src/tcache.c`, `src/bin.c`);
    - tcmalloc (`README.md`, `CMakeLists.txt`);
  - how Lean and Koka use mimalloc: Lean's `src/runtime/mimalloc.cpp`,
    `alloc.cpp`, `object.cpp` and `mpz.cpp`, and `USE_MIMALLOC` in
    `src/CMakeLists.txt`; Koka's `kklib/CMakeLists.txt` (`KK_MIMALLOC`) and
    `.gitmodules`;
  - Seastar's allocator (`src/core/memory.cc`: `free_cross_cpu`,
    `drain_cross_cpu_freelist`);
  - `foreign/idr/bench/alloc`: our allocation shapes on mimalloc and snmalloc, with
    the results;
  - fast_float at `9498cc3` (v8.3.0-16; `include/fast_float/float_common.h`,
    `README.md`), checked on a corpus of number strings;
  - Idris 2's `cast` from `String` (`support/chez/support.ss`: `cast-num`,
    `destroy-prefix`; `src/Core/Primitives.idr`: `castDouble`);
  - LLVM libc and LLVM in the pinned `llvm-project` (`libc/docs`,
    `libc/config/linux/x86_64/entrypoints.txt`,
    `llvm/include/llvm/ADT/DynamicAPInt.h`,
    `llvm/lib/Target/X86/X86FrameLowering.cpp`, `libcxx/CMakeLists.txt`,
    `clang/include/clang/Options/Options.td`,
    `clang/lib/Parse/ParseReflect.cpp`);
  - our own build and driver (`CMakeLists.txt`,
    `foreign/idr/tools/idris-mlir-cc.cc`, `PINS.md`).
