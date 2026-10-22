<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design: the e-graph's relations and matching in MLIR's sparse tensors

Status: written 2026-10-21 for D85 and D86
(`proposals/0000-mlir-native.md:1218-1245`, read in the working tree),
with D87 (`:1246-1259`) and the sibling `one-engine.md` read so the files
agree. D85 asks for full equality saturation, one engine written once,
whose relations become dense code "after the sparse arrays lowering in
mlir". D86 sends the engine to the C++ as MLIR printed by the
specification generator, compiled by the pinned toolchain's passes (the
sparsifier among them) to bitcode and linked statically. This file
designs that MLIR. It says which parts of an e-graph are sparse tensors
through the sparsifier, which are plain loops, which upstream patches it
needs (carried, D25), and what the generator prints for one rule, end to
end, to bitcode.

Grounds: *read* (a path:line), *measured* (a command I ran, named),
*recalled* (from memory), *conjecture*, *decision* (a ruling Dn). MLIR at
the pin is 7208ba24 (`.toolchain/llvm-project`, a one-commit checkout);
`M/` below is `.toolchain/llvm-project/mlir/`.

**What the measurements are, and are not.** No `mlir-opt` is built under
`.toolchain/` on this machine (the bootstrap's distribution lists it,
`tools/bootstrap.sh:1012`, but the toolchain here holds only the
TableGen and typecheck builds). Every *measured* claim used Homebrew's
LLVM 22.1.8 (`mlir-opt`, `mlir-translate`, `llc`, `clang`) on an Apple
M2 Max (virtual), arm64 macOS, on scratch files in
`/tmp/sparse-egraph-{exp,bench,up}`. LLVM 22.1.8 is not the pin, and two
divergences were seen. It accepts an `i1` sparse element, which the
pin's parser refuses (`M/lib/AsmParser/TypeParser.cpp:434-438` with
`M/lib/Dialect/SparseTensor/IR/SparseTensorDialect.cpp:922-931, 979-980`).
It also spells `sparse_tensor.sort`'s `perm_map` as an attribute
dictionary, where the pin's assembly format has a keyword
(`M/include/mlir/Dialect/SparseTensor/IR/SparseTensorOps.td:937-941`).
So a "compiles" below means it compiles on 22.1.8 and the pin's source
reads the same; each must be re-run with the pin's tools. Times are best
of five, single-threaded, on synthetic data, and bound nothing at our
scale.

## 0. In plain words

- **Yes, for the relational half.** E-matching a rule's pattern is a
  conjunctive query, and a conjunctive query over relations held as
  `i8` sparse tensors with `explicitVal = 1` is a `linalg.generic` that
  the sparsifier compiles to merge loops over dense `u32` buffers. Most
  relational steps compile today in codegen mode, with no runtime
  library: the join, the semi-naive delta (a set difference), the union
  of match sets, projections, extraction's cost sweep, and building
  indexes (sort, then assemble). The objects reference only `malloc`
  and `free` (*measured*).
- **No, for the union-find half.** `find` and `union`, canonicalizing a
  relation through the union-find (a gather, which no affine indexing
  map expresses), repairing congruence after a merge, lookup-or-insert
  of a node with a fresh class id, and the per-match application of a
  right side have no sparse-tensor form. They are plain `scf` and
  `memref` loops in the same module, compiled by the same pipeline, and
  they compile (*measured*).
- **Where the time goes** (*measured*, §6). A join costs about 5 ns per
  input tuple. Sorting a tuple table costs 95 to 118 ns per tuple.
  Materializing the matches costs 2.3 times the join into a sorted-COO
  output, and 4.7 times into a trie. So the dense join is not the cost.
  Index building and match materialization are. The fixes are sorting
  only what changed, a radix sort over dense ids, and applying matches
  inside the join (§4, U-S3).
- **One asymptotic gap.** The sparsifier intersects by a linear merge
  that advances one coordinate at a time. A semi-naive delta of 16
  tuples joined against a table of 2.1M costs time linear in the table
  (2.8 ms, against microseconds for a seek), so semi-naive evaluation
  buys nothing until co-iteration seeks. That is one upstream patch
  (U-S1, §4), the mechanism Etch's seek and Finch's looplets already
  have.
- **Three findings for the other files.**
  1. The allocation-free boundary of `one-engine.md` §5.2 holds for
     sort, assemble, joins into dense outputs, and loops. It fails for
     every sparsifier kernel with a sparse output, because their
     insertion code grows by `memref.realloc` (§1.6). Either the engine
     owns temporaries, or the matches go straight into the arena
     (U-S3).
  2. U-S1 moves 0015 D5's line on what a sparse-array plan may be.
  3. Upstream's `sparse-assembler` emits rank-1 coordinates for an AoS
     COO segment, which `assemble`'s verifier refuses. This design does
     not reach it (§4).

## 1. The pinned `sparse_tensor` dialect, as this design uses it

### 1.1 Encodings

