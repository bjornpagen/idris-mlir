# U10 — Lowering memrefs from bufferization, one function at a time, names from content

## Permitted outcome
1. Mandatory. idr-lower lowers every memref value and op C16 §2 admits,
   with the component list of C16 §3 (the cell, then the dynamic offset,
   sizes and strides; the aligned pointer is always the cell plus 16 and
   never held),
   for any rank, static or dynamic dimensions, identity or strided
   layout: `memref.alloc` to `idris_rt_array_new` with the saturating
   product (C16 §4.1), `memref.dim` (§4.3), `memref.load` and
   `memref.store` of elements of ours by their slots, a load taking no
   reference (C14 §3) and a store releasing the old element (§4.4),
   `memref.copy` to one memcpy or to `idris_rt_memref_copy` (§4.5), views
   through upstream's expansion and our patterns on components, and
   `memref.transpose` (§4.6), `idr.tie_shape` dropped (§4.7), linalg and
   word accesses left for upstream with a source materialization (§4.8),
   `idr.nat.to_extent` (§4.10).
2. Mandatory. The world-ordered `idr.array.new`, `get`, `set` and the
   buffer ops lowered on the new components, one slot path for every
   element (C16 §4.9).
3. Mandatory. Constants as immortal `memref.global`: one static cell,
   its header in front of its data, `memref.get_global` as its address
   (C16 §4.2; 0003 D23 as the coordinator amended it).
4. Mandatory. Static data named from content, `__idr.<kind>.<16 hex>`,
   keyed as C16 §7 says, with the collision check where a name is
   interned; `@__idr_release_cafs` lists the memo cells in name order.
5. Mandatory. The conversion runs per function in parallel with
   per-worker copies of the converter, the target, the patterns and the
   `Runtime`; declarations and static data are merged into the module
   after it, in name order; the output does not depend on the thread
   count (C16 §6, §8).
6. Mandatory. Identified types read in place of declarations: every read
   of `DataOp`, `CtorOp`, `lookupData`, `lookupCtor`, `declarationOf`,
   `listCons`/`listElement` on a declaration, `closureLabel` and
   `isMemo(DataOp)` in `lib/Conversion` becomes a read of C01's type;
   `idr.con`'s stack fact read from C02's inherent property (C16 §9).
7. Mandatory consumer adaptations: the D28 removal of the program mark's
   handling at the end of idr-lower; `Passes.h` unchanged; the
   `Runtime` and `StaticData` interfaces changed for item 5.

## Owner / exclusive writes
- `IDR/Conversion` (`foreign/idr/lib/Conversion`): every unit. New:
  `Memrefs.cpp` (the ops on buffers) and `StaticNames.cpp` (the names of
  static data). Changed: `Lower.cpp`,
  `Arrays.cpp`, `Buffers.cpp`, `Runtime.cpp`, `StaticData.cpp`,
  `Cells.cpp`, `Counting.cpp`, `Matches.cpp`, `Force.cpp`, `Facts.cpp`,
  `Strings.cpp`, `RuntimeCalls.cpp`, `Bigs.cpp` (`idr.nat.to_extent`).
  Unchanged unless a C01 accessor forces it: `Checks.cpp`, `Scalars.cpp`, `Entry.cpp`,
  `Fields.cpp`, `FuncToFunc.cpp`, `Mangle.cpp`, `Words.cpp`, and the tail
  call units (`TailCalls.cpp`, `TailCallPlan.cpp`, `TailPosition.cpp`,
  `Frame.cpp`, `ReturnRegisters.cpp`, `PassThroughMemory.cpp`). Deleted:
  the units `## Delete` names.
- `INC/Conversion` (`foreign/idr/include/idr/Conversion`): new
  `Arrays.h` (the descriptor of a memref and its helpers, internal to
  the lowering); changed `Runtime.h`, `StaticData.h`, `Patterns.h`,
  `Matches.h`, `Facts.h`; the headers `## Delete` names go.

