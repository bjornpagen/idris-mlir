# idris-mlir

An experimental whole-program compiler from a strict, versioned subset of
unmodified Idris 2 to native code through MLIR. The goal is high-level code
with guaranteed costs. Where the types promise something (in-place reuse of
linear values, no bounds check), the compiler either
delivers it or rejects the program with a named rule. It is not a Rust
replacement for explicit layout and control, and not merely a faster Idris
backend.

```text
Idris frontend (pinned) → checked TT → Core (Idris: types, monomorphisation, representations)
  → idr dialect (C++) → the simplify loop: inline, specialize, evaluate at compile time
    by running the program's own code in a JIT, to a fixpoint
  → defunctionalize, reference counting, loops → idr-lower → LLVM O3 with the runtime
  → object → lld links a static-PIE executable on musl
```

Targets: x86_64 Linux (musl, static PIE) today; arm64 macOS is the next
first-class target, and the code is written for both (AGENTS.md).

Idris does types; MLIR does programs. Idris checks the program,
monomorphises it and decides each value's representation; everything else
(inlining, specialization, compile-time evaluation, defunctionalization,
reference counting and loops) happens in MLIR. Compile-time
evaluation is runtime evaluation run early: every closed call of pure code
is evaluated by running the program's own lowered code with its own
runtime. As in Idris's own evaluator, totality does not decide what is
evaluated: total code runs to the end, and partial code runs within a
budget, past which the call is left to run at runtime.

## Why not Lean 4

Lean 4 is dependently typed, compiles through precise reference counting
with borrowing and in-place reuse, and ships a production compiler. Our
memory plan ports its passes. What Lean
cannot promise is *when* reuse happens. It tests the count at runtime, so one
extra reference anywhere silently turns an in-place update into a copy.
Koka's fully in-place functions check a function's body statically, but
still decide at runtime whether a call's argument is shared (FP², ICFP 2023).
Idris 2's quantitative type theory states linearity in the types, and this
compiler sees the whole program, so it can prove both halves: the callee
uses the value once, and every caller passes an unshared one. The plan is
to promise the result. A quantity-1 value that is matched and rebuilt at
the same size will be updated in place with no runtime test, or the program
will not compile, with a named reason. The promise will be
carried as ownership types in the `idr` MLIR dialect, and MLIR's verifier
will check it again after every pass instead of trusting the frontend.
Today the counting underneath is in place (below); the static promise is not.
That promise, more than dependent types alone, is why this compiler exists.

## What compiles today

Values that remain at runtime after the pipeline (inlining, known
constructors, case-of-case, specialization, compile-time evaluation of
closed calls, defunctionalization) live in cells on the heap, with
explicit reference counts: `idr-rc` reuses the cell of a value that dies
for a constructor of the same size, borrows the parameters a function only
reads, and adds each increment and decrement, and the verifier checks
after every later pass that every reference is consumed exactly once on
every path. Cells that never leave their frame are on the stack. Run with
`IDRIS_RT_LIVE=1`, a program reports on standard error how many cells are
still live when it ends: none.
- **v0:** programs over machine values alone, which never allocate:
  fixed-width integers, non-recursive data types and records, recursion,
  erased arguments. Self tail calls become loops.
