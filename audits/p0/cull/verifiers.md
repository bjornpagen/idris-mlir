<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Cull audit: verifiers, contracts, expect properties, stage facts

HEAD at start 363dcc0d. HEAD at finish d378e120. Between the two, 927f82e8
(L05y, C282) changed `Verify/Local.cpp` and `Verify/Program.cpp`; the line
numbers below are read at d378e120. Nothing was built, generated or run:
our C++ needs MLIR, so every confidence below is read or conjecture, never
measured. A count is a `git grep` over the tree at d378e120 unless the line
says otherwise.

No candidate touches `sources/`: nothing there is proposed for deletion.

Area: `foreign/idr/lib/IR/Verify/` (Attributes, Linearity, Local, Program,
Uses), the op, type and attribute verifiers of `foreign/idr/lib/IR/` (76
hand `verify`, `verifyRegions` and `verifySymbolUses`; sampled, see
§Survivors), `foreign/idr/lib/Transforms/Contracts/`,
`foreign/idr/lib/Transforms/Expect/` (34 files), `Expect.h`,
`ExpectProperties.inc`, `harness/Properties.idr`, and the stage facts
(`spec/Pipeline/Stage.idr`, `Generated/StageFacts.h.inc`).

Method: each part names its rule and the fact only it supplies, or it is a
candidate. Deletions first, ranked by lines removed; then what is kept and
why; then one finding that is no deletion; then what survives and could be
simplified.

---

## 1. Two numberings of the program's functions in idr-expect — MERGE

- **Part.** `foreign/idr/include/idr/Transforms/Expect.h`: 200-215
  (`concept FunctionNumbering`), 217-235 (`class GraphNumbering`), 270
  (`static_assert` over both), 275-287 (`withNumbering`, "the one place the
  two are told apart"), 289-305 (`idsOf`, a template with an
  `if constexpr` cast per numbering), 309-315 (`callees` template and its
  two `extern template`s), 38 (`#include ProgramGraph.h`).
  `Expect/Cycles.cpp`: 23 and 38-41 (explicit instantiations for both).
  The generic lambdas over `N` in `Reached.cpp:18-20`,
  `Allocation.cpp:41-42` and `ConstantStack.cpp:41, 92-94`.
- **Fact.** A numbering of the program's functions by id, so a check keeps
  bit sets and tables instead of maps. `WalkNumbering` (`Named.cpp:60-80`)
  already supplies it at every stage: it is what `withNumbering` falls back
  to at higher and lowered. Every edge the three users follow comes from
  `callees()` (`Cycles.cpp:23-36`, symbol uses of the body), never from the
  program graph's edges, so the graph contributes only ids, which the walk
  gives too.
- **What it costs.** Under `--idr-expect-at`, `Stages.cpp:80-88` builds a
  fresh `ModuleAnalysisManager` per request after every pass, so at the
  first, graded and owned stages `withNumbering` builds a whole
  `solver::ProgramGraph` (call graph and its components) to number
  functions. 19 tests carry the `heap-free` mark (`ls tests/*/heap-free`),
  which states `no-heap-allocation` at owned (`Harness.idr:718-720`), so
  for each of them the graph is built again after each owned pass. (read;
  the time is not measured)
- **Rule.** None. `GraphNumbering`, `WalkNumbering`, `withNumbering` and
  `FunctionNumbering`: 0 hits in `proposals/0000-mlir-native.md`,
  `audits/p0/verify/recheck6/` and `L19-tests.md`.
- **Readers.** `withNumbering`: `Allocation.cpp:41`, `ConstantStack.cpp:92`,
  `Reached.cpp:18` (3). `GraphNumbering`: `Expect.h` and
  `Cycles.cpp:38-39` only.
- **Deletion.** The ranges above. `WalkNumbering`, `walkOf`, `reachable`
  and `cycles` stay, typed over `WalkNumbering::Node`, not templates;
  `idsOf` becomes a 6-line function; `callees` one declaration. About 64
  lines in `Expect.h`, 5 in `Cycles.cpp`, 7 across the three properties:
  **about 76**. No test, generated output, CMake or spec entry changes.
  `firstOrderProgram` stays (`Continuations.cpp:28`, `Contracts.cpp:305`).
