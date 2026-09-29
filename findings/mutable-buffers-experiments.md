# Mutable buffers: experiments and raw notes

The raw notes behind `mutable-buffers.md`. `$S` is this session's
scratchpad, `research/mutable-buffers/`. Tools: `idris-mlir-opt`
(`build/dev/foreign/idr/idris-mlir-opt`, which registers every upstream
dialect and pass), the pinned `mlir-opt`, `mlir-translate` and `opt` from
`.toolchain/llvm/bin`, the pinned Chez `idris2`, and the pinned `lean`.
Every command ran under `timeout`, and those that read the build tree under
`flock -s build/.tree.lock`.

## E1. Arrays do not compile today

`$S/ioarr/Main.idr` (`import Data.IOArray`, `newArray 10`, one write, one
read) fails with:

    mlir backend: Main.main: unsupported (escape hatch):
    %extern Data.IOArray.Prims.prim__newArray (reached through Main.main)

The three array primitives are `%extern` (Data/IOArray/Prims.idr:11-13). The
Buffer primitives are `%foreign "scheme:blodwen-buffer-*"`. The registry lists
neither (Registry/Primitives.idr:66-74).

## E2. Contrib's LinArray is reference-semantic, and the difference shows

`$S/escape/Esc.idr`, compiled with the pinned Chez backend:

```idris
leak : LinArray Int
leak = newArray 4 (\1 a => a)      -- type-checks: the result `a` is free
main = do
  let a = leak
  let (ok1 # a1) = write a 0 10
  let (ok2 # a2) = write a 0 20
  let (v # _) = mread a1 0
  printLn v                         -- prints: Just 20
```

- Under value semantics, `a1` would hold 10.
- Chez prints `Just 20`, because contrib implements LinArray over one
  IOArray through `unsafePerformIO` (contrib/Data/Linear/Array.idr:43-56).
- memory-theory.md §4 found the same leak independently.
- Consequence: compiling LinArray with value semantics is faithful exactly
  when every update is in place. An out-of-place update is not a slow path.
  It is a different answer.

## E3. One-Shot Bufferize on the shapes idris-mlir produces

**Recursion (`rec.mlir`, `caller.mlir`).** A self-recursive `fill` that
threads a tensor through `tensor.insert` and a recursive call.
- With `--one-shot-bufferize="bufferize-function-boundaries"` it bufferizes
  in place: `memref.store` into `%arg0`, and the recursive call passes
  `%arg0`.
- Bufferization.md says recursive calls are not supported, but the pinned
  version handles this case.
- The caller `@unique` passes a fresh buffer with no copy.
- The caller `@shared`, which reads the old tensor after the call, gets
  `memref.alloc` + `memref.copy` before the call. That is a static
  copy-on-write, decided at compile time.

**The deallocation ABI on recursion.** `--buffer-deallocation-pipeline`:
- Default: `@fill` gets `bufferization.clone %2` on the path that returns
  its argument, which is a full copy per return. The reason is the ABI rule
  (OwnershipBasedBufferDeallocation.md, "Function boundary ABI"): "A
  function must not return a MemRef with the same allocated base buffer as
  one of its arguments".
- `private-function-dynamic-ownership=true` (`callerp.mlir`): the clone goes,
  and `@fill` returns an extra `i1`.
- But the caller then calls `@dealloc_helper` with five small heap arrays of
  pointers and flags, which is a runtime alias check at every call site.
- `--drop-equivalent-buffer-results` does not help: the equivalence of a
  recursive function's result with its argument is not inferred.

**The loop shape (`loop.mlir`).** This is what idr-tail-loops leaves: a
`scf.while` carrying the tensor, and a non-recursive private helper `@bump`
(extract, add, insert, return).
- Pipeline: `--one-shot-bufferize="bufferize-function-boundaries
  function-boundary-type-conversion=identity-layout-map"
  --drop-equivalent-buffer-results --buffer-deallocation-pipeline
  --canonicalize --cse`.
- Result:
  - `@bump(%m, %i)` returns nothing. It is Rust's `&mut`, derived.
  - The `scf.while` no longer carries the buffer.
  - The function has one `memref.alloc` and one `memref.dealloc`.
  - Every write is a `memref.store`.
  - There is no clone, no alias check and no count test.

