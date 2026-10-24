<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Recheck 6: the owner's rulings D65 to D131 against the tree

HEAD was 9f4889dd at start and f4e6f252 at finish. Between them:
- e72a024f (L12v) touches `lib/Transforms/Bufferize/Linear.cpp` only;
- 13b0e15e records C280, and e518e35c records C281, which amends C257's
  route to D128.3 (below);
- 29153f20 (L16em) deletes the frontend's `Acyclic` termination
  (`Translate/Choices.idr`, `Programs.idr`, `State.idr`, `Term.idr`, Emit);
- 2d7ee52d (L11z, C279) touches the driver, the pipeline and tests;
- d093dbfb (L17bc) rewrites the checker's case-tree scrutinee types and
  adds `Kplus` to the checker's vocabulary;
- ada7d302 widens D111 in place (the owner, 2026-10-22) and adds recheck
  6's D1 to D64 report; 3beee5fd adds its C131 to C279 report;
- f7271225 (L03aa) touches the specification's package list, `big.small`
  and the manifest; b2a2c4ae is the queue;
- 258be23d (L06j) rewrites `upstream/27-one-shot-tensor-like-copy`;
  1ab74a9d (L16en) touches Emit and the grade's specification;
  80a2ec31 records C282; f4e6f252 (L13x) touches `IR/ValueFacts.cpp`;
- 1f998972, b7302a89 and 5382e28b add recheck 6's other reports and
  amend C7, C74 and C158; a3e2599d is the queue.

Every cited line in the files those commits touch was read again at
f4e6f252: the frontend's internal errors in `Choices.idr` and
`State.idr` (same lines), the checker (`CaseBuilder.idr`'s
`shuffleVars` moved to `:1031-1033`; its "Delay pattern match" internal
error is gone, so D112.2's count is 55, not 56), the manifest (67 lines),
`Linear.cpp`, `Emit/Index.idr` (the sum node moved to `:210`),
`IR/ValueFacts.cpp` (`:192-234`), `spec/Grades/Grade.idr` (same lines),
`PINS.md` and `upstream/` (70 of 70 carried patches still recorded), and
the proposal (C205's and C218's amendments now at `:5275` and `:5368`,
§4 at `:5531`). One verdict moved inside its row: D131's
frontend half no longer waits on the checker's vocabulary (`Kplus` is at
`compiler/checker/known/Vocabulary.idr:315`), only on the frontend's own
reading, which is in the working tree. C281 changes how D128.3 is done,
not whether it is done. D111's widening was checked in full (Done). The
counts below were taken again at f4e6f252 and are unchanged but for the
C++'s length (102,065 lines). Nothing was built, typechecked,
generated or run.

Files were read as HEAD's text (`git show <rev>:`, `git grep <rev>`).
Where the working tree already differs, the row says "in flight" and what
is there; the working tree is not otherwise read. Paths are under
`foreign/idr/` unless they start with another top-level directory;
`spec/` is `compiler/spec/IdrisMLIR/Spec/`, and `p0.md` is
`proposals/0000-mlir-native.md` at f4e6f252. Owners are from
`ownership.json`, by longest prefix. *Read* means the cited line was
opened; *measured* gives the command. Recheck 5's "Missing" is this
report's "Not done".

D129, D130 and D131 are checked in full, with C265, C267 (and its
sharpening), C268 where D129 names C262's array case, and C276 where it
closes a D129 refusal. Every row recheck 5 left not Done was read again
in the code. Every Done row was checked for a regression with one grep
or one read line; none regressed. Eleven of recheck 5's not-Done rows
are closed: D127.1, .2, .4, .5; D128.1, .2; D124's frame case and its
tests; D121.

## Not done

### D128.3: the run-time re-check of every request (L16)