- **Verdict.** MERGE into `WalkNumbering` (`Named.cpp:60-80`). Confidence:
  read.
- **Owner.** L19. Files unmodified at d378e120; waits on nothing.

## 2. `crashSitesOf`, a second reading of whether a function crashes — MERGE

- **Part.** `foreign/idr/lib/Transforms/Expect/CrashSites.cpp:1-52`, the
  whole file; its declaration `Expect.h:387-390`; its one reader
  `Contracts.cpp:286`; `Transforms/CMakeLists.txt:620`.
- **Fact.** That a function the pass kept, whose row could not crash
  before the pass, has no place that may crash after it (the contract
  `crash-sites-not-added`). The row already holds it:
  - `rows::Check` holds every function's body within its row after every
    pass, by containment (`Func/Rows.cpp:167-190`, `Analysis/Effects.h:266-274`);
  - a call's row is its callee's (`Func/Call.cpp:268-269`);
  - MLIR verifies before `runAfterPass` (upstream `Pass.cpp:623-650`), so
    the contract only ever sees a verified module.

  So after any pass, a row without `crash` means there is no crash site.
  The record before the pass already holds the row's bit
  (`FunctionRecord::crash`, `Contracts.h:41-46`). The check becomes
  `k.before->crash == MayCrash::No && k.now.getRow().contains(Atom::crash)`.
- **Why the requirement for a count is gone.** AGENTS.md: "Nothing else ...
  reads effects its own way"; "Never: ... a second effect classifier
  (04 C26)". `crashes()` walks ops and asks `effects::own` per op
  (`CrashSites.cpp:31-42`), which is the derivation the row already holds.
  Its LLVM half (`CrashSites.cpp:32-41`, "after lowering") is never
  reached: `keptOf` finds only `FuncOp` (`Contracts.cpp:129-135`), so after
  idr-lower no kept function is an `llvm.func`.
- **What changes.** The row comparison is stronger. It also catches a pass
  that adds a call of a function that crashes, which the count skips
  (`CrashSites.cpp:33-36`: no call is a place). The relation's own test
  still fails as it should: `breakCrashSitesNotAdded` rewrites the rows
  (`Contracts.cpp:361-374`), so the row gains `crash`.
- **Rule that requires the relation.** AGENTS.md, eager evaluation: no pass
  adds a crash. That rule stays and so does the relation; only the count
  goes.
- **Readers.** `crashSitesOf`: 1 (`Contracts.cpp:286`). The comment at
  `Contracts.cpp:280-282` cites "idr-expect's crash-sites", a property that
  does not exist (`ExpectProperties.inc` has no `crash-sites` row).
- **Deletion.** `CrashSites.cpp` (52 lines), `Expect.h:387-390` (4), the
  CMake line (1). `Contracts.cpp:280-292` is rewritten at about the same
  size. The sentence for `crash-sites-not-added` in
  `harness/Properties.idr:285-` and `ExpectProperties.inc:162-164` changes
  wording, and `tests/expect-table-current` follows it.
  `tests/contracts-crash-sites-not-added` stays. **About 57.**
- **Verdict.** MERGE into the function record's row bit. Confidence: read.
- **Owner.** L19, plus INT for the CMake line. Files unmodified; waits on
  nothing.

## 3. Four program-verifier rules that idr-target or the only producer already hold — DELETE

All four are in `foreign/idr/lib/IR/Verify/Program.cpp`.

### 3a. `target()`: lines 54-72, called at 185-186

- **Fact.** The module's pointers are the runtime's words.
- **Where it is held.** idr-target refuses any module whose triple, data
  layout or target system description differs from the build's, under
  `Rule::OtherTarget` (`Target/Target.cpp:107-128`). Every pipeline slice
  starts with idr-target (`Transforms/Pipeline.cpp:76-82`;
  `Driver/Run.cpp:122`). No pass changes the data layout after it. The
  runtime is built for the same target entry, so its word size is the
  layout's pointer size by construction.
