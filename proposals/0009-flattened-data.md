# 0009: compiler-chosen flattened layouts of algebraic data

**Status:** proposed 2026-10-09; reconciled with 0003 on 2026-10-12 and
with 0004's pipeline cutover on 2026-10-14, and decided the same day.
Nothing here is built. The tree today (*measured*, 0002 and 0004 §0):
the cutover 0002 designed is committed and builds on arm64 macOS, where
`make test` was 415/415 at 7a27fd34, before the opt-in SCC pipeline,
and again at 552d682a with it off by default; both runs took the
Simplify rounds, and 0004's cutover deletes the rounds and that
pipeline together. x86_64 Linux is NotRun. `make self` has never
finished; 0004's cutover is what it waits on.

It is one of the three consumers of 0003's array style, with 0008's
tables and 0007's interpreter: the layouts it chooses are how their
columns are stored. In the queue it follows 0008, and it starts after
`make self` and sharding's first stages. Columns are 0003's
representation of an array of records, one tensor per field (0003 §4.5);
this proposal decides what 0003 §4.5 leaves to it (an array of sums),
adds the packed layout, and makes the measured choice for collections
that are not arrays. It builds on 0004's data types that carry their
constructors (0004 §4.1, D29), which 0004's lanes L5 and L1 land
together (0004 §10).

**Sources.** `sources/notes/flattened-data/`, which read the stored
papers and code and cite them by section and line:
- `packed-trees.md`: Gibbon (Gibbon-17), LoCal, Parallel LoCal, the
  mostly serialized collector (GC-24), GHC's compact regions (CNF),
  Marmoset and Allais's serialised data in Idris 2, with `code/gibbon`;
- `columnar.md`: Arrow, Dremel and Parquet, Zig's `MultiArrayList`,
  StructArrays, `vector`, hash-consing; what idris-mlir should take (§8)
  and avoid (§9);
- `flattening.md`: NESL, DPH, Futhark, Elsman.

`columnar.md` §0 cites the layout code as it was before the cutover
(`Layout/*.cppm`); the same code is now `foreign/idr/lib/IR/Layout/*.cpp`,
cited below.

**Claims** are marked: *read* (a stored source or a code path),
*measured*, *recalled*, *conjecture*, or *decision*.

## What it changes

Today one Idris type has one physical layout, chosen once per
declaration from the type's shape (*read*):
- `!idr.box<@T>` for a type that contains itself, or a record or closure
  sum whose cells would count more object slots than a header can: a
  cell with a reference count, object slots first, reused in place when
  unique (`foreign/idr/include/idr/IR/IdrTypes.td:30-38`;
  `IdrOps.td:117-160`). A header counts at most 255 object slots and
  65,536 tags (`runtime/idris_rt.h:106-107`), and Fit boxes records to fit
  it (`lib/IR/Layout/Fit.cpp:1-9`). After 0004's cutover boxing is the
  value's type alone, `!idr.box` around the identified type, and no
  longer a flag of the declaration as well (0004 D29).
- `!idr.data<@T>` for any other type: an unboxed sum, a tag of 8, 16 or
  32 bits, then slots shared between constructors, each component taking
  the first free slot of its type and countedness, spread over whatever
  holds the value (`IdrTypes.td:25-29`; `lib/IR/Layout/Components.cpp:33-77`;
  `include/idr/IR/Layout.h:106-126`). A counted slot holds null in every
  constructor that does not use it, "so that the references of a sum are
  exactly its counted slots" (`Layout.h:106-109`). The layout is computed
  from the declaration, which `Components::sum` finds today by the
  type's symbol in a table of the module's declarations it builds
  (`Components.cpp:23, 30-35`); after 0004's cutover it reads the
  constructors from the type, which carries them, and that table goes
  with the nominal form, as the module-scanning lookups do (0004 §6).
- An array is an array of structs: each element laid out as a cell of one
  field, less the header (`lib/IR/Layout/Layouts.cpp:157-178`;
  `runtime/idris_rt.h:152-165`). Nothing in the compiler is a structure
  of arrays.
- Closures and lazy values become closure sums and memo sums
  (defunctionalization; `IdrOps.td:122-135`). After 0004's cutover every
  label set is a finite set of functions and becomes a sum, with no
  refusal (0004 §2.4).

This proposal adds two physical layouts for the same Idris types, chosen
by the compiler from facts the types and analyses already provide:

