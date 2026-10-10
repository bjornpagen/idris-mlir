# 0004 companion — compiler: the lowering in depth

A companion to `README.md`, written independently as a full draft from the compiler side. Where it disagrees with the README, the README decides (see the README's layout note).

(Its original title: 0004: a typed array language, lowered to MLIR)

**Status:** proposed, 2026-10-09, replacing the 0004 of the same day
whole. Two premises are the user's: pure array programs are tensors
("tensors should definitely be tensors, pure array programs is one of
the heavy hitting features of mlir and we cannot lose this"), and rank
has no ceiling: the earlier draft's "rank above 1 only when a literal"
was ruled timid. Every other decision is taken here, with its reason or
with the measurement and threshold that settles it (Decisions). Claims
are marked: read (the path given), measured, recalled (from memory, to
be checked), conjecture, decision. A `sources/` path is the research
library's; papers the research pass of 2026-10-09 added are staged under
its stage directory at the same relative path until they are committed.
MLIR paths are of the pinned tree, `.toolchain/llvm-project/mlir` at
7208ba24. Nothing here is built.

The language is the one the APL line converged on (an array is a shape
and its atoms in row-major order, a function is written on cells, and one
rule lifts it over any frame) with its shape calculators in the types,
which is what Remora showed can be checked statically. The compiler is
MLIR's structured code generation applied without a ceiling: every
primitive is a structured op on tensors, and fusion, tiling,
bufferization, vectorization and partitioning are upstream's mechanisms
driven by facts the types already give. The `idr` dialect adds only what
upstream lacks. This draft goes deepest on the compiler; the surface
library appears where the compiler depends on it. 0005 owns the shard
runtime and 0001 Rust; both are cited, not restated.

## What it changes

Each move names the representation that changes and the branches it
deletes.

- **A value array is a tensor from the frontend on** (§4, D1). Data: the
  frontend's `TensorT k e`, emitted as `tensor<?x…xE>`, and the library
  `libs/mlir-array`, whose primitive layer the frontend recognizes by
  name. Deleted: `idr.array.generate` and `idr.array.fold`; the memref
  half of `Lower/Loops.cppm` (`lowerGenerate`, `lowerFold`, `reducedBy`,
  `readAsInputs` and its test on entry); the `ArrayLoop` hook and its two
  region signatures; the raise of write threads the earlier draft
  planned.
- **Rank is a fact of the instance** (§3.1, D2). Data: an erased shape
  keys a function instance by its skeleton, as a type keys one today;
  the frontend's `Rank0 | Rank1` becomes a number. A shape no instance
  can know is one opaque dimension with its extents beside it. Deleted:
  every rank-1 restriction (`Idr_Rank1ArrayValue` on loops, `LowerDim`'s
  refusal of dimensions other than 0, `arrayView`'s stride 1 for every
  dimension) and any unranked tensor.
- **An array value is its cell, its base and its extents** (§3.3, D4).
  Data: one word, the base, beside today's cell and sizes. Deleted: the
  copy that a leading-axis slice or a reshape would cost wherever it
  crosses a call or is stored.
- **Order is meaning** (§4.3, D7). Data: none in the compiler. The
  library writes a reduction's association as its shape (lanes and
  chunks), and no pass reorders a reduction. Deleted: any analysis of
  whether an operator associates, any fact recording it, and every use of
  partial-reduction tiling.
- **The rank operator is the one lifting primitive** (§4.2, §6, D6).
  Data: `idr.array.lift`. Deleted: per-rank and batched variants of
  every kernel; a matrix product over a stack of matrices is the matrix
  product lifted.
- **The grade crosses bufferization in the tensor's encoding** (§9.2,
  D11). Data: inside `idr-bufferize` only, `!idr.q<g, tensor<T>>` is
  spelled `tensor<T, #idr.grade<g>>`, which One-Shot analyzes as any
  tensor, linear parameters included; a store into the heap is a write
  of the stored buffer. Deleted: the earlier draft's plan to make `!idr.q`
  a `TensorLikeType`, which would have made every graded value, the world
  included, a tensor to One-Shot.
- **The target's facts are data** (§8.4, D10). Data: vector width,
  register count, cache sizes and the partition threshold join the
  target's entry and reach every module as DLTI entries. Deleted:
  `vectorBits`'s test of x86 (`foreign/idr/lib/Target/Vectors.cppm`), a
  per-target case outside the entry.
- **Irregular data is a library type over regular arrays** (§2, D5).
  Data: ragged rows as offsets and flat data; trees as parent vectors.
  Deleted: arrays of cells for regular nesting, which is flat by
  representation (§3.4).

## Rules it keeps

- **Both targets, one design; nothing per target outside the entry.**
  The cache, register and threshold facts live in the target's entry
  (§8.4). The library's reduction trees are the same constants on both
  targets, and no pass reassociates, so a reduction gives the same bits
  on x86-64 and arm64, at any vector width and any number of shards (a
  math function's last bit stays its platform library's, as today).
- **Idris does types; MLIR does programs.** The frontend decides rank
  skeletons and element representations from types (§3); batching,
  fusion, tiling, bufferization, vectorization and partitioning happen in
  MLIR (§5).
- **One thing, one representation.** The library's plain definition is
  the meaning and the tensor is the compilation, and the representation
  of an array type depends on the type alone (§3.4). The in-place
  decision is One-Shot's alone (§9). Crash and divergence facts come
  from `lib/Facts` and `idr-effects`, the one place that has them. The
  op set is upstream's wherever upstream has the op (§1.4, §16).
- **Checked TT; no fact erased before the pass that uses it.** The
  skeleton is read from the instance's types; extents from values
  (§3.1, §3.2).
- **No primitive has an implementation in Idris.** The array library's
  "primitives" are library functions recognized by name, as
  `Linear.Array`'s loops are today; sorting words is the runtime's
  (§4.4).
- **Compile-time evaluation follows upstream Idris.** Pure array code is
  pure, so its closed calls are evaluated (§4.6), which today they are
  not.
- **No oracle.** Expected files are the specification. C and Futhark are
  performance baselines only; their outputs agreeing with ours to 1e-9 is
  the benchmark's sanity check, as for C and Chez today (Performance
  goals).
- **`%foreign` and the C ABI stay out.** No runtime library of
  `sparse_tensor`, no OpenMP, MPI or async runtime, no GPU driver loaded
  at run time (§12, §13, §14).
- **Only `IdrisMLIR.Frontend.*` imports Idris; third_party/Idris2 is
  unmodified.** Nothing here changes Idris's elaborator.
- **Reject with a named rule, never miscompile.** `unsupported
  (uniqueness)` for a broken in-place promise on an array (§9.5),
  `unsupported (sparse element)` (§13).
- **No pass drops what Idris proved.** Between passes `!idr.lin` wraps
  the carrier, a tensor before bufferization and a memref after; inside
  `idr-bufferize` the same grade is the tensor's encoding (§9.2).
- **Erased does not mean constant; a linear binder is not unique
  ownership; indexed vectors are not contiguous.** No extent is read
  from an erased index (§3.2). One-Shot decides in place, and QTT only
  checks the promise (§9.2, §9.5). `Vect` stays a list; `Array` is
  contiguous by its constructor.
- **A bug upstream is fixed upstream.** The upstream changes are listed
  with their plans (Upstream).
- **Tests check behaviour.** Each stage's proof is expected files and
  named properties of `idr-expect` (§16), never op sequences.
- **Static linking.** A GPU device is reached through an OS framework or
  a kernel interface, never a loaded driver (§14).

## 1. What exists

### 1.1 Arrays are memrefs from birth, of rank 0 or 1

- **The type.** An array is a builtin `memref` of rank 0 or 1, every
  dimension dynamic (read: `foreign/idr/include/idr/IdrOps.td`:1788-1803;
  `Idr_ArrayValue` is "an array of rank 0 or 1 at any grade",
  :1579-1584). The frontend's `ArrayT Rank Ty` has
  `Rank = Rank0 | Rank1` (read: `compiler/src/IdrisMLIR/Types.idr`:86-120)
  and emits `MemRefType` (read: `compiler/src/IdrisMLIR/Emit/Types.idr`:41).
- **The ops are IO.** `idr.array.new`, `get` and `set` take one size or
  index per dimension and the world (read: IdrOps.td:1809-1887).
- **The cell** is a header, the element count and the elements (read:
  `runtime/idris_rt.h`:150-165); the value is the cell and one size per
  dimension (read: `foreign/idr/lib/Lower/Arrays.cppm`:1-20). Two lowering
  helpers are right only because the rank is at most 1: `arrayView`
  gives every dimension stride 1 (read: `foreign/idr/lib/Lower/ArrayView.cppm`:42-45)
  and `LowerDim` refuses any dimension but 0 (read: Arrays.cppm:213-231).
- **`Linear.Array`** is a size beside base's `ArrayData`, every operation
  an `unsafePerformIO` on a forged world; `freeze` gives a read-only,
  shared `IArray` (read: `libs/mlir-linear/Linear/Array.idr`).

### 1.2 Two loop ops, lowered to linalg on memrefs

- **Recognition.** `prim__generate` and `prim__foldl` of `Linear.Array`
  are recognized by name at word instances and become
  `idr.array.generate` and `idr.array.fold`, whose bodies apply the
  library's function (read: `compiler/src/IdrisMLIR/Registry/Recognized.idr`:91-110;
  `compiler/src/IdrisMLIR/Frontend/Translate/Terms.idr`:91-106).
- **Lowering.** Each becomes a `linalg.generic` on memrefs; a generate
  whose body is a fold over an outside array is one generic of two
  dimensions; reads of outside arrays at the loop's index become inputs
  behind one test on entry (read: `foreign/idr/lib/Lower/Loops.cppm`).