**Excluded:** `foreign/idr/lib/CMakeLists.txt` (the `IdrConversion`
source and link lists: the coordinator's build list; report the change);
`include/idr/Transforms/Passes.td` (U06, C12: idr-lower's
`dependentDialects` and description, C16 §1); `include/idr/IR/Layout.h`,
`lib/IR/Layout/*`, `lib/IR/Grades.cpp`, `include/idr/IR/Grades.h`,
`include/idr/IR/Symbols.h`, `lib/IR/Symbols.cpp` (U01, C01: the
components of a memref and `isArray`, C16 §3; the identified types);
`include/idr/IR/IdrArrayOps.td`, `lib/IR/OpsArrays.cpp` (U11, C11:
`idr.tie_shape` and the world-ordered ops); `lib/Transforms/Bufferize`
(U12, C15); `lib/Transforms/Ownership` (U08, C14); `runtime/` (U19,
C17); `tests/idr` (U17, C24); `lib/Transforms/Pipeline.cpp` (U06).

## Read first
- `contracts.md` (or `contracts/` until it exists): C16 in full; C17 §1
  to §7; C15 §3, §4.5, §7; C12 §2 rows `IdrLower`, `IdrEntry`,
  `IdrTailCalls` and §3 rows 17 to 26; C01 (identified types, `Layouts`);
  C02 (`idr.con`'s `stack`); C11 (`idr.tie_shape`, the world-ordered
  ops); C21 (the C++ name function); C14 (counting on memrefs).
- 0004 `README.md` §4 stages 12 and 13 (lines 963-976), §5.3 items 2 and
  3 (1103-1127), §6's rows "Names from counters", "`idr.stack` as a
  discardable attribute", "`idr.program` as a discardable attribute" and
  the lookup row (1236-1320), D18, D28, D29, D41 (1531-1844).
- 0003 `README.md` §4.5 (791-846), §8 (1125-1258), §12 (1429-1461), §13
  (1463-1483), §15 (1506-1529), D17, D23, D24, D40, D42.
- `foreign/idr/lib/Conversion/Lower.cpp` (all: 105-167 the conversion,
  172-221 the phases), `Arrays.cpp` (all), `Buffers.cpp`, `Runtime.cpp`
  (55-118, 161-197), `include/idr/Conversion/Runtime.h`,
  `StaticData.cpp` (all) with its header, `Cells.cpp` (29-103, 128-163,
  238-249), `Counting.cpp` (26-56, 63-187), `Matches.cpp` (41-94),
  `Force.cpp` (32-101), `Facts.cpp` (70-102), `Strings.cpp` (100-175),
  `RuntimeCalls.cpp` (25-124), `IdrPattern.h`, `Words.cpp`, `Entry.cpp`.
- `foreign/idr/include/idr/IR/Layout.h` (69-104, 128-178, 229-295),
  `lib/IR/Layout/Components.cpp` (79-128), `lib/IR/Layout/Layouts.cpp`
  (155-200), `lib/IR/Grades.cpp` (174-199), `include/idr/IR/IdrArrayOps.td`,
  `include/idr/IR/IdrIOOps.td` (69-199), `runtime/idris_rt.h` (26-60,
  152-212, 299-337), `runtime/Rc/Freeing.cpp` (32-113).
- Upstream: `M/lib/Conversion/MemRefToLLVM/MemRefToLLVM.cpp` (940-960
  get_global, 1142-1280 copy), `M/include/mlir/Dialect/MemRef/Transforms/Transforms.h:55-71`,
  `M/lib/Dialect/MemRef/Transforms/ExpandStridedMetadata.cpp:187-260,
  1071-1105`, `M/include/mlir/Conversion/LLVMCommon/MemRefBuilder.h`,
  `M/include/mlir/Transforms/DialectConversion.h` (190-240, 375-395,
  1515-1540), `M/include/mlir/IR/Threading.h:30-95`,
  `M/include/mlir/Dialect/LLVMIR/LLVMOps.td:1327-1400` (addressof) and
  `:880-920` (call builders by name), `LLVMIntrinsicOps.td:287, 847`
  (memcpy, umul.with.overflow).
- `proposals/0004-compile-time/array-drafts.json` entry 3 (the earlier
  lowering draft): its descriptor representation and its tests hold; its
  `useArrayCells` hook, its element-loop copy and its upstream patch
  number do not (C15 and C17 decide them).

## Fixed decisions
- The component list of a memref is C16 §3, whatever the element: the
  cell, then the dynamic offset, sizes and strides. The descriptor of a
  memref inside the lowering is `struct Descriptor { Value cell;
  OpFoldResult offset; SmallVector<OpFoldResult> sizes, strides; }` in
  `include/idr/Conversion/Arrays.h`, with `unpack(b, loc, type,
  components)`, `pack(b, loc, type, descriptor)`, `elementsOf(b, loc,
  cell)` (cell + `sizeof(idris_rt_array)`, the aligned pointer wherever
  an op needs one), `elementAddress(b, loc,
  descriptor, indices, stride)` and `toMemref(b, loc, runtime, type,
  components)`; they are defined in `Arrays.cpp`. `Arrays.cpp` is the one
  unit that includes the array cell's layout.
- The division of work is C16 §4's rule: upstream keeps word
  `memref.load`/`store` and linalg over words; idr-lower lowers every
  other memref op. Phase 2's target: the memref dialect illegal but
  `memref.load` and `memref.store` of a word; linalg dynamically legal
  when every memref operand holds words; `affine` legal;
  `applyFullConversion` per function.
- `memref.copy` is C17 §4's: memcpy for a slot-free element with both
  types contiguous by upstream's rule, `idris_rt_memref_copy` otherwise,
  the two descriptors in two slots of the function's entry block.
- Views: phase 1 applies `memref::populateExpandStridedMetadataPatterns`
  to each function with `applyPatternsGreedily`, folding, constant CSE and
  region simplification off; phase 2 lowers `reinterpret_cast`,
  `extract_strided_metadata` and `cast` on components.
- Per-function work: after phase 0 the module's `func.func` ops, in
  module order, are cut into K contiguous runs, K the context's thread
  count (1 without threading, never more than the functions);
  `failableParallelForEach` runs the runs, each building its own `Worker {
  TypeConverter; ConversionTarget; FrozenRewritePatternSet; Runtime; }`
  and lowering its functions in order. No claim, no flag, no atomic.
- `Runtime` holds the module, the frozen `Layouts`, its own
  `LLVMTypeConverter`, its `StaticData`, and its additions: a
  `llvm::StringMap<LLVM::LLVMFunctionType>` of functions called and an
  owned scratch `ModuleOp` holding the globals it wrote. It holds no
  symbol table: no pattern reads one. `Runtime::call`
  records the callee and builds the call by name; it never touches the
  module. `static LogicalResult Runtime::merge(ModuleOp module,
  ArrayRef<Runtime *> workers)` is the serial step of C16 §8: it declares
  the called functions in name order (an internal error on two types for
  one name), moves one global per name into the module in name order
  after the declarations (an internal error on two contents for one
  name), and builds `@__idr_release_cafs`. `Runtime::finish` goes.
- `StaticData` names each datum by C16 §7's key through C21's
  `ContentNames`, keeps each global with its key for the merge's check
  across workers, writes globals at the module's location into the
  worker's scratch module, and keeps the `caf` names. Its `globals`
  counter goes.
- The memo sums a force reads are one table, `Memos` (in `Patterns.h`),
  read by `readMemos(module, symbols)` after phase 0 and before the
  parallel step, from C01's types and the label functions' signatures;
  every worker's force pattern reads it.
- `memref.global` lookup for `memref.get_global`: a read-only
  `llvm::DenseMap<StringAttr, memref::GlobalOp>` built before the
  parallel step; the globals are erased after it.
- Facts (`Facts.cpp`) are read before phase 0 and applied after the
  merge, serially, as today.
- No pass option, no flag, no fallback path, no counter in a name.

## Inputs
- C01: the identified data type, its constructors by name (tag, field
  types, `by_name`), its kind (plain, closures, memo), the memo states,
  the registry's role (the list's cons), the constructor count;
  `Layouts::components`, `counted`, `element`, the box cell and the sum
  layout keyed as C01 keys them; `isArray` and `isFieldType` as C16 §3
  states.
