<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0013: compiler-chosen flattened layouts of algebraic data

**Status:** decided 2026-10-14; nothing of it is built (*read*,
2026-10-15: there is no `!idr.packed` type and no `Packed` library, and
`idr-columns` splits records alone,
`foreign/idr/lib/Transforms/Columns/Records.cpp:22-41`). Every stage is
**AFTER-SELF**. `make self` needs none of them, because every value
already has a layout: cells, sums held in place, arrays of structs, and
records in columns. With 0011's interpreter and 0012's tables, this is
one of the three consumers of 0010's array style. It starts after
`make self` and sharding's first stages. F2 needs only what is already
built, so it can come earlier if 0011's or 0012's tables hold an array
of a sum.

This builds on work done elsewhere:
- **Data types carry their constructors.** A data type is an identified
  type whose body is set once, with its constructors in tag order and a
  role for each. Boxing belongs to the value's type alone: `!idr.box`
  wraps the data type (`foreign/idr/include/idr/IR/IdrTypes.td:28-165`).
  This is the pipeline cutover's D29 (c7aa7b62) and the representation
  wave's D1 and D16 (bfdcac70); both proposals' last texts are at
  484d6403.
- **Arrays of records are columns,** one tensor per leaf, by upstream's
  one-to-N conversion: `idr-columns` (`lib/Transforms/Columns/`,
  bfdcac70; 0010 D44). That is the columns half of D1.