- **`idr-vectorize`** tiles parallel dimensions by the target's lanes and
  reductions by one, peels, and masks the last tile (read:
  `foreign/idr/lib/Vectorize/Tiles.cppm`); the lanes come from the
  module's `#llvm.target`, with a test of x86 (read:
  `foreign/idr/lib/Target/Vectors.cppm`). A body the vectorizer refuses
  (a crash check, a call) stays whole and runs in the program's order
  (read: Tiles.cppm:14-19; the test
  `tests/programs/arrays/linarray-rows-crash-order`).
  `idr-narrow-lanes` versions integer lanes to 32 bits; `idr-in-bounds`
  erases proved guards (read: `foreign/idr/include/idr/Passes.td`:443-493, 663-720).
- **Nothing is a tensor**, and the pipeline has no bufferization, fusion
  or tiling step (read: `foreign/idr/lib/Dialect/Registration/PipelineSteps.cc`).

### 1.3 Measured

(measured: `bench/runs/2026-10-07-f5a4dff9-darwin-arm64/results.md`,
Apple M2 Max, best of 5)

| benchmark | this compiler | clang -O2 | clang / this |
|---|---:|---:|---:|
| spectral-norm-linear 5500 | 0.596 s | 1.108 s | 1.86x |
| fannkuch-linear 12 | 24.155 s | 25.711 s | 1.06x |
| nbody 50000000 | 1.655 s | 1.924 s | 1.16x |
| mandelbrot 2000 | 0.229 s | 0.231 s | 1.01x |

On the Linux record (a 4-CPU Xeon container) spectral-norm-linear is
1.99x of C (measured: `bench/README.md`, record 2026-10-03). No program
in `bench/` has an array of rank above 1, a fused chain, a tiled loop, or
a parallel loop.

### 1.4 What upstream has at the pin, and what it lacks

| Need | At the pin | Here |
|---|---|---|
| structured ops at any rank | `linalg.generic`, `map`, `reduce`, `transpose`, `broadcast`, `contract`; ranked operands only (read: `mlir/include/mlir/Dialect/Linalg/IR/LinalgStructuredOps.td`:147, 230) | used; every rank static per instance (§3.1) |
| a scan | none in linalg; `vector.scan` takes a fixed combining kind (read: `mlir/include/mlir/Dialect/Vector/IR/VectorOps.td`:3032) | `idr.array.scan` |
| an op on cells (a region over tensors) | none: a generic's body is scalar | `idr.array.lift` |
| gather, scatter that bufferize | `tensor.gather` and `tensor.scatter` have no bufferization model (read: `mlir/lib/Dialect/Tensor/Transforms/BufferizableOpInterfaceImpl.cpp`:1190-1209) | gathers as generic bodies; `idr.array.scatter` |
| elementwise fusion | generic into generic, producer all-parallel, read as an input (read: `mlir/lib/Dialect/Linalg/Transforms/ElementwiseOpFusion.cpp`:141-200); a producer's other uses kept as extra results (:114-138); the pass fuses only one-use producers (:2807-2810) | our control function (§7) |
| horizontal fusion of generics | none; `transform.loop.fuse_sibling` fuses loops (read: `mlir/include/mlir/Dialect/SCF/TransformOps/SCFTransformOps.td`:495) | a multi-result merge, then upstream |
| tiling, tile and fuse | `TilingInterface`; `scf.for` or `scf.forall` loops; consumer-and-producer fusion (read: `mlir/include/mlir/Dialect/SCF/Transforms/TileUsingInterface.h`:48, 445); full or partial reduction tiling (read: `mlir/include/mlir/Interfaces/TilingInterface.h`:54-64) | full reduction tiling only (D7) |
| bufferization | One-Shot, destination-passing style, `allocationFn` and `memCpyFn` hooks (read: `mlir/include/mlir/Dialect/Bufferization/IR/BufferizableOpInterface.h`:256-344); a cycle of calls analyzed body by body, its boundaries assumed read and written (read: `mlir/lib/Dialect/Bufferization/Transforms/OneShotModuleBufferize.cpp`:373-376; `FuncBufferizableOpInterfaceImpl.cpp`:165-205); `to_tensor` only with `restrict` (read: `BufferizationOps.td`:361-370); a constant tensor becomes a `memref.global` (read: `mlir/lib/Dialect/Arith/Transforms/BufferizableOpInterfaceImpl.cpp`:48-53) | our hooks, the grade in the encoding, heap releases (§9) |
| target facts | DLTI target specs and `transform.dlti.query` (read: `mlir/include/mlir/Dialect/DLTI/DLTIAttrs.td`:139-148; `TransformOps/DLTITransformOps.td`:18) | the entry's facts (§8.4) |
| sparse arrays | the encoding on the tensor type; codegen without a runtime library, allocating with `memref.alloc` (read: `mlir/lib/Dialect/SparseTensor/Transforms/SparseTensorCodegen.cpp`:139-142); numeric primary types only (read: `SparseTensorDialect.cpp`:922-980); `sparsification-and-bufferization` takes One-Shot's options (read: `SparseTensor/Transforms/Passes.h`:277-284) | §13 |
| SPMD | `shard.grid`, `sharding-propagation`, `shard-partition`, linalg's sharding models; a float `addf` reduction is an `all_reduce` Sum (read: `mlir/lib/Dialect/Linalg/Transforms/ShardingInterfaceImpl.cpp`:46-73) | parallel dimensions only (§12.2) |
| GPU mapping | `transform.gpu.map_forall_to_blocks`, `map_nested_forall_to_threads` (read: `mlir/include/mlir/Dialect/GPU/TransformOps/GPUTransformOps.td`:149, 267); the toolchain builds the AArch64 and X86 backends only (read: `tools/bootstrap.sh`:112) | §14 |
| differentiation | none | the library (§15) |

## 2. The language the compiler is given

This section fixes only what the compiler relies on; the surface is the
library's.

- **The library.** `libs/mlir-array`, a new in-house package in plain
  Idris over base's primitives, as `mlir-linear` is. An immutable array
  is `Array : (0 s : Shape) -> Type -> Type` with `Shape = SnocList Nat`,
  outermost axis first, and its extents are a singleton `Ext s` at
  quantity ω wherever a size is needed. A snoc list lets unification find
  a frame from an argument alone: `SnocList.(++)` recurses on its right
  argument, so `f ++ [<n]` evaluates to `f :< n` (read:
  `third_party/Idris2/libs/prelude/Prelude/Types.idr`:424-427), and the
  research probes accept with snoc lists the call they refuse with cons
  lists (measured by the research pass, Idris 2 `0.8.0-1c630e67c`:
  `Probe4.idr` accepted, `Probe5.idr` refused; typed-rank notes §8.2).
- **The model.** An array is a shape and its atoms in row-major order; a
  k-cell is the subarray of the last k axes and the frame the rest (read:
  `sources/papers/bernecky-1983-satn45-rank-operator/satn45a.htm`:149-189;
  `sources/docs/bqn/doc/array.md`:110-138). A function is written on
  cells, and `lift : (Array c a -> Array d b) -> Array (f ++ c) a ->
  Array (f ++ d) b` applies it over any frame; with two arguments one
  frame must be a prefix of the other, the shorter one's cells reused
  along the excess (read: `sources/docs/j/help/dictionary/dictb.htm`:94-98;
  `sources/papers/hui-1995-rank-uniformity/rank1.htm`, §0).
- **Value semantics.** An operation that changes an array returns a new
  one; the old one is unchanged. In place is the compiler's business
  (§9), and the in-place promise is the grade's (§9.5). The linear arrays
  of the library, `LArray s a`, are born fresh and leave only by `freeze`.
- **Two layers** (decision). A *primitive layer* the frontend recognizes
  by name (§4.1), whose plain definition over a record of the extents and
  a row-major backing is the meaning; and everything else, written only
  against the primitive layer. Reason: when an array type is a tensor,
  the frontend never meets code that looks inside the record; when it is
  not yet one (§3.4), the primitive layer compiles as written.
