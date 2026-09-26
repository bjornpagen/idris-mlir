# Toolchain

Everything the project builds is installed under `.toolchain/`. Each bootstrap
writes a `provenance.json` stamp only after every step succeeds, and later
commands refuse to use a toolchain whose stamp is missing or stale.

## Prerequisites

On Ubuntu 24.04 (what upstream Idris CI uses):

```sh
sudo apt-get install -y chezscheme libgmp-dev   # Chez 9.5.8, built threaded
sudo apt-get install -y git make gcc g++ python3 # host compilers, usually present
sudo apt-get install -y libmpfr-dev libmpc-dev flex texinfo   # for bootstrap-gcc (TC-PIN-3)
```

On Apple Silicon use Chez 10 or later. If you build Chez from source, configure
it with `--threads`. Set `CPPFLAGS`/`LDFLAGS` if GMP is outside the compiler's
search paths. `python3 tools/dev.py doctor` reports what it finds.

## Idris

`third_party/Idris2` is an unmodified submodule; its gitlink is the pin.
`bootstrap-idris` builds that revision with upstream's `make bootstrap`, then
installs the compiler, libraries, and API into `.toolchain/idris2`. Idris
package variables inherited from other installations are cleared. The build
never uses an `idris2` found on `PATH`.

## GCC, CMake and Ninja

`toolchain.lock.json` (schema 3) pins GCC, CMake and Ninja by tag and
commit, and the release series the configure gate accepts. `bootstrap-gcc`,
`bootstrap-cmake` and `bootstrap-ninja` shallow-clone each tag (GCC from
its GitHub mirror), check the commit and build into `.toolchain/gcc`,
`.toolchain/cmake` and `.toolchain/ninja`. GCC is built for C and C++ only,
without bootstrap stages. The distribution compilers only build these tools.

## LLVM and MLIR

`bootstrap-llvm` shallow-clones the pinned LLVM tag into
`.toolchain/llvm-project`, checks the commit, and builds MLIR with the pinned
GCC, CMake and Ninja (native target, assertions on, no RTTI or exceptions,
rpath to the pinned GCC's `libstdc++`). It installs the libraries and CMake
packages into `.toolchain/llvm`, which the C++ `dev` preset finds, and the
tools `mlir-opt`, `mlir-translate`, `mlir-tblgen`, `opt`, `llc`, `llvm-nm`,
`FileCheck`, `not` and `count`. `lit` runs from the source tree. Clang is not
built (`PINS.md`: `lint-graph-unbuilt`). Some MLIR sources need ~5 GB of
memory each to compile, so parallel compiles are capped at one per 7 GB of
RAM. Expect several hours and ~20 GB of disk; `.toolchain/llvm-build-gcc`
can be deleted afterwards.

Distribution packages and apt.llvm.org builds track release branches, not the
pinned commit, so the project does not use them.

## C++ and the compiler

`dev.py build` configures and builds the `dev` CMake preset (the `idr`
dialect, `idris-mlir-opt`, `idris-mlir-cc`) with the pinned tools, writes
`compiler/src/IdrisMLIR/Frontend/Paths.idr` with the absolute paths of
`idris-mlir-cc` and the pinned `gcc` (the `-o` path never looks at `PATH`),
builds the Idris compiler, and installs the `idris-mlir-io` package into
`.toolchain/idris2`.

## Upgrades

Upgrade deliberately and in its own commit, never as a side effect.

- Idris: check out the new commit in the submodule and stage it. Review
  changes to `Core/TT`, `Core/Context`, `Core/TTC.idr`, `Compiler/Common.idr`,
  and `Idris/ProcessIdr.idr`. Rerun `bootstrap-idris`, `build`, and `test`.
- LLVM, GCC, CMake, Ninja: update the tag, commit, version and accepted
  series in the lock together, then work through `PINS.md` (the tombstone
  ritual). Rerun the bootstraps, `build`, `test`, `test-idr` and
  `test-mlir-tools`; pass names change between releases.