- **Rule.** None of its own. The commit that added it (653608e8) puts the
  refusal "in Target.cpp, Run.cpp and Verify/Program.cpp", so the same rule
  is held three times. AGENTS.md: "the one place the target is decided".
  It also reads `IDRIS_RT_WORD_BYTES` from the runtime header on the
  compiler's host; compare "Never: the host's `sizeof` of a runtime header
  in the lowering (11 I-CV10)".
- **Readers and tests.** No test names its message: "not the runtime" has
  0 hits in `tests/`. Without it, a module made for another target is
  refused once, at idr-target. Before that, `recycles()` may build layouts
  from the foreign layout (`Program.cpp:90-100`). That is noise ahead of
  the refusal, not an acceptance.

### 3b. `globals()`: lines 74-84, called at 193

- **Fact.** A `memref.global`'s alignment is at most a word.
- **Where it is held.** The only producer of `memref.global` is One-Shot's
  bufferization of `arith.constant`. It passes `options.bufferAlignment`
  (upstream `Arith/Transforms/BufferizableOpInterfaceImpl.cpp:52`), and
  `getGlobalFor` sets an alignment only when that is above 0 (upstream
  `Bufferization/Transforms/BufferUtils.cpp:134-136`). `Bufferize.cpp:327`
  sets `options.bufferAlignment = 0`. The frontend cannot write a global:
  the memref ops it is admitted are Dim, Alloc, Copy, Load and Store
  (`spec/Arrays/Declarations.idr:73-77`). No pass of ours creates
  `memref::GlobalOp`: `git grep GlobalOp::create foreign/idr/lib` finds
  only `LLVM::GlobalOp`.
- **Tests.** "is aligned to" has 0 hits in `tests/`.

### 3c. The alignment test on `memref.alloc`: lines 150-154

- **Where it is held.** The only producer is `allocate`
  (`Bufferize.cpp:199-204`). It receives One-Shot's alignment, which is
  `options.bufferAlignment` (upstream `BufferizationOps.cpp:83`) and so 0.
  `memref.alloc` is `PassesOnly` (`Declarations.idr:74`).
- **Tests.** 0.

### 3d. "a buffer of no strided layout": lines 171-174, with the sentence at 120-124

- **Where it is held.** Upstream's LLVM type converter refuses a memref
  with a non-strided layout, with its own error
  (`LLVMCommon/TypeConverter.cpp:488-493`). Bufferization makes identity
  or strided layouts only (`Bufferize.cpp:296`). The check is a second
  copy of upstream's legality, on a state no producer makes.
- **Tests.** "no strided": 0.

### What in `Program.cpp` is kept

- The identity-layout test on `memref.alloc` (147-149). Upstream's
  `castOrReallocMemRefValue` allocates its destination type, which may be
  strided (`BufferizationOps.cpp:60-86`), so a producer can make that
  state.
- `recycles()`, C41: "a recycle's layouts equal".
- The rest of `StageRules`, see §Kept.

### Deletion and verdict

- **Deletion.**
  - 3a: 19 lines, the call (2), the three includes only it and 3b/3c read
    (`LLVMTypes.h`, `DataLayoutInterfaces.h`, `idris_rt.h`).
  - 3b: 11 lines, and the call at 193.
  - 3c: 5 lines.
  - 3d: 4 lines.
  - The sentences of the header (`Program.cpp:7-8`), of `StageRules`
    (120-124) and of `Verify.h:35-39` lose their clauses.

  `verify::program` becomes: lowered gives success; counted runs
  `recycles`. `Rule::OtherTarget` stays (Target.cpp). No test changes.
  **About 52.**
- **Verdict.** DELETE. Confidence: read. That no producer makes 3b and 3c
  is read from upstream's pinned source.
- **Owner.** L04 (`Program.cpp`), L05 (`Verify.h`). `Program.cpp` was
  modified at the start (C282, committed as 927f82e8 during this audit)
  and is unmodified at d378e120. Waits on nothing.

