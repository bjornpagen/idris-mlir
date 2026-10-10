# 0006: compiler-chosen flattened layouts of algebraic data

**Status:** proposed (2026-10-09). Nothing here is built.

**Sources.** Under `sources/`, topic "Flattened data: packed, columnar and
nested layouts". The reading notes are in `sources/notes/flattened-data/`.

**Claims** are marked: *read* (a stored source or a code path), *measured*,
*conjecture*, or *decision*.

## What it changes

Today one Idris type has one physical layout, and the compiler picks it from
the type's shape (foreign/idr/include/idr/IdrOps.td, `idr.data`; *read*):
- a type that contains itself is a boxed cell (`!idr.box`), with reference
  counts, object slots first, and in-place reuse when it is unique;
- any other type is an unboxed sum (`!idr.data`), spread over whatever holds
  it;
- a record that would push its cell past 255 counted slots is boxed
  (foreign/idr/lib/Layout, the record-boxing merge);
- closures and lazy values become closure sums and memo sums
  (Defunctionalize).

This proposal adds two more physical layouts for the same Idris types,
chosen by the compiler from facts the types and analyses already provide:

1. **Packed:** a tree serialized in preorder in one buffer. Children follow
   their parent and every subtree is a contiguous slice. Traversals walk the
   buffer with a cursor instead of chasing pointers. This is Gibbon and LoCal
   (*read*: `papers/vollmer-2017-packed-tree-transforms`,
   `papers/vollmer-2019-local`, `papers/koparkar-2021-efficient-tree-traversals`,
   `code/gibbon`).
2. **Columnar:** a collection of values held as one array per field.
   - products are one column per field;
   - sums are a tag column plus per-constructor field columns (Arrow's dense
     union);
   - lists, `Vect` and ragged children are a values column plus an offsets
     column;
   - recursive values are preorder node arrays with parent and child-offset
     columns, Co-dfns style;
   - erased indices and proofs vanish, and `Fin n` is an integer index.

   *Read*: `docs/arrow`, `papers/melnik-2010-dremel`, `docs/parquet-format`,
   `code/zig` (`MultiArrayList`), `code/structarrays`, `code/vector`,
   `papers/hsu-2019-data-parallel-compiler`.

## The representation, decided by data

**Decision:** one Idris type, several physical layouts: cell, packed or
columnar. The layout is a property of a value's type at the MLIR level: a
layout parameter on `!idr.box`/`!idr.data`, or a new `!idr.packed<@T>` and
`!idr.columns<@T>`. It is never a discardable attribute, so no pass can
silently lose it.

When each layout is legal and chosen:
- **Packed** needs a tree with no sharing. The exclusive ownership grade
  (`!idr.q<…, excl, T>`) proves no sharing. The acyclic heap guarantees trees,
  never cyclic graphs (AGENTS.md). A value whose grade is not exclusive keeps
  the cell layout. This deletes the special cases packed systems need for
  sharing: in Gibbon, an indirection pointer per shared subtree, *read*
  `papers/vollmer-2019-local`. Here sharing simply selects the other layout.
- **The compiler packs** a recursive value when it is built once and
  traversed whole, in preorder, by consumers it can see: the whole-program
  analysis that already sees every consumer (defunctionalization, idr-rc). It
  keeps cells when a consumer needs random access to subtrees, or when the
  value is updated in place piecewise.
- **Columns** hold a collection of values of one type that is traversed
  field by field (a map over one field, a filter, an aggregate), and every
  array of records the array core touches (proposal 0004 — typed APL). An
  array of records becomes structure-of-arrays with no programmer action.
- **The measurement rule.** The automatic choice is on by default only for
  cases a fixture proves faster: at least 1.3× over the cell layout, on the
  benchmark set below. Every other case is opt-in (next section) until it is
  measured.

## The opt-in first

**Decision:** stage one is explicit. A trusted library gives
`Columns t` and `Packed t` views, derived from `t`'s definition by the
compiler; the derivation is the same code the automatic choice uses later.
- **Construction** goes through linear builders: a `Packed t` is written
  once, in order.
- **Reading** goes through cursors whose types track the position in the
  preorder. This is LoCal's location calculus reduced to what Idris's
  quantities already express (a cursor is linear, a reader is total).
- **Columns** support the array core's operations directly.

This is not user metaprogramming. Elaborator reflection in user code is
refused by the frontend's profile, and it is the wrong layer: the layout is
the compiler's decision, made from facts only the compiler has.

## How operations compile

