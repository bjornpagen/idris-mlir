# MLIR stack: the lowering target of a typed array language

Cluster `mlir-stack` of the APL research pass, 2026-10-09. What upstream MLIR (at the LLVM
pin, `7208ba24ca2894729cd394475a00d2a7b605e642`) gives an Idris-hosted, typed,
rank-polymorphic array language, what it lacks, and where the `idr` dialect has to add
ops. Every claim about a source cites the stored file under `sources/` with a line or
section; claims about our compiler cite the repository file.

Path convention. `sources/...` is the library path. Items this pass added are staged under
`scratchpad/selfhost/apl/stage/sources/` at the same relative path and marked *(staged)*;
everything else is already in the repository's `sources/`.

## 0. Sources

| Source | Where | State |
| --- | --- | --- |
| Vasilache et al. 2022, *Composable and Modular Code Generation in MLIR* (arXiv 2202.03293) | `sources/papers/vasilache-2022-structured-codegen/` *(staged)* | stored, TeX, CC BY 4.0 |
| Bik et al. 2022, *Compiler Support for Sparse Tensor Computations in MLIR* (TACO 19(4); arXiv 2202.04305) | `sources/papers/bik-2022-sparse-mlir/` *(staged)* | stored, TeX, CC BY 4.0 |
| Tillet, Kung, Cox 2019, *Triton* (MAPL 2019) | `sources/papers/tillet-2019-triton/paper.pdf` *(staged)* | stored, author PDF, ACM © |
| Lattner et al., *MLIR* (CGO 2021) | `sources/papers/lattner-2020-mlir/` (arXiv 2002.11054) | already stored; the CGO version is the library's link-only row `mlir-cgo-2021` (IEEE, no OA copy). Not duplicated. |
| Lücke et al. 2024, *The MLIR Transform Dialect* | `sources/papers/lucke-2024-transform-dialect/` | already stored; cross-linked |
| MLIR docs: Linalg, Linalg rationale, OpDSL, Bufferization, ownership-based deallocation, Transform, Vector, Shard, Shape, Broadcastable | `sources/docs/mlir/docs/...` | already stored at the pin; cross-linked, not duplicated |
| MLIR ODS for Linalg, Tensor, Bufferization, Vector, SparseTensor, Shard, SCF (+ transform ops, passes, OpDSL, `BufferizableOpInterface.h`) | `sources/code/mlir/include/mlir/Dialect/...`, `sources/code/mlir/python/...` *(staged, 38 files added to the existing snapshot; see `code/mlir/SNAPSHOT.addendum.md`)* | stored at the pin |
| MLIR interfaces (`TilingInterface`, `DestinationStyleOpInterface`, `SubsetOpInterface`, `ValueBoundsOpInterface`) | `sources/code/mlir/include/mlir/Interfaces/` | already stored |
| JAX shape polymorphism and export docs | `sources/docs/jax/docs/501/{shape-polymorphism,export}.md` *(staged)* | stored, Apache-2.0, jax `40a35abd` |
| JAX symbolic-dimension implementation | `sources/code/jax/jax/_src/export/{shape_poly,shape_poly_decision}.py` *(staged)* | stored, Apache-2.0 |
| Mojo docs on its MLIR design | `sources/docs/mojo/Mojo/docs/...` *(staged)* | stored, Apache-2.0 with LLVM exceptions, modular `135c332f` |
| Triton's MLIR dialects (selected ODS) | `sources/code/triton/include/triton/Dialect/...` *(staged)* | stored, MIT, triton `11523f38` |

Not stored: nothing of this cluster's list failed. The CGO 2021 MLIR paper stays link-only
(already recorded); the journal version of Bik et al. is behind `dl.acm.org`, which the
library does not fetch, and its arXiv version is the stored copy.

## 1. What `foreign/idr` has today (the starting line)

- **The array type is rank 0 or 1.** `Idr_ArrayValue` is "an array of rank 0 or 1 at any
  grade" and `Idr_Rank1ArrayValue` "an array of one dimension"
  (`foreign/idr/include/idr/IdrOps.td:1579-1584`); the carrier is a builtin
  `memref<?xE>` or `memref<E>` (`IdrOps.td:1801-1803`). There is no array type of our own;
  a rank above 1 is not expressible.
- **The array ops are IO.** `idr.array.new|get|set` take one size/index per dimension and
  a world (`IdrOps.td:1809-1906`); `get` can `move` an element out for an in-place rebuild
  (`IdrOps.td:1842-1851`).
- **Two loop ops, rank 1, words only.** `idr.array.generate` (`IdrOps.td:1923-1942`) and
  `idr.array.fold` (`IdrOps.td:1944-1960`) are region ops over an index space, emitted
  only when elements and accumulators are machine words (`IdrOps.td:1888-1903`).
- **Lowering is straight to `linalg.generic` on memrefs.** A generate is a parallel
  generic over the new array from element 1 on; a fold a reduction generic into a 0-d frame
  slot; a generate whose body is a fold is one 2-D generic (parallel, reduction); reads of
  outside arrays at the loop index become `ins` behind one entry test
  (`foreign/idr/lib/Lower/Loops.cppm:1-38`, `lowerGenerate` and `lowerFold`). No tensor,
  no bufferization, no fusion, no tiling for cache.
- **Vectorization** tiles every generic with a parallel dimension by the target's lanes,
  reductions by one lane (program-order float sums), peels, vectorizes full tiles
  unmasked and the last masked (`foreign/idr/include/idr/Passes.td:663-689`,
  `foreign/idr/lib/Vectorize/Tiles.cppm`). `idr-narrow-lanes` versions vector loops to
  32-bit integer lanes under a size bound (`Passes.td:691-720`).
- **Bounds proofs** are Presburger systems: `idr-in-bounds` erases each
  `idr.check.in_bounds` whose negation is infeasible, from path conditions, linear
  definitions, Euclidean quotients, masks and the array-length relation
  (`Passes.td:443-493`).
- **Ownership** is `idr-rc`: reset/reuse, borrow inference, explicit `dup`/`drop`,
  exclusivity grades `!idr.excl<T>` (`Passes.td:591-640`); quantity 1 is in the type
  (`!idr.lin<T>`), per AGENTS.md.

Everything below is measured against that: a typed APL needs rank r for every r, every
element type, fusion, tiling, in-place update decisions, SIMD, sparse, and SPMD.

## 2. Sources, one by one