## 4. results-as-given's "tail lost to a layout" branch — DELETE

- **Part.** `foreign/idr/lib/Transforms/Expect/Tails.cpp`: 65-78
  (`lostToLayout`), 113 (its call), 138-142 (its report), and the
  sentences at 7-8 and 104-109 that describe it. In the fixture
  `tests/expect-call-results/expect-call-results.mlir`: `@rejoins` (78-89),
  its `results-as-given=@rejoins:@g` item on the RUN line at 2, and its
  sentences at 11-13 and 14-19.
- **Fact.** A call whose results reach their function's return through a
  re-pack.
- **Where it is held.** The tail verifier refuses every such call from the
  graded stage on: `Tail.cpp:335-346` (line 344: `if (agree) return lostToRepack(...)`)
  with `layoutsAgree` from `tailLayoutsAt`. The verifier runs before any
  property reads the module (upstream `Pass.cpp:642-650`; `idr-expect`
  after a pipeline reads a verified module).
- **Where it is stated.** Every test that states results-as-given does so
  at graded or later: the seven lit tests run `to=graded`, and
  `tests/mutual-pure-tail-calls/mlir.expect` runs at owned. The only
  reader at an earlier stage is the fixture, whose own comment says so:
  "at a later stage that is a jump the compiler failed to make, which the
  verifier refuses before any property reads it" (14-19).
- **Rule that once required it.** C130 (properties at stages). No program
  states the property before the specializer runs, where the branch would
  be the only check.
- **Readers.** `lostToLayout`: 1 (`Tails.cpp:113`).
- **Deletion.** About 23 lines of C++ and about 16 of the fixture. The
  rest of results-as-given stays: the layout comparison of every call's
  results and `repackOfUse` both cover non-tail calls, which no verifier
  holds. **About 39.**
- **Verdict.** DELETE. Confidence: read.
- **Owner.** L19. Files unmodified; waits on nothing.

## 5. "Whether a region runs again", written four times — MERGE

- **Part.** Three copies of the same body, `!branch ||
  branch.isRepetitiveRegion(index)`:
  - `IR/Verify/Linearity.cpp:136-142` (`repeated`, read at 289);
  - `IR/Lifetimes/Verify.cpp:43-53` (`repeated`, read at 64);
  - `Transforms/Lifetimes/Read.cpp:116-122` (`repeated`, read at 131 and
    201).

  The typed fourth is `rows::detail::regionRuns` (`IR/Func/Fold.cpp:27-33`,
  declared at `Analysis/Effects.h:194-199`), which answers
  `Runs::Once | Runs::Repeatedly`.
- **Fact.** Whether a region of an op may run more than once per run of
  the op. Held once, in `regionRuns`.
- **Rule.** AGENTS.md: "a mechanism found by one fix is written once and
  shared"; "A choice is a type or an enum case, never a `bool`". The
  `bool` copies are the untyped form of `Runs`.
- **Readers.** 4 call sites across the three copies; `regionRuns`: 3
  (`Effects.h:221`, `Func/Call.cpp:152`, its definition).
- **Deletion.** The three copies, about 20 lines. `regionRuns` moves out
  of `rows::detail` into an IR header (`idr/IR/Flow.h` or a small
  `Regions.h`) so the verifier and the lifetimes read it without the
  effects layer, about 3 lines added. **About 17 net.** Not the same
  question, and kept: `Bufferize/Releases.cpp:64` (a non-branch op answers
  no) and `Counting/PlacementWalk.cpp:43`.
- **Verdict.** MERGE into `regionRuns`. Confidence: read.
- **Owner.** L05 (`Linearity.cpp`, `Lifetimes/Verify.cpp`,
  `Transforms/Lifetimes/Read.cpp`) and L02 (`Fold.cpp`, `Effects.h`).
  Files unmodified; waits on nothing.

## 6. Universal shapes no property has — DELETE

