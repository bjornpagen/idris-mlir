<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Working on idris-mlir

The code is the specification. Read it, and read the MLIR documentation and
sources (the pinned tree is in `.toolchain/llvm-project/mlir`; snapshots of
papers and upstream docs are in `sources/`) before changing how we use MLIR:
the best fix is usually an MLIR mechanism we are not using yet. Comments
explain why the code is the way it is; they do not cite documents or rule
numbers.

Representation first is the lens every change is judged by: "This document
outlines the philosophy and it's extremely important" (the owner,
2026-10-21). Read `.claude/skills/representation-first/SKILL.md` in full
before the first edit, and `.claude/skills/testing-by-search/SKILL.md`
before touching a test; every agent that edits code reads them too. A
handoff names, per obligation, the state made unrepresentable, the check
moved to a boundary or the branch deleted, or why the case is essential.

The rules are the owner's; a quoted, dated one is in the owner's words. A
"never" line is something this tree did, with its evidence: a commit, or
a P0 audit finding (`NN §s`, `NN ID`: `audits/p0/NN-*.md`; synthesis A to
E and the design documents: `audits/p0/synthesis/`, `audits/p0/design/`).

## The owner, and how work is done

- Architectural choices go to the owner before they are recorded: which
  op or type holds a fact, an API's shape, an engine, a reversal. An
  agent's choice is never written down as settled, and a recorded design
  is reversed only by a dated ruling of the owner, named in the commit
  that carries it out. Never: designs reversed by agents with no rule
  written, so the next change had nothing to keep (exclusivity put on
  `DataFlowSolver` by 595ed341 and taken off by ffa91113; the static
  lifetime cut over and taken out within a day, 467fa2f5 to c4d38e9b;
  lane 20 §4.1). The reversals that held were rulings written down the
  day they were made (19fe1332, 57bf8e1d, 7203ef2e).
- Decisions go to the owner one at a time, each with its full context,
  and the next waits until it is settled: "i cannot handle multiple issues
  at once, human must have full context for each issue before continuing"
  (2026-10-21). Say plainly what each option costs, what it buys and who
  pays.
- The coordinator resolves what AGENTS.md, strong agreement of the
  evidence or elegance settles, and records each decision with its reason,
  apart from the owner's rulings and open to their review. The owner alone
  decides the language's meaning, promises to users, scope between
  proposals, other agents' work, and contested core shapes (2026-10-21).
- Research comes before code: outside our code first, then our code
  against it. P0 (`proposals/0000-mlir-native.md`) comes before everything
  else in the queue, and no code of it is written until the owner approves
  the whole plan (2026-10-21).
- Hard cutover, hard culling: "it should always be a hard cutover, hard
  culling of the old code, maximally churning it to get the maximally
  elegant representation" (2026-10-21); "don't be afraid to churn massive
  portions of the codebase to be representation first to map well onto
  MLIR" (2026-10-17). A change replaces the old form in the same change: no
  shim, alias, re-export, dual path, fallback, compatibility flag or
  "remove later"; it deletes the dead code, dead tests and stale comments
  it leaves. Never: two implementations behind an option, "a
  behavior-selecting pass option with the rounds kept as fallback is
  fallback/configuration slop this compiler does not carry" (the owner's
  call, 2026-10-14, 57bf8e1d, striking 552d682a).
- A change is done when it is built, run and passes its checks (the last
  section) on all four targets. Type-checked is not built, and built is
  not run. Never: waves landed type-checked and unrun, 10-14 to 10-18
  (c7aa7b62, d06ed15c, 2c042728 among them); `make test` was 415/415 on
  10-14 and still not green on 10-21 (lane 20 §2.3, L2). Never: a landing
  whose message says "the program suite has not been rerun" (101edbc5:
  `make test` fell from 470/480 to 403/480 until 0be4e660).
- A claim carries its ground (read, measured, recalled, conjecture,
  decision: proposals/README.md), and a number its measure, build and
  input. Never: a jetsam footprint (627 GB), an RSS at a kill (43 GB), a
  process stopped by hand (52 GB) and a debug-build fixture (1.3 s) in one
  table of walls (21 P-18); a removal resting on an unmeasured claim
  (16005000; 21 P-9).

