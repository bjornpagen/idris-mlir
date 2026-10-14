# Snapshot: the Mojo compiler's pipeline, inliner and code generation

- **Upstream:** `modular/modular` on GitHub.
- **Revision:** `main` at `9211931` ("[Release] Pin lockfiles to Mojo 1.2.0.dev2026101405, MAX 26.7").
- **Fetched:** 2026-10-14, a shallow clone (`git clone --depth 1`) at `~/Documents/modular`,
  read only; nothing in it was built or run.
- **Paths:** relative to the repository root.
- **Files:** 17 source files and `LICENSE`.
- **Licence:** Apache License v2.0 with LLVM Exceptions, the repository's `LICENSE` (kept here);
  every file below carries Modular's Apache-2.0-with-LLVM-exception header. The repository's
  `Licenses/` directory is the MAX Community License for shipped products and does not apply to
  this source.
- **For:** the pipeline cutover proposal; the reading is `notes/compile-pipeline/mojo.md`.

**What is here.**
- The ready-set inliner: `Mojo/lib/Transforms/AutomaticInline.cpp`, with
  `Mojo/include/Mojo/TransformUtils/{CallGraphUtils.h,SCCUtils.h,InliningUtils.h}` and
  `Mojo/lib/TransformUtils/InliningUtils.cpp`.
- The pipeline: `Mojo/lib/Compiler/Pipeline/Pipeline.cpp`, `Mojo/lib/Compiler/KGENCompiler.cpp`,
  `Mojo/include/Mojo/KGENPasses.td`.
- Passes the proposal compares against ours: `Mojo/lib/Transforms/{Canonicalizer.cpp,
  EliminateDuplicateFunctions.cpp,SimplifyCF.cpp,DeadArgumentElimination.cpp}`.
- Instantiation: `Mojo/lib/Elaborator/{Elaborator.cpp,Elaborator.h}`.
- Code generation split for parallel LLVM:
  `Mojo/lib/Compiler/ObjectCompiler/{ObjectCompiler.cpp,LLVMIRUtils.cpp,KGENToLLVMPipeline.cpp}`.

A file ported into the compiler from here follows proposal 0001's porting protocol: the
Modular header kept, an SPDX line, a changes line naming `9211931`, and a PINS.md entry.
