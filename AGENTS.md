# Working on idris-mlir

The code is the specification. Read it, and read the MLIR documentation and
sources (the pinned tree is in `.toolchain/llvm-project/mlir`; snapshots of
papers and upstream docs are in `sources/`) before changing how we use MLIR:
the best fix is usually an MLIR mechanism we are not using yet. Comments
explain why the code is the way it is; they do not cite documents or rule
numbers.

- Two first-class targets: x86_64 Linux (musl, static PIE) today, and
  arm64 macOS (aarch64-apple-darwin) next. The machine you build on
  happens to be x86_64; that is not the design. Nothing may assume x86,
  Linux, ELF, musl or a page size outside the one place the target is
  decided (the module's target triple and data layout, which every tool
  reads). Write each piece so the arm64 macOS port is a new target entry,
  not a rewrite: intrinsics through LLVM, no inline asm, no cpuid outside
  the target's startup check, OS calls behind the runtime's platform
  layer. Heap references stay raw, untagged addresses, which is what
  Apple's data-memory-dependent prefetcher follows.
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
- The compiler implements Idris 2 fully for programs over the upstream
  prelude and base. The other packages shipped with Idris (contrib, linear,
  network, test) are no commitment: upstream itself plans to disband
  contrib for external packages. What they covered comes from the packages
  this compiler ships in `libs/` (today `mlir-linear`: linear arrays and
  linear data), written for this compiler's analyses in plain Idris over
  base's primitives, so that the stock Chez backend runs them unchanged as
  the oracle. A trusted library may run an IO action for a pure value
  (`unsafePerformIO`, a forged world): its effects happen where the value
  is demanded, in program order with every other effect, as Chez runs
  them. User code may not.
- Only `IdrisMLIR.Frontend.*` may import upstream Idris compiler modules.
- third_party/Idris2 is unmodified and pinned by its gitlink. Do not edit it
  or move the pin as a side effect of other work.
- Install build dependencies under .toolchain/ through `make bootstrap`. Do
  not modify the user's global compiler installation or shell configuration.
- Reject what the compiler cannot compile with an explicit `unsupported`
  error that names the reason; never miscompile silently.
- No pass may drop what Idris proved: multiplicities, erasure, linearity.
  They are what this compiler exists to exploit, so they live where MLIR
  cannot lose them: in types (`!idr.erased` for quantity 0, `!idr.lin<T>`
  for quantity 1), which every transformation must keep and the verifier
  checks after every pass. A fact kept in a discardable attribute can be
  dropped silently; do not keep one there.
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
  A brittle test means a missing test API: instead of matching exact op
  sequences, write the property once as an expressive check (a helper, a
  verifier-style assertion pass) and state tests in its terms.
- Checks: `make check` always. After compiler changes, run `make build` and
  `make test`. After C++ changes, also run `make test-idr`. After changing
  MLIR usage, also run `make test-mlir-tools`. Every command a test runs
  times out, so a hang is a failure, not a wait. If a toolchain is
  unavailable, say so; do not report skipped tests as passed.
