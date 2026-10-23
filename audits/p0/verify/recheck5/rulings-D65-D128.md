<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Recheck 5: the owner's rulings D65 to D128 against the tree

HEAD was 17725fdd at start and 59dcc964 at finish. Between them,
2bcbd726 and 59dcc964 touch only the queue, and 16ac96c4 is D126 round
2b-T. Nothing was built, typechecked, generated or run.

Files in the moving tree were read as HEAD's text (`git show HEAD:`).
Where the working tree already differs, the row is marked "in flight"
and says what is there. Paths are under `foreign/idr/` unless they start
with another top-level directory; `spec/` is
`compiler/spec/IdrisMLIR/Spec/`. Owners are from `ownership.json`.

D112 to D128 are checked in full. D65 to D111 are checked for
regressions since recheck 3; none regressed, and five of recheck 3's
findings are closed (D67, D75, D103, D104, D108), with D71's closed by
D122 and D98's ruled on by D127.

## Not done

### D127: constants through the e-graph (L14x in flight)

- **D127.1: the graph holds strings, Doubles and bigs as its own values**
  — **Missing** at HEAD, in flight.
  - At HEAD the graph computes only integers.
    `include/idr/Transforms/EGraph/Engine.h:15-16` says "the op's own fold
    is never asked, since a fold makes an attribute and the graph makes
    none". At `:177-192`, `node::Constant` is "a constant an op of the
    input holds as an attribute", and only `node::Integer` is a value.
  - The working tree adds `Text`, `Real`, `Big`, `node::Known` and a
    per-op `Meaning` to `Engine.h`, and a new untracked
    `lib/Transforms/EGraph/Values.cpp`.
  - Ground: read. Owner: L14, with L13 for `Fold.h`.
  - Remaining: land L14x. Delete the attribute-held `node::Constant` once
    every constant is read into a value at build.
  - D98's clause "an op's fold ... read by the e-graph" is this row. It
    was recheck 3's D98 finding, which D127 has now ruled on.
- **D127.2: `Fold.h`'s conversions made generic over the domain, the fold
  its attribute instance** — **Missing** at HEAD, in flight.
  - HEAD `include/idr/IR/Fold.h:80`: `strOf(Scope &, mlir::Attribute)`;
    every conversion reads an attribute.
  - The working-tree header (`:13-22`) instantiates one fold over two
    domains, an attribute and a value of the graph.
  - Ground: read. Owner: L13.
  - Remaining: land it with one row, one call and one reading of each
    kind in `Fold.h`, and keep no attribute-only copy.
- **D127.3: `NeverFolded` and a NaN stay unfolded** — **Done**. At HEAD
  this holds trivially, since the graph folds nothing; it is in flight.
  - The list: `spec/Ops/Shapes.idr:377-421` and
    `IR/Generated/Rewrites.h.inc:22`.
  - Working tree: `lib/Transforms/EGraph/Rules.cpp:70`
    `static_assert(noneComputed(generated::NeverFolded{}))`;
    `include/idr/IR/Fold.h:29` and `:305` (a NaN is no constant).
  - Ground: read.
- **D127.4: C205 and C218 amended** — **Missing**.
  - `proposals/0000-mlir-native.md:4930-4939` (C205) and `:5019-5025`
    (C218) stand as written.
  - C218 still says "a string, a big past the small range or a data
    constant is read only from an op that already holds it, never made by
    a fold inside the graph", the reverse of D127.
  - Ground: read. Owner: coordinator.
  - Remaining: amend both in place under D127. The graph computes
    string, Double and big constants with the runtime's functions, as its
    own values, and makes an attribute only at the write-back.
- **D127.5: the lowering's comment comes true** — **Missing** at HEAD,
  in flight.
  - HEAD `lib/Conversion/Lower.cpp:225`: "the optimizer folded what folds
    before the lowering", which is untrue while D127.1 is missing.
  - The working tree's `:222-228` restates it over the graph's values.
  - Ground: read. Owner: L21 (L14x is writing it).
  - Remaining: nothing beyond D127.1 landing.

### D128: settled implementations walked as written (L16ee in flight)

