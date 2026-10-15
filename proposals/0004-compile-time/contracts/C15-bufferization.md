## C15 The bufferization pass and its interface models

Producer: U12. Paths are under `foreign/idr/` unless named; `M/` is the
pinned MLIR, `.toolchain/build/llvm-project/mlir/`. Line numbers are the
tree at a3e61f3a and the pinned MLIR. Decided by 0003 §8 (D17, D18, D33,
D42, D43) and 0004 §4 stage 10; every choice below is fixed.

### 1. What the pass is

`idr-bufferize` is One-Shot Bufferize on the whole program, on `idr.func`,
once, in 0003's arrays stage (C12 row 9), before counting. It runs
upstream's module driver, as generalized to `FunctionOpInterface` by C18,
through its public steps (`M/lib/Dialect/Bufferization/Transforms/OneShotModuleBufferize.cpp:617-652`
written out), with external `BufferizableOpInterface` models of ours for
the idr ops that hold tensors. Before it, arrays are tensor values; after
it, no tensor type is left anywhere in the module (no value, no function
type, no type nested in another type), and no `bufferization` op is left.

The pass definition (U06 writes it in `Passes.td`, as C12 section 2 lists
it):

```tablegen
def IdrBufferize : Pass<"idr-bufferize", "::mlir::ModuleOp"> {
  let summary = "Put every array in a buffer, in place wherever the program allows";
  let dependentDialects = [
    "::mlir::bufferization::BufferizationDialect",
    "::mlir::memref::MemRefDialect", "::mlir::linalg::LinalgDialect"
  ];
  let statistics = [
    Statistic<"numAllocs", "allocs", "Buffers allocated">,
    Statistic<"numInPlace", "in-place", "Tensor operands bufferized in place">,
    Statistic<"numCopies", "copies", "Tensor operands bufferized out of place">,
  ];
}
```

No option. The description is U06's text and must say: a buffer is a cell
of the runtime (`memref.alloc`), a copy is the runtime's counted copy
(`memref.copy`); a linear array's thread is written in place, always; a
copy at a link of a thread is an internal error.

### 2. The header

`include/idr/Transforms/Bufferize.h` (new, U12), exactly these
declarations:

```cpp
#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/Operation.h"
#include "mlir/Pass/Pass.h"

namespace idr {

#define GEN_PASS_DECL_IDRBUFFERIZE
#include "idr/Transforms/Passes.h.inc"

namespace bufferize {

// The bufferization models of the idr ops that hold tensors, and of
// ub.poison, which upstream gives none.
void registerModels(mlir::DialectRegistry &registry);

// Whether `op` copies an array because a write could not be in place: a
// memref.copy into a cell allocated for it (One-Shot's copy before a
// conflicting write, or a reallocation to a cell's layout). A memref.copy
// into a view of a live buffer is the meaning of the op it came from
// (tensor.insert_slice), not such a copy.
bool copies(mlir::Operation *op);

} // namespace bufferize
} // namespace idr
```

- The constructor is the generated `idr::createIdrBufferize()`; the base
  is `idr::impl::IdrBufferizeBase<Derived>`; the unit holding
  `GEN_PASS_DEF_IDRBUFFERIZE` is `lib/Transforms/Bufferize/Bufferize.cpp`.
- `registerModels` adds two extensions to `registry`: one on
  `idr::IdrDialect` attaching the models of section 4, one on
  `mlir::ub::UBDialect` attaching the `ub.poison` model. Each extension is
  a function pointer, so a registry that already holds it is unchanged
  (`DialectRegistry::addExtension`, and `MLIRContext::appendDialectRegistry`
  returns early on a subset, `M/lib/IR/MLIRContext.cpp:425-439`).
- The pass's `getDependentDialects` calls the generated one and then
  `registerModels`. The pass manager appends every dependent registry of
  the whole pipeline before it runs (`M/lib/Pass/Pass.cpp:1054-1055`), so
  the models are attached for C12 row 8 (`eliminate-empty-tensors`) too.
  No tool calls `registerModels`; upstream's models (arith, tensor, scf,
  linalg, cf, bufferization) come from `registerAllExtensions`, which all
  three tools call (`tools/idris-mlir-opt.cpp:51`,
  `tools/idris-mlir-reduce.cpp:22`, `lib/Driver/Run.cpp:272`).
- `copies(op)` is exactly: `op` is a `memref::CopyOp` whose target is the
  result of a `memref::AllocOp`. Consumer: U17's `in-place` property
  (C24).