## The targets and the build

- Four first-class targets: arm64 macOS (aarch64-apple-darwin, PIE on
  libSystem), arm64 Linux with 16 KiB pages, arm64 Linux with 4 KiB
  pages, and x86_64 Linux (each PIE on glibc). None is the default and
  none is the port: one recipe builds the toolchain on any of them
  (`tools/bootstrap.sh`), and a change, a toolchain bump included, is
  done when it builds and passes on all four. Nothing may assume x86,
  arm64, Linux, ELF, glibc or a page size outside the one place the
  target is decided (the module's target triple and data layout, which
  every tool reads, from the target's entry in CMakeLists.txt, chosen by
  the triple and the page size; for the toolchain, the bootstrap's
  target section). Per-target cases elsewhere are bugs. A new target is
  a new entry, not a rewrite: intrinsics through LLVM, no inline asm, no
  cpuid outside the target's startup check, OS calls behind the runtime's
  platform layer. Heap references stay raw, untagged addresses, which is
  what Apple's data-memory-dependent prefetcher follows. Never: a fold
  falling back to the build machine's triple (03 O-81); the host's
  `sizeof` of a runtime header in the lowering (11 I-CV10).
- Every target links the operating system's own C library dynamically
  and nothing else shared: libSystem on macOS (/usr/lib, /System/Library:
  libSystem and the like, the only form macOS ships them in), glibc on
  Linux, whichever the build machine has, as the macOS SDK is. Everything
  we build is otherwise linked statically: our tools, every program, and
  the toolchain's LLVM; never a shared library of ours or of a third
  party, and never the system's libc++, since the pinned libc++ is
  static. Nothing of ours is loaded at run time or looked up with dlopen.
  `tools/bootstrap.sh` refuses an executable that breaks this, and
  `tests/static-linking` checks our tools and programs. The exception is
  the host side of the frontend: Idris 2 and the test runner run on Chez
  Scheme, which loads Idris's support library (PINS.md
  `idris-support-host-cc`).
- Install build dependencies under .toolchain/ through `make bootstrap`. Do
  not modify the user's global compiler installation or shell
  configuration. The LLVM umbrella projects (llvm-project), modular and
  Idris 2 track main; every other dependency is pinned to its latest
  release.

## What the compiler accepts, and what it means

- A strict subset of Idris 2, never a contradiction: "we already decided
  that we should support a strict SUBSET of upstream idris. but that
  doesn't mean we should ever support CONTRADICTORY flags or default
  pragma behaviors"; "upstream is not the ORACLE, it's the philosophy ...
  we are still an idris 2 compiler. we may even be MORE CORRECT than
  upstream. but we must never change the meaning of upstream concepts"
  (2026-10-21). The compiler may refuse a program upstream accepts; a
  program it accepts means what upstream's language says, and every flag,
  pragma and default (`partial`, `covering`, `total`, `%default`,
  `--total`) means what it means upstream. Where upstream's compiler
  departs from its own language, we keep the language. Never: taking its
  optimizer's choices as the meaning, as its inliner deleting an unused
  pure `let` that eager evaluation runs (`Inline.idr:200-206`).
- Eager evaluation is the meaning: "arguments to functions are evaluated
  before the function itself" (`docs/source/tutorial/typesfuns.rst:704`).
  An unused computation in partial code is evaluated, so its crash or
  endless loop happens; deleting it would give unused values a lazy
  meaning the language lacks. Only totality, as upstream defines it,
  licenses deletion: a function proved `total` carries no divergence
  effect, may be deleted when unused, and is lowered with `mustprogress`.
  A statically certain crash (a constant zero divisor) is a plain crash
  where evaluation reaches it, with no run-time test. Totality is not made
  mandatory: that would refuse most real programs (2026-10-21).
- There is no oracle. A test's committed expected files are its
  specification, and the runtime's documented semantics are the meaning of
  a primitive. Do not add a comparison against Idris's Chez backend or
  stock evaluator, and do not shape a feature so that Chez can run it;
  Chez is only the host Idris itself runs on.