**Building straight into a heap cell (`seal.mlir`).** `tensor.empty`, then an
`scf.for` of `tensor.insert`, then `bufferization.materialize_in_destination
... in restrict writable %cell`.
- With `--eliminate-empty-tensors` before One-Shot, the loop stores straight
  into `%cell`.
- No allocation and no copy remain. This is the zero-cost form of "hand the
  array to the heap".

**The conflict triple (`caller.mlir`, `test-analysis-only print-conflicts`).**
The shared caller is annotated with:
- `"C_0[DEF: result 0]"` on the `tensor.splat`;
- `"C_0[CONFL-WRITE: 0]"` on the call;
- `"C_0[READ: 0]"` on the later `tensor.extract`.

That is the content a rejecting error needs.

**Encoding to memory space (`enc.mlir`).** With `use-encoding-for-memory-space`,
`tensor<?xi64, "cell">` bufferizes to `memref<?xi64, "cell">`, alloc included.
A fact put in the encoding survives into the buffer type.

**Append (`concat.mlir`).** `tensor.concat` of a dead `%s` and `%t`
bufferizes to a new `memref.alloc` of the sum plus two `memref.copy`, always.
There is no in-place growth. A string built by repeated append is O(n²)
through this route.

## E4. Element types

- `memref<?x!idr.box<@L>>` is rejected: "invalid memref element type"
  (`eltm.mlir`). The idr types do not implement `MemRefElementTypeInterface`.
- `tensor<?x!idr.box<@L>>` parses. But `--one-shot-bufferize` on it
  **asserts** in `MemRefType::get` (StorageUniquerSupport.h:179) instead of
  emitting a diagnostic.
- It reproduces with the stock `mlir-opt` and an upstream type:
  `$S/mlir/upstream-bufferize-assert.mlir`, which uses
  `tensor<?x!emitc.opaque<"x">>`. That makes it an upstream bug candidate.
- We would not work around it: our design never bufferizes such tensors. So
  it needs no `upstream/` entry unless that changes.

## E5. Bounds checks (`bounds.mlir`)

**MLIR inserts the checks.** `--generate-runtime-verification` inserts
`cf.assert` before each `tensor.extract` / `tensor.insert`:
`0 <= i && i < dim`.

**MLIR removes only the sign test.**
- `--canonicalize --int-range-optimizations` removes `i >= 0` for the
  `scf.for` induction variable.
- It keeps `i < tensor.dim`, which is a relational fact. It also keeps
  `i < tensor.dim %iter_arg`, although the SCF `ValueBoundsOpInterface`
  implementation can prove that the iter_arg's dim equals the init's.
- No upstream pass folds an `arith.cmpi` through
  `ValueBoundsConstraintSet::compare`. Its users are linalg, affine and
  tensor utilities only.

**LLVM removes the rest.** The full chain was:
- runtime verification;
- one-shot;
- the dealloc pipeline;
- `convert-linalg-to-loops`, `expand-strided-metadata`,
  `finalize-memref-to-llvm`, `convert-scf-to-cf`, `convert-to-llvm`;
- `mlir-translate`, then `opt -O3`.

`@squares` is then a clean loop: load, mul, store, `add nuw nsw`, `icmp slt`.
Both asserts are gone, so LLVM's constraint elimination and induction
variable simplification remove the relational part. `@gather`, whose index
is data-dependent, keeps its check, as it must.

## E6. Typed access to a byte buffer (`bits32.mlir`)

`getBits32 buf off` as `vector.load %buf[%off] : memref<?xi8>, vector<4xi8>`,
then `vector.bitcast` to `vector<1xi32>`, then `vector.extract`. After
`opt -O3` this is one instruction: `load i32, ptr %p, align 1`. Data.Buffer's
typed getters and setters need no runtime call and no op of ours.

## E7. Lean's arrays (`$S/lean/Fill.lean` → `Fill.c`)

Two variants were compiled with the pinned `lean -c`: `fill` (`a.set! i v`,
index checked) and `fillFin` (`a.set i v h`, `h : i < a.size`).

**`fill`.** Each iteration calls `lean_array_set`, which does:
- a bounds check;
- `lean_ensure_exclusive_array`, a count test per write;
- `lean_box_uint64`: `Array UInt64` is an array of *boxed* objects, so every
  element store allocates on 64-bit.

