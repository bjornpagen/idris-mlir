<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Recheck 5, R5f: AGENTS.md's measurable rules, swept over the tree

HEAD at start `17725fdd`, at finish `04c2393d`. Six commits landed while
this was read (`2bcbd726`, `16ac96c4`, `59dcc964`, `cb5cd6fb`, `410113a7`,
`04c2393d`); the C++ counts were taken again after `410113a7`, and the
last commit touched only a test. The working tree
holds uncommitted edits by the lanes in flight. Two of the edited files
fall outside the common list's in-flight files: `lib/IR/Constants.cpp`
(D126 2b-S, closure holding) and `lib/Conversion/Lower.cpp` (a comment).
Every line number below is HEAD's text. Nothing was built, typechecked,
generated or run.

Grounds: *read* means the cited line was opened. *Measured* means a count
made with the command given. Where a plain grep would also count comments,
the count comes from a scan that strips comments and strings and reads
each template argument. The scan was written for this sweep and kept
outside the tree. Paths are under `foreign/idr/` unless they start with
another top-level directory. Owners are the longest prefix in
`ownership.json`.

## C++ (foreign/idr, runtime/, tools; Generated/ and upstream excluded)

- **(a) Greedy driver, canonicalize, canonicalization patterns.**
  **Done.** No hit for any of the three forms:
  - `git grep -nE 'applyPatternsGreedily|applyPatternsAndFoldGreedily|applyOpPatternsGreedily|GreedyRewriteConfig' -- foreign/idr runtime ':!foreign/idr/include/idr/IR/Generated'` returns 0.
  - `createCanonicalizerPass|canonicalize` returns 0 over `foreign/idr`, `runtime` and `compiler/spec`.
  - `getCanonicalizationPatterns|hasCanonicalizer` returns 0.

  The spec's pipeline runs no `canonicalize`. Its upstream passes are
  SymbolDCE through ReconcileUnrealizedCasts
  (`compiler/spec/IdrisMLIR/Spec/Pipeline/Pipeline.idr:101-111`). The
  seven `walkAndApplyPatterns` calls use upstream's one-pass walk driver,
  not the greedy one: `lib/Conversion/Lower.cpp:219`,
  `Lower/Accounts.cpp:107`, `lib/Transforms/Narrow/Copy.cpp:129-130`,
  `Narrow/Narrow.cpp:217` and `StructureLoops/StructureLoops.cpp:103,127`.
  (measured)

- **(b) `std::function`, and recursion through a type-erased callback.**
  **Done.** `std::function`, `move_only_function` and `copyable_function`
  have 0 hits. `function_ref` appears on 30 lines:
  - 20 are upstream's diagnostic hook, `function_ref<InFlightDiagnostic()>`;
  - 3 are comments;
  - 7 are signatures MLIR's mechanisms fix:
    - `verifyParts` (`lib/IR/Constants.cpp:69,136,162`): a ConstantAttrInterface method (`include/idr/IR/Generated/IdrInterfaces.td:231`);
    - `atFreshPositions` (`lib/Transforms/Defunctionalize/Indices.cpp:123,142`): an IndexPositionsTypeInterface method (`IdrInterfaces.td:79`);
    - `walkFamily` (`lib/IR/Families/SubElements.cpp:130-131`): upstream's `WalkImmediateSubElementsFn`.

  An interface method cannot be a template.

  None of the seven recurses. `verifyParts`'s one caller is a worklist
  (`lib/IR/Constants.cpp:251-266`), and `atFreshPositions`' `next` is a
  counter (`Indices.cpp:53-56`, asked at `:72`). A scan for a function whose lambda calls that
  function again finds only `match` cases, which are templates, not
  type-erased. (measured, read)

