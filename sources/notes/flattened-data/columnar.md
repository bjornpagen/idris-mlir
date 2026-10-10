# Notes: columnar layouts of nested and algebraic data, and generic flattening

Cluster `columnar` of the flattened-data study, read 2026-10-09. Every claim about a source
cites a stored path, relative to `sources/` (the staged copies are under
`scratchpad/selfhost/flat/stage/sources/` until they are committed). Claims about idris-mlir cite
repository paths. `§` is a section of a paper; `file:N` a line of a stored file at its pinned
revision.

Sources read:

| Source | Stored at | Read |
| --- | --- | --- |
| Arrow columnar format 1.5 (tag apache-arrow-26.0.0) | `docs/arrow/` | `Columnar.rst` whole; `Intro.rst` whole; `format/Schema.fbs` type tables, `Field`; `format/Message.fbs` `FieldNode`, `RecordBatch` |
| Arrow blog, Arrow and Parquet parts 1–3 | `docs/arrow-site/_posts/` | all three |
| Melnik et al., Dremel, PVLDB 3(1) 2010 | `papers/melnik-2010-dremel/paper.pdf` | whole paper with Appendices A–D |
| Parquet format 2.14.0 | `docs/parquet-format/` | `README.md` (format, types, nested encoding, nulls), `LogicalTypes.md` §Nested Types, `Encodings.md` (plain, dictionary, RLE hybrid), `VariantShredding.md` §Value Shredding |
| Parquet site | `docs/parquet-site/` | nested-encoding and nulls pages |
| Zig 0.15.2 | `code/zig/` | `lib/std/multi_array_list.zig` whole (code, not all tests); `lib/std/zig/Ast.zig` header, `Node`, `Data`, `extraData`; `lib/std/zig/Zir.zig` header; `src/InternPool.zig` header, `Local`, `Shard`, `Key`, `Item`, `Index`, `get` |
| StructArrays.jl v0.7.3 | `code/structarrays/` | `docs/src/{index,advanced,counterintuitive}.md`; `src/{interface,structarray,utils,collect}.jl` |
| `vector` 0.13.2.0 | `code/vector/` | `Data/Vector/Unboxed.hs` module docs; `Unboxed/Base.hs` families, class and every instance kind; `internal/unbox-tuple-instances` (pairs, zip/unzip); `GenUnboxTuple.hs` |
| Filliâtre & Conchon, ML 2006 | `papers/filliatre-2006-hash-consing/paper.pdf`, `code/ocaml-hashcons/` | whole paper; `hashcons.mli`; `hashcons.ml` table and add/resize |
| Already in the library (cross-links) | `papers/reinking-2021-perceus/`, `papers/lorenzen-2023-fp2/`, `papers/ullrich-2019-counting-immutable-beans/`, `papers/chataing-2024-unboxed-data-constructors/`, `papers/kjolstad-2017-taco/` | Perceus §2.4 (reuse analysis); Chataing abstract and §1 |
| Being committed from the `apl` staging tree (cross-links) | `papers/hsu-2019-data-parallel-compiler/`, `papers/henriksen-2019-incremental-flattening/`, `papers/bik-2022-sparse-mlir/`, `code/co-dfns/` | not re-read here; cited only for what their catalogue lines state |

## 0. The starting point: how idris-mlir lays out values today

Read so that every recommendation below is a change to something that exists.

- **The type decides the layout, once per declaration.** A monomorphic `idr.data` is either an
  unboxed sum (`!idr.data<@T>`, its values are its slots, "spread over whatever holds them") or
  a box (`!idr.box<@T>`, its values are cells). A type is a box when it contains itself, or when
  it is a record or closure sum whose values would overflow the header of a cell holding them
  (`foreign/idr/include/idr/IdrOps.td:113-131`, `:537-575`). A field's quantity is its type:
  `!idr.erased`, `!idr.lin<T>` or `T` (`IdrOps.td:577` comment above `Idr_CtorOp`); the grade
  `!idr.q<quantity, permission, T>` "lives in the type, where no pass can drop it"
  (`IdrOps.td:198-227`).
- **Components of a value type** (`foreign/idr/lib/Layout/Components.cppm:112-136`): none for
  erased and the world; one pointer for strings, boxes, closures, tokens and destinations; one
  `i64` for a big or a nat; an array is its cell pointer plus one `i64` per dimension (so a
  bounds check compares registers); an unboxed sum is its tag and slots; a scalar is itself.
  Which components are counted references is a parallel list (`:138-160`).