**`fillFin`.** It calls `lean_array_fset`. The bounds check is gone, because
the proof `h` licenses it, but the per-write exclusivity test and the boxing
remain.

**What that means for us.** Lean pays for polymorphic arrays (boxing) and
for tests at every write. We are monomorphic, so elements unbox. And our
exclusivity is decided once: statically by One-Shot, or at a single thaw.

## Small notes

- `upliftWhileToForLoop` / `populateUpliftWhileToForPatterns`
  (SCF/Transforms/Transforms.h:246-250, Patterns.h:77-81) exist as C++ API
  only. No pass or transform op exposes them in the pinned tree.
- `finalize-memref-to-llvm` has `use-generic-functions`, which calls
  `_mlir_memref_to_llvm_alloc` / `_mlir_memref_to_llvm_free`
  (Conversion/Passes.td:1015; LLVMIR/IR/FunctionCallUtils.cpp:42-45). This is
  the upstream hook for routing every MLIR buffer through our runtime.
- `BufferizationOptions` has `allocationFn`, `memCpyFn`,
  `functionArgTypeConverterFn` and `unknownTypeConverterFn`
  (BufferizableOpInterface.h:256-368). `TensorLikeType` / `BufferLikeType`
  (BufferizationTypeInterfaces.td) let custom types into One-Shot.
- Upstream `RuntimeVerifiableOpInterface` implementations cover
  `tensor.extract`/`insert` (Tensor/Transforms/RuntimeOpVerification.cpp:249-251),
  `memref.load`/`store`/atomics (MemRef/Transforms/RuntimeOpVerification.cpp:397-405),
  and linalg.

## Second run: E8–E16

The files are in `$S/x/`. Pipelines are spelled out once below; "One-Shot"
means `--one-shot-bufferize="bufferize-function-boundaries
function-boundary-type-conversion=identity-layout-map"`.

### E8. Counted elements need only the element interface (`ptrelt*.mlir`)

- `tensor<?x!llvm.ptr>` asserts in One-Shot exactly like E4's idr and
  emitc types: `!llvm.ptr` does not implement `MemRefElementTypeInterface`
  in the pinned tree. Only `!ptr.ptr` and an AMDGPU type do
  (`grep MemRefElementTypeInterface include/`).
- `ptrelt2.mlir` is the same function over `!ptr.ptr<#ptr.generic_space>`:
  `%old = tensor.extract`, a call that releases it, `tensor.insert`. It
  bufferizes in place to `memref.load` / call / `memref.store` on `%arg0`,
  and the return is annotated `__equivalent_func_args__ = [0]`.
- So an array of counted references needs nothing from MLIR but the
  interface on the element type. What the old element's release means is
  ours to state (here: a call), and it survives bufferization unchanged.
- With the built `idris-mlir-opt` (`box-tensor.mlir`, `lin-tensor.mlir`):
  `tensor<?x!idr.str>` parses; `memref<?x!idr.str>` is "invalid memref
  element type"; `!idr.lin<tensor<?xi64>>` is rejected by `LinType::verify`
  ("expects !idr.lin of a runtime type other than the world"), because
  `isFieldType` (Dialect.cc:121-128) has no array types.

### E9. Arrays as counted runtime objects through MLIR's allocation hooks (`hooks.mlir`, `rt.c`)

Pipeline: One-Shot with `buffer-alignment=0`, `--buffer-deallocation-pipeline
--canonicalize --cse --convert-linalg-to-loops --expand-strided-metadata
--lower-affine --finalize-memref-to-llvm="use-generic-functions"
--convert-scf-to-cf --convert-to-llvm --reconcile-unrealized-casts`, then
`mlir-translate --mlir-to-llvmir`, then the pinned musl `clang -O2` with a
40-line C runtime.

The runtime's `_mlir_memref_to_llvm_alloc` returns the data of an object with
a 16-byte header (count, info, byte length); `_mlir_memref_to_llvm_free` drops
one reference and frees at zero. A C function `keep` stands for a cell: it
takes a reference of its own, and `drop_kept` drops it later.

