<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 wave 2, lane ods-ops: every op, and the IR's core plumbing

*Written (2026-10-21), at e96bb991 plus the working tree's uncommitted
proposal; nothing built or run, every count from the source (§2, §9).
Scope: `foreign/idr/include/idr/IR/Idr{Ops,MatchOps,ClosureOps,
OwnershipOps,BigOps,ScalarOps,StringOps,CheckOps,ArrayOps,IOOps,
PlatformOps}.td`; `foreign/idr/lib/IR/Ops*.cpp`, `Asm.cpp`, `Regions.cpp`,
`Symbols.cpp`, `lib/IR/Func/`, `Dialect.cpp`, `Bytecode.cpp`,
`ContentNames.cpp`, `DataRemap.cpp`, `Constants.cpp`, `Ranges.cpp`,
`Tail.cpp`, and their headers (those of `include/idr/IR/*.h` not owned by
lanes 01 and 02).*

## 1. Reading notes

Written while reading the proposal top to bottom; each note names the
section and finding it comes from. All *read* (the proposal).

### §0-§4 (the brief and the bar)

- §2: 191 op definitions, 15 native traits, 12 interfaces, 72 effect
  declarations across 21 `.td` files; the dialect surface lists the op
  groups this lane owns (program and values, match, closures, ownership,
  big, scalar, string, check, array, IO, platform). §2 counts 48
  `isa<A, B, ...>`, 192 `std::visit`/`get_if`, 49 `hasTrait<`.
