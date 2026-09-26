# Working on idris-mlir

The normative spec is [docs/architecture/](docs/architecture/00-index.md).
- Before changing a compiler boundary, read 00, 01, 02, 03 and 08.
- Before any implementation work, read 16-agent-rules.md.

- The compiler front and middle end are Idris. The `idr` MLIR dialect and its
  passes are C++ in `foreign/idr/`, following bjornpagen/cpp-starter as
  adopted in docs/architecture/11-toolchain.md. No C++ exists yet; p0 creates
  it (docs/architecture/15-roadmap.md).
- The compiler consumes checked Idris TT and its definition context. Do not
  replace that input with CExp or runtime case trees, and do not erase facts
  before the passes that use them.
- Only `IdrisMLIR.Frontend.*` may import upstream Idris compiler modules.
- third_party/Idris2 is unmodified and pinned by its gitlink. Do not edit it
  or move the pin as a side effect of other work.
- Install build dependencies under .toolchain/ through tools/dev.py. Do not
  modify the user's global compiler installation or shell configuration.
- The compiler accepts only the current profile version
  (docs/architecture/02-profile.md). Reject anything outside it with an
  explicit `unsupported` error that names the rule; never miscompile
  silently.
- Erased does not mean constant. A linear binder does not imply unique heap
  ownership. Indexed vectors do not imply contiguous storage.
- Checks: `python3 tools/dev.py check` always. After compiler changes, run
  `build` and `test`. After changing MLIR usage, also run `test-mlir-tools`. If a
  toolchain is unavailable, say so; do not report skipped tests as passed.
- Tests must check exit status and produced artifacts, not just stdout.
- Research tasks produce documents only: do not build or run anything.