- **Level formats** (*read*, `M/include/mlir/Dialect/SparseTensor/IR/SparseTensorAttrDefs.td:165-172`;
  `Enums.h:154-161`): `dense`, `batch`, `compressed`, `loose_compressed`
  (each segment its own lo and hi, room between them), `singleton`
  (coordinates with no siblings, fused into the parent's COO segment),
  and `structured[n, m]` (n of m consecutive entries).
- **Properties** (`:186-190`; `Enums.h:204-207`): `nonunique`,
  `nonordered`, and `soa` (singletons only).
- **Verifier** (`SparseTensorDialect.cpp:805-851`): a singleton follows a
  compressed or loose level; `structured` is last, after dense levels
  only; a dense level never follows a non-unique one.
- **Widths**: `posWidth` and `crdWidth` of 8 to 64.
- **Values**: `explicitVal` (every stored entry has that value) and
  `implicitVal` (only 0 is supported, `SparseTensorDialect.cpp:968-976`).
- **Elements** must be a primary type: `f16`, `bf16`, `f32`, `f64`, `i8`
  to `i64`, or a complex. Neither `i1` nor `index` is one
  (`:922-931, 979-980`).
- **Relations.** A relation is therefore an `i8` tensor with
  `explicitVal = 1` (0009 §10; 0015 §4).

### 1.2 What a `linalg.generic` over sparse operands may be

- **Shape** (*read*, `M/lib/Dialect/SparseTensor/Transforms/Sparsification.cpp:1404-1468`):
  - one output, pure tensor semantics;
  - no non-trivial affine index on a sparse output;
  - loops already scheduled (`sorted`, set by `sparse-reinterpret-map`).
- **Reductions** are `addi`, `addf`, `subi`, `subf`, `ori` or `xori`
  only, or a custom `sparse_tensor.reduce`. A `min`, a `max` or an
  `and` reduction goes through `reduce`.
- **The Merger's kinds** (`M/include/mlir/Dialect/SparseTensor/Utils/Merger.h:129-196`;
  `M/lib/Dialect/SparseTensor/Utils/Merger.cpp:1046-1131`):
  - `muli` and `andi` iterate the conjunction of the operands' sparse
    spaces;
  - `addi`, `ori`, `xori` and `subi` iterate the disjunction;
  - comparisons iterate a disjunction with zero;
  - `sparse_tensor.binary`, `unary` and `select` state the absent cases
    by region.
  - There is no min or max kind, and an op outside the list is not
    sparsified. In particular a `func.call` in the body (a hook, an
    analysis) makes the kernel fall out of the sparsifier.
- **Semirings** follow from this: Boolean is `andi` over `ori`
  (conjunction, then an admissible reduction); counting is `muli` over
  `addi`; min-plus needs `reduce` and a dense result, because the
  implicit zero must be 0 (0009 §9 says the same).
- **Outputs whose sparsity is unknown are admissible**
  (`M/lib/Dialect/SparseTensor/Transforms/Utils/CodegenEnv.cpp:135-179`;
  `SparseReinterpretMap.cpp:506-524`). The output must materialize from
  `tensor.empty` or `alloc_tensor`, and insertion must run in
  lexicographic order. That holds when every output loop is outermost
  and parallel, or when at most the innermost output dimension sits
  under reductions, which uses the access-pattern expansion, whose
  workspace is a dense array as long as that dimension.
- **Scheduling.** The output's level order is a scheduling constraint,
  so a sparse output pins the loop order. A cyclic iteration graph is
  resolved by inserting one `sparse_tensor.convert` (a transposed copy)
  of one input, and otherwise refused (`SparseReinterpretMap.cpp:442-469, 528-593`).

### 1.3 Co-iteration

An intersection is a two-finger merge. Each step loads both
coordinates, takes their minimum, and advances every iterator that sits
at it by one. *Read*: `SparseTensorIterator.h:314` (`forwardIf`);
`locate` exists only for random-access levels (`SparseTensorIterator.cpp:92, 113`).
*Measured*: the sparsified join below is that `scf.while`. There is no
seek or gallop. Its cost is linear in the sum of the co-iterated
levels' sizes, which 0015 §4 already names (`proposals/0015-relational-core.md:152-156`).

### 1.4 Point lookup

`tensor.extract` on a sparse tensor has no codegen pattern. The codegen
pass declares only `tensor.extract` of a 0-d tensor legal for its own
rewrites (*read*, `SparseTensorPasses.cpp:266-270`). So "is node f(a, b)
present, and what is its class?" has no `sparse_tensor` form. It is a
binary search over the sorted table: loops (§2.6).

### 1.5 Building and sorting

- **`sparse_tensor.assemble`** wraps caller buffers as a sparse tensor
  and checks nothing (0009 §9). It requires a *static* dimension shape
  (*read*, `SparseTensorDialect.cpp:1336-1341, 1396`;
  *measured*: "the sparse-tensor must have static shape" on a `?` shape).
  It copies nothing (*measured*: a kernel over two assembled operands
  has no `memref.alloc` or `memref.copy` other than its own 0-d
  accumulator).
- **`sparse_tensor.sort`** sorts one AoS buffer of tuples under any
  permutation (`perm_map`), in place (`SparseTensorOps.td:909-944`). It
  is generated as code (a hybrid quicksort with heap-sort fallback,
  partition and binary-search helpers; *measured* by the object's
  symbols). Every algorithm offered is a comparison sort.
- **`sparse_tensor.convert`** to an ordered format from an unordered COO
  is staged. It copies into a fresh unordered COO, sorts that in place
  (`reorder_coo`), then inserts into the destination (*read*,
  `M/lib/Dialect/SparseTensor/IR/SparseTensorInterfaces.cpp:25-65`).
  The source is never sorted in place, and each tuple is inserted twice.

### 1.6 Insertion

Codegen insertion into a compressed level compares against the level's
last coordinate only, appends otherwise, and grows each buffer by
doubling through `memref.realloc` (*read*, `SparseTensorCodegen.cpp:270-345`).
Two consequences:

- **Out-of-order insertion corrupts silently.** An adjacent duplicate is
  dropped, but an insertion out of order produces malformed storage,
  with no check.
