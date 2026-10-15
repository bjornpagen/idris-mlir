## C16 The lowering contract

Producer: U10, the one writer of `foreign/idr/lib/Conversion` and
`foreign/idr/include/idr/Conversion`. Paths are under `foreign/idr/`
unless named; `M/` is the pinned MLIR, `.toolchain/build/llvm-project/mlir/`.
Line numbers are the tree at a3e61f3a. Decided by 0004 §4 stage 12, §5.3,
§6 (D18, D19, D28, D29, D41) and 0003 §4.5, §8, §12, §13 (D17, D18, D23,
D24, D42); C15 and C17 fix the IR and the runtime on either side, and this
contract agrees with both.

### 1. The passes

Unchanged interface: `include/idr/Conversion/Passes.h` declares, through
`GEN_PASS_DECL_IDRLOWER`, `GEN_PASS_DECL_IDRENTRY` and
`GEN_PASS_DECL_IDRTAILCALLS`, the generated `idr::createIdrLower()`,
`idr::createIdrEntry()` and `idr::createIdrTailCalls()`; the units holding
the `GEN_PASS_DEF` are `lib/Conversion/Lower.cpp`, `Entry.cpp` and
`TailCalls.cpp`. No pass has an option.

The `def`s are U06's (C12 §2). One change to C12's row for `IdrLower`:
its `dependentDialects` are `::mlir::arith::ArithDialect`,
`::mlir::scf::SCFDialect`, `::mlir::ub::UBDialect`,
`::mlir::LLVM::LLVMDialect`, `::mlir::func::FuncDialect`,
`::mlir::cf::ControlFlowDialect`, `::mlir::math::MathDialect`,
`::mlir::memref::MemRefDialect` and `::mlir::affine::AffineDialect`.
`affine` is added because the view expansion of §4.6 makes `affine.apply`;
`linalg` goes because idr-lower makes no linalg op any more (the array
loops are deleted). The description U06 writes says: every `idr.func`
becomes a `func.func` under its mangled name; matches become scf; memref
views become offsets, sizes and strides; then each function is converted
on its own, every idr op and type and every memref value into the runtime
layouts; a buffer is a cell of the runtime and a copy the runtime's
counted copy; constants are static data named by their content.

The pipeline keeps, after idr-lower, `lower-affine`, `expand-strided-metadata`,
`convert-to-llvm` and `reconcile-unrealized-casts` (C12 rows 22, 24, 25):
idr-lower's output needs each.

### 2. What reaches idr-lower

The output of C12 row 17, for every program. Each item is an invariant;
a module that breaks one is the compiler's internal error, reported by
the conversion as an op it could not legalize.

- The idr dialect as C01, C02 and C11 define it after stage 11: no
  `idr.data` or `idr.ctor` op (D29), no `idr.program` (D28), no closure,
  apply or suspension (the defunctionalizer's sums, checked as today,
  `Lower.cpp:73-100`).
- Every array value is a builtin `memref` (C15 §7, C11 §1). Its element
  is a field type at no grade and not the world (`isFieldType`,
  `lib/IR/Grades.cpp:174-181`); any rank; each dimension static or
  dynamic; layout the identity or a `StridedLayoutAttr`; memory space
  none (a value buffer) or `#idr.world` (a world-ordered array, rank 0 or
  1, every dimension dynamic, identity layout, C11 §1). No tensor type
  and no `tensor` or `bufferization` op.
- The memref ops, exactly: `memref.alloc` (identity layout, no
  `alignment` or one of at most `IDRIS_RT_WORD_BYTES`, 8, C17 §3),
  `memref.global` with `constant` and a dense initializer of a builtin
  integer or float element, `memref.get_global` of one, `memref.dim`,
  `memref.load`, `memref.store`, `memref.copy`, `memref.subview`,
  `memref.expand_shape`, `memref.collapse_shape`, `memref.transpose`,
  `memref.cast`, `memref.reinterpret_cast`,
  `memref.extract_strided_metadata`. No `memref.dealloc`, `realloc`,
  `alloca`, `alloca_scope`, `view`, `reshape` or atomic op: no
  ownership deallocation runs (C15 §3).