- **Coordinates are words.** In a loop body a coordinate is the loop's
  own index. A stored coordinate (a gather's index array, a permutation,
  a histogram's bins) must be a word in memory: an array of `Fin`, which
  is a big at run time (read: IdrOps.td:175-185), would be an array of
  counted values that no vector lane takes. The library's stored
  coordinate is a word with its bound erased; the conversions to and
  from `Fin` are its own.
- **Not an `Array`.** Ragged rows (offsets and flat data: Futhark's
  segmented arrays, read: `sources/code/futhark/src/Futhark/IR/SOACS/SOAC.hs`:81-146),
  and trees (Hsu's parent vectors, read:
  `sources/papers/hsu-2019-data-parallel-compiler/hsu-dissertation.pdf.txt`, §3)
  are library records of regular arrays whose operations are regular
  operations. An array of existentials, `Array s (Exists (\m => Array [<m] a))`,
  is an array of counted cells (§3.4).
- **Kept.** `Linear.Array` (growable, one object in world order) and
  base's `IOArray`, `Buffer` and `IORef` stay memrefs from birth.
  `Linear.Array`'s frozen `IArray a` becomes the rank-1 `Array` (§4.5).

## 3. Representation

### 3.1 Rank is a fact of the instance

**decision (D2).** An erased argument of type `Shape` keys a function
instance by its skeleton, the number of components of its canonical form
at the call, as type arguments key instances today; a runtime argument's
shape already keys one "when the type must reduce on the value" (read:
`compiler/src/IdrisMLIR/Frontend/Translate/Instances.idr`;
`Translate/State.idr`:27-40). Within an instance, `Array s a` has rank k,
the number of components of `s`, and is `tensor<?x…xE>` with k
dimensions. The frontend's `Rank` becomes a natural.

- **Why instances.** Every loop the compiler emits is at the array's own
  rank, so tiling, vectorization and partitioning see the real axes;
  every extent has one source, the tensor's dimension; and a call needs
  no reshape between the caller's rank and the callee's. A function
  polymorphic in a shape never looks inside it (it is a variable), so an
  instance per skeleton costs code size only, which the instance budget
  bounds (read: Instances.idr:35-36, 4096 per definition).
- **No ceiling.** Any k. A recursion whose skeleton shrinks from a known
  one (rank recursion on `Ext s`, total, as the research probe
  `Core2.idr`'s `sumAll` is) gives finitely many instances.
- **The opaque case.** A shape whose skeleton no instance can know (one
  built from run-time values, such as `replicate k 2`, or one that a
  recursion deepens at every call, which `growing` would refuse: read:
  Instances.idr:59-90) is one opaque component instead of a refusal: the
  array is one dimension of the shape's size, with its `Ext s` beside it
  as an ordinary value (a list of naturals, read only where the view
  changes); `idr-soa` (§3.4) separates the pair. Where a match makes the
  skeleton known again, the
  frontend expands the dimension by the extents (`tensor.expand_shape`
  takes a static reassociation and dynamic output extents: read:
  `mlir/include/mlir/Dialect/Tensor/IR/TensorOps.td`:1091). A reduction
  along a run-time axis of an opaque array is a three-dimensional view,
  prefix, axis and suffix, with run-time extents. This is the descriptor
  the research notes asked of the dialect (mlir-stack notes §3.2), made of
  values the program already has, so the dialect needs no type for it.
- **Erased does not mean constant.** The skeleton is the structure of
  the instance's types, the count of snoc cells; no extent is read from
  it (§3.2).

### 3.2 Extents are the array's own

**decision (D3).** Every extent is a run-time `index`: the tensor's
dimension, or the program's own `Ext` value, never an erased index read
as a number. A dimension becomes static (`tensor<3x4xf64>`) only where
constant propagation proves the run-time extent constant (recalled:
upstream's `tensor.empty` canonicalization folds constant extents into
the type; to check at the pin). Reason: Futhark's witnessed sizes, read
off the array that has them (read:
`sources/papers/bailly-2023-size-dependent/paper.pdf`, §2.1), and
AGENTS.md's rule. The library keeps a run-time shape equal to its type's
by construction, building every shape from `Ext` values: a trusted
invariant, as `Linear.Array`'s `0 <= size <= capacity` is.

### 3.3 The value: cell, base, extents

**decision (D4).**

- **Data.** A value array of rank k is k + 2 words: the cell (what
  counting and freeing see), the base (the address of the view's first
  element, inside the cell), and k extents, the elements dense and
  row-major from the base. Today's value is the cell and k sizes (read:
  Arrays.cppm:1-20); the base is new. In MLIR it is an identity-layout
  `memref<?x…xE>` whose descriptor's allocated pointer is the cell and
  whose aligned pointer is the base, as `arrayView` already makes them
  (read: ArrayView.cppm:35-47); its strides become the row-major products
  of the extents, which fixes that helper's stride 1.
- **Why the base.** Leading-axis slices (take, drop, a major cell, a row
  range) are the common structural operation of a leading-axis language
  (read: `sources/docs/bqn/doc/leading.md`, "The leading axis
  convention"), and a recursion on `drop 1 xs` would copy at every step
  if a slice could not cross a call. With the base, a contiguous slice
  and any reshape cross calls and live in the heap as they are.
- **Canonical form.** An array value that crosses a call that is not
  inlined, is returned, or is stored in the heap is dense and row-major
  from its base. A view that is not (a transpose, an interior slice, a
  broadcast, a reversal) is made canonical where it escapes: One-Shot's
  identity-layout boundary copies it (read:
  `mlir/include/mlir/Dialect/Bufferization/Transforms/Passes.td`:460-467),
  except a contiguous leading-axis subview, which is rebased (§9.4).
- **The cell** keeps today's layout. Counted element slots are born null
  (§9.1).

### 3.4 Elements

**decision (D5).**

- **Words** (integers, floats, characters, the tags of enumerations):
  tensors of the word.
- **Unboxed records and sums of words: one tensor per slot.** `idr-soa`
  splits a tensor of an unboxed record into one tensor per slot, and the
  record built or matched in a body into one block argument and one yield
  per slot; every structured op takes several inputs and results, and
  fusion and the vectorizer take multi-result generics. It runs after
  `idr-defunctionalize`, because that pass decides which records become
  boxes, so a record's slots are final only after it (read: Passes.td:337-343).
  The same pass separates any unboxed record whose fields are tensors (an
  opaque array and its `Ext`, §3.1), so that no tensor hides inside a
  value One-Shot cannot see into. Reason: a lane computes on a word; and
  Futhark's core language has tuples of arrays and no arrays of tuples, so
  one combinator can consume and produce several arrays (read:
  `sources/papers/henriksen-2019-incremental-flattening/paper.pdf`, §2).
- **Counted slots** (boxes, strings, bigs, closures, arrays of
  existentials): tensors of the counted type, which a memref can hold
  because every runtime value type is a memref element type (read:
  IdrOps.td:110-171). Copied by a counting copy, born null, counted per
  element in a structured body after bufferization (§10), never
  vectorized (the vectorizer refuses bodies that count: Passes.td:663-680).
- **Regular nesting is flat.** `Array f (Array c a)` has the
  representation of `Array (f ++ c) a`: every element has shape c by its
  type, so no check. An element read is a slice; building one from a
  cell function is the rank operator's assembly. SaC's with-loop
  scalarisation makes the same move as an optimization (read:
  `sources/papers/grelck-2006-sac/paper.pdf`, §3.4); here it is the
  representation.
- **One representation per type.** Whether an array type is a tensor
  depends on its element type alone, so every use of one type agrees.
  Until stage 5 an element type the compiler does not yet take compiles
  as the library writes it (§2, "Two layers").

### 3.5 A typed access has no guard

A read at a coordinate of the array's own shape is `tensor.extract` with
no `idr.check.in_bounds`; a gather reads its index array the same way.
The fact lives as the guard's absence, the rule `idr-in-bounds` already
follows (read: IdrOps.td:1835-1841). An integer becomes a coordinate only
through the library's checked conversion, whose check is the program's,
and `idr-in-bounds` proves it where it can. README.md's "no bounds check"
promise holds by construction for typed access.

## 4. What the frontend emits

### 4.1 The primitive layer

**decision (D1).** The frontend emits upstream ops wherever upstream has
the op, and the dialect's contract with the Idris side grows by `tensor`,
`linalg`, `scf` and `bufferization`, whose builders are generated from
their ODS as the others' are (read: `compiler/src/IdrisMLIR/Dialect/MemRef.idr`,
"Generated by idris-mlir-tblgen -gen-idris-dialect"), and whose ops the
parse of a program's module then admits (read:
`foreign/idr/lib/Driver/Run.cppm`, the contract's registry).

| Primitive | Emitted |
|---|---|
| `tabulate e f` | `tensor.empty` of `e`'s extents, then a `linalg.generic` with k parallel dimensions whose body is `f` at the `linalg.index` values |
| `lift` with scalar cells (`map`, `zipWith`, outer products of scalars) | one `linalg.generic` with projected-permutation maps; a shorter frame omits the trailing frame dimensions, so prefix agreement moves no data |
| `lift` with a cell of rank above 0 | `idr.array.lift` (§4.2, §6) |
| `foldl` along the leading axis, scalar combiner | a `linalg.generic` with one reduction dimension, run in index order (§4.3) |
| `foldl` with an array accumulator | `scf.for` over the leading axis, the accumulator a tensor carried by the loop |
| `scanl` along an axis | `idr.array.scan` |
| `scatter` with a combiner | `idr.array.scatter` |
| `index`; a gather by an index array | `tensor.extract`, in a body where it gathers |
| `take`, `drop`, a major cell, a slice | `tensor.extract_slice`, rank-reducing for a cell |
| `reshape` (sizes proved or checked equal) | `tensor.collapse_shape` to one dimension, then `tensor.expand_shape`: static reassociations, run-time extents |
| `transpose`, `swap` | a `linalg.generic` with a permutation map |
| `reverse`, `rotate` | a `linalg.generic` whose body reads at a computed index |
| `append` | `tensor.concat` |
| `pad`, `fill` | `tensor.pad`, `linalg.fill` |
| a literal array; a result of compile-time evaluation | `idr.array.constant` (§4.6) |
| `Linear.Array`'s `freeze`, and `thaw` of a value into it | `bufferization.to_tensor … restrict`, `idr.array.thaw` (§4.5) |
| `LArray`'s `freeze` and `thaw` | `idr.lin.use`, `idr.lin.enter` (§9.2) |
| sorting words | `idr.array.sort`, the runtime's |
| `extents` | `tensor.dim` of each axis |

Everything else (reductions with lanes, compress, histograms, inner and
outer products of any pair of functions, stencils, structural Under) is
library code over these. Reason: Futhark chose its second-order
combinators for their fusion algebra (read:
`sources/papers/henriksen-2017-futhark-thesis/thesis.pdf`, §7.1); here the
set is what lowers to exactly one structured op, so every composition is a
graph of structured ops the passes see. Fusion makes no special case of a
library function.

### 4.2 The rank operator

- **`idr.array.lift`** takes operands each with a static split into frame
  and cell, a principal frame (prefix agreement makes it one of the
  operands' frames: read: `sources/papers/slepak-2019-semantics/formalism.tex`:530-542),
  and a body region that takes the cells as tensors and yields the result
  cells; its results are the principal frame followed by the result
  cells. It is in destination-passing style.
- **With scalar cells it is a `linalg.generic`**, and the frontend emits
  the generic directly.
- **An empty frame needs no evaluation.** The result cells' extents are
  their type's, from `Ext` values or the operands' extents. SATN-45's
  empty-frame convention, J's cell of fills and BQN's inferred fills
  (read: satn45a.htm:199-201; dictb.htm:110-114;
  `sources/docs/bqn/commentary/problems.md`:11-13) have no counterpart.
- **The one generalization.** Each row, outer products, inner products of
  any pair of functions and batched linear algebra are library definitions
  over `lift` (read: `sources/papers/hui-2009-rank-operator/app1.htm`,
  `app2.htm`; satn45a.htm, the `⌹` example).

### 4.3 Order is meaning

**decision (D7).** The compiler never reassociates a reduction, a scan
or a combine. Every loop runs its reduction dimensions in index order;
vector lanes and shards are given parallel dimensions only; reduction
tiling is always `FullReduction` (read: TilingInterface.h:54-64), and
`PartialReductionOpInterface` is never used.

A reduction is parallel by its *shape*, which the library writes in plain
Idris over the primitive layer, so the compiler never knows its
constants:

- **`reduce op z xs`** over n elements: extend `xs` with `z` to C · 4096
  elements, C = ⌈n / 4096⌉; view it as [C, 256, 16]; fold each (chunk,
  lane) from `z` in order along the middle axis; pair adjacent lanes level
  by level, 16 to 1; pair adjacent chunks level by level, an odd last one
  carried up. The lanes are contiguous, so vectors take them; the chunks
  are independent, so shards take them.
- **`scan op z xs`**: chunks of 4096 scanned in order (`idr.array.scan`
  along the chunk's axis, parallel over chunks), the chunks' totals
  scanned in order, and each chunk's carry combined into its elements by
  a parallel map.
- **A histogram**: each chunk scattered into private bins in order
  (`idr.array.scatter`, batched over chunks), then the bins reduced over
  chunks by `reduce`.
- **`foldl` and `scanl`** are the sequential ones. An inner product folds
  k in order with `fma` (§8.3).

Reasons:

1. **One output per program.** No oracle means one expected file for
   every target, vector width and shard count (0005 D8); a compiler that
   reassociates a float reduction cannot give it.
2. **Nothing to prove or keep.** An association written in the program
   needs no law, so no fact about an operator exists to lose. For a
   lawful operator, integer addition say, the tree's result is the
   sequential result, so laws would buy no speed the tree does not give.
3. **The padding is in the definition.** Masking the last tile with `z`
   is exact whatever `z` is; no identity law is assumed.
4. **Floats become parallel.** A float sum, which has no law, gets
   sixteen lanes and every shard. The pairwise levels also bound its
   rounding error by the tree's depth instead of n (conjecture: the
   usual bound for pairwise summation).

**The constants** 16 and 4096 are the library's and are part of the
meaning: changing one changes printed results, so it is a decision about
the language, never a tuning knob. 16 is the widest f32 vector of either
target family (AVX-512's), so every target's vectors divide it, and it
gives eight independent f64 chains on NEON (recalled: two f64 lanes per
register). 4096 f64 elements are 32 KiB, an x86-64-v3 L1 data cache
(recalled), and 2^16 elements already make 16 chunks, enough for 12
shards.

`shard-partition` is never given a reduction dimension (its linalg model
would make a float sum an `all_reduce` Sum: read:
ShardingInterfaceImpl.cpp:46-73).

### 4.4 Gathers, scatters, compress, sort

- **Gather**: a generic whose body extracts at a computed index; the
  vectorizer's N-dimensional extract path makes it a gather or a
  contiguous load, and `idr-vectorize` asks for that path where a body
  extracts (today it passes false: Tiles.cppm:142).
- **`idr.array.scatter`**: a destination, indices, values and a combiner
  region; sequential in the values' index order, parallel over batch
  dimensions; in place on its destination. Upstream's `tensor.scatter`
  has neither a combiner nor a bufferization model (read: TensorOps.td:1619;
  the registrations above).
- **Compress** (filter, replicate): flags, an exclusive integer scan
  (integer addition is lawful, so the chunked scan gives the sequential
  result), and a scatter into an array the size of the total. Fusion
  stops there, as it must at a size-changing primitive (read:
  `sources/docs/bqn/implementation/compile/fusion.md`:9-11) and as `linalg`
  does anyway.
- **Sort**: of words by the runtime's sort, its one meaning in `runtime/`;
  with a program's comparison, the library's merge sort.

### 4.5 Values meet the mutable world

- **`freeze`** is `bufferization.to_tensor %m restrict`, not writable: a
  frozen array may be shared, so a value operation that would write it
  copies.
- **`thaw`** is `idr.array.thaw %t : tensor -> memref`, a release
  (§9.2): it copies only when the value is read again or its buffer is
  not writable, so thawing at a last use copies nothing.
- **`Linear.Array`** keeps its one-object meaning for `read`, `write`,
  `push` and `pop`. Its loops become value operations: `generate n f` is
  `thaw (tabulate [<n] f')`; `ifoldl`, `imap`, `map`, `zipWith` and
  `sum` (left to right, as documented) are folds and maps of the frozen
  `Array`; `IArray a` is the rank-1 `Array`. A `zipWith` over the shorter
  of two lengths reads both below that length by its coordinate's type,
  so the test on entry `readAsInputs` makes today (read: Loops.cppm:176-243)
  is gone.

### 4.6 Compile-time evaluation and constants

**decision (D19).**

- **Pure array code is evaluated.** Value-array code has no world, so a
  closed call of it is evaluated at compile time, as AGENTS.md requires
  of pure code; today none is, because array code performs IO through
  forged worlds and `idr-eval` runs only calls that perform none (read:
  Passes.td:119-157). Evaluation lowers alike: its round runs `idr-soa`,
  `idr-batch` and `idr-bufferize` before `idr-lower`, as a program does;
  it skips `idr-fuse` and `idr-schedule`, which change speed and never
  meaning (D7, D8).
- **Constants are cells.** A result array comes back as
  `idr.array.constant` (a word array as a dense elements attribute, any
  other as one attribute per element) and lowers to a persistent static
  cell, count 0 (read: `runtime/idris_rt.h`:26-36). Upstream's constant
  bufferization makes a `memref.global` (read: Arith
  BufferizableOpInterfaceImpl.cpp:48-53), which has no header, while an
  array must be a cell to be stored, sent or counted. Results over the
  existing 1 MiB limit stay for run time.

## 5. The pipeline

**decision.** The steps, new ones in bold:

1. `idr-isolate`, `idr-contify`, `idr-simplify`: unchanged. `linalg` and
   `tensor` ops pass through the inliner, specialization, `sccp`,
   canonicalization and evaluation.
2. `idr-defunctionalize`, `canonicalize`.
3. **`idr-soa`** (§3.4).
4. **`idr-batch`** (§6).
5. **`idr-fuse`** (§7).
6. **`idr-schedule`** (§8): cache tiles, packs, register tiles of
   contractions, partitions.
7. **`idr-bufferize`** (§9): One-Shot module bufferization with our hooks;
   `sparsification-and-bufferization` with the same options when the
   module has sparse arrays.
8. `idr-stack` (now also array cells that never leave their frame),
   `idr-accumulate`, `idr-rc` (§10), `idr-demand` (§9.5), `idr-trmc`,
   `idr-tail-loops`, `idr-narrow`, `idr-in-bounds`, `idr-lower` (without
   `Loops.cppm`'s memref half), `idr-entry`.
9. `idr-vectorize` (§11), `idr-narrow-lanes`, `convert-linalg-to-loops`
   and the rest, as today.

Why this order:

- **Bufferization before counting.** Every cell bufferization allocates
  must be counted, and counting runs on functional code, where recursion
  is still a call (read: PipelineSteps.cc's comment at `idr-stack`). A
  grade speaks of cells, which a tensor does not have.
- **Fusion and scheduling on tensors.** Use-def chains are every
  dependence there, so fusion and tiling need no alias analysis (read:
  `sources/papers/vasilache-2022-structured-codegen/2-codegen-flow-overview.tex`:25-31),
  and the in-place decisions that follow see the fused program (Futhark
  fuses before it decides memory: dataparallel notes §1.2).
- **Vectorization stays late.** A guard `idr-in-bounds` erases makes a
  body vectorizable, and `idr-in-bounds` runs on the loops `idr-narrow`
  leaves. Register tiles decided early (§8.3) reach it as generics of
  static shape, so the decision is made once.

## 6. Batching the rank operator

**decision (D6).** `idr-batch` lowers every `idr.array.lift`:

- **When every op of the body has a batching rule**, the batched ops
  replace it: a linalg op gets the frame's dimensions prepended,
  parallel, and an operand defined outside the body is read without them
  (a broadcast, by its map); `tensor.empty` gets the frame's extents;
  slices, reshapes, pads and concatenations get full frame dimensions; a
  scalar computed from a cell becomes a frame-shaped tensor, and its
  `arith` and `math` ops elementwise generics; `tensor.extract` at a
  frame-dependent index becomes a gather; an `scf.for` whose bounds do
  not depend on the cell carries batched values; an `scf.if` whose
  branches can neither crash nor diverge computes both and selects;
  `idr.array.scan` and `scatter` get the frame's dimensions.
- **Otherwise**, an `scf.forall` over the frame, cells taken by
  `tensor.extract_slice` and results put by
  `tensor.parallel_insert_slice` (read: `mlir/include/mlir/Dialect/SCF/IR/SCFOps.td`:336);
  or, when the body may crash or diverge, an `scf.for` over the frame in
  row-major order (§7's rule).
- **What it is.** These are batching rules for a closed op set, and
  regular flattening in Futhark's sense: nested parallel cells become one
  iteration space, which the partitioner then tiles whole (§12.1;
  moderate flattening: henriksen-2019 §3.1). It is not a raise: the
  lift op carries the structure and batching lowers it, as Vasilache's
  flow asks (2-codegen-flow-overview.tex:33-62).
- **Reason.** Hui measured integrated rank support, which strides through
  the argument instead of building cells, at 1.8x to 157.3x over the
  general routine (read: rank1.htm, §1, the table); an indexing map is
  integrated rank support for every function.

## 7. Fusion

**decision (D8).** `idr-fuse` runs upstream's elementwise fusion patterns
on generics (named ops generalized first), reshape propagation and
unit-dimension folding, under our control function:

1. **Never duplicate work.** A producer is fused into a consumer that
   reads it through one operand. A producer with other users is fused only
   as upstream's rewrite does it, keeping its result as an extra output of
   the fused op, computed once (read: ElementwiseOpFusion.cpp:114-138).
2. **Never lose parallelism.** Upstream's own conditions: an all-parallel
   producer, and every loop of a reducing consumer still bounded by an
   input (read: :159-200).
3. **Never reorder a crash.** Two ops are fused only where at most one of
   them may crash or diverge; then the fused loop meets the first crash
   the program would meet.

Then:

- **Horizontal.** Sibling generics over one iteration domain reading a
  common input become one multi-result generic: SaC computes `minval`
  and `maxval` in one sweep this way (read: grelck-2006 §3.3), Futhark
  fuses horizontally (thesis §7.1). Ours first, then proposed upstream
  (Upstream, U1).
- **Into reductions and contractions.** By tile-and-fuse (§8.1).
- **Measured motivation.** Futhark without fusion is 1.42x slower on
  k-means, 4.55x on LavaMD, 10.1x on Crystal, and four programs fail for
  memory (read: thesis.pdf §10.1.5).
- **Proof.** `fused=@f`: after bufferization, no array is allocated in @f
  between two loops of @f that the rules would have made one.

## 8. Scheduling

### 8.1 What `idr-schedule` decides

**decision.** For each root (an op whose result nothing fuses further:
reductions, contractions, scans, the last op of a fused group), from its
iterator types, its maps and the module's DLTI facts:

- **Cache tiles where there is reuse:** where an operand's map omits a
  loop dimension (contractions, stencils, broadcasts), the tile's working
  set fits L1 inside and L2 outside. A one-dimensional loop that only
  streams is not tiled.
- **Tile and fuse:** producers fused into the tile loops
  (`tileConsumerAndFuseProducersUsingSCF`), and a consumer of a reduction
  fused into its loop where it reads the result elementwise.
- **Packs** (`linalg.pack`) for a contraction whose operands exceed L2.
- **Register tiles** for contractions (§8.3).
- **The partition** (§12.1).
- Parallel dimensions get parallel tiles; reduction dimensions tile in
  order (D7). An op that may crash or diverge is not tiled.

### 8.2 The schedule is IR

**decision (D9).** `idr-schedule` decides in C++ and applies its decision
as a transform script it builds for each function
(`transform.structured.tile_using_for`, `tile_using_forall`, `fuse`,
`pack`), run by the transform interpreter; `--dump-dir` keeps the script.
Reasons: every decision is arithmetic on an op and the target's facts,
which is C++'s; the script replays any schedule with upstream's `mlir-opt
-transform-interpreter` on upstream ops alone, which is the reduction to
upstream dialects and tools AGENTS.md asks for before an upstream report;
and whole pipelines as transform scripts cost at most 2.6% of compile time
(read: `sources/papers/lucke-2024-transform-dialect/main.tex`:918, 950).

### 8.3 Contractions

**decision (D13).**

- **The meaning.** An inner product folds k in order with `fma` at each
  step: one rounding per step, and the peak operation of both targets'
  FMA units (recalled: x86-64-v3 has FMA3; apple-m1 has FMLA). The C
  baseline calls `fma()` in the same order.
- **Register blocking keeps the order.** Each output element accumulates
  its k in order while vector lanes run along j: Vasilache reached 92% of
  peak on that kernel shape without reassociating anything (read:
  `vasilache-2022-structured-codegen/4-experiments.tex`:352).
- **Padding never enters a reduction.** The k remainder is peeled; the i
  and j edges of packed panels are padded and their results discarded.
  Reason: a padded k step adds a product of zeros, which turns a sum of
  −0 into +0 (IEEE 754).

### 8.4 Target facts

**decision (D10).** The target's entry in `CMakeLists.txt` gains the
vector width in bits, the vector register count, the L1 data and L2
sizes of the smallest core among the target's machines, and the
partition work threshold W (§12.1). `idr-target` writes them as the
module's DLTI target spec; `idr-schedule` and `idr-vectorize` read them
there. `vectorBits`'s test of x86 goes. Values: apple-m1 128 bits and 32
registers, x86-64-v3 256 bits and 16 registers (recalled); the cache sizes
from the vendors' documents when the entries are written, and W measured
(§12.1).

## 9. Bufferization meets the grades

### 9.1 Options and hooks

**decision.** `idr-bufferize` is One-Shot module bufferization
(`runOneShotModuleBufferize`) with:

- `bufferize-function-boundaries`, the boundary type the identity layout
  (canonical form, §3.3);
- `allocationFn` building `idr.array.alloc`: a cell of the extents'
  product, word elements unwritten and counted slots null, which the free
  walk skips (read: idris_rt.h:66-68, 197);
- `memCpyFn` building `idr.array.copy`: elements copied, each counted
  slot taking one reference;
- no deallocation: counting frees every cell;
- `copyBeforeWrite` off; `idr.array.constant` bufferized to its static
  cell, not writable;
- with sparse arrays, `sparsification-and-bufferization` given these
  options (read: SparseTensor/Transforms/Passes.h:277-284).

### 9.2 The boundary contract

**decision (D11).**

- **Arrays at calls are tensors**, analyzed by One-Shot's module
  analysis: a callee may write its parameter in place, and each caller
  copies where it still reads the argument or the argument's buffer is not
  writable (read: Bufferization `Passes.td`:469-472).
- **A linear array is a tensor to One-Shot too.** Inside `idr-bufferize`
  a graded tensor `!idr.q<g, tensor<T>>` is spelled `tensor<T,
  #idr.grade<g>>`, the grade as the tensor's encoding (the attribute made
  of the same two enums as `!idr.q`'s grade: IdrOps.td:83-99), so that
  One-Shot analyzes it as the tensor it is, linear parameters and results
  included; `idr.lin.enter` and `idr.lin.use` are casts between the two
  spellings that keep their operand's buffer and neither read nor write
  it (the earlier draft's model). A callee writes its linear parameter in
  place, and its caller copies exactly when it still reads the argument or
  the argument is not writable. When One-Shot is done, every position that
  had a grade gets `!idr.q<g, memref<T>>` back. Between passes the grade
  is the wrapper, as for every other value, and the verifier checks it
  there.
- **The heap.** A store of a tensor into a cell (a constructor's field, a
  closure's capture, an element of an array, a message of 0005 §5) is a
  write of its buffer as One-Shot sees it, a *release*: One-Shot copies
  when the program still uses the tensor afterwards, so a cell never holds
  a buffer that tensor code may still write. A read from the heap is
  `to_tensor restrict`, not writable. `thaw` (§4.5) is the same release.

Reasons:

1. `!idr.q` cannot be a `TensorLikeType`: a type interface belongs to the
   type class, not to an instance, so every graded value, the world and a
   linear integer included, would be a tensor to One-Shot (read:
   `mlir/include/mlir/Dialect/Bufferization/IR/BufferizationTypeInterfaces.td`:18-50;
   `hasTensorSignature` in OneShotModuleBufferize.cpp:298-304). The
   encoding makes a graded array a builtin tensor, which is one, and only
   for the one pass that needs it to be.
2. A linear binder does not imply unique ownership: an unrestricted value
   may be passed at quantity 1, and a linear field of a shared cell is
   shared. Exclusivity is therefore One-Shot's conclusion, from every alias
   in tensor code with the heap's buffers read-only to it, never the
   grade's assumption; the grade is what the promise of §9.5 checks.
3. One-Shot's analysis stays the only in-place analysis, and no other pass
   meets the second spelling of a grade.
4. Two read-only tensors restricted to one heap buffer cannot cause an
   in-place write, since a write to either goes out of place; `restrict`
   protects against a write the analysis believes unaliased (conjecture;
   stage 1 pins it with a test that reads one field twice and updates one
   copy).

### 9.3 Recursion

- Idris loops are recursion until `idr-tail-loops`, which runs after
  counting. One-Shot analyzes a cycle of calls body by body and assumes
  its boundaries read and write every operand (read:
  OneShotModuleBufferize.cpp:373-376, 477-481; FuncBufferizableOpInterfaceImpl.cpp:165-205).
- A tail call costs nothing: its operands are not read after it.
- A recursion that reads an array after passing it on (divide and conquer
  over slices) copies at each call. **Measurement** (kept from the
  earlier draft): `idr-bufferize` reports each copy it makes at a call of
  a recursive function as a `missed` remark with One-Shot's conflict (the
  read, the conflicting write, the last write: read:
  `sources/docs/mlir/docs/Bufferization.md`, "Debugging Buffer Copies").
  The first `bench/` program with such a copy in its hot path is the
  threshold for an upstream change that analyzes a cycle of calls to a
  fixpoint (Upstream, U2).

### 9.4 Views across boundaries

- A contiguous leading-axis subview (offsets on the leading dimensions of
  a dense array, inner dimensions whole) that meets an identity-layout
  boundary is rebased by `idr.array.rebase` (the aligned pointer moved to
  the view's first element, offset 0) instead of copied. Sound because
  One-Shot has already found the alias safe; only the type differed.
- Any other view is copied there. **Measurement:** `idr-bufferize` counts
  boundary copies; a `bench/` program spending more than 5% of its time
  in them is the threshold for a strided boundary on the callee it
  reaches, a clone per layout, since the layout is in the memref type and
  a clone's key is its types.

### 9.5 The in-place promise for arrays

**decision (D20).** README.md's promise gains an array clause: a write to
an array that reached it through quantity-1 positions only (a chain of
`lin.use`, destination-passing updates and `lin.enter`) is in place. A
copy there, because the program still reads an old version or passed an
unrestricted value at quantity 1, is `unsupported (uniqueness)` under
`--demand-in-place`, naming the write and One-Shot's conflict. A copy from
a buffer that is not writable (a constant) is a copy under both meanings
and is allowed. The check is structural after bufferization: no
`idr.array.copy` reads an array that came out of a linear position
(`idr.lin.use`) or feeds one (`idr.lin.enter`), unless its source is a
constant cell. `idr-demand` checks it beside its clause for boxes (read:
Passes.td:642-657), and it becomes the default with the rest of the
promise.

An array in an unboxed record stays in tensor code (`idr-soa` splits the
record, §3.4), so a record of arrays threaded at quantity 1 is updated in
place. An array in a boxed record is read from the heap, read-only to
One-Shot, so its update copies: under `--demand-in-place` that is the
same rejection, naming the box, since bufferization runs before counting
can prove the box exclusive (§5). A `bench/` program that needs such an
array updated in place is the threshold for moving the box's exclusivity
ahead of bufferization.

## 10. Counting after bufferization

**decision (D12).**

- **Arrays are cells.** `idr-rc` grades every array as any value: a fresh
  cell `excl`, a shared one `own` (read: Passes.td:591-622).
- **A structured op borrows its operands.** `isArrayLoop` answers for
  every structured op, `linalg` and ours, instead of two op names (read:
  `foreign/idr/lib/Ownership/ArrayLoop.cppm`), and `pure-array-loops`
  states its property of them (read: `foreign/idr/lib/Expect/PureArrayLoops.cppm`).
- **Counted elements in a body.** An input element is a view of the
  cell's slot. The output's block argument is the slot's old element; the
  yield moves the new one in and releases the old one unless it is the
  old one, which is `idr.array.set`'s meaning per element (read:
  IdrOps.td:1869-1887). `linalg.fill` of a counted value takes one
  reference per element, as `idr.array.new`'s fill does (read:
  Arrays.cppm:75-145).
- **Array reuse.** An `idr.array.copy` whose source dies there takes the
  source's cell when it is unique, with no test when it is `excl`: the
  array case of reset and reuse. It is the dynamic half of in place: One-
  Shot decides on use-def chains, and counting catches the heap values
  that are unique at run time. It is outside the promise of §9.5, which
  has no run-time test.
- **The stack.** `idr-stack` takes `idr.array.alloc` cells that never
  leave their frame, under its size limits (read: Passes.td:495-514), so
  a fold's 0-dimensional accumulator is a frame slot, as `Loops.cppm`'s
  alloca makes it today.
- **A partitioned body counts nothing** (§12.1): `counts-nothing` holds
  there (read: Passes.td:749-750).

## 11. Vectorization

**decision.** `idr-vectorize`, generalized:

- **The vector shape.** The innermost parallel dimension that is
  contiguous in the output gets the lanes, the vector width over the
  widest word, both from DLTI; the other parallel dimensions get 1, and
  reduction dimensions 1, so the program's order holds as today.
- **Register tiles.** A generic whose dimensions are all static and fit
  the register budget (a register tile from §8.3) is vectorized whole at
  its shape: a contraction's tile becomes outer-product FMAs.
- **Transposed reads.** A two-dimensional tile whose read runs across
  rows becomes `vector.transpose`, since a reduction along the contiguous
  axis is the slow case (read: 4-experiments.tex:208-214).
- **Gathers** take the N-dimensional extract path.
- **Unchanged:** full tiles unmasked and the last masked; a body the
  vectorizer refuses stays whole (PINS.md `vectorize-precondition-body`);
  `idr-narrow-lanes`.

## 12. Multicore

### 12.1 Partitioned loops on 0005's shards

0005 §8 owns the lowering of `scf.forall` to a fork per shard and a join,
and the runtime. This section owns which array loops become one.

**decision (D14).**

- **What.** `idr-schedule` tiles a root's leading parallel dimensions
  (after batching: frames, and the chunk dimensions of the library's
  trees) with `tile_using_forall` into enough tiles for the shards, a
  run-time count, mapped by `#idr.shards`.
- **When.** The body can neither crash nor diverge; its elements are
  words, so it counts nothing; and its work (the iteration space's size
  times the body's ops) is at least W. Two versions under one test, as
  `idr-narrow-lanes` versions a loop.
- **W** is the work at which the partitioned row loop of spectral-norm
  breaks even on the target, rounded up to a power of two, in the
  target's entry. It is a work bound rather than an extent bound because
  a 5500-element map is not worth a fork and a 5500-row matrix product is.
- **Determinism.** Only parallel dimensions are partitioned, so every
  shard count prints the same output (0005 D8).
- **The arrays reach every shard by pointer** for the duration of the
  join, which is sound because a partitioned body touches no count and
  each tile writes its own slice (0005 §8).
- **Proof.** `partitioned=@f`: some loop of @f is mapped to shards, and
  every such loop's body counts nothing and can neither crash nor
  diverge.

### 12.2 Region SPMD through `shard-partition`

By 0005's rule for its P5: when it runs spectral-norm faster than
per-loop partitioning beyond the run-to-run spread. Then a region of roots
is outlined (`outlineSingleBlockRegion`), its tensors annotated
`shard.shard` along parallel dimensions only, and `sharding-propagation`
and `shard-partition` make it SPMD. Its collectives lower to 0005's
runtime: an `all_gather` of a result is each shard writing its slice of
one buffer. Its gain is one fork and one join for a region instead of one
per loop.

## 13. Sparse arrays

**decision (D15).**

- **The format is a type index.** `SArray (fmt : Format) s a`, with levels
  dense, compressed or singleton and an order, monomorphised into
  `#sparse_tensor.encoding` on the tensor type: sparsity is a property of
  the type and the same structured op lowers dense or sparse (read:
  `sources/papers/bik-2022-sparse-mlir/mlir.tex`:45-70). The same lifted
  functions apply, and `sparsification` decides the loops.
- **The meaning is the dense array.** A sparse array denotes its dense
  array with zeros. The library gives each lifted function its absent
  cases as its own values at zero (`f 0 0`, `f x 0`, `f 0 y` into the
  regions of `sparse_tensor.binary` and `unary`), so the sparse result is
  exactly the dense one.
- **No runtime library.** `enable-runtime-library=false` and
  `sparse-tensor-codegen`; the default calls a C++ runtime library (read:
  SparseTensor `Passes.td`:191, 244-245).
- **Numeric elements only**, as upstream allows (read:
  SparseTensorDialect.cpp:922); any other element is `unsupported (sparse
  element)`.
- **Storage.** Positions, coordinates and values are value arrays in a
  library record; `sparse_tensor.assemble` at use and `disassemble` into
  fresh cells at results. The library's constructors check or prove the
  invariants `assemble` assumes, since it "does not perform any sanity
  test" (read: `SparseTensorOps.td`:76-79). The sparsifier's own
  temporaries are `memref.alloc` and its own deallocations (read:
  SparseTensorCodegen.cpp:139-142). **Measurement:** if `disassemble`'s
  copies take more than 5% of spmv's time, an upstream change routes the
  sparse codegen's allocations through `allocationFn` (Upstream, U3).

## 14. GPU, later, through the same tensor level

**decision (D16).**

- **Nothing above `idr-schedule` assumes a CPU.** Tensors, batching,
  fusion and the partition decision are device-free; a device enters at
  tiling, where `scf.forall` carries a device mapping (read:
  `mlir/include/mlir/Dialect/SCF/IR/DeviceMappingInterface.td`:22) and
  `transform.gpu.map_forall_to_blocks` and `map_nested_forall_to_threads`
  map it (read: GPUTransformOps.td:149, 267).
- **A device is a target entry** beside its host's: the device triple,
  its DLTI facts, the runtime's device layer.
- **Static linking chooses the devices.** A Linux executable is a static
  PIE and cannot load `libcuda` or a Vulkan loader, so the Linux device
  is AMD's, through the kernel's KFD interface with LLVM's AMDGPU backend,
  and NVIDIA's, whose user-space driver is shared only, is out (recalled).
  macOS may link its own frameworks, so the Mac device is Metal: MLIR's
  SPIR-V path, a pinned SPIRV-Cross making Metal source, compiled by the
  OS at program start (recalled).
- **Gates.** After stage 6 meets its goals; both device entries land
  together, as AGENTS.md requires of a change; the toolchain gains the
  AMDGPU backend through CI, never a local LLVM build; and a device entry
  stays only if some dense benchmark runs at least twice as fast on it as
  on every shard of its host.
- **Device code counts nothing**, only word arrays move, and the trees
  are the same, so outputs agree.

## 15. Differentiation where it falls out

**decision (D17).**

- **Forward mode** is free: a dual number is a record of two words, so an
  array of duals is two tensors (§3.4), and code written over a numeric
  interface instantiated at duals is ordinary code.
- **Reverse mode** falls out of the primitive layer being closed under
  transposition: map to map, reduce to broadcast, broadcast to reduce,
  gather to scatter with addition, scan to reverse scan, slice to pad,
  transpose and reshape to themselves. Dex's transposition turns repeated
  reading into accumulation and reverses iteration order (read:
  `sources/papers/paszke-2021-dex/main.tex`:1300-1305, 1326-1327). The
  library's reverse mode, a pullback per primitive, is therefore a
  composition of the same primitives, compiled by the same pipeline, its
  cotangents linear arrays updated in place (§9.5). A broadcast's
  transpose is the library's `reduce`, so a gradient is deterministic too.
- **What it costs.** Where the program's shape is static, specialization
  removes the dictionaries and defunctionalization the pullback closures
  (conjecture). Data-dependent control flow keeps a run-time tape: slower,
  correct.
- **No AD pass in the compiler.** A derivative's float order is part of
  its meaning, and the library's definition is that meaning.
- **Measurement:** logreg-grad's gradient within 1.5x of the hand-written
  C gradient (decision; Dex's "small constant multiple" of the primal
  cost, read: main.tex:1302, made a number).

## 16. The idr dialect: what it adds and deletes

| | |
|---|---|
| **Ops added** | `idr.array.lift` (§4.2), `scan` (§4.3), `scatter` (§4.4), `alloc` and `copy` (§9.1), `thaw` (§4.5), `rebase` (§9.4), `constant` (§4.6), `sort` (§4.4) |
| **Interfaces they implement** | `DestinationStyleOpInterface`; `TilingInterface` (lift: frame dimensions parallel; scan and scatter: batch dimensions parallel, the sequential dimension tiled in order with its state carried); `BufferizableOpInterface`, also for `idr.lin.enter` and `use` (casts keeping the buffer) and for `idr.con` and closures with tensor operands (releases); `ShardingInterface` at stage 9 |
| **Attributes** | `#idr.shards`, a device mapping for `scf.forall`, on which 0005's lowering keys; `#idr.grade`, a tensor encoding made of the grade's two enums, which exists only inside `idr-bufferize` (§9.2) |
| **Passes added** | `idr-soa`, `idr-batch`, `idr-fuse`, `idr-schedule`, `idr-bufferize` |
| **Passes changed** | `idr-vectorize` (§11), `idr-rc` and `idr-stack` (§10), `idr-demand` (§9.5), `idr-in-bounds` (the length relation also starts at `idr.array.alloc` and every dimension), `idr-eval` (its round, §4.6), `idr-target` (§8.4) |
| **Properties of `idr-expect`** | `batched=@f` (no frame loop is left from a lift in @f), `fused=@f` (§7), `in-place=@f` (no copy of an array in @f), `program-order` (no reduction dimension anywhere has more than one lane or a partition), `partitioned=@f` (§12.1) |
| **Deleted** | `idr.array.generate` and `fold`; `Idr_Rank1ArrayValue` as a loop's operand type; `Loops.cppm`'s memref half; the `ArrayLoop` hook and its region signatures; `Rank0 | Rank1`; `vectorBits`'s test of x86 |

## Performance goals

### The suite

Each program has three versions: Idris over `libs/mlir-array`; C, built by
the pinned clang at `-O2` as `bench/` builds C today, with the same
algorithm and the same float order (`fma()` where the library uses it, the
same trees); and Futhark, the same algorithm, whose generated C
(`futhark c` and `futhark multicore`) is compiled by the pinned clang
(D18).

| Program | Input | Exercises | Stage |
|---|---|---|---|
| spectral-norm-linear | 5500 | today's best, kept | 1 |
| fannkuch-linear | 12 | `Linear.Array` writes, kept | 1 |
| matmul | 2048², f64 | tiles, packs, register tiles, `fma` | 2 (correct), 4 (goal) |
| mandelbrot-array | 8000², escape counts | a two-dimensional `tabulate`, partition | 2 |
| histogram | 2^27 values, 4096 bins | chunked scatter and the tree | 2 |
| radix-sort | 2^26 i32 keys | scan and scatter | 2 |
| spectral-norm-array | 5500 | lifted folds, a fused zipWith and sum | 3 |
| nbody-array | 20000 bodies, 10 steps | records as tensors, a lifted reduce | 3 |
| backprop | Rodinia's, input layer 2^20 | a matrix-vector product, an outer-product update in place | 3 |
| kmeans | generated, 494019 × 34, k = 5 | distances, argmin, histogram sums, in place | 3 |
| locvolcalib | FinPar small and medium | batched tridiagonal solves (scans) | 3 |
| hotspot | 1024², 360 iterations | a stencil, double buffering in place | 4 |
| srad | 2048², 100 iterations | stencils and reductions | 4 |
| spmv | CSR, 10^6 rows × 10, 100 iterations | sparse | 7 |
| logreg-grad | 10^6 × 64, 100 steps | reverse mode | 8 |

### The goals

**decision.** On both targets, best of 5, each ratio against the same
run's baseline (`bench/README.md`, "How to read them"):

- **G1, one thread against C:** at parity or faster (a ratio of at least
  1 within the record's spread) on every program; matmul at least 3x the
  C triple loop and at least 70% of one core's FMA peak.
- **G2, one thread against `futhark c`:** at parity or faster on every
  program.
- **G3, all cores:** at 8 shards on the M2 Max and 4 on the Linux record
  machine, at parity with or faster than `futhark multicore` at the same
  thread count; a speedup over one shard of at least 0.75 × shards on the
  compute-bound programs (matmul, mandelbrot-array, nbody-array) and at
  least 0.4 × shards on the bandwidth-bound ones (hotspot, srad, spmv,
  histogram).
- **G4, no regression:** every existing `bench/` program within its
  record's spread; no program's compile time up by more than 25%.
- **G5, memory:** `IDRIS_RT_LIVE=1` reports zero live cells for every new
  program.

Reasons: C is the floor, since this compiler sees the whole program and
its types, and the C is written in the same order, so a gap is the
compiler's. Futhark is the closest prior art: a functional array language
with fusion, uniqueness and size types, compiled to CPUs by its `c` and
`multicore` backends (recalled; its thesis measures GPUs, against
reference implementations: read: thesis.pdf §10.1). 70% of peak is below
Vasilache's 92% because the schedule is decided from the target's facts,
not chosen by an expert per kernel (read: 4-experiments.tex:172)
(conjecture). A goal a stage does not meet
blocks the next stage on that program until it is met or its reason is
measured and written into this proposal.

### The Futhark baseline

**decision (D18).** Futhark is pinned in `toolchain.lock.json` as a
bench-only tool, as Chez is for the Chez column. Its generated C is
committed beside each program's Futhark source and compiled on both
targets by the pinned clang, so the Mac needs no Futhark (recalled: its
release binaries are for Linux x86-64); `tests/bench` regenerates the C on
Linux and checks it matches. The licences of the Rodinia and FinPar
programs are checked before any is committed (to check).

## Staged plan

Each stage passes `make check`, `make build`, `make test`, `make test-idr`
and `make test-mlir-tools` on both targets, and runs `bench/` on both.
Stages 1 to 5 are in order; 6 follows 5 and 0005's P4; 7 and 8 follow 4;
9 and 10 wait on their measurements.

**1. Value arrays as tensors, rank 1** (§4, §9, §10).

- **Change:** the primitive layer at rank 1 (`tabulate`, scalar-cell
  `lift`, `foldl`, `index`, `freeze`, `thaw`); `Linear.Array`'s loops
  over it; `TensorT` and tensor emission; `idr-bufferize` with
  `idr.array.alloc`, `copy`, `constant` and the releases; counting of
  structured ops and cells; evaluation's round; the array clause of the
  promise. Deleted: `generate`, `fold`, `Loops.cppm`'s memref half, the
  `ArrayLoop` hook.
- **Proof:** every existing array test passes with its expected files
  unchanged, and `vectorized` and `pure-array-loops` hold where they
  held; new fixtures: an array computed at compile time
  (`no-heap-allocation=@f`); a linear update chain (`in-place=@f`); an
  unrestricted array updated and read again, which prints the old version;
  a field read twice and one copy updated (§9.2, reason 4); a
  `--demand-in-place` rejection naming One-Shot's conflict.
- **Benchmarks:** spectral-norm-linear within 3% of 0.596 s or faster;
  fannkuch-linear at parity.

**2. Any rank** (§3, §4.3, §4.4, §8.4).

- **Change:** instances by skeleton and the opaque case; `Rank` a number;
  cell, base and extents with row-major strides; `LowerDim` for every
  dimension; the structural primitives; `idr.array.scan`, `scatter` and
  `sort`; the library's trees; the target's facts in its entry and in
  DLTI.
- **Proof:** fixtures at ranks 0, 1, 2, 3, 5 and 8; a rank recursion; an
  opaque shape built from a run-time value, reduced along a run-time axis;
  a leading-axis slice passed through a recursion with no
  `idr.array.copy` in it; float tree sums whose one expected file holds on
  both targets; `program-order` everywhere.
- **Benchmarks:** matmul (correct, its ratio recorded), mandelbrot-array,
  histogram, radix-sort against C and `futhark c` on one thread.

**3. The rank operator** (§3.4, §6).

- **Change:** `idr.array.lift`, `idr-batch`, `idr-soa`.
- **Proof:** `batched=@f` for a matrix-vector product lifted over a stack,
  a row normalization and an inner product; a lift whose body crashes at
  two cells ends at the first in row-major order, as
  `linarray-rows-crash-order` does today; a cell with a data-dependent
  while loop takes the fallback and prints the same output.
- **Benchmarks:** spectral-norm-array, nbody-array, backprop, kmeans,
  locvolcalib (G1, G2).

**4. Fusion and scheduling** (§7, §8, §11).

- **Change:** `idr-fuse` with the horizontal merge; `idr-schedule` and
  its transform scripts; packs and register tiles; the generalized
  `idr-vectorize`.
- **Proof:** `fused=@f` on a map chain, a map and a reduction, and a
  stencil chain; `program-order`; `vectorized`; a dumped schedule replayed
  by `mlir-opt` gives the same tiled IR, checked as `tests/upstream`
  checks a reproducer.
- **Benchmarks:** matmul's goal; hotspot and srad; G1 and G2 on every
  program of stages 2 to 4; G4.

**5. Counted elements** (§3.4, §10).

- **Change:** tensors of counted slots; counting in structured bodies; the
  counting copy; null-born slots; array reuse.
- **Proof:** arrays of strings and of boxes through map, reduce,
  transpose, slicing and reshape, each with zero live cells at exit; a
  copy of a dying unique array takes its cell (`reuses-in-place`,
  extended to arrays).
- **Benchmarks:** G4.

**6. Multicore** (§12.1), after 0005's P4.

- **Change:** the partition in `idr-schedule`; `#idr.shards`; W measured
  and written into both entries.
- **Proof:** every array fixture at `IDRIS_RT_SHARDS=1` against its
  expected files and at more shards against the one-shard run (0005 D8);
  `partitioned=@f`; a body that may crash is not partitioned.
- **Benchmarks:** G3 on every program.

**7. Sparse arrays** (§13).

- **Proof:** sparse matrix-vector, sparse matrix product and elementwise
  fixtures whose expected files are their dense versions'; a sparse array
  of strings rejected.
- **Benchmarks:** spmv (G1, G2).

**8. Differentiation** (§15).

- **Proof:** gradients against expected files computed by the library's
  own definition; the reverse pass of a function of static shape builds
  no closure (`no-closures=@f`).
- **Benchmarks:** logreg-grad within 1.5x of C's hand-written gradient.

**9. Region SPMD** (§12.2), on 0005's P5 measurement.

**10. GPU** (§14), on its gates.

## Rejected alternatives

- **Raising `Linear.Array`'s write threads to tensors** (the earlier
  draft's `idr-tensorize`). Its meaning is one object, so a raise had to
  prove that no old version is read, on a scratch copy of the function.
  Value arrays are tensors by construction, and `Linear.Array`'s loops
  become value operations (§4.5).
- **One instance per rank-polymorphic function at collapsed rank**,
  reshaping at every call. The caller must then recover finer extents
  from somewhere, so every array would carry its full shape beside its
  tensor as a second source of each extent; instances by skeleton have
  one source, and a polymorphic function never looks inside a shape
  variable, so collapsing saves only code size. The collapsed form
  survives exactly where it is needed, for an opaque shape (§3.1).
- **Unranked tensors, or a dynamic-rank type of ours.** `linalg` takes
  ranked operands only (read: LinalgStructuredOps.td:230), and a run-time
  rank is a value the program already has (§3.1).
- **The shape in the cell's header**, so that a stored array is one word.
  A reshape of a shared array would then need a copy to change the
  header, and with instances by skeleton every stored array's rank is
  static anyway.
- **Trailing-axis broadcasting and MLIR's `Broadcastable` trait.** A
  size-1 dimension is stretched by a run-time decision, undefined when
  two dynamic sizes differ and neither is 1 (read:
  `sources/docs/mlir/docs/Traits/Broadcastable.md`:28-31); prefix
  agreement never consults a size and is what the rank operator composes
  with.
- **An unordered reduction op selected by a proved law.** For a lawful
  operator any association gives the tree's result, so the law buys
  nothing the tree does not; floats, which have no law, would stay on one
  lane. And partial sums by index modulo the lanes over the whole array
  give lanes but no shards: a lane's chain runs the whole array, so no
  shard can take part of it without reassociating.
- **Reassociating reductions in the compiler** (fast-math flags, partial
  reduction tiling, a vectorized reduction dimension, a sharded one).
  Results would depend on the target, the vector width and the shard
  count.
- **Atomics for parallel histograms and reductions.** Their order is the
  scheduler's; private bins per chunk are deterministic.
- **`!idr.q` as a `TensorLikeType`, or a graded tensor type every pass
  sees.** The first makes every graded value a tensor to One-Shot (§9.2);
  the second holds the grade twice for every pass, where the encoding
  holds it twice for the one pass that needs it.
- **The linear handoff as a write of the handed buffer, and `lin.use` as a
  fresh writable tensor.** A linear value read out of a shared cell reaches
  a linear position with no write One-Shot sees, so `lin.use` would call
  a shared buffer fresh; letting One-Shot see linear parameters as
  tensors makes exclusivity its conclusion instead (§9.2, reason 2).
- **Arrays of cells for regular nesting.** A cell per row is not
  contiguous, and no `linalg` op sees its rank; the type proves the
  nesting uniform, so it is flat (§3.4).
- **`tensor.generate`** (no destination, so it always allocates: read:
  Bufferization.md, "Destination-Passing Style"); **`tensor.gather` and
  `tensor.scatter`** (no bufferization model).
- **A dialect of array combinators mirroring `linalg`** (Futhark's
  SOACs as ours). It would restate `linalg`; the primitive layer maps onto
  upstream ops and adds only the ops upstream lacks (§16).
- **A schedule language for programs** (Halide's and TVM's split, ELEVATE
  strategies in user code). The program is Idris; schedules are the
  compiler's, decided from the target's facts (§8).
- **Autotuned thresholds** (Futhark's incremental flattening, read:
  henriksen-2019 §4.2; Lift's search). They make builds depend on the
  machine they ran on; each threshold is measured once per target and
  kept in its entry.
- **Fully dynamic layouts at calls.** Every array argument strided, and
  the vectorizer would need a version per unit stride; canonical form and
  rebase cover the leading-axis slices that matter (§3.3, §9.4).
- **Ownership-based buffer deallocation.** A second ownership system
  beside counting (read: `sources/docs/mlir/docs/OwnershipBasedBufferDeallocation.md`:10-12).
- **Bufferizing after `idr-rc`, with `excl` as One-Shot's state.** A grade
  speaks of cells, and the cells One-Shot allocates would need their
  counts placed by hand (the earlier draft's reason, kept).
- **A run-time uniqueness test as the in-place promise.** README.md
  promises no run-time test; the test survives only as array reuse,
  outside the promise (§10).
- **`sparse-tensor-conversion`, the default runtime library, and
  `sparse_tensor.new` from files.** A C++ runtime library, and input
  belongs to our runtime's IO.
- **MPI (`ShardToMPI`), OpenMP (`convert-scf-to-openmp`), async
  (`async-parallel-for`).** Second runtimes and C libraries; 0005's shards
  are the runtime.
- **Enzyme for differentiation.** A second pinned upstream that tracks
  LLVM's releases, and the float order of its derivative would be the
  tool's choice, so the expected files would specify a tool rather than
  the program.
- **CUDA's or Vulkan's loader for GPUs.** Shared libraries a static PIE
  cannot load (§14).
- **Fill elements, or running a function on a cell of fills for an empty
  frame** (J, BQN). The cell shape is the type's (§4.2).
- **`Fin` as the stored coordinate.** A big at run time, so an index
  array would be an array of counted values (§2).

## Decisions

Each decision's reason or measurement is in the section it points to.

- **D1** Value arrays are tensors from the frontend, which emits upstream
  ops wherever upstream has the op (§4.1).
- **D2** Rank is a fact of the instance: an erased shape keys instances
  by skeleton; a shape no instance can know is one opaque dimension with
  its extents beside it (§3.1).
- **D3** Extents are run-time values, read off the array or the program's
  `Ext` (§3.2).
- **D4** An array value is its cell, its base and its extents, canonical
  wherever it escapes (§3.3).
- **D5** Words as tensors, records as one tensor per slot, counted slots
  counted, regular nesting flat, irregular data a library type (§3.4, §2).
- **D6** The rank operator is the one lifting primitive, lowered by
  batching (§4.2, §6).
- **D7** Order is meaning; the compiler never reassociates; parallel
  reductions are parallel by their library-written shape, 16 lanes and
  chunks of 4096 (§4.3).
- **D8** Fusion never duplicates work, loses parallelism or reorders a
  crash (§7).
- **D9** Schedules are decided in C++ and applied as generated transform
  scripts (§8.2).
- **D10** The target's facts are in its entry and the module's DLTI spec
  (§8.4).
- **D11** Arrays cross calls as tensors under One-Shot's module analysis,
  linear ones with their grade in the tensor's encoding inside
  `idr-bufferize` only; a store into the heap is a write of the stored
  buffer, and a read from it is read-only (§9.2).
- **D12** Counting follows bufferization; structured ops borrow; a dying
  unique array's cell is reused (§10).
- **D13** Inner products fold in order with `fma`; no padding enters a
  reduction (§8.3).
- **D14** Only parallel dimensions of crash-free word loops of work at
  least W are partitioned (§12.1).
- **D15** Sparse arrays: the format in the type, the dense meaning, no
  runtime library, numeric elements (§13).
- **D16** GPUs are later target entries on both hosts, reached without
  loaded drivers, behind gates (§14).
- **D17** Differentiation is the library's; the primitive layer is closed
  under transposition (§15).
- **D18** Futhark is pinned for the bench and its C committed (Performance
  goals).
- **D19** Pure array code is evaluated at compile time; constants are
  static cells (§4.6).
- **D20** The in-place promise has an array clause, checked under
  `--demand-in-place` (§9.5).

0005 cites the earlier draft's §3.8 for SPMD (its §8 and P5); that
content is §12 here, and 0005's sentence on tiling loops to `scf.forall`
should cite §12.1, which owns which array loops are partitioned.
`proposals/README.md`'s entry becomes: "a typed array language lowered
to MLIR: arrays of any rank are tensors from the frontend, a closed
primitive layer around the rank operator, fusion and scheduling on
tensors, One-Shot Bufferize with the grades kept in the types, partitions on
0005's shards, sparse arrays and differentiation from the same layer.
Proposed."

## Upstream used, and the changes planned

| Mechanism | For |
|---|---|
| `tensor`, `linalg` on tensors, `DestinationStyleOpInterface`, `TilingInterface` | the representation and the primitives (§3, §4) |
| `scf.forall`, `tensor.parallel_insert_slice` | the batching fallback (§6), partitions (§12.1) |
| elementwise fusion patterns, reshape propagation, `linalg-generalize-named-ops` | fusion (§7) |
| `tileUsingSCF`, `tileConsumerAndFuseProducersUsingSCF`, `linalg.pack`, the transform interpreter, `transform.dlti.query` | scheduling (§8) |
| `runOneShotModuleBufferize`, `allocationFn`, `memCpyFn`, `to_tensor restrict`, identity-layout boundaries | bufferization (§9) |
| `linalg::vectorize`, masks, the N-dimensional extract path | vectorization (§11) |
| `shard.grid`, `shard.shard`, `sharding-propagation`, `shard-partition`, `outlineSingleBlockRegion` | region SPMD (§12.2) |
| `#sparse_tensor.encoding`, `sparsification`, `sparse-tensor-codegen`, `assemble`, `disassemble`, `sparsification-and-bufferization` | sparse arrays (§13) |
| `gpu` dialect, the GPU transform ops, SPIR-V and AMDGPU lowerings | a later device (§14) |

Changes to propose upstream, each through `upstream/` as AGENTS.md
describes (a report, a reproducer reduced to upstream ops and tools, an
upstreaming plan, a `tests/upstream` check and a `PINS.md` entry when a
patch is carried):

- **U1, a horizontal merge of sibling generics** into one multi-result
  generic, a `linalg` rewrite pattern. Ours from stage 4; offered upstream
  with its test as a new pattern, not a fix, so no patch is carried.
- **U2, a cycle of calls analyzed to a fixpoint** in
  `OneShotModuleBufferize`, on §9.3's measurement.
- **U3, sparse codegen's allocations through `allocationFn`**, on §13's
  measurement.
- **U4, documentation:** `Bufferization.md` says recursive calls are not
  supported (read: `sources/docs/mlir/docs/Bufferization.md`:283-288)
  while the pinned code analyzes a cycle of calls conservatively (read:
  OneShotModuleBufferize.cpp:373-376); a one-paragraph fix.
- **Kept:** `upstream/04-vectorize-precondition-body`, which the
  generalized `idr-vectorize` still relies on.