1. **Packed:** a tree serialized in preorder in one buffer. Children follow
   their parent and every subtree is a contiguous slice. Traversals walk the
   buffer with a cursor instead of chasing pointers. This is Gibbon and LoCal
   (*read* through `packed-trees.md` §1: `papers/vollmer-2017-packed-tree-transforms`,
   `papers/vollmer-2019-local`, `papers/koparkar-2021-efficient-tree-traversals`,
   `code/gibbon`). The tree of Gibbon-17's Fig. 1 takes 96 bytes as
   structs and 29 packed.
2. **Columnar:** a collection of values held as one array per component,
   each a 0003 tensor.
   - a product is one tensor per field;
   - a sum is a tag tensor and one tensor per slot of its `SumLayout`, or
     a tensor of boxes (§"Sums in columns");
   - lists, `Vect` and ragged children are 0003's `Ragged`, a values array
     and an offset per row (0003 §3.7);
   - a recursive value is preorder node arrays, Co-dfns style: an array
     of the node sum in columns plus a `subtree_size` column;
   - erased indices and proofs vanish: what Idris erased is no value of
     the module, so it has no column (AGENTS.md; the frontend emits no
     field for it, which supersedes `columnar.md` §8.4's `!idr.erased`,
     a type the cutover deleted); a `Fin n` that is a coordinate of an
     array is an `index` at its access, unguarded, and any other `Fin` a
     natural narrowed where proved (0003 D4).

   Columns are not a type of ours. An array of records is one ranked
   tensor per field by one-to-N type conversion, which bufferizes to one
   memref per field (0003 §4.5).

   *Read* through `columnar.md`: `docs/arrow`, `papers/melnik-2010-dremel`,
   `docs/parquet-format`, `code/zig` (`MultiArrayList`), `code/structarrays`,
   `code/vector`. The Co-dfns node arrays are *read* in
   `code/co-dfns/cmp/TT.apl:1-6`, whose passes take the tree as parent,
   depth, type and kind columns, and in
   `papers/hsu-2019-data-parallel-compiler`.

## The representation, decided by data

**Decision:** one Idris type, several physical layouts: cell, packed or
columnar. Each layout is a type over the one declaration:
- **cell** is today's `!idr.data` or `!idr.box`;
- **packed** is `!idr.packed<T>`, whose parameter `T` is the data type.
  After 0004's cutover `T` carries its constructors as an identified type
  with a body set once, so a pass reads the constructors from the type
  and never from a module lookup, and `!idr.packed` wraps it as
  `!idr.box` does (0004 D29);
- **columns** are 0003's tensors, one per component. `!idr.columns<@T>`
  is not added: a second representation of what a structure of tensors
  already is.

A layout parameter inside the identified type (say `!idr.data<"T",
packed>`) is not taken. An identified type's identity is its name, so
each layout would be a second identified type carrying a copy of the
body: one declaration held twice. A wrapper keeps one declaration and
states the layout as the type of the value, as `tensor<…x T>` does for
columns. The layout is never a discardable attribute, so no pass can
silently lose it; LoCal's located types are the precedent, checked
between passes (*read* through `packed-trees.md` §9.1: LoCal §3.2, §4;
`code/gibbon/gibbon-compiler/src/Gibbon/Compiler.hs`). `!idr.packed` is
ours because no upstream dialect has a type for a preorder-serialized
algebraic value: no upstream dialect defines a sum, union or variant
type at all (*read*: a search of the type definitions in the pinned
`M/include/mlir/**/*.td`, 2026-10-14), so none can describe a serialized
one.

### Sums in columns

0003 §4.5 leaves an array of sums to this proposal, in its terms: a tag
tensor and one tensor per field slot, or a tensor of boxes. *Decision:*
the cell layout decides, with no measurement.
- An unboxed sum's columns are its `SumLayout`: the tag tensor and one
  tensor per slot (`Layout.h:110-126`). The table that gives the
  array-of-structs element gives the columns too, and the width is the
  maximum over constructors of each slot type's use, not their sum. It is
  Arrow's sparse union over typed shared slots (*read* through
  `columnar.md` §8.1: `docs/arrow/docs/source/format/Columnar.rst:933-945`),
  and Zig's `MultiArrayList` splits a tagged union the same way, into its
  tags and a bare union as wide as its largest variant (`columnar.md` §3:
  `multi_array_list.zig:9-62`).
- A boxed type's column is a tensor of boxes, a counted element with one
  path (0003 D17).

