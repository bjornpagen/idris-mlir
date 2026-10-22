<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 wave 2, lane ods-effects: traits, interfaces and the effects model

Scope: `foreign/idr/include/idr/IR/IdrInterfaces.td`, `IdrRuntime.td`,
`IdrFlow.td`, `include/idr/IR/Traits.h`, `Flow.h`, `FlowEdges.h`;
`lib/IR/Effects.cpp`, `Flow.cpp`, `FlowEdges.cpp`, `FlowOps.cpp`,
`Crashes.cpp`; and every `getEffects`, `MemoryEffects`, `hasTrait`, trait or
interface query, world-operand read and resource use across `foreign/idr`.

Status: written 2026-10-21 at e96bb991, all nine sections. Nothing was
built; counts are over the source and TableGen's own reading of the
records (§2).

## 1. Reading notes

Written while reading, in the order read. Each note names the proposal
section and finding ID; *read* means read in the proposal.

**§2 (brief).** The trait layer "as another agent read it" (*recalled* by
the proposal, checked here in §3): right already are `GuardedOp`,
`Idr_ConsumesOnly`, `Idr_ResultCarriesOperand`, the resources, `Decides`;
gaps are `SameValue` without `verifyTrait`, ladders at
`IR/Canon/Sink.cpp:114`, `Transforms/StructureLoops/Forms.cpp:132`, four
`isa<ReturnOp, YieldOp>` in `Transforms/Tail`, three IO representations
(trait, `IOResource`, world operands), traits read once or never
(`TakesReference`, `BuildsValue`, `ObservableIO`). Counts at e96bb991:
`hasTrait<` 49, `getEffects`/`MemoryEffects` 139, 72 effect declarations,
15 native traits, 12 interfaces, six resources (Crash, IO, Divergence,
Lin, Reference, MemoState), `Idr_Runtime<"symbol">`.

**§3.** e96bb991: an interface query per pair of terminator and region
successor was quadratic; 3a96c407/7987388b: any-op patterns. Bears on
how flow/effect queries are asked (once per op, not per region).

**§4.** The bar: traits with `verifyTrait`, effects in ODS; "a hand
`verify` or `getEffects` is a declaration not yet made"; ladders over ops
are traits or interfaces not yet declared.

**§5.1 (mlir-analysis).**
- D1: `EffectInstance` = effect, resource, optional value/operand/result/
  symbol, stage, full-region flag; resources have `getParent`,
  `isSubresourceOf`, `isDisjointFrom`, `isAddressable` at the pin;
  speculation is `ConditionallySpeculatable`; `isPure` = speculatable and
  effect-free.
- D2: the reader table. Greedy DCE and region DCE read
  `wouldOpBeTriviallyDead`; CSE reads `isMemoryEffectFree` and, for
  read-only ops, resource disjointness and addressability; LICM reads
  `isPure`; control-flow sink and the inliner read
  `isMemoryEffectFree`; local alias analysis reads `getEffects` on values
  and gives up on `HasRecursiveMemoryEffects`; bufferization reads
  `Allocate`/`Free` on values; topological sort, mem2reg, SROA read none.
  Nothing upstream reads `stage`, `effectOnFullRegion` or symbol effects.
- D3: an op with only `Read` (or `Allocate` of its own result) is erased
  when unused; `RecursiveMemoryEffects` recomputes by a body walk per
  query, so a 30,000-case match is walked on every greedy visit.
- 5.1.2 item 6: declare `IOResource`, `ReferenceResource` disjoint and
  non-addressable where true; `RecursiveMemoryEffects` on a large match is
  a question for ODS and wave 2.
- W4 (mine in part): which ops carry `RecursiveMemoryEffects`, which
  upstream passes query them.
- C4, 5.1.2 item 5: match ops override `getPredecessors`,
  `getPredecessorValues`, `getSuccessorRegions(Region&)` (bears on the
  Flow interface, `IdrFlow.td`).

**§5.2 (mlir-ods), the lane's core.**
- A1-A2: an ODS `SideEffect` record (effect, resource, stage, full-region);
  one generated `getEffects`, one `emplace_back` per declaration;
  resources are function-local static singletons.
- A3: the resource hierarchy is C++ only (`virtual getParent()`); CSE
  (`CSE.cpp:222-228`) and local alias analysis (`:530`) read it.
- A4: `MemoryEffects<[...]>` composes through `TraitList`s into one
  generated `getEffects`; `Pure` is such a bundle.
- A5: all or nothing per op: ODS effects plus
  `DeclareOpInterfaceMethods<MemoryEffectsOpInterface>` is a tblgen error;
  an op whose effects depend on attributes, types or regions writes the
  whole method; `RecursiveMemoryEffects` is the one sanctioned dynamic
  form.
- A6: what upstream acts on: effect kind, resource (identity, parents,
  addressable), value or symbol. `wouldOpBeTriviallyDead`: every effect a
  `Read` or an `Allocate` of its own result.
- A7: MLIR splits "kept and ordered" (memory effects) from "may trap or
  not terminate" (`ConditionallySpeculatable`); `arith.divsi` is
  `NoMemoryEffect` plus `ConditionallySpeculatable`; non-local exits have
  no model.
- A8: siblings in the resource tree are disjoint; `classof` is
  hierarchy-aware, so "does IO" is one `isa<IOResource>` over effect
  instances.
- A9: consumption as an effect: the transform dialect puts `Read`+`Free`
  on the consumed `OpOperand` (`TransformMappingResource`); a trait
  (`FunctionalStyleTransformOpTrait`) supplies `getEffects` for a family;
  `InferEffects` stores a per-argument summary; the call op's hand
  `getEffects` looks the callee up (`lookupNearestSymbolFrom`, linear).
- B1-B3: trait kinds; `verifyTrait`, `verifyRegionTrait`, `foldTrait`;
  a trait member can supply an interface method; verification order
  (count traits, structural, `OpInvariants`, native/interface traits in
  declaration order, `verify()`).
- B4: `op->hasTrait<T>()` is a virtual call folding `TypeID` comparisons;
  on a typed op it is `constexpr`; `dyn_cast<Interface>` is a binary
  search plus, on a miss, a dialect fallback.
- B5: builtin traits passes read (`Commutative`, `ConstantLike`,
  `ReturnLike`, `Terminator`, `RecursiveMemoryEffects`, ...); builtin
  `token` is not a world model (5.2.5).
- C1-C3: interfaces: `body` vs `defaultBody` vs neither
  (`DeclareOpInterfaceMethods`); `$_raw_op` shares one body; external
  models.
- M1: one effects model: named bundles (`Idr_DoesIO`), `Arg`/`Res`
  classes, "does IO" as `isa<IOResource>`, the marker trait deleted; the
  world-operand rule is one trait supplying `getEffects` (row 3), never
  mixed with ODS effects (A5).
- M2: Divergence, Crash and Lin are three different MLIR facts:
  speculation for the first two (upstream's model), `Read`+`Free` on the
  consumed operand for Lin, derived from the type by one trait.
- M3: if Crash must stay ordered with IO and heap writes it is their
  ancestor, never a sibling.
- M4: `SameValue` gets a `verifyTrait`; marker traits with no reader go
  or become a classification.
- M5: `isa<ReturnOp, YieldOp>` is `ReturnLike` or
  `RegionBranchTerminatorOpInterface`; `Sink.cpp:114`, `Forms.cpp:132`
  become interface queries.
- M7: `Idr_Runtime<"symbol">` is row 12: `extraOpDeclaration` injecting
  `static constexpr StringLiteral getRuntimeSymbol()`, a `RuntimeFunction`
  interface with a `StaticInterfaceMethod`, one interface-rooted lowering
  pattern, `idris-mlir-tblgen` reading the same record.
- M8: op families from lists (platform, per-signedness words).
- Recipe rows 1-6, 7, 11, 12, 23 are this lane's; the sketch at
  5.2.3 (`Idr_DoesIO`, `Idr_Consumed`, `Idr_WorldEffects`,
  `Idr_RuntimeFunction`, `Idr_PlatformOp`).
- Rejected: mixing ODS effects and hand `getEffects`; keeping stage and
  full-region as if read.
- Owner questions ods-Q1 (Divergence/crash kept or deletable), Q2
  (effects from types: one trait vs split ops), Q3 (resource tree: Crash
  an ancestor?), Q5 (stages and full-region effects).
- Wave 2 W1 (mine): every hand `getEffects` and C++ `MemoryEffects` use:
  static, type-dependent or recursive; which ops declare both. W4 (mine
  for ladders over traits): each `isa<` over ops and which trait it
  restates. W10: interface `body`s using `$_op` that could use
  `$_raw_op`.

**§5.3 (llvm).**
- B1: variadic `isa` costs what a trait check costs; the case against it
  is representational (a class membership restated per use).
- B2: `TypeSwitch` is a declared ladder, right for a per-pass table; a
  classification more than one pass reads is a trait or interface.
- S0: before any solver, the representation that makes the solve
  unnecessary; "our `!idr.world` token already is, for IO, what MemorySSA
  is for LLVM's memory". 5.3.5 to dialect-design: if the token is the
  representation, "does IO" is read off it and the three IO
  representations can be one. This is the strongest claim about my
  subsystem from outside §5.2.
- I1: a ladder over ops is a trait (`isa<ReturnOp, YieldOp>` ->
  `hasTrait<ReturnLike>`). I8: a list in C++ that mirrors records is
  generated (`!instances`, `GenericTable`, wrappers).
- E1: `!instances<T>` and `assert` compute and check record sets in
  TableGen (a list of "every op carrying trait X").

**§5.4 (modular).**
- F6: IPDF reads unknown ops through `MemoryEffectOpInterface` effect by
  effect with the effect's value; an op without it is assumed to read
  and write every operand.
- F12: Mojo declares 0 resources, 0 `MemoryEffects<[...]>`, 15 `Arg`/`Res`
  effects, 7 hand `getEffects` where an attribute changes the effect.
  5.4.2 item 9: "P0's one effects model should go further than Modular
  went". Not to take: a hand `getEffects` where an attribute changes the
  effect.
- Wave-2 question (5.4.4): "any hand-written `getEffects` or `verify` that
  exists because an attribute changes an op's meaning (F12's
  anti-pattern)": mine for `getEffects`.

**§5.5 (cxx26).**
- Finding 8, 17: `OpT::hasTrait<T>()` is `constexpr` on a concrete class;
  a concept can read an ODS trait or interface membership at compile time.
- D1 (proposed §8 Q1 line): dispatch over ops is MLIR's (interface,
  trait, rooted pattern), never a C++ concept or `isa` that lists op
  classes; below the dispatch, typed code; a concept may read ODS, never
  list ops. Sketch `concept ConsumingOp = OpT::template
  hasTrait<idr::OpTrait::ConsumesOnly>()`.
- D4a: an op's runtime symbol, refusal category, effect row: each emitted
  to C++ and Idris from the one record, never a C++ switch.
- 5.5.5: a trait with `verifyTrait` can also be `static_assert`ed on a
  typed op.

**§5.6 (ecosystem).**
- A3: CIRCT's IMDCE reads upstream effects to decide roots
  (`isMemoryEffectFree`, `hasSingleEffect<Allocate/Read>`).
- E3: Flang's `AliasAnalysisRecursiveEffectsCache`, one summary per
  `HasRecursiveMemoryEffects` op, pass-scoped, "so mod-ref queries do not
  re-walk the regions".
- E4: HLFIR writes 24 `getEffects` by hand because effects depend on
  operand types; FIR defines its own resources. 5.6.5 to §5.2: "a case
  ODS cannot declare, which the redesign should make unrepresentable
  rather than hand-write". 5.6.5 to §5.8: HLFIR is the "one op, effects by
  operand type" design.
- F1: ClangIR at the pin: 64 `Pure`, 14 `MemRead`, 15 `MemWrite`, 2
  `MemAlloc`, 3 `RecursiveMemoryEffects`, 1 hand `getEffects` over 315
  ops: a baseline of how declarative effects can be.
- F2: ClangIR generates its LLVM lowering from ODS fields: a model for
  `Idr_Runtime`.
- Item 1, Design 2: a solver's domain is the values whose type leaves its
  question open, read off a type interface (`ValueFacts` named as the
  candidate).
- Item 9: an op's edge and effect table built once (e96bb991's lesson).
- W-E4 (discardable attributes carrying facts) and W-E6 (queries on a
  match that walk regions, including `RecursiveMemoryEffects`) bear on
  this lane.

**§5.7 (library).**
- B2: MLIR's four ways a pass meets an open set of ops: traits ("a single
  bit"), privileged hooks, optimization interfaces, dialect-specific
  passes.
- C6: the VSDG carries side effects as explicit state edges beside value
  edges, so ordering is data and dead-node elimination is one rule over
  both. 5.7.5 to §5.8: "the theory behind a world token as a value
  against effects on a resource". This is the theoretical case for the
  world operand as the IO representation.
- L1, L3: effect summaries as interned, frozen program tables.
- L4: "effect propagation" is a relation (union-find or semi-naive).

**§5.8 (dialect-design), effects as design: the lane's other core.**
- Summary (4): "Idiomatic MLIR orders IO with effects on a resource tree,
  not tokens; the builtin `token` cannot carry a world (B11, EF4, DS2)."
- A4: Mojo's function type carries per-argument conventions and an
  `FnEffects` bit enum; a call's obligations are read off the callee's
  type.
- B9: a function pass may not read sibling ops; a callee's type or
  declaration is a sibling of the caller, so a direct call's effects
  cannot be read off the callee from a parallel function pass.
- B10: verifiers are local; whole-function invariants are passes.
- B11: builtin `token` cannot cross calls, branches, region results.
- C1: four behaviours, two interfaces (memory effects; speculation for
  UB and infinite loops). Non-addressable resources do not alias any
  value-based location.
- C2: totality is a trait (`Arith_TotalIntBinaryOp` adds `Pure`),
  `divui` is `ConditionallySpeculatable`.
- C3: `memref.alloc`/`alloca` are one `AllocLikeOp<mnemonic, Resource>`;
  the difference is exactly the effect.
- C4: consumption is `Read`+`Free` on the operand, production
  `Allocate`+`Write` on the result; `FunctionalStyleTransformOpTrait`.
- C5: tokens order asynchrony, effects order memory; GPU ops keep both.
- C6: "An abort is a write": `cf.assert` declares `Write` on the default
  resource; `ub.unreachable` is a terminator with no effects.
- F2: FIR derives volatile effects from a type parameter in one helper
  (`addVolatileMemoryEffects`), on a non-addressable resource; one cast
  changes volatility. "The type is the one source; the effect is
  computed from it."
- F7, EF5: a fake resource standing in for identity (FIR's
  `DebuggingResource`): prefer a type or an operand.
- O2: two ops differing only in effect are one TableGen class
  parameterized by the resource; a region op's effects are its body's
  (`RecursiveMemoryEffects`), never a pure op plus an IO twin.
- O5: compose before fusing: `io.put_sint %x` is `io.write (str.show_sint
  %x)`, fused at lowering.
- EF1: two interfaces for four behaviours; abort kept as an effect;
  non-termination is the owner's question.
- EF2: resources form a tree; sketch: non-addressable `World` with
  children `Console`, `Files`, `Environment`, `Clock`, `Process`; a crash
  writes `World`.
