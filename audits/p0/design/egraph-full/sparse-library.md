<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design: `mlir-sparse`, sparse tensors whose shape and format are in their types

Written 2026-10-21 at e96bb991 for D87 (`proposals/0000-mlir-native.md:1246-1258`):
"if this depends on a new idris type that is specially optimized for
sparse tensors, we clearly need to add that first ... the linear arrays
philosophy, exact mapping to mlir concepts, but this time for sparse
tensors." It designs the library D85 and D86 put under the one e-graph
engine (`:1218-1245`), beside `one-engine.md` (the engine and its route)
and `speed.md` (its cost). It reads the pinned MLIR
(`.toolchain/llvm-project/mlir`, written `M/` below, at 7208ba24 of
2026-10-08), `libs/mlir-array`, the registry, 0009, 0015, `egraph.md` and
L12. Nothing was built, run or changed: no MLIR tool is built in this
checkout (*measured*: `find .toolchain -name mlir-opt` finds none; only the
`tblgen` and `typecheck` trees exist), so every MLIR sketch below is
unrun, and each claim that rests on running one is marked *conjecture*.

Grounds: *read* (path:line), *measured* (a command named), *recalled*,
*conjecture*, *decision* (a design this file proposes, open to the owner's
and the coordinator's review; none is settled by being written here).

## 0. In plain words

- **What a sparse tensor means in MLIR** is not its dense value. It is its
  *stored entries*: `sparse_tensor.unary` and `binary` choose a region by
  whether an entry is "stored explicitly", `foreach` visits stored entries
  in storage order, and `number_of_entries` counts them (*read*, §1.2). So
  the library's one meaning is a finite map from in-bounds indices to
  elements, kept in the format's level order; the dense value is that map
  completed with 0, the only implicit value MLIR supports.
- **Three types.** `SArray s f e` (a value), `LSArray s f e` (linear, its
  values rewritten in place, its pattern fixed) and `LBag s e` (linear, an
  unordered multiset appended in place). They are the three things MLIR
  can do with a sparse tensor without a run-time test: a value op, the
  sparsifier's "simply dynamic" in-place update, and insertion into an
  unordered coordinate scheme (*read*, §1.4). Insertion into an *ordered*
  format is defined by MLIR only in ascending level order; the library
  makes that order a fact of its own construction (`build` sorts), never
  a caller's duty.
- **The format is in the type, by construction.** MLIR's encoding verifier
  has eight rules about which level types may follow which
  (`M/lib/Dialect/SparseTensor/IR/SparseTensorDialect.cpp:805-900`). The
  library's `Format` is a family whose constructors can build only
  encodings that pass them, so none is ever checked. The element is from
  a closed universe of MLIR's primary types, with `Present` (a set, MLIR's
  `explicitVal = 1`) as one more member, so a relation is a sparse array of
  `Present` and every operation serves sets and valued tensors alike.
- **Bodies, then hooks.** Every operation has a plain Idris body over a
  sorted list of entries: the one meaning, what the stock host runs.
  idris-mlir replaces the whole library (the types and their operations
  together, one group) with `sparse_tensor`, `linalg` and `tensor` ops
  through the registry's `Faster` kind. Equality between a body and its op
  is equality of stored entries in level order, bit for bit; it is held by
  a search we own (the reference bodies against the hooked ops, in one
  idris-mlir program), since MLIR's semantics is prose and code, not
  something Idris can prove against.
- **For the e-graph** the library gives function tables (the hash-cons, a
  finite map, so the functional dependency is a type), relational views of
  them for matching, joins as einsums over `Present`, and batched insertion
  through bags. The union-find is not a sparse tensor: every id has a
  parent, and `find` chases pointers, which no sparse or `linalg` op means.
  It is `mlir-array`'s growable linear array. The library does not serve
  0015's relational core whole: lazy tries, hash levels, galloping
  intersection and the plan interpreter are not MLIR level types.
- **Build order**: `mlir-array`'s linear arrays gain bodies (0009 D45);
  then this library; then the engine. On D87's route question this file
  agrees with `one-engine.md` §7.5 (the generator, D86 as recorded) and
  adds the library's part of the reason (§6).

## 1. What the pinned MLIR means by a sparse tensor

### 1.1 The encoding

- A sparse tensor is a ranked tensor with a `#sparse_tensor.encoding`;
  dimensions are the semantic axes, levels the storage's, and `dimToLvl`
  maps one to the other (*read*,
  `M/include/mlir/Dialect/SparseTensor/IR/SparseTensorAttrDefs.td:133-157,
  336-368`).
- Level formats: `dense`, `batch`, `compressed`, `loose_compressed`,
  `singleton`, `structured[n, m]`, with properties `nonunique`,
  `nonordered` and `soa`; by default a level is unique and ordered
  (*read*, `SparseTensorAttrDefs.td:163-189`;
  `M/include/mlir/Dialect/SparseTensor/IR/Enums.h:154-162, 204-208`).
- The verifier's rules (*read*, `SparseTensorDialect.cpp:805-900`): a
  singleton follows a compressed or loose level or another singleton; the
  singletons of one run share AoS or SoA; batch levels lead; SoA only on a
  singleton; a dense level never follows a non-unique one; `n_out_of_m`
  is last with only dense levels before it; the level rank is not zero.
- Elements: only `f16`, `bf16`, `f32`, `f64`, `i8` to `i64` and two complex
  types (*read*, `SparseTensorAttrDefs.td:129-131`;
  `SparseTensorDialect.cpp:922-931`); `i1` is not one. `explicitVal` makes
  every stored value one constant, so a set stores no values at all;
  `implicitVal` may only be 0 (*read*, `SparseTensorAttrDefs.td:207-222`).

### 1.2 Its meaning is the stored entries

- `unary` runs `present` or `absent` "depending on whether the operand is
  nonzero (i.e. stored explicitly in the sparse storage format)"; `binary`
  runs `overlap`, `left` or `right` by which operands store the entry, an
  empty region contributing nothing (*read*,
  `M/include/mlir/Dialect/SparseTensor/IR/SparseTensorOps.td:980-1012,
  1100-1127`).
