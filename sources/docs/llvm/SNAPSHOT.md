# Snapshot: selected LLVM documentation

- **Upstream:** `llvm/llvm-project`, the `llvm/` component.
- **Revision:** llvm main at commit `7208ba24ca2894729cd394475a00d2a7b605e642`
  (`llvmorg-24-init-13225-g7208ba24ca28`, LLVM 24.0.0git), the repository's LLVM pin.
- **Fetched:** 2026-10-08, from the repository's git objects: each file re-taken with
  `git -C .toolchain/llvm-project cat-file blob 7208ba24…:llvm/<path>`. First fetched on
  2026-09-26 at tag `llvmorg-23.1.2` from
  `https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-23.1.2/`.
- **Paths:** relative to `llvm-project/llvm/` (so `docs/...`).
- **Files:** 11.
- **Licence:** Apache-2.0 WITH LLVM-exception.
- **Threads:** F, B, I.

**What is here.** `docs/LangRef.md`, `GarbageCollection.md`, `Statepoints.md`,
`ORCv2.md`, `JITLink.md`, `MCJITDesignAndImplementation.md`, `DebuggingJITedCode.md`,
`ProgrammersManual.md`, `Passes.md`, `NewPassManager.md`, `WritingAnLLVMPass.md`.

**Renamed.** Main converted five of the 2026-09-26 files from reStructuredText to Markdown:
`Statepoints.rst`, `ORCv2.rst`, `JITLink.rst`, `MCJITDesignAndImplementation.rst` and
`DebuggingJITedCode.rst` no longer exist at this revision. Each was removed and its `.md`
successor at the same path taken in its place; the other six files are the same paths as
before.

The manifest asked for LangRef, GC/Statepoints, ORC/JITLink, DataLayout, the Programmer's
Manual and Passes. **Correction:** LLVM's DataLayout has no separate file at this pin; it
is specified in `LangRef.md`.

`AIToolPolicy.md` is not from that revision, and was not re-taken. It is the page at `https://llvm.org/docs/AIToolPolicy.html`, fetched 2026-10-08. This one policy covers MLIR, Clang, and lld because they are llvm.org subprojects.
