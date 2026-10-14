# Snapshot: MLton pass sources

- **Upstream:** `MLton/mlton` on GitHub (the project site `mlton.org` is dead: no
  connection, HTTP 000).
- **Revision:** `master` at `aa2fd1ad9b91375903a4253cfcf1ea5ef2754f37`.
- **Fetched:** 2026-09-26, from
  `https://raw.githubusercontent.com/MLton/mlton/aa2fd1ad9b91375903a4253cfcf1ea5ef2754f37/<path>`.
- **Paths:** relative to the repository root (so `mlton/ssa/contify.fun`).
- **Files:** 16.
- **Licence:** MLton license (HPND-style) (verify).
- **Threads:** D, G.

**What is here.**
- `mlton/closure-convert/`: `abstract-value.fun`, `closure-convert.fun`,
  `closure-convert.sig`, `globalize.fun`, `lambda-free.fun`.
- `mlton/ssa/`: `contify.fun`, `useless.fun`, `remove-unused.fun`, `inline.fun`,
  `ssa-tree.fun`, `ssa2.fun`.
- `mlton/backend/`: `ssa2-to-rssa.fun`, `rssa.fun`, `packed-representation.fun`,
  `representation.sig`, `machine.fun`.

The manifest asked for the selected pass sources: closure conversion, the SSA passes
contify, useless and remove-unused, and the RSSA representation and layout.

**Correction.** RSSA lives under `mlton/backend/` (`ssa2-to-rssa.fun`, `rssa.fun`,
`packed-representation.fun`), not in a `mlton/rssa/` directory.

**Addendum, 2026-10-14.** For the pipeline cutover proposal
(`notes/compile-pipeline/mlton.md`), 27 more files at the same revision
`aa2fd1ad9b91375903a4253cfcf1ea5ef2754f37`, fetched from the same raw URL pattern: the
driver (`mlton/main/compile.fun`, `mlton/main/main.fun`), the controls
(`mlton/control/control.sml`, `control.sig`, `control-flags.sml`, `control-flags.sig`), the
pass lists (`mlton/xml/xml-simplify.fun`, `sxml-simplify.fun`, `mlton/ssa/simplify.fun`,
`simplify2.fun`, `mlton/backend/rssa-simplify.fun`), the passes the report reads
(`mlton/xml/shrink.fun`, `polyvariance.fun`, `monomorphise.fun`, `simplify-types.fun`,
`mlton/ssa/shrink.fun`, `introduce-loops.fun`, `loop-unroll.fun`, `known-case.fun`,
`mlton/core-ml/core-ml-simplify.fun`, `dead-code.fun`, `mlton/backend/backend.fun`,
`chunkify.fun`), the code generators (`mlton/codegen/c-codegen/c-codegen.fun`,
`mlton/codegen/llvm-codegen/llvm-codegen.fun`) and the C runtime's chunk interface
(`include/c-chunk.h`, `include/c-main.h`). `closure-convert.fun` was fetched again and is
byte-identical to the stored one. Files: 43 in all.