- `idr.nat.to_extent` (C11 §2).
- The ownership ops U01 declares for buffers: `idr.own.adopt` (an owned
  buffer from a `memref.alloc`) and `idr.own.give` (an owned value given
  to a counted `memref.store`). Each changes no count and is its operand
  (§4.7).
- A `linalg` op only where every memref operand's element is a word, a
  builtin `IntegerType` or `FloatType`. A structured op over elements of
  ours is loops before counting (C14), since counting reads each element
  access.
- `idr.tie_shape` on memrefs (C11, C15 §4.5); `idr.lin.enter` and
  `idr.lin.use` on memrefs (C15 §4.2); `ub.poison` of a memref type
  (C15 §4.5).
- The world-ordered array ops of C11 (`idr.array.new`, `idr.array.get`
  with `moves`, `idr.array.set`) and the buffer ops (`idr.buffer_load`,
  `idr.buffer_store` and the `CallsRuntime` buffer and transfer ops,
  `include/idr/IR/IdrIOOps.td:69-199`), on rank 0 or rank 1 identity
  memrefs with dynamic dimensions.
- `scf`, `arith`, `math`, `cf`, `ub` and `affine.apply` on `index`.

### 3. A memref at run time: its components

The one runtime form of every memref value, in registers, in function
signatures, in cell fields, in sum slots and in captures, is its cell
and the fields of its LLVM descriptor that its type does not fix, in this
order:

1. `!llvm.ptr`, the cell (`idris_rt_array`, C17 §1): one the runtime
   allocated, or a constant's static cell (§4.2). Counted.
2. `i64`, the offset in elements, only for a `StridedLayoutAttr` whose
   offset is dynamic. Not counted.
3. `i64` for each dynamic dimension, its size, in dimension order. Not
   counted.
4. `i64` for each dynamic stride of a `StridedLayoutAttr`, in dimension
   order. Not counted.

Every cell has its header in front of its elements, a constant's too
(0003 D23 as amended by the coordinator, 2026-10-14; C17 §5), so the
descriptor's allocated pointer is the cell and its aligned pointer is
always `cell + sizeof(idris_rt_array)` (16, C17 §1): computed where an op
needs it (`elementsOf`, one `getelementptr inbounds`), never held. An
identity layout has offset 0 and the row-major strides of its sizes,
likewise computed, never held. So `memref<?xE>` is `[cell, size]`,
`memref<E>` (an IORef) is `[cell]`, `memref<4x?xf64>` is `[cell, size1]`,
and `memref<?xf64, strided<[1], offset: ?>>` is `[cell, offset, size0]`.
A runtime call is given a buffer as `(cell, cell + 16, size)`, the first
byte computed at the call (§4.9, C17 §6).

Invariants:
- **One length.** A value's extents are its sizes, static in the type or
  components here; compiled code never loads `idris_rt_array.length`, and
  no pass derives a dimension from a cell (C17 §1). The cell's `length`
  is the runtime's record of the allocation, for releasing it.
- No op lowered here or by upstream changes the cell: a view changes the
  offset, sizes and strides.
- Counting a memref counts its cell alone; a view counts the cell it
  views.

