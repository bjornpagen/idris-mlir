<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
<!-- The question register: moved out of proposals/0000-mlir-native.md §8 on 2026-10-21, unchanged; every question ID in other documents resolves here. audits/p0/synthesis/F-decisions.md groups them into decision points. -->

# P0: the question register (158 questions)


Every open question the research has put to the owner, in one place,
grouped so that related questions are answered together. Each keeps the
ID its lane gave it, with the lane's name in front where two lanes used
the same numbers (`ods-Q1` is §5.2's Q1, `rc-Q1` §5.10's), and points to
the section that argues it: read that section's findings before
answering. An answered question leaves this list and becomes a dated
decision in §9. Questions for wave 2 stay in the lanes' sections: they
are checks of our code, not choices.

Every lane of wave 1 has put its questions here (2026-10-21).

A suggested order for stepping through: what the language means (8.1),
which only the owner can settle and which constrains the rest; then
scope (8.2), the dialect's representation (8.3), the solver layer (8.4),
counting (8.5), verification (8.6), threading and determinism (8.7),
specialization (8.8), C++ (8.9), tools (8.10), and running out of
memory (8.11).

### 8.1 What the language means: effects

- **ods-Q1. A dead crash or divergence: kept or deletable?** MLIR treats
  "may not end" and "may trap" as speculation facts, so a dead op may be
  deleted; a `Write` on a resource keeps it. Our `Divergence` and `Crash`
  resources keep it. Which does Idris's meaning want for an unused
  `check.may_loop` or crash, given AGENTS.md's "in program order with
  every other effect"? (§5.2 A6, A7)
- **DD-Q2. Divergence, the same question from the dialect.** May the
  compiler delete an unused call to a non-total function (upstream's
  model: non-termination blocks speculation only), or is divergence an
  effect to keep? Answer with ods-Q1. (§5.8 C1)
- **ods-Q3. Is a crash ordered with IO and with heap writes?** Sibling
  resources never conflict, so if it is, `Crash` is an ancestor of both
  in the resource tree, never a sibling. (§5.2 A8, M3)