- EF3: consumption is `Arg<T, "", [MemRead<Idr_Linear>,
  MemFree<Idr_Linear>]>`; "consumed exactly once on every path" is a pass,
  not an op verifier; `ConsumesOperands`/`ConsumesOnly` become these
  declarations; "the `Lin` resource is already the right shape if it is
  used this way".
- EF4: a world value beside declared effects is a second representation;
  if it stays, its effects must be derived from it by one rule (FIR's
  helper).
- T6: a function type carries conventions and effects; B9's catch.
- T7: `ValueFacts` as the home of "contains a linear field", "contains a
  reference", computed at construction.
- DS2.1: no world value after the frontend: effects on a resource tree,
  function effects in the type; `unsafePerformIO` a region op with
  `RecursiveMemoryEffects`; a call carries the callee's effect set as an
  inherent property verified in `verifySymbolUses` (CIR's `cir.call`
  `memory_effects`), or an analysis. DS2.2: keep the world, derive every
  IO effect by one rule. DS2.3 (builtin token): rejected.
- DS4 rows for my traits: `SameValue`, `TakesReference`, `BuildsValue`,
  `CarriesOperand`, `ResultCarriesOperand` -> one forwarding interface;
  `ConsumesOperands`, `ConsumesOnly`, `Lin` -> `MemFree<Idr_Linear>`;
  `PerformsIO`, `ObservableIO`, `IO`, world operands -> effects on
  `World`'s children; `MayCrash` -> an effect on `World` (or a `Crash`
  child); `NoReturn` -> terminators with no successors; `check.may_loop`,
  `Divergence` -> owner's question; `delay`/`force`/`memo.run`,
  `MemoState` -> a `lazy.` family; `Idr_Runtime`, `Primitive` -> keep the
  symbol trait, `Primitive` implied by it.
- Owner questions in scope: DD-Q2 (divergence), DD-Q3 (the world), DD-Q5
  (one op, several runtime functions).
- Wave-2 question (5.8.4) in scope: "Where `MayCrash`, `PerformsIO`,
  `ObservableIO`, `ConsumesOperands` and the world operands are read,
  mapped to the effect queries that would replace them (EF2, EF3)."

