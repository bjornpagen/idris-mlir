<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
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
- Everything we build is linked statically: our tools, every program, and
  the toolchain's LLVM. On macOS it may also link the operating system's
  own shared libraries (/usr/lib, /System/Library: libSystem and the like),
  which is the only form macOS ships them in; never a shared library of
  ours or of a third party, and never the system's libc++, since the
  pinned libc++ is static. Nothing of ours is loaded at run time or looked
  up with dlopen. On Linux every executable is a static PIE.
  `tools/bootstrap.sh` refuses an executable that breaks this, and
  `tests/toolchain/static-linking` checks our tools and programs. The
  exception is the host side of the frontend: Idris 2 and the test runner
  run on Chez Scheme, which loads Idris's support library (PINS.md
  `idris-support-host-cc`).
- Idris does types; MLIR does programs. The Idris side (`compiler/`: the
  frontend and `Emit`, on the fork of Idris's compiler in `compiler/idris`)
  checks what the compiler accepts, monomorphises and decides
  representations. The `idr` dialect and its passes
  (specialization, defunctionalization, loops, the
  heap-free check, lowering) are C++ in `foreign/idr/`, an in-tree MLIR
  dialect in upstream's layout and conventions; `PINS.md` records every
  deliberate deviation from it and every pinned workaround.
- The Idris side compiles under two hosts, always: upstream's Idris on Chez
  Scheme, which may compile it however it chooses but must compile and run
  it, and idris-mlir itself. This holds for the frontend, the fork, `libs/`
  and the Idris test machinery, so all of it is written in the subset
  idris-mlir compiles and uses nothing only one host has. Linearity is a
  performance property, never a correctness one: a linear program means the
  same under both hosts, and idris-mlir's optimizations of it (update in
  place, no counting) only make it faster. A primitive of `libs/` (an
  `%extern`) means only what `runtime/` says, so a program that reaches one
  runs under idris-mlir alone, and nothing the stock host runs reaches one.
  What the stock host runs uses only definitions with bodies, which
  idris-mlir may replace with a runtime op through the registry's `Faster`
  hook: the body is the one meaning, and removing the hook leaves the same
  result. A building stage may use either host, but neither is dropped.
  Neither host is given an escape hatch to compile it: a trust the frontend
  takes in Idris's compiler is stated in the fork, which is Idris's compiler,
  and one it takes in itself is `covering`, never asserted.
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
  runtime's (`runtime/`), which folders call too. A closed call runs at
  run time. Static normalization (proposal 0011) is what would fold one,
  and it is not built.
- The compiler implements the Idris 2 it can compile to the code a
  monomorphic program would be: every construct whose runtime choices
  (the types, instances, implementations or shapes a site can meet) form a
  set the whole program fixes, which specialization, closed sums and
  defunctionalization compile away. That
  covers programs over the upstream prelude and base. A megamorphic
  construct, whose set at a site no compile-time analysis bounds (an
  implementation chosen by a runtime value, a recursion that builds its
  type deeper at each call), is not Idris this compiler supports: it is
  refused with an `unsupported` error that names the site and the value
  whose set is unbounded, never compiled to a uniform boxed form. The
  other packages shipped with Idris (contrib, linear,
  network, test) are no commitment: upstream itself plans to disband
  contrib for external packages. What they covered comes from the packages
  this compiler ships in `libs/` (`mlir-array`: shaped arrays, linear
  arrays and the growable vector; `mlir-linear`: linear data), written for this compiler's analyses in plain Idris over
  base's primitives, and over runtime primitives (`%extern`) where only
  programs use an operation. A trusted library may run an IO action for a pure
  value (`unsafePerformIO`, a forged world): its effects happen where the
  value is demanded, in program order with every other effect. User code
  may not.
- There is no oracle. A test's committed expected files are its
  specification, and the runtime's documented semantics are the meaning of
  a primitive. Do not add a comparison against Idris's Chez backend or
  stock evaluator, and do not shape a feature so that Chez can run it; Chez
  is only the host Idris itself runs on.
