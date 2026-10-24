<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Recheck 6: AGENTS.md's measurable rules, swept over the tree

HEAD at start `9f4889dd`, at finish `258be23d`. Nine commits landed
while this was read. Each was swept again on the files it touched:
- `e72a024f` (L12v: `Bufferize/Linear.cpp`);
- `13b0e15e` and `e518e35c` (the design record and the queue);
- `29153f20` (L16em: Emit, `Translate/Choices`, `Programs`, `State`, `Term.idr`);
- `2d7ee52d` (L11z: `Driver/Run.cpp`, `Pipeline.cpp`, `Pipeline.h`, the harness and five tests);
- `d093dbfb` (L17bc: the checker);
- `f7271225` (L03aa: the specification, `OpsBigs.cpp`, `Bufferize/Generating.cpp`, `Narrow/Facts.cpp`);
- `b2a2c4ae` (the queue);
- `258be23d` (L06j: patch 27, `PINS.md`, `tests/upstream-one-shot-tensor-like-copy`, whose new RUN names the stage `idr-pipeline{from=first to=first}`, no pass).

One verdict changed: (j) went from Partial to Done with `2d7ee52d`. The
rescan of the other rows found the same counts.

The working tree holds uncommitted edits by the lanes in flight. Among
them are `Specialize/Open.cpp`, `Requests.cpp`, `Optimize/*` (L18x), Emit
and `Translate/*` (L16), and the checker. Every line number below is
HEAD's text, read from a `git archive` of HEAD outside the checkout.
Nothing was built, typechecked, generated or run.

Grounds: *read* means the cited line was opened. *Measured* means a count
made with the command or scan given. The scans were written for this
sweep and kept outside the tree (`/tmp/r6sweep`):
- a C++ comment and string stripper;
- a cast scan that reads each template argument against the classes the generated `.td` define;
- a scan of `bool` parameters;
- an Idris comment and string stripper.

Recheck 5's scan was not kept, so this one was calibrated on recheck 5's
tree (`04c2393d`). It gives 1,044 cast sites (376 over our classes, 96
over our interfaces, 572 upstream) where recheck 5 reported 1,036 (370,
96, 570): the counts agree to within six. Paths are under `foreign/idr/`
unless they start with another top-level directory. Owners are the
longest prefix in `ownership.json`.

## C++ (foreign/idr, runtime/, tools; Generated/ and upstream excluded)

- **(a) Greedy driver, canonicalize, canonicalization patterns.**
  **Done** (recheck 5: Done). The counts:
  - `applyPatternsGreedily|applyPatternsAndFoldGreedily|applyOpPatternsGreedily|GreedyRewriteConfig`: 0 (0).
  - `createCanonicalizerPass|canonicalize` over `foreign/idr`, `runtime` and `compiler/spec`: 0 (0).
  - `getCanonicalizationPatterns|hasCanonicalizer`: 0 (0).

  The seven `walkAndApplyPatterns` calls are upstream's one-pass walk
  driver: `lib/Conversion/Lower.cpp:219`, `Lower/Accounts.cpp:103`,
  `Narrow/Copy.cpp:129-130`, `Narrow/Narrow.cpp:219` and
  `StructureLoops/StructureLoops.cpp:103,127`.

  In `tests/`, `canonicalize` appears only in four kinds of place:
  - the upstream reproducers' runs over upstream dialects (`upstream-composite-fixed-point-sccp`, `upstream-early-exit-*`);
  - a dialect-text fixture (`dialect-text/witness/tests/pipe-opt`);
  - the `no-fuel` fixtures;
  - bench records.

  (measured)

- **(b) `std::function`, and recursion through a type-erased callback.**
  **Done** (Done). `std::function`, `move_only_function` and
  `copyable_function`: 0 (0). `function_ref`: 30 lines (30):
  - 20 are upstream's diagnostic hook;
  - 3 are comments (`Support/Actions.h:59`, `Families/SubElements.cpp:127,129`);
  - 7 are signatures MLIR fixes:
    - `ConstantAttrInterface::verifyParts` (`lib/IR/Constants.cpp:84, 176, 202`, declared at `Generated/IdrInterfaces.td:270`);
    - `IndexPositionsTypeInterface::atFreshPositions` (`Defunctionalize/Indices.cpp:123, 142`);
    - upstream's sub-element walk (`Families/SubElements.cpp:130-131`).

  None recurses:
  - `verifyParts`' one caller is a worklist (`Constants.cpp:291-307`);
  - `atFreshPositions`' `next` is a counter (`Indices.cpp:53-55`).

  (measured, read)

