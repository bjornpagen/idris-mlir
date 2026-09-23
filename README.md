# idris-mlir

An experimental compiler from checked Idris 2 TT to MLIR. The goal is to turn
the information established by Idris's type system into less runtime work.

This is a separate compiler project. Idris supplies its existing frontend via
the compiler API. Our adapter will preserve useful checked information in an
IR we own, before specialization, representation selection, and runtime erasure.

## Current scope

- An unmodified Idris 2 Git submodule pinned to upstream main at
  `1c630e67c386629a0fbbc6b78a59176fde7f0a76`.
- An Idris frontend adapter using the existing incremental module callback to
  write deterministic `.ttsummary` inspection files before TTC serialization.
- A small C++ `idris-mlir-opt` driver accepting the standard `arith` and `func`
  dialects, with standard transformation passes.
- Tests for the inspection callback and MLIR driver, plus dependency checks.

The summary is **not a complete typed export**. There is no Idris-to-MLIR
translation, custom dialect, native Idris code generation, or runtime yet.
Compilation/execution through the inspection backend intentionally reports an
error. The frontend and MLIR driver are separate scaffold components.

## Dependencies

`toolchain.lock.json` records exact Idris and LLVM/MLIR source revisions. Git's
submodule entry independently records the Idris revision. Ordinary builds never
advance either pin. The LLVM baseline is release `llvmorg-23.1.2`; LLVM source
is not downloaded automatically.

The frontend build needs Python 3.9+, Git, Make, a C compiler, a threaded Chez
Scheme, and GMP headers/libraries. On Apple Silicon use Chez 10 or later.
The MLIR build separately needs CMake 3.20+, Ninja, a C++17 compiler, and an
LLVM/MLIR development build matching the lock. No global package installation
is performed by project tooling.

## Start here

From the repository root:

```sh
git submodule update --init --recursive
python3 tools/dev.py doctor
python3 tools/dev.py check
```

`doctor` reports dependency availability; `check` validates pins and runs the
Python tooling tests. Neither builds or tests the Idris/C++ components.

Build Idris and its API into this repository's `.toolchain/idris2` prefix:

```sh
python3 tools/dev.py bootstrap-idris --scheme /absolute/path/to/scheme
python3 tools/dev.py build-frontend
python3 tools/dev.py test-frontend
```

The bootstrap uses the pinned source, then installs the matching API. Its build
outputs live in the submodule's ignored build directories and `.toolchain/`.
Set `CPPFLAGS`/`LDFLAGS` if GMP is outside the compiler's search paths. The
frontend package depends on `idris2`, which is the package name declared in
upstream's `idris2api.ipkg`.

The tests run the no-Prelude vector fixture in a temporary directory, check its
summary, preserve a warm cache, and check failure behavior. They do not alter
upstream tests or their caches. See [the frontend guide](frontend/README.md).

## Build the MLIR scaffold

Use an LLVM/MLIR build from the locked revision. See
[toolchain setup](docs/toolchain.md) for a source-build recipe.

```sh
python3 tools/dev.py configure-mlir --mlir-dir /absolute/path/to/lib/cmake/mlir
python3 tools/dev.py build-mlir
python3 tools/dev.py test-mlir
```

CMake checks the exact LLVM package version. Reproducing the exact source build
also requires using the locked Git revision; a package version alone does not
prove source provenance.

## Design and next milestone

- [Architecture and boundaries](docs/architecture.md)
- [Toolchain and dependency upgrades](docs/toolchain.md)
- [Inspected upstream interfaces](docs/research/compiler-interfaces.md)
- [Existing tests and the first experiment](docs/research/starting-point-and-tests.md)
- [MLIR and Mojo research](docs/research/mlir-and-mojo.md)

Next: extend the inspector from signature/quantity summaries to checked clauses
and constructor index relationships, compare fresh and cached imports, and
define the first typed export. No performance claim is made by this scaffold.

## License

Project code is licensed under [0BSD](LICENSE). The Idris 2 dependency retains
its [upstream license](third_party/Idris2/LICENSE).