- **An unboxed sum's layout** (`Components.cppm:69-110`, `Layout/Sums.cppm`): a tag of 8, 16 or
  32 bits by constructor count (none for one constructor), then slots shared between
  constructors: a constructor's component takes the first unused slot of the same MLIR type and
  the same countedness, else a new slot. A counted slot holds null in every constructor that does
  not use it, "so that the references of a sum are exactly its counted slots" (`Sums.cppm`). This
  is neither a C union (bytes overlapping across types) nor one field per constructor: it is a
  typed overlay.
- **A cell** (`runtime/idris_rt.h:26-73`, `:167-171`; `Layout/Layouts.cppm:171-220`,
  `Layout/Cells.cppm`): an 8-byte header (`count`, then `info` = tag 16 bits, objs 8 bits, kind
  7 bits, a stack-cell bit), then the counted components, one word each, then the others sorted
  by alignment descending "so that the small ones ... share a word": "the order of fields in the
  source is not a layout" (`Layouts.cppm:193-205`). Limits: 65,536 constructor tags, 255 object
  slots (`idris_rt.h:106-107`, `Layout/CellInfo.cppm`).
- **Fit** (`Layout/Fit.cppm:1-8`, `:66-70`, `:157-196`): when a cell would hold more object
  slots than a header counts, records and closure sums are made boxes, widest first, by setting
  `box` on the declaration and retyping its values: "the type decides how a value is flattened,
  so making a declaration a box and retyping its values is the whole change".
- **Arrays are arrays of structs.** An array is a builtin `memref` of value types
  (`IdrOps.td:110-112`); its cell is the header, the length, then the elements, "each laid out as
  idr-lower lays out a cell's fields (object slots first)" (`idris_rt.h:152-165`); the element's
  stride is its size at its own alignment and the array's tag holds the stride
  (`Layouts.cppm:150-169`). Nothing in the compiler is a structure of arrays.
- **Closures are sums.** idr-defunctionalize makes each closure key (type, label set) a sum
  `@fn$<n>` with one constructor per label whose fields are its captures, unboxed unless the key
  is on a cycle through captures, "as a recursive set of lambdas is a recursive datatype"
  (`foreign/idr/lib/Defunctionalize/Sums.cppm:19-35`).
- **The compiler's own terms** are Idris 2's `Term : Scoped`, a recursive family indexed by its
  scope, with an `FC` in every constructor, a de Bruijn `idx : Nat` with an erased proof
  `(0 p : IsVar name idx vars)`, and lists of arguments (`compiler/idris/src/Core/TT/Term.idr:98-126`;
  binders `Core/TT/Binder.idr:93-115`). Under the layout above every node is a box cell and every
  child a pointer. The context's definitions were just moved to a growable `Linear.Array` table
  (commit `f21bcbfe`; `libs/mlir-linear/Linear/Array.idr:1-21`): the first index-addressed table
  in the fork.

So today "flattening" in idris-mlir means unboxing a non-recursive sum into the slots of the one
record that holds it (array of structs, record of slots); recursion, lists and trees are
pointers. Everything below is about the other axis: one column per component across many
values.

## 1. Apache Arrow: a physical layout per type, children per nested type

**Definitions.** An array is a data type, a sequence of buffers, a 64-bit length, a null count
and, if dictionary-encoded, a dictionary; nested arrays add child arrays
(`docs/arrow/docs/source/format/Columnar.rst:209-219`). "Each data type uses a well-defined
physical layout" (`:100-101`), and the type table gives it (`:107-175`). A nested type is
"fully specified" by its children, and two are equal iff their children are (`:82-85`). The
type of a field is a finite tree: `Field { name, nullable, type, dictionary, children: [Field] }`
(`docs/arrow/format/Schema.fbs:520-539`). No construct names a type from inside itself, so a
recursive type has no Arrow layout.

**How a layout is derived from a type.**
- *Product* (`Struct`): one child array per field, all of the struct's length, "independent and
  need not be adjacent", plus the struct's own validity bitmap (`Columnar.rst:768-791`). A
  child slot under a null struct may hold a valid value ("alice" in the example), so whether a
  child entry is valid is the AND of both bitmaps (`:841-858`).
- *Optionality*: every array except a union has a validity bitmap, one bit per slot, LSB
  numbering, `is_valid[j] = bitmap[j/8] & (1 << (j%8))`; with a zero null count it may be
  absent (`:315-348`). A null slot's memory "can have any value" (`:354-356`). Nested arrays
  have their own bitmap "regardless of" their children's (`:350-352`). The `nullable` flag of a
  `Field` "has no bearing on the array's physical layout" (`:1278-1281`).