Where it is implemented: `Layouts::components` and `Layouts::counted` of
every `MemRefType` of §2, a world-ordered array and a value buffer alike
(`lib/IR/Layout/Components.cpp:79-128`, U01's, C01), return exactly this
list and `[true, false, ...]`; the memory space changes no component.
Items 2 and 4 are the same rule for the strided views inside a function
(C15 §7: every buffer that crosses a call, a wrapper or a cell is the
identity layout's). `idr::isArray` is C11's (world-ordered arrays only);
`isFieldType` accepts a value buffer too, since a cell may hold one (C15
§7). `Layouts::element(E)` of a word `E` has one slot of type `E` at
offset 0 and stride equal to the data layout's size of `E` (as
`lib/IR/Layout/Layouts.cpp:161-179` computes it today).

### 4. What each memref op means after idr-lower

Two words used below. A **word** element is a builtin integer or float
type. A **slot-free** element is one whose `Layouts::counted` holds no
`true`: every word, and every element of ours without a counted
component. The rule that divides the work: upstream keeps what it lowers
and vectorizes (`memref.load` and `memref.store` of a word, and linalg
ops over words), and idr-lower lowers everything else.

#### 4.1 `memref.alloc`

`memref.alloc(%d...) : memref<S x E>`:
- `count` is the product of every extent of `S`, static ones as
  constants and dynamic ones `%d` cast to `i64`, multiplied with
  `llvm.intr.umul.with.overflow`; any overflow makes it `UINT64_MAX`
  (C17 §3). LLVM folds it for a static shape.
- `cell = llvm.call @idris_rt_array_new(count, info) : (i64, i32) -> !llvm.ptr`,
  `info` being `Layouts::element(E)->info.word()`, the call's result
  marked `noalias` (as `Arrays.cpp:108-114` today).
- The value is `[cell, %d as i64...]`.
- A non-identity layout or an `alignment` above 8 is an internal error at
  the op. An element `Layouts::element` refuses is `unsupported (layout)`
  at the op, as today (`Arrays.cpp:44-53`), the one refusal of C04's rule
  `layout` this lowering makes.

#### 4.2 `memref.global` and `memref.get_global` (0003 D23, amended)

Each `memref.global` that some `memref.get_global` reads becomes one
private constant LLVM global, `@__idr.array.<h>`, `h` the content hash of
§7 over its initial value and its type: a cell like any other, of type
`!llvm.struct<(i32, i32, i64, array<N x E>)>`, aligned to 8, holding the
header `{0, layout::CellInfo::array(stride, 0).word(), N}` and then the
dense value reshaped to rank 1 (row-major), N the number of elements
(C17 §5). Count 0 is the runtime's persistent mark. A `memref.global`
whose `alignment` is above 8 is an internal error at the
`memref.get_global`, as an allocation's is.

`memref.get_global @g` is `[llvm.mlir.addressof @__idr.array.<h>]`,
static data (`StaticData::isStatic`), so counting it emits nothing. Every
`memref.global` is erased. Upstream's `GetGlobalMemrefOpLowering`, which
writes `0xdeadbeef` as the allocated pointer
(`M/lib/Conversion/MemRefToLLVM/MemRefToLLVM.cpp:946-951`), never runs.

#### 4.3 `memref.dim`

A constant index of a static dimension is that extent as an `index`
constant; of a dynamic one, `arith.index_cast` of its size component. A
non-constant index selects among the rank's extents with `arith.select`
on the index; an index outside the rank is poison, as `memref.dim`
defines it.

#### 4.4 `memref.load` and `memref.store`

- Of a word: left for upstream. Its memref operand is the source
  materialization of §4.8, and `convert-to-llvm` lowers the op.
- Of an element of ours: the address of element `(i_0, ...)` is
  `cell + 16 + (offset + sum_k i_k * stride_k) * Layouts::element(E)->stride`,
  one `llvm.getelementptr inbounds` of `i8`. A load reads each slot of
  the element and takes no reference: idr-rc places an `idr.dup` right
  after a load of a counted element (C14 §3). A store loads the old
  element, releases each counted slot of it, and stores the new value,
  which moves in (its value comes from `idr.own.give`, C14).

#### 4.5 `memref.copy`

- A copy of a slot-free element whose two types are contiguous by
  upstream's rule (identity layout, or a static, non-empty, contiguous
  row-major shape, `M/lib/Conversion/MemRefToLLVM/MemRefToLLVM.cpp:1264-1276`)
  is one `llvm.intr.memcpy` of `count * stride` bytes, from `cell + 16 +
  offset * stride` of the source to the same of the target.
- Every other copy is `llvm.call @idris_rt_memref_copy(rank, from, to) :
  (i64, !llvm.ptr, !llvm.ptr) -> ()` (C17 §4): `from` and `to` are slots
  of the enclosing function's entry block, each holding the ranked
  descriptor `!llvm.struct<(ptr, ptr, i64, array<R x i64>, array<R x
  i64>)>` (rank 0: `!llvm.struct<(ptr, ptr, i64)>`), every field the type
  fixes written as its constant, the aligned pointer `cell + 16`, and
  every identity stride computed.