- **ods-Q2. Effects that follow from types.** One trait computing effects
  from operand types (the world, a grade) for a whole family of ops, or
  ops split until every effect is static in ODS? The first keeps one op
  per semantics where the type already decides; the second makes the
  dynamic case unrepresentable but multiplies ops (the limit in the
  representation-first skill). (§5.2, the recipe's row 3)
- **DD-Q3. The world.** Effects only, after the frontend (MLIR orders IO
  by effects, not tokens, and the builtin `token` cannot pass through
  calls, branches or loops), or a world value whose effects are derived
  from it? Answer with ods-Q2. (§5.8 DS2.1, DS2.2)
- **ods-Q5. Effect stages and full-region effects,** which no upstream
  pass reads: declare them anyway, as documentation ODS keeps, or only
  where a pass of ours reads them? (§5.2 A6)

### 8.2 Scope and process

- **Q2. Self-hosting.** P0 comes before everything: does 0001's S3 rerun
  stop until P0's plan is approved, or run alongside as measurement?
- **Q3. The frontend's mirror.** Churning the `.td` files changes what
  `idris-mlir-tblgen` generates for the Idris side: is the frontend cut
  over in the same change?
- **Q4. Measurements.** Designs are judged on the stage-1 module: who runs
  the release `idris-mlir` on it for P0's measurements?
- **DD-Q8. Renames.** Is every name open, including `con`, `dup`, `drop`
  and the `idr` namespace itself? (§5.8)
- **QL5. Equality saturation:** out of P0's scope? (§5.7)
- **QL6. Snapshots:** approve the list of documents for `sources/` in
  §5.7.6.
- **Q-M4. Porting more of Modular.** Beyond the deduplicator: the
  call-graph schedule, the per-worker parallel driver (or as an upstream
  patch), the dead-argument pass, `Shared<T>`; each port keeping its
  header, with a `PINS.md` entry. Port, or rewrite? (§5.4 designs 1, 2, 6)
- **Q-E4. Porting from CIRCT and IREE** (both Apache-2.0 WITH
  LLVM-exception, as Modular's code is): for example `InstanceGraph`'s
  maintained shape for our program graph, and CIRCT Dedup's parallel
  structural hashing for our deduplicate pass, recorded in `PINS.md` like
  the Modular port? Answer with Q-M4. (§5.6)

### 8.3 The dialect's representation

- **QL2. One value per ownership state.** Should static single
  information be a rule of the dialect redesign: every ownership change
  defines a new value, and every case region binds its refined
  scrutinee, so that an ownership analysis keeps one fact per value and
  no state per program point? (§5.7 L1)
- **Q-O1. Structured match after defunctionalization?** MLton's core is a
  first-order CFG with `case` as a terminator whose arms are blocks;
  upstream MLIR has the mechanism (produced successor operands), and in
  that form the wide-match query of e96bb991 cannot arise. Is the
  structured `match` (a region per case) to be kept past
  defunctionalization, and if so, for which passes? (§5.9 design 2)
- **Q-O3. Facts into types.** Should every fact a later pass reads be
  written into a type by the pass that proves it (closure sums per flow
  set, dead fields absent from their constructors, an immutable
  `!idr.data` naming a type constructor whose bodies live in one table
  op), with everything else recomputed and nothing carried between passes
  as a side table? (§5.9 design 3)
- **Q-E2. Where a summary lives.** In a cached analysis object, typed and
  indexed by function, out of the IR; or, where later passes rely on it
  (a function's effects, its parameters' grades), in the IR as a type or
  an inherent property that the verifier checks after every pass, as
  IREE does with resource lifetimes, at the price of every
  transformation keeping it right? Answer with Q-O3. (§5.6 D6)
- **DD-Q1. Grades on trivially copyable types.** Swift erases ownership
  wrappers on trivial types, and MLIR's normalizations drop defaults. May
  `!idr.lin<i64>` normalize to `i64` when it is built, or is that
  "dropping what Idris proved" (AGENTS.md)? (§5.8 B5, D4)
- **DD-Q4. Signedness.** arith's and comb's school (signless integer
  types, the sign on the op where the computation differs), or CIR's and
  Mojo POP's (signed types, one op)? The lane recommends arith's: we lower
  to it, and the frontend has already monomorphized the source types.
  (§5.8 B3, E4, F5, G4)
- **DD-Q5. One op, several runtime functions.** May one op with an enum
  (`io.clock <kind>`, `idr.check <reason>`) map to several runtime
  functions, selected by a table generated from ODS, where
  `Idr_Runtime<"symbol">` ties one op to one function today? (§5.8)
- **DD-Q6. Borrows: regions or lifetimes in types.** Borrows as regions,
  with no lifetime in the type, or lifetimes as symbolic attributes in
  types (Mojo, which keeps them until one checking pass and then erases
  them in one step)? Bears on rc-Q1. (§5.8 T5)
- **DD-Q7. Our own function op.** Should conventions and effects live in
  a custom function type, which means keeping `idr.func`, or should we
  take `func.func` and keep them in an analysis? Bears on Q-E2.
  (§5.8 T6)

### 8.4 The solver layer

QA4, Q-O2, QL1 and Q-llvm-3 are four sides of one choice, the shared
state representation; answer them together.
- **QA1. Patch upstream's state storage first?** Patch the framework's
  storage (U1), then decide analysis by analysis what returns to it. And
  which patch: P1 (two declarations, likely quick upstream) or P2 (a
  flat map and typed arenas, freeing per type, a larger review)? (§5.1)
- **Q-E5. Two upstream RFCs.** A call graph maintained in place, with its
  SCCs, as an upstream analysis (CIRCT's is the precedent; upstream's
  `CallGraph` is rebuilt), and a scope between function and module in the
  dataflow framework (per-SCC solves with summaries, which was suggested
  upstream in 2022, §5.1 A8). Should the plan record them as upstream
  work, sent separately? (§5.6)
- **QA2. The scope of a solve.** Per-function solves with summaries
  (Design 1) as the default for per-value analyses, accepting less
  precision inside recursive SCCs, or whole-program solves (Design 2)
  wherever they measure small enough after U1? (§5.1)
- **QA3. `remove-dead-values`.** Split it (upstream's pass per function,
  our signature solver over the call graph), or run it on the whole
  module on the patched framework? (§5.1)
- **QA4. One state representation.** May the solver layer fix one state
  representation for all our solvers (dense per-function numbering,
  arrays and bit vectors, templates and concepts), so that every solver
  of ours shares it? (§5.1)
- **Q-O2. The model.** A constraint-generating abstract interpreter
  (facts per SSA value, flow-insensitive, cells with handlers: MLton's
  model, and the direction ffa91113 and b8301ebe already took) named as
  *the* solver layer, with `DataFlowSolver` kept only for intraprocedural
  analyses whose state fits? (§5.9 design 1)
- **Q-E1. The architecture.** One maintained program graph and three
  solve shapes: summaries over the call graph's SCCs, local solves per
  function, and extract-solve-write-back. Or is there a problem of ours
  already known not to fit any of the three? (§5.6 Design 1)
- **QL3. How analyses are stated.** As rules over relations (Flix,
  Soufflé: composing analyses is the union of their rules), or as
  transfer functions over one engine? The theory favours rules; the cost
  is an engine that understands them. (§5.7 D4, L2)
- **Q-M1. The spine.** One call-graph schedule for every summary analysis
  (callees first and callers first), on MLIR's thread pool: as a port of
  Modular's `SCCGraph` (its header kept, a `PINS.md` entry, as the
  deduplicator's port has), or a fresh implementation informed by it?
  (§5.4 design 1)
- **QL1. The solver's input.** A scoped, read-only array view of the IR,
  built per solve and freed after it (it restates def-use structure for
  the length of one solve), or every solver directly over MLIR `Value`s,
  keyed by hash maps? (§5.7 L2)
- **Q-llvm-3. Numbering.** MLIR numbers blocks at the pin but nothing
  numbers ops or values. Number per solve, hold a numbering as a cached
  analysis in the `AnalysisManager`, or patch upstream to give ops or
  values numbers like LLVM's blocks? (§5.3 B7, S1)
- **Q-llvm-2. Budgets.** Analyses a refusal rests on have no budget
  (finite height or widening only); optimization-only analyses may stop
  at one and take the pessimistic state (the Attributor's rule); a spent
  budget is never an error. Confirm. (§5.3 C1, C5)
- **Q-E3. Budgets, the same line from the ecosystem.** An optimizing
  analysis may stop at a budget and finalize pessimistically, reporting
  success; an analysis a refusal rests on has no budget and terminates by
  its lattice. (IREE turns its round budget into compile errors, which
  AGENTS.md forbids.) Answer with Q-llvm-2 and oom-2. (§5.6 item 5)
- **Q-llvm-7. The giant SCC.** If one call-graph component holds most of
  the frontend (an elaborator is mutually recursive), component-level
  parallelism buys nothing there: is solving it serially acceptable, or
  should the layer carry lld's double-buffered rounds from the start?
  (§5.3 D2)

### 8.5 Counting and ownership

- **rc-Q1. Borrow inference.** Koka turned it off, because a borrowed
  parameter can hold memory the callee would have freed, by an amount no
  constant bounds; Lean infers it per SCC and lets a user annotation
  override its heuristic part; MLIR's deallocation fixes it by ABI. Keep
  inferring borrows, restrict inference to the frame-limited cases (the
  caller uses the argument later, or it has constant size), or declare
  borrowing only on runtime primitives? (§5.10 A5, A6, B2, G5)
- **rc-Q2. How much exclusivity is static.** Prove what one marking can
  and test the rest at run time (R1), or also specialize functions by
  grade under `idr-optimize`'s budget (R2), at a cost in code size and a
  change of pipeline order? And is a run-time uniqueness test an
  acceptable fallback where the proof fails (linearity is a performance
  property, so the test changes speed, never meaning)? (§5.10 R1, R2)
- **rc-Q3. A space guarantee.** Perceus's insertion is garbage-free;
  drop-guided reuse is frame-limited; reuse before insertion and
  unrestricted borrowing are neither. Should compiled programs carry one
  of these as a stated property, with a test, as the grades are
  verified? (§5.10 A5)
- **rc-Q5. Drops at last use.** Idris has no user-visible destructors, so
  nothing needs Swift's lexical lifetimes: confirm that drops go at last
  use, everywhere. (§5.10 C3)

### 8.6 Verification

Three lanes raise one question from three sides; answer them together.
- **ods-Q6.** Accept that a module pass re-verifies all 70,000 functions,
  or make nesting on functions a rule of the pipeline's design, so that
  verification is per function and parallel? (§5.2 H3, M11)
- **Q-M2.** Keep full verification after every pass in release builds, or
  split it: the grade check after every pass always, MLIR's structural
  verifier after every pass in development builds and at phase
  boundaries in release (Modular's practice)? (§5.4 F16)
- **Q-O5.** MLton verifies at IR boundaries. Keep AGENTS.md's grade
  verification after every pass as the contract, and treat its cost at
  70,000 functions as a measured budget of the verifier? (§5.9)

### 8.7 Threading and determinism

- **QL4.** Is byte-identical output for any thread count a requirement?
  It fixes the threading rules: sorted hand-offs, ids assigned after the
  fixpoint, no thread-tagged ids in output. (§5.7 A2, G3)
- **Q-llvm-6.** Should every solver be tested by running it with one
  thread and with many and comparing the frozen solutions? (§5.3)
- **rc-Q4. Threads and shards.** Confirm that no counted cell is ever
  shared between threads, so that the runtime needs no atomic count and
  no mark-shared pass, and say what proposal 0007's shards will pass
  between them (ORCA's messages are the model if anything is). (§5.10 F2)

### 8.8 Specialization and pass order

- **Q-O4.** MLton specializes higher-order functions before its flow
  analysis; we specialize after defunctionalization. Should the order be
  studied, given that it changes what the label solve sees? (§5.9
  design 7)
- **Q-M5.** Mojo's elaborator is demand-driven from roots, with
  suspension; our optimizer runs each function once, bottom-up. Should
  wave 2 weigh moving specialization to Mojo's shape, or is bottom-up
  settled? (§5.4 design 5)

### 8.9 C++

- **Q1. Interfaces and concepts.** The representation-first skill says
  shared shape is "an interface ...; never an `isa<A, B>` ladder or a C++
  concept"; §1 asks for concept-heavy C++. The reading proposed: MLIR
  interfaces and traits for anything over ops, types and attributes;
  templates and concepts for our own C++ (the solver layer, utilities,
  pass internals). Is that the line, and should the skill say so?
- **Q-M3.** Modular writes no concepts; its templates are CRTP over op
  and interface types. Is a concept-constrained problem type (§5.4
  design 1's `SummaryProblem`) the C++ §1 wants, inside Q1's line?
  (§5.4 F13)
- **Q-llvm-1. Monomorphized or type-erased core.** clang chose a CRTP
  adapter over a core compiled once, and SCCP a pimpl, both for compile
  time. The proposal is one explicit instantiation of `solve` per
  analysis, each in its own translation unit, with compile time measured
  as part of P0. Is that the line? (§5.3 C2, C5, S1)
- **cxx-Q1 (input to Q1).** The line made precise: MLIR interfaces,
  traits and op-rooted patterns for anything over ops, types and
  attributes; templates and concepts below the dispatch and over our own
  C++ types; a concept may read ODS (a trait, interface membership: both
  compile-time constants) and may never list ops. The skill would then
  read "never an `isa<A, B>` ladder or a C++ concept that lists ops".
  (§5.5 D1)
- **Variants: Q-llvm-4 and cxx-Q2 conflict; decide them together.**
  - **Q-llvm-4.** A hard rule for the cutover banning
    `get_if`/`holds_alternative` chains in favour of one exhaustive
    `std::visit` (or `PointerUnion` for handles), or wave 2's judgement
    case by case? (§5.3 I3, I4)
  - **cxx-Q2.** Ban `std::visit` itself in favour of one fold `match`, or
    allow it on variants of at most 11 alternatives? Measured: above 11,
    libc++ dispatches through a function-pointer table (300 sites,
    11.3 s and 3 MB, against 2.0 s and 68 KB for the fold, which
    compiles to a jump table). (§5.5 D2, finding 12)
- **cxx-Q3. Headers.** Precompiled headers for `foreign/idr` now, C++20
  modules and `import std` not in P0? (§5.5 D6, D7)
- **cxx-Q4. Hardening.** Which libc++ hardening mode for debug and test
  builds of the pinned, static libc++, and is release measured or left
  unchecked? (§5.5 D8)
- **cxx-Q5. Reflection.** Static reflection is not usable at the pin (only
  `^^` on builtin types behind a cc1 flag) and P0 does not wait for it:
  agreed, or should P0 plan a later pin bump for it? (§5.5 D9)

### 8.10 Rewrites and tools

- **ods-Q4. DRR allowed, PDLL refused?** PDLL has no production user at
  the pin and runs on an interpreter; DRR generates native, rooted
  patterns. (§5.2 E4, M13)
- **Q-llvm-5. One TableGen tool.** Should `idris-mlir-tblgen` become a
  generator registered in a tool built on `MlirTblgenMain`, reading ops,
  traits and effects through `mlir::tblgen::Operator` and `SideEffect`
  rather than raw records, so that one tool generates both the C++ and
  the Idris mirror? (§5.3 E3)

### 8.11 Running out of memory

The lane ranks these: the first four shape P0's runtime C++ and the
pipeline's instrumentation; the rest wait until a program or a shard
needs them. oom-2 bears on Q-llvm-2 (budgets), and oom-3 on Q4
(measurements).

*Urgent:*
- **oom-1. Outside the language.** Is running out of memory outside the
  language's meaning, a named crash of the machine as a stack overflow
  is, and never a value or an effect in the types? (The lane's reading:
  yes.) (§5.11.2)
- **oom-2. The compiler running out.** Is it a crash, distinct from a
  refusal, so that a named line on pressure is allowed by "a budget never
  rejects a program"? And is every compiler budget counted in the
  program's units (ops, rewrites), never bytes or seconds, which is what
  keeps stage 2 = stage 3? (§5.11 A3, A4, C7)
- **oom-3. A footprint record per pass.** Does P0 include one, and which
  measure: `phys_footprint` on macOS (what jetsam reads, compressed pages
  included); on Linux the cgroup's, or resident plus swap? (§5.11 A2)
- **oom-4. Stack probes on all four targets.** A correctness item: without
  them, a frame larger than the guard page skips it and an overflow
  corrupts memory silently. (§5.11 B2)

*Can wait:*
- **oom-5. A memory limit for programs:** off by default, set by an
  environment variable, or read from the cgroup's `memory.max` by
  default? A counter in the allocator's chain of ranges, or the
  reservation's size? (§5.11 B4)
- **oom-6. Exit statuses:** one for an out-of-memory crash and one for a
  stack overflow, distinct from other crashes?
- **oom-7. Returning the stack's pages** after deep recursion, once 0006
  measures it. (§5.11 B5)
- **oom-8. A pressure signal** in the runtime, for releasing slack only.
  (§5.11 B6)
- **oom-9. Shards:** a process-wide limit only, and a reactor that drains
  its allocator's remote frees before it blocks?

### 8.12 From wave 2

New questions the wave-2 lanes raise from our code, by lane, as each
finishes (`audits/p0/`); they move into the groups above when the plan is
reconciled.

*frontend-checks* (`audits/p0/16-frontend-checks.md` §6):
- **Q-fc-1. The proof's model and the code.** Theorem 1 is proved over a
  model of templates (`Proof/Bound.idr`'s `Term m`, three constructors),
  and the frontend builds no derivation: a run-time witness
  (`Finite.heightWithin`, `sizedWithin`, `Translate/Types.idr:853`) bridges
  proof and code, an internal error that would fire on a frontend bug,
  never on a user program. Should the cutover make the code's `Template`
  the model (the frontend builds the derivation and the witness goes), or
  is the witness the accepted bridge, recorded as a trust point the way
  AGENTS.md records `covering`?
- **Q-fc-2. Context-sensitive flow as a representation fix.** If stage 1
  shows the node split's product (`Heads.combinations`,
  `Graph.familyHeads`) to be large, the fix that keeps acceptance
  unchanged is a flow split by node (context-sensitive), at the price of a
  larger flow solve. Is that the direction, given that no budget may cut
  an acceptance analysis?

*canon* (`audits/p0/04-canon.md` §6; the lane's NQ1–NQ5 are canon-Q1–Q5):
- **canon-Q1. Pre-defunctionalization canonical forms.** No canonicalizer
  runs before `idr-defunctionalize`, so the force, suspension and closure
  canonicalizations (two patterns, three folds, arms in `feeds` and
  `Sink`) are reached only by their fixtures. Add a canonicalization
  before defunctionalization, where they would shrink the closure sets
  the label solve sees, or delete them with their fixtures?
- **canon-Q2. A rewrite budget for canonicalization.** `maxNumRewrites` is
  unset, so a cycle of patterns hangs inside one iteration (c179ab2d).
  Set it per run to a multiple of the function's op count, a budget in
  the program's units that leaves a function less canonical and never
  fails, with `test-convergence=true` in the tests still reporting the
  cycle? Answer with Q-llvm-2, Q-E3 and oom-2.
- **canon-Q3. Output's canonical direction.** Canon fuses (`put_str(show_sint
  x)` to `put_sint x`); §5.8 composes (a pure `show` and one write, fused
  at lowering). Which is the canonical form?
- **canon-Q4. Which dialects' canonicalizations.** The canonicalizer
  collects every loaded dialect's and registered op's patterns; the pin's
  `filter-dialects` can name them. Name them (idr, arith, ub, and those
  each pipeline point needs)?
- **canon-Q5. Canonicalization's place.** Keep it a pass at four pipeline
  points and in idr-optimize's inner pipeline, on upstream's greedy
  driver, or move to MLton's shape: one per-function normalizer each pass
  calls on what it rewrote, on the walk driver, with the greedy driver
  kept only for upstream's folds and patterns (§5.9 Design 5)?

*tail* (`audits/p0/10-tail.md` §6; the lane's NQ-1–NQ-4 are tail-Q1–Q4):
- **tail-Q1. Tail position in the call.** Should "this call is in tail
  position" be a property of `idr.call` (MLton's `Return.t`, §5.9 C3),
  written by the passes that make tail calls, checked by the call's
  verifier, and lowered into `llvm.call`'s `tail_call_kind`, so that
  neither `IR/Tail.cpp`'s per-query climb nor `TailPosition.cpp`'s path
  walk exists? Or a cached analysis per function, with the walk on the
  LLVM dialect kept? Bears on DD-Q7 and Q-O1.
- **tail-Q2. The constant-stack promise.** Is "a mutual tail recursion and
  an IO loop run in constant stack" part of a program's meaning (then a
  tail call on a cycle left as a call is a broken contract between
  idr-rc-stack and idr-tail-calls, an internal error), or a performance
  property (then a statistic, as today)? The same for a frames component
  left without a plan, whose left-nested binds keep their stack growth
  with nothing said.
- **tail-Q3. Frames' stack per result type.** One stack data type per
  member result type (a mutually recursive group), making "a frame of
  another type on top" unrepresentable and deleting the impossible empty
  cases in every resume; or one stack type per component, the impossible
  cases moved to a default region?
- **tail-Q4. Case blocks at the boundary.** Once the fork's TTC keeps a
  block's parent (0003 B1), should the frontend emit a clause's case block
  in place, as a match region of its parent, so that idr-contify sees only
  what the compiler itself makes? (Lanes 15 and 17 hold the evidence.)

*idris-dialect-side* (`audits/p0/14-idris-dialect-side.md` §6; the lane's
NQ-14-1–6 are ids-Q1–Q6):
- **ids-Q1. Checked-in generated modules.** The fifteen generated Idris
  modules are in git so the Idris build needs no other step and an ODS
  change shows as a change of the Idris it means; their fingerprints cover
  the generator's source, so 16 of the 29 commits touching `Syntax/Idr.idr`
  restamped one line. Keep them checked in (fingerprinting only the
  records and the output), or make them build outputs of `make build`,
  which already runs the generator?
- **ids-Q2. Native properties from the frontend.** The Idris writer puts
  inherent attributes in each op's dictionary, so every property of an op
  the frontend writes must be an attribute. Accept that as a constraint
  on the ODS redesign (§5.2's properties only for ops the frontend never
  writes), or generate each op's property encoder for the Idris writer?
- **ids-Q3. The handoff's text.** Encode every `idr` type and attribute
  natively in bytecode, deleting the copied declarative-format parser and
  the Idris printers; or keep text and patch upstream to make the format
  parser a library? Answer with Q-llvm-5.
- **ids-Q4. Generated binder names.** Prime every generated parameter
  (`(lhs' : Value)`), so no keyword list is kept, or keep the list, copied
  from the fork's lexer?
- **ids-Q5. ODS naming the Idris primitive.** Should an op's record name
  the base primitive it implements, so the registry's IO rows are
  generated, or does the registry stay the one place that names a library
  definition? Bears on DD-Q5.
- **ids-Q6. The `Faster` property as a test.** Nothing checks AGENTS.md's
  "removing the hook leaves the same result". A mode that drops the
  `Faster` hooks, and a test that compiles each program both ways and
  compares exit, output and refusals (no Chez involved, so no oracle):
  wanted, or is the rule a review rule?

*defunc* (`audits/p0/06-defunc.md` §6; the lane's NQ-defunc-1–4 are
defunc-Q1–Q4):
- **defunc-Q1. Deduplication across cycles.** Partition refinement merges
  duplicates inside call-graph cycles, which today's pass never does
  (`EliminateDuplicateFunctions.cpp:142`); it changes which functions
  survive and where their locations point. Adopt it, or keep the exclusion
  with CIRCT's barrier-free hashing? Answer with Q-M4 and Q-E4.
- **defunc-Q2. Effects before the conversion.** Fold idr-effects into
  defunctionalization's decision (one summary over calls and label runs
  that also decides `by_name`, idr-optimize keeping it current), or keep a
  separate pass after the conversion?
- **defunc-Q3. Types first.** Replace the per-function dialect conversion
  by one walk that writes the decision into the types, legality checked by
  the stage verifier, though the skill names `TypeConverter` and
  `ConversionTarget` for lowering? The types here depend on the value (its
  flow set), not the type, which is why the pass keeps a plan per function
  today.
- **defunc-Q4. One sink per operand.** A use that moves into two points
  unifies them (`LabelSites.cpp:106-110`), coarsening both sets so the plan
  holds one key per use. Keep, or let the operand be coerced into each
  sink?

*counting* (`audits/p0/08-counting.md` §6.1; the lane's NQ1–NQ4 are
count-Q1–Q4):
- **count-Q1. The in-place promise: the program's or the optimizer's?**
  idr-demand binds the promise only where an `idr.cell.recycle` takes its
  token from a take of the parameter (`Demand.cpp:59-77`). So skipping one
  reuse action (an MLIR action a debug counter can skip), or idr-rc-stack
  making the parameter a frame value, removes the promise and with it the
  refusal; and `sinkConsumers` (`Reshape.cpp:149-210`), an optimization,
  decides whether a dup appears, hence exclusivity, hence the verdict.
  AGENTS.md: acceptance is a property of the program, never of the
  optimizer. Should the promise be stated where it is made (the
  `in_place` type and the function's own rebuild of a quantity-1
  parameter, before counting), with stack and reuse bound to honour it?
  (*read* chain; no program run to show it.) Answer with own-Q2.
- **count-Q2. Reuse before or after borrow inference?** Today reuse is
  decided first and borrow inference keeps a reused parameter owned
  (Lean's order); drop-guided reuse after placement (Koka's) deletes the
  simulation but needs the forced-owned reason from somewhere else.
  Answer with own-Q1, rc-Q1 and rc-Q3.
- **count-Q3. Counting before or after TRMC?** Borrows predicts idr-trmc's
  tail calls today; Koka runs TRMC first.
- **count-Q4. Conventions on the call?** `idr.call` already copies and
  verifies its callee's `effects`; should it carry its callee's parameter
  conventions the same way, so consumption is read off the call and
  grading can run nested on functions? Bears on DD-Q7 and tail-Q1.

*ownership-analysis* (`audits/p0/07-ownership-analysis.md` §6; the lane's
NQ1–NQ3 are own-Q1–Q3):
- **own-Q1. Reuse before or after counting.** Lean's order (reuse decided
  before borrow inference and placement, so a take wins over a borrow),
  with the decision made as IR at once; or Koka's (drop-guided reuse
  after placement, so a borrow wins and reuse can be frame-limited)?
  Answer with count-Q2.
- **own-Q2. What specifies the uniqueness refusal.** idr-demand refuses on
  the grades exclusivity writes, so a precision fix or a redesign changes
  which programs pass. Is `unsupported (uniqueness)` defined by the
  analysis's answer (a more precise analysis admits more programs), or by
  a declarative rule the analysis must decide exactly, with a test of the
  rule's boundary? Answer with count-Q1.
- **own-Q3. Grade copies' home.** Grade specialization (inside
  idr-rc-exclusive) and the optimizer's specialization are two
  specializers. Should the grade be a key of the one specializer (§5.10
  R2), or stay where exclusivity is solved, after optimization? Answer
  with rc-Q2.

*conversion* (`audits/p0/12-conversion.md` §6; the lane's NQ1–NQ5 are
conv-Q1–Q5):
- **conv-Q1. One meaning for the scalar primitives.** Euclidean division,
  the total shifts and the scalar-value test are written in C++ twice
  (folder, lowering) and division a third time in the runtime; none is a
  runtime primitive, so AGENTS.md's "its one meaning is the runtime's,
  which folders call too" is not kept for them. Make each a runtime
  function, or allow one C++ template instantiated for folding and for
  lowering as the one meaning? Answer with ops-Q2.
- **conv-Q2. `idr-lower` under the pass manager.** That needs every runtime
  function declared and every static datum made before the function pass:
  accept those two program passes, or keep the worker-and-merge scheduler
  as an honest scheduler of ours, said so in its header?
- **conv-Q3. The take's expansion.** Is it counting's last step at the idr
  level (the test, the moves, the counts), leaving the lowering only
  primitive ops, or does it stay the lowering's?
- **conv-Q4. Crash sites as data.** May a crash site reach the runtime as
  (cause, file, line, column), an ABI change, instead of one message
  string per site? Bears on oom-6.
- **conv-Q5. Mangling.** May the mangling prefix every program symbol, so
  that no program symbol can be a runtime symbol or `main`?

*ods-ops* (`audits/p0/03-ods-ops.md` §6; the lane's NQ1–NQ4 are
ops-Q1–Q4):
- **ops-Q1. A refined constructor type.** Should a case region bind the
  scrutinee at a type naming its constructor (`!idr.ctor<T, @C>`), so
  `field`, `take` and `unpack` lose their `tag` attribute and a field read
  of the wrong constructor is unwritable? QL2 in typed form; answer with
  QL2 and Q-O1.
- **ops-Q2. Ops with no runtime function.** `divs`, `mods`, the four shifts
  and `to_char_s/u` have no runtime function; their meaning is written
  twice in C++. Should the runtime gain them (one meaning in `runtime/`,
  which the folders call), or is their expansion into `arith` the one
  meaning? Answer with conv-Q1.
- **ops-Q3. Guards on upstream ops.** May the frontend guard an `arith` op
  (`check.nonzero` then `arith.divui`) through a generated pairing record,
  so `divu` and `modu` leave the dialect?
- **ops-Q4. The stage on the ops.** Should each op family declare the
  stages it is legal at (a generated trait), replacing the program
  verifier's stage rule for ops?

*frontend-translate* (`audits/p0/15-frontend-translate.md` §6; the lane's
NQ-1–NQ-5 are ft-Q1–Q5):
- **ft-Q1. Representation choices: frontend or dialect?** The frontend
  collapses a type with one runtime field to its field, maps Nat-likes to
  `!idr.nat` and pointer-like word types to `u64`, and enumerates crash
  alternatives, while `Term.idr:110-112` says layout is "the dialect's
  decision, made once from the type graph". Move these to the dialect, or
  are they Idris facts the frontend states?
- **ft-Q2. 0011's O2 and O3 inside P0?** Core as tables (O2) and Translate
  as semi-naive over an interned instance table (O3) are marked after
  self-hosting; the lane's D-1, D-3 and D-5 are their smaller form. Take
  the small form in P0, or fold O2 and O3 into the cutover? Answer with
  hist-Q4.
- **ft-Q3. Polyvariance in the frontend?** If Q-O4 is studied, is the
  frontend the place (it has the lambdas, the keys and the bound), with
  the C++ specializer keeping only what flows through data?
- **ft-Q4. The Core dump.** It is the whole program a second time (79 MB
  on the self compile), read by the harness's prelude coverage and one
  test. Keep it (streamed), or make the module the one output and move
  its readers onto the module?
- **ft-Q5. A refusal in the fork's `Error`?** `TS.inFlight` exists because
  Idris's `Error` cannot carry a refusal. May the fork (ours) gain a
  constructor for the frontend's refusal, so the side channel and the
  dedupe by printed text go?

*runtime* (`audits/p0/18-runtime.md` §6; the lane's N1–N5 are rt-Q1–Q5):
- **rt-Q1. The count's encoding.** Adopt Koka's signed count without its
  atomic half (0 = unique, negative = sticky), after a measurement, at the
  cost of moving "count 0 is persistent" (static data, 0007's detach
  table) to the sticky constant? Bears on rc-Q4.
- **rt-Q2. Live cells in shipped programs.** Every program counts every
  allocation in a `thread_local` and reads `IDRIS_RT_LIVE` at exit, for
  the harness's leak check. Move the count to the checked runtime, so the
  leak check runs there and shipped programs carry neither?
- **rt-Q3. Strict hosts.** A program cannot start today under Linux
  overcommit mode 2 or a `ulimit -v` below its reservations (64 GiB of
  stack, 4 GiB of heap region, snmalloc's pagemap); 1445d894 chose one
  constant knowingly. Should programs start there, or is that outside
  what a program promises? Answer with oom-5.
- **rt-Q4. Test seams in the runtime's sources.** `IDRIS_RT_IO_BUFFER_SIZE`
  (`Io/Io.h:26-29`) is a knob a test compiles in: keep it as a seam, or
  require the test to work through the shipped buffer?
- **rt-Q5. snmalloc's config.** Patch snmalloc upstream for a seed-range
  hook, or keep our copy of its standard config with a test comparing it
  to the pinned one?

*arrays* (`audits/p0/11-arrays.md` §6; the lane's N1–N5 are arr-Q1–Q5):
- **arr-Q1. 0009's stage-2 decision, inside P0?** "Buffers in data-type
  bodies", with `!idr.lin<T>` tensor-like per instance (0009 §16, §20
  item 2), deletes the retype after bufferization and the release and link
  models; it is "a decision for stage 2" and reverses 0009 §8's reason for
  keeping the grade off `TensorLikeType`. Does P0 take it, with its two
  upstream patches (27, a per-instance `extraClassOf`), or leave it to
  0009?
- **arr-Q2. Is a link an op?** Whether an `idr.lin.enter` is a link (in
  place, always) or a head (may copy) is re-proved by an analysis on every
  query (`Linear.cpp:32-50`), though the translation knows when it threads
  one `LArray` across a boundary. One op per kind, the check then
  confirming the op, or one op with the fact computed once?
- **arr-Q3. Where the generating set's one meaning lives.** AGENTS.md: "A
  primitive of `libs/` (an `%extern`) means only what `runtime/` says";
  `Array.Core`'s 21 externs mean what the dialect's ops mean
  (`Core.idr:12-16`, `IdrArrayOps.td`'s descriptions and the lowerings),
  not a runtime function. Should AGENTS.md (or 0009) name the dialect as
  their one meaning? Answer with conv-Q1 and ops-Q2.
- **arr-Q4. Transposition as a tabulate.** Delete `idr.transpose`: the
  frontend writes a transpose as a tabulate of a permuted read, and
  linalg's specialization names it again. Acceptable, given 0009 §3.1's
  "the leading axis is reached through `transpose`, which is an indexing
  map"?
- **arr-Q5. 0009's MLIR form for the generating ops, in P0?**
  Destination-style ops, `TilingInterface`, the ordered form through
  upstream after bufferization: P0's direction, but 0009 places its pieces
  in stages 3 and 4. In P0's cutover, or after it?

*analyses* (`audits/p0/05-analyses.md` §6; the lane's Q-AN1–Q-AN3):
- **Q-AN1. Tail calls and given-back arguments in the IR.** May "a call is a
  tail call" and "a function gives back argument i" become function and
  call facts carried in the IR and verified, as `effects` already is, so
  their re-derivations (seven tail-position readers, the whole-module
  Returned solve) are deleted? Answer with tail-Q1, Q-O3 and Q-E2.
- **Q-AN2. The optimizer and the shared spine.** Is the optimizer's dynamic
  schedule (nodes inserted and SCCs merged during the solve) the shared
  spine's job, or is the optimizer the one dynamic client of a static
  spine? Answer with Q-M1 and Q-E1.
- **Q-AN3. Ranges.** Per function with callers-first argument summaries, or
  a measured whole-program solve after the storage patch (QA1's U1)? The
  one analysis of the lane where QA2's answer changes the code.

*ods-types* (`audits/p0/01-ods-types.md` §6; the lane's NQ1–NQ4 are
types-Q1–Q4):
- **types-Q1. Where the owned rule runs.** OSSA's checker follows def-use
  chains, which MLIR's verifier doctrine keeps out of op verifiers. Keep
  it in `idr.func`'s region verifier (after every pass, parallel, as
  today), or make it a check pass the pipeline's instrumentation runs after
  every pass (the transform dialect's `check-uses` shape), with the region
  verifier keeping only local rules? Answer with the 8.6 group.
- **types-Q2. Who decides the boxes.** The frontend emits every type in
  place and `layout::fit` boxes the cycles by a whole-program remap at
  defunctionalization. Should the frontend emit the boxes (it holds the
  whole table), so a table is never cyclic in place, `DataTableAttr::verify`
  refuses a cycle once per table, and `fit` with its remap goes? Answer
  with ft-Q1.
- **types-Q3. Plain before and after counting.** `Permission::Plain` means
  "nothing decided" before idr-rc and "holds no reference" after; the
  program's stage says which. Two cases of the permission (one only before
  counting), or one case read by stage?
- **types-Q4. A closed grade set without an interface.** §5.8 proposes a
  grade attribute interface; our grades are one closed set (six quantity
  and permission pairs occur), and the skill forbids an interface where
  the type fixes the implementation. One grade attribute with methods:
  agreed? Answer with DD-Q1.

*fork-boundary* (`audits/p0/17-fork-boundary.md` §6; Q-FB1–Q-FB3):
- **Q-FB1. The run-time case tree.** Keep an erasure-only run-time tree in
  the TTC (a fork deviation: built without `%transform` and `%spec`) and
  have the frontend translate it, deleting `Translate/Forced.idr` and the
  erasure at each application; or stop building it (it is computed and
  discarded today) and keep 0003's plan (`scTy`, the clause index),
  erasing from Idris's own `eraseArgs`? Answer with hist-Q4 and tail-Q4.
- **Q-FB2. A linear binder used twice after translation.** Emit holds a
  quantity-1 binder plain when the translated body uses it twice. Is that
  a demotion the boundary may make and state, an internal error (the
  translation must keep Idris's proof), or a refusal?
- **Q-FB3. Elaboration decided by a count.** `%ambiguity_depth` (3) and
  `%auto_implicit_depth` (50) make Idris refuse a program when a count runs
  out, as `%totality_depth` did until the fork removed it. Remove them the
  same way, or accept them as Idris's type checking, outside AGENTS.md's
  "a count is never a reason to refuse"?

*optimize* (`audits/p0/09-optimize.md` §6; Q-opt-1–Q-opt-4):
- **Q-opt-1. Interleave, or MLton's order?** Keep inlining and
  specialization interleaved per round, or specialize to completion and
  then decide inlining once on the final graph with true call counts, then
  normalize? Interleaving finds keys only inlining exposes; separating
  them removes two classes of blow-up but loses those keys unless
  specialization runs a second time. Answer with Q-O4 and Q-M5.
- **Q-opt-2. A made node's call count.** Count its requesters, known only
  once every caller has run, or weigh a made node only as a leaf or a beta
  step?
- **Q-opt-3. Keys outside the context.** Keys are held by no op: may they
  be the run's own interned data, freed with the pass and taking no
  context lock, or must they stay attributes so that tools can print them?
- **Q-opt-4. Our half of a split QA3.** If `remove-dead-values` is split,
  may the signature half live in idr-optimize's summary (parameters
  bottom-up, results in a callers-first pass) rather than in a separate
  solver? Answer with QA3.

*driver-pipeline* (`audits/p0/13-driver-pipeline.md` §6; the lane's NQ1–NQ6
are drv-Q1–Q6):
- **drv-Q1. Assertions in measurements.** Stage 2, which every build of
  idris-mlir links, has `LLVM_ENABLE_ASSERTIONS=ON`. Should P0's stage-1
  measurements be taken on an LLVM without assertions (a second stage-2
  build, or assertions off for the one toolchain, which the dev build then
  loses), or stated as including them? Answer with Q4.
- **drv-Q2. The pipeline as one TableGen list** (order, reasons, options),
  its stage chain asserted in TableGen and its nesting computed from
  anchors, generating the textual pipeline, the registrations and the
  tests' table?
- **drv-Q3. Decide, apply, restructure** as the rule for every lane's
  passes: a decide pass computes a whole-program fact and changes nothing
  (no verification), nested apply passes rewrite each function in
  parallel from the cached fact, and only a restructure pass changes the
  program's shape? Answer with ods-Q6.
- **drv-Q4. Worker stacks.** The context's workers on reserved stacks like
  the main thread, through a pool of ours or upstream's `StdThreadPool`
  given a stack size? Today a pass's recursion limit depends on the thread
  it runs on and the OS.
- **drv-Q5. The prepared runtime's bitcode** in one home on every target
  (beside the object), removing a per-target fact branched on in four
  places?
- **drv-Q6. Profiling stage 1.** One buffered time trace flushed on memory
  pressure, or MLIR's streamed action profile (a lock and a flush per
  event; about 1 GB a minute in idr-optimize)? Answer with oom-3.

*tests-harness* (`audits/p0/19-tests-harness.md` §6; T-Q1–T-Q5):
- **T-Q1. The cutover's invariant oracle.** Should P0 name the program
  tests (234, 907 cases), the rejects with their neighbours, the semantics
  runs, the benchmarks' outputs and the fuzz seeds as the set every step
  must pass unchanged, so that no step's correctness rests on tests the
  same step rewrote? Answer with hist-Q2.
- **T-Q2. Rewriting the fixtures.** 339 fixtures hold 26,025 names of
  today's dialect. Rewrite them by hand in the cutover, convert them once
  by a script that is not kept, or replace each that can be a program test
  by one?
- **T-Q3. idr-expect's names.** Are the 82 property names and argument
  shapes a frozen test API across P0 (their implementations restated over
  declared facts), or open to DD-Q8's renames like everything else?
- **T-Q4. Contracts at scale.** Keep `--idr-contracts` test-only, and move
  it from a module clone per pass to per-function records under P0's
  nesting?
- **T-Q5. Measuring the verifier.** Measure the verifier from
  `--mlir-timing`'s rows, keeping `tests/verifier-every-pass`'s rule whole,
  or allow a `--verify-each=0` run outside the tree for the measurement?

*ods-effects* (`audits/p0/02-ods-effects.md` §6; the lane's
ods-eff-NQ1–NQ4 are eff-Q1–Q4; answer them with the 8.1 group):
- **eff-Q1. What a function's `effects` summarize.** Only {io, crash,
  diverge}, as today, or every state a caller must order with, including
  memory its arguments reach and memo state? Today memory is carried
  across a call by the root resource's accident and memo state not at all;
  the resource tree cannot land without the answer.
- **eff-Q2. Ending the process.** Is `exit` a crash, a divergence, or an
  effect of its own? It never returns, yet the summary says a function
  that always exits returns. Answer with ods-Q1 and DD-Q2.
- **eff-Q3. A closure's cell before counting.** May CSE merge two equal
  closures, suspensions or evaluated suspensions into one cell, as it may
  today (they declare no allocation), while a box's `con` may not
  (`OpsCon.cpp:50-56`)? Declaring their allocation stops it.
- **eff-Q4. Runtime state.** Are `handle.string`'s read of the handle table
  and `io.strerror`'s read of the C library's text IO, ordered with
  output, or a state ordered only with what changes it (`io.handle_free`,
  a failing call)? Today both are `IOResource`; `io.strerror` is
  deliberately not observable (`IdrPlatformOps.td:311-313`).

*perf-tracing* (`audits/p0/21-perf-tracing.md` §6.2; the lane's
NQ-21-1–3 are perf-Q1–Q3):
- **perf-Q1. The parallel agent and D4.** Does "no code until the whole
  plan is approved" bind the agent working 0001's S3, or may it keep
  changing counting, exclusivity, the stack inference and the trait layer
  on main while P0's lanes plan the same code? If it may, should its
  changes be limited to fixes that unblock a stage-1 measurement, each with
  a record, and its four trait waves be P0's ods lanes' work rather than
  landed ahead of them? Answer with Q2 and hist-Q5.
- **perf-Q2. `Positions` (101edbc5): the scope, or an interim?** It is
  defective on main (`make test` 403/480 at 101edbc5, against 470/480 at
  e96bb991; recorded by 51a4771b). Repair it toward the per-function scope
  P0 builds on (a coordinate per block, an analysis, one numbering shared
  with the owned verifier, invalidated by a rewriter listener), revert to
  e96bb991's queries until P0, or treat it as the interim that counting's
  one reverse walk deletes?
- **perf-Q3. A record per stage-1 run.** Should every stage-1 run leave a
  record under `bench/records/` (how far it got, per-pass time, footprint
  and its measure), wall or not, replacing 0001's "a record when both
  halves exit 0", so that P0's designs have a baseline? Answer with Q4,
  oom-3 and drv-Q1.

*history* (`audits/p0/20-history.md` §6; the lane's NQ1–NQ5 are hist-Q1–Q5):
- **hist-Q1. Measure before adopting, patch before dropping.** Should P0 make
  it a rule (AGENTS.md or §4) that an upstream mechanism is adopted only
  with a measurement at stage-1 scale, and removed only with the upstream
  patch tried or a measurement showing the state is essential? The
  history has one adoption (595ed341) and two removals (ffa91113,
  16005000) that would each have failed it.
- **hist-Q2. Unbuilt landings.** May P0 land as type-checked, unbuilt waves, as
  the waves of 10-14 to 10-18 did, or must every step build and pass the
  five suites and a stage-1 run on the build machine before the next? The
  full suite has not been green since those waves (415/415 on 10-14,
  470/480 now).
- **hist-Q3. Patches that reach nothing.** 06, 28 and 63 reach no pass of ours
  today: retire them now by `upstream/README.md`'s procedure, or hold them
  until QA3 is answered?
- **hist-Q4. P0 and 0003.** 0003 (each fact once) is queued after
  self-hosting, P0 before it, and P0's goal includes "no rederivation
  chains": does P0 absorb 0003, or leave its 21 standing items for later?
- **hist-Q5. Reversals.** May an agent reverse a recorded design (an engine, a
  type's representation) without a dated ruling from the owner, as
  595ed341 to ffa91113 and the static-lifetime cutover were?

