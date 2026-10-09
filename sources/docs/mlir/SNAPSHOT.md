# Snapshot: MLIR documentation

- **Upstream:** `llvm/llvm-project`, the `mlir/` component (rendered at
  https://mlir.llvm.org/docs/).
- **Revision:** llvm main at commit `7208ba24ca2894729cd394475a00d2a7b605e642`
  (`llvmorg-24-init-13225-g7208ba24ca28`, LLVM 24.0.0git), the repository's LLVM pin.
- **Fetched:** 2026-10-08, from the repository's git objects: each file re-taken with
  `git -C .toolchain/llvm-project cat-file blob 7208ba24…:mlir/<path>`. First fetched on
  2026-09-26 at tag `llvmorg-23.1.2` from
  `https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-23.1.2/`, with the tree
  enumerated through the GitHub tree API. `mlir/docs/**` holds the same 99 files at both
  revisions; 24 of the 100 files changed.
- **Paths:** relative to `llvm-project/mlir/` (so `docs/...`, `include/mlir/...`).
- **Files:** 100: all of `mlir/docs/**` and `include/mlir/Transforms/Passes.td`.
- **Licence:** Apache-2.0 WITH LLVM-exception.
- **Threads:** F, B, I.

The manifest asked for all of `mlir/docs/**`, `mlir/include/mlir/Transforms/Passes.td`, and
the dialect docs for arith, builtin, cf, func, index, linalg, llvm, memref, pdl, ptr, scf,
transform, ub and vector.

**Correction.** arith, cf, index, ptr, scf, ub and pdl have no standalone `.md` file in
`mlir/docs/Dialects/` at this pin: their docs are generated from ODS/TableGen, and the full
`docs/**` snapshot is what covers them.
