# Snapshot: MLIR headers and TableGen interfaces

- **Upstream:** `llvm/llvm-project`, the `mlir/` component.
- **Revision:** llvm main at commit `7208ba24ca2894729cd394475a00d2a7b605e642`
  (`llvmorg-24-init-13225-g7208ba24ca28`, LLVM 24.0.0git; the `mlir` subtree is
  `ec52aa1c2a6f38a131b8edffc6390e1c60cbc4e0`), the repository's LLVM pin.
- **Fetched:** 2026-10-08, from the repository's git objects: each file re-taken with
  `git -C .toolchain/llvm-project cat-file blob 7208ba24…:mlir/<path>`. The list is the one
  first fetched on 2026-09-26 at tag `llvmorg-23.1.2` from
  `https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-23.1.2/` and the GitHub tree
  API; every file still exists at the new revision, and 22 of the 94 changed.
- **Paths:** relative to `llvm-project/mlir/` (so `include/mlir/...`).
- **Files:** 94.
- **Licence:** Apache-2.0 WITH LLVM-exception.
- **Threads:** F, B, I.

**What is here.** `include/mlir/IR/PatternMatch.h` (which declares `RewriterBase`),
`IR/OpDefinition.h`, all `Interfaces/*.td` (27 files), `Transforms/` (dialect conversion,
the greedy pattern rewrite driver, `Passes`), the dataflow framework
(`Analysis/DataFlowFramework.h` and `Analysis/DataFlow/*`), the Transform dialect
(`Dialect/Transform/**`: IR, interfaces, transforms, utilities and the Debug, IRDL, Loop,
PDL, SMT and Tune extensions), `Dialect/PDL/IR`, `Dialect/PDLInterp/IR`, and the LLVM
dialect `.td` files including `LLVMOps.td` (tail-call and GC attributes).

The manifest asked for `PatternMatch.h`, `OpDefinition.h`, `RewriterBase.h`, the
interfaces, dialect conversion, the dataflow framework, `Transform`, `PDL`/`PDLInterp`, the
`LLVMOps.td` tail-call/GC attributes, and pointers for the large `lib/` trees.
**Correction:** `include/mlir/IR/RewriterBase.h` does not exist at this pin (nor at
`llvmorg-23.1.2`); `RewriterBase` is declared in `PatternMatch.h`, which is here.

The rest of this file was `sources/pointers/mlir-lib-trees.md`.

## Pointer: MLIR `lib/` implementation trees (not vendored)

**What it is.** The C++ implementation of MLIR: the rewrite/pattern machinery, dialect
conversion, dataflow analyses, and the Transform/PDL interpreters. Only the *headers* and
TableGen interface definitions are vendored in this folder; the large `lib/`
implementation trees are pointed to here instead.

**Pin.**
- `llvm/llvm-project`, main at commit `7208ba24ca2894729cd394475a00d2a7b605e642`.
- Local: the bootstrap's clone, `.toolchain/llvm-project`, holds the commit's objects
  (`git -C .toolchain/llvm-project show 7208ba24…:mlir/<path>`).
- Raw base: `https://raw.githubusercontent.com/llvm/llvm-project/7208ba24ca2894729cd394475a00d2a7b605e642/`
- Tree listing: `https://api.github.com/repos/llvm/llvm-project/git/trees/7208ba24ca2894729cd394475a00d2a7b605e642?recursive=1`
  (the recursive listing is truncated by GitHub; fetch the `mlir` subtree SHA
  `ec52aa1c2a6f38a131b8edffc6390e1c60cbc4e0` for the complete `mlir/` tree).

**Paths deliberately not copied (large implementation trees).**
- `mlir/lib/IR/` — core IR, including `PatternMatch.cpp`, `PDL/PDLPatternMatch.cpp`.
- `mlir/lib/Transforms/` and `mlir/lib/Transforms/Utils/` — `GreedyPatternRewriteDriver.cpp`,
  `DialectConversion.cpp`, `CSE.cpp`, `Inliner.cpp`, `FoldUtils.cpp`, `RegionUtils.cpp`, …
- `mlir/lib/Analysis/` — `DataFlowFramework.cpp` and `DataFlow/*.cpp`.
- `mlir/lib/Dialect/Transform/` — the Transform dialect interpreter and extensions.
- `mlir/lib/Dialect/PDL/` and `mlir/lib/Dialect/PDLInterp/` — PDL/PDLInterp interpreters.
- `mlir/lib/Conversion/` — dialect conversion passes.
- `mlir/lib/Dialect/` — all dialect implementations (815 files at the pin).

**Why not vendored.** These trees are large and mostly implementation detail; the corpus
needs the *interfaces* (vendored) and a reproducible pointer to the *implementations*.
Fetch any single file on demand with:

```bash
git -C .toolchain/llvm-project show 7208ba24ca2894729cd394475a00d2a7b605e642:mlir/lib/<path>
curl -L --fail -o /tmp/<name>.cpp \
  "https://raw.githubusercontent.com/llvm/llvm-project/7208ba24ca2894729cd394475a00d2a7b605e642/mlir/lib/<path>"
```

**Vendored counterpart.** `include/mlir/` in this folder holds the selected headers
(`PatternMatch.h`, `OpDefinition.h`, all `Interfaces/*.td`, `Transforms/DialectConversion.h`,
the dataflow headers, the Transform/PDL/PDLInterp headers and `.td`, and the LLVM dialect
`.td` including `LLVMOps.td`).