The one-to-N conversion of 0003 §4.5 takes `SumLayout::types()`
(`Layout.h:117-124`) as its N, so records and sums go through one
converter. The counted-slot invariant carries over: a counted column is
null wherever its constructor does not use it, so releasing an array's
references scans the counted columns with no tag dispatch (`columnar.md`
§8.2). The tag column keeps the cell's tag type: a one-bit tag tensor
would be a second layout of the tag, and `memref<?xi1>` takes a byte per
element anyway, since LLVM stores an `i1` in a whole byte (*read*:
`getTypeStoreSize` rounds a type's bits up to a multiple of 8,
`L/include/llvm/IR/DataLayout.h:579-597`). Arrow's dense union is not
taken for arrays: its per-constructor children have data-dependent
lengths and an offsets array, so a map over it is a gather, not an
elementwise `linalg.generic` (`Columnar.rst:874-889`).

## When each layout is legal and chosen

- **Packed** needs a tree with no sharing. The exclusive grade
  (`!idr.excl<T>`, the spelling of `!idr.q<many, excl, T>`,
  `IdrTypes.td:116-143`) proves no sharing. The acyclic heap guarantees
  trees, never cyclic graphs: a new object points only at objects older
  than it, and the one cell written after it exists, an array, is
  refused a type that reaches it again (*read*:
  `lib/IR/Verify/Knots.cpp:3-10`, `unsupported (cycle)` at `:100`); a
  pure strict language builds DAGs and never cycles (*read* through
  `packed-trees.md` §2: LoCal §6). A value whose grade is not exclusive
  keeps the cell layout. This deletes the special cases packed systems
  need for sharing: in LoCal-era Gibbon,
  an indirection constructor added to every datatype (*read* through
  `packed-trees.md` §2: LoCal §5;
  `code/gibbon/gibbon-compiler/src/Gibbon/Passes/RemoveCopies.hs`). Here
  sharing selects the other layout.
- **Random access selects cells** (*decision*). A consumer that reaches a
  subtree out of preorder keeps the value in cells; the packed layout has
  no offsets and no indirections. Gibbon's offsets change the
  representation for every function using the type, and its
  implementation keeps the old case clauses beside the new (*read*
  through `packed-trees.md` §4, §10: LoCal §4.2; `Passes/AddRAN.hs`).
  A dummy traversal instead would change complexity silently
  (`rightmost` 150 times slower packed, Gibbon-17 §6.1), and AGENTS.md's
  rule against silent miscompilation covers cost.
- **The compiler packs** a recursive value when it is built once, in
  preorder, and traversed whole by consumers it can see. After 0004's
  cutover it sees every consumer: the world is closed by a verified
  invariant, and every closure is a sum whose applies are direct calls
  (0004 §2.2, §2.7). That is the closed world Gibbon's representation
  selection also needs (*read* through `packed-trees.md` §2: ParLoCal §4).
  The choice reads idr-rc's exclusive grades, and they exist only after
  counting is placed: idr-rc writes the owned grades, places counting
  per function, then solves exclusivity and writes `!idr.excl<T>`, then
  commits (*read*: `lib/Transforms/Ownership/Rc.cpp:60-101`), because
  the solve "reads the dups placement made, so it runs after placement"
  (`lib/Analysis/Ownership/Exclusivity.cpp:22-24`). *Decision:* the
  packed choice is a module step between the exclusive grades and the commit,
  reading the grades as a frozen fact of that stage (0004 §4.11, §9).
  It needs no change to placement: a value is exclusive only if no
  `idr.dup` reaches any cell of its graph (any dup makes it shared,
  `Exclusivity.cpp:11-20`), so placement left an exclusive tree only
  moves and drops, and the commit is where the tree's per-cell drops
  become the buffer's one decrement, at the use of the traversal's end
  cursor (F4 proves it). This supersedes the earlier "before counting is
  placed", which the order of idr-rc rules out. It is one of the layouts
  0004 decides whole-program before lowering (0004 §1, §4.12); each
  function's types then convert per function.
- **Columns** hold a collection of values of one type that is traversed
  field by field (a map over one field, a filter, an aggregate), and every
  array of records or sums the array core touches (0003). An array of
  records or sums becomes structure-of-arrays by representation, with no
  programmer action and no measurement gate. *Decision:* the choice of
  columns for a collection that is not an array (F3) is a whole-program
  step right before 0003's arrays stage, which runs after dead-value
  removal and before the memory passes (0003 D26). Reason: a column is a
  tensor, which the arrays stage's structuring, fusion and One-Shot
  Bufferize must see, while packing is a cell layout that idr-rc's
  commit must see; each choice sits before the passes that read it.