- `foreach` "iterates over elements in their storage order" and gives
  dimension coordinates (*read*, `SparseTensorOps.td:1359-1400`);
  `number_of_entries` counts stored entries, explicit zeros included
  (*read*, `:386-404`).
- `convert` between sparse types moves "only explicitly stored values";
  from a dense tensor it tests for nonzero; to a dense one it makes the
  implicit zeros explicit (*read*, `:162-178`).

So two tensors with one dense value and different stored patterns are
different values to every op that has a region per presence case: the
meaning is the finite map (*decision*, from the reading).

### 1.3 Where MLIR leaves the meaning open

- **Insertion order.** `tensor.insert` into a sparse tensor is lowered on
  the assumption that insertions occur "in a reasonable order" with "no
  in-between insertions that need data movement" (*read*,
  `M/lib/Dialect/SparseTensor/Transforms/SparseTensorCodegen.cpp:455-461`):
  a compressed level compares the new coordinate with the last one only,
  reusing its position if equal and appending otherwise; a non-unique
  level always appends (*read*, `:270-357`, comment at `:317-321`).
  Out-of-order insertion into an ordered level builds a corrupt structure.
- **Duplicates.** The runtime library asserts on a duplicate insertion
  (*read*, `M/include/mlir/ExecutionEngine/SparseTensor/Storage.h:559`);
  codegen keeps the last value. The fast sorts are unstable; the one stable
  sort is insertion sort (*read*, `SparseTensorAttrDefs.td:633-639`).
- **Unchecked assembly.** `assemble` "does not perform any sanity test"
  (*read*, `SparseTensorOps.td:76-79`); writing into the buffers of
  `positions`, `coordinates` or `values` is undefined (*read*, `:276, 306,
  341, 370`).
- **Old SSA values.** After `push_back` or `compress`, "referencing the old
  SSA value is undefined behavior" (*read*, `:721-722, 821-822`). This is
  exactly what a linear type makes unwritable.
- **No point lookup.** Codegen converts `tensor.insert`, `tensor.empty`,
  `convert`, `load` and the storage getters, and no `tensor.extract` on a
  sparse tensor (*read*, the converter list
  `SparseTensorCodegen.cpp:555-1298`); a compressed level is not
  random-access (*read*,
  `M/lib/Dialect/SparseTensor/Transforms/Utils/SparseTensorIterator.cpp:92,
  113`). A lookup is a join, batched.

### 1.4 In place: the two admissible cases

The sparsifier admits a sparse output in two ways (*read*,
`M/lib/Dialect/SparseTensor/Transforms/Utils/CodegenEnv.cpp:135-162`):
"simply dynamic", which changes values but not the nonzero structure; and
"truly dynamic", where the output "materializes uninitialized" and
insertions occur in lexicographic index order. Outside a kernel, an
unordered non-unique coordinate scheme accepts insertion in any order
(the append path above). Copying a sparse tensor is
`bufferization.alloc_tensor copy(...)` (*read*,
`SparseTensorCodegen.cpp:754-767`).

### 1.5 When the sparsifier refuses a kernel

- One output, pure tensor semantics; a reduction whose combiner is not
  `add`, `sub`, `or` or `xor` must be a `sparse_tensor.reduce` (*read*,
  `M/lib/Dialect/SparseTensor/Transforms/Sparsification.cpp:1405-1458`;
  `SparseTensorOps.td:1213-1214`).
- A kernel with no admissible loop order fails: "the sparse kernel can not
  be scheduled", after trying masks and, for a cycle, converting one input
  (*read*, `M/lib/Dialect/SparseTensor/Transforms/SparseReinterpretMap.cpp:440-468,
  527-580`).
