# Mutable buffers: upstream reports, drafted

Drafts in the form upstream/README.md asks for. The reproducers use
upstream dialects only and are in the stream's scratch directory,
`research/mutable-buffers/x/` and `mlir/`. By AGENTS.md, a report moves to
`upstream/<name>/`, with its `tests/upstream/<name>/run` and its `PINS.md`
entry, in the same change as the workaround that needs it. Only the first
report here has a workaround in the design (mutable-buffers.md §9). The
others are recorded so that nobody works around them unannounced.

All of them were run at `llvmorg-23.1.2` with the pinned
`.toolchain/llvm/bin/mlir-opt`.

## 1. one-shot-recursive-boundaries: [mlir][bufferization] functions in a call cycle get no boundary summaries

**What happens.** `OneShotModuleBufferize` analyzes the body of a function
that is part of a call cycle, but none of its boundary facts: which tensor
arguments it reads or writes, and which results are equivalent to which
arguments. Two consequences follow.

1. **A call to a read-only recursive function copies its operand whenever
   the caller uses the tensor again.** `readrec.mlir`:

   ```mlir
   func.func private @sum(%i: index, %t: tensor<?xi64>, %acc: i64) -> i64 {
     %c1 = arith.constant 1 : index
     %c0 = arith.constant 0 : index
     %n = tensor.dim %t, %c0 : tensor<?xi64>
     %done = arith.cmpi sge, %i, %n : index
     %r = scf.if %done -> i64 {
       scf.yield %acc : i64
     } else {
       %x = tensor.extract %t[%i] : tensor<?xi64>
       %a = arith.addi %acc, %x : i64
       %j = arith.addi %i, %c1 : index
       %s = func.call @sum(%j, %t, %a) : (index, tensor<?xi64>, i64) -> i64
       scf.yield %s : i64
     }
     return %r : i64
   }
   func.func @main(%n: index, %v: i64) -> i64 {
     %c0 = arith.constant 0 : index
     %z = arith.constant 0 : i64
     %e = tensor.empty(%n) : tensor<?xi64>
     %t = linalg.fill ins(%v : i64) outs(%e : tensor<?xi64>) -> tensor<?xi64>
     %s1 = func.call @sum(%c0, %t, %z) : (index, tensor<?xi64>, i64) -> i64
     %s2 = func.call @sum(%c0, %t, %s1) : (index, tensor<?xi64>, i64) -> i64
     %t2 = tensor.insert %s2 into %t[%c0] : tensor<?xi64>
     %x = tensor.extract %t2[%c0] : tensor<?xi64>
     return %x : i64
   }
   ```

   ```
   $ mlir-opt readrec.mlir --one-shot-bufferize="bufferize-function-boundaries function-boundary-type-conversion=identity-layout-map"
   ```

   `@main` gets `memref.alloc` + `memref.copy` of the whole array before
   each of the two calls. `@sum` never writes its argument. Expected: no
   copy. The same program with `@sum` written as an `scf.for` gets none.

2. **A result that is always the argument is not known to be.**
   `e5-rec.mlir` (a quicksort-shaped recursion: write one slot, then recurse
   twice on the result) keeps `@rec : (index, index, memref<?xi64>) ->
   memref<?xi64>` after `--drop-equivalent-buffer-results`. With
   `--buffer-deallocation-pipeline`, the base-case path returns a
   `bufferization.clone` of the argument, and `@main` calls `@dealloc_helper`
   with five heap-allocated arrays. Expected: the result is dropped, as it is
   for a non-recursive function of the same shape, and the program has one
   allocation and one deallocation (`e5-fixed.mlir` is the expected
   output, written by hand).

**Where.**
- `mlir/lib/Dialect/Bufferization/Transforms/OneShotModuleBufferize.cpp:510-523`:
  "Analyze all other functions. All function boundary analyses are
  skipped." There is a TODO.
- `FuncBufferizableOpInterfaceImpl.cpp:171-173, 186-188, 200` then answer
  conservatively: read, written, no aliasing known.
- `DropEquivalentBufferResults.cpp:65-75, 114` compares return operands with
  block arguments syntactically, modulo `memref.cast` only. It sees neither
  through a region-branch op's yields nor through a call result.

