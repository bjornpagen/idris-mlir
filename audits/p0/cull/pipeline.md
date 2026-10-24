<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Cull audit: the pipeline and its passes

HEAD at start: `363dcc0d` (AGENTS.md: delete before you optimize).
HEAD at finish: `d378e120`. Four commits landed while this was read
(927f82e8, a8b9fa3d, 723cac53, d378e120). Of the files below, only
d378e120 (L14ab, C285) touches any: `EGraph.h`, `EGraph/Engine.h`,
`EGraph/Reads.h`, `EGraph/Rules.cpp` and `EGraph/Values.cpp`. Every line
cited from them was read again at d378e120, and so was every line this
report's verdicts rest on (`git show HEAD:<path>`).

Area:
- `compiler/spec/IdrisMLIR/Spec/Pipeline/`: `Pipeline.idr` 644 lines,
  `Pass.idr` 238, `Stage.idr` 233;
- `foreign/idr/lib/Transforms/` and `foreign/idr/lib/Conversion/`,
  40,113 lines in all;
- their headers under `include/idr/Transforms` and
  `include/idr/Conversion`, 9,250 lines.

Every step of `programPipeline` and `pipeline` (Pipeline.idr:585-644) was
read in order, along with the three inner steps idr-optimize makes
(`redirect`, `inlineLeaves`, `constants`) and the two steps around a nest
(`widenRows`, `writeRows`). Each step names its rule; §2 has them all.

Method: the Elon algorithm, in order.
1. Each part names its rule (an owner's ruling Dnnn, a coordinator's
   decision Cnnn, or an AGENTS.md rule) and the fact only it supplies.
2. A part is deleted when its rule is gone, or when a type, a
   construction, a generated table or another part already holds its
   fact.
3. What survives and could be simpler is noted after that.

How things were checked:
- "No reader" means a `git grep -n -w` over `compiler/`, `foreign/`,
  `harness/` and `tests/` at HEAD, with its count given. Each search
  leaves out `audits/`, `proposals/`, `sources/`, `third_party/` and
  `AGENTS.md`.
- A dead-function scan was run on a `git archive` of HEAD under
  `/tmp/pipeline-cull`. It took every function declared in a Transforms
  or Conversion header (626 declarations) and counted the word's uses
  outside comments. Every one has at least one use beyond its
  declaration and definition, so nothing in the area is dead at the
  symbol level. What follows is a cull of design, not of dead code.
- Nothing was built, generated or run. Building our C++ needs the MLIR
  libraries, and those need LLVM. Where only a pass statistic can decide
  a verdict, the report says which statistic to read and on what input.

Grounds: *read* (the cited line was opened), *measured* (a search count,
with its command), *conjecture* (needs the named measurement).

Other lanes are editing the checkout. `git status` at finish over the
files below: `compiler/spec/IdrisMLIR/Spec/Pipeline/Pipeline.idr` and
`foreign/idr/lib/Transforms/Specialize/Open.cpp` are modified, apparently
by L18's open-copy work (the diff touches `redirect`'s record). Every
`foreign/idr/include/idr/IR/Generated/` output is modified as well.
Everything else cited is clean. A deletion that touches Pipeline.idr, or
that regenerates the specification's outputs, waits on those edits.

The relayed request ("keep all the sources") is honoured: no file under
`sources/` is a candidate, and every citation stays in this report. It
also reads as the answer to §4's open item 1, which item 2, the
idr-constants question (candidate 2 here), waits on.

## 1. Candidates, ranked by lines deleted

### 1. idr-deduplicate: its stated premise is gone; delete unless the suite shows merges

- **The part.** `foreign/idr/lib/Transforms/Deduplicate/Deduplicate.cpp`
  (409 lines, `idr::deduplicate`) and `include/idr/Transforms/Deduplicate.h`
  (46). The step is `Pipeline.idr:235-243` (`deduplicate`), run at `:590`.
- **The fact it supplies.** Each class of functions that are equal op for
  op, types and inherent facts included, is merged into its first member.
  The premise it states is "Monomorphization writes one function per
  instantiation, and erasure leaves some of them one function twice
  over" (`Deduplicate.cpp:6-7`). The frontend's instance key now
  contradicts that premise. An erased argument keys no instance: "Any
  other erased argument keys nothing" (`Frontend/Translate/Instances.idr:312-316`,
  `supplying ErasedParam = pure (Keyless AValue)` at `:168`). So erasure
  makes one instance, never two. What can still produce two equal
  functions is narrower:
  - two type arguments that key two instances but appear in no IR type
    (a phantom parameter). A type that names a family has content
    identity, so its `!idr.data<…>` differs, and the merge, which
    compares types, would not fire on it;
  - two dictionaries that give one body.
