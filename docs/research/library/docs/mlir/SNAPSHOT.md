# Snapshot: MLIR documentation

- **Upstream:** `llvm/llvm-project`, the `mlir/` component (rendered at
  https://mlir.llvm.org/docs/).
- **Revision:** tag `llvmorg-23.1.2` = commit `2d56740342c3bd86a7525fb4c147252757589e30`.
- **Fetched:** 2026-09-26, from `https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-23.1.2/`,
  with the tree enumerated through the GitHub tree API.
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
