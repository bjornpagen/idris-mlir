# idris-mlir

An experimental whole-program compiler from a strict, versioned subset of
Idris 2 to native code through MLIR. The goal is to turn what Idris's type
system establishes into less runtime work.

```text
Idris frontend (pinned) → checked TT → Core (Idris) → guaranteed eliminations
  → idr dialect (C++) → upstream MLIR → LLVM → object → pinned gcc links
```

The specification is [docs/architecture/](docs/architecture/00-index.md)
(normative). p0, v0, v1 and v2 are implemented; see its
[roadmap](docs/architecture/15-roadmap.md) for the status and the deviations.

## What compiles today

Programs are heap-free: after monomorphisation and the guaranteed
eliminations (beta reduction, known constructors, specialization on
functions, arity raising, compile-time string evaluation, output fusion),
no closure, thunk or runtime-built string may remain, or compilation fails
with an `unsupported (<RULE>)` error at the source location.
- **v0:** a single `--no-prelude` module with `main : Int` (the exit status):
  fixed-width integers, non-recursive data types and records, recursion,
  erased arguments. Self tail calls become loops.
- **v1:** `main : IO ()` programs over several modules with the
  `idris-mlir-io` package: `do`, `putStr`/`putStrLn`/`putChar`/`getChar`/
  `exit`, `Char`, static strings, lambdas, higher-order and polymorphic
  functions, and user monads written with plain functions. The executable
  references only `write`, `read` and `_exit`.
- **v2:** user-defined interfaces (superclasses, defaults, named and
  constrained implementations, higher-kinded ones such as a user `Monad`
  with `do`), resolved at compile time; `Double` with Chez's semantics and
  shortest round-trip printing; libm functions. See
  [the math showcase](tests/e2e/v2/math-showcase) for what that allows.

- **v3 (in progress):** `import Prelude` in IO programs: `Num`, `Eq`,
  `Ord`, `Bool`, `if`, `Maybe`, pairs, `cast`, and `show`, with `Integer`,
  `Nat` and lists evaluated at compile time. See
  [the v3 note](docs/research/v3-entry.md) for what is still missing.

On the heap-free programs it can compile, the output is faster than MLton's
on every benchmark in [bench/](bench/README.md), by 1.4x to 4.3x, and within
reach of gcc -O2.

```sh
idris-mlir --no-prelude --cg mlir --inc mlir --check Prog.idr    # main : Int
idris-mlir --no-prelude -p idris-mlir-io --cg mlir -o prog Main.idr   # IO
python3 tools/dev.py compile Prog.idr -o prog                     # either
```

The Prelude is not supported yet: its modules come later, layer by layer.

## Setup

Prerequisites: Python 3.9+, Git, Make, a host C/C++ compiler, a threaded Chez
Scheme, GMP headers, and GCC's build prerequisites (MPFR, MPC, flex,
texinfo). See [toolchain](docs/toolchain.md) for exact packages.

```sh
git submodule update --init
python3 tools/dev.py doctor
python3 tools/dev.py check                      # tooling tests
python3 tools/dev.py bootstrap-idris --scheme scheme
python3 tools/dev.py bootstrap-gcc              # slow: pinned GCC 16
python3 tools/dev.py bootstrap-cmake
python3 tools/dev.py bootstrap-ninja
python3 tools/dev.py bootstrap-llvm             # slow: pinned LLVM/MLIR
python3 tools/dev.py build                      # C++ dev preset, compiler, IO package
python3 tools/dev.py test                       # profile, e2e (incl. Chez diff)
python3 tools/dev.py test-idr                   # the idr dialect (lit)
python3 tools/dev.py test-mlir-tools
```

Everything is installed under `.toolchain/`.

## Docs

- [Architecture spec](docs/architecture/00-index.md) (normative)
- [Toolchain](docs/toolchain.md)
- [Whole-program compilation: prior art and plan](docs/research/whole-program-compilation.md)
- [Next research brief: optimizing from first principles](docs/research/next-research-prompt.md)
- Research notes from before the rewrite: [compiler interfaces](docs/research/compiler-interfaces.md),
  [starting point and tests](docs/research/starting-point-and-tests.md),
  [MLIR and Mojo](docs/research/mlir-and-mojo.md)

## License

[0BSD](LICENSE). The Idris 2 dependency keeps its
[upstream license](third_party/Idris2/LICENSE).