Internal to U12 (no other lane includes them): `lib/Transforms/Bufferize/Models.h`
and the units `Bufferize.cpp`, `Functions.cpp`, `Linear.cpp`, `Data.cpp`,
`Values.cpp` (section 6).

### 3. The options and the steps

`runOnOperation` builds one `mlir::bufferization::OneShotBufferizationOptions`:

| Field | Value | Why |
| --- | --- | --- |
| `bufferizeFunctionBoundaries` | `true` | the module driver and the boundary models |
| `setFunctionBoundaryTypeConversion` | `LayoutMapOption::IdentityLayoutMap` | a buffer that crosses a call is a whole cell; sets `inferFunctionResultLayout = false` (`BufferizableOpInterface.cpp:467-487`), so the driver never folds result casts |
| `unknownTypeConverterFn` | `getMemRefTypeWithStaticIdentityLayout(cast<TensorType>(t), space)` | a new buffer is a cell; upstream's default is a fully dynamic layout (`:404-410`) |
| `bufferAlignment` | `0` | `memref.alloc` carries no `alignment` (`:362-371`); the cell's header fixes element alignment at 8 (C17 §3) |
| `allocationFn` | upstream's default (`memref.alloc`) | a buffer is the runtime's cell: C16 lowers `memref.alloc` to `idris_rt_array_new` (C17 §3), whose counted slots start empty. No op of ours: upstream has the allocation. The owned grade a fresh cell takes in counting is counting's vocabulary (C14), as a counted store's is |
| `memCpyFn` | upstream's default (`memref.copy`) | a copy is the runtime's counted copy: C16 lowers `memref.copy` to `idris_rt_memref_copy` (C17 §4), counted by the element type, so one path for counted elements (D17) |
| `allowReturnAllocsFromLoops` | `true` | a loop that yields a new buffer is the program's; refusing it would make acceptance the optimizer's |
| `allowUnknownOps`, `copyBeforeWrite`, `testAnalysisOnly` | `false` (defaults) | every op with tensor semantics has a model; the analysis runs |
| `analysisHeuristic` | `BottomUp` (default) | upstream's |
| every other field | default | |

No ownership-based deallocation runs, and none is added to any pipeline:
counting frees cells (D18), and that scheme refuses a returned memref
aliasing an argument (`M/docs/OwnershipBasedBufferDeallocation.md:55-70`).
No `bufferization.writable` or `bufferization.buffer_layout` attribute is
written: the models answer from types (section 4).

The steps, in order:
1. `OneShotAnalysisState state(module, options)`; under a
   `ScopedDiagnosticHandler` that keeps each error it is given,
   `analyzeModuleOp(module, state, &statistics)`.
2. On failure, the internal error of section 5, then
   `signalPassFailure()`.
3. The copy remarks of section 5.
4. `insertTensorCopies(module, state, bufferizationState)` and
   `bufferizeModuleOp(module, options, bufferizationState, &statistics)`,
   under the same handler; a failure is section 5's internal error.
5. The retyping (D42, section 4.6): `idr::DataRemap remap(module,
   "buffers", leaf)` (C01 §7) with the leaf map `RankedTensorType t ->
   B(t)` and nothing for every other type, then `remap.retype(module)`.
   The leaf is a named local that outlives `remap`, which holds it as a
   `function_ref`.
6. `numAllocs`, `numInPlace`, `numCopies` add
   `BufferizationStatistics::numBufferAlloc`, `numTensorInPlace`,
   `numTensorOutOfPlace`.

### 4. The models

Every model is an external model attached by `registerModels`. "Tensor"
below is a `TensorLikeType` value; "wrapped" is `!idr.lin<tensor<...>>`,
which is no tensor to One-Shot (`idr::QType` does not implement
`TensorLikeType`, 0003 §8). The buffer type of a tensor type `T`, written
`B(T)`, is `getMemRefTypeWithStaticIdentityLayout(T)`: shape and element
of `T`, identity layout, no memory space; the cell's layout.

#### 4.1 `idr.func`, `idr.call`, `idr.return`

Shaped on upstream's `FuncBufferizableOpInterfaceImpl.cpp:162-535`.

