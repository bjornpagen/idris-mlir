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
- Delete before you optimize: "apply the elon algorithm, our representation
  has massively improved so we should have the balls to remove parts that
  are no longer needed or cargo culted and no longer needed because of our
  representation first total redesign ... aggressively cull the old parts.
  ship of theseus, except it gets smaller" (2026-10-23). Every part (a
  pass, an analysis, a verifier rule, an op, a runtime function, a test, a
  tool, a dependency, a patch) names the ruling or rule that requires it
  and the fact only it supplies; a part whose fact a type, a construction
  or another part already holds is deleted, not simplified, tuned or kept
  in step. Question the requirement first, delete second, simplify only
  what survives.
- A change is done when it is built, run and passes its checks (the last
  section) on all four targets. P0's cutover is one change, built only when it is
  whole ("we will only build when this entire cutover is fully done",
  2026-10-21), and it lands only built and passing. Type-checked is not built, and built is
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
  release. Every dependency is fast-forwarded to that latest about once a
  week, LLVM and MLIR included, with the carried patches rebased or
  dropped where upstream now has them: "good to do this every week or
  so" (2026-10-21).

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
  An unused computation is evaluated, so its crash or endless loop
  happens; deleting it would give unused values a lazy meaning the
  language lacks. Only the derived effect row licenses deleting or moving
  a call: one whose row carries neither a crash nor a divergence
  (2026-10-21). Totality, as upstream defines it, removes divergence: a
  function proved `total` carries no divergence effect and is lowered
  with `mustprogress`, but it may still crash (upstream reports
  `g x = div x 0` total, and it crashes), so `total` alone never licenses
  a deletion. A statically certain crash (a constant zero divisor) is a
  plain crash where evaluation reaches it, with no run-time test.
  Totality is not made mandatory: that would refuse most real programs
  (2026-10-21).
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
  compile-time analysis bounds (an implementation chosen from a set no
  analysis bounds, a recursion that builds its type deeper at each call),
  is not
  Idris this compiler supports: it is refused with an `unsupported` error
  that names the site and the value whose set is unbounded, never compiled
  to a uniform boxed form. A run-time choice among implementations the
  program fixes is a closed sum and compiles (2026-10-21). Idris's other packages (contrib, linear,
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
  in-place promise exclusivity cannot meet. That promise is a rule read
  off the program before counting (a function that takes apart a
  quantity-1 parameter of an `in_place` type and builds one from it
  rebuilds it), counting must honour it (reuse recycles the cell, no frame
  and no dup takes it), and only a call the exclusivity analysis cannot
  prove exclusive is refused. Every refusal's rule carries
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
- Every compiled program is frame-limited (2026-10-21): at every
  allocation, each heap cell is either still reachable from what the
  program will use, or held by an active call (a native frame or a heap
  continuation frame), which holds at most a fixed number of bytes it no
  longer needs, computed by the compiler for its function from types. A
  call may hold reuse tokens of statically sized cells, its stack cells'
  shells, and values borrowed past their last use whose type bounds all
  they reach; never a dead dynamically sized cell past an allocation, a
  borrowed argument no active call needs after the call unless its type
  bounds all it reaches, or any structure past its last use. Outside it: the
  allocator's overhead, spare room in a live cell, persistent static data
  (live), a saturated count. It is stated for counting without a collector and without cycles
  (`idr-knots` refuses every one): "i don't want to cargo cult any
  properties from that paper that only exist to address those edge
  cases" (2026-10-21). Never: reuse decided before drops are placed,
  holding a token across calls with no bound stated, and borrows
  inferred with no space rule, so neither garbage-freedom nor a frame
  bound held and no test bounded the peak (07 R-09, 08 rc-Q3, 19 T19).
