<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Rederivation plan: carriers, the owner's questions, dispatch

The synthesis of the eight rederivation reports in this directory
(multiplicities, sharing, types-layouts, effects-termination, control-calls,
identities-names, constants-values, checker-boundary), read against
AGENTS.md's "NO FACT KNOWN STATICALLY" rule with the owner's word of
2026-10-23 ("a fact is carried from where it is first known to every use
... never dropped at a boundary and read again past it"), "Delete before you
optimize", the proposal's C281, C282, C286, C288, C289, D132 (and the
decisions they lean on: C64, C74, C75, C129, C130, C203, C206, C275, D102),
and `audits/p0/verify/ownership.json`.

- HEAD at writing: `2c500794`. Two commits landed while this was read:
  bc08f095 (L16ep, the frontend's Translate and Growth files) and 2c500794
  (the L16 queue; C281's steps 1 and 2 dispatched as L16et). So
  `Frontend/Translate/*` and `Growth/*` are clean this moment and are about
  to be held again by L16et.
- Ground. Everything is **read**: the findings, their sites and their line
  estimates are the reports'; where two reports estimate one deletion, the
  overlap is counted once. Nothing was built (no C++ tool on this machine,
  LLVM is built elsewhere). Lane attribution of modified files is by `git
  status` at 2c500794 and, for files no report attributes, by reading their
  hunks (marked "by hunk").
- Cross-checked against the cull audits (`audits/p0/cull/`) only where they
  name the same parts, by search, not in full: analyses A (`#idr.given_back`),
  pipeline 1, 5, 7 and 14, frontend 2 and 13, verifiers (Uses.cpp, the
  contracts). Each overlap is named where it bears.

Finding references below are `report number`: `mult R1`, `shar 1`, `type 1`,
`eff 1`, `ctrl R1`, `id 1`, `const 1`, `CB-1`.

---

## 1. The carriers that cut across the reports

77 findings; 9 of them restate another report's fact, so 68 distinct facts.
The duplicates, merged here and never dispatched twice:

- `mult R3` = `shar 6` (a held buffer's claim, dropped at the field read).
- `eff 2` = `ctrl R3` = `CB-2` (Idris's components and their loop verdicts,
  dropped by the checker, recomputed by `Recursion.idr`).
- `id 2` = `CB-8` (a nested block's parent; CB-8 adds the pattern variable's
  function and the correctness defect).
- `id 7` = `CB-6` (escape hatches found by re-lexing the source).
- `mult R1` = `shar 2` (function results graded `many`; sharing adds
  idr-in-place's writer grading what the stage rule refuses).
- `mult R4` = `shar 1` item 1 (`flowsLinearly`); `mult R10` = `shar 1` item
  5 (the cast walkers); `mult R2`'s `fieldReadOnce` = `shar 1` item 6.
- `eff 5` is inside `eff 1`.

Grouped by the representation change that fixes them (20 carriers):

| Carrier | Fixes, across reports |
|---|---|
| C1 Fresh values carry their one consumer's uses (C286 to returns, yields, scrutinees) | mult R1, R4, R6, R10; shar 1 (items 1, 2, 3, 5), shar 2 |
| C2 QTT's product rule held once, generated for constructors and closures | mult R2, R5; shar 1 item 6 |
| C3 A held buffer's claim reaches the op that opens it | mult R3; shar 6 |
| C4 One op per meaning of a reindex | type 1 (with the b2aab6e9 queue item) |
| C5 A type's computed facts kept in its storage | type 2, 4, 7 |
| C6 Divergence carried with the code by `idr.may_loop` | eff 1, 2, 5; ctrl R3; CB-2 |
| C7 One effect query, asked while the row is on the op | eff 4, 6 |
| C8 What a pass changes, declared once and honoured by the analysis manager | ctrl R2; eff 3 |
| C9 The tail fact held by structure | ctrl R1, R4, R5 |
| C10 The checker's output contract: the TTC keeps what the checker computed | id 2, 7; CB-1, 5 (checker half), 6, 8 |
| C11 The reading kept: what the boundary read once rides in `DefinitionRead` | CB-3, 4, 5 (frontend half), 9; mult R7; type 5 (frontend half), 8 |
| C12 Emit writes the dialect's fact, not its own restatement | type 3, 6; const 8 |
| C13 A known constant held at its type | const 2, 3, 7; type 9 |
| C14 Typed identities at the module boundary | id 3, 4, 11, 14 |
| C15 Content identity computed once; one copy of a callee fact | id 5, 6; ctrl R6 |
| C16 A partial primitive is a guard and a total op; the guard's absence is the proof | const 5, 6; eff 7 |
| C17 Intervals computed once and kept | const 1, 4 |
| C18 Claims declared by the op and the specification | shar 4, 5, 7, 8, 9, 10 |
| C19 The registry read once, where it is static | CB-7; id 8, 10; mult R9 |
| C20 Tool and harness boundaries typed | id 1, 9, 12, 13, 15; CB-10; mult R8 |

Outside the carriers: `const 9` (idr-constants still declared by the
specification) is part of D132's own landing (fold-in F1); `shar 3`,
`const 4`, `const 10`, `ctrl R5`'s destination form and parts of `const 2`
and `const 6` are deferred (§3, "not asked").

The pattern every carrier answers is the one the owner named: a stage that
had the fact wrote it at a weaker type (a `many` grade, a bare carrier, an
enum, a number, a printed name, a dropped field), and a later stage walks,
solves, parses or tests to get it back.

---

## 2. Each carrier

Each entry gives the fact, the findings, what the fix deletes (the reports'
estimates), and the decision: an existing ruling or decision that settles
it, a rule of AGENTS.md that settles it (the coordinator records it, open to
the owner's review), or the owner's question in §3.

### C1. Fresh values carry their one consumer's uses

- **Fact.** A value Emit builds for one consumer is used once there; a
  callee hands its caller its one reference to its result, with the claim
  the local rule proves of its returns.
- **Findings.** mult R1, R4, R6, R10; shar 1 (items 1, 2, 3, 5), shar 2.
- **Dropped at.** `Emit/Index.idr:179-183` (every result `many`);
  `Emit/Bodies.idr:180-183` (`plain`: every region yield cast to `many`, at
  the match arms, literal and natural arms, join bodies, array regions),
  `:190-193` (a tail built at `many`), `:714, 733, 735` (a literal or
  natural scrutinee cast to `many`); `Emit/Operations.idr:237-247` (the
  Enter cast that leaves the value as made at `many`).
- **Deletes.** `Analysis/Ownership/Local.h:295-300` `flowsLinearly`, dead
  under C286 (about 9); `InPlace/Chains.cpp:41-58, 111-152` and
  `Rule.h:207-216`, the use walks idr-in-place runs on `many` values (about
  70); the cast arms of `Specialize/Patterns.cpp:38-57, 133-147` and
  `Keys.cpp:124-128, 244-282` (about 30); `Verify/Uses.cpp:35-54` and
  `Grades.h:317-327` become one definition chain over `sourceOf` (about 20,
  once Narrow's four readers move); the Leave/Enter pair at every match in
  a linear position; and, by Q1, either the dead result half of
  idr-unique-results and linear-kept's result half (about 130), or
  rc-exclusive's re-derivation of fresh results, its grade copies for
  them, and the `idris_rt_is_unique` tests freshness would have proved
  (`Lower/Counting.cpp:134-171`; how often, conjecture). About 250 lines.
- **A live contradiction.** idr-in-place records and grades `many` values
  with claims (`Versions.cpp:110-112`, `Writer.cpp:52-73`), which C286's
  stage rule refuses (`Verify/Program.cpp:118-121, 181-183, 214-220`);
  `tests/in-place-borrowed-read-ends` and `tests/leet-relink-in-place`
  reach it (conjecture until built).
- **Decision.** C286 settles all but one part: `flowsLinearly`'s deletion;
  region yields at the uses Emit already passes into the arms (`w.uses`)
  and a matched scrutinee at its own grade ("the multiplicity Idris proved
  at the consumer is never dropped"); and a `many` value's in-place
  obligation left to rc-exclusive after counting ("exclusivity after
  counting raises the rest"), which deletes Chains' walks and the writer's
  grading of `many` values. The function result's grade in the signature is
  a core shape: **Q1**. Rejected (coordinator): shar 1's extension to an ω
  `let` Emit sees used once. Emit would be counting uses, an analysis on the
  Idris side ("idris should be pure representation, none of the
  optimization stuff"); after counting, exclusivity raises it.

### C2. QTT's product rule held once

- **Fact.** A field of a value used `u` times is used `u * q` times; a
  closure or suspension is `once` exactly when a capture is.
- **Findings.** mult R2, R5; shar 1 item 6.
- **Dropped at.** Emit builds fields at their declared quantity
  (`Bodies.idr:176-178`, `Operations.idr:437`); `data.con` has no rule tying
  its result's uses to its fields' (`IR/Counting/Ops.cpp:53-62`,
  `OpsCon.cpp:107-131`); Emit passes captures as bare `Value`s
  (`Bodies.idr:773-775, 799-801`).
- **Deletes.** `fieldReadOnce` (`Verify/Uses.cpp:125-150`,
  `Grades.h:355-359`) becomes one `hasOneUse` at its two readers
  (`Families/Rules.cpp:31`, `OpsConReads.cpp:97`); `LazyForceOp::fold`'s use
  test (`OpsClosures.cpp:263`); `usedOnce`'s Enter arm; Emit's `holding`
  (`Bodies.idr:452-467`), which matches its own printed MLIR types. About 50.
- **Decision.** Settled by C75 ("Grade rules are typed data ... printed to
  the C++ and imported by Emit"; C75 deleted the closure-quantity rule in
  `Bodies.idr`, and `holding` is that rule back) and AGENTS.md ("one thing,
  one representation ... generate the second copy from the first"; quantity
  1 "the verifier checks after every pass"): a verified property of
  `data.con` generated from the specification's `times`, as
  `ResultUsesMaxOf` is. Before it lands, check mult R2's soundness note
  against `LinCastOp::fold` (`IR/Lifetimes/Cast.cpp:62-70`).

### C3. A held buffer's claim reaches the op that opens it

- **Fact.** A cell claiming `unique self` holds the only reference to its
  buffer's storage (D122; `Grade.idr:212, 221-228`).
- **Findings.** mult R3; shar 6.
- **Dropped at.** Emit casts the buffer to the bare carrier before
  `bufferization.to_tensor` (`Bodies.idr:416-420`); a `count.share` may land
  between; for `LArray` the field is declared at ω
  (`libs/mlir-array/Array/Core.idr:154-155`), so the read is `many` and
  D122's row is never reached.
- **Deletes.** `Bufferize/Releases.cpp:207-237` (a cast and use-list walk
  per `to_tensor`, one of the last users of `linearPositions`) and the cast
  in `caseFields`. About 35.
- **Decision.** Which op or type holds the fact: **Q6**.

### C4. One op per meaning of a reindex

- **Fact.** Whether `idr.data.reindex` is free (same words), works without
  building, or builds a cell; whether a field read re-packs.
- **Findings.** type 1, and the b2aab6e9 queue item (three builders that
  pick their own result type).
- **Dropped at.** One op for three meanings (`Spec/Families/Ops.idr:211-260`).
- **Re-derived by** about twenty readers per query: the verifier, every
  flow-edge query, field-read inference, effects through a pair-rule
  mechanism that exists for this op alone, speculation and carry (so tail
  position rests on it), bufferization's `byCarry`, the lowering, static
  form.
- **Deletes.** The pair-rule machinery (`Spec/Effects/Declaration.idr`,
  about 110; `Effects/Rules.h:193-250`, about 58; `Conditions.cpp:91-98`,
  `Vocabulary.h:329`, `Declared.h`), `fieldReadBuilds`, the per-query
  `builds` readers, `isFree`/`getCarry`/`getSpeculatability`'s tests,
  `byCarry`, `LowerReindex`'s branch. About 300 deleted, 80 added.
- **Decision.** Reverses C275 (2026-10-23), which rejected both storing the
  answer on the op and splitting the reindex ("the distinction is derived
  from its types, not chosen"), and amends C206 (one op): **Q3**.

### C5. A type's computed facts kept in its storage

- **Findings.** type 2, 4, 7.
- **type 2.** `classify` throws away the per-constructor substitution and
  each field's placement; the second `possibleAt` in one construction,
  `Layouts::fieldsAt`/`solvedBinders`, the re-pack walk and
  `bindersOf`/`determined` unify again. Kept as plain arrays in
  `LayoutFacts`; deletes `classAt`, the `Unfolding` enum, Repacks'
  recomputing arms, `solvedBinders`. About 140.
- **type 4.** A refined type's verify re-runs `possibleAt` and `determined`
  on every `get` (assertions are on); checked against the base's stored
  `possibleTags`, the full check staying at `getNormalized`. About 20.
- **type 7.** The program verifier builds a whole `Layouts` per verification
  of a program holding a recycle (`Verify/Program.cpp:86-99`); the cell's
  size goes on the token, written by counting from the analysis it has.
  About 25.
- **Decision.** Settled by AGENTS.md ("computed once and kept"; "a fact that
  can be numbered once is not recomputed per query"; a fact that crosses
  passes "lives in a type or a verified property") and by the families'
  own statement that layout facts are "computed once, when the type is
  made" (`Families.h:132-137`). type 4 and type 7 change a type's
  parameters; each report offers one carrier and no alternative, so the
  coordinator records them for the owner's review.

### C6. Divergence carried with the code

- **Fact.** Whether code may run for ever because it recurses through code
  Idris did not prove to end.
- **Findings.** eff 1, 2, 5; ctrl R3; CB-2 (three auditors found the same
  re-derivation independently).
- **Dropped at.** `Emit/Closures.idr:62-79` (one component number per
  function), `Term.idr:1999-2009` (`withRegions` joins every local
  definition's verdict into its function's), and the checker
  (`SizeChange.idr:591-600` keeps one bit; the TTC keeps `totality` only).
- **Re-derived by** `Fold.cpp:37-53` per derivation; `addCycles` at 12
  whole-program writes; `Component.cpp:108-120`; the cycle-divergence-kept
  contract and its breaker; the loop builders' `Ending`; the dissolvers;
  `unittests/Rows.cpp`; and in the frontend `Recursion.idr` (162 lines: a
  second Tarjan and the size-change search per compile, library code
  included), beside `verdictOf`'s own search.
- **Carrier both options share.** `idr.may_loop` (already declared with the
  right effect, `Spec/Control/Joins.idr:199-232`) at the entry of every body
  Idris did not prove, and of each local definition's join region from that
  definition's own verdict; it moves with the code, and the state "every
  member of a cycle dropped it together" cannot be written. `LoopToJoin`
  must not erase an entry mark.
- **Deletes.** About 280 under Q2 (a) (adding a field to the checker's
  totality); about 700 under Q2 (b).
- **Decision.** Amends C74 (itself amended by D102): **Q2**.

### C7. One effect query, asked while the row is on the op

- **Findings.** eff 4 (the lowering re-reads loop progress from LLVM's
  `willreturn`, which crash, IO and exit withhold too, and counts
  `idr.may_loop` ops in place of the row: `Conversion/Matches.cpp:405-415,
  431-471`); eff 6 (the specializer's raise restates the resource tree from
  bare atoms, more coarsely than the tree: `Specialize/Consumer.cpp:113-118`).
- **Deletes.** About 21 lines, and the conflation of crash and IO with
  divergence at the latches.
- **Decision.** Settled by AGENTS.md ("Nothing else names a resource, reads
  effects its own way"; every reader "asks through one query API"). L18
  confirms that `mayMoveAcross` is the order the raise needs.

### C8. What a pass changes, declared once and honoured

- **Findings.** ctrl R2 (the call graph built 8 to 10 times per compile; the
  specification's `GraphEffect` read by nothing; `Keeps` passes that drop the
  graph, `Edits` passes that invalidate it, tailLoops recorded `Keeps`
  though it deletes calls); eff 3 (12 whole-program row writes each derive
  every function, though C64 records a writer seeded by what changed).
- **Deletes.** 6 to 8 whole-program graph builds per compile (leaving
  defunctionalization's and the one after SymbolDCE),
  `InlinePass.cpp:64-68`, the passes' hand preservation; 9 of the 12 full
  derivations per compile (the three counting nests touch every function).
  About 30 lines; the rest is work.
- **Conflict with cull/pipeline.md 7**, which deletes `GraphEffect` because
  nothing reads it and it disagrees with the passes' own preservation.
  Resolved for this carrier: the disagreement is the drop ctrl R2 names, and
  the specification is the one source of every fact known when the compiler
  is built, so `GraphEffect` is generated into `StagedPass` (preserve on
  `Keeps`; thaw and freeze around `Edits`, as widenRows and writeRows are
  placed from `adds`), the three records the cull found wrong and tailLoops'
  are corrected, and the hand `markAnalysesPreserved` calls go. Cull 7's
  `PassKind` half is unaffected.
- **Decision.** Settled by C64 (the seeded writer) and AGENTS.md ("an
  analysis lives in the analysis manager and survives every pass that does
  not change it"; build-time facts "generated from the dialect's Idris
  specification"). eff 3 needs the writer's share of compile time measured
  before any speedup is claimed.

### C9. The tail fact held by structure

- **Findings.** ctrl R1 (the fact decided at defunctionalization, then
  decided again in full by every pass that edits a body: `decideTails` at 11
  sites, 12 calls, per-query reads in Redirect, Continuations, Open and
  AccumulatorPlan, verifier walks after every pass); ctrl R4 (Emit knows
  every tail by construction and writes `nontail`; defunctionalization reads
  tails three ways); ctrl R5 (a self call's context dropped to
  `modulo_context`, recomputed by trmc and on every verification; trmc's
  guard can never fire).
- **A likely bug.** `LabelSites.cpp:338-339`'s unification of a direct tail
  call's results with its caller's never runs (tails are decided after
  labels), so a coercion can land after the call and `decideTails` then
  writes `nontail`: a tail call lost silently, against "a tail call the
  compiler fails to make is an internal error". Conjecture until a program
  test runs; the fix does not wait on Q4 (U09).
- **Deletes.** `Optimize/Tails.h` (52) and its 12 calls; Redirect's and
  Continuations' per-query reads; the tail halves of `IR/Tail.cpp`'s
  verifiers (`:308-318, 348-376`); `TailCalls.cpp:68-84`; `StageTails` and
  `tailsAt`; LabelSites' tails table; `Edits.cpp:37, 89-101`;
  defunctionalization's `decideTails`. About 230.
- **Decision.** Where the fact lives amends C203 (the frontend writes every
  call `nontail`): **Q4**. ctrl R5's interim (delete trmc's dead guard) is
  settled now; its verifier move rides on Q4; its destination form is
  deferred.

### C10. The checker's output contract

- **Findings.** id 2 = CB-8; id 7 = CB-6; CB-1; CB-5 (checker half).
- **CB-8 / id 2 (correctness first).** `Nested (outer, k)` and `PV n fi`
  keep another session's context entry number (`Core/TTC.idr:126, 129`), so
  the frontend's reading follows a nested definition's "parent" into an
  unrelated definition (`Boundary.idr:183-188`, `Closed.idr:562-606`), may
  be how R-META's three refusals are reached (conjecture), and walks the
  whole program per compile to invent parents and ordinals
  (`Boundary.idr:503-654`). Carrier: `Nested (parent : Name) (ordinal :
  Nat)` and `PV` holding its function's name, as `CaseBlock` and
  `WithBlock` already are. Deletes about 200 and the walk.
- **CB-6 / id 7.** The elaborator resolves every escape-hatch reference
  (`TTImp/Elab/App.idr:86-92`) and drops it; the profile re-reads and
  re-lexes every user source and matches unqualified spellings, so a user's
  own `believe_me` is refused. Carrier: each resolved reference and hole of
  a user module kept by the TTC beside `pragmaUses`. Deletes about 80 and a
  read and lex per user module per compile.
- **CB-5, checker half.** `refersTo` is kept by the TTC and read by nothing;
  extended to the type's references, the boundary reads it in place of
  `termRefs`/`treeRefs`/`patRefs`/`references` (about 75).
- **CB-1.** Solved metavariables kept as references to definitions whose
  type the TTC drops; the frontend tables, refuses (R-META, measured on 3 of
  5 of our programs) and fills them in at every normalisation. About 230.
- **Decision.** CB-8 / id 2 extends C129's typed parent to `Nested` and
  `PV` (AGENTS.md: "a block's parent kept as printed text" is a never-line;
  "the TTC keeps every fact a reader would otherwise rebuild"). CB-6 / id 7
  and CB-5 are settled by the same TTC rule and by "a name is text for a
  human". CB-1 is the owner's: **Q5**, asked only after CB-8 lands and
  R-META is measured again.

### C11. The reading kept

- **Findings.** CB-3, 4, 5 (frontend half), 9; mult R7; type 5 (frontend
  half), type 8.
- **CB-3.** `DefinitionRead` keeps the type as written; eleven sites
  normalise it again (the busiest per case alternative and per instance).
  Carrier `DefinitionRead.normal`.
- **CB-4.** The freeze decodes every loaded definition, reached or not
  (measured: +0.8 to 1.0 s CPU with 11 base modules imported, same `main`).
  Carrier: the frozen context decodes an entry when read.
- **CB-5, frontend half.** `DefinitionRead.refers`; the profile and the
  growth model take `d.type`/`d.matched` from the reading (7 re-decodes, 3
  by-name lookups in the live context go).
- **CB-9.** `dataParams`' fallback (about 45) for a case the checker's
  a386fe4d fixed; `parampos` alone.
- **mult R7.** Erasure read from `eraseArgs` and again from the binder's
  quantity, and decided by both the growth walk and the translation; one
  reading on C281's annotated tree (plus checker-boundary's two more sites,
  `Resolve.operandsOf`).
- **type 5, frontend half.** The array language's snoc field guessed to be
  a numeral (`Terms.idr:2332`) where the type constructor's natness says.
- **type 8.** Emit's `fitting` compares each value's type with its slot's;
  the translation emits the reindex where it reads a variable at a refined
  type (about 50).
- **Decision.** CB-3 and CB-4 are C289's "each definition is read once from
  the frozen context" (an eager whole-context decode there would keep
  CB-4's cost: tell L17bh). mult R7 is C281's fold. CB-5 and CB-9: the TTC
  and one-reading rules. type 5: the family declaration does **not** gain a
  shape field (identity is content; a field derivable from the declaration
  is a second copy held in step); the C++'s `shapeOf` runs once per family
  made and is kept, and `Constraints.cpp:40` already reads the stored
  `listShape()`. type 8: settled by the 2026-10-23 rule (the refinement is
  first known at the case); if the translation cannot place the reindex
  without a type-indexed core term, it goes to the owner then. About 150.

### C12. Emit writes the dialect's fact, not its own

- **type 3.** Emit's per-group "holds references" (`Emit/Index.idr:32,
  69-86, 317-397`) disagrees with the C++'s per-application fact: a
  quantity-1 closed `Vect` of words or a `Fin` is written
  `!idr.graded<once, counted, ...>`, which `GradedType::verify` refuses at
  the module's read (latent: no fixture holds one). Carrier: the C++'s fact
  alone; the boundary's `GradedType` builder normalizes (drops a hold the
  carrier cannot have), and the array op is chosen in C++ by the element's
  `holdsReferences` (C284's split). Deletes about 100 in Emit, 40 moved.
- **type 6.** `Ty`, `ITerm`, `Sort` hold a bare `FamilyId`; 13 lookups in
  `Emit/Index.idr`, each with a `Nothing` arm, three of them silent
  fallbacks. Carrier: a family reference resolved at registration. About 30.
- **const 8.** Emit writes the Integer-to-Char scalar bound itself
  (`Emit/Operations.idr:396-407`); one op whose meaning is the template's
  `toChar`. About 10.
- **Decision.** Settled by AGENTS.md ("one thing, one representation"; the
  char conversions have "their one meaning in one C++ template") and C75 ("a
  lookup that can miss is a missing index").

### C13. A known constant held at its type

- **const 2.** A literal natural and a parameter a key fixes to a closed
  shape lose their value at every slot (`NatT IOpaque`, a reindex that folds
  no constant), so a keyed copy computes its predecessor chain at run time.
  Carrier: the keyed parameter is `!idr.nat<k>` in the instance's signature,
  a reindex of a constant folds to the constant, a literal is built at its
  slot's type.
- **const 3.** Bigs cross between `APInt` and the runtime as decimal text
  (`Fold/Scope.cpp:50-72`; `StaticBytes.cpp:103-116, 133-140`); words both
  ways. About 30.
- **const 7.** `ranges::ofType`, reading a closed natural's index too, seeds
  the e-graph's leaves as it seeds `Ranges`. About 10.
- **type 9.** A numeral constant kept as successor cells and walked
  (`numeralValue`); held as its number. About 15.
- **Decision.** Settled by AGENTS.md ("What the compiler knows about a
  program goes into the program as a constant: ... a specialized entry
  point, a constant operand"; "writing a known fact as text to be parsed
  back") and by the dialect's own statement that a closed natural's type is
  that natural (`IR/TypeLiterals.cpp:51-63`). Deferred: which of the type
  and the `#idr.big` attribute stops holding a closed natural's value.

### C14. Typed identities at the module boundary

- **id 3.** Every property is written by name and string-compared back into
  its slot by MLIR per op per compile; MLIR's own property encoding
  (ODS `writeProperties`/`readProperties`, `kHasProperties`) carries it by
  position, the op number from the specification's op index.
- **id 4.** Every type occurrence carries its family group's whole attribute
  and re-walks its closure in the writer; the group referred to by
  `FamilyId`, numbered once.
- **id 11.** Instance symbols guarded against print collisions by a table
  (`keyLinks`); a discriminator that is a function of the link.
- **id 14.** `sameName` is dead; `OpIndex.h.inc` is included by nothing and
  becomes id 3's op number.
- **Deletes.** About 150 hand lines (110 name literals, the name-keyed
  property path, `keyLinks`), and MLIR's per-op ladders and dictionary sort
  at run time.
- **Decision.** Settled by AGENTS.md ("A name is text for a human ... a
  missing type") and upstream first (MLIR's own encoding). Coordinate with
  cull/frontend.md 2 (the same writer files).

### C15. Content identity computed once; one copy of a callee fact

- **id 5.** `stableDigest` re-encodes a whole value on every call, though
  `Specialize.h:132-134` says it is kept; a Merkle digest in the storage,
  uniqued identity for in-process buckets. About 25.
- **id 6.** A static datum's global found again by digesting and looking up
  its name (O(N²) per cell run); idr-lower-statics rewrites each use to the
  op naming its global. About 20.
- **ctrl R6.** Gives-back held twice (`#idr.given_back` and `CalleeFacts`),
  read by name per query. cull/analyses.md A has already measured that no
  transforming reader reads the attribute and deletes it (about 399, not
  counted here); what remains for this carrier is `CalleeFacts` keyed by
  `FunctionId`.
- **Decision.** Settled by AGENTS.md ("computed once and kept"), MLIR's
  global and reference model, and "Delete before you optimize" for the
  attribute (cull A, which names the C18 amendment).

### C16. The guard's absence is the proof

- **const 5.** A literal case's facts (its key; the default's exclusions)
  are held by no value; `Ranges` restates them by `dyn_cast`, the e-graph
  reads neither, so a guard on the default's binding is tested at run time.
  Carrier: the frontend's refinement, and `specGuarded` writes no guard a
  refinement decides. About 115.
- **const 6, settled part.** A refuted guard passes its operand's interval
  on, so `guardsHold` re-decides each guard at every fold and
  `getSpeculatability` matches structure per query. A refuted guard gives
  no value; `guardsHold` goes in both instances; `NatPredOp::foldable` goes.
  `getSpeculatability`'s body shrinks only after a verifier rule (or proof)
  that no pass builds a total op on an unchecked operand, which nothing
  states today. About 60.
- **eff 7.** `io.exit` declares a crash on every status; a status guard and
  a total exit. About 12, and the crash off every exit's row.
- **Decision.** Settled by the specification's own rule ("a partial
  primitive is a guard and a total op ... a proof is the absence of the
  guard", `Spec/Ops/Checks.idr:13-17`) and C285. Deferred: a guarantee as a
  type parameter of our own types (non-empty string, non-zero big).

### C17. Intervals computed once and kept

- **const 1.** Narrow's per-function range solve is made three times under
  the same summaries on the same IR (four solves where two differ); read
  once into `Facts` at the arguments phase. About 50, and half the solves.
- **const 4.** Deferred (see §3).
- **Decision.** Settled by AGENTS.md ("A fact is computed once and kept ...
  sized by the problem").

### C18. Claims declared by the op and the specification

- **shar 4.** A constructor's fresh claim computed by `DataConOp::freshClaim`
  and again from flow edges by the local rule; `data.con` infers it, in one
  place (as C282 has the dialect's builder ask `freshClaim`). About 25.
- **shar 5.** `LocalCheck` re-runs each op's inference per verification to
  learn which ops admit more; a specification trait on `cell.init` and
  `memo.take`. About 13.
- **shar 7.** The claims' order restated by enum ordinals with no
  `static_assert`; generated tables, `Unique` for `Asks`. About 25.
- **shar 8.** A reuse token's nullness tested at run time after the
  uniqueness test decided it; a cell on both paths, or the consumer sunk.
  About 10 and a run-time test (cost conjecture).
- **shar 9.** Flow edges rebuilt per query at 81 sites; a per-body table in
  the analysis manager. Work, not lines; measure first (C4 removes the
  costliest per-query part).
- **shar 10.** A quantity-1 `in_place` parameter's obligation computed by a
  pass from its type (`boundaryAsks`); written from the type. About 15.
- **Decision.** Settled by C282, C286 and AGENTS.md (traits and generated
  tables from the specification; "testing what its types prove"; numbered
  once).

### C19. The registry read once, where it is static

- **CB-7.** The registry is validated against the pinned libraries on every
  compile by printed-name shapes; at prefix install instead. About 90.
- **id 8.** `%foreign` entries validated, thrown away, searched again with
  spec strings re-parsed per entry; held at their sites. About 12.
- **id 10.** Trust decided by a package's name text; a typed `Lib` from the
  package's place under the compiler's prefix. About 12.
- **mult R9.** The registry's `Multiplicity` restates `Use`. About 12.
- **Decision.** Settled by AGENTS.md (no static fact paid when the compiler
  runs; "a name is text for a human") and `Libraries.idr`'s own "trust never
  follows from a name"; the auditors of CB-7 and id 10 name the coordinator.

### C20. Tool and harness boundaries typed

- **id 1.** The `covers` check prints the whole module, scans it character
  by character, matches names by suffix, scans sources, and keeps two hand
  copies of the registry (about 365); the frontend writes its typed `Read`
  table as an artifact beside the report and timing it already writes.
- **id 9** (endings compared as printed text), **id 12** (dialect by its
  namespace string per op), **id 13** (runtime functions by a name set after
  linking), **id 15** (the transform library parsed from text per context),
  **CB-10** (`self.sh`'s hand list of the checker's dependencies). About 60
  together.
- **mult R8.** The quantities-kept contract keys binders by a discardable
  location and skips silently when it is gone.
- **Decision.** Settled by AGENTS.md ("A brittle test means a missing test
  API"; "writing a known fact as text to be parsed back") and
  testing-by-search. mult R8: C130's carrier stands and the contract fails
  where a binder's identity is lost instead of skipping; if that fires on
  legitimate passes, the carrier goes to the owner then.

### Coordinator decisions to record (each open to the owner's review)

C1's settled parts and the rejected ω-let extension; C2; C5 (with the two
type-parameter changes named); C7; C8, resolving cull 7 the other way; C9's
interim; C10 without CB-1; C11, with type 5's field rejected and type 8's
return condition; C12; C13 without the double statement; C14; C15; C16
without the type guarantees; C17's const 1; C18; C19; C20, with mult R8's
condition. Each names the rule above as its reason.

---

## 3. The owner's questions

Six questions no rule settles, in the order to ask them, one at a time.
Duplicates are merged: Q1 is mult R1 and shar 2; Q2 is eff 1, eff 2, ctrl
R3 and CB-2; Q6 is mult R3 and shar 6.

### Q1. A function's result: graded `once` in its signature, or kept `many`

C286 makes Emit build a fresh constructor at the uses its one consumer
takes, and a `many` value claims nothing before counting. Every function's,
closure's and suspension's result is still `many` in its signature
(`Emit/Index.idr:179-183`). So before counting no result carries a claim to
its caller: idr-unique-results' result half (the result table and its
cyclic re-solve, `readCalled`, `writeSignature`, `recall`) computes nothing
now; idr-in-place grades results with claims the stage rule refuses
(`Writer.cpp:69-73`; `tests/leet-relink-in-place`, conjecture until built);
rc-exclusive re-derives fresh results' claims after counting, with grade
copies; and where it fails, the take expands to a run-time uniqueness test.

- **(a) The result is `once`, with its claim.** The return is the result's
  one use; `writeSignature` writes the claim once and every call copies it;
  a caller that uses it many times, or not at all, casts it out, forgetting
  the claim. Buys: the in-place promise through a call result is met before
  counting, as AGENTS.md reads the promise; idr-unique-results does what its
  name says; rc-exclusive follows only what freshness cannot prove; fewer
  grade copies and run-time tests. Costs: a cast at every call whose result
  is shared or dropped; dead-result elimination needs a rule for results
  (`Optimize/Results.cpp:204`'s reason is about parameters); the
  specializer's result regrading and linear-kept change meaning. Paid by
  L16 (Emit), L08, L18, L19.
- **(b) Kept `many`.** Delete the dead half (about 130 lines with
  linear-kept's result half) and stop idr-in-place grading results
  (`Writer.cpp:47-49, 69-73`, the results half of `PromiseCopies`' key).
  Buys: smaller now. Costs: every in-place obligation through a call result
  waits for the program-wide solve after counting, with its grade copies, or
  for a run-time test; what Emit knew (the callee hands over its one
  reference) is dropped at every return, the drop the 2026-10-23 word names.
  Paid by every program that rebuilds a value a call returned.

Recommendation: **(a)**. It is C286's own rule applied at the call boundary,
and the fact then lives where it is first known.

### Q2. Divergence: C74's per-component verdict, or the transitive verdict Idris already gives

C74 (amended by D102) holds divergence as `#idr.terminates<component N>` on
each function. Six C++ readers rebuild "this cycle may diverge" from it and
the call graph, and the frontend re-runs Tarjan and the size-change search
over the whole reached program per compile (`Recursion.idr`, 162 lines),
because the checker computes components and drops them. Both options put
`idr.may_loop` at the entry of every body Idris did not prove (and per local
definition's region), carried with the code, which deletes about 100 lines
of readers.

- **(a) Keep the per-component verdict.** Marks go on functions whose own
  component is endless; `addCycles` stays for cycles a pass makes across
  components; the checker gains each member's own-loop verdict and its
  component (named by its least member, the same in every session) in its
  totality record and TTC, searched before the early `BadPath` return, so
  `Recursion.idr` goes. About 280 deleted, a field added to the checker
  (built by both hosts). Keeps precision: a function whose own loops
  decrease but which calls a partial function gets divergence only through
  the callee's row, so it becomes deletable if an optimization removes that
  call.
- **(b) Use `Defined.ends`, which the frontend already reads.** A mark on
  every function not `IsTerminating`; nothing in the C++ reads a
  termination proof; the attribute, `provedTogether`, `addCycles`,
  `Component.cpp`'s rule, the contract and its test, the specification's
  `Termination.idr`, its encodings and `Recursion.idr` all go: about 700
  lines, no checker change. It is AGENTS.md's own sentence ("an endless loop
  is an effect of code not proved total"). Costs: the precision case above,
  rare and never unsound; soundness across cycles that specialization and
  defunctionalization make rests on Idris's soundness (size change plus
  positivity, decided for every type constructor at each module's end,
  upstream #524), read and not yet tested; C74 is amended.

Recommendation: **(b)**, with a two-host program test of C74's motivating
`data D = MkD (D -> Nat)` written first, so the positivity precondition is
seen to hold.

### Q3. The reindex: one op asked by every reader, or one op per meaning

C206 made `idr.data.reindex` one op whose run-time work follows from its two
types, which the frontend cannot know; C275 (2026-10-23) rejected storing
that answer on the op and splitting the op, since the distinction is derived
from the types. The audit finds about twenty readers deriving it again per
query, among them an effect pair-rule mechanism (about 170 lines in the
specification and C++) that exists for this op alone, and the carry that
tail position rests on.

- **(a) Three ops from the specification's list.** A free reindex (pure,
  speculatable, carries freely, no effect, a cast as `tensor.cast` is), a
  re-pack that works, and a re-pack that allocates (`Acquisition` on its
  result), each with static effects, speculation and carry; a field read is
  a projection at its slot's layout, with the re-pack appended where the
  binder lays out otherwise. The frontend still writes one form; the C++
  builder picks the op where it is made (the boundary's builder, as
  `getNormalized` already normalizes) and again only where substitution
  rewrites its types, which already re-infers every op. Buys about 300
  deleted (80 added), static ODS facts in place of a per-query derivation.
  Costs: substitution replaces an op when a closed index changes its class;
  three ops to declare and model; C275 reversed and C206 amended. Paid by
  L04, L01, L09, L12, L21, L10.
- **(b) Keep C275.** One op and one classifier; with C5's stored unfolding
  the classifier compares stored facts instead of unifying, so each query is
  cheaper, but every reader still asks, and the pair-rule machinery and
  `byCarry` stay.

Recommendation: **(a)**: AGENTS.md's "an operand, attribute or enum that
changes what an op means or may do is a flag, and the op is two", with the
types as that flag, and the 2026-10-23 rule on facts first known where the
op is made.

### Q4. The tail fact: a terminator op, an enum Emit writes, or C203 as it stands

AGENTS.md: whether a call is in tail position "is one fact on the call,
decided once and obeyed by every pass". Under C203 the frontend writes every
call `nontail`, the decider writes `tail` and `modulo_context` at first
order, and every pass that edits a body runs it again over the whole
function (12 calls at 11 sites), with per-query readers and verifier walks
after every pass. Emit already knows every tail by construction (its
`Scope`).

- **(a) A tail call is its own terminator op**, leaving through every
  `PropagateControlFlowBreak` op to the function's exit by the mechanism
  `idr.jump` already uses (upstream's early exit, patch 65). Emit writes it
  where a position-indexed `Scope` stands at a tail (apply and force too);
  `modulo_context` stays the decider's. "Nothing follows a tail call" is
  MLIR's terminator check, no pass can put an op after one, and the lowering
  emits `musttail` and a return with no block split. Deletes about 230.
  Costs: a new op every call-handling pass must know; the inliner's
  terminator hook turns an inlined tail call at a non-tail site into a call
  and a yield; the region rule as `idr.jump` has it; C203 amended. Paid by
  L10, L18, L14, L16, L02, L03.
- **(b) The enum stays on `idr.call`**; Emit writes `tail` from the indexed
  `Scope` (apply and force carry it), each pass writes the kind where it
  places a call, `decideTails` goes. Deletes about 170; C203 amended. Costs:
  the enum is a flag that changes what the op may do, kept honest by a
  verifier walk after every pass.
- **(c) C203 as it stands.**

Recommendation: **(a)**, built directly (no step through (b), whose per-pass
writes (a) would rewrite). The lost tail call is fixed now under any option
(U09).

### Q5. Solved metavariables: filled in by the checker, or kept as references

Ask after W04 lands CB-8 and R-META is measured again, since a stale parent
may be what reaches it. The checker writes each solution as a definition
whose type the TTC drops, and leaves bound pattern variables as `ImpBind`
references inside other solutions; the frontend tables every metavariable
named anywhere, refuses what it cannot tell (R-META: three of five of our
programs, measured by INT-24), and fills solutions in again at every
normalisation (`Closed.idr:355-397`).

- **(a) The checker fills each solution in, and maps each pattern variable
  to its local, in every term of a definition before the TTC writes it**;
  the decoder states "a `Meta` read from a TTC names a hole". Deletes about
  230 lines and a walk plus a normaliser run per normalisation. Costs: a
  solution copied at every use in the TTC (upstream keeps metavariables as
  globals so a back end compiles each once; the frontend already copies at
  every normalisation); a checker change and TTC bump built by both hosts.
  Paid by L17, L16.
- **(b) The boundary fills solutions in once per definition read.** The
  per-normalisation walk goes; the table, the solution reading and the
  pattern-variable gap stay (only the checker knows the local a pattern
  variable became).
- **(c) As now.**

Recommendation: **(a)**.

### Q6. A cell's buffer opened as a tensor: by an op taking the cell, or by a flag written where claims are raised

Emit casts a buffer field to the bare carrier before `to_tensor` (upstream's
op takes the bare type), forgetting its uses and claim; a share may land
between; bufferization walks back through casts and uses to decide
`writable`. For `LArray` the field is declared at ω, so D122's rule (a
`unique self` cell claims its buffer's storage) is never reached.

- **(a) One op of ours opens a held buffer as a tensor, taking the cell** (the
  buffer moved out once), so `writable` is its operand's claim. Buys: one
  place for the fact, no chain a pass can break, D122 reached for every
  family. Costs: an op in the specification with its bufferization model;
  Emit's `caseFields`. Paid by L12, L16.
- **(b) `writable` written on `to_tensor` by the passes that raise the
  claim.** The fact in two places, kept in step by every writer of claims.
- **(c) The library declares the field at quantity 1** (L20), so the read
  gives `unique self` by the table; `freeze`'s `!*` needs ω, so it does not
  hold for this family as written.

Recommendation: **(a)**.

### Not asked (evidence first, or too small to spend a question on)

- shar 3 (who records that a callee keeps nothing of a parameter: a fact on
  the function, or an explicit `idr.lend`): the report's own confidence is
  conjecture (the two markings differ in tail calls, frames and quantity-1
  arguments). L08 shows what they share after W06.
- ctrl R5's destination form (a self call modulo a context takes the hole's
  `!idr.dest` where it is decided): after Q4, and only with an L07 design
  for counting a destination before counting runs.
- const 4 (a function's parameter and result intervals as an inherent
  property of `idr.func`, lowered to LLVM's `range`): the report's carrier
  is conjecture (that the e-graph's final intervals are tight enough to
  replace the returns phase); L14 measures first.
- const 6's type guarantees, const 2's double statement (type and attribute
  holding a closed natural), const 10 (a loop's descent on the self call,
  conjecture): small, or unestablished.

---

## 4. Dispatch

### Who holds what now (git status at 2c500794)

| Lane | Holds |
|---|---|
| L05y (C286) | `Emit/{Bodies,Monad,Operations}.idr`; `Spec/Grades/{Declarations,Grade}.idr`; `Generated/Grades.h.inc`; `Analysis/Ownership/Local.h`; `InPlace/Unique.{h,cpp}`; `Verify/{Local,Program}.cpp`; `OpsCon.cpp`, `OpsConReads.cpp`; `Families.h`, `Families/{Refinement,Repacks}.cpp`; `Flow.h`, `FlowEdges.{h,cpp}`, `FlowOps.cpp`, `OpsArrays.cpp` (by hunk); `Lifetimes.h`, `Lifetimes/Ops.cpp`, `Counting/{Borrows,PlacementRewrite}.cpp`, `Counting/Placement.h`, `Bufferize/Reindex.cpp`, `Specialize/Open.cpp` (by hunk: `builtHold(uses, …)`, a lent view claiming nothing); the reindex, open, lowered-hold and built-of-a-shared-part tests |
| L14ac (D132) | `EGraph/*` (with the new `Regions.cpp`), `EGraph.h`, `EGraph/Engine.h`; `Analysis/Constants.*` and `Effects/Constants.cpp` (deleted); `Transforms/Effects.h`; `Optimize.h`, `Optimize/{Optimize,Settle}.cpp`; `Conversion/Lower.cpp`; the two CMakeLists; `Spec/Core/Admitted.idr`, `Spec/Ops/Shapes.idr`, `Spec/Generator/Cpp.idr`, `Generated/Rewrites.h.inc` (by hunk); `PINS.md` |
| L16et (C281 steps 1, 2) | `Frontend/Translate/*`, `Growth/*` (clean this moment: L16ep landed bc08f095) |
| L16er | `Frontend/Profile.idr`, `Registry/Libraries.idr`, `tools/self.sh` |
| L17be/bf/bg/bh | `compiler/checker/**`; `Proof/{Covers,Requests}.idr` and the deleted `Proof/{Dictionaries,Primitives}.idr` (D133 step 1) |
| shared | `foreign/idr/generated.manifest` (L05y, L14ac) |

A unit that changes the specification starts now but lands its
regeneration through INT after L05y's and L14ac's, which hold the manifest.
No C++ unit can be built on this machine; each says what it could not run.
Every dispatch packet carries representation-first and testing-by-search,
and each handoff names, per finding, the state made unrepresentable, the
check moved or the branch deleted.

### Fold-ins: no new lane, given to the lane that holds the files

| | To | Findings | Why there |
|---|---|---|---|
| F1 | L14ac | const 9 (the `constants` pass and its actions still in `Spec/Pipeline/Pipeline.idr:529-535, 566`; generated `IdrInnerPasses.td`, `Actions.h.inc`); ctrl R6's `CalleeFacts` keyed by `FunctionId` (`Simplify.cpp:63-75`, `Nodes.cpp:559-566`) | D132's landing breaks the build without the first; L14ac is moving returned constants into `CalleeFacts` now |
| F2 | L05y | mult R4 (`flowsLinearly`); C1's settled part: region yields at `w.uses`, mult R6's scrutinee at its own grade; shar 1 item 2 and shar 2's writer (idr-in-place stops admitting and grading `many` values before counting: `Chains.cpp`, `Versions.cpp`, `Writer.cpp`, `Rule.h`) | the same rule and files as C286; the contradiction otherwise lands with it |
| F3 | L16er | CB-10 (`self.sh` derives the list from the ipkgs) | its in-flight file |
| F4 | L17bh | CB-4 (the frozen context decodes an entry when read) | D133 step 4 is that freeze; an eager decode keeps the measured cost |

If L05y declines F2, its Emit half becomes W05's first item and its
idr-in-place half W06's.

### Units that wait on nothing (start now; write paths disjoint)

| Unit | Carrier: findings | Files | Owner | Lines |
|---|---|---|---|---|
| U01 | C17: const 1 | `Analysis/Ranges.{cpp,h}`, `Transforms/Narrow/*`, `Narrow.h` | L12, with L14 | ~50 |
| U02 | C7: eff 4 | `Conversion/Matches.cpp` | L09 | ~15 |
| U03 | C7: eff 6; C15: id 5's consumer bucket | `Specialize/Consumer.cpp`, `Specialize.h` (stale comment) | L18 | ~10 |
| U04 | C16: eff 7 | `Spec/Ops/{IO,Checks}.idr`, `Conversion/RuntimeCalls.cpp` (`LowerExit`), the runtime's exit helper, `Spec/Runtime/Endings.idr` | L13, with L21, L11 | ~12 |
| U05 | C18: shar 8 | `Counting/{Expand,ReuseAssign}.cpp`, `Lower/Counting.cpp`, the runtime's token helper | L07, with L21 | ~10 |
| U06 | C13: const 3, fold half | `IR/Fold/Scope.cpp` (callers keep `bigOf`/`bigAttr`'s signatures) | L13 | ~15 |
| U07 | C15: id 6; C13: const 3, lowering half | `Conversion/{StaticData,StaticNames,StaticBytes,Runtime}.cpp`, `StaticData.h`, `Lower/{Statics,Accounts,Lifetimes,Values}.cpp` | L21 | ~35 |
| U08 | C5: type 4; C15: id 5's storage digest | `Families/DataNormal.cpp`, `IR/Types.cpp`, `IR/ContentNames.cpp`, `IR/Symbols.cpp`, `Symbols.h`, `Families/FamilyStorage.h`, `Spec/Families/Types.idr` | L04 | ~45 |
| U09 | C9: ctrl R4's lost tail call | a new two-host program test (a direct tail call to a closure-returning function with fewer labels than its caller), then `Analysis/LabelSites.cpp`'s direct-call unification reads the structural standing, as `readFiring` does for applies | L19, then L14 | ~5 |
| U10 | C9: ctrl R5's dead guard | `Tail/Trmc.cpp:111-118` | L10 | ~8 |
| U11 | C14: id 3, 4, 14 | `Spec/Generator/Idris.idr`, `idris-mlir-tblgen.cpp`, `MLIR.idr`, `MLIR/Bytecode.idr`, the generated `Dialect/*` and `Encoding/*`, `SyntaxSamples.idr`, `OpIndex.h.inc`, `Emit/Index.idr`'s `typeIn` | L03, with L16 | ~150 |
| U12 | C20: id 9, mult R8 | `harness/{Facts,Programs,Fuzz,FuzzRun}.idr`, `Expect/Quantities.cpp` | L19 | ~10 |
| U13 | C20: id 12, 13 | `Driver/{Run,LinkRuntime}.cpp` | L11 | ~18 |
| U14 | C20: id 15 | `Target/Schedules.cpp`, `Transforms/Pipeline.cpp` | L21, with L03 | ~30 |

About 410 lines. Caveats, each a hunk that waits while the rest goes:

- U04: if Emit needs a hand edit to write the status guard (rather than
  `specGuarded` reading the specification), that hunk of
  `Emit/Operations.idr` waits on L05y.
- U07: if the address rewrite needs `Conversion/Lower.cpp`, that hunk waits
  on L14ac; cull/pipeline.md 5 (merging idr-lower-statics into idr-lower) is
  compatible and goes to the same lane.
- U08: the base is threaded inside `refined`/`refinedTo` so the 22 callers of
  a refined `get` are untouched; any caller hunk waits on its lane
  (`Refinement.cpp` is L05y's). cull/pipeline.md 1 (deleting
  idr-deduplicate) removes one of id 5's callers.
- U11: `Emit/Operations.idr:104-105` (`MkOpName`) waits on L05y; one lane
  takes cull/frontend.md 2 with it (the same writer files).

### Units that wait on a running lane (no ruling needed)

| Unit | Carrier: findings | Files | Owner | Waits on |
|---|---|---|---|---|
| W01 | C11: CB-3, CB-5 (frontend), CB-9, mult R7, type 5 (snoc), type 8; C14: id 11; C20: id 1's artifact | `Frontend/Translate/*`, `Growth/*`, `Fields.idr`, `Implementations.idr`, `Keys.idr`, the driver's artifact | L16 | L16et (C281's fold); L17bh's D133 step 4 |
| W02 | C20: id 1 | `harness/Covers.idr` | L19 | W01's table |
| W03 | C19: CB-7, id 8, id 10, mult R9 (and `sameName`) | `Frontend/Resolve.idr`, `Registry.idr`, `Registry/{Entry,Recognized,Libraries}.idr`, `Profile.idr:328`, the prefix-install step (`Makefile`, INT), its test (L19) | L16 | L16er |
| W04 | C10: CB-8 / id 2, CB-6 / id 7, CB-5 (checker) | checker: `Core/Name.idr`, `TTImp/Elab/{Local,App}.idr`, `ImplicitBind.idr`, `Core/{TTC,Context,Binary,Metadata}.idr`, `ProcessDef.idr`; frontend: `Boundary.idr`, `State.idr`, `TypeConstructors.idr`, `Keys.idr`, `Closed.idr`, `Profile.idr`, `Registry.idr`, `Recognized.idr`, `Entry.idr` | L17, then L16 | L17's TTC bump (D133); the frontend half after W01 and W03. CB-8 first: correctness, and Q5 waits on it |
| W05 | Emit after C286: C1 (F2 if declined), C2 (fields at `times`, closure grade by the generated builder), C12 (type 3, type 6, const 8), C13 (const 2's literal at its slot), C16 (const 5's refinement and `specGuarded`), C18 (shar 4, 10's Emit parts) | `Emit/*`, `Ids.idr`, `Types.idr`, `Term.idr` | L16 | L05y; U11 (`Generator/Idris.idr`, `typeIn`); type 6's ripple and const 2's keyed parameter after W01 |
| W06 | C1 (L08 half), C18: shar 4, 5, 7, 10 | `InPlace/*`, `Analysis/Ownership/{Local.h,Facts.h}`, `Ownership/Exclusive.cpp`, `Analysis/Ownership/Exclusivity*.cpp`, `Verify/Local.cpp`, `OpsCon.cpp`, `Grades.h` (claims), `Spec/Grades/*`, the specification's trait | L08, with L05, L04, L03 | L05y; shar 7's `Generator/Cpp.idr` after L14ac |
| W07 | C2 (C++ half), C1: mult R10, C5: type 7 | `IR/Counting/Ops.cpp`, `Verify/Uses.cpp`, `Grades.h` (walkers), `Families/Rules.cpp`, `OpsConReads.cpp`, `OpsClosures.cpp`, `Specialize/{Patterns,Keys}.cpp`, Narrow's `throughLinear` readers, `Counting/Reuse.cpp`, `Verify/Program.cpp`, `Spec/Counting`, `Generator/Ods.idr` | L05, with L07, L18, L04, L03 | L05y; W06 (`Grades.h`); U01 (Narrow) |
| W08 | C13: const 7; C16: const 6 (settled part, verifier rule first); C15: ctrl R6's other readers | `EGraph/{Build,Nodes,Values}.cpp`, `IR/Ranges.cpp`, `OpsChecks.cpp`, `OpsBigs.cpp`, `Fold.h`, `Numeric/Trait.h`, `Traits.h`, `Specialize/Requests.cpp`; `Open.cpp:969, 991` | L14, with L13, L03, L18 | L14ac; the `Open.cpp` hunk after L05y |
| W09 | C5: type 2; C13: type 9 | `Layout/*`, `Families/{Repacks,Refinement,DataNormal}.cpp`, `Families.h`, `IR/Types.cpp`, `IR/Constants.cpp`, `Fold/Values.cpp` | L04, with L13 | L05y; U08 |
| W10 | C8: ctrl R2, eff 3 | `Spec/Pipeline/{Pass,Pipeline}.idr`, `IdrDialect.h` (`StagedPass`), `Generator/Cpp.idr`, `Analysis/Solver/ProgramGraph.*`, `Effects/Writer.cpp`, `Transforms/Effects.h`, the hand preservation in about fifteen passes | L03, with L14, L02 and each pass's lane | L14ac; L05y (`Counting/Borrows.cpp`); U05, U07; W06 (`Cpp.idr`); a measurement of the writer's share |

### Units that wait on a ruling

| Unit | Ruling | Carrier: findings | Lanes and files | Also waits on |
|---|---|---|---|---|
| O1 | Q1 | C1's result half | W05 (`Emit/Index.idr:179-183`, `Bodies.idr:190-193`); W06 (`Unique.cpp`, `UniqueResults.cpp`, `Unique.h`, `Writer.cpp`, `GradeCopies.h`, `Exclusive.cpp`); L18 (`Optimize/Results.cpp`, `Specialize/Open.cpp`); L19 (`Contracts.cpp`, `tests/contracts-linear-kept`) | L05y |
| O2 | Q2 | C6: eff 1, 2, 5; ctrl R3; CB-2 | L16 (`Emit/Closures.idr`, `Term.idr`, `Translate/{State,Boundary,Programs}.idr`, `Recursion.idr`, Encoding); L02 (`Fold.cpp`, `Analysis/Effects.h`, `Effects/{Writer,Component}.cpp`, `Func.h`, `Func/Values.cpp`, `Spec/Functions/{Termination,Declarations}.idr`); L09 (`Joins/*`, `Joins.h`); L10 (`Dissolve.cpp`); L18 (`Contify.cpp`, `CaseOfCase.cpp`, `JoinLoops.cpp`); L19 (the contract and its test); L15 (`unittests/Rows.cpp`); under (a), L17 (`SizeChange.idr`, `TT.idr`, `TTC.idr`) | L14ac (`Settle.cpp`); L05y (`Bodies.idr:513-521`); L16et; the positivity test first |
| O3 | Q3 | C4: type 1, b2aab6e9's builders | L04 (`Spec/Families/Ops.idr`, `Refinement.cpp`, `Repacks.cpp`, `OpsConReads.cpp`, `Families.h`); L01 (the pair machinery); L09 (`FlowOps.cpp`); L12 (`Bufferize/Reindex.cpp`); L21 (`Lower/Repack.cpp`); L10 (`Tail.cpp`, `Tail/Accumulate.cpp`, `Defunctionalize/Walk.cpp`); L13 (`Constants.cpp`) | L05y; W09 |
| O4 | Q4 | C9: ctrl R1, R4, R5's verifier move | L10 (`IR/Tail*`, `Tail/*`, `TailCalls.cpp`); L18 (`Optimize/Tails.h`, Redirect, Raise, Inline, InlinePass, CaptureDrops, `Defunctionalize/{Pass,Edits}.cpp`, `Open.cpp`); L14 (`Elaborate.cpp`, LabelSites' tails table); L12 (`Narrow.cpp`); L02 (`Func/Inliner.cpp`, `Spec/Functions/Tail.idr`); L03 (`Stage.idr`); L16 (W05's `Scope`) | L14ac; L05y; U01, U09, U10 |
| O5 | Q5 | C10: CB-1 | L17 (`ProcessDef.idr`, `TTC.idr`, `ImplicitBind.idr`); L16 (`Boundary.idr`, `Closed.idr`, `State.idr`, `Terms.idr`, `Profile.idr`) | W04 and R-META measured again; D133's steps |
| O6 | Q6 | C3: mult R3, shar 6 | L12 (`Bufferize/Releases.cpp`, the op's specification and model); L16 (W05's `caseFields`) | L05y |

### Order where write paths meet

U01 before W07 and O4 (Narrow); U05 and U07 before W10 (Expand's and the
statics' preservation); U08 before W09 (`DataNormal.cpp`, `Types.cpp`); U09
before O4 (LabelSites); U10 before O4 (Trmc); U11 before W05 (the generator,
`typeIn`); W03 before W04's `Profile.idr` hunks; W06 before W07
(`Grades.h`) and before W10 (`Generator/Cpp.idr`); W09 before O3. Units
of one carrier that sit in different lanes (C1: F2, W05, W06, O1; C2: W05,
W07; C10: W04, O5; C16: U04, W05, W08) land together in the one cutover.

---

## 5. Summary

The eight reports hold 77 findings, 68 distinct facts once duplicates across
reports are merged (three auditors found `Recursion.idr`'s second
termination search on their own), fixed by 20 carriers. Under the
recommended answers to the six questions, the fixes delete about 3,850
hand-written lines (about 2,900 under the smaller answers), plus regenerated
output and cull A's 399 lines of `#idr.given_back` this plan leaves to the
cull; about 410 of those lines sit in 14 units that wait on nothing, and
four fold-ins go to lanes already holding the files. The three highest-value
carriers: **C6**, divergence carried with the code by `idr.may_loop` (about
700 lines under Q2 (b), and a whole-program Tarjan and size-change search
per compile gone); **C10**, the checker's output contract (about 355 lines
settled now and 230 under Q5, a correctness defect fixed, since a nested
definition's parent is another session's entry number, and R-META's
measured refusals of three of five of our programs addressed); and **C1**,
fresh values carrying their one consumer's uses (about 250 lines, a live
contradiction between idr-in-place and C286's stage rule, and run-time
uniqueness tests where freshness is the proof).