- **Part.** The overloads `wholeProgram(std::type_identity<Nothing>, ...)`
  and `wholeProgram(std::type_identity<Roots>, ...)` at
  `Expect/Lookup.cpp:35, 39`, with their sentence at 31-34. The
  constructors `WholeOfNothing` and `WholeModule` of `Whole` at
  `harness/Properties.idr:99, 101`, with their sentence at 94-96.
- **Fact.** That a universal property of no argument, or of the whole
  module, could be written. No universal property has either shape. The
  one universal row is `constant-stack`, whose shape is `Functions`
  (`ExpectProperties.inc:143`).
- **Rule.** None. A capability is added when a property needs it.
- **Readers.** 0 rows instantiate either overload, and 0 properties use
  either constructor (`grep -n WholeOfNothing\|WholeModule harness/`: only
  the definitions).
- **Deletion.** About 6 lines.
- **Verdict.** DELETE. Confidence: read.
- **Owner.** L19. Waits on nothing. If `reached` becomes a contracts
  universal (§Survivors), `WholeOfNothing` and its overload return with
  their user.

---

## Kept, each with its rule and the fact only it supplies

- **`Verify/Attributes.cpp` (24 lines).** Rule: AGENTS.md, "A fact kept in
  a discardable attribute can be dropped silently; do not keep one there"
  (14 T38). Fact: no op or argument carries an `idr.*` attribute. No
  producer writes one today (`setDiscardableAttr("idr.` and `"idr.` keys
  in `lib/`: 0). Nothing else stops a new one, so this is the only check.
  read.
- **`Verify/Linearity.cpp` (462).** Rule: AGENTS.md, "Quantity 1 is the
  grade's `once`, which every transformation must keep and the verifier
  checks after every pass"; C41 (exactly-once owned references, tokens,
  maximum over alternatives, a repeated region counted twice). Fact: use
  counts per path, which no type holds. read.
- **`Verify/Local.cpp` (200).** Rule: the grade ruling (2026-10-21,
  `unique deep`); C282. Fact: that a value typed `unique deep` is made
  only of what claims as much, op by op, after every pass. The exclusivity
  pass writes the claim, and only this checks it after later passes.
  read. Modified at d378e120, by the lane holding C282.
- **The rest of `Verify/Program.cpp`.**
  - `recycles` (C41).
  - Closure reach past higher (167-170). Closure types stand on block
    arguments and parameters, which no op's stage legality could hold.
  - The flow rule while closures remain (139), which the label solve's
    soundness rests on.
  - The rule that no linalg element holds references past higher (141-145).
    The admitted tensor ops' bufferization can make linalg ops, so this is
    not shown unproducible. conjecture.
  - Alloc identity layout (147-149, §3).
  - An `idr.func` in a lowered program (199-200). It is the only
    enforcement of `FuncOp`'s stages until C28's trait exists (§Finding).
- **`Verify/Uses.cpp` (283).** Not a check. It holds the shared value
  sources, and every function has readers: `throughLinear` 11, `sourceOf`
  8, `buildsCell` 7, `ownerOfPart` 7, `readFrom` 6, `storedBy` 4,
  `viewRoot` 4, `linearPositions` 1 (`Bufferize/Releases.cpp:223`),
  `arrayRoot` 1 (`OpsArrayFusion.cpp:85`), `fieldReadOnce` 1
  (`Families/Rules.cpp:31`). It sits under `Verify/` without a rule in it.
  That calls for a move, not a cull.
- **Contracts.**
  - `quantities-kept`. Rule: C130, AGENTS.md (17 FB-28). Fact: the binders
    Emit identified, followed into clones and join regions by identity,
    which `linear-kept` (by symbol) never sees.
  - `linear-kept`. Fact: results, dropped positions, and the parameters
    of functions a pass made (which carry no identity) across later
    passes. Both relations fire on the parameters Emit wrote of a kept
    function; that overlap is noted and is not a copy of either.
  - `cycle-divergence-kept`. Rule: AGENTS.md, effects. Fact: the
    divergence of a cycle of several functions, which no function's
    check sees (`Func/Rows.cpp:161-162`). Both row writers add it
    (`Effects/Writer.cpp:59-70, 102`; `Effects/Component.cpp:118-120`), so
    it guards a future writer, or a pass that forms a cycle without
    rewriting rows. That no pass does so today is conjecture.
  - The four breakers (`Contracts.cpp:326-452`). They are how each
    relation's test can fail at all (testing-by-search).