- The result of `binary` or `unary` "may only feed directly into the
  output ... or into a custom reduction" (*read*, `SparseTensorOps.td:1011,
  1127`): two custom products cannot nest in one kernel. The Merger knows
  `muli`, `mulf` and `andi` as products and `addi`, `addf`, `ori`, `xori`
  as sums, and no `min` or `max` (*read*,
  `M/include/mlir/Dialect/SparseTensor/Utils/Merger.h:129-215`).

A refused kernel would make acceptance a property of the optimizer
(`AGENTS.md:176-196`). So every kernel the library emits must be one the
sparsifier schedules by construction (§3.3).

### 1.6 What it costs, and what it does not do

- Co-iteration advances sorted cursors one by one; nothing gallops (*read*:
  the only binary search is the insertion sort's,
  `M/lib/Dialect/SparseTensor/Transforms/SparseBufferRewriting.cpp:314-330`).
  A join's intersection is linear in the sum of its sides, where generic
  join needs the smallest (*read*, `proposals/0015-relational-core.md:149-162`).
- Codegen allocates its own storage (`memref.alloc`,
  `SparseTensorCodegen.cpp:142, 765, 927, 1210`; `memref.realloc`,
  `SparseBufferRewriting.cpp:1361`, *read*). `finalize-memref-to-llvm`'s
  `use-generic-functions` sends allocation to `_mlir_memref_to_llvm_alloc`
  and its free, symbols the linker resolves (*read*,
  `M/include/mlir/Conversion/Passes.td:1052-1055`;
  `M/lib/Dialect/LLVMIR/IR/FunctionCallUtils.cpp:42`).
- The runtime library is optional: `enable-runtime-library` defaults to
  true and must be set false (*read*,
  `M/include/mlir/Dialect/SparseTensor/Transforms/Passes.td:191-192`); the
  explicit iteration ops are "experimental" (*read*, `:187-188`).
- Two sparse passes are anchored on `func::FuncOp` (*read*, `Passes.td:196,
  231`): 0009's U2 (`proposals/0009-typed-apl/README.md:935-936`).
  idris-mlir does not use the dialect today (*measured*: `grep -rln
  'SparseTensor\|sparse_tensor' foreign/idr` finds nothing).

## 2. The types

### 2.1 Shape (D60)

The shape is `Array.Core`'s: a `SnocList Nat` of index terms, its run-time
form `Extents s`, a position `Index s`, one `Fin` per axis
(`libs/mlir-array/Array/Core.idr:31-76`, *read*). A dimension is static
where its term is a constant after D58's specialization and `?` otherwise,
equal sizes inside a function tied at run time (D60, `0000:1000-1010`).
Those three definitions have bodies and no `%extern`, so the stock host can
use them; they move to their own module, `Array.Shape`, so that importing
a shape does not import the bodiless generating set (*decision*).

### 2.2 Format: MLIR's rules as constructors

The library offers the formats whose stored pattern is any set of indices,
one entry per stored index, with no explicit zero the format itself forces:
dense levels only before the first sparse one, then compressed or loose
levels, a coordinate run (a repeating head and its singletons) where one
is wanted, and any dimension-to-level permutation (*decision*). A dense
level after a sparse one stores whole blocks (BSR's inner levels), which
puts zeros in the pattern that no operation asked for; batch, `n:m`,
affine block maps and slices are left out with it. A format of no sparse
level is a dense array, which is `Array`: one thing, one representation.

| MLIR rule (`SparseTensorDialect.cpp`) | made unrepresentable by |
| --- | --- |
| singleton after compressed, loose or singleton (`:805-815`) | only `Run` makes singletons, after its head |
| one AoS/SoA per run (`:819-825`) | `Run` holds one `Layout` |
| batch levels lead (`:829-831`) | no batch level |
| SoA only on a singleton (`:833-841`) | `Layout` exists only in `Run` |
| no dense after a non-unique level (`:843-850`) | dense levels only lead |
| `n_out_of_m` rules (`:852-879`) | no `n_out_of_m` |
| non-empty level rank (`:887-889`) | `Groups` is non-empty |
| `lvlToDim` inferable from `dimToLvl` (`:897-900`) | `Perm` is a permutation by construction (a Lehmer code) |

Uniqueness and order are derived, never stated: every lone sparse level is
unique and ordered; a run's head and inner singletons are non-unique and
its last singleton unique. Coordinate width is derived from the shape: the
narrowest of 8, 16, 32 and 64 bits that holds every extent when all are
static, native otherwise; position width is native, since entry counts are
data (*decision*; a coordinate is a `Fin` of its extent, so the width is a
fact the type already holds, D58's "`Fin 256` is a byte").

### 2.3 Elements: a closed universe

`Elem` lists the Idris types whose image is a primary MLIR type (`Int8` to
`Int64`, `Bits8` to `Bits64`, `Double`), `Id n` (a class id below `n`,
`Fin n`, the typed ids 0009 §10 makes the precondition of relations,
`README.md:594-595`), and `Present`, whose one value is `()` and whose
image is `i8` with `explicitVal = 1` and `implicitVal = 0` (*decision*).
`El : Elem -> Type` decodes it. A closed universe makes a sparse array of
strings unwritable at the user's line; 0009's `SparseElement` interface
(D31, `README.md:873-874`) is open, so a user's instance would defeat its
own promise. `Present` folds 0009 §10's separate "relation" row into the
one family: the encoding's `explicitVal` follows from the element, one
fact in one place. MLIR's integer types are signless; signedness is the
Idris type's, read by the op that compares.

### 2.4 The three types

```idris
SArray : (0 s : Shape) -> (0 f : Format (length s)) -> (0 e : Elem) -> Type
LSArray : (0 s : Shape) -> (0 f : Format (length s)) -> (0 e : Elem) -> Type
LBag : (0 s : Shape) -> (0 e : Elem) -> Type
```

- `SArray` is a value, never written after it is made: `tensor<..., #enc>`.
- `LSArray` is given only fresh, at quantity 1, to a continuation whose
  result is unrestricted (`thaw`), as `LArray` is
  (`libs/mlir-array/Array/Core.idr:206-226`, *read*). Its pattern never
  changes; its values are rewritten in place, the sparsifier's simply
  dynamic kernel with the tensor as both input and output.
- `LBag` is a multiset of entries, appended in place in any order, given
  only fresh to a continuation (`withBag`) and left only by `build`. Its
  storage is fixed by its meaning, not chosen: compressed (non-unique,
  non-ordered) then singletons (non-unique, non-ordered), so it has no
  format parameter.
- D24, D70, D71 (`0000:375-398, 1101-1119`): `LSArray` and `LBag` are two
  more `in_place` entries. Their only introductions hand them to linear
  binders, so every value of them is exclusive (L12's theorem,
  `audits/p0/verify/L12-arrays.md:593-621`, *read*); exclusivity holds at
  every call, bufferization reads the grade, and MLIR's "referencing the
  old SSA value is undefined behavior" cannot be written. Elements are
  primary types, so D70's shared contents never arise. The writes are
  D61's per-parameter writes through an exclusive owned parameter
  (`0000:1011-1017`); every structure-building op acquires memory, an
  effect deletable when unused (AGENTS.md, Effects).
- This amends 0009 §9's "A linear sparse array is not offered"
  (`README.md:578`), in the change that lands the library.

### 2.5 What a kernel combines with: closed sums

- `Merge e`, how `build` keeps one value of entries at one index: an
  `arith` op that is commutative and associative by the primitive's own
  meaning (least, greatest, wrapping sum, bitwise or, and, xor; `Once` for
  `Present`). The sorts are unstable (§1.3), so only such a merge makes the
  result a function of the bag's multiset; a merge that could see the
  order is unwritable, and no law needs proving in Idris (*decision*).
- `Plus e` and `Times e`, an einsum's sum and product: `arith` ops the
  Merger reads (`ori`, `addi`, `addf`; `andi`, `muli`, `mulf`), which nest
  over any number of operands, or a region (`sparse_tensor.reduce` with
  its identity, `sparse_tensor.binary`'s overlap), which works over two.
  A sum, never a flag: the case is the representation MLIR has.
- No laws are carried, because the library promises no reassociation: a
  sum runs in the library's loop order, the same in the body and in the
  kernel, so a float sum is deterministic (0009 D15's ordered folds,
  `README.md:393-423`). A product over absent entries is absent: that is
  the finite-map meaning, and it differs from IEEE dense arithmetic only on
  NaN and infinities, as MLIR's sparsifier does (*read*: `mulf` is a
  conjunction to the Merger, `Merger.h:129-215`).

