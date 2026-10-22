<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 wave 2, lane 11: arrays

Scope: the array stage end to end. `foreign/idr/lib/Transforms/StructureLoops/`,
`Bufferize/`, `Columns/`, `Narrow/`; `lib/Conversion/Arrays.cpp`, `Elements.cpp`,
`Memrefs.cpp`, `Descriptors.cpp`, `Buffers.cpp`; their headers; the array parts of
`IdrArrayOps.td` (lane 03 owns the op definitions); `libs/mlir-array` and
`libs/mlir-linear`.

Marks: *read* (path:line, commit, proposal section), *measured* (a count, with its
command), *recalled*, *conjecture*. Paths below are relative to the repository root;
`idr/` abbreviates `foreign/idr/`.

## 1. Reading notes

Written while reading, in the proposal's order. Each note names the section
and finding ID and says why it bears on the array stage.

**§2 (brief).** The pipeline order puts `columns` after symbol DCE, then
canonicalize+CSE, `structure loops` (arrays to linalg), `bufferize`, then
accumulate/frames/counting, `narrow` after TRMC/tail loops, then lowering to
func/memref/vector, the vectorization schedule (transform dialect), linalg to
loops, LLVM. §2 lists `Transforms/Narrow/{Lanes,Copy}` among the analyses still
on upstream's dataflow framework; the carried patches 24, 27 (one-shot
bufferization) and 09, 57 (integer ranges) are ours to check. §2's trait-layer
report names `Transforms/StructureLoops/Forms.cpp:132` as an `isa<>` ladder
restating a trait class. The array op surface listed: `tabulate`,
`tabulate_io`, `fold_last`, `scan_last`, `transpose`, `yield`, `new`, `get`,
`set`, `update`, `element.update`, `nat.to_extent`, `tie_shape`; interfaces
`Generating`, `Update`, `LastAxisFold`.

**§3.** The stage-1 module (70,000 functions, matches of tens of thousands of
cases) is the scale every design must fit; the walls were state models
(per-value, per-point), not algorithms. None of the listed walls is in the
array stage; whether the array stage runs at all on the stage-1 module (it has
few arrays) is a measurement question (section 8).

**§5.1 mlir-analysis.**
- A4: a `DataFlowSolver` state costs about 2.9 KB at the pin (two 64-bucket
  tables); U1/P1 cuts it fifteenfold. Bears on Narrow's two solver uses
  (Lanes, Copy) and on `IntegerRangeAnalysis` if narrowing moves onto it.
- A6: the supported scope is one function (`top` = a function, calls through
  `visitExternalCall`). Narrow is a program pass today (checked: `Passes.td:679`;
  its word rewrite runs per function, `:707`).
- A7: `loadBaselineAnalyses` (DeadCode + SCCP) must be loaded beside any sparse
  analysis; SCCP's fold simulation uniques property dictionaries (F3, W5).