- **(c) Maps keyed by `Operation *`, `Value`, `Block *`, `Region *`.**
  **Done** (Done). 122 map and set declarations (120). 18 lines are keyed
  by an MLIR handle; recheck 5 listed 16 of them and called it 15. The two
  new lines are `lib/Transforms/Lifetimes/Lend.cpp:88` and `:224`: one
  loan walk's set of aliases, and the parameter that reads it. The set is
  the walk's own, sized by the loan, and gone when the walk ends; that is
  the visited-set case `Loans.h:73` already is.

  The rest are as recheck 5 classed them:
  - numberings: `Solver/Extraction.h:145`, `LabelPoints.h:94, 145`, `Bufferize/Releases.cpp:117`, `EGraph/Simplify.cpp:147`, `Narrow/Widths.cpp:104`, `StructureLoops/Linalg.cpp:44`;
  - visited sets: `IR/Lifetimes/Loans.h:73`, and `Narrow/Versions.cpp:50`, whose `Goal` is a pair of values;
  - ordered input lists: `Narrow.h:322, 368`, `Narrow/Copy.cpp:31`, `Lanes.cpp:178`, `Widths.cpp:59-60`, `Specialize/Consumer.cpp:149`.

  No map is keyed by a `Block *` or a `Region *`. The LLVM-handle maps
  (`Driver/Prepare.cpp:77`, `Driver/StackBound.cpp:146`,
  `Target/Partition.cpp:59, 141, 244`) are unchanged. The
  `const void *` keys (`SpecializeState.h:249`, `Specialize.h:363`,
  `ContentNames.cpp:43`) key interned patterns and uniqued storage, not IR
  nodes. (measured, read)

- **(d) Parameters that are a choice typed `bool`.**
  **Partial** (Partial). The scan reads every parameter and template
  parameter declared `bool` in the 608 files, comments and strings
  stripped. It finds 12. Unlike recheck 5's scan, it includes `bool &`
  out-parameters and leaves out locals.

  Recheck 5's two runtime choices are gone (d76f1b33):
  - `setEnvironment` takes `enum class WhenSet { Keep, Replace }` (`runtime/Platform/Platform.h:268-270`), converted once from the ABI's integer (`runtime/Io/Process.cpp:56-57`);
  - End's `number(…, bool negative)` no longer exists.

  Two choices remain, one of them new:
  - `lib/IR/ValueFacts.cpp:54`: `template <typename T, bool counted> struct ArrayFacts`, attached at `:153-156`, `true` for the memrefs and `false` for the tensors. It was in flight at recheck 5 and is held by no lane now.
  - `lib/Transforms/EGraph/Values.cpp:393`: `template <bool Signed> struct FromInteger`, used at `:407` and `:409` for `arith.sitofp` and `uitofp`. It is new, from L14y (07e4e844).

  The rest are not choices:
  - truth values handed to a check: `Testing/Box.h:69`, `unittests/Hooks.cpp:42`, `HooksCompare.cpp:51`, `Refusals.cpp:330`;
  - upstream signatures: `ContentNames.cpp:132`, `Bufferize/Bufferize.cpp:312`, `runtime/Alloc/Cells.cpp:162`;
  - a predicate over a `SmallVector<bool>`: `Families/Substitute.cpp:637`;
  - two out-parameters, which recheck 5's scan did not count:
    - `runtime/Numerals/Reading.cpp:27`, `bool &grouped`: a fact of the text being read, known only at run time;
    - `tools/idris-mlir-tblgen.cpp:1952`, `bool &found`: an `std::optional` written as a flag; see (o).

  (measured, read)