- *Lists*: `List<T>` is a validity bitmap, `length + 1` offsets (32-bit; 64-bit for
  `LargeList`) into a child array of `T`, monotonic even across nulls, and a null may own a
  non-empty child segment (`:441-449`, `:541-588`). `List<List<Int8>>` is offsets into a list
  array that has offsets into an `Int8` array (`:589-624`): each level of nesting adds one
  offsets buffer and one bitmap, and leaves are contiguous.
- *List views*: offsets and explicit sizes, so offsets may be out of order and lists may share
  child values (`:628-725`), with the invariants `0 <= offsets[i] <= len(child)` and
  `offsets[i] + size[i] <= len(child)` (`:643-647`).
- *Fixed-size lists*: no offsets; slot `j` is `values[j*N .. j*N+N]` (`:727-765`).
- *Sums* (`Union`): no validity bitmap of their own; nullness is the selected child's
  (`:867-869`). **Dense**: an `int8` types buffer, an `int32` offsets buffer into the selected
  child, offsets increasing per child, one child per variant, "5 bytes of overhead for each
  value" (`:874-889`). **Sparse**: no offsets, every child as long as the union, only the
  selected slot meaningful (`:933-1014`); it costs space but "is more amenable to vectorized
  expression evaluation" and lets equal-length arrays become a union by adding a types array
  (`:940-945`). More than 128 variants is a union of unions (`:881-884`). `typeIds` may map
  type codes to children (`Schema.fbs:148-157`).
- *Maps*: `List<entries: Struct<key, value>>`, keys and values each contiguous
  (`Schema.fbs:118-146`; `Intro.rst`, section Map).
- *Strings*: offsets plus bytes (`Columnar.rst:423-478`), or 16-byte views that inline strings
  of at most 12 bytes and otherwise keep a 4-byte prefix, a buffer index and an offset, from
  Umbra (`:482-526`).
- *Repetition compression*: a dictionary-encoded array is an integer index array plus a
  separately laid out dictionary, which may repeat values or hold nulls (`:1025-1072`); a
  run-end-encoded array is two children, strictly increasing `run_ends` and `values`, with no
  parent bitmap; random access is a binary search, O(log n) (`:55-56`, `:1085-1164`).
- *Buffers per layout* are fixed by the layout (`:1166-1187`): e.g. struct = validity only,
  sparse union = type ids only, dense union = type ids and offsets, REE = none.

**How operations act on the layout.** Element `j` of a list is a slice of the child, computed
from two offsets (`:439-440`); a union slot reads its type code, then (dense) its offset; a
struct field is a whole child array, so projection is free. Serialization flattens the field
tree by a pre-order depth-first walk into `FieldNode {length, null_count}`s and a flat list of
buffers, each `(offset, size)` in the body, so an array is rebuilt "using pointer arithmetic and
thus no memory copying" (`:1297-1348`; `docs/arrow/format/Message.fbs:31-43`). The layout is
"relocatable without pointer swizzling" (`:45-46`): every internal reference is an offset.
Alignment and padding to 8 or 64 bytes are recommended in memory and required in IPC
(`:264-295`).

**Type versus programmer.** The type fixes the layout family; the producer chooses the variant:
dense or sparse union (the `mode` parameter, `:182-183`), 32- or 64-bit offsets, list or list
view, dictionary encoding and run-end encoding of any array, and whether a zero-null bitmap is
materialized. A consumer "should be ready to handle those two possibilities" (`:343-348`).

**Arrow and Parquet compared.** Arrow gives O(1) random access, Parquet does not; Parquet is a
storage format built for size, Arrow an in-memory format for vectorized kernels
(`docs/arrow-site/_posts/2022-10-05-arrow-parquet-encoding-part-1.md`, section Parquet vs Arrow).
Arrow keeps one validity mask per nullable level; Parquet keeps only definition levels on the
leaves (`.../2022-10-08-arrow-parquet-encoding-part-2.md`, sections Struct / Group Columns and
Definition Levels). Converting between them is "complex", with corner cases such as a non-empty
offset range under a null list (`.../2022-10-17-arrow-parquet-encoding-part-3.md`, section
Additional Complications).

## 2. Dremel and Parquet: shredding nested records into leaf columns

