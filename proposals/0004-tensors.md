# 0004: dense array programs as tensors

**Status:** proposed (2026-10-09). Its premise is decided: on 2026-10-09
the user ruled that pure array programs are tensors ("tensors should
definitely be tensors, pure array programs is one of the heavy hitting
features of mlir and we cannot lose this"). That decision lives in
section 2, with the design it asked for. Claims are marked: read,
measured, recalled, conjecture, decision.

## 1. What exists

### Arrays are memrefs from birth

(read: `foreign/idr/include/idr/IdrOps.td`, "Arrays")

- **The type.** An array is a builtin `memref` of rank 0 or 1, every
  dimension dynamic, over a field type: no array type of our own.
  `memref<?xE>` holds base's `ArrayData` (so `IOArray`) and `Buffer`;
  `memref<E>` is an `IORef`'s cell, the array of rank 0. The cell is
  counted like a constructor's, and an element moves in and out with its
  reference (runtime `idris_rt_array`).
- **The ops.** `idr.array.new`, `get` and `set` take one size or index per
  dimension and the world, and give the next world: every array op is IO,
  ordered by its world.
- **The linear library.** `libs/mlir-linear/Linear/Array.idr` is a size
  beside base's `ArrayData`, threaded at quantity 1, every operation an
  `unsafePerformIO` over base's primitives on a forged world
  (`idr.world.new`). It now grows: `push`, `pop` and `reserve` keep a
  capacity, the backing's length, and `freeze` trims to the size once and
  gives an `IArray`, read-only and shared freely.

### Two loop ops, lowered to linalg on memrefs

- **`idr.array.generate` and `idr.array.fold`** (read: IdrOps.td) are graded
  region ops whose body runs once per index, in index order. The frontend
  emits them for Linear.Array's `generate` and `ifoldl` (so `imap`, `map`,
  `zipWith`, `foldl`, `sum`) when the element and accumulator are machine
  words; any other instance compiles as the library writes it.
- **The lowering** (read: `foreign/idr/lib/Lower/Loops.cppm`) makes a
  generate a parallel `linalg.generic` over the new array from element 1
  on, and a fold a reduction generic into a 0-d slot in the frame. A
  generate whose body is a fold over an outside array (spectral-norm's
  rows) is one generic of two dimensions, parallel then reduction. A
  generate that reads outside arrays at its own index takes them as inputs
  where one test on entry shows every one at least as long.
- **`idr-vectorize`** (read: `foreign/idr/include/idr/Passes.td`), in the
  default pipeline: each generic with a parallel dimension is tiled by the
  target's lanes, peeled, the full tiles unmasked and the last one masked.
  A reduction dimension gets one lane, so a float accumulator adds in
  program order.
- **`idr-narrow-lanes`** gives each vectorized loop on wide integer lanes a
  32-bit version under a bound on its sizes.
- **`idr-in-bounds`** erases each `idr.check.in_bounds` it proves, from the
  length relation that starts at `array.new` and `array.generate`.

### Measured

(measured: `bench/runs/2026-10-07-f5a4dff9-darwin-arm64/results.md`, Apple
M2 Max, best of 5)

| benchmark | this compiler | clang -O2 | clang / this |
|---|---:|---:|---:|
| spectral-norm-linear 5500 | 0.596 s | 1.108 s | 1.86x |
| fannkuch-linear 12 | 24.155 s | 25.711 s | 1.06x |
| fasta, fasta-redux, k-nucleotide, regex-redux, reverse-complement | | | 0.12x to 0.46x |

The byte and string programs are IO programs over buffers, strings and
lists. They are not array programs in this proposal's sense and it does not
change them; their gap is the object model's (one contiguous run cell for
strings, buffers and arrays).

### Missing

- Rank above 1.
- Fusion: `map f (map g xs)` makes and frees the middle array.
- Tiling for the cache.
- In-place decisions over a whole function: today an array is one object
  written in world order, so nothing is ever copied, and nothing proves a
  value-style program could be.
