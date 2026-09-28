# Working on idris-mlir

The normative spec is [docs/architecture/](docs/architecture/00-index.md).
What comes next is [docs/plan.md](docs/plan.md), the only plan; keep it
current instead of writing new plan documents.
- Before changing a compiler boundary, read 00, 01, 02, 03 and 08.
- Before any implementation work, read 16-agent-rules.md.

- Idris does types; MLIR does programs. The Idris side (the frontend and
  `Emit`) checks the profile, monomorphises and decides representations.
  The `idr` MLIR dialect and its passes (specialization, compile-time
  evaluation, defunctionalization, loops, the heap-free check, lowering) are
  C++ in `foreign/idr/`, following bjornpagen/cpp-starter as adopted in
  docs/architecture/11-toolchain.md. p0, v0, v1, v2 and v3 are implemented,
  as the cutover compiles them (docs/architecture/15-roadmap.md); `PINS.md`
  records every deliberate deviation from that C++ profile, the plan and
  the pinned upstreams.
- The compiler consumes checked Idris TT and its definition context. Do not
  replace that input with CExp or runtime case trees (only the `ZERO`/`SUCC`
  constructor flags are read from `Core.CompileExpr`, FE-IN-2), and do not
  erase facts before the passes that use them.
- No primitive has an implementation in Idris: its one meaning is the
  runtime's, which folders and compile-time evaluation call too (LOW-RT-1).
  Compile-time evaluation runs total code always and partial code never
  (SEM-EVAL-6).
- Only `IdrisMLIR.Frontend.*` may import upstream Idris compiler modules.
- third_party/Idris2 is unmodified and pinned by its gitlink. Do not edit it
  or move the pin as a side effect of other work.
- Install build dependencies under .toolchain/ through `make bootstrap`. Do
  not modify the user's global compiler installation or shell configuration.
- The compiler accepts only the current profile version
  (docs/architecture/02-profile.md). Reject anything outside it with an
  explicit `unsupported` error that names the rule; never miscompile
  silently.
- Erased does not mean constant. A linear binder does not imply unique heap
  ownership. Indexed vectors do not imply contiguous storage.
- A workaround for upstream behaviour (LLVM, MLIR, Idris) needs a bug report
  in `upstream/` (see upstream/README.md): reduce it to upstream dialects and
  tools, and add the report, its reproducer, its `tests/upstream/` check and
  its `PINS.md` entry in the same change. If it does not reproduce upstream,
  the bug is ours: fix it instead.
- Checks: `make check` always. After compiler changes, run `make build` and
  `make test`. After C++ or contract changes, also run `make test-idr`.
  After changing MLIR usage, also run `make test-mlir-tools`. If a toolchain
  is unavailable, say so; do not report skipped tests as passed.
- Tests must check exit status and produced artifacts, not just stdout.
- Research tasks produce documents only: do not build or run anything.