- **Expect properties.**
  - `constant-stack` (universal, after every compilation the suite makes
    under `--idr-contracts`: `harness/Lit.idr:120`, `Programs.idr:252`).
    Rule: AGENTS.md, proper tail calls and frame stacks. Fact: no cycle of
    the lowered module calls without `musttail`.
  - `labels-least`. An oracle for the label solve, of the kind
    testing-by-search names ("a second implementation we own"). Stated by
    `tests/closure-result-roundtrip/mlir.expect`.
  - `reached`. Checked of every emitted module by the harness
    (`Universal.idr:255`).
  - `folded`. Also read by the fuzz harness (`FuzzRun.idr:128`).
  - Every other property has at least one program test (`mlir.expect`) or
    lit test that states it. Counts of program tests:
    - 23: `tests-nothing`;
    - 12: `reuses-in-place`;
    - 7: `counts-nothing`;
    - 6: `calls`;
    - 4: `reuses-every-cell`, `resets-unshared`;
    - 3: `no-heap-allocation` (plus 19 `heap-free` marks), `contified`,
      `vectorized`, `structured-loops`;
    - 2: `in-place`, `moves-out`;
    - 1: `builds-nothing`, `one-clone`, `not-called`, `specialized-once`,
      `tail-calls`, `results-as-given`, `no-guards`, `may-diverge`,
      `word-loop`, `writes-forwarded`, `overwrites-dropped`,
      `narrowed-lanes`, `labels-least`.

    Each reads the effect system's one query, an interface or a type, and
    holds an optimization's outcome, which no verifier states. The
    machinery that remains (`Expect.cpp`, `Stages.cpp`, `Lookup.cpp`,
    `Report.cpp`, `Arguments.cpp`, `Named.cpp`) is the test vocabulary
    those properties are stated in (C130).
- **Stage facts (`Stage.idr:78-233`).** Each of the six columns has
  readers: `closuresAt` 2 files, `countingAt` 6, `functionsAt` 2,
  `tailsAt` 1, `tailLayoutsAt` 1, `edgeHoldsAt` 1. Two pairs partition the
  chain identically: `closuresAt` with `tailsAt`, and `tailLayoutsAt` with
  `edgeHoldsAt`. Each names a different guarantee, though: what
  defunctionalization makes versus who decides tail facts
  (`Stage.idr:91-95`); what the specializer's re-keying gives layouts
  versus holds (97-115). One could move without the other, so merging them
  would hide two cases in one name, which is Brooks's limit. KEEP.
  conjecture.

## Finding (no deletion): C28's stage-legality trait does not exist

C28 says: "Each op family declares in the specification the stages it is
legal at ..., checked by one generated trait". recheck6 marks it Done
(`decisions-C1-C130.md:275`) on the strength of `legalAt` existing. What
the tree has:
- No generated trait holds an op to its stages. "stage" appears 5 times in
  `Generated/IdrOps.td`, all for `idr.program`.
- `IdrAdmittedBase.td:38-39` prints `firstStage` and `lastStage` for every
  admitted op, and no backend reads them. `git grep firstStage foreign/`
  finds only the `.td`; `idris-mlir-tblgen.cpp` reads `alias`, `guards`
  and `frontendWrites` of the record.
- The spec's `Op.stages` is read only by `Generator/Idris.idr:310`
  (`written`, legal at higher). `Admitted.legal` is read only to print
  those two unread fields (`Generator/Outputs.idr:188`).

The requirement stands, so the data is kept and the check is missing:
- Owner: L03 (generator), with INT for the generated `.td`.
- When the trait lands, `Program.cpp:199-200` (an `idr.func` in a lowered
  program) is a second copy and goes with it.