- **The measurement rule.** The automatic choice for anything that is not
  an array covers a case only once a fixture proves it at least 1.3×
  over the cell layout, on the benchmark set below. The case is then
  part of the compiler's rule, written in the compiler, never an option
  (0004 D2). A case not yet proved stays in cells unless the program
  writes `Packed t` (next section).

## The opt-in first

**Decision:** stage one is explicit, for packing. A trusted library gives
`Packed t`, derived from `t`'s definition by the compiler: from the Idris
declaration in the frontend and from the data type's body in MLIR, by the
same code the automatic choice uses later. The opt-in for columns is
0003's array: an `Array s t` of records or sums is already columns
(§"Sums in columns"), so the earlier `Columns t` view would be a second
spelling of it and is not added.
- **Construction** goes through a linear builder: a `Packed t` is written
  once, in order. The builder writes one contiguous buffer and grows it by
  doubling through the runtime's allocator. Every reference inside is a
  relative offset and the builder is linear, so moving the buffer
  invalidates nothing (*decision*; *read* through `packed-trees.md` §4,
  §9.5: Allais's relative offsets copy a subtree with one slice copy;
  LoCal §3.4). Chunk lists linked by end-of-chunk redirection tags
  (`packed-trees.md` §8) are not taken: they put a pointer-carrying tag in
  the format, the indirection the rest of this design keeps out.
- **Reading** goes through cursors whose types track the position in the
  preorder. This is LoCal's location calculus reduced to what Idris's
  quantities already express (a cursor is linear, a reader is total).
  Allais does it in plain Idris 2 as a library, with erased trees as
  indices (*read* through `packed-trees.md` §3, §9.8).
- **No grade is needed.** The builder writes the tree once, in order, so
  it has no sharing inside by construction, and a `Packed t` is one
  buffer from the frontend on. Sharing the buffer itself is a counted
  reference to one cell, which the format allows; the exclusive grade
  is what the automatic choice needs, because it starts from cells.

This is not user metaprogramming. Elaborator reflection in user code is
refused by the frontend's profile, and it is the wrong layer: the layout is
the compiler's decision, made from facts only the compiler has.

## How operations compile

- **On packed data:** a traversal compiles to a cursor walk; end
  witnesses are SSA results, so no pass reorders bindings to find them
  (*conjecture*, `packed-trees.md` §9.2). Folds stream through the buffer
  once. The order of fields in a constructor follows the traversals that
  read it (Gibbon's layout inference, *read* through `packed-trees.md`
  §3), chosen by a greedy walk over the field-access graph, Marmoset's
  greedy variant (*decision*; *read* through `packed-trees.md` §4:
  Marmoset `design.tex` §3.2-3.7, 1.14 to 54 times over Gibbon). Its ILP
  is not taken: it needs a CPLEX solver through generated Python
  (`design.tex` §4), and its costs are "best intuition".
- **Parallel traversal** comes from the per-value choice, never from
  offsets inside a buffer (*decision*): cells above a task cutoff, packed
  subtrees below it. Parallel LoCal's own finding is that granularity
  decides representation: serialising only the bottom two levels of a
  binary tree removes 75% of pointers (*read* through `packed-trees.md`
  §6: ParLoCal §4.1). This supersedes the earlier "splits at subtree
  boundaries recorded at build time", which needs the random-access
  offsets refused above.
- **On columnar data:**
  - per-constructor work is a masked map over the tag column;
  - a fold over a tree is a segmented reduction in reverse preorder;
  - binders are segmented scans;
  - a rewrite is gather, scatter and compaction;
  - all of it lowers to `linalg` through the array core and fuses with
    neighbouring array code (0003); gathers, scatters and filters are
    where fusion stops (0003 §4.4).

  Segmented reductions follow Futhark's and NESL's (*read* through
  `flattening.md` §1, §4: `papers/larsen-2017-segmented-reductions`,
  `papers/blelloch-1995-nesl`, `papers/elsman-2019-flattening-by-expansion`).
- **What is not done: full flattening of everything,** Data Parallel Haskell's
  vectorisation. It flattened all nested parallelism and paid in index
  arithmetic and space (*read* through `flattening.md` §4-5:
  `papers/chakravarty-2007-dph-status`,
  `papers/keller-2012-vectorisation-avoidance`,
  `papers/lippmeier-2012-work-efficient-vectorisation`). The layouts here are
  chosen per value, where the access pattern pays for them.

## Reference counting and messages