- **v1:** `main : IO ()` programs over several modules: `do`,
  `putStr`/`putStrLn`/`putChar`/`getChar`/`getLine` (the Prelude's), `Char`,
  static strings, lambdas, higher-order and polymorphic functions, and user
  monads written with plain functions. For input and output the executable
  references only `write`, `read` and `_exit`; its entry runs the program
  on a reserved stack of a gibibyte, so a recursion that exhausts it ends
  with `idris-mlir: stack exhausted` after the output written so far.
- **v2:** user-defined interfaces (superclasses, defaults, named and
  constrained implementations, higher-kinded ones such as a user `Monad`
  with `do`), resolved at compile time; `Double` with Chez's semantics and
  shortest round-trip printing; libm functions. See
  [the math showcase](tests/e2e/v2/math-showcase) for what that allows.

- **v3:** the stock Prelude, imported explicitly by IO programs and used
  the ordinary way: `Num`, `Neg`, `Fractional`, `Integral`, `Eq`, `Ord`,
  `Show` (on `Int`, `Double`, `Bool`, `Maybe`, pairs and user types),
  `Maybe`, `Either`, `if`, `cast`, `getChar`/`putStr`/`printLn`, lists and
  ranges with `Foldable` (`sum`, `product`, folds, `map`, `for_`,
  `traverse_`). `Integer`, `Nat`, lists and streams have runtime
  representations, built at runtime on the heap; a `Nat` is a big integer
  that is never negative, and the Prelude's arithmetic and comparisons on
  it are the runtime's, as in Idris's own backends
  ([naturals](tests/registry/nat-operations)); a closed call is
  evaluated at compile time, and its result is static data. Base's
  `IOArray` is an array cell read and written through the world, and its
  `Buffer` an array of bytes ([buffers](tests/e2e/v3/buffer-bytes)). The pure
  parts of the base library (`-p base`) are trusted too: length-indexed
  vectors (`Data.Vect`), with their indices at compile time only. See
  [vectors](tests/e2e/v3/vect),
  [complex numbers through the Prelude](tests/e2e/v3/prelude-math).

On the programs of the benchmarks, the output is faster than MLton's
on seven of the eight benchmarks in [bench/](bench/README.md), by 1.4x to
4.3x (and 32x where call-pattern specialization removes most of the work),
and within reach of clang -O2. On deep non-tail recursion with no constant
argument (`ackdyn`), MLton is 2.3x faster.

```sh
idris-mlir --no-prelude --cg mlir -o prog Main.idr
make compile SRC=Main.idr OUT=prog
```

The Prelude is imported explicitly (`--no-prelude` plus `import Prelude`);
a program that needs a heap (a list whose length is known only at runtime,
a string built at runtime and kept) is rejected with the rule it breaks.

## Setup

Prerequisites: Git, Make, a host C/C++ compiler, python3 and m4 (to build
LLVM and GMP), a threaded Chez Scheme, the Linux UAPI headers and coreutils'
`timeout`. On Ubuntu 24.04:

```sh
sudo apt-get install -y git make gcc g++ python3 m4 curl chezscheme linux-libc-dev
```

`make bootstrap` builds the pinned CMake, Ninja, a two-stage LLVM/MLIR
(static on musl and libc++, with LTO), musl, GMP and Idris 2 into
`.toolchain/`; the steps and their environment are at the top of
`tools/bootstrap.sh`. Stage 1 and stage 2 take hours and tens of GB of disk.
Distribution LLVM packages track release branches, not the pinned commit, so
they are not used.

```sh
git submodule update --init
make doctor                  # what the host has, and what is built
make check                   # the repository: pins, commands, source rules; no build
make bootstrap               # slow: the pinned LLVM/MLIR, musl, GMP, Idris
make build                   # the C++ dev preset and the compiler
make test                    # compiler, profile, e2e (incl. the Chez diff and the dumps' properties), bench
make test-idr                # the idr dialect, with FileCheck
make test-mlir-tools         # the upstream bugs in upstream/ still reproduce
make bench                   # bench/run.sh
```

Everything is installed under `.toolchain/`; `make` alone lists the commands.

## Layout

- `compiler/`: the Idris side: frontend, Core, `Emit`.
- `foreign/idr/`: the `idr` dialect, its passes, the JIT and the tools.
- `runtime/`: the runtime every program links, and that folding and
  compile-time evaluation call.
- `tests/`: golden tests (`tests/Main.idr`); `bench/`: benchmarks.
- `tools/`: the toolchain's bootstrap and the compile chain;
  `tools/bisect.sh SOURCE TAG` finds the action of TAG (an evaluation, a
  clone) after which a program behaves differently than with `--no-eval`.
- `upstream/`: upstream bugs we work around, written to be filed.
- `PINS.md`: every pinned workaround and deviation.
- `sources/`: vendored papers, upstream docs and source snapshots.

## License

[0BSD](LICENSE). The Idris 2 dependency keeps its
[upstream license](third_party/Idris2/LICENSE).