- The compiler implements the Idris 2 it can compile to the code a
  monomorphic program would be: every construct whose runtime choices
  (the types, instances, implementations or shapes a site can meet) form
  a set the whole program fixes, which specialization, closed sums and
  defunctionalization compile away; that covers programs over the upstream
  prelude and base. A megamorphic construct, whose set at a site no
  compile-time analysis bounds (an implementation chosen by a runtime
  value, a recursion that builds its type deeper at each call), is not
  Idris this compiler supports: it is refused with an `unsupported` error
  that names the site and the value whose set is unbounded, never compiled
  to a uniform boxed form. Idris's other packages (contrib, linear,
  network, test) are no commitment (upstream plans to disband contrib);
  what they covered comes from `libs/` (`mlir-array`: shaped arrays,
  linear arrays, the growable vector; `mlir-linear`: linear data), written
  for this compiler's analyses in plain Idris over base's primitives, and
  over runtime primitives (`%extern`) where only programs use an
  operation. A trusted library may run an IO action for a pure value
  (`unsafePerformIO`, a forged world): its effects happen where the value
  is demanded, in program order with every other effect. User code may
  not.
- Reject what the compiler cannot compile with an explicit `unsupported`
  error that names the reason; never miscompile silently. Never: no stack
  probes, so a frame larger than the 1 MiB guard lands in the signal stack
  below it (read, 18 R-STK-1, R-STK-2); a solve's answer dropped in
  release behind `[[maybe_unused]]` and an `assert` (10 R-2).
- Acceptance is a property of the program, never of the optimizer. Every
  analysis a refusal rests on is total on the programs the frontend
  admits: defunctionalization makes every closure set of the closed,
  monomorphic module a sum, and the only refusals are the frontend's, each
  naming a construct whose choices no compile-time analysis bounds, and
  two of constructs outside the language's memory model, each on a total
  analysis: a reference knot counting could never free, and a library's
  in-place promise exclusivity cannot meet. Every refusal's rule carries
  its category in ODS, and no representation limit refuses a program: a
  limit is lifted by a representation. Inlining, specialization, constant
  propagation and every other pass that only makes code faster or smaller
  terminate by construction (a fixed sequence, a bottom-up order) and may
  stop at a budget; a spent budget leaves the program less optimized and
  never rejects it. A round count, a fixpoint that has to be reached, or
  any other count is never a reason to refuse a program. Never: a round
  budget that refused (`max-rounds`, until c7aa7b62 and the owner's ruling
  in 19fe1332); valid programs refused because the TTC dropped a `let`'s
  type (17 FB-01); a refusal an optimization can add or remove (read: the
  in-place promise binds only where reuse recycled the cell, 08 NQ1).
- No primitive has an implementation in Idris: its one meaning is the
  runtime's (`runtime/`), which folders call too. A closed call runs at
  run time. Static normalization (proposal 0010) is what would fold one,
  and it is not built.
- `%foreign` and the C ABI are outside the language, as threads, collector
  finalizers and raw pointers are. Do not implement `%foreign`, `%extern`
  as a C export, a C calling convention, libffi, or declaring or calling a
  C symbol from user code. The refusal is `unsupported` and names
  `%foreign` or the extern; never ignore the pragma. A `Data.Buffer`
  operation is a runtime primitive, with its one meaning in `runtime/`.
  There is no C interop now or later: the one foreign world planned is
  Rust (proposal 0020), and a C library is reached only through a Rust
  `-sys` crate and the safe crate over it.

## One fact, held once

- One thing, one representation. A concept the compiler holds twice (the
  dialect's ops, types or primitives mirrored on the Idris side, a fact
  kept in a type and again in an attribute, one analysis computed in two
  places) drifts until the copies disagree, and every new case then costs
  a branch in each. Generate the second copy from the first, or delete it;
  a copy kept in step by a verifier is still a copy. When a new case shows
  up, change the data and its invariants until the case is no longer
  special, or no longer expressible, before adding a branch, a flag or a
  guard. Never: Euclidean division written in the folder, the lowering
  and the runtime (03 O-47); `Idr_Decides` restating
  `RegionBranchOpInterface`, kept in step by a `verifyTrait` run per region
  per verification (101edbc5; 21 P-5); a guard filtering a state the
  representation still allows (9db9813d; 21 P-15).