**Data model.** `τ = dom | <A1 : τ[*|?], ..., An : τ[*|?]>`: a field is required, optional
(`?`) or repeated (`*`, an ordered list) (`papers/melnik-2010-dremel/paper.pdf` §3). Only leaf
(atomic) fields become columns.

**Repetition and definition levels** (§4.1, Figure 3). For a value of a field with path `p`:
- the *repetition level* is the depth of the repeated field in `p` that repeated most recently,
  0 meaning a new record; for `Name.Language.Code` it ranges over 0–2;
- the *definition level* is how many of the fields in `p` that could be undefined (optional or
  repeated) are present; a NULL is any value whose definition level is below the maximum, and
  is not stored. Integer levels rather than is-null bits are chosen "so that the data for a leaf
  field ... contains the information about the occurrences of its parent fields".
- Levels are stored only where needed (none for `DocId`), packed in as few bits as the maximum
  level needs (2 bits for a maximum of 3), and both maxima are computed from the schema (§4.1
  "Encoding"; `docs/parquet-format/README.md`, section Nested Encoding). Parquet encodes levels
  with the RLE/bit-packing hybrid (`docs/parquet-format/Encodings.md`, RLE = 3), so a column of
  1,000 NULLs is one run of definition level 0 and no values (`README.md`, section Nulls).
- Empty records need their own level-only stripes for a lossless encoding (Appendix A, last
  paragraph).

**Algorithms.** Shredding (Appendix A, Figure 16): a tree of field writers isomorphic to the
schema; `DissectRecord` tracks the current repetition level; the definition level is fixed by
the writer's position; writers update lazily, a child syncing to its parent's levels only when
it gets a value (§4.2). Assembly (§4.3, Appendices B–C, Figures 17–18): a finite-state machine
whose states are field readers and whose transitions are labelled by the next repetition level;
for a transition `(f, l) -> n`, `n` is the first leaf inside `f`'s ancestor that repeats at level
`l`. An FSM over a subset of fields reconstructs records "as if they contained just the selected
fields", keeping the enclosing structure (Figure 5). Queries need no assembly: select-project-
aggregate advances readers in lockstep by `fetchLevel`/`selectLevel` (Appendix D, Figure 19),
and expressions emit at the nesting level of their most-repeated input (§5).

**Measured** (§7, one dual-core machine for the local experiment, thousands of nodes otherwise):
reading few columns is "about an order of magnitude" faster than reading records; time grows
linearly with the number of fields; record assembly and parsing "each potentially doubling the
execution time"; the crossover with record storage "often lies at dozens of fields" (Figure 9).
A MapReduce job reading one field read 0.5 TB of columns instead of 87 TB of records, hours to
minutes, and Dremel took it to seconds (Figure 10). A within-record aggregation over a 70 TB
table read 13 GB (query Q4). The authors conclude that software layers "need to be optimized to
directly consume column-oriented data" (§8).

**Parquet's schema rules.** A list must be the 3-level structure
`<rep> group (LIST) { repeated group list { <rep> element } }`, the outer repetition saying
whether the list is nullable and the element's whether elements are; maps are
`repeated group key_value { required key; <rep> value }` (`docs/parquet-format/LogicalTypes.md`,
sections Lists and Maps); older 2-level files need five reading rules (Backward-compatibility
rules). Parquet has no union type. Its answer to heterogeneous data is `VARIANT`: a
self-describing binary `value` column beside an optional `typed_value` column that "shreds" the
values matching one chosen type into a plain column; the pair's four null/non-null combinations
are given meanings, and an object may be partially shredded
(`docs/parquet-format/VariantShredding.md`, section Value Shredding).

**Type versus programmer.** The schema fixes the columns and level maxima; the writer chooses
encodings per page and, for variants, which paths to shred.

## 3. Zig: structure of arrays derived at compile time, and index-based compiler IRs

**`std.MultiArrayList(T)`** (`code/zig/lib/std/multi_array_list.zig`).
- *Derivation from the type* (`:9-62`): for a struct, one array per field; for a tagged union,
  an array `tags` and an array `data` of the same union with its tag removed (`Bare`), built by
  `@Type` at compile time; an untagged union or any other type is a compile error. A field that
  is itself a struct stays one array of that struct: the split is one level deep, never
  recursive. The `data` array of a union is as wide as its largest variant, so a union list is
  sparse in Arrow's sense with overlapped storage.