- **The layout limits are representations,** not refusals. A cell with
  more object slots than its header counts carries a count word. A box
  of a sum with more than 2^16 constructors has a two-level tag. An
  element with a stride over 64 KiB is boxed
  (`include/idr/IR/Layout.h:3-11`; the representation wave's D4).

**Sources.** `sources/notes/flattened-data/`:
- `packed-trees.md`: Gibbon, LoCal, Parallel LoCal, GC-24, GHC's compact
  regions (CNF), Marmoset, and Allais's serialised data in Idris 2;
- `columnar.md`: Arrow, Dremel and Parquet, Zig's `MultiArrayList`,
  StructArrays, `vector`;
- `flattening.md`: NESL, DPH, Futhark, Elsman.

Their code citations predate the cutover (`Layout/*.cppm`). That code is
now `foreign/idr/lib/IR/Layout/*.cpp`. Claims are marked *read*,
*measured*, *recalled*, *conjecture* or *decision*.

## What it changes

Today an Idris type has one layout, chosen from its shape (*read*):
- **Cell.** `!idr.box` holds a type that contains itself in place.
  `layout::fit`, run in idr-defunctionalize, makes those boxes from the
  type graph (`lib/IR/Layout/Fit.cpp:3-13`,
  `lib/Transforms/Defunctionalize/Pass.cpp:124`).
- **Sum in place.** Any other `!idr.data` value is a sum held in place.
  It has a tag of 8, 16 or 32 bits, then slots that its constructors
  share by component and countedness. A counted slot is null in every
  constructor that does not use it
  (`lib/IR/Layout/Components.cpp:28-69`, `include/idr/IR/Layout.h:137-164`).
- **Arrays.** An array stores its structs inline: each element is a
  one-field cell without its header (`lib/IR/Layout/Layouts.cpp:141-165`).
  Arrays of records are the exception, held as columns, except for the
  records that `idr-columns` keeps whole
  (`include/idr/Transforms/Columns.h:5-23`).

This proposal adds two layouts for the same types. The compiler chooses
between them from facts that the types and analyses already hold:
1. **Packed:** a tree serialized in preorder into one buffer, so every
   subtree is a contiguous slice. A cursor walks the buffer instead of
   following pointers. Gibbon-17's Fig. 1 tree takes 96 bytes as structs
   and 29 bytes packed.
2. **Columnar,** for what is not yet columns:
   - an array of sums (D6);
   - lists, `Vect` and ragged children, as 0010's `Ragged` (0010 §3.7);
   - a recursive value, as preorder node arrays with a `subtree_size`
     column, Co-dfns style (`sources/code/co-dfns/cmp/TT.apl:1-6`).

   An erased value has no column, because the frontend emits no field
   for it.

On packed data, a traversal is a cursor walk whose end witnesses are SSA
results (*conjecture*), and a fold streams through the buffer once.

On columns, operations become array operations, lowered to `linalg`
through the array core (0010 §4.4):

| Operation | Becomes |
| --- | --- |
| Per-constructor work | a masked map over the tag column |
| A fold over a tree | a segmented reduction in reverse preorder, as in Futhark and NESL |
| A binder | a segmented scan |
| A rewrite | a gather, scatter and compaction |

Fusion stops at gathers, scatters and filters. Nothing is fully
flattened, as DPH did: it paid in index arithmetic and space, and here a
layout is chosen for each value where its access pattern pays.

## Decisions

- D1. Each layout is a type over the one declaration:
  - **Cell:** as today.
  - **Packed:** `!idr.packed<T>`, where `T` is the identified data type.
    It wraps `T` as `!idr.box` does.
  - **Columns:** 0010's tensors. There is no `!idr.columns` type.

  A layout is never a discardable attribute, which a pass could drop. It
  is never a parameter inside the identified type either: each layout
  would then be a second identified type holding a copy of the body.
  `!idr.packed` is ours because no upstream dialect defines a sum type of
  any kind (*read*: the type definitions in the pinned
  `M/include/mlir/**/*.td`, 2026-10-14). LoCal's located types,
  checked between passes, are the precedent.
- D2. A value is packed only at the exclusive grade (`!idr.excl<T>`,
  `IdrTypes.td:242-271`), and a packed buffer holds no offsets:
  - **Sharing selects cells.** The heap is acyclic
    (`lib/IR/Verify/Knots.cpp:3-14`), so an exclusive value is a tree.
    This removes the need for Gibbon's indirection constructor.
  - **Random access selects cells.** A consumer that reaches a subtree
    out of preorder keeps the value in cells. Offsets would change the
    representation for every function that uses the type. A dummy
    traversal would silently change complexity: `rightmost` runs 150×
    slower packed (Gibbon-17 §6.1).
  - **Columns** hold a collection traversed field by field.
- D3. The opt-in, `Packed t` from a trusted library, comes first.
  - **Automatic choices** for what is not an array land one case at a
    time. A case lands when a fixture proves it at least 1.3× faster
    than cells on the benchmark set (F3, F4). It then becomes part of
    the compiler's rule.
  - **Arrays of records and sums** are always columns, with no gate.
    0002 (in progress) makes `idr-columns` an optimization by role.
    Skipping its conversion leaves the array whole and the program's
    output unchanged.
  - **The opt-in for columns** is 0010's array. A `Columns t` view would
    be a second way to write the same thing.

  The builder is linear and writes the tree once, in order. Cursors are
  linear, and their types track the position in the preorder: LoCal's
  location calculus, reduced to Idris's quantities, as Allais does in
  plain Idris 2. The builder writes in order, so nothing inside the
  buffer is shared and no grade is needed. Sharing the buffer itself is
  a counted reference to it. *Decision (audit, 2026-10-15):* `Packed t`
  lands together with `!idr.packed<T>` (F1). The byte layout, field
  order included, is derived once, in C++, from the type's body. The
  frontend checks cursors against `t`'s constructors and derives no
  layout. An F1 without the type would be a frontend copy of the layout,
  for the type to replace later.
- D4. A packed buffer has one count. Its internal references are
  offsets, so freeing it walks nothing, as with GC-24 and CNF. When
  idr-rc proves the buffer unique, reuse in place covers all of it. A
  column set is N array cells, one per tensor, as One-Shot Bufferize
  allocates them (0010 §4.5, §8). In-place reuse of columns is
  One-Shot's decision (0010 D18). One allocation for all N columns, as
  Zig's `MultiArrayList` makes, would need a bufferization model of ours
  beside upstream's.
- D5. Packed and columnar values are the message format between shards
  (0008):
  - an exclusive value moves, and its region goes with it (0008,
    "Lessons from Swift's concurrency model");
  - any other value is sent as a copy of its buffers, with no detach
    walk.

  The send check is unchanged.
- D6. An array of a sum held in place becomes:
  - a tag tensor, in the cell's tag type;
  - one tensor per shared slot.

  An array of a boxed type is a tensor of boxes, a counted element with
  one path (0010 D17). This is Arrow's sparse union over typed shared
  slots (`Columnar.rst:933-1014`): a slot's width is the maximum over
  constructors of each slot type's use, not their sum. Two forms are
  rejected:
  - **A one-bit tag tensor:** it would be a second layout of the tag,
    and LLVM stores an `i1` in a whole byte anyway
    (`L/include/llvm/IR/DataLayout.h:579-597`).
  - **Arrow's dense union:** a map over it is a gather.

  *Corrected 2026-10-15:* the slots are shared by value type, not by
  `SumLayout`'s runtime components. `SumLayout::types()`
  (`Layout.h:152-158`) gives words and `!llvm.ptr`
  (`Components.cpp:127-149`), which would erase the types that idr-rc
  counts by. `idr-columns` runs before idr-rc, on value types
  (`Records.cpp`). One slot rule serves both cases: the first free slot
  of a type and its countedness (`Components.cpp:35-67`), parameterised
  by what a component is, so the rule exists in one copy. A counted
  slot that a constructor does not use has no null at the value level:
  the runtime's NULL exists only as a lowered word. F2 settles what
  such a slot holds. The candidate is a persistent constant of the
  slot's type, which counting skips (`runtime/idris_rt.h`, "Reference
  counting"). Releasing a column set would then scan the counted
  columns with no tag dispatch (*conjecture*).
- D7. A packed buffer is one contiguous allocation, grown by doubling
  through the runtime's allocator. It holds only relative offsets: no
  chunks, no redirection tags, no tagged pointers. Gibbon packs a chunk
  offset into a pointer's high bits and caps chunks at 65 KB for it. The
  builder is linear and every offset is relative, so moving the buffer
  invalidates nothing (Allais; LoCal §3.4).
- D8. Parallel traversal of packed data comes from cells above a task
  cutoff and packed subtrees below it, never from offsets inside a
  buffer. In Parallel LoCal, packing only the bottom two levels of a
  tree removes 75% of its pointers (ParLoCal §4.1).
- D9. Field order in a packed constructor follows the traversals that
  read it, chosen by a greedy walk over the field-access graph. This is
  Marmoset's greedy variant, 1.14 to 54 times faster than Gibbon.
  Marmoset's ILP is not taken: it needs CPLEX, called through generated
  Python.
- D10. The automatic packed choice reads idr-rc's exclusive grades. It is
  a module step between step 4 of `lib/Transforms/Ownership/Rc.cpp:3-26`,
  which writes those grades, and step 5, the commit. It cannot come
  earlier: exclusivity reads the dups that placement made
  (`lib/Analysis/Ownership/Exclusivity.cpp:11-30`). Placement does not
  change. An exclusive tree has no dups, only moves and drops, and the
  commit folds the tree's drops into the buffer's one decrement at the
  traversal's end cursor. The choice is an optimization: skipping it
  leaves the value in cells, so it is an action (0002's I2).
- D11. Packed data is built only by the program, or received from its own
  shards. Nothing loads it from a file, so there is no trusted header
  and no unchecked reader. The compiler's files, from its Idris half to
  the C++ driver, carry columns. Their reader checks each id column once
  against the extent of the table it indexes (0009 §5.4, 0012 D1). A
  packed buffer would need a walk over the whole tree to check its
  offsets.
- D12. Columns for a collection that is not an array are chosen by a
  whole-program step before `idr-columns`, so that `idr-columns` turns
  them into columns and 0010's arrays stage sees tensors. `idr-columns`
  runs right after idr-optimize and before dead-value removal
  (`lib/Transforms/Pipeline.cpp:48-76`). F3 settles exactly where the
  step sits.
- D13. A proved automatic case is part of the compiler's rule. An
  unproved case stays in cells unless the program writes `Packed t`.
  There is no option.

## Staged plan

| Stage | Needs | Content | Proof |
| --- | --- | --- | --- |
| F1 **AFTER-SELF** | identified data types (built) | `Packed t` with `!idr.packed<T>`, verified after every pass: the linear builder and cursors; a layout derived from the type's body (D3, D9); idr-rc's commit and idr-lower handle the buffer | fixtures that build a packed tree and fold it in preorder, with output equal to the cell version; an `idr-expect` property: one count per packed buffer |
| F2 **AFTER-SELF** | `idr-columns` (built) | arrays of sums as columns (D6), in `idr-columns`' one conversion, together with records | output equal to the array-of-structs version; an `idr-expect` property: one array cell per column |
| F3 **AFTER-SELF** | F2 | columns for lists and trees of records traversed field by field, converted to 0010 arrays before `idr-columns` (D12) | nbody-style records at least 1.3× faster than cells |
| F4 **AFTER-SELF** | F1 | automatic packing of exclusive trees that are built once and traversed whole (D10) | Gibbon's tree add1, sum and repmax at least 1.3× faster than cells on both targets, and within 1.5× of Gibbon's published numbers on x86_64 Linux, where every Gibbon result was measured; a fixture for each drop the commit folds |
| F5 **AFTER-SELF** | F1, F2; 0008's P4 | packed and columnar values as shard messages (D5) | 0008's message benchmarks: copy cost per byte against the detach walk |

## Rejected alternatives

Each is rejected for the reason in the decision that names it:
- packing shared data with indirections (D2);
- offsets or dummy traversals for random access (D2);
- a layout parameter inside the identified type, or `!idr.packed<@T>`
  naming a symbol, the nominal form the cutover replaced (D1);
- a `Columns t` view (D3);
- one allocation for all columns (D4);
- Arrow's dense union (D6);
- chunked buffers with redirection tags (D7);
- Marmoset's ILP (D9);
- choosing packing before counting is placed (D10);
- packed buffers as the compiler's files (D11);
- an option that turns an automatic choice on (D13).

Three more, for their own reasons:
- **Always columnar, or always packed:** it pays index arithmetic where
  pointers were cheaper.
- **Full flattening, as DPH did:** see "What it changes".
- **User metaprogramming that derives layouts:** it is the wrong layer.
  Elaborator reflection is a pragma, which user modules may not use
  (`compiler/src/IdrisMLIR/Frontend/Profile.idr`, `checkPragmas`).

## Rules it keeps

- **Facts in types:** the layout is the value's type; grades and
  multiplicities are unchanged (D1).
- **One declaration per data type.**
- **The acyclic heap,** which makes packing always possible.
- **The closed world:** every closure is a sum whose applies are direct
  calls, so the compiler sees every consumer.
- **Raw, untagged heap references** (D7).
- **No way in from outside** (D11).
- **No oracle:** a layout change is invisible to a program's output, and
  the corpus proves it.
- **Both targets:** no layout is target-specific.

## Consumers

- **0011's term arena and tables:** hash-consing makes the arena a DAG,
  so it is never packed; its tables are columns.
- **0010's array core.**
- **0012's syntax nodes and Core in preorder,** the columnar form of a
  tree.
- **bumbledb's port** (`../bumbledb/proposals/0003-idris-port.md`).
- **0015's sums over a field computed from another field:** 0015 leaves
  to this proposal whether the tag shares storage with that field, and
  this proposal does not design it yet.