- **`explicitVal` folds reads only.** Its one use is at
  `Sparsification.cpp:504`, which folds the loaded value to the
  constant. Insertion still appends the value
  (`SparseTensorCodegen.cpp:134, 512`; *measured*: the generated
  `_insert_*` stores the `i8` into a values buffer that it reallocates).
  A relation pays one dead byte per tuple.

### 1.7 The pipeline

- **The pipeline.** `buildSparsifier`
  (`M/lib/Dialect/SparseTensor/Pipelines/SparseTensorPipelines.cpp:37-111`)
  runs generalization and fusion, then the sparsification-and-bufferization
  mini-pipeline, then the lowering to LLVM.
- **The runtime library is on by default**, so the build passes
  `enable-runtime-library=false` (`Pipelines/Passes.h:69-72`).
- **Anchors.** The passes are anchored on `ModuleOp` or `func::FuncOp`
  (`Transforms/Passes.td:14-546`). The engine's module is `func.func`
  only, so 0009's U2 (the sparse passes on `FunctionOpInterface`) is not
  needed for it.
- **Bufferization.** The mini-pipeline's bufferization options
  (`SparsificationAndBufferizationPass.cpp:218-245`) leave
  `allowReturnAllocsFromLoops` false
  (`M/include/mlir/Dialect/Bufferization/Transforms/OneShotAnalysis.h:41`).
  So an `scf.while` cannot carry a sparse value made in its body
  (`M/lib/Dialect/SCF/Transforms/BufferizableOpInterfaceImpl.cpp:1087-1120`;
  *measured*: "Yield operand #0 is not equivalent to the corresponding
  iter bbArg").
- **Linkage.** Upstream marks its generated helpers `private` at the
  func level (`SparseBufferRewriting.cpp:100`, `CodegenUtils.cpp:333`),
  but they reach the object as global symbols (*measured*: `T
  __sparse_hybrid_qsort_*`, `T __insert_*`).
- **The iteration ops** (`extract_iteration_space`, `iterate`,
  `coiterate`, `M/include/mlir/Dialect/SparseTensor/IR/SparseTensorOps.td:1470-1809`)
  are the "experimental" emit strategy (`Transforms/Passes.td:187-188`).
  *Measured* on 22.1.8:
  - upstream's own tests pass;
  - a hand-written nested `coiterate`/`iterate` join crashes
    `lower-sparse-iteration-to-scf` (exit 139), with identity level maps
    too;
  - the join of §2.4 under `sparse-emit-strategy=sparse-iterator`
    fails to verify ("number mismatch between iter args and results").

## 2. The e-graph mapped onto it

### 2.1 State: the arena

The state is dense memrefs that the C++ adapter carves from its
per-function arena, as `one-engine.md` §5.2 and `egraph.md` §4.1 place
it:

- **one tuple table per operator kind** `f` of arity `k`: AoS, `u32`,
  `k + 1` columns (children, then the output class), with a capacity
  and a fill;
- **the union-find**: a parent array, one `u32` per class, whose
  representative is the smallest id (`egraph.md` §4.1);
- **the next class id**;
- **the previous round's canonical tables**, for the delta (§2.5).

One table per operator kind means no operator tag is stored and none is
dispatched on at run time. The closed sum of node kinds is split into
relations once, by the generator (AGENTS.md's no static fact paid for).

### 2.2 Relations and indexes

- **Ids are `u32`, and the universe is static.** Every axis of every
  relation is `4294967296`. `assemble` needs a static shape (§1.5), and
  a compressed or singleton level allocates nothing per dimension, so
  the static universe costs nothing. It states the fact that the id
  type fixes, as 0009 states a size the program fixes as a static
  dimension. The widths are `posWidth = 32, crdWidth = 32`.
  - The one hazard is the access-pattern expansion, whose workspace is
    as long as the innermost output dimension. The generator never
    prints a kernel that needs it (§2.4), and a kernel with a dense
    output takes the class count from the arena as a dynamic dimension.
- **The output class is a coordinate, never a value.** Joins are on
  coordinates. An equality between one atom's value and another's
  coordinate has no `linalg` form, so the relation is `(k + 1)`-ary and
  Boolean. It is not a `k`-ary map whose values are classes.
- **An index is a permutation of a relation's columns**, one per
  `(operator, permutation)` that some rule's join reads. The generator
  computes the set from the rules (static). There are two formats:
  - *The output last*, with the keys in any order before it:
    `(keys : compressed ..., out : singleton)`. A singleton level holds
    one coordinate per parent position, so two classes for one key are
    unrepresentable in this index, and the functional dependency of a
    hash-cons is in the type. It is built from the canonical sorted
    table by one scan that writes positions and coordinates into arena
    buffers, then `assemble`. *Measured*: a join over it, and
    `assemble` with its trailing AoS segment, compile.
  - *The output not last*: sorted COO,
    `(c0 : compressed(nonunique), c1 : singleton(nonunique), ..., cn : singleton)`,
    assembled with no copy over the table sorted under that
    permutation. *Measured* (§6): a join over two sorted-COO indexes
    returns the same matches as over tries, at 1.0 to 1.4 times the
    time, and needs no trie built. The trie's levels are the runs, which
    the sparsifier finds as it goes.
- **D87's library must state what these use.** 0009 §9's `Level` has
  `Dense | Compressed | Singleton | LooseCompressed` and no properties.
  The sorted COO needs `nonunique`, and the static universe needs a
  width (input to `sparse-library.md`).

### 2.3 A pattern as a conjunctive query

The generator compiles each rule's left side to a conjunctive query by
relational e-matching's unnesting (*read*,
`sources/papers/zhang-2022-relational-ematching/algorithm.tex:264-300`).
There is one atom per operator occurrence, and one variable per pattern
variable, intermediate class and root.

It then chooses one variable order, by that paper's two heuristics:
- respect the functional dependencies;
- put intersections first, and batch variables that occur in one atom
  only (`optimizations.tex:88-125`).

Each atom's index is the permutation that lists its variables in that
order. So the iteration graph is acyclic by construction, and the
sparsifier's cycle repair (a hidden `convert`) never fires.

A variable repeated inside one atom, as in `(sub ?x ?x)`, is not
sparsified as a diagonal map `(x, r) -> (x, x, r)`. *Measured*: the
generic stays, and codegen fails with "failed to legalize unresolved
materialization". It is printed as two loop variables and a
`sparse_tensor.select` on `linalg.index` equality (*measured*:
compiles). A one-atom pattern is a scan with a filter anyway, the fast
path relational e-matching names (`optimizations.tex:15-30`).

### 2.4 The join

One `linalg.generic` per rule and semi-naive variant:
- its indexing maps are the atoms' variable lists;
- all its iterators are parallel;
- its body is the `arith.andi` of the `i8` inputs, the conjunction
  lattice;
- its output is a sorted-COO match tensor of rank equal to the variable
  count, its levels in the variable order.

The output's order pins the schedule. Insertion is lexicographic,
because every loop is a parallel output loop, so there is no expansion.

*Measured*: §8 shows what it lowers to. On the 4.2M-node e-graph the
join costs 21 ms counted, 48 ms with the COO output and 99 ms with a
trie output (§6). The output is COO because insertion into it is an
append.

A rule's side conditions (`egraph.md` §3.1's `Cond`) are read from
per-class analysis arrays in the apply loop (§2.6). A hook call in the
kernel's body would take it out of the sparsifier (§1.2).

