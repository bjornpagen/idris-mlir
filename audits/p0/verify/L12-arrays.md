<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 verification, lane L12: arrays

HEAD at start: `e96bb991` (2026-10-21T21:31Z). HEAD at finish: `e96bb991`
(unchanged; every anchor below is at that commit, the dirty tree read as it
stood). Rulings in scope: D20 (the world's arrays), D39 (element views), D41
(the vectorization stage), D42, D43. Nothing here was built or run: every
cost is *read* or *conjecture*, and every behaviour claim that would need a
run is written as the test that would show it.

Marks: *read* (path:line at HEAD; `M/` is the pinned MLIR tree,
`.toolchain/llvm-project/mlir` at 7208ba24, unpatched in the checkout:
`git status` there is clean), *measured* (the command given), *recalled*,
*conjecture*, *decision* (Dn, Cn). `idr/` is `foreign/idr/`.

Classification of observations: **[defect]** a defect confirmed in the
source; **[incomplete]** structural incompleteness; **[mismatch]** an
integration mismatch; **[unverified]** unverified behaviour; **[simplify]**
an optional simplification.

## 1. Verification

### 1.1 Verdicts

| ruling | verdict | the correction, in one line |
| --- | --- | --- |
| D20 (arrays part) | holds with a correction | the update op's "region cannot see the empty place" moves from the world to an effect rule; `#idr.world` names a deleted concept |
| D39 (element views) | holds with a correction | the anchor is stale; the view is a cast after `memref.load`, whose result type upstream fixes; aliasing of shared arrays decides "no write" |
| D41 (vectorization stage) | holds | the arith expansion of a linalg body happens inside `idr-lower`, which already precedes the schedule |
| D42 | holds with a correction | 22 externs; 3 are identities, one of which (`merge`) drops a fact and miscompiles; most mean upstream ops or compositions, and the table is hand code that C6 makes generated |
| D43 | holds with corrections | `lowerToLoopsUsingSCFForOp` takes only buffer-semantics ops; the destination needs the cells' extents before the first cell; the bridging ops refuse a non-shaped tensor-like type, so the second patch has a second hunk; `UseModel`'s writability is a defect, not a reason that goes away |

### 1.2 D20: the world's arrays

**D20.1. "The `tabulate`/`tabulate_io` pair merges." Holds.** *read*:
`idr.tabulate_io` differs from `idr.tabulate` only by a world operand, a
region argument after the indices and a world result
(`idr/include/idr/IR/IdrArrayOps.td:114-135` against `:99-112`); both carry
`RecursiveMemoryEffects` (`:55`). Its iterations are "all `Ordered`" by kind
(`idr/lib/IR/OpsTabulate.cpp:190-192`), and `formOf` special-cases it
(`idr/lib/Transforms/StructureLoops/Forms.cpp:165-167`) because at rank 0 no
dimension can carry the world's order (11 I-SL11). With the world gone, the
region's own derived effects carry the order: a region that does IO fails
`computes` (`Forms.cpp:67-76`) and is ordered at every rank, rank 0
included. The case is gone, not handled. [simplify] confirmed.

**D20.2. "The `array.update`/`element.update` pair merges." Holds with a
correction.** *read*: the two share every line of C++ (11 I-TD4, citing
`idr/lib/IR/OpsArrays.cpp:148-232`), and differ by the world operand and by
the operand's memory space (`IdrArrayOps.td:362-428`). The correction:
`array.update`'s soundness rests on a sentence the world made true: "only the
region runs there: it binds no world, so it performs no access of an array a
world orders and cannot see the empty place" (`IdrArrayOps.td:355-357`).
After D20 the region binds nothing that forbids it, so a region that read or
wrote an aliasing array would see the hole the element left. [incomplete]:
the merged op needs the guarantee restated as a rule its region verifier
reads from the one effect query: the region's derived effects hold no access
to `contents` (D27's resource for memory written in place). The producers the op
names meet it (an IORef's modify and a record's update in place rebuild a
value from itself, `IdrArrayOps.td:357-359`; the post-bufferization move
yields the element, `Bufferize.cpp:240-247`), so the rule should refuse
nothing a program writes (*conjecture* for the frontend's every emission
of an update, unread); it is a check moved to the op's
verifier, once per op, not a guard.

**D20.3. "The ten world-ordered memory ops read effects." Holds with a
correction.** *read*: the array ops declare plain `MemRead`/`MemWrite`/
`MemAlloc` on their array operand, which is `DefaultResource`, the root
(`IdrArrayOps.td:288, 314, 334`), beside `Idr_PerformsIO` (`:272`) and
world operands. After D20 and D27 the effects are on `contents` (read,
written in place) and the allocation on `heap`; that is lane L01's
declaration, recorded here as the seam. Two corrections inside the arrays:
- [incomplete] The memory space `#idr.world` (`IdrArrayOps.td:236-239`)
  names the world D20 deletes. The fact it carries is essential and stays:
  this memory is written after it is shared (base's `IOArray`, `IORef`,
  `Buffer`), unlike a value array's buffer, which is written only where
  One-Shot proved the write in place. Renamed for the state it is (D28's
  rule), `#idr.mutable`.
- [simplify] The world ops and `element.update` take `I64` indices "as an
  array a world orders does" (`IdrArrayOps.td:287, 314, 335, 367, 410`;
  `Bufferize.cpp:236-239` casts every store's indices to match); with the
  world gone that reason is gone. One coordinate, `index`, as upstream's
  memref ops take (11 I-BU5, I-TD7).

### 1.3 D39: an array element a view

**Holds with a correction.** The claim: "an array element a view where D27's
effects show no write to the array", deleting "the `dup` of every counted
element read from an array (`Ownership.h:22-23`) where no write intervenes".
- [mismatch] The anchor is stale. `idr/include/idr/IR/Ownership.h:18-23` is
  `buildsCell`'s comment. The dup is counting's `ownFields`: "So does every
  element read from a buffer, right after its load"
  (`idr/lib/Transforms/Ownership/Reshape.cpp:109-112`, *read*).
- [incomplete] The view cannot be the load's own result: `memref.load`'s
  result type is the memref's element type (upstream's op verifier), so no
  grade or lifetime can sit on it. The view is a grade cast right after the
  load, at the buffer's lifetime (D40's lifetime of the buffer value), which
  counting places instead of today's `idr.dup`. Lane L05 owns the cast; the
  seam is that the array stage emits plain `memref.load`.
- [incomplete] "No write to the array" must mean "no write to `contents`
  that may alias it". A value array's buffer is written only by One-Shot's
  in-place decisions, but a `#idr.mutable` array is shared memory read
  through any number of SSA values (two field reads of one `IORef` are two
  memrefs naming one cell). The test is the one effect query over the
  element's live range with MLIR's alias analysis on the memref values; a
  call in that range carries its callee's row (D22), whose `write` atom ends
  the view. Upstream's `memref.store` declares its write on the root
  resource, which the query reads as covering `contents`: correct, and
  coarser than D27 (the seam with L01: whether the effect system reads a
  root effect with an addressable memref value as a `contents` effect).
- Element views on linear arrays meet a QTT loss first (§3.3 item 3): the
  frontend's translation of `LArray.read` uses the linear binder twice, and
  Emit then holds it plain.

### 1.4 D41: the vectorization stage

**Holds.** *read*: the pipeline lowers with `idr-lower`
(`idr/lib/Transforms/Pipeline.cpp:140`) before the vectorization schedule
(`:150`), `idr-narrow-lanes` (`:152`) and `convert-linalg-to-loops`
(`:166`). A linalg body reaches the schedule only through `idr-lower`, so the
D41 template's IR-builder instance, applied by `idr-lower` to the inline
arithmetic ops inside linalg bodies, is "the stage that needs arith" for
vectorization; no separate stage exists or is needed. `formOf` admits such
ops in a body when they only compute and crash (`Forms.cpp:46-63`), which is
what keeps their parallel dimensions parallel. The interval instance
(`InferIntRangeInterface`) is what `idr-narrow-lanes` reads after the
expansion (`Pipeline.cpp:152`); nothing in the array stage computes the
meaning a second time. [unverified]: no fixture shows a linalg body holding
an inline arithmetic op reaching the schedule; S1 should hold one (a
Euclidean division in a `tabulate` over `Int`).

### 1.5 D42: the generating set means the dialect's ops

**Holds with a correction.**
- *measured* (`grep -c '%extern' libs/mlir-array/Array/Core.idr`): 22, as
  D42 says (11 counted 21; `tabulateIO` makes 22).