- `idr.func`:
  `OpWithUnstructuredControlFlowBufferizableOpInterfaceExternalModel<FuncModel, idr::FuncOp>`;
  `supportsUnstructuredControlFlow()` true (contification and multi-block
  inlining make blocks). `hasTensorSemantics`: a tensor in its inputs,
  results, or the arguments of any block. `getAliasingOpOperands(bbArg)`:
  `getAliasingBranchOpOperands` (none for the entry block).
  `getBufferType(entry bbArg) = B(type)`; any other block argument is the
  template's (the reconciled types of what branches pass).
  `isWritable(bbArg)`: true, for every block: a plain tensor parameter is
  written in place by the callee and every caller copies where it still
  reads the argument, by the module analysis (upstream's convention).
  `bufferize`: inputs and results that are tensors become `B(T)`;
  `bufferizeBlockSignature` on every block; each `idr.return` operand that
  is a tensor becomes `bufferization.to_buffer` of `B(T)`; then
  `setFunctionType`. Wrapped types are left to step 5.
- `idr.call`: reads `func_ext::FuncAnalysisState` (C18) only when the
  state is a `OneShotAnalysisState` that has the extension and the
  callee's entry in `analyzedFuncOps` is `Analyzed`; otherwise, with no
  symbol lookup, `bufferizesToMemoryRead` and `bufferizesToMemoryWrite`
  are true and `getAliasingValues` is `detail::unknownGetAliasingValues`.
  So the model is exact on the module analysis and conservative under a
  nested, per-function analysis, where it reads no sibling. With the
  state: read and written from `readBbArgs`, `writtenBbArgs`; aliasing
  from `aliasingReturnVals` and `equivalentFuncArgs`, as upstream's
  `:195-226`. `getBufferType(result) = B(type)`. `bufferize`: tensor
  results become `B(T)`; each tensor operand is `getBuffer`, then
  `castOrReallocMemRefValue` to `B(T)` where its type differs; the new
  call is `idr::CallOp::create(rewriter, loc, types, operands,
  call.getProperties(), discardable attributes)`, so `callee`,
  `arg_attrs`, `res_attrs` and `effects` are kept;
  `replaceOpWithBufferizedValues`.
- `idr.return`: read, not written, no alias; `bufferize` does nothing
  (the function's model rewrites it).

#### 4.2 `idr.lin.enter`, a release; `idr.lin.use`

- `idr.lin.enter`: its tensor operand is read and written, with no
  aliasing value (it makes no tensor). One-Shot therefore copies there
  exactly when the operand's buffer is read after the enter or is not
  writable. `mustBufferizeInPlace(operand)` is the link test below.
  `bufferize`: `getBuffer`, `castOrReallocMemRefValue` to `B(T)` where the
  layout differs (a thread's buffer is a whole cell, so a link never
  reallocates), then `idr::LinEnterOp::create(rewriter, loc,
  idr::linear(B(T)), buffer)` replacing the op.
- **The link test**, the in-place promise of `LArray` (D33): the enter is
  a link when `state.findValueInReverseUseDefChain(&operand, isUse, config)`
  is not empty, where `isUse(v)` is "`v` is the result of an
  `idr.lin.use`" and `config` is `TraversalConfig` with
  `alwaysIncludeLeaves = false` and `followEquivalentOnly = true`, every
  other field default. So the operand's buffer is one an `idr.lin.use`
  began, directly or through the destinations of the writes between them;
  a slice is not the thread's buffer. It reads only aliasing, which the
  models answer before any decision, as the analysis's constructor needs
  (`M/lib/Dialect/Bufferization/Transforms/OneShotAnalysis.cpp:173-183`).
  A head (an enter no use began: `withArray`'s fresh tensor, `thaw`'s
  argument) is a plain release.
- `idr.lin.use`: no tensor operand; its tensor result has no aliasing
  operand (a new root), `isWritable` true (the release that made the
  linear value made its buffer the thread's), `bufferizesToAllocation`
  false, `getBufferType = B(type)`. `bufferize`:
  `idr::LinUseOp::create(rewriter, loc, B(T), linear)`,
  `replaceOpWithBufferizedValues`.

The tensor promise is held by the wrapper type alone; no attribute or
option records it. C14's promise (cells, checked by idr-demand) is the
other representation, and neither is held twice.

#### 4.3 Cells: `idr.con`, `idr.field`, `idr.force`

- `idr.con`: each tensor operand is read and written, with no alias: a
  store into a cell is a release. `bufferize`: each tensor operand is
  `getBuffer`, `castOrReallocMemRefValue` to `B(T)` where it differs (a
  cell holds a whole cell), set in place with `modifyOpInPlace`.
- `idr.field`, `idr.force`: a tensor result is a read from the heap, as
  `bufferization.to_tensor ... restrict`: no aliasing operand,
  `isWritable` false (a write to it copies), `bufferizesToAllocation`
  false, `getBufferType = B(type)`. A wrapped result is no tensor; its
  `idr.lin.use` makes the writable root (D33's `restrict writable`).
  `bufferize`: a clone of the op whose result has type `B(T)`,
  `replaceOpWithBufferizedValues`.

#### 4.4 Matches: `idr.match`, `idr.match_lit`, `idr.yield`

Shaped on upstream's `scf.index_switch` and `scf.yield` models
(`M/lib/Dialect/SCF/Transforms/BufferizableOpInterfaceImpl.cpp:321-428, 1127-1202`).

- `idr.match`, `idr.match_lit`: `getAliasingOpOperands(result i)` is the
  operand i of each region's `idr.yield`, `Equivalent`, definite only when
  one region ends in `idr.yield` (a case that crashes ends in
  `ub.unreachable`, `lib/IR/OpsMatch.cpp:25-33`, and gives no value). A
  match no case of which yields gives its result the type `B(T)`. A region's block argument (a bound field) is a
  read from the heap: no aliasing operand, `isWritable` false,
  `getBufferType = B(type)`. `getBufferType(result)` reconciles the
  yields' buffer types with `options.reconcileBufferTypeMismatchFn`.
  `bufferize`: `rewriter.cloneWithoutRegions(*op)` with tensor results
  retyped, the regions moved with `inlineRegionBefore`,
  `bufferizeBlockSignature` on each region's block,
  `replaceOpWithBufferizedValues`.
- `idr.yield`: read, not written; `getAliasingValues(operand i)` is the
  parent's result i, `Equivalent`, definite only when one region of the
  parent ends in `idr.yield`; `mustBufferizeInPlace` true (upstream's reason: no allocation
  yielded where none is needed). `bufferize`: each tensor operand is
  `getBuffer` cast with `options.castFn` to the parent result's buffer
  type; `replaceOpWithNewBufferizedOp<idr::YieldOp>`.

#### 4.5 Values: `idr.tie_shape`, `ub.poison`

- `idr.tie_shape` (C11's op): its tensor operand is neither read nor
  written and aliases the result, `Equivalent`, definite;
  `getBufferType(result)` is the operand's. `bufferize`: a clone with
  operand 0 the operand's buffer and result 0 of that buffer's type, the
  dims unchanged (0003 §8: the same op on the memref, so value bounds
  still relate dimensions; idr-lower drops it, C16).
- `ub.poison` with a tensor result (upstream registers no model, and
  RemoveDeadValues, C12 row 5, leaves one where a kept op used a dead
  value, `M/lib/Transforms/RemoveDeadValues.cpp:199-215`): no aliasing
  operand, `isWritable` true, `resultBufferizesToMemoryWrite` false (its
  contents are undefined), `bufferizesToAllocation` false,
  `getBufferType = B(type)`. `bufferize`: `ub.poison` of `B(T)`. No
  allocation and no copy: a dead value's buffer is never read or written.

No other idr op takes or makes a plain tensor (C01, C11); one that did
would make One-Shot fail with "op was not bufferized", an internal error.

#### 4.6 The retyping (D42)

Wrapped values, and data types whose bodies hold tensors, are no tensors
to One-Shot, whose block-signature rewrite converts tensor-like arguments
only (`M/lib/Dialect/Bufferization/Transforms/Bufferize.cpp:402-449`).
Step 5 retypes the whole module once with the leaf map `T -> B(T)` on
ranked tensor types, through C01's `DataRemap` of kind `"buffers"`: every
`!idr.lin<tensor<S x E>>` becomes `!idr.lin<memref<S x E>>` (op results,
block and region arguments, function types), and every identified data
type whose body holds a tensor becomes a new identified type with the
converted body, named `contentName(old name, "buffers", key)` (C01 §7,
C21). During steps 1 to 4 a wrapped value may already carry
`!idr.lin<memref>` while its users still say `!idr.lin<tensor>`; the
module is consistent again at the end of step 5, and the verifier runs
after the pass, never inside it.

### 5. Failure paths and remarks

- Every analysis, copy or bufferization failure is an internal error: no
  program reaches one (an `LArray` aliases nothing by the library's
  construction, 0003 §3.8). The handler re-emits each error it kept at
  its location as `internal error: idr-bufferize: ` followed by upstream's
  message and notes. Never `unsupported`, and no refusal rule (C04).
- A link whose operand's buffer is read after its release fails
  upstream's pre-analysis check, "not bufferizable under the given
  constraints: cannot avoid RaW conflict"
  (`OneShotAnalysis.cpp:1540-1552`). Then the error is emitted at the
  link instead: for each link in module order whose operand has a use by
  an op the link properly dominates (`DominanceInfo` of its function) and
  that reads the operand (`state.bufferizesToMemoryRead`), `internal
  error: idr-bufferize: the linear array released here is read after its
  release: <upstream's message>` at the link, with a note `read here` at
  each such use. Where no link has such a use, upstream's error is
  re-emitted as above. So the error names the write and the conflicting
  read, and One-Shot's own conflict.
- After a successful analysis, for each `idr.call` tensor operand that is
  not in place (`!state.isInPlace`) and whose callee is not `Analyzed`
  (it is on a cycle of calls with the caller, where upstream's driver
  assumes every operand read and written, `OneShotModuleBufferize.cpp:515-529`):
  `mlir::remark::missed(loc, RemarkOpts::name("Copy").category("idr-bufferize"))`
  with "the array is copied before this call: the callee is on a cycle of
  calls, whose analysis assumes it reads and writes every array it is
  given". A remark changes no output byte (observation, 0004 §6's kept
  list).

### 6. Files (U12's writes, ownership.json)

| Path | Holds |
| --- | --- |
| `include/idr/Transforms/Bufferize.h` | section 2 |
| `lib/Transforms/Bufferize/Models.h` | `B(T)` as `mlir::MemRefType idr::bufferize::bufferType(mlir::RankedTensorType)`, `cellType`, `boundaryType`, `cellBuffer`, `analyzedCallee`, `isLink`; `attachFunctionModels`, `attachLinearModels`, `attachDataModels`, `attachTieShapeModel`, `attachPoisonModel`, each `void (mlir::MLIRContext *)` |
| `lib/Transforms/Bufferize/Bufferize.cpp` | the pass (section 3, 5), `registerModels`, `copies`, `bufferType` |
| `lib/Transforms/Bufferize/Functions.cpp` | 4.1 |
| `lib/Transforms/Bufferize/Linear.cpp` | 4.2 |
| `lib/Transforms/Bufferize/Data.cpp` | 4.3, 4.4 |
| `lib/Transforms/Bufferize/Values.cpp` | 4.5 |

The build list (the coordinator's `lib/Transforms/CMakeLists.txt`): a
library `IdrBufferize` of the five units, linking `IdrIR`,
`MLIRBufferizationDialect`, `MLIRBufferizationTransforms`,
`MLIRMemRefDialect`, `MLIRLinalgDialect` (a dependent dialect),
`MLIRUBDialect`, `MLIRFunctionInterfaces`, `MLIRControlFlowInterfaces`,
`DEPENDS IdrOpsIncGen IdrPassesIncGen`, `EXCLUDE_FROM_LIBMLIR`,
`DISABLE_INSTALL`, `PARTIAL_SOURCES_INTENDED` as every idr pass library;
`IdrPipeline` links it, and through it the three tools.

### 7. What the output promises (for the passes after it)

- No tensor type, no `bufferization` op. Every array value is a memref.
- A buffer is made only by `memref.alloc` (identity layout, no memory
  space, no `alignment`), from One-Shot's allocations and reallocations;
  a copy is only `memref.copy`, its target a fresh `memref.alloc` (a
  copy, `copies`) or a `memref.subview` of a live buffer (an
  `insert_slice`'s meaning). Views are upstream's (`memref.subview`,
  `memref.cast`, `memref.expand_shape`, `memref.collapse_shape`).
- Every buffer that crosses a function boundary, a wrapper or a cell has
  the identity layout of `B(T)`.
- `!idr.lin<memref<...>>` is the graded buffer; the grade is kept, which
  the verifier checks after the pass.
- `idr.tie_shape` survives on memrefs until idr-lower drops it.

### 8. Consumers by lane

- U06 (C12): the `def` of section 1, `idr::createIdrBufferize()` at row 9,
  the include of `idr/Transforms/Bufferize.h` in `Pipeline.h`.
- U08 (C14): idr-rc, idr-stack and idr-demand see section 7's output:
  a `memref.alloc` result is a fresh cell, which counting makes owned in
  its own vocabulary (C14); `memref.copy` borrows both
  operands (the runtime counts the elements it copies, C17 §4); views
  read from their source; `!idr.lin<memref>` is a linear cell.
- U10 (C16): lowers `memref.alloc` to `idris_rt_array_new` and
  `memref.copy` to `idris_rt_memref_copy` (C17), `ub.poison` of a memref
  type, `idr.tie_shape` dropped, `!idr.lin<memref>` and identified types
  whose bodies hold memrefs.
- U17 (C24): `idr::bufferize::copies` for `in-place`; dialect fixtures run
  `idris-mlir-opt --idr-bufferize`.
- U19 (C17): the IR its hooks' callers lower from, as section 3 fixes it.
