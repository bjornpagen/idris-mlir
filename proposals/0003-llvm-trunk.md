# 0003: pin LLVM to a trunk commit, what remains

**Status:** decided and done but for one step. The pin is llvm main
7208ba24, the toolchain is one recipe for both targets
(`tools/bootstrap.sh`), and PINS.md, `upstream/README.md`, `sources/` and
proposal 0001 record the move. When the step below is done, this file is
deleted.

**Build and pass on each target.** No toolchain is built yet with the
patches the tree carries: the `llvm.patch` of `upstream/` 02 to 07, 09,
16 and 19 (none for Idris). The pin was first built on arm64 macOS, with
02 to 07, 09 and 15, by the earlier one-stage Darwin recipe, and passed
every suite there; x86_64 Linux has never been built at the pin. Until a
target is built, `make build` refuses on it.

On arm64 macOS and on x86_64 Linux: `tools/bootstrap.sh llvm` (stage 1,
the target's C library, the runtimes and stage 2, into `.toolchain/llvm`),
then `make build`, `make check`, `make test`, `make test-idr` and
`make test-mlir-tools`, all green. A failure that reproduces with upstream
dialects and tools is a patch in `upstream/`; any other is ours, fixed in
the tree. The retirements PINS.md records were observed on arm64 macOS
only, and this run is their check on x86_64 Linux. The same run is
proposal 0002's first remaining item.
