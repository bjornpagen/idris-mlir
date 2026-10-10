# 0001: pin LLVM to a trunk commit, what remains

**Status:** decided. The pin is llvm main 7208ba24, the toolchain is one
recipe for both targets (`tools/bootstrap.sh`), and PINS.md,
`upstream/README.md`, `sources/` and proposal 0013 record the move. On
arm64 macOS, at 8395d4f7, the toolchain is built with the patches the tree
carries: `make build` passes, `make check` is 26/26, `make test-idr` is
269/269 and `make test-mlir-tools` is 17/17. `make self` (1ce907d3) builds
stages 1 to 3 and stage 2 matches stage 3. x86_64 Linux has not been built
at the pin. When that target is green, this file is deleted.

**Build and pass where it has not.** On arm64, `make test` is left with
two programs set aside: `programs/prelude/every-interfaces-export` and
`every-types-export` compile and then hit their time limits. On x86_64
Linux: `tools/bootstrap.sh llvm`
(stage 1, the target's C library, the runtimes and stage 2, into
`.toolchain/llvm`), then `make build`, `make check`, `make test`,
`make test-idr` and `make test-mlir-tools`, all green. A failure that
reproduces with upstream dialects and tools is a patch in `upstream/`;
any other is ours, fixed in the tree. The retirements PINS.md records
were observed on arm64 macOS only, and the Linux run is their check
there. The same run is proposal 0002's first remaining item.
