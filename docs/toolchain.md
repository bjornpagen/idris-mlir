# Toolchain

Everything the project builds is installed under `.toolchain/`. Each bootstrap
writes a `provenance.json` stamp only after every step succeeds, and later
commands refuse to use a toolchain whose stamp is missing or stale.

## Prerequisites

On Ubuntu 24.04 (what upstream Idris CI uses):

```sh
sudo apt-get install -y chezscheme libgmp-dev   # Chez 9.5.8, built threaded
sudo apt-get install -y git make gcc python3     # usually present
sudo apt-get install -y cmake ninja-build g++    # only for bootstrap-llvm
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

## LLVM and MLIR

`toolchain.lock.json` pins the LLVM release tag and its commit.
`bootstrap-llvm` shallow-clones that tag into `.toolchain/llvm-project`,
checks the commit, builds `mlir-opt`, `mlir-translate`, `opt`, and `llc`
(MLIR enabled, native target, assertions on), and copies them to
`.toolchain/llvm/bin`. Clang is not built: the system `cc` only links the
object file that `llc` produces. Some MLIR sources need ~5 GB of memory each
to compile, so parallel compiles are capped at one per 7 GB of RAM. Expect a
few hours and ~15 GB of disk. You can delete `.toolchain/llvm-build`
afterwards.

Distribution packages and apt.llvm.org builds track release branches, not the
pinned commit, so the project does not use them.

## Upgrades

Upgrade deliberately and in its own commit, never as a side effect.

- Idris: check out the new commit in the submodule and stage it. Review
  changes to `Core/TT`, `Core/Context`, `Core/TTC.idr`, `Compiler/Common.idr`,
  and `Idris/ProcessIdr.idr`. Rerun `bootstrap-idris`, `build`, and `test`.
- LLVM: update the tag, commit, and version in the lock together. Rerun
  `bootstrap-llvm` and `test-mlir-tools`; pass names change between releases.