- [mismatch] They do not all mean "the op the Idris specification declares
  for each". *read* (`compiler/src/IdrisMLIR/Registry/Recognized.idr:132-161`,
  `Frontend/Translate/Terms.idr:1530-1600`): three are identities in the
  registry (`nest`, `merge`, `LArray.freeze`; `Recognized.idr:146-147, 158`),
  three are our ops (`tabulate`, `foldLast`, `scanLast`, plus `tabulateIO`,
  which D20 folds into `tabulate`), and the rest are upstream ops or
  compositions written by hand in `Terms.idr` (`!!` and `read` are
  `tensor.extract`, `update` and `write` `tensor.insert`, `take`/`drop`
  slices, `++` and `pad` and `grow` concatenations, `reshape` collapse and
  expand, `withArray` a filled tabulation applied to the continuation,
  `thaw` the continuation applied to the array). AGENTS.md on disk is
  amended (`AGENTS.md:531-536`: "the dialect op the specification declares
  for it, with upstream's tensor and linalg semantics"); its text should say
  "the op, ours or an admitted upstream one (D51), or the composition the
  specification declares for it".
- [mismatch] The table that says which extern means what is hand code in two
  places (the registry rows and the translation's `case` over `ArrayPrim`,
  `Registry/Entry.idr:205-209`). C6 and D50 make it the specification's: one
  row per extern naming its op or composition, the registry's row generated.
- [defect] `merge`'s meaning is lost. Its documented reason to take the
  cells' extents is the empty frame: "The cells' extents are given, so that
  an empty frame, which has no cell to read them from, still has a shape"
  (`libs/mlir-array/Array/Core.idr:151-155`). The registry's identity hook
  reads none of the arguments before the last: "a runtime argument before it
  is not read (`nest`'s cell form, `merge`'s extents)"
  (`compiler/src/IdrisMLIR/Registry/Entry.idr:285-289`). And the ordered
  tabulation gives an empty domain's cells extent 0 where its type leaves
  them dynamic (`idr/lib/Transforms/StructureLoops/Nests.cpp:141-151`). So
  `shape (merge [<k] (tabulate [<m] (\_ => tabulate [<k] f)))` at run-time
  `m = 0` reads `[<0, 0]` where Idris's meaning is `[<0, k]`. *conjecture*
  until run (§4 I2 holds the test).

### 1.6 D43: 0009's array cutover in P0

**D43.1. "`tabulate`, `fold_last` and `scan_last` take destinations,
implement `DestinationStyleOpInterface` and `TilingInterface`, bufferize
through upstream's model, and an ordered one becomes loops through
`lowerToLoopsUsingSCFForOp`." Holds with corrections.**
- [incomplete] `lowerToLoopsUsingSCFForOp` refuses an op with results:
  "unable to lower to loops operations with return values"
  (`M/lib/Dialect/SCF/Transforms/TileUsingInterface.cpp:2608-2612`, *read*).
  So the ordered form lowers the bufferized op, and each generating op must
  have a buffer form (memref destinations, no results), which today's
  definitions do not admit (`IdrArrayOps.td:103, 146-147, 171-172`: results
  and inits are `AnyRankedTensor`). DPS's own verifier admits exactly this
  pair, a tensor or a memref init, and checks tied result types
  (`M/lib/Interfaces/DestinationStyleOpInterface.cpp:29-60`).
- [incomplete] `DstBufferizableOpInterfaceExternalModel` supplies three
  methods only: every operand read, inits written, an init aliasing its tied
  result (`M/include/mlir/Dialect/Bufferization/IR/DstBufferizableOpInterfaceImpl.h:22-47`).
  `bufferize` is the op's own. And "every operand read" is wrong for a
  tabulation's destination and a scan's results, which the op writes and
  never reads: left so, One-Shot keeps a destination's undefined contents
  alive and copies where no copy is needed. The model overrides it
  (§2.3).
- [incomplete] A destination must exist before the op runs, and a tabulated
  array of cells whose extents the type leaves dynamic gets them from its
  first cell: today's ordered form makes the first cell before the array
  (`Nests.cpp:94-123`), and Emit says so ("those it leaves dynamic the cells'
  own, which every cell shares", `compiler/src/IdrisMLIR/Emit/Tensors.idr:429-433`).
  D43 deletes `Nests.cpp` whole, so this essential case needs its own
  representation in destination-passing form (§4 I4).
- [incomplete] "`TilingInterface`" names twenty methods with defaults
  (`M/include/mlir/Interfaces/TilingInterface.td:75-505`). The ordered form
  needs three (`getLoopIteratorTypes`, `getIterationDomain`,
  `generateScalarImplementation`); exactness needs the rest left at their
  defaults, which return failure, so no tiling driver can retile an op whose
  order is observable (§2.3, §4 I7).
- *read*, holds: value bounds needs no method for a result's dimension of a
  DPS op; upstream ties it to the tied operand's
  (`M/lib/Interfaces/ValueBoundsOpInterface.cpp:455-461`). But that fallback
  applies only when the op does not implement `ValueBoundsOpInterface`, and
  the region's indices still need their bounds, so each op keeps the
  interface with two one-line methods.

**D43.2. "`idr-structure-loops` only turns the pure word ops into linalg;
deletes `Nests.cpp` whole, `GeneratingOpInterface` and `Idr_Iteration`'s
translation." Holds, extended.** *read*: `GeneratingOpInterface`'s consumers
are three casts in the pass (`Forms.cpp:136, 169`; `Lowering.cpp:75`) and one
legality test in columns (`idr/lib/Transforms/Columns/ArrayOps.cpp:117`);
`Idr_Iteration` is never stored, only derived from the op's kind
(`OpsTabulate.cpp:126-128, 190-192`; `OpsFolds.cpp:87-91, 174-178`). Its
two cases are exactly upstream's two iterator types on an op that
implements no `PartialReductionOpInterface` (§4 I7), so the enum goes whole,
not just its translation.

**D43.3. "An array field is its buffer from the frontend on: `idr.con` takes
a tensor through `bufferization.to_buffer`, `idr.field` gives one through
`to_tensor restrict`, the data-type verifier refuses a tensor in a body."
Holds with corrections.**
- *read*, holds: upstream's `to_buffer` model reads and writes its operand
  and aliases no result (`M/lib/Dialect/Bufferization/Transforms/BufferizableOpInterfaceImpl.cpp:280-297`):
  a release, as `StoreModel` is (`idr/lib/Transforms/Bufferize/Data.cpp:32-57`).
  Its fold reallocates and copies a slice to the declared identity layout
  (`M/lib/Dialect/Bufferization/IR/BufferizationOps.cpp:27-63, 94-135`), as
  `cellBuffer` does (`Bufferize.cpp:91-101`). `to_tensor` without `writable`
  is a non-writable root (`BufferizableOpInterfaceImpl.cpp:257-278`), as
  `HeapReadModel` is (`Data.cpp:59-81`). Both of ours go.
- [incomplete] For a linear field the read must be writable or the linear
  thread copies at every write; and whether it may be writable is the cell's
  exclusivity, not the field's quantity (§4 I1, which also finds the defect
  in today's model).
- [incomplete] Under D48 there is no "data-type verifier" beside the type:
  the family attribute's verifier (run once per unique attribute) refuses a
  field type that is tensor-like. Lane L04's attribute; the seam in §2.6.

**D43.4. "`!idr.lin<T>` is tensor-like where `T` is, so One-Shot bufferizes
linear wrappers and signatures itself; two upstream patches, carried."
Holds with corrections.**
- *read*: a type interface may decide per instance (`extraClassOf`,
  `M/include/mlir/IR/Interfaces.td:123-128`; emitted for type interfaces,
  `M/tools/mlir-tblgen/OpInterfacesGen.cpp:658-668`). `TensorLikeType` and
  `BufferLikeType` have none (`M/include/mlir/Dialect/Bufferization/IR/BufferizationTypeInterfaces.td:18-50`).
- [incomplete] The bridging ops refuse a tensor-like type that is not
  shaped. `to_tensor` and `to_buffer` carry `SameOperandsAndResultShape`
  and `SameOperandsAndResultElementType` beside the tensor-buffer match
  (`M/include/mlir/Dialect/Bufferization/IR/BufferizationOps.td:331-334,
  415-420`). For a type that is not a `ShapedType`, the element type is the
  type itself (`M/lib/IR/Operation.cpp:1086-1108` through
  `getElementTypeOrSelf`), so `!idr.q<one, plain, tensor<?xi64>>` and its
  buffer `!idr.q<one, plain, memref<?xi64>>` differ and the verifier refuses
  the op. One-Shot itself builds such a `to_tensor` for every tensor-like
  result it replaces (`M/lib/Dialect/Bufferization/IR/BufferizableOpInterface.cpp:824-837`),
  and the frontend would write one at every linear field read. The second
  patch therefore has a second hunk (§4 I5).
- [incomplete] At the pin `TensorLikeType` has no buffer-type method; a
  non-builtin tensor-like type is converted by `unknownTypeConverterFn`,
  whose default and our own both `cast<TensorType>`
  (`BufferizableOpInterface.cpp:404-411`; `idr/lib/Transforms/Bufferize/Bufferize.cpp:275-279`),
  and `defaultGetBufferType` asserts a builtin tensor
  (`BufferizableOpInterface.cpp:969-973`). Every model that may meet a graded
  tensor must compute its buffer type through our converter (grade kept,
  inner tensor to its cell buffer), today's `cellType` included
  (`Bufferize.cpp:81-83`, read by `MatchModel` for a case's block argument,
  `Data.cpp:121-123`).
- [unverified] Upstream's SCF models compute an iter-arg's or a result's
  buffer type from inits and yields through `getBufferType`
  (`M/lib/Dialect/SCF/Transforms/BufferizableOpInterfaceImpl.cpp:249-299,
  387-399`); whether every path stays clear of the builtin assertion for a
  graded tensor is unread in full. The test: an `scf.for` and an `scf.if`
  carrying a linear array through One-Shot, and an `idr.call` returning one
  under patch 24.
- [mismatch] Submission 27's report says "`tests/upstream-one-shot-tensor-like-copy`
  checked that the pinned source still skips such an OpOperand"
  (`upstream/27-one-shot-tensor-like-copy/README.md`, "Testing at the pin");
  *measured* (`ls tests | grep -i tensor-like`): no such test exists.

**D43.5. "Deletes the buffers retype (`DataRemap`), `heldType`,
`StoreModel`, `HeapReadModel`, and the reason `EnterModel` and `UseModel`
exist." Holds with a correction.** *read*: the retype exists because a
linear tensor and a body holding a tensor are no tensors to One-Shot
(`Bufferize.cpp:29-34, 314-330`); `heldType` serves it and `HeapReadModel`
(`Bufferize.cpp:85-89`; `Data.cpp:77`). With buffers in bodies and the
wrapper tensor-like, nothing is left for it; D48 deletes `DataRemap` whole
for its own reasons, so the two rulings agree. The correction: `lin.enter`
and `lin.use` still need one model, a cast whose result is its operand's
buffer (an equivalent alias that reads and writes nothing); what goes is
`EnterModel`'s release and `UseModel`'s root. And `UseModel`'s root is not
merely obsolete: its unconditional `isWritable` (`idr/lib/Transforms/Bufferize/Linear.cpp:91`)
is a defect (§4 I1).

**D43.6. "Reverses 0009 §8's reason for keeping the grade off
`TensorLikeType`; 0009 is amended in the same change." Holds.** *read*:
0009 §8 (`proposals/0009-typed-apl/README.md:509-527`), §16's stage-2
decision (`:746-749`) and "The MLIR form owed" (`:958-970`) all point here;
§20 item 2 (`:945-950`) is the paragraph to rewrite.

### 1.7 Load-bearing claims of 11 and synthesis C this lane re-read

- 11 R3 ("C3 moves ordered generating ops past bufferization, so counting
  meets them on buffers"): holds; resolved by §4 I6, which keeps them there
  on purpose.
- 11 C6 (bufferization's facts computed once): holds; under the tensor-like
  wrapper the link test shrinks to a type fact and its hand conflict check
  goes (§4 I9), which removes most of what C6 cached.
- Synthesis C §3.11 and 11 §3.1 (ownership-based deallocation refuted as a
  target): holds; counting frees buffers (`Bufferize.cpp:23-27`).
- 11 I-BU12 and §5.1 C2 (the pin's repetitive-region cache never fills):
  holds; the generating ops' regions are repetitive by their
  `RegionBranchOpInterface` (region to region), which One-Shot must see, so
  their model keeps upstream's default; the match models override it to
  "never" (11 C6).

## 2. Boundaries

### 2.1 Types

| type | holds | invariant |
| --- | --- | --- |
| `tensor<d… x E>` | a value array (`Array s a`, and `LArray s a` under its grade) | a dimension is static where Idris's index term is a constant, dynamic otherwise; `E` a word, a float, or one of ours through `MemRefElementTypeInterface` |
| `!idr.q<g, tensor<…>>` | a graded value array | tensor-like exactly when its value type is (patch 64's `isTensorLike`, read from a bit the type computes when made); its buffer is `!idr.q<g, memref<…>>`, the grade kept |
| `memref<d… x E>` (default space) | a value array's buffer, the cell bufferization made | identity layout wherever it crosses a call, enters a grade or sits in a field; written only where One-Shot decided in place |
| `!idr.q<g, memref<…>>` | a graded buffer | buffer-like exactly when its value type is (patch 64's `isBufferLike`) |
| `memref<?xE, #idr.mutable>`, `memref<E, #idr.mutable>` | `IOArray`/`Buffer` (rank 1), an `IORef`'s cell (rank 0) | written after it is shared; never tensor-like; never tied by `tie_shape` |
| `#idr.mutable` (renamed from `#idr.world`) | the memory space attribute | the one fact: memory written while shared |

`!idr.lin<T>` is the grade `(one, plain)`; an exclusive linear grade
`(one, excl)` is what an `LArray` value carries if the owner rules §6 OQ2
yes.

### 2.2 Ops

**The generating set** (each destination-style, each `RecursiveMemoryEffects`,
`RecursivelySpeculatable`, `SingleBlock`, one region whose leading block
arguments are the domain's indices, ending in `idr.array.yield` or
`ub.unreachable`):

| op | operands | results (tensor form; none on buffers) | region arguments |
| --- | --- | --- | --- |
| `idr.tabulate` | `outs` (≥ 1, each `tensor` or `memref`, all sharing the domain's leading dimensions) | one per tensor init, tied | the domain's indices |
| `idr.fold_last` | `length : index`; `outs` (the accumulators' first values, overwritten with the last) | one per tensor init, tied | the frame's indices, the step, one accumulator per init |
| `idr.scan_last` | `length : index`; `inits` (inputs, read); `outs` (every accumulator) | one per tensor out, tied | the frame's indices, the step, one accumulator per init |
| `idr.array.yield` | the cells (tabulate) or next accumulators (fold, scan) | none (terminator) | — |

`idr.tabulate_io` and `idr.transpose` are gone (D20; §4 I10). `idr.array.yield`
ends a generating op's region only (`ParentOneOf` the three, from the
specification's family); the update op and `memo.run` end in terminators of
their own (11 I-BU14).

**Arrays of `#idr.mutable` memory** (D20, D27): `idr.array.new` (allocates
on `heap`, writes its fill), `idr.array.get` (reads `contents` of its array,
its index guarded by `idr.check.in_bounds`), `idr.array.set` (reads and
writes `contents`, guarded), one `idr.array.update` on any memref (reads and
writes `contents` of the element's place, `RecursiveMemoryEffects`, its region
verified to touch no `contents`), all at `index` coordinates and no world.

**Kept**: `idr.nat.to_extent` (an extent entering `index` at its allocation,
which may crash, `IdrArrayOps.td:441-448`), `idr.tie_shape` (`:465-476`),
`lin.enter`/`lin.use` with one cast model (or lane L13's merged `lin.cast`).

**Upstream, as they are**: `tensor` (`extract`, `insert`, `extract_slice`,
`insert_slice`, `collapse_shape`, `expand_shape`, `empty`, `dim`, `cast`),
`bufferization.to_buffer`, `to_tensor` (with `restrict`, and `writable` per
§4 I1), `bufferization.alloc_tensor` (the copy patch 27's hook makes for a
graded tensor), `linalg.generic` and its named forms, `scf.for`/`scf.if`,
`memref.alloc`/`load`/`store`/`copy`/`subview`/`dim`.

### 2.3 The generating ops' interfaces, method by method

The acceptance asks for each op's interfaces method by method. "computes"
below is the one effect query's answer that the region does no more than
compute and crash (lane L02's classifier); it is asked once per op.

**`idr.tabulate`**

| interface | method | answer |
| --- | --- | --- |
| `DestinationStyleOpInterface` | `getDpsInitsMutable` | `outs` (no inputs: the region reads captured arrays with `tensor.extract`) |
| `TilingInterface` | `getLoopIteratorTypes` | `parallel` on every dimension where the region computes; `reduction` on every dimension otherwise (§4 I7) |
| | `getIterationDomain` | `[0, dim(outs[0], d), 1]` for each `d` below the rank |
| | `generateScalarImplementation(ivs)` | the region cloned at `ivs`; each yielded value `j` written into `outs[j]` at `ivs` (an element by `memref.store`, a cell by `memref.subview` then `memref.copy`); a region ending in `ub.unreachable` writes nothing |
| | every other method | default (failure): never tiled |
| `BufferizableOpInterface` (upstream's DPS model, plus ours) | `bufferizesToMemoryRead(outs)` | false (written, never read) |
| | `bufferizesToMemoryWrite(outs)` | true (the DPS model's) |
| | `getAliasingValues(outs[j])` | result `j`, equivalent (the DPS model's) |
| | `bufferize` | the op cloned over the inits' buffers with no results, its region moved; results replaced by the buffers |
| | `isRepetitiveRegion(0)` | true (upstream's default, read from `RegionBranchOpInterface`) |
| `RegionBranchOpInterface` | `getSuccessorRegions` | from the op into the region; from the region to itself (the next index) or out; nothing forwarded (yielded values go to memory) |
| `ReifyRankedShapedTypeOpInterface` | `reifyResultShapes` | result `j`'s sizes are `outs[j]`'s |
| `ValueBoundsOpInterface` | `populateBoundsForIndexValue(iv d)` | `0 ≤ iv < dim(outs[0], d)` |
| | `populateBoundsForShapedValueDim(result j, d)` | `dim(outs[j], d)` |
| `MemoryEffectOpInterface` (own effects, beside `RecursiveMemoryEffects`) | `getEffects` | a write of `contents` on each buffer init; none on tensors (a typed rule of the effect specification: effects that follow from operand types) |
| `Idr_FlowOpInterface` | `getFlowEdges` | result `j` is init `j` with each yielded value `j` moved into its elements |

**`idr.fold_last`**: as `idr.tabulate`, with these differences.

| interface | method | answer |
| --- | --- | --- |
| `DestinationStyleOpInterface` | `getDpsInitsMutable` | `outs` (the accumulators) |
| `TilingInterface` | `getLoopIteratorTypes` | `parallel` on the frame where the region computes, then `reduction`; `reduction` everywhere otherwise |
| | `getIterationDomain` | the frame from `outs[0]`'s leading dimensions, then `[0, length, 1]` |
| | `generateScalarImplementation(p, j)` | each accumulator read from `outs[k]` at `p` (an element by `memref.load`, a cell its subview), the region cloned at `(p, j, acc…)`, each next accumulator written back at `p` |
| `BufferizableOpInterface` | `bufferizesToMemoryRead(outs)` | true (the first values are read) |
| `LastAxisFoldOpInterface` | `getInits`, `getLength`, `getFrameRank`, `getAccumulators` | kept: the shape fold and scan share, read by `idr-structure-loops`' reduction and interchange forms |
| `MemoryEffectOpInterface` | `getEffects` | a read and a write of `contents` on each buffer init |

**`idr.scan_last`**: as `idr.fold_last`, with these differences.

| interface | method | answer |
| --- | --- | --- |
| `DestinationStyleOpInterface` | inputs / `getDpsInitsMutable` | `inits` / `outs` |
| `TilingInterface` | `getIterationDomain` | the frame from `outs[0]`, then `[0, length, 1]` |
| | `generateScalarImplementation(p, j)` | the accumulator is `inits[k]` at `p` when `j = 0`, else `outs[k]` at `p :< j-1` (one `scf.if`, which LLVM's loop peeling removes); the next accumulator written to `outs[k]` at `p :< j` |
| `BufferizableOpInterface` | `bufferizesToMemoryRead` | true on `inits`, false on `outs` |
| | `getAliasingValues(inits[k])` | none |
| `MemoryEffectOpInterface` | `getEffects` | a read of `contents` on each buffer init, a write on each buffer out |

### 2.4 Passes and where each fact is decided

1. **The frontend** (lane L16) writes value arrays as tensors, array fields
   as buffers (`to_buffer` before `idr.con`, `to_tensor restrict` after
   `idr.field`), each generating op over a destination (`tensor.empty` of
   the frame's extents and the cells'), the first-cell form where no cell
   extent is known outside the region (§4 I4), `merge` as a reshape to its
   given extents (§4 I2), and `idr.tie_shape` at a function's entry, a
   call's results and a field's read (where a sibling field states an
   extent).
2. **`idr-structure-loops`**, per function, after the optimizer: a pure op
   over words becomes linalg (parallel, reduction, or the interchange of an
   ordered last dimension around a parallel frame); any other op stays as it
   is. `Nests.cpp` is gone; "ordered" means "left alone".
3. **`idr-bufferize`**, whole program (One-Shot's module analysis, patch 24):
   upstream's models for `tensor`, `linalg`, `scf`, `bufferization`, the
   function boundary on `idr.func`/`call`/`return`; ours for the generating
   ops (§2.3), the cast (`lin.enter`/`lin.use`), the region-branch
   forwarding template (`match`, `match_lit`, `memo.run`, 11 I-BU13),
   `tie_shape`, and `ub.poison` until its upstream model lands (11 I-BU21).
   Options: patch 27's `tensorAllocationFn` (a graded tensor's copy:
   `alloc_tensor` of its value, the grade put back), `unknownTypeConverterFn`
   and `functionArgTypeConverterFn` that keep a grade around the cell
   buffer, identity layouts at boundaries (`Bufferize.cpp:271-285`, kept).
4. **Counting** meets the generating ops on buffers, through their declared
   flow and effects (§4 I6).
5. **The ordered loops**, right before `idr-lower`, per function:
   `lowerToLoopsUsingSCFForOp` on every generating op left, which by then has
   buffer semantics.
6. **`idr-lower`**: the D41 expansion inside linalg bodies; the array
   lowering (`idr/lib/Conversion/Arrays.cpp`, `Elements.cpp`, `Memrefs.cpp`,
   `Descriptors.cpp`, `Buffers.cpp`), which counts nothing once counting owns
   element accesses (0009 owed; 11 C9).

### 2.5 Constructor provenance

| fact | constructed by | who alone may | read by |
| --- | --- | --- | --- |
| an array's shape is a ranked tensor type, static where Idris's term is a constant | the frontend (Emit) | the frontend; specialization may refine a dimension to static (D48's index substitution, or 0009 stage 2's cast) | every tensor op; value bounds |
| two dimensions are equal | Idris's type checker; written as `idr.tie_shape` with an SSA size | the frontend | value bounds, `formOf`'s permuted reads (`Forms.cpp:121-127, 151-152`) |
| a graded tensor is tensor-like | the grade type, when made (a bit in its storage from its value type) | the type's builder | One-Shot (every `isa<TensorLikeType>`) |
| a field holds a buffer, never a tensor | the family attribute's verifier (L04) | Idris's declaration through the frontend | `idr.con`, `idr.field`, layout |
| a field read is writable | the frontend, as `to_tensor … writable`, only for a scrutinee whose grade is exclusive | the frontend (§4 I1) | One-Shot |
| a linear array is exclusive | the closed world of `LArray`'s introductions (§3.2), written as its grade | the frontend from the registry's `LArray` hook, if OQ2 rules yes | bufferization (in place by type), counting, exclusivity (L08) |
| a generating op's destination and its cells' extents | the frontend (`tensor.empty`, or the first-cell form) | the frontend; a canonicalization may hoist the cell extents out of the first-cell form | DPS, tiling's domain, bufferization |
| a dimension's visit (parallel or ordered) | the op's class and the region's effects | the specification (class), the one effect query (region) | `formOf`, tiling drivers |
| a combine is reassociable | the region's combiner (upstream's `matchReduction`, `getCombinerOpKind`, 11 I-SL7) | `formOf` | the reduction form |
| an operand is written in place, or copied | One-Shot's analysis | One-Shot alone | the rewrite; the `in-place` property reads One-Shot's record (11 I-BU2) |
| a write on a linear thread is in place | the grade (exclusive) and One-Shot's consistency check | — | internal error on a conflict (`M/lib/Dialect/Bufferization/Transforms/OneShotAnalysis.cpp:1542-1552`) |
| an element read is a view | counting (L05/L07), from the effect query between the load and the element's last use | counting | the lowering |

### 2.6 Consumers, failure and cleanup paths

- **A One-Shot failure** is an internal error with One-Shot's words, the
  program's invariant broken (`Bufferize.cpp:144-168`, kept).
- **A RaW conflict on an operand that must be in place** (a linear thread's
  write, a region-branch yield) is One-Shot's consistency check, reported as
  an internal error, never `unsupported`.
- **A `to_tensor` left after bufferization** is a verifier error at the
  pass's end; with patch 64's second hunk it verifies for a graded type, so
  a leftover is One-Shot's own `allowUnknownOps` failure, which the pass does
  not set.
- **A region ending in `ub.unreachable`** writes nothing at its index; the
  crash ends the run (D21) before anything reads the hole, so a partly
  written destination is never observed or freed.
- **An empty domain**: no region runs; the destination's extents are the
  frame's (zero) and the cells', so `shape` and `merge` read what Idris says.
- **Columns** (`idr-columns`) splits a tabulation over records into one
  destination per field: the 1:N conversion of `outs` and results together
  (the consumer adaptation of `ResultColumns`/`FoldColumns`, 11 I-CO8).

### 2.7 What goes

- `idr/lib/Transforms/StructureLoops/Nests.cpp` whole (`tabulated`,
  `folded`, `transposed`, `lowerOrdered`); `lowerOrdered`, `cloneRegion`,
  `valuesOf`, `emptyOf`, `structurable`, `formOf` as exports
  (`idr/include/idr/Transforms/StructureLoops.h:57-63, 85, 96-110`); the
  `Ordered` case of `lower` (`StructureLoops.cpp:37-38`).
- `Idr_GeneratingOpInterface` (`idr/include/idr/IR/IdrInterfaces.td:204-225`)
  and its declarations on the ops (`IdrArrayOps.td:66-79`); `Idr_Iteration`
  (`IdrArrayOps.td:38-42`) and every `getIterations`; `getExtent`,
  `getExtentBound`, `reifyTabulated`, `reifyDimOfResult`, `boundTabulated`
  (`idr/lib/IR/OpsTabulate.cpp`, `OpsFolds.cpp`).
- `Idr_TabulateIOOp` and its canonicalizer; `Idr_TransposeOp` with its
  verifier, folder, flow, reify and bounds (`IdrArrayOps.td:119-135,
  192-204`; `idr/lib/IR/OpsGenerating.cpp:106-122`); `TransposeColumns`
  (`Columns/ArrayOps.cpp:16-34`); `formOf`'s two special cases
  (`Forms.cpp:163-167`); `lowerParallel`'s transpose branch.
- `Idr_ElementUpdateOp` (merged into `idr.array.update`); `LowerUpdate<OpT>`'s
  parameter; both hand `getEffects` bodies (11 I-TD4).
- `idr/lib/Transforms/Bufferize/Data.cpp`: `StoreModel`, `HeapReadModel`,
  `MemoRunModel` and `MatchModel` as two copies (one template);
  `Bufferize.cpp`: `heldType`, the `DataRemap` "buffers" block (`:314-330`);
  `BufferizeModels.h`: `heldType`; `Linear.cpp`: `EnterModel`'s release,
  `UseModel`, and `isLink`'s conflict half (`:44-48`, §4 I9);
  `Releases.cpp`: `sharers` per query.
- `idr/lib/Transforms/Expect/StructuredLoops.cpp:27`'s call of the pass's
  predicate (the property reads the IR the pass leaves, lane L19).
- `compiler/src/IdrisMLIR/Registry/Recognized.idr:147`'s identity entry for
  `merge` (§4 I2); `Terms.idr`'s hand compositions, generated from the
  specification's table (C6).
- `#idr.world` as a name; the `I64` coordinates of the array ops.
- Proposal 0009's §8 reason and §20 item 2 (amended in the change).

### 2.8 Essential distinctions that stay

- **Value against mutable memory**: a tensor (written in place only where
  One-Shot proves it) against `#idr.mutable` memory (written while shared).
  Two kinds of array, because the language has both (`Array` against
  `IOArray`).
- **Parallel against ordered**: a dimension whose visits the program can
  observe is ordered; one it cannot is parallel. Read off the region.
- **Words against counted elements in linalg**: no linalg body holds a
  reference while counting runs between bufferization and the lowering and
  reads no linalg body (`Forms.cpp:78-97`; 11 I-SL6).
- **A fold's last dimension against a scan's**: two ops, two results (O1).
- **A head against a link of a linear thread**: the head may copy (a fresh
  array, a thawed one), a link never may. Under the tensor-like wrapper both
  are one cast op; the distinction is the grade (§4 I9).
- **A cell's extents known before the first cell, or only after it**
  (§4 I4): essential to the flattening of an array of arrays into one
  tensor.

### 2.9 Seams with other lanes

| lane | the declaration both sides write against | state |
| --- | --- | --- |
| L01 | the generating ops' typed rule (a write of `contents` on each buffer destination, a read where the op reads it) beside `RecursiveMemoryEffects`; `idr.array.*` on `contents` and `heap`; the update region's "no `contents`" rule | unfixed: §5.1's five forms do not yet name a rule for destinations |
| L02 | "computes": the region's derived effects at most a crash | fixed by D9 (one query) |
| L04 | the family attribute: a field's type plain (a buffer for an array), its quantity apart; the verifier refuses a tensor-like field | fixed in shape by D48; the tensor rule is this lane's ask |
| L05 | the element view: a cast after `memref.load` at the buffer's lifetime | unfixed |
| L07 | counting meets the generating ops on buffers (flow edges, `IdrArrayOps.td:49-53`); one counting protocol per element access (0009 owed); a store into a slot of a fresh destination places, never releases (§3.4) | unfixed |
| L08 | a field read is writable only for an exclusive scrutinee; `LArray` exclusive by construction (OQ2) | unfixed |
| L09 | the generating ops are region ops whose region repeats; no join point's jump crosses one (they implement no `PropagateControlFlowBreak`, D25) | fixed by D19, D25 |
| L11 | `idris_rt_array_new`'s NULL fill (`runtime/Alloc/Arrays.cpp:96-112`) for arrays that a generating op wholly places | unfixed |
| L13 | one op per semantics: the merges, the transpose, the yield split | fixed by D20, open for the yield |
| L16 | Emit's array fields, destinations, the first-cell form, `merge`, `tie_shape` at field reads, the linear `read` | unfixed |
| L18 | the specializer's key for static extents: D48's index arguments or 0009 stage 2's refined tensor type (OQ1) | unfixed |
| L19 | the tests of §4 | — |

## 3. QTT

### 3.1 Where quantities enter, stay, are read and are lost

| fact | Idris's TT | the frontend | the dialect | the lowering | LLVM |
| --- | --- | --- | --- | --- | --- |
| a shape `(0 s : Shape)` | erased index of `Array`, `LArray` (`Core.idr:92, 99`) | no parameter (AGENTS.md: q0 is no value); a dimension static where `s`'s term is a constant | `tensor` dims static or `?`; equalities by `tie_shape` | the extents live in the value (cell plus dynamic dims, `idr/include/idr/Conversion/Arrays.h:3-13`) | words |
| `Extents s` at ω (a singleton) | a run-time value | sizes as `index` (`idr.nat.to_extent` at an allocation) | operands of the destination's `tensor.empty` | words | words |
| `Index s` (a `Fin` per axis) | ω values bounded by the type | a coordinate, unguarded: "its type bounds it by an extent" (`Emit/Tensors.idr:47-54`) | `index` | `index` | no bounds check (D10 kept) |
| proofs: `LTE k n` (`take`, `drop`), `count s = count t` (`reshape`), `fits : LTE n cap` (`Vec`) | q0 | nothing | nothing | nothing | nothing (kept) |
| `LArray s a` at 1 | linear binders and continuations (`Core.idr:206-236`) | `!idr.lin<tensor>` | the grade; One-Shot's link check | the grade on buffers | — |
| a linear field | the field's quantity | the field's quantity | `fieldType`: scrutinee's quantity times the field's (`idr/lib/IR/Grades.cpp:253-260`) | — | — |
| ω arrays | sharing | plain tensors | One-Shot's SSA aliasing; field reads non-writable | counted cells | — |

**Lost** (each a finding):
1. **At `LArray.read` and `LArray.shape`.** The translation writes the
   linear array twice in one term: the element (or the extents) read from
   `l`, and `l` again as the second component of the result
   (`compiler/src/IdrisMLIR/Frontend/Translate/Terms.idr:1570-1578,
   1582-1589`). Emit counts the uses and, past one, "is used once where it is
   bound and held plain" (`compiler/src/IdrisMLIR/Emit/Bodies.idr:131-138`;
   17 FB-28). So every `read` of a linear array drops the grade in that
   scope, and the verifier's linearity check no longer covers the thread
   there; only `isLink`'s def-chain search re-finds it. §4 I3.
2. **At `merge`.** The extents argument is discarded (§1.5). §4 I2.
3. **At a field read.** The field's quantity is read as exclusivity
   (§4 I1).

### 3.2 What a quantity proves about aliasing that bufferization now analyses

*Theorem (decision, argued from QTT; the argument is written out because no
source states it).* In a program with no escape hatch (`believe_me`,
`assert_linear`), every value of a type whose every introduction gives it
only to a linear binder is referenced once at run time. Proof sketch: QTT
scales the resources of a term by its binder's quantity (Atkey; Idris 2's
`Rig` multiplication), so a term that mentions a linear variable is itself
usable only linearly; a constructor holding the value (`MkT l`) is then used
linearly, and matching it at quantity 1 binds the field at 1
(`third_party/Idris2/docs/source/tutorial/multiplicities.rst:156-180`).
Matching at ω gives ω fields (`:192-206`), but no ω value holding such a
value can be built. `LArray`'s introductions are `withArray` and `thaw`
(fresh, to a linear continuation, `Core.idr:206-207, 225-226`), `read`,
`write` and `grow` (linear in, linear out, `:211, 216, 236`); there is no
ω introduction, and the library exports no constructor (`:96-99`). So every
`LArray` value is exclusive.

Consequences, each a fact the design still pays for at compile time:
- One-Shot analyses every write of a linear thread for read-after-write
  conflicts (its per-operand conflict check) and `isLink` repeats the check
  by hand (`Linear.cpp:44-48`: every sharer's every use against
  `mayRunAfter`). Both decide what the theorem settles: in place. §4 I9.
- The theorem does **not** hold for a linear binder of a type that has an ω
  introduction (a value array `Array s a` bound at 1, a linear field of a
  record built from an ω array). AGENTS.md's "a linear binder does not imply
  unique heap ownership" is exactly that case, and today's model gets it
  wrong (§4 I1).

### 3.3 Using quantities harder

1. **Exclusivity by construction for `LArray`, and for `Linear.Vec.Vec`**
   (whose one constructor holds a linear `LArray` and which is only ever
   given linearly, `libs/mlir-array/Linear/Vec.idr:38-48`): the grade
   `(one, excl)` written by the frontend from the registry, verified by the
   type (no op makes an exclusive value from a shared one but a fresh
   allocation or a release that copies). Owner question OQ2, because it
   makes `LArray`'s promise D24's.
2. **Writability is exclusivity.** A buffer read out of a cell is writable
   only when the cell's grade is exclusive; quantity 1 alone never makes it
   so (§4 I1).
3. **The linear `read` keeps its binder.** One linear use, the array given
   back (§4 I3), so the verifier's linearity check covers every thread end
   to end, and the element view of D39 is decided on a typed thread.
4. **A dying exclusive buffer moves.** `grow` copies the old array into a
   larger one with a counted copy (each element gains a reference) and then
   drops the old (each loses one); `Vec.freeze` keeps the fill reachable
   through the spare capacity of the frozen view (`Vec.idr:20-23, 126-128`).
   Exclusivity plus last use make both a move (§4 I8): 2n count updates and
   a second live buffer gone, and D26's "a structure held past its last use"
   honoured.
5. **Shapes erased, not doubled.** A rank-1 buffer in a field or across a
   call carries its extent as a component beside the cell, whose header
   holds the length (`runtime/Alloc/Arrays.cpp:106`, `array->length =
   count`): one fact held twice at run time for rank 1. [simplify], lane L11
   and the lowering's: drop the component where the header holds the extent.
6. **`Fin n` one word below `n`** (D48, 0018): a coordinate made from an
   `Index s` is then a word, and today's `idr.big.to_int` then
   `arith.index_castui` pair (`Emit/Tensors.idr:50-54`) goes with the big it
   converts.

### 3.4 A static fact paid at run time (D10), for lanes L07 and L11

`idris_rt_array_new` zero-fills every object slot of a new array "until a
store", and every store "releases what the slot held, and the cell's death
releases every slot, written or not" (`runtime/Alloc/Arrays.cpp:91-112`);
the lowering's store decrements the old element (`idr/lib/Conversion/Elements.cpp:52-62`,
`Memrefs.cpp:97-109`), through a NULL test (18 R-RC-1). For an array a
generating op makes, every slot is written exactly once, before anything
reads or frees the array (an abnormal end of a region ends the run, D21): a
static fact. It stands only while the generating op stands, which is one
reason §4 I6 keeps the op until the lowering. The selected shape: a
generating op over counted elements always writes a fresh destination
(its init verified to be `tensor.empty`, so empty-tensor elimination never
gives it an old slice; overwriting part of an existing counted array stays
`insert_slice`'s counted copy), its scalar implementation places (the
lowering's `placeElement`, `Elements.cpp:41-50`) and never decrements, and
the allocation feeding it is not zero-filled. The allocation's side is lane
L11's (the runtime entry's fill), the store's lane L07's.

## 4. Improvements

### I1. A cell's field is writable only when the cell is exclusive (coordinator)

- **Evidence.** *read*: `UseModel::isWritable` returns true unconditionally
  (`idr/lib/Transforms/Bufferize/Linear.cpp:91`), justified as "A linear
  array read from a cell is no tensor here; its use makes the writable root,
  since the store was its release" (`Data.cpp:14-16`). A field of a linear
  scrutinee is read at the product of the quantities
  (`idr/lib/IR/Grades.cpp:253-260`). Idris passes an ω value to a quantity-1
  parameter freely.
- **Counterexample.**
  ```idris
  record Box where
    constructor MkBox
    1 arr : Array [<3] Int

  bump : (1 _ : Box) -> Array [<3] Int
  bump (MkBox a) = update a [<0] 5

  main : IO ()
  main = do
    let b = MkBox (tabulate [<3] (const 0))
    printLn (bump b !! [<0])                    -- 5
    printLn (case b of MkBox a => a !! [<0])    -- must print 0
  ```
  In `bump`, `a` is `!idr.lin<tensor<3xi64>>`; `lin.use` is a writable root;
  `tensor.insert` bufferizes in place into the buffer `b`'s cell holds,
  which `main` still shares. Expected output `5` then `0`; the model predicts
  `5` then `5` (*conjecture* until run). AGENTS.md: "Linearity is a
  performance property, never a correctness one".
- **Root cause.** The store's release made the buffer the cell's alone, but
  the cell is shared; the representation reads "this buffer is mine" off a
  quantity, a fact about the binder, where it is a fact about the cell's
  ownership.
- **Correction.** Under the tensor-like wrapper, `lin.use` and `lin.enter`
  are equivalent casts, roots no more. The root of a field's buffer is the
  frontend's `to_tensor restrict`, `writable` exactly when the scrutinee's
  grade is exclusive. Before counting no grade is exclusive but an `LArray`
  value's (OQ2); every other linear field read copies before its first
  write, which is One-Shot's ordinary out-of-place decision.
- **Deletes.** `UseModel`; `EnterModel`'s release; the comment's argument.
- **Discriminated by.** The program above as a test (expected `5`, `0`); and
  `tests/` linear-array programs unchanged (no copy on an `LArray` thread,
  read through One-Shot's in-place statistic).

### I2. `merge` keeps the extents it is given (coordinator)

- **Evidence.** §1.5: the identity hook discards `merge`'s extents
  (`Registry/Entry.idr:285-289`, `Recognized.idr:147`); an empty domain's
  dynamic cell extents are 0 (`Nests.cpp:141-151`).
- **Counterexample.** `shape (merge [<k] (tabulate [<m] (\_ => tabulate [<k]
  f)))` with `m` and `k` run-time values, `m = 0`, `k = 5`: expected
  `[<0, 5]`, predicted `[<0, 0]` (*conjecture* until run); `(++)` along the
  last axis of two such arrays shows it again.
- **Root cause.** A fact Idris states (the cells' extents) is dropped by a
  registry hook that calls the function an identity; the flattening of an
  array of arrays needs it exactly when no cell exists.
- **Correction.** `merge e x` is `tensor.collapse_shape` then
  `tensor.expand_shape` to the frame's extents followed by `e`'s: equal
  counts on a non-empty frame (every cell has `e`'s shape by type) and 0 = 0
  on an empty one, so the reshape is valid in both cases and the result
  carries `e`. `nest` stays the identity (its cell form is erased-length,
  `Core.idr:58-64`).
- **Deletes.** The identity entry for `merge`; the empty-domain zero of the
  cell extents becomes harmless (no reader sees it).
- **Discriminated by.** The program above as a test, expected `[<0, 5]`.

### I3. The linear `read` and `shape` are one linear use (coordinator; with L16, L17's C5)

- **Evidence.** §3.1 item 1.
- **Counterexample.** `withArray [<4] 0 (\l => let x # l = read l [<0] in
  let l = write l [<1] x in freeze l)`: after Emit, `l` is held plain from
  its first `read` (*read*, `Emit/Bodies.idr:131-138`); a pass that
  duplicated a plain value there would be legal by the IR and wrong by the
  library's promise, and the verifier could not tell.
- **Root cause.** The translation writes "read, and give back" as two uses
  of the binder because Core has no form for "use once, give back".
- **Correction.** The translation emits the read through the binder's one
  use: the array used once, read, and re-entered into the grade as the
  second component (in MLIR, `lin.use`, `tensor.extract`, `lin.enter`); the
  same for `LArray.shape`. Emit then counts one use and keeps the grade, and
  17's C5 (a binder's quantity proved of the term) holds for these sites by
  construction.
- **Deletes.** These two sites' reliance on Emit's demotion; the demotion
  itself goes with 17 C5.
- **Discriminated by.** The quantities contract (`tests/expect-quantities`,
  keyed by binder, lane L19) on an `LArray` program: every binder of the
  thread linear after Emit.

### I4. A tabulation of cells whose extents only a cell knows (coordinator)

- **Evidence.** §1.6 D43.1, third item.
- **Counterexample.** `tabulate [<n] (\i => g i)` where `g i : Array c a`
  and the only run-time witness of `c` is inside `g`. With a destination
  required before the op, there is nothing to size it with; recomputing the
  first cell would run the region twice at index 0, which an effectful
  region (D20 folds `tabulateIO` in) may not do.
- **Root cause.** Flattening an array of arrays into one tensor needs the
  cell extents at allocation; Idris guarantees one cell shape (`c` is fixed
  outside the lambda) but not a witness outside it.
- **Correction.** The frontend writes, for a tabulation whose cell type has
  a dynamic dimension: if the domain is empty, the destination with cell
  extents 0 (unobservable after I2); otherwise the cell at the zero index
  computed once (`%first`), the destination sized by the frame and
  `%first`'s extents, and the op over the whole domain whose region yields
  `%first` at the zero index and runs the body elsewhere. Each index runs
  the body once, the domain is a box, and the op is destination-style. A
  canonicalization removes the zero-index case and the outer copy when the
  yielded cell's reified extents are defined above the region (the common
  case: `tabulate [<n] (\i => tabulate e f)`); it changes speed, never what
  is accepted.
- **Deletes.** `Nests.cpp:94-153`'s first-cell path with the rest of the
  file.
- **Discriminated by.** A tabulation whose cell extents come from inside the
  region (a test of output and of the region running once per index, the
  region printing its index under an IO tabulation), and the same with an
  outside witness, checked to carry no zero-index case after
  canonicalization (a property of the output, lane L19).

### I5. The two upstream patches, specified (coordinator; D25)

**Patch 27, `upstream/27-one-shot-tensor-like-copy/`** (carried; was a
submission). The diff as written (`pull-request.diff`, against 7208ba24)
becomes `llvm.patch`: `BufferizationOptions::tensorAllocationFn`, its
default failing with the type named; `allocateTensorForShapedValue` calls
it for a tensor-like value that is not a builtin tensor, where it reached
`llvm_unreachable`; `resolveTensorOpOperandConflicts` takes every
tensor-like operand, where it skipped them (a silent miscompile);
`one-shot-bufferize-tensor-like-copy.mlir`. Ours: `idr-bufferize` sets the
hook for a graded tensor (its value copied by `bufferization.alloc_tensor
… copy(…)`, the grade put back). The README's "Why there is no patch"
becomes "Patch"; `tests/upstream-one-shot-tensor-like-copy` is written
(it is claimed and absent, §1.6); PINS.md and `upstream/README.md:97` change
in the same commit. Upstreaming plan unchanged (an issue and a PR).

**Patch 64, `upstream/64-tensor-like-per-instance/`** (new; filed after 27).
Title: "[mlir][bufferization] Let a type be tensor-like or buffer-like per
instance". Two hunks:
1. `BufferizationTypeInterfaces.td`: `TensorLikeType` gains
   `InterfaceMethod<"Whether this instance is tensor-like", "bool",
   "isTensorLike", (ins), "", "return true;">` and `let extraClassOf =
   [{ return $_type.isTensorLike(); }];`; `BufferLikeType` the same with
   `isBufferLike`. A qualifier type that wraps any value (a grade, a
   linearity wrapper, an attribute-carrying wrapper) is then tensor-like
   exactly where it wraps a tensor; the precedent is `SymbolOpInterface`'s
   `extraClassOf` for ops. Builtins keep the defaults through their external
   models (`M/lib/Dialect/Bufferization/IR/BufferizationDialect.cpp:38-62`).
2. `BufferizationOps.td`: `to_tensor` and `to_buffer` drop
   `SameOperandsAndResultShape` and `SameOperandsAndResultElementType`; the
   tensor-buffer match (`verifyCompatibleBufferType`) is their one check.
   For builtins nothing is lost: the builtin model already checks shapes and
   element types (`BufferizationDialect.cpp:42-55`). For a tensor-like type
   that is not shaped, the dropped trait refused every bridge
   (`Operation.cpp:1086-1108`).

   Test: `one-shot-bufferize-tensor-like-per-instance.mlir` with a test
   type `!test.maybe_tensor<T>` (tensor-like iff `T` is a builtin tensor,
   not shaped) and its buffer twin: an op on `!test.maybe_tensor<i32>` is
   not analysed; one on `!test.maybe_tensor<tensor<4xf64>>` bufferizes, its
   `to_tensor`/`to_buffer` verify. Cost: one indirect call per
   `isa<TensorLikeType>` on a builtin tensor (*conjecture*; the PR measures
   `check-mlir`'s bufferization tests). Status: not filed; dropped when the
   pin carries it.

Ours, with it: `!idr.q`'s models (tensor-like and buffer-like where its
value is; `verifyCompatibleBufferType` equal grades and compatible values;
the bit computed when the type is made, so the check is O(1)), the two type
converters keeping the grade, and §1.6's buffer-type paths. **Deletes**: the
retype, `heldType`, the release and root models. **Discriminated by**: the
two patches' upstream tests; `tests/upstream-…` for each; a linear array
crossing an `idr.call`, an `scf.for` and an `idr.match` bufferized with no
copy.

### I6. The generating ops stand until the lowering (coordinator; with L07)

- **Evidence.** D18 (lossless); `lowerToLoopsUsingSCFForOp` needs the op on
  buffers anyway (§1.6); counting already reads the ops' flow
  (`IdrArrayOps.td:49-53`, `DeclareOpInterfaceMethods<Idr_FlowOpInterface>`
  at `:57`).
- **Counterexample.** Lowering to `scf.for` right after bufferization turns
  "every slot written once, before any read" into stores in a loop, and the
  NULL fill and NULL tests of §3.4 follow; counting then also meets the
  loops 11 R3 feared, as stores it cannot tell from overwrites.
- **Root cause.** A loop drops the op's statement of its domain and of its
  writes.
- **Correction.** Counting runs on the bufferized generating op through its
  flow and effects; `lowerToLoopsUsingSCFForOp` runs per function right
  before `idr-lower`; the scalar implementation places into the fresh
  destination (§3.4).
- **Deletes.** The question of when ordered loops are made; the zero fill
  for wholly placed arrays (with L11).
- **Discriminated by.** A tabulation of strings: no `inc`/`dec` of an
  element slot at its stores in the lowered module (a property of the
  output); the live-cell differential unchanged.

### I7. `Idr_Iteration` goes whole; the iterator types are exact (coordinator)

- **Evidence.** §1.6 D43.2; partial reduction requires
  `PartialReductionOpInterface` by name
  (`M/lib/Dialect/SCF/Transforms/TileUsingInterface.cpp:740-744, 835-892`).
- **Counterexample.** A tabulation whose region prints its index, answering
  `parallel`: `tile_using_forall` (stage 3's schedule, 0009 §7.1) may run it
  on many shards, and a 2-D one tiled with `tile_using_for` visits tile by
  tile, not row by row: output order changes.
- **Root cause.** "Parallel" is a property of the region, not of the op's
  kind; today's enum states it by kind (`OpsTabulate.cpp:126-128`).
- **Correction.** `getLoopIteratorTypes` answers `parallel` only where the
  region computes, else `reduction`; `reduction` on an op that implements no
  `PartialReductionOpInterface` means "in order, carried", which no upstream
  transform reassociates. Every tiling method stays at its failing default.
  0009 D32's reassociable fold (stage 4) is then the op implementing
  `PartialReductionOpInterface`, never a third enum case.
- **Deletes.** `Idr_Iteration`, `getIterations`, the hand translation
  (`Linalg.cpp:139-141, 200`).
- **Discriminated by.** A dialect test: the transform interpreter's
  `tile_using_forall` on an effectful tabulation fails to apply; on a pure
  one over strings it applies.

### I8. A dying exclusive buffer resizes by moving (coordinator; D26, with L07, L11)

- **Evidence.** `grow` is a concatenation with copies (`Terms.idr:1590-1593`):
  a counted copy of the old elements, then the old array dropped. `freeze` is
  `take n` of the cells (`Vec.idr:126-128`), a view: the spare slots past
  `n` keep their references to the fill for as long as the frozen array
  lives.
- **Counterexample.** `withVec 0 bigList` then a thousand pushes then
  `freeze`: the frozen `Vector 1000` keeps `bigList` alive through slots the
  program can never read, against D26's "never: any structure held past its
  last use"; each growth of a vector of strings pays a count per element twice.
- **Root cause.** The copy forgets that its source is exclusive and dies at
  the copy; the view forgets that the slots past it are dead.
- **Correction.** On the last use of an exclusive buffer (OQ2's grade,
  counting's last use), `grow` is a reallocation that keeps the elements'
  references (`memref.realloc` on the runtime's cell, new slots filled), and
  a `take` that ends a thread shrinks the buffer, releasing the dropped
  slots. One op of ours where upstream has no tensor-level resize, naming
  the gap.
- **Deletes.** 2n count updates per growth; the fill held by a frozen
  vector's spare capacity.
- **Discriminated by.** The program above: peak live cells after `freeze`
  exclude `bigList` (the live-cell differential); `Vec` benchmarks' count
  calls per push.

### I9. A link is a type, not a search (coordinator)

- **Evidence.** `isLink` traces equivalences back to `lin.use`, then walks
  every sharer's every use against `mayRunAfter` (`Linear.cpp:32-50`) per
  `mustBufferizeInPlace` query, which is One-Shot's own conflict check done
  again; One-Shot already reports a conflict on a must-in-place operand
  (`OneShotAnalysis.cpp:1542-1552`).
- **Counterexample.** None in output; the cost is the per-query walk,
  O(sharers × uses) on each entry of each thread (*read*), and the double
  statement of one check.
- **Root cause.** The fact "this entry continues a thread" is re-derived
  instead of held.
- **Correction.** With the wrapper tensor-like, a thread is one alias chain
  to One-Shot; an entry's operand is in place by type when it is a graded
  exclusive value's buffer (OQ2), or when its equivalence chain reaches a
  cast out of a linear value (computed once in `prepare`, 11 C6, if OQ2 is
  no). A conflict there is One-Shot's internal error.
- **Deletes.** `isLink`'s second half; `sharers` per query.
- **Discriminated by.** The linear-array tests unchanged; a fixture whose
  thread a pass breaks (a read after a write of the same version, written by
  hand) reports the internal error.

### I10. A transpose is a tabulation (coordinator; 11 C2)

- **Evidence.** 11 C2, I-SL9, I-SL16, I-CO10; `idr.transpose` "moves
  elements and makes none" (`IdrArrayOps.td:189-191`); 0009 §3.1 calls the
  transpose "an indexing map", which a permuted read in a generic is.
- **Correction.** The library's `transpose` means a tabulation reading at
  the swapped indices; a word transpose becomes a `linalg.generic` with a
  permutation map (named again by `linalg-specialize-generic-ops`).
- **Deletes.** §2.7's transpose list.
- **Discriminated by.** The transpose programs' output unchanged; no
  `idr.transpose` in any module.

### I11. `#idr.mutable`, `index`, and the update rule (coordinator)

§1.2 D20.2, D20.3: rename the memory space for the state it is, one
coordinate type, and the merged update op's region verified to touch no
`contents`. **Deletes** the name, the casts (`Bufferize.cpp:236-239`), the
`I64` operands, `ElementUpdateOp`. **Discriminated by** a dialect test: an
update whose region reads an array refuses.

### I12. The externs' meanings, one generated table (coordinator; C6, D50)

§1.5: one row per extern in the specification (op or composition), the
registry's rows and the translation's dispatch generated or read from it.
**Deletes** the hand `case` over `ArrayPrim` and the hand rows.
**Discriminated by** D49's regeneration check.

## 5. Work units (drafts; none dispatched)

**U1. The two upstream patches.** Write set: `upstream/27-one-shot-tensor-like-copy/`
(`llvm.patch`, README), `upstream/64-tensor-like-per-instance/` (README,
`llvm.patch`, reproducer), `tests/upstream-one-shot-tensor-like-copy/`,
`tests/upstream-tensor-like-per-instance/`, `PINS.md`, `upstream/README.md`.
Outcome: both carried, each with its plan. Must not: change any idr code.
Acceptance: the patches apply to the pin (`tests/upstream-patches`), the
toolchain builds on four targets, each test runs its reproducer.

**U2. The specification of the array ops.** Write set: the array module of
`compiler/spec/` (C7) and the generated, committed `.td` and C++ it
produces (D49). Outcome: the three generating ops destination-style, the
merged update, the mutable array ops on `contents`/`heap`, `idr.array.yield`
for generating ops alone, the typed effect rule for destinations, the
extern table (I12). Deletes: `tabulate_io`, `transpose`, `element.update`,
`GeneratingOpInterface`, `Idr_Iteration`, `#idr.world`. Must not: write a
`.td` by hand. Acceptance: D49's check; the dialect parses and verifies the
§2.3 forms.

**U3. The op implementations.** Write set: `idr/lib/IR/OpsTabulate.cpp`,
`OpsFolds.cpp`, `OpsGenerating.cpp`, `OpsArrays.cpp`. Outcome: §2.3's
methods. Must not: implement any tiling method but the three. Acceptance:
I7's dialect test; `lowerToLoopsUsingSCFForOp` on each op's buffer form
gives row-major loops (a test of output order under an IO region).

**U4. Bufferization.** Write set: `idr/lib/Transforms/Bufferize/*`,
`idr/include/idr/Transforms/Bufferize.h`, `BufferizeModels.h`. Outcome:
§2.4 item 3; I1, I5's ours, I9. Deletes: §2.7's bufferization list. Must
not: run ownership-based deallocation. Acceptance: I1's program; no copy on
linear threads in the suites; One-Shot's statistics before and after on the
array benchmarks (0009 §16), 11 §8's counters.

**U5. Structure loops.** Write set: `idr/lib/Transforms/StructureLoops/*`,
`idr/include/idr/Transforms/StructureLoops.h`,
`idr/lib/Transforms/Expect/StructuredLoops.cpp`. Outcome: forms only;
`Nests.cpp` deleted. Must not: emit `scf` for an ordered op. Acceptance: the
`structured-loops` property reads the output IR; outputs unchanged.

**U6. The ordered loops and the array lowering.** Write set:
`idr/lib/Transforms/Pipeline.cpp` (the one step before `idr-lower`),
`idr/lib/Conversion/Arrays.cpp`, `Elements.cpp`, `Memrefs.cpp`; with L11,
`runtime/Alloc/Arrays.cpp`. Outcome: I6, §3.4. Must not: count in the
lowering once counting owns element accesses. Acceptance: I6's test; the
live-cell differential.

**U7. The frontend's arrays.** Write set: `compiler/src/IdrisMLIR/Emit/Tensors.idr`,
`compiler/src/IdrisMLIR/Frontend/Translate/Terms.idr` (the array
primitives), `compiler/src/IdrisMLIR/Registry/Recognized.idr` (generated
rows). Outcome: buffers in fields, destinations, I2, I3, I4, I10,
`tie_shape` at field reads, `index` coordinates. Must not: use anything one
host lacks. Acceptance: I2's, I3's and I4's tests under both hosts' builds
of the frontend.

**U8. Columns.** Write set: `idr/lib/Transforms/Columns/*`. Outcome: the 1:N
conversion of destinations with results (§2.6). Acceptance: the array-of-
records programs unchanged.

**U9. Proposal 0009.** Write set: `proposals/0009-typed-apl/README.md`.
Outcome: §8, §16's stage-2 decision, §20 item 2 and "The MLIR form owed"
amended to what D43 makes. Acceptance: no sentence of 0009 contradicts P0.

## 6. Owner questions

**OQ1. Are an array's shape terms D48's index terms, one mechanism, at
least where a function's signature states them?** Today a dimension is
static or dynamic, and what Idris proved equal crosses calls through
`idr.tie_shape` with run-time sizes (`IdrArrayOps.td:454-476`). D48 gives a
function quantity-0 index parameters (`idr.func @map<n : nat>`), substituted
at calls; 0009 stage 2 plans static extents by keying specialization on a
refined tensor type at the call (`proposals/0009-typed-apl/README.md:307-321`).
Two keys for one fact (a size the call fixes) is what AGENTS.md forbids.
- *A. One key*: a signature records, for each dynamic dimension of an array
  argument or result, its index term; the specializer substitutes D48's
  index arguments and the clone's tensor types become static where the term
  becomes a constant; inside a function, equalities stay `tie_shape`'s (MLIR's
  tensor type has no symbolic dimension, and value bounds needs SSA sizes).
  Costs: a part of `idr.func`'s signature property and of the family
  attribute's field shapes; the frontend writes index terms for array
  dimensions. Buys: 0009 stage 2's key never built; equal sizes across calls
  by substitution, not by a run-time tie.
- *B. Two mechanisms*: D48's indices for families, tensor casts at calls for
  arrays (0009 stage 2 as written). Costs: two specialization keys for one
  fact. Buys: no change to the signature's shape.
- *C. Arrays as a family-like type of ours with symbolic dimensions*: loses
  every upstream tensor, linalg and bufferization mechanism (0009's ruling:
  "a shape is a ranked tensor type").
Recommendation: A. Array extents are run-time values ("erased does not mean
constant"), so they can never be D48's compile-time indices alone; but where
a signature names a size by an index variable, that variable is the one key.

**OQ2. Is `LArray`'s in-place promise (and `Linear.Vec`'s) D24's?** The
library promises a linear array is written in place
(`libs/mlir-array/Array/Core.idr:94-99, 213-216`); today One-Shot keeps the
promise and a copy at a link is an internal error (`Linear.cpp:13-22`). D24
promises in-place rebuilding for types of kind `in_place` (`LList`, `LNat`),
bound by exclusivity proved at every call.
- *A. One promise*: `LArray` and `Vec` are `in_place` types; their values
  carry the exclusive linear grade by construction (§3.2's theorem), so the
  exclusivity analysis always succeeds for them; bufferization reads the
  grade (I9), and `Vec`'s cell is rebuilt in place by D24's rule. Costs: the
  registry gains two `InPlaceType` entries; a program that defeats the
  closed world with an escape hatch meets `unsupported (uniqueness)` instead
  of an internal error. Buys: one mechanism for "written in place", I1's
  writable rule and I8's moves decided by a type.
- *B. Two promises*: `LArray`'s stays One-Shot's link check, D24's stays
  counting's. Costs: two statements of one promise, `isLink`'s search kept
  in some form. Buys: D24's list unchanged.
Recommendation: A.

## Handoff

File: `audits/p0/verify/L12-arrays.md`. Checks run: none (reading, `grep`,
`wc`, `git` only); no file but this one written.