- Parallelism.
- Loop ops over non-word elements.

## 2. The decision this design serves

**What.** An array that no world orders is a value, and in MLIR a value
array is a `tensor`: built, read, sliced and combined by `tensor` and
`linalg` ops on tensors until One-Shot Bufferize turns it into memrefs.
Arrays the program mutates in the order its world gives (base's `IOArray`,
`Buffer`, `IORef`) stay memrefs from birth.

**Why.** Upstream's array machinery works on tensors:

- fusion and tiling of `linalg` on tensors;
- bufferization in destination-passing style, "with aggressive in-place
  bufferization", which decides in-place updates over a whole function and
  aims to "copy as little memory as possible" (read:
  `.toolchain/llvm-project/mlir/docs/Bufferization.md`);
- SPMD partitioning across a grid, whose sharding is a property of a tensor
  (read: `mlir/include/mlir/Dialect/Shard/IR/ShardOps.td`,
  `mlir/include/mlir/Dialect/Shard/Transforms/Passes.td`, at the pin).

These are single-thread wins first (fusion, in-place updates) and the
multicore path second: single-thread performance wins the tie
(`proposals/0005-shards.md`, "Rules it keeps"). The decision answers
whether pure array programs exist as tensors before bufferization: yes.

## 3. The design

### 3.1 Which arrays are tensors

**decision** The criterion is a property of the IR, judged by the analysis
that bufferizes, so that no second analysis of ours restates it:

1. **Its elements are words**, an integer or a float type: what `linalg`
   and the vectorizer compute on, and what a bufferization copy may copy
   with `memcpy`. A counted element needs a reference per element copied
   and per element read, which `memref.load` does not take; such arrays
   keep the memref ops and their counting.
2. **No world of the program orders it.** Every op on it takes a forged
   world. An array that meets the program's world (`IOArray`, `Buffer`,
   `IORef`) is one object whose identity a later read observes; a tensor
   has no identity.
3. **Every loop result is a tensor.** A generate makes a new array and a
   fold only reads, so neither can disagree with the one-object meaning.
   Where a loop meets a memref (a frozen array read out of a box, say), the
   edge is `bufferization.to_tensor`; where a tensor is stored into a box,
   it is `bufferization.to_buffer`, and the stored value is a memref from
   then on.
