# Pointer: MLIR `lib/` implementation trees (not vendored)

**What it is.** The C++ implementation of MLIR: the rewrite/pattern machinery, dialect
conversion, dataflow analyses, and the Transform/PDL interpreters. Only the *headers* and
TableGen interface definitions are vendored under `sources/code/mlir/`; the large `lib/`
implementation trees are pointed to here instead.

**Pin.**
- `llvm/llvm-project`, tag `llvmorg-23.1.2`, commit `2d56740342c3bd86a7525fb4c147252757589e30`.
- Raw base: `https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-23.1.2/`
- Tree listing: `https://api.github.com/repos/llvm/llvm-project/git/trees/llvmorg-23.1.2?recursive=1`
  (the recursive listing is truncated by GitHub; fetch the `mlir` subtree SHA
  `ca7b652dc7f3c9b48dc57f408c70f5229dc39363` for the complete `mlir/` tree).

**Paths deliberately not copied (large implementation trees).**
- `mlir/lib/IR/` — core IR, including `PatternMatch.cpp`, `PDL/PDLPatternMatch.cpp`.
- `mlir/lib/Transforms/` and `mlir/lib/Transforms/Utils/` — `GreedyPatternRewriteDriver.cpp`,
  `DialectConversion.cpp`, `CSE.cpp`, `Inliner.cpp`, `FoldUtils.cpp`, `RegionUtils.cpp`, …
- `mlir/lib/Analysis/` — `DataFlowFramework.cpp` and `DataFlow/*.cpp`.
- `mlir/lib/Dialect/Transform/` — the Transform dialect interpreter and extensions.
- `mlir/lib/Dialect/PDL/` and `mlir/lib/Dialect/PDLInterp/` — PDL/PDLInterp interpreters.
- `mlir/lib/Conversion/` — dialect conversion passes.
- `mlir/lib/Dialect/` — all dialect implementations (795 files at the pin).

**Why not vendored.** These trees are large and mostly implementation detail; the corpus
needs the *interfaces* (vendored) and a reproducible pointer to the *implementations*.
Fetch any single file on demand with:

```bash
curl -L --fail -o /tmp/<name>.cpp \
  "https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-23.1.2/mlir/lib/<path>"
```

**Vendored counterpart.** `sources/code/mlir/include/mlir/` holds the selected headers
(`PatternMatch.h`, `OpDefinition.h`, all `Interfaces/*.td`, `Transforms/DialectConversion.h`,
the dataflow headers, the Transform/PDL/PDLInterp headers and `.td`, and the LLVM dialect
`.td` including `LLVMOps.td`).