- NO FACT KNOWN STATICALLY, RIGHT NOW OR IN PRINCIPLE, MAY EVER BE PAID FOR
  AT RUNTIME (the owner, 2026-10-21): not when the compiler runs, and not
  when a compiled program runs. A fact that TableGen, the compiler's
  build, a pass's construction, an earlier pass, Idris's type checker or a
  type already knows is never recomputed, re-derived, looked up, tested,
  string-compared, hashed or rebuilt; and a fact some earlier stage knew,
  or could have kept, counts as known: throwing it away and deriving it
  again is the same violation. A static fact is a compile-time constant
  (generated from the one TableGen source, checked by `static_assert` or
  `consteval`, dispatched by templates and concepts), carried in a type or
  a verified property, or computed once and kept. What the compiler knows
  about a program goes into the program as a constant: a folded test, a
  specialized entry point, a constant operand. A cost at run time is
  allowed only for a fact not known until then (the program's input, the
  machine, which registered op an `Operation *` is), and the code that
  pays it says why. Never, when the compiler runs:
  - building per function what is the same for every function:
    defunctionalization built, froze and destroyed a pattern set of one
    pattern per registered op for every function, about 11% of the
    dialect suite's sampled CPU, in a per-function step that took 70%
    (51a4771b; perf-sources C2);
  - rebuilding a whole table per item: the table of data types was remade
    and verified for every declaration, 843 s of one pass (73bba53f);
  - trying a pattern on every op when ODS knows which ops it can match:
    about 75 million attempts per pattern in 31 traced minutes (3a96c407);
  - recomputing the IR's order per query: half of idr-rc-grades in
    ancestor walks, a quarter in block renumbering (101edbc5);
  - restating a generated table: 37 folders converting constants by hand
    though the generated ABI table says how (04 C40); the TableGen backend
    reading records by C++ spelling and name strings (14 T06, T34).
  Never, when a compiled program runs:
  - testing what its types prove: a uniqueness test on a value typed
    exclusive (08 C-76, 12 CV-30), the count read on an exclusive drop (12
    CV-32), a NULL and odd-bit test in every `inc` and `dec` whose kind the
    type states (18 R-RC-1), 4,472 increments and 4,472 decrements in one
    function of one test where the runs of fields are known (18 R-RC-4);
  - writing a known fact as text to be parsed back: every crash exited
    with status 1, its kind only in a message the harness parsed from
    stderr in three copies (18 R-ABI-4; 19 C4); every shipped program
    counting every allocation for a test (18 R-AL-5).
- No pass may drop what Idris proved: multiplicities, erasure, linearity.
  They are what this compiler exists to exploit, so they live where MLIR
  cannot lose them. What Idris erased (quantity 0) is no value of the
  module: the frontend emits no parameter, field or argument for it.
  Quantity 1 is a type, `!idr.lin<T>`, which every transformation must
  keep and the verifier checks after every pass. A fact kept in a
  discardable attribute can be dropped silently; do not keep one there.
  Never: refusals kept in the discardable `idr.refusals` (14 T38); Emit
  demoting a quantity-1 binder its body uses twice, unseen by any contract
  (17 FB-28).
- Erased does not mean constant. A linear binder does not imply unique
  heap ownership. Indexed vectors do not imply contiguous storage.
- One op per semantics: "if two ops are secretly the same with slightly
  different effects, let's take advantage of pushing hard on the
  representation" (2026-10-21). Ops that differ in a parameter are one
  family whose members come from a list; an operand, attribute or enum
  that changes what an op means or may do is a flag, and the op is two.
  The `idr` dialect holds only what upstream's dialects do not mean.
- A name is text for a human. Every string that names a thing (a key, a
  printed form used as an identity, a kind spelled as text) is a missing
  type: an enum, a typed identity or a generated table. Never: a data type
  whose printed text held every body it reached, digested by printing
  (b9d4d592); a fixpoint tested by comparing printed modules (2ab5adf9).