### 2.1 Vasilache et al. 2022 — structured, retargetable code generation

`sources/papers/vasilache-2022-structured-codegen/` *(staged)*.

**Key ideas.**
- *Structured code generation*: start from tensor-algebra ops that carry their own
  structure, never raise from loops; transformations need "no complicated analysis and
  heuristics" (`2-codegen-flow-overview.tex:25-31`).
- Tiling and fusion are generic in op and data type: they "only assume a generic, monotonic
  (from the point of set inclusion), structural decomposition pattern", which dense and
  sparse both have (`2-codegen-flow-overview.tex:52-55`).
- The *progressive lowering principle*: every step is materialized in IR, little logic
  hides in C++ (`2-codegen-flow-overview.tex:69`). Flow: structured IR on tensors → tiled
  structured ops (loops around smaller structured ops, plus fusion) → vector → bufferize →
  loops + vectors on memrefs → `llvm` (`2-codegen-flow-overview.tex:33-62`).
- Dialect roles: `vector` is n-D and decomposes progressively (`:100-104`); `memref` is
  n-D with explicit layout (`:113-117`); `tensor` is an immutable value without a memory
  decision, "value insertion" creates new tensors (`:119-128`); `linalg` ops decompose into
  themselves on subsets and carry parallel/reduction facts (`:134-135`).