| function | what it does | allocs / frees after it |
|---|---|---|
| `fill_sum(1000)` | fill in place, sum | 1 / 1 |
| `shared(1000)` | reads the old tensor after an insert | 3 / 3 (2 for it: the copy) |
| `escape(1000)` | stores the buffer in the "cell" | 4 / 3: alive after the function's own release |
| `drop_kept()` | the cell dies | 4 / 4, 5 releases |

- Output: `fill_sum 332833500`, `shared 14`, `escape 7`.
- `keep` asserts that the memref's allocated and aligned pointers are equal
  with `buffer-alignment=0`: one pointer is the whole object, so a cell
  needs one object slot for an array.
- Conclusion: every buffer MLIR allocates can be a counted runtime object,
  with no pattern of ours. A `memref.dealloc` is then "release one
  reference", and lifetimes compose with the cells' counts.

### E10. The recursion gap has two halves (`readrec.mlir`, `e5-rec.mlir`, `e5-fixed.mlir`)

**Read-only recursion copies at the call site (`readrec.mlir`).** `@sum`
recursively reads its tensor. `@main` calls it twice on `%t`, then writes
`%t`.
- One-Shot puts `memref.alloc` + `memref.copy` before **each** call: two
  whole-array copies.
- The callee never writes. But its boundary is not analyzed
  (OneShotModuleBufferize.cpp:510-523), so `CallOpInterface` answers "read
  and written" (FuncBufferizableOpInterfaceImpl.cpp:171-173, 186-188).
- A binary search written recursively and called n times is O(n²), and it
  is silent.

**A writer's result is not known equivalent (`e5-rec.mlir`, quicksort's shape).**
- One-Shot plus `--canonicalize --drop-equivalent-buffer-results` keeps
  `@rec : (index, index, memref) -> memref`. The result is `scf.if` over
  `%arg2` and a call result, and `DropEquivalentBufferResults` compares
  return operands with block arguments syntactically, modulo casts only
  (DropEquivalentBufferResults.cpp:65-75, 114).
- The full deallocation pipeline then adds `bufferization.clone` on the
  base-case path, plus a `dealloc_helper` call with five heap arrays in
  `@main`.
- `e5-fixed.mlir` is the same program with the result dropped by hand, which
  is what a greatest fixpoint over the SCC would conclude. The deallocation
  pipeline leaves one `memref.alloc`, one `memref.dealloc`, no clone and no
  helper.

### E11. Bounds checks: static length folds in MLIR, symbolic does not (`static.mlir`)

`--canonicalize --cse --loop-invariant-code-motion --cse
--int-range-optimizations --canonicalize`:
- `@f` over `tensor<12xi64>`: both `i < dim` and `i >= 0` fold, and the
  `scf.if` is gone.
- `@g` over `tensor<?xi64>`, a loop `for i in [0, dim)`: `cmpi slt %i, %dim`
  stays, although the loop's upper bound is the very SSA value it compares
  against. IntegerRangeAnalysis is not relational.

### E12. ValueBounds proves the relational fact, but nothing folds a compare with it (`vb3`–`vb7`)

The only upstream consumer that fits is
`transform.affine.simplify_min_max_affine_ops`. The pass
`affine-simplify-with-bounds` handles `affine.delinearize_index` /
`linearize_index` only (SimplifyAffineWithBounds.cpp:8-10). So the fact is
tested through a clamp, `affine.min(i, dim)`, which folds to `i` exactly
when ValueBounds proves `i < dim`:
- `vb4.mlir`: in a loop over `[0, dim)`, `min(i, dim)` becomes `i`. Proved.
  (`vb3.mlir`, `min(i, dim - 1)`, does not fold, because the helper asks a
  strict `<`; that is a property of the helper, not of the fact.)
- `vb5.mlir`: the same loop with the tensor threaded through `iter_args`
  (as linear Idris code threads it) and the length read from the iteration
  argument does **not** fold. `vb6.mlir`, with `linalg.fill` (a DPS op) in
  place of `tensor.insert`: it does not fold either.
- `vb7.mlir`: with `tensor.insert_slice` in place of `tensor.insert`,
  `--scf-for-loop-canonicalization` rewrites `tensor.dim %iter_arg` to
  `tensor.dim %init`, and then the clamp folds.