### 2.5 Semi-naive evaluation

- **The delta.** `Δf` is the canonical table now, minus the previous
  round's table as it was stored (not re-canonicalized). A tuple that
  canonicalization changed is then new, which is what egglog's
  timestamps achieve (*read*, `sources/papers/zhang-2023-egglog/implementation.tex:52-80`).
  - In sparse form it is a `sparse_tensor.binary` with
    `overlap = {}, left = identity, right = {}` (*measured*: compiles).
  - Allocation-free, it is a merge loop of the two sorted tables into
    an arena buffer.
- **The variants.** The matches of an n-atom pattern are the union over
  `i` of the join with atom `i` read from `Δ` and the rest from `Now`.
  The union is one more kernel (`ori`, both inputs sorted COO;
  *measured*: compiles, not run), so a match with two delta atoms is
  applied once.
- **What it costs today.** `Δ ⋈ Now` co-iterates the join variable over
  both sides by the linear merge, so it costs `O(|Now|)`, not
  `O(|Δ| log |Now|)`. *Measured*, with 16 delta tuples:

  | Add's size | delta join time |
  | --- | --- |
  | 131k | 0.10 ms |
  | 525k | 0.52 ms |
  | 2.1M | 2.82 ms |

  Until U-S1, a delta round costs as much as a naive one in the join,
  and saves only in the apply.

### 2.6 Adding nodes: the apply

This part has no sparse form. It is a `sparse_tensor.foreach` over the
match tensor in storage order, which is lexicographic, so the class ids
it creates are deterministic at any thread count. *Measured*: a
`foreach` whose body calls functions and stores to memrefs compiles.

For each match, each node of the right side is `make(f, children)`:
- a binary search over the sorted canonical prefix of `f`'s table;
- on a miss, a fresh class (`parent[id] = id`) and a tuple appended past
  the prefix.

Then `union(root, class of the right side)`.

- **Two misses on one key.** Two misses on one key in one round make
  two classes. The next rebuild finds the duplicate key and unions
  them, so the table never holds a key twice after a rebuild. That is
  egglog's resolution of a function conflict by its `:merge` union
  (`implementation.tex:58-80`).
- **The budget.** `make`'s capacity check is the budget: the table's
  capacity is the representation of the budget (`one-engine.md` §5.2).
  The check is essential, the problem's own case. A full table ends
  saturation, and extraction proceeds: the function is less optimized,
  never refused.
- **Unknown sparsity.** New nodes are an append, never a sparse
  insertion. They become sparse tensors at the next index build, from
  a sorted table. So the generator never prints an insertion out of
  order (§1.6), and the hazard is unrepresentable in what it prints.

### 2.7 Rebuilding: congruence closure

Rebuilding has no sparse form, and is all loops (*measured*: they
compile).

1. **Canonicalize** every id of every tuple through `find`, with path
   halving. This is a gather, which no affine indexing map expresses.
2. **Sort** each table by key: `sparse_tensor.sort` on the arena table,
   in place.
3. **Scan** adjacent tuples with equal keys and different outputs, and
   `union` the outputs.
4. **Repeat** 1 to 3 while a pass makes a union. The number of roots
   strictly falls, so the loop ends by room left in a finite universe,
   with no count.
5. **Drop duplicate tuples**, and compact.

That is egglog's rebuild with union as the merge.

The incremental form is *conjecture*, motivated by §6's costs. One
`O(n)` scan finds the tuples that contain a non-root id. Only those are
canonicalized and sorted. Then one merge puts them back into the sorted
table. Sorting stops being `O(n log n)` per round.

### 2.8 Extraction