- No `memref.copy` reaches `convert-to-llvm`, so upstream's `memrefCopy`
  is never called.

#### 4.6 Views

Before the conversion, every `memref.subview`, `memref.expand_shape` and
`memref.collapse_shape` of the function is expanded by upstream's
`memref::populateExpandStridedMetadataPatterns`
(`M/include/mlir/Dialect/MemRef/Transforms/Transforms.h:65-67`) into
`memref.extract_strided_metadata`, `affine.apply` and
`memref.reinterpret_cast`. Then:
- `memref.transpose` is the source's cell and offset, its sizes
  and strides permuted by the op's permutation.
- `memref.reinterpret_cast` is the source's cell and the op's
  offset, sizes and strides, each dynamic field of the result type its
  operand cast to `i64`, or its static value as an `i64` constant.
- `memref.extract_strided_metadata` is the base buffer, a `memref<E>` of
  the source's cell, and the offset, sizes and strides as `index`
  values: constants where the type fixes them, casts of components where
  it does not, and row-major products of the sizes for an identity
  layout's strides.
- `memref.cast` is the source's fields as the result type takes them: a
  field the result fixes is dropped, a field the result leaves dynamic
  that the source fixed is its constant.

#### 4.7 Ops with no runtime form

`idr.tie_shape` (its source, operand 0), `idr.lin.enter`, `idr.lin.use`,
`idr.borrow`, `idr.share`, `idr.own.adopt` and `idr.own.give` are the
value itself.
`ub.poison` of a memref type is a null cell and poison for every other
component (`Cells.cpp:206-222`, unchanged).

#### 4.8 Linalg and the source materialization

A linalg op over words, and a word `memref.load` or `memref.store`, is
legal. A memref operand it holds is materialized from the components as
the LLVM descriptor `convert-to-llvm` reads, its allocated pointer the
cell and its aligned pointer `cell + 16`, built with upstream's
`MemRefDescriptor` over the type `Runtime::llvmTypeConverter()` gives
(the same converter and data layout `convert-to-llvm` uses,
`Runtime.h:36-39`), and cast to the memref by an
`unrealized_conversion_cast` that meets its inverse in `convert-to-llvm`.
No legal op makes a memref, so no target materialization exists. A memref
of an element of ours has no LLVM type: a legal op that held one fails
the conversion, an internal error by §2.

#### 4.9 The world-ordered ops and the buffers (C11, 0003 §13)

- `idr.array.new [sizes], fill`: each size clamped to 0 with
  `arith.maxsi`, `count` their product (rank 0: 1), the cell from
  `idris_rt_array_new` as §4.1, then every element written with `fill`:
  its slots stored at the element's address, each counted component of
  `fill` taken once per element and given up once after the loop (as
  `Arrays.cpp:82-149` today). A word element is a slot of its own, so one
  path writes every element.
- `idr.array.get` and `idr.array.set`: §4.4's slot path at the indices
  (`i64`), for every element, words included. A `get` that `moves` takes
  the array's references and leaves the counted slots null, as today
  (`Arrays.cpp:151-215`).
- `idr.buffer_load` and `idr.buffer_store`: the byte at `cell + 16 +
  offset`, loaded or stored at alignment 1.
- A `CallsRuntime` op's runtime call passes every operand's components in
  operand order (`RuntimeCalls.cpp`), a memref operand as its cell, then
  its first element `cell + 16`, then its other components: so a buffer
  is `(cell, first byte, size)`, C17 §6.

#### 4.10 `idr.nat.to_extent` (C11 §2)

The natural's word: a small word (low bit 1) is `index_cast` of the word
shifted right by one, an extent below 2^62 (the small range,
`include/idr/IR/Ranges.h:22-24`); any other word is the crash with the
op's cause, `array too large`, at the op's location
(`Runtime::crashIf`, as every guard crashes).

### 5. The counting the lowering implements (for C14)