- C02: `idr.con`'s inherent `stack` property; every op that names a
  constructor gives `getDataType()` and `getTag()` (`idr.match`:
  `getCaseTag(i)`); no `idr.program`.
- U01's ownership ops `idr.own.adopt` and `idr.own.give` (C++
  `OwnAdoptOp`, `OwnGiveOp`), each its operand.
- C11: `idr::TieShapeOp` (source operand 0, result of the source's type);
  `idr::NatToExtentOp` (`getNatural()`, `getCrashCause()`); the world
  memory space `#idr.world` on world-ordered memrefs;
  `idr.array.new`, `idr.array.get` (`moves`), `idr.array.set` with
  `getArrayType()`, `getSizes()`, `getFill()`, `getIndices()`,
  `getValue()`, `getMoves()`.
- C15: the output of C15 §7 (`memref.alloc` with no alignment,
  `memref.copy`, upstream's views, constant `memref.global`, no tensor or
  bufferization op).
- C17: `idris_rt_array_new (i64, i32) -> ptr`, `idris_rt_memref_copy
  (i64, ptr, ptr)`, the header `{0, info, N}`, the buffer entry points'
  parameters, the table of §7.
- C21: the C++ function that names content: owner and key bytes to
  `<owner>.<16 lowercase hex digits>`, the low 64 bits of XXH3-128.
- C12: idr-lower at row 18 with C16 §1's `dependentDialects`; rows 19 to
  26 after it.
- C14: the counting C16 §5 lowers.

## Outputs
- C16, the lowering contract (`contracts/C16-lowering.md`): the
  memref components, what idr-lower accepts, what each memref op means
  after it, the counting it implements, the runtime calls it makes, the
  names of static data, the per-function conversion and its determinism.
- Consumers: U01 (C16 §3 in `Layouts`), U06 (§1), U07 (§7), U08 (§5),
  U11 (§4.7, §4.9), U12 (§2, §4), U17 (§10), U19 (§3, §4).

## Implement
- `include/idr/Conversion/Arrays.h` and `Arrays.cpp`: the `Descriptor`
  and its helpers (above); then the patterns: `LowerAlloc` (§4.1),
  `LowerGetGlobal` (§4.2), `LowerDim` for every memref (§4.3),
  `LowerElementLoad` and `LowerElementStore` for elements of ours
  (§4.4), `LowerCopy` (§4.5), `LowerReinterpretCast`,
  `LowerExtractStridedMetadata`, `LowerCast` (§4.6),
  `LowerTranspose` (§4.6), `LowerAsItself<TieShapeOp>` (§4.7), and the
  world-ordered
  `LowerArrayNew` and `LowerArrayAccess` rebuilt on `Descriptor` with one
  slot path (§4.9). The element address is one helper used by every
  access. `populateArrayPatterns` registers them all.
- `Memrefs.cpp` (new): `LowerDim`, `LowerElementLoad`, `LowerElementStore`,
  `LowerCopy`, the view patterns and `toMemref`, registered by
  `populateMemrefPatterns`; `Arrays.cpp` keeps the descriptor, the
  shared element helpers, the cells (allocation, constants) and the arrays
  a world orders.
- `StaticNames.cpp` (new): `StaticData`'s keys and interning (`intern`,
  `cellKey`, `fieldKey`, `boxName`, `runNames`, `kindOf`, `printed`).