- *Storage* (`:20-24`, `:166-201`, `:602-610`): one allocation (`bytes`, `len`, `capacity`);
  the field arrays follow each other in order of alignment, descending, so no padding is needed
  between them; a `Slice` caches each field's start pointer (`:66-75`, `:219-231`). Zero-sized
  fields take no bytes (`:89-92`).
- *Operations*: `items(.field)` is a typed slice of one column (`:83-94`); `get(i)`/`set(i, e)`
  gather and scatter one element across the columns, converting a union to and from tag and bare
  payload (`:96-117`); insert, remove, sort and resize run per column with `inline for` over the
  fields (`:296-387`, `:535-562`); growth is superlinear from an initial capacity of a cache line
  divided by the widest field (`:463-478`).

**The self-hosted compiler's AST** (`code/zig/lib/std/zig/Ast.zig`). `tokens` and `nodes` are
`MultiArrayList`s and `extra_data` is a `[]u32` (`:17-31`). A node is `{tag, main_token, data}`
with a one-byte tag and an 8-byte `data` union, asserted at compile time (`:3014-3086`); `data`
is one of a closed set of shapes, pairs of node indices, token indices, optional indices and
extra indices (`:3964-3984`). Each tag's documentation says which shape its `data` has and what
its `main_token` is (e.g. `test_decl`, `global_var_decl`, `:3089-3130`). Children are `u32`
indices (`Node.Index`), absence is a sentinel `maxInt(u32)` (`OptionalIndex`), and some
references are relative offsets (`:3020-3076`). Payloads that do not fit 8 bytes go to
`extra_data`, read back by `extraData(index, T)`, which decodes `T`'s fields in order from
consecutive words (`:283-305`).

**ZIR** (`code/zig/lib/std/zig/Zir.zig:1-36`) is the same pattern for the untyped IR:
`instructions` (a `MultiArrayList` slice), `string_bytes`, `extra`; because nothing in it is a
pointer, it is written to a cache file as those arrays behind a `Header` of their lengths
(`:38-50`), and later stages need no access to the AST (`:5-8`).

**InternPool** (`code/zig/src/InternPool.zig`): every type and value of the typed compiler is an
`Index` (`enum(u32)`); "two values which have the same type can be equality compared simply by
checking if their indexes are equal" (`:4580-4587`). The flat form of an entry is
`Item {tag, data: u32}` plus words in `extra` (`:4574-4578`); its rich form is the `Key` union
(`:2008-2030`). `get(key)` looks the key up and returns the existing index, or appends the item
(`:7817-7860`), so the pool is hash-consing over flat storage. Storage is per thread (`locals`,
with `items`, `extra`, `limbs`, `strings` lists, `:1030-1075`) and the maps are sharded
(`:1533-1545`); the thread id is packed into the top bits of an index (`:4829-4837`).

**Type versus programmer.** `MultiArrayList` derives the split from the type and nothing else.
In the AST, ZIR and InternPool the programmer designs the encoding: which shapes `data` has, what
moves to `extra`, which references are relative. The type system checks the indices' kinds
(`Node.Index` versus `TokenIndex` versus `ExtraIndex`) but not their validity.

## 4. StructArrays.jl: a schema per element type, overridable

- **Schema.** `staticschema(T)` is by default the `NamedTuple` of `T`'s field names and types,
  generated per type (`code/structarrays/src/interface.jl:28-36`); `component(x, i)` defaults to
  `getfield` (`:10`) and `createinstance(T, args...)` builds an element from components
  (`:52-58`). Overloading the three gives a non-standard layout, e.g. flattening a `NamedTuple`
  field into its own columns (`docs/src/advanced.md`, section Structures with non-standard data
  layout).
- **Representation.** `StructArray{T, N, C, I}` holds `components::C`, a tuple of arrays of equal
  shape (`src/structarray.jl:1-29`); any `AbstractArray` can be a column, including GPU arrays
  (`docs/src/index.md`, section Using custom array types). `getindex` materializes an element by
  `createinstance(T, get_ith(cols, I...)...)` (`src/structarray.jl:345-357`); a range index gives
  a `StructArray` of sliced columns.
- **Recursion is opt-in.** Whether a field's column is itself a `StructArray` is decided by an
  `unwrap` predicate the caller passes (`src/structarray.jl:146-182`, `:245-253`); per-field
  loops recurse into nested `StructArray` columns (`src/utils.jl:55-82`).
- **Sums are not a layout.** A column's element type widens when a collected element does not
  fit (`Union{Missing, Int64}` in the example), by re-allocating that column
  (`docs/src/advanced.md`, section Mutate-or-widen; `src/collect.jl:65-112`): a sum lives inside
  one column as Julia's union element type, not as a tag column with children.