## The C++

- Our own C++ is concept-constrained templates: "I'm serious about
  modernizing our C++ this time, and culling all the polymorphic ladders";
  "i cannot stress this enough, heavy use of templates and concepts pls";
  "we should push on this maximally insane compile time c++ requirement. i
  will not accept any plan that does anything less than this"
  (2026-10-21). Callbacks are template parameters constrained by concepts;
  a type-erased callback stays only where an upstream API takes one or the
  owner accepted it. A ladder over our own types is a concept-constrained
  overload set or one fold over a closed sum. Code is monomorphized, and
  where compile time calls for it each solver is instantiated once,
  explicitly, behind `extern template`; what templates cost the compiler's
  own build is measured, never assumed.
- Over ops, dispatch is MLIR's (an interface, a trait or a rooted
  pattern), kept only where the op set is open; below that one dispatch
  the code is typed. A concept may read an ODS fact (trait or interface
  membership, a generated constant) but never lists ops, and shared shape
  over ops is never an `isa<A, B>` ladder.
- Every fact knowable when the compiler is built is a compile-time
  constant, generated from TableGen and checked when the compiler is built
  (`static_assert`, `consteval`, or the generator for a fact that spans
  records). Runtime dispatch, runtime-built tables, string compares and
  hash lookups of static facts survive only where MLIR's open op set
  forces them, each one listed and justified in its design.
- A choice is a type or an enum case, never a `bool`. Nothing static is
  built per function; no attribute or type is made on a worker's hot path;
  no pointer-keyed map holds per-node state; a fact that can be numbered
  once is not recomputed per query.
- Never: `mark(seeds, bool backward)` (08 C-51); recursion through a
  `std::function` (21 P-19); representation first written as variants and
  worklists while the ladders stood, 34 variants, 113 accesses and 89
  worklists in one wave and the count of `isa<` lowered by none
  (d06ed15c; lane 20 L6); marker traits no C++ reads (02 T7); patterns
  rooted at every registered op but a hand list of nine names, enumerated
  per function at run time (7987388b; 21 P-6); a mutable type's facts read
  through the uniquer's write lock, where optimizer workers queued for
  half of a ten-minute window (98c6315c); a question answered by mutating
  IR, a fold probe that relinked a use list being walked (1b2e31da).

## Effects

- One effect system, defined and monomorphized in one place, "so there's
  never downstream disagreement about this ever again ... so it can all be
  defined and monomorphized in a single place" (2026-10-21). One TableGen
  source declares every effect fact: the resource tree, each op's static
  effects, the rules by which effects follow from types, consumption, the
  bits of a function's summary, and what LLVM is told. Every reader is
  generated or monomorphized from it and asks through one query API.
  Nothing else names a resource, reads effects its own way or maps summary
  bits to resources.
- A function's effects are derived from its ops by one derivation and
  held to it by the verifier, per function; a call carries its callee's.
  What the compiler knows of effects reaches LLVM. A crash and an endless
  loop are effects of partial code only: eager evaluation keeps them, and
  totality, as upstream defines it, is what removes them. `exit` is its
  own effect, an IO action that ends the process normally and never
  returns: not a crash, not a divergence (2026-10-21). The world and the
  rest of the tree's shape are the owner's to rule.
- Never: "does IO" held four ways that disagree, a trait on 80 ops, a
  world operand on the same 80, the `IOResource` effect (written by 80,
  read by 70 of another set) and the summary's own reading (02 §3.1); a
  function summary ignoring its ops: a handle-table read lost at the
  boundary, `exit` claiming to return, memo state in no bit (02 §3.7); a
  second effect classifier (04 C26); no effect reaching LLVM (12 CV-05).
  Never land the tree apart from the derived summary: a callee's
  buffer, array and memo writes stay ordered across a call today only
  because every effect sits under the root resource (02 §8).

## Analyses and solvers