- `ProgramOp::verifyRegions`'s comment, "Which kind of function a stage
  holds is each op's legal stages, not this rule's" (`Func/Program.cpp:55-57`),
  describes a check that does not run today.

## Survivors that could be simplified (not counted in the totals)

- **`Local.cpp:132-143`.** It re-runs `inferReturnTypes` on every op that
  touches a value typed `unique deep`, after MLIR's own verification ran
  the same inference. Only `CellInitOp`, `OwnAdoptOp` and `MemoTakeOp`
  override `isCompatibleReturnTypes` (git grep: 3). For every other
  inferring op the result type equals the inference, so none of its
  results is judged. A trait on those three (from the spec), asked before
  inferring, removes the second inference. Owner L08. The file is modified
  at d378e120, so this waits on the lane holding it.
- **`Linearity.cpp:418-420`, "holds a reuse token at many uses".** Every op
  that makes or takes a token requires it once (`isTokenValue`,
  `IdrOps.td:2578, 2687, 2698, 2709, 2720`). Many is representable only as
  the bare type (`bareGrade` gives many to a carrier that holds
  references, `Grades.cpp:156-160`) or through a region argument. A type
  rule would make it unrepresentable at every stage: the token's bare
  grade once, or a by-type case that carries a hold. Owners L05 and L07.
  conjecture.
- **`Linearity.cpp:96-119` (`Exclusivity`).** A cache built per verify,
  searched linearly, keyed by `OperationName`, of a fact of each op class.
- **The array op verifiers.** `OpsArrays.cpp:61-80, 112-123` share
  `verifyCount` and `verifyElement`: the index count and the element type
  against the buffer. These are declarations not yet made (constraints
  generated from the spec), not deletions.
- **Two "every compilation" mechanisms.** `reached` runs as its own
  `idris-mlir-opt` process per compilation (`Universal.idr:253-263`), while
  `constant-stack` is a universal of the contracts (`Lookup.cpp:57-68`).
  `ContractInstrumentation` already reads the emitted module before the
  first pass (`Contracts.cpp:515-518`), so `reached` could be checked
  there and the process spawn dropped. Owner L19. conjecture.

---

## Table

| # | Part | Verdict | Lines removed | Owner | Waits on |
|---|------|---------|---------------|-------|----------|
| 1 | `GraphNumbering` and `FunctionNumbering` beside `WalkNumbering` (Expect.h, Cycles.cpp, three properties) | MERGE into `WalkNumbering` | ~76 | L19 | nothing |
| 2 | `CrashSites.cpp`, `crashSitesOf` | MERGE into the record's row bit | ~57 | L19 (+INT, CMake) | nothing |
| 3 | `Program.cpp`: `target()`, `globals()`, the alloc alignment test, the strided test | DELETE | ~52 | L04, L05 (Verify.h) | nothing (Program.cpp clean at d378e120) |
| 4 | results-as-given's lost-to-layout branch, and `@rejoins` in its fixture | DELETE | ~39 (23 C++, 16 test) | L19 | nothing |
| 5 | Three `repeated()` copies | MERGE into `regionRuns` | ~17 | L05, L02 | nothing |
| 6 | Universal shapes `Nothing` and `Roots` | DELETE | ~6 | L19 | nothing |
| — | Attributes.cpp, Linearity.cpp, Local.cpp, rest of Program.cpp, Uses.cpp, four contracts, expect properties, stage facts | KEEP | 0 | L03/L04/L05/L08/L19 | — |
| — | C28 trait missing | finding | 0 | L03, INT | — |

**Total removed by DELETE and MERGE: about 247 lines.** DELETE: about 97
(#3 52, #4 39, #6 6). MERGE: about 150 (#1 76, #2 57, #5 17).

The area holds about 4,144 lines in Verify, Contracts and Expect. The
verifier rules there are mostly typing and quantity rules that no type
carries, so they are kept. The deletions come from second copies (rows,
idr-target, the tail verifier, upstream's converter) and from one
numbering doing nothing the other does not.