- `Buffers.cpp`: the byte address from the cell's first element.
- `RuntimeCalls.cpp`: a memref operand passed as its cell, its first
  element (computed at the call) and its other components (C17 §6).
- `Bigs.cpp`: `LowerNatToExtent` (C16 §4.10) beside the other small-word
  patterns.
- `Lower.cpp`: phase 0 serial; the map of `memref.global`; the workers;
  per function: matches, view expansion, conversion; then
  `Runtime::merge`, the erasure of every `memref.global`, the facts. The
  type converter converts every memref through `Layouts::components`
  (and every idr type as today); its one source materialization is
  `toMemref`, for word memrefs, null otherwise. Delete the program mark's
  removal (D28) and the legality of the declaration ops (D29).
- `Runtime.cpp`, `Runtime.h`: the additions, `call` by name, `merge`;
  `crash` through the message datum; no symbol table.
- `StaticData.cpp`, `StaticData.h`: C16 §7's keys and names; the
  constant's one cell (§4.2); the scratch module; the `caf` list by name.
- `Cells.cpp`, `Counting.cpp`, `Matches.cpp`, `Force.cpp`, `Facts.cpp`,
  `Strings.cpp`: C01's reads (item 6). `Cells.cpp`'s stack cell reads
  C02's property. `Force.cpp` builds its memo table from the memo types
  the module's functions use, read from C01, before the parallel step.