- **The sweep.** Per operator kind with cost `k_f`, one sweep is
  `best[c] = min over f(c1, ..., ck, c) of k_f + Σ best[ci]`. In sparse
  form it is a `linalg.generic` over the index keyed by output first,
  with dense `best` operands and the output loop parallel:
  - the children's loops are reductions;
  - `sparse_tensor.unary` (present region) computes the sum;
  - `sparse_tensor.reduce` with `minui` reduces it;
  - the result is dense.

  *Measured*: compiles. Sweeps repeat until none lowers a cost. Costs
  are naturals that only fall, so the repetition ends.
- **The choice.** Packing the cost into the high 32 bits and the node id
  into the low ones (or the id's complement, for `egraph.md` §4.2's tie
  to the larger id) makes the minimum also the argmin, with
  deterministic ties, and no second pass (*conjecture*, a
  representation).
- **Its model.** This is the tree-cost greedy extraction `egraph.md`
  §1.6 describes, blind to sharing. Extraction that sees counting stays
  `egraph.md` §10.3's research.

### 2.9 Analyses

D41's analyses whose `make` is C++ are `one-engine.md` §5.3's hooks.
Sparse form adds one constraint: a hook is called from loops (the apply,
a per-class pass after a rebuild), never from a `linalg.generic` body
(§1.2). A rule's condition is read as a per-class array, filled by the
hooks after each rebuild.

## 3. What compiles, what needs a patch, what has no sparse form

| part | form | at the pin, by reading and 22.1.8 | evidence |
| --- | --- | --- | --- |
| e-node relations | `i8`, `explicitVal = 1`, u32 ids, static universe | yes | read §1.1, §1.5; measured |
| index, output last | compressed keys, singleton output (the FD in the type) | yes | measured: compiles |
| index, output not last | sorted COO over the sorted table, no copy | yes; join 1.0-1.4× a trie's | measured, §6 |
| index build | copy, `sparse_tensor.sort`, scan, `assemble` | yes; the sort dominates | measured, §6 |
| e-matching join, tree patterns | `linalg.generic`, `andi`, COO output | yes; about 5 ns per input tuple, output 2.3× | measured, §6 |
| repeated variable | two loop variables and `select` | yes; the diagonal map fails | measured |
| semi-naive delta | `binary` set difference, variants, `ori` union | compiles; a delta join costs O(\|Now\|) | measured |
| projection | `ori` reduction into a sparse output | yes | measured: compiles |
| extraction sweep | `unary` and `reduce(minui)` into a dense output | yes | measured: compiles |
| union-find | `scf.while` over a memref | no sparse form; loops compile | measured |
| rebuild | gather, sort, scan | no sparse form; loops compile | measured |
| apply: lookup-or-insert, fresh ids, union | `foreach`, binary search, append | no sparse form; loops compile | measured |
| apply fused into the join | `coiterate` and `iterate` | not today | measured: crash and verifier failure on 22.1.8 |
| round loop carrying sparse indexes | `scf.while` over sparse values | not without U-S4 | read §1.7; measured |
| allocation-free sparse outputs | — | no: insertion grows by realloc | read §1.6; measured |

## 4. Upstream: patches, carried (D25), and what is not needed

Each patch lives in `upstream/<NN>-<name>/llvm.patch` with its report,
reproducer, `tests/upstream-<name>` check, `PINS.md` entry and plan, as
AGENTS.md requires. None is written. The numbers are this file's labels,
not `upstream/`'s.

- **U-S1. Seeking intersection in co-iteration.** It is needed for
  semi-naive evaluation to pay.
  - *What*: for a conjunctive lattice point over compressed (and
    sorted-COO) levels, the lagging iterator advances by exponential
    then binary search to the first coordinate at or above the leader's,
    instead of by one. Leapfrog intersection is Etch's seek and Finch's
    looplets (§7). Galloping is never asymptotically worse than the
    merge, which it falls back to when the gaps are one.
  - *Where*: `SparseTensorIterator.{h,cpp}` (a seek on compressed and
    singleton-run levels, beside `forwardIf`) and the loop emitter's
    co-iteration for intersections.
  - *Upstream test*: a sparsification FileCheck test of a skewed
    intersection showing the search loop, and an integration test of the
    result.
  - *Measured motivation*: §2.5's table.
  - *Its reach*: it turns the co-iterated intersection of generic join
    into Leapfrog Triejoin's, so the worst-case optimal bound of
    relational e-matching (`algorithm.tex:460-470`) holds for patterns
    whose intersections the variable order exposes (*conjecture*).
- **U-S2. No values buffer under `explicitVal`.** The storage layout,
  insertion, `assemble` and `disassemble` would omit the values field
  when `explicitVal` is set, which saves a byte and a realloc stream per
  tuple (§1.6). Carried only if measured above 5% of a round, by 0009
  §9's rule for U3.
- **U-S3. The iteration ops, made to lower nested joins with effectful
  bodies.** It would fix the crash in `lower-sparse-iteration-to-scf` on
  nested `coiterate`/`iterate`, and the sparse-iterator emit strategy's
  failure on sparse outputs. With it the generator prints the join as
  explicit iteration with the apply in the body:
  - no match tensor is built (*measured*: that costs 1.3× the join's own
    work on top of it, with the COO output);
  - nothing is allocated, which closes finding 1 of §0.

  It is *research* until the pin's behaviour is measured. The path is
  labelled experimental upstream.
- **U-S4. Loop-carried sparse values in the sparsifier's pipeline.**
  It would add an option that sets `allowReturnAllocsFromLoops` in
  `getBufferizationOptionsForSparsification`. Not needed: the round loop
  carries the arena's memrefs only, and builds and drops each round's
  indexes inside the round (*measured*: such a round compiles). Recorded
  so that it is not reached for.