- §2 "trait layer as another agent read it" (recalled, wave 2 checks):
  `SameValue` has no `verifyTrait`; four copies of `isa<ReturnOp,
  YieldOp>` in `Transforms/Tail`; three representations of "does IO"
  (`PerformsIO`, `IOResource`, a body effect read off world operands);
  `TakesReference`, `BuildsValue`, `ObservableIO` read once or never.
  Checked in §3 below for the op side (the trait C++ is lane 02's).
- §3: e96bb991 (an interface query per terminator and region successor,
  quadratic in a match's case count) is a fact about the match op's
  control-flow interface, which this lane owns.
- §4: "a hand `verify` or `getEffects` is a declaration not yet made";
  runtime dispatch only where the set is open (MLIR's ops are, to C++).

### §5.1 mlir-analysis

- C1-C4, 5.1.2 item 5, design 1 "ours, in the dialect": the match ops
  must override `getPredecessors`, `getPredecessorValues`,
  `getSuccessorRegions(Region&)` and `BufferizableOpInterface::
  isRepetitiveRegion` with O(1)/O(answer) answers read off the shape
  (every case region's one predecessor is the parent; the parent's
  predecessors are the terminators; nothing repeats).
- D2-D3, 5.1.2 item 6: `RecursiveMemoryEffects` on a match of 30,000
  cases is a 30,000-region walk per `wouldOpBeTriviallyDead` query in
  every greedy visit. W4 asks which of our ops carry it.
- E2/H5: `lookupNearestSymbolFrom` in an op `verify()` is a linear scan;
  `verifySymbolUses` shares one `SymbolTableCollection`.
- F2/W6: functions must be `IsolatedFromAbove` and reached by nesting
  module -> `idr.program` -> function for the pass manager to parallelize.
- W3 (every per-query edge table), W4 (RecursiveMemoryEffects), W6
  (anchoring) fall partly here.

### §5.2 mlir-ods (the recipe)

- A5: ODS effects and `DeclareOpInterfaceMethods<MemoryEffectsOpInterface>`
  on one op collide; effects that depend on attributes, types or regions
  need the whole hand method, or a trait supplying it (row 3, A9's
  `FunctionalStyleTransformOpTrait` precedent).
- A7: "may trap / may not end" is `ConditionallySpeculatable`, not a
  memory effect (`arith.divsi` is `NoMemoryEffect` + speculatable
  interface). Q1 asks the owner which Idris wants for `check.*`.
- A9/M2: consumption = `Read`+`Free` on the consumed `OpOperand`
  (transform dialect); a borrow = `Read` only.
- B2: a trait can *supply* an interface method (member function), so a
  family's shared method lives once.
- B3: verify order: counts, structural traits, `OpInvariants`
  (generated constraints, `ConfinedProp`), native traits in declaration
  order, then `verify()`; region traits after the regions.
- B5: builtin `token` type is not a world token (cannot cross calls).
- C2: interface `body` is instantiated per op unless written over
  `$_raw_op` (W10).
- D3: inherent attributes are always properties at the pin; properties
  are inline, mutable, non-uniqued; `EnumProp`, `ConfinedProp`.
- D5: relational traits (`AllTypesMatch`, `TypesMatchWith`,
  `SameOperandsAndResultType`) generate `InferTypeOpInterface` and
  builders without result types.
- E5: `hasFolder`, `hasCanonicalizeMethod`, `hasCanonicalizer`, all
  rooted.
- F3/M8: op families from lists (TableGen classes, `foreach`); whether a
  family stays many ops or becomes one op with an enum is §5.8's call.
- G2/row 20: `OpAsmOpInterface` result names, `genMnemonicAlias`;
  readable IR declared, not hand-printed.
- H4: `RegionBranchOpInterface` adds a region verifier visiting every
  branch point and every successor on every verify.
- H5: a symbol check in `verify()` with `lookupNearestSymbolFrom` is
  linear per op; move to `verifySymbolUses`.
- M7 / row 12: `Idr_Runtime<"sym">` becomes a `NativeOpTrait` injecting
  `static constexpr StringLiteral getRuntimeSymbol()` plus a
  `RuntimeFunction` interface with a `StaticInterfaceMethod`; one
  interface-rooted lowering pattern.
- The recipe table (rows 1-24) is the yardstick for section 4's *ods*
  category: rows 1-2 (static effects), 3 (type-dependent effects by
  trait), 4 (recursive), 5 (speculation), 7-10 (traits, constraints,
  structure), 11 (interfaces), 12 (runtime symbol), 13 (properties), 14
  (enums), 17 (folders), 20 (asm names), 21 (bytecode), 23 (families
  from lists), 24 (`DependsOnParent`).
- W1 (every hand `getEffects`: static, type-dependent or recursive), W3
  (every `verify()`/`verifyRegions()`), W4 (isa ladders over ops), W8
  (bytecode), W10 (`$_op` bodies) are answered in §3 for this lane's
  files.

### §5.3 llvm

- B1/I1: an `isa<ReturnOp, YieldOp>` is not slow, it is a fact restated;
  over ops it is a trait (`ReturnLike`) or interface.
- B2/I2: `TypeSwitch` with `DefaultUnreachable` is the form for a per-pass
  table over ops; a classification more than one pass reads is a trait.
- B3/I3: `get_if` chains over our own sums become one exhaustive
  `std::visit` (`llvm::makeVisitor`).
- B4/I4: a sum of handles is a `PointerUnion`.
- E1: `!instances<T>`, `foreach`, `defset`, `assert` compute and check
  op sets in TableGen; E2: `GenericTable`/`SearchIndex` for lookup
  tables (lives in `llvm-tblgen`, not linkable by a custom backend).
- I8: a C++ list mirroring records is generated.
- M10: our 44 `switch`es on our own enums that recur are a record set
  not yet generated.

### §5.4 modular

- F7, 5.4.2 item 4, design 4: HLCF uses its own `ControlFlowNode` /
  `ControlFlowTerminator` interfaces, not `RegionBranchOpInterface`;
  `CFGAnalysis` asks each terminator once and inverts predecessors. For
  our match the quadratic shape goes when predecessors are inverted from
  successors once (e96bb991's lesson).
- F12: Modular's ODS: 380 assembly formats against 17 custom; families
  as ODS base classes bundling traits, operands, format and folder
  (`POP_ArithmeticBinaryOp`); 7 hand `getEffects`, each where an
  attribute (`volatile`, atomic ordering) changes the op's effects:
  the flag the skill says to split (5.4.2 item 9).
- 5.4.4 wave-2 item: "whether our call op can implement upstream's
  `CallOpInterface` once specialization is done" (answered in §3).
- 5.4.4 wave-2 item: "any hand-written `getEffects` or `verify` that
  exists because an attribute changes an op's meaning (F12's
  anti-pattern)" (answered in §3).
- 5.4.5 dialect-design note: `hlcf.switch` with `DenseI32ArrayAttr` case
  values and a `VariadicRegion`.

### §5.5 cxx26

- D1 (the proposed answer to §8 Q1): over ops, dispatch is MLIR's (an
  interface, a trait, a rooted pattern); never a C++ concept or `isa`
  listing op classes. Below the dispatch (an interface's
  `Model<ConcreteOp>`, `OpRewritePattern<OpT>`) templates and concepts;
  a concept may *read* ODS (`OpT::hasTrait<T>()` is `constexpr`, finding
  17), never *list* ops.
- Finding 16: an interface's model is MLIR's monomorphization point.
- Finding 19: a fold over the dialect's op list hits `-fbracket-depth`
  past 256; our 191 ops fit.

### §5.6 ecosystem

- E4 / 5.6.5 note to §5.2 and §5.8: HLFIR writes 24 hand `getEffects`
  because effects depend on operand types; "a case ODS cannot declare,
  which the redesign should make unrepresentable rather than
  hand-write"; HLFIR is the "one op, effects by operand type" design §1
  asks about.
- F1: ClangIR, 315 ops: 64 `Pure`, 1 hand `getEffects`, 3
  `RecursiveMemoryEffects`. F2: ClangIR generates its LLVM lowering from
  ODS fields on its base op class (`hasLLVMLowering`, `llvmOp`).
- D5: IREE's `TiedOpInterface` declares in-place results by interface
  with default methods over one attribute.
- D6: write the analysis answer's own bits in the type.
- Item 8: a case's state as a delta over the match entry's; W-E8 asks
  whether IR after defunctionalization is single-block regions
  throughout (answered in §3 for the match op).
- Item 9 / W-E6: every query on a match that walks or enumerates its
  regions, per query (answered in §3 for our op definitions).

### §5.7 library

- B4: Bhat and Grosser lower Lean's λrc to MLIR with a case's
  alternatives as regions; region values may not escape.
- M3: e96bb991 is "validation repeated where a parse belongs"; a
  match's N edges are a star, enumerate once per op.
- M6/L3: `!idr.data<@T>` is a symbol-named nominal type; an interned
  structural description would make "same type" an integer compare
  (lane 01's).
- **L1 (SSI) is a rule for the op set**: an op that changes what may be
  done with a reference (consume, share, borrow, give, take, enter a
  linear scope) defines a new SSA value; a match's case region binds the
  refined scrutinee as a block argument. "Whether `take`, `own.give`,
  `share`, `borrow` and the rest already define one is wave 2's to
  check" (answered in §3). QL2 asks the owner.

### §5.8 dialect-design (read most carefully)

- Carrier table (5.8.2): every use -> a type; one op's meaning -> an
  inherent attribute/property; what an op does to state -> a declared
  effect; a classification -> trait/interface; a whole-function property
  -> an analysis or a pass. A fact in a lower row than its readers need
  is rederived.
- B3/B4/O1 (upstream's line, the lane's synthesis): one op when variants
  share operand/result structure, traits, effects and verification and
  differ only in the pure function computed (enum); separate ops when
  the computation, effects, UB or valid states differ. An enum that
  changes effects/UB/valid states is a flag.
- B3: `arith.divsi`/`divui` two ops; `ptr.load`/`llvm.load` carry flags
  only because they mirror LLVM.
- C2: totality is a trait (`Arith_TotalIntBinaryOp` adds `Pure`;
  `divui` is `ConditionallySpeculatable`).
- C3/O2: `memref.alloc`/`alloca` are one TableGen class
  `AllocLikeOp<mnemonic, Resource>`; ops differing only in effect are
  one class parameterized by the resource. An op whose effects are its
  region's is one op with `RecursiveMemoryEffects`, "never a pure op
  plus an IO twin".
- C4/EF3: consumption = `Read`+`Free` on the operand; never trivially
  dead; `ConsumesOperands`/`ConsumesOnly` would become these.
- C6: `cf.assert` writes the default resource; `ub.unreachable` a
  terminator with no effect.
- E4: comb's `divs/divu/mods/modu/shrs/shru` are exactly our mnemonics;
  comb has one `shl`; no redundant ops (no `~x`, no zero-extend).
- E5: one op with optional operands or two ops follows what consumers
  share.
- E7/S3: store indices, print names (`hw.struct_inject`).
- O3: a regrade is a cast with computed result type (`TypesMatchWith`),
  legality from the grade; an ownership event with a runtime cost is
  its own op; forwarding is a category declared once in an interface;
  consuming an aggregate is one destructuring op.
- O4: a lower form is another op (often another dialect), never a flag;
  ops legal only before/after a pass go through `ConversionTarget`.
- O5: compose before fusing: `io.put_sint %x` = `io.write
  (str.show_sint %x)`, fused at lowering.
- N1: mnemonic `family.verb`/`family.noun`; make prefixes total (every
  op in exactly one family named after its type or resource). N2: no
  implicit semantics in names; candidates `put_sint/uint/double`,
  `show_*`, `int_head_s/u`, `double_head`, six stat-time ops, eight
  clocks.
- EF1: two interfaces for four behaviours; EF2: a resource tree
  (`World` with children); EF4: a world value kept beside effects is a
  second representation unless effects are derived by one rule.
- S1: every op has a declarative assembly format; print each type once;
  enum keywords first; `oilist` for flags. S2: generated aliases. S3:
  result names, stored indices printed by name.
- DS2.1: no world after the frontend; `unsafePerformIO` a region op
  with `RecursiveMemoryEffects`; a call carries the callee's effect set
  as an inherent property verified by `verifySymbolUses`, or effects are
  an analysis. DS2.2: keep the world, derive effects by one rule.
- **DS4, the first mapping** (checked op by op in §3 and §5): cell
  alloc class; `cell.reuse`/`cell.init`; one regrade cast for `lin.enter,
  lin.use, own.adopt, own.give, share, borrow`; keep `dup`/`drop`; one
  consuming destructure for `take`/`unpack`; one forwarding interface for
  `SameValue, TakesReference, BuildsValue, CarriesOperand,
  ResultCarriesOperand`; `MemFree<Idr_Linear>` for consumption; effects on
  `World`'s children for IO; `NoReturn` -> terminators; `check.nonzero,
  in_bounds, nonempty, finite, range` -> `arith.cmpi` + one `idr.check
  %cond, <reason>`; `check.crash/crash_str` -> one terminator; `may_loop`
  owner's; word ops -> `arith` where semantics agree; `shls/shlu` -> one;
  `put_*` -> `show` + `io.write`; one `io.file.stat` with several results;
  one `io.clock <kind>`; one `array.tabulate`; `fold_last, scan_last,
  transpose` -> named linalg forms; array value ops in tensor style;
  `closure`/`apply` legal only before defunc; a `lazy.` family; `data.con,
  data.field, data.tag` as indices printed by name; `func/call/return` ->
  `func.*` unless `!idr.fn` carries conventions; `match_lit` ->
  `scf.index_switch`/`cf.switch`; keep the runtime-symbol trait,
  `Primitive` implied by it.
- DD-Q4 (signedness), DD-Q5 (one op, several runtime functions), DD-Q7
  (own function op), DD-Q8 (renames) are this lane's owner questions to
  give evidence for (§6).
- Wave-2 items for this lane (answered in §3): which word ops differ
  from `arith` on inputs the runtime defines, and why `shls`/`shlu` are
  two; every DS4 pair's semantics, effects, verifier, folders and the
  `isa<>`s that tell members apart; what `!idr.token` is (lane 01's);
  where `MayCrash`, `PerformsIO`, `ObservableIO`, `ConsumesOperands` and
  world operands are read (lane 02's, with op-side evidence here); every
  op with a `UnitAttr`, an optional operand or an enum, and whether it
  changes effects, UB or valid states.
- 5.8.5: `scf.index_switch` has a region per case as our `match` does.

### §5.9 mlton (read most carefully, for the match)

- C3: MLton SSA's `Case` is a terminator whose arms are `(Con, Label)`
  pairs, each a jump to a block taking the constructor's fields as
  arguments; a 30,000-arm case is a vector; nothing nests; the checker
  requires a default iff non-exhaustive. `Return.t = Dead | NonTail
  {cont, handler} | Tail`: tail position is a sum on the call.
- C4: SSA2 builds a constructor's `Object` then `Inject`s it into its
  sum; mutability is per field of the object type (bears on `con`,
  `cell.*`, `own.*`).
- F6: RSSA's `Switch` is a flat sorted vector of `(WordX, Label)`.
- H, row e96bb991: "nothing nests, so there is no 'where does this
  region's yield go' question to ask".
- **M3**: "The match with a region per case is the representation behind
  e96bb991." MLIR's mechanism: `BranchOpInterface` with
  `SuccessorOperands` whose leading block arguments are *produced* by the
  terminator (`ControlFlowInterfaces.h:30-58`).
- **Design 2**: from defunctionalization on, a match is a terminator
  over a sum whose arms are successor blocks receiving the fields as
  produced successor operands, with a join block. Costs: structured
  passes (structure loops, TRMC, frames, counting's scopes) run before
  the lowering or recover structure; a 30,000-arm case becomes 30,000
  blocks in one region (dominator tree cost, Q-W3). Deletes:
  `RegionBranchOpInterface` on `match` after the lowering; `YieldTargets`
  and `RunsLabels`-style plumbing "if wave 2 finds that is what they do".
- Design 5: known-constructor fold of the case terminator (the shrinker's
  `simplifyCase`) as a per-op fold.
- **Q-O1** (owner; evidence in §6): keep the structured match past
  defunctionalization, and for which passes?
- Q-W3 (match cost in objects; partly here, measured by count of
  constructs per case), Q-W4 (which passes read the match's region
  structure; answered from the op side in §3).

### §5.10 rc

- R1.4: `is_unique %x` as an op whose folder returns true when `%x` is
  exclusive by type; drop specialization emits `scf.if` on it. R1.5:
  `dup`/`drop` write the count resource, `is_unique` reads it, a
  consuming operand is `Read`+`Free`.
- M7: `cell.recycle` is Koka's `drop-reuse` / Lean's `reset`; `cell.init`
  is `alloc-at` / `reuse`.
- M8: `Captures` may vanish under defunctionalization (a closure's
  captures are its constructor's fields).
- **W7 (this lane's)**: each ownership op against the field's: `take`
  and `unpack` against FP²'s destructive match, `share` against
  uniqueness logic's one-way `P ⊢ P°`, `own.adopt` and `own.give` as
  possibly two directions of one conversion, `lin.enter` and `lin.use`
  against QTT's binder rules, `borrow` against OSSA's guaranteed scope;
  which of them are one op with different effects.
- W8: whether counting runs on `idr.match` regions or on a CFG (op-side
  evidence here; counting is lane 08's).

### §5.11 oom

- Nothing op-specific beyond the crash ops' meaning (oom-1: out of
  memory is a named crash of the machine, never a value or effect).

### §8 (owner's questions this lane gives evidence for)

- §8.3: **Q-O1** (structured match past defunctionalization), **DD-Q4**
  (signedness), **DD-Q5** (one op, several runtime functions), **DD-Q7**
  (own function op), and §8.2 **DD-Q8** (renames). Also touched: QL2
  (SSI, case regions binding refined scrutinees), ods-Q1/DD-Q2 (dead
  crash or divergence), ods-Q2/DD-Q3 (effects from types, the world).

### proposal 0003 (facts once), items in this lane's files

- "A token without its cell": `!idr.token` has no parameters; the
  verifier, `Conversion/Fields.cpp`, `Demand.cpp`,
  `ReusesEveryCell.cpp` each walk back to `idr.take`; owed
  `!idr.token<!idr.box<T>, @C>` inferred by `TakeOp` (the type is lane
  01's; `TakeOp`'s inference is this lane's).
- "What an enclosing match says about a value, three ways":
  `OpsMatch.cpp` `takenFromEnclosing`, `Canon/Eta.cpp` `knownFromMatch`,
  `OpsConReads.cpp` `FieldOp::canonicalize`; `TagOp::fold` never asks;
  owed one `knownConstructor(Value, at)`.
- `idr.crash_str` drops its site; `OsOp::fold`'s fallback to the build
  machine's triple.
- "The owned stage reads upstream's buffer ops by name": `own.adopt`,
  `own.give` carry values across the boundary; owed `idr.own.load/
  store/alloc` or `own.give` as a flow edge.
- "Resources read as effect bits by hand ... beside
  `idr::effectInstances` (`lib/IR/Func/Func.cpp`)".
- "The crash-site count and the crash effect disagree": `idr.exit` is
  `NoReturn` but not `MayCrash`.
- "Data types carry no location": `Declarations::define` errors at
  `UnknownLoc`; the body should hold its location, "carried by
  DataRemap".
- "`Defunctionalize/Pass.cpp` builds a `TypeGraph` outside the manager";
  "the comment about one symbol-use map is stale" (`Component.cpp`).

## 2. What the subsystem is

### Files and sizes (*measured*)

| part | files | lines |
| --- | --- | ---: |
| op definitions | `include/idr/IR/Idr{Ops,MatchOps,ClosureOps,OwnershipOps,BigOps,ScalarOps,StringOps,CheckOps,ArrayOps,IOOps,PlatformOps}.td` | 3,209 |
| op C++ | `lib/IR/Ops*.cpp` (16 files) | 3,194 |
| core plumbing | `lib/IR/{Asm,Regions,Symbols,Dialect,Bytecode,ContentNames,DataRemap,Constants,Ranges,Tail}.cpp`, `lib/IR/Func/{Func,Call,Inliner}.cpp` | 2,029 |
| headers | `include/idr/IR/{IdrDialect,Func,Symbols,Tail,Ranges,Arrays}.h` | 1,024 |

Command: `wc -l` over each list (run from `foreign/idr`).

### The ops (*measured* from the ODS, at the working tree)

The `.td` files were expanded with the pinned `mlir-tblgen -gen-op-decls`
into `/tmp/p0-ods-ops/IdrOps.h.inc` (nothing in the repository written or
built; the checked-in `build/typecheck/.../IdrOps.h.inc` is from
2026-10-18 and predates `idr.memo.run`), and the traits counted per
generated op class (`grep -c <trait> classes.txt`):

| fact | ops |
| --- | ---: |
| op definitions (`class ...Op : public ::mlir::Op<`) | **189** (§2 of the proposal says 191 at e96bb991; two were deleted since or counted differently) |
| `MemoryEffectOpInterface` (generated or declared) | 181 |
| `HasRecursiveMemoryEffects` | 9 (`match`, `match_lit`, `memo.run`, `tabulate`, `tabulate_io`, `fold_last`, `scan_last`, `array.update`, `element.update`) |
| `RegionBranchOpInterface` | 9 (the same nine) |
| `ConditionallySpeculatable` | 52 (37 `AlwaysSpeculatable`, 6 `RecursivelySpeculatable`, 9 conditional) |
| `CallsRuntime` (`Idr_Runtime<"sym">`) | 119 |
| `Primitive` (the frontend names it) | 114 |
| `PerformsIO` | 80 |
| `ObservableIO` | 68 |
| a world operand (`Idr_WorldType:$world` in the `.td`, by text) | 44 definitions, most through family classes |
| `FlowOpInterface` (lane 02's) | 42 |
| `InferIntRangeInterface` | 29 |
| `OpAsmOpInterface` | 73 |
| `GuardOpInterface` (the guards) / `GuardedOp` (guarded ops) | 5 / 11 |
| `MayCrashOpInterface` | 8 |
| `NoReturn` | 3 (`crash`, `crash_str`, `io.exit`) |
| `IsTerminator` | 3 (`return`, `yield`, `array.yield`) |
| ops with regions | 11 = 189 − 178 `ZeroRegions`: one region each for `program`, `func`, `memo.run`, the four generating ops, `array.update`, `element.update` (9 `OneRegion`); a default plus a variadic list for `match`, `match_lit` |

Hand-written hooks in this lane's C++ (`grep -rn 'Op::<hook>' lib/IR`):
9 `getEffects` (all nine in this lane's files), 22 `verify()`, 11
`verifyRegions()`, 4 `verifySymbolUses`, 2 `getSpeculatability`, 21 of
the 69 `fold`s (the rest are lane 04's `Fold/` and `Canon/`), 1
`canonicalize`, 9 `getCanonicalizationPatterns`, 10 of the 42
`getFlowEdges` (the rest are lane 02's `FlowOps.cpp`), 29
`inferResultRanges`, 8 `getSuccessorRegions`.

Mnemonics (`grep -oE '"idr\.[a-z_0-9.]+"'` over the generated header):
189, of which 46 have no family prefix (`apply borrow call closure con
constant crash_str crash delay divs divu double_head drop dup field
fold_last force func int_head_s int_head_u match_lit match may_loop mods
modu os program return scan_last share shls shlu shrs shru suspend
tabulate_io tabulate tag take tie_shape to_char_s to_char_u to_int
transpose unpack yield`); the rest are `io.` 74, `str.` 21, `big.` 21,
`check.` 5, `array.` 5, `cell.` 4, `nat.` 3, `own.` 2, `lin.` 2,
`handle.` 2, `world.`, `memo.`, `element.`, `dest.` 1 each.

C++ idioms in the lane's 35 C++ files and headers (`cat | grep -oF`):
`isa<` 33 (5 over several types: `OpsBigs.cpp:42`, `OpsMatch.cpp:32`,
`Constants.cpp:129`, `Tail.cpp:39, 269`), `dyn_cast<` 33,
`dyn_cast_or_null<` 26, `TypeSwitch<` 2, `std::variant<` 2,
`std::get_if<` 8, `holds_alternative` 1, `function_ref<` 6,
`std::function<` 1, `concept` 2, `template <` 12, `switch (` 1,
`DenseMap<` 11, `DenseSet<` 6.

### What it holds and derives

- **Every op's semantics and legality**: operand, result, attribute and
  region constraints; 22 hand verifiers and 11 region verifiers; the
  effects of 181 ops (172 declared in ODS, 9 by hand).
- **The program** (`idr.program`): its root (a property; a function's
  visibility is derived from it, `IdrOps.td:93-101, 186-194`), its stage
  (an enum that decides which ops and grades are legal, `IdrOps.td:42-57`),
  and the table of data types (lane 01's attribute, declared through
  `Declarations`, `Symbols.h:88-137`).
- **Functions** (`idr.func`): `total` (Idris's proof), `no_inline`,
  `effects` (a bit-enum property, copied onto every call), `instance`;
  `bodyEffect`, `componentEffects`, `writeEffects` and the
  bit-to-resource table `effectInstances` (`Func/Func.cpp:185-265`); the
  rule of the root (`rootKind`, `Func/Func.cpp:275-287`).
- **Content names** (`ContentNames.cpp`, XXH3-128 of canonical text) and
  reserved names (`Symbols.cpp:86-88`); **data remaps**
  (`DataRemap.cpp`): new data types made from content where a body would
  change.
- **Tail position** and tail position modulo a context (`Tail.cpp`), read
  by `Analysis/Recursion`, `Ownership/Borrows`, `IR/Lifetimes`, and the
  five `Transforms/Tail` passes.
- **Ranges** of bigs and naturals (`Ranges.cpp`), read by every
  `inferResultRanges` here and by idr-narrow.
- **The asm**: aliases of data types and large constants, result and
  block-argument names (`Asm.cpp`), and the `CtorRef` directive (a
  constructor printed by name, stored by tag).
- **The bytecode** of the table (`Bytecode.cpp`).

### Readers and threading

- Every pass reads the ops through their generated accessors and the
  interfaces; the match ops are read by name in 27 files of
  `lib/Transforms`, `lib/Conversion` and `lib/Analysis` (*measured*:
  `grep -rlE '\bMatch(Lit)?Op\b|MatchOpInterface' lib/Transforms
  lib/Conversion lib/Analysis`), 134 occurrences in the tree.
- Verification: the op verifiers run per op, the `idr.func` region
  verifier per function (in parallel, `IsolatedFromAbove`), the program's
  region verifier (`verify::program`, lane 01's) and `ProgramOp::verify`'s
  whole-program walk on one thread (`Func/Func.cpp:56-120`), after every
  pass on the program.
- Folders and range hooks run inside the greedy driver and the dataflow
  solver on any thread the pass manager gives; `Asm.cpp`'s hooks keep no
  state, so the printer may run them from any thread
  (`Asm.cpp:8-10`). `ContentNames` and `DataRemap` are per pass, one
  thread (`Symbols.h:279-283`).
- The ops reach the Idris side through `idris-mlir-tblgen` (lane 14):
  the generated constructors (`compiler/src/IdrisMLIR/Dialect/Idr.idr`,
  191 functions ending in `Op`), the `PurePrim`/`IOPrim`/`IdrRegionPrim`
  sums from `Primitive`, the guards from `Idr_Guarded`
  (`Dialect/Idr.idr:124`: `MkGuard 1 Nonzero "division by zero"`), and
  the runtime prototypes and op-to-function table from `Idr_Runtime`.

## 3. Reconciliation with the proposal

Each finding or design of §5 that touches the ops, judged against the
code; then every wave-2 question that falls here, by ID. *Read* unless
marked.

### §2 (the brief) and the recalled trait layer

- *191 op definitions*: **holds in part**: 189 at the working tree
  (*measured*, §2 above).
- *Four copies of `isa<ReturnOp, YieldOp>` in `Transforms/Tail`*:
  **holds, and there are two more** in this lane's `lib/IR/Tail.cpp:39,
  269` (O-92). Both ops carry `ReturnLike` (`IdrOps.td:242`,
  `IdrMatchOps.td:163`), so the ladder restates a trait.
- *Three representations of "does IO"*: **holds, and it is four on one
  op**: every `Idr_IOOp` carries `PerformsIO`, `ObservableIO`,
  `MemoryEffects<[Read IO, Write IO]>` and a world operand and result
  (`IdrIOOps.td:19-23`), and `bodyEffect` reads a fifth, world-typed
  parameters plus `isa<WorldNewOp>` (`Func/Func.cpp:189-202`). The array
  and buffer ops drop the IO resource and keep the world
  (`IdrArrayOps.td:262-273`, `IdrIOOps.td:138-147`), and `io.strerror`
  keeps the IO resource but drops `ObservableIO` (`IdrPlatformOps.td:311-
  322`): the representations do not even agree with each other (O-36,
  O-41).

### §5.1 mlir-analysis

- **C4 / 5.1.2 item 5 (the match must answer per op)**: **holds**. The
  match declares only `getEntrySuccessorRegions`,
  `getRegionInvocationBounds`, `getSuccessorInputs` and defines
  `getSuccessorRegions` (`IdrMatchOps.td:28-30, 62-95`); the parent's
  successors are enumerated once (O(N), correct) and a yield's are O(1)
  (`Regions.cpp:14-18`), but `getPredecessors`, `getPredecessorValues` and
  `isRepetitiveRegion` keep upstream's per-call O(N) (O-13). For
  `isRepetitiveRegion` on a match the cost is the `SmallVector<bool>(N)`
  that `traverseRegionGraph` allocates per call
  (`.toolchain/llvm-project/mlir/lib/Interfaces/ControlFlowInterfaces.cpp:234-243`),
  since a case region's only successor is the parent (*read*; the cost on
  stage 1 is *conjecture*). `BufferizableOpInterface::isRepetitiveRegion`
  is lane 11's.
- **D3 / 5.1.2 item 6 (`RecursiveMemoryEffects` on a big match)**:
  **holds**: both matches carry it (`IdrMatchOps.td:26`) and `MatchOp` adds
  a hand `getEffects` on top (`OpsMatch.cpp:135-138`), so every effect
  query of a match walks every case (O-12).
- **W3** (every per-query edge table and quadratic helper): in this
  lane's files none is built per query. Elsewhere (*measured*, `grep -rn
  'getPredecessors\|isRepetitiveRegion\|insideMutuallyExclusiveRegions'
  lib include`): `isRepetitiveRegion` at `lib/IR/Verify/Linearity.cpp:126`
  (lane 01, run after every pass) and `lib/IR/Lifetimes.cpp:54` (lane 01),
  `lib/Transforms/Bufferize/Releases.cpp:44` and
  `insideMutuallyExclusiveRegions` at `:111` (lane 11). The two
  `block.getPredecessors()` in exclusivity are CFG block predecessors, not
  the interface (lane 07).
- **W4** (which ops carry `RecursiveMemoryEffects`): the nine region ops
  listed in §2 (*measured*). Which upstream passes query them on stage 1
  is unmeasured (no build); canonicalize's DCE and CSE do by construction
  (§5.1 D2), and the pipeline runs both after symbol DCE (§2 of the
  proposal).
- **W6** (anchoring): **holds**: `idr.program` and `idr.func` are both
  `IsolatedFromAbove`, the function `HasParent<ProgramOp>`
  (`IdrOps.td:71-72, 109-111`), so module → program → function nesting is
  available; which passes use it is lane 13's.

### §5.2 mlir-ods (the recipe)

- **M1** (one effects model reachable with ODS): **holds** for the ops;
  the hand `getEffects` are nine (W1 below) and every one is
  type-dependent, property-dependent or a static effect written by hand.
- **M2** (consumption as `Read`+`Free`; derived from the type by one
  trait): **holds, already built**: `Idr_ConsumesOnly` is a `TraitList`
  whose C++ trait `ConsumesOperands` supplies `getEffects` through
  `consumedEffects` (`IdrInterfaces.td:310-316`, `Traits.h:85-91`), i.e.
  row 3 exists in the tree. It declares a `Free` on `ReferenceResource`
  per owned operand taken over, without the transform dialect's `Read`
  (`lib/IR/Effects.cpp:96-105`). Four hand `getEffects` (`call`, `con`, `own.give`, and the
  stage-dependent part of each) call `consumedEffects` by hand instead
  of inheriting it.
- **M7** (`Idr_Runtime` as row 12): **holds in part**: the record is one
  source, read by `idris-mlir-tblgen` into the C prototypes and an
  op-to-function table (`tools/idris-mlir-tblgen.cpp:2754-2982`; the C++
  trait `CallsRuntime` is a bare marker, `Traits.h:31-40`). There is no
  `getRuntimeSymbol()` on the op class and no interface; the lowering
  reads the generated table. M7's static member would let a folder or a
  pattern reach the symbol from the op class at compile time.
- **M8** (families from lists): **holds in part**: the families are
  TableGen classes (`Idr_IOOp`, `Idr_PlatformIOOp`, `Idr_HandleQueryOp`,
  `Idr_PathOp`, `Idr_ReadingOp`, `Idr_ActionOp`, `Idr_ClockQueryOp`,
  `Idr_BigBinaryOp`, `Idr_StrBuilderOp`, `Idr_CheckOp`,
  `Idr_GeneratingOp`, `Idr_MatchOpBase`, ...), but every member is a
  hand-written `def`: no `foreach` or `defset` over a list.
- **W1** (every hand `getEffects`: static, type-dependent or recursive):
  - static, written by hand: `memo.run` (`Read`+`Write` `MemoState` on
    the cell, `OpsClosures.cpp:260-265`), `array.update` and
    `element.update` (`Read`+`Write` default on the array,
    `OpsArrays.cpp:80-84`); each beside `RecursiveMemoryEffects`;
  - type-dependent: `match`, `field`, `tag` (a memo sum reads
    `MemoState`, `OpsMatch.cpp:135`, `OpsConReads.cpp:35, 157`); `con` (a
    box allocates, owned fields are freed, `OpsCon.cpp:50-56`);
    `own.give` (consumed operand, `OpsOwnership.cpp:232-235`);
  - property-dependent: `call` (the `effects` bits, consumed operands,
    an allocation on `LinResource` per linear result, `Call.cpp:65-72`);
  - none mixes ODS effects with `DeclareOpInterfaceMethods` (A5): the
    recursive ones combine the trait `RecursiveMemoryEffects`, which is
    not an ODS effect, with the hand method.
- **W3** (every `verify`/`verifyRegions`): 22 and 11 (§2). What a trait or
  constraint expresses: `DupOp` (O-71), `FieldOp`'s result type (O-57),
  the array ops' rank and element checks (O-77), `TieShapeOp`'s count
  (O-77), the region ends (O-50). What follows def-use chains, against
  the verifier doctrine: `OwnAdoptOp`, `OwnGiveOp` (O-70). Symbol lookups
  in `verify()`: none in an op's `verify()`; `ProgramOp::verifyRegions`
  finds the root by `SymbolTable::lookupSymbolIn` (linear, O-64), and
  the four symbol users use `verifySymbolUses` with the shared collection
  (`Call.cpp:29`, `OpsClosures.cpp:103, 138`, `Constants.cpp:147`).
  Whole-module walks per pass: `ProgramOp::verify` (O-62), and
  `verify::program` (lane 01).
- **W4** (`isa<` over ops): 5 multi-type sites in this lane (§2), two of
  them `ReturnLike` restated (O-92), one a terminator set (O-50).
- **W8** (bytecode): **yes, on the handoff**: the frontend writes the
  module as bytecode and the driver reads it once
  (`lib/Driver/Run.cpp:270`, 0003's preface); `IdrBytecode.td` encodes
  5 of the 13 types and only the table among the attributes, so every
  constant goes as text (O-99; the encodings are lane 01's).

### §5.3 llvm and §5.5 cxx26

- **I1/I2/I3 over this lane's files**: the ladders are few (5 multi-type
  `isa`), the variant chains two (`Tail.cpp`'s `Where`, `Role` read by
  `get_if` six times, O-60, O-94), the per-pass op tables two
  (`eliminationAt`, the TRMC walk's `step`, O-82, O-93).
- **§5.5 D1** (concepts read ODS, never list ops): **holds already** in
  `Ops.cpp:225-294`: `DivisionOp` and `ShiftOp` read `quotient`,
  `isSigned`, `left`, which the families inject (O-48).
- **M4** (`Support/Scc.cpp` against `scc_iterator`): `DataRemap.cpp:257`
  is one of its clients (O-85).

- **§5.3's wave-2 items over this lane's files** (*measured*, §2's idiom
  counts): the 6 `function_ref`s are cold callbacks of traversals or
  diagnostics (`Arrays.h:44-54`'s `graded` and `extent`,
  `Declarations::define`'s body, the type verifiers' `emitError`): keep;
  the one `std::function` is `DataRemap::Leaf`, stored (O-85); the 2
  `std::variant`s are `Role` (lane 01; read by `get_if` six times here,
  O-60) and `Tail.cpp`'s `Where` (O-94); the 11 `DenseMap`s and 6
  `DenseSet`s are one per remap, per pass or per verify, none per node,
  but `Constants.cpp`'s set is one per constant per verify (O-102); the
  one `switch` on an enum of ours is `stageFacts` (O-61); the one
  worklist is `DataRemap`'s `OnceWorklist` over data types; the SCC
  utility's client is `DataRemap.cpp:257` (O-85).

### §5.4 modular (wave-2 items)

- *"Whether our call op can implement upstream's `CallOpInterface` once
  specialization is done"*: **it already does**: `idr.call` with a
  `FlatSymbolRefAttr` callee (`IdrOps.td:210-237`) and `idr.apply` with a
  value callee (`IdrClosureOps.td:124-157`) both implement it.
- *"Any hand-written `getEffects` or `verify` that exists because an
  attribute changes an op's meaning"*: `idr.call`'s `effects` property
  (`Call.cpp:65-72`); `idr.func`'s `total` changes `bodyEffect`
  (`Func/Func.cpp:190`); `idr.program`'s `stage` changes which root and
  which grades the verifiers accept (`Func/Func.cpp:107`, O-61); and
  `idr.cell.init`'s `holes` change its result list (inferred, not
  verified).
- *"Every option or flag that selects between two implementations"*
  (F17): in this lane's headers, `consumes(operand, callees)` answers
  from the callee's signature or from the operand's grade depending on
  whether a table is passed (`IdrDialect.h:101-108`, O-96).

### §5.6 ecosystem

- **W-E6** (queries on a match that enumerate its regions): effect
  queries through `RecursiveMemoryEffects` (O-12), `isRepetitiveRegion`'s
  per-call vector (above), the region-branch verifier (linear per verify,
  §5.2 H4: acceptable), `takenFromEnclosing` and `FieldOp::canonicalize`
  walking parents per fold (O-52), and `verifyMatchRegions` (linear per
  verify, O-50).
- **W-E8** (single-block regions after defunctionalization): **holds**:
  every region of every op is `SizedRegion<1>` or `SingleBlock`
  (`IdrOps.td:76, 165`; `IdrMatchOps.td:27, 32-33`;
  `IdrClosureOps.td:189, 198`; `IdrArrayOps.td:56, 63, 362, 369, 401,
  412`); the inliner's one transient second block is erased at each site
  (`IdrOps.td:126-129`, `Func/Inliner.cpp:25-32`). It stays so until
  idr-lower makes each match an `scf.index_switch`
  (`lib/Conversion/Matches.cpp:96, 123`) and tail loops make loops.
- **E4** ("one op, effects by operand type", HLFIR): `con`, `field`,
  `tag`, `match` and `call` are this design today (O-8..O-10, O-54).
- **W-E4** (an analysis fact in a discardable attribute): none written
  in this lane's files; one read, the target triple from the module's
  `llvm.target` (`OpsPlatform.cpp:39-42`, O-103).
- **W-E5** (budgets): two, neither can fail: `constantBytes = 1 << 20`
  leaves a large folded constant unfolded (`IdrDialect.h:263-268`, O-97),
  and `aliasFrom = 256` prints a large constant as an alias
  (`Asm.cpp:51-55`, O-90).

### §5.7 library

- **L1's check** ("whether `take`, `own.give`, `share`, `borrow` and the
  rest already define one [value per ownership change]"): **holds for
  every ownership op**: `borrow`, `share`, `lin.enter`, `lin.use`,
  `own.adopt`, `own.give`, `dup` each give a new value; `take` gives a
  token and the fields, `unpack` the fields; even the guards give their
  operand back refined (`IdrCheckOps.td:56-73`), which is SSI for
  refinements. `drop` alone ends a value without one, as it must. **Does
  not hold for the match**: a case region binds the constructor's
  *fields*, never the refined scrutinee, and the default binds the
  scrutinee back at its *unrefined* type (`IdrMatchOps.td:106-112`); so
  "what this case knows about the scrutinee" is recovered by walking up
  to the enclosing match, three ways (O-52).
- **M3** (e96bb991 is a parse repeated): the op side answers per terminator
  in O(1); the quadratic was the client's (lane 07).

### §5.8 dialect-design, DS4 row by row

| DS4 row | verdict | ground |
| --- | --- | --- |
| `cell.new`, `cell.stack` as one `Idr_CellAllocOp` class | **holds** | they differ only in result constraint and resource (`IdrOwnershipOps.td:182-213`), exactly memref's alloc/alloca |
| `cell.recycle` → `cell.reuse` with `Free` stage 0, `Alloc` stage 1 | **holds, built**; a rename | `MemFreeAt<0, FullEffect>` on the token and `MemAlloc<Default, 1>` on the cell already (`IdrOwnershipOps.td:230-231`) |
| `lin.enter, lin.use, own.adopt, own.give, share, borrow` → one regrade cast | **refuted in part** | their effects differ (`borrow` `Pure`; `share` `ConsumesOnly`; `lin.*` allocate on `LinResource`; `own.give` a hand consuming `getEffects`; `own.adopt` `Pure`), so O1 keeps them apart; what holds: `lin.enter`/`lin.use` are one regrade in two directions, and `share`'s two readings (forget exclusivity, raise the lifetime) are one regrade whose legality is `forgets` (`IdrOwnershipOps.td:120-121`) |
| `dup`, `drop` kept | **holds** | |
| `take`, `unpack` → one consuming destructure | **refuted** | `take` reads, writes and may free a cell and gives a token; `unpack` touches no memory (`IdrOwnershipOps.td:318, 329-343`): different effects, two ops; the choice is the operand's type (`buildsCell`), so make the wrong one unwritable (O-27) |
| one forwarding interface for `SameValue, TakesReference, BuildsValue, CarriesOperand, ResultCarriesOperand` | lane 02's | op side: `ResultCarriesOperand` on `borrow, share, lin.enter, lin.use`; `SameValue` on `borrow, lin.enter, lin.use`; `TakesReference` on `dup, array.get`; `BuildsValue` on `con, closure, suspend, delay, cell.init` (*measured*, generated classes) |
| `ConsumesOperands`/`ConsumesOnly` → `MemFree` on consumed operands | **holds, built** | `consumedEffects` frees on `ReferenceResource` (`IdrDialect.h:96-99`, M2 above) |
| `NoReturn` → terminators | **holds** | `crash`, `crash_str`, `io.exit` are each followed by `ub.unreachable` (`IdrCheckOps.td:21, 28-29`, `IdrPlatformOps.td:280-281`) |
| `check.nonzero ... range` → `arith.cmpi` + one `idr.check %cond, <reason>` | **refuted** | a guard returns its operand refined so the total op "stays below its check by data dependence" and "a proof is the absence of the guard" (`IdrCheckOps.td:56-73`); `cf.assert`'s shape has no result, so any pass that reads only def-use could hoist the total op above its check. The guards also check against the very value indexed (`IdrCheckOps.td:105-107`), which a `cmpi` on a length computed apart loses. What holds: one class, `kind` as data, and the `cause` an enum (O-38) |
| `check.crash`, `crash_str` → one terminator | **holds** | O-37 |
| `may_loop`, `Divergence` | owner's (ods-Q1, DD-Q2) | |
| `divs, divu, mods, modu, shrs, shru` → `arith` where it agrees | **holds for `divu`, `modu`; refuted for the rest** | the lowering of `divu`/`modu` is exactly `arith.divui`/`remui` behind their guard (`lib/Conversion/Scalars.cpp:75-77`); `divs`/`mods` are Euclidean and wrap `MIN / -1` (`Scalars.cpp:79-100`, `Ops.cpp:207-223`), which neither `divsi` nor `floordivsi` is; the four shifts are defined for every amount and a signed negative amount reverses (`IdrScalarOps.td:55-60`), where `arith`'s are poison from the width |
| `shls`, `shlu` → one | **refuted** | they differ on negative amounts: the signed op turns them (`Ops.cpp:260-264`) |
| `put_sint, put_uint, put_double, put_char` → `show` then `io.write` | **holds as design**, needs the runtime's check | each calls its own runtime entry (`IdrIOOps.td:47-61`); composition is meaning-preserving only if `idris_rt_io_put_int_s(x)` writes what `idris_rt_str_show_s(x)` builds (lane 18) |
| six stat-time ops → one `io.file.stat` | **holds in part** | the OS call is already one, `io.file_time`, which fills a handle; the six read fields of that handle and `io.handle_free` frees it (`IdrPlatformOps.td:136-152`): one op of six results deletes seven ops' worth of handle traffic, but base's API is the six primitives over a pointer, so the registry (lane 15/16) maps them |
| eight clock ops → `io.clock <kind>` | **holds in part, and goes further** | six readings differ only by clock id (`IdrPlatformOps.td:330-335`, two of them "never valid"); the three queries `clock_valid`, `clock_second`, `clock_nanosecond` are pure functions of an `OSClock` word (`IdrPlatformOps.td:17-19`) that today take and give a world (`:337-348`): IO for a pure computation |
| `tabulate`, `tabulate_io` → one | **holds if the world goes** (O-43) | |
| `fold_last`, `scan_last`, `transpose` → linalg forms | lane 11's | |
| `array.*` in the tensor style | lane 11's | |
| `closure`, `apply` legal only before defunctionalization | **holds**; today the stage rule (`verify::program`, lane 01) enforces it, not the op | O-1 |
| a `lazy.` family | **holds in part** | `suspend`, `delay`, `force`, `memo.run` |
| `con, field, tag` → `data.*`, indices printed by name | **holds, built but the names**: tags are stored as `i32` and printed by name through `CtorRef` (`Symbols.cpp:143-168`) | rename only |
| `func, call, return` → `func.*` unless `!idr.fn` carries conventions | owner's (DD-Q7), evidence §6 | |
| `match_lit` on words → `scf.index_switch` / `cf.switch` | **holds in part** | idr-lower already makes both matches `scf.index_switch` (`Conversion/Matches.cpp:96, 123`) and a string or big key chain of `scf.if` (`:140-159`); on `i1` it is idr-rc's select (`IdrMatchOps.td:138-141`), i.e. `scf.if` |
| `Idr_Runtime` kept; `Primitive` implied by it | **refuted for `Primitive`** | 114 `Primitive` against 119 `CallsRuntime`, different sets (O-30) |

- **§5.8 wave-2: "which word ops differ from `arith` on inputs the runtime
  defines, and why `shls` and `shlu` are two"**: answered in the table
  (divisions, shifts).
- **§5.8 wave-2: "every op with a `UnitAttr`, an optional operand or an
  enum, and whether it changes effects, UB or valid states"**:
  `idr.func`'s `total` (changes the body's divergence effect),
  `no_inline` (changes inlining's legality), `effects` (changes every
  call's effects); `idr.call`'s `effects` (changes its effects);
  `idr.program`'s `stage` (changes every op's valid states); `big.cmp`
  and `str.cmp`'s predicate (only the pure function: B4's legitimate
  enum); `cell.init`'s `holes` (changes its results); `transpose`'s
  permutation (pure); the match's optional default region (an empty one
  means "no other constructor arrives", a valid-state fact, O-44); the
  guards' `cause` (only the text). No op has an optional operand.

### §5.9 mlton

- **M3** ("the match with a region per case is the representation behind
  e96bb991"): **holds in part**: the representation *admits* the
  quadratic query, but the op itself answers each terminator in O(1); the
  quadratic was a client asking per (terminator, successor) pair.
- **Design 2's premise** ("produced successor operands are the arm block
  receiving the fields"): the match already declares its case arguments
  as no successor inputs (`IdrMatchOps.td:17-21, 92-94`), which is the
  region form of exactly that: the op produces the fields.
- **Q-W3** (what a 30,000-arm match costs): per case, one `Region`, one
  `Block`, its field arguments, one `idr.yield` (or `ub.unreachable`)
  and a 4-byte tag in the `DenseI32ArrayAttr` (*read*: the op's
  structure); as a CFG terminator the `Region` objects go and the
  terminator gains a `BlockOperand` per arm. Bytes per object are
  *conjecture* until measured (§8).
- **Q-W4** (which passes read the match's region structure): after
  defunctionalization, `Transforms/Tail` (Frames, FramesPlan,
  FramesTypes, Loop, TailLoops, Trmc, WhileDo, AccumulatorPlan),
  `Transforms/Ownership` (Placement, Reshape, Take),
  `Transforms/Bufferize/Data`, `Columns/Calls`, `Narrow/Ops`,
  `Specialize/Raise`, `Inline/Inline`, `Expect` (Does, Placement,
  Quantities, Returns), `Analysis/{Ranges,IdentitiesRecord}`,
  `Analysis/Ownership/Reuses`, and the lowering `Conversion/Matches`
  (*measured*, `grep -rlE` above); 17 files of `lib/IR` and
  `lib/IR/Canon` beside them. Counting runs on the regions (W8 of §5.10).

### §5.10 rc

- **W7** (each ownership op against the field's):
  - `take`/`unpack` are FP²'s destructive match, `take` with the reuse
    credit as its token (`IdrOwnershipOps.td:304-352`); two ops because
    only one touches memory.
  - `share` is uniqueness logic's one-way `P ⊢ P°` (exclusive → owned)
    and, at a join, a lifetime raise (heap → frame); one regrade whose
    legality is `forgets` (`IdrOwnershipOps.td:109-133`).
  - `own.adopt`/`own.give` are the two directions of one crossing
    between our grades and upstream's buffers (plain memref ↔ owned),
    with different effects (`Pure` against a consumption), and two
    verifiers that follow def-use chains (O-70); 0003's owed
    `own.alloc/load/store` would make the crossing structural.
  - `lin.enter` and `lin.use` are the two directions of QTT's binder rule
    at quantity 1 (any value fills a linear binder; its one use becomes
    an ordinary value), each "allocated on a resource of its own" so CSE
    never merges two entries (`IdrOwnershipOps.td:388-399`): EF5's fake
    resource.
  - `borrow` is OSSA's guaranteed value without an `end_borrow`: its scope
    is "every use before the owner's consuming use on each path", checked
    by the owned stage's verifier, a whole-function rule (B10's pass, not
    an op verifier). DD-Q6's region form would make it local.
  - **one op with different effects**: `lin.enter`/`lin.use` (same
    effects, two directions); none other: `borrow`/`share`/`own.*`/
    `take`/`unpack` differ in effect.
- **W8**: counting runs on the match's regions: `Transforms/Ownership/
  {Placement,Reshape,Take}.cpp` read `MatchOp` (Q-W4 above).

### proposal 0003

- *A token without its cell*: **holds**; `TakeOp::inferReturnTypes`
  already knows the box and the tag where it makes the token
  (`OpsOwnership.cpp:153-167`), so `!idr.token<box, @C>` costs nothing
  there (the type is lane 01's).
- *What an enclosing match says, three ways*: **holds** (O-52).
- *`OsOp::fold`'s fallback*: **holds** (O-81).
- *`own.adopt`/`give` and the owned verifier's `memref::` cases*:
  **holds** (O-28, O-70).
- *`effectInstances` beside hand readings*: **holds** (O-66).
- *The crash-site count and the crash effect disagree*: **holds**:
  `io.exit` carries `NoReturn` but not `Idr_MayCrash`
  (`IdrPlatformOps.td:282` against `IdrInterfaces.td:116-117`); making
  every program-ending op a terminator (O-37, O-39) gives "ends the
  program" one representation.

## 4. Issues

Paths below are relative to `foreign/idr/` unless they say otherwise.
All *read* unless marked. IDs are `O-<n>`; the table is grouped by file.

### 4.1 The `.td` files

| ID | file:line | category | what | proposed disposition |
| --- | --- | --- | --- | --- |
| O-1 | `include/idr/IR/IdrOps.td:52-57, 74` | attribute / ladder | `idr.program`'s `stage` (`higher, first, graded, owned, lowered`) is an inherent enum that changes which ops and grades are legal in every nested function; legality is then checked by branching on the stage in verifiers (see O-61) rather than declared. It is not discardable, so AGENTS.md holds, but it is a flag on the program that decides the valid states of other ops (O1, O4: "ops legal only before/after a pass go through `ConversionTarget`") | keep the stage (it is the pipeline's typestate, essential), but make each op's legal stages ODS data (a `list<Idr_Stage>` field per op class, e.g. `Idr_OwnedOp` declaring `[Graded, Owned]`, the closure ops `[Higher]`), checked by one generated trait; delete the per-stage branches in the verifiers |
| O-2 | `IdrOps.td:97-101, 190-194` | upstream / ods | `ProgramOp` and `FuncOp` implement `setVisibility` as a silent no-op and derive `getVisibility` from the program's `root`: the `Symbol` contract is answered by a lie on write | keep visibility derived (one fact: the root), but make `setVisibility` unreachable (`= delete` is impossible through the interface; an `llvm_unreachable` with the reason, or an assert in debug), so a pass that tries to publish a function is caught |
| O-3 | `IdrOps.td:157-164` | attribute | `idr.func`'s `total` and `no_inline` are `UnitAttr` flags; `no_inline` is "written only by the frontend, on a function of no parameters whose result is lazy" (`:140-141`), i.e. a function of its type | check whether every such function carries it (frontend, lane 15); if it is exactly the type's fact, derive it (`isCAF()` from `function_type`) and delete the attribute. `total` stays (Idris's proof, essential); make it a `BoolProp` or keep `UnitProp` |
| O-4 | `IdrOps.td:162-163, 219-220` | state / ods | `effects` is held on `idr.func` and copied onto every `idr.call` (`writeEffects` writes both), verified by `verifySymbolUses`: a cache with one source and a check, DS2.1's first option already built | keep (it is DS2.1's design); the call's copy is read by its hand `getEffects` (O-5) |
| O-5 | `IdrOps.td:212` (`Idr_CallOp`) | ods | hand `getEffects` (`DeclareOpInterfaceMethods<MemoryEffectsOpInterface>`) translating the `effects` property into resources | essential while effects are a property (A5: effects that depend on an attribute need the whole hand method); generate the property-to-resource table from ODS (the `Idr_Effect` enum's cases carry their resource) so the C++ is one generated loop |
| O-6 | `IdrOps.td:242-248` | ods | `idr.return` has a hand `verify` | read in §4.2 (O-40); upstream's `func.return` keeps a hand verify for the same check, so this is essential unless `FuncOp` becomes `func.func` (DD-Q7) |
| O-7 | `IdrOps.td:256-274` | ods | `idr.constant`: `AnyAttr:$value` plus a hand `verify` and `isBuildableWith` deciding which attribute kinds a type admits | a `TypedAttrInterface`-style constraint per kind (`Idr_ConstantValueAttr` = `AnyAttrOf<[ConAttr, ClosureAttr, StringAttr, BigAttr]>` with the type check in a `PredOpTrait`); `isBuildableWith` stays as the dialect's `materializeConstant` gate |
| O-8 | `IdrOps.td:283-308` (`Idr_ConOp`) | ods / ladder | hand `getEffects` and hand `ConditionallySpeculatable`: a box's con allocates, a sum's is pure, both read off the result *type* (ods-Q2, row 3); also `hasVerifier`, `hasFolder` | effects follow from the result type: one trait supplying `getEffects` for every op whose result type decides (row 3), or split `con` into `data.box` (allocates) and `data.con` (pure) (ods-Q2; evidence §6) |
| O-9 | `IdrOps.td:329-352` (`Idr_FieldOp`) | ods / ladder | hand `getEffects` (memo sums read `MemoStateResource`) and hand speculatability (a box's field is not speculatable, a sum's is), both type-dependent; `hasFolder`, `hasCanonicalizeMethod`, `hasVerifier` | same as O-8: one type-driven trait shared by `field`, `tag`, `match`; or the memo sum's reads become their own ops (`lazy.state`), which makes the memo case unrepresentable on `field` |
| O-10 | `IdrOps.td:359-368` (`Idr_TagOp`) | ods | `AlwaysSpeculatable` plus hand `getEffects` for the memo case | as O-9 |
| O-11 | `IdrOps.td:377` | upstream | `idr.dest.write`'s `Arg<Idr_DestType, "", [MemWrite]>` writes the default resource, not a resource of cells | name the cell resource (lane 02's tree) |
| O-12 | `IdrMatchOps.td:25-37` | upstream / budget | the match carries `RecursiveMemoryEffects` (W4: yes) **and** a hand `getEffects` (`MatchOp`, `:102`): every `wouldOpBeTriviallyDead`, `isMemoryEffectFree` and CSE query walks all N case regions (§5.1 D3) | measure on the stage-1 module (W4); replace the recursive walk by an effect summary computed once per op (Flang's `AliasAnalysisRecursiveEffectsCache` shape, §5.6 E3) or, under Q-O1's CFG form, delete the region op after defunctionalization |
| O-13 | `IdrMatchOps.td:62-72` | upstream | `getSuccessorRegions(parent)` enumerates every non-empty region (O(N), correct per op); but `getPredecessors`, `getPredecessorValues`, `getSuccessorRegions(Region&)` and `BufferizableOpInterface::isRepetitiveRegion` keep upstream's O(N)-per-call defaults (§5.1 C2/C4) | override each with its O(1) answer for a match (a case region's only predecessor is the parent; the parent's predecessors are the yields; no region repeats), declared as `DeclareOpInterfaceMethods<RegionBranchOpInterface, [...]>` |
| O-14 | `IdrMatchOps.td:15-17, 32-33, 42-46` | ods (coordinate) | the default is region 0 and case `i` is region `i + 1` "since ODS takes a list of regions only last"; `caseOf` subtracts 1 and asserts; every reader converts | under the CFG form (Q-O1) the issue is gone; while regions stay, keep the default *last* by making it part of the variadic list's tail is impossible in ODS, so keep one generated accessor pair and ban `getRegion(i)` in passes (essential coordinate cost of ODS) |
| O-15 | `IdrMatchOps.td:35-37` | ods | `hasVerifier`, `hasRegionVerifier`, `hasCanonicalizer` on both matches | read in §4.2 (O-44..O-48) |
| O-16 | `IdrMatchOps.td:142-159` | upstream / list | `idr.match_lit` keeps its keys in an untyped `ArrayAttr` and branches on scalars, strings, bigs, naturals and `i1`: on `i1` it is `scf.if`, on integers `scf.index_switch` (or `cf.switch` under Q-O1), on strings and bigs it is ours | split by what the scrutinee is: integer and `i1` keys go to `scf.index_switch`/`scf.if` (upstream), string and big keys stay one `idr` op with a typed key array (`Idr_LiteralArrayAttr` checked by the type's `LiteralTypeInterface`) |
| O-17 | `IdrMatchOps.td:163-170`, `IdrArrayOps.td:215-224` | ods (two copies) | two yields: `idr.yield` (match; `Idr_ConsumesOnly`, `ParentOneOf<[MatchOp, MatchLitOp]>`) and `idr.array.yield` (generating ops, `array.update`, `element.update`, `memo.run`; `Pure`, parent must implement `YieldTargetsOpInterface`) | one `idr.yield` whose parent's interface decides what its leading values move into (`YieldTargets`), or two yields that say why (the match's consumes, the array's moves into memory); today the array yield is `Pure` while the match yield is `ConsumesOnly`, though both move their operands on |
| O-18 | `IdrClosureOps.td:37-65` | ods (family) | `idr.closure` and `idr.suspend` are one shape (callee + captures, the same five traits, `hasFolder`), differing in result type (`fn` vs `lazy`) | one TableGen class `Idr_CaptureOp<mnemonic, ResultType>`; both are legal only at stage `higher` (O-1) |
| O-19 | `IdrClosureOps.td:101-118` vs `:124-157` | ods / effects | `idr.force` declares `Write` on Crash, Divergence and IO; `idr.apply`, which also runs a label (`Idr_RunsLabelsOpInterface`), declares nothing (unknown effects): two ops that run unknown code with two effect declarations | both "run what a label stands for": one declaration (a `Idr_RunsUnknownCode` bundle) on both, so a reader sees the same effects |
| O-20 | `IdrClosureOps.td:189-215` | ods | `idr.memo.run`: `RecursiveMemoryEffects` + hand `getEffects` + `RegionBranchOpInterface` methods + `hasCanonicalizer`, `hasVerifier`, `hasRegionVerifier`; its region ends in `idr.array.yield` | the hand `getEffects` is the op's own read/write of the cell: declare as `Arg<Idr_MemoCell, "", [MemRead<MemoState>, MemWrite<MemoState>]>` (row 2) if the resource is the memo state, deleting the method |
| O-21 | `IdrOwnershipOps.td:60` | dead / ods | `class Idr_OwnedOp` adds nothing to `Idr_Op`: "an op that idr-rc writes and nothing before it meets" is said in a class name and enforced nowhere | give it the stage list of O-1 (`[Graded, Owned]`), or delete the class |
| O-22 | `IdrOwnershipOps.td:74, 89, 318` | upstream | `dup`, `drop`, `take` put `MemRead/MemWrite/MemFree` on the **default** resource; consumption (`Read`+`Free` on the operand) is right (C4), but on the default resource it conflicts with every memref access | a counted-cell resource (lane 02's tree: `Idr_CountResource` under the heap) so the counts and memref traffic are disjoint |
| O-23 | `IdrOwnershipOps.td:62-80` | ods | `idr.dup` has a hand `verify` and a result grade that is owned *or* exclusive depending on what static data the operand reaches (0003: "A `dup` of atoms-only data exempted by its producer") | the exclusive case is a different op's result (a constant atom needs no dup: `static` lifetime, 0003's owed grade), deleting the walk |
| O-24 | `IdrOwnershipOps.td:98-133` | ods (one op, several readings) | `borrow` (owned → view), `share` (exclusive/frame → owned/heap) are regrades with computed result types (`TypesMatchWith` / `PredOpTrait forgets`) | keep as two ops (they differ in effect: borrow is `Pure`, share `ConsumesOnly`; O1); both are DS4's "one regrade cast" only if effects agree, which they do not |
| O-25 | `IdrOwnershipOps.td:182-213` | ods (family) | `cell.new` and `cell.stack` are memref's `alloc`/`alloca` pair written twice (differ only in result constraint and resource) | one `Idr_CellAllocOp<mnemonic, Resource, CellConstraint>` class (O2, DS4) |
| O-26 | `IdrOwnershipOps.td:237-239` | ods | `cell.init`'s legality is a `PredOpTrait` whose predicate is a C++ function `detail::fillsCell(cast<CellInitOp>(&$_op))`: a hand verify spelled as a predicate | essential check (fields against the cell's constructor); make it a named `NativeOpTrait` with `verifyTrait` so the generated verifier names it, or a type constraint per operand built from `CellType` |
| O-27 | `IdrOwnershipOps.td:304-352` | ods (one op, two types) | `take` (box with a cell: reads/frees memory, gives a token) and `unpack` (sum or atom: no memory) are chosen by `buildsCell` of the constructor; their effects differ, so O1 keeps two ops, but the choice is a function of the operand's type | keep two ops (effects differ: essential); make the wrong one unwritable by operand constraint (`take` on `Idr_BoxWithCell`, `unpack` on its complement) instead of a verifier check (§4.2) |
| O-28 | `IdrOwnershipOps.td:357-382` | ods (two directions) | `own.adopt` (memref result → owned) and `own.give` (owned → plain for a store) cross the boundary with upstream's buffers; `adopt` is `Pure`, `give` has a hand `getEffects`; both `hasVerifier` | 0003's owed form: `idr.own.alloc/load/store` made once by idr-rc, or `give`'s result a flow edge; either deletes both ops' verifiers and the owned verifier's `memref::` cases |
| O-29 | `IdrOwnershipOps.td:388-425` | ods / effects | `lin.enter` and `lin.use` allocate on `Idr_LinResource` so that CSE never merges two entries and DCE removes an unused one: a fake resource standing in for identity (EF5) | the two are one regrade in two directions (`lin.enter`: many → one; `lin.use`: one → many); if QL2's SSI rule holds, each is a value-defining cast and the fake resource can go if CSE is prevented by `Read`+`Free` on the operand (consumption) instead |
| O-30 | `IdrBigOps.td:27-200`; `IdrInterfaces.td:318-320` | ods / list | `Idr_Primitive` means "the frontend names this op as a primitive" (it makes a constructor of the generated `PurePrim`/`IOPrim`), not "calls the runtime": 114 ops are `Primitive`, 119 `CallsRuntime`, and the sets differ both ways (`io.put_list`, `str.pack` are Primitive without a runtime call; `big.pred`, `big.from_sint` call the runtime without being Primitive) (*measured*, §2) | keep both facts (they differ: DS4's "Primitive is implied by the symbol" is refuted, §3); but `Primitive` is applied by hand op by op and is a fact about the *Idris side's* view, so it belongs in the family class (each family says whether its members are the frontend's), never per op |
| O-31 | `IdrBigOps.td:90-91, 219-220`; `IdrScalarOps.td:31-34, 67-70, 101-102, 147-148`; `IdrStringOps.td:104-105` | ods / cpp | families pass `isLeft`, `isSigned`, `isQuotient` as `bit`s into `static constexpr bool` members read by shared C++ (`foldDivision`, `foldShift`): a family as a class template parameter | this is the right C++ shape (a constant of the op class, read under the dispatch, §5.5 D1); keep, and make the bits the family's ODS fields so `idris-mlir-tblgen` reads the same (W5) |
| O-32 | `IdrBigOps.td:208-228`; `IdrScalarOps.td:94-110, 139-156`; `IdrStringOps.td:96-113`; `IdrIOOps.td:47-55` | ods (signedness) | five signedness pairs whose operand constraint is `Idr_SInt` vs `Idr_UInt` and whose runtime symbol ends `_s`/`_u`: `big.from_sint/uint`, `to_char_s/u`, `int_head_s/u`, `str.show_sint/uint`, `io.put_sint/uint` | DD-Q4's evidence (§6); each pair differs in the runtime function, so they are two ops under arith's school; under CIR's they are one op whose operand type carries the sign |
| O-33 | `IdrScalarOps.td:78-89` | ods (two ops, one computation?) | `shls` and `shlu`: a left shift is the same bit computation for both signs *except* that the signed op "reads a negative amount as a shift the other way" (`:58-59`) | they differ on negative amounts, so two ops are right (answers §5.8's "why `shls` and `shlu` are two"); see §3 |
| O-34 | `IdrStringOps.td:60-72` vs `:84-91` | ods (inconsistent split) | `str.pack` (list of `Char`) and `str.concat` (list of `String`) are two ops for the element type, while `io.put_list` takes either (`Idr_BaseListOf<[I32, Idr_StrType]>`) as one op | one rule: the element type decides (one `str.from_list` op) or two ops each (`io.put_chars`, `io.put_strs`); the first matches B4 (same structure, pure function differs) |
| O-35 | `IdrStringOps.td:16-21` | ods | class `Idr_StrBuilderOp` and interface `Idr_StrBuilderOpInterface` disagree: `substr`, `reverse`, `drop_bytes` are of the class without the interface; `big.show` has the interface without the class | one fact: the class lists the interface |
| O-36 | `IdrStringOps.td:84`; `IdrIOOps.td:19-23`; `IdrPlatformOps.td:313-315`; `IdrArrayOps.td:271-273`; `IdrIOOps.td:146-147, 227-228` | ods (four representations) | an IO op carries `Idr_PerformsIO`, `Idr_ObservableIO`, `MemoryEffects<[Read IO, Write IO]>` and a world operand/result; array and buffer ops carry `PerformsIO` and the world but effects on the buffer only; `io.strerror` has `PerformsIO` and IO effects but no `ObservableIO`; `world.new` writes IO with no world operand | DS2 (owner's DD-Q3): one representation; op-side evidence in §6 |
| O-37 | `IdrCheckOps.td:22-50` | ods (two ops, one meaning) | `idr.crash` (message attribute) and `idr.crash_str` (message value); both `MayCrash` + `NoReturn`, neither a terminator, each followed by `ub.unreachable`; `crash_str`'s cause is the string literal `"idris_crash"` (`:38`) | one terminator `idr.crash` taking a message operand (a constant string folds from the attribute form), with no successor; deletes `NoReturn` and the trailing `ub.unreachable` (DS4) |
| O-38 | `IdrCheckOps.td:74-140` | ods / attribute | the five guards carry the crash text as a per-op `StrAttr:$cause`, while the guarded op's ODS already names it (`Idr_Guarded<..., "division by zero">`); the guard's kind is a TableGen record field `checkKind` read by `idris-mlir-tblgen` | the cause is a fact of the (guard kind, guarded op) pair: a generated enum of causes from the `Idr_Guarded` records, stored as an `EnumProp`; the per-instance string goes |
| O-39 | `IdrPlatformOps.td:282-287` | ods | `idr.io.exit` is `NoReturn`, gives a world `next` that never exists, and is followed by `ub.unreachable` | a terminator with no results (as O-37) |
| O-40 | `IdrPlatformOps.td:141-152, 330-348` | ods (family) | six file-time field ops over a file-time handle; six clock readings (two of which, `gc_cpu`, `gc_real`, are documented "never valid" yet call the runtime, `:334-335`); three clock queries | DS4's `io.file.stat` with several results and `io.clock <kind>` (DD-Q5 evidence, §6); the two GC clocks fold to `-1` at once (no runtime call) |
| O-41 | `IdrPlatformOps.td:311-322` | ods / effects | `io.strerror` is "the same at every call" and "nothing the program's outside observes", yet declares `Write` on the IO resource and takes a world | `Read` only (or `Pure` with the runtime as its meaning), no world: it then CSEs and dies when unused |
| O-42 | `IdrBigOps.td:305-322`; `IdrArrayOps.td:236-260` | dead (misplaced) | type constraints (`Idr_ArrayValue`, `Idr_Rank1ArrayValue`, `Idr_ByteBuffer`) and an attribute (`Idr_WorldSpaceAttr`) live in op files | move to the types file (lane 01) in the cutover |
| O-43 | `IdrArrayOps.td:99-135` and `:362-428` | ods (one op, a world flag) | `tabulate`/`tabulate_io` and `array.update`/`element.update` are each one op twice: the second of each pair adds a world operand and result (and `PerformsIO`), and `element.update` works on a default-space memref | if DD-Q3 removes the world (DS2.1), each pair is one op whose region's effects decide (`RecursiveMemoryEffects`, DS4); if the world stays, the pair is an optional operand, i.e. a flag (lane 11 owns the array ops' semantics) |
| O-44 | `IdrMatchOps.td:101-116`, `OpsMatch.cpp:40-47` | ods (two forms, one meaning) | an exhaustive match's default is an *empty region*; a default that runs binds the scrutinee; and a default region ending in `ub.unreachable` is also accepted (`OpsMatch.cpp:30-36`): two spellings of "the rest never happens" | one: the empty default (no region object) is canonical, a default ending in `ub.unreachable` folds to it (canonicalizer, lane 04) and is refused by the verifier after; under Q-O1's CFG form it is "no default successor" |
| O-45 | `IdrPlatformOps.td:355-361` | upstream | `idr.handle.is_null` is `Pure` and calls the runtime for `h == -1` | the handle encoding is the runtime's (one meaning), so keep the op, but give it a folder calling the runtime (as the other pure runtime ops have), so constants fold |
| O-46 | `IdrScalarOps.td:114-122`; `IdrBigOps.td:258-269`; `IdrStringOps.td:144-155, 214-240` | ods | the guarded ops (`to_int`, `big.from_double`, `str.tail`, `str.index`, `str.head`, the divisions, the array accesses, the buffer ops) carry `Idr_Guarded<...>` records **and** `Idr_GuardedOp` by hand; `NoMemoryEffect` + `ConditionallySpeculatable` again by hand on the word ones | one class per guarded family that lists all three (`Idr_GuardedOp`, the `Guarded` record, the speculation trait), so a guarded op cannot forget one (lane 02 owns `GuardedOp`) |

### 4.2 The C++ of the ops (`lib/IR/Ops*.cpp`) and the core plumbing

| ID | file:line | category | what | proposed disposition |
| --- | --- | --- | --- | --- |
| O-47 | `lib/IR/Ops.cpp:205-294` | rederivation / list | Idris's Euclidean division and every-amount shift are written twice in C++: `idrisDivMod`/`idrisShift` (the folders, APInt) and `LowerDivision`/`LowerShift` (`lib/Conversion/Scalars.cpp:58-160`, arith); neither calls the runtime, so AGENTS.md's "folders call the runtime" has no single definition to call | one definition: the expansion into `arith` (the lowering pattern) is the meaning, applied early enough that `arith`'s folders and range inference do the folding; or the runtime gains `idris_rt_divs`/`shls` and both call it. Deletes one of the two copies |
| O-48 | `lib/IR/Ops.cpp:225-232, 276-282` | cpp | `concept DivisionOp`, `concept ShiftOp` constrain templates over op classes by their static members (`quotient`, `isSigned`, `left`) | this is §5.5 D1's shape (a concept reads ODS-generated constants, lists no op); keep, generated from the family's ODS bits (O-31) |
| O-49 | `lib/IR/Ops.cpp:32-199` | ods | nine custom directives (`ResultAtGrade`, `OwnedResult`, `NaturalResult`, `Read`, two `Fields`, `CellResult`, `Shared`, `CellDests`), each "print the type only when it is not the default the grade implies" | essential while grades print as types (they implement the elision S1 asks for); one generic directive `custom<Defaulted>(type, default-builder)` replaces `ResultAtGrade`, `OwnedResult`, `NaturalResult`, `Shared`, `CellResult` (five copies of one rule) |
| O-50 | `lib/IR/OpsMatch.cpp:30-36` | ladder | `verifyMatchRegions` checks every region ends in `isa<YieldOp, ub::UnreachableOp>`; the same check again for the generating set (`OpsGenerating.cpp:56-63`) | `idr.yield`'s `ParentOneOf` and the other terminators' own `HasParent` already make any other terminator unwritable in a match region except foreign unconstrained ones; replace both by `SingleBlockImplicitTerminator`-like ODS constraint or a trait `EndsIn<Yield, Unreachable>` with `verifyRegionTrait`, declared once |
| O-51 | `lib/IR/OpsMatch.cpp:107-129` | ods | `MatchOp::verify`: cases count = regions count, each tag in range, no duplicate, each case region's arguments the constructor's fields at the scrutinee's grade; reads the data type's body through `ctorAt` (`OpsCon.cpp:78-88`) per case per verify | essential (a relation between attribute, operand type and region signatures); keep, but the per-case body read is a read of a mutable type's storage (lane 01, 98c6315c) on every verify of every match |
| O-52 | `lib/IR/OpsMatch.cpp:78-94`; `lib/IR/OpsConReads.cpp:116-138`; (`lib/IR/Canon/Eta.cpp` `knownFromMatch`, lane 04) | rederivation | "what an enclosing match says about a value" is computed three ways with different identity rules (0003): `takenFromEnclosing` looks through linear positions, `FieldOp::canonicalize` requires the value itself; `TagOp::fold` (`OpsConReads.cpp:164-186`) never asks; each walks parents per query | one `knownConstructor(Value, Operation *at)` (0003's owed fix); under QL2/L1 (case regions bind the refined scrutinee) the question disappears: the case's block argument *is* the refined value, so a fold reads its definer, not its ancestors |
| O-53 | `lib/IR/OpsMatch.cpp:163-178`, `OpsConReads.cpp:68-92, 164-186`; `lib/IR/Symbols.cpp:28-37` | state | `builtStateHolds` walks a memo value's users looking for `MemoRunOp` on every fold of every `field`, `tag` and `match` of a memo sum | the memo state as SSA (the force's result is the new state value, QL2) makes "the built state still holds" a def-use fact; until then, keep and note the per-query user walk (O(uses)) |
| O-54 | `lib/IR/OpsMatch.cpp:135-138`, `OpsConReads.cpp:35-38, 157-160` | ods / ladder | three hand `getEffects` (match, field, tag) whose only body is `readsMemoState` of the operand: an effect that follows from the operand's type (row 3) written per op | one trait `Idr_ReadsSumState` supplying `getEffects` (row 3, the `ConsumesOperands` precedent); or the memo read as its own op (O-9) |
| O-55 | `lib/IR/OpsCon.cpp:29-35, 92-104, 239-254` | rederivation | `fits` (a field given at the field's type or owned, at a lifetime the constructor's holds) is applied by `ConOp::verify` and `fillsCell` (cell.init), and the holes interleave is decoded three times: `givenField`/`holeDest` (`OpsCon.cpp:153-165`), `fillsCell` (`:239-254`) and `tail::fieldOf` (`lib/IR/Tail.cpp:99-106`, an unbounded `for (;;)`) | one `NativeOpTrait` `FillsConstructor` with `verifyTrait` for both ops; one `HolePositions` view type (`fieldAt(index)` giving a sum of `Given(Value)` and `Hole(Dest)`) used by all three readers |
| O-56 | `lib/IR/OpsCon.cpp:50-67`; `lib/IR/OpsConReads.cpp:26-29` | ods | `ConOp::getSpeculatability` (box, or any owned field) and `FieldOp::getSpeculatability` (box) read types by hand | with O-8's split (`data.box` vs `data.con`), `box` is `NotSpeculatable` + `MemAlloc`, `con` `Speculatable` unless the owned-field case (the owned stage), which is a fact of the stage (O-1) |
| O-57 | `lib/IR/OpsConReads.cpp:47-62` | ods | `FieldOp::verify` recomputes the result type the builder already infers (`fieldType(value, ctor.fields[index])`) | declare `InferTypeOpAdaptor` (as `take`/`unpack` do): the generated verifier then checks it, and the hand verify goes (the index range check stays as `inferReturnTypes`' failure) |
| O-58 | `lib/IR/OpsConReads.cpp:188-194` | state (guard) | `TagOp::inferResultRanges` handles `data == null` (impossible: the operand is `Idr_SumRead`) and a data type with no constructors | delete the null branch (the operand constraint makes it unrepresentable); keep the empty type's case (an empty sum is real) |
| O-59 | `lib/IR/OpsClosures.cpp:103-165` | ods (two copies) | `ClosureOp` and `SuspendOp` have identical `fold` bodies and near-identical `verifySymbolUses` | one family class (O-18) with the shared methods in a trait or `extraClassDefinition` on the class |
| O-60 | `lib/IR/OpsClosures.cpp:211`; `DataRemap.cpp:198, 246, 312`; `Bytecode.cpp:75, 108` | cpp | `std::get_if<role::Label>` on `Ctor::role` (a `std::variant`, lane 01's) in six places of this lane's files | lane 01's `Role` redesign; at the op side, `memo.run`'s verifier asks for a memoizing label: a typed accessor `DataType::label(Tag) -> optional<Label>` (or `memo()`'s typed view, 0003) replaces the `get_if` |
| O-61 | `lib/IR/Func/Func.cpp:105-120`, `include/idr/IR/Func.h:61-113` | ladder | `ProgramOp::verifyRegions` branches on `stageFacts(stage).idrFunctions()` to accept `idr.func` or `func.func` as the root; `StageFacts` decodes the stage into four `bool`s (16 states, 5 valid) | the stage's facts as ODS data on the enum cases (an `Idr_Stage` record with fields), generated, read by one constexpr table; the root's kind per stage stays essential (two levels of the IR) |
| O-62 | `lib/IR/Func/Func.cpp:56-90` | budget / state | `ProgramOp::verify` walks every op of the program (attribute dictionaries, result types, block arguments) to find a data type the table does not declare: a whole-program walk after every pass on the program, serial | a type's membership in the table is a fact of its creation (lane 01: data types made only through `Declarations`, which declares them); make undeclared types unconstructible and delete the walk, or move it to the `--idr-contracts` instrumentation |
| O-63 | `lib/IR/Func/Func.cpp:92-95`, `IdrOps.td:93-96` | dead | `ProgramOp::lookupRoot` is declared and defined, never called (*measured*: `grep -rn lookupRoot lib include tools unittests`) | delete |
| O-64 | `lib/IR/Func/Func.cpp:106`; `:92-95` | upstream | the root is found with `SymbolTable::lookupSymbolIn(op, name)`, a linear scan of the program's block (§5.2 A9), on every program verify | read it through the verifier's `SymbolTableCollection` (`verifySymbolUses` on the program for its `root` attribute) |
| O-65 | `lib/IR/Func/Func.cpp:189-202` | rederivation / ladder | `bodyEffect` re-derives what a body does by a walk with `isa<MayCrashOpInterface>`, `isa<WorldNewOp>`, `isa<RunsLabelsOpInterface>` and world-typed parameters, beside the ops' declared `MemoryEffects` (the comment says they disagree: "a possible crash also writes the IO resource") | lane 02's one effects model; at the op side, a function's effect is the join of its ops' declared effects mapped to bits by one generated table (O-66), deleting the ladder |
| O-66 | `lib/IR/Func/Func.cpp:232-265` | list | `effectInstances`' `rows[]` hand-copies the ODS bundles (`Idr_IOOp`'s `[Read IO, Write IO]`, `Idr_MayCrash`'s `[Write Crash, Write IO]`, `may_loop`'s `Write Divergence`); its comment cites the ODS it mirrors | generate the table from the `Idr_Effect` enum cases, each carrying its ODS `MemoryEffects` bundle as a record field (one fact, one place) |
| O-67 | `lib/IR/Func/Call.cpp:65-72` | ods / effects | `CallOp::getEffects`: the bits' resources, the consumed operands, and an `Allocate` on `LinResource` per linear result (the fake resource of O-29 again) | as O-5 and O-29 |
| O-68 | `lib/IR/Func/Call.cpp:74-86`, `IdrOps.td:242-248` | ods | `ReturnOp::verify` compares operand types to the parent function's results | essential (as `func.return`); with DD-Q7's `func.func` it is upstream's |
| O-69 | `lib/IR/Func/Func.cpp:140-174` | ods | `FuncOp` has a custom parser and printer only to place `effects<...>` before the symbol and refuse a written visibility | keep (the function syntax is not declarative upstream either), but put `effects` in the attribute dictionary position the generic `printFunctionOp` already handles, deleting the bespoke part, if the owner accepts `idr.func @f(...) attributes {effects = ...}` |
| O-70 | `lib/IR/OpsOwnership.cpp:211-230` | upstream (verifier doctrine) | `OwnAdoptOp::verify` reads its operand's producer (`memref::AllocOp`, one use); `OwnGiveOp::verify` reads its result's user (`memref::StoreOp`): verifiers that follow def-use chains, which MLIR's developer guide forbids (§5.8 B10) | 0003's owed `idr.own.alloc/load/store` makes the pairing structural (one op each), deleting both verifiers and the owned verifier's `memref::` cases |
| O-71 | `lib/IR/OpsOwnership.cpp:91-96` | ods | `DupOp::verify` is a type relation between operand and result | a `PredOpTrait` (or `TypesMatchWith` from the result) in ODS |
| O-72 | `lib/IR/OpsOwnership.cpp:104-203` | ods (two copies) | `TakeOp`/`UnpackOp`: `inferReturnTypes` mirror each other (one requires `buildsCell`, the other forbids it), identical `isCompatibleReturnTypes` and `build` | one family class; the `buildsCell` split as operand constraints (O-27) so inference never refuses |
| O-73 | `lib/IR/OpsOwnership.cpp:240-260` | ods | four identical `inferResultRangesFromOptional` bodies (`borrow`, `share`, `lin.enter`, `lin.use`) required by `Idr_ResultCarriesOperand`'s `DeclareOpInterfaceMethods<InferIntRangeInterface, [...]>` | the `ResultCarriesOperand` C++ trait supplies the member (§5.2 B2), the `TraitList` lists the interface plain; four definitions go (lane 02 owns the trait) |
| O-74 | `lib/IR/OpsOwnership.cpp:22-83` | dead (misplaced) | `buildsCell` and `CellType`'s parser, printer, verifier and value facts live in the ownership ops' file | move with lane 01's types |
| O-75 | `lib/IR/OpsArrays.cpp:42-90, 148-234` | ods (two copies) | `ArrayUpdateOp` and `ElementUpdateOp` delegate seven methods each (`verify`, `verifyRegions`, `getSuccessorRegions`, `getSuccessorInputs`, `getRegionInvocationBounds`, `getEffects`, `getFlowEdges`) to shared helpers over `UpdateOpInterface` | interface default methods (`UpdateOpInterface` with `defaultImplementation`s) or one op (O-43): fourteen definitions become zero or seven |
| O-76 | `lib/IR/OpsArrays.cpp:80-84, 185-188, 229-232` | ods | `updateEffects` is a static `Read`+`Write` on the array operand (default resource) written in C++ | `Arg<..., "", [MemRead, MemWrite]>` in ODS (row 2), beside `RecursiveMemoryEffects`; the hand `getEffects` goes |
| O-77 | `lib/IR/OpsArrays.cpp:25-40, 124-140`; `OpsTabulate.cpp:36-48`; `OpsFolds.cpp:21-37`; `OpsGenerating.cpp:77-86`; `OpsArrays.cpp:276-283` | ods | rank and element-type checks by hand (`verifyCount`, `verifyElement`, `verifyIndices`, `verifyTabulated`, `verifyInits`, `TieShapeOp::verify`) | one `NativeOpTrait` per shared rule (`IndexesArray`, `BindsIndices<rank>`) with `verifyTrait`; `TieShapeOp`'s count as a `PredOpTrait` |
| O-78 | `lib/IR/OpsTabulate.cpp:116-240` | ods (two copies) | `TabulateOp`/`TabulateIOOp`: ten methods each delegating to shared helpers | O-43: one op if the world goes |
| O-79 | `lib/IR/OpsGenerating.cpp:179-187` | ladder | `ArrayYieldOp::getFlowEdges` branches on whether the parent's target is a memo cell or an array: one yield serving two kinds of parent | O-17: `memo.run` gets its own terminator (or the target kind becomes the parent's interface method), deleting the branch |
| O-80 | `lib/IR/OpsArrays.cpp:242`, `IdrCheckOps.td:38`, `OpsChecks.cpp` (`getCause`) | attribute / list | crash causes are spelled three ways: a C++ string literal per op (`"array too large"`, `"idris_crash"`), a per-instance `StrAttr` on guards (O-38), and the frontend's per-site message on `idr.crash` | one generated `CrashCause` enum (from `Idr_Guarded` records and the op-level causes), the per-site message of `idr.crash` kept as the one essential string |
| O-81 | `lib/IR/OpsPlatform.cpp:22-44` | per-target | `OsOp::fold` maps a triple to Idris's OS names by a ladder of `Triple` predicates and falls back to the build's triple (`IDRIS_MLIR_TARGET_TRIPLE`) when the module has none (0003 owes its removal) | the Idris OS name is a field of the target's entry (CMake target table), read with the triple; the fallback goes (the program verifier requires a target) |
| O-82 | `lib/IR/Symbols.cpp:39-73` | ladder | `eliminationAt` decides which ops eliminate a value by `dyn_cast_or_null<MatchOp>`, `<FieldOp>`, `<PutStrOp>` (and `isClosures()`), a closed list of op classes in C++ | an `EliminatesOperand` op interface (match, field of a closure sum, put_str), so raising's set is declared on the ops (lane 09 reads it) |
| O-83 | `lib/IR/Symbols.cpp:19-24` | ladder | `dataTypeOf` is a `TypeSwitch` over `DataType`/`BoxType` | a type interface method `getDataType()` on both (lane 01) |
| O-84 | `lib/IR/DataRemap.cpp:30-85` | list | `describe(Type)` is a second printer of every type kind (`TypeSwitch` with eight cases plus memref/tensor layout and memory space) for content keys | the printer itself with data types elided to their names (an `OpAsmDialectInterface` alias hook per key, or `AttrTypeReplacer` substituting a name-only type, then `canonicalText`); the hand printer goes |
| O-85 | `lib/IR/DataRemap.cpp:257-258`; `include/idr/IR/Symbols.h:170-171` | upstream / cpp | the remap's component order uses `idr::stronglyConnected` (`lib/Support/Scc.cpp`, §5.3 M4) and stores its leaf as a `std::function` | `llvm::scc_iterator` over a `GraphTraits` of the `held` map (§5.3 I6); `unique_function` or a template parameter (§5.3 I5) |
| O-86 | `lib/IR/DataRemap.cpp:97-121` | state | a fresh `AttrTypeReplacer` (and its cache) per field shape and per remade type | essential to the recursion (the comment says a shared one would answer a type still being remade); measure on stage 1 before changing |
| O-87 | `lib/IR/DataRemap.cpp:166-187` | budget | `remakeAll` walks every op of the program (attributes, results, block arguments) per remap, once per pass that remaps | acceptable (linear, once per pass); it is the same walk as O-62's: one cached "data types reached" analysis would serve both |
| O-88 | `lib/IR/ContentNames.cpp:104-127` | state | a content key of a type or attribute is made by printing it in a fresh detached `ModuleOp` (`heldAlone`) and hashing the text, per call (`ContentNames::digest` caches per pass) | measure; a structural hash over uniqued storage is not stable across runs, so text is the honest key; keep, cached in one place |
| O-89 | `lib/IR/Asm.cpp:174-242` | ods | nine `getAsmResultNames` and one `getAsmBlockArgumentNames` written by hand; `ClosureOp`, `SuspendOp`, `DelayOp`, `LinEnterOp`, `ForceOp`, `ApplyOp` each return one constant name | a TableGen field `string resultName` on the op class generating the constant ones (S3); the computed ones (`constant`, `con`, `call`) stay |
| O-90 | `lib/IR/Asm.cpp:51-84` | budget | `aliasFrom = 256`: a printer size policy (constants larger than that print once, as an alias) | fine (it bounds text, never what is printed); keep |
| O-91 | `lib/IR/Regions.cpp:14-18` | upstream | `YieldOp::getSuccessorRegions` asks the parent's `getSuccessorRegions(RegionBranchPoint(term))`, O(1) for a match | keep; with O-13's overrides the yield's successors stay O(1) |
| O-92 | `lib/IR/Tail.cpp:39, 269` | ladder | `isa<ReturnOp, YieldOp>(terminator)` twice more (beside §2's four in `Transforms/Tail`) | `hasTrait<OpTrait::ReturnLike>()` (both carry it, `IdrOps.td:242`, `IdrMatchOps.td:163`) |
| O-93 | `lib/IR/Tail.cpp:145-195` | ladder | the tail-modulo-context walk's `step` is a `dyn_cast` chain over `CellInitOp`, `ConOp`, `YieldOp`, `UnpackOp`, `FieldOp` plus a `ResultCarriesOperand` trait test | a `TypeSwitch` with `DefaultUnreachable`-free `.Default` (I2: a per-pass table over ops), or a forwarding interface (DS4's "one forwarding interface") that says which operand moves into which result part |
| O-94 | `lib/IR/Tail.cpp:57-78` | cpp | `Where = std::variant<Result, Inside, Somewhere>` visited with `get_if`/`holds_alternative` (`:83, 147, 184`) | one exhaustive `match`/`std::visit` (§5.5 D2, I3) |
| O-95 | `include/idr/IR/IdrDialect.h:58-99`; `IdrInterfaces.td:85-92` | ods | the resources are C++ classes here and named in ODS (correct per §5.2 A3: the hierarchy cannot be declared in ODS); `LinResource` exists only to stop CSE (EF5) | lane 02's tree; O-29 removes `LinResource` |
| O-96 | `include/idr/IR/IdrDialect.h:101-108` | state (flag) | `consumes(OpOperand &, const SymbolTable *callees = nullptr)` answers from the callee's signature or from the operand's grade depending on whether a table is passed (0003: "`ownsParameter` answers ... depending on whether a table was passed") | two functions named for their two questions, or one answer read off the call's operand type alone (the call verifier already holds operand types equal to the parameters', `Call.cpp:34-43`), deleting the table path (lane 02 owns `consumes`) |
| O-97 | `include/idr/IR/IdrDialect.h:268` | budget | `constantBytes = 1 << 20`: folders leave a constant larger than 1 MiB unfolded | a budget that only leaves code unoptimized, never refuses (AGENTS.md): keep |
| O-98 | `include/idr/IR/IdrDialect.h:12-43` | cpp | `IdrDialect.h` includes 20 MLIR headers and is included by every unit of the tree | §5.5's precompiled header; split the op declarations by family (`GET_OP_CLASSES` per `.td`) so passes include what they use |
| O-99 | `lib/IR/Bytecode.cpp:68-130`, `include/idr/IR/IdrBytecode.td:38-68` | upstream | the bytecode encodes 5 of 13 types and 1 of 10 attributes (the table); every constant (`#idr.con`, `#idr.closure`, `#idr.big`), `!idr.data`, `!idr.cell` and the rest go as text (§5.2 G1, W8); the frontend writes bytecode and the driver reads it once (`lib/Driver/Run.cpp:270`) | lane 01 decides the encodings; for this lane, the table's `getRows`/`fromRows` translate between `Role` and two parallel fields (`label`, `byName`) "as the format has no case with members of its own": a sum flattened to a product with a validity check (`Bytecode.cpp:107-120`) |
| O-100 | `lib/IR/Func/Inliner.cpp:33-35` | ods | every op and region is legal to inline anywhere | correct for a closed dialect; keep |
| O-101 | `lib/IR/OpsGenerating.cpp:106-122`; `OpsClosures.cpp:205-234`; `OpsMatch.cpp:200-216` | ods (essential) | the remaining hand verifiers: `TransposeOp::verify` (a permutation of the dimensions with matching static sizes), `MemoRunOp::verify`/`verifyRegions` (a memoizing label, its captures at the cell's lifetime, the forced value yielded), `MatchLitOp::verify` (keys are distinct literals of the type) | essential: each relates an attribute, operand types and region signatures in a way no constraint states; keep, `TransposeOp`'s goes if `linalg.transpose` replaces the op (lane 11) |
| O-102 | `lib/IR/Constants.cpp:17-21, 147-150` | state | `verifySymbolUses` of every `idr.constant` builds a `DenseSet<pair<Attribute, Type>>` of checked parts, 64 buckets once it holds one (§5.3 B7), per constant per verify | a constant's parts are uniqued attributes: check each (attribute, type) once per *verify run* through a set the symbol-use walk shares, or move the closure check into the attribute's own verifier where the type is known (lane 01) |
| O-103 | `lib/IR/OpsPlatform.cpp:39-42` | attribute | `OsOp::fold` reads the target triple from the module's discardable `llvm.target` attribute | the target is lane 13's; with O-81 the op reads the target entry's field, not a discardable attribute |


## 5. Target design

What the ops become, applying §5.2's recipe, §5.8's guide and §5.9's
history to what §3 found. Names are proposals (DD-Q8 is the owner's);
effects name lane 02's resources by role (`IO` and its children,
`Crash`, `Heap` for counted cells, `Count`, `MemoState`), whose tree is
lane 02's and the owner's (ods-Q3). Every change states its line.

### 5.1 The rules, as they bind the op set

- **R1. Families from lists.** A family is one TableGen class carrying
  everything its members share: effect bundle, `Idr_Runtime` symbol
  pattern, `Primitive` bit, speculation, guard records, assembly format,
  result name. Members whose difference is data (a symbol, an operand
  shape) are instantiated with `foreach` over a `list` of records
  (§5.3 E1), so adding an OS call is one list entry and `idris-mlir-tblgen`
  reads the same records through `mlir::tblgen` (lane 14). *Line:* a
  member that forgets its family's trait (O-30, O-35, O-46) is
  unwritable.
- **R2. One op per semantics, by O1's line.** Merge where only the pure
  function or the memory differs and an operand's type decides; split
  where effects, undefined behaviour or valid states differ; keep two
  where the computations differ. Applied in the table.
- **R3. Declare, don't write.** Every static effect in ODS (O-20, O-76);
  every type-dependent effect by one trait per rule (row 3; the
  `ConsumesOperands` precedent, §3) or by the split ods-Q2 chooses; every
  type relation a verifier checks as a `PredOpTrait`, `TypesMatchWith`,
  `InferTypeOpAdaptor` or a `NativeOpTrait` with `verifyTrait` (O-26,
  O-55, O-57, O-71, O-77); no verifier reads a producer or a user (O-70);
  the stage's legal ops as data on each family (O-1). *Line:* the 9 hand
  `getEffects` become 1 (`call`, essential while effects are a property)
  and the 22 hand `verify()` become the few that state a relation no
  constraint expresses (`match`, `match_lit`, `constant`, `memo.run`,
  `transpose`, `return`, `program`).
- **R4. A program end is a terminator.** `crash`, `crash_str` and
  `io.exit` become terminators with no successors (O-37, O-39). *Line:*
  the `NoReturn` trait, the `ub.unreachable` the frontend writes after
  each, and the world result of `exit` that never exists go.
- **R5. One yield.** `idr.yield` ends every region of ours; the parent's
  `YieldTargetsOpInterface` says which leading values move into memory it
  holds and of which kind (array elements, a memo state) (O-17, O-79).
  *Line:* the yield's branch on "memo cell or array" goes into the
  parent's identity.
- **R6. Syntax declared.** Every op keeps a declarative format (all but
  `idr.func` have one today; `hasCustomAssemblyFormat` occurs twice in
  the op files, on `idr.func` and on the `!idr.cell` type, O-69); the
  five "print the type only when it is not the default" directives
  become one `custom<Defaulted>` (O-49); constant result names come from
  a `resultName` field (O-89).
- **R7. Every op in one family** (N1): the 46 unprefixed mnemonics get a
  family named after the type or resource they act on (DD-Q8).

### 5.2 The match (Q-O1 and QL2)

Two forms, one per answer the owner may give Q-O1; both delete the three
"what the enclosing match says" rederivations (O-52).

**(a) The region form kept, made sparse by representation (QL2/L1).** A
case region binds, before the constructor's fields, the scrutinee
*refined to its constructor*: `^case(%v: !idr.ctor<!L, @Cons>, %x: i64,
%xs: !L)`, a type that names one constructor of the data type (lane 01:
a type parameterised by the data type and a tag, as `!idr.cell` already
is, `IdrOwnershipOps.td:166-167`). Then:
- `data.field`, `own.take` and `own.unpack` take `!idr.ctor<T, @C>` and
  carry no `tag` attribute: the constructor is the type's, one fact
  (today the op's `tag` must agree with an enclosing case that no
  verifier compares, `OpsConReads.cpp:47-62`).
- a field read is total and speculatable: the rule "a box's field stays
  where its constructor is known" (`IdrOps.td:310-328`) becomes
  unrepresentable instead of a speculation hook (O-9, O-56).
- folders read the refined value's definer (the case argument), never
  the ancestors: `takenFromEnclosing`, `knownFromMatch` (lane 04) and
  `FieldOp::canonicalize`'s walk go.
- the default binds the scrutinee at its own type, as now; an empty
  default is the one spelling of "no other constructor arrives" (O-44).
- the interface: override `getPredecessors` and `getPredecessorValues`
  with their O(1) answers (O-13); keep `RecursiveMemoryEffects` and
  measure it (O-12, W4); if it is a wall, the fix is upstream (a
  recursive-effects summary, Flang's pass-scoped cache made an analysis
  invalidated by the rewriter's listener) or form (b).
- *Line:* a field read of a constructor the value is not, and the three
  enclosing-match walks, are unrepresentable; the per-op speculation
  branches go.

**(b) A CFG core from a lowering point on (§5.9 Design 2).** A
terminator `data.case %v : !L [@Nil: ^nil, @Cons: ^cons], default ^d`
whose successors receive the refined value and the fields as *produced*
operands (`BranchOpInterface`, `SuccessorOperands` with a produced count,
`ControlFlowInterfaces.h:30-58`), and a join block; `cf.br` elsewhere.
Every pass of Q-W4's list (§3) that reads the region structure runs
before the lowering point or is rewritten on blocks; the match regions
and `idr.yield` exist only before it (`ConversionTarget`, O4).
- *Line:* "where does this region's yield go" cannot be asked; the
  successors are the terminator's operand list.
- *Cost:* the 27 files of Q-W4; one region of N blocks whose dominator
  tree upstream builds (Q-W3, unmeasured).

In both, `match_lit` splits by its keys (O-16): integer and `i1` keys are
upstream's `scf.index_switch` / `scf.if` (or `cf.switch` under (b)); only
string and big keys remain ours, as `lit.match` with a typed key array.

### 5.3 The op table

Every one of the 189 ops (§2) appears once in a first column.
"(world)" marks an operand and result that DD-Q3's DS2.1 deletes and
DS2.2 keeps; effects are given for DS2.1, with DS2.2 adding nothing (the
world then only restates the order the effects give).

#### Program, functions, values

| current | proposed (name; op or family; operands → results) | effects | why | representation-first line |
| --- | --- | --- | --- | --- |
| `program` | `idr.program`; one op; properties `root`, `stage`, `types`; one region | none | the closed world and its stage are essential; the root checked through `verifySymbolUses` (O-64); the undeclared-type walk deleted (O-62) | an op illegal at the program's stage fails a generated stage trait: the per-stage branches go (O-1, O-61) |
| `func` | `idr.func` (or `func.func`, DD-Q7); properties `total`, `effects`, `instance`; **`no_inline` deleted** | n/a | `no_inline` is exactly "no parameters, lazy (later memo-box) result" (`compiler/src/IdrisMLIR/Emit/Declarations.idr:52-57`), a function of `function_type` read once (`lib/Analysis/Inline.cpp:29`) | a stale copy of the type's fact is unrepresentable (O-3) |
| `call` | `idr.call`; `CallOpInterface`; `effects` property verified against the callee | from a generated table of the `Effect` bits (O-66), consumption by trait | DS2.1's "the call carries its callee's effects, checked by `verifySymbolUses`" is this op already (`Call.cpp:29-59`) | the bit-to-resource table is generated from ODS: its hand copy goes |
| `return` | `idr.return` (or `func.return`, DD-Q7) | `ConsumesOnly` | essential | — |
| `constant` | `idr.constant`; value constrained to `AnyAttrOf<[#idr.con, #idr.closure, #idr.big, StringAttr]>`, the type relation a `PredOpTrait` | `Pure`, `ConstantLike` | O-7 | `isBuildableWith`'s kind ladder becomes the constraint |
| `con` | ods-Q2 (A): `data.con`, one op, effects by one trait `Idr_BoxAllocates` reading the result type; (B): `data.con` (unboxed sum: `Pure` but for owned fields) and `data.box` (`Res<..., [MemAlloc<Heap>]>`, not speculatable) | (A) type-driven; (B) static | the box/sum branch lives in `getEffects` and `getSpeculatability` (`OpsCon.cpp:50-67`) | (B) makes "a sum that allocates" unwritable; (A) moves the branch into one trait (O-8, O-56) |
| `field` | `data.field %v : !idr.ctor<T, @C> [i]`, result inferred | `Pure` | 5.2(a); `InferTypeOpAdaptor` replaces the hand verify (O-57); the memo read leaves (O-9) | reading another constructor's field is unrepresentable |
| `tag` | `data.tag %v : T -> i64` | `Pure` | O-10, O-58 | the memo branch of its effects goes into `lazy.state` |
| `match` | 5.2(a) `data.match` with refined case arguments, or 5.2(b) `data.case` terminator | `RecursiveMemoryEffects` (a) / none (b) | Q-O1, QL2 | 5.2 |
| `match_lit` | integer and `i1` keys: `scf.index_switch`, `scf.if`; string and big keys: `lit.match` with typed keys | recursive | O-16 | the untyped key array and the `i1` special case go |
| `yield`, `array.yield` | one `idr.yield`, `ReturnLike`, the parent's `YieldTargetsOpInterface` deciding the targets | `ConsumesOnly` | R5, O-17, O-79 | the memo-or-array branch in the yield goes |
| `dest.write` | `cell.write_hole %dest, %value` | `Arg<Dest, [MemWrite<Heap>]>`, consumes `%value` | O-11 | the default resource stops conflicting with every memref access |

#### Closures and suspensions (legal at stage `higher` only)

| current | proposed | effects | why | line |
| --- | --- | --- | --- | --- |
| `closure`, `suspend` | `fn.closure`, `lazy.suspend`; one family `Idr_CaptureOp<mnemonic, ResultType>` with the shared `fold` and `verifySymbolUses` | `ConsumesOnly` | O-18, O-59 | one definition of the capture rule; the duplicate `fold` goes |
| `apply` | `fn.apply` | the bundle "runs unknown code" (IO, Crash, Divergence writes), shared with `lazy.force` | O-19 | the two label-running ops cannot declare different effects |
| `delay` | `lazy.value` (an evaluated suspension) | `ConsumesOnly` | rename only | — |
| `force` | `lazy.force` | "runs unknown code" | O-19 | as `fn.apply` |
| `memo.run` | `lazy.run %cell : !memo-box @Label`; region ends in `idr.yield` | `Arg<MemoCell, [MemRead<MemoState>, MemWrite<MemoState>]>` + `RecursiveMemoryEffects` | O-20 | the hand `getEffects` goes |
| (new) | `lazy.state %v`: the read of a memo sum's state that `tag`, `field` and `match` make today | `MemRead<MemoState>` | O-9, O-54 | a memo read is its own op: no `data.*` op branches on "is this a memo sum" |

#### Ownership and cells (stages `graded`, `owned`)

| current | proposed | effects | why | line |
| --- | --- | --- | --- | --- |
| `dup` | `own.dup` | `Arg<View, [MemRead<Count>, MemWrite<Count>]>` | result relation as `PredOpTrait` (O-71); the exclusive result for static atoms goes to the static lifetime (0003) | O-23: no producer walk decides a grade |
| `drop` | `own.drop` | `Arg<Own, [MemRead<Count>, MemWrite<Count>, MemFree<Heap>]>` | O-22 | counts and memref traffic disjoint |
| `borrow` | `own.borrow` (or a region, DD-Q6) | `Pure` | essential | — |
| `share` | `own.share` | `ConsumesOnly` | one regrade, legality `forgets` (§3) | — |
| `lin.enter`, `lin.use` | one `lin.cast %v : A -> B`, exactly one side at quantity one, legality the grade's | `Res<..., [MemAlloc<Lin>]>` (essential: MLIR's CSE would merge two entries of one value) | §5.10 W7: two directions of one rule | a cast that changes no quantity is unrepresentable; two folders become one round-trip rule |
| `own.adopt`, `own.give` | 0003's `own.alloc` (an owned buffer), `own.store` (an owned element into a buffer, consumed), `own.load` (an element with a reference of its own) | `MemAlloc<Default>`; `MemWrite<Default>` + consumption; `MemRead<Default>` | O-28, O-70 | the pairing with `memref.alloc`/`store` is structural: two def-use verifiers and the owned verifier's `memref::` cases go |
| `cell.new`, `cell.stack` | one class `Idr_CellAllocOp<mnemonic, Resource, CellConstraint>`: `cell.new` (`Heap`), `cell.stack` (`AutomaticAllocationScope`) | `Res<Cell, [MemAlloc<R, 0, FullEffect>]>` | O-25, §5.8 C3 | one definition, the difference exactly the resource |
| `cell.recycle` | `cell.reuse` | `MemFreeAt<0>` token, `MemAlloc<Heap, 1>` cell (unchanged) | rename only (§3) | — |
| `cell.init` | `cell.init`; `Idr_FillsConstructor` trait shared with `data.con`; holes read through one typed view | `Arg<Cell, [MemWrite<Heap>]>` | O-26, O-55 | the hole interleave is decoded once |
| `take` | `own.take %v : !idr.ctor<!idr.box<T>, @C>` (a constructor with a cell) → `!idr.token<box, @C>`, fields | `Arg<Own, [MemRead<Heap>, MemWrite<Count>, MemFree<Heap>]>` | O-27, 0003's token | operand constraints make `take` of an atom or a sum unwritable; the token names its cell |
| `unpack` | `own.unpack %v : !idr.ctor<T, @C>` (no cell) → fields | `ConsumesOnly` | O-27, O-72 | as `take`, the complement |

#### Integers and naturals (`big.`, `nat.`)

| current | proposed | effects | why | line |
| --- | --- | --- | --- | --- |
| `big.add`, `big.mul` | family `Idr_BigNaturalOp`, members from a list | `Res<Big, [MemAlloc<Heap>]>` | unchanged semantics | R1 |
| `big.sub`, `big.and`, `big.or`, `big.xor` | family `Idr_BigBinaryOp`, from a list | as above | `arith` keeps one op per operation (B4 reserves enums for comparisons) | R1 |
| `big.shl`, `big.shr` | family `Idr_BigShiftOp` | as above | — | R1 |
| `big.div`, `big.mod` | family `Idr_BigDivisionOp`, guarded, the class listing `Idr_Guarded` and `Idr_GuardedOp` (O-46) | as above | — | a guarded op cannot forget its guard trait |
| `big.neg`, `big.from_str`, `big.to_double`, `big.show` | a unary big family | `MemAlloc` where they make a big or a string; else `Pure` | — | R1 |
| `big.pred` | `nat.pred` (it takes a natural, `IdrBigOps.td:144`) | `MemAlloc` | N1 | — |
| `big.cmp` | `big.cmp <pred>` | `Pure` | B4's legitimate enum | — |
| `nat.to_big`, `nat.from_big` | unchanged | `ConsumesOnly`, no runtime form; `MemAlloc` | — | — |
| `big.from_sint`, `big.from_uint` | unchanged pair (DD-Q4) | `MemAlloc` | two runtime functions | — |
| `big.small`, `big.to_int`, `big.from_double` | unchanged (`from_double` guarded) | `Pure` / `MemAlloc` | — | — |

#### Fixed-width integers and doubles (`int.`, `f64.`)

| current | proposed | effects | why | line |
| --- | --- | --- | --- | --- |
| `divu`, `modu` | **deleted**: `arith.divui`, `arith.remui` behind `check.nonzero`, the pairing a generated `Idr_GuardOf<"arith.divui", ...>` record the frontend's guards read | `arith`'s | their lowering is exactly `arith`'s (§3) | two ops and their folder copy go |
| `divs`, `mods` | `int.divs`, `int.mods` (Euclidean, wrapping `MIN / -1`), one meaning (O-47) | `NoMemoryEffect`, `ConditionallySpeculatable`, guarded | differ from `divsi` and `floordivsi` | the folder and the lowering stop being two copies |
| `shls`, `shlu`, `shrs`, `shru` | `int.shl_s`, `int.shl_u`, `int.shr_s`, `int.shr_u`, one meaning (O-47) | `Pure` | every amount defined; a signed negative amount reverses (§3) | as above |
| `to_char_s`, `to_char_u` | `int.to_char_s`, `int.to_char_u` | `Pure` | signedness changes the result (DD-Q4) | — |
| `int_head_s`, `int_head_u` | `int.head_s`, `int.head_u` | `Pure` | two runtime functions | — |
| `to_int` | `f64.to_int` | guarded | — | — |
| `double_head` | `f64.head` | `Pure` | — | — |

#### Strings (`str.`)

| current | proposed | effects | why | line |
| --- | --- | --- | --- | --- |
| `str.append`, `str.cons`, `str.from_char`, `str.substr`, `str.reverse`, `str.drop_bytes`, `str.show_double` | builder family whose class lists `StrBuilderOpInterface` (O-35) | `Res<Str, [MemAlloc<Heap>]>` | class and interface agree | R1 |
| `str.show_sint`, `str.show_uint` | unchanged pair (DD-Q4) | as builders | two runtime functions | — |
| `str.pack`, `str.concat` | one `str.from_list %l : !List<T>`, `T` a character or a string (O-34) | builder | `io.put_list` already decides by element type | one rule for "a list's text" |
| `str.tail`, `str.head`, `str.index` | guarded family | `MemAlloc` (`tail`); else `NoMemoryEffect` + speculation | O-46 | — |
| `str.length`, `str.bytes_length`, `str.scalar_at`, `str.scalar_bytes`, `str.cmp`, `str.to_int`, `str.to_double` | pure runtime family | `Pure` | — | R1 |

#### Checks and program ends (`check.`)

| current | proposed | effects | why | line |
| --- | --- | --- | --- | --- |
| `check.nonzero`, `check.in_bounds`, `check.nonempty`, `check.finite`, `check.range` | five ops of one class (their operand structures differ, so O1 keeps five), each returning its operand refined; `cause` a generated `CrashCause` `EnumProp` (O-38) | `MemWrite<Crash>` (ods-Q3 places `Crash` in the tree) | §3: DS4's `cmpi` + `check %cond` loses the data dependence | the per-instance text that ODS already holds goes |
| `crash`, `crash_str` | one terminator `check.crash %msg : !idr.str` (a static message is a constant) | `MemWrite<Crash>` | R4, O-37 | `NoReturn`, the trailing `ub.unreachable` and one op go |
| `may_loop` | owner's (ods-Q1, DD-Q2): kept as `check.may_loop` with `MemWrite<Divergence>`, or deleted | — | — | — |

#### Arrays (`array.`; semantics are lane 11's)

| current | proposed | effects | why | line |
| --- | --- | --- | --- | --- |
| `tabulate`, `tabulate_io` | one `array.tabulate` if DS2.1 (O-43, O-78); else two | `RecursiveMemoryEffects` | ten duplicated methods | the world is the only difference |
| `fold_last`, `scan_last` | `array.fold_last`, `array.scan_last` (different result shapes: two) | recursive | — | — |
| `transpose` | `array.transpose` (or `linalg.transpose`, lane 11) | `Pure` | — | — |
| `array.new`, `array.get`, `array.set` | family `Idr_ArrayOp` with an `IndexesArray` trait (O-77) (world) | `Arg` effects on the array (unchanged) | hand verifiers become one trait | R3 |
| `array.update`, `element.update` | one `array.update` over a memref of either memory space if DS2.1 (O-43, O-75) | `Arg<..., [MemRead, MemWrite]>` + recursive (O-76) | fourteen delegating methods | the world is the only difference |
| `nat.to_extent` | unchanged | `MemWrite<Crash>` | — | — |
| `tie_shape` | `array.tie_shape` | `Pure` | count as `PredOpTrait` | — |

#### IO, buffers, the platform (`io.`, `buffer.`, `clock.`, `handle.`, `target.`)

| current | proposed | effects | why | line |
| --- | --- | --- | --- | --- |
| `io.put_str`, `io.put_char`, `io.get_byte`, `io.get_line`, `io.eof`, `io.n_processors`, `io.write_bytes`, `io.read_bytes`, `io.put_list` | the IO family `Idr_IOOp` (world) | `Read`+`Write` on the console or file child of `IO` (lane 02) | four IO representations become one (DD-Q3) | R1 |
| `io.put_sint`, `io.put_uint`, `io.put_double` | **deleted** (O5): `str.show_*` then `io.put_str`, fused at lowering into the runtime's entry | — | lane 18 confirms the runtime's output equals the show | the pure half folds and CSEs; three ops go |
| `io.buffer_load`, `io.buffer_store`, `io.buffer_copy`, `io.buffer_set_string`, `io.buffer_get_string` | `buffer.load`, `buffer.store`, `buffer.copy`, `buffer.set_string`, `buffer.get_string`; guarded family (world) | `Arg` effects on the buffer only (as today) | memory ops, not IO (`IdrIOOps.td:138-145`) | the `PerformsIO` mark their effects contradict goes |
| `world.new` | DS2.1: `io.unsafe_run` region op, `RecursiveMemoryEffects`; DS2.2: kept | — | DD-Q3 | — |
| `os` | `target.os`, folded from a field of the target's entry (O-81) | `Pure` | — | the OS ladder and the build-triple fallback go |
| `io.file_open`, `io.file_close`, `io.file_read_chars`, `io.file_write_line`, `io.file_chmod`, `io.file_remove`, `io.file_error`, `io.file_flush`, `io.file_seek_line`, `io.file_size`, `io.file_poll`, `io.file_is_tty`, `io.file_read_line`, `io.file_read_char`, `io.file_errno` | `io.file.*`, members of the shape classes instantiated from one list of `(mnemonic, symbol, shape)` records (world) | `Read`+`Write` on `IO.Files` | R1 | adding an OS call is one entry |
| `io.file_time`, `io.file_atime_sec`, `io.file_atime_nsec`, `io.file_mtime_sec`, `io.file_mtime_nsec`, `io.file_ctime_sec`, `io.file_ctime_nsec` | one `io.file.times %file -> (i64 x 6)` (world) | `Read` on `IO.Files` | the OS call is already one; the six are field reads of a handle (§3) | the file-time handle, its six readers and its free go (still one op, one runtime function) |
| `io.dir_current`, `io.dir_change`, `io.dir_create`, `io.dir_remove`, `io.dir_open`, `io.dir_close`, `io.dir_entry` | `io.dir.*`, from the list (world) | `IO.Files` | R1 | — |
| `io.arg_count`, `io.arg`, `io.env_get`, `io.env_pair`, `io.env_set`, `io.env_unset`, `io.sleep`, `io.usleep`, `io.time`, `io.pid`, `io.errno`, `io.handle_free` | `io.process.*`, `io.env.*`, from the list (world) | `IO.Process`, `IO.Environment` (reads disjoint from console writes, EF2) | R1 | — |
| `io.exit` | terminator `io.exit %status`, no results | `MemWrite<IO>` | R4, O-39 | the world after the end of the program is unrepresentable |
| `io.term_raw`, `io.term_reset`, `io.term_setup`, `io.term_cols`, `io.term_lines` | `io.term.*`, from the list (world) | `IO.Terminal` | R1 | — |
| `io.strerror` | `io.strerror %code -> !idr.str`, no world | `MemAlloc<Heap>` on the string only | "the same at every call", "nothing the program's outside observes" (`IdrPlatformOps.td:311-312`) | the IO write it declares against its own comment goes (O-41) |
| `io.clock_monotonic`, `io.clock_utc`, `io.clock_process`, `io.clock_thread`, `io.clock_gc_cpu`, `io.clock_gc_real` | one `io.clock <kind>` (enum `ClockKind`; the two GC kinds fold to `-1`) (world) | `Read` on `IO.Clock` | DD-Q5: one op, one runtime function taking the kind (`clock_gettime`'s id) | six ops become one; "never valid" stops being a runtime call |
| `io.clock_valid`, `io.clock_second`, `io.clock_nanosecond` | `clock.valid`, `clock.seconds`, `clock.nanoseconds`: pure runtime calls on an `OSClock` word, no world | `Pure` | they compute on a word (`IdrPlatformOps.td:17-19`) | IO for a pure computation is unrepresentable |
| `handle.is_null` | unchanged, with a folder (O-45) | `Pure` | — | — |
| `handle.string` | unchanged | `MemRead<IO.Handles>` | — | — |

**Count** (*conjecture*, arithmetic over the table): deletions and
merges remove `divu`, `modu`, `io.put_sint`, `put_uint`, `put_double`
(5), the file-time handle and its six readers become one op (−6), six
clock readings become one (−5), the two crashes one (−1), `lin.enter`
and `use` one (−1), `str.pack` and `concat` one (−1), one yield (−1);
`own.adopt`/`give` become three ops (+1), `lazy.state` is new (+1); with
DS2.1, `tabulate_io` and `element.update` go (−2). About 189 → 168 ops,
and `match_lit`'s integer keys leave for `scf`.

### 5.4 The C++ that remains, and what it becomes

- **`lib/IR/Ops*.cpp`**: the folders (21 here), the few essential
  verifiers, the region-interface methods of the region ops, the range
  hooks, one generic directive (O-49) and the canonicalize hooks;
  everything a trait supplies moves into the trait (O-54, O-55, O-73,
  O-75, O-77). Shared op code stays a class template over op types
  constrained by a concept that reads the family's ODS constants (§5.5
  D1, already `Ops.cpp:225-294`), never an `isa` list.
- **`Func/`**: `bodyEffect`'s ladder goes into lane 02's one effects
  model (O-65); `effectInstances` is generated (O-66); `StageFacts` is
  generated from the `Idr_Stage` records (O-61).
- **`Symbols.cpp`**: `eliminationAt` becomes an interface query (O-82);
  `builtStateHolds` goes with `lazy.state` (O-53).
- **`Tail.cpp`**: `ReturnLike` instead of the two ladders (O-92); the TRMC
  walk a `TypeSwitch` or the forwarding interface (O-93); `Where` one
  exhaustive visit (O-94). The algorithm is lane 10's.
- **`DataRemap.cpp`, `ContentNames.cpp`**: `describe` replaced by the
  printer with data types elided (O-84); `scc_iterator` (O-85).
- **The Idris side** (lane 14 generates it; this lane's ops decide what
  it holds): the generated constructors follow the new ops; the guard
  causes become a generated `CrashCause` enum (`MkGuard 1 Nonzero
  DivisionByZero` in place of the string at
  `compiler/src/IdrisMLIR/Dialect/Idr.idr:124`); the six clock
  primitives of `Registry/Primitives.idr:345-350` map to one `IOPrim`
  constructor `Clock ClockKind` whose argument is the generated enum, so
  a registry entry names its clock by a constructor of a closed sum;
  `Emit/Declarations.idr:52-57` loses `noInline`. All of it within both
  hosts' subset: enums and constructors, no dependent field.

### 5.5 Order inside the subsystem, and dependencies

1. **Declarations without semantic change** (R3, R6): ODS effects for
   `memo.run` and the updates, traits for the shared verifiers, the
   generic directive, result names, the stage list per family. Depends
   on lane 02's resource tree and trait C++ (`ResultCarriesOperand`
   supplying ranges, `ConsumesOperands`).
2. **Families from lists** (R1): IO, platform, big, str, check. Depends on
   lane 14 (`idris-mlir-tblgen` reading the `mlir::tblgen` wrappers, so
   the Idris constructors follow the lists).
3. **Merges and splits** (the table): the crash and exit terminators, the
   cell class, `lin.cast`, the clock and file-time ops, `str.from_list`,
   `divu`/`modu` to `arith`, `put_*` composed. Depends on lanes 15/16
   (the registry), 18 (the runtime's functions), 12 (the lowering).
4. **The match** (5.2): (a) or (b) by Q-O1, with QL2; depends on lane 01
   (`!idr.ctor<T, @C>`), lane 04 (the folds that read enclosing
   matches), lanes 07, 08, 10, 11, 12 (the readers of Q-W4).
5. **The world** (DD-Q3) and the `con` split (ods-Q2) when the owner
   rules; each halves a pair of rows above.
6. **Renames** (R7, DD-Q8) last: mechanical, one change across C++, ODS,
   tests and the generated Idris side.

## 6. Evidence for the owner's questions

No answers: what the code says, by question.

### Q-O1 (structured match after defunctionalization?)

- **The op is already the region form of a case with produced fields.**
  A case region binds the constructor's fields, which the match declares
  as no successor inputs (`IdrMatchOps.td:15-24, 92-94`); every region is
  one block (`SizedRegion<1>`, `SingleBlock`) ending in `idr.yield` or
  `ub.unreachable` (`OpsMatch.cpp:25-36`). The interface answers each
  terminator in O(1) and the parent in O(N) (`IdrMatchOps.td:62-72`,
  `Regions.cpp:14-18`); e96bb991's quadratic was a client's.
- **What reads the regions after defunctionalization** (*measured*):
  27 files outside `lib/IR` (Q-W4 in §3), among them every counting pass
  that places dups and drops per case (`Transforms/Ownership/
  {Placement,Reshape,Take}.cpp`), TRMC and tail loops, whose
  modulo-context walk joins a value "once every region has given it"
  (`lib/IR/Tail.cpp:197-216`), frames, bufferization, columns, narrowing,
  raising and inlining. In a CFG form each of these is rewritten on
  blocks or runs before the lowering point.
- **The structured form already lasts to the end**: idr-lower makes every
  match an `scf.index_switch` (`lib/Conversion/Matches.cpp:96, 123`), and
  upstream's SCF-to-CF makes the CFG; nothing of ours runs on a CFG of
  matches today.
- **The cost the region form keeps**: `RecursiveMemoryEffects` on the
  match (every effect query walks every case, O-12), and the three
  enclosing-match walks (O-52), which 5.2(a)'s refined case argument
  deletes without leaving regions.
- **What a CFG form would delete in this lane**: `Idr_MatchOpBase`'s
  region-branch methods, `verifyMatchRegions`, `caseOf`'s `+1`
  coordinate (O-14), `idr.yield` in match regions, and the empty-default
  convention (O-44).

### DD-Q4 (signedness)

- **The tree is arith's school today, said in ODS**: "Idris's IntN and
  BitsN share one signless integer type and differ in their operations,
  so each operation that reads a sign is one op per signedness, as
  arith's divsi and divui are" (`IdrScalarOps.td:15-18`;
  `IdrTypes.td:312-319`: `Idr_Int`, `Idr_SInt`, `Idr_UInt` are all
  `AnyTypeOf<[I8, I16, I32, I64]>`, differing only in the C ABI word's
  extension).
- **Nine pairs** split by sign: five differ only in the runtime function
  and the operand's ABI extension (`big.from_sint/uint`,
  `to_char_s/u`, `int_head_s/u`, `str.show_sint/uint`,
  `io.put_sint/uint`, O-32); four differ in the computation (`divs/divu`,
  `mods/modu`, `shls/shlu`, `shrs/shru`, §3). `str.to_int` is already one
  op for both signs (`IdrStringOps.td:255-257`).
- **Readers of the sign**: the range hooks (`Ranges.cpp:85-98`,
  `ofInteger(range, isSigned)`), the folders (`Ops.cpp:237-294`,
  `OpsScalars.cpp:22-33`) and the lowerings (`lib/Conversion/
  Scalars.cpp:58-160`) read `OpT::isSigned`, a constant of the op class.
  Under CIR's school the sign would move into the type and each of these
  would read it from the operand's type instead.

### DD-Q5 (one op, several runtime functions)

- **Today one op is one function**, enforced: `idris-mlir-tblgen` refuses
  a symbol two records declare (`tools/idris-mlir-tblgen.cpp:2862-2874`)
  and generates one `Function` per op whose `function` member is the
  C symbol (`:2970-2982`), which folders call
  (`OpsChecks.cpp:38-39`, `fold::runtime<StrLengthOp>`).
- **The runtime already holds the enum the op would carry**:
  `idris_rt_io_clock_utc` is `reading(rt::platform::Clock::Utc)`, the
  thread clock `reading(rt::platform::Clock::Thread)`
  (`runtime/Io/Clock.cpp:39-58`); the file-time readers are
  `field(time, AccessSec)` (`runtime/Io/FileTimes.cpp:48-49`). So
  `io.clock <kind>` can stay one op, one function, with the kind a
  parameter of `idris_rt_io_clock(int64_t kind)`: the one-to-one rule
  survives and the six externs go. The same holds for crash causes,
  which the lowering already passes to one crash function as a string
  (`lib/Conversion/Checks.cpp:110`).
- **The Idris side**: each base primitive is one registry entry naming
  one `IOPrim` constructor (`Registry/Primitives.idr:337-350`); one op
  with a kind is one constructor with an enum argument, generated.

### DD-Q7 (our own function op)

- `idr.func` holds `total`, `no_inline`, `effects` (a property, printed
  before the symbol), `instance`, and derives its visibility from the
  program's root (`IdrOps.td:109-196`); `no_inline` is derivable from the
  type (O-3).
- `idr::FuncOp` is named 530 times in `lib`, `include`, `tools`;
  `func::FuncOp` 26 (the lowered stage); `FunctionOpInterface` 99
  (*measured*, `grep -rhoE '\bFuncOp\b' ... | wc -l`).
- **What the custom call buys**: `idr.call` carries its callee's effects
  as a property verified by `verifySymbolUses` (`Call.cpp:29-59`) and
  declares them to MLIR (`Call.cpp:65-72`), so upstream's CSE and DCE
  read a call alone. `func.call` has no effects interface and no
  property for them; with `func.func` the effects would live in an
  analysis (DS2.1's second option), and upstream passes would see every
  call as having unknown effects.
- The lowering already makes `func.func` (the program's root at stage
  `lowered` is a `func::FuncOp`, `Func/Func.cpp:105-112`).

### DD-Q8 (renames)

- 46 of 189 mnemonics have no family prefix (§2); the families present
  are by type (`big.`, `str.`, `nat.`, `array.`, `cell.`) and by role
  (`io.`, `check.`, `own.`, `lin.`, `handle.`, `world.`, `memo.`,
  `element.`, `dest.`).
- **The cost of renaming**: 334 of the 356 `.mlir` files in `tests/`
  name an `idr` op, 26,104 occurrences, 9,647 of them unprefixed
  mnemonics (*measured*, `grep -rhoE` over `tests/**.mlir`); the Idris
  side is generated (`compiler/src/IdrisMLIR/Dialect/Idr.idr`, 191
  constructor functions) and follows the ODS. A rename is mechanical but
  touches every fixture.

### Touched: QL2, ods-Q1/DD-Q2, ods-Q2/DD-Q3, DD-Q6

- **QL2**: every ownership op already defines a new value (§3, L1); the
  match does not bind its refined scrutinee (§3), which 5.2(a) adds.
- **ods-Q1/DD-Q2**: `check.may_loop` exists only to keep a possibly
  endless loop alive (`IdrCheckOps.td:42-50`); `idr.force` and every
  `MayCrash` op write the divergence or crash resources
  (`IdrClosureOps.td:101-103`, `IdrInterfaces.td:116-117`).
- **ods-Q2/DD-Q3**: `con`, `field`, `tag`, `match` and `call` are the
  "effects from types" shape (§3, W1); the world appears on 44 op
  definitions (*measured*, by text) and is the only difference between
  `tabulate` and `tabulate_io`, and between `array.update` and
  `element.update` (O-43).
- **DD-Q6**: `borrow`'s scope is checked by the owned stage's
  whole-function rule, not by the op (§3, W7).

### New questions for the owner

- **NQ1. A refined constructor type.** Should a case region bind the
  scrutinee at a type naming its constructor (`!idr.ctor<T, @C>`, 5.2a),
  so that `field`, `take` and `unpack` lose their `tag` attribute and a
  field read of the wrong constructor is unwritable? It is QL2 in typed
  form, and a new type (lane 01).
- **NQ2. Ops with no runtime function.** `divs`, `mods`, the four
  shifts and `to_char_s/u` have no runtime function; their meaning is
  written twice in C++ (folder and lowering, O-47). Should the runtime
  gain them (one meaning in `runtime/`, which the folders call, as
  AGENTS.md asks of primitives), or is their expansion into `arith` the
  one meaning?
- **NQ3. Guards on upstream ops.** May the frontend guard an `arith` op
  (`check.nonzero` then `arith.divui`) through a generated pairing
  record, so `divu` and `modu` leave the dialect?
- **NQ4. The stage on the ops.** Should each op family declare the
  stages it is legal at (a generated trait), replacing the program
  verifier's stage rule for ops (O-1)?

## 7. Deletion list

By file and symbol; each is deleted in the change that makes it dead.

- `include/idr/IR/IdrOps.td`: `Idr_FuncOp`'s `no_inline`;
  `ProgramOp::lookupRoot` (`:93-96`); `Idr_ConOp`'s and `Idr_FieldOp`'s
  and `Idr_TagOp`'s `DeclareOpInterfaceMethods<MemoryEffectsOpInterface>`
  (`:285, 329, 360`) and `ConditionallySpeculatable` (`:287, 330`);
  `Idr_FieldOp`'s `tag` attribute and `hasVerifier` (5.2a, O-57).
- `include/idr/IR/IdrMatchOps.td`: `Idr_YieldOp` (one yield, R5);
  `Idr_MatchLitOp` on integer and `i1` keys (O-16); under 5.2(b) the
  whole `Idr_MatchOpBase`.
- `include/idr/IR/IdrClosureOps.td`: `Idr_MemoRunOp`'s
  `DeclareOpInterfaceMethods<MemoryEffectsOpInterface>` (`:191`).
- `include/idr/IR/IdrOwnershipOps.td`: `class Idr_OwnedOp` (`:60`) as an
  empty class; `Idr_LinEnterOp` and `Idr_LinUseOp` (one `lin.cast`);
  `Idr_OwnAdoptOp`, `Idr_OwnGiveOp` (0003's three ops); `Idr_TakeOp`'s
  and `Idr_UnpackOp`'s `tag` (5.2a); the two `Idr_CellNewOp`/
  `Idr_CellStackOp` bodies (one class).
- `include/idr/IR/IdrScalarOps.td`: `Idr_DivUOp`, `Idr_ModUOp`.
- `include/idr/IR/IdrStringOps.td`: `Idr_StrPackOp`, `Idr_StrConcatOp`
  (one `str.from_list`).
- `include/idr/IR/IdrCheckOps.td`: `Idr_NoReturn`, `Idr_CrashStrOp` (one
  terminator); the guards' `StrAttr:$cause` (O-38).
- `include/idr/IR/IdrIOOps.td`: `Idr_PutIntOp`, `Idr_PutSIntOp`,
  `Idr_PutUIntOp`, `Idr_PutDoubleOp` (O5); `Idr_WorldNewOp` under DS2.1.
- `include/idr/IR/IdrPlatformOps.td`: `Idr_FileTimeOp` and the six
  `Idr_File{A,M,C}time{Sec,Nsec}Op`; the six `Idr_Clock*Op` readings;
  `Idr_ExitOp`'s `next` result; the world operands of `clock_valid`,
  `clock_second`, `clock_nanosecond`, `strerror`.
- `include/idr/IR/IdrArrayOps.td`: `Idr_ArrayYieldOp` (R5);
  `Idr_TabulateIOOp` and `Idr_ElementUpdateOp` under DS2.1.
- `lib/IR/Ops.cpp`: one of `idrisDivMod`/`idrisShift` or their
  `Conversion/Scalars.cpp` twins (O-47); the five defaulted-type
  directive pairs folded into one (O-49).
- `lib/IR/OpsMatch.cpp`: `takenFromEnclosing` (`:78-94`),
  `verifyMatchRegions` (`:30-36`); `MatchOp::getEffects` (`:135-138`).
- `lib/IR/OpsConReads.cpp`: `FieldOp::getEffects`, `TagOp::getEffects`,
  `FieldOp::getSpeculatability`, `FieldOp::verify`, the enclosing-match
  walk in `FieldOp::canonicalize` (`:124-138`), `TagOp`'s null-data
  branch (`:189-193`).
- `lib/IR/OpsCon.cpp`: `ConOp::getEffects` and `getSpeculatability`
  (into a trait or the split), `givenField`/`holeDest` (one view).
- `lib/IR/OpsClosures.cpp`: `SuspendOp::fold` and
  `SuspendOp::verifySymbolUses` as copies (family), `MemoRunOp::getEffects`.
- `lib/IR/OpsOwnership.cpp`: `DupOp::verify`, `OwnAdoptOp::verify`,
  `OwnGiveOp::verify`, `OwnGiveOp::getEffects`, the four
  `inferResultRangesFromOptional` (`:242-260`), the mirrored halves of
  `TakeOp`/`UnpackOp` inference; `CellType`'s definitions move to lane
  01's file.
- `lib/IR/OpsArrays.cpp`: `verifyCount`, `verifyElement`, the seven
  delegating methods of `ElementUpdateOp` (DS2.1) or of both updates
  (interface defaults), `updateEffects`, `TieShapeOp::verify`.
- `lib/IR/OpsTabulate.cpp`: the ten `TabulateIOOp` methods and
  `WorldUnused` under DS2.1.
- `lib/IR/OpsGenerating.cpp`: `ArrayYieldOp::getFlowEdges`' memo branch
  (`:182-185`).
- `lib/IR/OpsPlatform.cpp`: `osName`'s ladder and the build-triple
  fallback (`:22-44`).
- `lib/IR/Func/Func.cpp`: `ProgramOp::verify`'s walk (`:56-90`),
  `lookupRoot` (`:92-95`), `bodyEffect`'s ladder (`:189-202`), the hand
  `rows[]` (`:232-265`), `StageFacts`' hand switch (`Func.h:94-113`).
- `lib/IR/Func/Call.cpp`: the `LinResource` allocation per linear result
  if `lin.cast`'s design moves it (O-67).
- `lib/IR/Symbols.cpp`: `eliminationAt`'s ladder (`:39-73`),
  `builtStateHolds` (`:28-37`) with `lazy.state`.
- `lib/IR/Tail.cpp`: the two `isa<ReturnOp, YieldOp>` (`:39, 269`),
  `fieldOf`'s unbounded loop (`:99-106`).
- `lib/IR/DataRemap.cpp`: `describe` (`:30-85`).
- `lib/IR/Asm.cpp`: the six constant `getAsmResultNames` (`:193-216`).
- `compiler/src/IdrisMLIR/Emit/Declarations.idr`: `noInline = shared`
  (`:52-57`); the Idris side's generated constructors of every deleted
  op (lane 14).

## 8. Risks, unknowns, measurements needed

- **No build**: every cost here is read or counted from source; nothing
  ran. The counts of §2 come from regenerating the op declarations into
  `/tmp` with the pinned `mlir-tblgen`.
- **Measurements needed on the stage-1 module**: the case count of the
  largest matches and how often an effect query walks one (O-12, W4);
  the bytes and objects of a 30,000-case match in region form against a
  terminator with 30,000 successors (Q-W3); the time of `ProgramOp::verify`'s
  walk and of `verify::program` per pass (O-62, §5.2 W7); how many calls
  of `isRepetitiveRegion` the linearity verifier makes per match
  (`lib/IR/Verify/Linearity.cpp:126`).
- **Risk: one meaning for `divs`/shifts (NQ2)**: moving the meaning to the
  runtime makes every fold a call through the runtime's C ABI at compile
  time, as the string and big folders already are; moving it to an `arith`
  expansion loses the op's identity for ranges and narrowing unless they
  run before the expansion.
- **Risk: `lin.cast` and `LinResource`**: CSE merges two pure ops with the
  same operands; the fake allocation is what stops it today (§3). Any
  replacement must keep two entries of one value distinct; the
  allocation on a non-addressable resource is the cheapest upstream form.
- **Risk: the refined type (NQ1)** adds a type every pass that rewrites a
  case's arguments must keep; a pass that moves a field read out of its
  case would now fail to type-check rather than miscompile, which is the
  point, but the 27 readers of Q-W4 change.
- **Risk: `put_*` composition**: correct only if the runtime's
  `idris_rt_io_put_int_s(x)` writes exactly `idris_rt_str_show_s(x)`;
  lane 18 must confirm (O5).
- **Unknown: which constructors' `no_inline` the passes change**: if a
  pass adds a parameter to a lazy constant (specialization), the derived
  fact changes where the attribute would have stayed; read
  `Transforms/Optimize` and `Specialize` (lane 09) before deleting it.
- **Unknown: bytecode of constants**: every `#idr.con` goes as text in
  the frontend's bytecode (O-99); on a 71 MB module this may dominate the
  handoff's read time (lane 01, lane 13 measure).
- **Cross-lane dependencies** (no duplication here): the resource tree,
  traits and `consumes` (lane 02); the types `!idr.ctor`, `!idr.token<..>`,
  the table, `Role` (lane 01); the folds and canonical patterns of the
  matches (lane 04); the array ops' semantics (lane 11); the lowering
  (lane 12); `idris-mlir-tblgen` (lane 14); the registry (lanes 15, 16);
  the runtime functions (lane 18).

## 9. Sources read

- `.claude/skills/representation-first/SKILL.md` (whole); `AGENTS.md`;
  `proposals/0000-mlir-native.md` (whole: §0-§4 and §5.1, §5.2, §5.8,
  §5.9 in full; §5.3, §5.4, §5.10 in full; §5.5, §5.6, §5.7, §5.11 by
  their findings, designs and questions; §6-§9); `proposals/0003-facts-
  once.md` (whole); `audits/p0/README.md`; the scopes of
  `audits/p0/01-ods-types.md` and `02-ods-effects.md`.
- This lane's files, line by line:
  `foreign/idr/include/idr/IR/{IdrOps,IdrMatchOps,IdrClosureOps,
  IdrOwnershipOps,IdrBigOps,IdrScalarOps,IdrStringOps,IdrCheckOps,
  IdrArrayOps,IdrIOOps,IdrPlatformOps}.td`;
  `foreign/idr/lib/IR/{Ops,OpsMatch,OpsMatchSyntax,OpsCon,OpsConReads,
  OpsClosures,OpsOwnership,OpsArrays,OpsTabulate,OpsGenerating,OpsBigs,
  OpsScalars,OpsStrings,OpsChecks,OpsFolds,OpsPlatform,Asm,Regions,
  Symbols,Dialect,Bytecode,ContentNames,DataRemap,Constants,Ranges,
  Tail}.cpp`; `foreign/idr/lib/IR/Func/{Func,Call,Inliner}.cpp`;
  `foreign/idr/include/idr/IR/{IdrDialect,Func,Symbols,Tail,Ranges,
  Arrays}.h`.
- Read for context (other lanes' files, cited above): `IdrInterfaces.td`
  (`:85-128, 295-340`), `IdrBase.td` (`:255-310`), `IdrAttrs.td`
  (`:200-209`), `IdrTypes.td` (`:312-319`), `IdrBytecode.td`,
  `include/idr/IR/Traits.h` (`:25-60`), `lib/Conversion/Scalars.cpp`
  (`:1-205`), `lib/Conversion/Matches.cpp` (`:1-160`),
  `lib/Analysis/Inline.cpp` (`:15-40`), `lib/Transforms/Narrow/Ops.cpp`
  (`:160-172`), `tools/idris-mlir-tblgen.cpp` (by grep: `:2754-2982`,
  `:1052-1253`), `runtime/Io/Clock.cpp`, `runtime/Io/FileTimes.cpp` (by
  grep), `compiler/src/IdrisMLIR/Emit/Declarations.idr` (`:35-75`),
  `compiler/src/IdrisMLIR/Registry/Primitives.idr` (by grep),
  `compiler/src/IdrisMLIR/Dialect/Idr.idr` (by grep).
- Pinned upstream: `.toolchain/llvm-project/mlir/lib/Interfaces/
  ControlFlowInterfaces.cpp:225-320`.
- History: `git log` of every file above; `git show` of 64655a9d,
  651164af, 6f99507c, a676302b, 1e1a3827, 08647d2e (messages), and the
  subjects of 7987388b, 73bba53f, b9d4d592, 98c6315c, c4d38e9b, 955e2b92.
- Measurements (commands in §2 and §6): `wc -l`; the pinned
  `.toolchain/build/tblgen/bin/mlir-tblgen -gen-op-decls/-gen-op-defs`
  over `IdrOps.td` into `/tmp/p0-ods-ops/` and `grep -c` per trait;
  `grep -rn 'Op::<hook>' lib/IR`; the mnemonic census; the idiom counts
  over the 35 files; the test fixtures' op occurrences.
