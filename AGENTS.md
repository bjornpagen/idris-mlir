# Working on idris-mlir

Read README.md and docs/architecture.md before changing a compiler boundary.

- The compiler front and middle are Idris. Whether MLIR dialects and passes
  of our own (C++) are worth it is an open research question
  (docs/research/next-research-prompt.md). Do not add C++ until that research
  recommends it and the user agrees. Until then, emit MLIR text in upstream
  dialects and run it through the pinned tools.
- The compiler consumes checked Idris TT and its definition context. Do not
  replace that input with CExp, and do not erase facts before the passes that
  use them.
- Only `IdrisMLIR.Frontend.*` may import upstream Idris compiler modules.
- third_party/Idris2 is unmodified and pinned by its gitlink. Do not edit it
  or move the pin as a side effect of other work.
- Install build dependencies under .toolchain/ through tools/dev.py. Do not
  modify the user's global compiler installation or shell configuration.
- The backend supports a small subset (see README). Reject anything outside
  it with an explicit `unsupported` error; never miscompile silently.
- Erased does not mean constant. A linear binder does not imply unique heap
  ownership. Indexed vectors do not imply contiguous storage.
- Checks: `python3 tools/dev.py check` always. After compiler changes, run
  `build` and `test`. After changing MLIR usage, also run `test-mlir-tools`. If a
  toolchain is unavailable, say so; do not report skipped tests as passed.
- Tests must check exit status and produced artifacts, not just stdout.
