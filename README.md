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
  → defunctionalize, loops, the heap-free check → idr-lower → LLVM O3 with the runtime
  → object → lld links a static-PIE executable on musl
```

Idris does types; MLIR does programs. Idris checks the program,
monomorphises it and decides each value's representation; everything else
(inlining, specialization, compile-time evaluation, defunctionalization,
loops and the heap-free profile's check) happens in MLIR. Compile-time
evaluation is runtime evaluation run early: every closed call of total,
pure code is evaluated by running the program's own lowered code with its
own runtime, and partial code never is.

## Why not Lean 4

Lean 4 is dependently typed, compiles through precise reference counting
with borrowing and in-place reuse, and ships a production compiler. Our
memory plan ports its passes ([plan](docs/plan.md), section 4.2). What Lean
cannot promise is *when* reuse happens. It tests the count at runtime, so one
extra reference anywhere silently turns an in-place update into a copy.
Koka's fully in-place functions check a function's body statically, but
still decide at runtime whether a call's argument is shared (FP², ICFP 2023).
Idris 2's quantitative type theory states linearity in the types, and this
compiler sees the whole program, so it can prove both halves: the callee
uses the value once, and every caller passes an unshared one. The plan is
to promise the result. A quantity-1 value that is matched and rebuilt at
the same size will be updated in place with no runtime test, or the program
will not compile, with a named rule (`MEM-LIN-1`). The promise will be
carried as ownership types in the `idr` MLIR dialect, and MLIR's verifier
will check it again after every pass instead of trusting the frontend.
None of this is implemented yet: today's programs are heap-free (below).
That promise, more than dependent types alone, is why this compiler exists.

The specification is [docs/architecture/](docs/architecture/00-index.md)
(normative). p0, v0, v1, v2 and v3 are implemented; see its
[roadmap](docs/architecture/15-roadmap.md) for the status and the deviations.

## What compiles today

Programs are heap-free: after the documented pipeline (inlining with no
threshold, known constructors, case-of-case, specialization on
constant-like arguments, compile-time evaluation of total code, output
fusion, defunctionalization), nothing may allocate at runtime (a closure
that remains, a list, string or `Integer` built at runtime), or
compilation fails with an `unsupported (<RULE>)` error at the source
location.
- **v0:** a single `--no-prelude` module with `main : Int` (the exit status):
  fixed-width integers, non-recursive data types and records, recursion,
  erased arguments. Self tail calls become loops.
- **v1:** `main : IO ()` programs over several modules: `do`,
  `putStr`/`putStrLn`/`putChar`/`getChar` (today the Prelude's), `Char`,
  static strings, lambdas, higher-order and polymorphic functions, and user
  monads written with plain functions. The executable references only
  `write`, `read` and `_exit`.
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
  representations, but may not allocate at runtime yet: a closed call of
  total code is evaluated at compile time, and its result is static data. The pure
  parts of the base library (`-p base`) are trusted too: length-indexed
  vectors (`Data.Vect`), with their indices at compile time only. See
  [vectors](tests/e2e/v3/vect),
  [complex numbers through the Prelude](tests/e2e/v3/prelude-math) and
  [the plan](docs/plan.md) for what is still missing.

On the heap-free programs it can compile, the output is faster than MLton's
on seven of the eight benchmarks in [bench/](bench/README.md), by 1.4x to
4.2x (and 65x where call-pattern specialization removes most of the work),
and within reach of gcc -O2. On deep non-tail recursion with no constant
argument (`ackdyn`), MLton is 2.4x faster.

```sh
idris-mlir --no-prelude --cg mlir --inc mlir --check Prog.idr    # main : Int
idris-mlir --no-prelude --cg mlir -o prog Main.idr                # IO
make compile SRC=Prog.idr OUT=prog                                # either
```

The Prelude is imported explicitly (`--no-prelude` plus `import Prelude`);
a program that needs a heap (a list whose length is known only at runtime,
a string built at runtime and kept) is rejected with the rule it breaks.

## Setup

Prerequisites: Git, Make, a host C/C++ compiler, python3 and m4 (to build
LLVM and GMP), a threaded Chez Scheme, and the Linux UAPI headers. See
[toolchain](docs/toolchain.md) for exact packages.

```sh
git submodule update --init
make doctor                  # what the host has, and what is built
make check                   # the spec's rules against the tests, no build needed
make bootstrap               # slow: the pinned LLVM/MLIR, musl, GMP, Idris
make build                   # the C++ dev preset and the compiler
make test                    # compiler, profile, e2e (incl. the Chez diff)
make test-idr                # the idr dialect, with FileCheck
make test-mlir-tools         # the pinned upstream MLIR tools, and upstream/
make bench                   # bench/run.sh
```

Everything is installed under `.toolchain/`; `make` alone lists the commands.

## Docs

- [Architecture spec](docs/architecture/00-index.md) (normative)
- [Toolchain](docs/toolchain.md)
- [The plan](docs/plan.md): the only plan; what comes next and why
- [Research library](docs/research/library/): vendored papers and source snapshots

## License

[0BSD](LICENSE). The Idris 2 dependency keeps its
[upstream license](third_party/Idris2/LICENSE).