- **One count per packed buffer.** A packed buffer is one counted cell,
  freed exactly when its last reference dies. Its internal references
  are offsets, not pointers, so there is nothing to walk. This is how
  Gibbon's work on mostly serialized heaps avoids per-node work, and how
  a compact region is one object to GHC's collector (*read* through
  `packed-trees.md` §8, §9.7: GC-24, CNF §4.2). Reuse in place applies to
  the whole buffer when idr-rc proves it unique.
- **A column set is N array cells** (*decision*, superseding "a set of
  columns is one counted cell"). An array of records or sums is N tensors,
  which One-Shot Bufferize allocates as N memrefs through the runtime's
  allocator (0003 §4.5, §8), each an array cell with its own count. A
  word column has nothing to walk when freed; a counted column is walked
  as any array of boxes is (0003 D17). In-place reuse of columns is
  One-Shot's decision (0003 D18), not idr-rc's. One allocation for all N
  columns, as Zig's `MultiArrayList` makes (*read* through `columnar.md`
  §3: `multi_array_list.zig:20-24, 166-201`), would need a bufferization
  model of ours beside upstream's, which 0003 rules out.
- **Packed and columnar data are the message format between shards**
  (0005). A value at the exclusive grade crosses as a move and its region
  goes with it (0005, "Lessons from Swift's concurrency model"); any other
  packed or columnar value crosses by copying its buffers, with no detach
  walk, like GHC's compact regions (*read* through `packed-trees.md` §8:
  `papers/yang-2015-compact-normal-forms`). The send check is unchanged: a
  region holds no mutable cell.
- **The compiler's own process boundary carries columns, never packed
  buffers** (*decision*). 0006 runs the compiler's Idris half as
  processes and passes summaries between them as files (0006 §5.4), so
  it is the one place a layout of this proposal could be read from a
  file. A summary is a
  set of columnar relations (0006 §3.1), and its reader checks every id
  column once against the extent of the table it indexes, which turns
  the file's words into typed ids: the guarded entry 0003 D4 gives an
  extent, so every read after it is unguarded (0008 D1). A packed buffer
  would need its whole tree walked to check its offsets, the trusted
  header or unchecked reader D11 keeps out, so none crosses as a file.

## Consumers

- **The term arena and the interpreter's tables (proposal 0007),** shared
  by the frontend, the type checker and static normalization. Hash-consed
  terms share subterms, so the arena is a DAG and is never packed: its
  tables are columns, arrays of records keyed by id (0007 §3), and 0007
  builds them.
- **The array core (proposal 0003):** records, sums and trees enter array
  programs through columns.
- **bumbledb's port** (`../bumbledb/proposals/0003-idris-port.md`): its
  images are columns already.
- **The frontend's own passes,** once self-hosted: 0008's syntax nodes and
  full Core in preorder are the columnar form of a tree (0008 §3).

## Rules it keeps

- **Facts in types.** The layout is the value's type; grades and
  multiplicities are unchanged.
- **One declaration per data type.** Every layout is a type over it; none
  copies its constructors (0004's data types that carry their
  declaration).
- **The acyclic heap,** which is what makes packing always possible.
- **Whole-program compilation,** which is what lets the compiler see every
  consumer.
- **Raw, untagged heap references.** Gibbon packs a chunk-footer offset
  into the high bits of its pointers and caps chunks at 65 KB for it
  (*read* through `packed-trees.md` §10: GC-24 §4); a packed buffer here is
  one contiguous cell, and no pointer carries a tag.