- **The rule that required it.** None found. No ruling or decision in
  §2 or §3 names the pass. C240 mentions it only to drop the audit's
  worry about it (`proposals/0000-mlir-native.md:2158-2161`). Its place
  "after acceptance, so no merge changes a verdict" (`Pipeline.idr:590`)
  is §8's fix of a bug the pass caused, not a reason for it to exist. It
  is an optimization: its merge is an action a debug counter may skip
  (`Pipeline.idr:240`), and `harness/Universal.idr:147-168` runs the
  program suite with every action skipped.
- **Readers.** The pass runs in the pipeline, and nothing reads what it
  decides.
  - `git grep -n -i deduplicat HEAD -- compiler foreign harness tests`
    finds only these: the spec record and its list entry; the generated
    `IdrPasses.td:68`, `PassDialects.h.inc:25-27`, `Pipeline.h.inc:34`
    and `:181`, and `Actions.h.inc:15`; `Pipeline.h:26`; CMake
    `lib/Transforms/CMakeLists.txt:137-155`, `:184` and `:725`.
  - The rest are comments: `Expect.h:29`, `Expect/Named.cpp:7` (it
    fuses locations), `IR/Symbols.h:76`, `IR/Ops/Sites.cpp:14`,
    `SpecializeState.h:115` (the forms table uses upstream's
    `OperationEquivalence` itself, not the pass) and
    `Analysis/Solver/Extraction.h:5`.
  - No test names the pass (0 hits for `idr-deduplicate` under `tests/`).
- **The deletion.**
  - `lib/Transforms/Deduplicate/` (409) and `include/idr/Transforms/Deduplicate.h` (46).
  - `Pipeline.idr:235-243` and `:590`, with its entry in `passes`
    (`:562`).
  - `lib/Transforms/CMakeLists.txt:137-155`, and `IdrDeduplicate` at
    `:184` and `:725`.
  - `Pipeline.h:26`.
  - The generated records, regenerated: `IdrPasses.td` (14 lines),
    `PassDialects.h.inc`, `Pipeline.h.inc` (step and row) and
    `Actions.h.inc` (one tag).
  - The comments that name it in `Expect.h:29`, `Expect/Named.cpp:7`
    and `Symbols.h:76`. `Named.cpp:96` still walks `FusedLoc`, which a
    library's fusion also makes (`Sites.cpp:14`).
  - About 510 lines.