- `%foreign` and the C ABI are outside the language, as threads, collector
  finalizers and raw pointers are. Do not implement `%foreign`, `%extern`
  as a C export, a C calling convention, libffi, or declaring or calling a
  C symbol from user code. The refusal is `unsupported` and names
  `%foreign` or the extern; never ignore the pragma. A `Data.Buffer`
  operation is a runtime primitive, with its one meaning in `runtime/`. There
  is no C interop now or later: the one foreign world planned is Rust
  (proposal 0021), and a C library is reached only through a Rust `-sys`
  crate and the safe crate over it.
- Only `IdrisMLIR.Frontend.*` may import the fork of Idris's compiler
  (`compiler/idris`), and the fork never imports `IdrisMLIR.*`.
- third_party/Idris2 is unmodified and pinned by its gitlink. Do not edit it
  or move the pin as a side effect of other work; a patch to Idris applies
  to the copy the bootstrap builds, never to the checkout.
- Install build dependencies under .toolchain/ through `make bootstrap`. Do
  not modify the user's global compiler installation or shell configuration.
  The LLVM umbrella projects (llvm-project), modular and Idris 2 track main;
  every other dependency is pinned to its latest release.
- Reject what the compiler cannot compile with an explicit `unsupported`
  error that names the reason; never miscompile silently.
- Acceptance is a property of the program, never of the optimizer. Every
  analysis a refusal rests on is total on the programs the frontend
  admits: defunctionalization makes every closure set of the closed,
  monomorphic module a sum, and the only refusals are the frontend's, each
  naming a construct whose choices no compile-time analysis bounds, and
  two of constructs outside the language's memory model, each on a total
  analysis: a reference knot counting could never free, and a library's
  in-place promise exclusivity cannot meet. Every refusal's rule carries
  its category in ODS, and no representation limit refuses a program: a
  limit is lifted by a representation.
  Inlining, specialization, constant propagation and every other pass that
  only makes code faster or smaller terminate by construction (a fixed
  sequence, a bottom-up order) and may stop at a budget; a spent budget
  leaves the program less optimized and never rejects it. A round count, a
  fixpoint that has to be reached, or any other count is never a reason to
  refuse a program.
- No pass may drop what Idris proved: multiplicities, erasure, linearity.
  They are what this compiler exists to exploit, so they live where MLIR
  cannot lose them. What Idris erased (quantity 0) is no value of the
  module: the frontend emits no parameter, field or argument for it.
  Quantity 1 is a type, `!idr.lin<T>`, which every transformation must
  keep and the verifier checks after every pass. A fact kept in a
  discardable attribute can be dropped silently; do not keep one there.
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
  when the pin moves past upstream's fix, or when nothing in the tree
  reaches the bug any more, its report kept as a submission (see
  upstream/README.md). The fork
  of Idris's compiler (`compiler/idris`) is ours: a bug in its upstream
  code is fixed there, as its own code, recorded in `PINS.md`, with the
  change against the pin in `upstream/<bug>/pull-request.diff` for the
  re-sync to read, and the fix goes when a re-sync of the fork brings
  upstream's. Nothing is sent to Idris: it takes no contribution written
  with generative AI or a coding agent (upstream/README.md). A patch to the stock Idris is only for what
  it still builds (the fork, the frontend, the test runner).
- Tests check behaviour: exit status, produced artifacts, the property a
  pass guarantees. Not clone numbers, function order or SSA names. A test
  that goes stale on an unrelated change was a bad test; fix or delete it.
  A brittle test means a missing test API: instead of matching exact op
  sequences, write the property once as an expressive check (a helper, a
  verifier-style assertion pass) and state tests in its terms.
- Checks: `make check` always. After compiler changes, run `make build` and
  `make test`. After C++ changes, also run `make test-idr` and
  `make test-unit`. After changing
  MLIR usage, also run `make test-mlir-tools`. Every command a test runs
  times out, so a hang is a failure, not a wait. If a toolchain is
  unavailable, say so; do not report skipped tests as passed.