- **Semantics of materialized elements.** Built from columns, a `StructArray` is a view of them;
  built from an array of structs it is a copy; mutating a materialized mutable element changes
  nothing stored, so immutable element types are recommended (`docs/src/counterintuitive.md`).

**Type versus programmer.** The type gives the default columns; the programmer chooses nesting
depth (`unwrap`), custom schemas, and column storage.

## 5. `vector`'s `Data.Vector.Unboxed`: a data family indexed by the element type

- **Mechanism.** `data family Vector a` and `data family MVector s a`; `class (G.Vector Vector a,
  M.MVector MVector a) => Unbox a` (`code/vector/vector/src/Data/Vector/Unboxed/Base.hs:72-80`).
  Every element type gets its own representation by a data-family instance: "adaptive unboxed
  vectors ... picks an efficient, specialised representation for every element type"
  (`vector/src/Data/Vector/Unboxed.hs`, module header).
- **Instances, by type shape.** `()` is a length only (`Base.hs:111-112`); primitives are
  primitive byte arrays (`:448-525`); `Bool` is a `Word8` array (`:526-546`); a tuple of 2 to 6
  is a length and one vector per component, `V_2 !Int !(Vector a) !(Vector b)`, with every
  method distributed over the components and `zip`/`unzip` O(1) (`vector/internal/unbox-tuple-instances:1-8`,
  `:111-136`), generated by `vector/internal/GenUnboxTuple.hs`; `Complex a` and `Arg a b` are
  newtypes over vectors of pairs (`Base.hs:594-597`, `:720-723`).
- **User products.** `IsoUnbox a b` converts a type to its representation, by default by
  coercing `GHC.Generics` representations of the same shape; `As a b` derives the instances
  through `b` (`Base.hs:270-350`). A field may be kept boxed with `DoNotUnboxLazy`,
  `DoNotUnboxStrict` or `DoNotUnboxNormalForm` (`:790-813`, `:895-898`, `:981-984`).
- **No sums.** There is no instance for `Maybe` or `Either` in the stored module, and the module
  says a new instance "requires defining two data family and two type class instances"
  (`Unboxed.hs` header): sums and user types are the programmer's job.

**Type versus programmer.** Dispatch is by type, but every instance is written or derived by
hand; tuples are columns, records become columns only through an explicit `IsoUnbox`.

## 6. Hash-consing: one representation per value

- **Technique** (`papers/filliatre-2006-hash-consing/paper.pdf` §1–2). Smart constructors look
  every new value up in a table of existing ones, so structurally equal values are physically
  equal: `x = y ⇔ x == y ⇔ x.tag = y.tag` (§2.1, equation 1). Values are a private record
  `{node; tag; hkey}` (§2.1; `code/ocaml-hashcons/hashcons.mli`, type `hash_consed`), so maximal
  sharing "is now easily enforced by type checking"; equality on a node compares children with
  `==` and hashing combines children's stored keys, both O(1) (§2.2). The unique tags give O(1)
  hashing and a total order, hence Patricia-tree sets and maps (§2.2; `hashcons.mli`, `Hset`,
  `Hmap`). The table is weak, so unreferenced values are collected, and it stores the hash key so
  resizing never rehashes (§2.3; `code/ocaml-hashcons/hashcons.ml:20-90`).
- **Measured** (§3.1, Pentium 4, OCaml native): a λ-calculus quicksort ran in 91.5 s and 1,680 KB
  without hash-consing, 195 s and 480 KB with it; with memoization added, 54 s and 95,300 KB
  without, 5.06 s and 720 KB with. A SAT solver over hash-consed proxies "always" wins and on the
  de Bruijn formulas shows "a different asymptotic behavior" (§3.2.4); an 80-line BDD package
  falls out of it (§3.3).
- **Limits** (§4): a value is allocated before it is looked up; tags do not survive
  serialization; deep pattern matching through the record is inconvenient.
- **The flat version** is Zig's InternPool (§3 above): the tag is the index, the node is the
  `Item` plus `extra`, and the table maps keys to indices.

## 7. Cross-links in the library

- `papers/reinking-2021-perceus/perceus-tr-v4.pdf` §2.4: reuse analysis pairs a matched cell
  with an allocation "of the same size" in the branch and passes a reuse token. With columns there
  is no per-value cell to reuse; the analogue is reusing an index (a free slot in each column).
  `papers/lorenzen-2023-fp2/` (fully in-place functions) and
  `papers/ullrich-2019-counting-immutable-beans/` (borrowing, reset/reuse) are the same family.
