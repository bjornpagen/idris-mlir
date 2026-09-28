# Snapshot: selected LLVM documentation

- **Upstream:** `llvm/llvm-project`, the `llvm/` component.
- **Revision:** tag `llvmorg-23.1.2` = commit `2d56740342c3bd86a7525fb4c147252757589e30`.
- **Fetched:** 2026-09-26, from `https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-23.1.2/`.
- **Paths:** relative to `llvm-project/llvm/` (so `docs/...`).
- **Files:** 11.
- **Licence:** Apache-2.0 WITH LLVM-exception.
- **Threads:** F, B, I.

**What is here.** `docs/LangRef.md`, `GarbageCollection.md`, `Statepoints.rst`,
`ORCv2.rst`, `JITLink.rst`, `MCJITDesignAndImplementation.rst`, `DebuggingJITedCode.rst`,
`ProgrammersManual.md`, `Passes.md`, `NewPassManager.md`, `WritingAnLLVMPass.md`.

The manifest asked for LangRef, GC/Statepoints, ORC/JITLink, DataLayout, the Programmer's
Manual and Passes. **Correction:** LLVM's DataLayout has no separate file at this pin; it
is specified in `LangRef.md`.