- **Tiling** on tensors yields `scf.for` with `extract_slice`/`insert_slice`, the tiled op
  being the same op on subsets; partial tiles force dynamic tile types
  (`3-transformations.tex:32-53`). **Padding vs peeling**: peel when there is no temporal
  locality, pad (with the consumer's neutral element) when reuse amortizes the copy; padded
  tiles can be hoisted and packed (`3-transformations.tex:55-109`).
- **Vectorization** recipe: one `vector.transfer_read` per operand along the indexing maps,
  pointwise ops, broadcasts for lower-rank operands, `vector.transpose` for permutations,
  reductions to `vector.contract` or `vector.multi_reduction`, convolution unrolling
  (`3-transformations.tex:111-167`).
- **Bufferization** (One-Shot's design): destination-passing style ties each result to an
  output operand; a result either reuses its tied operand's buffer or gets a new one;
  in-place decisions are a greedy RaW-conflict analysis over SSA use-def chains; ops with no
  natural destination allocate (`3-transformations.tex:169-267`).
- **n-D vector lowering**: unrolling to target shapes and power-of-two pieces, transfers to
  1-D loads and shuffles, `contract` to outer products and FMAs
  (`3-transformations.tex:269-318`).
- *Transformation-oriented IR design*: legality comes from the op's structure, so
  transformations are legal by design (`3-transformations.tex:320-347`); a meta-programming
  dialect can express the transformations as IR (`:357-376`) — the later Transform dialect.
- **Measured** (Xeon Gold 6154, single thread, AVX-512): matmul 92% of peak
  (`4-experiments.tex:352`), stride-1 convolutions about 96% of peak (`:390`), ColRed2D up to
  212 GB/s vs RowRed2D 99 GB/s in L1 because of horizontal reductions (`:212`); 2-D transpose
  needed a hand asm lowering for `vblendps` (`:276-280`); the sparse matvec is on par with
  TACO (`:525`, Table `tbl:sparse-matvec`). Strategies were hand-picked "fixed expert-driven"
  (`:172`).

**Steal.**
- The whole layering: Idris checks shapes and ranks; the compiler emits structured ops on
  tensors and never loops. Every APL primitive is a structured op so tiling, fusion and
  vectorization apply without analysis.
- Peel-or-pad as an explicit decision per op (we peel today in `idr-vectorize`); padding
  needs a neutral element, which a typed APL's reductions have by construction (a monoid
  witness in Idris).
- Reductions handled by first-class `vector.multi_reduction`/`contract`, and the
  measured lesson that a reduction along the contiguous axis is the slow one
  (`4-experiments.tex:212`): prefer layouts that reduce across lanes, not within a lane.

**Avoid.**
- Hand-picked per-kernel strategies (`4-experiments.tex:169-174`): a general-purpose
  language compiler must decide from the op and the target, as `idr-vectorize` already
  does.
- Inline asm for shuffles (`4-experiments.tex:272-280`): AGENTS.md forbids inline asm;
  accept LLVM's shuffle lowering or fix LLVM upstream.
- The bufferization heuristic's blind spot: ops without a destination always allocate
  (`3-transformations.tex:234-240`). Emit DPS ops only (§2.5).

**Limits.** Single-thread CPU only; no fusion results (`4-experiments.tex:144`); scans
are only mentioned as a weakness of Halide (`5-related-work.tex:39`) and get no structured
op; nothing about element types other than numbers.

### 2.2 Lattner et al., MLIR (cross-link)

`sources/papers/lattner-2020-mlir/` (already stored). The principles the APL lowering
relies on: *progressive lowering* (`design.tex:44-50`), maintaining "structure of
computation" while lowering (`design.tex:80`), and traceability (`design.tex:118-126`).
Steal: progressive lowering is the reason an APL primitive should be an op, not a library
call. Nothing new to avoid here beyond §2.3.

### 2.3 Linalg (docs, rationale, OpDSL, ODS)

`sources/docs/mlir/docs/Dialects/Linalg/_index.md`,
`sources/docs/mlir/docs/Rationale/RationaleLinalgDialect.md`,
`sources/docs/mlir/docs/Dialects/Linalg/OpDSL.md`,
`sources/code/mlir/include/mlir/Dialect/Linalg/IR/*.td` *(staged)*.

**Key ideas.**
- `linalg.generic` (`LinalgStructuredOps.td:55-130`): operands define the iteration space
  (Property 1, `_index.md:76-165`), indexing maps relate loops and data (Property 2,
  `:167-240`), iterator types are declared, `parallel` or `reduction` (Property 3,
  `:242-276`), the payload is a region over element scalars with no further restriction
  ("the frontend is responsible for the semantics of iterator types to correspond to the
  operations inside the region", Property 4, `:278-300`), it may map to a library call
  (Property 5), and it is a perfectly nested loop that writes all of its outputs (Property
  6, `:450-484`). Imperfect nesting appears only as the result of tiling and fusion
  (`RationaleLinalgDialect.md:648-674`).
- Out-of-bounds access is impossible by construction, "assuming dynamic operand dimensions
  agree with each other" (`_index.md:140-143`).
- Four forms — generic, category (`contract`, `elementwise`), named (`matmul`, `add`, ...),
  composite (`softmax`) — convertible between generic/category/named
  (`RationaleLinalgDialect.md:509-554`); `linalg-generalize-named-ops`,
  `linalg-specialize-generic-ops`, `linalg-morph-ops` move between them
  (`code/mlir/include/mlir/Dialect/Linalg/Passes.td:48-103`).
- The named rank-polymorphic ops: `linalg.map` (elementwise, any rank, all operands the
  same shape; `LinalgStructuredOps.td:233-312`), `linalg.reduce` (any set of sorted
  `dimensions`, a combiner region; `:314-396`), `linalg.transpose` (moves data;
  `:398-472`), `linalg.broadcast` (adds `dimensions`; `:474-548`), `linalg.elementwise`
  (a kind attribute plus optional broadcast/transpose maps; `:550-...`), `linalg.contract`
  (`D[H] = SUM_{(I∪J)\H} A[I]*B[J] + C[H]`, iterator kinds inferred from the maps;
  `:824-870`), `linalg.pack`/`unpack` (`LinalgRelayoutOps.td:95, 308`), `linalg.index`
  (`LinalgOps.td:49`).
- Guiding principles: avoid raising, progressive lowering as "reducing a potential
  function" (`RationaleLinalgDialect.md:462-507`); the dialect need not be closed under
  transformations, only monotone (`:648-674`).
- Open issues the rationale itself lists: nesting of `linalg.generic`, regions over views
  rather than scalars (`_index.md:675-693`). Future data types: ragged, sparse, trees
  (`RationaleLinalgDialect.md:610-627`).

**Steal.**
- **Every rank-polymorphic APL primitive at a static rank r is one structured op.**
  Pointwise lift (`map`), reductions over any axis set (`reduce`), transpose, broadcast
  (Remora's frame extension becomes a projected indexing map or `linalg.broadcast`),
  inner/outer products (`contract`), and any user cell function (`generic` with the cell
  body as region, the frame dims parallel and the cell's own reductions as reduction
  iterators). No rank ceiling exists in `linalg`: the iteration domain has as many
  dimensions as the maps say.
- Iterator types as a *contract the frontend guarantees* (`_index.md:262-269`): Idris
  proves parallelism (a pure cell function) and the monoid laws of a reduction; the
  compiler can mark dims `parallel` without analysis. Only claim `parallel` where the
  region is pure, since Property 4 makes a wrong claim undefined behaviour.
- Generalize/specialize: emit `generic` from the frontend (one representation), let
  `linalg-specialize-generic-ops` recover named forms for pattern matching.

**Avoid.**
- `library_call` (`LinalgStructuredOps.td:73-77`): "assumed to be dynamically linked"; a C
  library call is outside the language (AGENTS.md).
- Relying on the body region to be anything at all for transformations: tiling and fusion
  accept any region, but the vectorizer refuses calls and crashes (we already see this:
  `Vectorize/Tiles.cppm`, `vectorizable`). Keep the region's ops vectorizable or accept a
  scalar loop.
- Writing named ops into the frontend: the named op set is generated from OpDSL
  (`python/mlir/dialects/linalg/opdsl/ops/core_named_ops.py`, `OpDSL.md`), a Python
  generator at build time; our frontend should emit `generic`/`map`/`reduce` only and
  let specialization run.

**Limits.**
- **Static rank only.** Every structured op takes ranked tensors or memrefs
  (`TensorOrMemref`, `LinalgStructuredOps.td:230`); unranked `tensor<*xE>` is not an
  operand.
- **Element type.** Builtin `tensor` admits any non-builtin dialect type as element
  (`mlir/lib/IR/BuiltinTypes.cpp:435-442` at the pin, not vendored), and `memref` admits a
  type implementing `MemRefElementTypeInterface`, which every idr value type already does
  (`IdrOps.td:113-171`). So `tensor<?x?x!idr.box<...>>` is legal; but the vectorizer and
  the `memref.copy` of bufferization only understand numbers.
- **No scan.** There is no `linalg` scan at the pin (no structured op in
  `LinalgStructuredOps.td`); only `vector.scan` (§2.7).
- No nesting (`_index.md:679`): an array of arrays of different shapes (ragged, boxed APL
  nested arrays) is not a linalg value.

### 2.4 Tensor

`sources/code/mlir/include/mlir/Dialect/Tensor/IR/TensorOps.td` *(staged)*.

**Key ideas.** Immutable values; shape ops are views after bufferization where layouts
allow: `extract_slice` (`:362`), `insert_slice` (`:821`), `parallel_insert_slice`
(`:1468`, the combining terminator of `scf.forall`), `expand_shape` (`:1091`: a rank
increase by a static *reassociation*, with dynamic `output_shape` operands), `collapse_shape`
(`:1176`), `reshape` (`:994`, by a shape tensor), `pad` (`:1251`), `concat` (`:131`),
`generate` (`:724`), `empty` (`:264`), `splat` (`:1760`), `gather` (`:584`), `scatter`
(`:1619`), `from_elements` (`:540`), `dim`/`rank` (`:200`, `:968`).

**Steal.** APL structural primitives map one-to-one: take/drop/slices → `extract_slice`;
catenate → `concat`; reshape between ranks of the same element count → `expand_shape`
/ `collapse_shape` (views when contiguous); fill → `linalg.fill` of `tensor.empty`;
padding with a fill element → `tensor.pad`. Use `tensor.dim` as the size the bounds
relation reads (0004 already plans this).

**Avoid.** `tensor.generate` (no destination, always allocates: §2.5). `tensor.gather`
and `tensor.scatter`: at the pin they have no `BufferizableOpInterface` model (the
registrations in `mlir/lib/Dialect/Tensor/Transforms/BufferizableOpInterfaceImpl.cpp:1194-1206`
cover collapse, concat, expand, generate, pad, parallel_insert_slice and others, not
gather/scatter; not vendored), so they cannot reach code. Express indexing-by-array as a
`linalg.generic` whose body does `tensor.extract` at a computed index (the vectorizer's
`vectorizeNDExtract` path), or as an idr op.

**Limits.** `expand_shape`'s reassociation is a static attribute: the rank of both sides
must be known at compile time. Dynamic rank is out of reach of the tensor dialect.

### 2.5 Bufferization: One-Shot Bufferize, DPS, deallocation

`sources/docs/mlir/docs/Bufferization.md`,
`sources/docs/mlir/docs/OwnershipBasedBufferDeallocation.md`,
`sources/code/mlir/include/mlir/Dialect/Bufferization/IR/*.td`,
`.../IR/BufferizableOpInterface.h`, `.../Transforms/Passes.td` *(staged)*.

**Key ideas.**
- One-Shot Bufferize is monolithic, interface-extensible, whole-function, two-phase
  (analyze then rewrite), greedy and modular (the analysis is replaceable through
  `AnalysisState`) (`Bufferization.md:30-65`). It does not deallocate (`:67`).
- DPS: each tensor result has a tied "destination"; the result's buffer is either the
  destination's buffer or a new allocation, nothing else is considered
  (`Bufferization.md:87-139`). Non-DPS ops always allocate (`:140-160`). Copies appear when
  an SSA chain splits (`:180-203`).
- The tensor/buffer boundary: `to_tensor ... restrict writable`, `to_buffer`,
  `materialize_in_destination` (`Bufferization.md:205-253`;
  `BufferizationOps.td:331-414` for `restrict`: the only way the tensor IR reaches that
  memref, required by One-Shot).
- Function boundaries are bufferized only on request, and "recursive calls are not
  supported" (`Bufferization.md:278-288`).
- Extending: implement `BufferizableOpInterface`: `bufferizesToMemoryRead/Write`,
  `getAliasingValues`, `bufferRelation`, `bufferize` (`Bufferization.md:344-372`;
  `BufferizableOpInterface.td:36-612` lists also `bufferizesToElementwiseAccess`,
  `mustBufferizeInPlace`, `isWritable`, `isRepetitiveRegion`, `isParallelRegion`).
- **Custom tensor-like and buffer-like types**: `TensorLikeTypeInterface` and
  `BufferLikeTypeInterface` (`BufferizationTypeInterfaces.td:18-50`); `to_tensor` and
  `to_buffer` operate on them (`BufferizationOps.td:388-440`). A dialect type can therefore
  be the "tensor" One-Shot analyzes and its own buffer type the result.
- **Hooks**: `BufferizationOptions` has `allocationFn`, `memCpyFn`, `castFn`, the
  function-boundary and unknown type converters (`BufferizableOpInterface.h:252-372`):
  allocation and copying are the client's.
- Ownership-based deallocation: buffers are owned by blocks, ownership is an `i1` SSA value
  "conceptually similar to `std::unique_ptr`" (`OwnershipBasedBufferDeallocation.md:10-12`);
  a lattice `uninitialized < unique(X) < unknown` (`:113`); function ABI: arguments are never
  owned, results always are (`:55-76`); no unstructured loops (`:216`); unsimplified
  `dealloc` costs O(|memrefs|²) at run time (`:53`).

**Steal.**
- One-Shot as *the* in-place analysis for value arrays, with `memCpyFn` and `allocationFn`
  set to our runtime's cell and an element-aware copy. With a counting-aware `memCpyFn`
  (dup every counted element copied) the "words only" restriction of 0004 §3.1 item 1 is
  a choice, not a limit: an array of boxes can be a tensor too.
- The custom-type interfaces: an `!idr.lin<tensor<...>>` / `!idr.lin<memref<...>>` pair (0004
  §3.3) is exactly what `TensorLikeType`/`BufferLikeType` were added for; quantity 1 then
  stays in the type across bufferization, as AGENTS.md requires.
- `restrict writable` is how a quantity-1 array enters tensor land: Idris's linearity is
  precisely the "only way to reach this memref" fact `restrict` asks for, proved instead of
  promised.
- `bufferizesToElementwiseAccess` (`BufferizableOpInterface.td:94-145`): an op whose reads
  and writes are elementwise may update in place even when an operand equals the
  destination; every pointwise APL lift has this property by construction.

**Avoid.**
- The ownership-based deallocation pipeline: our cells are counted (`idr-rc`), and a second
  ownership system (`i1` ownership, runtime alias checks) would be the "one thing, two
  representations" AGENTS.md forbids. Set no deallocation; let counting free cells.
- `bufferize-function-boundaries` across recursion (`Bufferization.md:283-284`): Idris loops
  are recursion until `idr-tail-loops`; either run bufferization after loops are loops, or
  keep recursive boundaries as buffers.
- Fully dynamic layout maps at unknown ops (`Bufferization.md:290-342`): emit only
  bufferizable ops, so layouts stay identity/strided and precise.

**Limits.** Greedy and per-function; no global copy minimization (the paper calls this
future work, `vasilache-2022-structured-codegen/3-transformations.tex:240`). One-Shot does not
understand reference counts: an array shared by count 2 must not be written in place,
which SSA-only analysis cannot see if two SSA values alias the same cell through a box
(0004 §3.1 already excludes arrays read out of boxes).

### 2.6 Transform dialect (docs, ODS, Lücke et al.)

`sources/docs/mlir/docs/Dialects/Transform.md`,
`sources/papers/lucke-2024-transform-dialect/main.tex` (already stored),
`sources/code/mlir/include/mlir/Dialect/{Linalg,SCF,Bufferization,Vector}/TransformOps/*.td`
*(staged)*, `sources/code/mlir/include/mlir/Dialect/Transform/**` (already stored).

**Key ideas.** Transform IR drives transformations of payload IR through handles to ops,
values and parameters (`Transform.md:7-64`); three-state results with silenceable
failures (`:228-270`); consuming a handle invalidates handles into the affected subtree
(`:272-334`); positioned between patterns and passes, for fine-grained composition such as
split, then tile one part and unroll the other (`:336-393`). Structured transform ops at the
pin include `structured.tile_using_for`, `tile_using_forall` (`LinalgTransformOps.td:2403`),
`fuse` (`:439`), `fuse_into_containing_op` (`:534`), `pad` (`:1242`), `pack` (`:989`),
`vectorize` (`:2605`), `tile_reduction_using_forall` (`:2107`), `generalize`/`specialize`
(`:601`, `:639`), `bufferize_to_allocation` (`:195`); `transform.bufferization.one_shot_bufferize`
(`BufferizationTransformOps.td:55`); `transform.loop.peel|unroll|forall_to_parallel`
(`SCFTransformOps.td`). Lücke et al. measure ≤2.6% compile-time overhead for whole
pipelines expressed as transform scripts (`main.tex:918, 950`) and a 20× gain from a
microkernel schedule (`main.tex:1225`); they add pre/post-conditions for lowering
composition (`main.tex:592-620`).

**Steal.** Our passes already call upstream's C++ entry points (`scf::tileUsingSCF`,
`linalg::vectorize` in `Vectorize/Tiles.cppm`). Transform ops are the same entry points
with handles; they are the right tool for *one-off* experiments and for tests of a
schedule. Keep schedules decided in C++ from the op and the target (as `idr-vectorize`
does), and use transform scripts in `tests/` to pin a schedule's property.

**Avoid.** User-visible scheduling languages: a typed APL in Idris should not expose a
schedule beside the program (that is Halide/TVM's split, not this compiler's "the compiler
decides"). Also avoid interpreter overhead at every compile for every loop: an op-local
C++ decision costs less than interpreting a script per op.

**Limits.** Handles are untyped sets; nothing proves a schedule correct beyond the
transforms' own legality; schedules are per op, not global.

### 2.7 Vector

`sources/docs/mlir/docs/Dialects/Vector.md`,
`sources/code/mlir/include/mlir/Dialect/Vector/IR/VectorOps.td` *(staged)*.

**Key ideas.** n-D virtual vectors unrolled to hardware sizes; operating on vector SSA
values avoids unroll-and-jam, register-reuse restructuring, store-to-load forwarding and
raising (`Vector.md:210-229`); automatic vectorization is out of scope and becomes pattern
rewriting on structured ops (`:231-260`); scalable dims `vector<4x8x[128]xf32>` lower to
`vscale` vectors (`:79-90`). Ops: `contract` (`VectorOps.td:48`), `multi_reduction`
(`:309`), `transfer_read`/`write` with masks and in-bounds flags (`:1270`, `:1525`),
`mask` (`:2745`), `gather`/`scatter` (`:2122`, `:2234`), `scan` (`:3032`: inclusive or
exclusive along one dimension with a *combining kind*, not a region), `step` (`:3090`).

**Steal.** Keep vectorization as `linalg::vectorize` of structured ops (we do). Use
`vector.multi_reduction` reorderings for reductions where Idris proved associativity and
commutativity (e.g. integer `+`), and keep the one-lane program-order rule for floats,
where no law was proved. `vector.mask` for the last tile is already our scheme.

**Avoid.** Scalable vectors: our two targets (x86_64, arm64 Apple) have fixed-width
vectors and Apple's arm64 has no SVE; a scalable path is a per-target special case AGENTS.md
forbids until a target needs it.

**Limits.** `vector.scan` combines with a fixed `CombiningKind`, not an arbitrary
associative function; a user scan with an Idris monoid has no vector op. No ragged vectors.

### 2.8 SparseTensor (Bik et al. 2022 and the ODS)

`sources/papers/bik-2022-sparse-mlir/mlir.tex` *(staged)*,
`sources/code/mlir/include/mlir/Dialect/SparseTensor/**` *(staged)*.

**Key ideas.**
- *Sparsity as a property of the tensor type*, not of the code: a `#sparse_tensor.encoding`
  on the tensor type turns the same `linalg.matmul` into SpMM/SpMSpM kernels
  (`mlir.tex:45-70`). The TACO-style encoding gives each level a format
  (dense/compressed), a dimension ordering and bit widths: 2^d·d!·16 formats for a
  d-dimensional tensor (`mlir.tex:141-325`). At the pin the encoding is
  `map = (i, j) -> (i : dense, j : compressed)` with formats dense, batch, compressed,
  loose_compressed, singleton, structured[n,m] and properties nonunique/nonordered/soa
  (`SparseTensorAttrDefs.td:115-280`).
- Ops: materialization (`new`, `assemble`), conversion via COO to avoid the quadratic
  number of direct conversions (`mlir.tex:349-365`), and lowering helpers (`positions`,
  `coordinates`, `values`, `expand`/`compress`) (`SparseTensorOps.td:32-881`). At the pin
  there are also explicit iteration ops: `extract_iteration_space`, `iterate`, `coiterate`
  (`SparseTensorOps.td:1470-1810`) and set-semantics regions for generic bodies
  (`binary`, `unary`, `reduce`, `select`; `:980-1312`).
- The sparsifier follows TACO's sparse iteration model: a topologically sorted iteration
  graph, iteration lattices per index, co-iteration with `scf.while`
  (`mlir.tex:396-460`); sparse outputs by direct insertion or access-pattern expansion
  (workspaces) (`mlir.tex:464-497`). Mechanism and policy are separated (`mlir.tex:394`).
- Front end: PyTACO's implicit broadcast and reduction, with temporaries when a reduction
  is over a sub-expression (`mlir.tex:505-566`).
- **Measured** (Xeon W2135): I/O 1.1-1.9× faster than TACO (`mlir.tex:597-615`); SpMSpM
  1.06-1.09× (`:617-636`); SpMV with a CDR format plus AVX-512 1.12-1.27× (`:646-665`);
  MTTKRP 1.44× (`:673-686`). Getting loop order and fusion wrong is asymptotically worse in
  sparse code (`mlir.tex:741`).

**Steal.**
- The design move: one sparsity-agnostic program, the storage format in the type. In a
  typed APL the encoding is a type index of the array (Idris can carry a format parameter),
  monomorphised into the tensor type's encoding attribute; the same `linalg.generic` then
  lowers dense or sparse.
- `sparse-tensor-codegen` (direct code, `Passes.td:287-341`) with
  `enable-runtime-library=false`: storage is plain buffers, no C++ runtime.
- Iteration lattices for zero-preserving element functions: Idris can prove `f 0 = 0` and
  annihilation, which is what decides intersection vs union co-iteration.

**Avoid.**
- `sparse-tensor-conversion` and the default `enable-runtime-library=true`
  (`SparseTensor/Transforms/Passes.td:191, 224, 443`): it calls a C++ runtime library,
  a shared-library dependency outside AGENTS.md's static-linking and no-C rules.
- `sparse_tensor.new` from files (Matrix Market, FROSTT) (`mlir.tex:333-347`): file I/O
  belongs to our runtime's IO, not the dialect's.
- Sparse arrays of non-numbers: the encoding "can only be applied to tensors with supported
  primary element types" (`SparseTensorAttrDefs.td:129-131`).

**Limits.** Numeric elements only; implicit value 0 only (`SparseTensorAttrDefs.td:218-222`);
the format search is the user's (state-space search, `mlir.tex:568-587`).

### 2.9 Shard (formerly Mesh) and `shard-partition`

`sources/docs/mlir/docs/Dialects/Shard.md`,
`sources/code/mlir/include/mlir/Dialect/Shard/**` *(staged)*.

**Key ideas.** GSPMD-style sharding (`Shard.md:1-9`): a `shard.grid` of devices, possibly
of dynamic shape (`ShardOps.td:31-60`); a sharding maps each tensor dimension to grid axes
(`split_axes`), with optional halos or uneven `sharded_dims_offsets` (`ShardOps.td:200-250`);
`shard.shard` annotates values (`:357`). Collectives are defined on tensor dimensions,
devices inferred from shardings (`Shard.md:13-26`); collectives are pure, the execution
model SPMD with all processes in sync at collectives (`:65-84`). Passes:
`sharding-propagation` (forward/backward), `shard-simplify` (e.g. `all_reduce(x) +
all_reduce(y)` → `all_reduce(x+y)`), `shard-partition` (fully annotated IR → SPMD form)
(`Shard/Transforms/Passes.td:19-111`). Ops participate through `ShardingInterface`
(iterator types, indexing maps, `partition`) (`ShardingInterface.td:14-165`). Resharding
decomposes into four basis moves: replicate→split (slice), split→replicate (all-gather),
axis swap, move to another tensor axis (all-to-all) (`ReshardingPartitionDoc.md:618-680`).

**Steal.** The sharding attribute is a property of tensor *dimensions*, i.e. of a typed
array's shape; partitioning is derived from the same iterator types and indexing maps as
tiling. `linalg` ops implement `ShardingInterface` upstream
(`mlir/lib/Dialect/Linalg/Transforms/ShardingInterfaceImpl.cpp` at the pin, not vendored),
so a structured APL program is partitionable without new interface code. `shard-simplify`'s
all-reduce endomorphism rule is sound exactly when the reduction is a monoid homomorphism,
which Idris can prove.

**Avoid.** The `ShardToMPI` conversion (`mlir/lib/Conversion/ShardToMPI` at the pin): MPI is
a C library, multi-process; our multicore runtime is shards of one process
(`proposals/0005-shards.md`). Keep `shard` for the partitioning decision and lower the
collectives to our runtime (0004 §3.8 already decides this).

**Limits.** Partition requires every op to implement `ShardingInterface` or be fully
replicated (`Passes.td:65-71`); contiguous shards only (`ShardOps.td:234`); no cost
model.

### 2.10 SCF `forall`

`sources/code/mlir/include/mlir/Dialect/SCF/IR/SCFOps.td:336-470` *(staged)*.

**Key ideas.** A multi-dimensional parallel region with `shared_outs`; non-shared tensors
written inside are privatized; results are combined by `scf.forall.in_parallel` with
`tensor.parallel_insert_slice` in unspecified order; an implicit synchronization point; a
`mapping` attribute names processing units (`SCFOps.td:350-395`). It is what
`tile_using_forall` produces (`LinalgTransformOps.td:2403`) and what bufferization handles
(`isParallelRegion`, `BufferizableOpInterface.td:579`).

**Steal.** `scf.forall` is the target-independent "for each frame cell, in parallel" of a
rank-polymorphic lift, on tensors, bufferizable, and lowerable to our own fork/join
(`proposals/0005-shards.md`, P4). A custom `mapping` attribute (`DeviceMappingInterface.td`)
can name our shards.

**Avoid.** `convert-scf-to-openmp` and `async-parallel-for` lowerings: both need a C runtime
(libomp, the MLIR async runtime) loaded as a library; out per AGENTS.md.

### 2.11 Triton (paper and MLIR dialects)

`sources/papers/tillet-2019-triton/paper.pdf` *(staged)*,
`sources/code/triton/include/triton/Dialect/**` *(staged)*.

**Key ideas.** The *tile*, a statically shaped multi-dimensional sub-array, as the unit of
the language and IR (paper, Abstract and §1). Triton-C: tile declarations with tunable
shapes, NumPy broadcasting by left-padding with ones then replication (§3.2.2), a
single-threaded SPMD programming model in which each kernel instance owns a tile and
`get_global_range` gives its indices (§3.3); Triton-IR adds tile types, `reshape`,
`broadcast`, `dot`, `trans` and predicated SSA (`cmpp`, `psi`) for divergence within tiles
(§4.2-4.3); machine-independent passes (prefetching, tile peepholes) and machine-dependent
ones (hierarchical tiling into micro- and nano-tiles, coalescing, shared-memory allocation and
barrier insertion by RAW/WAR data-flow) (§5.1-5.2); an exhaustive autotuner over power-of-two
tile sizes (§5.3). Measured on a GTX1070: matmul on par with cuBLAS and above 90% of peak, 2-3×
faster than other DSLs (§6.1); IMPLICIT_GEMM convolution on par with or faster than cuDNN; a
fused shift-conv hides the shift (§6.2). Today's Triton is MLIR: `tt.reduce` and `tt.scan`
take a combiner *region* over an axis (`TritonOps.td:839-905`), and layouts are encodings on
the tensor type (blocked, slice, dot-operand, MMA, linear layouts;
`TritonGPUAttrDefs.td:661-790`).

**Steal.**
- `tt.scan`'s shape: an associative scan with a region combiner over one axis, multiple
  operands, a `reverse` flag. This is the op upstream lacks (§2.3, §2.7) and the one a typed
  APL needs for `scan`/prefix sums with a user monoid.
- Layout as a tensor-type encoding (like sparse encodings): a per-target distribution of
  elements to lanes is data on the type, not a pass flag.
- Broadcasting by left-padding with ones (§3.2.2) is the special case of Remora's frame
  agreement where the cell is a scalar; a typed APL proves it instead of checking it.

**Avoid.** The pointer-tile programming model (tiles of pointers, explicit masks;
Listing 1): a typed APL hands whole arrays to structured ops and lets the compiler tile.
GPU-specific memory passes are out of scope for two CPU targets.

**Limits.** Static tile shapes (§4.2.1); the 2019 IR is LLVM-based, not MLIR; GPU-only
evaluation; no types beyond numbers and pointers.

### 2.12 JAX shape polymorphism

`sources/docs/jax/docs/501/{shape-polymorphism,export}.md` *(staged)*,
`sources/code/jax/jax/_src/export/{shape_poly,shape_poly_decision}.py` *(staged)*.

**Key ideas.**
- A function is traced and lowered once with *dimension variables*; the exported module
  runs for every shape that matches (`shape-polymorphism.md:1-47`). Correctness statement:
  if native execution and export both succeed, the export gives the same result
  (`:107-128`).
- Dimension expressions: variables ≥ 1, combined with `+ - * floordiv mod max min`
  (`:132-147`); representation: a sorted linear combination of terms, each a product of
  factors, a factor a variable or `floordiv/mod/max/min` of expressions
  (`shape_poly.py:100-129, 264-270, 396-411`).
- Comparisons are partial: equality is total and *unsound* by choice ("We choose to make
  equality total, thus allowing unsoundness", `shape-polymorphism.md:490-509`), inequalities
  are decided by bounds or raise `InconclusiveDimensionOperation` (`:239-271`). Bounds come
  from elimination of terms against constraints (`shape_poly_decision.py:50-70`).
  User constraints `>=`, `<=`, `==` (equalities as rewrite rules) (`:291-358`).
- Dimension variables must be solvable from input shapes, only from linear univariate
  equations (`:511-600`); unsolvable ones are passed as empty arrays of shape `(0, k)`
  (`:557-584`).
- Calling convention: the inner function takes dimension variables as scalar `i32`/`i64`
  arguments; `main` extracts them with `get_dimension_size` and checks
  `@shape_assertion` custom calls for every implicit constraint (`export.md:527-625`).

**Steal.**
- Dimension values as ordinary integer arguments next to the arrays, with the shape
  facts checked once at the boundary: in Idris these are the erased-or-not indices of the
  array type. "Erased does not mean constant" (AGENTS.md): an index at quantity 0 is still a
  runtime size when the program needs it, and the compiler must pass it like JAX's
  dimension arguments.
- The algebra of size expressions (`floordiv`, `mod`, `max`, `min` over linear terms) is
  what `idr-in-bounds`'s Presburger systems already decide exactly (`Passes.td:443-470`);
  JAX shows which operations real array programs need on sizes.

**Avoid.**
- JAX's unsound total equality (`shape-polymorphism.md:490-509`): a typed APL has Idris's
  proofs of size equalities; the compiler must never decide an equality it was not given.
- Rejecting what cannot be decided at trace time (`InconclusiveDimensionOperation`): in our
  setting the type checker already accepted the program, so a size fact the compiler cannot
  decide must stay a runtime check or a proof term, never an error.
- Recompilation per concrete shape (`shape-polymorphism.md:45-47`): we compile once,
  ahead of time.

**Limits.** Tracing semantics, not a type system; only linear univariate solving; the
decision procedure is incomplete by design (`shape_poly_decision.py:50-70`).

### 2.13 Mojo

`sources/docs/mojo/Mojo/docs/**` *(staged)*.

**Key ideas.** Mojo is built on MLIR and exposes it in source: `__mlir_type`,
`__mlir_attr`, `__mlir_op` (with `_type`, `_properties`, `_region`) and `__mlir_region`
(`site/reference/inline-mlir.mdx:23-63, 416, 511-540`). Its own `pop` dialect is
*parametric*: types and ops before elaboration carry parameters (`!kgen.simd<size, dtype>`,
`!pop.array<size, type>`), the elaborator resolves them, and the post-elaboration IR is a
serializable, target-independent distribution format (`stdlib/internal/pop_dialect.md:5-60`);
`pop.cast_to_builtin`/`cast_from_builtin` bridge to builtin types and `vector`
(`:87-140`). Parameter expressions stay symbolic (`T[Int.add(a,b)]`), folded by a limited
symbolic inlining rather than the interpreter (`stdlib/internal/mlir.md:12-51`). The parser
type-checks without instantiation, so `rebind` defers a type equality to elaboration
(`site/manual/parameters/index.mdx:1348-1400`). SIMD width and dtype are parameters of
one `SIMD` struct (`:456-525`). Hardware lowering goes through LLVM-level dialects and other
MLIR backends (`site/faq.md:99-104`).

**Steal.** The split between a parametric pre-elaboration IR and a monomorphic one is ours
already (Idris monomorphises, the `idr` dialect is monomorphic). The `rebind` lesson: a
dependent type checked before instantiation needs an explicit equality at instantiation;
Idris supplies the proof, so the compiler never needs `rebind`.

**Avoid.** Inline MLIR in the surface language: it bypasses the type system that is the
point of a typed APL, and AGENTS.md keeps the language's meaning in Idris plus our runtime.
Mojo's compiler is closed; only its docs and stdlib are open.

**Limits.** Internal docs are explicitly unstable (`stdlib/internal/mlir.md:1-8`); there is
no published account of Mojo's array (tensor/layout) lowering in this snapshot.

## 3. The lowering map, without a rank ceiling

The question 0004 §3.7 answered timidly ("the backing stays one-dimensional", rank-r only
by name and only for words): what upstream gives is enough for every static rank, and a
small set of idr ops covers what it does not.

### 3.1 Static rank (rank a literal after monomorphisation): no ceiling

| APL concept | Upstream mechanism | Source |
| --- | --- | --- |
| array of rank r, shape `[d1..dr]`, element E | `tensor<?x...x?xE>` (r dims) before bufferization; `memref<...>` after | §2.4, §2.5 |
| pointwise lift of a scalar function | `linalg.map` / `linalg.generic` with identity maps, all `parallel` | `LinalgStructuredOps.td:233` |
| frame agreement / prefix broadcast (Remora principal frame) | projected indexing maps in one `generic` (no data movement), or `linalg.broadcast` | `_index.md:167-240`; `LinalgStructuredOps.td:474` |
| lift of a cell function of rank c over a frame of rank f | one `generic` over f+c' dims: frame dims `parallel`, the cell's own loop dims as its body needs; body = the cell function | `_index.md:76-300` |
| reduce along any axes with a monoid | `linalg.reduce dimensions=[...]` with the monoid in the region | `LinalgStructuredOps.td:314` |
| inner/outer product, contraction | `linalg.contract` / `generic` | `LinalgStructuredOps.td:824` |
| transpose / permute axes | `linalg.transpose` or permutation maps | `LinalgStructuredOps.td:398` |
| reshape between ranks | `tensor.expand_shape` / `collapse_shape` (views when contiguous) | `TensorOps.td:1091, 1176` |
| take, drop, slice | `tensor.extract_slice` | `TensorOps.td:362` |
| catenate / laminate | `tensor.concat` | `TensorOps.td:131` |
| fill, pad | `linalg.fill` of `tensor.empty`; `tensor.pad` | `TensorOps.td:264, 1251` |
| index by computed position (gather, rotate) | `generic` body with `linalg.index` + `tensor.extract` | §2.4 |
| fusion of producer into consumer | `linalg-fuse-elementwise-ops`, `transform.structured.fuse` | `Linalg/Passes.td:167`; `LinalgTransformOps.td:439` |
| tiling for cache | `scf::tileUsingSCF` / `tile_using_for` via `TilingInterface` | `code/mlir/include/mlir/Interfaces/TilingInterface.td:19-500` |
| SIMD | `linalg::vectorize` → `vector` (already `idr-vectorize`) | §2.7 |
| in-place update of a value array | One-Shot Bufferize on DPS ops | §2.5 |
| data-parallel over cores | `tile_using_forall` → `scf.forall`; or `shard` + `shard-partition` | §2.9, §2.10 |
| sparse array | tensor with `#sparse_tensor.encoding`, `sparse-tensor-codegen` | §2.8 |

Nothing in this table restricts r. `Idr_ArrayType` must admit `memref` of any rank (it
already takes one size/index per dimension in its ops), and the frontend must emit the
r-dimensional op directly from the Idris array type's rank, not reconstruct it from a 1-D
backing by name.

### 3.2 Dynamic rank: canonical collapse plus an idr op

Ranked types need the rank at compile time (§2.3 Limits, §2.4 Limits). When the rank is
not a literal after monomorphisation (rank-polymorphic recursion over rank, a rank computed
at run time), upstream has no op: unranked tensors are not `linalg` operands, and
reassociations are static. Two facts make this small:

1. **Contiguous arrays of any rank are collapsible.** A pointwise lift at any rank is the
   1-D `generic` over the collapsed buffer; a reduction over one axis k is the 3-D
   `generic` over (prefix product, d_k, suffix product); a lift of a cell function with
   frame rank f is the 2-D `generic` over (frame product, cell product) when the cell
   function itself is pointwise or a reduction. These shapes are fixed-rank and need only
   the runtime products of the shape — the same scalar dimension values JAX passes (§2.12).
2. **Only the shape vector is dynamic data.** A dynamic-rank array is a descriptor (rank,
   shape vector, data); the data is a 1-D memref.

So the idr dialect needs a dynamic-rank array type (descriptor: rank, extents, one
backing) and ops that view it at a fixed collapsed rank given runtime extent products. A
static rank is a special case that canonicalizes to the ranked tensor. That keeps one
representation (AGENTS.md "one thing, one representation"): the descriptor's shape is the
type's shape whenever the rank is known.

### 3.3 Element types beyond words

`tensor` and `memref` already accept idr element types (§2.3 Limits). What restricts 0004
§3.1 to words is (a) bufferization's copy and (b) the vectorizer. (a) is a hook:
`memCpyFn` can emit a counted copy (dup per element) and `allocationFn` our cell
(§2.5 Steal). (b) is not a limit on correctness: a non-vectorizable `generic` lowers to
loops (`convert-linalg-to-loops`), as `idr-vectorize` already leaves scalar loops. The
remaining real constraint is aliasing through counts: a counted array value shared by two
references must not be written in place; One-Shot sees SSA aliasing only. Exclusivity
(`!idr.excl<T>`, `Passes.td:611-618`) or quantity 1 is exactly the fact that makes it safe.

## 4. Missing upstream, and where `idr` must add

| Need | Upstream at the pin | idr must add |
| --- | --- | --- |
| scan with a user monoid | none in `linalg`/`tensor`; `vector.scan` has a fixed combining kind (`VectorOps.td:3032`) | `idr.array.scan` (region combiner over an axis, `reverse`), implementing `TilingInterface` (and `PartialReductionOpInterface` for a two-pass parallel scan), modelled on `tt.scan` (`code/triton/.../TritonOps.td:876-905`) |
| dynamic rank | none (§3.2) | a descriptor array type and fixed-rank view ops (`idr.array.view` at a collapsed rank, `idr.array.shape`) |
| gather/scatter that reach code | `tensor.gather`/`scatter` lack bufferization (§2.4) | `generic` bodies with `tensor.extract`, or an idr op with a `BufferizableOpInterface` model |
| allocation in our runtime's cell | `memref.alloc` | `allocationFn` building `idr.array.alloc` (0004 §3.5) |
| copying counted elements | `memref.copy` | `memCpyFn` emitting a counted copy |
| linearity across bufferization | `TensorLikeType`/`BufferLikeType` exist (`BufferizationTypeInterfaces.td:18-50`) | `!idr.lin`/`!idr.excl` implementing them over tensor and memref carriers |
| SPMD collectives on our shards | `ShardToMPI` (C library) | lowering of `shard` collectives to the shard runtime (0005) |
| parallel `scf.forall` on CPU without a C runtime | `scf-to-openmp`, `async` | lowering `scf.forall` to our fork/join (0005 P4) |
| nested / ragged arrays (boxed APL) | none; `linalg` has no nesting (`_index.md:679`) | arrays of `!idr.box` elements (legal tensor elements) plus element-aware bufferization; ragged as an array of arrays, not a linalg value |
| sparse arrays of non-numbers | encoding restricted to numeric elements (`SparseTensorAttrDefs.td:129-131`) | out of scope until a program needs it |
| proven associativity/commutativity/neutral element | not representable; reductions carry only `reduction` iterators | a property of the reduction op proved by Idris, kept in the op (not a discardable attribute) so float reductions may reassociate only when proved |

## 5. Rules these sources impose on a revised 0004

- One representation: emit structured ops from the Idris array type's rank; do not keep a
  1-D backing plus a recognized-by-name rank-r library (§3.1).
- Every op the frontend emits is in DPS, so One-Shot never allocates where a destination
  exists (§2.5).
- Quantity 1 and exclusivity stay in types across bufferization through
  `TensorLikeType`/`BufferLikeType` (§2.5).
- No C runtimes: not `library_call`, `sparse-tensor-conversion`'s runtime, ShardToMPI,
  OpenMP or async (§2.3, §2.8, §2.9, §2.10).
- Shape facts Idris proved are never re-decided unsoundly (JAX's total equality, §2.12);
  undecided facts stay runtime checks.
- Scan, dynamic rank and counted-element copies are the three genuinely new idr pieces;
  everything else is upstream's.