**§5.9 (mlton).** F2: RemoveUnused keeps `MayReturn` and `MayRaise` per
function as two-point cells (an effect summary per function, demand
driven). M1, Q-O3: facts a later pass reads go into types. Design 1
names `Effects` among the whole-program solvers a constraint
interpreter would replace (lane 06's call).

**§5.10 (rc).**
- C2: Swift's retains and releases carry `MayHaveSideEffects`; RC
  identity is a per-instruction relation (which result carries which
  operand's count): our `CarriesOperand`/`ResultCarriesOperand`.
- G5, M3: `ConsumesOperands`, `ConsumesOnly`, `Idr_ConsumesOnly` are the
  per-operand lifetime-ending bit; upstream form `Read`+`Free` on the
  operand.
- R1.5: "Effects declared once: `dup` and `drop` write the count
  resource, `is_unique` reads it, a consuming operand is `Read`+`Free` on
  it, so no upstream pass can move a `dup` above an `is_unique`."
- W5: does the grade verifier read consumption from declared traits and
  effects or re-derive it in C++? W7: which ownership ops are one op
  with different effects (shared with lane 07/08 and ods-ops).

**§5.11 (oom).** (B): allocation failure is outside the program's
meaning; "if every allocating op carried the `Crash` resource, no pure
allocation could be speculated, sunk, CSE'd or deleted". 5.11.5 to
§5.8: "`MemAlloc` on a constructor must stay free of `Crash`". oom-1 is
the owner's.

**proposals/0003-facts-once.md** (items in this lane's files; each to be
checked in §3 and §4):
- "MoveOut classifies effects a second way" (`lib/IR/Canon/MoveOut.cpp`:
  its own `Does`, `doesOf`, `isa<ForceOp>` beside `idr::classify` in
  `lib/IR/Effects.cpp`; they disagree on `ub.unreachable`; `idr.force`
  declares no valueless `MemRead`).
- "Resources read as effect bits by hand" (`Expect/Placement.cpp`
  `Order`, `StructureLoops/Forms.cpp` `atMostCrashes`) beside
  `idr::effectInstances` (`lib/IR/Func/Func.cpp`).
- "The crash-site count and the crash effect disagree":
  `Expect/CrashSites.cpp` counts `NoReturn` (includes `idr.exit`),
  `bodyEffect` counts `MayCrash`. Owed: "may crash" one ODS fact.
- `holdsLabels(Value)` (`lib/IR/Flow.cpp`) repeating `carriesLabels(Type)`
  (`Analysis/Labels.h`).
- `knownNonEmpty` re-walks the append tree per question (`Crashes.cpp`):
  put non-emptiness in the type.
- `Effects.cpp` (the pass) preserves only `SymbolTable` though it writes
  only effects; the optimizer restamps every call's effects each round
  (`Component.cpp` `writeCallEffects`).
- Function facts `effects` and `total` reach no LLVM attribute
  (`willreturn`, `mustprogress`, `nounwind`, `memory`).
- `feeds()` is a ladder of op kinds (`lib/IR/Canon/Feeds.cpp`): lane 04's,
  but its fix is an interface (my mechanism).

**§8.1** gathers this lane's owner questions: ods-Q1, DD-Q2 (answer
together), ods-Q3, ods-Q2, DD-Q3 (answer together), ods-Q5; DD-Q5 is in
§8.3. Q-E2 and DD-Q7 (a function's effects in the IR or in an analysis)
bear on DD-Q3. §9 holds four decisions (D1-D4), none on effects.

## 2. What the subsystem is

All counts *measured* at e96bb991 unless marked. The trait and effect
counts come from TableGen's own reading of the records, not from grep:
`.toolchain/build/tblgen/bin/llvm-tblgen --dump-json -I
.toolchain/llvm-project/mlir/include -I foreign/idr/include
foreign/idr/include/idr/IR/IdrRuntime.td` (it includes every op file), then
small `python3 -I` scripts over the JSON that flatten `TraitList`s as
mlir-tblgen does (scripts kept outside the repository in
`/tmp/p0-ods-effects-scripts/`, reproducible from this description: an op
is a record of class `Op` whose `opDialect` is `Idr_Dialect`; its effects
are its `MemoryEffects` traits' `effects` plus the `decorators` of its
`Arg`/`Res` operands and results). 189 `idr` ops (the brief's 191 includes
the target dialect's ops).

### 2.1 Files and sizes

`wc -l` (*measured*):

| file | lines | what it holds |
| --- | ---: | --- |
| `include/idr/IR/IdrInterfaces.td` | 340 | 2 type interfaces, 6 resources, `Idr_Op`, 9 op interfaces, 7 native traits, 3 trait lists |
| `include/idr/IR/IdrFlow.td` | 55 | `FlowOpInterface` (one method, an interface verifier) |
| `include/idr/IR/IdrRuntime.td` | 98 | 14 `Idr_RuntimeFunction` records (the lowering's own runtime calls) and 18 `Idr_CType`s |
| `include/idr/IR/Traits.h` | 203 | C++ halves of 12 native traits, `Guard`/`Guarded`, `consumedEffects` |
| `include/idr/IR/Flow.h` | 115 | flow reading, `Does`/`classify`/`onlyAllocates`/`performsIO`/`mayRunAt` |
| `include/idr/IR/FlowEdges.h` | 388 | `Carrier`, `Carriers`, `FlowAnchor`, `FlowPoint`, `FlowEdges` |
| `lib/IR/Effects.cpp` | 184 | consumption from flow, `readsMemoState`, the classifiers, `mayRunAt` |
| `lib/IR/Flow.cpp` | 351 | `forwardedValues`, `flowEdgesOf`, the flow verifiers |
| `lib/IR/FlowEdges.cpp` | 132 | carriers of a type, the edge helpers |
| `lib/IR/FlowOps.cpp` | 367 | 30 ops' `getFlowEdges` (12 more live beside their ops, `OpsArrays.cpp`, `OpsFolds.cpp`, `OpsGenerating.cpp`, `OpsTabulate.cpp`, `OpsClosures.cpp`), 8 external models, `NeverRuns` |
| `lib/IR/Crashes.cpp` | 45 | `knownNonEmpty`, `CrashOp::getCrashCause` |

Beside them, and read here for how effects are read (their algorithms are
lanes 05's and 06's): `lib/IR/Func/Func.cpp` (`bodyEffect`,
`componentEffects`, `writeEffects`, the bit-to-resource table `rows`),
`lib/IR/Func/Call.cpp` (the call's effects), `include/idr/Analysis/Effects.h`
(64), `lib/Analysis/Effects.cpp` (96), `lib/Transforms/Effects/{Effects,Constants}.cpp`
(43, 209), the `Effect` bit enum (`include/idr/IR/IdrAttrs.td:200-209`) and
the resource classes (`include/idr/IR/IdrDialect.h:55-99`).

### 2.2 The facts the subsystem holds

Each fact, its carriers, and where they agree or disagree (*measured* from
the records unless marked):

| # | fact | carriers today | ops |
| --- | --- | --- | ---: |
| F1 | an op is an Idris IO action (takes the world, gives the next) | trait `Idr_PerformsIO` (`IdrInterfaces.td:295-297`); a `!idr.world` operand and result | 80 with the trait; 79 take and give a world, 1 (`world.new`) gives one: **the two sets are identical** |
| F2 | an IO op the program's outside observes | trait `Idr_ObservableIO` (`IdrInterfaces.td:306-308`) | 68 (every `Idr_IOOp` and `io.put_list`) |
| F3 | ordered with output | `MemWrite<Idr_IOResource>` | 80: the 68 observable, `io.strerror`, `world.new`, 8 `Idr_MayCrash` ops, `may_loop`, `force` |
| F4 | reads the outside's state | `MemRead<Idr_IOResource>` | 70: the 68, `io.strerror`, `handle.string` |
| F5 | may crash | interface `MayCrashOpInterface` (via `Idr_MayCrash`, `IdrInterfaces.td:105-117`); `MemWrite<Idr_CrashResource>`; `Idr_NoReturn` ∪ `GuardOpInterface` (idr-expect's count) | interface 8; Crash writers 9 (+`force`); crash sites 8 (`exit` in, `nat.to_extent` out) |
| F6 | may not end | `MemWrite<Idr_DivergenceResource>`; `total` on `idr.func`; `Effect::diverge` | `may_loop`, `force` |
| F7 | takes an operand's reference over | `Free<ReferenceResource>` computed from the flow edges and the owned grade (`Effects.cpp:96-105`) | 8 via `Idr_ConsumesOnly`; `call`, `con`, `own.give` by hand |
| F8 | gives a fresh linear value | `MemAlloc<Idr_LinResource>` on the result | `lin.enter`, `lin.use` in ODS; `call` by hand (`Call.cpp:69-71`) |
| F9 | reads or writes a memo cell's state | `MemoStateResource` | `memo.run` R+W; `tag`, `field`, `match` R when the operand is a memo sum |
| F10 | heap memory | `DefaultResource` (the root) on operands and results | 36 `MemAlloc` results, 10 write and 9 read operands, `dup`, `drop`, `take`, cells, arrays, buffers |
| F11 | the result is the operand at run time | `Idr_NoRuntimeForm`; `Idr_ResultCarriesOperand` (with a `verifyTrait`, `Traits.h:97-105`); `Idr_SameValue` (none); `InferIntRangeInterface` carried; `ViewLikeOpInterface` (borrow); the op's flow edge | 8; 4; 3 |
| F12 | the runtime function that is the op's meaning | `Idr_Runtime<"symbol">` (`IdrBase.td:272-275`, C++ trait `CallsRuntime`) | 119 ops, 119 distinct symbols: a bijection |
| F13 | Idris names the op as a primitive | `Idr_Primitive` | 114; independent of F12 (10 primitives call no runtime function, 15 runtime ops are no primitive) |
| F14 | the result takes a reference of its own | `Idr_TakesReference` | `dup`, `array.get` |
| F15 | builds a value at run time | `Idr_BuildsValue` | `con`, `closure`, `suspend`, `delay`, `cell.init` |
| F16 | a guard and what it guards | `GuardOpInterface` (5), `Idr_Guarded` marks (20 ops), `Idr_GuardedOp` (11) | |
| F17 | what a function's run may do | `Effect` bits {io, crash, diverge} as a property of `idr.func` and of `idr.call`; `bodyEffect` (`Func.cpp:189-202`); the table `rows` (`Func.cpp:250-256`) | |
| F18 | where a value moves | `FlowOpInterface` | 42 ops in ODS, 8 upstream ops by external model |

Effect declarations by kind and resource, over the 189 ops (an op counted
once per kind): `MemWrite<IO>` 80, `MemRead<IO>` 70, result
`MemAlloc<Default>` 36, operand `MemWrite<Default>` 10, operand
`MemRead<Default>` 9, `MemWrite<Crash>` 9, operand `MemFree<Default>` 2,
`MemWrite<Divergence>` 2, result `MemAlloc<Lin>` 2, and one each of a
result `MemWrite<Default>`, `MemAlloc<Default, 0, FullEffect>`,
`MemAlloc<Default, 1, FullEffect>`, `MemFreeAt<0, FullEffect>` and
`MemAlloc<AutomaticAllocationScope, 0, FullEffect>`. 53 lines of `.td`
declare an effect (`grep -rnE 'MemoryEffects<|MemRead|MemWrite|MemAlloc|MemFree'
include | grep '\.td:' | wc -l`).

Speculation: 56 ops declare it (37 always speculatable, 6 recursively:
`match`, `match_lit`, `tabulate`, `tabulate_io`, `fold_last`, `scan_last`;
11 through `GuardedOp`; 2 by a hand `getSpeculatability`: `con`, `field`);
the other 133 declare none and are therefore not speculatable to MLIR. Effects: only
`apply`, `func` and `program` declare no effects at all; 9 ops are
`RecursiveMemoryEffects` (`match`, `match_lit`, `tabulate`, `tabulate_io`,
`fold_last`, `scan_last`, `array.update`, `element.update`, `memo.run`).

### 2.3 The six resources

All six are `Resource::Base<X>` with no `getParent` override and the
default `isAddressable` (`IdrDialect.h:59-99`): **siblings under
`DefaultResource`, all addressable**. Two siblings never conflict
(`SideEffectInterfaces.h` at the pin, `isDisjointFrom`), and every
resource conflicts with `DefaultResource`, the root (*read*, pinned
`mlir/include/mlir/Interfaces/SideEffectInterfaces.h:132-153, 178-195`).

| resource | written by | read by | meaning, as its comment states |
| --- | --- | --- | --- |
| `CrashResource` | 9 ops | `Forms.cpp:60`, `Placement.cpp:90` | "a possible crash writes to" |
| `IOResource` | 80 ops | `Effects.cpp:140, 173`, `MoveOut.cpp:75`, `Forms.cpp:61`, `Placement.cpp:89` | every IO op reads and writes it; a crash and a loop that may not end write it "so that no pass reorders either with output" |
| `DivergenceResource` | `may_loop`, `force` | nothing by name | "so that a loop that may not end is never removed as dead" |
| `LinResource` | `lin.enter`, `lin.use`, `call` (allocations on results) | `Reshape.cpp:302`, `Allocation.cpp:38` | "no heap, only a new value that no pass may merge with another" |
| `ReferenceResource` | consuming ops (frees) | `Reshape.cpp:304` | "a consumed reference is freed from" |
| `MemoStateResource` | `memo.run` | `tag`, `field`, `match` of a memo sum (reads) | the state of a memo cell |

Because the six are siblings, the crash family and `may_loop` write
`IOResource` *as well as* their own resource: the double write is how
"ordered with output" is said when the tree cannot say it
(`IdrInterfaces.td:113-117`, `IdrCheckOps.td:46-47`, `Func.cpp:246-255`).
Readers then have to tell a crash's IO write from an IO op's
(`Forms.cpp:51-62` asks `isa<MayCrashOpInterface>` for it; `classify`
keys "performs IO" on the *read* of `IOResource`, `Effects.cpp:135-142`).

### 2.4 The traits and interfaces, and who reads them

Readers per trait (*measured*: `grep -rn 'hasTrait<' lib include tools
unittests` gives 49 lines; each trait's other readers by name):

| trait / interface | ops | readers in the compiler | readers elsewhere |
| --- | ---: | --- | --- |
| `PerformsIO` | 80 | none | `idris-mlir-tblgen.cpp:1481` (an IO primitive's shape) |
| `ObservableIO` | 68 | `Analysis/Effects.cpp:66` (`observableRuns`) | |
| `CallsRuntime` (`Idr_Runtime`) | 119 | none: the C++ reads the generated `Abi<Op>` table (`RuntimeCalls.cpp:101-153`, `Fold.h:43`) | tblgen's `markOf(op, "Idr_Runtime")` (`idris-mlir-tblgen.cpp:2878`) |
| `Primitive` | 114 | none | tblgen (`:1596`, `:2307`) |
| `NoReturn` | 3 | `Expect/CrashSites.cpp:28`, `Expect/ComputesNothing.cpp:26` | tblgen (`:950`, the C result kind) |
| `TakesReference` | 2 | `Verify/OwnedOps.cpp:240` | |
| `BuildsValue` | 5 | `Expect/Does.cpp:34`, `Expect/Placement.cpp:117` (both test properties) | |
| `SameValue` | 3 | `Grades.cpp:166, 200`, `Commit.cpp:92` | |
| `ResultCarriesOperand` | 4 | 17 sites (Lifetimes, Tail, Sink, Feeds, OwnedOps, Owned, Fold/Bigs, Grades, Narrow ×4, Classes ×2, Conversion/Fields) | |
| `NoRuntimeForm` | 8 | `Conversion/Lower.cpp:69` (a trait-rooted conversion pattern) | |
| `ConsumesOperands` | 8 | MLIR (it supplies `getEffects`) | |
| `GuardedOp` | 11 | MLIR and the ops' folders (it supplies `guardHolds`, `getSpeculatability`) | |
| `MayCrashOpInterface` | 8 | `Func.cpp:194`, `Forms.cpp:52` (`isa` only; `getCrashCause` is called once, on a typed `NatToExtentOp`, `Conversion/Bigs.cpp:44`, never through the interface) | |
| `GuardOpInterface` | 5 | `CrashSites.cpp:28`, `ComputesNothing.cpp:26`, `Expect/Guards.cpp:20`, `Expect/Placement.cpp:259`, `Conversion/Checks.cpp:121` (compile time) | tblgen |
| `RunsLabelsOpInterface` | 2 | `Func.cpp:198`, `Analysis/Effects.cpp:70`, the label solve | |
| `FlowOpInterface` | 42 + 8 | 6 `flowEdgesOf` callers, `consumes` (17 callers) | |

### 2.5 Who reads effects, and how

Readers of MLIR's effects in our tree (*read*, each file at the line):
`classify`/`onlyAllocates`/`performsIO` over `getEffectsRecursively`
(`Effects.cpp:113-142`; callers `Canon/Sink.cpp:71-79, 223`,
`Canon/CaseOfCase.cpp:78, 117, 126`, `Canon/Force.cpp:45`,
`Bufferize/Bufferize.cpp:193`, `Analysis/IdentitiesRecord.cpp:308, 314`,
`Specialize/Consumer.cpp:62`, `Expect/Facts.cpp:39-40`); `mayRunAt`
(`Effects.cpp:161-184`); MoveOut's own classifier (`Canon/MoveOut.cpp:59-101`);
`atMostCrashes` (`StructureLoops/Forms.cpp:46-63`); `orderOf`
(`Expect/Placement.cpp:78-92`); `storedBy` (`Verify/Uses.cpp:52-63`),
`madeStatic` via `isPure` (`Verify/Uses.cpp:74-78`); the owned walk's
`writes` and roles (`Verify/Owned.cpp:106-107, 183, 191-210`);
`Placement::writes` (`Ownership/Placement.cpp:152-161`), `Reshape::movable`
(`Ownership/Reshape.cpp:291-306`); `Expect/Memory.cpp:48-61`,
`Expect/Allocation.cpp:33-41`; `Effects/Constants.cpp:149`
(`wouldOpBeTriviallyDead`); `Narrow/Widths.cpp:48`, `Tail/AccumulatorPlan.cpp:140`,
`Tail/TailLoops.cpp:150`, `Tail/WhileDo.cpp:199`, `Tail/Accumulate.cpp:113`,
`Conversion/TailPosition.cpp:204` (`isMemoryEffectFree`, `isSpeculatable`,
`isOpTriviallyDead`). Upstream passes in the pipeline that read our
effects: the canonicalizer (greedy DCE, region simplification disabled,
`Pipeline.cpp:28-32`) and CSE, twice on `idr.func` (`Pipeline.cpp:92-94,
115-117`), and SCCP's baseline through `Effects/Constants.cpp`.

Readers of the function-level `Effect` bits: `Func.cpp:207-230`
(`componentEffects`, `writeEffects`), `Analysis/Effects.cpp:36-47`, the
pass `Transforms/Effects/Effects.cpp:28-41`, `Verify/Program.cpp:58-69`
(`effectsCovered`), `Call.cpp:54-57` (`verifySymbolUses`), `Call.cpp:65-72`
(the call's `getEffects` through `rows`), `IdentitiesRecord.cpp:160`,
`Specialize/Consumer.cpp:59-62`, `Tail/Frames.cpp:320`,
`Tail/FramesPlan.cpp:158`, `Contracts/Contracts.cpp:169-246`,
`Expect/SolvedEffects.cpp:29`.

Readers of the world as an effect: `bodyEffect` (a world parameter means
IO, `Func.cpp:191`; `world.new` means IO, `:196`), `Canon/MoveOut.cpp:104-113`
(the world chain finds the next IO), `Specialize/Consumer.cpp:48`,
`Analysis/Identities.cpp:30`, `Specialize/Keys.cpp:201`, `rootKind`
(`Func.cpp:279-283`), tblgen's IO primitive shape (`idris-mlir-tblgen.cpp:1446-1458`).
42 C++ lines name the world (`grep -rn 'holdsWorld\|isWorld(\|WorldType\b\|WorldNewOp'
lib include | grep -v '\.td:' | wc -l`); the Idris side names it on 391
lines in 21 files (`grep -rw -e World -e world compiler/src | wc -l`).

### 2.6 State, threading, cost

No state of its own: every answer is recomputed per query. A
`getEffects` of a consuming op builds the op's whole `FlowEdges` list
(`Effects.cpp:47-48`, a `SmallVector<Edge, 4>`) and walks it; `consumes(operand)`
does the same for one operand, so asking every operand of an op is
quadratic in its operand count (`Effects.cpp:86-90`). `classify` and
`mayRunAt` call `getEffectsRecursively`, a walk of every region of a
`RecursiveMemoryEffects` op, per query (`Effects.cpp:115, 168`). The flow
interface's verifier runs per op per verification (`IdrFlow.td:49-52`).
`effectsCovered` walks every function's body twice per program
verification, on one thread (`Verify/Program.cpp:58-69`, run from
`ProgramOp::verifyRegions`, `Func.cpp:105-120`). `observableRuns` is
parallel per function, read-only (`Analysis/Effects.cpp:63-73`). Nothing
here takes a lock.

### 2.7 History

20 commits touch the subsystem's files (`git log --oneline --
<paths> | wc -l`). The design is recent and deliberate: 1e5a8a8e's §9
(the 0004 representation wave, 2026-10-18) decided "idr.call carrying its
own effects with the second effects API" deleted: contracts S6 (effects
one property on a function and a call, a call's `getEffects` the bit
table plus `consumedEffects` plus a fresh linear result,
`verifySymbolUses` holding the call to its callee) and S7 (`bodyEffect`
once, "one table maps `Effect` bits to MLIR resources and back"), landed
in 2c042728. 955e2b92 made the memo state a resource (marked WIP in its
own message: "whether builtStateHolds can be read off the resource"
remains). 1feec99c narrowed `mayRunAt`. 7987388b added `Idr_BuildsValue`
to replace two hand lists in idr-expect. 1cd1193a ("one effects rule read
by analysis and verifier") is the origin of `bodyEffect` as the verifier's
rule.

## 3. Reconciliation with the proposal

### 3.1 The brief (§2) and §3

- **Counts.** `hasTrait<` 49: holds (*measured*, §2.4's command). 15
  native traits or trait lists and 12 interfaces: hold (*read*: the 12
  `NativeOpTrait`s of `IdrInterfaces.td`, `IdrBase.td:272-293` and
  `IdrCheckOps.td:19`, the three `TraitList`s at `IdrInterfaces.td:116,
  315, 337`; two type and ten op interfaces). `getEffects`/`MemoryEffects`
  139: *measured* 155 lines over `lib include tools unittests`, 129 in C++
  alone (`grep -rnE 'getEffects|MemoryEffects' ... | wc -l`); the brief's
  method is not stated. 72 effect declarations: *measured* 53 `.td` lines
  (§2.2's command); by record, 81 ops carry a `MemoryEffects` trait and
  the operand and result decorators add 64 more (an op counted once per
  kind, §2.2).
- **"Right already: `GuardedOp`".** Holds (`Traits.h:153-199`: the guards
  are a compile-time tuple generated per op, `IdrGuards.inc`; the folder
  and `getSpeculatability` read it). It is upstream's model for a total
  op (`arith.divsi`: `NoMemoryEffect` plus `ConditionallySpeculatable`,
  §5.2 A7), applied to all 11 guarded ops.
- **"`Idr_ConsumesOnly` and `Idr_ResultCarriesOperand` as `TraitList`s".**
  Holds (`IdrInterfaces.td:315-316, 337-338`). `Idr_ConsumesOnly` is
  already recipe row 3 (§5.2.3): a native trait supplies `getEffects` for
  a family, the interface listed plain.
- **"Effect resources rather than effect flags".** Holds in part. The
  six resources exist (`IdrDialect.h:59-99`), but function and call
  effects are a second, flag form (`Effect` bits, `IdrAttrs.td:200-209`)
  with a hand table between them (`Func.cpp:250-256`), and the resources
  form no tree (§2.3), so every crash writes two of them.
- **"The `Decides` trait, declared in ODS, with a `verifyTrait`".**
  Refuted: no `Decides` exists (`grep -rn Decides foreign/idr/include
  foreign/idr/lib foreign/idr/tools` finds one comment, `Symbols.h:197`).
  The one native trait with a `verifyTrait` is `ResultCarriesOperand`
  (`Traits.h:97-105`).
- **"`SameValue` states a checkable fact with no `verifyTrait`".** Holds
  (`Traits.h:111-112`). What is checkable: every `SameValue` op also lists
  `Idr_ResultCarriesOperand` (borrow, lin.enter, lin.use:
  `IdrOwnershipOps.td:98, 403, 416`) but nothing makes that a dependency
  (`dependentTraits` is empty), and the "exclusivity kept" half is the
  complement of `share`'s predicate `forgets` (`IdrOwnershipOps.td:118-122`,
  `Grades.cpp:113-116`).
- **"`isa<>` ladders restating trait classes".** Holds in part.
  - `isa<ReturnOp, YieldOp>`: five copies, not four (`lib/IR/Tail.cpp:39,
    269`, `Tail/Frames.cpp:119`, `Tail/Accumulate.cpp:104`,
    `Tail/Trmc.cpp:177`). Both ops are the only `idr` ops with
    `ReturnLike` (*measured*: 2 ops carry it), but after structure loops a
    body may hold upstream `ReturnLike` terminators (`scf.yield`), so
    `hasTrait<ReturnLike>()` alone is not equivalent: the ladder means "a
    terminator of an `idr.func` or an `idr.match` region", a fact of the
    parent (lane 10's).
  - `Canon/Sink.cpp:114` `isa<ConOp, ClosureOp>` restates no trait: two
    of the five `BuildsValue` ops, the ones a later fold meets by shape;
    0003's owed `meets` interface method (`Canon/Feeds.cpp`) is the
    classification (lane 04's).
  - `StructureLoops/Forms.cpp:132` is `GeneratingOpInterface` (4 ops)
    plus `TransposeOp`: an interface that misses one member (lane 11's).
- **"Three representations of does IO".** Holds, and the code holds
  four, which disagree (*measured*, §2.2 F1-F4):
  `PerformsIO` is exactly "has a world operand or result" (80 = 80, the
  same ops), so the trait restates the operand types; `IOResource` is
  written by 80 ops and read by 70, the write alone meaning "ordered with
  output"; a world parameter is IO to `bodyEffect` (`Func.cpp:191`); and
  `ObservableIO` (68) is a fourth classification. Ten `PerformsIO` ops
  declare no `IOResource` effect (`array.get/new/set/update`, the five
  `io.buffer_*`, `tabulate_io`: their effects are on the buffer or array
  value, `IdrIOOps.td:138-147`), and `handle.string` reads `IOResource`
  with no world (`IdrPlatformOps.td:363-374`).
- **"Traits read once or never".** Holds and is wider: `TakesReference`
  1 reader, `ObservableIO` 1, `BuildsValue` 2 (both test properties);
  `PerformsIO`, `CallsRuntime` and `Primitive` have no C++ reader at all
  (tblgen reads them); `MayCrashOpInterface`'s one method is never called
  through the interface (§2.4).
- **§3, e96bb991.** The flow reading asks the control-flow interface per
  point, not per pair: `forwardFrom` enumerates a point's successors once
  (`Flow.cpp:44-52`); `successorInputs` is per region of one op
  (`Flow.cpp:96-109`), linear. Holds as the right shape.

### 3.2 §5.1 (mlir-analysis)

- **D1.** Holds: the pin's resources have `getParent`, `isDisjointFrom`,
  `isAddressable`; we use none (§2.3).
- **D2.** In our pipeline the upstream readers of our effects are the
  canonicalizer's DCE and CSE (`Pipeline.cpp:28-32, 92-94, 115-117`) and
  SCCP's cleanup inside `Effects/Constants.cpp:149`. LICM, control-flow
  sink, the inliner pass, alias analysis and bufferization do not run on
  `idr` ops (none is added; sinking is ours, `Canon/Sink.cpp`). So what
  declaring buys today is DCE and CSE; the rest is our own readers
  (§2.5). Once declared as §5 proposes, the upstream readers that gain
  (*conjecture*, from §5.1 D2 and §5.2 A3, A6): CSE, which merges a heap
  read across output and crashes and a memo read across output once
  those are disjoint subtrees (T1); the canonicalizer's DCE, unchanged
  under ods-Q1's "kept" and deleting dead guards and `may_loop` under
  "deletable"; `remove-dead-values` per function if §5.1 item 4 brings it
  back (it reads `wouldOpBeTriviallyDead` and `isMemoryEffectFree`);
  local alias analysis, should any pass use it, which treats a
  non-addressable resource as never aliasing memory (E2); upstream's
  control-flow sink and LICM only if a pass runs them on `idr` ops (our
  `Canon/Sink.cpp` does the sinking today, lane 04); and LLVM, through
  the function attributes T2's bits lower to (0003's owed item).
- **D3, W4.** Holds: 9 `RecursiveMemoryEffects` ops (§2.2). Besides
  upstream's DCE and CSE, our `classify`, `onlyAllocates`, `performsIO`
  and `mayRunAt` (`Effects.cpp:115, 168`), MoveOut's `doesOf`
  (`MoveOut.cpp:86-99`), `atMostCrashes` and `computes`
  (`Forms.cpp:46-75`) and `orderOf` (`Placement.cpp:85`) walk them per
  query. Their stage-1 counts need a built compiler (§8).
- **5.1.2 item 6.** Holds in part: the resources are already disjoint
  (siblings) and addressable (the default). Non-addressable is true only
  of `IOResource`, `CrashResource` and `DivergenceResource`, which no
  effect gives a value; `MemoState`, `Reference` and `Lin` effects carry
  an operand or result (`Effects.cpp:83, 103`, `Call.cpp:71`,
  `IdrOwnershipOps.td:410, 422`), which a non-addressable resource
  forbids (§5.2 A3).
- **W5 (attributes on a hot path), for this subsystem.**
  `ReturnOp::getFlowEdges` calls `FlatSymbolRefAttr::get` on every query
  (`FlowOps.cpp:97`): a uniquer lookup per call, under a shard's reader
  lock (§5.1 F3); every `consumes` of a return operand pays it.

### 3.3 §5.2 (mlir-ods)

- **A3, A8.** Hold: the hierarchy is C++ only, and siblings never
  conflict. Our readers mix `isa<IOResource>` (hierarchy-aware,
  `Effects.cpp:140, 173`, `Placement.cpp:89-90`) and identity tests
  (`effect.getResource() == IOResource::get()`, `MoveOut.cpp:75`,
  `Forms.cpp:60-61`), which agree only while there is no tree.
- **A4.** Holds: `Idr_MayCrash` bundles the interface and a
  `MemoryEffects` trait (`IdrInterfaces.td:116-117`).
- **A5, W1.** Holds: no op mixes ODS effects and a hand `getEffects`
  (tblgen would refuse). The hand forms, classified (W1):
  - static, declarable in ODS today: `MemoRunOp` (`OpsClosures.cpp:260-265`:
    `Read`+`Write` `MemoState` on `$cell`), `ArrayUpdateOp`,
    `ElementUpdateOp` (`OpsArrays.cpp:185-188, 229-232`, through
    `updateEffects`, `:78-84`: `Read`+`Write` `Default` on `$array`), each
    beside `RecursiveMemoryEffects`;
  - type-dependent (row 3): `ConOp` (`OpsCon.cpp:50-56`: an allocation
    when the result is a box; consumption), `FieldOp`, `TagOp`
    (`OpsConReads.cpp:35-38, 157-160`), `MatchOp` (`OpsMatch.cpp:135-138`,
    beside `RecursiveMemoryEffects`): a memo read when the operand is a
    memo sum; `OwnGiveOp` (`OpsOwnership.cpp:232-235`): exactly
    `ConsumesOperands`' body; the trait itself (`Traits.h:87-90`);
  - property-dependent: `CallOp` (`Call.cpp:65-72`): its `effects`
    property through `rows`, then consumption, then a fresh linear result;
  - upstream's own idiom: `VectorizeLanesOp` (`Target/Schedules.cpp:303-308`:
    `consumesHandle`, `producesHandle`, `modifiesPayload`), which
    `FunctionalStyleTransformOpTrait` supplies (§5.2 A9);
  - an upstream gap: `NeverRuns` (`FlowOps.cpp:344-346`), an external
    model of `MemoryEffectOpInterface` on `ub.unreachable`.
- **A6, ods-Q5.** Holds: four declarations carry a stage or a full-region
  bit (`IdrOwnershipOps.td:192, 211, 230-231`) and nothing reads either
  (`grep -rn 'getEffectOnFullRegion\|getStage()' foreign/idr/lib` finds
  only `ProgramOp::getStage`, the program's stage).
- **A7.** Both of MLIR's models are already in use: the 11 total ops
  speculate (upstream's), the guards and crashes write resources and are
  never dead (ours). ods-Q1 decides between them for the guards.
- **A9.** Holds in part: consumption is a `Free` on the consumed
  `OpOperand` (`Effects.cpp:103`), without the transform dialect's `Read`
  beside it, and only after idr-rc (an owned grade), so it is
  type-derived, row 3, already.
- **B4.** Our lowering already reads ODS at compile time:
  `if constexpr (OpT::template hasTrait<GuardOpInterface::Trait>())`
  (`Conversion/Checks.cpp:121`) and `requires { Abi<OpT>::entry; }`
  (`Conversion/RuntimeCalls.cpp:153`), folded over `GET_OP_LIST`.
- **W10.** One interface `body` uses `$_op`
  (`IdrInterfaces.td:241`, `UpdateOpInterface::getArray`, 2 ops): two
  instantiations, negligible; `$_raw_op->getOpOperand(0)` would share it.
- **M1.** Holds in part. At the op level the world produces no effect
  today: IO ops declare `IOResource` statically through their class
  (`IdrIOOps.td:19-23`), and the ten world-threaded memory ops declare
  value effects; only the function level reads the world
  (`bodyEffect`). So the world trait of row 3 is needed only if the
  function summary keeps reading types; deriving the summary from the
  ops' effects (§5, T2) makes it unnecessary.
- **M2.** Holds in part, mis-aimed on `Lin`: in our code consumption is
  `ReferenceResource` (`Effects.cpp:103`), and `LinResource` is the fresh
  linear result (`IdrDialect.h:76-80`), a resource standing in for
  identity (§5.8 EF5).
- **M3.** Holds: the double IO write is its symptom (§2.3).
- **M4.** Holds (§2.4's table).
- **M5.** Holds in part (§3.1).
- **M7.** Holds in part. The symbol is one record (`IdrBase.td:272-275`),
  and the C++ reads a generated, typed table, `Abi<Op>`, instantiated per
  op over `GET_OP_LIST` (`RuntimeCalls.cpp:146-165`): monomorphized and
  checked at compile time, better than M7's interface-rooted pattern,
  which dispatches at run time. What is wrong is smaller: the C++ trait
  `CallsRuntime` (`Traits.h:34-40`) is empty and never queried, so the
  mark need not be a trait.
- **M8.** The IO families are TableGen classes already (`Idr_IOOp`,
  `Idr_PlatformIOOp`, `Idr_HandleQueryOp`, `Idr_ReadingOp`, ...,
  `IdrPlatformOps.td:29-60`) with one `def` per member (lane 03's).

### 3.4 §5.3, §5.4, §5.5, §5.6, §5.7

- **§5.3 S0.** Holds in part: the world is an SSA chain of the 79 ops
  that take it, and MoveOut uses it as one (`MoveOut.cpp:11-13,
  104-113`); the crash family, `may_loop`, `force` and `handle.string`
  are ordered by effects alone, and the buffer ops by the world and their
  value effects.
- **§5.3 I1, I8.** See §3.1 for I1. I8 holds for the runtime ABI (one
  record set, generated into C, C++ and Idris by idris-mlir-tblgen,
  `idris-mlir-tblgen.cpp:2750-2995`).
- **§5.4 F12, item 9, and its wave-2 question** ("a hand `getEffects`
  because an attribute changes an op's meaning"): the only property that
  changes effects is `idr.call`'s `effects`, a cache of the callee's held
  by one writer and checked by `verifySymbolUses` (`Call.cpp:54-57`).
  One unit attribute changes a function's effects: `idr.func`'s `total`,
  whose absence is `diverge` (`Func.cpp:190`), essential (it is Idris's
  proof, §5.8 O1's question for this lane); no other unit attribute,
  optional operand or enum of an op changes its effects. The
  type-dependent bodies (§3.3) depend on operand and result types.
- **§5.5 D1, D4a.** D1 is already applied in two places (§3.3, B4); D4a
  holds for the runtime symbol.
- **§5.6 E3, E4, F1.** E3's per-op cache of recursive effects would serve
  `classify` and `mayRunAt`. E4: we write 5 type-dependent bodies (HLFIR:
  24). F1's baseline: ClangIR has 1 hand `getEffects` over 315 ops; we
  have 9 bodies (8 ops, one trait) over 189, plus one upstream-idiom op
  and one external model.
- **§5.6 W-E4.** No discardable attribute carries an effect fact here:
  `effects` is an inherent property (`IdrOps.td:162, 219`), `total` an
  inherent attribute.
- **§5.6 W-E6.** See §5.1 W4 above.
- **§5.7 C6.** The world is the VSDG's state edge for the 79 ops that
  take it, and only for them.

### 3.5 §5.8 (dialect-design)

- **B11.** Holds: our world crosses calls (a function takes it,
  `rootKind`, `Func.cpp:279-283`), region arguments
  (`OpsTabulate.cpp:173`) and region results (a match yields it), which
  the builtin `token` forbids.
- **C3, O2.** `cell.new` and `cell.stack` differ only in resource and
  result constraint (`IdrOwnershipOps.td:182-212`): lane 03's.
- **C4, EF3.** Refuted in part: "`ConsumesOperands`, `ConsumesOnly`
  become `MemFree<Idr_Linear>` declarations" does not fit, because
  consumption is not static per op: it depends on the operand's grade
  (owned only after idr-rc, `Effects.cpp:98`) and on which uses the op's
  flow takes over (`eachTaken`, `Effects.cpp:45-75`; a call's argument
  only when its parameter owns it, `:32-37, 55-57`). An ODS
  `Arg<..., [MemFree<...>]>` would declare it on every operand at every
  stage. The type-derived trait is the right form; and `Lin` is not
  consumption (§3.3, M2).
- **C6.** A crash writes `Crash` and `IO`, not the default resource
  (`IdrInterfaces.td:117`).
- **F2.** Our consumption and memo reads are FIR's volatile pattern: an
  effect computed from a type by one helper (`consumedEffects`,
  `readsMemoState`, `Effects.cpp:79-105`).
- **F7, EF5.** Two fake resources: `LinResource` (fresh identity) and
  `DivergenceResource` (keeps `may_loop`; nothing reads it by name).
  `MemoState` is real state.
- **EF2.** No tree today (§2.3).
- **EF4.** Holds: four representations of does IO (§3.1).
- **T6, DS2.1.** The call already carries its callee's effects as an
  inherent property verified in `verifySymbolUses` (`Call.cpp:29-59`):
  DS2.1's mechanism is today's code (1e5a8a8e's S6). What DS2.1 adds is
  deleting the world.
- **DS4.** `Primitive implied by Idr_Runtime`: refuted (*measured*: 10
  primitives call no runtime function, 15 runtime ops are no primitive,
  §2.2 F13). `MayCrash` as an effect: holds (two carriers, three sets).
  The forwarding interface over `SameValue`, `ResultCarriesOperand` and
  the flow edges: holds in part (§5, T6). `NoReturn`: 3 ops, 3 readers.
- **5.8.4's question** "where `MayCrash`, `PerformsIO`, `ObservableIO`,
  `ConsumesOperands` and the world operands are read, mapped to the
  effect queries that would replace them":

| fact | read at | the effect query that replaces it |
| --- | --- | --- |
| `MayCrashOpInterface` | `Func.cpp:194` (crash bit), `Forms.cpp:52` (which IO write is a crash's) | a `Write` on `Crash` in the op's effects; with a tree (§5, T1) no IO write to tell apart |
| `PerformsIO` | tblgen `:1481` (IO primitive shape) | a world operand or result (the same set, measured), read off the ODS constraints as `ioResultOf` already does (`:1446-1458`) |
| `ObservableIO` | `Analysis/Effects.cpp:66` | an effect on the outside resource (§5, T1) |
| `ConsumesOperands` | MLIR, through the trait's `getEffects` | unchanged: it is the query |
| world operands | `bodyEffect` (`Func.cpp:191, 196`), MoveOut, Consumer, Identities, Keys, `rootKind`, tblgen | `bodyEffect`: the body's declared effects (§5, T2); the others read the world as a value, not as an effect, and stay or go with DD-Q3 |

### 3.6 §5.10, §5.11, 0003

- **§5.10 R1.5.** Today `dup` and `drop` write the default resource, the
  root (`IdrOwnershipOps.td:74, 89`); there is no `is_unique` op
  (`idris_rt_is_unique` is a lowering helper, `IdrRuntime.td:76-77`).
- **§5.10 W5.** The owned verifier reads consumption through
  `consumes()` (`Verify/Uses.cpp:27`), from the flow edges; the `Free`
  effect is derived by the same function (`eachTaken`), so one fact with
  two read paths that cannot disagree.
- **§5.11.** Holds: a box's allocation is `Allocate` on the default
  resource with no `Crash` (`OpsCon.cpp:50-56`); `nat.to_extent`'s crash
  ("array too large", `OpsArrays.cpp:242`) is a program-meaning crash.
- **0003 items.** All confirmed: MoveOut's second classifier (the
  enum is duplicated with the same name and cases, `Flow.h:83`,
  `MoveOut.cpp:60`; its `ub.unreachable` case and the comment calling it
  "doing anything" are stale, since `NeverRuns` is registered with the
  dialect on every registry, `InitIdr.h:22-26`; its `isa<ForceOp>`
  remains because `force` writes but does not read `IOResource`,
  `IdrClosureOps.td:102-103`); resources read as bits by hand
  (`Placement.cpp:78-92`, `Forms.cpp:46-63`); three crash sets (§2.2
  F5); `holdsLabels` (`Flow.cpp:90-92`) equal to `carriesLabels`
  (`Labels.h:59-61`); `knownNonEmpty` per question (`Crashes.cpp:18-43`);
  the effects pass preserving only `SymbolTable`
  (`Transforms/Effects/Effects.cpp:39`); and no lowering reads a
  function's `effects` or `total` (`grep -rn 'getEffects()\|Effect::\|getTotal()'
  foreign/idr/lib/Conversion` finds nothing).

### 3.7 A finding no lane made: the function summary can lose an op's effect

`bodyEffect` does not read the body's declared effects. It reads `total`
and four other facts: a world parameter, `MayCrashOpInterface`,
`WorldNewOp`, `RunsLabelsOpInterface` (`Func.cpp:189-202`). The verifier
holds a function's `effects` to that same rule (`Verify/Program.cpp:58-69`),
not to its ops. So an op whose effect none of the four sees is dropped at
the function's boundary. `handle.string` is one (*read*): it reads
`IOResource` "so it stays before the slot's release in the order of IO"
(`IdrPlatformOps.td:363-366`), and Idris reaches it from the pure
`prim__getString` (`compiler/src/IdrisMLIR/Registry/Primitives.idr:373-375`),
so a function holding it and no world gets `effects<none>` (if total);
every call of it then declares no effect (`Call.cpp:65-72`), and CSE,
DCE, `onlyAllocates` and `mayRunAt` may move or merge the call past an
`io.handle_free` of the same slot. *Conjecture*: a miscompile needs a
program that reads a string handle in a helper that is not inlined and
frees it after; none is in the tests. A second, latent case: `idr.exit`
never returns, but neither `crash` nor `diverge` covers it (it is no
`MayCrashOpInterface`, `IdrPlatformOps.td:282-287`), so a function that
always exits says it returns (`IdentitiesRecord.cpp:160` reads
`returns = !diverge`); harmless while no lowering maps the bits to LLVM's
`willreturn`, unsound once 0003's "function facts lowered" lands.

A third case is structural. The bit set has no bit for memory, so what a
callee does to memory its arguments reach is carried across a call only
by accident of the tree's root: a buffer or array op writes
`DefaultResource` (`IdrIOOps.td:157-197`), the root, which conflicts with
the `IOResource` write a call of a world-taking callee declares. The memo
state has no such luck: `MemoStateResource` is a sibling of
`IOResource`, `memo.run`'s write of it is lost at its function's
boundary, and a call of a memo dispatch declares nothing a `tag` or
`field` read of the cell conflicts with (`Call.cpp:65-72`), so CSE, which
lets a read cross writes to disjoint resources (§5.1 D2, §5.2 A3), may
merge a read before the call with one after it. *Conjecture* that no
pipeline reaches it today (memo reads live in the dispatch functions
defunctionalization writes, and `tests/effects-memo-state` holds the
inline form only); it is the reason the resource tree (§5 T1) cannot land
without a summary that covers memory (§5 T2).

## 4. Issues

Every item is *read* at the cited line unless marked; counts are §2's.
Items in another lane's files are listed where they read this lane's
facts, with the owning lane named; their algorithms are not judged here.
No per-target case and no budget occurs in this subsystem's files
(`grep -n -i 'apple\|darwin\|linux\|x86\|aarch64\|arm64\|limit\|budget'`
over them finds none).

| ID | file:line | category | what | proposed disposition |
| --- | --- | --- | --- | --- |
| **The resources** | | | | |
| E1 | `include/idr/IR/IdrDialect.h:59-99` | ods | six resources, all siblings under `DefaultResource`; "ordered with output" cannot be said, so 10 ops write `IOResource` beside their own (`IdrInterfaces.td:117`, `IdrCheckOps.td:46-47`, `IdrClosureOps.td:102-103`, `Func.cpp:253-255`) | one resource tree in one header (§5 T1); every double write goes |
| E2 | `IdrDialect.h:59-75` | ods | `IOResource`, `CrashResource`, `DivergenceResource` are addressable (the default) though no effect on them names a value | `isAddressable() == false` on the outside subtree (T1) |
| E3 | `IdrDialect.h:72-75` | ods | `DivergenceResource` has no reader by name; it exists to keep `may_loop` and `force` alive | a child of the outside resource (T1), or speculation only, by ods-Q1/DD-Q2 |
| E4 | `IdrDialect.h:76-80`; `IdrOwnershipOps.td:410, 422`; `Call.cpp:69-71` | ods | `LinResource`: a resource standing in for a fresh value's identity (§5.8 EF5); two readers exclude it as "not memory" (`Reshape.cpp:302`, `Allocation.cpp:38`) | the fresh-linear-result rule derived from the result type by the typed-effects trait (T3); the resource kept only as the tree's "values, not memory" node |
| E5 | `IdrOwnershipOps.td:74, 89` | ods | `dup` and `drop` read, write and free `DefaultResource`, the root, so a count conflicts with every effect, IO and crash included (§5.10 R1.5) | a count resource in the heap subtree (T1); counting lanes 07/08 decide its readers |
| E6 | `IdrOwnershipOps.td:192, 211, 230-231` | ods | four declarations carry an effect stage or a full-region bit; nothing reads either (§3.3 A6) | by ods-Q5: keep as documentation or delete |
| **Does IO** | | | | |
| E7 | `IdrInterfaces.td:295-297`; `Traits.h:52-60` | rederivation, dead | `PerformsIO` is exactly "takes or gives a world" (80 = 80 ops, measured); no C++ reader | delete; idris-mlir-tblgen reads the world constraint (E9) |
| E8 | `IdrInterfaces.td:306-308`; `Traits.h:62-70` | ods | `ObservableIO` (68) restates "reads and writes the outside", with `io.strerror` left out by hand (`IdrPlatformOps.td:311-313`) | an effect on the outside resource (T1); delete the trait |
| E9 | `tools/idris-mlir-tblgen.cpp:1481` | rederivation | the IO primitive's shape read from `PerformsIO`, though `ioResultOf` reads the world constraints already (`:1446-1458`) | read "has a world operand" (lane 14 owns the tool) |
| E10 | `lib/Analysis/Effects.cpp:66` | rederivation | `observableRuns` asks `hasTrait<ObservableIO>()` | ask the op's effects for the outside resource |
| E11 | `IdrPlatformOps.td:363-374` | ods | `handle.string` reads `IOResource` with no world: the runtime's handle table treated as the outside | a runtime-state child of the outside resource (T1) |
| E12 | `IdrPlatformOps.td:311-321` | ods | `io.strerror`: IO in the world's order but not observable, said by omitting a trait | the same runtime-state child (T1) |
| E13 | `IdrIOOps.td:220-232` | ods | `world.new` writes `IOResource` only to be ordered and kept | a child of the outside resource that orders without being IO (T1); goes with the world if DD-Q3 says so |
| E14 | `IdrIOOps.td:138-147`, `IdrArrayOps.td:119, 272-288` | ods | ten world-threaded ops (buffers, arrays, `tabulate_io`) are IO to Idris and memory to MLIR: value effects on `DefaultResource`, ordered by the world | keep the value effects; the buffer and array memory joins the heap subtree (T1); DD-Q3 evidence |
| **May crash, may not end** | | | | |
| E15 | `IdrInterfaces.td:105-117` | dead, rederivation | `MayCrashOpInterface`: `getCrashCause` is never called through the interface (once on a typed op, `Conversion/Bigs.cpp:44`); its membership restates `Write<Crash>` | delete the interface; "may crash" is the `Crash` effect; each op's cause stays an op accessor |
| E16 | `lib/IR/Func/Func.cpp:194`; `StructureLoops/Forms.cpp:52` | rederivation | the two readers of "may crash" ask the interface, not the effect; `force` writes `Crash` without it | read the effect (T2) |
| E17 | `lib/IR/Crashes.cpp:45`; `IdrCheckOps.td:37-39, 88-90`; `OpsArrays.cpp:242` | dead | `getCrashCause` defined in three places (C++, two `extraClassDefinition`s) for an interface method nothing calls | delete with E15 |
| E18 | `IdrCheckOps.td:19`; `Traits.h:42-50` | ods | `NoReturn`: 3 ops (`crash`, `crash_str`, `exit`), each followed by `ub.unreachable`; readers: tblgen's C result kind (`:950`), two test properties | terminators with no successors (§5.8 DS4, lane 03 decides); tblgen reads that |
| E19 | `IdrPlatformOps.td:282-287` | ods | `exit` never returns but is neither `crash` nor `diverge` to the function summary; `IdentitiesRecord.cpp:160` then says a function that always exits returns | an explicit effect for ending the process (T1); owner question NQ2 |
| E20 | `Expect/CrashSites.cpp:28`; `Expect/ComputesNothing.cpp:26` | ladder | "may crash" as `NoReturn ∪ GuardOpInterface`: a third set (§2.2 F5), the 0003 disagreement | read the `Crash` effect (lane 19 owns the files) |
| E21 | `IdrCheckOps.td:46-50` | ods | `may_loop` writes `Divergence` and `IO`; "lowers to llvm.sideeffect" | one write on the tree's divergence node (T1), or speculation only (ods-Q1) |
| **The function summary** | | | | |
| E22 | `Func.cpp:189-202` | rederivation | `bodyEffect` reads `total`, world parameters, `MayCrashOpInterface`, `WorldNewOp`, `RunsLabelsOpInterface`, not the body's effects; `handle.string`'s read is lost at the boundary (§3.7, *conjecture* of a miscompile) | derive the summary from the ops' declared effects plus `total` (T2) |
| E23 | `Func.cpp:236-265` | list | `rows`: a hand table from bits to effect instances; its reverse is written by hand three times (E22, E24, E25) | one generated two-way table (T2) |
| E24 | `Expect/Placement.cpp:78-92` | rederivation | `Order`: resources read back as bits by hand (0003) | the generated reverse table (T2); lane 19 owns the file |
| E25 | `StructureLoops/Forms.cpp:46-63` | ladder | `atMostCrashes` tells a crash's IO write from an IO op's by `isa<MayCrashOpInterface>` | with the tree a crash writes only `Crash`; the predicate becomes "every write is on `Crash`" (lane 11 owns the file) |
| E26 | `IdrAttrs.td:200-209`; `IdrDialect.h:55` | list | the `Effect` bit enum and `anyEffect` beside the resources: a second vocabulary for three of them | generate the bits from the resource records (T2) |
| E27 | `Func.cpp:196` | rederivation | `isa<WorldNewOp>` means IO, though `world.new` declares its effect | read the effect (T2) |
| E28 | `Func.cpp:191` | rederivation | a world parameter means IO: the type read for an effect the body's IO ops declare themselves | delete with T2; a function that only passes a world on takes its callees' effects |
| E29 | `Verify/Program.cpp:58-69` | state, rederivation | `effectsCovered` walks every function twice per program verification, on one thread, against the summary rule, never against the ops | check each function against its derived effects in `FuncOp::verifyRegions`, parallel per function (T2; lane 13 on verification's cost) |
| E30 | `Transforms/Effects/Effects.cpp:39` | rederivation | the pass preserves only `SymbolTable`, so contify rebuilds `CallCycles` (0003) | lane 06's; noted |
| **Runs a label** | | | | |
| E31 | `IdrClosureOps.td:101-104` | ods | `force` declares `Write` on `Crash`, `Divergence`, `IO` but no `Read` of `IO`, unlike an unsolved call (`rows`: `io` is read and write); so `performsIO(force)` is false and MoveOut special-cases it (`MoveOut.cpp:89`) | `force`'s effects are `anyEffect`'s, supplied by the runs-label trait (T4) |
| E32 | `IdrClosureOps.td:124-158` | ods | `apply` declares no effects (unknown): the other form of "runs a label: anything" | the same trait (T4) |
| E33 | `Func.cpp:198` | rederivation | `bodyEffect` restates "runs a label means anything" | read the effect (T2, T4) |
| **The classifiers** | | | | |
| E34 | `lib/IR/Canon/MoveOut.cpp:59-101` | rederivation, ladder | a second classifier beside `classify`: its own `Does`, its own walk, `isa<ub::UnreachableOp>` (stale: `NeverRuns` is always registered, `InitIdr.h:22-26`), `isa<ForceOp>` (E31) | one classifier taking MoveOut's question as a parameter (T5; lane 04 owns the pattern) |
| E35 | `include/idr/IR/Flow.h:83`; `MoveOut.cpp:60` | dead | `enum class Does` declared twice, same name, same cases | one declaration (T5) |
| E36 | `lib/IR/Effects.cpp:113-142` | ods, state | `classify` keys "performs IO" on a `Read` of `IOResource`, the coordinate that tells IO from ordering; every call walks `getEffectsRecursively` | with the tree, "performs IO" is an effect on the outside subtree, not on its ordering children (T1, T5); the walk cached per op per pass where hot (§5.6 E3) |
| E37 | `Effects.cpp:113-114`; `Flow.h:84-87` | cpp | `classify` takes a `function_ref` predicate; two callers, two lambdas | a template on the asker, or an enum of the questions (T5) |
| E38 | `Effects.cpp:161-184` | state | `mayRunAt` walks every op between per query and treats any `isa<IOResource>` effect as IO | keep (an essential ordering question, lanes 09/10 call it), read on the tree |
| E39 | `Effects.cpp:148-157` | cpp | `sourcesOf`: a `std::get_if` chain over the `Source` variant | one exhaustive `match` (§5.5 D2) |
| **Consumption and type-derived effects** | | | | |
| E40 | `Traits.h:84-91`; `IdrInterfaces.td:314-316` | ods (right already) | `ConsumesOperands` supplies `getEffects` from the flow and the owned grade: recipe row 3 | becomes the typed-effects trait's consumption part (T3) |
| E41 | `lib/IR/OpsOwnership.cpp:232-235` | ods | `own.give`'s hand body is exactly `ConsumesOperands`' | list the trait; delete the body |
| E42 | `lib/IR/OpsCon.cpp:50-67` | ods | `con`'s effects and speculatability branch on box against sum, a type fact | the typed-effects trait: a result the op's flow declares `Fresh` and whose type is a cell pointer is allocated (T3) |
| E43 | `IdrClosureOps.td:37, 54, 72` | ods | `closure`, `suspend`, `delay` build a cell and declare no allocation, so CSE may merge two before idr-rc and the allocation test special-cases two of them (E44) | the same rule (T3): their flow already declares the result `Fresh` (`FlowOps.cpp:74, 164`) |
| E44 | `Expect/Allocation.cpp:28-33` | ladder | `isa<ClosureOp>`, `isa<SuspendOp>` special cases, "Pure as a value but built in a cell"; `delay` is not among them (*conjecture*: a property that misses a delay's cell) | deleted by T3 (lane 19 owns the file) |
| E45 | `IdrBase.td:293`; `Traits.h:119-123` | ods | `BuildsValue`: 5 ops, read only by two test properties; four of the five are the ops whose flow declares a `Fresh` result (`cell.init` is not) | lane 19 decides whether "builds a value" is the flow's `Fresh` (then the trait goes) or keeps `cell.init` (then it stays, test-only) |
| E46 | `lib/IR/Effects.cpp:79-84`; `OpsConReads.cpp:35-38, 157-160`; `OpsMatch.cpp:135-138` | ods | the memo read, a type-derived effect, written as three hand bodies | the typed-effects trait's memo part (T3) |
| E47 | `OpsConReads.cpp:26-29` | ods | `field`'s speculatability branches on box against sum | the typed rule for speculation beside T3 (lane 03 owns the op) |
| E48 | `Call.cpp:69-71` | rederivation | the call adds the fresh-linear-result allocation by hand; `lin.enter` and `lin.use` declare it in ODS | one rule over result types (T3) |
| E49 | `OpsClosures.cpp:260-265` | ods | `memo.run`'s effects are static (read and write `MemoState` on `$cell`) yet written by hand | `Arg<Idr_MemoCell, "", [MemRead<..>, MemWrite<..>]>` in ODS; delete the body |
| E50 | `OpsArrays.cpp:78-84, 185-188, 229-232` | ods | the two update ops' static effects written by hand through `updateEffects` | `Arg` decorators on `$array`; delete the bodies |
| E51 | `lib/Target/Schedules.cpp:303-308` | ods | `VectorizeLanesOp` writes the transform dialect's functional-style effects by hand | `FunctionalStyleTransformOpTrait` with the interface listed plain |
| E52 | `Effects.cpp:32-37` | state | `ownsParameter` has two modes, with and without the program's table, for placement's transient state (0004 S6 judged it essential) | lane 08 decides; noted as a dual path |
| E53 | `Effects.cpp:86-90` | state | `consumes(operand)` builds every edge of the op to answer for one operand: quadratic over an op's operands when every operand is asked (Placement asks each, `Placement.cpp:137-146`) | one query returning the taken uses of an op once (T6) |
| E54 | `Effects.cpp:96-105` | state | `consumedEffects` rebuilds the op's flow edges on every effect query (every DCE and CSE query after idr-rc) | read a per-op-class static "takes over" shape where the flow is static (T6) |
| E55 | `Effects.cpp:45-46` | cpp | `eachTaken` takes a `function_ref` on a hot path (every effect query) | a template on the callback (§5.3 I5) |
| **Forwarding** | | | | |
| E56 | `IdrBase.td:280`; `Traits.h:107-112` | ods | `SameValue`: no `verifyTrait`, no `dependentTraits` on `ResultCarriesOperand` though all 3 ops list it | folded into T6's forwarding kind; until then a `verifyTrait` and the dependency |
| E57 | `IdrInterfaces.td:322-338`; `Traits.h:93-105, 125-130`; `IdrOwnershipOps.td:98-133, 403-425` | rederivation | "the result is the operand" held six ways: `NoRuntimeForm`, `CarriesOperand`, `SameValue`, the carried range, `ViewLikeOpInterface` (borrow), and each op's flow edge | one forwarding declaration (T6) |
| E58 | `lib/IR/FlowOps.cpp:79-81, 176-207` | ladder, cpp | five identical `getFlowEdges` bodies (`handOn`: two checks, `nat.to_big`, `lin.enter`, `lin.use`), two identical reads (`dup`, `borrow`), two empty (`tag`, `cell.stack`) | default bodies supplied by the forwarding trait (T6) |
| E59 | `IdrBase.td:287`; `Traits.h:114-117` | ods | `TakesReference` (2 ops, 1 reader, `Verify/OwnedOps.cpp:240`) restates a count write on the operand | read off the count resource's effect once E5 lands (lanes 07/08 confirm) |
| E79 | `Traits.h:97-105` | rederivation | `ResultCarriesOperand::verifyTrait` checks "same value at any grade", which each of its four ops already checks in its own ODS type constraint (`TypesMatchWith` on borrow, lin.enter, lin.use; `forgets` on share, `IdrOwnershipOps.td:98-133, 403-425`) | delete the trait's verifier; the constraint is the one check (T6) |
| **The flow interface** | | | | |
| E60 | `lib/IR/Flow.cpp:90-92` | rederivation | `holdsLabels(Value)` is `carriesLabels(Type)` (`Analysis/Labels.h:59-61`) | one `Carriers` method |
| E61 | `include/idr/IR/FlowEdges.h:46-80` | cpp | `Carrier`/`Carriers`: a hand bit set with its own operators | `LLVM_MARK_AS_BITMASK_ENUM` on `Carrier`; `Carriers` deleted |
| E62 | `FlowEdges.h:363-369` | cpp | `DenseMapInfo<FlowAnchor>` defines hash and equality only, no empty or tombstone key | complete it or delete it (lane 06 reads the key) |
| E63 | `FlowEdges.h:188-199`; `Effects.cpp:36` | cpp | a parameter and a result are named by `FlatSymbolRefAttr`, then looked up by name | a function identity (§5.6's `FunctionId`, or the `FuncOp`), lane 05/06's program graph |
| E64 | `FlowOps.cpp:97` | state | `ReturnOp::getFlowEdges` uniques a `FlatSymbolRefAttr` on every query (§5.1 F3) | carry the function's existing name (`getSymNameAttr`) or E63's identity |
| E65 | `Flow.cpp:96-109, 288-290` | cpp | `SmallPtrSet<void *>` of opaque pointers where `SmallPtrSet<Value>` is meant | the typed set |
| E66 | `Flow.cpp:130-157` | state | `writesKnown` scans every edge for each edge: quadratic per op per verification on ops that write parts | one pass collecting overwrites first |
| E67 | `lib/IR/FlowOps.cpp:344-346` | upstream | `NeverRuns`: our external model of `MemoryEffectOpInterface` on `ub.unreachable`, which declares none upstream | an `upstream/` patch giving `ub.unreachable` no memory effects, with report and test (AGENTS.md); delete the model and MoveOut's case |
| E68 | `include/idr/IR/Flow.h:67-76`; `unittests/Flow.cpp:213` | upstream | an interface's verifier never runs for an external model, so a unit test holds the 8 models to the rule | keep the test; record the upstream behaviour (no patch proposed: *conjecture* that upstream would not take one) |
| **Runtime and primitives** | | | | |
| E69 | `IdrBase.td:272-275`; `Traits.h:31-40` | dead | `CallsRuntime`: the C++ trait is empty and never queried; the C++ reads the generated `Abi<Op>` | the symbol a field of the op class (as ClangIR's `llvmOp`, §5.6 F2); delete the C++ trait |
| E70 | `IdrInterfaces.td:320`; `Traits.h:72-80` | dead | `Primitive`'s C++ class is never queried; the record is an independent fact tblgen reads | keep the record as a field; delete the C++ class |
| E71 | `Traits.h:28-80` | cpp | five marker classes repeat a private constructor and two friends; seven other traits do not | one form for every marker, or none once E7, E8, E69, E70 delete them |
| E72 | `include/idr/IR/IdrRuntime.td:25-47` | list | each C type's ABI kind is a string (`"Int32"`) that tblgen matches by spelling (`kindSpelled`) | a record per kind, so a misspelling is a TableGen error (lane 14 owns the tool) |
| **Smaller** | | | | |
| E73 | `lib/IR/Crashes.cpp:18-43` | rederivation | `knownNonEmpty` re-walks the append tree per question; `dyn_cast<StrAppendOp>` beside the builder interface | non-emptiness in the type or the builder interface (0003; lanes 01, 04) |
| E74 | `IdrInterfaces.td:24-64` | cpp | `ValueFactsTypeInterface`: five boolean methods, five dispatches for one bit set | one method returning the facts (§5.8 T7; lane 01 owns the types) |
| E75 | `IdrInterfaces.td:241` | cpp | the one interface body over `$_op` | `$_raw_op` (§5.2 W10); negligible |
| E76 | `include/idr/Analysis/Effects.h:51-52` | cpp | `LabelsRun`, a callback threaded from defunctionalization | lane 06's |
| E77 | `compiler/src/IdrisMLIR/Dialect/Idr.idr:1413-1517` | idris | the generated `IOPrim` sum and a separate `ioResult : IOPrim -> IOResult` | index the sum by its result shape, `data IOPrim : IOResult -> Type`, so `IOGives (ioResult p)` becomes the index (lane 14 owns the generator) |
| E78 | `compiler/src/IdrisMLIR/Emit/Operations.idr:329-356` | idris | `effect` reaches two internal errors ("gives no next world", "gives no value") and takes operands as a `List Val` that "ends with the world" | the world a field of its own and the results non-empty by type (0003's leftover; lane 14) |


## 5. Target design

*Conjecture* throughout: a plan for the coordinator and the owner, not a
decision. Where a choice is the owner's (§8), each design says which
answer it assumes and what changes under the other. Every change ends
with the line the skill asks for.

The subsystem becomes three declarations and one derivation:
- **what state exists** (one resource tree, T1);
- **what an op does to it**, declared in ODS where it is static, by one
  typed rule where it follows from types and the flow (T3), and by one
  trait where the op runs unknown code (T4);
- **how a value moves**, which the flow interface already declares and a
  forwarding kind makes shorter (T6);
- and **what a function does**, derived from its ops by one generated
  table (T2).
Classification by trait shrinks to what supplies a method or a rooted
pattern (T7), and readers ask one classifier (T5).

### T1. One resource tree, in one header, named once in ODS

`include/idr/IR/Resources.h` replaces `IdrDialect.h:59-99`; each class
overrides `getParent` and `isAddressable` (*read*: the pin's API,
`SideEffectInterfaces.h:88-195`; an addressable resource may not have a
non-addressable parent, `:158-169`). The shape, assuming ods-Q1 keeps
crashes and divergence, ods-Q3 orders a crash with output and not with
the heap, and DD-Q3 keeps the world:

```
DefaultResource                 (upstream root)
├── idr::Heap                   addressable: cells, boxes, arrays, buffers
│   ├── idr::Count              addressable: reference counts (dup, drop; §5.10 R1.5)
│   └── idr::MemoState          addressable: a memo cell's state
├── idr::Fresh                  addressable: a new value no memory holds (today's Lin)
└── idr::Outside                not addressable: what the program's outside sees
    ├── idr::Halt               not addressable: ends what the outside sees (crash, exit)
    │   └── idr::Divergence     not addressable: may never end (may_loop)
    ├── idr::RuntimeState       not addressable: errno text, the handle table
    └── idr::Forge              not addressable: a forged world's order (gone with DD-Q3)
```

- An IO op reads and writes `Outside` itself (the 68 `Idr_IOOp`
  instances and `put_list`): they conflict with one another and with
  every child.
- A crash writes `Halt`, a loop that may not end writes `Divergence`:
  each conflicts with output (an ancestor) and with each other (a chain),
  never with the heap (a sibling subtree). Two siblings never conflict,
  so a chain is the only way two distinct resources stay ordered; whether
  crash and divergence share one node instead is the owner's (ods-Q3).
- `handle.string` reads and `io.strerror` reads and writes `RuntimeState`;
  `world.new` writes `Forge`: ordered with output, never output.
- Today's `Reference` (consumption's `Free`) becomes a `Free` on `Count`
  or stays a sibling node: lanes 07 and 08 decide, since its readers are
  theirs (`Reshape.cpp:302-305`).
- What it buys upstream (§5.1 D2): CSE merges a heap read across output
  and crashes, and a memo read across output; DCE unchanged. Our readers
  become identity tests on the tree: "performs IO" is an effect on
  `Outside` exactly (E36), "only crashes" is "every write is on `Halt`"
  (E25), "observable" is an effect on `Outside` (E8, E10).
- Under the other answers: if ods-Q1 makes crashes and divergence
  speculation facts, `Halt` and `Divergence` go and the guards and
  `may_loop` become `NoMemoryEffect` and not speculatable (`arith.divsi`'s
  form, §5.2 A7); if ods-Q3 orders a crash with heap writes, `Heap` moves
  under `Halt`'s ancestor and CSE gains nothing on heap reads; if DD-Q3
  drops the world, `Forge` goes and the IO ops' order is their effects on
  `Outside` alone (it already is, beside the world: they all conflict).

*Made unrepresentable:* a crash that is unordered with output, and the
second write that said it (10 ops lose their `MemWrite<Idr_IOResource>`);
*branch deleted:* every reader's test of "which IO write is a crash's".

### T2. A function's effects derived from its ops, through one generated table

The `Effect` bits become generated from the tree: each resource record a
summary carries names its bit (`def Idr_Outside : Idr_Resource<...,
summaryBit = "io">`), and idris-mlir-tblgen (or an `EnumAttr` generated
from the same list) writes both directions: `effectInstances(Effect)`
and `effectOf(const EffectInstance &)`. The bit set covers every node a
caller must see: `io` (`Outside` and its children but `Halt`), `crash`
(`Halt`), `diverge` (`Divergence`), and the two today carried only by
the root (§3.7): `memory` (a write or free of `Heap` on a value the body
did not allocate, conservatively; which heap effects escape a function
exactly is a question for lane 07's analyses) and `memo` (a write of
`MemoState`). Then:

```cpp
// lib/IR/Func/Func.cpp, replacing bodyEffect's four special cases.
Effect idr::bodyEffect(FuncOp fn) {
  Effect own = fn.getTotal() ? Effect::none : Effect::diverge;   // Idris's proof, essential
  fn.getBody().walk([&](Operation *op) {
    if (isa<CallOp>(op)) return WalkResult::skip();              // a call's own property, summed by componentEffects
    if (auto effects = dyn_cast<MemoryEffectOpInterface>(op)) {
      SmallVector<MemoryEffects::EffectInstance> all;
      effects.getEffects(all);
      for (const auto &e : all) own = own | effectOf(e);
    }
    return WalkResult::advance();                                // RecursiveMemoryEffects ops: their bodies are walked
  });
  return own;
}
```

The program verifier's `effectsCovered` moves to `FuncOp::verifyRegions`
(parallel per function, H1) and checks a function's `effects` against
this derivation; `verifySymbolUses` keeps the call's containment
(`Call.cpp:54-57`), which is DS2.1's form and right. 0003's "function
facts lowered" then reads the bits: LLVM's `memory` attribute from
`memory` and `memo`, `willreturn` where neither `diverge` nor `crash` is
set, and `exit` is a `Halt` write (E19), so a function that always exits
no longer says it returns.

*Made unrepresentable:* a function whose summary omits an effect one of
its ops declares (§3.7's three cases); *deleted:* `rows` and its three
hand reverses (E23-E25), `bodyEffect`'s world, `world.new`, `MayCrash`
and runs-label cases (E22, E27, E28, E33); *check moved:* from a
whole-program walk on one thread to each function's region verifier.

### T3. Effects that follow from types: one typed rule, one trait

Recipe row 3 (§5.2.3), generalized from `ConsumesOperands`. A native
trait `Idr_TypedEffects`, listed with `MemoryEffectsOpInterface` and no
ODS effects (A5), supplies `getEffects` from the op's flow edges, its
ODS read operands and its types, by four rules that today are four hand
bodies:
1. *consumption:* a `Free` on each use the flow takes over at an owned
   grade (today's `consumedEffects`, `Effects.cpp:96-105`);
2. *fresh linear values:* an `Allocate` on `Fresh` for each result of a
   linear type (today's `Call.cpp:69-71`, `IdrOwnershipOps.td:410, 422`);
3. *memo reads:* a `Read` of `MemoState` on each operand the op reads in
   place (its ODS constraint is `Idr_SumRead`, `IdrOps.td:36`; tblgen
   emits the indices per op, as it emits `Guarded<Op>`) whose type is a
   memo sum (today's `readsMemoState`, three hand bodies);
4. *allocation:* an `Allocate` on `Heap` for each result the flow
   declares `Fresh` whose type is a cell pointer
   (`ValueFactsTypeInterface::isCellPointer`): a box's `con`, `closure`,
   `suspend`, `delay` (today only `con` declares it, `OpsCon.cpp:50-56`).

The ops: `con`, `field`, `tag`, `match`, `closure`, `suspend`, `delay`,
`return`, `yield`, `share`, `unpack`, `nat.to_big`, `own.give`,
`lin.enter`, `lin.use`. `call` keeps one hand `getEffects`: its property
through T2's table, then the typed rule as a free function (it is the
one op whose effects are a property, essential). The static hand bodies
become ODS: `memo.run` (E49), the two updates (E50), `VectorizeLanesOp`
through upstream's `FunctionalStyleTransformOpTrait` (E51). The rule is
one function, so 0004's "one effects rule" stays one.

This assumes ods-Q2's first answer (a trait computing effects from
types). Under the second (ops split until every effect is static), `con`
splits into box and sum ops, `tag`/`field`/`match` into memo and plain
ops (or the memo sum becomes a type of its own, lane 01), and
consumption, which changes with the stage (owned grades appear at
idr-rc), cannot be made static without doubling every consuming op
across the idr-rc boundary.

*Made unrepresentable:* a builder that allocates a cell and says it
does not (E43) and an allocation test that lists the exceptions (E44);
*deleted:* 8 hand `getEffects` bodies (`own.give`, `con`, `field`, `tag`,
`match`, `memo.run`, two updates) and the call's linear-result loop.

### T4. An op that runs a label does anything: one trait

`Idr_RunsLabels = TraitList<[Idr_RunsLabelsOpInterface,
MemoryEffectsOpInterface, NativeOpTrait<"RunsUnknownCode">]>`, whose
`getEffects` is `effectInstances(anyEffect)`: `apply` and `force` say
the same thing (today `apply` says nothing and `force` says less than an
unsolved call, E31, E32). `bodyEffect` reads it through T2.

*Branch deleted:* `isa<RunsLabelsOpInterface>` in `bodyEffect` (E33) and
`isa<ForceOp>` in MoveOut (E31); *made unrepresentable:* a label run
that performs IO and declares no read of the outside.

### T5. One classifier

`classify` (`Effects.cpp:113-127`) takes its question as a template
parameter checked by a concept (§5.3 I5, §5.5 D3), and MoveOut's
question ("touches an array of this type") is one instance:

```cpp
template <class Q>
concept Question = requires(const Q &q, const mlir::MemoryEffects::EffectInstance &e) {
  { q.touches(e) } -> std::same_as<bool>;
};
template <Question Q> Does classify(mlir::Operation *op, const Q &question);
```

One `Does` enum (`Flow.h:83`); MoveOut's enum, walk, `ub.unreachable`
case and `isa<ForceOp>` go (E34, E35). Where a pass asks many questions
of one region op, an `AnalysisManager`-cached summary per op (Flang's
`AliasAnalysisRecursiveEffectsCache`, §5.6 E3) bounds the walks; only if
§8's measurement shows `getEffectsRecursively` hot.

*Branch deleted:* the second classifier and its two special cases.

### T6. Forwarding: one kind per op, declared once

The ops whose result is their operand at run time today hold that fact
six ways (E57). One `ParamNativeOpTrait<"Forwards", "Kind">` per op,
`Kind` a sum of the five ways the code moves a forwarded value
(*read*, `FlowOps.cpp`): `HandsOn` (taken over, same identity:
`lin.enter`, `lin.use`, `nat.to_big`, and the two guards that pass their
operand), `Views` (read, same identity, no reference: `borrow`),
`Forgets` (released, identity no longer explained: `share`), `Adopts`
(fresh: `own.adopt`), `Gives` (released and read: `own.give`). Its C++
supplies the default `getFlowEdges` for the kind (E58's nine bodies),
`keepsIdentity()` (today's `SameValue`: `HandsOn` and `Views`, but for
`nat.to_big` and the guards, whose identity readers never ask) and
`getViewSource` for `Views`. Two facts stay apart from the kind because
the problem has them apart: `NoRuntimeForm` (a guard forwards its
operand and still runs a check; `nat.to_big` forwards across types and
runs nothing), and "the same value at another grade", which each of the
four ops already checks in its own ODS constraint (`TypesMatchWith` on
`borrow`, `lin.enter`, `lin.use`, the `forgets` predicate on `share`,
`IdrOwnershipOps.td:98-133, 403-425`): `ResultCarriesOperand`'s
`verifyTrait` (`Traits.h:100-104`) restates those four checks and goes,
and its 17 readers ask the kind and the type relation through one
method, with the carried range supplied once. `consumes` becomes one
query per op returning the taken uses at once (E53), and
`consumedEffects` reads the kind's static shape where the flow is
static (E54).

The limit (Brooks): the five are five cases the problem has (counting
moves a reference in five ways), not one flag; and `own.adopt` and
`own.give` may become their own ops (0003's owed `idr.own.load`, `store`,
`alloc`), lanes 03, 07 and 08's.

*Made unrepresentable:* a grade op that carries its operand and forgets
to say whether it keeps its identity (E56); *check moved:* the type
relation to each op's own constraint, where it already is; *deleted:*
`SameValue`, `CarriesOperand`, the `Idr_ResultCarriesOperand` list and
its `verifyTrait`, nine hand `getFlowEdges` bodies.

### T7. Traits that classify only what a method or a rooted pattern needs

- `PerformsIO`: deleted; tblgen reads the world constraint (E7, E9).
- `ObservableIO`: deleted; an effect on `Outside` (E8, E10).
- `MayCrashOpInterface` and its three `getCrashCause` definitions:
  deleted; the `Halt` effect (E15-E17).
- `Idr_Runtime`: the symbol a field of the op record
  (`string runtimeSymbol`), read by tblgen as today; the empty C++ trait
  `CallsRuntime` deleted (E69). The generated `Abi<Op>` table and the
  compile-time fold over `GET_OP_LIST` stay: they are §5.5 D1 done right.
- `Primitive`: a field (`bit idrisPrimitive`), the C++ class deleted
  (E70).
- `NoReturn`: by lane 03's choice, the three ops become terminators with
  no successors, or keep the trait for tblgen's C result kind only; idr-
  expect's crash sites read the `Halt` effect (E18, E20).
- `TakesReference`: read off the `Count` effect once T1 lands, then
  deleted (E59, lanes 07/08 confirm).
- `GuardedOp`, `NoRuntimeForm` (its trait-rooted lowering,
  `Lower.cpp:69`), the typed-effects, runs-labels and forwarding traits
  stay: each supplies a method or roots a pattern.

*Deleted:* `PerformsIO` and `ObservableIO`; `CallsRuntime` and
`Primitive` as traits (their records become fields); `TakesReference`
after T1; `NoReturn` by lane 03's choice; one interface
(`MayCrashOpInterface`). *Branch deleted:* every `hasTrait` on a marker
that restated an operand type or an effect.

### T8. The upstream patch

`ub.unreachable` declares no memory effects upstream, so a reader of
effects takes it for "anything"; our external model (`FlowOps.cpp:344-346`)
and MoveOut's case work around it. An `upstream/<bug>/mlir.patch` gives
it an empty `MemoryEffects` (it never executes), with its report,
reproducer (`getEffectsRecursively` of a region ending in
`ub.unreachable` returns no answer), `tests/upstream-<bug>` check and
`PINS.md` entry, per AGENTS.md; `NeverRuns` and MoveOut's case go in the
same change. *Branch deleted:* our model of an upstream op's interface.

### Order and dependencies

1. T5 and T4 first: local, behaviour-preserving for `apply` (unknown and
   anything are read alike by every reader, §2.5), a fix for `force`.
   With lane 04 (MoveOut).
2. T3 and the ODS declarations (E49-E51), after ods-Q2. With lanes 03
   (op definitions) and 07/08 (consumption's readers).
3. T1 and T2 together, never apart (§3.7's third case: a tree without
   the memory bits breaks buffer and memo ordering across calls), after
   ods-Q1, ods-Q3, DD-Q2, DD-Q3. With lanes 06 (the effects solve and
   `observableRuns`), 08 (`Reshape`'s resource tests), 11 (`Forms.cpp`),
   12 (lowering the bits to LLVM attributes), 19 (idr-expect's crash
   sites, allocation and order properties).
4. T6 after lanes 03, 07 and 08 settle the grade ops.
5. T7 with lane 14 (idris-mlir-tblgen reads the fields and the world
   constraint; the Idris side's `IOPrim` is unchanged in content, E77).
6. T8 independent; the patch goes to `upstream/` with its plan.

## 6. Evidence for the owner's questions

What the code says, by question; no answer.

**ods-Q1 (a dead crash or divergence: kept or deletable?) and DD-Q2
(divergence).**
- Today every one is kept: the eight `Idr_MayCrash` ops write `Crash`
  and `IO` (`IdrInterfaces.td:116-117`); `may_loop` writes `Divergence`
  and `IO` (`IdrCheckOps.td:46-47`); `force` writes all three
  (`IdrClosureOps.td:102-103`); a call whose `effects` hold `crash` or
  `diverge` writes them (`Func.cpp:253-255`). A write keeps an op from
  being trivially dead (§5.2 A6).
- `may_loop`'s own reason: "MLIR deletes a region op without effects even
  if it never finishes; this op's effect keeps such a loop"
  (`IdrCheckOps.td:42-45`). It is made only by idr-tail-loops, in loops
  of functions without `total`.
- Both of MLIR's models are already in the dialect: the 11 total ops
  that a guard protects are `NoMemoryEffect` and `ConditionallySpeculatable`
  (`IdrScalarOps.td:24-26`, `Traits.h:153-199`), as `arith.divsi` is; only
  the guard op keeps the crash. A guard's result is the operand its total
  op takes (`IdrCheckOps.td:56-61`), so a guard is dead only when its
  total op is dead too: under "deletable", a dead `div x 0` goes with its
  guard.
- `diverge` comes from `total`, which the frontend writes only where
  Idris proved every loop of the body terminating, and on lambda and
  delay functions; idr-defunctionalize writes it on force functions; and
  `absorb` clears it when a body takes in a callee without it
  (`IdrOps.td:131-140`). Readers that tell `diverge` apart:
  `IdentitiesRecord.cpp:160` (a call returns), `Specialize/Consumer.cpp:57-62`
  (a callee that may not end takes in only a consumer that performs no
  IO), `Contracts.cpp:169-178`.
- Test properties that assume a crash is kept: idr-expect's
  computes-nothing ("a guard or a crash is kept for the crash",
  `Expect/ComputesNothing.cpp:1-7`) and crash-sites, and the contract
  crash-sites-not-added (`Contracts.cpp:182-195`).
- A box's allocation carries no `Crash` (`OpsCon.cpp:50-56`): running out
  of memory is outside both questions (§5.11, oom-1).

**ods-Q2 (effects that follow from types: one trait, or ops split?).**
- Type-dependent effects today (§3.3 W1): `con` (box or sum,
  `OpsCon.cpp:50-56`), `field`, `tag`, `match` (memo sum or not,
  `OpsConReads.cpp:35-38, 157-160`, `OpsMatch.cpp:135-138`),
  consumption (owned grade and flow: 8 ops by the trait, `call`, `con`,
  `own.give` by hand), and a call's fresh linear results
  (`Call.cpp:69-71`). Speculation also follows the type in `con` and
  `field` (`OpsCon.cpp:62-67`, `OpsConReads.cpp:26-29`).
- Each distinction is already a type: `BoxType` against `DataType`,
  `DataType::isMemo()`, the grade. The trait form exists and works:
  `Idr_ConsumesOnly` (`IdrInterfaces.td:314-316`).
- What a split would make (*measured* from the sets): `con` into 2 ops;
  `tag`, `field`, `match` into memo and plain variants (3 more ops), or a
  memo type (lane 01); consumption changes with the stage (owned grades
  appear at idr-rc, `Effects.cpp:98`) on 11 ops (`return`, `yield`,
  `share`, `unpack`, `nat.to_big`, `closure`, `suspend`, `delay`,
  `own.give`, `call`, `con`), so a split by stage doubles them.
- 0004 judged `consumes`'s two modes essential (1e5a8a8e, README S6).
- idris-mlir-tblgen reads no effects (`grep -n 'effectOnFullRegion\|decorators\|SideEffect'
  tools/idris-mlir-tblgen.cpp` finds nothing), so neither form changes the
  Idris side.

**ods-Q3 (is a crash ordered with IO and with heap writes?).**
- With IO: the runtime's crash flushes the output buffer, writes its
  message to standard error and exits (`runtime/Io/Ending.cpp:64-71`);
  standard output goes "through the output buffer" (`IdrIOOps.td:93-95`).
  So output before a crash is written first and output after it never
  happens; today that order is kept by the second `IO` write of every
  crash (§2.3).
- With the heap: no path of the runtime reads program memory after a
  crash (`Ending.cpp:66-71`: flush, message, exit). Today a crash is
  ordered with heap writes only because every heap effect is on
  `DefaultResource`, the root, which conflicts with everything
  (`IdrOwnershipOps.td:74, 89`, `IdrIOOps.td:157-197`): an accident of
  the tree, not a decision.
- `exit` "writes pending output and ends the process"
  (`IdrPlatformOps.td:282-287`): the same order as a crash, though it is
  no `MayCrash` op.
- What changes with the answer: T1's `Heap` subtree is a sibling of
  `Outside` under "no", under `Halt`'s ancestor under "yes" (§5 T1).

**ods-Q5 (effect stages and full-region effects).**
- Four declarations use them: `cell.new`, `cell.stack`, and
  `cell.recycle`'s `MemFreeAt<0, FullEffect>` and
  `MemAlloc<DefaultResource, 1, FullEffect>` (`IdrOwnershipOps.td:192,
  211, 230-231`), written by 0004 after `memref.realloc`'s form
  (1e5a8a8e, `proposals/0004-representation/README.md` at that commit,
  lines 421-454).
- Nothing in our tree reads a stage or a full-region bit (§3.3 A6's
  grep), nor does idris-mlir-tblgen; upstream reads neither (§5.2 A6).

**DD-Q3 (the world: effects only, or a world with derived effects?).**
For keeping it:
- It is Idris's own representation of IO, threaded by the frontend from
  TT (391 lines in 21 files of `compiler/src`), and the generated Idris
  primitive sum is shaped by it (`IOPrim`, `ioResult`,
  `compiler/src/IdrisMLIR/Dialect/Idr.idr:1413-1517`).
- MoveOut reads the world's def-use chain as the path to the next IO op
  (`MoveOut.cpp:11-13, 104-113`): §5.3 S0's MemorySSA use.
- It orders the ten world-threaded memory ops (buffers, arrays,
  `tabulate_io`) by data dependence beside their value effects
  (`IdrIOOps.td:138-147`).
- The root takes it before lowering (`Func.cpp:275-287`); specialization
  keys, identities and consumers read it as a value (`Keys.cpp:201`,
  `Identities.cpp:30`, `Consumer.cpp:46-49`).
For effects only:
- `PerformsIO` restates it exactly (80 = 80 ops), and the IO ops already
  conflict with one another through their effects (all 68 read and write
  `IOResource`), so their order does not need it.
- A call already carries its callee's effects as an inherent property
  that `verifySymbolUses` checks (`Call.cpp:29-59`): DS2.1's mechanism is
  today's code.
- The crash family, `may_loop`, `force`, `handle.string` and `io.strerror`
  are ordered by effects alone already.
- The function summary's world rule (`Func.cpp:191`) is one of its four
  special cases, and the summary loses effects (§3.7).
- It lowers to nothing (`RuntimeCalls.cpp:138-139`), and no C prototype
  takes it (`idris-mlir-tblgen.cpp:2898-2900`); `world.new` exists only to
  order a forged chain (`IdrIOOps.td:220-232`).
- The builtin `token` cannot replace it: it crosses calls and region
  results (§3.5, B11).

**DD-Q5 (one op, several runtime functions?).**
- Today one op is one function: 119 ops, 119 distinct symbols, plus 14
  helpers (`IdrRuntime.td:61-96`).
- The generator enforces it: an op whose operand admits more than one ABI
  kind is refused, "one C function takes one"
  (`idris-mlir-tblgen.cpp:2825`), and so is an op with an attribute or
  property other than a comparison's `predicate` (`:2809, 2813`); a
  primitive with an inherent attribute is refused for the Idris side too,
  "no constructor of a primitive can give" it (`:1464`).
- The C++ reads `Abi<Op>`, keyed by the op class (`RuntimeCalls.cpp:101,
  132, 153`; `Fold.h:43`; `Conversion/Checks.cpp:63, 72`;
  `Conversion/Strings.cpp:106-145`). An enum op would key the table by
  (op, case): an array per op indexed by the enum, generated from the
  enum's cases with a symbol field on each `EnumCase` record; the folders'
  `Abi<Op>::function` becomes an indexed call, and the Idris primitive's
  constructor takes the case (lane 14's generator).
- The families DS4 names: six clock readings (`Idr_ReadingOp`) and three
  clock queries (`Idr_ClockQueryOp`, `IdrPlatformOps.td:330-347`), and
  sixteen `Idr_HandleQueryOp`s among which the six stat times
  (`:141-152`), each its own symbol.

**New questions for the owner.**
- **ods-eff-NQ1. What a function's `effects` summarize.** Only
  {io, crash, diverge}, as today, or every state a caller must order
  with, including memory its arguments reach and memo state? Today memory
  is carried across a call by the root's accident and memo state not at
  all (§3.7's third case); T1 cannot land without the answer (§5, order
  item 3).
- **ods-eff-NQ2. Ending the process.** Is `exit` a crash, a divergence,
  or an effect of its own? It never returns, yet the summary says a
  function that always exits returns (§3.7).
- **ods-eff-NQ3. A closure's cell before counting.** May CSE merge two
  equal closures, suspensions or evaluated suspensions into one cell, as
  it may today (they declare no allocation), while a box's `con` may not
  (`OpsCon.cpp:50-56`)? T3 declares their allocation and stops it.
- **ods-eff-NQ4. Runtime state.** Are `handle.string`'s read of the
  handle table and `io.strerror`'s read of the C library's text IO,
  ordered with output, or a state ordered only with what changes it
  (`io.handle_free`, a failing call)? Today both are `IOResource`;
  `io.strerror` is deliberately not observable (`IdrPlatformOps.td:311-313`).

## 7. Deletion list

By file and symbol, under §5's designs (the owner's answers move some
lines, as §5 says). Items in another lane's files are marked with the
lane.

- `include/idr/IR/IdrInterfaces.td`: the six `Resource` defs (`:87-92`,
  replaced by the tree's); `Idr_MayCrashOpInterface` (`:105-111`);
  `Idr_MayCrash` (`:116-117`, replaced by an effect bundle on `Halt`);
  `Idr_PerformsIO` (`:295-297`); `Idr_ObservableIO` (`:306-308`);
  `Idr_ConsumesOperands`, `Idr_ConsumesOnly` (`:314-316`, into the
  typed-effects trait); `Idr_Primitive` as a trait (`:320`, a field);
  `Idr_CarriesOperand`, `Idr_ResultCarriesOperand` (`:330-338`, into the
  forwarding trait).
- `include/idr/IR/IdrBase.td`: `Idr_Runtime` as a trait (`:272-275`, a
  field); `Idr_SameValue` (`:280`); `Idr_TakesReference` (`:287`, once
  the count resource lands); `Idr_BuildsValue` (`:293`, if lane 19 takes
  the flow's `Fresh`).
- `include/idr/IR/IdrCheckOps.td`: `MemWrite<Idr_IOResource>` in
  `may_loop` (`:47`); the two `getCrashCause` definitions (`:37-39,
  88-90`); `Idr_NoReturn` (`:19`) if lane 03 makes the three ops
  terminators.
- `include/idr/IR/IdrClosureOps.td`: `force`'s `MemoryEffects<[...]>`
  (`:102-103`, the runs-label trait).
- `include/idr/IR/IdrIOOps.td`, `IdrPlatformOps.td`, `IdrStringOps.td`,
  `IdrArrayOps.td`: every `Idr_PerformsIO` and `Idr_ObservableIO` in a
  trait list (`IdrIOOps.td:21, 147, 227`, `IdrPlatformOps.td:313`,
  `IdrStringOps.td:84`, `IdrArrayOps.td:119, 272`); `MemRead<Idr_IOResource>`
  and `MemWrite<Idr_IOResource>` renamed to the tree's nodes.
- `include/idr/IR/Traits.h`: `CallsRuntime`, `PerformsIO`,
  `ObservableIO`, `Primitive`, `SameValue`, `ResultCarriesOperand`,
  `ConsumesOperands` (`:31-40, 52-80, 84-112`); `TakesReference`,
  `BuildsValue`, `NoReturn` with their records; `consumedEffects`'s
  declaration (`:25-26`, into the typed rule).
- `include/idr/IR/IdrDialect.h`: `anyEffect` (`:55`, generated); the six
  resource structs (`:59-99`, into `Resources.h`); `readsMemoState`'s
  declaration (`:92-93`).
- `include/idr/IR/Flow.h`: `classify`'s `function_ref` signature
  (`:84-87`).
- `include/idr/IR/FlowEdges.h`: the `Carriers` class (`:49-80`).
- `lib/IR/Effects.cpp`: `readsMemoState` (`:79-84`), `consumedEffects`
  (`:96-105`) and `eachTaken`'s callback form (`:45-75`), all into the
  typed rule; `consumes`' per-operand form (`:86-90`).
- `lib/IR/Func/Func.cpp`: `bodyEffect`'s world, `world.new`, `MayCrash`
  and runs-label cases (`:191-199`); `appendEffect`, `Row`, `rows`,
  `effectInstances`' body (`:236-265`, generated).
- `lib/IR/Func/Call.cpp`: the linear-result loop (`:69-71`).
- `lib/IR/Verify/Program.cpp`: `effectsCovered` (`:58-69`, into
  `FuncOp::verifyRegions`).
- `lib/IR/Crashes.cpp`: `CrashOp::getCrashCause` (`:45`).
- `lib/IR/Flow.cpp`: `holdsLabels` (`:90-92`).
- `lib/IR/FlowOps.cpp`: `handOn` (`:79-81`) and the nine bodies it and
  its twins write (`:176-207`, the forwarding kinds' defaults);
  `NeverRuns` (`:344-346`) and its registration (`:365`), with T8's patch.
- `lib/IR/OpsCon.cpp:50-56`, `OpsConReads.cpp:35-38, 157-160`,
  `OpsMatch.cpp:135-138`, `OpsOwnership.cpp:232-235`,
  `OpsClosures.cpp:260-265`, `OpsArrays.cpp:78-84, 185-188, 229-232`:
  every hand `getEffects` body (lane 03 owns the files).
- `lib/Target/Schedules.cpp:303-308`: `VectorizeLanesOp::getEffects`
  (lane 13).
- `lib/IR/Canon/MoveOut.cpp:59-101`: `Does`, `doesOf` (lane 04).
- `lib/Analysis/Effects.cpp:66`: the `ObservableIO` test (lane 06).
- `lib/Transforms/StructureLoops/Forms.cpp:46-63`: `atMostCrashes`'
  crash-or-IO test (lane 11).
- `lib/Transforms/Expect/Placement.cpp:78-92` (`Order`),
  `Expect/Allocation.cpp:28-33` (the closure and suspension cases),
  `Expect/CrashSites.cpp:28`, `Expect/ComputesNothing.cpp:26` (the
  `NoReturn ∪ Guard` set): lane 19.
- `tools/idris-mlir-tblgen.cpp:1481` (`PerformsIO`), `:950` (`NoReturn`,
  if the ops become terminators): lane 14.

## 8. Risks, unknowns, measurements needed

**Risks.**
- **The tree without the summary.** T1 alone makes a callee's buffer,
  array and memo writes invisible across a call (§3.7's third case):
  today the root masks it. T1 and T2 land together or not at all.
- **CSE gains depend on completeness.** Once the heap is a sibling of
  the outside, CSE moves a heap read across an IO op or a crash; that is
  sound only if every op that writes heap memory says so on a value or
  through its call summary. The 119 runtime ops' declared effects must be
  checked against what each runtime function does (lane 18 holds the
  functions' meanings); this lane has not done that audit.
- **A more precise summary is a new surface.** T2 gives fewer bits to a
  function that only passes a world on, so its calls become movable and
  deletable; any op whose declared effects are incomplete becomes a
  miscompile there instead of being masked.
- **The world and MoveOut.** If DD-Q3 drops the world, MoveOut's search
  for the next IO op (today a def-use step, `MoveOut.cpp:104-113`)
  becomes a walk over effects; without care it is quadratic in a block's
  length.
- **`apply` from unknown to "anything".** Every reader treats an unknown
  op and an op that writes the outside and the crash alike (*read*:
  `classify` returns `Touches` for both, `Effects.cpp:115-121`;
  `mayRunAt` returns false for both, `:168-176`; DCE and CSE keep both),
  so T4 should change no output; to be confirmed by the tests.
- **Generated Idris side.** T7 changes what idris-mlir-tblgen reads; the
  Idris primitive sets must stay byte-identical (the IO set is the same
  set of ops, *measured*, §2.2 F1).
- **Test properties.** idr-expect's crash-sites, computes-nothing,
  builds-value and allocation properties and two contracts read facts
  T2, T3 and T7 delete (lane 19).

**Unknowns.**
- Whether §3.7's first and third cases are reachable by any program
  (*conjecture* both ways; a test would settle each).
- Whether upstream takes T8's patch; it applies locally from
  `upstream/` meanwhile, as AGENTS.md says.
- Whether CSE on our functions walks `RecursiveMemoryEffects` bodies per
  op at the stage-1 module's sizes (§5.1 D3).

**Measurements needed** (a built compiler on the stage-1 module; none
could be run here):
- Calls of `getEffects` on consuming ops per pass, and the time spent
  building their `FlowEdges` (E53, E54).
- Time in `getEffectsRecursively` from `classify`, `mayRunAt`, MoveOut,
  `Forms.cpp` and `Placement.cpp` per pass; the number of
  `RecursiveMemoryEffects` ops and their region counts (§5.1 W4, §5.6
  W-E6).
- `effectsCovered`'s time per program verification (E29).
- Functions whose derived summary (T2) differs from today's `bodyEffect`,
  on the stage-1 module and the tests: the size of T2's behaviour change.
- CSE merges with and without T1's tree: the gain T1 claims.
- The operand counts of ops on which `consumes` is asked per operand (the
  quadratic exposure of E53).

## 9. Sources read

**Read in full:** `.claude/skills/representation-first/SKILL.md`;
`AGENTS.md`; `proposals/0000-mlir-native.md` §0-§4, §5.1-§5.8 and
§6-§9 in full; §5.9, §5.10 and §5.11 read by search for this lane's
terms (effect, resource, trait, interface, world, consumption, memo,
crash, speculation), every hit read in its context, plus their
"what it means", questions and notes for other lanes (5.9.2, 5.9.4,
5.10.2-5.10.5, 5.11.2's (B), 5.11.4-5.11.5); `proposals/0003-facts-once.md`;
`audits/p0/README.md`.

**The subsystem, line by line:** `foreign/idr/include/idr/IR/IdrInterfaces.td`,
`IdrRuntime.td`, `IdrFlow.td`, `Traits.h`, `Flow.h`, `FlowEdges.h`;
`foreign/idr/lib/IR/Effects.cpp`, `Flow.cpp`, `FlowEdges.cpp`,
`FlowOps.cpp`, `Crashes.cpp`; `include/idr/Analysis/Effects.h`,
`lib/Analysis/Effects.cpp`, `lib/Transforms/Effects/Effects.cpp`;
`lib/IR/Func/Func.cpp`, `lib/IR/Func/Call.cpp`; `include/idr/IR/IdrDialect.h:1-140`;
`include/idr/InitIdr.h`.

**Read in the cited ranges:** `include/idr/IR/IdrAttrs.td:180-209`,
`IdrBase.td:230-330`, `IdrOps.td:109-395`, `IdrIOOps.td` (whole),
`IdrCheckOps.td` (whole), `IdrClosureOps.td:22-217`,
`IdrOwnershipOps.td:56-135, 182-260, 304-427`, `IdrMatchOps.td:15-172`,
`IdrPlatformOps.td:1-60, 270-385`, `IdrScalarOps.td:20-30`,
`IdrArrayOps.td:210-222`; `lib/IR/OpsCon.cpp:30-75`,
`OpsConReads.cpp:15-70, 145-175`, `OpsMatch.cpp:120-150`,
`OpsClosures.cpp:250-270`, `OpsArrays.cpp:70-90, 170-245`,
`OpsOwnership.cpp:220-250`; `lib/IR/Grades.cpp:105-260`;
`lib/IR/Canon/MoveOut.cpp:1-140`, `Canon/Sink.cpp:55-130, 210-230`,
`Canon/Force.cpp:30-60`; `lib/IR/Verify/Program.cpp:40-90`,
`Verify/Uses.cpp:45-85`, `Verify/Owned.cpp:95-115, 175-215`;
`lib/Transforms/StructureLoops/Forms.cpp:1-150`,
`Expect/Placement.cpp:60-130`, `Expect/Memory.cpp:20-70`,
`Expect/Allocation.cpp:20-50`, `Expect/CrashSites.cpp:1-60`,
`Expect/ComputesNothing.cpp`, `Expect/Does.cpp:1-60`,
`Expect/Facts.cpp:25-50`, `Expect/SolvedEffects.cpp:20-40`,
`Contracts/Contracts.cpp:150-260`, `Ownership/Placement.cpp:135-175`,
`Ownership/Reshape.cpp:280-310`, `Specialize/Consumer.cpp:35-75`,
`Specialize/Keys.cpp:190-210`, `Effects/Constants.cpp:1-40, 135-160`,
`Pipeline.cpp:20-212` (by grep); `lib/Analysis/Identities.cpp:20-45`,
`IdentitiesRecord.cpp:150-170, 300-320`; `include/idr/Analysis/Labels.h:50-140`;
`lib/Conversion/RuntimeCalls.cpp:90-165`, `Conversion/Checks.cpp:110-135`;
`lib/Driver/Register.cpp:60-130`; `lib/Target/Schedules.cpp:290-315`;
`tools/idris-mlir-tblgen.cpp:1390-1500, 2750-3010` and by grep;
`runtime/Io/Ending.cpp:60-76`; `compiler/src/IdrisMLIR/Dialect/Idr.idr`
(by grep, `:1221-1517`), `compiler/src/IdrisMLIR/Emit/Operations.idr:320-356`,
`compiler/src/IdrisMLIR/Registry/Primitives.idr:370-376`;
`tests/effects-memo-state/effects-memo-state.mlir`;
`.toolchain/llvm-project/mlir/include/mlir/Interfaces/SideEffectInterfaces.h:70-210`.

**History:** `git log --oneline` over the subsystem's files (20
commits); `git show` of 955e2b92 (the memo state as a resource),
1feec99c (`mayRunAt`), the effects parts of 1cd1193a and 1e5a8a8e
(`proposals/0004-representation/README.md` at 1e5a8a8e, contracts S6-S10
and its finding table, lines 100-300 and 560-680); `git log -S` for
`bodyEffect`, `PerformsIO`, `NeverRuns`.

**Measured:** TableGen's records dumped to JSON
(`.toolchain/build/tblgen/bin/llvm-tblgen --dump-json -I
.toolchain/llvm-project/mlir/include -I foreign/idr/include
foreign/idr/include/idr/IR/IdrRuntime.td`), read by `python3 -I` scripts
in `/tmp/p0-ods-effects-scripts/` (traits per op, effects per op, the IO
sets, speculation, world operands, runtime symbols, primitives); `grep`
and `wc` counts as cited at each claim.