idr-rc (U08) places `idr.dup` and `idr.drop` as these meanings require:
- a memref value is counted by its cell alone; `memref.alloc`
  and `idr.array.new` give one owned reference, every counted slot empty;
- a `memref.get_global` is static data: a dup or drop of it emits nothing;
- `memref.load` of a counted element is a plain load, with no increment:
  the `idr.dup` idr-rc puts after it takes the reference (C14 §3); a
  store of a counted element consumes its value (`idr.own.give`), and the
  lowering releases the element it overwrites; `idr.array.get` takes a
  reference of its own, and with `moves` takes the array's and empties the
  place, as today;
- `memref.copy` borrows both operands; the runtime counts what it copies
  and what it overwrites (C17 §4);
- views, `memref.cast`, `idr.tie_shape`, `idr.lin.enter`, `idr.lin.use`,
  `idr.own.adopt`, `idr.own.give` and the base buffer of
  `memref.extract_strided_metadata` are their source's cell: no
  reference of their own;
- `memref.dim` reads no element.

### 6. The runtime calls

C17 is the authority on every function's C type; idr-lower calls each by
name with the LLVM type C17 §3, §4, §6 and §7 give it. A call is built by
its callee's name (`LLVM::CallOp::create(b, loc, results, name, args)`),
and the declarations are made once the functions are converted (§8):
one `llvm.func` per function the converted code calls, in name order at
the start of the module, of the type its calls use (the coordinator's
decision of 2026-10-14, which C17 §7 follows); two calls of one
function with two types are an internal error. A declaration whose
parameter is an integer narrower than 32 bits takes `zeroext` there, and
`idris_rt_crash`, `idris_rt_crash_str` and `idris_rt_io_exit` are
`noreturn` (`Runtime.cpp:78-88`, unchanged). The call of a crash is cold
and noreturn at the call site (`Runtime.cpp:93-104`, unchanged). So no
pattern inserts into the module's symbol table, and the set declared is
the set called, decided by the conversion and nothing else.

### 7. Static data: names from content (D18, 0004 §5.3 item 3)

Every global idr-lower writes is static data: `private`, aligned to 8
unless §4.2 says otherwise, constant except a static memo cell, at the
module's location, named

`__idr.<kind>.<16 lowercase hex digits>`

where the digits are C21's C++ name of the datum's content key, the low
64 bits of its XXH3-128 hash. The kinds and their keys:

| kind | what | key |
| --- | --- | --- |
| `msg` | a crash's message bytes | the bytes |
| `str` | a static string | the bytes |
| `big` | a big outside the small range | its decimal text |
| `box` | a static box cell | the cell's content, below |
| `caf` | a static memo cell (kind `IDRIS_RT_KIND_THUNK`) | the cell's content, below |
| `array` | a constant array's cell, header and data | the initial value and type of its `memref.global`, printed |

A cell's content key is its type, its constructor and, in field order,
each field's key: a scalar's printed attribute; an unboxed sum's
constructor and its fields' keys; for a reference (a string, a big, a
box) the name of the datum it points at. A run's cell is keyed the same
way, its spine being the name of the next cell, from the tail back; so a
cell's name is a function of everything it reaches, a shared suffix is
one cell, and a memo cell is one per value, which a force needs
(`StaticData.cpp:140-146`). Keys are built from attributes alone, never
from the order anything was lowered.

Two keys whose names are equal are compared in full where the name is
interned, through C21's `ContentNames` in each worker and by the merge
across workers; unequal keys are C21's internal error naming both, never
a merge and never a widened name. The globals come after the declarations at the
start of the module, in name order. `@__idr_release_cafs` (made in every
module, `StaticData.cpp:68-79`) calls `idris_rt_caf_release` on every
`caf` in name order. `@__idr_main` and `@main` keep their names
(`Entry.cpp:115-120`).

Consumers: U07 reads that static data is private and named under
`__idr.` (0004 D41); U17's fixtures match
`__idr\.(msg|str|big|box|caf|array)\.[0-9a-f]{16}`.

### 8. One function at a time (0004 §4 stage 12)

- The layouts are the module's `Layouts`, decided before the pass and
  read frozen (`include/idr/IR/Layout.h:229-234`).