**Not needed**, each with its reason:

| item | why not |
| --- | --- |
| 0009's U2 | the engine's functions are `func.func` |
| a dynamic-shape `assemble` | the id universe is static, §2.2 |
| private linkage of the sparsifier's helpers | LLVM's `internalize`, given the generated entry list, at the bitcode step, §5 |
| point lookup on sparse tensors | binary search over the sorted table |
| a radix sort in `sparse_tensor.sort` | if measurement asks for it, the generator prints an LSD radix sort over dense ids as loops; it is ours, not upstream's gap |

**Found, not reached.** At the pin, `sparse-assembler` gives an AoS COO
segment's coordinates the field's rank-1 memref type
(`M/lib/Dialect/SparseTensor/Transforms/SparseAssembler.cpp:38-55`),
while `assemble`'s verifier requires `?×rank` for a trailing COO
(`SparseTensorDialect.cpp:1345-1354`). *Measured* on 22.1.8: "input/output
trailing COO level-ranks don't match". This design assembles in its own
entry points and never runs the pass. Under AGENTS.md it gets a
report only when something in the tree reaches it.

## 5. The printed module and its way to bitcode (D86, concretely)

- **What the generator prints** (stock Idris on Chez):
  - one `egraph.mlir` in upstream dialects only (`func`, `arith`, `scf`,
    `memref`, `tensor`, `bufferization`, `linalg`, `sparse_tensor`),
    target-neutral;
  - the entry list;
  - the header `one-engine.md` §5.1 describes.

  All three are committed under D67's manifest. The text is in the
  pin's syntax (§0's sort spelling shows that the syntax moves), so a
  toolchain bump that changes it fails D67's regenerate-and-compare and
  the build, never silently.
- **Per target**, with the stage-2 tools the bootstrap installs
  (`tools/bootstrap.sh:1012`):
  1. `mlir-opt --sparsifier="enable-runtime-library=false create-sparse-deallocs=true"`;
  2. `mlir-translate --mlir-to-llvmir`, with the triple and data layout
     from the target's one entry;
  3. `opt -passes=internalize` with the entry list, then `-O3`;
  4. the bitcode into the tools' static link, as an object or under LTO.
- **Upstream's pipeline, whole.** Taking `--sparsifier` as it is keeps
  the pipeline upstream's as LLVM tracks main. A pass list of our own
  would be a copy that drifts.
- **The boundary**:
  - entries carry `llvm.emit_c_interface`;
  - they take memref descriptors (allocated pointer, aligned pointer,
    offset, sizes, strides) and scalars;
  - no sparse tensor crosses, because the engine assembles its own
    views;
  - the object references `malloc` and `free` only (*measured*), which
    the tools already get from the OS's C library.
- **No globals written**, only generated functions and constants, so
  the engine is reentrant under the parallel pass manager (*conjecture*
  from the generated module, which holds no `memref.global` written to).

## 6. Measurements

The kernel is §2.4's join for `(mul ?x (add ?y ?z))`. The e-graph is
synthetic: node `i` is a leaf below 64, otherwise an `Add` or a `Mul`
(even odds) of two classes drawn uniformly from those before it, one
class per node. The indexes are built and sorted by the C harness (not
timed). `mlir-opt --sparse-assembler --sparsifier=...`, `llc -O3`, a
`clang -O2` harness, best of five. Times are in ms.

| nodes | \|Mul\| | \|Add\| | matches | trie, count | COO, count | trie, output | COO, output | Δ16, trie | Δ16, COO |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 262,144 | 131,110 | 130,970 | 65,663 | 1.143 | 1.554 | 5.750 | 2.747 | 0.104 | 0.224 |
| 1,048,576 | 523,896 | 524,616 | 262,285 | 5.906 | 6.142 | 24.869 | 11.630 | 0.518 | 0.933 |
| 4,194,304 | 2,099,664 | 2,094,576 | 1,048,921 | 21.041 | 24.477 | 99.339 | 47.959 | 2.819 | 3.293 |

The trie and COO kernels agree on every match count, which
cross-checks the formats. The generated `sparse_tensor.sort` on 3×u32
tuples, best of five:

| tuples | time | per tuple |
| --- | --- | --- |
| 131,072 | 12.4 ms | 95 ns |
| 524,288 | 57.8 ms | 110 ns |
| 2,097,152 | 247.3 ms | 118 ns |

Read together (*conjecture* beyond the numbers):
- **The sort.** A round that re-sorts every index from scratch spends
  about twenty times its join on sorting. That matches what Sun et al.
  measured of Soufflé, insertion at 78% of its run time
  (`sources/papers/sun-2025-gpu-datalog/main.tex:133`, *read*). So
  sorting only the delta, and a radix sort over dense ids, come before
  any join tuning.
- **Small functions.** Most functions at stage-1 scale are small, so the
  fixed costs per round are what to measure at the pin first, with U1's
  instrument (`egraph.md` §7): the kernels' setup, and the allocations
  when a sparse output is used.

## 7. Relation to 0015, 0009 and the prior art

- **0015.** R4's layer 3 is this engine (D69, D85). Its e-matching plans
  have fixed formats, a fixed variable order and a fixed join order,
  with no hash level, lazy level or worst-case optimal intersection. So
  they are what 0015 D5 calls a 0009 sparse-array program
  (`proposals/0015-relational-core.md:239-241`), and this file is
  consistent with D5 as written. U-S1 would put a seeking intersection
  inside the sparsifier and move D5's line. That is a scope question
  between proposals, so it is the owner's.