- Upstream first, then upstream patched (`upstream/<bug>/`), then our own
  solver, named as what it is, in one solver layer whose composition and
  threading are explicit: "let's just be honest, and refactor it out into
  its own code where we can better understand how they compose and are
  threaded" (2026-10-21). Upstream is not dropped for ours with the middle
  step skipped. Never: exclusivity put on `DataFlowSolver` after one
  0.84 s test (595ed341) and dropped 21 days later at 627 GB with no patch
  of the state storage tried (ffa91113), though a two-line patch cuts that
  state about fifteenfold (wave1/5.1 A4); remove-dead-values adopted in
  place of our pass (0451b1b8) and dropped, four patches later, on a run
  stopped by hand at 52 GB (16005000); a union-find inclusion solve
  described as "a sparse dataflow analysis" (06 L-17).
- A fact is computed once and kept: an analysis lives in the analysis
  manager and survives every pass that does not change it; a fact that
  crosses passes lives in a type or a verified property; a mechanism
  found by one fix is written once and shared. Never: the call graph built
  up to seven times per compile, and "gives back argument i" solved,
  dropped and solved again after lowering (05 §2.2, R5); tail position
  decided in four places (synthesis C §1); three graph or numbering types
  in twelve hours, no code shared (b8301ebe, ffa91113, 101edbc5; 21 P-14).
  What an analysis admits changes only in a commit that says so. Never:
  `decides` narrowed to five ops, unrecorded, while the owned verifier
  still admitted `scf.if` (101edbc5; 21 P-3).
- A solve's state is sized by the problem. Never: state per value over the
  whole program in a general framework, two or more states per value at
  about 2.9 KB each (627 GB, ffa91113; perf-sources C7); a bit vector per
  value copied along every edge (47 GB, b8301ebe); an interface query per
  pair of successor and terminator (a graph build that never finished,
  fixed by e96bb991 three hours after ffa91113 wrote it); IR cloned per
  pair of member and answer (43 GB, 16005000); per-node state in maps
  keyed by `Value`, `Operation *` or `Block *` (perf-sources §3).

## The Idris side

- Idris does types; MLIR does programs. The Idris side (`compiler/`: the
  frontend and `Emit`, on the fork of Idris's compiler in `compiler/idris`)
  checks what the compiler accepts, monomorphises and decides
  representations. The `idr` dialect and its passes (specialization,
  defunctionalization, loops, the heap-free check, lowering) are C++ in
  `foreign/idr/`, an in-tree MLIR dialect in upstream's layout and
  conventions; `PINS.md` records every deliberate deviation from it and
  every pinned workaround.
- The Idris side compiles under two hosts, always: upstream's Idris on Chez
  Scheme, which may compile it however it chooses but must compile and run
  it, and idris-mlir itself. This holds for the frontend, the fork, `libs/`
  and the Idris test machinery, so all of it is written in the subset
  idris-mlir compiles and uses nothing only one host has. Linearity is a
  performance property, never a correctness one: a linear program means
  the same under both hosts, and idris-mlir's optimizations of it (update
  in place, no counting) only make it faster. A primitive of `libs/` (an
  `%extern`) means only what `runtime/` says, so a program that reaches one
  runs under idris-mlir alone, and nothing the stock host runs reaches
  one. What the stock host runs uses only definitions with bodies, which
  idris-mlir may replace with a runtime op through the registry's `Faster`
  hook: the body is the one meaning, and removing the hook leaves the same
  result. A building stage may use either host, but neither is dropped.
  Neither host is given an escape hatch to compile it: a trust the
  frontend takes in Idris's compiler is stated in the fork, which is
  Idris's compiler, and one it takes in itself is `covering`, never
  asserted. Never: the hosts agreeing by coincidence (float text matched
  only because two printers happen to agree; 14 X01).
- The Idris side is refactored wherever the representation calls for it:
  "if we need to heavily refactor our idris code, representation first, so
  be it" (2026-10-21); type-driven (indices, views, erased proofs, evidence
  over `Bool`), within the subset both hosts compile.