- **D128.1: the translation walks a settled implementation as the site
  walk does, never through the host's normaliser** — **Missing** at
  HEAD, in flight.
  - HEAD `Frontend/Translate/Terms.idr:1045-1062`: `settle` translates
    `lambdasApplied (foldl (App EmptyFC) value terms)`.
  - HEAD `Frontend/Growth/Sites.idr:1915`:
    `settled <- lambdasApplied ...`.
  - Both go through `Translate/Closed.idr:413-414`
    (`host.normaliseHoles`).
  - The working tree drops both calls and translates through `applyHead`
    (`Terms.idr:861-941`).
  - Ground: read, and measured with `git grep -n -w lambdasApplied --
    compiler/src`: 12 at HEAD, 9 in the working tree.
  - Owner: L16.
  - Remaining: land L16ee. The callers left (`Terms.idr:486`
    `formType`, `Closed.idr:993` and `:1047`, `Growth/Template.idr:2422`)
    read types, keys and roots, which D128 leaves to the normaliser.
- **D128.2: a closure argument bound once by a `let`, not inlined at each
  use** — **Missing** at HEAD, in flight.
  - HEAD `Terms.idr:1047-1050`: an argument "is given in place when the
    evaluator may see it whole".
  - Working tree `Terms.idr:534`: "A runtime value, bound once by a `let`
    before the term"; also `:772` and `:879-887`.
  - Ground: read. Owner: L16.
- **D128.3: the run-time re-check deleted** — **Missing**, not in
  flight.
  - `compiler/src/IdrisMLIR/Frontend/Finite.idr:171-194`: `unsound` and
    its callers at `:183`, `:185` and `:194` still run.
  - `compiler/src/IdrisMLIR/Proof/Covers.idr:99`: "The induction is not
    yet whole, so the run-time re-check stays".
  - Ground: read. Owner: L16.
  - Remaining: once C257's site walk lands and Covers' five open steps
    (`:101`, `:111`, `:122`, `:134`, `:169`) are proved, delete `unsound`
    and its three callers. This is the D68 row's obligation too.
- **D128.4: keys still read through the host's normaliser** — **Done**.
  `Translate/Closed.idr:413-422`. Ground: read.

### D126: the type-dispatch cull (round 2b-S in flight, 2b-T landed, 2c queued)

- **D126** — **Partial**, in flight. Ground: read and measured.
- **The counts:**
  - 606 lines with `isa<` or `dyn_cast<` outside `Generated/` (`git grep
    -n -E '(isa|dyn_cast)<' HEAD -- foreign/idr
    ':!foreign/idr/include/idr/IR/Generated/*' | wc -l`). bb8ce09c's own
    figure of 590 used another pattern.
  - 1,039 lines with any of `isa`, `dyn_cast` or `cast`, counted with
    PCRE and with comment lines excluded, in 95,016 lines of C++.
  - Ladders of three or more tests of one subject: 12, found by a
    heuristic (the same subject tested three ways within 30 lines). All
    are over interfaces or upstream classes (e.g.
    `lib/Analysis/IdentitiesRecord.cpp:177`,
    `lib/IR/Lifetimes/Verify.cpp:198`); none is over three concrete
    classes of ours.
  - Two-way tests over concrete classes of ours: 8 sites.
- **What is in:** the interfaces are declared in
  `spec/Core/Interfaces.idr` (bb8ce09c), with
  `include/idr/IR/Interfaces/Vocabulary.h` and
  `lib/IR/Interfaces/Defaults.cpp`. Round 2b-T moved the tail kind into
  `Tail.h` (16ac96c4).
- **In flight (2b-S):**
  - `lib/Transforms/Defunctionalize/Convert.cpp:100-104`: `ClosureAttr`
    or `ConAttr` by two `dyn_cast`s (L18).
  - `lib/Analysis/LabelSites.cpp:260-267` (L14).
  - `lib/Conversion/Lower/Statics.cpp:46`: a crash site read by the
    attribute name `"site"`; `:101`: `ConstantOp` or `LifetimeHomeOp`
    (L21).
  - `lib/Conversion/Strings.cpp:76` (`CountDropOp` or `IoPutStrOp`),
    and `:172` and `:188` (`is_same_v<OpT, StrPackOp>`) (L13).
  - `lib/IR/Lifetimes/Ops.cpp:54-91` (`extentOf`, `packedOf`) and
    `Proof.cpp:127` (`dyn_cast<CellArenaOp>`) (L05).
