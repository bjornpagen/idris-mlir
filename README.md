# idris-mlir

An experimental compiler from checked Idris 2 TT to MLIR. The goal is to turn
what Idris's type system establishes into less runtime work.

```text
Idris frontend (pinned) → checked TT → our typed IR → specialization,
representation, erasure → MLIR text → mlir-opt → mlir-translate → opt → llc → cc
```

Everything up to MLIR text is written in Idris. MLIR is used only through the
stock, pinned LLVM tools with upstream dialects; the project has no C++.

## Current state

- `compiler/` builds `idris-mlir`, the Idris driver with a `core-inspect`
  backend. Its incremental callback writes a `.ttsummary` per module: names,
  definition kinds, pi-binder quantities, clause counts. This is an inspection
  summary, not a typed IR.
- There is no typed IR, MLIR emitter, or runtime yet.
- `tests/mlir/` checks that the pinned tools turn hand-written MLIR into a
  working executable.

## Setup

Prerequisites: Python 3.9+, Git, Make, a C compiler, a threaded Chez Scheme,
and GMP headers. The MLIR tools additionally need CMake and Ninja to build.
See [toolchain](docs/toolchain.md) for exact packages.

```sh
git submodule update --init
python3 tools/dev.py doctor
python3 tools/dev.py check                      # tooling tests
python3 tools/dev.py bootstrap-idris --scheme scheme
python3 tools/dev.py build
python3 tools/dev.py test                       # frontend integration test
python3 tools/dev.py bootstrap-llvm             # slow: pinned MLIR tools
python3 tools/dev.py test-mlir-tools
```

Everything is installed under `.toolchain/`.

## Docs

- [Architecture](docs/architecture.md)
- [Toolchain](docs/toolchain.md)
- Research notes from before the scaffold: [compiler interfaces](docs/research/compiler-interfaces.md),
  [starting point and tests](docs/research/starting-point-and-tests.md),
  [MLIR and Mojo](docs/research/mlir-and-mojo.md)

## License

[0BSD](LICENSE). The Idris 2 dependency keeps its
[upstream license](third_party/Idris2/LICENSE).