- The cause is that `isShapePreserving` (LoopCanonicalization.cpp:38-60)
  follows `tensor.insert_slice` and nested `scf.for` only, not
  `tensor.insert` or other destination-style ops.
- Also: there is no ValueBounds model for `arith.index_cast`. The arith
  models (Arith/IR/ValueBoundsOpInterfaceImpl.cpp:20-400) cover constant,
  `extsi`, add, sub, mul, the divisions and remainders, select, min and
  max. `cmpi slt` of two
  `index_cast`s is not canonicalized to an `index` compare (`ic.mlir`). An
  Idris `Int` check therefore never reaches the domain where ValueBounds
  works.

### E13. spectral-norm's A·v vectorizes over rows and keeps IEEE order (`spectral.mlir`)

- The kernel is a `linalg.generic` with maps `(i,j)->(j)` and `(i,j)->(i)`,
  and iterators `[parallel, reduction]`. `A(i,j)` is computed in the body
  from `linalg.index`.
- Transform script: `tile_using_for [4, 1]`, then `vectorize vector_sizes
  [4, 1]`.
- Result: an outer loop over rows by 4, an inner sequential loop over `j`,
  and one `arith.addf` on `vector<4xf64>` per `j`, with a masked tail.
- Each lane is one row's sum, added in the scalar program's order, so the
  output is bit-identical without reassociation. Idris `Double` is IEEE with
  no fast-math, so vectorizing the reduction dimension would not be allowed.

### E14. reverse-complement's kernel vectorizes to gathers (`revcomp.mlir`)

- `out[i] = table[in[n-1-i]]` as a `linalg.generic` with `tensor.extract` in
  the body.
- Transform script: tile by 16, then `vectorize ... {vectorize_nd_extract}`.
- Both the reversed read and the table lookup become `vector.gather` (masked).
- The reversed contiguous read is not recognized as a `transfer_read`
  plus a reverse shuffle, and x86 has no byte gather. For this kernel,
  LLVM's loop vectorizer (reverse consecutive access) is the better
  backend; linalg buys fusion with the line re-wrap, not codegen.

### E15. Upstream API a workaround can use

- `analyzeModuleOp`, `insertTensorCopies(op, analysisState, state)` and
  `bufferizeModuleOp` are public (OneShotModuleBufferize.h:28-56,
  Transforms.h:76-86). A driver can therefore run analysis, inspect
  `OneShotAnalysisState::isInPlace`, and then rewrite.
- `FuncAnalysisState` is a public `OneShotAnalysisState::Extension` with
  public maps (FuncBufferizableOpInterfaceImpl.h:36-77):
  - `equivalentFuncArgs`, `aliasingReturnVals`, `readBbArgs`,
    `writtenBbArgs`;
  - `analyzedFuncOps`.
- `analyzeModuleOp` never touches the `analyzedFuncOps` entry of a function
  in a call cycle (:510-523). A summary seeded there before the call is what
  `CallOpInterface` reads (FuncBufferizableOpInterfaceImpl.cpp:171-200).
  That is the hook for a fixpoint that uses public API only.
- The `bufferization.access` argument attribute is read only by
  `funcOpBbArgReadWriteAnalysis` (OneShotModuleBufferize.cpp:249-255), which
  never runs for functions in a call cycle. So it cannot carry a summary.
- `finalize-memref-to-llvm` has no lowering for `memref.realloc`;
  `expand-realloc` turns it into alloc + copy + dealloc.
- `memref.copy` lowers to `llvm.memcpy` for identity layouts
  (MemRefToLLVM.cpp:1139-1190), which is undefined on overlap. R6RS
  `bytevector-copy!`, which Chez's `blodwen-buffer-copydata` uses, is
  defined on overlap.

### E16. The idr pipeline order today

`Registration.cc:16-29`:
`idr-simplify, idr-defunctionalize, canonicalize, idr-stack, idr-rc,
idr-tail-loops, idr-lower, ...`. Counting "runs on functional code, where
recursion is still a call"; idr-rc refuses regions other than matches
(Counts.cc:67-71). So there are no loops before counting, and
bufferization placed before counting sees recursion, not `scf.for`. That is
why the recursion gap (E10) is on the main path, not a corner.