- **The measurement that would keep it.** `numMerged`
  (`-mlir-pass-statistics`, the harness's Scale report) summed over the
  program suite and `bench/` at HEAD. If it is 0, or a handful, delete
  the pass. If it is large, the duplicates have a source upstream of the
  pass: the merge belongs where the instance key is made, and the pass
  goes anyway (parse at the boundary).
- **Verdict.** DELETE, *conjecture* (the premise is *read* false; the
  remaining duplicates are unmeasured).
- **Owner.** L18 (the pass, the header), L03 (spec), INT (CMake,
  generated). Clean in the checkout, apart from Pipeline.idr (modified)
  and the generated outputs. Waits on L18's open Pipeline.idr edit.

### 2. idr-constants: the owner's open question (§4 item 2); evidence both ways, no verdict

- **The part.** `foreign/idr/lib/Transforms/Effects/Constants.cpp` (199,
  `IdrConstantsPass`), the inner pipeline's fourth step
  (`Optimize/Optimize.cpp:45-53`, `createConstants` at `:52`). Its
  machinery: `include/idr/Analysis/Constants.h` (115,
  `SummarizedConstantPropagation`, `CalleeReturns`, `keepFixed`,
  `returnedConstants`) and `lib/Analysis/Constants.cpp` (73). The spec
  record is `Pipeline.idr:529-535`.
- **Where it runs.** In every round of every member: right after
  `idr-simplify`, the e-graph (`Optimize.cpp:51`), and before the last
  redirect. So two folders run back to back on one body, every round.
- **What only it carries (read):**
  - The constants a final callee returns. They are kept in
    `Summary.constants` (`include/idr/Transforms/Optimize.h:76-83`),
    written from the final body by `returnedConstants`
    (`Settle.cpp:184`, `Analysis/Constants.cpp:60-73`) and read through
    `constantsOf` (`Effects/Constants.cpp:169-176`). The e-graph reads a
    callee's `CalleeFacts.givesBack` alone, an argument given back whole
    (`EGraph/Nodes.cpp:544-552`), never a constant.
  - Joins over live paths: region results, block arguments and
    loop-invariant values, through upstream's SCCP with
    `DeadCodeAnalysis` (`Effects/Constants.cpp:178-181`).
  - Each result of a multi-result op (`replaceWithConstant` per result,
    `:129-133`).
  - Our hand-written folds, reached through upstream's `visitOperation`.
- **What only the e-graph does.** It rewrites, shares, reasons by
  intervals, chooses by cost and places static data
  (`audits/p0/verify/handoffs/L16-queue.md:667-679`).
- **What both hold once already.** The never-folded list, generated
  with the e-graph's tables (`Analysis/Constants.cpp:15`, `:33-36`), and
  IEEE's rule (`keepFixed` through `fold::ieeeOn`). They read one
  meaning, but they are two propagators, and the queue records them
  drifting: `math.sqrt` folded by one and left by the other, and the
  byte budget binding one of them.
- **A second copy that goes with (A).** The optimizer keeps two
  summaries per final callee, each built at the component's end from
  the same final body: `Summary.constants` in `schedule.members[].phase`
  and `CalleeFacts` (gives back) in `schedule.callees`
  (`Settle.cpp:170-185`). One summary per result ("an argument path, a
  constant, or unknown") would hold both.
- **What (A), one folder, deletes.**
  - `Effects/Constants.cpp` (199).
  - From `Analysis/Constants.h`: `ConstantResults`, `keepFixed`,
    `returnedConstants`, `CalleeReturns` and
    `SummarizedConstantPropagation`, about 85 of 115 lines. `Folding` and
    `foldingOf` stay, since `Conversion/Lower.cpp:139-140` reads them.
  - From `Analysis/Constants.cpp`, about 45 of 73 lines.
  - `Summary.constants`, its write at `Settle.cpp:184`,
    `InnerCounts.constants` and `Optimize.cpp:52`.
  - `createConstants` in `Effects.h:265`.
  - The spec record (7 lines) and its list entry; the three
    `constants-*` actions; `IdrInnerPasses.td:33-37`.
  - About 360 lines, against what the e-graph gains: callee constants
    beside gives-back, live-path joins as region rules, hand folds as
    meanings.
- **What (B) keeps.** Two propagators, with idr-constants folding only
  the specification's lists.
- **Verdict.** None: the owner's engine choice. Neither figure is
  counted in the totals.
- **Owner.** L02 (`Effects/Constants.cpp`), L14 (`Analysis/Constants.*`,
  `EGraph/`), L18 (`Optimize/`), L03 (spec). The e-graph headers and
  sources changed in d378e120. Waits on the owner's ruling, then on
  L14's e-graph.

### 3. The `reached` property: no fixture states it

- **The part.**
  - `foreign/idr/lib/Transforms/Expect/Reached.cpp` (42, `expect::reached`).
  - Its row in `include/idr/Transforms/ExpectProperties.inc:66-69`.
  - Its record in `harness/Properties.idr:186-189` (`property "reached"
    NoArgument Stated`).
  - Its self-test, `tests/expect-reached/` (51).
- **The fact it supplies.** Every function of the module is reachable
  from its public roots. Its own comment says the frontend already
  makes this hold ("The frontend writes a function only where the
  program needs it", `Reached.cpp:6-8`). After the optimizer, upstream's
  `symbol-dce` makes it hold, twice (`Pipeline.idr:595`, `:612`).
- **The rule that required it.** The tests rule (a property a test
  states). But no test states it. The search
  `git grep -n -E "(holds=|: |,| )reached(=| |,|$)" HEAD -- tests` finds
  only `tests/expect-reached/expect-reached.mlir:1`. No `mlir.expect`
  names it (`git grep -l -w reached -- 'tests/**/mlir.expect'`: 0), and
  `harness/Universal.idr` does not state it. A property only its own
  self-test states checks the checker, not the compiler, which
  testing-by-search deletes.
- **Readers.** `harness/Properties.idr:186`, the generated row, and the
  self-test.
- **The deletion.**
  - `Expect/Reached.cpp` and `lib/Transforms/CMakeLists.txt:634`.
  - `ExpectProperties.inc:66-69`, regenerated by `runtests
    --expect-table` from `harness/Properties.idr:186-189`, which goes.
  - `tests/expect-reached/`.
  - About 103 lines.
- **Verdict.** DELETE, *measured*.
- **Owner.** L19. Clean. Waits on nothing.

### 4. The stage facts: two pairs of columns that are one fact each

- **The part.** `compiler/spec/IdrisMLIR/Spec/Pipeline/Stage.idr` holds
  six columns of `stageFacts` (`:225-233`). Two pairs of them partition
  the five stages identically.
  - `closuresAt` and `tailsAt` (`:190-192`, `:206-208`): `Higher` on
    one side, everything else on the other. The tails column's own
    comment names the same event: the decider's answer "which the pass
    that makes the program first order writes" (`:92-94`).
  - `tailLayoutsAt` and `edgeHoldsAt` (`:211-214`, `:217-220`): `Higher` and
    `First` on one side, everything else on the other. Both readers
    name the same event, the specializer done keying calls:
    - `IR/Tail.cpp:260-269`: "idr-optimize's specializer makes it one";
    - `IR/Grades.cpp:232-239`: "no edge of a program past the
      specializer".
- **The fact.** One fact per pair: the program is first order, and the
  specializer is done keying calls. Each pair holds it twice, so a new
  stage between `First` and `Graded` would have to be placed in two
  columns or the pair drifts.
- **The rule.** "One thing, one representation" (AGENTS.md). Brooks'
  limit was checked: each pair's readers name one event, so this is not
  two cases forced into one.
- **Readers** (measured: `git grep -n -w <column> HEAD -- foreign
  compiler/src`, outside `Generated/`):
  - `tailsAt`: 1, at `IR/Tail.cpp:258`;
  - `closuresAt`: 2, at `IR/Verify/Program.cpp:201` and
    `Expect/Named.cpp:54`;
  - `tailLayoutsAt`: 1, at `IR/Tail.cpp:268`;
  - `edgeHoldsAt`: 1, at `IR/Grades.cpp:238`.
- **The deletion.** In `Stage.idr`:
  - `StageTails` (`:91-95`), `tailsClosed` (`:154-164`), `tailsAt`
    (`:206-208`) and the column at `:230`. `Tail.cpp:258` reads
    `closuresAt == FirstOrder` instead.
  - One of `StageTailLayouts` or `StageEdgeHolds` (`:97-104` or
    `:106-115`), its `Closed` record, its function and its column. Name
    the survivor for the event; the name is L03's to choose. Its two
    readers read it.
  - In the generated `StageFacts.h.inc`, two enums, their traits and
    their arrays, about 46 lines.
  - About 95 lines.
- **Verdict.** MERGE (into `closuresAt`, and into one "keyed" column),
  *read*.
- **Owner.** L03 (spec), L10 (`Tail.cpp`), L05 (`Grades.cpp`), INT
  (generated). `Stage.idr`, `Tail.cpp` and `Grades.cpp` are clean.
  `Grades.h` and the generated outputs are modified. Waits on the
  generated outputs' lane.

### 5. idr-lower-runtime and idr-lower-statics: two passes that are idr-lower's serial phase

- **The part.**
  - `lib/Conversion/Lower/Declarations.cpp:12-48` (`LowerRuntime`, a
    pass whose body is one loop).
  - `lib/Conversion/Lower/Statics.cpp:12-123` (`LowerStatics`).
  - `Pipeline.idr:461-471`, run at `:619-620`.
- **The fact they supply.** Every runtime function is declared and
  every static datum made before any function is lowered, so that the
  parallel lowering writes nothing outside its function
  (`Lower.cpp:4-6`). `idr-lower` already has a serial phase 0, which
  renames and builds every function before the parallel phases
  (`Lower.cpp` header, phase 0; `Lower/Functions.cpp:6-8`). The same
  order holds with both loops called there.
- **The rule that required them.** None separately. They change no
  stage (both `At Owned`, so no `--idr-pipeline` slice ends between
  them), and no test names them (0 hits for `idr-lower-runtime` or
  `idr-lower-statics` under `tests/`).
- **What survives and could be simpler (step 3).** A static datum's
  global is found again at every use by recomputing its content's
  digest and looking up the name. `StaticNames::string`, `big`, `cell`,
  `array` and `text` hash per call (`StaticNames.cpp:51-80`). They are
  called from:
  - `StaticData.cpp:106`, `:125`, `:128`, `:179`, `:238` and `:245`;
  - `StaticBytes.cpp:37`, `:86`, `:119`, `:137` and `:163`;
  - `Runtime.cpp:179-180`;
  - `Lower/Accounts.cpp:107`.

  The digest-named symbol is how two passes agree on one global
  (`StaticNames.cpp:3-7`): "NO FACT KNOWN STATICALLY … hashed". Held in
  one pass, phase 0 can keep a constant-to-global table, read through a
  const view by the parallel phases, and name each global once.
- **The deletion.**
  - The two `Pass` records and their `Run` lines.
  - The generated `IdrPasses.td:360-371`, their `PassDialects.h.inc`
    entries, and `Pipeline.h.inc:130-134` and `:213-214`.
  - The pass boilerplate in both files (includes, `GEN_PASS_DEF`, the
    struct), about 35 lines.
  - Their bodies become two functions called from `Lower.cpp`'s
    phase 0.
  - About 75 lines.
- **Verdict.** MERGE into `idr-lower`, *read*.
- **Owner.** L21 (Conversion), L03 (spec), INT (generated). The
  Conversion files are clean. Waits on L18's Pipeline.idr edit.

### 6. Stale entries in the ownership map

- **The part.** `audits/p0/verify/ownership.json` has 35 entries that
  name files or directories under this area that no longer exist.
  Measured with `os.path.exists` over every entry naming Transforms,
  Conversion or Pipeline:
  - INT: `lib/Conversion/CMakeLists.txt`.
  - L03: `include/idr/Transforms/Passes.td` and `InnerPasses.td` (now
    `Generated/IdrPasses.td` and `IdrInnerPasses.td`).
  - L05: `lib/Transforms/Stack/` and `Stack.h`.
  - L07: eleven `lib/Transforms/Ownership/*.cpp` (Buffers, Cells,
    Classes, Grades, Placement, Reshape, Reuse, Share, Signatures,
    Specialize, Take), `Ownership.h`, `Demand/` and `Demand.h`.
  - L08: `Ownership/Commit.cpp`.
  - L10: `Conversion/TailCallPlan.*`, `TailPosition.*` and `Frame.*`.
  - L14: `Transforms/Identity/` and `Identity.h`.
  - L21: `Conversion/Facts.*`, `Fields.*`, `FuncToFunc.*` and
    `Counting.cpp`.
- **The fact.** None: no file holds it. Every existing file in the area
  has an owner (checked: 0 files without one).
- **Verdict.** DELETE the 35 entries, *measured*.
- **Owner.** Coordinator. Waits on nothing.

### 7. `PassKind` and `GraphEffect`: two fields of every pass that nothing reads

- **The part.** `compiler/spec/IdrisMLIR/Spec/Pipeline/Pass.idr:38-51`
  (`data PassKind = Decide | Apply | Restructure | Check`, `data
  GraphEffect = Keeps | Edits | Invalidates`, with their comments), the
  record fields `kind` and `graph` (`:206-207`), and the value of each in
  all 39 `MkPass` calls.
- **The fact.** `GraphEffect` claims what each pass does to the program
  graph. The C++ already holds that fact, in each pass's
  `markAnalysesPreserved` calls, and the two copies disagree (*read*):
  - `defunctionalize` is `Invalidates` (`Pipeline.idr:216`), but its
    pass preserves `ProgramGraph` (`Defunctionalize/Pass.cpp:105`);
  - `inline` is `Edits` (`:274`), but it invalidates everything and
    builds the graph anew (`Inline/InlinePass.cpp:67-72`);
  - `columns` is `Edits` (`:284`), but `Columns.cpp` preserves nothing.

  `PassKind`'s one reader is the proof in `RunDeciding` (`Pipeline.idr:189`,
  `p.kind = Decide`). It checks a label against the constructor the pass
  already stands in, which is the decider's mark, and the generator
  reads that mark (`Generator/Cpp.idr:1492-1506`, `applyGroupOf…`).
- **Readers** (measured):
  - `git grep -n -w -E "Decide|Apply|Restructure|Check|Keeps|Edits|Invalidates" HEAD -- compiler/spec`,
    outside the `MkPass` lines, finds only the two `data` lines and
    `Pipeline.idr:189`;
  - `MkPass` is never destructured (`git grep -n MkPass`: the
    constructor's declaration alone);
  - `passOds` (`Generator/Ods.idr:1025-1041`) prints name, anchor, doc,
    statistics, options, loads and construction, but never `kind` or
    `graph`.
- **The rule that required them.** None. The pass's preserved analyses
  are the pass's own C++, and nothing generates them from the spec.
- **The deletion.** `Pass.idr:38-51` and `:206-207`, two arguments in
  each of the 39 `MkPass` calls (`Pipeline.idr:210-555`), and
  `Pipeline.idr:189`. About 20 lines, plus 78 arguments.
- **Verdict.** DELETE, *measured*.
- **Owner.** L03. `Pass.idr` is clean; `Pipeline.idr` is modified. Waits
  on L18's Pipeline.idr edit.

### 8. idr-contify's first run: its stated reason moved to Emit

- **The part.** `Pipeline.idr:591`, `Run contify "while each
  continuation still returns to the one place it was made for"`, and its
  generated step and row in `Pipeline.h.inc`.
- **The fact it supplied.** It contified source continuations before the
  optimizer could move them. C240 moved exactly that to Emit: "Emit
  writes `idr.join`, or `idr.loop` for a recursive one, for each
  continuation the program as written makes … Contify stays what D75
  calls optimization, finding the rest after inlining"
  (`proposals/0000-mlir-native.md:2147-2161`).
- **What the first run still finds, and who else finds it.** A
  definition called from one continuation (`Contify.cpp:6-10`). The
  inliner inlines any function called once, since its verdict is
  `(calls - 1) * (size - kSmall) <= kProduct`, which holds at
  `calls = 1` (`include/idr/Transforms/Inline.h:52-60`). The second
  contify run (`:594`, C45's "contify again") then finds what the
  inliner's cap kept.
- **The rule.** C45 (`proposals/0000-mlir-native.md:3608-3616`) orders
  "specialize … inline once … contify again". The "again" reads as
  presupposing a first run, and C240 removed that run's reason.
- **The deletion.** One spec line and about 4 generated lines; the pass
  stays, run once.
- **Measurement.** `numContified` for the first contify (step 5 of
  `Pipeline.h.inc`) over the program suite. Delete if 0, or if the
  second run's count rises by as much. Also compare `numNodes`, the
  copies the specializer makes, with and without it.
- **Verdict.** DELETE (one run), *conjecture*. The second run is KEEP
  (C45, C240).
- **Owner.** L03 (spec), L18 (contify). Waits on L18's Pipeline.idr edit,
  and on whoever runs the measurement.

## 2. Every step, in the specification's order

Each step below has its rule, and the fact only it supplies. "KEEP" means
the rule stands and no type, construction or other step holds the fact.
The upstream passes are KEEP throughout: upstream's own, run as upstream
ships them (D99).

1. **idr-target** (`lib/Target/Target.cpp`).
   - Fact: writes the target triple, CPU, features, data layout and
     vector width.
   - Rule: AGENTS.md's one place the target is decided.
   - KEEP.
2. **idr-defunctionalize** (1,862 lines).
   - Fact: makes every closure a constructor and every force a call,
     solves the labels, runs the one tail decider, builds the program
     graph and derives the rows.
   - Rule: AGENTS.md (defunctionalization makes every closure set a sum),
     C203 (the tail decider runs here).
   - KEEP.
3. **idr-knots** (173).
   - Fact: refuses a reference cycle on the type graph.
   - Rule: AGENTS.md ("`idr-knots` refuses every one"). It refuses a
     user's program, so it is a pass and not a verifier rule
     (`Knots.cpp:26-27`).
   - KEEP.
4. **idr-in-place** (InPlace/, minus UniqueResults).
   - Fact: decides the in-place promise before any optimization.
   - Rule: D24, D70-D72, D79; C190 (the local rule runs where the grade
     was just written).
   - KEEP.
5. **idr-deduplicate**: candidate 1.
6. **idr-contify, first run**: candidate 8.
7. **idr-optimize** (Optimize/, Specialize/, Inline/Inline.cpp). Fact:
   specialization to completion bottom-up, then the dead results,
   parameters and captures. Its inner steps:
   - `redirect`: KEEP. C45, C46, D129 (the open copy).
   - `inline-leaves`: KEEP. C45: leaf inlining "shows the constructors
     a caller's other calls are keyed on", `Inline.h:8-12`.
   - `simplify`: KEEP. D98, D106-D108.
   - `constants`: candidate 2, the owner's question.

   Rule: AGENTS.md (the monomorphic program); D58 and D89 (the keys); C45
   and C46. Raising (`Specialize/Raise.cpp`, `Consumer.cpp`, 584 lines)
   had no ruling a search could find (`grep -rn -i "arity rais\|raising"
   proposals/`: one mention, as a pass `decideTails` follows, in C203).
   Its fact is still unique: the dispatch that runs an action meets the
   constructors its callee's tails built, so an IO loop allocates no
   action closures. KEEP, with the gap noted for the coordinator.

   *Survives, could be simpler:* three least fixpoints of one rule ("a
   position is read unless every use passes it to an unread position"):
   - `Demand.cpp` (178): parameters, per component;
   - `Results.cpp` (316): results, whole program;
   - `Captures.cpp` and `CaptureDrops.cpp` (448): captures, whole
     program.

   They run at different times (parameters before callers are taken up,
   the other two after every function is final), so they are not
   trivially one pass. Their rule could be one marking over a typed
   position.
8. **idr-inline** (`InlinePass.cpp`, 76).
   - Fact: weighed inlining on the final graph, upstream's
     `mlir::Inliner` with the e-graph as its simplification.
   - Rule: C45.
   - KEEP.
9. **idr-contify, second run** (`Contify.cpp`, 362).
   - Fact: makes a function a join point where all its calls return to
     one place.
   - Rule: C45, C240, D75.
   - KEEP.
10. **symbol-dce**: what the optimizer left unnamed. KEEP.
11. **idr-columns** (1,053).
    - Fact: holds a tensor of records as one tensor per leaf.
    - Rule: 0009's D44, absorbed by D43
      (`proposals/0009-typed-apl/README.md:398-400`).
    - KEEP.
12. **idr-simplify**: D98, D106-D108. KEEP.
13. **idr-structure-loops** (StructureLoops/, 736).
    - Fact: turns the pure word ops into linalg.
    - Rule: D42, D43.
    - KEEP.
14. **idr-unique-results** (`UniqueResults.cpp` 351, `Unique.cpp` 356,
    the latter shared).
    - Fact: unique deep claims from QTT and freshness, before
      bufferization reads them.
    - Rule: C92, C190, C282. rc-exclusive needs placement, which needs
      buffers, which need this, so it cannot run here
      (`Ownership/Exclusive.cpp:4-6`).
    - KEEP.
15. **idr-bufferize** (1,550).
    - Fact: puts every array in a buffer, in place where the grade
      allows.
    - Rule: D43, D122, D124.
    - KEEP.
16. **idr-simplify**: what bufferization leaves. D98. KEEP.
17. **idr-accumulate** (`Accumulate.cpp`, `AccumulatorPlan.cpp`, 662).
    - Fact: turns an exactly associative tail combination into an
      accumulator.
    - Rule: C4 (widened, amended).
    - KEEP.
18. **idr-rc-cells**: each constructor of a cell becomes its allocation.
    It is counting's first step (AGENTS.md's frame limit; D26; C1).
    KEEP.
19. **idr-lifetimes** (1,704).
    - Fact: every lifetime born decided.
    - Rule: D39, D63, D88-D96, C189.
    - KEEP.
20. **idr-rc-borrows** (`Borrows.cpp`, 392).
    - Fact: writes the borrowed parameters into the signatures, and the
      loans.
    - Rule: D26, whose borrows carry a space rule; C1.
    - KEEP.
21. **idr-rc-place**: drops at last use, and drops specialized. D26:
    reuse is decided after the drops are placed. KEEP.
22. **idr-rc-exclusive**: the exclusivity marking, committed to grades.
    D24, AGENTS.md. KEEP.
23. **idr-rc-reuse, idr-rc-expand**: reuse, and the take's two-region
    match folded by grade. D26, AGENTS.md (no test of what the type
    proves). KEEP.
24. **symbol-dce**: grade copies no call kept. KEEP.
25. **idr-trmc** (514).
    - Fact: turns a self call modulo a context into a loop with a
      destination.
    - Rule: AGENTS.md (TRMC is a promise), D30.
    - KEEP.
26. **idr-frames** (Tail/, about 1,800).
    - Fact: puts cycle depth on typed frame stacks.
    - Rule: AGENTS.md (proper tail calls, a small native stack), D30,
      D66, C189.
    - KEEP.
27. **idr-tail-loops** (156).
    - Fact: turns self tail calls into a recursive join point.
    - Rule: AGENTS.md ("a recursive join point is a loop"). The loop is
      "an optimization over the guarantee" (`TailLoops.cpp:9-11`), and
      narrow's versioning reads it (`Narrow/Versions.cpp`).
    - KEEP.
28. **idr-narrow, idr-narrow-words** (Narrow/ minus Lanes, Copy and
    Widths, about 1,270).
    - Fact: bigs and naturals proved small become words.
    - Rule: AGENTS.md ("NO FACT KNOWN STATICALLY … at runtime"). It
      reads upstream's range analysis (`Analysis/Ranges`), which is
      L14's.
    - KEEP.
29. **idr-ordered-loops**: the generating ops left become loops, by
    their tiling methods. D42. KEEP.
30. **idr-lower-runtime, idr-lower-statics**: candidate 5.
31. **idr-lower** (Conversion/, about 7,600). The lowering. KEEP. Its
    `Lower/Accounts.cpp` calls inline to nothing in the shipped runtime
    and are kept by C138.
32. **idr-entry** (`Entry.cpp`, 123).
    - Fact: erases the program op into the module, and adds the entry
      body and record.
    - A pass on the program cannot erase its own op, so this is a module
      pass.
    - KEEP.
33. **DebugInfoScope** (upstream): line tables need it. KEEP.
34. **ScheduleInterpreter** (upstream): vectorization. KEEP.
35. **idr-narrow-lanes** (Lanes, Copy, Widths: 618).
    - Fact: gives a 32-bit version under a found bound.
    - Rule: 0009's stage 1, built, under D43.
    - KEEP.
36. **LinalgToLoops through ReconcileUnrealizedCasts** (upstream). KEEP.
37. **idr-tail-calls** (`TailCalls.cpp` 137, `PassThroughMemory.cpp`
    102, `ReturnRegisters.cpp` 76).
    - Fact: ends each musttail call's block with a return, and passes
      results too large for the registers through memory.
    - Rule: D30. LLVM's rule that `ret` follows `musttail`, and the
      result that does not fit the registers.
    - KEEP.
38. **idr-expect** (registered, not in the pipeline; Expect/ 2,405).
    - Rule: AGENTS.md's tests rule (the property written once as a test
      API).
    - KEEP, except `reached` (candidate 3).
    - `constant-stack` (`Expect/ConstantStack.cpp`, 127) overlaps the
      driver's cycle check (`lib/Driver/StackBound.cpp:202-216`). That
      check runs on every compilation, but on the module after LLVM's
      optimization (`Artifacts.cpp:338`, `Graph::of(optimized, …)`),
      where LLVM's tail-recursion elimination could hide a self call the
      pipeline left growing. Its unique fact is "the pipeline made it,
      not LLVM" (D30: a missed tail call is an internal error, never
      silent). KEEP.
39. **widen-rows, write-rows** (`Pipeline.cpp`, `Effects/Writer.cpp`,
    `Parts.cpp`).
    - Fact: rows cover their bodies while a nest runs, and are exact
      after it.
    - Rule: AGENTS.md (one effect system, one writer), D9.
    - KEEP.

## 3. Seen outside the area

- `tests/arity-raising/Main.idr:5-7` says the loop "takes the world as an
  argument". The world ends at Emit (D20), so the comment is stale (L19).
- `tests/upstream-cse-statistic-assignment/run:4-7` retires patch 23
  because "no test compares pass statistics across thread counts any
  more". `tests/determinism-threads-rbtree/expected:4` and
  `tests/determinism-threads-linarray-lanes/expected:4` do compare them.
  The patch is still unreached, since no upstream CSE runs (D98, D100),
  but the stated reason is wrong (L19, upstream).

## 4. Table

| # | candidate | verdict | ground | lines | owner | waits on |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | idr-deduplicate | DELETE | conjecture (premise read false; `numMerged` to measure) | ~510 | L18, L03, INT | L18's Pipeline.idr edit |
| 2 | idr-constants | owner's question (A/B) | read | (A) ~360, not counted | L02, L14, L18, L03 | the owner's ruling, then L14's e-graph |
| 3 | `reached` property | DELETE | measured | ~103 | L19 | nothing |
| 4 | stage facts: tails≡closures, tail layouts≡edge holds | MERGE | read | ~95 | L03, L10, L05, INT | the generated outputs' lane |
| 5 | idr-lower-runtime, idr-lower-statics | MERGE into idr-lower | read | ~75 | L21, L03, INT | L18's Pipeline.idr edit |
| 6 | stale ownership.json entries | DELETE | measured | 35 | coordinator | nothing |
| 7 | `PassKind`, `GraphEffect` | DELETE | measured | ~20 (+78 arguments) | L03 | L18's Pipeline.idr edit |
| 8 | idr-contify's first run | DELETE (one run) | conjecture (`numContified` to measure) | ~5 | L03, L18 | L18's Pipeline.idr edit; the measurement |

Totals (DELETE and MERGE verdicts):
- read or measured: 3 + 4 + 5 + 6 + 7 = **~328 lines**;
- conjecture: 1 + 8 = **~515 lines**;
- in all, **~843 lines**;
- **~360 more** if the owner chooses (A) on idr-constants, net of what
  the e-graph gains.

Nothing in the pipeline's 39 steps is dead at the symbol level (the
626-declaration scan above). Every step but candidates 1, 5 and 8 has a
standing rule and a fact no type, construction or other step holds.