4. **A thread of writes is a tensor when it is linear in effect.** A thread
   starts at a new array (`array.new`, a generate, a copy) and runs through
   SSA: block and region arguments, results, calls to functions of the
   module, unboxed records. It ends where the array is frozen or stored.
   Its writes become `tensor.insert` when One-Shot's analysis of the raised
   thread puts every one of them in place. A RaW conflict means the program
   reads an old version after writing a new one, where the library's
   meaning (one object: "Bound unrestricted and shared, it is still that
   one object", read: Linear/Array.idr, `mkArray`) and the tensor's
   meaning differ; such a thread keeps its memref ops and its meaning. The
   analysis runs on a copy of the function, as idr-narrow-lanes finds its
   bound in a scratch module. A copy forced by a source that is not
   writable (a constant) is a copy under both meanings and does not undo
   the raise.

A thread that starts at a value read out of a box is not raised: another
reference may read the box after the write, and the analysis cannot see
that read. A thread that Idris bound at quantity 1 never conflicts, so
Linear.Array used as its documentation asks is raised whole.

### 3.2 The raise, `idr-tensorize`

**decision** One pass of ours, after `idr-defunctionalize` and
`canonicalize`, when no closure is left in a loop body. It replaces the
memref half of `Lower/Loops.cppm`, which goes:

| Today | Tensor form |
|---|---|
| `idr.array.generate` | `linalg.fill` of the fill into `tensor.empty`, then a parallel `linalg.generic` whose `outs` is the slice from element 1 on (`tensor.extract_slice`, `tensor.insert_slice`) |
| `idr.array.fold` | a reduction `linalg.generic` into a 0-d tensor |
| generate of a fold over an outside array | one generic of two dimensions, parallel then reduction (Loops.cppm's rule, kept) |
| generate reading outside arrays at its index | those arrays as `ins`, under the same test on entry |
| `idr.array.new`, `set`, `get` on a raised thread | `linalg.fill` into `tensor.empty`, `tensor.insert`, `tensor.extract` |
| `freeze` of a thread | `tensor.extract_slice` to the size, a view with no copy |

`tensor.generate` is not used: it has no destination and always bufferizes
to an allocation (read: Bufferization.md, "Destination-Passing Style").
Every access keeps its `idr.check.in_bounds`, now against `tensor.dim`,
which `idr-in-bounds` reads as a size measured off the array.

Two readers change with it:

- **`isArrayLoop`** (read: `foreign/idr/lib/Ownership/ArrayLoop.cppm`)
  answers for every `linalg` structured op: its body runs once per index of
  its iteration domain. Counting then sees a generic's body as it sees a
  generate's.
- **`pure-array-loops`** (read: `foreign/idr/lib/Expect/PureArrayLoops.cppm`)
  states its property of the generics.

### 3.3 The grade survives bufferization

A linear parameter is `!idr.lin<memref<?xE>>` today, and AGENTS.md keeps
quantity 1 in the type through every pass. **decision** The grade wraps the
carrier, whichever it is: `!idr.lin<tensor<?xE>>` before bufferization and
`!idr.lin<memref<?xE>>` after. `idr::QType` implements upstream's
`TensorLikeType` over a tensor carrier and `BufferLikeType` over a memref
one, which function-boundary bufferization accepts in place of builtin
tensors (read:
`mlir/lib/Dialect/Bufferization/Transforms/FuncBufferizableOpInterfaceImpl.cpp`,
`TensorLikeType`). `idr.lin.enter` and `idr.lin.use` implement
`BufferizableOpInterface`: their result is equivalent to their operand, and
they neither read nor write it.

### 3.4 Fusion and tiling

- **Fusion** is upstream's `linalg-fuse-elementwise-ops`, on tensors: a
  producer generic whose result only a consumer reads is folded into the
  consumer's body, and the middle array is never allocated.
- **Tiling for the cache** is `transform.structured.fuse` (tile, then fuse
  the producers into the tile loop), for a generic of two or more
  dimensions only: a one-dimensional elementwise loop streams, and tiling
  it buys nothing. The tile's working set is at most the target's L1 data
  cache, read from the module's DLTI target spec
  (`L1_cache_size_in_bytes`), which `idr-target` writes from the target's
  entry in CMakeLists.txt. No other pass reads a cache size.
- **Vectorization stays where it is.** The tiles bufferize to memref
  generics, which `idr-vectorize` and `idr-narrow-lanes` treat as today.

### 3.5 Bufferization

**decision** `idr-bufferize` is upstream's One-Shot Bufferize, called
through `bufferization::runOneShotModuleBufferize` with our options:

- **`bufferize-function-boundaries`**, the boundary type the identity
  layout (`function-boundary-type-conversion=identity-layout-map`): the
  memref an array cell holds, so a strided view becomes a copy only where
  it crosses a call.
- **The allocation is the runtime's cell.** `allocationFn` builds
  `idr.array.alloc`, a new op: a new array cell of word elements whose
  elements are unspecified until written, as `tensor.empty`'s are. It is
  an op of ours because only our runtime gives the cell.
- **No deallocation pass.** Every buffer is an array cell, and counting
  frees it.

**Where.** After `idr-tensorize`, fusion and tiling, and before
`idr-stack`. A buffer that never leaves its frame then goes on the stack by
the rule that puts cells there, which is how a fold's 0-d accumulator
becomes a frame slot, as Loops.cppm makes it today. Compile-time evaluation
runs in the simplify loop, before the raise, and never meets a tensor.

**Recursion.** Upstream analyses the bodies of functions that call each
other but not their boundaries, and treats such a call as reading and
writing its operands (read: `OneShotModuleBufferize.cpp`, "functions that
call each other circularly"). Idris loops are recursion until
`idr-tail-loops`, which runs later. On a raised thread this costs nothing:
the operand of a recursive call is not read after the call, so the
conservative call makes no conflict. Measurement rule: the raise reports
each thread it does not raise as a `missed` remark with One-Shot's conflict
(the read, the conflicting write, the last write; read: Bufferization.md,
"Debugging Buffer Copies"). A program of `bench/` whose thread stays
memref only because of a recursive boundary is the threshold for extending
the module analysis upstream, as a patch under `upstream/`, not an analysis
of ours.

**How it meets idr-rc's grades.** **decision** They do not overlap, and
neither knows the other:

- One-Shot decides in place over SSA, before counting. A raised thread
  never meets a heap cell while it is written (3.1, item 4), so SSA is
  every alias there is, and every write of a raised thread is in place by
  the criterion itself.
- After bufferization every buffer is an array cell. `idr-rc` grades it as
  it grades any array: a new cell is `excl`, a frozen array shared freely
  is `own` and dup'd. No pass consults a grade to decide a copy, and no
  runtime uniqueness test exists.

The alternative of bufferizing after counting, with `excl` as One-Shot's
analysis state, is rejected in section 6.

### 3.6 The in-place promise, checked

The in-place check of README.md's promise covers a quantity-1 value
matched and rebuilt at the same size. **decision** It gets one clause for
arrays: every write whose array came out of a quantity-1 binder is in a
raised thread. A write that is not, because One-Shot found a conflict, is
`unsupported (uniqueness)`, naming the write and One-Shot's conflicting
read. It is behind the same switch, `--demand-in-place`, and becomes the
default with the rest of the check.

### 3.7 Rank above 1

**decision** The backing stays base's one-dimensional `ArrayData`: one
runtime cell kind and no new primitive. The rank is in the type, the shape
beside the backing:

- **Idris side.** `Linear.Array`'s frozen array gains its rank,
  `IArray : Nat -> Type -> Type`, a record of a shape (`Vect rank Int`) and
  a backing, row-major. Today's `IArray a` is `IArray 1 a`. A rank-r array
  is built whole, by `tabulate : Vect r Int -> (Vect r Int -> a) -> IArray
  r a`, by `map` and `zipWith` at rank r, and by `reshape` of a frozen
  backing; it is read by `index : IArray r a -> Vect r Int -> a`. Writing
  single elements stays rank 1: the growable `Array` is the one mutable
  array, and a dense program builds its arrays whole. Each is plain Idris
  over the one-dimensional primitives, row-major arithmetic included.
- **Compiler side.** The frontend recognizes `tabulate`, `index` and the
  rank-r folds by name, as it does the rank-1 loops, when the rank is a
  literal after monomorphisation and the elements are words. It emits the
  loop ops with r sizes and r indices; `Idr_ArrayType` admits any rank,
  which `array.new`, `get` and `set` already take one size or index per
  dimension for. The rank-r value is `tensor.expand_shape` of the
  one-dimensional backing by the shape: upstream's own way of viewing a
  flat buffer at a shape, which bufferizes to a view.
- **Otherwise** (a rank that is not a literal, a counted element), the
  library's definition compiles as written: a rank erased at quantity 0 is
  not a constant the compiler may assume.

An `index` in a loop body at an affine function of the loop's indices
becomes an input of the generic with that indexing map, which is Loops'
rule for reads at the loop's own index, generalized. Matrix product is
then one generic of three dimensions, which upstream tiles, fuses and
vectorizes.

### 3.8 Multicore: SPMD through `shard-partition`

**decision** The multicore step partitions tensor programs with upstream's
`shard` dialect:

- **The grid** is `shard.grid @cores(shape = ?)`. Its size is a runtime
  value, as upstream allows ("dynamic device assignment", read: ShardOps.td,
  `Shard_GridOp`), and `shard.process_linear_index` is the running shard.
- **What is partitioned.** A region of generics over one parallel dimension
  is outlined into a function (`outlineSingleBlockRegion`), its tensor
  arguments and results annotated with `shard.shard` along that dimension;
  `sharding-propagation` and `shard-partition` make it SPMD. `linalg`
  structured ops and the `tensor` ops have upstream's `ShardingInterface`
  models (read: `mlir/lib/Dialect/Linalg/Transforms/ShardingInterfaceImpl.cpp`;
  `mlir/lib/Dialect/Tensor/Extensions/ShardingExtensions.cpp`).
- **Reductions.** Only parallel dimensions are sharded. A reduction
  dimension stays on one shard, as it stays on one lane, so a float result
  is the same on any number of cores. An integer fold may be sharded, its
  combine an `all_reduce`.
- **The launch and the collectives are ours.** The call site runs the
  partitioned function on every shard of `@cores` and joins, through the
  shard runtime of `proposals/0005-shards.md`. The result is allocated
  whole and each shard is given its slice as destination, so the gathering
  `all_gather` of a result is no copy: each shard writes its slice of one
  buffer. An `all_reduce` is a combine at the join. The arrays reach every
  shard by pointer for the duration of the join, which is sound because a
  partitioned body only loads and stores words in its own slice: the
  `counts-nothing` property, already an `idr-expect` check.
- **When.** Before this step, `proposals/0005-shards.md` (§8, stage P4)
  tiles a loop that counts nothing to `scf.forall` and lowers it to a fork
  per shard and a join: one loop at a time, joined after each. SPMD
  replaces that lowering for tensor programs by 0005's own rule: when it
  runs spectral-norm faster than P4's lowering beyond the run-to-run
  spread. Its gain is the region: one fork and one join for a region of
  loops, and each cross-shard step a named collective.
- **Size.** A partitioned region has two versions, as idr-narrow-lanes
  versions a loop: partitioned when the parallel extent is at least a
  bound, sequential below it. The bound is the extent at which the
  partitioned spectral-norm row loop breaks even, measured per target,
  rounded up to a power of two, kept in the target's entry.

The order of the pipeline is then: `idr-tensorize`, fusion, sharding and
partition, tiling, `idr-bufferize`, `idr-stack`, and the rest as now.

## 4. What it deletes

- The memref half of `Lower/Loops.cppm`: the loops are generics on tensors
  from the raise on.
- The rank-1 restriction of `Idr_ArrayType`.

## 5. Rules of AGENTS.md it keeps

- **Idris does types; MLIR does programs.** The rank and the element type
  are Idris's; whether an array is a tensor is a property of the program,
  judged in MLIR.
- **One representation.** The in-place decision is One-Shot's alone; the
  criterion does not restate it.
- **No pass drops what Idris proved.** Quantity 1 stays in the type across
  bufferization (3.3).
- **Never miscompile silently.** A thread whose tensor meaning would differ
  is not raised; under `--demand-in-place`, a linear one is a named
  rejection.
- **Erased does not mean constant; indexed vectors do not imply contiguous
  storage.** Rank is used only where monomorphisation makes it a literal,
  and a rank-r array is one backing by construction, not by its index.
- **Nothing per target outside the target's entry.** The cache size and
  the partition bound live there.

## 6. Staged plan

Each stage passes `make check`, `make build`, `make test`, `make test-idr`
and `make test-mlir-tools` on both targets, and runs `bench/` on both.

1. **Loops as tensors.** `idr-tensorize` for generate and fold,
   `idr-bufferize`, `idr.array.alloc`, `isArrayLoop` over `linalg`; the
   memref half of Loops.cppm goes. Proof: the existing tests pass with
   their expected files unchanged, `vectorized` and `pure-array-loops`
   hold where they held, and spectral-norm-linear is within noise (3%,
   best of 5) of 0.596 s or faster.
2. **Threads of writes.** Raised threads, the grade over the tensor carrier
   (3.3), and the in-place clause (3.6). Proof: a new `idr-expect`
   property, `in-place-thread=@f`, holds when every write in @f is in a
   raised thread and no copy was inserted; a test of a Linear.Array
   program states it; a test of an unrestricted `mkArray` written and read
   again keeps the one-object output in its expected file; a test under
   `--demand-in-place` expects the rejection; fannkuch-linear stays at
   parity with clang.
3. **Fusion and tiling.** Proof: a property `fused=@f` (no array allocated
   between two loops of @f) on `map f (map g xs)`; tiling stays on only if
   a benchmark it changes gets faster on both targets and none gets slower
   beyond noise.
4. **Rank above 1.** `IArray r`, `tabulate`, `index`; `Idr_ArrayType` of
   any rank. Proof: a dense matrix product test with expected output, and
   a `bench/` program for it with its clang -O2 C counterpart, reported in
   the next results.
5. **SPMD.** After `proposals/0005-shards.md`'s runtime and its P4.
   Proof: spectral-norm-linear's output is identical on one shard and on
   all of them, and it runs faster than under P4's lowering beyond the
   run-to-run spread on both targets, with no benchmark slower beyond
   noise.

## 7. Rejected alternatives

- **Our own fusion and in-place analysis on memrefs.** It would duplicate
  upstream's on a representation upstream's transforms do not take.
- **Every array a tensor.** An array ordered by the program's world is one
  object whose writes a later read sees; a tensor has no identity to see.
- **Deciding tensor-ness on the Idris side.** It needs the flow of the
  whole thread and its conflicts, which One-Shot computes; Idris would hold
  a second copy of that analysis.
- **Bufferizing after `idr-rc`, with `excl` as One-Shot's analysis
  state.** A grade speaks of cells and a tensor has none until it is
  bufferized; and the cells One-Shot allocated after counting would need
  their counts placed by hand.
- **A runtime uniqueness test before a write**, Lean's way. README.md
  promises in place "with no runtime test".
- **Nested arrays for rank 2.** `IArray 1 (IArray 1 a)` is a cell per row:
  not contiguous, and no `linalg` op sees its rank.
- **Sizes in the type.** Sizes are runtime words; a size index is erased,
  and erased does not mean constant.
- **Tensors of counted elements now.** A bufferization copy would have to
  dup every element, and a `memref.load` of one takes no reference. A
  `bench/` program whose hot loop is over counted elements is what would
  reopen it.
- **Ownership-based buffer deallocation.** It frees memrefs by runtime
  ownership indicators over static aliasing. Our arrays are cells, shared
  through the heap and counted.
- **MPI for collectives.** `ShardToMPI` targets processes and MPI. Our
  shards are threads of one process, and a collective over one shared
  buffer is a slice, not a message.

## 8. Upstream used

| Mechanism | For |
|---|---|
| `tensor`, `linalg` on tensors, `DestinationStyleOpInterface` | the raise (3.2) |
| `TensorLikeType`, `BufferLikeType`, `BufferizableOpInterface` | the grade across bufferization (3.3) |
| `linalg-fuse-elementwise-ops`, `transform.structured.fuse`, DLTI `L1_cache_size_in_bytes` | fusion and tiling (3.4) |
| `runOneShotModuleBufferize`, `bufferize-function-boundaries`, `allocationFn` | bufferization (3.5) |
| `tensor.expand_shape` | rank above 1 (3.7) |
| `shard.grid`, `shard.process_linear_index`, `shard.shard`, `sharding-propagation`, `shard-partition`, `ShardingInterface` models of `linalg` and `tensor` | SPMD (3.8) |
| `outlineSingleBlockRegion` | the partitioned region (3.8) |