- `papers/chataing-2024-unboxed-data-constructors/paper.pdf` (abstract, §1): unboxing a
  constructor is rejected when it would make distinct values share a representation, and checking
  that requires expanding type definitions, which need not terminate with recursive types: the
  "is this layout injective" question every flattening must answer for sums.
- `papers/kjolstad-2017-taco/` and, from the `apl` staging tree, `papers/bik-2022-sparse-mlir/`:
  per-level tensor formats; a compressed level (positions plus coordinates into the next level)
  is the same structure as Arrow's list offsets into a child.
- From the `apl` staging tree: `papers/hsu-2019-data-parallel-compiler/` with
  `code/co-dfns/cmp/TT.apl` (trees kept flat as parent vectors and transformed with data-parallel
  primitives) and `papers/henriksen-2019-incremental-flattening/` (flattening nested parallelism):
  the program-transformation side of what Arrow and Dremel do for data.

## 8. What idris-mlir should take

1. **Columns are another layout of the same `SumLayout`, not a second analysis.** The slots of an
   unboxed sum are already decided once per declaration from its constructors' component types
   (`Components.cppm:69-110`). An array of `!idr.data<@T>` laid out as columns is one column per
   slot plus one tag column: Arrow's sparse union, but over typed shared slots, so its width is
   the maximum over constructors of each slot type's use, not the sum over constructors
   (`Columnar.rst:933-945` versus `Components.cppm:84-100`). The same table then gives both the
   array-of-structs element (`Layouts.cppm:150-169`) and the struct-of-arrays columns; a second
   per-constructor layout would be a fact computed twice.