## 3. The generating set

### 3.1 Each operation, its MLIR, and its one meaning

Every operation is total on its inputs; none tests anything at run time.

| operation | MLIR | meaning (on stored entries) |
| --- | --- | --- |
| `extents x` | `tensor.dim` per dynamic dimension | the extents |
| `stored x` | `sparse_tensor.number_of_entries` | how many entries |
| `withBag e k` | `tensor.empty` of the bag's encoding, `k` applied | `k` of an empty bag |
| `add b i v` | `tensor.insert %v into %b[%i]` (the append path) | the bag with one more `(i, v)` |
| `build m b` | `sparse_tensor.load %b hasInserts`; `Once`: `sparse_tensor.convert` to `f`; otherwise a convert to an ordered coordinate scheme in `f`'s order, then `sparse_tensor.foreach` keeping `m` of each run and `tensor.insert` in order into a `tensor.empty` of `f`, then `load hasInserts` | the finite map whose value at `i` is `m` over the bag's values at `i` |
| `thaw x k` | `bufferization.alloc_tensor() copy(%x)`, `k` applied | `k` of a fresh copy |
| `mapInPlace g l` | `linalg.generic ins(%l) outs(%l)`, `sparse_tensor.unary present={g} absent={}`, `linalg.index` | each stored value `v` at `i` replaced by `g i v` |
| `freeze l` | the tensor itself | the same entries, no copy |
| `map g x` | `linalg.generic` into `tensor.empty`, `unary present={g} absent={}` | `g i v` at each stored `i` |
| `keep p x` | `linalg.generic`, `sparse_tensor.select` | the entries where `p i v` |
| `merge r x y` | `linalg.generic`, `sparse_tensor.binary` with `r`'s three regions | per index: overlap if both store it, left or right if one does, nothing for an empty region |
| `einsum sr q xs` | operands converted where their level order disagrees with the loop order, then one `linalg.generic` (maps and iterator types from `q`; body the `arith` product and sum, or `binary` feeding `reduce`, two operands per kernel) | at each result index met by a full assignment of the summed variables, the sum in loop order of the products |
| `convert x` | `sparse_tensor.convert` | the same entries in `g`'s level order |
| `foreach x st k` | `sparse_tensor.foreach in %x init(%st)` | `k` over the entries in level order, threading `st` |
| `densify x` | `sparse_tensor.convert` to the unencoded tensor | the dense array, 0 where nothing is stored |
| `sparsify a` | `sparse_tensor.convert` from the unencoded tensor | the nonzero entries |

`densify` and `sparsify` take a `Numeric e` witness (no `Present`, no `Id
n`, whose absence is not a number). They cross into `Array`, whose
operations are bodiless externs today (`Core.idr:12-16, 121-189`), so the
frontend may reach them only once 0009 D45 gives those bodies (§6).

### 3.2 What is not offered, and why

- `new`, `out`, `print`, `has_runtime_library`: the runtime library
  (codegen only; 0015 §1, `0015:32-33`; 0009 §9, `README.md:553-556`).
- `assemble`, `disassemble`, `positions`, `coordinates`,
  `coordinates_buffer`, `values`, `storage_specifier.*`, `slice.*`:
  storage exposed, unchecked (§1.3).
- `push_back`, `expand`, `compress`, `load` alone, `sort`, `reorder_coo`,
  `reinterpret_map`, `lvl`, `crd_translate`: the sparsifier's own
  vocabulary, reached through `build`, `einsum` and `convert`.
- `concatenate`: static inputs only (*read*, `SparseTensorOps.td:416`).
- `unary`'s `absent` region: it stores every index, so its result is a
  dense array; written as `densify` then `Array`'s `map`.
- `extract_iteration_space`, `iterate`, `coiterate`: experimental (§1.6).
  They are the MLIR concept for a join plan written by hand rather than
  scheduled; whether the engine wants them is open (§9, question 5).
- A point lookup: not an MLIR concept (§1.3).

### 3.3 Every kernel scheduled by construction

`einsum`'s loop order is the result's level order followed by the summed
variables in ascending order. An operand whose levels do not visit its
variables in that order is converted first to the same groups under the
permutation that does; the result is inserted in its own level order, a
prefix of the loop order, so the truly dynamic condition holds with no
access-pattern expansion (*conjecture* until the search of §4.4 runs every
format pair through the pinned sparsifier). `Einsum` carries erased proofs
that each operand's variables are distinct, the result's are distinct, and
every result variable is met in some operand (no dense broadcast). A
custom product over more than two operands is the left-nested chain of
two-operand kernels with no variable summed early, which keeps the meaning
exactly and costs the intermediates (*decision*). No kernel the library
writes is one the sparsifier can refuse; if the search finds one, the
library is wrong, not the program.

## 4. Bodies, hooks, and what equality means

### 4.1 The reference representation

```idris
||| A tensor's stored entries, their indices strictly ascending in the
||| format's level order: no index twice, and the order `foreach` visits.
public export
record Entries (s : Shape) (f : Format (length s)) (a : Type) where
  constructor MkEntries
  list : List (Index s, a)
  0 ascending : Ascending f (map fst list)
```

