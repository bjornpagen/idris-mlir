## C18 Patched upstream APIs and their patches

Producer: U16, alone. What the carried LLVM patches change in the API our
code compiles against after the cutover, and which patches are carried.
`M/` is `.toolchain/llvm-project/mlir`, the pristine pin (7208ba24), which
`tests/spec/upstream-patches` checks every patch against; line numbers are
the pin's.

### 1. The patches the tree carries

`tools/bootstrap.sh` applies every `upstream/*/llvm.patch`, in byte order of
the directory names (`tools/patches.sh`), to its copy of the pin. After the
cutover that list is exactly:

| Patch | Bug | Site after the cutover |
| --- | --- | --- |
| 03 | bytecode-deferred-quadratic | the driver reads the frontend's bytecode (C22) |
| 04 | vectorize-precondition-body | C13's vectorization schedule (`transform.idr.vectorize_lanes`, `foreign/idr/lib/Target/Schedules.cpp`) |
| 05 | forward-dataflow-callee-lookup | every sparse or dense forward solve (remove-dead-values, int-range, C10's summaries) |
| 06 | remove-dead-values-unreachable | the pipeline's one `remove-dead-values{canonicalize=false}` (C12 row 5) |
| 07 | inline-unreachable-terminator | `mlir::inlineCall` from `idr-optimize` (C07) |
| 09 | int-range-narrowing-exactness | `idr-narrow-lanes` |
| 19 | pass-timing-dynamic-pipeline | every pass that runs a pipeline through `runPipeline` (`idr-optimize`, `idr-rc`, `idr-narrow`, `idr-returned-arguments`, `idr-tail-calls`) |
| 23 | cse-statistic-assignment | CSE nested in `idr-optimize`'s inner pipeline and the pipeline's cleans |
| 24 | one-shot-module-function-interface | One-Shot Module Bufferize on `idr.func` (C15); new, section 2 |

Not carried, each a report kept as a submission with `pull-request.diff`
in place of `llvm.patch` and no `PINS.md` entry: 02
(composite-fixed-point-sccp), 16 (remove-dead-values-unchanged-call), 22
(remove-dead-values-poison-operand), all three because nothing in the tree
runs a composite fixed point after the cutover; 08 and 17 as before. 02,
16 and 22 change nothing a lane codes against: their diffs touched only
`SCCP.cpp`, `PatternMatch.{h,cpp}`'s `eraseOpResults` and
`RemoveDeadValues.cpp`, whose public API they never changed. No
Presburger patch exists or is planned in this wave (nothing in the tree
reaches integer emptiness once the in-bounds prover goes).

### 2. Patch 24: One-Shot Module Bufferize on FunctionOpInterface

Directory `upstream/24-one-shot-module-function-interface/`: `README.md`,
`llvm.patch`, `named-sequence.mlir`, `no-return.mlir`, `idr-call.mlir`. Check
`tests/upstream/one-shot-module-function-interface/`. `PINS.md` entry
`one-shot-module-function-interface`. It relands llvm-project pull request
110322 (reverted by 113124) with the revert's cause fixed: the function set
is limited to function ops with a bufferization model. It also bufferizes a
function that never returns (U12's request). For `idr.func`, which always
has C15's model, "every function op with a model" is every `idr.func`.

**`mlir/Dialect/Bufferization/IR/BufferizableOpInterface.h`** (was
`M/include/mlir/Dialect/Bufferization/IR/BufferizableOpInterface.h:268-273`)
now includes `mlir/Interfaces/FunctionInterfaces.h`, drops the forward
declaration of `func::FuncOp`, and declares:

```cpp
  /// Tensor-like -> Buffer-like type conversion.
  /// Parameters: tensor-like type, memory space, function op, bufferization
  /// options
  using FunctionArgTypeConverterFn = std::function<BufferLikeType(
      TensorLikeType, Attribute memorySpace, FunctionOpInterface,
      const BufferizationOptions &)>;
```

`BufferizationOptions::functionArgTypeConverterFn` keeps its name and is
called with the `idr.func` whose argument or result is converted.
`setFunctionBoundaryTypeConversion(LayoutMapOption)` and the default
converter keep their behaviour. `BufferizationOptions::isOpAllowed` is
unchanged (it still denies only the func dialect's ops when
`bufferizeFunctionBoundaries` is false).

**`mlir/Dialect/Bufferization/Transforms/FuncBufferizableOpInterfaceImpl.h`**
(was `:1-85`), exactly these declarations besides the header's includes
(`CallInterfaces.h`, `FunctionInterfaces.h`, `<optional>` added):

```cpp
namespace mlir {
namespace bufferization {
/// Helper function that returns the return-like terminators of the blocks of
/// the given function.
SmallVector<Operation *> getReturnOps(FunctionOpInterface funcOp);

namespace func_ext {
enum class FuncOpAnalysisState { NotAnalyzed, InProgress, Analyzed };
using func::FuncOp;

struct FuncAnalysisState : public OneShotAnalysisState::Extension {
  FuncAnalysisState(OneShotAnalysisState &state);
  using BbArgIndexSet = DenseSet<int64_t>;
  using IndexMapping = DenseMap<int64_t, int64_t>;
  using IndexToIndexListMapping = DenseMap<int64_t, SmallVector<int64_t>>;
  DenseMap<FunctionOpInterface, IndexMapping> equivalentFuncArgs;
  DenseMap<FunctionOpInterface, IndexToIndexListMapping> aliasingReturnVals;
  DenseMap<FunctionOpInterface, BbArgIndexSet> readBbArgs;
  DenseMap<FunctionOpInterface, BbArgIndexSet> writtenBbArgs;
  DenseMap<FunctionOpInterface, FuncOpAnalysisState> analyzedFuncOps;
  mutable SymbolTableCollection symbolTables;
  void startFunctionAnalysis(FunctionOpInterface funcOp);
};

const FuncAnalysisState &getFuncAnalysisState(const AnalysisState &state);
FuncOpAnalysisState getFuncOpAnalysisState(const AnalysisState &state,
                                           FunctionOpInterface funcOp);
std::optional<int64_t>
getEquivalentFuncArgIdx(FunctionOpInterface funcOp,
                        const FuncAnalysisState &state, int64_t returnValIdx);
FunctionOpInterface getCalledFunction(CallOpInterface callOp,
                                      SymbolTableCollection &symbolTables);
FunctionOpInterface getCalledFunction(CallOpInterface callOp,
                                      const AnalysisState &state);
BufferLikeType getBufferizedFunctionArgType(FunctionOpInterface funcOp,
                                            int64_t index,
                                            const BufferizationOptions &options);

void registerBufferizableOpInterfaceExternalModels(DialectRegistry &registry);
} // namespace func_ext
} // namespace bufferization
} // namespace mlir
```

What each returns (the func dialect's models are written on the same
functions, so the meaning is theirs):
- `getReturnOps(f)`: for each block of `f`'s body in order, its terminator
  when it has the `ReturnLike` trait. An `idr.return` is one (`IdrOps.td`
  declares `ReturnLike`).
- `getFuncAnalysisState(state)`: the extension the module driver adds;
  asserts that `state` is a `OneShotAnalysisState` holding it.
- `getFuncOpAnalysisState(state, f)`: `Analyzed` once the driver has run
  the boundary analyses of `f`; `NotAnalyzed` for a function in a call
  cycle (whose boundary is never analyzed), for a state without the
  extension, and for a function outside the set.
- `getEquivalentFuncArgIdx(f, s, i)`: the argument index every return of
  `f` returns as its `i`-th operand, equivalently buffered, if any.
- `readBbArgs[f]`, `writtenBbArgs[f]`: argument indices of `f` read,
  written; `aliasingReturnVals[f][a]`: the return operand indices that may
  alias argument `a`. An index is a position among the function's
  arguments; for `idr.call` it equals the operand number, since its
  operands are its arguments.
- `getCalledFunction(call, ...)`: the callee resolved through the symbol
  table collection, or null when it is not a `FunctionOpInterface` op.
- `getBufferizedFunctionArgType(f, i, options)`: the buffer type of
  argument `i` (a `TensorLikeType`), by `options.functionArgTypeConverterFn`
  and a `bufferization.buffer_layout` argument attribute when present.

**The module driver** (`OneShotModuleBufferize.h` unchanged:
`analyzeModuleOp`, `bufferizeModuleOp`, `removeBufferizationAttributesInModule`,
`runOneShotModuleBufferize`, each on `Operation *moduleOp`):
- The functions are the ops directly in the module's blocks that implement
  `FunctionOpInterface` and `BufferizableOpInterface` (an external model
  counts). Any other op, a function op without a model among them, is
  bufferized by the final "other ops" loop, as at the pin.
- The calls are the `CallOpInterface` ops nested in a function of the set
  whose callee resolves to a function of the set with a `TensorLikeType`
  argument or result. A call of anything else orders nothing and asserts
  nothing.
- Order: callees before callers; the members of a call cycle are analyzed
  and bufferized after the rest, their boundaries unanalyzed (the pin's
  rule, `M/lib/Dialect/Bufferization/Transforms/OneShotModuleBufferize.cpp:515-529`).
- A function of the set none of whose blocks ends in a `ReturnLike`
  terminator (every block ends in `ub.unreachable`, as a crash does) is
  analyzed with no result aliasing or equivalent to an argument, and
  bufferizes; at the pin it failed with "cannot bufferize func.func
  without func.return". Its callers bufferize too.
- `inferFunctionResultLayout` folds `memref.cast` before the returns and
  sets the type with `cloneTypeWith(getArgumentTypes(), resultTypes)`.
- `noAnalysisFuncFilter` matches `SymbolTable::getSymbolName(f)`.
- `removeBufferizationAttributesInModule` clears
  `bufferization.buffer_layout` and `bufferization.writable` from every
  function of the set.

"Tensor" in all of this means `TensorLikeType`: a type that wraps a tensor
without implementing `TensorLikeType` is no tensor to the driver.

### 3. Requirements on the ops of C15

For `idr.func` to be a function of the set: `FunctionOpInterface` (it
is: `IdrOps.td`), an external `BufferizableOpInterface` model attached
before the pass runs, a body whose blocks end in `idr.return`
(`ReturnLike`). For a call to order its callee: `idr.call` implements
`CallOpInterface` with `resolveCallableInTable` (it does). The models of
`idr.func`, `idr.call` and `idr.return` are C15's (U12): they read the
boundary analysis only through section 2's queries, and they never keep a
copy of it.

### 4. Until the toolchain is rebuilt

`make typecheck` re-exports `.toolchain/build/llvm-project` when the patch
list changes (24 in; 02, 16, 22 out) and then compiles our units against
section 2. Before that re-export, `check-units.py` compiles against the
unpatched headers, and an error naming `FuncAnalysisState`'s key type,
`FunctionArgTypeConverterFn`'s third parameter or a missing `func_ext`
query is expected; report it, do not work around it. Stage 2 is rebuilt
with the new list on the owner's machine (`tools/verify-pins.sh` refuses a
stamp that records another list).

### 5. Consumers

- U12: `foreign/idr/lib/Transforms/Bufferize` and
  `foreign/idr/include/idr/Transforms/Bufferize.h` (the models, the options
  with `functionArgTypeConverterFn` on `FunctionOpInterface`, the call of
  `runOneShotModuleBufferize`).
- U06: the pipeline's empty tensor elimination on the module (C12 row 8),
  which runs `analyzeModuleOp` with `bufferizeFunctionBoundaries`
  (`M/lib/Dialect/Bufferization/Transforms/EmptyTensorElimination.cpp:208-228`).
- U17: the bufferization fixtures in `tests/idr`.
- U18: `tests/spec/upstream-patches` (every report's sections and every
  patch applying), `tests/toolchain` if it names the patch list.
- The coordinator: `make typecheck`'s re-export; the owner's stage-2
  rebuild on both targets.
