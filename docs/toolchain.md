# Toolchain

Everything the project builds is installed under `.toolchain/` by
`make bootstrap` (`tools/bootstrap.sh all`). The rules are in
[11-toolchain](architecture/11-toolchain.md); the steps, what each builds and
the environment they read are at the top of `tools/bootstrap.sh`. Each step
writes a `provenance.json` stamp only after every step succeeded, its checks
included, and later commands refuse a toolchain whose stamp is missing or
stale.

## Prerequisites

The host only builds the pinned tools (TC-PIN-3). On Ubuntu 24.04:

```sh
sudo apt-get install -y git make gcc g++ python3 m4 curl chezscheme linux-libc-dev
```

`python3` is LLVM's configure, `m4` GMP's, and Chez Scheme (built with
threads; on Apple Silicon Chez 10 or later) runs Idris. `make doctor`
reports what it finds and what is built.

## What is built

- `.toolchain/cmake`, `.toolchain/ninja`: CMake and Ninja, with the host's
  C++ compiler.
- `.toolchain/stage1`: clang and lld for x86-64, with the host's C++
  compiler; they build the next steps.
- `.toolchain/sysroot`: musl, the host's Linux UAPI headers, compiler-rt's
  builtins, libunwind, libc++abi, libc++ and GMP, for
  `x86_64-unknown-linux-musl`.
- `.toolchain/llvm-musl`: stage 2, the LLVM, MLIR, clang, lld and clang-tidy
  the C++ `dev` preset and the tests use, static on musl and libc++, with LTO.
- `.toolchain/idris2`: Idris 2 and its API, from the unmodified submodule
  `third_party/Idris2` (its gitlink is the pin), on the host's Chez Scheme.
  Idris package variables inherited from other installations are cleared,
  and the build never uses an `idris2` found on `PATH`.

Stage 1 and stage 2 take hours and tens of GB of disk; parallel jobs are
capped at one per 5 GiB of memory. Distribution packages and apt.llvm.org
builds track release branches, not the pinned commit, so the project does
not use them.

`make build` configures and builds the `dev` CMake preset (the `idr`
dialect, `idris-mlir-opt`, `idris-mlir-cc`) with the pinned tools, writes
`compiler/src/IdrisMLIR/Frontend/Paths.idr` with the absolute paths of the
pinned tools (the `-o` path never looks at `PATH`), and builds the Idris
compiler.

## Upgrades

Upgrade deliberately and in its own commit, never as a side effect.

- Idris: check out the new commit in the submodule and stage it. Review
  changes to `Core/TT`, `Core/Context`, `Core/TTC.idr`, `Compiler/Common.idr`,
  and `Idris/ProcessIdr.idr`. Rerun `make bootstrap`, `make build` and
  `make test`.
- LLVM, musl, GMP, CMake, Ninja: update the pin in `toolchain.lock.json`,
  then work through `PINS.md` (the tombstone ritual) and `upstream/`: a
  report whose test now fails was fixed upstream, and its workaround goes.
  Rerun `make bootstrap`, `make build`, `make test`, `make test-idr` and
  `make test-mlir-tools`; pass names change between releases.