2. **Keep the counted-slot invariant per column.** A counted slot is null where its constructor
   does not use it (`Layout/Sums.cppm`); in a column, that makes "release every reference of the
   array" a scan of the counted columns with no tag dispatch, as the runtime frees a cell by its
   `objs` today (`idris_rt.h:40-44`). Arrow's "masked memory can have any value"
   (`Columnar.rst:354-356`) is acceptable only for uncounted slots, which is exactly what
   `idr.field` already promises for an unboxed sum ("reading another constructor's gives an
   unspecified value", `IdrOps.td:630-633`).
3. **Optionality is a sum, not a flag.** Arrow's validity bitmap is a one-bit tag column of a sum
   with one nullary constructor; Parquet's definition level is the depth of the deepest present
   constructor. Idris has only sums (`Maybe`), so a "nullable" bit next to the type would be the
   tag kept twice (Arrow's own `Field.nullable` has "no bearing on the array's physical layout",
   `Columnar.rst:1278-1281`, and is such a duplicate). What to take is the encoding: a column tag
   for a two-constructor sum can be one bit, where today a tag is at least 8 bits
   (`Components.cppm:78`).
4. **Erased fields have no column.** `!idr.erased` has no components (`Components.cppm:115-117`),
   as Arrow's Null layout allocates no buffers (`Columnar.rst:1016-1021`) and `vector`'s `()` is
   a length only (`Base.hs:111-112`). Indices with erased proofs, like `Term`'s `Local` with
   `(0 p : IsVar name idx vars)` (`Term.idr:99-100`), keep only the index column.
5. **Indices instead of pointers for the compiler's own data.** Zig's AST, ZIR and InternPool show
   a self-hosted compiler whose trees are tables of `u32` indices with a small fixed node and an
   `extra` array (`Ast.zig:3014-3086`, `:283-305`; `Zir.zig:26-36`), serialized by writing the
   arrays (`Zir.zig:38-50`). For the fork, a `Term` table with a tag column, an `FC` column (or
   an index into an `FC` table), and payload columns, written in plain Idris over
   `Linear.Array` as `mlir-linear` already does for the context (`Linear/Array.idr:1-21`), is the
   path that needs no compiler support; Idris can type the indices by the table they index,
   which Zig cannot.
6. **Hash-cons what is compared.** Names, types and normal forms that elaboration compares
   structurally are the case Filliâtre measures: equality and hashing become O(1) and memoization
   becomes cheap (§3.1: 54 s versus 5.06 s with memoization). An InternPool-style table (key to
   index, flat items) is the flat form (`InternPool.zig:4574-4587`, `:7817-7860`).
7. **Product splitting follows the type; depth is a choice.** `MultiArrayList` splits one level
   (`multi_array_list.zig:32-62`), StructArrays recurses only where `unwrap` says
   (`structarray.jl:146-182`), `vector` splits tuples fully and records only by `IsoUnbox`. For
   idris-mlir, the unboxed sum is already flattened recursively into slots (a record inside a
   record contributes its slots, `Components.cppm:133-134`), so a column per slot is the whole
   recursive split, and a box field is one pointer column. Fit's rule (box the widest record)
   then applies to the element of a columnar array exactly as to a cell.
8. **Lists as offsets, where the list is built once.** Arrow's `List<T>` (offsets plus one child)
   and `ListView` (offsets plus sizes, sharing allowed) are the flat forms of a finite list held
   inside many values (`Columnar.rst:541-725`). Idris's `List` is recursive and shared, so it
   stays a box chain in general; the offset form fits arrays that hold lists built once, frozen
   (`Linear.Array`'s `freeze`), and the compiler's own argument lists in a term table.
9. **Serialization by pre-order flattening.** Arrow's IPC flattens the type tree pre-order into
   field nodes and buffers with offsets relative to a body (`Columnar.rst:1318-1356`); with
   index-based data, a TTC file can be the tables themselves, as ZIR's cache is.

## 9. What idris-mlir should avoid

1. **Dremel levels as an in-memory form.** Levels give no O(1) random access
   (`2022-10-05-arrow-parquet-encoding-part-1.md`), assembly and parsing each can double a scan
   (`melnik-2010-dremel` §7), and the reading rules carry compatibility special cases
   (`LogicalTypes.md`, Backward-compatibility rules). They are a storage encoding.
2. **Struct validity independent of children.** Arrow lets a child be valid under a null struct
   and requires an AND of bitmaps (`Columnar.rst:841-858`); in Idris a field of an absent
   constructor does not exist, so a second validity per child would be a second, disagreeing
   copy of the tag.
3. **Programmer-chosen layout variants exposed in the type.** Dense versus sparse unions, 32- versus
   64-bit offsets, dictionary and run-end encoding are producer choices in Arrow
   (`Columnar.rst:182-183`, `:1025-1164`). If idris-mlir adopts any of them, the choice belongs to
   the layout (decided per module, like the tag width), not to a user-visible type, so that a
   program has one meaning whatever layout is picked.
4. **Untyped extra arrays.** Zig's `extra_data` is decoded by the reader's choice of `T`
   (`Ast.zig:291-305`): a wrong `T` reads garbage. A flat term table in Idris should index
   payloads by tag-dependent types.
5. **Hash-consing everything.** Without memoization it doubled the run time of the λ-term
   benchmark (§3.1: 91.5 s versus 195 s); tags are lost on serialization (§4). Intern what is
   compared or memoized, not every node.
6. **Mutable element views.** StructArrays' materialized mutable elements silently drop writes
   (`counterintuitive.md`); idris-mlir's values are immutable and arrays are written through
   `idr.array.set` in the world's order, which avoids the problem only if a columnar element is
   never exposed as an addressable cell.

## 10. Limits of these sources

- None flattens recursive types by type: Arrow's field tree is finite (`Schema.fbs:520-539`),
  Dremel's schema is a finite tree of records (§3), `MultiArrayList`, StructArrays and `vector`
  split non-recursive products and (Zig) tagged unions. Trees are flattened only by hand (Zig's
  AST, InternPool) or by program transformation (Hsu, Futhark), which other clusters cover; the
  packed-trees cluster staged beside this one (Gibbon's packed representations, GHC compact
  regions) covers trees serialized into buffers.
- None handles indexed or dependent types, quantities, or reference counting: Arrow and Parquet
  are schemas for data without identity; Zig frees by arena; Julia and Haskell rely on a tracing
  collector.
- Measurements: only Dremel (§7, 2010 hardware, Google's workloads) and Filliâtre (§3, a 2006
  Pentium 4) give numbers. The stored Zig, Julia and Haskell sources assert the benefits
  ("memory savings if the struct or union has padding", `multi_array_list.zig:13-15`) without
  measuring them.
- Arrow's spec is version 1.5 at tag 26.0.0; list views, binary views (1.4) and run-end encoding
  (1.3) are recent additions and not every implementation supports them (`Columnar.rst:485`,
  `:631`, `:1088`).
- The Parquet site's pointer to the Twitter post "Dremel made simple with Parquet" could not be
  fetched (HTTP 403 at `blog.x.com`, Wayback availability rate-limited).
