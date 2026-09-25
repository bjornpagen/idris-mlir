# Working on idris-mlir

Read README.md and docs/architecture.md before changing a compiler boundary.

- The compiler is written in Idris. Do not add C++ or an MLIR dialect of our
  own. Emit MLIR as text using upstream dialects and run it through the pinned
  tools.
- The compiler consumes checked Idris TT and its definition context. Do not
  replace that input with CExp, and do not erase facts before the passes that
  use them.
- Only `IdrisMLIR.Frontend.*` may import upstream Idris compiler modules.
- third_party/Idris2 is unmodified and pinned by its gitlink. Do not edit it
  or move the pin as a side effect of other work.
- Install build dependencies under .toolchain/ through tools/dev.py. Do not
  modify the user's global compiler installation or shell configuration.
- The frontend currently emits an inspection summary, not a typed IR. Keep
  documentation and error messages accurate about that.
- Erased does not mean constant. A linear binder does not imply unique heap
  ownership. Indexed vectors do not imply contiguous storage.
- Checks: `python3 tools/dev.py check` always. After Idris changes, run
  `build` and `test`. After changing MLIR usage, run `test-mlir-tools`. If a
  toolchain is unavailable, say so; do not report skipped tests as passed.
- Tests must check exit status and produced artifacts, not just stdout.
