# Toolchain

## Idris

The Git submodule and toolchain.lock.json must agree. The lock pins the commit
that was upstream main when this repository was scaffolded. It is not a floating
branch dependency. `verify-pins` also checks the source package and TTC versions
and rejects tracked modifications inside the dependency.

`bootstrap-idris` requires an existing threaded Chez executable and GMP development
files. It builds from the pinned source and installs the compiler, libraries, and
API into `.toolchain/idris2`. A provenance file is written only after all steps
succeed. Compiler/API versions are built together; the frontend never chooses
an arbitrary `idris2` from PATH. Package-search environment variables inherited
from other installations are removed for local builds.

Host C/C++ compilers, Make, and Chez are prerequisites rather than hermetically
pinned dependencies. Record them with benchmark results. The source pins make
dependency selection reproducible; they are not a claim of bit-identical builds
across host systems.

## LLVM and MLIR

The lock records the commit behind `llvmorg-23.1.2`, the release selected for
this scaffold. CMake accepts an external MLIR development package only when
its LLVM package version matches. Build from the exact locked commit for source
provenance; the version check alone cannot distinguish patched builds.

One project-local source-build recipe, run from the repository root:

```sh
mkdir -p .toolchain
git clone --filter=blob:none --no-checkout https://github.com/llvm/llvm-project.git .toolchain/llvm-project
git -C .toolchain/llvm-project checkout --detach 85ac560262434c9ccfc0c183ec22d4138ed647fb
cmake -S .toolchain/llvm-project/llvm -B .toolchain/llvm-build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS=mlir \
  -DLLVM_TARGETS_TO_BUILD=Native \
  -DLLVM_ENABLE_ASSERTIONS=ON
cmake --build .toolchain/llvm-build
python3 tools/dev.py configure-mlir --mlir-dir .toolchain/llvm-build/lib/cmake/mlir
python3 tools/dev.py build-mlir
python3 tools/dev.py test-mlir
```

This is an optional, substantial source build. Nothing fetches/builds LLVM as
a side effect of scaffold checks or the frontend experiment.

## Intentional upgrades

For Idris, select a new exact upstream commit, update the submodule checkout
and lock metadata together, stage the submodule entry, and rebuild the local
compiler/API. Run the frontend tests and fresh-versus-cached inspection tests
before accepting the upgrade. Review TT, context, serialization, and callback
changes rather than relying only on package version numbers.

For LLVM, update the lock's tag, commit, and version together; rebuild the MLIR
driver and run its parser/transform tests. Generated output and caches should
record the compiler/schema versions once the typed interchange format exists.

## CI scope

The scaffold workflow runs dependency/tooling checks and a real frontend build
and integration test on Ubuntu with Chez. It does not build LLVM or claim MLIR
coverage. The MLIR driver has separate CTest coverage, run when the pinned
development toolchain is available. Add a cached pinned LLVM build job before
depending on changes to MLIR lowering.