- The compiler consumes checked Idris TT and its definition context. Do
  not replace that input with CExp or runtime case trees, and do not erase
  facts before the passes that use them. The TTC keeps every fact a reader
  would otherwise rebuild, and the frontend reads each once, at the
  boundary, into a typed table. Never: a `let`'s type dropped by the TTC
  and guessed back (17 FB-01); erasure decided by five readers with
  different defaults while the fork's own `eraseArgs` is read by nothing
  (17 FB-15); a block's parent kept as printed text (17 FB-10); imports
  found by splitting source text into words (16 FC-79); the registry
  resolved, dropped and searched again by printed name (14 R06, 15 RS-1).
- A fact the dialect and the Idris side both hold is generated to both
  from ODS, and a `.td` change the Idris side names lands with the Idris
  side it regenerates: the frontend would not build otherwise, and a shim
  is a second copy. Never: `CmpPredicate` held in Idris and in C++ (14
  E14); `Profile.outsideLanguage` restating the rules of `IdrBase.td` (16
  FC-78); the harness's hand copy of the primitives (19 G6).
- Only `IdrisMLIR.Frontend.*` may import the fork of Idris's compiler
  (`compiler/idris`), and the fork never imports `IdrisMLIR.*`.

## Upstream and pins

- third_party/Idris2 is unmodified and pinned by its gitlink. Do not edit
  it or move the pin as a side effect of other work; a patch to Idris
  applies to the copy the bootstrap builds, never to the checkout.
- A bug in a pinned upstream (LLVM, MLIR, clang, lld, Chez Scheme, Idris)
  is fixed in that upstream, by a patch to its source, not worked around
  in ours: a workaround hides the bug from upstream, drifts from it, and
  every pass written after it has to know it. Reduce it to upstream
  dialects and tools first; if it does not reproduce there, the bug is
  ours: fix it. Prefer upstream's own fix, backported, to one of ours. The
  patch lives with the bug's report as `upstream/<bug>/<project>.patch`,
  and `tools/bootstrap.sh` applies it to the pinned source it builds; add
  the report, the reproducer, the patch, its `tests/upstream-<bug>` check
  and its `PINS.md` entry in the same change, and delete the workaround it
  replaces. Every patch has a written plan to upstream it (where it goes,
  the upstream test, its status); sending it is separate work. A patch
  goes when the pin moves past upstream's fix, or when nothing in the tree
  reaches the bug any more, its report kept as a submission (see
  upstream/README.md). The fork of Idris's compiler (`compiler/idris`) is
  ours: a bug in its upstream code is fixed there, as its own code,
  recorded in `PINS.md`, with the change against the pin in
  `upstream/<bug>/pull-request.diff` for the re-sync to read, and the fix
  goes when a re-sync of the fork brings upstream's. Nothing is sent to
  Idris: it takes no contribution written with generative AI or a coding
  agent (upstream/README.md). A patch to the stock Idris is only for what
  it still builds (the fork, the frontend, the test runner).
- PINS.md and `upstream/` change in the commit that changes what they
  describe. Never: an upstream gap in `ub.unreachable` modelled in our
  code (`NeverRuns`, synthesis A B9); the fork's `paramPos` bug patched in
  the frontend instead of fixed in the fork (17 FB-18); patches 06, 28 and
  63 carried after 16005000 left them nothing to reach, PINS.md naming the
  dropped pass, the upstream table missing 62 and 63 (lane 20 H2, H3).

## Tests and checks

- Tests check behaviour: exit status, produced artifacts, the property a
  pass guarantees. Not clone numbers, function order or SSA names. A test
  that goes stale on an unrelated change was a bad test; fix or delete
  it. A brittle test means a missing test API: instead of matching exact
  op sequences, write the property once as an expressive check (a helper,
  a verifier-style assertion pass) and state tests in its terms. Never: a
  test that names a pass, so a rename leaves it checking nothing
  (`fuzz-two-hosts` named the step idr-rc, "which no pass is any more",
  28274bd3; 644 RUN lines name 24 `--idr-*` passes, 19 T1-T3).
- Checks: `make check` always. After compiler changes, run `make build`
  and `make test`. After C++ changes, also run `make test-idr` and
  `make test-unit`. After changing MLIR usage, also run
  `make test-mlir-tools`. Every command a test runs times out, so a hang
  is a failure, not a wait. If a toolchain is unavailable, say so; do not
  report skipped tests as passed.