- **0009.** §9 and §10 give the same encodings (`i8` relations with
  `explicitVal = 1`, semirings as `i8`, codegen only), and D22 the same
  boundary. Stage 6's U2 is not needed for the engine's module (§4).
- **Can idris-mlir compile the engine through this path?** Not in P0.
  - Bootstrap order: the C++ tools need the engine before idris-mlir
    exists (`one-engine.md` §7 weighs the bootstrap route).
  - The elaborator's printing must build on the stock host, so its
    operations are plain Idris bodies (D87, 0009 D45).
  - After self-hosting, with 0009 stages 6 and 7 and D87's `Faster`
    rows mapping each library operation to the op this file prints,
    idris-mlir compiling the engine would emit the same upstream-dialect
    module: the same kernels and the same loops (*conjecture*). The code
    that comes out is §8's either way.
- **Prior art**:
  - TACO formalized level formats and co-iteration by iteration
    lattices (`sources/papers/kjolstad-2017-taco/`, stored; Bik et al.
    2022 describes MLIR's sparsifier as built on it,
    `sources/papers/bik-2022-sparse-mlir/mlir.tex:702`, *read*).
  - Relational e-matching reduces e-matching to conjunctive queries
    under generic join, worst-case optimal
    (`zhang-2022-relational-ematching/algorithm.tex:460-470`, *read*),
    and egglog makes the e-graph the database, with semi-naive
    evaluation (`zhang-2023-egglog/implementation.tex:86-106`, *read*).
    This file compiles those queries with the sparsifier instead of
    interpreting them.
  - Etch's indexed streams (Kovach, Kolichala, Gu, Kjolstad, PLDI 2023,
    doi:10.1145/3591268) are one contraction language for sparse tensor
    algebra and relational algebra. The follow-up (arXiv 2507.06456)
    gives streams a seek, which is U-S1's mechanism (*read* through a
    search summary).
  - Finch and Looplets (Ahrens et al., OOPSLA 2025, doi:10.1145/3720473;
    CGO 2023) structure co-iteration by protocols (*read* through a
    search summary); a jumper looplet that gallops is *recalled*.
  - SparseTIR (composable formats, ASPLOS 2023) and tensor relational
    algebra (Yuan et al., VLDB 2021) are *recalled* and add nothing this
    design uses.
  - Datalog over semirings (Abo Khamis et al., PODS 2022) and FAQ (PODS
    2016) are *recalled* as the theory that a join with an aggregate is
    a semiring sum of products, which §1.2's lattices implement for
    Boolean and min-plus.

## 8. One rule, end to end

The rule is distributivity over machine words, which holds in Z/2^n
because it is a ring, so it has no condition, in `egraph.md` §3.1's
shape (a sketch, not compiled):

```idris
distribute : Rule IdrSig
distribute = MkRule
  { ctx = [(Many, I64), (Many, I64), (Many, I64)]          -- x, y, z
  , lhs = Op MulI [Var 0, Op AddI [Var 1, Var 2]]
  , rhs = Op AddI [Op MulI [Var 0, Var 1], Op MulI [Var 0, Var 2]]
  , conds = [], dir = Equal
  , bound = ..., linear = ..., safe = ... }
```

**What the generator derives**, in total functions over the rule:
- *atoms*: `MulI(x, a, r)` and `AddI(y, z, a)`, where `a` is the inner
  class and `r` the root;
- *variable order*: `a` first, the one intersection; then `x, r`,
  batched in Mul; then `y, z`, batched in Add;
- *indexes*: `MulI` permuted to `(a, x, r)`, output last, so the FD
  format; `AddI` permuted to `(a, y, z)`, output first, so sorted COO;
- *variants*: `ΔMulI ⋈ AddI` and `MulI ⋈ ΔAddI`, unioned.

**What it prints for the join.** This is the full-table variant; each
delta variant is the same text over a delta view. The text is
*measured* to compile and lower in the trie spelling (§6); the COO
spelling for `AddI`'s index was measured in the counting kernel.

```mlir
#MulI_axr = #sparse_tensor.encoding<{
  map = (x, a, r) -> (a : compressed, x : compressed, r : singleton),
  posWidth = 32, crdWidth = 32, explicitVal = 1 : i8 }>
#AddI_ayz = #sparse_tensor.encoding<{
  map = (y, z, a) -> (a : compressed(nonunique), y : singleton(nonunique), z : singleton),
  posWidth = 32, crdWidth = 32, explicitVal = 1 : i8 }>
#Match_distribute = #sparse_tensor.encoding<{
  map = (a, x, r, y, z) -> (a : compressed(nonunique), x : singleton(nonunique),
                            r : singleton(nonunique), y : singleton(nonunique), z : singleton),
  posWidth = 32, crdWidth = 32, explicitVal = 1 : i8 }>
!MulI = tensor<4294967296x4294967296x4294967296xi8, #MulI_axr>
!AddI = tensor<4294967296x4294967296x4294967296xi8, #AddI_ayz>
!Q = tensor<4294967296x4294967296x4294967296x4294967296x4294967296xi8, #Match_distribute>

func.func private @match_distribute(%mul: !MulI, %add: !AddI) -> !Q {
  %init = tensor.empty() : !Q
  %q = linalg.generic {
      indexing_maps = [affine_map<(a, x, r, y, z) -> (x, a, r)>,
                       affine_map<(a, x, r, y, z) -> (y, z, a)>,
                       affine_map<(a, x, r, y, z) -> (a, x, r, y, z)>],
      iterator_types = ["parallel", "parallel", "parallel", "parallel", "parallel"]}
    ins(%mul, %add : !MulI, !AddI) outs(%init : !Q) {
  ^bb0(%m: i8, %d: i8, %o: i8):
    %v = arith.andi %m, %d : i8
    linalg.yield %v : i8
  } -> !Q
  return %q : !Q
}
```