- **(c) Maps keyed by `Operation *`, `Value`, `Block *`, `Region *`.**
  **Done.** 15 lines are keyed by an MLIR handle. Each one numbers handles
  into a vector, marks a visited set for one walk, or keeps the ordered
  list of a loop's inputs:
  - numberings: `include/idr/Analysis/Solver/Extraction.h:145`, `LabelPoints.h:94`, `LabelPoints.h:145`, `lib/Transforms/Bufferize/Releases.cpp:117`, `EGraph/Simplify.cpp:147` (in flight, L14x), `Narrow/Widths.cpp:104` and `StructureLoops/Linalg.cpp:44`;
  - visited sets for one walk: `include/idr/IR/Lifetimes/Loans.h:65` and `lib/Transforms/Narrow/Versions.cpp:50` (pairs of values, each asked once);
  - ordered input lists, the shape of upstream's `getUsedValuesDefinedAbove`: `include/idr/Transforms/Narrow.h:270`, `:316`, `Narrow/Copy.cpp:31`, `Narrow/Lanes.cpp:178`, `Narrow/Widths.cpp:59-60` and `Specialize/Consumer.cpp:147`.

  No map is keyed by a `Block *` or a `Region *`.

  The LLVM-handle maps after lowering are numberings or visited sets, each
  with its reason written beside it: `lib/Driver/Prepare.cpp:79`,
  `Driver/StackBound.cpp:146` and `Target/Partition.cpp:59, 141, 244`.

  The typedef keys hold declarations or uniqued attributes, never an IR
  node: FlowAnchor (`include/idr/IR/FlowEdges.h:85-110`), the exclusivity
  `Key` (`ExclusivityDetail.h:118-121`), TypeGraph's, Defunctionalize's
  and Captures' `Ctor`. The command was
  `git grep -nE '(DenseMap|DenseSet|SmallDenseMap|SmallDenseSet|SmallPtrSet|SetVector|MapVector|std::map|std::set|unordered_map|unordered_set)\s*<'`,
  120 lines, filtered by key. (measured, read)