A sorted list, not `Data.SortedMap`, because its order is the storage
order `foreach` must reproduce, its invariant is a type, and its merges
are the sparsifier's own two-pointer co-iteration, so the stock host
differs from the compiled code by a constant factor, not an exponent
(*conjecture*, to be measured on the elaborator's workload). A bag is a
`SnocList (Index s, a)`; `build` is a merge sort on level order (total by
`SizeAccessible` on length, no `assert_total`) and a fold over runs.
`Entries` is parametrized by the element's type, not indexed by an erased
`Elem`, so no field's representation depends on an erased value (the
subset's dependent-field rule).

### 4.2 The hook group

`SArray`, `LSArray` and `LBag` have one constructor each over the
reference, private to `Sparse.Core`; each operation's body is the
reference function on the unwrapped value. Under idris-mlir a new hook
kind of `Faster` makes the three types tensors and every operation its op.
The pieces stand or fall together: removing only the type's hook would
leave the operations producing tensors for list-typed code. So the
registry holds them as one group, whose removal compiles the whole library
from its bodies with the same results (`Registry/Entry.idr:322-326`: a
`Faster` hook "is another lowering with the same meaning", *read*). Two
registry changes follow (*decision*):
- a `Bodied` expectation beside `Bodiless` (`Entry.idr:443-454`): a
  definition with a body whose own type is what its calls take, so no
  entry restates a type (today a bodied `Faster` entry restates its shape,
  `Registry/Primitives.idr:388-399`, *read*; `scalarBytes` moves to it in
  the same change);
- the group's rows and the translation's dispatch generated from one
  table, as L12's I12 asks for the array library
  (`L12-arrays.md:959-964`): one row per operation naming its MLIR form,
  read by the registry and, under route G, by `specgen`'s printer
  (`one-engine.md` §10). Every definition of `Sparse.Core` that sees the
  constructor is in the group, checked once when the registry is
  validated, so no unhooked body can match a tensor.

AGENTS.md says the `Faster` hook replaces a body "with a runtime op"
(`AGENTS.md:557-559`); here it is a dialect op, as D87 says, and that line
is amended to "a runtime or dialect op".

### 4.3 What equality means

For every operation and every input its type admits: the hooked op, after
the sparsifier in codegen mode, stores exactly the entries the body
stores, with bit-identical values, and `foreach` threads its state through
them in the same order. The dense views then agree. Where MLIR leaves the
meaning open (§1.3), the library's types exclude the input: no ordered
insertion by a caller, no duplicate reaching an ordered level, no storage
exposed. Float results agree because both sides run the same IEEE
operations in the same order (the library's loop order; the sparsifier
with vectorization and parallelization off), not because two printers
happen to agree (`AGENTS.md:563-564`).

### 4.4 How it is held, and what it costs

- **The search.** One test program, compiled by idris-mlir, generates
  shapes, formats, patterns and values (formats drawn over every group and
  permutation of small rank, swarm-weighted), and compares each hooked
  operation with the public `Sparse.Reference` function on the same input.
  That is a second implementation we own, two forms of one expression
  (`.claude/skills/testing-by-search/SKILL.md:14-21`); Chez is not
  consulted. Both hosts also run the library's program tests against their
  committed expected files.
- **The strongest form** is an erased specification per operation (the
  declarative einsum: the product over all assignments, grouped) and a
  proof that the body meets it; research-level proof work, not a
  precondition (*conjecture* on its size).
- **Costs.** Two lowerings of each operation exist (the body, the hook's
  translation) and their agreement is searched, not proved; the stock host
  runs lists; the registry gains a group, a hook kind and an expectation;
  idris-mlir's pipeline gains the sparsifier and U2. **Buys.** The stock
  host runs the elaborator's engine; the body is the one meaning; removing
  the group changes speed alone; no `%extern` is added, so nothing the
  stock host runs reaches one.

## 5. What the e-graph engine needs from it

- **Tables.** For an operator `f` of arity `k`, its function table is an
  `SArray` over `k` class-id dimensions with `Id n` values: children to
  class, the hash-cons. It is a finite map, so the functional dependency
  egglog keeps by its `:merge` (*read*,
  `sources/papers/zhang-2023-egglog/implementation.tex:22-51`) is a type,
  between rebuilds. Relational e-matching wants the class as a coordinate,
  `R_f(class, c1, ..., ck)` (*read*,
  `sources/papers/zhang-2022-relational-ematching/algorithm.tex:174-187`):
  that is a `Present` array of rank `k + 1`, derived from the table once a
  round (a `foreach`, a bag, `build Once`), and each index a join plan
  needs is the same fact under another permutation (`convert`), computed
  once and kept for every rule that reads it.
- **Matching** is an `einsum` over `Present` (`andi` products, `ori` sums),
  any number of operands in one kernel. `Q(root, a) <- R_f(root, a, x),
  R_g(x, a)` is three variables, result `(root, a)`, `x` summed, `R_g`
  converted to `(a, x)` order. The sparsifier runs it a variable at a time
  with linear merges: generic join's plan without its intersection cost
  (§1.6).
- **Insertion.** A rule's new nodes are appended to a bag of rank `k + 1`
  over `Present` (children, then class); `build Once` dedupes them exactly
  (duplicates of a set are equal); a `foreach` over the result, sorted by
  children then class, keeps the least class of each run and appends the
  others' unions to a pair bag, deterministically. The hash-cons lookup is
  this batch, as egglog's rebuild is batched (*read*,
  `implementation.tex:53-80`).
- **Rebuild.** Re-keying a table through `find` moves values into
  coordinates, which no `linalg` op does: `foreach`, a bag, `build`. The
  rows that name a changed class are a semijoin with a `Present` vector of
  changed ids (an `einsum`); they leave the table by a `merge` that keeps
  the left side only where the right stores nothing.
- **The union-find is not a sparse tensor.** Every id has exactly one
  parent (dense), `find` is a data-dependent pointer chase (`scf.while`
  over loads), and path compression is a point write: no `sparse_tensor`
  or `linalg` op means any of it. It is `mlir-array`'s `Linear.Vec` of ids
  (`libs/mlir-array/Linear/Vec.idr:38-48`, *read*), written in place under
  D71, its representative the least id (`egraph.md:666-667`, *read*).
  Per-class analysis data and costs are dense arrays too.
- **Extents.** A table's extent is the class capacity. A compressed level
  costs nothing per unit of extent, but a dense level and the sparsifier's
  access-pattern expansion cost the extent (*read*, `SparseTensorOps.td:772`);
  the engine's formats have no dense level, §3.3's loop order needs no
  expansion, and the capacity grows by copying at doubling (*conjecture*).
