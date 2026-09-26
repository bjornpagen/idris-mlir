# idris-mlir

An experimental compiler from checked Idris 2 TT to MLIR. The goal is to turn
what Idris's type system establishes into less runtime work.

```text
Idris frontend (pinned) → checked TT → our IR → erasure → MLIR text
  → mlir-opt → mlir-translate → opt → llc → cc
```

Today everything up to MLIR text is written in Idris, and MLIR is used only
through the stock, pinned LLVM tools with upstream dialects. The target
architecture, specified in [docs/architecture/](docs/architecture/00-index.md)
(draft, awaiting review), adds an MLIR dialect of our own in C++, compiles a
versioned, heap-free subset of Idris 2, and is not implemented yet.

## Current state

The `mlir` backend compiles a single no-Prelude module of first-order
functions over fixed-width integers (`Int`, `IntN`, `BitsN`): literals,
`+ - *`, comparisons, casts, calls, `let`, and matches on integer literals.
Quantity-0 parameters stay in the IR and are removed by an explicit erasure
pass. A zero-argument `main : Int` becomes C `main`, returning the exit status.
Anything else fails with an explicit `unsupported` error.

```sh
idris-mlir --no-prelude --cg mlir --inc mlir --check Arith.idr
# writes build/ttc/<version>/Arith.ir and Arith.mlir
```

Not yet: IO, data types, closures, the Prelude, multiple modules, and running
the native tools from the compiler. The test harness runs them for now
([tests/native.py](tests/native.py)).

## Setup

Prerequisites: Python 3.9+, Git, Make, a C compiler, a threaded Chez Scheme,
GMP headers, and CMake and Ninja for the LLVM build. See
[toolchain](docs/toolchain.md) for exact packages.

```sh
git submodule update --init
python3 tools/dev.py doctor
python3 tools/dev.py check                      # tooling tests
python3 tools/dev.py bootstrap-idris --scheme scheme
python3 tools/dev.py bootstrap-llvm             # slow: pinned MLIR tools
python3 tools/dev.py build
python3 tools/dev.py test                       # Idris source to executable
python3 tools/dev.py test-mlir-tools
```

Everything is installed under `.toolchain/`.

## Docs

- [Architecture spec](docs/architecture/00-index.md) (normative; draft)
- [Toolchain](docs/toolchain.md)
- [Whole-program compilation: prior art and plan](docs/research/whole-program-compilation.md)
- [Next research brief: optimizing from first principles](docs/research/next-research-prompt.md)
- Research notes from before the rewrite: [compiler interfaces](docs/research/compiler-interfaces.md),
  [starting point and tests](docs/research/starting-point-and-tests.md),
  [MLIR and Mojo](docs/research/mlir-and-mojo.md)

## License

[0BSD](LICENSE). The Idris 2 dependency keeps its
[upstream license](third_party/Idris2/LICENSE).
