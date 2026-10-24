<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Cull audit: the dialect as the specification declares it

Area: `compiler/spec/IdrisMLIR/Spec/` (ops, types, attributes, interfaces,
traits, rules, laws, tables, enums, hooks), the generated outputs under
`foreign/idr/include/idr/IR/Generated/` and `compiler/src/IdrisMLIR/Dialect/Idr.idr`,
and the hand C++ under `foreign/idr/lib/IR/` and `foreign/idr/include/idr/IR/`.

- HEAD at start: `363dcc0d` (AGENTS.md: delete before you optimize).
- HEAD at finish: `aca24580` (C286, a proposal-only commit after `88cafbf3`, D132). The commits since start touch none of the
  files a DELETE below names except `EGraph.h`/`Rules.cpp` (the `PowerOfTwo`
  case is still there) and the guard work (C285), which made `PerClass`
  dead; every count below was rechecked at `88cafbf3` plus the working tree.
- Method: read-only. Writers of an op were searched three ways: C++
  `XOp::create(` / `create<XOp>` / `NewOp<XOp>` over every non-generated
  `.h`/`.cpp` under `foreign/`, `tools/`, `runtime/`; the frontend's typed
  builder (`Idr.xOp`) over `compiler/src`; and the specification value the
  registry or Emit names (`Runs fileOpen`, `Op bigShow`, `specOp …`,
  `guardOpOf`, the e-graph's `simplify` rules). An op is called unwritten
  only when all three are empty. Readers were searched as named symbols
  outside `Generated/`. Every number below names its search.
- "Keep all the sources": nothing under `sources/` is a candidate, and each
  claim below carries the search or file it rests on.
- Ownership by `audits/p0/verify/ownership.json` (longest-prefix match).
  "M" marks a file modified in the working tree at finish (a lane holds it).

Ranked by lines deleted.

---

## 1. `OpIndex.h.inc` and its generator: a per-op key no table is keyed by

- **Part.** `foreign/idr/include/idr/IR/Generated/OpIndex.h.inc` (865 lines:
  `enum class OpIndex`, `EnumTraits<OpIndex>`, `IndexOf<OpT>`, `indexOf`);
  its generator `compiler/spec/IdrisMLIR/Spec/Generator/Cpp.idr:286-300`
  (`OpKey`, `keyName`, `keyClass`) and `:316-330` (`opIndexHeader`);
  `Generator/Outputs.idr:396-400` (`opKeys`) and `:421` (its `generate`
  row); `foreign/idr/generated.manifest:27`.
- **Fact it supplies.** A dense number per op, "the key of every per-op
  table". No reader: `grep -rn 'OpIndex\|IndexOf<\|indexOf<\|opIndex'` over
  `foreign tools runtime` (`.h .cpp .td .inc`), excluding the file itself:
  **0**; no file includes `Generated/OpIndex.h.inc` (search for the file
  name over the tree: **0** includers; only the manifest names it).
  `IndexedOp` (the planned `Operation* → OpIndex` bridge): **0**.
  `EnumArray<OpIndex`: **0**.
- **Where the fact lives now.** Every per-op fact is a class specialization
  keyed by the op's C++ class itself, dispatched at compile time:
  `runtime::Abi<Op>` (`RuntimeAbi.h.inc`), `Guarded<Op>` (`Guards.h.inc`),
  `Declared<Op>`/`EffectRules<OpT>` (`Effects.h.inc`), `LifetimeOpener<Op>`,
  `ShownOutput<Op>`, `ListElement<Op>`, `BigOfInteger<Op>`; the run-time
  `Operation*` dispatch is MLIR's interfaces. The index is a key nobody
  turns.
- **Rule that once required it.** The compile-time C++ design
  (`audits/p0/design/compile-time-cpp.md` §2.3(a); L15 §2.3, its D1 row:
  "`Operation *` → `OpIndex` through `IndexedOp`"), under AGENTS.md "every
  fact knowable when the compiler is built is a compile-time constant". No
  Dnnn or Cnnn names `OpIndex` (`grep -n OpIndex proposals/0000-mlir-native.md`:
  0). The rule is met by the specializations above, so the index has no
  job left.
- **Readers.** None (searches above).
- **Deletion.** Whole `OpIndex.h.inc`; `Cpp.idr:286-300` and `:316-330`
  (the "Op identity" section keeps `admittedClassesHeader`, retitled);
  `Outputs.idr:396-400`, `:421`; manifest row `:27`. No test, CMake or
  ipkg entry names it.
- **Verdict.** DELETE. Confidence: measured (0 includers, 0 symbol readers).
- **Owner / waits on.** L03 (`Spec/Generator/`), INT (`Generated/`,
  `generated.manifest`, M). Waits on INT's next regeneration; nothing else
  holds these files.
- **Lines.** 902.

## 2. Generated Idris builders the frontend never calls

- **Part.** `compiler/src/IdrisMLIR/Dialect/Idr.idr` (1042 lines, printed by
  `Spec/Generator/Idris.idr`'s `buildersModule ourOps`): 99 typed builders
  no module of `compiler/src` other than `SyntaxSamples.idr` calls (600
  lines). Of them, 84 build an op with no attribute and no region
  (`bigAddOp`, `strAppendOp`, every `io*Op`, every `buffer*Op`,
  `handleStringOp`, …) and 9 an op with one (`lifetimeOp`, `lendOp`,
  `arrayUpdateOp`, the five `check*Op`, `ioUnsafeRunOp`); 33 builders of
  attribute-free, region-free ops are called (`returnOp`, `yieldOp`,
  `natPredOp`, `strShowSintOp`, …).
- **Fact it supplies.** How the frontend writes one op. Held twice: the
  registry rows name the specification's op value (`Runs fileOpen`,
  `Op bigAdd NatT`, `PureOp`), and Emit writes it generically through
  `specOp : Spec.Op i o 0 0 -> …` (`Emit/Operations.idr:138-139, 353, 556,
  592-612`); the typed builder of the same op is printed beside it and
  unread. Search: each builder name, whole word, over `compiler/src/**/*.idr`
  minus `Dialect/Idr.idr` and `SyntaxSamples.idr`: 99 with 0 hits.
- **Rule that once required it.** D51/C137's "the frontend's builders are
  generated from ODS" (one source). It holds; what it does not require is
  a builder for an op the frontend writes another way, or never.
- **Readers.** `SyntaxSamples.idr` (one: `checkNonzeroOp`); none else.
- **Deletion.** Print a builder only where the frontend writes the op
  through one. Two shapes settle it, a choice for L03 and L16 (coordinator):
  (a) give our ops the `Writer` the admitted ops already carry
  (`FrontendWrites | PassesOnly`, `Spec/Core/Admitted.idr`), one
  representation for both, and print by it; or (b) every attribute-free,
  region-free op is written by `specOp` from its specification value, the
  33 typed calls become `specOp`, and the generator prints builders only for
  ops with an attribute or a region. Either removes the ~600 unread lines;
  (b) removes ~200 more and the second writing path.
- **Verdict.** MERGE (into `specOp` over the specification's op value, or
  into a `Writer` on our ops). Confidence: measured for "unread", conjecture
  for which shape the coordinator takes.
- **Owner / waits on.** L03 (`Generator/Idris.idr`), L16
  (`Dialect/Idr.idr`, `Emit/Operations.idr` M). Waits on L16's Emit edits.
- **Lines.** ~600 (counted at 600).

## 3. `idr.lazy.delay`: an op nothing writes

- **Part.** The third member of the capture family:
  `Spec/Closures/Declarations.idr:194` (`AnEvaluated`), `:196-223` (`Made`,
  `madeOf`, `nameCount`, `attrsOf`, `capturesOf`: with one case left they
  collapse to the function member's attributes and captures), `:228, 234,
  243, 249` (its clauses), `:251-270` (`namesFunction`, `verifyOf`,
  `formatOf` collapse to the function case), `:284-288` (`buildsDoc`),
  `:331-334` (`delayOp`), `:414` (list entry); `forceOp`'s `meaning =
  HandFolder` (`:356`) becomes `NoFold`, its doc `:340`. C++:
  `lib/IR/OpsClosures.cpp:236-248` (`LazyDelayOp::verify`), `:253-266`
  (`LazyForceOp::fold`, whose only case is a force of a delay),
  `lib/IR/FlowOps.cpp:191-197` (`LazyDelayOp::getFlowEdges`),
  `lib/Transforms/Defunctionalize/Edits.cpp:79-84` (its walk); comments at
  `OpsClosures.cpp:9-11`, `include/idr/Transforms/Defunctionalize.h:203`,
  `Edits.cpp:10`, `Defunctionalize/Indices.cpp:8`, `Emit/Bodies.idr:751`.
  Generated: `IdrOps.td` def (17), `Effects.h.inc` `Declared<LazyDelayOp>`
  (8), `Effects.cpp.inc` `getEffects` (~12), `Idr.idr` `lazyDelayOp` (6).
- **Fact it supplies.** "A suspension already evaluated, of a value." No
  writer: C++ create: 0; `lazyDelayOp`/`delayOp` in `compiler/src`: 0; Emit
  writes every `Delay` as `idr.lazy.suspend` of a lifted function
  (`Emit/Bodies.idr:793-801`, `SuspendF`); `grep -rlF idr.lazy.delay tests`:
  0. History: `git log -S "lazy.delay" -- compiler/src` finds only a
  comment (adf80e06); no commit ever wrote one.
- **Rule that once required it.** C112 (one capture family, "deletes the
  separate `delay` definition"), C3 (`delay` of an unrestricted value is
  pure). Both rule on what `delay` is if written; neither requires a
  writer. The representation the frontend chose (a suspension of a lifted
  function) covers the case.
- **Readers.** The three C++ members above and the force's fold, all only
  reached through a `LazyDelayOp`.
- **Deletion.** As listed. `buildsLabelInterface` and the memo family's
  forced state stay (the suspension and the memo ops read them).
- **Verdict.** DELETE. Confidence: read.
- **Owner / waits on.** L18 (`Spec/Closures/`, `OpsClosures.cpp`,
  `Defunctionalize/`), L09 (`FlowOps.cpp`, M: a lane is editing its splat
  model), L16 (the `Bodies.idr` comment), INT (generated). Waits on the
  `FlowOps.cpp` lane.
- **Lines.** ~133.

## 4. `idr.io.unsafe_run`: an op nothing writes

- **Part.** `Spec/Ops/IO.idr:184-217` (doc and `unsafeRun`), `:307` (list
  entry), `:144` (section title); `lib/IR/Ops/IO.cpp:15-22`
  (`getSuccessorRegions`) and its header comment `:3-6`;
  `lib/Conversion/Scalars.cpp:54-75` (`LowerUnsafeRun`) and its
  registration `:138`. Generated: `IdrOps.td` def (16), `Effects.h.inc`
  `Declared<IoUnsafeRunOp>` (8), `Idr.idr` `ioUnsafeRunOp` (6).
- **Fact it supplies.** A region run once for a trusted library's
  `unsafePerformIO`. No writer: C++ create 0; `ioUnsafeRunOp`/`unsafeRun` in
  `compiler/src`: 0; tests 0. The frontend writes a forged world as
  `NewWorld` (`Frontend/Translate/Terms.idr:680-682`), which Emit makes the
  world value (`Emit/Bodies.idr:901`, `NewWorldF → worldVal`), gone after
  Emit.
- **Rule that once required it.** C113 lists "`io.unsafe_run` a region op
  (D20)". D20 itself (2026-10-21) says the derived row's `io` atom "covers
  a trusted library's forged world" and the world ends at Emit; AGENTS.md:
  "its effects happen where the value is demanded, in program order with
  every other effect". The forged world plus the derived row is that
  representation; no region op is needed for it, and none is written.
- **Readers.** `Ops/IO.cpp` (the op's own method), `Scalars.cpp` (its
  lowering). Nothing else names `IoUnsafeRunOp`.
- **Deletion.** As listed; `scf::ExecuteRegionOp`'s include in
  `Scalars.cpp` goes if nothing else uses it.
- **Verdict.** DELETE. Confidence: read. C113's line naming it is amended
  in the same change (coordinator; D20 is not reversed).
- **Owner / waits on.** L13 (`Spec/Ops/IO.idr`, `Ops/IO.cpp`,
  `Conversion/Scalars.cpp`), INT (generated). Nothing modified.
- **Lines.** ~97.

## 5. `RuleScope`: a rule fact no one reads

- **Part.** `Spec/Core/Rules.idr:27-34` (`data Scope`), `:125-132`
  (`scope`), `:179-195` (`scopeClosed`), `:262-263, 265-267` (the `scopeOf`
  column and its `where`), `:256` (doc); `Spec.idr:253`
  (`enumDef scopeClosed`) and `:258` (header doc). Generated: `IdrBase.td:162-172`
  (`Idr_RuleScope`, `Idr_RuleScopeAttr`), `Rules.h.inc:48-77` (`scopeOf`),
  `EnumTraits.h.inc` (`EnumTraits<RuleScope>`).
- **Fact it supplies.** Where each refusal rule is decided (frontend,
  pipeline, build). No reader: `RuleScope` in non-generated C++: 0;
  `scopeOf` in non-generated C++: 0 (`categoryOf` has one,
  `lib/IR/Attrs.cpp:18`); no ODS op or attribute uses `Idr_RuleScopeAttr`;
  in Idris, `scope`/`scopeClosed`/`AgainstBuild` outside `Rules.idr`: 0.
- **Rule that once required it.** None found
  (`grep -n "RuleScope\|scopeOf\|where a rule is decided"` over the proposal
  and recheck6: 0). AGENTS.md requires each refusal's *category* in ODS,
  which `categoryOf` keeps.
- **Readers.** None.
- **Deletion.** As listed.
- **Verdict.** DELETE. Confidence: measured.
- **Owner / waits on.** L03 (`Spec/Core/`, `Spec.idr`), INT (generated).
  Nothing modified.
- **Lines.** ~85.

## 6. `idr.lifetime.reserve`: an op nothing writes

- **Part.** `Spec/Lifetimes/Declarations.idr:730-747` (doc and `reserve`),
  `:870` (list entry), `:482-484` (`roomOf` directive, used only by its
  format) and `:877`, `:260-261` and `:288-289` (`roomPredicate`,
  `roomLifetime`, used only by its result) and `:878`;
  `lib/IR/Lifetimes/Ops.cpp:229-241`; `lib/IR/Lifetimes/Proof.cpp:42-43`
  (the reserved-room case of the proof walk becomes the target itself);
  `lib/Conversion/Lower/Lifetimes.cpp:177-189` (`LowerReserve`) and its
  registration `:307`; `lib/IR/Lifetimes/Kind.cpp:60-64`
  (`parseRoomLifetime`, `printRoomLifetime`) and the comment `:52-53`;
  comments `include/idr/IR/Lifetimes.h:14, 401`. Generated: `IdrOps.td`
  def (12), `Effects.h.inc` (8), `Hooks.h.inc` (RoomLifetime and
  `isRoomLifetime` declarations, 6).
- **Fact it supplies.** A room carved from a cursor, for a cursor-holding
  caller that calls a room copy. No writer: C++ create 0, frontend 0, tests
  0. The decide step never plans that call: a cursor's or home's group keeps
  a call only if the callee has a copy of the group's own mode
  (`Transforms/Lifetimes/Decide.cpp:196-212`,
  `modes.contains(modeOf(group.source))`), else the call is counted; room
  lifetimes come only from `idr.lifetime.block`
  (`Transforms/Lifetimes/Write.cpp:168-170`).
- **Rule that once required it.** C146 (2026-10-21): "a caller holding a
  `cursor` that calls a `room` copy writes `idr.lifetime.reserve`"; C160
  lists it among derived lifetimes. The decide step made that call
  unrepresentable (it is demoted to counting), so C146 has no case to rule.
- **Readers.** `Ops.cpp`, `Proof.cpp`, `Lower/Lifetimes.cpp` (all only of
  a `LifetimeReserveOp`). `isRoomLifetime` itself stays (read by
  `Func/Verifier.cpp:53`, `Conversion/Lower/Rooms.cpp:101`), declared once
  in `Lifetimes.h`.
- **Deletion.** As listed; C146 and C160's mention are amended in the same
  change (coordinator decisions). If a cursor-to-room call is later wanted,
  it returns with its writer.
- **Verdict.** DELETE. Confidence: read.
- **Owner / waits on.** L05 (`Spec/Lifetimes/`, `lib/IR/Lifetimes/`,
  `Lifetimes.h`), L21 (`Conversion/Lower/Lifetimes.cpp`), INT (generated).
  Nothing modified.
- **Lines.** ~84.

## 7. Specification vocabulary no declaration uses

Constructors the specification language offers that no op, type,
attribute, interface or rule constructs: each is a generator branch with
nothing to print. Search: every constructor of every `data` in
`Spec/Core/*.idr`, counted as a token over every `.idr` outside
`Spec/Core/` and `Spec/Generator/` (comments excluded); 0 hits, then each
confirmed by `grep -rnw` over `compiler/spec` and `compiler/src`.

| Constructor | Where | Generator branches that go | Lines |
|---|---|---|---|
| `EnumShape.SetOf` | `Core/Enums.idr:24` | `Ods.idr:118-119, 142`; and `Outputs.idr:304-317` (`setProperties`, a refusal of a set-valued property no enum can be) and `:392` | 18 |
| `Typed`/`TypedBy` | `Core/Types.idr:409-416, 423` (only `Untyped` is ever given) | `Ods.idr:668-671` (`typedParameterOds` becomes `parameterOds`); `typed = Untyped` at `Spec.idr:98`, `Functions/Parameters.idr:116`, `Functions/LivesIn.idr:83` | 14 |
| `ParamItem.Struct`, `CustomParams` | `Core/Types.idr:231-232` | `Ods.idr:677-679` | 5 |
| `Law.Commutative`, `Idempotent`, `Involution`, `Annihilator` | `Core/Op.idr:281` | `Ods.idr:351-353`, `Cpp.idr:953-955` | 7 |
| `Cond.PowerOfTwo` | `Core/Rewrite.idr:55` | `Cpp.idr:907`; C++ `Transforms/EGraph.h:98` (enum case), `EGraph/Rules.cpp:381-384` (0 rows in `Rewrites.h.inc`) | 7 |
| `VerifyOrder` (only `AfterRegions` given) | `Core/Interfaces.idr:44-46, 50` | `Ods.idr:876-878`; `Control/Flow.idr:31` | 6 |
| `MethodBinding.PerClass` | `Core/Interfaces.idr:22` (dead since C285 made `decide` a template member, `Ops/Checks.idr:207-209`) | `Ods.idr:843, 852`, `Cpp.idr:1320` | 4 |
| `Root.RootedAtUpstream` | `Core/Rewrite.idr:46` | `Rewrite.idr:80`, `Cpp.idr:901-902` | 4 |
| `Trait.NoRegionArguments`, `ImplicitTerminator` | `Core/Op.idr` | `Ods.idr:297, 317` | 4 |
| `Blocks.AnyBlocks` | `Core/Op.idr:131` | `Ods.idr:444` | 2 |
| `PredicateSubject.OnAttribute` | `Core/Hooks.idr:87` | `Cpp.idr:1254-1256` (collapses) | 3 |
| `Declarations.tables` | `Core/Declarations.idr:35` (never read: only unioned, `:58`; every table is printed through `headers`' `TableOf`) | `nothing`, `union`, `Families/Declarations.idr:26`, `Arrays/Declarations.idr:505` | 6 |

- **Fact supplied.** None: no declaration builds these, so no generated
  file holds output of them (`Rewrites.h.inc` has 0 `PowerOfTwo` rows).
- **Rule that once required them.** None names them; they are vocabulary
  written ahead of a use that never came.
- **Verdict.** DELETE. Confidence: measured (token counts) and read.
- **Owner / waits on.** L03 (`Spec/Core/`, `Spec/Generator/`, `Spec.idr`),
  L14 (`EGraph.h`, `EGraph/Rules.cpp`), L09 (`Control/Flow.idr`), L02
  (`Functions/`), L04 (`Families/Declarations.idr`), L12
  (`Arrays/Declarations.idr`). Nothing modified among them at finish.
- **Lines.** ~80.

## 8. Hook declarations with no definition and no use

- **Part.** Six op-level directive hooks printed into
  `Generated/Hooks.h.inc:22-44` (`parseIndexTerms`/`printIndexTerms`,
  `Sorts`, `Members`, `Refinement`, `FamilyRef`, `DataRef`, each taking
  `OpAsmParser &` / `Operation *`), caused by listing `termsParam,
  sortsParam, membersParam, refinementParam, familyParam, dataParam` in
  `Spec/Families/Declarations.idr:29-30`'s `directives`; and the predicate
  `isCellValue` (`Spec/Families/Ops.idr:44-45`, list entry
  `Families/Declarations.idr:32`; `Hooks.h.inc:104-106`).
- **Fact it supplies.** None. No ODS format uses `custom<IndexTerms>` and
  the other five (the `custom<…>` census over every generated `.td` lists
  13 directives, none of these); no C++ defines the op-level forms (their
  parameter-level forms, `Hooks.h.inc:224-235`, come from the types'
  parameters through `textCodecDecls`, not from `directives`); `isCellValue`
  is used by no ODS constraint (0) and defined by no C++ (0).
- **Rule that once required it.** None; the six are parameter directives
  listed where op directives go.
- **Readers.** None.
- **Deletion.** Drop the six from `directives` and `cellValue` from
  `predicates` (and its definition); 26 generated lines go.
- **Verdict.** DELETE. Confidence: measured.
- **Owner / waits on.** L04 (`Spec/Families/`; `Families/Ops.idr` is M),
  INT (generated). Waits on the lane holding `Families/Ops.idr`.
- **Lines.** ~29.

## 9. `OpensLifetimeOpInterface`: an interface no one asks

- **Part.** `Spec/Lifetimes/Declarations.idr:355-368` (`opensLifetime`),
  its `Implements opensLifetime []` in `plainOpener` (`:543`) and
  `stackOpener` (`:602`), its entry in `interfaces :=` (`:874`);
  `include/idr/IR/Lifetimes.h:155-158` (`openerOfOp`) and the comment
  `:149-151`; generated `IdrInterfaces.td` def (~5) and the five openers'
  `DeclareOpInterfaceMethods` entries.
- **Fact it supplies.** Where an opener's memory comes from. Held already
  by the op's class (one op per source) and read at compile time as
  `LifetimeOpener<Op>::opener` (`Lifetimes.h:374`, the region trait).
  The interface: `OpensLifetimeOpInterface` named in C++ only by a comment
  (1); `getOpener` called 0 times; `openerOfOp` read only by the
  interface's default.
- **Rule that once required it.** "A reader asks the op and lists no op"
  (its own doc). No reader exists; the one reader of the fact reads the
  class constant.
- **Readers.** None.
- **Deletion.** As listed; `LifetimeOpener`, `Opener`, `openerTable`
  stay.
- **Verdict.** DELETE. Confidence: measured.
- **Owner / waits on.** L05, INT. Nothing modified.
- **Lines.** ~26.

## 10. `WordOfBigOpInterface`: an interface no one asks

- **Part.** `Spec/Ops/Bigs.idr:104-120` (`wordOfBigInterface`) and the doc
  `:69-75`; `big.to_int`'s `Implements wordOfBigInterface []` (`:528`); the
  unread method `getValue` of `bigWordInterface` (`:83-84`); generated
  `IdrInterfaces.td` (`Idr_WordOfBigOpInterface`, ~5).
- **Fact it supplies.** "An integer read out of a big, its word the
  result." `WordOfBigOpInterface` in C++: 0. The one reader of the pair,
  idr-narrow, asks only the base: `isa<BigWordOpInterface>`
  (`Transforms/Narrow/Narrow.cpp:145`); `BigWordOpInterface::getValue` is
  called nowhere through the interface. `BigOfIntegerOpInterface` keeps a
  reader (`Narrow/Facts.cpp:125`, `getSignedness`).
- **Rule that once required it.** None beyond its doc ("which side its word
  is on is the interface it takes besides").
- **Deletion.** `big.to_int` implements `bigWordInterface` directly; the
  word-of-big interface and the base's method go.
- **Verdict.** MERGE into `BigWordOpInterface`. Confidence: measured.
- **Owner / waits on.** L13 (`Spec/Ops/Bigs.idr`), INT. Nothing modified.
- **Lines.** ~24.

## 11. The flow model of `tensor.splat`

- **Part.** `lib/IR/FlowOps.cpp` `splatEdges` (`:280-285` at HEAD) and its
  `attachInterface` (`:307`); `include/idr/IR/Flow.h:111` (comment).
- **Fact it supplies.** How labels move through a `tensor.splat`. No op
  writes one: `SplatOp`/`tensor.splat`/`splatOp` over `foreign`,
  `compiler/src`, `compiler/spec`, `tests`: only these lines; `tensor.splat`
  is not admitted (`IdrAdmittedTensor.td`).
- **Rule.** None.
- **Verdict.** DELETE, unless the lane now editing `FlowOps.cpp`/`Flow.h`
  (M: it rewrites `splatEdges` over a new `everyElementEdges`) is about to
  admit a writer. Confidence: conjecture (the in-flight edit suggests
  intent).
- **Owner / waits on.** L09 (both files M). Waits on that lane.
- **Lines.** ~8.

---

## Examined and kept

- **`ArrayMeaning`/`Composed` and `tensorJoinsAdmitted`**
  (`Spec/Arrays/Declarations.idr:48-58, 100-497`). No reader today
  (`ArrayMeaning`, `Composed`, `MkArrayMeaning` outside the file: 0;
  `Tensor.concatOp`/`padOp`/`yieldOp` uncalled; the frontend writes `++`
  through `insert_slice`, `Emit/Tensors.idr:361-393`). KEEP: C284
  (2026-10-23) accepts them as "the one table the frontend reads", queued as
  N10 (`audits/p0/verify/handoffs/L16-queue.md`). The second copy is the
  frontend's (`ArrayPrim`, `generatedOperands`, `arrayTerm`,
  `Frontend/Translate/Terms.idr:2358…`, `Term.TensorOp`): that is the MERGE,
  L16's, not this area's; not counted here.
- **The run helpers** `incRun*`/`decRun*` (`Spec/Runtime/Helpers.idr:51-59,
  68, 79-86`; 16 rows of `RuntimeAbi.h.inc`; `runtime/Rc/Counting.cpp:77-100`).
  No lowering calls them (`helper::incRun…`/`decRun…`: 0; only
  `incOf`/`decOf`'s one-word entries, `Conversion/Runtime.cpp:79-110`).
  KEEP for now: AGENTS.md's never-line 18 R-RC-4 and L07 §2.8 plan their
  reader (`inc_slots`/`dec_slots` per run). If L07 drops §2.8 from the
  cutover, they go (~75 lines, L11).
- **`arith.maxui`, `arith.minsi`, `arith.minui` admissions**
  (`Spec/Ops/Shapes.idr:283-293`). The frontend never calls
  `Arith.maxuiOp`/`minsiOp`/`minuiOp`; `minui` is written by
  `Narrow/Copy.cpp:54`; upstream's `LowerAffine` (in the pipeline,
  `Pipeline.idr:637`) writes `minsi`/`maxsi` from affine min/max. KEEP
  (conjecture that nothing writes `maxui`); `minUI`'s `FrontendWrites` is
  wrong (only a pass writes it) and folds into candidate 2's `Writer`.
- **`InlineMeanings.h.inc`**: read only by `unittests/Intervals.cpp`, which
  searches every inline meaning (a property over the generated set). KEEP.
- **Traits.** Every `NativeOpTrait` of `IdrBase.td` has a C++ reader
  (`hasTrait`, a concept, or a `verifyTrait` MLIR runs); `ResultUsesMax`'s
  reader is its own `verifyTrait`.
- **Interfaces.** Every other method of `IdrInterfaces.td` has a caller
  (per-method call census over non-generated C++).
- **Ops with no direct writer that are written:** `int.head_s/u`,
  `f64.head` (the e-graph's `simplify` rules, `Spec/Ops/Rewrites.idr:145-149`);
  the five `check.*` guards (`guardOpOf`, `Spec/Ops/Checks.idr:338-342`);
  every `io.*`, `buffer.*`, `big.*`, `str.*` op without a typed-builder call
  (registry rows and `specOp`).
- **Not counted, owner-level.** `idr.call` carries copies of its callee's
  row, write part and `lives_in`, held equal by its symbol-use verifier
  (`lib/IR/Func/Call.cpp:52-73, 272`). AGENTS.md requires the row ("a call
  carries its callee's"); whether `lives_in` must be copied for "a pass on
  the caller reads a call alone" is a contested core shape, for the owner.

---

## Table

| # | Candidate | Verdict | Lines | Owner | Waits on |
|---|---|---|---|---|---|
| 1 | `OpIndex.h.inc` and its generator | DELETE (measured) | 902 | L03, INT | INT's regeneration |
| 2 | 99 unread generated Idris builders | MERGE (measured / conjecture on shape) | 600 | L03, L16 | coordinator's choice; L16 (`Emit/Operations.idr` M) |
| 3 | `idr.lazy.delay` | DELETE (read) | 133 | L18, L09, L16, INT | L09's `FlowOps.cpp` (M) |
| 4 | `idr.io.unsafe_run` | DELETE (read) | 97 | L13, INT | none; C113 amended |
| 5 | `RuleScope` | DELETE (measured) | 85 | L03, INT | none |
| 6 | `idr.lifetime.reserve` | DELETE (read) | 84 | L05, L21, INT | none; C146, C160 amended |
| 7 | Unused specification vocabulary (12 constructors and the `tables` field) | DELETE (measured) | 80 | L03, L14, L09, L02, L04, L12 | none |
| 8 | Six op-level hook declarations, `isCellValue` | DELETE (measured) | 29 | L04, INT | L04's `Families/Ops.idr` (M) |
| 9 | `OpensLifetimeOpInterface` | DELETE (measured) | 26 | L05, INT | none |
| 10 | `WordOfBigOpInterface` | MERGE into `BigWordOpInterface` (measured) | 24 | L13, INT | none |
| 11 | `tensor.splat` flow model | DELETE (conjecture) | 8 | L09 | L09's in-flight `FlowOps.cpp` |
| – | `ArrayMeaning`, tensor joins | KEEP (C284, N10) | 0 | L12 | – |
| – | Run counting helpers | KEEP pending L07 §2.8 | 0 (75 if dropped) | L11 | L07 |
| – | `arith` min/max admissions | KEEP (conjecture) | 0 | L13 | – |

**Total removed by DELETE and MERGE: ~2,068 lines** (DELETE 1,444; MERGE
624). Without candidate 2, whose shape is the coordinator's: ~1,468.
Generated lines are most of it (OpIndex 865, builders 600, ~130 across the
others); hand-written specification and C++: ~470.