- **No way in from outside.** Packed data is only built by the program or
  received from its own shards; nothing loads it from a file, so no
  trusted header or unchecked reader exists (`packed-trees.md` §10 names
  Allais's and CNF's). The compiler's own files between its processes
  carry columns, read with every id checked (§"Reference counting and
  messages").
- **No oracle; behaviour is the specification.** A layout change is
  invisible to a program's output, and the corpus proves it.
- **Both targets.** No layout is target-specific.

## Staged plan, each stage with its proof

| Stage | Needs | Content | Proof |
| --- | --- | --- | --- |
| F1 | 0004's identified data types | `Packed t` in a trusted library: the linear builder and cursors; the compiler derives it from the data type's declaration | fixtures: a preorder fold over a packed tree, build and traverse; outputs equal to the cell version |
| F2 | F1; 0003's one-to-N conversion of record elements (0003 §4.5) | `!idr.packed<T>` in the `idr` dialect, verified after every pass; idr-rc's commit and idr-lower handle packed buffers; arrays of sums through the `SumLayout` one-to-N conversion | verifier checks; `idr-expect` properties: one count per packed buffer, one array cell per column |
| F3 | F2 | columns for collections other than arrays (lists and trees of records traversed field by field), as a conversion to 0003's arrays right before its arrays stage | benchmarks: nbody-style records ≥ 1.3× over cells |
| F4 | F2 | automatic packing for exclusive, build-once, traverse-whole trees, chosen between idr-rc's exclusive grades and its commit | Gibbon's benchmark programs (tree add1, sum, repmax) ≥ 1.3× over cells on both targets, and within 1.5× of Gibbon's published numbers on x86_64 Linux; a fixture per drop the commit folds into the buffer's one decrement |
| F5 | F2; 0005's P4 | packed and columnar values as shard messages | 0005's message benchmarks: copy cost per byte against the detach walk |

F4's second bar is on x86_64 Linux only (*decision*): every Gibbon result
was measured on x86 Xeon or Threadripper machines, and none on ARM or
macOS (*read* through `packed-trees.md` §11).

## Rejected alternatives

- **User metaprogramming that derives layouts** (elaborator reflection): the
  wrong layer, and refused in user code.
- **Always columnar, or always packed:** it pays index arithmetic where
  pointers were cheaper. The choice is per value.
- **Full flattening, as DPH did:** see above.
- **Packing shared data with indirections:** the exclusive grade selects
  cells instead, so the special case cannot be expressed.
- **Offsets or dummy traversals for random access in a packed buffer:** a
  second layout of the same type, or a silent change of complexity;
  random access selects cells.
- **A layout parameter inside the identified data type:** each layout
  would be a second declaration.
- **`!idr.packed<@T>` naming a symbol:** the nominal form 0004 replaces
  with types that carry their declaration.
- **Arrow's dense union for arrays of sums:** a map over it is a gather.
- **One allocation for all of an array's columns:** a bufferization model
  of ours beside One-Shot's.
- **A `Columns t` library view:** a second spelling of 0003's arrays.
- **Chunked packed buffers with redirection tags:** an indirection in the
  format.
- **Marmoset's ILP for field order:** a solver outside the toolchain for a
  choice the greedy walk makes.
- **Choosing packing before counting is placed:** the exclusive grades
  it reads exist only after placement (§"When each layout is legal and
  chosen").
- **Packed buffers as the files between the compiler's processes:**
  their offsets would need a checking walk; summaries cross as columns
  with checked ids.
- **An option that turns an automatic choice on:** a proved case is the
  compiler's rule, and an unproved one stays in cells (0004 D2).

## Decisions

- D1. Each layout is a type over the one declaration: cell as today,
  packed as `!idr.packed<T>`, a wrapper around the identified type as
  `!idr.box` is after 0004 D29, columns as 0003's tensors; never an
  attribute, never a parameter inside the identified type.
- D2. Packed only at the exclusive grade, without offsets: sharing and
  random access select cells. Columns for collections traversed field by
  field.
- D3. The opt-in `Packed t` comes first; automatic choices for what is not
  an array land only per measured case (≥ 1.3×); arrays of records and
  sums are columns by representation, with no gate.
- D4 (restated 2026-10-14). One count per packed buffer; a column set is
  N array cells, one per tensor, as 0003's bufferization allocates them.
- D5. Packed and columnar values are the shard message format; an
  exclusive one moves.
- D6. An array of an unboxed sum is its `SumLayout` in columns, the tag
  tensor and one tensor per slot; an array of a boxed type is a tensor of
  boxes.
- D7. A packed buffer is contiguous, grown by doubling, with relative
  offsets only; no chunks and no tagged pointers.
- D8. Parallel traversal of packed data comes from cells above packed
  subtrees, never from offsets inside a buffer.
- D9. Field order in a packed constructor follows the traversals that read
  it, by a greedy walk over the access graph.
- D10 (restated 2026-10-14). The packed choice reads idr-rc's exclusive
  grades and is made after they are written and before the commit, with
  the other layouts 0004 decides before lowering; placement is
  unchanged, and the commit folds the tree's drops into one.
- D11. Packed data is built only by the program; nothing loads it from
  outside. The compiler's own files between its processes carry
  columns, whose ids the reader checks once against their tables.
- D12. Columns for a collection that is not an array are chosen right
  before 0003's arrays stage (0003 D26), so its passes see them as
  tensors.
- D13. A proved automatic case is part of the compiler's rule; an
  unproved one stays in cells unless the program writes `Packed t`.
  There is no option.

There is no open question for the owner.