- **(d) Parameters that are a choice typed `bool`.**
  **Partial.** Every declaration in the 603 files was swept, comments
  stripped: 16 hits. These three are choices:
  - `runtime/Platform/Platform.h:265` and `runtime/Platform/Posix/Process.cpp:38`: `setEnvironment(…, bool overwrite)`, whether to replace a variable or keep it. Its one caller converts the ABI's integer, `overwrite != 0` (`runtime/Io/Process.cpp:56-57`).
  - `runtime/End/End.cpp:86`: `number(uint64_t value, bool negative)`. The sign is printed or not; this is the weaker case, a sign carried beside its magnitude.
  - `lib/IR/ValueFacts.cpp:35`: `template <typename T, bool counted> struct ArrayFacts` (in flight, D126 2b-S).

  The rest are not choices:
  - truth values handed to a check: `include/idr/Testing/Box.h:69`, `unittests/Hooks.cpp:42`, `HooksCompare.cpp:51` and `Refusals.cpp:330`;
  - upstream signatures: `lib/IR/ContentNames.cpp:132` (`writeOwnedBool`), `lib/Transforms/Bufferize/Bufferize.cpp:305` (`tensorAllocationFn`) and `runtime/Alloc/Cells.cpp:162` (snmalloc's `amplify`);
  - locals: `bool held = true, …` in `lib/Transforms/Expect/*`.

  Owner: L11. Remaining: `setEnvironment` takes an enum (overwrite or keep
  a set variable), converted once from the ABI's `int64_t` in
  `idris_rt_io_env_set`. `number` takes the sign as an enum, or the signed
  value. (measured, read)

- **(e) D126 round 3's list.**
  **Partial.** D126 is not finished: 14 sites still form ladders over our
  classes, and 5 more call for D126's typed signature or typed walk.

  The counts come from a scan of the nine cast forms (`isa`, `dyn_cast`,
  `cast`, `isa_and_nonnull`, `isa_and_present`, `dyn_cast_or_null`,
  `dyn_cast_if_present`, `cast_or_null`, `cast_if_present`, and
  `TypeSwitch`/`.Case`). Each template argument was matched against the
  classes the generated `.td` define: 201 ops, 13 types, 32 attributes and
  32 interfaces. The scan finds 1,036 sites outside `Generated/`:
  - 370 over our concrete classes (333 outside the in-flight files, 37 in them);
  - 96 over our interfaces;
  - 570 over upstream classes or template parameters.

  `TypeSwitch` is used nowhere. A grep that counts comments,
  `git grep -h -o -E '(isa|dyn_cast)<' -- foreign/idr ':!foreign/idr/include/idr/IR/Generated' | wc -l`,
  gives 606 at HEAD; bb8ce09c's count was 590.

  Of the 333 sites outside flight: 14 are ladders (13 counted by the scan,
  plus one variadic template), 5 call for D126's other forms, 190 are
  single typed tests, 115 are casts already decided, and 10 are unit
  tests. Owners are per site, and D126's units take them.

  **Ladders D126 removes, as two units.**

  *Unit R3-A, the closure and suspension carriers* (7 sites; L05, L09, L13, L18):
  - `lib/IR/Grades.cpp:238` (`isClosureType`, `isa<FnType>`) and `:240` (`isLazyType`, `isa<LazyType>`): the two predicates whose callers chain them, at `lib/IR/FlowEdges.cpp:34-37` and `lib/IR/Constants.cpp:40` (`ClosureAttr::isBuildableAt`).
  - `lib/IR/FlowEdges.cpp:31` (`Carriers::of`): `CellType`, then `FnType`, `LazyType` and references, one ladder.
  - `lib/IR/Constants.cpp:83` and `:111` (`ClosureAttr::verifyParts`): `LazyType`, else `FnType`. The file is being edited in the working tree.
  - `lib/Transforms/Defunctionalize/Declare.cpp:59` (`arity`): `FnType`, else a suspension's 0.
  - `include/idr/Transforms/Defunctionalize.h:71` (`carrierOf`): `LazyType`, else a closure, read into `enum class Carrier : bool`.
  - Beside them, though not a cast site: `lib/IR/Families/Family.cpp:65-67`, where `closureReach`'s walker callbacks on `FnType` and `LazyType` answer the same question.

  What answers them: one type method, declared in the specification,
  for what a value of the type carries for the label solve. It gives the
  `Carriers` set and, for a label's carrier, its call arity. FnType and
  LazyType implement it; CellType answers with its value's, and GradedType
  with its carrier's. No such method exists yet: ValueFactsTypeInterface
  has `holdsReferences`, `getByType`, `isCounted` and `isCellPointer`.

  *Unit R3-B, the rest* (7 sites; L04, L13, L19, L12, L09):
  - `lib/IR/Layout/Classes.cpp:259` and `:262`: `SelfType`, else `DataType`. bb8ce09c kept this split "with its reason"; D126 admits no `isa` chain over our types, so the keep is the coordinator's, not the ruling's. Answer: `IndexedTypeInterface::getPositionalMember`, which TypeGraph already asks (74632859), names a member by position for both.
  - `lib/IR/Ops/Constraints.cpp:25`, instantiated at `:58-59` (`isBigOrNatRead`, `isBigOrNatValue`): `isa<BigType, NatType>`. Answer: `NumericTypeInterface::isCarriedAsBig`, which is true for exactly those two (`lib/IR/TypeLiterals.cpp:95-97`, `lib/IR/Types.cpp:305`).
  - `lib/Transforms/Expect/ResetsUnshared.cpp:51`: `isa<CellType, ReuseTokenType>`. Its comment says "no value fact says 'a cell's memory'"; a new ValueFactsTypeInterface method says it.
  - `lib/Transforms/Narrow/Narrow.cpp:146`: `isa<BigToIntOp>` after `BigOfIntegerOpInterface` and `ConstantLike`, recheck 3's D7 remnant. Its comment argues against a trait. The specification's `BigToWord` table already lists `BigToIntOp` (`include/idr/IR/Generated/BigToWord.h.inc`). Answer: the word side of the conversion, declared on the op in the specification (new).
  - `lib/Conversion/Matches.cpp:314` and `:318`: `YieldOp`, else `JumpOp`, on a block's terminator. Answer: upstream's `RegionBranchTerminatorOpInterface::getSuccessorRegions`, which both ops implement (`lib/IR/Control/Joins.cpp:170-172` casts a yield to it).

  **D126's other forms (5 sites).** D126 rules that a function taking a
  bare handle and casting takes the op's type, and that a walk testing
  each op is a typed walk:
  - `lib/Transforms/Counting/Borrows.cpp:300` (L07): `findLoans`' walk handles only `CallOp` and region-branch terminators. Fix: two typed walks.
  - `include/idr/Transforms/Expect.h:231` (L19): `id(FunctionOpInterface)` casts to `FuncOp`. Fix: it takes `FuncOp`.
  - `lib/IR/Families/FamilyVerify.cpp:47` (L04): `sortsOfMember(Attribute payload, …)` casts a non-null payload to `FamilyAttr`. Fix: it takes `FamilyAttr`, where null is the own group.
  - `lib/IR/Lifetimes/Kind.cpp:105` (L05): `lifetimes::kindOf(Value)`. Fix: it takes `TypedValue<LifetimeType>`.
  - `lib/Conversion/Lower/Lifetimes.cpp:104` (L21): a second, local `kindOf(Type)` with the same cast. Fix: it goes, and its three callers (`:117`, `:138`, `:278`) ask `lifetimes::kindOf` of the typed value.

  **Single typed tests that stay (190).** Each tests one class within an
  open set: a value's users or its defining op, a block's terminator, an
  op's parent, a value's type (of any dialect), a folded operand's
  attribute (any constant), or a walk that handles every op and singles
  out one class. Examples of the walk: `lib/Analysis/Ownership/Borrows.cpp:187,195`,
  `lib/Transforms/InPlace/Rule.cpp:178`, `Inline/Inline.cpp:58`,
  `Optimize/Captures.cpp:114` and `Expect/InPlace.cpp:31`. Two more are a
  literal type reading its own literal class (`lib/IR/TypeLiterals.cpp:41,56`).

  Two of the 190 are close to a ladder:
  - `lib/Analysis/IdentitiesRecord.cpp:49` compares two literals by testing `BigAttr`; `LiteralTypeInterface::sameLiteral` (unit D's) would answer it.
  - `lib/Transforms/Defunctionalize/Declare.cpp:142` is a single `DataType` test.

  Files, with counts:
  - 7: `lib/IR/OpsConReads.cpp`.
  - 6: `lib/IR/Grades.cpp`.
  - 5: `lib/IR/Lifetimes/Verify.cpp`, `lib/IR/OpsBigs.cpp`, `lib/Transforms/Tail/ComponentLifetimes.cpp`.
  - 4: `Lifetimes/Read.cpp`, `Tail/AccumulatorPlan.cpp`.
  - 3: `include/idr/Transforms/Counting/Facts.h`, `lib/Analysis/IdentitiesRecord.cpp`, `lib/IR/ConAttr.cpp`, `Counting/CellInit.cpp`, `Counting/Ops.cpp`, `Verify/Linearity.cpp`, `Columns/Records.cpp`, `Optimize/Captures.cpp`, `Tail/Split.cpp`.
  - 2: `Analysis/Ownership/Facts.h`, `Analysis/Ownership/Borrows.cpp`, `Control/Joins.cpp`, `Families/Refinement.cpp`, `Func/Program.cpp`, `Func/Verifier.cpp`, `Layout/Reach.cpp`, `Lifetimes/Loans.cpp`, `Ops/Constraints.cpp`, `OpsArrayFusion.cpp`, `OpsArrayRules.cpp`, `OpsMatch.cpp`, `Symbols.cpp`, `TypeLiterals.cpp`, `Counting/Placement.cpp`, `Expect/Accesses.cpp`, `Expect/Quantities.cpp`, `Expect/ReusesInPlace.cpp`, `InPlace/Rule.cpp`, `InPlace/Sites.cpp`, `Joins/JoinRules.cpp`, `Joins/MatchRules.cpp`, `Joins/Rules.cpp`, `Lifetimes/Lend.cpp`, `Optimize/Results.cpp`, `Ownership/Knots.cpp`, `Specialize/Keys.cpp`, `Specialize/Lift.cpp`, `Specialize/Order.cpp`, `StructureLoops/Forms.cpp`, `Tail/Outline.cpp`.
  - 1 each, 64 files:
    - headers: `Analysis/Effects.h`, `IR/Arrays.h`, `IR/Verify.h`, `Transforms/Specialize.h`, `Tail/Frames.h`;
    - analyses: `Analysis/Constants.cpp`, `IdentitiesRebuilds.cpp`, `ExclusivityGraph.cpp`, `Ranges.cpp`;
    - conversion: `Lower/Drops.cpp`, `Lower/Lifetimes.cpp`, `Lower/Regions.cpp`, `Lower/Rooms.cpp`, `Conversion/Matches.cpp`;
    - IR: `Asm.cpp`, `Attrs.cpp`, `Counting/Takes.cpp`, `Counting/Types.cpp`, `Dialect.cpp`, `Effects/Conditions.cpp`, `Families/Family.cpp`, `FamilyVerify.cpp`, `Scopes.cpp`, `Substitute.cpp`, `TermSyntax.cpp`, `Flow.cpp`, `Func/Extents.cpp`, `Func/Func.cpp`, `Layout/Layouts.cpp`, `Lifetimes/Kind.cpp`, `OpsArrayShapes.cpp`, `OpsArrays.cpp`, `OpsClosures.cpp`, `OpsCon.cpp`, `Tail/Context.cpp`, `Verify/Uses.cpp`;
    - transforms: `Bufferize/Bufferize.cpp`, `Contracts/Contracts.cpp`, `Counting/Borrows.cpp`, `Counting/Bound.cpp`, `Counting/Expand.cpp`, `Counting/Reuse.cpp`, `Defunctionalize/Declare.cpp`, `Expect/Allocation.cpp`, `Expect/InPlace.cpp`, `Expect/LabelsLeast.cpp`, `Expect/Named.cpp`, `Expect/ReusesEveryCell.cpp`, `Expect/Stages.cpp`, `Expect/TestsNothing.cpp`, `InPlace/Versions.cpp`, `Inline/Inline.cpp`, `Joins/CaseOfCase.cpp`, `Joins/Joins.cpp`, `Lifetimes/Decide.cpp`, `Narrow/Versions.cpp`, `Optimize/Demand.cpp`, `Optimize/Settle.cpp`, `StructureLoops/Lowering.cpp`, `StructureLoops/Updates.cpp`, `Tail/Accumulate.cpp`, `Tail/Dissolve.cpp`, `Tail/TailLoops.cpp`, `Tail/TrmcRewrite.cpp`.

  Five more single tests ask whether a type or op is the dialect's at all
  (`isa<IdrDialect>`), which only the open set leaves to run time:
  `include/idr/Analysis/Ownership/Facts.h:238`,
  `lib/Conversion/Descriptors.cpp:180`, `Lower.cpp:123`, `IR/Grades.cpp:293`
  and `Verify/Uses.cpp:206`.

  **Casts already decided, which stay (115).** The class is fixed above
  the cast by one of these:
  - the op's ODS constraint on an operand or result type (e.g. `lib/Conversion/Cells.cpp:102-104`, `Lower/Packages.cpp:68,102`; with a grade around the carrier, no typed accessor exists);
  - a parent trait (`lib/IR/OpsClosures.cpp:340`, `Func/Func.cpp:25`, `Func/Call.cpp:311`);
  - an interface or closed sum that already chose the case:
    - `lib/IR/Families/Family.cpp:300,303`, after `getFieldReach`;
    - `Layout/Layouts.cpp:266`;
    - `Conversion/Lower/Rooms.cpp:124`, after `getLifetimeUse`;
    - `Families/Matching.cpp:96,107,113`, inside `matchInstance`;
    - `Tail/Accumulate.cpp:162`, a `ShortCircuit`, which could hold its match;
  - the external model's own op (`lib/Transforms/Bufferize/Generating.cpp:146-193`, `Bufferize/Values.cpp:92`);
  - an upstream API that returns `Operation *` for an op built or cloned as that class (`Tail/Accumulate.cpp:191`, `Specialize/Raise.cpp:80`, `Optimize/Results.cpp:287`);
  - upstream callbacks typed by interface where the stage holds only `idr.call` (`include/idr/Analysis/Constants.h:89`, `lib/Analysis/Ranges.cpp:107`);
  - upstream's legality callbacks registered for one op (`Columns/Calls.cpp:195`, `Columns/ArrayOps.cpp:98`).

  Files, with counts:
  - 6: `OpsClosures.cpp`, `Bufferize/Generating.cpp`.
  - 4: `Conversion/Cells.cpp`, `Tail/Accumulate.cpp`.
  - 3: `ConAttr.cpp`, `Counting/Takes.cpp`, `Families/Family.cpp`, `Families/Matching.cpp`, `FlowOps.cpp`, `Columns/Calls.cpp`, `Joins/CaseOfCase.cpp`.
  - 2: `IR/Families/Families.h`, `Lower/Counting.cpp`, `Lower/Lifetimes.cpp`, `Lower/Packages.cpp`, `Lower/Repack.cpp`, `Control/Joins.cpp`, `Counting/Flow.cpp`, `Counting/Ops.cpp`, `Families/SubElements.cpp`, `Families/TermSyntax.cpp`, `Columns/ArrayOps.cpp`, `Counting/ReuseAssign.cpp`, `InPlace/Writer.cpp`, `Inline/Inline.cpp`, `Joins/YieldedFields.cpp`, `Lifetimes/Write.cpp`, `Specialize/Order.cpp`, `Tail/TrmcRewrite.cpp`.
  - 1 each, 38 files:
    - headers: `Analysis/Constants.h`, `IR/IdrDialect.h`, `Transforms/Specialize.h`;
    - analyses: `IdentitiesRebuilds.cpp`, `Ownership/Exclusivity.cpp`, `Ranges.cpp`, `Solver/ProgramGraph.cpp`;
    - conversion: `Lower/Rooms.cpp`;
    - IR: `Counting/CellInit.cpp`, `Counting/Types.cpp`, `Families/Refinement.cpp`, `Families/Substitute.cpp`, `Func/Call.cpp`, `Func/Func.cpp`, `Layout/Layouts.cpp`, `OpsArrays.cpp`;
    - transforms: `Bufferize/Values.cpp`, `Counting/Bound.cpp`, `Counting/Reuse.cpp`, `Defunctionalize/Decide.cpp`, `Defunctionalize/Declare.cpp`, `Defunctionalize/Edits.cpp`, `Defunctionalize/Rules.cpp`, `Defunctionalize/Walk.cpp`, `Inline/InlinePass.cpp`, `Joins/JoinRules.cpp`, `Joins/Joins.cpp`, `Joins/Rules.cpp`, `Narrow/Ops.cpp`, `Optimize/Results.cpp`, `Specialize/Lift.cpp`, `Specialize/Raise.cpp`, `Specialize/Specialize.cpp`, `StructureLoops/Forms.cpp`, `StructureLoops/Lowering.cpp`, `Tail/Continuations.cpp`, `Tail/Outline.cpp`, `Tail/TailLoops.cpp`.

  **Unit tests (10)**, single tests that stay: `unittests/Flow.cpp` 7,
  `Rows.cpp` 2, `Calls.cpp` 1.

  **Template-parameter casts outside flight**, not counted in the 333:
  - Stay: `Support/Match.h`, the fold; `Lifetimes.h:364`, `Traits.h:119`, `Numeric/Trait.h:83` and `FlowOps.cpp:233`, CRTP or external-model casts to their own class; `Symbols.cpp:59`, a typed step; `Transforms/Lifetimes/Plan.h:90`, a typed walk; `OpsArrayFusion.cpp:145`; `SubElements.cpp:69`.
  - One to look at: `lib/IR/Dialect.cpp:142-155` (`laws::identityOf`) tests `isa` per class over the generated `laws::Units`. D126 says a templated visitor is not the form; this one reads a generated list, so it keeps no second copy.

  **In the in-flight files, not classified (37):**
  `Defunctionalize/Convert.cpp` 7, `IR/Tail.cpp` 5, `Analysis/LabelSites.cpp` 4,
  `Lifetimes/Ops.cpp` 4, `Conversion/Strings.cpp` 3, `Func/Inliner.cpp` 3,
  `Tail/Trmc.cpp` 3, `Fold/Values.cpp` 2, `Control/MatchFamily.h` 1,
  `Lower/Functions.cpp` 1, `Lower/Statics.cpp` 1, `Fold/Scope.cpp` 1,
  `Lifetimes/Proof.cpp` 1, `EGraph/Nodes.cpp` 1. Of these, `Lower/Functions.cpp:76`
  and `Layout/Components.cpp`'s `wordsOf` (a `match` over the dialect's
  types) are already queued as round 2c's `getRunTimeWords` (59dcc964).

  (measured; every ladder and typed-form site read)

- **(f) Assertions.** Not counted: the owner reversed D112 for the C++
  (2026-10-22).

## Idris (compiler/src, compiler/spec, the checker's own files, libs/, tests' runners)

- **(g) `assert_total`, `assert_smaller`, `believe_me`, `idris_crash`, `unsafePerformIO`.**
  **Done.** The sweep, comments and strings stripped, covered:
  `compiler/src` (97 files), `compiler/spec` (86), `harness/` (34; the
  tests' runner), `libs/` (16) and the checker's 13 files written here (no
  upstream copyright line, e.g. `Idris/Host.idr`, `Idris/Syntax/Tree.idr`,
  `Libraries/Data/Table.idr`). It finds 0 in `compiler/src`,
  `compiler/spec` and `harness`, and these elsewhere:
  - `libs/mlir-array/Array/Core.idr:208, 222, 322, 334`: 4 `unsafePerformIO`. The library is trusted (`Library InHouse`, `compiler/src/IdrisMLIR/Registry/Libraries.idr:101`), the case AGENTS.md allows.
  - `compiler/checker/src/Idris/Host.idr:109` (`believe_me`) and `:3618` (`host = assert_total`): recorded in the L16 queue (audit at db4bcb11, "Kept as run-time facts").
  - Over the whole checker there are 26: the two above and `compiler/checker/src/Core/Primitives/Host.idr` (1 `believe_me`, 23 `assert_total`: string head, tail and index after their range checks, division and modulo after their non-zero checks). L17ac (8e898465) states each once, as a fact of the two hosts' primitives.
  - `tests/` programs: 8 sites in 5 tests, each a deliberate witness or refusal fixture: `escape-hatch-assert-total-in-*`, `world-unsafe-perform`, `no-fuel/{witness,near-miss}`, `rules-covered/{witness,near-miss}`.

  (measured, read)

- **(h) Internal errors (`internal`, `InternalError`, and the typed
  equivalents `unsound`, `missedEntry` and Emit's `Unfit`).**
  **Partial.** 26 sites raise one; every one that is not a run-time fact
  is already recorded. Owner: L16. Most are in flight (L16ee:
  `Translate/*`, `Growth/*`).

  | Site | Recorded by |
  |---|---|
  | `compiler/src/IdrisMLIR/Frontend/Finite.idr:183, 185, 194` (`unsound`, defined `:171-172`) | Queue "From recheck 4", C222 ("the run-time `unsound` goes"); D128 deletes the re-check |
  | `Frontend/Finite.idr:224` | Queue L16cw (`State.Request` holds that its link was absent) |
  | `Frontend/Growth/Graph.idr:2752, 2754` (`Outside`, `Unheaded`; in flight) | Queue L16cw (`Graph.idr:2530, :2533`: proofs) |
  | `Frontend/Translate/Cases.idr:953` (in flight) | Queue audit at db4bcb11, the C222 cluster (`Cases.idr:921, 947`) |
  | `Frontend/Translate/Choices.idr:567` (in flight) | Queue audit (`Choices.idr:533`, "likely C222's") |
  | `Frontend/Translate/Keys.idr:1149` (in flight) | Queue: kept as a run-time fact, a 64-bit hash collision |
  | `Frontend/Translate/Shapes.idr:300` (in flight) | Queue audit (`Shapes.idr:300`, `InstanceSig`'s binders) |
  | `Frontend/Translate/State.idr:1342, 1365` (`missedEntry`, `:1328-1329`; in flight) | Queue audit (`State.idr:1103` at db4bcb11, the same throw) |
  | `Frontend/Translate/Terms.idr:625, 1677, 1773` ("the values an implementation closes over are gone"; in flight) | Queue L16cc and L16cm (held values read twice); C222 cluster |
  | `Terms.idr:735` (a lambda's result), `:745` (a force's operand), `:1577` (an application) | Queue L16dc (C228's last three; `:657` now under D128) |
  | `Frontend/Program.idr:85` and `Emit/Tensors.idr:192` (`Unfit`) | Queue audit and L16dc (the term indexed by its type) |
  | `Frontend/Program.idr:55, 64, 78, 88, 98, 105` | Not recorded. A file that cannot be written is a run-time fact, and stays. |

  The checker's own files have none. The specification's
  `Runtime/Endings.idr:215` and the harness's `Facts.idr:68` declare and
  read the internal ending rather than raise one.
  `Frontend/Driver.idr:230-234, 371, 409` and `Errors.idr:258` map or pass
  one through. Remaining: the queue items as written; nothing beyond them.
  (measured, read)

- **(i) Maps keyed by `String` holding a fact that has a type.**
  **Partial.**
  - `compiler/src/IdrisMLIR/Registry/Libraries.idr:122`: `admittedFromPrimIO : SortedSet String`, which `admits` asks of every reference by its name text (`:135-136`). Beside it, `assertion` compares `q.name` against `"assert_total"` and `"assert_smaller"` (`:142-143`). Recheck 3 named it (`recheck3/idris-and-tests.md`, under L16), but it was routed into neither the L16 queue nor §3. Owner: L16. Remaining: admission becomes a typed hook resolved once at the boundary, as `defHooks` is. The registry's rows name the `PrimIO` definitions admitted and the two assertions, read by resolved name once. The set and both name compares go.
  - `harness/Prims.idr:637-638`: `comparisons : List (String, Integer -> Integer -> Bool)` keys each comparison by its word. That word also spells Idris's primitive's name. Owner: L19, minor. Remaining: keyed by a typed comparison, with the word printed from it.

  The other String-keyed structures are text at a boundary or output text,
  not a typed fact of ours:
  - command-line flags (`Frontend/Driver.idr:129`);
  - LLVM module text (`harness/RuntimeEffects.idr:294-299`), REPL text (`harness/Covers.idr:274, 355`), JSON (`harness/Lock.idr:48`), trace zones (`harness/Trace.idr:88-89`) and printed labels of a program's output (`harness/Fuzz.idr:731`);
  - test names (`harness/Sem.idr:159`, `Main.idr:264`);
  - the generator's printed output (`compiler/spec/IdrisMLIR/Spec/Generator/Cpp.idr:397, 655`, `Idris.idr:455`);
  - MLIR's own name-keyed dictionaries (`compiler/src/IdrisMLIR/MLIR.idr:116`);
  - the checker's identifier interning (`compiler/checker/src/Core/Name/Ident.idr:96`).

  (measured, read)

## Tests

- **(j) RUN lines naming a pass.**
  **Partial.** RUN lines are clean: 60 in `tests/`, and every `--idr-`
  flag on one names a stage-level option, not a pass: `--idr-expect` 23,
  `--idr-pipeline` 7, `--idr-contracts` 5 (`git grep -h -o -E -- '--idr-[a-z0-9-]+' -- tests`).

  Three `run` scripts name the `idr-target` pass, though:
  - `tests/frame-over-guard/run:12`;
  - `tests/pipeline-timing/run:60` (and the comment at `:16`);
  - `tests/upstream-aarch64-sibcall-callee-pop/run:14`.

  Recheck 3 counted `--idr-target` as a stage. It is a pass
  (`compiler/spec/IdrisMLIR/Spec/Pipeline/Pipeline.idr:208`,
  `target : Pass`). The stages are `Higher | First | Graded | Owned |
  Lowered` (`Spec/Pipeline/Stage.idr:25`).

  Tracked tests name other passes only in comments
  (`tests/expect-narrowed-lanes/expect-narrowed-lanes.mlir:3,6`; the
  runtime tests' "as idr-lower lays it out"). L14x's new
  `tests/simplify-computes-constants/simplify-computes-constants.mlir:1`,
  untracked when first read and naming `idr-simplify`, landed in 04c2393d
  stated by stage (`idr-pipeline{from=first to=first}`), with no pass
  named.

  Owner: L19. Remaining: the three scripts reach the target through the
  driver or `--idr-pipeline` instead of the pass's flag. (measured, read)

- **(k) Printed IR compared against op sequences or SSA names.**
  **Done.** Every FileCheck line in the tests, by prefix:
  - 16 `CHECK:` and 1 `CHECK-NEXT:` (`rg '(CHECK|GONE|NOT|ERR|OUT|NOTE)[-A-Z]*:' tests -g '*.mlir' -g '*.ll'`);
  - 0 with an SSA `%` name.

  The one `CHECK-NEXT` (`tests/dialect-text/near-miss/tests/diagnostics/diagnostics.mlir:6`)
  is a fixture of the dialect-text checker. So are all but one of the
  `CHECK:` lines; the exception is `tests/syntax-nested-constant`. No
  `expected` file pins SSA names. `tests/handoff-readable/expected:4-5`
  names ops as a property ("no func.func"), not a sequence. (measured)

## One source

- **(l) A `.td` of ours not produced by specgen.**
  **Done.** Our tracked `.td` files, compared against
  `foreign/idr/generated.manifest`:
  - the 18 under `include/idr/IR/Generated/` are each listed in the manifest;
  - the other 8 are checker fixtures (`tests/zones`, `file-size`, `no-behaviour-options` and `registry-only`, `witness/` or `near-miss/`) and one upstream reproducer (`upstream/76-pass-base-derived-class/crtp-pass.td`);
  - none is untracked.

  The fingerprints were not recomputed (nothing was generated), and D126
  2b-S is regenerating `Generated/` now. (measured)

- **(m) Hand copies of a generated table.**
  **Partial.**
  - `lib/Conversion/Matches.cpp:357, 367, 377, 380` name the join family's members `JoinOp, LoopOp` by hand: the patterns, the legality, the lowering's patterns and the illegal list. Specgen writes the list (`GET_JOIN_POINTS_FAMILY_LIST`, `include/idr/IR/Generated/JoinPointsFamily.h.inc:6-10`), and nothing includes it (`rg GET_JOIN_POINTS_FAMILY_LIST` finds only the file itself). Owner: L09. Remaining: the four lists expand the generated list, e.g. through a `JoinPointsOps` type list built from it, and the hand names go.
  - `include/idr/IR/Grades.h:115-118`: `countedCases` and `scopedCases` restate by hand the inverse of the generated `holdRelease` and `holdClaim` (`Generated/Grades.h.inc:159, 170`). Their order must match `Unique`'s by convention. Owner: L05. Remaining: a `consteval` inversion of the two generated arrays, or a generated inverse; the hand arrays go.
  - Idris: no literal op-name list in `compiler/src` outside the generated `IdrisMLIR/Dialect/Idr.idr`, which `generated.manifest:62` lists (an op-mnemonic search over `compiler/src`, `harness` and `libs`).
  - Related, though not literal op names: the frontend's `Prim` keeps 15 hand constructors beside `Op : Spec.Op` (`compiler/src/IdrisMLIR/Types.idr:426-449`), recheck 3's finding, still standing (L16).

  (measured, read)

## Counts

| Verdict | Rows |
|---|---|
| Done | 6: (a), (b), (c), (g), (k), (l) |
| Partial | 6: (d), (e), (h), (i), (j), (m) |
| Missing, Regressed, Superseded, Open-owner | 0 |
| Not counted | 1: (f) |

## Seen outside the range

- `compiler/src/IdrisMLIR/Registry/Libraries.idr:59`: `trusted, admitted, reportAtCaller : Bool`, three flags where a sum would carry the state.
- `include/idr/Target/Target.h:94, 102`: the schedule library's entry names, `"idr.vectorization"` and its cleanup, are C++ literals beside the library that defines those symbols. Whether this is a second copy was not checked.
- `include/idr/Support/Match.h`'s header now states D126 (cb5cd6fb), but its `match(mlir::Type, …)` fold over `DialectTypes` (`:297`) still exists. Its one user is the in-flight `Layout/Components.cpp:101-125`.
- Recheck 3's done list, item 13, read `--idr-target` as a stage; see (j).
