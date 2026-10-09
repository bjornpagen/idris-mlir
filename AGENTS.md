# Working on idris-mlir

The code is the specification. Read it, and read the MLIR documentation and
sources (the pinned tree is in `.toolchain/llvm-project/mlir`; snapshots of
papers and upstream docs are in `sources/`) before changing how we use MLIR:
the best fix is usually an MLIR mechanism we are not using yet. Comments
explain why the code is the way it is; they do not cite documents or rule
numbers.

- Two first-class targets: x86_64 Linux (musl, static PIE) and arm64
  macOS (aarch64-apple-darwin, PIE on libSystem). Neither is the
  default and neither is the port: one recipe builds the toolchain on
  either (`tools/bootstrap.sh`), and a change, a toolchain bump included,
  is done when it builds and passes on both. Nothing may assume x86,
  Linux, ELF, musl or a page size outside the one place the target is
  decided (the module's target triple and data layout, which every tool
  reads, from the target's entry in CMakeLists.txt; for the toolchain,
  the bootstrap's target section). Per-target cases elsewhere are bugs.
  A new target is a new entry, not a rewrite: intrinsics through LLVM,
  no inline asm, no cpuid outside the target's startup check, OS calls
  behind the runtime's platform layer. Heap references stay raw, untagged
  addresses, which is what Apple's data-memory-dependent prefetcher
  follows.
- Idris does types; MLIR does programs. The Idris side (`compiler/`: the
  frontend and `Emit`) checks what the compiler accepts, monomorphises and
  decides representations. The `idr` dialect and its passes
  (specialization, compile-time evaluation, defunctionalization, loops, the
  heap-free check, lowering) are C++ in `foreign/idr/`, following
  bjornpagen/cpp-starter; `PINS.md` records every deliberate deviation from
  it and every pinned workaround.
- One thing, one representation. A concept the compiler holds twice (the
  dialect's ops, types or primitives mirrored on the Idris side, a fact kept
  in a type and again in an attribute, one analysis computed in two places)
  drifts until the copies disagree, and every new case then costs a branch
  in each. Generate the second copy from the first, or delete it. When a new
  case shows up, change the data and its invariants until the case is no
  longer special, or no longer expressible, before adding a branch, a flag
  or a guard.
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
  base's primitives. A trusted library may run an IO action for a pure
  value (`unsafePerformIO`, a forged world): its effects happen where the
  value is demanded, in program order with every other effect. User code
  may not.
- There is no oracle. A test's committed expected files are its
  specification, and the runtime's documented semantics are the meaning of
  a primitive (`findings/decision-no-oracle.md`). Do not add a comparison
  against Idris's Chez backend or stock evaluator, and do not shape a
  feature so that Chez can run it; Chez is only the host Idris itself runs
  on.
- `%foreign` and the C ABI are outside the language, as threads, collector
  finalizers and raw pointers are. Do not implement `%foreign`, `%extern`
  as a C export, a C calling convention, libffi, or declaring or calling a
  C symbol from user code. The refusal is `unsupported` and names
  `%foreign` or the extern; never ignore the pragma. A `Data.Buffer`
  operation is a runtime primitive, with its one meaning in `runtime/`. There
  is no C interop now or later: the one foreign world planned is Rust
  (proposal 0001), and a C library is reached only through a Rust `-sys`
  crate and the safe crate over it.
- Only `IdrisMLIR.Frontend.*` may import upstream Idris compiler modules.
- third_party/Idris2 is unmodified and pinned by its gitlink. Do not edit it
  or move the pin as a side effect of other work; a patch to Idris applies
  to the copy the bootstrap builds, never to the checkout.
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
- A bug in a pinned upstream (LLVM, MLIR, clang, lld, Chez Scheme, Idris) is
  fixed in that upstream, by a patch to its source, not worked around in
  ours: a workaround hides the bug from upstream, drifts from it, and every
  pass written after it has to know it. Reduce it to upstream dialects and
  tools first; if it does not reproduce there, the bug is ours: fix it.
  Prefer upstream's own fix, backported, to one of ours. The patch lives
  with the bug's report as `upstream/<bug>/<project>.patch`, and
  `tools/bootstrap.sh` applies it to the pinned source it builds; add the
  report, the reproducer, the patch, its `tests/upstream/` check and its
  `PINS.md` entry in the same change, and delete the workaround it
  replaces. Every patch has a written plan to upstream it (where it goes,
  the upstream test, its status); sending it is separate work. A patch goes
  when the pin moves past upstream's fix (see upstream/README.md).
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