- **Memory under route G.** The engine "allocates nothing", the caller
  passing every buffer (`one-engine.md` §0). Every structure-building
  operation here allocates, and codegen grows coordinate arrays by
  `realloc` (§1.6). They meet through `use-generic-functions`: the C++
  defines `_mlir_memref_to_llvm_alloc` and its free over its per-function
  arena, one more link-time symbol beside the engine's hooks (*decision*,
  for `one-engine.md` §5.2 to take).
- **0015, whole?** No. The library is the fixed-plan subset (0015 D5,
  `0015:239-242`; 0009 D22): joins with fixed formats, variable order and
  join order; semi-naive deltas (`merge` with an empty overlap, 0009 §10,
  `README.md:585-591`); lattice-valued relations whose merge is in `Merge`
  (0015 D9, `0015:257-261`); aggregates as einsum sums. It is not COLT's
  lazy tries, hash levels, galloping or worst-case optimal intersection,
  the four-variant planner, Allen interval kernels, the interpreter over a
  validated plan, or sharded rounds (0015 §2, D1, D8, `0015:84-94,
  220-226, 250-256`); none of those is an MLIR level type
  (`Enums.h:154-162`). Whether 0015 is re-based on this library is the
  owner's (question 3).

## 6. Build order, and the route to the C++

1. **`mlir-array` first, under 0009 D45** (`README.md:876-899`):
   `Array.Shape` split out (§2.1); `LArray`'s operations and `Linear.Vec`
   gain bodies over base's `Data.IOArray` with a forged world, which a
   trusted library may use (`AGENTS.md:167-170`), so the union-find runs on
   the stock host; the `Array` operations `densify` and `sparsify` reach
   gain bodies when the frontend first reaches them.
2. **`mlir-sparse`**: `Sparse.Format`, `Sparse.Element`,
   `Sparse.Reference`, `Sparse.Core` (the generating set with bodies),
   `Sparse` (library code over it: union, intersection, difference, delta,
   graph of a function table); one row in `Registry/Libraries.idr:101-102`'s
   `moduleOrigin`; the hook group, `Bodied`, two `InPlaceType` rows; the
   translation generated from the one table; in idris-mlir's pipeline the
   sparsifier inside One-Shot's single bufferization (D43), runtime
   library off, U2; the search and the program tests on both hosts and all
   four targets.
3. **The engine** over it (`one-engine.md`).
4. **The route.** Weighed against AGENTS.md and D86, from the library's
   side (`one-engine.md` §7 weighs the engine's):

| | G: `specgen` prints the engine (D86 as recorded) | S: idris-mlir compiles the engine (a stage) |
| --- | --- | --- |
| what the library must be | its generating set also an interface over a value representation (`SparseOps v`), its own instance the bodies, `specgen`'s printers the others (`one-engine.md` §2.2's machine includes it) | plain functions; an interface with one instance is not written |
| who writes the library's MLIR | idris-mlir's hooks and `specgen`'s printer, both from the one table | idris-mlir's hooks alone |
| copies of the engine's meaning | the bodies (stock host), the hooked compile of the printed Idris (self-hosted elaborator), `specgen`'s MLIR (C++): three, held by one source and one set of fixtures | the bodies and one idris-mlir compile, shared by the self-hosted elaborator and the C++: two |
| the boundary | memref descriptors of generated `func.func`s, upstream dialects only, storage from the caller's allocator (§5) | a C-callable export of compiled Idris (`AGENTS.md:258-261`), and its values in idris-mlir's layouts (runtime array headers, `runtime/Alloc/Arrays.cpp:106`, *read* in L12 §3.3) crossing into C++, which would restate them (`AGENTS.md`: never the host's `sizeof` of a runtime header) |
| bootstrap | none: the stage-2 `mlir-opt` the bootstrap installs (`tools/bootstrap.sh:1012, 1354`, *read*) compiles it first | a stage without the engine, or a seed only idris-mlir regenerates (`one-engine.md` §7.2) |

S's one real gain is the last copy fewer: the same compiled engine would
serve the self-hosted elaborator and the C++. It is paid with an export
mechanism AGENTS.md forbids, the runtime's layouts restated in C++, and a
cycle. G keeps every rule, at the price of the staged interface and a
second printer of the library's ops, which the one table keeps from
drifting. Recommendation: G, as `one-engine.md` §7.5 (*decision*, for the
owner). Either way the library's types, meanings, bodies and table are the
same; only whether its generating set is also an interface waits on the
ruling.

## 7. What this amends, in the change that lands it

- 0009 §9 (`README.md:529-578`): `Format` as §2.2's family, not a vector of
  levels with any level anywhere; `SArray`'s argument order (the format
  depends on the shape, so the shape comes first); D31's interface becomes
  the universe; "a linear sparse array is not offered" goes; §10's relation
  row becomes `Present`.
- 0015 §1 and §4: the library is the C++ side's engine's vocabulary under
  D86 (as `one-engine.md` §8 item 4 records).
- AGENTS.md:557: "a runtime or dialect op".
- `Array.Core`'s shape definitions move to `Array.Shape`, their importers
  updated, no re-export.

## 8. The surface

