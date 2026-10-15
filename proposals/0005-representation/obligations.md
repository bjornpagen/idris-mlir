# Every lane's obligations

**The engagement.**
- One checkout, `/Users/bjorn/Documents/idris-mlir`, on `main`. Seventeen other lanes edit their own files in the same tree at the same time.
- Write only the paths `ownership.json` gives your lane. Never edit, revert, reformat or "fix" any other file, even one that looks broken: name it in your report.
- No git command that writes (`add`, `commit`, `checkout`, `restore`, `reset`, `stash`, `mv`, `rm --cached`, `push`). The coordinator commits. Delete a file with plain `rm`.
- This is a hard cutover: compatibility is owed to nothing it replaces.

**What decides.**
- AGENTS.md binds you.
- `proposals/0005-representation/README.md` is the design. §2's rules (no fuel, no count refusal, fix your bugs) bind every lane, and §4's decisions name the APIs lanes share.
- Implement against those names, whether or not the lane that owns them has landed them yet. Never wait on a sibling.
- Where the README and the code disagree, the README wins. Where the README is silent, decide by `proposals/0004-compile-time/dispatch/parts/representation-first.md` (the owner's guideline, binding) and say what you decided.
- Read the pinned MLIR (`.toolchain/llvm-project/mlir`) before writing anything upstream already has.

**Representation first.** A new case changes the data until it is not special or not expressible. Never answer it with any of these:
- a flag, an option, a fallback or a second path;
- a guard that validates and discards;
- a fact in a discardable attribute;
- a name made from a counter;
- fuel.

Delete what your change makes dead, in your files. Comments say why the code is the way it is; they cite no documents, rule numbers or lane names.

**Verification here.** This machine builds no LLVM: never run `make bootstrap`, `make build`, `make test`, `make test-idr` or `make test-mlir-tools`.
- **C++:** run `python3 proposals/0004-compile-time/check-units.py <your .cpp files>`, which runs the typecheck build's compile commands, syntax only.
  - Headers generated from a sibling's ODS may be stale. When an error is only a missing contract name, regenerate privately: `mlir-tblgen` from `.toolchain/build/typecheck-llvm/bin`, with `-I .toolchain/build/llvm-project/mlir/include -I foreign/idr/include`, into a `/tmp` directory placed first on the include path.
  - Report which errors were the sibling's names.
  - A new unit is not in the build until the coordinator adds it. Compile it with a sibling unit's command from `build/typecheck/compile_commands.json`.
- **Idris:** typecheck a private copy of `compiler/src` under `/tmp` with `.toolchain/idris2/bin/idris2`, after `root=$PWD; . tools/toolchain.sh`. Set `CHEZ=.toolchain/chez/bin/scheme` before running anything.
- **Specs:** a `tests/spec/<name>/run` may be run with `IDRIS_MLIR_ROOT=$PWD sh tests/spec/<name>/run`.
- Never run `make typecheck` or `make check`: they write the shared build directory. The coordinator runs them.

**Your report** is your final message: plain text, no preamble. Give:
1. the paths you changed, created or deleted, and any unit to add to or remove from a build list;
2. each README decision and §7 bug in your lane: done, or not done with the reason;
3. every fuel site and to-a-fixpoint loop you removed;
4. what you decided where the README was silent;
5. what another lane must do for your code to compile or be right, naming the lane and the exact API;
6. what you ran and its result.