- Phase 0, serial: every `idr.func`, `idr.call` and `idr.return` becomes
  its func op under the mangled name (`FuncToFunc.cpp`, unchanged); the
  facts of §9 are read before it.
- Then the module's `func.func` ops, in module order, cut into contiguous
  runs, one per thread of the context's pool (one without threading),
  the runs in parallel (`mlir::failableParallelForEach` over them). Each
  run builds its own worker (the type converter, the target, the patterns
  and the `Runtime`) and lowers its functions in order: the matches
  (`Matches.cpp`), the view expansion (§4.6), and the conversion,
  `applyFullConversion` on the function, so an op no pattern lowers and no
  rule keeps is the compiler's error. A worker writes only inside its
  functions and into its own `Runtime`; nothing is claimed or shared.
- Then, serial: the workers' declarations and static data are merged by
  name into the module (§6, §7), every `memref.global` is erased,
  `@__idr_release_cafs` is made, and the facts are applied.
- The output is a function of the input alone: byte-identical at 1, 2
  and 8 threads (0004 §4 determinism rules; `tests/determinism`).

### 9. Identified types in the lowering (D29, D19)

idr-lower reads every fact of a data type from the value's identified
type (C01): a constructor by its name within the type, its tag (its
position), its field types, `by_name`; the sum's kind, so whether a box is
a memo sum, and a memo sum's running and forced states; the role the
registry names (the list's cons, for the string builders and
`put_list`); the number of constructors (for the tag's `range`,
`Facts.cpp:44-66`). The cells and slots come from `Layouts` keyed by
what C01 keys them by. Nothing in `lib/Conversion` looks up a data type or
a constructor in a symbol table, scans the module for a declaration, or
erases one. Whether a box goes on the stack is `idr.con`'s inherent
`stack` property (C02), read at `Cells.cpp:50-66`'s place.

### 10. What tests check (U17's fixtures, C24)

Behaviour, never op order or SSA names:
- `memref.alloc` of a rank-2 dynamic `f64` buffer is `[cell, size0,
  size1]` and calls `idris_rt_array_new` once, with the saturating product of the two sizes
  and the element's info; no `malloc`, `aligned_alloc`, `free`,
  `memrefCopy`, `_mlir_memref_to_llvm_alloc` or `3735928559`
  (`0xdeadbeef`) is in any lowered module.
- A `memref.copy` of `!idr.box` elements calls `idris_rt_memref_copy`; of
  contiguous `f64`, it is one `llvm.intr.memcpy`; of a strided `f64` view,
  `idris_rt_memref_copy`.
- A `memref.load` of a box element takes no reference; a `memref.store`
  of one releases the old element.
- `idr.nat.to_extent` of a natural that is not small crashes with `array
  too large`.
- A `memref.subview` of a `memref<?x!idr.box<...>>` leaves no memref op on
  a box element after idr-lower.
- A constant `memref.global` with `memref.get_global` gives one
  `__idr.array.` global whose leading words are `{0, info, N}` and whose
  data follows them, and the component of the constant passed to a
  function is that global's address.
- `idr.tie_shape` leaves no op.
- Every static datum's name matches §7's pattern, and two runs of one
  module print identical names; a module with two equal string constants
  in two functions holds one `__idr.str.` global.
- `idris-mlir-opt --idr-lower` on the same module at
  `--mlir-num-threads=1`, `2` and `8` prints identical output.

### 11. Consumers by lane

- U01 (C01): `Layouts::components`, `counted` and `element` and
  `isArray` as §3 states them.
- U06 (C12): §1's `dependentDialects` and description; the rows after
  idr-lower that §1 names.
- U07 (C13): §7's names and linkage of static data.
- U08 (C14): §5.
- U11 (C11): §4.7 and §4.9: what the world-ordered ops, the buffer ops
  and `idr.tie_shape` mean after idr-lower.
- U12 (C15): §2 and §4: every op its output holds has its lowering here.
- U17 (C24): §10.
- U19 (C17): §3's components, §4.1, §4.2, §4.5 and §4.9: what the
  runtime is handed, a buffer's first byte computed at the call.