- `RuntimeCalls.cpp`: unchanged flattening; the call by name.
- Failure paths: an internal error is emitted at the op as
  `internal error: idr-lower: ...` and fails the pass; `unsupported
  (layout)` stays the one refusal (C16 §4.1), carrying C04's rule as C04
  makes every refusal carry it.

## Delete
- `include/idr/Conversion/ArrayLoops.h`, `lib/Conversion/ArrayLoops.cpp`,
  `lib/Conversion/ArrayLoopReads.cpp` (`asMemref`, `viewed`,
  `readAsInputs`, `populateArrayLoopPatterns`) and the phase-1 loop block
  of `Lower.cpp:194-205` with its include.
- `include/idr/Conversion/ArrayView.h`, `lib/Conversion/ArrayView.cpp`
  (`arrayView`, the old `elementsOf`), replaced by `Arrays.h`.
- In `Arrays.cpp`: `wordView`, `elementAt`, the rank-1 `LowerDim`
  (`isRank1Array`), the word-view branches of the array ops (one slot
  path for every element).
- In `Buffers.cpp`: `byteAt` through the old `elementsOf`.
- In `StaticData`: the `globals` counter and the prefixes `__idr_msg_`,
  `__idr_caf_`, `__idr_box_`, `__idr_str_`, `__idr_big_`; the
  `(Attribute, Type)` map as the identity of a global (names are).
- In `Runtime`: `finish`, the declaration on first use into the module's
  symbol table.
- In `Lower.cpp`: the removal of `idr.program` (D28), the legality and
  erasure of `DataOp` and `CtorOp` (D29), the serial
  `applyPartialConversion`.
- In `Cells.cpp`: the read of `idr.stack` as a discardable attribute
  (`StackAttrHelper`).
- Every `lookupCtor`, `lookupData` and `DataOp`/`CtorOp` read in
  `lib/Conversion` (`Counting.cpp:71, 127`, `Cells.cpp:78, 137, 186`,
  `Matches.cpp:46-80`, `Force.cpp:77-91`, `Facts.cpp:80`,
  `StaticData.cpp:84, 110`, `Strings.cpp:111, 165`).
- The retired names this lane removes from the tree: `ArrayLoops`,
  `ArrayLoopReads`, `ArrayView`; nothing in `lib/Conversion` may name
  `idr-in-bounds`, `idr-vectorize`, `prim__index` or `prim__arraySize`
  after the lane.

## NOT TO DO
- Do not write `Layouts`, `isArray` or any file of `lib/IR` (U01): if
  C16 §3 is not yet in `Components.cpp`, report the seam.