- **Queued for 2c** (`audits/p0/verify/handoffs/L16-queue.md:444-461`):
  - `getRunTimeWords` declared on `ValueFactsTypeInterface` in the
    specification. Then two things go: `lib/IR/Layout/Components.cpp:98`
    `wordsOf`, a template fold over our types, the form D126 rules out
    (L04); and `lib/Conversion/Lower/Functions.cpp:76`
    `dyn_cast<DestType>` (L21).
  - `lib/Transforms/Tail/Frames.cpp:154-164` and
    `Transforms/Lifetimes/Pass.cpp`'s `framingOf` ask one question twice
    (L10, L05).
  - `include/idr/Support/Match.h:9-12` still says "a type interface ...
    is not used to say what each of our types is", against D126 (L15).
  - The tail kind is read by hand at `lib/Conversion/Lower/Accounts.cpp:66`
    (L21), `lib/IR/Func/Call.cpp:273` (L02) and
    `lib/Transforms/EGraph/Build.cpp:62-63` (L14).
- **Not queued:**
  - `lib/Conversion/Matches.cpp:314-318` tests a terminator two ways,
    `YieldOp` or `JumpOp` (L09).
  - `lib/Transforms/Expect/ResetsUnshared.cpp:51`,
    `isa<CellType, ReuseTokenType>`, is kept with a stated reason
    (L19).
- **Remaining:** each named test becomes an interface method the
  specification declares, or a typed walk. `wordsOf` is deleted, and
  `Match.h`'s header is rewritten to say what D126 rules.

### D112: no invariant asserted on the Idris side