- Proper tail calls: a call in tail position must never grow the stack
  (2026-10-21), on a cycle or not, as ML and Scheme guarantee and as
  upstream Idris has on Chez. Whether a call is in tail position is one
  fact on the call, decided once and obeyed by every pass; a tail call
  the compiler fails to make is an internal error, never a silent call.
  Running an action never grows the native stack however its binds
  nest, and no recursion on a call cycle does either: its depth lives on
  typed, linear, uncounted, contiguous frame stacks, one per result type.
  The native stack is small and statically bounded ("i'm in the musl
  camp on this", 2026-10-21): it holds only the acyclic call depth, its
  size computed when the program is built, and reaching its guard is an
  internal error. Tail recursion modulo context is a promise too: a self
  call whose result a tail returns inside cells built for it is a loop
  with a destination, read off the program, and a missed one is an
  internal error. The compiler's own tools keep a small stack as well:
  our C++ never recurses on the input's size, and a recursion of MLIR's
  that does is fixed upstream. A program commits no memory before it
  uses it, reserves no address space beyond what the host allows, and
  starts on strict hosts (overcommit mode 2, `ulimit -v`). Every ending
  has its own exit status, from one generated table (2026-10-21): 0
  returned, `n` for `exit n` (a status outside 0 to 255 a crash at the
  exit's site), 1 crashed, 111 out of memory, 126 cannot
  run on this machine, `SIGABRT` for an internal error; messages go to
  standard error as `<program>: fatal: <cause>`. Every size is
  the program's or the host's, never a round constant (2026-10-21).
  Never: a 64 GiB stack reservation so that recursion
  would never overflow, under which a runaway recursion took the machine
  down instead of crashing (1445d894). Never: a
  tail call left an ordinary call with only a statistic to show it
  (`numFrameBound`, 10 TC-5), tail position decided in four places, two
  of which had to agree (10 D1).
- No primitive has an implementation in Idris. A primitive the runtime
  implements (strings, big integers, IO) has its one meaning in
  `runtime/`, which folders call too. An op of inline arithmetic
  (Euclidean division, the total shifts, the scalar-value test, the char
  conversions) has its one meaning in one C++ template generic over a
  numeric domain, instantiated as the folder, as the op's integer ranges
  and as its expansion into `arith`, which the runtime includes too
  (2026-10-21). A closed call runs at run time. Static normalization
  (proposal 0010) is what would fold one, and it is not built.
- `%foreign` and the C ABI are outside the language, as threads, collector
  finalizers and raw pointers are. Do not implement `%foreign`, `%extern`
  as a C export, a C calling convention, libffi, or declaring or calling a
  C symbol from user code. The refusal is `unsupported` and names
  `%foreign` or the extern; never ignore the pragma. A `Data.Buffer`
  operation is a runtime primitive, with its one meaning in `runtime/`.
  There is no C interop now or later: the one foreign world planned is
  Rust (proposal 0020), and a C library is reached only through a Rust
  `-sys` crate and the safe crate over it. Rust is its own foreign
  runtime, reached as IO and never optimized as Rust, and it never calls
  back into Idris (2026-10-21).

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
  when a compiled program runs. A fact that the dialect's specification,
  the compiler's build, a pass's construction, an earlier pass, Idris's
  type checker or a
  type already knows is never recomputed, re-derived, looked up, tested,
  string-compared, hashed or rebuilt; and a fact some earlier stage knew,
  or could have kept, counts as known: throwing it away and deriving it
  again is the same violation. A static fact is a compile-time constant
  (generated from the one source, the dialect's Idris specification,
  checked by `static_assert` or
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
  Quantity 1 is the grade's `once` (`!idr.graded<once, …>`), which every
  transformation must keep and the verifier checks after every pass. A fact kept in a
  discardable attribute can be dropped silently; do not keep one there.
  Never: refusals kept in the discardable `idr.refusals` (14 T38); Emit
  demoting a quantity-1 binder its body uses twice, unseen by any contract
  (17 FB-28).
- Erased does not mean constant. A linear binder does not imply unique
  heap ownership. Indexed vectors do not imply contiguous storage.
- A data type is the inductive family Idris checked (2026-10-21): an
  attribute holding the declaration (erased indices; per constructor the
  index variables it binds, the equation it satisfies, its fields with
  their quantities; recursion as a back-reference carrying an index),
  applied to index terms (`!idr.data<#Vect[n]>`). Identity is content:
  no table, no name looked up, no name without a body. Index variables
  are quantity-0 parameters bound by a function. A match refines the
  index, a case whose equation is false does not exist, a known index
  fixes the shape, and inline or in a cell is layout computed from the
  type. Never: a data type whose
  identity was a name, remade under a content-derived name on every body
  change (`DataRemap`), with a name-alone state the verifier hunted for
  across the whole program (01 T05, T59).
- A value's grade is `!idr.graded<uses, hold, T>` (2026-10-21): uses
  (`once` or `many`; zero is absence) on every type, hold only on types
  that hold references: `static`, or `counted` or `scoped` with what is
  known of its sharing (nothing printed, `unique self` for its own
  family's cells, those of every `in_place` field it holds and the
  storage, never the elements, of every buffer they hold, `unique deep`
  for everything it reaches; 2026-10-21, the buffer 2026-10-22: "i take
  your rec"). Who frees a
  value and what is known of its sharing are two axes, never one enum,
  and a lifetime is not a field of the grade. Never: a grade whose
  permission mixed ownership with sharing and whose lifetime field split
  ownership across two fields, so an owned value in a frame needed a rule
  to forbid it (L05).
- A lifetime is an SSA value (2026-10-21, a hard cutover): `idr.lifetime`
  opens a region and yields its token, a function takes a lifetime as an
  argument and a call passes it as an operand; MLIR's region scoping and
  dominance check that nothing of a lifetime outlives it, and upstream's
  inliner, CSE and dead code handle it as any SSA value. Where a function
  allocates into a lifetime the token is the run-time arena handle;
  elsewhere it is erased. Views and cells allocated into a lifetime live
  in it; a lifetime is an optimization over counting, never a
  replacement. What a lifetime is at run time is its type's kind,
  `!idr.lifetime<view | room | cursor | home k>`, which every
  allocation, callee, frame and the lowering read; where its memory
  comes from is the op that opens it, one op per source; a `view`
  parameter accepts any kind, and every lifetime is born decided
  (2026-10-21). Never: static data graded from where a value came instead
  of from what it holds (467fa2f5, removed by c4d38e9b).
- One op per semantics: "if two ops are secretly the same with slightly
  different effects, let's take advantage of pushing hard on the
  representation" (2026-10-21). Ops that differ in a parameter are one
  family whose members come from a list; an operand, attribute or enum
  that changes what an op means or may do is a flag, and the op is two.
  The `idr` dialect holds only what upstream's dialects do not mean.
- The lossless representation at every point: "we always always want to
  choose the data structure that prevents the loss of information we
  already had statically" (2026-10-21). A form that loses a fact already
  known is used only for a stated performance reason, and only after the
  fact is carried elsewhere. Representations are chosen first for what
  they let the compiler prove about counting: "mlton has a gc, we have rc
  with proved rc copy optimizations, which i want to exploit more
  heavily. this needs to be foundational" (2026-10-21).
- Control flow: regions, join points, blocks only at the lowering. A
  match is a region per case, a single-entry, single-exit scope rejoining
  at the op's results, from the frontend to the lowering. A linear,
  non-escaping continuation called in tail position, and a local tail
  call contification finds, is a join point: a continuation local to its
  function, jumped to with typed arguments (grades and reuse tokens
  among them), never an allocated closure; a recursive join point is a
  loop. Blocks appear only at the lowering, through upstream's
  `convert-scf-to-cf`. This is a hard cutover, "never reversed until we
  come up with something strictly better" (2026-10-21): a form that keeps
  every fact this one keeps, proves at least every counting decision it
  proves and proves more, shown on evidence and accepted by a dated
  ruling of the owner. Never: MLton's flat CFG taken as ours; chosen
  under a garbage collector, it drops the scope and ownership facts our
  counting proofs read (`audits/p0/wave1/5.9-mlton.md` C3).
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
  constant, generated from the dialect's Idris specification (through the
  TableGen it generates, or directly) and checked when the compiler is built
  (`static_assert`, `consteval`, or the generator for a fact that spans
  records). Runtime dispatch, runtime-built tables, string compares and
  hash lookups of static facts survive only where MLIR's open op set
  forces them, each one listed and justified in its design.
- Assertions (2026-10-21, reversed 2026-10-22): "we should turn on llvm
  and mlir assertions to help us debug too." The toolchain's LLVM and MLIR
  are built with their assertions on, in the one toolchain the tests run
  and the compiler ships with, and our C++ is compiled to match, without
  `NDEBUG`. That last part is reversed for
  the C++: "c++ assertions are totally fine! the more the merrier! c++ has
  a totally different policy from the idris. in fact, we should probably
  be using c++26 contracts too for correctness!" (2026-10-22). Our C++
  checks its invariants freely (`assert`, or an always-on fatal internal
  error), and moves to C++26 contracts once the pinned clang has them. The Idris side is the
  opposite: "we should strive to prove things rather than assert them,
  or refactor the represnetations such that invalid states are
  unrepresentable" (2026-10-22). An `internal` error, `assert_total`,
  `assert_smaller` of ours in Idris is a missing type or a missing proof;
  one stays only for a fact not known until run time, and says so. No
  `believe_me` at all: "we should not have any believe me in our own
  codebase, we're better than that" (2026-10-23). What a host's primitive
  gives, or what an evaluator computes, is carried as evidence a
  function returns or made unnecessary by the representation, never
  asserted; only a test of the refusal of `believe_me` holds one.
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
  defined and monomorphized in a single place" (2026-10-21). The one
  source, the dialect's Idris specification, declares every effect fact:
  the resource tree, each op's static
  effects, the rules by which effects follow from types, consumption, the
  bits of a function's summary, and what LLVM is told. Every reader is
  generated or monomorphized from it and asks through one query API.
  Nothing else names a resource, reads effects its own way or maps summary
  bits to resources.
- A function's effects are derived from its ops by one derivation and
  held to it by the verifier, per function; a call carries its callee's.
  What the compiler knows of effects reaches LLVM. An endless loop is an
  effect of code not proved total, which totality, as upstream defines
  it, removes; a crash is an effect of any code that can reach a failing
  check, total or not; eager evaluation keeps both (2026-10-21). `exit` is its
  own effect, an IO action that ends the process normally and never
  returns: not a crash, not a divergence (2026-10-21). After the frontend,
  IO is ordered by declared effects alone: the world value ends at Emit,
  and the derived effect row's `io` atom is IO's typed carrier
  (2026-10-21). A computation's row lives on its op (`idr.func`,
  `idr.call`), never in an MLIR value type: none of our effects changes a
  calling convention. A crash is ordered with IO only: heap effects may
  move across a crash or a guard, while crashes, `exit` and output stay
  ordered among themselves; a total op stays below its guard by data
  dependence on the guard's refined result, never by an effect
  (2026-10-21). Running out of memory is outside the language, a named
  crash of the machine, never a value or an effect
  in the types: allocations are not ordered for the sake of failing, and
  where new memory enters the arena is marked by an "acquires memory"
  effect, deletable when unused (2026-10-21). The resource tree
  (2026-10-21): under upstream's root, upstream's frame; the heap, which
  only acquires and frees the memory any cell lives in, over its
  contents, its counts and its memo state; a fresh value's identity; and
  IO, one ordered state, over runtime state (read only), exit, and crash
  over divergence. Immutable memory has no resource. Memory the kernel or
  a foreign library touches is held by ownership (a moved buffer, a
  reference to immutable bytes), never by a resource of its own.
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
- No greedy rewriting where our ops are (2026-10-21: "wipe it off the
  face of the earth"): no call of MLIR's greedy driver in our code, no
  `canonicalize` at a point that holds our ops, no canonicalization
  pattern on our ops. Simplification is a narrow e-graph, "not for
  speed, it's for shared representation, elegance, and pushing qtt
  extremely hard to remove bugs", built from MLIR's own mechanisms in
  C++, its rules and laws generated from the dialect's Idris
  specification; "the frontend stays the frontend, mlir stays mlir": the
  elaborator keeps its own union-find (2026-10-21). An op's fold is its
  meaning, which the e-graph reads. Upstream's passes are never
  duplicated to avoid it: the driver inside an upstream pass stays
  upstream's ("let's not duplicate upstream's passes", 2026-10-21).
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

- Idris does types; MLIR does programs: Idris is representation, and
  every optimization runs in C++ over MLIR ("idris should be pure
  representation, none of the optimization stuff. within reason",
  2026-10-21); the specification may state an op's rules and laws as
  data, which the C++ uses. The Idris side (`compiler/`: the
  frontend and `Emit`, over our type checker in `compiler/checker`)
  checks what the compiler accepts, monomorphises and decides
  representations. The `idr` dialect and its passes (specialization,
  defunctionalization, loops, the heap-free check, lowering) are C++ in
  `foreign/idr/`, an in-tree MLIR dialect in upstream's layout and
  conventions; `PINS.md` records every deliberate deviation from it and
  every pinned workaround.
- Two hosts, always, and no fork: "idris-mlir must self host idris-mlir,
  that is obviously a goal. it must be compisable BOTH from upstream idris
  and our idris-mlir"; "i don't care about idris-mlir compiling
  upsteram"; "we should purge the fork entirely. there should be only raw
  upstream, and idris-mlir" (2026-10-22). Our Idris compiles under stock
  upstream Idris on Chez, the bootstrap, and under idris-mlir itself, so
  all of it is written in the strict subset above and uses nothing only
  one host has. Raw upstream Idris, pinned and unmodified, is the
  bootstrap host and nothing more; a bug in it is patched upstream, never
  worked around in a fork. idris-mlir compiling upstream's code is no
  goal, and the subset is never widened past its definition for any
  code. The type checker idris-mlir uses is our code, Idris's checker
  copied into our tree with its attribution (`compiler/checker`, D118):
  it tracks no upstream and no rule keeps upstream's form in it. Never: a
  "fork" of Idris's compiler kept against upstream, with a re-sync tool,
  a list of kept files and diffs for merges (`compiler/idris`, until
  D118). Never: a ruling recorded as dropping
  self-hosting (D116's first text, corrected the same hour). Linearity is a
  performance property, never a correctness one: a linear program means
  the same under both hosts, and idris-mlir's optimizations of it (update
  in place, no counting) only make it faster. A primitive of `libs/` (an
  `%extern`) means what `runtime/` says, or, for the array library's
  generating set, the dialect op the specification declares for it, with
  upstream's tensor and linalg semantics (2026-10-21); either way a
  program that reaches one runs under idris-mlir alone, and nothing the
  stock host runs reaches one. What the stock host runs uses only definitions with bodies, which
  idris-mlir may replace with a runtime op through the registry's `Faster`
  hook: the body is the one meaning, and removing the hook leaves the same
  result. A building stage may use either host, but neither is dropped.
  Neither host is given an escape hatch to compile it: what the frontend
  needs of the checker's evaluator is evidence the evaluator returns, and
  what it needs of itself is `covering`, never asserted. Never: the hosts agreeing by coincidence (float text matched
  only because two printers happen to agree; 14 X01).
- Anything of ours above the C++ is Idris: "our higher level spec should
  not be in a python dsl, opdsl, etc... it should just be idris.
  obviously. we have chez so we can always bootstrap. always idris"
  (2026-10-21). A specification above TableGen, a generator or a DSL of
  ours is written in Idris, in the subset both hosts compile, never in
  Python, YAML, OpDSL or a language of its own; stock Idris on Chez builds
  it first, so the build always starts.
- Our TableGen is generated, 100%, from the dialect's Idris specification:
  "tablegen FULLY 100% generated by idris is the right move. i approve. it
  must be an extremely hard cull and cutover" (2026-10-21). The Idris
  specification is the one source of the `idr` dialect: its ops, types,
  attributes, effects, rules and tables, with their invariants proven by
  Idris's types. Every `.td` file of ours is its output; none is written
  or edited by hand, and none survives beside it. The generated files are
  committed (2026-10-21), their fingerprints in one committed manifest
  (each file's content hash, the specification's and the generator's), no
  stamp in any file; `make check` regenerates them and fails on any
  difference. They are the specification's output, never a
  second source: a C++ build never waits on Idris, and a reviewer sees
  what a specification change produces. Upstream's own `.td` files
  (MLIR's `OpBase.td` and kin) stay upstream's.
- Code is never kept worse to spare the compiler: "we should undo the
  damage from rewriting our parser in a simpler form taht our compiler
  can handle, our codebase should be great as fuck. our compiler is
  better now and we should be doing the maximally good thing for our
  code" (2026-10-22). Where idris-mlir does not compile the best form of
  our own code and the program fixes the construct's runtime choices,
  the compiler gains the construct; only a megamorphic one stays
  rewritten. And never pass types around: "that type passing bullshit is
  really bad. that's just called bad code" (2026-10-22). No constructor
  field whose type the constructor hides, no `Type` held at run time, no
  type computed from a run-time value; the code states the types it
  means, and a parser is combinators that use quantities. Never: the
  checker's parser rewritten from upstream's deep embedding into a
  shallow one with five `assert_total`s (360db182), nor restored to
  upstream's type-passing embedding (30018c00).
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
- third_party/Idris2 is unmodified and pinned by its gitlink. Do not edit
  it or move the pin as a side effect of other work; a patch to Idris
  applies to the copy the bootstrap builds, never to the checkout.
- A bug in a pinned upstream (LLVM, MLIR, clang, lld, Chez Scheme, Idris)
  is fixed in that upstream, by a patch to its source, not worked around
  in ours: "never dance around upstream again. we fix upstream and save
  the patches" (2026-10-22). Never: stock-Idris bugs listed for our code
  to "avoid until fixed" (pattern lambdas on `Nil`/`::`/`#`, nested linear
  pairs, an effectful `let` the body ignores) instead of patched; a workaround hides the bug from upstream, drifts from it, and
  every pass written after it has to know it. Reduce it to upstream
  dialects and tools first; if it does not reproduce there, the bug is
  ours: fix it. Prefer upstream's own fix, backported, to one of ours. A
  change upstream we need, a fix or a feature, is carried as a patch,
  always, upstream's own form first, even an unmerged pull request: "we
  always always carry the patch, ESPECIALLY if it's meant to be upstreamed
  or coming for free in a future release" (2026-10-21; the early-exit
  work, PR #166688, carried for join points). The
  patch lives with the bug's report as `upstream/<bug>/<project>.patch`,
  and `tools/bootstrap.sh` applies it to the pinned source it builds; add
  the report, the reproducer, the patch, its `tests/upstream-<bug>` check
  and its `PINS.md` entry in the same change, and delete the workaround it
  replaces. Every patch has a written plan to upstream it (where it goes,
  the upstream test, its status); sending it is separate work. A patch
  goes when the pin moves past upstream's fix, or when nothing in the tree
  reaches the bug any more, its report kept as a submission (see
  upstream/README.md). Our type checker (`compiler/checker`) is our code:
  a bug in it is fixed in it, like any of ours, with nothing kept against
  upstream. Nothing is sent to Idris: it takes no contribution written
  with generative AI or a coding agent (upstream/README.md). A patch to
  the stock Idris is only for what it builds as our bootstrap host (our
  Idris: the checker, the frontend, the test runner).
- PINS.md and `upstream/` change in the commit that changes what they
  describe. Never: an upstream gap in `ub.unreachable` modelled in our
  code (`NeverRuns`, synthesis A B9); the checker's `paramPos` bug patched
  in the frontend instead of fixed in the checker (17 FB-18); patches 06, 28 and
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