**What the sparsifier makes of it** (*measured*, from
`--sparse-reinterpret-map --sparsification`, abridged):
- one `scf.while` merges the two `a` coordinate arrays;
- inside a hit, nested `scf.for` loops run over Mul's `x` and `r`
  positions and Add's `y` and `z` positions;
- the innermost body is one insertion `[a, x, r, y, z]`;
- the loads of `explicitVal` are folded to the constant 1.

After codegen these are loops over `memref<?xi32>` position and
coordinate buffers: the "dense" form D85 named.

```mlir
%r:3 = scf.while (%pm = %m0, %pa = %a0, %q = %init) : (index, index, !Q) -> (index, index, !Q) {
  %more = arith.andi (%pm < %mEnd), (%pa < %aEnd)
  scf.condition(%more) %pm, %pa, %q
} do {
  %cm = memref.load %mulCrd0[%pm]   %ca = memref.load %addCrd0[%pa]
  %a = arith.minui %cm, %ca
  %q2 = scf.if (%cm == %a and %ca == %a) {
    scf.for %px = %mulPos1[%pm] to %mulPos1[%pm + 1] {        // x, then r
      scf.for %pr = ... {
        scf.for %py = ... {                                    // y, then z, in Add's run
          scf.for %pz = ... { tensor.insert %c1 into %q[%a, %x, %r, %y, %z] } } } }
  }
  scf.yield (%pm + (%cm == %a)), (%pa + (%ca == %a)), %q2
}
```

(The listing is abridged pseudo-MLIR; the full text is the output of
§6's command on `/tmp/sparse-egraph-exp/match.mlir`.)

**What it prints for the apply**: one `sparse_tensor.foreach` over `!Q`
whose body is
`c1 = make(MulI, x, y); c2 = make(MulI, x, z); c3 = make(AddI, c1, c2); union(r, c3)`.
It carries the round's outcome as a generated enum value, not an `i1`.
`make` and `union` are §2.6's loops (*measured*: compile).

**What it prints for the round**: `@egraph_round`, the entry, whose
`scf.while` carries only memrefs. Each iteration:
1. rebuilds (§2.7);
2. writes each needed index into the arena (a copy sorted under its
   permutation; a scan for FD-format indexes) and `assemble`s it;
3. computes the deltas by merge loops, and their indexes;
4. calls each rule's variants, the union and the apply;
5. stops when a round makes no tuple and no union, or the table is
   full.

*Measured*: a round of this shape, with `convert` for the index,
compiles and links against `malloc` and `free` only.

**Then** comes §5's per-target command chain. The bitcode's public
symbols are the entry list (after `internalize`). The header declares
`_mlir_ciface_egraph_round` and `_mlir_ciface_egraph_extract` with their
descriptor types. The C++ adapter calls the round, refills the analysis
arrays through its hooks between rounds (`one-engine.md` §5.3), then
calls extraction and elaborates.

## 9. Buildable now, patches, research, and questions

- **Buildable now** (by the pin's source, 22.1.8 measurements to
  repeat at the pin):
  - relations, both index formats, index building by sort and
    `assemble`;
  - joins for tree patterns and filtered repeated variables, unions,
    deltas, projections, the extraction sweep;
  - the union-find, rebuild, apply and round as loops;
  - the pipeline to an object with no runtime library.

  Semi-naive evaluation compiles but pays `O(|Now|)` per delta join.
  Sparse outputs allocate.
- **Needs carried patches**: U-S1, for semi-naive evaluation to pay;
  U-S2 if measured. U-S3 if the engine must allocate nothing, or to
  remove the measured cost of materializing matches.
- **Research**:
  - the incremental rebuild and index maintenance (sort the delta,
    merge runs);
  - a radix sort printed over dense ids;
  - the iteration-op form of the join (U-S3);
  - worst-case optimal behaviour on cyclic patterns, with U-S1;
  - the `Faster` route after self-hosting (§7);
  - everything `egraph.md` §10.3 already lists for extraction.
- **For the owner, one at a time**, each with its context above:
  1. *The allocation boundary* (§0 finding 1, §1.6, U-S3). Either the
     engine allocates kernel temporaries itself (freed before it
     returns; what compiles today), or it allocates nothing and its
     matches go straight into the arena (needs U-S3, research). This
     amends `one-engine.md` §5.2 either way.
  2. *U-S1 as a carried patch*, and with it 0015 D5's line on what a
     sparse-array plan may contain (§7).

**Representation-first handoff.**
- *Unrepresentable*: two classes for one key in an output-last index
  (the singleton level); a cyclic iteration graph (each atom's
  permutation derived from the variable order); an out-of-order sparse
  insertion (sparse tensors are only assembled from sorted tables, and
  new nodes are appends); a value-to-coordinate join (the class is a
  coordinate).
- *Deleted*: dispatch on an operator tag at run time (one relation per
  kind); per-round interpretation of rules (each rule printed as its
  own kernel); a round count (the measures are roots falling and room
  in the table).
- *Moved to the boundary*: the static facts (the index set, the formats,
  the variable orders, the id universe), computed once by the generator.
- *Essential*: `make`'s hit-or-miss and capacity checks, and rebuild's
  repeat-while-merged. The problem has those cases.