**Proposed fix.**
- **(a) Summaries by fixpoint in `analyzeModuleOp`.** For each strongly
  connected component of the call graph, seed optimistic summaries:
  - no argument read or written;
  - each result equivalent to the argument that its first returning path
    returns.

  Analyze the bodies, recompute the summaries with the existing
  `funcOpBbArgReadWriteAnalysis` and `aliasingFuncOpBBArgsAnalysis`, weaken
  the ones that do not hold, and repeat from a fresh state until stable.
  Each round only grows read/write sets or shrinks equivalences, so it
  terminates. At the fixpoint the assumption is the analysis's own result,
  which is sound by induction on call depth for every call that returns.
- **(b) `DropEquivalentBufferResults` as a greatest fixpoint.** A result is
  equivalent to argument `j` when every return operand is argument `j`
  modulo casts, a `RegionBranchOpInterface` result all of whose yields are
  equivalent, or the same result of a call into the same SCC whose operand
  `j` is equivalent.

**Our workaround (not yet built).** Both, carried locally, using public API
only:
- in our bufferization driver, seed `FuncAnalysisState` (a public
  extension) before `analyzeModuleOp` and iterate;
- a pass that is (b).

Retire both when `readrec.mlir` gets no copy and `e5-rec.mlir` loses its
result upstream.

## 2. scf-dim-of-iter-arg-insert: [mlir][scf] `DimOfIterArgFolder` ignores `tensor.insert` and other destination-style ops

**What happens.** `vb5.mlir`: a loop over `[0, dim(%t0))` threads `%t0`
through `iter_args` with `tensor.insert`, and reads `tensor.dim %a` of the
iteration argument.
- `--scf-for-loop-canonicalization` leaves `tensor.dim %a`.
- With `tensor.insert_slice` in place of `tensor.insert` (`vb7.mlir`), the
  pass rewrites it to `tensor.dim %t0`, and ValueBounds then proves the
  index below the length: `transform.affine.simplify_min_max_affine_ops`
  folds `min(i, dim)` to `i`.

Expected: `tensor.insert`, whose result has its destination's shape by
definition, is handled like `tensor.insert_slice`.

**Where.** `mlir/lib/Dialect/SCF/Transforms/LoopCanonicalization.cpp:38-60`,
`isShapePreserving`: a `TypeSwitch` over `tensor::InsertSliceOp` and
`scf::ForOp` only.

**Proposed fix.** Follow any `DestinationStyleOpInterface` result to its
tied init (`getTiedOpOperand`). That covers `tensor.insert`, `linalg.*`
and every other destination-style op.

**Our workaround.** None needed. In our pipeline arrays are memrefs, and
loop-invariant, before loops exist (mutable-buffers.md §7). File it
without a PIN.

## 3. bufferize-invalid-element-assert: [mlir][bufferization] One-Shot asserts on a tensor whose element type is not a valid memref element

**What happens.** `upstream-bufferize-assert.mlir` (in `mlir/`) uses
`tensor<?x!emitc.opaque<"x">>`. `ptrelt.mlir` in `x/` uses
`tensor<?x!llvm.ptr>`. On both, `--one-shot-bufferize` hits the assertion in
`MemRefType::get` (`StorageUniquerSupport.h:179`, from
`getMemRefTypeWithStaticIdentityLayout`) after printing "invalid memref
element type". Expected: a diagnostic, and the pass fails.

**Where.** `bufferization::getMemRefTypeWithStaticIdentityLayout` and the
other builders call `MemRefType::get` instead of `MemRefType::getChecked`,
or checking `BaseMemRefType::isValidElementType` first.

**Our workaround.** None. With `MemRefElementTypeInterface` on our element
types, and our verifier rejecting any other tensor element
(mutable-buffers.md §3 rule 1), we never reach it.

## 4. A missing feature, not a bug: folding a comparison with ValueBounds

**What happens.** No upstream pass folds `arith.cmpi` through
`ValueBoundsConstraintSet`, although ValueBounds proves `i < dim` for
`scf.for %i = 0 to dim` (`vb4.mlir`). The only consumers are affine and
linalg utilities. `int-range-optimizations` is not relational (`static.mlir`,
`@g`).

**Offer.** A pattern that decides an `index` comparison with
`ValueBoundsConstraintSet::compare`, alongside `int-range-optimizations`.
Plus a ValueBounds model for `arith.index_cast` between `index` and an
integer of the index width. There is none today (only `extsi`), and
`cmpi` of two `index_cast`s is not canonicalized to an `index` compare
(`ic.mlir`).

This is our residue until then (mutable-buffers.md §7), not a workaround,
so it needs no `upstream/` entry.