- **D128.3, with D68 and D46: "with C257's site walk the run-time
  re-check is deleted"** — **Not done.**
  - `compiler/src/IdrisMLIR/Frontend/Finite.idr:171-172` is `unsound`, an
    internal error; its callers at `:183`, `:185` and `:194` still run.
  - `compiler/src/IdrisMLIR/Proof/Covers.idr:99`: "The induction is not
    yet whole, so the run-time re-check stays", followed by the five open
    steps. (read)
  - What landed: C257's obligation 2 and D128's walk (cc71ed8b, L16ee).
    C281 (e518e35c, `p0.md:2672`, for the owner's review) replaces the
    rest of C257's threading: the growth model records each decided
    request in its tree and the translation folds it, so no request can
    miss its site; with the lemma's induction over the model's walk this
    deletes `Finite.unsound`, `heightWithin`, `sizedWithin` and
    `Types.boundsHold`.
  - **Owner:** L16 (`Frontend/`, `Proof/`).
  - **Waits on:** C281's lane, not yet dispatched; before it, the
    coordinator revises `audits/p0/verify/handoffs/L16-threading-design.md`
    to C281 (its obligations 1 to 7 are C257's threading). Its item 8
    stops for the owner if the induction needs the normaliser idempotent
    beyond D68.
  - **Remaining:** C281's tree of decided requests, the lemma's induction
    over Covers' open steps (`Covers.idr:99-176`), then delete `unsound`
    and its three callers, `heightWithin`, `sizedWithin` and
    `Types.boundsHold` (`Frontend/Translate/Types.idr:601-606`, called at
    `:906`).

### D129.3: the array case of a tail call's result layout (L18x in flight)

- **D129: "C262's array result is the same rule's array case"** — **Not
  done**, in flight.
  - `lib/Transforms/Specialize/Open.cpp:111-115`: `openResult` returns
    any type that is not a data type unchanged (`if (!data) return
    type;`), so a tail call whose array result's element re-packs gets no
    copy that returns the caller's element layout. (read)
  - The queue's L04v item records that such a tail is an internal error
    before bufferization today (`L16-queue.md`, "From L04v"). C262's own
    rule (every result axis `?`, its size in `#idr.extents`) stands, and
    D129 leaves it unchanged.
  - In flight: L18x ("Dispatched after INT-23"). The working tree changes
    `Specialize/Consumer.cpp`, `Open.cpp`, `Requests.cpp` and
    `Specialize.h` (an array returned open where its element is), and
    adds `tests/array-tail-element-open/`.
  - **Owner:** L18. **Remaining:** land L18x. After it, the internal error
    has no program that reaches it.

### D131.2: the frontend reads base's `plus` on `Nat` (L16, in flight)

- **D131: a sum "read off base's `plus` on `Nat` by identity, as `IO` is
  recognised"** — **Not done**, in flight.
  - At HEAD the frontend can write a sum: `compiler/src/IdrisMLIR/Types.idr:126`
    has `ISum (List1 (Nat, Nat)) Nat`, `:212-216` is `sumOf`, and
    `Emit/Index.idr:210` writes the sum node. (read)
  - Nothing reads `plus`: `git grep -n -E 'plusTerm|natPlus' f4e6f252 --
    compiler/src` finds only the definition (`Types.idr:233`) and
    substitution (`Term.idr:527`). (measured)
  - The checker's name landed: `compiler/checker/known/Vocabulary.idr:315`
    `("Kplus", "plus")` (d093dbfb).
  - In flight in the working tree: `Translate/Types.idr` reads `plus` at
    the address the boundary read (`Reading.natPlus`, never by name) into
    `plusTerm`; `Translate/State.idr` and `Boundary.idr` add `natPlus` to
    the reading; and `tests/index-nat-plus/` is new.
  - Until it lands, `tests/vect`'s length is opaque in the frontend's
    output, and its tail call is kept by C267's open result rather than
    "with no mechanism of its own".
  - Also read: the specification's sum is normal by its type
    (`spec/Families/Terms.idr:87`, `TSum` with an erased `LTE 2
    (occurrences times)`). The frontend's `ISum` is normal only by its
    smart constructors (`sumOf`, `plusTerm`, `scaledTerm`): a
    one-level-once sum and a repeated level are representable. See "Seen
    outside the range".
  - **Owner:** L16. **Remaining:** land the reading, with
    `tests/index-nat-plus` and `tests/vect` stating the closed copies.

## Partial

### D126: the type-dispatch cull (rounds 2b-S, 2c-T, 3-A and 3-B landed)

- **D126** — **Partial.** (read, measured)
- **The counts at f4e6f252**, each against recheck 5's commit 7aefe545
  with the same command:
  - Lines with `isa<` or `dyn_cast<` outside `Generated/`: 608 against
    603 (`git grep -n -E '(isa|dyn_cast)<' <rev> -- foreign/idr
    ':!foreign/idr/include/idr/IR/Generated/*' | wc -l`).
  - Lines with any of `isa`, `dyn_cast` or `cast` (PCRE, comment lines
    excluded): 966 against 960.
  - C++ in `.cpp` and `.h` outside `Generated/`: 102,065 lines against
    95,820. So the density fell from 6.3 to 6.0 per thousand lines while
    the C++ grew by 6,200 lines.
  - Ladders of three or more tests of one subject within 30 lines: 14,
    found by a script over HEAD's text. All are over interfaces or
    upstream classes, e.g. `include/idr/Analysis/Ownership/Facts.h:267`,
    `lib/IR/Lifetimes/Verify.cpp:198`, `lib/IR/Flow.cpp:32`.
  - One subject tested against two or more concrete classes of ours
    within 30 lines: three sites, listed below.
- **Done since recheck 5:**
  - Every site recheck 5 named as in flight under 2b-S:
    - `Defunctionalize/Convert.cpp` and `Analysis/LabelSites.cpp:270-290`
      fold `closureHoldingOf`'s sum with `match`;
    - `Conversion/Lower/Statics.cpp` reads no `"site"` attribute;
    - `Strings.cpp` has no `is_same_v<OpT, StrPackOp>`;
    - `IR/Lifetimes/Ops.cpp:57-87` and `Proof.cpp:129` ask
      `PerLevelOpInterface`, `CursorBinderOpInterface`,
      `LifetimeUseOpInterface` and `LifetimePutOpInterface`.
  - Every item round 2c queued:
    - `ValueFactsTypeInterface::getRunTimeWords`, declared at
      `spec/Core/Types.idr:365` and answered per type
      (`lib/IR/ValueFacts.cpp:192-234`, `Types.cpp:289`, `Grades.cpp:140`);
    - `Layout/Components.cpp`'s `wordsOf` and `Lower/Functions.cpp`'s
      `DestType` test are gone;
    - `framingOf` is gone (`ProgramGraph::frame()`, cb5cd6fb);
    - `Support/Match.h:1-12` now says what each type is "is a method of a
      type interface the specification declares";
    - `Accounts.cpp:67`, `Func/Call.cpp:281` and `EGraph/Build.cpp:63`
      read the tail through `Tail.h`'s `tailCallOf` and `lastActOf`.
  - Round 3-B's follow-ups: `lifetimes::kindOf` takes
    `TypedValue<LifetimeType>` (`include/idr/IR/Lifetimes.h:192`), and
    the `idsOf` and `groupOf` casts are gone (measured).
- **Not done:**
  - Two-way tests over concrete classes of ours:
    - `lib/Conversion/Strings.cpp:78-86` (`writtenOnly`): `isa<CountDropOp>`,
      then `dyn_cast<IoPutStrOp>` on each user. Owner L13.
    - `lib/IR/Families/Repacks.cpp:165-174` (`namedBy`): `SelfType`, then
      `DataType`, on one field type; `IndexedTypeInterface` already
      answers a self type's member (`getPositionalMember`). Owner L04.
    - `lib/Transforms/Specialize/Open.cpp:377-406`: the downward walk
      tests `CallOp`, then the `ResultCarriesOperand` trait, then
      `DataReindexOp`, then `InferTypeOpInterface`, on each user. Owner
      L18; this file is in flight under L18x.
  - Compile-time branches on our ops' identity (`if constexpr
    (std::is_same_v<...>)`), which D126 rules out as a templated visitor:
    - `lib/Transforms/Columns/ArrayOps.cpp:45` and
      `lib/Transforms/StructureLoops/Linalg.cpp:151`
      (`ArrayScanLastOp`), owner L12;
    - `include/idr/IR/IdrDialect.h:185-187` (`ProgramOp` or `ModuleOp`),
      owner L03.
    - The queue already routes these (b2a2c4ae, "From recheck 6 (D1 to
      D64)", as D7's branches).
  - Ladders over upstream attributes, which D126 answers with an
    interface of ours attached to upstream's classes, as `ValueFacts.cpp`
    already does for builtin types:
    - `lib/IR/Constants.cpp:245-262` (`staticFormOf`: our interface, then
      `StringAttr`, `IntegerAttr`/`FloatAttr`, `ub::PoisonAttr`), owner
      L13;
    - `lib/Transforms/EGraph/Values.cpp:509-520` (`heldFacts`: integer,
      real, string, big, tried in turn), owner L14.
    - The queue's "From L14y" item names the form:
      `ConstantAttrInterface::getFoldValue`, a closed sum, attached to the
      builtin string, integer and float attributes, declared in the
      specification (L03).
- **Remaining:** each named test becomes a method the specification
  declares, or a typed walk. **Waits on:** L18x for `Open.cpp`, and on
  the running specification lanes (L16en, L01s) for L03's declarations.

### D112.1: the frontend's internal errors (L16)

- **D112.1** — **Partial.** (read, measured)
  - 17 call sites, against recheck 5's 18. Measured with `git grep -n -P
    '(?<![A-Za-z_])internal [a-zA-Z.]+ |InternalError \(|unsound [a-z]'
    f4e6f252 -- 'compiler/src/*.idr'`, excluding comments, the two
    definitions (`Errors.idr:220`, `Finite.idr:172`), the driver's
    predicate (`Driver.idr:230`) and the six file-write failures.
  - Kept with its reason: `Translate/Keys.idr:1149`, two links sharing a
    key by a 64-bit hash collision.
  - D128.3's re-check: `Frontend/Finite.idr:183`, `:185`, `:194`.
  - Waiting on the next threading lane, under C281 (L16ek's note in the
    queue):
    - `Translate/Terms.idr:696`, `:1736`, `:1833` ("the values an
      implementation closes over are gone": `classifyKeys` returns what
      it read);
    - `Cases.idr:954` and `Choices.idr:567` (`request`'s signature tied to
      the kinds requested, C234);
    - `Shapes.idr:300` (`InstanceSig` keeps the binders it admitted).
  - Other sites:
    - `Terms.idr:802` and `:1636`: a Core type read as no suspension's or
      no function's, which C228 (b) and (c) close by `Types.coreTypeIn`
      returning the Core and Idris types together.
    - `Finite.idr:224`: an instance table whose lookup returns evidence.
      Base's `SortedMap` states no lookup-after-insert facts
      (threading design, "Outside the threading").
    - `Program.idr:85`: Emit's `Unfit`, which a term indexed by its type
      makes impossible (queue, "From L16dc").
    - `Growth/Graph.idr:2782`, `:2784`: a visit's reading that misses its
      node.
    - `Translate/State.idr:1408`: `missedEntry`, a reading not indexed by
      what `main` reaches.
  - **Remaining:** each becomes the type named, or a refusal where a
    program can reach it.

### D112.2: the checker's internal errors (L17)

- **D112.2** — **Partial.** (read, measured)
  - 55 `throw (InternalError …)` sites, against 71 at recheck 5. Measured
    with `git grep -n InternalError <rev> -- 'compiler/checker/*.idr'`,
    comment lines dropped, keeping lines that throw or build `Left
    (InternalError …)`: 71 at 7aefe545, 56 at 9f4889dd, 55 at f4e6f252.
  - **Closed** (1c8e1d7d, L17bb; d093dbfb, L17bc):
    - six of `Context`'s seven "stored term" throws: each `Root` now holds
      its locations and scope, proved where the columns are laid;
    - `ProcessDef`'s "Can't happen" pair and "With abstraction failure #1"
      to "#4";
    - `Hash`'s throw;
    - `%start`, now refused as `unsupported` while desugaring
      (`Idris/Desugar.idr:1440`, `tests/checker-start-refused`);
    - `CaseBuilder`'s Delay match.
  - **Kept with a stated reason:**
    - `Core/Context.idr:733` (`sealedRoots`): "decided rather than proved
      because the arena's columns are `mlir-array`'s arrays, of which a
      type knows nothing element by element" (`:723-728`).
    - 16 host or environment facts: `Core/Binary.idr:317`, `:410`, `:528`;
      `Binary/Prims.idr:49`, `:56`, `:66`; `Context.idr:2494`, `:2501`;
      `Directory.idr:36`, `:161`; `Idris/Package.idr:553`, `:558`,
      `:574`, `:586`, `:597`, `:635`.
  - **Not done: 38 impossibilities written as text, not types.**
    - `Core/Case/Util.idr:27`; `Core/LinearCheck.idr:570`, `:638`, `:652`,
      `:654`; `Termination/CallGraph.idr:285`; `Core/TTC.idr:133`,
      `:1270`.
    - `Core/Unify.idr:646` ("Can't happen: no definition"; L17bb says the
      re-read of the mutable context stays because backtracking drops
      staged entries, which the message does not say) and `:1787`.
    - `Idris/Desugar.idr:893`; `Elab/Implementation.idr:221`;
      `Package.idr:746`; `ProcessIdr.idr:172`;
      `Libraries/Utils/Shunting.idr:72`, `:76`, `:131`;
      `Parser/Source.idr:53`, `:55`.
    - `TTImp/Elab/Check.idr:231`; `Elab/Local.idr:198`; `Elab/Term.idr:261`;
      `TTImp/ProcessBuiltin.idr:188`, `:190`, `:254`, `:275`, `:278`;
      `ProcessDef.idr:609`; `ProcessRecord.idr:64`, `:154`, `:180`,
      `:190`, `:202`, `:211`; `Reflect.idr:638`, `:640`;
      `TTImp/TTImp/TTC.idr:413`; `WithClause.idr:25`.
    - `ProcessBuiltin`'s five are reached from a user's `%builtin` pragma
      on a constructor of the wrong shape (`:186-190`). Like `%start`,
      each is a refusal written as an internal error. (read)
    - Whether `Reflect`'s two are reachable depends on elaborator
      reflection being admitted. That was not checked (conjecture).
  - **Remaining:** refuse the user-reachable ones (`ProcessBuiltin`),
    give `Unify.idr:646` its run-time reason or a type, and turn the rest
    into the types that make each case impossible (a well-formed
    weakening, a with-clause head, a record's telescope). Recheck 5
    counted only 15 impossibilities, the ones whose text says so.
    D112's rule ("one stays only for a fact not known until run time,
    and says so") covers all 38.
  - **Owner:** L17. **Waits on:** L17bd, now writing
    `compiler/checker/src/Core/Unify.idr` and `TTImp/Elab/` in the working
    tree.

### D68: the stated trust in the host's normaliser (L16)

- **D68** — **Partial**, unchanged since recheck 3 (not a regression).
  - The trust is stated once, in our checker:
    `compiler/checker/src/Idris/Host.idr:28-37` (`Reduces`, `Reduct`,
    `mappedReduces`).
  - Its readers' soundness is not proved whole (`Proof/Covers.idr:99`).
  - The run-time witness stays (`Frontend/Finite.idr:171-194`). (read)
  - **Remaining:** D128.3's row (C281, the lemma's induction, the
    deletion).

### The measurements the rulings order (INT, the owner's machine)

- **D78, D95, D100, D108, D115** — **Partial**, unchanged. Only the
  measurement is left; each needs the LLVM build, which D111 puts on the
  owner's other machine.
  - D78: today's stack cells against cells in a lifetime.
  - D95: the gain of a per-level lifetime.
  - D100: the loss in the built output with nothing run at the
    upstream-only points.
  - D108: `nodesPerOp = 64`, which `spec/Pipeline/Pipeline.idr:296-304`
    still calls "Not yet measured".
  - D115: the price of assertions on, against the same commit with them
    off. (read)

## Done

Each was read (or measured, where said) at f4e6f252.

- **D127**, every clause (closes recheck 5's four not-Done rows):
  - **.1** The graph holds a string's bytes, a Double's bits and a big
    past the small range as its own values (`Text`, `Real`, `Big`; the
    sum `Constant`, `include/idr/Transforms/EGraph/Engine.h:184-199`;
    `node::Known`, `:288-294`). They are computed by the runtime's
    functions through the one fold (`lib/Transforms/EGraph/Values.cpp:1-27`).
    `node::Held` (`Engine.h:275-282`) keeps an input op's own attribute,
    read once into the graph's values (`heldFacts`, `Values.cpp:509-520`)
    and placed again unchanged. It makes no attribute and holds the data
    constants the graph never computes (C218 as D127 amends it).
  - **.2** `IR/Fold.h:13-22`: one fold over two domains (the concept
    `Where`, `:172`). `InAttributes` (`:189`, `static_assert` at `:227`)
    is MLIR's fold; `InGraph` (`Values.cpp:180`, `static_assert` at
    `:261`) is the graph's.
  - **.3** `NeverFolded` is a list in the specification
    (`spec/Core/Admitted.idr:60`; `spec/Ops/Shapes.idr:410-454`), checked
    disjoint from `ComputedOnDoubles` when the compiler is built
    (`EGraph/Rules.cpp:75`). A NaN is no constant (`Fold.h:122-124`,
    `ieeeOn`).
  - **.4** C205 and C218 carry "*Amended by D127*" (`p0.md:5275`,
    `:5368`).
  - **.5** `lib/Conversion/Lower.cpp:221-229` says the e-graph computed
    before the lowering what an idr op's fold computes, "each placed
    where its constant op stands", and `:230` folds nothing.
    C264(c)'s residual (a computed string or big at a call argument
    stays applied) is C264's row in the decisions report.
- **D128.1** (cc71ed8b, L16ee):
  - A settled implementation is walked as written:
    `Translate/Terms.idr:1090-1095` (`implementationAt` → `settle`),
    through `applyHead` (`:960`), as `Growth/Sites.idr:1904` walks it.
  - `lambdasApplied` is left in 9 lines (`git grep -n -w lambdasApplied
    f4e6f252 -- compiler/src`), all reading roots, types and keys:
    - `Growth/Template.idr:2268` (`dictionaryRoot`);
    - `Translate/Terms.idr:552` (`formType`);
    - `Translate/Closed.idr:929`, `:983` (the compile-time reducer);
    - the definition `Closed.idr:352-353` and doc lines.
- **D128.2**: `Terms.idr:960-990`. A runtime argument is "bound by a
  `let` at the binder's quantity" (`asValue`, `:983`), and a variable
  given to a binder of quantity many "is bound once".
- **D128.4**: keys read through `host.normaliseHoles`
  (`Translate/Closed.idr:353`, `:361`).
- **D129.1**, the specializer's half for data results (39a38d24, L18y;
  8b218c36, L04x):
  - A tail lost to a layout is `TailStanding::LostToLayout`
    (`lib/Transforms/Specialize/Requests.cpp:186-193`).
  - It asks each result its caller lays out otherwise `AtOpen`
    (`Consumer.cpp:268-282`).
  - The copy's result is the callee's marked open at the caller's grade
    (`signatureOf`, `:300-338`; `Open.cpp:111-115`).
  - A non-tail call asks every result `AsGiven` (`:270-271`).
  - The axis is one mark of two, so "at most doubles", with no budget
    (`include/idr/Transforms/Specialize.h:17-29`).
  - C267 and its sharpening: a result no copy could give closed is marked
    open in its owner's type, once per function (`Open.cpp:1-36`,
    `openResults` at `:967`, scheduled at `Optimize/Waves.cpp:98`). So
    nothing is refused.
  - Tests (unrun): `tests/open-copy-keeps-refined-index`,
    `closed-result-opens-for-tail`, `class-copy-keeps-opaque-tail` and
    `sum-index-closed-tail`, each stating L19u's `tail-calls` and
    `results-as-given` (`harness/Properties.idr:182`, `:185`).
  - The queue holds two fixes to those tests, for L19 ("From L18z", "From
    L14u").
- **D129.2**, the verifier's half (0642ef67, L10z; 1bce116e, C265):
  - `lib/IR/Func/Call.cpp:281-289` runs `tail::verifyLayouts` on every
    tail call, beside the given-back results.
  - `lib/IR/Tail.cpp:378-394` reports a residual mismatch as an internal
    error.
  - A tail lost to a re-pack is `lostToRepack` (`:115-123`), once layouts
    agree (`:267-269`). They agree from Graded on, by the specification's
    `StageTailLayouts` (`spec/Pipeline/Stage.idr:104`, `:211-214`).
  - LLVM's `musttail` stays the last check
    (`lib/Conversion/Lower/Functions.cpp:226-227`).
- **D130** (8b218c36, L04x):
  - `LayoutMark = ByIndices | Open` (`spec/Families/Layout.idr:40`), a
    parameter of `DataType` (`spec/Families/Types.idr:170`;
    `lib/IR/Types.cpp:181`, `:200`). It is printed and parsed
    (`Families/DataSyntax.cpp:35`, `:76-77`) and carried in bytecode
    (`Families/Bytecode.cpp:31`).
  - The layout classes read it (`IR/Layout/Classes.cpp:242`,
    `:281-284`), and so does the layout comparison
    (`Layout/Components.cpp:159-171`).
  - Substitution keeps it (`Families/Substitute.cpp:168`).
  - Refinement reads indices alone (`Families/ScopeWalk.cpp:252-264`), so
    a match on an open value still refines and prunes.
  - The open copy returns its result marked open (`Open.cpp:115`).
- **D131.1**, the index language (8b218c36, L04x):
  - `TSum` is normal by its type (`spec/Families/Terms.idr:82-88`), and
    so is `plus` (`:102-119`).
  - The C++ holds it as `TermKind::Sum` (`IR/Families/Terms.cpp:258`).
  - Substitution normalizes a sum (`Substitute.cpp:89-101`).
  - Unification learns nothing of a sum's parts and finds no clash in
    one (`Unify.cpp:165-172`).
- **D124's frame case** (closes recheck 5's row; 80f6e719, L05x, C266):
  - A stretch is cut at every op no loan region may hold, and each side
    is lent under its own view (`lib/Transforms/Lifetimes/Lend.cpp:1-20`,
    `lendPart` at `:285-420`).
  - An alias read across a cut is made again from that side's loan
    (`remakeAlias`).
  - The two residual cases are always-on internal errors (`:327-332`,
    `brokenAt`).
  - The shares left (`:521`, `:544`) give a reference to a value that is
    no loan: a tensor taken over at the bare grade, or an alias that
    leaves the loan. So no loan changes a count. (read)
- **D124's tests** (closes recheck 5's row; 7cf10ff2, L19z;
  80f6e719), all unrun:
  - `tests/loan-escapes-refused/loan-escapes-refused.mlir`: one module
    lends and verifies; four are refused, each at the op that takes the
    alias out (out of the region, returned, stored, adopted), with the
    note at the loan.
  - `tests/loan-across-frame` and `tests/loan-stored-in-cell`.
  - The check is `State::loans` (`lib/IR/Lifetimes/Loans.cpp:181-215`).
- **D121** (closes recheck 5's row; 230852fe, L06h; f3f857b5, L06i):
  - The slow elaboration is two upstream bugs, both carried: 109 and
    `upstream/115-size-change-as-pattern-doubling`.
  - `audits/p0/design/idris-linear-check.md:5-11` says it is resolved,
    and `:113` strikes §5.
  - Every `upstream/*/` with a patch has its README, its
    `tests/upstream-<name>` and a PINS entry: 70 of 70 (measured, a loop
    over `upstream/*/` at f4e6f252).
  - The Idris rows run to 118 (`upstream/README.md:179-183`).
  - Rerunning `tools/bootstrap.sh idris` so the installed stock Idris
    carries 115 to 118 is INT's (queue, "From L06h").
- **D65**: `runtime/Platform/Posix/Cgroups.cpp:281-300` takes the lowest
  `memory.max` and `memory.swap.max` up the tree.
- **D66**: `runtime/Start/Runner.cpp:136` commits the stack and the
  signal stack before the thread runs.
- **D67**:
  - `foreign/idr/generated.manifest` has 67 lines: the specification's
    hash, the generator's and one line per file.
  - `make check` compares them (`Makefile:376`ff, `spec-current`).
- **D69**: `proposals/0011-data-oriented-frontend.md:413-414` (O6, O7
  as D69 brings them in).
- **D70**: `data Unique = None | Self | Deep` (`spec/Grades/Hold.idr:34`).
- **D71**: `unsupported (uniqueness)` at
  `lib/Transforms/InPlace/InPlace.cpp:62`.
- **D72**: `include/idr/Analysis/Ownership/Facts.h:34-35`.
- **D73**: `lib/Analysis/Ownership/Borrows.cpp:18`, `:348`: a part of the
  caller's parameter is a view while the parameter is one.
- **D74**: `lib/Transforms/Counting/Placement.cpp:58-61` and
  `Bound.cpp:215`.
- **D75**: `lib/Transforms/Optimize/Contify.cpp:6-12` promises nothing.
- **D76**: no `idr.cont` or `ContType` (measured: 0 hits in `foreign`,
  `compiler`, `runtime` and `tests`).
- **D77**: `lib/Driver/LinkRuntime.cpp:75-80` strips the probes, and
  `runtime/CMakeLists.txt:154` keeps stack-clash protection.
- **D78**, code: no stack bit in the cell header (`runtime/Rc/Rc.h`, read).
  The `idris_rt_stack_*` hits are the native stack's plan and a room's
  chunks, not a counted cell.
- **D79**: `lib/Transforms/InPlace/UniqueResults.cpp:322`
  (`lendReads`), and `tests/in-place-borrowed-read-ends`.
- **D80**: `runtime/End/End.cpp:291` (`idris_rt_crash_at`).
- **D81**: `runtime/Platform/Posix/Process.cpp:63-70` raises `SIGPIPE`.
- **D82**: `PINS.md:579-580` (`upstream/65-early-exits`, #166688).
- **D83**:
  - No test expects "megamorphic" (measured: 0).
  - The category is `spec/Core/Rules.idr:25`.
- **D88, D90**:
  - `data Uses = Once | Many` (`spec/Grades/Grade.idr:25`), and
    `data Hold = Counted Unique | Scoped Unique | Static`
    (`spec/Grades/Hold.idr:41`).
  - The deleted names give 0 hits (measured).
- **D89**: copies keyed by hold (`lib/Transforms/Specialize/Specialization.cpp:121`),
  and the marker's test (`runtime/Rc/Rc.h:79-82`).
- **D92**:
  - `proposals/0020-rust-interop.md:5-8` is amended.
  - The 152 `.rs` files are the sources lane's snapshots, 151 under
    `sources/code` and one under `sources/docs` (measured), not our
    code.
- **D93**: `LifetimeKind = View | Room | Cursor | Home Nat`
  (`spec/Lifetimes/Kind.idr:25`).
- **D94**: `Amount`, whose `Unbounded` carries `Not (kind = Room)`
  (`spec/Functions/Parameters.idr:63-67`).
- **D95**, code: `lib/Transforms/Tail/Split.cpp:127` packs, and
  `lib/Conversion/Lower/Packages.cpp:62` and `:97` lower the pack and
  the unpack.
- **D96**: `lib/IR/Tail.cpp:275-276`: no lifetime is handed over at a
  tail call.
- **D98**:
  - No greedy driver, canonicalizer or CSE (measured: 0 hits for recheck
    5's pattern in `foreign/idr` and `compiler/spec`).
  - The fold clause is D127's. On the owner question queued about the
    two folders, see "Seen outside the range".
- **D99**: upstream's passes are listed by name and made with their
  defaults (`spec/Pipeline/Pipeline.idr:45-69`).
- **D100**, code: no `canonical` or `cse` in `lib/Transforms/Pipeline.cpp`
  (measured: 0).
- **D101**: `compiler/checker/src/Libraries/Text/Bounded.idr:77-78`;
  `isIrrelevant` gives 0 hits.
- **D102**: `spec/Core/Rewrite.idr:57` (`Clean`).
- **D103**: `spec/Arrays/Memory.idr:484-486`, implemented at
  `lib/IR/OpsArrayFusion.cpp:334`.
- **D104**:
  - `libs/mlir-array/Array/Core.idr:400-409` (`withFrozen`) freezes and
    thaws in place. `thaw` of a shared array copies (`:392-393`), as it
    must.
  - `Fail` hands the input back (`libs/mlir-array/Linear/Parser.idr:36`).
- **D105**: `spec/Control/Matches.idr:8-11` (a case binds the scrutinee
  refined).
- **D106**: `spec/Core/Rewrite.idr:6` ("Every rule is one-way").
- **D107**: the checker's union-find (`compiler/checker/src/Core/UnifyState.idr:13`,
  `:112`).
- **D108**, the admission: one ledger (`lib/Transforms/EGraph/Simplify.cpp:66`,
  `:81`), and the budget `nodesPerOp × ops` (`Build.cpp:80`).
- **D109**: no optimization module in `compiler/src` (measured: `git
  ls-tree` finds no optimizer, inliner or simplifier).
- **D110**: `DataType::getFieldReach` (`lib/IR/Types.cpp:244`), and
  `SelfType`'s (`:250`).
- **D111**, with its widening (`p0.md:1653-1669`, ada7d302):
  - `.toolchain/` holds no LLVM build. `.toolchain/build/typecheck-llvm/bin`
    holds only `llvm-tblgen`, `llvm-min-tblgen`, `mlir-tblgen` and
    `mlir-linalg-ods-yaml-gen`, and `.toolchain/build/llvm-project` is
    a source tree (measured, `ls`).
  - The lanes build the Idris half on exports, e.g. L17bb's "make checker
    and make frontend exit 0" (1c8e1d7d).
- **D113**:
  - `shuffleVars` (`compiler/checker/src/Core/Case/CaseBuilder.idr:1031-1033`)
    and `updateLocal` (`Core/Normalise/Eval.idr:252-256`) stand.
  - The README section is gone (measured).
- **D114**: 88 `assert(` lines and 13 `reportFatalInternalError` lines in
  our C++ (measured).
  - The local checkouts' clang has no `contract_assert` (measured:
    `.toolchain/llvm-project` at 7208ba24c, and the bootstrap's copy).
  - The pinned 416f328b is not in the local checkout, so the pin itself
    was not checked.
- **D115**:
  - `tools/bootstrap.sh:926` passes `-DLLVM_ENABLE_ASSERTIONS=ON`.
  - `foreign/idr/CMakeLists.txt:21-45` strips `NDEBUG` from our units.
  - `runtime/CMakeLists.txt:172` keeps it for the runtime's profile.
- **D116**: `Makefile:42`, `:336` (`self`, `self-spec`) and
  `tools/self.sh`.
- **D117**: `compiler/` holds `checker`, `spec` and `src`, and no
  `idris` (measured).
- **D118**:
  - No `tools/extract-idris.sh` and no fork in `PINS.md` (measured: 0
    and 0).
  - The checker's copies of stock-Idris bugs 117 and 118 are being fixed
    in it by L17bd, in flight: `Core/Unify.idr` and `TTImp/Elab/Case.idr`
    in the working tree, and two untracked `tests/checker-*`.
- **D119**:
  - No `TokType` or `ActType` in code. The two hits are the README's
    account of what upstream did (`compiler/checker/README.md:417`,
    `:420`).
  - No escape hatch in the parser files (measured: 0).
- **D120**: `foreign/idr/CMakeLists.txt:40-46`: only the typecheck build
  accepts an LLVM without assertions.
- **C226, as D115 amends it**: 13 `llvm_unreachable` sites, each live
  under assertions (measured).
- **D122**:
  - `FieldReach` has `HeldBuffer` (`spec/Grades/Grade.idr:203`, `:217`).
  - `promisedClaim` is at `lib/IR/Types.cpp:237`, and `bufferClaim =
    Unique::Self` at `lib/Transforms/Bufferize/Releases.cpp:59`.
  - `tests/linarray-records` and `tests/vec-pop-then-push` expect
    `compile: exit 0`.
- **D123**:
  - `unite` (`lib/Transforms/EGraph/Nodes.cpp:567`) and `rebuild`
    (`:621`).
  - Extraction is by cost (`Elaborate.cpp:5-13`).
  - `replacedBy` and `ownClass` give 0 hits.
- **D124**, apart from the two rows above:
  - `idr.carrier` is implemented at `lib/IR/Lifetimes/Loans.cpp:40-48`.
  - `shareIntoCarriers` and `readBare` give 0 hits.
  - No scoped memory space (measured: 0).
- **D125**: `Idris/Desugar.idr` does not import `Syntax.Tree`
  (measured: 0).
- **D112.3**:
  - No `assert_total`, `assert_smaller` or `believe_me` in code in
    `compiler/src`, `compiler/spec`, `libs` or `harness`: the six
    `compiler/src` hits are the registry's spellings and refusal texts.
  - In `compiler/checker` only the stated trusts are left:
    - `trusted` at `src/Core/Primitives/Host.idr:28` and
      `src/Idris/Host.idr:109`;
    - the partial primitives, each guarded (`Core/Primitives/Host.idr:142-258`);
    - `host` at `Idris/Host.idr:3618`. (measured)

## Superseded

- **D84, D86, D87**: by D107.
- **D85**: by D106 and D107.
- **D97**: by D107.
- **D91**: its C++ half by D114, its toolchain half by D115.
- **D112.4** (the C++ half): by D114.

No row is open with the owner. §4 reads "Open: none" (`p0.md:5531`).
C267, C276, C277, C278 and C281 are coordinator decisions recorded for
the owner's review, and they bind meanwhile.

## Count

67 rulings, 83 rows. Recheck 5 had 64 rulings in 77 rows. The six new
rows are D129.1 to .3, D130, D131.1 and .2.

| Verdict | Recheck 6 | Recheck 5 | Which |
| --- | --- | --- | --- |
| Done | 68 | 55 | +D127.1, .2, .4, .5; D128.1, .2; D124's frame case and tests; D121; D129.1, .2; D130; D131.1 |
| Superseded | 7 | 7 | |
| Partial | 5 | 8 | D68, D112.1, D112.2, D126, the measurements |
| Not done | 3 | 7 | D128.3; D129.3 (in flight, L18x); D131.2 (in flight, L16) |
| Regressed | 0 | 0 | |
| Open-owner | 0 | 0 | |

## Dispatchable items, by owner

**L16**
1. **D128.3, D68 (with D46): the run-time re-check.**
   - Build C281's tree of decided requests, which the translation folds,
     and prove the lemma's induction over `Proof/Covers.idr:99-176`.
   - Then delete `Frontend/Finite.idr:171-194` (`unsound`, `heightWithin`,
     `sizedWithin`) and `Translate/Types.idr:601-606` (`boundsHold`, and
     its call at `:906`).
   - Waits on the coordinator's revision of
     `handoffs/L16-threading-design.md` to C281. It stops for the owner if
     the induction needs the normaliser idempotent beyond D68.
2. **D131.2: read base's `plus` on `Nat` as a sum** (in flight in the
   working tree). The reading is in `Translate/Types.idr`, `State.idr` and
   `Boundary.idr`, with `tests/index-nat-plus`. Then `tests/vect` keys
   closed copies. Nothing it waits on.
3. **D112.1: 16 internal errors** (`Keys.idr:1149` stays).
   - With the threading lane: `Terms.idr:696`, `:1736`, `:1833`,
     `Cases.idr:954`, `Choices.idr:567` and `Shapes.idr:300`.
   - With C228 (b) and (c): `Terms.idr:802` and `:1636`, through
     `Types.coreTypeIn` returning both types.
   - An instance table with evidence: `Finite.idr:224`.
   - `Program.idr:85`: Emit's `Unfit`.
   - `Growth/Graph.idr:2782`, `:2784`.
   - `State.idr:1408`.
   - `Finite.idr:183`, `:185`, `:194` go with item 1.

**L18**

4. **D129.3: the array case** (in flight, L18x). An array result whose
   element re-packs at a tail call is returned open where its element is
   (`Specialize/Open.cpp:111-115`). Lands with
   `tests/array-tail-element-open`.
5. **D126:** `Specialize/Open.cpp:377-406`, the downward walk's tests of
   `CallOp`, `DataReindexOp` and the trait, each user. Make them an
   interface method or a typed walk. Waits on L18x, which holds the file.

**L13**

6. **D126:** `Conversion/Strings.cpp:78-86`, `writtenOnly`'s
   `CountDropOp` or `IoPutStrOp`. Make it an interface method or a
   declared per-op fact.
7. **D126:** `IR/Constants.cpp:245-262`, `staticFormOf`'s ladder over
   upstream attributes. Use the queued `ConstantAttrInterface` model
   attached to the builtin string, integer and float attributes. Waits on
   L03's declaration.

**L14**

8. **D126:** `Transforms/EGraph/Values.cpp:509-520`, `heldFacts` tries
   four readers in turn. Use the same interface, through `getFoldValue`.
   Waits on L03.

**L04**

9. **D126:** `IR/Families/Repacks.cpp:165-174`, `namedBy`'s `SelfType` or
   `DataType`. Use `IndexedTypeInterface`, which answers a self type's
   member.

**L12, L03**

10. **D126** (already queued as D7's branches by recheck 6's D1 to D64
    report): the `if constexpr (std::is_same_v<...>)` branches.
    - L12: `Columns/ArrayOps.cpp:45` and `StructureLoops/Linalg.cpp:151`.
    - L03: `include/idr/IR/IdrDialect.h:185-187`.
    - L03 also declares item 7's interface model.
    - Waits on L16en and L01s releasing the specification.

**L17**

11. **D112.2: the 38 impossibilities.**
    - First, refuse `TTImp/ProcessBuiltin.idr:188`, `:190`, `:254`,
      `:275`, `:278` as user errors, since a `%builtin` pragma reaches
      them.
    - Give `Core/Unify.idr:646` its run-time reason or a type.
    - Make the rest types (list in D112.2's row).
    - `Context.idr:733` stays as stated, or the arena's columns gain
      element facts.
    - Waits on L17bd, which is writing `Core/Unify.idr` and `TTImp/Elab/`.

**INT** (the owner's machine)

12. **The measurements: D78, D95, D100, D108 and D115.**
    - D108: `nodesPerOp`, at `spec/Pipeline/Pipeline.idr:296-304`.
    - Rerun `tools/bootstrap.sh idris` so the installed stock Idris
      carries 115 to 118 (D121).

**Coordinator**

13. **The threading design revised to C281** (item 1 waits on it; also
    recheck 6's C131 to C279 report).

### Queue items found done (strike from `L16-queue.md`)

- **"D126 round 2c (left by round 2b-T)"**, all four bullets:
  - `getRunTimeWords`, with `wordsOf` and `Functions.cpp`'s `DestType`
    test gone;
  - `framingOf`;
  - `Match.h`'s header;
  - the hand readings of the tail kind at `Accounts.cpp`,
    `Func/Call.cpp` and `EGraph/Build.cpp`.
- **"D126's second round"**, units E, B, F, A and H. Units D and G were
  not checked.
- **"Recheck 5's items not yet dispatched"**:
  - "The coordinator: strike `idris-linear-check.md` §5 when L06h
    returns": struck at `:113`.
  - L06h, L05x and L19z have all landed.
- **"D130 and D131 ... after round 3-A lands its regeneration"**:
  - the families lane's mark and sum term, C265's gate and C267's rule
    (8b218c36, 410c5dcd);
  - L18y's test with L19's two properties.
  - Only "After L16ee: the frontend's `indexTerm` reads base's `plus`"
    is left, and it is in flight.
- **The threading design's "Outside the threading"**: `KPlus` in the
  checker's vocabulary is done (d093dbfb).
- **"From L18z"**, first clause: a class copy's cast from `#Vect[_]` to
  `#Vect[3]` is admitted (C276, `Families/ScopeWalk.cpp:252-259`).

## Seen outside the range

- **The two folders, for the owner.** The queue's item "For the owner,
  after the sources question (L14u's finding)" is not in §4, which says
  "Open: none" (`p0.md:5531`).
  - idr-constants (`spec/Pipeline/Pipeline.idr:530-533`,
    `lib/Analysis/Constants.cpp`) and the e-graph both fold the same ops
    by two routes. They read one meaning (`Fold.h`'s two domains), but
    they are two propagators.
  - The coordinator either puts the question in §4 or records why it
    waits.
- **The frontend's index term restates the specification's.**
  - `compiler/src/IdrisMLIR/Types.idr:122-130` (`ITerm`) is a hand copy
    of `spec/Families/Terms.idr:73-95` (`Term`). Its normal form holds by
    smart constructors, where the specification's holds by type.
  - Substitution reads a level by a lookup that can miss
    (`compiler/src/IdrisMLIR/Term.idr:527`, `fromMaybe IOpaque (getAt l
    bs)`).
  - The queue's "From L16em" item routes the same kind of copy for
    `Term.Termination`.
- **C268** (`tie_shape` names its axes) is not in the tree:
  `spec/Arrays/Memory.idr:415-440` has no axes attribute. It is recheck
  6's C131 to C279 report's row; D129 names only C262's rule as its array
  case.
- **`.toolchain/llvm-project`** is checked out at 7208ba24c, while
  `toolchain.lock.json:5` pins 416f328b. This is unchanged since
  recheck 5. It is a local cache; whether the bootstrap reads it was not
  checked.
- **Closed:** `lib/Transforms/Bufferize/Linear.cpp:13` now says
  `idr.lin.cast` "changes a value's uses". Recheck 5 noted the old
  wording.