- B5: `IntegerRangeAnalysis` is sparse forward over `InferIntRangeInterface`,
  loop bounds from `LoopLikeOpInterface`, lattice 240 B, and converges on
  loop-carried values by a per-state widening budget that loses precision and
  never fails (AGENTS.md's shape for a budget). `int-range-optimizations` is
  per-function when scheduled on functions. Directly the design question for
  narrowing.
- C2: bufferization's `AnalysisState::getEnclosingRepetitiveRegion(Block*)`
  never fills its cache (upstream performance bug); `insideMutuallyExclusiveRegions`
  is O(N·depth) per pair; `BufferizableOpInterface::isRepetitiveRegion` is
  overridable. Bears on one-shot bufferization on match-heavy functions.
- D2: bufferization reads `hasEffect<Allocate/Free>` on values and
  `getEffects` (BufferViewFlowAnalysis, BufferUtils, OptimizeAllocationLiveness,
  ownership-based deallocation): effects on values matter to the array stage.
- G3: ownership-based deallocation fixes a function-boundary ABI and leaves
  runtime conditions for a simplifier; the model nearest our counting, and the
  upstream alternative to our own frees (checked: `Bufferize/Releases.cpp` is One-Shot's
  preparation, not a deallocation; counting frees buffers, section 3.2 W9).
- 5.1.2 item 2: `Narrow/{Lanes,Copy}` should go back on the framework as
  per-function solves with summaries through `visitExternalCall`.
- U3: fill bufferization's region cache; walk ancestors in
  `insideMutuallyExclusiveRegions`. Upstream patches the array stage depends on.
- Owner questions: QA2 (per-function solves with summaries vs whole-program
  solves after U1), QA4 (one state representation for our solvers).
- Wave-2 questions in scope: W2 (Narrow's lattices), W3 (`isRepetitiveRegion`,
  `insideMutuallyExclusiveRegions` on our ops through bufferization), W5
  (attributes created on Narrow's hot path), W6 (whether Narrow/Bufferize/
  Columns/StructureLoops are function-anchored), W7 (backward callee
  resolution in Copy, if backward).

**§5.2 mlir-ods.**
- A5: ODS effects and a hand `getEffects` cannot mix on one op;
  `RecursiveMemoryEffects` is the one dynamic form. Tabulate/fold ops have
  regions: are they recursive-effects ops?
- B2/C2: a trait can supply an interface method; `DeclareOpInterfaceMethods`
  for per-op methods. The `Generating` interface is ours; is it used as an
  interface or restated by `isa` (Forms.cpp:132)?
- E1: `OpInterfaceRewritePattern` is filed only under ops with the interface.
- E3: walk driver for one-shot rewrites (structure loops, columns).
- M5: `StructureLoops/Forms.cpp:132` "becomes an interface query".
- Recipe rows 2 (operand effects for `get`/`set`: `MemRead`/`MemWrite` on the
  operand, as memref does), 9 (`AllTypesMatch`, `TypesMatchWith` for element
  types of tensors), 11 (a shape several ops share is an interface), 13
  (properties for axis/extents), 17 (folders), 18 (rooted patterns).
- Q2 (effects that follow from types): bears on `tabulate_io` (world operand)
  versus `tabulate`.
- W1 (every hand `getEffects` in our files), W2 (`MatchAnyOpTypeTag` in our
  files), W3 (every `verify()`), W4 (every `isa<` over ops).

**§5.3 llvm.**
- B1/I1: an `isa<A,B>` ladder over ops is a restated trait, not slow;
  I2: a per-pass table over ops is a `TypeSwitch` with `DefaultUnreachable`.
- B3/I3: closed sums of our own data visited once exhaustively, never a
  `get_if` chain. I4: a sum of handles is a `PointerUnion`.
- B5/I5: hot callbacks are templates, cold ones `function_ref`.
- B6: `zip_equal`, `enumerate` replace parallel-list index bookkeeping (Narrow's
  lane/width vectors, Columns' field lists: to check).
- B7/I7: per-node state is a vector indexed by a dense number; a per-node
  `DenseMap` costs 64 buckets.
- S0: before any solver, ask whether the dialect can carry the answer (a type,
  an op) so no pass solves for it. Directly applicable to narrowing: a width
  carried in the element type of a tensor/memref, or in a `nat.to_extent`
  result type, is a fact no solver recomputes.
- S2: "Analyses whose answer is per function (ranges inside a function,
  lanes, copies) stay on upstream's framework, run in function passes" —
  names Narrow's Lanes and Copy explicitly.
- M9 / Q-llvm-2: budgets cost precision never soundness; an analysis a refusal
  rests on has no budget.

**§5.4 modular.** F9: Modular uses SCF, Linalg and Bufferization zero times
(it has its own memory model); no precedent there for the array stage. F5: its
SCCP iterates loops to a threshold that weakens the result (a budget of
AGENTS.md's shape). Design 2 (per-function solvers, three-tier contract)
applies to a per-function Narrow.

**§5.5 cxx26.** D1: dispatch once where the set is open (MLIR interfaces over
ops), typed code below; a concept may read ODS, never list ops. D2: closed sums
of our own types as `std::variant` plus one exhaustive `match`; `get_if`/
`holds_alternative` banned outside it. D3: solver state is an `IndexVector`
keyed by a typed `Id` the graph mints; no `DenseMap<Value, L>` as solver state.
D4: lists over IR are generated from TableGen; C++-only lists one
`consteval`-checked table. Finding 12: `std::visit` cliff at 12 alternatives.
Q2 (cxx-Q2 in §8, to confirm): ban `std::visit` for one `match`, or allow it
at ≤11 alternatives. Wave-2 items: sort `isa<>`/`dyn_cast` over ops vs our
types; each variant's alternative count and use form; each `function_ref`.

**§5.6 ecosystem.**
- A5: CIRCT's `comb-int-range-narrowing` loads `DeadCodeAnalysis` +
  `IntegerRangeAnalysis` on a pass-anchored op (scoped): the upstream-shaped
  precedent for our `Narrow` (a word-width narrowing pass on ranges).
- D3: IREE's `OptimizeIntArithmeticPass` is per function (FunctionLikeNest),
  re-solves after each greedy round, with a listener erasing states of erased
  ops: upstream `IntegerRangeAnalysis` scoped per function in production.
- D5: IREE's `TiedOpInterface` declares in-place results by interface,
  "rather than hardcoded op names": a model for an in-place promise on array
  update ops (lane-03/02 territory; bears on Bufferize/Linear).
- D6: an analysis answer written into a type once (IREE's resource
  lifetimes); the TODO warns the type should hold the answer's own bits, not a
  lossy summary. Bears on Narrow: the width it finds should become the
  element type, after which nothing re-derives it.
- 5.6.2 item 1: a solver's domain is the values whose type leaves the question
  open (Design 2). Narrow should only see values whose type is a word that a
  range can shrink.
- Design 3: "`Narrow`" is named among the per-value sparse problems that stay
  on upstream's framework, per function, patched.
- W-E2 (state per value vs values whose type leaves it open), W-E4 (facts in
  discardable attributes), W-E5 (budgets), W-E7 (`DenseMap<Value,…>` state).

**§5.7 library.** C2: range analysis is a PLV problem; e-SSA/σ at branches
makes it sparse (relational facts like `i < n` are not PLV: bounds checks on
array indices are relational, hence their own representation: `Fin n`, an
extent in a type). G6: FPL computes at 16 bits and retries wider on overflow,
one dispatch per computation: the same shape as a narrowed kernel version with
a wide fallback (Narrow's `Versions.cpp`, to check). L2 note:
`int-range-optimizations` nested per function measured 3 s vs 30 s module-wide
(`sources/notes/compile-pipeline/upstream-mlir-llvm.md` §4) — direct evidence
for QA2 on the range analysis Narrow would use.

**§5.8 dialect-design (the design the array stage maps onto).**
- B6/T2: a qualifier is an attribute implementing an interface (tensor's
  `encoding`, memref's layout). B7/T7: bufferization admits dialect types
  through `TensorLikeType`/`BufferLikeType` type interfaces; tensor has
  `ValueSemantics`. Our array types (to read) either become builtin
  tensor/memref or implement these.
- B12/O4: linalg's four forms (generic, category, named, composite); a lower
  form is another op (often another dialect), never a flag; "the dialect need
  not be closed under transformations".
- H1: the linalg "op explosion" RFC: separate ops only where code cannot be
  shared; casts/broadcasts/transposes through affine maps.
- O2: two ops differing only in effect are one TableGen class parameterized by
  the resource; a region op whose effects are its body's is one op with
  `RecursiveMemoryEffects`, never a pure op plus an IO twin.
- F3: HLFIR values vs variables (`!hlfir.expr` cannot change, so it moves);
  ownership of a temporary threaded as `i1` `must_free`.
- C7: ownership-based deallocation: ownership as an `i1`, per function, an ABI.
- DS4 rows for this lane:
  - `tabulate`, `tabulate_io` -> one `array.tabulate` with
    `RecursiveMemoryEffects` (O2).
  - `fold_last`, `scan_last`, `transpose` -> named forms of a category,
    lowering to linalg (B12), "(to be read)".
  - `array.new`, `get`, `set`, `update`, `element.update` -> value-semantics
    ops in the tensor style, in place where bufferization or the grade proves
    it (O4, F3), "(to be read)".
  - check ops `in_bounds`, `nonempty`, `range` -> `arith.cmpi` + one
    `idr.check %cond, <reason>` (bears on array index checks).
- DD-Q1 (may `!idr.lin<i64>` normalize to `i64`): bears on linear arrays of
  words and on `!idr.lin` wrapping array values.
- Wave-2: every op with a `UnitAttr`, optional operand or enum that changes
  effects or valid states (O1); every DS4 family's semantics, effects,
  verifier, folders, and every `isa<>` telling members apart.

**§5.9 mlton.** C4: SSA2 makes `Array`/`Vector` one `Object` whose `Prod`
records per-field mutability, and reads/writes take `Base = Object |
SequenceSub {index, sequence}`: mutability as a fact of the field's type, so
`ref` and arrays need no special case in flattening. F3: `DeepFlatten`, the one
pass with state per object value (not per type), is MLton's documented memory
blowup: the lesson for `Columns` (record-of-arrays flattening, to check): size
state by types and constructors. F6: representation chosen once per type, as
sums whose constructors carry only what that representation needs (`TyconRep`,
`ConRep`). G2.7: facts written into the IR's types; nothing else survives.
Q-O3 asks whether every fact a later pass reads is written into a type by the
pass that proves it.

**§5.10 rc.** B7: Lean's arrays carry a linearity marker bit checked where the
runtime would copy; a dynamic assertion of what `!idr.excl` states statically.
G2: Idris 2's quantity 1 is a future promise only; uniqueness follows from a
closed world of construction (`newArray : (1 k : (1 arr : Array t) -> a) -> a`):
the design question for `libs/mlir-array`'s linear arrays. M4: an exclusive
operand makes `is_unique` constant true. R1.4: static and dynamic uniqueness as
one op whose folder reads the grade. **W9: "Whether arrays after bufferization
are freed by our code or could be by upstream's ownership-based deallocation
(G5)"** — in this lane's scope (section 3).

**§5.11 oom.** Wave-2 question **6: "Whether an array's byte size (n × element
size) is checked for overflow before it reaches the allocator (Rust's
`CapacityOverflow`, R1)"** — in this lane's scope (section 3). Item 8:
attributes created per function or per value (Narrow, Columns: to check).
A1: each solver states its state's size in program units; a state sized by a
product of two quantities is a wall (Narrow's versions × lanes: to check).

**§8 owner questions this lane gives evidence for.** QA2 (§8.4, the scope of a
solve) and cxx-Q2 (§8.9, `std::visit` vs a fold `match`), as the dispatch asks.
Also touched: Q-O3/Q-E2 (facts into types: narrowed widths, column layouts),
DD-Q1 (grades on trivially copyable types: linear arrays of words),
ods-Q2 (`tabulate_io` vs `tabulate`), Q-llvm-2/Q-E3 (budgets: any cap in
StructureLoops/Narrow), Q1/cxx-Q1 (the ladder at `Forms.cpp:132`), QA4 (one
state representation, if Narrow keeps a solver of its own), rc-Q2 (static vs
dynamic uniqueness for in-place array update).

**Proposal 0003 (facts once), items in this lane's files.**
- "Ranges discarded (`Narrow.cpp`) and re-solved over the whole program after
  versioning a few loops; `Lanes.cpp` finds a size bound by search behind a
  run-time guard, maybe one `Ranges` proved. Emit ranges as `range` facts and
  seed the re-solve." (filed under the defunc lane there; the files are ours).
- "Resources read as effect bits by hand (`Expect/Placement.cpp` `Order`,
  `StructureLoops/Forms.cpp` `atMostCrashes`): the reverse reading beside
  `idr::effectInstances`."
- "`narrow::Copy`'s hand resync (`copy.bound`, `Narrow/Lanes.cpp`)" among
  "types that could carry the fact".
- The static lifetime: `ownership::isStatic` is read by
  `Transforms/Narrow/Facts.cpp` (one of its readers; owed: `static` in
  `Idr_Lifetime`, `isStatic` deleted).
- `idris_rt_memref_copy` "re-reads the element layout the compiler had"
  (target lane there; it is the array lowering's runtime call, `Memrefs.cpp`/
  `Buffers.cpp`, to check).
- Idris-side leftovers: four "gives no result" internal errors in
  `Emit/Operations.idr` and `Emit/Tensors.idr` (Emit is lane 14's; the
  tensor half is the array stage's frontend side, noted for them).
- §1's rule: keep a fact when re-deriving it is a guess, can refuse, or costs
  more than linear; derive it when it is a total cheap function of a smaller
  representation that is the one source.

**Proposal 0009 (typed APL), read because it holds the owner's array decisions.**
P0's designs for this lane must be reconciled with it, not decided past it.
- The ruling (§0): "a linear thread of writes is a destination-passing chain that
  One-Shot Bufferize puts in place"; "an unordered combine is a structured
  reduction"; "An op, type or pass of ours exists only where upstream has none,
  and each names the gap it fills (§19)".
- §5 / D10, D26: structuring per function after the optimizer, reading final
  effects; D15: reductions mean their left fold, a linalg reduction only in three
  cases (case 1, one associative-commutative integer op, built in
  `Forms.cpp:reassociates`); D16: `idr.scan`/`idr.scatter` until upstream has
  them; D17: one path for counted elements; D18/D33/D43: the release and link
  models; D42: the buffers retype (stage 2 deletes it); D44: columns by upstream's
  1:N conversion.
- §16 stage 2: "Buffers in data-type bodies": from the frontend on, an array
  field is its cell buffer, `idr.con`/`idr.field` the `to_buffer`/`to_tensor
  restrict` boundary, the data-type verifier refuses a tensor in a body;
  `!idr.lin<T>` tensor-like by submission 27 plus a per-instance `extraClassOf`;
  deletes the remap, `heldType`, the retyping loop and "the reason the release
  and link models exist". Its stage-2 decision is open.
- §17 rejected: `tensor.generate`, `concat`, `gather`, `scatter` ("no
  destination, or no bufferization model"); emitting linalg from the frontend;
  ownership-based deallocation ("a second ownership system").
- "The MLIR form owed" (end of 0009): generating ops destination-style and
  tileable (`outs`/inits, `DstBufferizableOpInterfaceExternalModel`,
  `TilingInterface` in place of `GeneratingOpInterface`), the ordered form through
  `lowerToLoopsUsingSCFForOp` after bufferization, then `Nests.cpp` goes;
  `Idr_Iteration` as upstream's `IteratorType` with only `Ordered` ours; one
  counting protocol per element access (`array.get` → `memref.load` + `idr.dup`,
  `array.set` → `own.give` + `memref.store`, the lowering stops counting).

**Proposal 0012 (flattened data).** Columns are the one representation of arrays
of records (0009 D44); arrays of sums as columns is its F2, not built.

**Proposal 0018 (Fin words).** Where a `Fin`'s bound is static the frontend makes
it a word; most bounds are dynamic and stay bigs, which is what `idr-narrow`
recovers (bears on S0: the dialect carrying the width).

## 2. What the subsystem is

### 2.1 Files and sizes (*measured*)

Command: `wc -l` over each path (run from `foreign/idr`, and `libs/`).

| unit | files | lines |
| --- | --- | ---: |
| `lib/Transforms/StructureLoops/` | StructureLoops 78, Forms 189, Linalg 223, Lowering 115, Nests 256 | 861 |
| `lib/Transforms/Bufferize/` | Bufferize 338, Data 360, Linear 115, Releases 161, Values 86 | 1,060 |
| `lib/Transforms/Columns/` | Columns 68, Records 289, Calls 118, Tensors 267, ArrayOps 126 | 868 |
| `lib/Transforms/Narrow/` | Narrow 181, Facts 114, Versions 200, Carried 145, Ops 232, Widths 167, Lanes 249, Copy 159 | 1,447 |
| `lib/Conversion/` (array half) | Arrays 307, Elements 85, Memrefs 172, Descriptors 228, Buffers 78 | 870 |
| headers | Transforms/{StructureLoops 125, Bufferize 36, BufferizeModels 81, Columns 202, Narrow 180}, Conversion/{Arrays 102, Elements 52} | 778 |
| C++ total | | 5,884 |
| `include/idr/IR/IdrArrayOps.td` (lane 03 owns) | 13 ops, 1 enum, 1 attr, 2 type constraints | 478 |
| `libs/mlir-array` | Array 153, Array/Core 248, Linear/Vec 128, ipkg 13 | 542 |
| `libs/mlir-linear` | List 37, Nat 26, Notation 41, String/Iterator 131, ipkg 14 | 249 |

Out of scope but read because the subsystem depends on them: `Analysis/Ranges.{h,cpp}`
(94 lines; lane 05), `IR/Ranges.h`, `IR/Arrays.h`, `lib/IR/OpsArrays.cpp` (319),
`lib/IR/OpsGenerating.cpp` (187), `lib/IR/OpsTabulate.cpp`, `lib/IR/OpsFolds.cpp`
(`getIterations`), the `IdrInterfaces.td` array interfaces (lines 188-266), the
`Passes.td` entries, `Pipeline.cpp`, `Registry/Recognized.idr`'s `arrayLanguage`
(lines 120-160) and `Emit/Tensors.idr` (lane 14) for where the libraries' externs land.

### 2.2 Pattern counts (*measured*)

Command: `bash -c 'grep -rn -- "$p" $F | wc -l'` with `F` the C++ files of 2.1.

| token | count | | token | count |
| --- | ---: | --- | --- | ---: |
| `isa<` | 44 | | `DenseMap<` | 5 |
| `dyn_cast<` / `_or_null<` | 37 / 3 | | `DenseSet<` | 10 |
| `cast<` | 53 | | `MapVector<` / `SetVector<` | 5 / 10 |
| `TypeSwitch<` | 2 | | `walk(` / `walk<` | 13 / 2 |
| `std::visit` / `holds_alternative` / `get_if` | 1 / 1 / 0 | | `DataFlowSolver` | 11 |
| `function_ref<` | 4 | | `OnceWorklist` | 4 |
| `switch (` | 2 | | `hasTrait<` | 7 |
| `template <` / `requires` / `if constexpr` | 15 / 1 / 5 | | `internal error` strings | 9 |
| `std::optional<` | 42 | | `llvm_unreachable` | 3 |

No discardable attribute is set or read anywhere in the subsystem (*measured*: `grep -rn
-E "setAttr\(|setDiscardableAttr|getAttr\(\"|removeAttr"` finds none). No
`MatchAnyOpTypeTag` (7987388b removed the last; `Narrow/Ops.cpp:216-230` roots one pattern
per op from the generated `BigToWord` list).

### 2.3 The passes, what each holds and derives (*read*)

The pipeline order (`lib/Transforms/Pipeline.cpp:85-182`): `idr-columns` (program) →
canonicalize + CSE per function → … → `idr-structure-loops` (nested on `idr.func`,
`Pipeline.cpp:110`) → `idr-bufferize` (program, `:113`) → canonicalize + CSE → counting …
→ `idr-narrow` (program, `:135`, nesting `idr-narrow-words` on each function) → lowering
(`idr-lower`, the array conversion patterns) → vectorization schedule (transform
interpreter) → `idr-narrow-lanes` (`func.func`, `:152`) → `convert-linalg-to-loops`.

**idr-columns** (`Passes.td:310`, anchored on `idr.program`, serial). Holds `Records`
(`Columns.h:66-115`): `held`, the set of record types an array of which some data type's
field holds (`Records.cpp:49-66`, built by walking every op's result types and every block
argument of the program and reaching through fields). `splits(DataType)` is recomputed on
every `recordOf` query (`Records.cpp:76-96`), recursively through fields. The conversion is
upstream's 1:N `applyPartialConversion` (`Columns.cpp:57`) with a `TypeConverter` whose
source and target materializations gather and scatter through `idr.tabulate`
(`Records.cpp:206-259`). Patterns: 6 for calls/returns/matches (`Calls.cpp:102-116`), 7
tensor ops plus a name-rooted `PerColumn` over a hand-written table of 7 op names
(`Tensors.cpp:240-264`), 6 for array ops (`ArrayOps.cpp:102-124`), and upstream's SCF
structural conversions (`Columns.cpp:36`). It never refuses (`Passes.td:337`).

**idr-structure-loops** (`Passes.td:346`, anchored on `idr.func`, parallel). One
post-order walk collects `structurable` ops (`StructureLoops.cpp:46-58`); for each,
`formOf` decides one of four `Form`s (`StructureLoops.h:41-55`, `Forms.cpp:162-187`) from
the op's kind, `getIterations`, the region's effects (`atMostCrashes`, `computes`), the
element types (`overWords`) and, for a fold, whether every combiner reassociates
(`reassociates`) and whether an input is read along the last axis (`readsOf`). Nothing is
stored: `formOf` is re-asked by `Expect/StructuredLoops.cpp:27`. Parallel/Reduction/
Interchange become `linalg.generic` (or `linalg.transpose`), Ordered an `scf.for` nest
(`Nests.cpp`).

**idr-bufferize** (`Passes.td:395`, anchored on `idr.program`, serial). Upstream One-Shot
module bufferization, written out step by step (`Bufferize.cpp:267-335`: `prepare`,
empty-tensor elimination on its own analysis, `analyzeModuleOp`, `insertTensorCopies`,
`bufferizeModuleOp`) over upstream's function-boundary models attached to
`idr.func/call/return` (`Bufferize.cpp:103-113`, patch 24), plus models of ours for 10 op
kinds (`Data.cpp:352-360`, `Linear.cpp:112-115`, `Values.cpp:80-86`). After it,
`moveElementsOut` (`Bufferize.cpp:216-253`) rewrites a load-then-store of an element that
holds references into `idr.element.update`, and `DataRemap` "buffers" retypes every data
type and function that held a tensor (`Bufferize.cpp:319-330`; 0009's D42). Per-query
state: `sharers` (a worklist closure over every aliasing relation, `Releases.cpp:67-80`),
`isLink` (a reverse use-def traversal plus `sharers` plus `mayRunAfter` per use,
`Linear.cpp:32-50`), `yields(match)` (a walk of every region of a match,
`Data.cpp:86-93`).

**idr-narrow** (`Passes.td:679`, anchored on `idr.program`). Reads `Ranges`, an
interprocedural `DataFlowSolver` over the whole program with `DeadCodeAnalysis`,
`SparseConstantPropagation` and a subclass of upstream's `IntegerRangeAnalysis`
(`lib/Analysis/Ranges.cpp:25, 67-76`). Versions each `scf.while` whose natural only
descends (`Versions.cpp`), and when it versioned any loop, invalidates and re-solves the
whole program (`Narrow.cpp:158-165`). Then runs `idr-narrow-words` nested on each function
(`Narrow.cpp:169-172`), which reads the solve through `getCachedParentAnalysis`
(`Narrow.cpp:72-78`): joints first (`Carried.cpp`, an `OpInterfaceRewritePattern
<RegionBranchOpInterface>` building each op's forwarding edges once and grouping them in
`EquivalenceClasses`), then ops (`Ops.cpp`, one pattern per op of the generated
`BigToWord` list plus `MatchLitOp`, `CheckNonzeroOp`, `DupOp`, `DropOp`), both on the walk
driver; then the greedy driver on the conversions only (`Narrow.cpp:125-129`). State per
function: `Facts::madeBounds` (`DenseMap<Value, Bounds>`) and `conversions`
(`DenseSet<Operation *>`) (`Narrow.h:85-87`).

**idr-narrow-lanes** (`Passes.td:782`, anchored on `func.func` after lowering, parallel).
For each outermost vectorized `scf.for` computing on lanes wider than 32 bits
(`Lanes.cpp:113-121`, `Widths.cpp:37-53, 77-86, 139-148`), copies the loop into a scratch
module (`Copy.cpp:28-58`) and searches the largest bound 2^e, e in [8, 31], by one solve
at 2^8 and one per bit of the span (`Lanes.cpp:81-83, 135-159`): at most 1 +
`bit_width(23)` = 6 intraprocedural solves of upstream's `IntegerRangeAnalysis` per loop
(*measured*, arithmetic on the constants), then upstream's `arith-int-range-narrowing`
patterns on the copy (`Copy.cpp:116-149`).

**The array lowering** (`lib/Conversion/{Arrays,Elements,Memrefs,Descriptors,Buffers}.cpp`,
inside `idr-lower`, per function). A memref has two runtime forms: its *components* (cell
plus each field its type leaves dynamic) at function boundaries and in cells, and
upstream's LLVM descriptor inside a function, each built from the other at each use by two
type converters' materializations (`Descriptors.cpp:170-214`). Patterns of ours: alloc,
get_global, `array.new/get/set`, both updates, `array.yield` (`Arrays.cpp:297-305`); element
load/store, the runtime copy, ranked cast (`Memrefs.cpp:165-170`); buffer load/store
(`Buffers.cpp:72-76`). Word loads/stores and linalg over words stay for upstream
(`leftToUpstream`, read by `Lower.cpp:121-127`).

**The libraries.** `Array.Core` declares two external types (`Array`, `LArray`) and 21
bodiless `%extern`s (*measured*: `grep -c '%extern' libs/mlir-array/Array/Core.idr`, 21),
each mapped to a registry entry (`Registry/Recognized.idr:135-158`; `nest`, `merge`,
`freeze` are `identityOn`). `Array.idr` and `Linear/Vec.idr` are plain Idris over them.
`mlir-linear` mirrors contrib's `Data.Linear.*` and `Data.String.Iterator` (two runtime
externs, `Iterator.idr:40-41`).

### 2.4 Who reads the subsystem's results (*read*)

`Expect/StructuredLoops.cpp:27` (`structure::structurable`), `Expect/NarrowedLanes.cpp:27,
32` (`narrow::accumulations`, `narrow::laneWidth`), `Expect/InPlace.cpp:31`
(`bufferize::copies`), `Expect/Words.cpp:10` (includes `Narrow.h`),
`Conversion/Lower.cpp:121-127` (`leftToUpstream`), `Conversion/StaticBytes.cpp:44`
(`holdsWords`), `unittests/Words.cpp:15`. The rewritten IR itself is every pass's result:
nothing is carried between passes in a side table (the one cross-pass fact is `Ranges`,
held by `idr-narrow` for its nested pass only).

### 2.5 Threading (*read*)

Per function and parallel under the pass manager: `idr-structure-loops`,
`idr-narrow-words`, `idr-narrow-lanes`, the lowering. Serial, whole program:
`idr-columns`, `idr-bufferize` (One-Shot's module analysis is interprocedural by design),
`idr-narrow`'s versioning and its one or two whole-program range solves. No mutex, atomic
or `parallelFor` in the subsystem (*measured*: `grep -rn -E "mutex|atomic|parallelFor"`,
none). On the stage-1 module the frontend imports no `mlir-array`, so the value-array
stage sees no tensor there (0009 §7, "SELF-HOST measurement"): its cost there is walks,
One-Shot's module analysis, the retype, and `idr-narrow`'s whole-program solve.

## 3. Reconciliation with the proposal

### 3.1 Findings and designs that touch the subsystem

| finding | verdict | ground |
| --- | --- | --- |
| §2 trait-layer report: `StructureLoops/Forms.cpp:132` is an `isa<>` ladder restating a trait class | **holds in part.** It restates `GeneratingOpInterface` for four of its five ops (`TabulateOp`, `TabulateIOOp`, `FoldLastOp`, `ScanLastOp`; `IdrArrayOps.td:54-57`), plus `TransposeOp`, which is no generating op (`IdrArrayOps.td:192`). The same op set is dispatched three more times in the pass: `formOf` (`Forms.cpp:163, 166, 178`), `lowerParallel` (`Linalg.cpp:109, 118`), `lowerOrdered`'s `TypeSwitch` (`Nests.cpp:242-253`); and `Expect/StructuredLoops.cpp:27` reads the ladder | *read* |
| §5.2 M5: `Forms.cpp:132` "becomes an interface query" | **holds,** and the interface exists already; the remaining case is `idr.transpose` (I-SL9, design C2 below) | *read* |
| §5.1 B5: `IntegerRangeAnalysis` converges by a widening budget that loses precision and never fails | **holds.** `Analysis/Ranges.h:25-33` documents the 128-merge widening and that nothing refuses on a range; `idr-narrow` only narrows where a range states bounds (`Narrow/Facts.cpp:52-69`) | *read* |
| §5.1 5.1.2 item 2, §5.3 S2, §5.6 Design 3: "`Narrow/{Lanes,Copy}` back on the framework, per function" | **holds already for Lanes/Copy, refuted as the open part.** `Copy::analyse` solves a scratch module holding one loop, intraprocedurally (`Copy.cpp:66-76`), freed with the trial: narrower than per function. The whole-program solve is `Analysis/Ranges` (`Ranges.cpp:67-76`, `setInterprocedural(true)` on `idr.program`), read by `idr-narrow`; that is where QA2 bites (§6) | *read* |
| §5.1 A7: SCCP's baseline must load beside a sparse analysis, and uniques property dictionaries per fold | **holds, twice per use.** `Ranges.cpp:74` and `Copy.cpp:71` call `loadBaselineAnalyses`; `idr-narrow-lanes` runs up to 6 solves per vectorized loop (2.3), each with the baseline, in a scratch module whose attributes stay uniqued in the context | *read*; context growth *conjecture* |
| §5.1 C2: bufferization's `getEnclosingRepetitiveRegion(Block*)` never fills its region cache; `insideMutuallyExclusiveRegions` is O(N·depth) per pair; `isRepetitiveRegion` is overridable | **holds, and our models make it reachable.** Pin `BufferizableOpInterface.cpp:84-104` declares `visitedRegions` and never pushes (*read*, confirmed). Our `MatchModel` does not override `isRepetitiveRegion` (`Data.cpp:98-175`), so the default walks the match's region graph per query; `Releases.cpp:111` calls `insideMutuallyExclusiveRegions` per (use, release) pair in `mayRunAfter`, which `prepare` (`Releases.cpp:150-160`) and every `isLink` query (`Linear.cpp:44-48`) reach | *read*; cost on the stage-1 module *conjecture* (no tensor there, so `isLink` never runs; `prepare` still walks every op) |
| §5.1 G3 and §5.10 W9: ownership-based deallocation as the model, or as the freer of buffers | **refuted as a target, by the owner's earlier decision.** `Bufferize.cpp:23-27` ("No ownership deallocation runs: counting frees cells, one ownership system and not two"); 0009 §17 rejects it. W9 answered in 3.2 | *read* |
| §5.2 A5: an op cannot mix ODS effects with a hand `getEffects`; `RecursiveMemoryEffects` adds the op's own declared effects to its body's | **holds; the update ops' hand `getEffects` is a declaration not yet made.** `OpsArrays.cpp:80-84, 185-188, 229-232` (`updateEffects`: `Read` and `Write` on the array operand, default resource) is exactly `Arg<..., [MemRead, MemWrite]>` beside `RecursiveMemoryEffects`, which `IdrArrayOps.td:362, 401` already list | *read* (lane 02/03 own the change) |
| §5.2 W2: every `MatchAnyOpTypeTag` | **none** in the subsystem (7987388b); `Narrow/Ops.cpp:216-230` roots `NarrowWord` per op of the generated list | *read* |
| §5.3 I1/I2: an `isa<A,B>` over ops is a trait; a per-pass table is a `TypeSwitch` with `DefaultUnreachable` | **holds in part.** `Nests.cpp:242-253` and `Ops.cpp:146-185` are already `TypeSwitch` tables (I2). Ladders remain at `Forms.cpp:109-110, 132`, `Narrow.cpp:107`, `Widths.cpp:46, 78` (section 4) | *read* |
| §5.3 I3, §5.5 D2, cxx-Q2: closed sums visited once, no `holds_alternative` validator | **one instance.** `layout::DescriptorField` (`Fixed` \| `Carried`, two alternatives) is visited once with `makeVisitor` (`Descriptors.cpp:84-87`) and asked with `holds_alternative` (`:34-36`), a validator whose answer is discarded at each of its three callers (`:101-104, 133-136`) | *read* |
| §5.3 I5: hot callbacks templates, cold ones `function_ref` | **holds.** `Linalg.cpp:51-52` (`Bind`, `Yield`) and `Nests.cpp:50` (`cellDim`) hand code its own static type through `function_ref`; `Bufferize.cpp:149` (`underOneShot`'s step) is cold and stays | *read* |
| §5.3 S0, §5.6 D6, §5.9 G2.7: the IR carries the answer, written into a type once | **holds for narrowing.** "Nothing it learns is stored: the rewritten IR is the fact" (`Narrow.cpp:9-10`); a narrowed web is `arith` on `i64`. The only side state is `Facts::madeBounds` for values the pass itself makes (`Narrow.h:86`), live for one function | *read* |
| §5.6 A5, D3: upstream's range analysis scoped to a function in production (CIRCT's `comb-int-range-narrowing`, IREE's `OptimizeIntArithmetic`) | **holds for lanes, not for words.** Words need ranges of naturals across calls (`Ranges.h:24`, "the interprocedural solve of the program"); per function they would need summaries of returned ranges (QA2) | *read* |
| §5.6 item 1 / Design 2: state only for values whose type leaves the question open | **refuted today.** `NaturalRanges` subclasses `IntegerRangeAnalysis` and solves every value of the program (`Ranges.cpp:25-76`), though `idr-narrow` asks only of bigs and naturals (`Facts.cpp:23`, `isBig`) and the integers that feed them | *read*; counts on the stage-1 module unmeasured (section 8) |
| §5.8 DS4 "`tabulate`, `tabulate_io` → one `array.tabulate` with `RecursiveMemoryEffects`" | **holds, conditional on DD-Q3.** `tabulate_io` differs only by the world it threads (`IdrArrayOps.td:119-135`); both already carry `RecursiveMemoryEffects` (`:55`). `Forms.cpp:166`'s `isa<TabulateIOOp>` restates `TabulateIOOp::getIterations` (all `Ordered`, `OpsTabulate.cpp:190-191`) except at rank 0, where no dimension can carry the world's order (I-SL9) | *read* |
| §5.8 DS4 "`fold_last`, `scan_last`, `transpose` → named forms of a category, lowering to linalg" | **holds in part.** Folds already lower to linalg where order allows (`Forms.cpp:174-186`, `Linalg.cpp:134-221`); a scan has no upstream structured form (0009 D16), so `fold_last` and `scan_last` stay two ops (they compute different results, O1); `transpose` is a tabulate of a permuted read, not a third op (C2) | *read* |
| §5.8 DS4 "`array.new`, `get`, `set`, `update`, `element.update` → value-semantics ops in the tensor style" | **refuted for the world arrays, holds for value arrays.** A value array's read and write are already upstream's `tensor.extract`/`tensor.insert` (`IdrArrayOps.td:10-12`; 0009 §2's table). `array.new/get/set/update` act on `IOArray`, `IORef`, `Buffer`: mutable memory that the program shares and orders by the world (`IdrArrayOps.td:230-250`), which is memory by meaning, not a value; `element.update` exists only after bufferization, on a value array's buffer (`:387-428`). The essential split is value (tensor) against memory (memref), which the dialect already draws | *read* |
| §5.8 O2: two ops that differ only in effect are one TableGen class | **holds for the updates.** `ArrayUpdateOp` and `ElementUpdateOp` share every line of C++ (`verifyUpdate`, `verifyUpdateEnd`, `updateSuccessors`, `updateSuccessorInputs`, `updateEffects`, `updateEdges`, `getRegionInvocationBounds`: `OpsArrays.cpp:148-232`); they differ by the world operand and the operand's memory space (`IdrArrayOps.td:362-428`) | *read* |
| §5.8 B7/T7: bufferization admits dialect types through `TensorLikeType`/`BufferLikeType` | **holds as the blocked path.** `!idr.lin<tensor>` is not tensor-like because a type interface belongs to `!idr.q`'s class (`Bufferize.cpp:29-34`; `upstream/27-one-shot-tensor-like-copy/README.md`, "Why there is no patch"); 0009 §16 stage 2 plans the per-instance `extraClassOf` | *read* |
| §5.9 F3: the one pass with state per object value is the one that blows up | **holds in our favour.** `Records` is keyed by `DataType` (`Columns.h:66-115`), not by value; its cost is per query (`splits` recomputed), not per value | *read* |
| §5.10 B7: Lean checks linearity at run time with a marker | **we check it at compile time.** A link is `mustBufferizeInPlace` (`Linear.cpp:67-69`); a copy there is an internal error, never a refusal (`Passes.td:406-410`; 0009 D33) | *read* |
| 0003 "Ranges discarded (`Narrow.cpp`) and re-solved over the whole program after versioning" | **holds.** `Narrow.cpp:158-165` invalidates `Ranges` and re-solves the program when any loop was versioned | *read* |
| 0003 "`Lanes.cpp` finds a size bound by search behind a run-time guard, maybe one `Ranges` proved" | **holds.** The program's solve is dropped at `idr-narrow`'s end; `idr-narrow-lanes` runs after lowering and re-derives bounds by trial (`Lanes.cpp:135-159`) | *read* |
| 0003 "resources read as effect bits by hand (`StructureLoops/Forms.cpp` `atMostCrashes`)" | **holds.** `Forms.cpp:46-63` compares `CrashResource::get()` and `IOResource::get()` and special-cases `MayCrashOpInterface` | *read* |
| 0003 "`narrow::Copy`'s hand resync (`copy.bound`)" | **holds.** `Copy::bound` mutates the copy's constants (`Copy.cpp:60-64`); after the search the copy holds the bound tried last and `largestFitting` resyncs it (`Lanes.cpp:156-157`) | *read* |
| 0003 the static lifetime: `ownership::isStatic` read by `Narrow/Facts.cpp` | **holds.** `Facts.cpp:42, 49` | *read* (lane 01/08 own the cutover) |
| §5.11 wave-2 item 6: an array's byte size checked for overflow | **holds, in two places.** `LowerAlloc` saturates the element count at `UINT64_MAX` with `llvm.umul.with.overflow` (`Arrays.cpp:61-79`); `idris_rt_array_new` refuses `count > (SIZE_MAX - sizeof(idris_rt_array)) / stride` (`runtime/Alloc/Arrays.cpp:98-101`). A world array has rank ≤ 1 (`IdrArrayOps.td:241`), so `LowerArrayNew`'s `countOf` multiplies at most one factor (`Arrays.cpp:125`). A natural extent past the small range is `idr.nat.to_extent`'s crash, "array too large" (`IdrArrayOps.td:434-448`, `OpsArrays.cpp:246`) | *read* |

### 3.2 Wave-2 questions of §5 that fall here, by ID

**§5.1 (mlir-analysis).**
- **W1** (V, B, P, F at each solve point). Unmeasured: no built compiler in this
  checkout. The subsystem's solve points are `idr-narrow` (whole program, once or twice)
  and `idr-narrow-lanes` (per vectorized loop, ≤ 6 trials). On the stage-1 module only the
  first matters, and at A4's 2.9 KB per state plus a 240 B `IntegerValueRangeLattice` and
  the baseline's lattices, it is the shape of the 52 GB wall of 16005000 (section 8, R1).
- **W2** (lattice, scope, summaries, design). `Ranges`: per value
  (`IntegerValueRange`), interprocedural, needs summaries of argument and returned ranges
  to go per function (Design 1); `Copy`: per value, one loop, already S2's shape.
- **W3** (per-query edge tables and quadratic helpers). Three in this subsystem:
  `Data.cpp:86-93` `yields(match)` walks every region of a match on each call, called per
  aliasing and buffer-type query (`:105, :125`) and, in `YieldModel::getAliasingValues`,
  once per yield operand (`:190`): O(N²) per match of N cases; `MatchModel` inherits the
  default `isRepetitiveRegion` (O(N) per query, C2); `Releases.cpp:111`
  `insideMutuallyExclusiveRegions` per pair. `Narrow/Carried.cpp:75-118` builds each
  joint's edges once per op (the right shape); `Versions.cpp:79-92` visits a merge's
  regions once per goal, goals deduplicated (`OnceWorklist`, `:46`).
- **W4** (`RecursiveMemoryEffects` ops and who queries them). The four generating ops
  (`IdrArrayOps.td:55`) and both updates (`:362, :401`). Queried by `Forms.cpp:49` (the
  fallback) and by upstream CSE/DCE. Their regions are one block of an element's code, not
  tens of thousands of cases: no wall.
- **W5** (attributes on a hot path). `Copy::analyse` loads the SCCP baseline per trial
  (`Copy.cpp:71`); `Ranges.cpp:74` once per solve. In rewrites only: `Ops.cpp:59`
  (`getI64IntegerAttr` per key of a narrowed `match_lit`), `Linalg.cpp:96-102`
  (`AffineMap`s per read).
- **W6** (function anchoring). Function-anchored: `idr-structure-loops`
  (`Passes.td:346`), `idr-narrow-words` (`:707`), `idr-narrow-lanes` (`:782`, on
  `func.func`). Program-anchored: `idr-columns` (`:310`), `idr-bufferize` (`:395`),
  `idr-narrow` (`:679`).
- **W7** (backward callee resolution in a scoped solve). None: both solves are forward;
  `Copy` is intraprocedural with one function (`Copy.cpp:70`).

**§5.2 (mlir-ods), for the array ops of `IdrArrayOps.td` (lane 03 owns them).**
- **W1** (hand `getEffects`). `ArrayUpdateOp::getEffects`, `ElementUpdateOp::getEffects`
  (`OpsArrays.cpp:185, 229`): static (row 2 of the recipe) plus recursive (row 4); both
  expressible in ODS together (A5).
- **W3** (hand `verify`). `TransposeOp::verify` (`OpsGenerating.cpp:106-122`: a
  permutation and matching extents), `ArrayNewOp`/`ArrayGetOp`/`ArraySetOp::verify`
  (`OpsArrays.cpp:124-140`: index count equals rank, element type matches: a
  `PredOpTrait` and a `TypesMatchWith` through `unrestricted`), the update verifiers
  (`:148-150, 211-213`), `TieShapeOp::verify` (`:276`), the generating ops' `hasVerifier`
  and `hasRegionVerifier` (`IdrArrayOps.td:64-65`). None looks up a symbol.
- **W4** (`isa<` over ops): the 12 in section 4 (I-SL*, I-NA*, I-BU*).

**§5.3 (llvm).** Worklists: four `OnceWorklist`s (`Releases.cpp:69`, `Versions.cpp:46`,
`Widths.cpp:102, 118`), each a deduplicating vector keyed by a `Value`, an `Operation *`
or a pair, local to one query or one loop; none is a schedule a graph algorithm would
replace. Per-node maps: none; every `DenseMap`/`DenseSet` is per solve or per query. The
`DataFlowSolver` files: `Narrow/Lanes.cpp`, `Narrow/Copy.cpp` (S2 already), and the
whole-program `Analysis/Ranges` they sit beside (lane 05). Switches on an enum of ours:
`StructureLoops.cpp:30` and `:63`, both over `Form`, in one file (I-SL1).

**§5.4 (modular).** Hand `getEffects` or `verify` because an attribute changes an op's
meaning: none; `Idr_Iteration` is not an attribute, it is derived from the op's kind
(`OpsTabulate.cpp:126-127, 190-191`, `OpsFolds.cpp:87-89, 174-176`).

**§5.5 (cxx26).** The one variant (`DescriptorField`) has two alternatives; the four
`function_ref`s are listed above; templates: `StoreModel<Store>` (one instantiation,
`Data.cpp:33`), `MatchModel<Match>` (two), `ResultColumns<OpT>`, `TerminatorColumns<OpT>`,
`FoldColumns<OpT>`, `LowerUpdate<OpT>`, `addressOf<OpT>`, `elementAt<OpT>`, `wordOf<OpT>`,
`narrowBig<OpT>`, `addNarrowWords<OpTs...>`, `widened<Extend>`, `tabulation<BodyFn>`;
none carries a concept.

**§5.6 (ecosystem).**
- **W-E2.** `Ranges` keeps a state for every value; the question is open only for values
  of type `!idr.big`/`!idr.nat` and the integers in their webs. Unmeasured.
- **W-E4.** No discardable attribute in the subsystem (2.2).
- **W-E5.** Budgets: `IntegerRangeAnalysis`'s 128-merge widening (precision only);
  `Lanes.cpp:81-82` (the search range 2^8 to 2^31, which states where a version pays, not a
  cap that fails: a loop outside it stays wide, `Lanes.cpp:182-183`); the greedy driver's
  default iteration budget in `Copy::narrow`, its result unread (`Copy.cpp:111-133`). None
  becomes a failure.
- **W-E6.** Queries on a match that enumerate its regions: W3's three.
- **W-E7.** `DenseMap<Value, …>` as solver state: `Facts::madeBounds` (`Narrow.h:86`),
  per function, holding only values the pass made.
- **W-E9.** No state copied per edge or per branch.

**§5.8 (dialect-design).** Ops with a flag that changes effects or valid states:
`tabulate` against `tabulate_io` and `array.update` against `element.update` (both the
world operand); `idr.array.yield` serves four kinds of parent (generating ops, updates,
`memo.run`) and its meaning (what its leading values move into) is read off the parent
(`IdrArrayOps.td:206-224`; `Data.cpp:291-296` relies on pipeline order for which parents
remain).

**§5.9 (mlton) Q-W4** (passes that read a match's region structure): `idr-bufferize`'s
`MatchModel`/`YieldModel` (`Data.cpp:86-222`) and `idr-narrow`'s joints and versions
(through `RegionBranchOpInterface`, `Carried.cpp:75-118`, `Versions.cpp:72-92`). Neither
needs nested regions: both would read a `case` terminator's successors as well.

**§5.10 (rc) W9.** Arrays after bufferization are freed by counting, deliberately: no
deallocation pass runs (`Bufferize.cpp:23-27`), a buffer is a runtime cell allocated by
`memref.alloc`'s lowering (`Arrays.cpp:54-85`), and counting frees it with every other
cell. Upstream's ownership-based deallocation could free them only as a second ownership
system beside counting, which the owner rejected (0009 §17). An array cell is counted
like a constructor's (`IdrArrayOps.td:247-250`).

**§5.11 (oom).** Item 6 answered in 3.1 (last row). Item 8: the subsystem creates no
attribute per value in an analysis; Columns creates one `RankedTensorType` per column
(`Records.cpp:24-30`), structure loops one `AffineMap` per read. Item 7 (state sized by a
product): `Data.cpp:190` (yields × yields per match) is the one product in the subsystem.

### 3.3 How much of the array stage is upstream already (*read*)

| piece | upstream mechanism today | carried patch | ours, and why |
| --- | --- | --- | --- |
| value arrays | builtin `tensor`, `tensor.extract/insert/extract_slice/insert_slice/expand_shape/collapse_shape/cast/empty/dim` (`Emit/Tensors.idr:296-420`) | — | the generating ops (`IdrArrayOps.td`): row-major observable order, several results, cells; `tensor.generate` rejected by 0009 §17 (no destination) |
| pure forms | `linalg.generic`, `linalg.transpose`, `linalg.index` (`Linalg.cpp`) | 56 (CSE of nested `linalg.index`, `DependsOnParent`), 57 (`linalg.index` ranges, which `idr-narrow` needs on loop bodies) | the decision (`formOf`, D10/D15) |
| ordered forms | `scf.for`, `affine.delinearize_index` (`Nests.cpp`) | 58 kept as a submission (no longer reached) | the nest builder (C3 replaces it with `TilingInterface` + `lowerToLoopsUsingSCFForOp`) |
| bufferization | One-Shot module driver, its function-boundary models on `idr.func/call/return`, empty-tensor elimination (`Bufferize.cpp:267-311`) | 24 (FunctionOpInterface, no-return functions, cycles, non-writable results, nearest symbol table) | models for `con`, `field`, `match`, `match_lit`, `yield`, `memo.run`, `array.yield`, `lin.enter`, `lin.use`, `tie_shape`, `ub.poison`; the retype; the element move. 27 is a submission (nothing reaches it until C5) |
| columns | 1:N dialect conversion, SCF structural conversions (`Columns.cpp:36, 57`) | — (I-CO6 adds one) | which records split; the gather/scatter materializations; call and terminator patterns |
| word narrowing | `IntegerRangeAnalysis` subclassed, interprocedural (`Ranges.cpp:25-76`); walk driver | — | versioning descending loops, the joints, the big→word rewrite (`BigToWord` generated from ODS) |
| lane narrowing | `IntegerRangeAnalysis` intraprocedural, `arith-int-range-narrowing` patterns, value bounds (`Copy.cpp`, `Widths.cpp:153-165`) | 09 (remainders narrowed exactly; before it, `idr-narrow-lanes` kept a second copy of the narrowing's own decision) | the scratch copy, the bound search, the versioning |
| lowering | memref-to-LLVM for words, views, contiguous copies; `getStridedElementPtr`, `MemRefDescriptor` (`Arrays.cpp`, `Descriptors.cpp`) | — | cells, counted elements, the runtime copy, the two runtime forms of a memref |

## 4. Issues

Every claim *read* at the cited line unless marked. "Lane NN" names the owner where the
fix is outside this lane's files. Paths are under `foreign/idr/` unless they start with
`libs/`.

### 4.1 Structure loops (`lib/Transforms/StructureLoops/`, `StructureLoops.h`)

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| I-SL1 | `StructureLoops.cpp:29-41`, `:62-73` | list | Two `switch`es over `Form` in one file (lowering and statistic), plus a third dispatch on the same op set in `lowerOrdered` (`Nests.cpp:242`) | One `constexpr` table indexed by `Form` (§5.5 D4b) holding the lowering and the statistic, or the forms deleted into the ops' interfaces (C1, C3) |
| I-SL2 | `Forms.cpp:31` vs `Conversion/Descriptors.cpp:59` | rederivation | Two definitions of "a word element": `isIntOrIndexOrFloat` here, `isa<IntegerType, FloatType>` (no `index`) for the lowering; they disagree on `index`, and decide "reaches linalg" against "left to upstream" | One classification, declared once (upstream's `VectorType::isValidElementType`, or a type interface lane 01 declares); both readers call it |
| I-SL3 | `Forms.cpp:46-63` | ladder, rederivation | `atMostCrashes` reads effect instances by hand: compares `CrashResource::get()` and `IOResource::get()`, special-cases `MayCrashOpInterface` (a crash also writes IO); 0003 names it | Read effects through the one classifier (`idr::classify`, lane 02); with `Crash` placed in the resource tree (ods-Q3), "only crashes" is `isa<CrashResource>` of every non-allocating effect |
| I-SL4 | `Forms.cpp:49`, `:67-76` | upstream | The `HasRecursiveMemoryEffects` fallback and `computes`' walk re-implement upstream's recursive effect collection | `mlir::getEffectsRecursively` on the generating op, which is `RecursiveMemoryEffects` (`IdrArrayOps.td:55`), then I-SL3's test |
| I-SL5 | `Forms.cpp:69` | ladder | "The region returns" asked as `isa<ArrayYieldOp>(terminator)` | `hasTrait<OpTrait::ReturnLike>()` or `RegionBranchTerminatorOpInterface`; the other end is `ub.unreachable` |
| I-SL6 | `Forms.cpp:82-97` | essential (kept) | `overWords`: no array of non-word elements reaches linalg, `tensor::DimOp` excepted | Essential while counting runs between bufferization and `convert-linalg-to-loops` and reads no linalg body (0009 §5, "nothing in one counts"). Keep; read the word test from I-SL2's one place |
| I-SL7 | `Forms.cpp:104-119` | upstream, ladder | `reassociates`: a nine-op `isa<AddIOp, MulIOp, AndIOp, OrIOp, XOrIOp, MinSIOp, MinUIOp, MaxSIOp, MaxUIOp>` and a hand match of the combiner chain | Upstream's `matchReduction` (`mlir/Analysis/SliceAnalysis.h:264`) for the chain and `linalg::getCombinerOpKind` (`mlir/Dialect/Linalg/Transforms/Transforms.h:46`, `Vectorization.cpp:625-649`, the same nine plus float kinds) filtered to integer kinds, plus the overflow-flag test this rule adds (0009 D15 case 1) |
| I-SL8 | `Passes.td:362-364` | list | The nine combiner ops restated in the pass's prose | Delete the list from the prose; the code (I-SL7) is the one statement |
| I-SL9 | `Forms.cpp:131-133` | ladder | `structurable`: `isa<TabulateOp, TabulateIOOp, FoldLastOp, ScanLastOp, TransposeOp>`, four of which are `GeneratingOpInterface`; read again by `Expect/StructuredLoops.cpp:27` | `isa<GeneratingOpInterface>(op)` once `idr.transpose` is a tabulate (C2); Expect reads the IR the pass leaves (no generating op remains), not the pass's predicate (lane 19) |
| I-SL10 | `Forms.cpp:163-164` | ladder | `formOf` special-cases `TransposeOp` | Goes with C2 |
| I-SL11 | `Forms.cpp:166-167` | ladder (coordinate) | `isa<TabulateIOOp>` restates `TabulateIOOp::getIterations` (all `Ordered`, `OpsTabulate.cpp:190-191`) except at rank 0, where `frame == iterations.size()` would wrongly pick `Parallel`: the world's order lives on no dimension | Under DS2.1 (DD-Q3) the region's IO effects decide (`computes` fails) and the case goes; under DS2.2 the order is the op's (an interface answer "orders its steps"), not a cast |
| I-SL12 | `Forms.cpp:178` | essential (kept) | Only `FoldLastOp` may be a reduction | Essential (a scan keeps every step); expressed through the op's interface (0009 owed: `PartialReductionOpInterface`), not a `dyn_cast` |
| I-SL13 | `Linalg.cpp:26-30, 32-45` | state, cpp | `Inputs`: three vectors (`arrays`, `maps`, `of`) matched by position | One vector of `{Value array; AffineMap map;}` and, per read, its index (the skill's "three lists matched by position") |
| I-SL14 | `Linalg.cpp:51-52, 58-83` | cpp | `Bind` and `Yield` `function_ref`s threaded through `genericOf`, whose three callers know their static types | Data, not callbacks: each form passes the region's argument list and the yield's extension; or template parameters (I5) |
| I-SL15 | `Linalg.cpp:79-81` | upstream, dead | Erasing unused `linalg.index` by hand | Delete: `linalg.index` is pure; the canonicalize after `idr-bufferize` (`Pipeline.cpp:116`) erases it |
| I-SL16 | `Linalg.cpp:109-117`, `:118` | ladder | `lowerParallel` branches on `TransposeOp`, else `cast<TabulateOp>` | Goes with C2 (one op); `linalg.transpose` is recovered by `linalg-specialize-generic-ops` (0009 stage 3) |
| I-SL17 | `Linalg.cpp:158`, `Nests.cpp:160` | ladder (variant) | `isa<ScanLastOp>` re-decided inside shared fold code: a fold/scan flag | The kind chosen once at the dispatch: `lowerInterchange<OpT>`/`folded<OpT>` templated on the op class (compile-time `if constexpr`), or both forms deleted into the op's own loop generation (C3) |
| I-SL18 | `Linalg.cpp:139-141, 200`; `IdrArrayOps.td:38-42` | list | `Idr_Iteration` (`Parallel`, `Ordered`) and `utils::IteratorType` (`parallel`, `reduction`): two enums of one concept, translated by hand | 0009 owed: `Idr_Iteration` spelled as upstream's `IteratorType`, only `Ordered` ours (lane 03) |
| I-SL19 | `Lowering.cpp:33-50`, `Columns/Tensors.cpp:32-45`, `Linalg.cpp:178-185` | list | Three copies of "offsets, sizes, strides" (`Slice`, `Mixed`, a lambda) | Upstream's `mlir::Range` (`mlir/Dialect/Utils/StaticValueUtils.h:42`) and the mixed-value helpers; one builder of "a cell's slice" |
| I-SL20 | `Lowering.cpp:80-83` | upstream | `valuesOf` re-implements `getValueOrCreateConstantIndexOp(b, loc, ArrayRef<OpFoldResult>)` (`mlir/Dialect/Arith/Utils/Utils.h:70-72`) | Delete; call upstream's overload |
| I-SL21 | `Lowering.cpp:85-91` | upstream | `emptyOf` re-implements `tensor.empty`'s builder from mixed sizes (`TensorOps.td:315`), which `Releases.cpp:59` already uses | Delete; one builder |
| I-SL22 | `Lowering.cpp:24-31` | essential (kept) | A region ends in a yield or in `ub.unreachable` (poison stands for no value) | Essential: two ends of a region |
| I-SL23 | `Nests.cpp:38-153` (`state`), `:243-250` | ladder (flag in data) | The world threaded as an optional `state` range (empty or one value) through the shared tabulation | Goes under DS2.1 (DD-Q3); under DS2.2 stays, and is the op's |
| I-SL24 | `Nests.cpp:50` | cpp | `function_ref<OpFoldResult(unsigned)> cellDim` for a lambda of known type | Template parameter (I5) |
| I-SL25 | `Nests.cpp:175` | cpp (validation discarded) | `(void)reifyResultShapes(...)`: a failure leaves `shapes` empty and `zip_equal` asserts at `:177` | Return the failure as an internal error, or make the scan's shape a builder that cannot fail |
| I-SL26 | `Nests.cpp:217-236` | dead (after C2) | `transposed`, the ordered transpose | Becomes the ordered tabulation of a permuted read |
| I-SL27 | `Nests.cpp:240-254` | upstream | The ordered form is ours: a `TypeSwitch` over the generating set building `scf.for` nests, the third dispatch over one op set in the pass | 0009 owed: each generating op implements `TilingInterface` (`generateScalarImplementation`), the ordered form is upstream's `lowerToLoopsUsingSCFForOp` after bufferization, and `Nests.cpp` goes (C3) |
| I-SL28 | `StructureLoops.h:57-63` | rederivation | `structurable` and `formOf` exported so that Expect decides again what the pass decided | Expect reads the output IR (linalg against scf, no generating op left), lane 19 |
| I-SL29 | `IdrArrayOps.td:54-80`, `IdrInterfaces.td:204-225` | upstream | `GeneratingOpInterface` (rank, iterations, indices, extent, extent bound, held arrays) where upstream has `TilingInterface` (`getIterationDomain`, `getLoopIteratorTypes`) and `DestinationStyleOpInterface` | 0009 owed: generating ops destination-style and tileable; `GeneratingOpInterface` deleted (lane 03) |

### 4.2 Bufferization (`lib/Transforms/Bufferize/`, `Bufferize.h`, `BufferizeModels.h`)

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| I-BU1 | `Bufferize.cpp:85-89`, `BufferizeModels.h:31-34` | dead (after stage 2) | `heldType` exists for the retype | Deleted by 0009 §16 stage 2 |
| I-BU2 | `Bufferize.cpp:115-118`; reader `Expect/InPlace.cpp:31` | rederivation | `copies` re-derives One-Shot's out-of-place decision from the rewritten IR (a `memref.copy` into a `memref.alloc`) | The property reads One-Shot's own record of the decision (the analysis state's `isInPlace`, or the `bufferization.alloc_tensor … copy(…)` that `insertTensorCopies` leaves before the rewrite), lane 19 |
| I-BU3 | `Bufferize.cpp:174-183, 191-209` | state (cost) | `readBefore` walks back from each store, and `takesBuffer` walks each prior op's nested ops: stores × block × nesting | Goes with I-BU4 |
| I-BU4 | `Bufferize.cpp:216-253`; `OpsArrays.cpp:144-146` | rederivation (two copies) | `moveElementsOut` is a second implementation of "a read then a write of one element is its update": Canon's MoveOut does it for `array.set` (`canon::addMoveOutPatterns`), this does it for `memref.store` after bufferization | One rewrite, rooted at the write, building the `UpdateOpInterface` op (lane 04 owns MoveOut); or, under 0009 owed ("one counting protocol per element access"), counting owns element moves (lane 08) |
| I-BU5 | `Bufferize.cpp:236-239`; `IdrArrayOps.td:287, 314, 335, 367, 410` | state (coordinate) | Indices cast `index` → `i64` because `element.update` takes `I64` indices "as an array a world orders does"; upstream's memref coordinate is `index` | One coordinate: `index` for every access and update, the `Int` → `index` cast where Idris gives an `Int` (lanes 03, 12) |
| I-BU6 | `Bufferize.cpp:292-311` | upstream (kept) | One-Shot module analysis, whole program, serial (with patch 24, cycles to a fixpoint) | Keep: the boundary analysis is interprocedural by design; measure on stage 1 (0009 §7 SELF-HOST) |
| I-BU7 | `Bufferize.cpp:319-330` | rederivation | `DataRemap` "buffers": every data type and function holding a tensor remade after One-Shot (0009 D42) | 0009 §16 stage 2: bodies hold buffers from the frontend on; `idr.con`/`idr.field` are the `to_buffer`/`to_tensor restrict` boundary; the remap goes (C5) |
| I-BU8 | `Data.cpp:33-57` | dead (after stage 2) | `StoreModel<ConOp>`: a con's tensor field stored as its cell buffer | Replaced by `bufferization.to_buffer`'s own model (C5) |
| I-BU9 | `Data.cpp:60-81` | dead (after stage 2) | `HeapReadModel` on `idr.field` | Replaced by `bufferization.to_tensor restrict` (C5) |
| I-BU10 | `Data.cpp:86-93`, uses `:105, :125` | state (per-query edge table) | `yields(match)` walks every region of a match on each aliasing and buffer-type query | Built once per match per analysis in a `OneShotAnalysisState` extension (upstream's `AnalysisState::addExtension`), or answered by the op from its shape |
| I-BU11 | `Data.cpp:186-191` | state (quadratic) | `YieldModel::getAliasingValues` calls `yields(match).size()` per yield operand: O(N²) per match of N cases | As I-BU10: "exactly one case yields" computed once per match |
| I-BU12 | `Data.cpp:98-175` | upstream, state | `MatchModel` does not override `isRepetitiveRegion`, so every query walks the match's region graph (§5.1 C2), and the pin's block cache never fills | Override: a match's regions never repeat (O(1)); and patch U3 upstream (§5.1) |
| I-BU13 | `Data.cpp:98-175` and `:227-289` | list | `MatchModel` and `MemoRunModel` are two copies of one model: clone without regions, retype results from the yields' buffer types, inline regions, bufferize block signatures | One model template over `RegionBranchOpInterface` ops whose results are their terminators' forwarded operands, attached to `match`, `match_lit`, `memo.run` |
| I-BU14 | `Data.cpp:291-297`, `Conversion/Arrays.cpp:277-279` | ods | `MemoYieldModel` is attached to every `idr.array.yield` and is right only because structure loops has removed the generating ops by then; the lowering's yield pattern says the same | One terminator per kind of parent (generating op, update, memo force), so each model and pattern is attached to the op it is for (lane 03) |
| I-BU15 | `Linear.cpp:32-50`, `:67-69` | rederivation | `isLink` recomputed on every `mustBufferizeInPlace` query: an `AnalysisState`, a reverse use-def traversal, the `sharers` closure, `mayRunAfter` per use; though it "reads only aliasing and positions, which the models answer before the analysis decides anything" (`BufferizeModels.h:60-66`) | A fact of the program before analysis: computed once in `prepare` and held in an analysis-state extension; or a link is its own op (new owner question N2) |
| I-BU16 | `Linear.cpp:54-108` | dead or changed (after stage 2) | `EnterModel`, `UseModel` exist because `!idr.lin<tensor>` is no tensor to One-Shot | 0009 §16: with `!idr.lin<T>` tensor-like per instance, One-Shot bufferizes the wrapper; the link check stays as the in-place promise's (D33) |
| I-BU17 | `Releases.cpp:67-80` | rederivation | `sharers` closes the aliasing relation per release (`:152`) and per `isLink` query (`Linear.cpp:44`) | One partition of the program's tensor values into alias classes (`llvm::EquivalenceClasses`), built once in `prepare` |
| I-BU18 | `Releases.cpp:82-117`, `:111` | upstream (cost) | `mayRunAfter` calls `insideMutuallyExclusiveRegions` per pair, O(N·depth) on a match | Patch U3 (§5.1); our match answers mutual exclusion from its shape |
| I-BU19 | `Releases.cpp:119-126` | rederivation (minor) | Every call operand is a release whatever the callee's analyzed boundary says | Keep until patch 24's boundary facts are readable by a model; then read them (*conjecture* that they suffice) |
| I-BU20 | `Releases.cpp:131-141` | rederivation (phase repair) | `prepare` clones every `tensor.empty` per use, undoing the sharing CSE made (`Pipeline.cpp:93-94`) | Measure the upstream order instead: `eliminate-empty-tensors`, then `empty-tensor-to-alloc-tensor` (`Bufferization/Transforms/Passes.td:375`), whose `alloc_tensor` declares no memory effects and so is never merged (*conjecture*: it keeps empty-tensor elimination's wins) |
| I-BU21 | `Values.cpp:53-76` | upstream (gap) | `PoisonModel`: upstream gives `ub.poison` no bufferization model (*measured*: no match in `lib/Dialect/{Bufferization,UB}`) | A new `upstream/<bug>/` report and patch (the model upstream, beside `ub.poison`), then ours goes |
| I-BU22 | `Values.cpp:19-47` | kept | `TieShapeModel` | Keep: `idr.tie_shape` is a gap 0009 §19 names |

### 4.3 Columns (`lib/Transforms/Columns/`, `Columns.h`)

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| I-CO1 | `Records.cpp:49-66` | rederivation | `Records` walks every op's result types and every block argument of the program to find its data types | Read the program's table (`TypeGraph::declarations()`, `IR/TypeGraph.h:56`), a cached analysis |
| I-CO2 | `Records.cpp:76-96`; `Columns.h:58-61` | rederivation | `splits` recomputed (recursively through fields) on every `recordOf` query, though the header says "The program decides it once" | Decided once in the constructor into `DenseMap<DataType, Record>`; queries are lookups |
| I-CO3 | `Records.cpp:82-88` | ladder (types), essential cases | A field splits unless graded, linear by type, a world memref, a dynamic-shape tensor, or another shaped type | The cases are the problem's (a linear field is used once; a dynamic array is not one column); hold the classification in one place, lane 01's type facts (`ValueFacts`) |
| I-CO4 | `Columns.h:129-132`, `Tensors.cpp:209, 223`, `ArrayOps.cpp:50, 81, 121` | cpp | `recordsOf` recovers `Records` from a `TypeConverter &` by `static_cast` | Patterns take `const Records &` in their constructor |
| I-CO5 | `Tensors.cpp:256-264` | list | A hand table of seven op names that act per column (`tensor.empty`, `tensor.cast`, `idr.tie_shape`, `idr.lin.enter`, `idr.lin.use`, `arith.select`, `ub.poison`) | Ours declare it (a trait or interface "acts on an array as on each column", lane 03); the four upstream ops stay a named list (an external interface model at most): the set of upstream ops is closed to us |
| I-CO6 | `Calls.cpp:30-57` | upstream (patched) | `FuncColumns` re-implements a 1:N signature conversion of a `FunctionOpInterface` op, expanding `arg_attrs`/`res_attrs` per value (`expand`, `:17-24`) | `populateAnyFunctionOpInterfaceTypeConversionPattern` (`DialectConversion.h:824`), patched upstream first: its `convertFuncOpTypes` sets the new type and leaves the argument and result attribute arrays at their old length (*read*, pin `lib/Transforms/Utils/DialectConversion.cpp:3858-3903`), which a 1:N conversion makes inconsistent with the type; a new `upstream/<bug>/` with report and test |
| I-CO7 | `Calls.cpp:59-81` | upstream (gap) | `CallColumns`: upstream's call conversion is `func.call`-only (`Func/Transforms/FuncConversions.h:32`) | Keep, or a `CallOpInterface` version upstream |
| I-CO8 | `Calls.cpp:85-94, 112-115`; `ArrayOps.cpp:110-113` | ladder | `TerminatorColumns` for `ReturnOp` and `YieldOp`, `ResultColumns` for `MatchOp`, `MatchLitOp`, `TabulateOp`, `TabulateIOOp`, `FoldColumns` for `FoldLastOp` and `ScanLastOp`: one instantiation per op | Interface-rooted patterns (§5.2 E1): `ReturnLike`/`RegionBranchTerminatorOpInterface`, `RegionBranchOpInterface`, `LastAxisFoldOpInterface` |
| I-CO9 | `Tensors.cpp:32-45` | list | `Mixed`: the second copy of a slice's parameters | I-SL19 |
| I-CO10 | `ArrayOps.cpp:16-34` | dead (after C2) | `TransposeColumns` | Goes with `idr.transpose` (a tabulate is converted by `ResultColumns`) |
| I-CO11 | `ArrayOps.cpp:114-123` | ods | A yield's conversion decided by asking whether its parent is a generating op | I-BU14 (one terminator per parent kind) |
| I-CO12 | `Tensors.cpp:251-255` | essential (kept) | A select whose condition is shaped is per element, not a choice of arrays | Keep |

### 4.4 Narrowing (`lib/Transforms/Narrow/`, `Narrow.h`)

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| I-NA1 | `Narrow.cpp:143-165`; `Analysis/Ranges.cpp:67-76` | rederivation, state | One whole-program interprocedural range solve, a state per value of the program; invalidated and re-solved whole when any loop was versioned (0003) | QA2's choice (§6): per-function solves on upstream's framework with a summary per function (argument and returned ranges), solved over the call graph's SCCs; a version re-solves only its function. The analysis itself is lane 05's |
| I-NA2 | `Narrow.cpp:106-109`; `Facts.cpp:92-99` | ladder | The conversions between words and bigs listed by hand twice: `isa<BigSmallOp, BigFromSIntOp, BigFromUIntOp>` plus a big `ConstantOp`, and `word`'s `getDefiningOp` chain over the same three | One declaration: a trait (or the generated `BigToWord` table's inverse) on those ops, read by both (lanes 03, 14) |
| I-NA3 | `Narrow.cpp:111-112`, `Facts.cpp:89-91`, `Versions.cpp:61-64` | rederivation | Three hand walks up `ResultCarriesOperand` chains | One named step (0003's `definitionChain` in `Grades.h`) |
| I-NA4 | `Facts.cpp:23` | ladder (types) | `isBig` = `isa<BigType, NatType>` | One type fact (lane 01): bigs and naturals as one family, or the natural's lower bound as the type's range (S0) |
| I-NA5 | `Facts.cpp:41-50` | rederivation | `owned`/`borrowed` call `ownership::isStatic`, a definition-chain search (0003) | 0003's static lifetime in `Idr_Lifetime` (lanes 01, 08); the calls read the grade |
| I-NA6 | `Narrow.h:85-87`, `Facts.cpp:107-112` | state (kept) | `madeBounds` (`DenseMap<Value, Bounds>`) and `conversions` for values the pass makes, per function | Keep: the solve is not re-run inside a function, so the made values' bounds have no other holder; freed with the function |
| I-NA7 | `Versions.cpp:83-88` | ladder (coordinate) | "A region that ends the program" detected as a terminator whose operand count differs from the merge's result count | Ask the terminator: `RegionBranchTerminatorOpInterface` (or `ReturnLike`) against `ub.unreachable` |
| I-NA8 | `Ops.cpp:147, 162, 177` and `:226` | list | `MatchLitOp`, `CheckNonzeroOp`, `DupOp`, `DropOp` listed twice in one file: as `TypeSwitch` cases and as `addNarrowWords` roots | One type list expanded into both (pack expansion, §5.5 D4d) |
| I-NA9 | `Ops.cpp:84-116` | cpp, list | `wordOf`'s `if constexpr` chain on the word op (`CmpIOp`, `TruncIOp`, `MaxSIOp`, none, constant) | The per-op facts (a predicate map, a constant) as fields of the generated `BigToWord` record (lane 14's backend) |
| I-NA10 | `Carried.cpp:90-99` | cpp, state | `EquivalenceClasses<void *>` over opaque pointers mixing `Value` and `OpOperand *` | A dense numbering of the joint's edges with `IntEqClasses`, or `PointerUnion` keys (§5.3 I4) |
| I-NA11 | `Widths.cpp:37-53` | ladder | `isVectorized`: a dialect test (`isa_and_nonnull<vector::VectorDialect>`) and `isa<scf::ForOp, scf::YieldOp>` | Kept as the one predicate its three readers share (`Lanes.cpp:114`, `Expect/NarrowedLanes.cpp`); the dialect test is its definition |
| I-NA12 | `Widths.cpp:77-86` | kept | `laneWidth` excludes casts and selects (they move lanes) | Keep; `CastOpInterface` is upstream's |
| I-NA13 | `Widths.cpp:94-135`, `:140`, `Copy.cpp:93`, `Expect/NarrowedLanes.cpp:27` | rederivation (minor) | `accumulations` computed for the loop, again for its copy, again by the property | Computed once per loop and passed to the copy; the property reads the result IR (lane 19) |
| I-NA14 | `Lanes.cpp:81-83, 135-159` | budget (never fails) | A search over 2^8 to 2^31, at most 6 solves per loop; a loop outside the range stays wide | Keep: a range where a version pays, not a cap that refuses; its cost is a seedable re-derivation (I-NA16) |
| I-NA15 | `Copy.cpp:60-64`; `Lanes.cpp:156-157` | state | `Copy::bound` mutates the copy's constants; after the search the copy holds the last bound tried and is resynced by hand (0003) | Each trial an immutable value (`{exponent, solver}`) that `analyse` returns, and `narrow(trial)` sets the copy's bound from it: the bound and the solve it was narrowed under cannot disagree |
| I-NA16 | `Lanes.cpp:135-159`; `Narrow.cpp:167-176` | rederivation | The program's ranges, proved before lowering, are dropped; the lanes pass re-derives size bounds by trial (0003) | Keep what the program proved where a later pass reads it: a bound on an extent becomes IR the frontend's `tie_shape`/value bounds already carry, or the lanes trial starts from the extents' proved ranges (*conjecture*: how many trials it saves is unmeasured) |
| I-NA17 | `Copy.cpp:117-125` | kept (upstream idiom) | A listener erasing solver states for erased ops | Keep (IREE's form, §5.6 D3) |

### 4.5 The array lowering (`lib/Conversion/{Arrays,Elements,Memrefs,Descriptors,Buffers}.cpp`)

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| I-CV1 | `Arrays.cpp:115-151`, `:198-210`, `:213-224` | rederivation | Counting in the lowering: `array.new` increments per element and drops the fill, `array.get` increments, `array.set` decrements the old element, beside `idr-rc` | 0009 owed: one counting protocol per element access; `idr-rc` lowers `array.get` to `memref.load` + `idr.dup` and `array.set` to `idr.own.give` + `memref.store`; the lowering stops counting (lanes 08, 12) |
| I-CV2 | `Arrays.cpp:233-275` | ods (two ops) | `LowerUpdate<ArrayUpdateOp>`, `LowerUpdate<ElementUpdateOp>`: one template for two ops that are one (O2) | One update op (C4); the template's parameter goes |
| I-CV3 | `Arrays.cpp:277-290` | ods | "No other op of the generating set reaches the lowering": a precondition held by pipeline position | I-BU14 |
| I-CV4 | `Arrays.cpp:153-175` | essential (kept) | `addressedAs`: an element that is itself an array is held as components, a function's array as a descriptor, "two runtime forms of one type" | Essential while a memref has two runtime forms (I-CV7) |
| I-CV5 | `Elements.cpp:33-83` | cpp (switch in four places) | `element.boxed` tested in `readElement`, `placeElement`, `writeElement`, `takeElement`: one tag switched on in four functions | `layout::Element` as a sum (`InPlace` \| `Boxed`) whose four operations are one exhaustive `match` each, or two policy types (lane 01/12 own `Layout.h`) |
| I-CV6 | `Descriptors.cpp:34-36`, `:101-104`, `:133-136` | cpp (validator) | `carries` asks `holds_alternative<Carried>` and throws the answer away at three callers; `unpack` visits the same sum once (`:84-87`) | `DescriptorFields` gives the carried fields once (an index list), or every reader is one `match` (cxx-Q2) |
| I-CV7 | `Descriptors.cpp:80-144, 170-214`; `Arrays.h:3-13` | essential (kept), upstream gap | A memref's two runtime forms (components at boundaries and in cells, descriptor inside) and materializations both ways | Keep: upstream's bare-pointer convention covers static shapes only; state the gap in the header |
| I-CV8 | `Descriptors.cpp:59` | rederivation | `holdsWords` | I-SL2 |
| I-CV9 | `Descriptors.cpp:176` | ladder (dialect) | "An element of ours" asked as `isa<IdrDialect>(type.getDialect())` | `MemRefElementTypeInterface`, which our element types implement (0009 §4.5) |
| I-CV10 | `Descriptors.cpp:222-226` | per-target (*conjecture*) | `sizeof(idris_rt_array)` is the host compiler's layout of the runtime header, not the target data layout's | The header's size as a fact of the target's entry, or a `static_assert` per target entry; equal on the four LP64 targets today (lanes 12, 13, 18) |
| I-CV11 | `Memrefs.cpp:38-42` | rederivation (minor) | `contiguous` restates upstream's condition for lowering `memref.copy` to a memcpy | Keep, cite upstream's rule; or call it if upstream exposes it |
| I-CV12 | `Descriptors.cpp:67-71`, `Arrays.h:93-94` | dead | `asIndex` is declared and defined, never called (*measured*: `grep -rn asIndex lib include`, two hits, both its own) | Delete |

### 4.6 The op definitions (`IdrArrayOps.td`, read; lane 03 owns)

| ID | file:line | category | what | disposition (for lane 03) |
| --- | --- | --- | --- | --- |
| I-TD1 | `:99-135` | ods (flag) | `tabulate` and `tabulate_io` differ by a world operand, region argument and result | One op under DS2.1 (DD-Q3); one TableGen class otherwise (O2) |
| I-TD2 | `:143-187` | list | `fold_last` and `scan_last` repeat four `extraClassDeclaration` bodies verbatim | One TableGen base class; two ops kept (different results, O1) |
| I-TD3 | `:189-204` | ods | `idr.transpose`: a tabulate of a permuted read, with its own verifier, folder, flow, reify, value bounds | Deleted (C2); the folder's identity and inverse cases become tabulate canonicalizations |
| I-TD4 | `:362-428`; `OpsArrays.cpp:148-232` | ods (two ops) | `array.update` and `element.update` share every line of C++, differ by world and memory space; hand `getEffects` on both | One op (or one class) with `Arg<…, [MemRead, MemWrite]>` beside `RecursiveMemoryEffects` (§5.2 A5) |
| I-TD5 | `:64-65, 202, 292, 320, 340, 373-374, 416-417, 475`; `OpsArrays.cpp:124-140`; `OpsGenerating.cpp:106-122` | ods | Hand verifiers for counts and element types | `PredOpTrait` for "one index per dimension" and `TypesMatchWith` through `unrestricted` for the element (recipe rows 7, 9) |
| I-TD6 | `:206-224` | ods | `idr.array.yield` ends four kinds of region; its meaning is its parent's | One terminator per parent kind (I-BU14) |
| I-TD7 | `:287, 314, 335, 367, 410` | ods (coordinate) | `I64` indices on the world ops and on `element.update` | `index` (I-BU5) |

### 4.7 The libraries (`libs/mlir-array`, `libs/mlir-linear`)

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| I-LI1 | `libs/mlir-array/Array.idr:47-62` | idris | `(!?) : Array s a -> SnocList Integer -> Maybe a`: a coordinate list of another rank is one of the `Nothing`s | Index the coordinates by the shape, as `Index` is: `data Coords : Shape -> Type where Lin : Coords [<]; (:<) : Coords s -> Integer -> Coords (s :< n)` (n erased): the rank mismatch is unrepresentable, the `Nothing` is only "outside its extent" |
| I-LI2 | `libs/mlir-array/Array/Core.idr:121-248`, header `:12-16` | idris (meaning) | 21 bodiless `%extern`s whose one meaning is the dialect's ops (their ODS descriptions and lowerings), while AGENTS.md says "A primitive of `libs/` (an `%extern`) means only what `runtime/` says" | New owner question N3 (section 6): which document holds the generating set's one meaning |
| I-LI3 | `libs/mlir-array/Array/Core.idr:166`; `IdrArrayOps.td:197` | list (two forms) | The library's `transpose` swaps the last two axes; the op takes any permutation; the frontend computes the permutation (`compiler/src/IdrisMLIR/Types.idr:291`, `Emit/Tensors.idr:64-73`) | With C2 the frontend emits a tabulate reading at the swapped indices; the permutation attribute goes |
| I-LI4 | `libs/mlir-array/Linear/Vec.idr:117-123` | idris (kept) | `reserve` tests `k <= minus c n` as a `Bool`; neither branch needs its evidence | Keep: the branch carries no proof obligation |
| I-LI5 | `libs/mlir-linear/Linear/String/Iterator.idr:60-64, 86-91` | idris, essential | The iterator's offset invariant (at a character boundary, at most the byte length) is prose; `uncons` tests it with a `Bool` | Essential at this boundary: it rests on runtime primitives (`prim__scalarAt`, `stringByteLength`) that do not reduce on variables, so no Idris proof can be built; `foldl` and `unpack` already carry their measure (`Accessible LT left`, `:96-131`) |

Right as they are (checked, no issue): `Extents s` as the shape's singleton, `Index s` with a
`Fin` per axis (`Core.idr:43-56`), `Cell` with erased lengths (`:58-64`), `along`'s
structural recursion with an erased sum (`Array.idr:105-118`), `withArray`'s closed world
of construction (`Core.idr:199-207`, rc G2), `Vec`'s capacity held once in the array's
extent (`Vec.idr:6-8, 59`), `push`'s `So` beside its lemma (`:96-102`), `pop` on `Vec (S n)`
(`:108`); in C++, the generated `BigToWord` dispatch (`Ops.cpp:146-157, 216-230`), the
joints' edge table per op (`Carried.cpp:75-118`), the walk driver for one-shot rewrites
(`Narrow.cpp:90, 95`), the nested pass reading its parent's cached analysis
(`Narrow.cpp:72-78`), upstream's 1:N conversion (`Columns.cpp:57`).

## 5. Target design

The array stage is already the part of the compiler closest to upstream: value arrays are
builtin tensors, their reads and writes `tensor.extract`/`tensor.insert`, the pure forms
`linalg.generic`, bufferization One-Shot's module driver, columns upstream's 1:N
conversion, lane narrowing upstream's range analysis and narrowing patterns. What remains
ours is either a gap 0009 §19 names (`idr.tie_shape`, the structuring, the scan), or one of
the re-derivations and ladders of section 4. The target applies P0 to it, inside the
owner's decisions in 0009 (D15, D16, D17, D33, D44, §17's rejections), and takes 0009's
"MLIR form owed" as the direction. Each change below says what it is, what it deletes,
and the skill's one line. *Conjecture* throughout until built and measured.

### C1. The forms decided from interfaces and upstream's utilities (no owner decision needed)

`formOf` keeps its decision (it is D10/D15's) but reads every fact from where it is
declared: the op set from `GeneratingOpInterface` (after C2, `isa<GeneratingOpInterface>`
replaces `Forms.cpp:132`); the region's effects from `mlir::getEffectsRecursively` and the
one effect classifier with `Crash` in the resource tree (lane 02; replaces
`atMostCrashes`, `computes`'s walk and the hand resource compares); the combiner from
upstream's `matchReduction` plus `linalg::getCombinerOpKind` filtered to integer kinds and
no overflow flags (replaces the nine-op ladder and the prose list); the word test from one
classification (I-SL2). The fold/scan difference is chosen once, at the `TypeSwitch`, as a
template parameter (`lowerInterchange<OpT>`, `folded<OpT>`), not re-asked inside;
`Form`'s lowering and statistic are one `constexpr` table; `Inputs` is one vector of
records; `Bind`/`Yield` become data; `valuesOf` and `emptyOf` are upstream's.
*One line:* branch deleted: `Forms.cpp:49, 52-62, 109-110, 132`, `Linalg.cpp:79-81, 158`,
`Nests.cpp:160`, `StructureLoops.cpp:62-73`; check moved to its declaration (effects,
combiner kind, word element).

### C2. `idr.transpose` is a tabulate (with lane 03, and lanes 14/15 for emission)

A transpose moves elements and makes none (`IdrArrayOps.td:189-191`): it is a tabulation
whose region reads the input at the permuted index. The frontend emits that tabulate
(`Emit/Tensors.idr:64-73` already computes the permutation); `readsOf`'s affine map
(`Forms.cpp:135-160`) recognizes the permuted read, so a transpose of words lowers to a
`linalg.generic` with a permutation map (recovered as `linalg.transpose` by
`linalg-specialize-generic-ops`, 0009 stage 3) and one of other elements to the ordered
tabulation that `transposed` (`Nests.cpp:217-236`) writes by hand today. The folder's two
cases become tabulate canonicalizations: a tabulate whose region is the read of a
same-shaped array at its own indices is that array; a read of a tabulate is its region at
the index (which composes two transposes).
*One line:* state made unrepresentable: an array op outside the generating set; branches
deleted: `Forms.cpp:163-164`, `Linalg.cpp:109-118`, `Nests.cpp:217-236, 252`,
`Columns/ArrayOps.cpp:16-34`, `TransposeOp`'s verifier, folder, flow, reify and bounds.
*Risk:* `readsOf` must prove the extents equal through value bounds (`Forms.cpp:151-152`);
the frontend ties them (section 8, R4).

### C3. The generating ops destination-style and tileable; the ordered form upstream's (0009 owed; owner N5)

As 0009's "MLIR form owed" states: `idr.tabulate`, `fold_last`, `scan_last` take
destinations (`outs`, the folds' inits already are), implement `DestinationStyleOpInterface`
and `TilingInterface` (`getIterationDomain`, `getLoopIteratorTypes` from `Idr_Iteration`
spelled as upstream's `IteratorType` plus `Ordered`, `generateScalarImplementation`), and
bufferize through upstream's `DstBufferizableOpInterfaceExternalModel`. `idr-structure-
loops` then only turns the pure word ops into linalg (Parallel, Reduction, Interchange);
an ordered op survives bufferization and becomes loops through upstream's
`lowerToLoopsUsingSCFForOp`. The scan stays an op of ours (D16) until upstream has one;
fold and scan stay two ops (O1: different results).
*One line:* branch deleted: `Nests.cpp` whole (the nest builder and the third dispatch over
the generating set), `GeneratingOpInterface`, `Idr_Iteration`'s translation
(`Linalg.cpp:139-141, 200`).
*Depends on:* lane 03 (the ops), lane 08 (counting must read an ordered generating op's
flow on buffers, which `IdrArrayOps.td:49-53` already declares), lane 12/13 (where loops
are made).

### C4. One op per semantics for the array ops (lane 03; DD-Q3 for the world)

- `array.update` and `element.update` are one op over an array that is either a world
  array or a value buffer (the operand's memory space says which, `IdrArrayOps.td:251-260`),
  with `Arg<…, [MemRead, MemWrite]>` on it beside `RecursiveMemoryEffects`; the hand
  `getEffects` (`OpsArrays.cpp:185, 229`) and `LowerUpdate`'s template parameter go. While
  the world stays a value (DS2.2) the world operand keeps them one TableGen class (O2), not
  one op.
- `tabulate` and `tabulate_io` become one op under DS2.1 (the region's effects order it,
  `Forms.cpp:166` and `Nests.cpp`'s `state` go); under DS2.2 one class.
- `idr.array.yield` split per kind of parent (generating op, update, memo force), so each
  bufferization model and conversion pattern is attached to the terminator it is for
  (`Data.cpp:291-297`, `Arrays.cpp:277-279`, `Columns/ArrayOps.cpp:114-123`).
- One coordinate type for every access and update: `index`, as upstream's memref ops take
  (`Bufferize.cpp:236-239`'s casts go).
*One line:* two ops that differ only in effect become one; the effect is declared, not
written; a model's correctness no longer rests on pipeline position.

### C5. Buffers in data-type bodies, and the linear wrapper tensor-like (0009 §16 stage 2; owner N1)

0009 already designs it: from the frontend on, an array field is its cell buffer at its
grade; `idr.con` takes a tensor and `idr.field` gives one through upstream's
`bufferization.to_buffer` and `to_tensor restrict` (the store a release, the read not
writable); the data-type verifier refuses a tensor in a body; `!idr.lin<T>` becomes
tensor-like where `T` is, by submission 27 (`tensorAllocationFn`) and a per-instance
`extraClassOf` on `TensorLikeType`/`BufferLikeType` (two upstream patches, each with its
`upstream/<bug>/`). One-Shot then bufferizes signatures and linear wrappers itself.
*One line:* state made unrepresentable: a body holding a tensor (verifier); deleted: the
`DataRemap` "buffers" retype (`Bufferize.cpp:319-330`), `heldType`, `StoreModel`,
`HeapReadModel`, and the reason `EnterModel`/`UseModel` exist; the link check stays as the
in-place promise (D33).
*Depends on:* lanes 01 (the data-type verifier, the grade type's interface), 14/15 (Emit's
array fields), upstream patches 27 and `extraClassOf`.

### C6. Bufferization's facts computed once per analysis (no owner decision needed)

- Links (`isLink`) and alias classes (`sharers`) are facts of the program before the
  analysis (`BufferizeModels.h:60-66`): `prepare` computes them once (alias classes as one
  `EquivalenceClasses` over the program's tensor values; links from them and positions)
  and stores them in a `OneShotAnalysisState` extension that the models read.
- A match's yielding regions are counted once per match in the same extension, so no
  model walks a match per query (I-BU10, I-BU11).
- The match ops' model overrides `isRepetitiveRegion` (never) and our code stops asking
  `insideMutuallyExclusiveRegions` per pair (it asks the match, whose regions exclude each
  other by construction); upstream patch U3 for the pin's cache and helper (§5.1).
- `MatchModel` and `MemoRunModel` are one template over `RegionBranchOpInterface`.
- `PoisonModel` goes upstream (a new report and patch).
- `moveElementsOut` and Canon's MoveOut become one rewrite rooted at the write (lane 04),
  or counting's (0009 owed; lane 08).
*One line:* check moved to a boundary (links and alias classes computed at `prepare`, read
by every query); the O(N²) per match is unrepresentable (no per-query region walk).

### C7. Columns read the program's table and decide once (no owner decision needed)

`Records` takes the data types from `TypeGraph::declarations()` (a cached analysis, not a
walk of every op), decides `splits` once into a map, and is passed to each pattern's
constructor (no `static_cast` from the converter). Terminators, region-branch ops and folds
are converted by interface-rooted patterns; signatures by upstream's
`populateAnyFunctionOpInterfaceTypeConversionPattern`, patched upstream first to expand
the argument and result attribute arrays under a 1:N conversion (it leaves them at their
old length today, pin `DialectConversion.cpp:3858-3903`). The per-column table keeps the four upstream ops by name;
ours declare the property.
*One line:* rederivation deleted (the program walk, the per-query decision); the
instantiation list per op becomes interface roots.

### C8. Narrowing scoped by function, the domain by type (QA2, QA4; with lane 05)

The word rewrite already runs per function on the program's cached solve
(`Narrow.cpp:67-133`); what is whole-program is the solve. Under Design 1 of §5.1 it
becomes upstream's `IntegerRangeAnalysis` solved per function in a function-anchored pass,
reading a summary per function (the joined ranges of its arguments over its callers, the
range of its results over its returns) from a summary layer solved over the call graph's
SCCs in both directions (Q-M1). A versioned loop re-solves its own function only (the
whole-program re-solve of `Narrow.cpp:158-165` goes). Under §5.6's Design 2, the solve
keeps state only for values whose type leaves the question open (bigs, naturals and the
integers of their webs), read off the type. In `idr-narrow-lanes`, a trial is an immutable
value (`{exponent, solver}`), so the copy's bound and its solve cannot disagree; the
conversions between words and bigs are declared once (I-NA2); one chain walk (I-NA3).
*One line:* state bounded by construction (the peak is the largest function's solve, not
the program's); the program re-solve after versioning deleted; the hand resync
unrepresentable.
*Alternative (QA2's other side):* keep the whole-program solve on the patched framework
(U1) if it measures small on the stage-1 module.

### C9. The lowering stops counting and stops switching (lanes 08, 12)

`array.get`, `array.set` and `array.new`'s element references are counting's (0009 owed:
`idr-rc` writes `memref.load` + `idr.dup`, `idr.own.give` + `memref.store`), so the
lowering's `inc`/`dec` go (I-CV1). `layout::Element` becomes a sum (`InPlace` |
`Boxed`), each of `Elements.cpp`'s four operations one exhaustive match (I-CV5);
`DescriptorFields` gives its carried fields once (I-CV6); "an element of ours" is
`MemRefElementTypeInterface` (I-CV9); `asIndex` is deleted; the runtime header's size is a
fact of the target's entry (I-CV10).
*One line:* one counting protocol (the second copy in the lowering deleted); a tag switched
in four places becomes one sum.

### C10. The libraries, type-driven (Idris, both hosts)

`(!?)` takes `Coords s`, coordinates indexed by the shape as `Index s` is, so a coordinate
list of another rank cannot be written (I-LI1). The library's `transpose` keeps its type;
its call is emitted as C2's tabulate (I-LI3). Everything else in both libraries already
carries its invariants in its types (section 4's closing paragraph); `Linear.String.
Iterator`'s offset invariant is essential prose at a runtime boundary (I-LI5). `Coords`
is a family indexed by a parameter the value does not store (n erased), inside the subset
both hosts compile, as `Index` is.
*One line:* state made unrepresentable: a coordinate list whose rank is not the array's.

### Order and dependencies

1. **Now, inside the lane, no decision needed:** C1, C6, C7, the narrow items of C8 that
   need no scope change (I-NA2, I-NA3, I-NA15), C9's dead code and `Elements.cpp` sum,
   C10. Each is independent of the others.
2. **With lane 03:** C2, C4 (its world-free half waits on DD-Q3), then C3 (larger; needs
   lanes 08, 12, 13).
3. **After owner decisions:** C5 (0009's stage-2 decision, N1), C8's scope (QA2, QA4),
   C4's merges (DD-Q3), C3's timing (N5).

Lanes depended on: 01 (word classification, grade type interface, data-type verifier,
static lifetime), 02 (effect classifier, resource tree), 03 (op definitions), 04 (MoveOut),
05 (`Ranges`, the summary layer), 08 (counting of element accesses and ordered generating
ops), 12 (lowering), 13 (pipeline order), 14/15 (emission), 19 (Expect reading the IR).

## 6. Evidence for the owner's questions

Evidence only; the decisions are the owner's.

**QA2 (per-function solves with summaries, or whole-program solves after U1).**
- The subsystem runs two kinds of range solve. `idr-narrow-lanes` already solves the
  smallest scope there is: one loop, copied into a scratch module, intraprocedural
  (`Copy.cpp:28-76`), at most six times per loop (2.3). `idr-narrow` reads one
  whole-program interprocedural solve of every value (`Analysis/Ranges.cpp:67-76`,
  `setInterprocedural(true)` on `idr.program`), and solves the whole program again when it
  versioned any loop (`Narrow.cpp:158-165`; 0003 records this).
- What crosses calls: naturals' ranges ("as MLIR's integer range analysis finds them
  across calls", `Ranges.h:3-5`). A per-function solve needs, per function, the join of its
  arguments' ranges over its callers (callers first) and the range of its results over its
  returns (callees first): both directions of Q-M1's schedule.
- The precision a per-function solve gives up inside a recursive SCC is of the kind the
  analysis already gives up: upstream's 128-merge widening sends a loop-carried counter to
  "no bounds" (`Ranges.h:25-33`), and `idr-narrow` recovers loop counters by versioning
  inside one function (`Versions.cpp`), not by cross-call precision.
- The consumer is already per function: `idr-narrow-words` runs nested on each function
  and only reads the solve (`Narrow.cpp:67-83`, `Passes.td:707-718`).
- Scale: on the stage-1 module this is the subsystem's one whole-program per-value solve
  (the value-array passes see no tensor there, 0009 §7). At §5.1 A4's 2.9 KB per state
  plus a 240 B `IntegerValueRangeLattice` and the baseline's lattices, it has the shape of
  16005000's 52 GB wall; nothing has measured it (section 8, R1).
- Precedents read: CIRCT and IREE run upstream's range analysis per op the pass manager
  anchors (§5.6 A5, D3); the library's notes measured `int-range-optimizations` nested per
  function at 3 s against 30 s module-wide (§5.7 L2, citing
  `sources/notes/compile-pipeline/upstream-mlir-llvm.md` §4).
- One-Shot's module analysis (`Bufferize.cpp:5-16`) is whole-program by design (function
  boundary facts, cycles to a fixpoint with patch 24); QA2's per-function option does not
  apply to it unless its boundary facts become summaries, which upstream does not offer.

**cxx-Q2 (ban `std::visit` for one fold `match`, or allow it at ≤ 11 alternatives), with
Q-llvm-4.**
- The subsystem holds one `std::variant`: `layout::DescriptorField = std::variant<Fixed,
  Carried>` (`IR/Layout.h:188-192`), two alternatives. It is visited once with
  `llvm::makeVisitor` (`Descriptors.cpp:84-87`, libc++'s switch path) and asked once more
  with `std::holds_alternative<Carried>` (`:34-36`), whose answer three callers throw away
  (`:101-104, 133-136`). Both rules remove the `holds_alternative`; they differ only on
  whether the two-alternative `visit` becomes a `match`.
- One disguised sum: `layout::Element::boxed` (`std::optional<Cell>`, `IR/Layout.h:163`)
  is tested in four functions (`Elements.cpp:35, 43, 54, 67`): a sum (`InPlace` |
  `Boxed`) that neither rule reaches unless it is first written as one (I-CV5).
- `ranges::Bounds` (`IR/Ranges.h:27-33`, two optionals) is a product whose four states
  are all legal; no sum.

**Other questions the subsystem bears on.**
- **DD-Q3 / ods-Q2 (the world).** Two op pairs differ only by a world:
  `tabulate`/`tabulate_io` (`IdrArrayOps.td:99-135`) and `array.update`/`element.update`
  (`:362-428`, identical C++, `OpsArrays.cpp:148-232`). The world arrays' ops already
  declare their effects on the array, "not on the IO resource: the world operand already
  orders them" (`IdrArrayOps.td:262-270`): two orderings of one access. Under DS2.2 the
  rank-0 `tabulate_io` is the one place the order cannot live on a dimension
  (`Forms.cpp:166`, I-SL11).
- **Q-O3 / Q-E2 (facts into types).** The subsystem writes every answer into the IR:
  narrowing into `arith` on `i64` ("the rewritten IR is the fact", `Narrow.cpp:9-10`);
  columns into one tensor per leaf; bufferization into memref types; structuring into
  linalg or scf. The one fact carried between passes is `Ranges`, held by `idr-narrow` for
  its nested pass; `madeBounds` lives one function.
- **DD-Q1 (grades on trivially copyable types).** No array is trivially copyable; the
  array-side interaction is C5's: `!idr.lin<T>` tensor-like per instance where `T` is a
  tensor, which an interface on the one grade type must decide per instance
  (`upstream/27-one-shot-tensor-like-copy/README.md`).
- **Q-llvm-2 / Q-E3 / oom-2 (budgets).** The subsystem's three: upstream's widening
  (precision), `idr-narrow-lanes`' search range 2^8 to 2^31 in program units (a loop
  outside it stays wide, `Lanes.cpp:182-183`), the greedy driver's default budget in
  `Copy::narrow`, its result unread (`Copy.cpp:111-133`). None fails; none is in bytes or
  seconds.
- **Q1 / cxx-Q1 (interfaces over ops, concepts over our C++).** The one op-listing ladder
  (`Forms.cpp:132`) restates an interface we have. The templates over op classes
  (`LowerUpdate<OpT>`, `ResultColumns<OpT>`, `FoldColumns<OpT>`, `MatchModel<Match>`) sit
  below the dispatch as D1 allows, but are instantiated from per-op registration lists
  (I-CO8) where an interface root would do. No concept in the subsystem.
- **QA4 (one state representation).** The subsystem has no solver of its own; C6's alias
  classes are the one structure that would take the solver layer's dense numbering.
- **rc-Q2 (static against dynamic uniqueness).** In-place array writes are decided
  statically by One-Shot, a copy at a link being an internal error (D33); the lowering
  already tests uniqueness at run time where it must, for a boxed element's cell
  (`Elements.cpp:75-81`, `runtime.exclusive`).
- **Q-O1 (structured match after defunctionalization).** Two passes here read a match's
  regions: bufferization (`Data.cpp:86-222`) and narrowing's joints and versions
  (`Carried.cpp`, `Versions.cpp`, through `RegionBranchOpInterface`). A `case` terminator
  with successors would put One-Shot on unstructured control flow, which upstream supports
  only through `BranchOpInterface` models with limits (*recalled*, to check).

### New questions for the owner

- **N1. 0009's stage-2 decision, inside P0?** "Buffers in data-type bodies" with
  `!idr.lin<T>` tensor-like per instance (0009 §16, §20 item 2) deletes the retype and the
  reason for the release and link models (C5). It is "a decision for stage 2", and it
  reverses §8's reason for keeping the grade off `TensorLikeType`. Does P0 take it, with
  its two upstream patches (27, per-instance `extraClassOf`), or leave it to 0009?
- **N2. Is a link an op?** Whether an `idr.lin.enter` is a link (in place, always) or a
  head (may copy) is re-proved by an analysis on every query (`Linear.cpp:32-50`), though
  the translation knows when it threads one `LArray` across a boundary. One op per kind
  (the check then confirming the op), or one op with the fact computed once (C6)?
- **N3. Where the generating set's one meaning lives.** AGENTS.md: "A primitive of
  `libs/` (an `%extern`) means only what `runtime/` says". `Array.Core`'s 21 externs mean
  what the dialect's ops mean (`Core.idr:12-16`; `IdrArrayOps.td`'s descriptions and the
  lowerings), not a runtime function. Should AGENTS.md (or 0009) name the dialect as their
  one meaning?
- **N4. Transposition as a tabulate.** C2 deletes `idr.transpose`: the frontend writes a
  transpose as a tabulate of a permuted read, and linalg's specialization names it again.
  Acceptable, given 0009 §3.1's "the leading axis is reached through `transpose`, which is
  an indexing map (D3)"?
- **N5. 0009's "MLIR form owed" for the generating ops in P0?** Destination-style,
  `TilingInterface`, the ordered form through upstream after bufferization (C3) is P0's
  direction, but 0009 places its pieces in stages 3 and 4. In P0's cutover, or after it?

## 7. Deletion list

By file and symbol; the change that deletes each in brackets. "(lane NN)" where the
symbol is another lane's to delete.

- `lib/Transforms/StructureLoops/Forms.cpp`: `isWord`, `notWords` (into one
  classification) [C1]; `atMostCrashes`'s resource compares and the
  `HasRecursiveMemoryEffects` fallback [C1]; `computes`' walk [C1]; `reassociates`' nine-op
  ladder [C1]; `structurable`'s op list [C1, C2]; `formOf`'s `TransposeOp` and
  `TabulateIOOp` branches [C2, C4].
- `StructureLoops.cpp`: `counterOf`'s switch and `lower`'s switch (one table) [C1].
- `Linalg.cpp`: `Inputs`' three parallel vectors [C1]; `Bind`, `Yield` [C1]; the unused
  `linalg.index` erase loop (`:79-81`) [C1]; `lowerParallel`'s transpose branch [C2];
  `lowerInterchange`'s `isa<ScanLastOp>` [C1].
- `Lowering.cpp`: `Slice`, `sliceAt`, `valuesOf`, `emptyOf` [C1].
- `Nests.cpp`: `transposed` [C2]; the whole file, `lowerOrdered` and its `TypeSwitch` [C3].
- `include/idr/Transforms/StructureLoops.h`: `structurable`/`formOf` as exports read by
  Expect (lane 19), `valuesOf`, `emptyOf`, `lowerOrdered`, `cloneRegion` [C1, C3].
- `lib/Transforms/Bufferize/Bufferize.cpp`: `heldType` and the `DataRemap` "buffers" block
  (`:314-330`) [C5]; `copies` as a re-derivation (lane 19 reads One-Shot's record) [C6];
  `moveElementsOut`, `readBefore`, `takesBuffer` (one rewrite with MoveOut, lane 04, or
  counting's, lane 08) [C6].
- `Data.cpp`: `StoreModel`, `HeapReadModel` [C5]; `yields`' per-query walk [C6];
  `MemoRunModel` as a second copy (one template with `MatchModel`) [C6].
- `Linear.cpp`: `isLink` as a per-query computation (computed once in `prepare`) [C6];
  `EnterModel`, `UseModel` reduced or deleted by the tensor-like wrapper [C5].
- `Releases.cpp`: `sharers` per query (one partition) [C6]; the de-CSE loop of `prepare`
  (`:131-141`), if measurement agrees [C6, I-BU20].
- `Values.cpp`: `PoisonModel` (upstreamed) [C6].
- `lib/Transforms/Columns/Records.cpp`: `reach` and the program walk of the constructor
  [C7]; `splits` as a per-query computation [C7].
- `Columns.h`: `recordsOf` [C7].
- `Calls.cpp`: `FuncColumns`, `expand` (upstream, patched) [C7]; `TerminatorColumns` and
  `ResultColumns` instantiations per op (interface roots) [C7].
- `Tensors.cpp`: `Mixed` [C1]. `ArrayOps.cpp`: `TransposeColumns` [C2]; the
  `isa<GeneratingOpInterface>` legality of yields [C4].
- `lib/Transforms/Narrow/Narrow.cpp`: the whole-program re-solve after versioning
  (`:154-165`) [C8]; the conversion op list of `conversion` [C8].
- `Facts.cpp`: the `ResultCarriesOperand` walk and the conversion chain in `word` (one
  declaration, one step) [C8]; the `isStatic` calls (lanes 01, 08).
- `Versions.cpp`: the operand-count test for "ends the program" (`:84-88`) [C8].
- `Ops.cpp`: the second copy of the op list (`:226`) [C8].
- `Copy.cpp`, `Lanes.cpp`: `Copy::bound` as a public resync (`Lanes.cpp:156-157`) [C8].
- `lib/Conversion/Arrays.cpp`: the `inc`/`dec` of `LowerArrayNew`, `LowerArrayGet`,
  `LowerArraySet` (counting's, lane 08) [C9]; `LowerUpdate`'s op parameter [C4].
- `Elements.cpp`: the four `element.boxed` branches (one sum) [C9].
- `Descriptors.cpp`: `carries` [C9]; `asIndex` (dead) [C9]; the dialect test at `:176`
  [C9].
- `include/idr/IR/IdrArrayOps.td` and `lib/IR/Ops*.cpp` (lane 03): `TransposeOp` and its
  C++ [C2]; one of `ArrayUpdateOp`/`ElementUpdateOp` and their hand `getEffects` [C4];
  `TabulateIOOp` under DS2.1 [C4]; `GeneratingOpInterface`, `Idr_Iteration` as its own
  enum [C3]; the count and element verifiers that a `PredOpTrait` and `TypesMatchWith`
  declare [C4].
- `include/idr/Transforms/Passes.td`: the combiner list in `IdrStructureLoops`' prose
  (`:362-364`) [C1].
- `libs/mlir-array/Array.idr`: `(!?)`'s `SnocList Integer` argument (`Coords s`) [C10].

## 8. Risks, unknowns, measurements needed

**Risks.**
- **R1. `idr-narrow` on the stage-1 module.** Its whole-program interprocedural range
  solve (`Ranges.cpp:67-76`) keeps a state per value with the baseline beside it, the
  state model of 16005000's wall (§5.1 A4, H1). It has never been measured on that module.
  If it is the next wall, C8 (or U1) is not optional.
- **R2. One-Shot on large matches in array programs.** `YieldModel`'s O(N²) per match
  (I-BU11) and the default `isRepetitiveRegion` (I-BU12) cost only when a match's results
  are tensors; the stage-1 module has none (0009 §7), so the risk is an array program with
  a match of many cases returning arrays (*conjecture*: no such test measured).
- **R3. C3 moves ordered generating ops past bufferization**, so counting meets them on
  buffers. Their flow is declared (`IdrArrayOps.td:49-53`) but counting has never run on
  them (lane 08's risk).
- **R4. C2 rests on value bounds proving a permuted read's extents equal**
  (`Forms.cpp:151-152`). Where it cannot, a word transpose becomes ordered: slower, never
  wrong.
- **R5. C5 needs two upstream patches** (27 and a per-instance `extraClassOf` on
  `TensorLikeType`/`BufferLikeType`); until they are carried, the retype stays.
- **R6. C8 loses cross-call precision inside recursive SCCs**; the `words` property
  (`Expect/Words.cpp`) and the narrowed statistic measure it.
- **R7. I-BU20**: replacing `prepare`'s de-CSE by `alloc_tensor` may lose empty-tensor
  elimination's in-place wins; the `copies` statistic (`Passes.td:420`) measures it.
- **R8. I-CV10**: the runtime header's size is the host's layout; equal on the four LP64
  targets today (*conjecture*, not checked per target).

**Unknowns.** Whether upstream's `getCombinerOpKind` link dependency (it lives in
`MLIRLinalgTransforms`) is already linked (*conjecture*: yes, the vectorizer is used);
whether One-Shot's unstructured-control-flow support would carry Q-O1's CFG core;
how many vectorized loops a bench program has, hence `idr-narrow-lanes`' trial count.

**Measurements needed** (none possible in this checkout: no built compiler).
- `idris-mlir` on the stage-1 module with `--mlir-timing` and a per-pass footprint
  (§5.11 A2): `idr-narrow`'s time and peak; `idr-bufferize`'s and the retype's time (0009
  §7 SELF-HOST).
- V, and the values of big/nat type and their integer webs, at `idr-narrow` (W1, W-E2).
- On the array benches (0009 §16): `numCopies`, `numInPlace`, `numParallel`,
  `numReductions`, `numOrdered`, `numNarrowed`, `numWide` before and after C1, C2, C6, C8.
- The largest match whose results are tensors in the array suites (R2).

## 9. Sources read

**Required reading, in order.** `.claude/skills/representation-first/SKILL.md` (whole);
`AGENTS.md` (whole); `proposals/0000-mlir-native.md` (whole, lines 1-11141, every lane
§5.1-§5.11, §6-§9); `proposals/0003-facts-once.md` (whole); `audits/p0/README.md` (whole).

**The subsystem, line by line.** `foreign/idr/lib/Transforms/StructureLoops/{StructureLoops,
Forms,Linalg,Lowering,Nests}.cpp`; `lib/Transforms/Bufferize/{Bufferize,Data,Linear,
Releases,Values}.cpp`; `lib/Transforms/Columns/{Columns,Records,Calls,Tensors,ArrayOps}.cpp`;
`lib/Transforms/Narrow/{Narrow,Facts,Versions,Carried,Ops,Widths,Lanes,Copy}.cpp`;
`lib/Conversion/{Arrays,Elements,Memrefs,Descriptors,Buffers}.cpp`;
`include/idr/Transforms/{StructureLoops,Bufferize,BufferizeModels,Columns,Narrow}.h`;
`include/idr/Conversion/{Arrays,Elements}.h`; `include/idr/IR/IdrArrayOps.td` (whole);
`libs/mlir-array/{mlir-array.ipkg,Array.idr,Array/Core.idr,Linear/Vec.idr}`;
`libs/mlir-linear/{mlir-linear.ipkg,Linear/List.idr,Linear/Nat.idr,Linear/Notation.idr,
Linear/String/Iterator.idr}`.

**Beside it.** `include/idr/IR/{Arrays.h,Ranges.h}`; `include/idr/Analysis/Ranges.h`;
`lib/Analysis/Ranges.cpp` (solver setup); `include/idr/IR/IdrInterfaces.td:180-290`;
`include/idr/IR/Layout.h:150-215`; `include/idr/IR/TypeGraph.h:56`;
`include/idr/IR/Symbols.h:155-170`; `lib/IR/OpsArrays.cpp:75-300`;
`lib/IR/OpsGenerating.cpp:100-140`; `lib/IR/OpsTabulate.cpp:126-127, 190-191`;
`lib/IR/OpsFolds.cpp:87-89, 174-176`; `include/idr/Transforms/Passes.td:33-71, 308-424,
677-718, 780-810`; `lib/Transforms/Pipeline.cpp:25-182` (by grep);
`lib/Transforms/Expect/{StructuredLoops,NarrowedLanes,InPlace,Words}.cpp` (includes and
reads, by grep); `lib/Conversion/{Lower,StaticBytes}.cpp` (reads, by grep);
`tools/idris-mlir-tblgen.cpp:3071-3100, 3239` (`gen-big-to-word`);
`runtime/Alloc/Arrays.cpp:98-101`; `compiler/src/IdrisMLIR/Registry/Recognized.idr:120-160`;
`compiler/src/IdrisMLIR/Emit/Tensors.idr` (structure, `:296-420`);
`compiler/src/IdrisMLIR/Frontend/Translate/Terms.idr:1540-1580`.

**Proposals and audits.** `proposals/0009-typed-apl/README.md` (lines 1-150, 340-975:
the ruling, §2, §5-§8, §12-§20, "The MLIR form owed"); `proposals/0012-flattened-data.md`
(status, decisions by grep); `proposals/0018-fin-words.md` (head); `audits/bugs.md`
("arrays"); the other wave-2 documents by grep for this lane's files (`02-ods-effects.md`,
`03-ods-ops.md`, `05-analyses.md`).

**Upstream reports.** `upstream/24-one-shot-module-function-interface/README.md`;
`upstream/27-one-shot-tensor-like-copy/README.md`;
`upstream/09-int-range-narrowing-exactness/README.md`;
`upstream/57-linalg-index-int-range/README.md`;
`upstream/56-cse-nested-linalg-index/README.md`;
`upstream/04-vectorize-precondition-body/README.md` (head);
`upstream/58-delinearize-empty-basis/README.md`.

**Pinned tree** (`.toolchain/llvm-project/mlir`, 7208ba24).
`lib/Dialect/Bufferization/IR/BufferizableOpInterface.cpp:60-106` (the repetitive-region
caches); `include/mlir/Dialect/Bufferization/IR/BufferizationOps.td:28-36`
(`alloc_tensor`); `include/mlir/Dialect/Bufferization/Transforms/Passes.td:375`;
`include/mlir/Analysis/SliceAnalysis.h:250-266` (`matchReduction`);
`include/mlir/Dialect/Linalg/Transforms/Transforms.h:46` and
`lib/Dialect/Linalg/Transforms/Vectorization.cpp:625-700` (`getCombinerOpKind`);
`include/mlir/Dialect/Linalg/IR/LinalgStructuredOps.td:233, 314, 398, 474` (map, reduce,
transpose, broadcast); `include/mlir/Dialect/Tensor/IR/TensorOps.td:131, 724, 1251` and the
`tensor.empty` builders (`:306-315`); `lib/Dialect/Tensor/Transforms/
BufferizableOpInterfaceImpl.cpp` (by grep); `include/mlir/Dialect/MemRef/IR/MemRefOps.td:
1087-1135` (`generic_atomic_rmw`); `include/mlir/Transforms/DialectConversion.h:812-824`;
`lib/Transforms/Utils/DialectConversion.cpp:3855-3970`;
`include/mlir/Dialect/Func/Transforms/FuncConversions.h:32-58`;
`include/mlir/Dialect/Arith/Utils/Utils.h:60-72`;
`include/mlir/Dialect/Utils/StaticValueUtils.h:42`; `lib/Dialect/UB/IR/UBOps.cpp` and
`lib/Dialect/Bufferization` (grep for a poison model: none);
`lib/Dialect/SCF/Transforms/BufferizableOpInterfaceImpl.cpp:1313-1340`.

**History.** `git log --oneline` of every path above; `git show` of bf3a8ede (columns: a
record held by a data type keeps its arrays whole), 4108916a (the bug phase: narrowing
through views, the rank-0 tabulation, the cast lowering), 3c8a666a (the arrays-refused
audit's last record), the subjects of 7987388b, c4d38e9b, 467fa2f5, da66bd95, 651164af,
d2ee4e41, 56e39f59, 7446d444, 1e1a3827, a4e763c7.

**Commands run** (read-only): `wc -l`, `grep -rn`, `grep -c`, `find`, `ls`, `sed -n`,
`git log`, `git show`; the counts of 2.2 with `bash -c 'grep -rn -- "$p" $F | wc -l'`.