- **(e) D126: ladders over our classes, and the typed signature and walk.**
  **Partial** (Partial). Recheck 5's 14 ladders and 5 typed-form sites
  are gone, but two new ladders and one new bare-handle pattern landed.

  The cast scan (nine cast forms and `.Case`) finds 1,048 sites outside
  `Generated/` (1,036), against 203 ops, 13 types, 32 attributes and 37
  interfaces:
  - 358 over our concrete classes (370);
  - 103 over our interfaces (96);
  - 587 over upstream classes or template parameters (570).

  `TypeSwitch` is used nowhere. The plain grep
  `git grep -h -o -E '(isa|dyn_cast)<' -- foreign/idr ':!foreign/idr/include/idr/IR/Generated' | wc -l`
  gives 610 (606).

  **Recheck 5's ladders.** All 14 are gone:
  - Unit R3-A by aaa578c6. `getCarrying` answers `Carriers::of` (`lib/IR/FlowEdges.cpp:31-45`), `isClosureType` and `isLazyType` (`lib/IR/Grades.cpp:270-290`), `verifyParts` and Declare's carrier (`Defunctionalize/Declare.cpp:286-294`); `Carrier : bool` is gone.
  - Unit R3-B by 839adb08:
    - `Layout/Classes.cpp:264-266` asks `getPositionalMember`;
    - `Ops/Constraints.cpp` asks `isCarriedAsBig`;
    - `ResetsUnshared` asks `isCellMemory`;
    - `Narrow.cpp:145` asks `BigWordOpInterface`;
    - `Conversion/Matches.cpp:322` asks `RegionBranchTerminatorOpInterface`.

  Recheck 5's five typed-form sites are done:
  - `Counting/Borrows.cpp`'s `findLoans` is two typed walks;
  - `Expect.h`'s `id` takes `FuncOp`;
  - `sortsOfMember` takes `FamilyAttr`;
  - `lifetimes::kindOf` takes `TypedValue<LifetimeType>` (`lib/IR/Lifetimes/Kind.cpp:104`);
  - `Lower/Lifetimes.cpp`'s local `kindOf` is gone.

  The two casts round 3-B left are queued as written (`Expect.h:302`'s
  `idsOf`, `FamilyVerify.cpp:57`'s `groupOf`). The queue's units A, B, D,
  E, F and G are done (read at their sites):
  - `Lifetimes/Ops.cpp`'s `extentOf` and `packedOf` ask interfaces;
  - `LabelSites` and `Convert` fold `closureHoldingOf`;
  - `Lower/Statics.cpp` has no `"site"` read;
  - `MatchFamily.h:122` hashes its keys;
  - `Strings.cpp` reads `ListElement`;
  - `Rule.h`'s `Demand` holds counts.

  `Support/Match.h`'s header now states D126, and its fold over our types
  is gone.

  **Ladders now (4 sites).**
  - `lib/IR/Families/Repacks.cpp:166, 169` (`namedBy`): `SelfType`, else `DataType`.
    - It landed in c497d41d (L04w), after round 3-B removed the same split from `Layout/Classes.cpp`.
    - It computes the same group, member, terms and mark that `Classes.cpp:264-272` computes: a second copy of one question.
    - Outside flight. Item L04-1.
  - `lib/Transforms/Specialize/Open.cpp:377, 403`: the use walk that lowers grades singles out `CallOp`, then `DataReindexOp`, between interface and trait arms (`forwardedValues`, `ResultCarriesOperand`, `InferTypeOpInterface`).
    - The reindex arm applies the reindex's own rule (`reindexed`).
    - In flight (L18x). Item L18-1; a candidate whose form is L18's to choose.

  **D126's typed form: `tail::Tail` hands calls as bare handles (8 sites).**
  `Tail::source` is an `Operation *` (`include/idr/IR/Tail.h:62-65`), as
  are `sourcesOf` and `tailSource`. Eight readers cast it to `CallOp`:
  - `lib/IR/Tail.cpp:340`;
  - `Tail/Accumulate.cpp:233, 306`;
  - `Expect/Tails.cpp:75`;
  - `Specialize/Requests.cpp:189`;
  - `Specialize/Open.cpp:579, 681`;
  - `include/idr/Transforms/Optimize/Tails.h:41`.

  The fact "a call lost to a layout" (`repack && isa<CallOp>`) is derived
  three times: `Tail.cpp:340-343`, `Expect/Tails.cpp:73-76` and
  `Requests.cpp:188-190`. Three passes write tail kinds from the one
  reading, in two spellings:
  - `Open.cpp:578-580` gives a re-packed call `nontail`;
  - `Accumulate.cpp:305-307` and `Optimize/Tails.h:35-42` give it `withContext`.

  The two spellings agree only because a call that reaches a tail through
  a re-pack has no context (read; not run). Item L10-1.

  **Single tests that ask a question round 3-A declared (1).**
  `lib/Analysis/LabelSites.cpp:279`, `dyn_cast<LazyType>(next.carrier)`,
  asks whether a closure's carrier is a suspension. `getCarrying` answers
  that, and its `carrying::Suspension` holds the `TypeOf<LazyType>` the
  arm reads (`include/idr/IR/Interfaces/Vocabulary.h:140-143`). Item L14-1.

  **Op-naming template branches (from recheck 6's D-report, queued in b2a2c4ae).**
  A scan for `std::is_same_v`/`std::same_as` over our classes finds three:
  - `include/idr/IR/IdrDialect.h:173-187` (`ProgramOp`, else `ModuleOp`);
  - `Columns/ArrayOps.cpp:45`;
  - `StructureLoops/Linalg.cpp:151`.

  The queue's fourth (`Narrow/Ops.cpp:125-133`) names upstream ops. They
  are recorded there and not repeated as items here.

  **The other sites, outside flight (304: 196 tests and 108 casts).**
  189 are single typed tests that stay: one class within an open set (a
  user, a defining op, a terminator, a value's type, a folded constant),
  or a walk that handles every op and singles out one class. Among them:
  - `Expect/MayDiverge.cpp:30` and `Expect/Tails.cpp:73` ask whether a function op is ours, since a lowered one is upstream's;
  - `Narrow/Facts.cpp:81` tests `BigSmallOp` on a carrier chain;
  - `Repacks.cpp:274, 275, 291` are one `DataType` test per value, beside a memref test.

  Two are not ladders though the chain detector paired them:
  - `Conversion/Strings.cpp:81, 83`: a user that only drops the string is skipped, and the one output is sought. These are two roles, not alternatives;
  - `Counting/Placement.cpp:252, 282`: two different questions, 30 lines apart.

  Of the 108 casts:
  - 107 are decided above the cast: an ODS constraint, a parent trait, an external model's own op (`Bufferize/Reindex.cpp:142-166`, new), or a clone;
  - one is the queued `groupOf`.

  **In flight (44)**, in `Specialize/`, `Optimize/`, `Bufferize/` and
  `OpsArrays.cpp`. Read where new:
  - `Open.cpp`: the ladder above, two tail readers, two single tests;
  - `Requests.cpp:189` and `Optimize/Tails.h:41`: tail readers;
  - `Bufferize/Reindex.cpp`: 5 external-model casts.

  The rest are recheck 5's, unchanged in count.

  **Unit tests (10)** are unchanged.

  `lib/IR/Dialect.cpp:143-156` (`laws::identityOf`) still tests `isa` per
  class over the generated `laws::Units`; it stays as recheck 5's "one to
  look at". (measured; every new site and every ladder read)

- **(f) Assertions.** Not counted: the owner reversed D112 for the C++
  (2026-10-22).

## Idris (compiler/src, compiler/spec, the checker's own files, libs/, the harness)

- **(g) `assert_total`, `assert_smaller`, `believe_me`, `idris_crash`, `unsafePerformIO`.**
  **Done** (Done). The scan, comments and strings stripped, covered
  `compiler/src` (97 files), `compiler/spec` (86), `harness/` (34) and
  `libs/` (16): 0 in the first three, 4 in `libs/`. The 4 are
  `libs/mlir-array/Array/Core.idr:208, 222, 322, 334`, a trusted library
  (`Library InHouse`, `Registry/Libraries.idr:98`).

  The checker:
  - Its own files (16, up from 13) hold `Idris/Host.idr:109` (`believe_me`, `trusted`) and `:3618` (`host = assert_total`), as recorded.
  - Over the whole checker there are 26: those two and `Core/Primitives/Host.idr`'s 24 (L17ac's statement of the hosts' primitives).

  `tests/` holds 8 sites in 8 files, each a witness or refusal fixture.
  `d093dbfb` changed none of these. (measured)

- **(h) Internal errors (`internal`, `InternalError`, `unsound`,
  `missedEntry`, Emit's `unfit`).**
  **Partial** (Partial). 25 raises (26); every one that is not a run-time
  fact is in the queue. Owner L16.

  | Site | Recheck 5's line | Waits on |
  |---|---|---|
  | `compiler/src/IdrisMLIR/Frontend/Finite.idr:183, 185, 194` (`unsound`, `:171-172`), `:224` | same | the threading pass after C281 (D128.3, C222) |
  | `Frontend/Growth/Graph.idr:2782, 2784` | 2752, 2754 | the same |
  | `Translate/Cases.idr:954`, `Choices.idr:567`, `Shapes.idr:300` | 953, 567, 300 | the same (D112.1, C234) |
  | `Translate/Keys.idr:1149` | same | kept: a 64-bit hash collision, a run-time fact |
  | `Translate/State.idr:1421, 1444` (`missedEntry`, `:1407-1408`) | 1342, 1365 | the same |
  | `Translate/Terms.idr:696, 1736, 1833` ("the values an implementation closes over are gone") | 625, 1677, 1773 | the same (`classifyKeys` returns what it read) |
  | `Terms.idr:802` (a force's operand), `:1636` (an application) | 745, 1577 | the same; the lambda's result (735) is gone |
  | `Emit/Tensors.idr:207` (`unfit`), mapped at `Frontend/Program.idr:85` | 192, 85 | L16en (Emit) |
  | `Frontend/Program.idr:55, 64, 78, 88, 98, 105` | same | kept: a file that cannot be written |

  The specification's `Runtime/Endings.idr:215, 311` and the harness's
  `Facts.idr:68` declare or read the internal ending.
  `Frontend/Driver.idr:230-234, 371, 409` and `Translate/Errors.idr:219-220, 258`
  define or pass one through.

  The checker as a whole (all of it ours since D118) has 75 lines naming
  `InternalError` (76 at start; `d093dbfb` removed `CaseBuilder.idr:663`).
  By L17bb's own count, 56 raises remained after it (1c8e1d7d). They are
  outside recheck 5's range and not classified here. (measured, read)

- **(i) Maps keyed by `String` holding a fact that has a type.**
  **Partial** (Partial).
  - The registry's `admittedFromPrimIO : SortedSet String` and its `"assert_total"`/`"assert_smaller"` compares are gone (L16eg, 57148ff2).
  - `Registry.idr:47`'s `spellings : SortedMap String (Hooks QName)` is keyed by source text, which is what the source gives (a boundary); a definition's hooks are found by its resolved entry.
  - Remaining: `harness/Prims.idr:637-639`, `comparisons : List (String, Integer -> Integer -> Bool)`, keyed by the word that also spells Idris's primitive. Owner L19, minor; unchanged.

  The other `String`-keyed structures are as recheck 5 listed them:
  flags, LLVM and REPL text, JSON, trace zones, labels, test names, the
  generator's output, MLIR's dictionaries and the checker's interning.
  Two more are text output:
  - the symbols written beside their statements (`Emit/Declarations.idr:80`, `Emit/Monad.idr:39`);
  - phase names for `--timing` (`Frontend/Program.idr:116`).

  (measured, read)

## Tests

- **(j) Tests naming a pass.**
  **Done at finish** (Partial; Partial at this sweep's start).
  `2d7ee52d` took `--idr-target` out of the three run scripts recheck 5
  named (`tests/frame-over-guard/run`, `pipeline-timing/run`,
  `upstream-aarch64-sibcall-callee-pop/run`). `idr-target` now runs first
  in every slice the driver and `--idr-pipeline` build.

  RUN lines: 116 in `tests/` (61 at recheck 5's tree), 89 outside
  fixtures. Every pass they name is a stage, a property checker, or the
  contracts' mutant:
  - `--idr-` flags: `--idr-expect` 27 (23), `--idr-pipeline` 7 (7), `--idr-contracts` 6 (5);
  - inside `--pass-pipeline`: `idr-pipeline` 46, `idr-expect` 44, `idr-contracts` 4, `test-idr-break-contract` 4 (`Contracts.cpp:360`).

  A grep of the 38 other pass mnemonics in `Generated/IdrPasses.td` and `IdrInnerPasses.td` over
  `tests/`, `harness/` and `tools/bisect.sh` finds them only in comments
  (`expect-narrowed-lanes.mlir:3,6`, the runtime tests' "as idr-lower lays
  it out", `harness/prop/bigmodel.h:56`). It also finds one checker
  fixture, `no-behaviour-options/witness`. (measured)

- **(k) Printed IR compared against op sequences or SSA names.**
  **Done** (Done). FileCheck lines in `tests/` `.mlir`/`.ll`:
  - 19 `CHECK:` (16) and 1 `CHECK-NEXT:` (1); 0 with an SSA `%` name;
  - all fixtures of the dialect-text, expect-coverage and verifier-every-pass checkers, except `tests/syntax-nested-constant`.

  No `expected` file holds an SSA binding. (measured)

## One source

- **(l) A `.td` of ours not produced by specgen.**
  **Done** (Done). The 18 under `include/idr/IR/Generated/` are each in
  `generated.manifest`. The rest of ours are 7 checker fixtures and one
  upstream reproducer (`upstream/76-pass-base-derived-class/crtp-pass.td`).
  None is untracked. The 99 `.td` under `sources/` are upstream's
  snapshots (C13). Fingerprints were not recomputed. (measured)

- **(m) Hand copies of a generated or declared table.**
  **Partial** (Partial). Done:
  - Recheck 5's two C++ copies are gone (839adb08). `Conversion/Matches.cpp:478, 495` expand `GET_JOIN_POINTS_FAMILY_LIST`. `Grades.h:79` computes `holdsFreedBy` from the specification's `holdRelease`/`holdClaim` when the compiler is built.
  - Idris: no op mnemonic is spelled outside the generated `Dialect/` modules (a search of the 202 mnemonics over `compiler/src`, `harness`, `libs`).

  Remaining:
  - The frontend's `Prim` keeps 16 hand constructors beside `Op : Spec.Op` (`compiler/src/IdrisMLIR/Types.idr:490-516`; recheck 5 counted 15 of the same set). This is recheck 3's finding (L16).
  - `Termination` is held three times:
    - the specification's `Unproved | InComponent Nat` (`Spec/Functions/Termination.idr:29`);
    - `include/idr/IR/Func.h:58-77` by hand;
    - the frontend's `Terminates ComponentId | MayDiverge` (`compiler/src/IdrisMLIR/Term.idr:1676`).

    The first two are queued (L02, L03), and the third since e518e35c (L16 with L03).
  - New: `Bufferize/Linear.cpp:115-116` attaches `GradeModel` to `LinCastOp` and `CountShareOp` by name. The concept at `:65` checks that a named op carries `ResultCarriesOperand`, not that every op carrying it is named. Today the two are exactly the trait's members (`Generated/IdrOps.td`, read). Commit e72a024f's claim that such an op "cannot lack a model" holds only while the list and the trait agree. Item L12-1.

  (measured, read)

## Rules recheck 5 did not sweep as rows

- **(n) Facts kept in discardable attributes.**
  **Done** (new row). C++ writes discardable attributes in four places:
  - `Conversion/Matches.cpp:352-353, 466` puts upstream's `llvm.loop_annotation` on the branches a progressing loop becomes, made once (`:503-511`) from the row's verdict, which lives in the effect row;
  - `Target/Target.cpp:117, 134` writes the module's target facts, the one place the target is decided;
  - `Optimize/Results.cpp:285` and `Tail/AccumulatorPlan.cpp:125` carry another op's discardable dictionary across a rebuild.

  The generated Idris builders pass `[]` for every op's discardable
  attributes (`compiler/src/IdrisMLIR/Dialect/*`), and no `idr.*`
  attribute name is spelled in our C++. (measured, read)

- **(o) String compares and hash lookups of static facts.**
  **Partial** (new row). Over our C++, comments stripped, 35 lines compare
  text or name an operation (`getOperationName`). The `getOperationName`
  uses build an `OperationState` or a nested pass manager. The compares
  are boundary text:
  - a file's extension (`Driver/Artifacts.cpp:73`);
  - the cgroup files (`runtime/Platform/Posix/Cgroups.cpp`);
  - a string's bytes (`runtime/Strings/Order.cpp:17`).

  `Driver/StackBound` keys frame sizes by LLVM symbol name, which is
  LLVM's identity across the modules it joins (read). The Idris side has
  one compare, a command-line flag's dash (`Frontend/Driver.idr:172`).
  Remaining, in our TableGen backend:
  - `tools/idris-mlir-tblgen.cpp:1014` decides whether a parameter is a list by reading its printed Idris type back (`starts_with("List ")`). The makers at `:977, :1005, :1714` knew it when they wrote `"List " + …` into `Kind` (`:222`).
  - `elemsOf` (`:1951-1959`) reports "found" through `bool &found` where an `std::optional` carries it.

  Its selection of a dialect's records by `-idris-dialect` (`:1955`) is
  a command-line name, a boundary. Item L03-1. (measured, read)

- **(p) Per-target cases outside the target's entry.**
  **Done** (new row). In C++, the grep of `__x86_64__`, `__aarch64__`,
  `__APPLE__`, `__linux__`, the `Triple` predicates, page sizes and
  `cpuid` finds three kinds of site:
  - the runtime's platform layer (`runtime/Platform/Aarch64/Cpu.cpp:17, 26`, `Platform/Posix/Files.cpp:74`, `Platform/CpuBits.h`, `X86_64/Cpu.cpp`);
  - the runtime's ABI `static_assert`s;
  - the module's own triple, read by `OpsPlatform.cpp:30-35` to fold `platform.os` and by `Driver/ReadRuntime.cpp:112-113` to compare a runtime member's triple.

  The Idris side holds no per-target case. Tests that name a target check
  that target's own fact:
  - the AArch64 feature list;
  - the upstream reproducers for one target;
  - `static-linking`'s per-libc names;
  - `memory-limit/expected.linux`, the host having a limit command.

  (measured, read)

## Counts

| Row | Recheck 5 | Recheck 6 (finish) |
|---|---|---|
| (a) greedy, canonicalize | Done (0, 0, 0) | Done (0, 0, 0) |
| (b) type-erased callbacks | Done (30 `function_ref`) | Done (30) |
| (c) IR-handle maps | Done (15 lines as stated) | Done (18 lines; 2 new, one loan walk's set) |
| (d) `bool` choices | Partial (3 choices) | Partial (2: one carried, one new) |
| (e) D126 | Partial (14 ladders, 5 typed-form sites) | Partial (4 ladders, 2 new outside flight; 8 bare-handle tail readers; 1 declared question asked by cast) |
| (f) assertions | Not counted | Not counted |
| (g) Idris escape hatches | Done | Done (same counts) |
| (h) internal errors | Partial (26) | Partial (25, all queued or run-time) |
| (i) String-keyed facts | Partial (2) | Partial (1) |
| (j) tests naming passes | Partial (3 scripts) | Done (Partial at start) |
| (k) printed IR in tests | Done | Done |
| (l) hand-written `.td` | Done | Done |
| (m) hand copies of tables | Partial (2 C++, 1 Idris) | Partial (Prim; Termination, queued; Linear.cpp's list, new) |
| (n) discardable facts | not a row | Done |
| (o) string compares of static facts | not a row | Partial (the TableGen backend) |
| (p) per-target cases | not a row | Done |

On recheck 5's twelve counted rows: 7 done and 5 partial (6 and 6). With
the three new rows: 9 done, 6 partial. No row regressed, but two
recurrences sit inside partial rows:
- a `SelfType`/`DataType` ladder (Repacks.cpp, c497d41d) of the shape round 3-B had just removed;
- a `bool` template choice (EGraph/Values.cpp, 07e4e844).

## Dispatchable items, by owner

Each names the change, its files and lines, what it waits on, and its
ground.

**L04**
- **L04-1.** One function for the application a declared field type names: the group, member, terms and mark of a positional member or of a data type.
  - The change:
    - It asks `IndexedTypeInterface::getPositionalMember` and `getIndexTermRuns` for a positional member, and tests `DataType` for a data type.
    - `Families/Repacks.cpp:165-174` (`namedBy`) and `Layout/Classes.cpp:264-272` both ask it; Repacks' `SelfType` test goes.
    - The tag set Repacks adds stays Repacks'.
  - Files: `lib/IR/Families/Repacks.cpp`, `lib/IR/Layout/Classes.cpp`, a header under `include/idr/IR/Families/`.
  - Waits on: nothing running holds these files (L16en holds only the specification's `Families/Ops.idr`). It may ride with L04's queued `builds` member, which waits on L16en.
  - Ground: read.

**L10 (with L18 and L19 for readers)**
- **L10-1.** `tail::Tail` hands its call typed.
  - The change:
    - The tail reading gives each tail that is a call as `CallOp` with its re-pack. That is a typed list from `tailsOf(FuncOp)`/`tailsOf(Block &)`, beside the sources that are not calls; `sourcesOf` and `tailSource` likewise.
    - "A call lost to a layout" becomes one function in `Tail.h`.
    - Re-deciding a function's or a block's tail kinds from the reading becomes one function that `Open.cpp:578-580`, `Accumulate.cpp:305-307` and `Optimize/Tails.h:35-42` call, in one spelling.
    - The eight casts go: `IR/Tail.cpp:340`, `Tail/Accumulate.cpp:233, 306`, `Expect/Tails.cpp:73-76`, `Specialize/Requests.cpp:188-190`, `Open.cpp:579, 681`, `Optimize/Tails.h:41`.
  - Files: `include/idr/IR/Tail.h`, `lib/IR/Tail.cpp`, `lib/Transforms/Tail/Accumulate.cpp` (L10); `Specialize/`, `Optimize/Tails.h` (L18); `Expect/Tails.cpp` (L19).
  - Waits on: L18x, which holds `Specialize/` and `Optimize/` and is editing `Open.cpp` and `Requests.cpp` in the working tree.
  - Ground: read. That the two spellings agree today is by reading, not run.

**L18**
- **L18-1.** `Specialize/Open.cpp:377, 403`: the grade-lowering use walk's `CallOp` and `DataReindexOp` arms.
  - The change: the reindex's rule (`reindexed`) answered by the reindex op itself, beside the `builds` member L04's queued item adds, so the walk keeps its interface and trait arms and one stop at a call. Which form fits is L18's to choose.
  - Waits on: L18x (the file is edited in the working tree).
  - Ground: read.

**L14**
- **L14-1.** `Analysis/LabelSites.cpp:279`: match `carryingOf(next.carrier)` and read the suspension's `TypeOf<LazyType>` for `FlowAnchor::forcedOf`; the `dyn_cast<LazyType>` goes.
  - Waits on: nothing running.
  - Ground: read. `next.carrier` is unrestricted where it is made (`:169`, `:286`), so today's cast misses no graded carrier.
- **L14-2.** `Transforms/EGraph/Values.cpp:393-409`: `FromInteger`'s `bool Signed` becomes a signedness enum, or the op itself as the parameter, converted to APFloat's `bool` once at `convertFromAPInt` (`:401`).
  - Waits on: nothing running.
  - Ground: read.

**L13**
- **L13-1.** `lib/IR/ValueFacts.cpp:54-65`: `ArrayFacts` loses its `bool counted`, and `isCounted` answers from upstream's class hierarchy (`std::derived_from<T, BaseMemRefType>`). The attachments at `:153-156` lose their second argument.
  - Waits on: nothing running.
  - Ground: read.

**L03**
- **L03-1.** `tools/idris-mlir-tblgen.cpp`:
  - `Kind` (`:222`) holds whether it is a list as an enum, set by its makers (`:977, :1005, :1714`), and `fieldWith` (`:1014`) reads that, not the text;
  - `elemsOf` (`:1951-1959`) returns `std::optional<std::vector<const llvm::Record *>>` and its caller (`:1966-1970`) tests that.
  - Waits on: nothing (L03aa landed in f7271225).
  - Ground: read.
- **L03-2 (with L12).** The specification generates the list of ops carrying `ResultCarriesOperand`, which `Bufferize/Linear.cpp:115-116` expands in place of the two names.
  - Waits on: L12v (Bufferize) for the C++ half.
  - Ground: read.

**L19**
- **L19-1.** `harness/Prims.idr:637-639`: the comparisons keyed by a typed comparison, its word printed from it (carried from recheck 5).
  - Waits on: nothing.
  - Ground: read.
- `Expect/Tails.cpp:73-76` under L10-1. `Expect.h:302`'s `idsOf` cast is already queued.

**L16**
- No new item. The 25 internal errors are queued as the table in (h) says. They wait on:
  - the threading pass, which C281 (e518e35c) put to the owner's review;
  - L16en, for `Emit/Tensors.idr:207`.

  `Prim`'s 16 constructors and `Term.Termination` are queued.

**L02**
- No new item. `Func.h:58-77`'s hand `Termination` is queued with L03.

## Seen outside the range

- `compiler/src/IdrisMLIR/Registry/Libraries.idr:55-73`: `Row` keeps three `Bool` columns (`trusted, admitted, reportAtCaller`) read through `column : Purpose -> Row -> Bool`. Carried from recheck 5; a table of flags where the purposes could index the facts.
- `Transforms/Columns/Tensors.cpp:283-289`: a hand list of six ops (`tensor.empty`, `tensor.cast`, `ArrayTieShapeOp`, `LinCastOp`, `arith.select`, `ub.poison`) that share one per-column rule, registered by name. It predates recheck 5 (present at `04c2393d`). No declared fact names the set; whether one should is L12's.
- Recheck 5's question about `Target.h:94, 102` is answered: `Target/Schedules.cpp:263-264` builds the schedule library's text from those two constants, so the entry names are held once. The library is MLIR text parsed once per context when the transform dialect loads (read; not measured).
- Recheck 5 counted `Prim`'s hand constructors as 15; there are 16, the same set as then.
