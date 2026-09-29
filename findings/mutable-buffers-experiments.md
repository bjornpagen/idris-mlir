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