```idris
-- Array.Shape (moved from Array.Core, unchanged): Shape, count, Extents,
-- Index, Cell, volume, volumeIsCount.

module Sparse.Format
%default total

||| The level a sparse group starts with.
public export
data Head = Compressed | LooseCompressed

||| How a coordinate run's singleton levels are laid out.
public export
data Layout = AoS | SoA

||| Sparse levels that go together: one unique, ordered level; or a head
||| whose coordinate repeats, then `S k` singletons, the last closing each
||| entry.
public export
data Group : (width : Nat) -> Type where
  Keeps : Head -> Group 1
  Run : Head -> Layout -> (k : Nat) -> Group (2 + k)

||| One or more groups, outermost first.
public export
data Groups : (width : Nat) -> Type where
  Last : Group w -> Groups w
  (::) : Group w -> Groups v -> Groups (w + v)

||| A permutation of `r` places by construction: each dimension's level,
||| among the levels not yet taken.
public export
data Perm : (r : Nat) -> Type where
  Nil : Perm 0
  (::) : Fin (S r) -> Perm r -> Perm (S r)

||| Leading dense levels, the sparse groups, and the dimension each level
||| stores.
public export
data Format : (rank : Nat) -> Type where
  MkFormat : (dense : Nat) -> {0 w : Nat} -> Groups w -> Perm (dense + w) ->
             Format (dense + w)

module Sparse.Element
%default total

public export
data Elem = Present | I8 | I16 | I32 | I64 | U8 | U16 | U32 | U64 | F64 | Id Nat

public export
El : Elem -> Type
El Present = ()
El I8 = Int8
El I16 = Int16
El I32 = Int32
El I64 = Int64
El U8 = Bits8
El U16 = Bits16
El U32 = Bits32
El U64 = Bits64
El F64 = Double
El (Id n) = Fin n

||| Elements whose absence is the number 0.
public export
data Numeric : Elem -> Type where
  NI8 : Numeric I8
  NI16 : Numeric I16
  NI32 : Numeric I32
  NI64 : Numeric I64
  NU8 : Numeric U8
  NU16 : Numeric U16
  NU32 : Numeric U32
  NU64 : Numeric U64
  NF64 : Numeric F64

||| Integers, signed or not.
public export
data Integral : Elem -> Type where
  II8 : Integral I8
  II16 : Integral I16
  II32 : Integral I32
  II64 : Integral I64
  IU8 : Integral U8
  IU16 : Integral U16
  IU32 : Integral U32
  IU64 : Integral U64

||| Elements with an order.
public export
data Ordered : Elem -> Type where
  Whole : Integral e -> Ordered e
  Real : Ordered F64
  Ids : Ordered (Id n)

||| How `build` keeps one value of several at one index: commutative and
||| associative by the primitive's meaning.
public export
data Merge : Elem -> Type where
  Once : Merge Present
  Least : Ordered e -> Merge e
  Greatest : Ordered e -> Merge e
  Sum : Integral e -> Merge e
  BitOr : Integral e -> Merge e
  BitAnd : Integral e -> Merge e
  BitXor : Integral e -> Merge e

||| An einsum's product.
public export
data Times : Elem -> Type where
  Both : Times Present
  MulInt : Integral e -> Times e
  MulReal : Times F64
  Overlap : (El e -> El e -> El e) -> Times e

||| An einsum's sum, run in the library's loop order.
public export
data Plus : Elem -> Type where
  Either : Plus Present
  AddInt : Integral e -> Plus e
  AddReal : Plus F64
  Reduce : (identity : El e) -> (El e -> El e -> El e) -> Plus e

public export
record Semiring (e : Elem) where
  constructor MkSemiring
  plus : Plus e
  times : Times e

module Sparse.Core
import Array.Shape
import Linear.Notation
import Sparse.Element
import Sparse.Format
import Sparse.Reference
%default total

export data SArray : (0 s : Shape) -> (0 f : Format (length s)) -> (0 e : Elem) -> Type
export data LSArray : (0 s : Shape) -> (0 f : Format (length s)) -> (0 e : Elem) -> Type
export data LBag : (0 s : Shape) -> (0 e : Elem) -> Type

||| One side of a pointwise combination: nothing, the value itself, or a
||| function of the index and the value.
public export
data Side : Shape -> Elem -> Elem -> Type where
  Drop : Side s a c
  Same : Side s c c
  With : (Index s -> El a -> El c) -> Side s a c

public export
data Both : Shape -> Elem -> Elem -> Elem -> Type where
  Neither : Both s a b c
  Combine : (Index s -> El a -> El b -> El c) -> Both s a b c

public export
record Regions (s : Shape) (a, b, c : Elem) where
  constructor MkRegions
  overlap : Both s a b c
  left : Side s a c
  right : Side s b c

||| An operand's map: its rank and its dimensions as variables.
public export
Map : Nat -> Type
Map v = (r ** Vect r (Fin v))

||| The shape of a map's operand: its variables' extents, in its order.
public export
dims : Vect v Nat -> Vect r (Fin v) -> Shape

||| The proofs that make an einsum one kernel the sparsifier schedules.
public export
data Einsum : (v : Nat) -> List (Map v) -> Vect o (Fin v) -> Type where
  MkEinsum : (0 apart : AllDistinct ms) -> (0 outApart : Distinct out) ->
             (0 met : Met ms out) -> Einsum v ms out

||| The operands, one per map, each in its own format. Its spine is fixed
||| by its index, so it is inline (D58) and never a cell.
public export
data Operands : Vect v Nat -> Elem -> List (Map v) -> Type where
  Nil : Operands sizes e []
  (::) : {f : Format (length (dims sizes m))} -> SArray (dims sizes m) f e ->
         Operands sizes e ms -> Operands sizes e ((r ** m) :: ms)

export extents : SArray s f e -> Extents s
export stored : SArray s f e -> Nat

export withBag : Extents s -> (1 _ : (1 _ : LBag s e) -> !* b) -> !* b
export add : (1 _ : LBag s e) -> Index s -> El e -> LBag s e
export build : {f : Format (length s)} -> Merge e -> (1 _ : LBag s e) -> !* (SArray s f e)

export thaw : SArray s f e -> (1 _ : (1 _ : LSArray s f e) -> !* b) -> !* b
export mapInPlace : (Index s -> El e -> El e) -> (1 _ : LSArray s f e) -> LSArray s f e
export freeze : (1 _ : LSArray s f e) -> !* (SArray s f e)

export map : (Index s -> El a -> El b) -> SArray s f a -> SArray s f b
export keep : (Index s -> El e -> Bool) -> SArray s f e -> SArray s f e
export merge : {g : Format (length s)} -> Regions s a b c ->
               SArray s f a -> SArray s h b -> SArray s g c
export einsum : {0 sizes : Vect v Nat} -> {ms : List (Map v)} -> {out : Vect o (Fin v)} ->
                {g : Format (length (dims sizes out))} ->
                Semiring e -> Einsum v ms out -> Operands sizes e ms ->
                SArray (dims sizes out) g e
export convert : {g : Format (length s)} -> SArray s f e -> SArray s g e
export foreach : SArray s f e -> (1 _ : t) -> ((1 _ : t) -> Index s -> El e -> t) -> t

export densify : {e : Elem} -> (0 _ : Numeric e) -> SArray s f e -> Array s (El e)
export sparsify : {f : Format (length s)} -> (0 _ : Numeric e) -> Array s (El e) -> SArray s f e
```