- **D112.1: the frontend's internal errors** — **Partial**.
  - 18 call sites, measured with `git grep -n -P '(?<![A-Za-z_])internal
    [a-zA-Z.]+ |InternalError \(|unsound [a-z]' HEAD -- 'compiler/src/*.idr'`,
    excluding comments, the two definitions, the driver's predicate and
    the file-write failures.
  - Not in flight:
    - `Frontend/Finite.idr:183`, `:185`, `:194`: D128.3's re-check.
    - `Frontend/Finite.idr:224`: a request new to its own chain, a fact of
      the instance table (queue "From L16cw").
    - `Frontend/Program.idr:85`: Emit's `Unfit`, since the term is not
      indexed by its type (queue "From L16dc").
  - In flight (Translate and Growth):
    - `Terms.idr:625`, `:735`, `:745`, `:1577`, `:1677`, `:1773`.
    - `Cases.idr:953`, `Choices.idr:567`, `Shapes.idr:300`,
      `State.idr:1329`.
    - `Growth/Graph.idr:2752` and `:2754`.
  - Kept with its reason: `Translate/Keys.idr:1140-1149`, a 64-bit hash
    collision ("Essential").
  - Ground: read, measured. Owner: L16.
  - Remaining: each becomes the type the queue names ("Audit at
    db4bcb11", "From L16dc", "From L16cw"), or a refusal where a program
    can reach it. `Keys.idr:1149` stays.
- **D112.2: the checker's internal errors** — **Partial**.
  - 71 `throw (InternalError …)` sites in `compiler/checker`. Measured:
    `git grep -n InternalError HEAD -- 'compiler/checker/*.idr'`, with
    comments and pattern-match arms dropped.
  - 15 of them state an impossibility:
    - `compiler/checker/src/Core/Context.idr:556-777`: seven, "A stored
      term is not a term of its arena", and a frozen node's child.
    - `TTImp/ProcessDef.idr:169` and `:174` ("Can't happen"), and
      `:495-528` ("With abstraction failure #1" to "#4").
    - One each in `Core/Unify.idr` and `Core/Hash.idr`.
  - `Idris/Desugar.idr:1499`: `throw (InternalError "%start not
    implemented") -- TODO!` is a refusal written as an internal error.
  - Ground: read, measured. Owner: L17.
  - Remaining:
    - Index the stored terms by their arena, so a read cannot miss
      (`Context`).
    - Have the with-abstraction steps return evidence (`ProcessDef`).
    - Refuse `%start` as `unsupported`.
    - What depends on the host stays and says so (`Context.idr:2576`,
      the current directory).
- **D112.3: `assert_total`, `assert_smaller`, `believe_me`** — **Done**.
  - There are none in code in `compiler/src`, `compiler/spec` or `libs`
    (measured: `git grep -n -w` per directory, comments and the
    registry's spellings excluded).
  - In `compiler/checker` only the stated trusts are left:
    - `0 trusted = believe_me ()` at
      `src/Core/Primitives/Host.idr:27-28` and `src/Idris/Host.idr:108-109`,
      each with its scope listed (`Idris/Host.idr:97-107`).
    - The partial primitives, each guarded by its test
      (`Core/Primitives/Host.idr:142-258`).
    - `Idris/Host.idr:3618` `host`, the frontend's one covering trust.
  - Ground: read, measured.
- **D112.4: the C++ half** — **Superseded** by D114.

### D124: lending an array to upstream's ops

- **D124, the frame case** — **Partial**.
  - `lib/Transforms/Lifetimes/Lend.cpp:111-115`: a read's span holding a
    call that continues on a frame gets no region.
  - `:169-193`: such a read is then shared (`share`, `:162-167`, a
    `CountShareOp`), so the count changes on a loan, which D124 rules
    out.
  - No decision records this case (measured: `grep 'continues on a
    frame\|shared into the read' proposals/0000-mlir-native.md` finds
    nothing).
  - Ground: read, measured. Owner: L05, with the coordinator.
  - Remaining: either record the case as a decision with its reason, or
    lend the reads on each side of the framed call under their own
    lifetimes (or across it by D95's pack and unpack) and delete `share`
    from `lendCounted`.
- **D124, the escape refusals are untested** — **Partial**.
  - No test reaches `idr.carrier`. Measured: `git grep -l 'idr.carrier'
    HEAD -- tests` finds 0, and no test is named for a loan or a carrier.
  - So none of the three refusals is pinned (an alias leaving its
    region or returned, an alias stored, an alias adopted), nor the
    check's run after every pass (`lib/IR/Verify/Program.cpp:205-206`).
  - Ground: measured. Owner: L19.
  - Remaining: one failing program per escape, each expecting the loan
    refusal, plus one program that lends and compiles.

### D68: the stated trust in the host's normaliser

- **D68** — **Partial**, unchanged since recheck 3 (not a regression).
  - Since D118 the trust lives in our checker:
    `compiler/checker/src/Idris/Host.idr:28-34` states `Reduces` and
    `Reduct` at quantity 0, over the relation `:782-799` declares.
  - The readers' soundness is not proved whole (`Proof/Covers.idr:99`).
  - The run-time witness is still there (`Frontend/Finite.idr:171-194`).
  - Ground: read. Owner: L16.
  - Remaining: prove `ReadingCovers` over Covers' five open steps, then
    delete `Finite.unsound` (with D128.3).

### D121: upstream bugs patched, never worked around

- **D121** — **Partial**.
  - What holds:
    - Every `upstream/*/` with a patch has its README, a
      `tests/upstream-<name>` and a PINS entry (measured: a loop over
      `upstream/*/`).
    - Idris patches 96 and 104 to 114 are carried
      (`upstream/README.md:161`, `:169-179`), covering two of the three
      named hazards.
  - What is left: the slow elaboration of nested linear patterns on the
    stock host has no record. `audits/p0/design/idris-linear-check.md:5-8`
    says "The cause is **not found**, there is **no fix**", and `:108`
    names "no `upstream/<bug>/` contents, no `PINS.md` line". Its §5
    (`:110`ff, "What our libraries should avoid until this is fixed")
    still gives avoid-advice.
  - Ground: read, measured. Owner: L06 for `upstream/`; the coordinator
    for the note.
  - Remaining: reproduce it on the stock Idris at the gitlink. Then
    either carry `upstream/<bug>/idris.patch` with its README,
    reproducer, `tests/upstream-<bug>` and PINS entry, or record that
    nothing in the tree meets it. Either way, strike §5.

### The measurements the rulings order (INT, at qualification)

- **D78, D95, D100, D108, D115** — **Partial**. Only the measurement is
  left; each needs a build, and no code changes.
  - D78: today's stack cells against cells in a lifetime.
  - D95: the gain of a per-level lifetime.
  - D100: the loss in the built output with nothing run at the
    upstream-only points.
  - D108: `nodesPerOp = 64`, which `spec/Pipeline/Pipeline.idr:295-303`
    calls "Not yet measured".
  - D115: the price of assertions on, against the same commit with them
    off.
  - Ground: read. Owner: INT.

## Done

Each was read (or measured, where said) at HEAD.

- **D65**: `runtime/Platform/Posix/Cgroups.cpp:279-310` takes the lowest
  limit up the cgroup tree, plus swap, less what is held.
- **D66**: `runtime/Start/Runner.cpp:136` commits the whole computed stack
  before the thread runs.
- **D67** (closes recheck 3's finding):
  - `foreign/idr/generated.manifest` lists 62 files with the spec and
    generator hashes. `Dialect/Idr.idr`, `Encoding/Wire.idr` and
    `Encoding/Idr.idr` are specgen outputs (384796f3 onward), with no
    stamp (`compiler/src/IdrisMLIR/Dialect/Idr.idr:3-5`).
  - `make check` compares them (`Makefile:371-375`).
  - The spec and `Generated/` are in flight under 2b-S.
- **D69**: 0011 is amended at `proposals/0011-data-oriented-frontend.md:413-414`
  and `:490-497`, 0009 at `:8, 68, 910`, and
  `proposals/0015-relational-core.md` at `:6-9, 21-23`.
- **D70**: `unique self` is `Unique::Self` (`spec/Grades/Hold.idr:34`;
  in flight).
- **D71**: `compiler/src/IdrisMLIR/Registry/Recognized.idr:139-142`. The
  writable read is gated on the cell's claim
  (`lib/Transforms/Bufferize/Releases.cpp:221-237`), and
  `unsupported (uniqueness)` is raised at
  `lib/Transforms/InPlace/InPlace.cpp:62`. The claim level is D122's.
- **D72**: a holder owes `unique self` through the part's reach
  (`include/idr/Analysis/Ownership/Facts.h:102-106`,
  `lib/Transforms/InPlace/Chains.cpp:247`).
- **D73**: `lib/Analysis/Ownership/Borrows.cpp:15-18` allows lending a
  part of a value the caller keeps.
- **D74**: `lib/Transforms/Counting/Placement.cpp:51-54` and
  `Bound.cpp:213`: nothing is freed after a process-ending path's last
  allocation.
- **D75** (closes recheck 3's finding; in flight):
  - The frontend makes the join points itself
    (`Translate/Programs.idr:453-523`, `Emit/Bodies.idr:901-920`).
  - `lib/Transforms/Optimize/Contify.cpp:6-12` promises nothing.
- **D76**: no `!idr.cont` and no `ContType` (measured: `git grep -E
  'idr\.cont\b|ContType'` finds 0). The target is the builtin token
  (`spec/Control/Joins.idr:11-16`).
- **D77**: `lib/Driver/LinkRuntime.cpp:87-88` strips the probes from the
  joined runtime. The runtime takes `-fstack-clash-protection`
  (`runtime/CMakeLists.txt:154-168`).
- **D78**, code: no stack bit in any header or test (measured). Its
  measurement is in the row above.
- **D79**: `lendReads` is used in the in-place check
  (`lib/Transforms/InPlace/UniqueResults.cpp:322`), and
  `tests/in-place-borrowed-read-ends` exists.
- **D80**: `runtime/End/End.cpp:293` has
  `idris_rt_crash_at(cause, function, file, line, column)`.
- **D81**: `runtime/Platform/Posix/Process.cpp:57-70` raises `SIGPIPE`
  after `EPIPE` (`Posix/Files.cpp:24`, `:115`).
- **D82**: `PINS.md:566-587` carries `upstream/65-early-exits`, PR
  #166688.
- **D83**: no test expects "megamorphic" (measured).
  `spec/Core/Rules.idr:164` defines the category by its analysis.
- **D88, D90**:
  - `Uses`, `Release` and `Unique` are at `spec/Grades/Grade.idr:25`
    and `Hold.idr:24, 34, 41` (in flight).
  - The deleted names are gone (measured: `git grep` for `!idr.q`,
    `!idr.lin`, `idr.borrow`, `idr.frame` and the old hold words finds 0
    outside `audits/`, `proposals/` and `sources/`).
- **D89**: copies are keyed by hold
  (`lib/Transforms/Specialize/Specialization.cpp:105-113`). The count-0
  marker is tested only on the path where the kind is unknown
  (`runtime/Rc/Rc.h:77-81`).
- **D92**: `proposals/0020-rust-interop.md:5-20` is amended. There is no
  Rust code.
- **D93**: `LifetimeKind = View | Room | Cursor | Home Nat`
  (`spec/Lifetimes/Kind.idr:25`). The openers are at
  `spec/Lifetimes/Declarations.idr:489-493` and `lifetime.forget` at
  `:652` (in flight).
- **D94**: `Amount = Finite bytes | Unbounded`, where `Unbounded` carries
  a proof the kind is not `Room` (`spec/Functions/Parameters.idr:66-67`).
  It is derived per body (`lib/IR/Func/Fold.cpp:37-60`).
- **D95**, code: `lifetime.pack` and `lifetime.unpack` are built by the
  frame split (`lib/Transforms/Tail/Split.cpp:127`) and lowered at
  `lib/Conversion/Lower/Packages.cpp:62` and `:97`.
- **D96**: unchanged since recheck 3.
- **D98**, the cutover itself:
  - No greedy driver and no canonicalize or CSE in our code or pipeline
    (measured: `git grep -E
    'applyPatternsGreedily|applyOpPatternsGreedily|GreedyRewriteConfig|createCanonicalizerPass|createCSEPass|getCanonicalizationPatterns'
    HEAD -- foreign/idr compiler/spec` finds 0).
  - The inliner's simplification is the e-graph
    (`spec/Pipeline/Pipeline.idr:278-279`).
  - Its fold clause is D127.1.
- **D99**: upstream passes are made by their default `create…Pass()`,
  with no options (`spec/Pipeline/Pipeline.idr:47-69`).
- **D100**, code: nothing simplifies after lowering
  (`spec/Pipeline/Pipeline.idr:17-19`). There is no `canonical` or `cse`
  in `lib/Transforms/Pipeline.cpp` (measured).
- **D101**: `compiler/checker/src/Libraries/Text/Bounded.idr:76-78` has
  `Irrelevant ty | Relevant ty Bounds`, and `isIrrelevant` gives 0 hits.
  The libraries were reshaped (bb2063ea).
- **D102**:
  - `spec/Core/Rewrite.idr:47-57` has the `Clean` row condition; no
    `Total` is left.
  - `lib/Transforms/EGraph/Build.cpp:28-55` floats only clean calls.
  - `spec/Effects/LLVM.idr:139-143`.
  - Other deletion sites check the derived effects
    (`Narrow/Copy.cpp:132`, `Narrow/Narrow.cpp:179`).
- **D103** (closes recheck 3's finding):
  - `ForwardWritten` and `DeleteOverwritten` are skeleton rules
    (`spec/Arrays/Memory.idr:470-486`), generated into `SkeletonRules`
    (`IR/Generated/Rewrites.h.inc:3700`).
  - They are implemented at `lib/IR/OpsArrayFusion.cpp:334-355`.
- **D104** (closes recheck 3's two findings; in flight):
  - A thaw hands over the array itself, with no `fresh` tabulate
    (`Translate/Terms.idr:2431-2437`).
  - `libs/mlir-array/Array/Core.idr:396-409` freezes and thaws in place;
    `Linear/Bytes.idr:42-60` builds on it.
  - `Fail` hands the handle back (`Linear/Parser.idr:33-36`).
- **D105** (in flight):
  - A successor of a literal is one literal
    (`Translate/Terms.idr:2086-2101`).
  - A case binds its scrutinee refined (`spec/Control/Matches.idr:224-228`,
    `compiler/src/IdrisMLIR/Emit/Bodies.idr:619-643`).
- **D106**: every rule is one-way (`spec/Core/Rewrite.idr:6-7`).
  Associativity fires only on two constants, and there is no
  commutativity rule (`spec/Generator/Cpp.idr:914-952`).
- **D107**:
  - The engine is C++ over MLIR's ops, its rules generated
    (`lib/Transforms/EGraph/Rules.cpp:28`).
  - The checker keeps its own union-find
    (`compiler/checker/src/Core/UnifyState.idr:13`, `:112`, `:263`).
- **D108**, the admission (closes recheck 3's finding):
  - `lib/Transforms/EGraph/Simplify.cpp:63-112`: every idr-simplify run
    enters its arena into one per-process ledger, whichever pass runs it.
  - An arena alone larger than the host ends through
    `report_bad_alloc_error`.
  - The budget is `nodesPerOp × ops` (`Build.cpp:82`).
- **D109**: no optimization pass in `compiler/src` (measured).
- **D110**: `DataType::getFieldReach` (`lib/IR/Types.cpp:229-231`) and
  the closure over members' own cells (`lib/IR/Families/Family.cpp:302-310`).
- **D111**: there is no `.toolchain/llvm`. The typecheck LLVM holds the
  TableGen tools only (measured, `ls`).
- **D113**:
  - The README section "Rewritten so that this compiler can compile it"
    is gone (measured).
  - `shuffleVars` (`compiler/checker/src/Core/Case/CaseBuilder.idr:838-842`)
    and `updateLocal` (`Core/Normalise/Eval.idr:252-260`) are restored.
  - C230 and C232 touched only the proposal.
  - The parser clause is superseded by D119.
- **D114**: our C++ asserts freely: 44 `assert` sites and 11
  `reportFatalInternalError` sites (measured). The contracts clause waits
  on clang: the pinned tree has no `contract_assert` (measured).
- **D115**:
  - `tools/bootstrap.sh:925-927` passes `-DLLVM_ENABLE_ASSERTIONS=ON` to
    every stage (`:962`, `:1067`, `:1188`).
  - `foreign/idr/CMakeLists.txt:21-45` strips `NDEBUG` and refuses an
    LLVM built without assertions.
  - `runtime/CMakeLists.txt:172` keeps `NDEBUG` for the runtime.
  - The price is in the measurements row.
- **D116**: `tools/self.sh:1-20` and `Makefile:38, 307, 322, 334` run the
  self-host stages.
- **D117**: `compiler/idris` is gone (measured, `ls`). The only live
  mention is AGENTS.md's never-line.
- **D118, with C233's deletions**:
  - `compiler/checker/idris-mlir-checker.ipkg`;
    `compiler/checker/README.md:1-17` states the attribution and that it
    tracks no upstream.
  - Measured gone: `tools/extract-idris.sh`, `MODULES`, `upstream/fork-*`,
    any fork entry in PINS.md, the re-sync sections, and the import
    fence.
- **D119**:
  - The grammars run over a quantity-1 `Input`, with termination in the
    types (`compiler/checker/src/Libraries/Text/Parser/Core.idr:2-29`,
    `:128-156`).
  - `TokType`, `ActType`, the metadata records and the tokenizer's tag
    are gone (measured; `Lexer/Tokenizer.idr:23-37`).
  - There are no escape hatches in the parser files (measured).
- **D120**: `foreign/idr/CMakeLists.txt:40-45`: only the typecheck build
  accepts an LLVM without assertions, then matches its `NDEBUG`.
  `tools/bootstrap.sh:1217` sets it.
- **C226, as D115 amends it**:
  - The always-on form is `reportFatalInternalError`.
  - `lib/Driver/Outcome.cpp:38` prints the internal error.
  - The five `llvm_unreachable` sites are live under assertions.
- **D122**, every clause:
  - `FieldReach` has `HeldBuffer` (`spec/Grades/Grade.idr:203`,
    `:212-260`; in flight; `lib/IR/Grades.cpp:220-227`).
  - `promisedClaim` is `Self` for every in-place type
    (`lib/IR/Types.cpp:223-225`).
  - `bufferClaim = idr::Unique::Self`
    (`lib/Transforms/Bufferize/Releases.cpp:59`).
  - A constructor's cell claims through its buffers
    (`include/idr/Analysis/Ownership/Local.h:52-58`,
    `lib/IR/Families/Family.cpp:296-315`).
  - A held buffer is written in place under the claim
    (`Releases.cpp:221-237`).
  - The eight C185 programs expect `compile: exit 0` (measured, e.g.
    `tests/linarray-records/expected:1`, `tests/vec-pop-then-push/expected:1`).
  - `boundaryAsks` is the one reader (`lib/Transforms/InPlace/Rule.cpp:132-138`).
- **D123** (settles D57's union; L14x builds on it):
  - The union-find unites a matched right side with the root's class
    (`lib/Transforms/EGraph/Rules.cpp:155-190`).
  - The rebuild restores congruence after each round
    (`Nodes.cpp:463-583`), and the facts meet (`:305-321`).
  - Extraction is by cost, an op one and a constant none
    (`Elaborate.cpp:59-107`).
  - The budget is `nodesPerOp` (`Build.cpp:82`).
  - The interim is gone (measured: `replacedBy` and `ownClass` give 0).
- **D124**, apart from the two rows above:
  - `idr.carrier` is declared at `spec/Lifetimes/Declarations.idr:638-645`
    (in flight) and implemented at `lib/IR/Lifetimes/Loans.cpp:32-44`.
  - The escape check uses `ViewLikeOpInterface` and `getAliasingValues`
    (`include/idr/IR/Lifetimes/Loans.h:92`, `:100`; `Loans.cpp:103-140`)
    and runs in `verify::function` (`lib/IR/Verify/Program.cpp:205-206`).
  - `shareIntoCarriers` and `readBare` give 0 hits (measured).
  - No scoped memory space was built (measured).
- **D125**:
  - The flat tree and its decoder are
    `compiler/checker/src/Idris/Syntax/Tree.idr:1-16`, which `Desugar`
    does not import (measured).
  - There is no interval join, row per clause or binder field
    (measured).

## Superseded

- **D84, D86, D87**: by D107. No sparse tensor library and no bitcode
  engine (measured: `git grep -i -l 'sparse_tensor|SparseTensor|sparsif|eqsat'`
  over `compiler libs foreign runtime tools` finds 0).
- **D85**: by D106 and D107.
- **D97**: by D107.
- **D91**: its C++ half by D114, its toolchain half by D115.
- **D112's C++ half**: by D114 (row D112.4).

No row is Open-owner. §4's one open question (C262, a tail call's result
layout) is a coordinator decision outside this range.

## Count

64 rulings, 77 rows.

| Verdict | Rows | Which |
| --- | --- | --- |
| Done | 55 | |
| Superseded | 7 | |
| Partial | 8 | D68, D112.1, D112.2, D121, D124 frame case, D124 tests, D126, the measurements |
| Missing | 7 | D127.1, .2, .4, .5; D128.1, .2, .3 |
| Regressed | 0 | |
| Open-owner | 0 | |

Of the Missing rows, five are in flight. D127.4 waits on the coordinator,
and D128.3 on L16 once C257's walk and Covers' induction land.

## Seen outside the range

- D60: recheck 3's three findings are fixed:
  - `proposals/0009-typed-apl/README.md:328-339`;
  - one `extentOf` reading (`Translate/Types.idr:145-158`);
  - static copies at `lib/IR/Families/Substitute.cpp:175-226`.
- D57: settled by D123, and the engine is in at HEAD (the D123 row).
- L16dz's two refusals of valid programs (`Compose`, `Ord (Either a b)`
  through a constraint pair) are still queued
  (`handoffs/L16-queue.md`, "From L16dz"). Both are gaps in the growth
  model.
- `.toolchain/llvm-project` is checked out at 7208ba24c, while
  `toolchain.lock.json:5` pins 416f328b. It is a local cache; whether the
  bootstrap uses it was not checked.
- `lib/Transforms/Bufferize/Linear.cpp:13` still calls `idr.lin.cast` the
  grade cast. This is wording only.