- Do not add a hook into One-Shot (`allocationFn`, `memCpyFn`): C15 keeps
  upstream's defaults and this lane gives their ops their meaning.
- Do not write an element loop for `memref.copy` in compiled code: the
  copy that counts is `idris_rt_memref_copy` (C17 §4).
- Do not keep a word path beside the slot path in the world-ordered ops,
  a second copy of the address formula, or a target materialization.
- Do not declare runtime functions into the module while converting, and
  do not insert globals into the module from a worker.
- Do not hash with `llvm::xxh3_128bits` here or anywhere in this lane:
  the name function is C21's, one copy.
- Do not keep an option to run the conversion serially, a thread count
  that changes output, or a fallback to `applyPartialConversion`.
- Do not edit `Passes.td`, `Pipeline.cpp`, the CMake lists, the runtime
  or the tests; report what they need.
- Do not lower linalg over elements of ours, nor accept a tensor or a
  bufferization op: those are other stages' invariants.

## Tempting partial solutions
- Carrying the aligned pointer as a component beside the cell: it is
  always the cell plus 16, a constant's too (C16 §4.2), so it would be one
  fact held twice; rejected by C16 §3's component list, which `Layouts`
  implements, and by `unpack`'s check that it consumes every component.
- Leaving `memref.alloc`, `memref.copy` or `memref.get_global` to
  `convert-to-llvm`: rejected by §10's check that no `malloc`,
  `memrefCopy` or `0xdeadbeef` is in a lowered module.
- Naming static data by a hash of the requesting op or by insertion
  order with a final sort: rejected by §10's two-function module holding
  one `__idr.str.` global and by determinism at 1, 2 and 8 threads.
- Naming a run's interior cells by position from the head: rejected by
  the memo-cell rule (a shared suffix of memo labels is one cell, or a
  force runs twice; `tests/idr/lower/static-thunk.mlir`).
- A mutex around the module's symbol table instead of per-worker
  additions: rejected by determinism (declarations and globals would land
  in schedule order) and by the rule that no worker touches the module.
- Lowering `idr.array.get` of words through `memref.load` again: two
  addressings of one cell; rejected by the review condition below.
- Handling `idr.data` declarations as legal ops and erasing them: they no
  longer exist (D29), and the build fails on them.

## Acceptance
- `python3 proposals/0004-compile-time/check-units.py` on every changed
  `.cpp` of `lib/Conversion` reports 0 failing, or each failure is a
  missing declaration of C01, C02, C11 or C21, listed in the handoff with
  the contract that declares it.
- Review: `grep -rn 'lookupCtor\|lookupData\|DataOp\|CtorOp\|StackAttrHelper\|ProgramAttrHelper\|isRank1Array\|wordView\|arrayView\|globals++' foreign/idr/lib/Conversion foreign/idr/include/idr/Conversion`
  finds nothing; no file named in `## Delete` exists; no pattern calls
  `SymbolTable::insert` or `LLVM::LLVMFuncOp::create`;
  `StaticData::global` builds every name through C21's function; every
  memref op of C16 §2 but word `load` and `store` has a pattern in
  `Arrays.cpp`.
- The owner's machine (NotRun here): `make build`, `make test-idr` with
  U17's fixtures of C16 §10, `make test`, `tests/determinism` at 1, 2
  and 8 threads, `make test-mlir-tools`.

## Stop and return
- Deliverable: the changed and deleted files under `IDR/Conversion` and
  `INC/Conversion`, check-units output, the handoff of the common
  obligations.
- Report without stopping: the build list change for
  `foreign/idr/lib/CMakeLists.txt` (remove the three units `## Delete`
  names; link `MLIRMemRefTransforms`, `MLIRMemRefUtils`,
  `MLIRAffineDialect`); C12's `dependentDialects` row
  for `IdrLower`; any C01, C02, C11 or C21 declaration the code needs
  that the contracts do not give, with the file and line that needs it.