- **On packed data:** a traversal compiles to a cursor walk. The order of
  fields in the buffer follows the traversal that reads them (Gibbon's
  layout inference; *read* `code/gibbon`). Folds stream through the buffer
  once. Parallel traversal splits at subtree boundaries recorded at build
  time (*read* `papers/koparkar-2021-efficient-tree-traversals`).
- **On columnar data:**
  - per-constructor work is a masked map over the tag column;
  - a fold over a tree is a segmented reduction in reverse preorder;
  - binders are segmented scans;
  - a rewrite is gather, scatter and compaction;
  - all of it lowers to `linalg` through the array core and fuses with
    neighbouring array code (proposal 0004).

  Segmented reductions follow Futhark's and NESL's (*read*
  `papers/larsen-2017-segmented-reductions`,
  `papers/blelloch-1995-nesl`, `papers/elsman-2019-flattening-by-expansion`).
- **What is not done: full flattening of everything,** Data Parallel Haskell's
  vectorisation. It flattened all nested parallelism and paid in index
  arithmetic and space (*read* `papers/chakravarty-2007-dph-status`,
  `papers/keller-2012-vectorisation-avoidance`,
  `papers/lippmeier-2012-work-efficient-vectorisation`). The layouts here are
  chosen per value, where the access pattern pays for them.

## Reference counting and messages

- **One count per region.** A packed buffer or a set of columns is one
  counted cell, freed exactly when its last reference dies. Its internal
  pointers do not exist, so there is nothing to walk. This is also how
  Gibbon's work on mostly-serialized heaps avoids per-node work (*read*
  `papers/koparkar-2024-mostly-serialized-gc`). Reuse in place applies to the
  whole region when it is unique.
- **Packed data is the message format between shards** (proposal 0005). A
  packed or columnar value crosses by copying its buffer, with no detach
  walk, like GHC's compact regions (*read*
  `papers/yang-2015-compact-normal-forms`). The send check is unchanged: a
  region holds no mutable cell.

## Consumers

- **The elaborator's terms (proposal 0007):** flat, hash-consed term arenas
  (*read* `papers/filliatre-2006-hash-consing`, `code/ocaml-hashcons`). That
  makes shifting, equality and occurs checks vector operations.
- **The array core (proposal 0004):** records and trees enter array programs
  through columns.
- **bumbledb's port** (`../bumbledb/proposals/0003-idris-port.md`): its
  images are columns already.
- **The frontend's own passes,** once self-hosted: Translate and Emit over
  columnar TT.

## Rules it keeps

- **Facts in types.** The layout is part of the type; grades and
  multiplicities are unchanged.
- **The acyclic heap,** which is what makes packing always possible.
- **Whole-program compilation,** which is what lets the compiler see every
  consumer.
- **No oracle; behaviour is the specification.** A layout change is
  invisible to a program's output, and the corpus proves it.
- **Both targets.** No layout is target-specific.

## Staged plan, each stage with its proof

| Stage | Content | Proof |
| --- | --- | --- |
| F1 | `Columns t` / `Packed t` views in a trusted library; the compiler derives them | fixtures: map/filter/fold over columns; preorder fold over a packed tree; outputs equal to the cell version |
| F2 | layout as a type parameter in the `idr` dialect; Layout and idr-rc handle packed and columnar regions | verifier checks; idr-expect properties for one count per region |
| F3 | automatic columns for arrays of records in the array core | benchmarks: nbody-style records ≥ 1.3× over cells |
| F4 | automatic packing for exclusive, build-once, traverse-whole trees | Gibbon's benchmark programs (tree add1, sum, repmax), ≥ 1.3× over cells and within 1.5× of Gibbon's published numbers on the same machine class |
| F5 | packed and columnar values as shard messages | 0005's message benchmarks: copy cost per byte against the detach walk |
| F6 | the elaborator on flat, hash-consed terms (with 0007) | 0007's elaboration benchmarks |

## Rejected alternatives

- **User metaprogramming that derives layouts** (elaborator reflection): the
  wrong layer, and refused in user code.
- **Always columnar, or always packed:** it pays index arithmetic where
  pointers were cheaper. The choice is per value.
- **Full flattening, as DPH did:** see above.
- **Packing shared data with indirections:** the exclusive grade selects
  cells instead, so the special case cannot be expressed.

## Decisions

- D1. The layout is part of the type in the dialect, never an attribute.
- D2. Packed only with the exclusive grade; columns for collections
  traversed field by field.
- D3. The opt-in views come first; automatic choices land only per measured
  case (≥ 1.3×).
- D4. One reference count per region.
- D5. Packed and columnar values are the shard message format.
