# Working on idris-mlir

The code is the specification. Read it, and read the MLIR documentation and
sources (the pinned tree is in `.toolchain/llvm-project/mlir`; snapshots of
papers and upstream docs are in `sources/`) before changing how we use MLIR:
the best fix is usually an MLIR mechanism we are not using yet. Comments
explain why the code is the way it is; they do not cite documents or rule
numbers.

- Idris does types; MLIR does programs. The Idris side (`compiler/`: the
  frontend and `Emit`) checks what the compiler accepts, monomorphises and
  decides representations. The `idr` dialect and its passes
  (specialization, compile-time evaluation, defunctionalization, loops, the
  heap-free check, lowering) are C++ in `foreign/idr/`, following
  bjornpagen/cpp-starter; `PINS.md` records every deliberate deviation from
  it and every pinned workaround.
- The compiler consumes checked Idris TT and its definition context. Do not
  replace that input with CExp or runtime case trees, and do not erase facts
  before the passes that use them.
- No primitive has an implementation in Idris: its one meaning is the
  runtime's (`runtime/`), which folders and compile-time evaluation call
  too. Compile-time evaluation follows upstream Idris 2: every closed call of
  pure code is evaluated, total code to the end, partial code within a
  budget, after which the call stays for runtime.
- Only `IdrisMLIR.Frontend.*` may import upstream Idris compiler modules.
- third_party/Idris2 is unmodified and pinned by its gitlink. Do not edit it
  or move the pin as a side effect of other work.
- Install build dependencies under .toolchain/ through `make bootstrap`. Do
  not modify the user's global compiler installation or shell configuration.
- Reject what the compiler cannot compile with an explicit `unsupported`
  error that names the reason; never miscompile silently.
- Erased does not mean constant. A linear binder does not imply unique heap
  ownership. Indexed vectors do not imply contiguous storage.
- A workaround for upstream behaviour (LLVM, MLIR, Idris) needs a bug report
  in `upstream/` (see upstream/README.md): reduce it to upstream dialects and
  tools, and add the report, its reproducer, its `tests/upstream/` check and
  its `PINS.md` entry in the same change. If it does not reproduce upstream,
  the bug is ours: fix it instead.
- Tests check behaviour: exit status, produced artifacts, the property a
  pass guarantees. Not clone numbers, function order or SSA names. A test
  that goes stale on an unrelated change was a bad test; fix or delete it.
- Checks: `make check` always. After compiler changes, run `make build` and
  `make test`. After C++ changes, also run `make test-idr`. After changing
  MLIR usage, also run `make test-mlir-tools`. Every command a test runs
  times out, so a hang is a failure, not a wait. If a toolchain is
  unavailable, say so; do not report skipped tests as passed.