The implicits the bodies read at quantity many (`{f}`, `{g}`, `{ms}`,
`{out}`) are compile-time terms at every hooked call, which the
translation reads from the call's types; a format or map no analysis
closes is `unsupported (polymorphism)` at its site, as any family is.
Formats in common use are definitions over `MkFormat`: `CSR = MkFormat 1
(Last (Keeps Compressed)) [0, 0]`, `CSC` the same with `[1, 0]`, `DCSR`,
`COO k = MkFormat 0 (Last (Run Compressed AoS k)) identity`, `CSF`.

## 9. The MLIR mapping

| Idris | MLIR |
| --- | --- |
| `s = [<d0, ..., dk]` | `tensor<d0 x ... x dk x E, #enc>`; static where the term is a constant, `?` otherwise |
| `MkFormat d gs p` | `#sparse_tensor.encoding<{map = (dims) -> (levels)}>` |
| `d` | `d` leading `dense` levels |
| `Keeps Compressed` / `Keeps LooseCompressed` | `compressed` / `loose_compressed` |
| `Run h AoS k` | `h(nonunique)`, `k` × `singleton(nonunique)`, `singleton` |
| `Run h SoA k` | the same with `soa` on each singleton |
| `p : Perm r` | `dimToLvl` as a permutation map; `lvlToDim` inferred |
| coordinate width | derived: 8, 16, 32 or 64 when every extent is static, else 0 |
| position width | 0 |
| `Present` | `i8`, `explicitVal = 1 : i8`, `implicitVal = 0 : i8` |
| `I8` ... `I64`, `U8` ... `U64` | `i8` ... `i64` |
| `F64` | `f64` |
| `Id n` | `i32` when `n` is a constant below 2^31, else `i64` |
| `SArray s f e` | `tensor<..., #enc>` |
| `LSArray s f e` | `!idr.lin<tensor<..., #enc>>`, the `in_place` grade |
| `LBag s e` | `!idr.lin<tensor<..., #bag>>`, `#bag = compressed(nonunique, nonordered)` then `singleton(nonunique, nonordered)` per further level |
| `Merge` | the `arith` op in `build`'s merging `foreach`: `minsi`/`minui`/`minimumf`, `maxsi`/`maxui`/`maximumf`, `addi`, `ori`, `andi`, `xori`; `Once`: `convert` alone |
| `Times` | `andi`, `muli`, `mulf`, or `sparse_tensor.binary` overlap with `left={}`, `right={}` |
| `Plus` | `ori`, `addi`, `addf`, or `sparse_tensor.reduce` with its identity |
| `Regions` | `sparse_tensor.binary` `overlap`, `left`, `right`; `Same` is `identity`, `Drop` and `Neither` are `{}` |
| operations | §3.1's table |
| pipeline | `sparse-reinterpret-map`, `sparsification`, codegen, inside `sparsification-and-bufferization` with One-Shot; `enable-runtime-library=false`; no vectorization or parallelization of float sums; `finalize-memref-to-llvm{use-generic-functions}` where the caller owns memory |

## 10. Questions for the owner, one at a time

Each waits for the one before it.

1. **Which formats does the library promise?** *A* (recommended): §2.2's,
   dense levels only before the first sparse one, any permutation, no
   batch, `n:m`, block maps or slices. Buys: every format's pattern is any
   set, so `convert` never changes a meaning and the bodies stay a sorted
   list; the e-graph and 0015's fixed plans need nothing more. Costs: BSR,
   ELL and 2:4 sparsity are unwritable until a later change adds blocks
   to the meaning. *B*: every level type MLIR has. Buys: numeric
   programs' block formats. Costs: the meaning gains forced explicit
   zeros, the bodies a format-dependent closure, and `convert` stops being
   the identity on entries. Amends 0009 §9 either way.
2. **Elements from a closed universe, or 0009 D31's interface?** *A*
   (recommended): `Elem` with `Present` and `Id n` (§2.3). Buys: a
   non-primary element is unwritable, sets are one member, ids are typed.
   Costs: element functions are written over `El e`, and D31 is amended.
   *B*: `SparseElement a`. Buys: plain Idris types at the surface. Costs:
   an open interface cannot keep its promise, and sets need a second type.
3. **Is 0015 re-based on this library?** D85 puts the e-graph on MLIR's
   sparse pipeline; 0015 keeps an interpreter with lazy tries, hash levels
   and galloping for plans that do not fit (§5). *A*: 0015's fixed-plan
   layer and its layers 2 and 3 become this library and the engine;
   its interpreter and the bumbledb gates stay 0015's, after self. *B*:
   0015 whole as written, a second route beside the engine. *C*: 0015's
   interpreter dropped. Scope between proposals is the owner's; no
   recommendation beyond noting that *B* keeps two join engines.
4. **D87's route** (`one-engine.md` §10, the same question): G as recorded
   (recommended, §6), or S with its amendments. This decides only whether
   the generating set is also an interface.
5. **Galloping** (*conjecture*, research first): an upstream patch giving
   the sparsifier's compressed-level iterator a galloping `forwardIf`
   would make §5's joins worst-case optimal in the sense generic join is;
   or the engine writes its plans with the explicit iteration ops once
   they are not experimental. To be measured on `speed.md`'s workloads
   before it is put.
