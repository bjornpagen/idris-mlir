## C17 Runtime hooks

Producer: U19. The one authority is `runtime/idris_rt.h`, the runtime's C
ABI; this section fixes what changes in it and what the other lanes code
against. Definitions live in `runtime/Alloc/Arrays.cpp` (allocation and
copy), `runtime/Io/Buffer.cpp` and `runtime/Io/Bytes.cpp` (buffers).
Consumers: U10 (idr-lower calls every hook below and writes the constant
cells), U12 (its `allocationFn` and `memCpyFn` produce the IR that U10
lowers to these hooks), U01 (`layout::CellInfo::array` builds the info word
the cell carries), U11 (the world-ordered allocation and buffer ops whose
operands become these calls' arguments), U17 (lowering fixtures that name
these symbols and their types), U18 (`tests/toolchain/runtime-api`, which
links the runtime and calls them from C), U07 (the names, §8).

### 1. The array cell, the memory behind every memref

Layout unchanged (`runtime/idris_rt.h:152-165`), 16 bytes then the
elements:

```c
typedef struct idris_rt_array {
  idris_rt_header header; /* count, info */
  uint64_t length;
} idris_rt_array;
```

- `header.info` is `idris_rt_info(elementBytes, objs, IDRIS_RT_KIND_ARRAY)`:
  tag the size of one element in bytes (below `IDRIS_RT_TAG_LIMIT`,
  `idris_rt.h:106`), objs the number of object slots each element starts
  with. It is exactly `layout::Element::info.word()`, which
  `Layouts::element` builds through `CellInfo::array(stride, objs)`
  (`foreign/idr/lib/IR/Layout/Layouts.cpp:161-179`,
  `foreign/idr/lib/IR/Layout/CellInfo.cpp:42-55`). An element is laid out
  as idr-lower lays out a cell's fields, object slots first, so an element
  with objs above 0 is a multiple of `IDRIS_RT_WORD_BYTES` (8,
  `idris_rt.h:79`) long.
- In every cell, a constant's included, the elements start right after the
  struct: element 0 is at `(char *)cell + sizeof(idris_rt_array)`.
- Every memref value's allocated pointer is an `idris_rt_array`: a cell from
  `idris_rt_array_new` (§3), or a constant's static cell (§5). An IORef
  is a cell of one element (rank 0).

**One length.** `length` is the number of elements the cell holds, a fact
of the allocation. It is written once, when the cell is made (by
`idris_rt_array_new`, or as a constant's static cell), and only the
runtime reads it: to release each element's object slots when a counted
cell dies (`runtime/Rc/Freeing.cpp:32-39, 98-113`). The shape of a memref
value is its descriptor's sizes and strides (§2), which idr-lower holds as
SSA components (C16); a view (subview, cast, reshape) has its own sizes
over the same cell. Compiled code never loads `length`, no pass derives a
dimension from a cell, and no runtime entry point takes a size and
compares it to `length`. Invariant: for every `idris_rt_array`, `length`
equals the number of elements right after it.

**Object slots are never garbage.** From the moment a cell exists, every
object slot of every element holds NULL, an odd word or a counted
reference. `idris_rt_array_new` makes that true at birth (§3); a compiled
store into an element releases what the slot held and moves the new value
in; a move out of an element leaves NULL (the `moves` read); the cell's
death releases every slot.

### 2. The descriptor

New in `idris_rt.h`, after `idris_rt_array`:

```c
/* A memref's descriptor, as LLVM lays it out for a memref of rank R. */
typedef struct idris_rt_memref {
  idris_rt_array *allocated; /* the cell, a constant's static cell too */
  char *aligned;             /* (char *)allocated + sizeof(idris_rt_array) */
  int64_t offset;            /* of the view's first element, in elements */
} idris_rt_memref;
/* followed in memory by int64_t sizes[R], then int64_t strides[R], in elements */
```

- It is the prefix of the struct LLVM gives a ranked memref descriptor,
  `!llvm.struct<(ptr, ptr, i64, array<R x i64>, array<R x i64>)>`, under the
  data layout of both targets (every field one 8-byte word, no padding);
  `runtime/Alloc/Arrays.cpp` asserts `sizeof(idris_rt_memref) == 3 *
  IDRIS_RT_WORD_BYTES` and the offsets of its three fields. No flexible
  array member: the runtime is C++ under `-Wpedantic`, and the sizes follow
  the struct as a string's bytes follow `idris_rt_str`.
- `aligned` is always `(char *)allocated + sizeof(idris_rt_array)`, for a
  constant too (§5). No idr value carries it separately (C16): idr-lower
  computes it wherever it builds a descriptor or a buffer argument (§6).
  The view's element `(i_0, ..., i_{R-1})` is at `aligned + (offset +
  sum_k i_k * strides[k]) * elementBytes`.
- Only `idris_rt_memref_copy` reads a descriptor in memory. idr-lower
  builds it the way upstream's `memref.copy` lowering builds the descriptor
  it passes to `memrefCopy`
  (`.toolchain/build/llvm-project/mlir/lib/Conversion/MemRefToLLVM/MemRefToLLVM.cpp:1194-1256`:
  the ranked descriptor promoted to a stack slot), with every field the
  type fixes written as its constant.

### 3. The allocation hook

```c
idris_rt_array *idris_rt_array_new(uint64_t count, uint32_t info);
```

LLVM type `!llvm.func<ptr (i64, i32)>`. Changed from `(int64_t length,
uint32_t info)`.

- A new cell of `count` elements with the header `{1, info}` (kind
  `IDRIS_RT_KIND_ARRAY`), `length = count`, counted as a live cell as
  `idris_rt_cell` counts one (`idris_rt_live_cells`).
- When `idris_rt_info_objs(info) > 0`, every byte of the elements is 0, so
  every object slot is NULL; otherwise the elements are not written.
- Element 0 is aligned to `IDRIS_RT_WORD_BYTES` (8) and to nothing larger:
  snmalloc aligns a block to the largest power of two dividing its size
  class (`third_party/snmalloc/src/snmalloc/ds/sizeclasstable.h:504-512`),
  every class is a multiple of 8 (`SNMALLOC_MIN_ALLOC_STEP_SIZE=8`,
  `runtime/CMakeLists.txt:158`), and the elements start 16 bytes in. An
  element type whose alignment exceeds 8 is no element of a cell.
- `count` is unsigned and is the element count itself: the runtime clamps
  nothing. A negative Idris size is the caller's to clamp to 0 (the
  world-ordered allocation's meaning, C11, lowered by C16); the product of
  a memref's sizes that overflows 64 bits is passed as `UINT64_MAX`.
- A count whose cell (`sizeof(idris_rt_array) + count * elementBytes`)
  does not fit `size_t` ends the process through `idris_rt_crash` with
  "idris runtime: array too large\n"; `UINT64_MAX` always does, for an
  element of at least one byte. Exhausted memory ends it with "idris
  runtime: out of memory\n". Both messages are today's
  (`runtime/Alloc/Arrays.cpp:15-18`, `runtime/Alloc/Blocks.cpp:13-16`).
- The result is fresh memory: idr-lower marks the call's result `noalias`,
  as today (`foreign/idr/lib/Conversion/Arrays.cpp:108-114`).

Callers: idr-lower, for every `memref.alloc` (what One-Shot's
`allocationFn` emits, C15) and for the world-ordered array allocation
(C11). `memref.alloc` reaches idr-lower with no `alignment` attribute, or
one of at most 8 (C15 sets `bufferAlignment` accordingly); a larger one is
idr-lower's internal error (C16).

### 4. The copy hook

```c
void idris_rt_memref_copy(int64_t rank, const idris_rt_memref *from,
                          const idris_rt_memref *to);
```

LLVM type `!llvm.func<void (i64, ptr, ptr)>`. New. Its name is
`memref.copy`'s, as an op with `CallsRuntime` names its function
(`foreign/idr/include/idr/IR/IdrDialect.h:100-116`).

- The meaning of `memref.copy` for every element type: each element of the
  view `from` is assigned to the same place of the view `to`, in row-major
  order. Both views have rank `rank` and the sizes of `from`; their element
  type is the same.
- The element is the one `to->allocated->header.info` describes: its tag
  the element's bytes, its objs the object slots it starts with. The cell
  carries the element's description, so the call passes none, and a call
  cannot disagree with its cell. (A constant is never a target: it is not
  writable, so One-Shot copies before any write to it.)
- Assignment of one element: each of its object slots in `from` gains a
  reference (`idris_rt_inc`), then the slot it overwrites in `to` loses
  one (`idris_rt_dec`), then the element's bytes are moved. The increment
  comes first, so an element assigned onto itself keeps its counts. A
  target cell fresh from `idris_rt_array_new` holds NULL slots, whose
  release does nothing: one rule for a fresh target and a live one.
- An element with no object slot is its bytes alone; where both innermost
  strides are 1, a row of them is one `memmove`.
- Precondition (the caller's, One-Shot's analysis): the two views are
  disjoint or the same view. The same view is left as it was.
- Any size 0 copies nothing. Rank 0 copies one element.

Callers: idr-lower lowers every `memref.copy` (One-Shot's `memCpyFn` emits
`memref.copy`, C15) to a call of `idris_rt_memref_copy`, except a copy
whose element has no object slot and whose two types are both contiguous
by upstream's rule (identity layout, or a static, non-empty, contiguous
row-major shape: `MemRefToLLVM.cpp:1264-1276`), which stays upstream's
`llvm.intr.memcpy`. No program references upstream's `memrefCopy`, which
lives in a shared library no program links.

### 5. Immortal constant headers

A constant array (`memref.global` with a dense initializer, words or
floats only, 0003 D23 as amended: the header in front of the data, as for
every cell) is one static object that idr-lower writes (C16), laid out as
every other cell:

- the header, a static `idris_rt_array`:
  `{ {0, idris_rt_info(elementBytes, 0, IDRIS_RT_KIND_ARRAY)}, N }`, N the
  number of elements;
- right after it, the data, its elements row-major.

One LLVM global of type `!llvm.struct<(i32, i32, i64, array<N x E>)>`, E
the element's type, aligned to 8; an element's alignment is at most 8
(§3), so the data starts at offset `sizeof(idris_rt_array)` with no
padding. The constant's descriptor has `allocated` = the object's address
and `aligned` = that address plus `sizeof(idris_rt_array)`, as for every
cell (§2). Count 0 is the runtime's persistent mark (`idris_rt.h:29-32`):
`idris_rt_inc` and `idris_rt_dec` do nothing, `idris_rt_is_unique` is
false, `idris_rt_free_cell` does nothing, and it never dies, so its
`length` is never read. No runtime entry point writes a header whose
count is 0, so the whole object may be emitted constant.
`idris_rt_memref_copy` reads a constant's elements through `aligned`, as
it reads any cell's.

### 6. The buffer entry points

A `Data.Buffer` is a world-ordered `memref<?xi8>`. A buffer operand of a
`CallsRuntime` op reaches the runtime as three arguments, in order: the
cell (`idris_rt_array *`), its first byte (`(char *)cell +
sizeof(idris_rt_array)`, which idr-lower computes at the call, since no
idr value carries it, C16), the size (`int64_t`). The runtime addresses
through the first byte it is given; it reads neither the cell nor the
size, since `idr.check.range` tests every span before the call. The
functions keep their names (`idris_rt_` and the op's name), and their
parameters follow the op's operands in operand order, a buffer taking the
three:

```c
int64_t idris_rt_io_write_bytes(int64_t handle, idris_rt_array *cell, const char *bytes,
                                int64_t size, int64_t offset, int64_t count);
int64_t idris_rt_io_read_bytes(int64_t handle, idris_rt_array *cell, char *bytes,
                               int64_t size, int64_t offset, int64_t count);
void idris_rt_io_buffer_copy(idris_rt_array *src_cell, const char *src, int64_t src_size,
                             int64_t src_offset, int64_t n, idris_rt_array *dst_cell,
                             char *dst, int64_t dst_size, int64_t dst_offset);
void idris_rt_io_buffer_set_string(idris_rt_array *cell, char *bytes, int64_t size,
                                   int64_t offset, const idris_rt_str *str);
const idris_rt_str *idris_rt_io_buffer_get_string(idris_rt_array *cell, const char *bytes,
                                                  int64_t size, int64_t offset, int64_t n);
```

LLVM types, in order: `i64 (i64, ptr, ptr, i64, i64, i64)`, the same for
read, `void (ptr, ptr, i64, i64, i64, ptr, ptr, i64, i64)`, `void (ptr,
ptr, i64, i64, ptr)`, `ptr (ptr, ptr, i64, i64, i64)`. Their meaning is
today's (`idris_rt.h:299-337`): `buffer_copy` is `memmove`, the transfers
go through `rt::io::writeBytes` and `readBytes`.

`idris_rt_buffer_at` is deleted from the C ABI and the runtime: no compiled
code calls it (`tests/idr/lower/buffer.mlir:1` checks its absence), and
with the first byte passed, an address in a buffer is `bytes + offset`.

### 7. The hooks idr-lower calls by name

idr-lower declares the runtime functions after conversion, from what the
functions call, in name order (C16 §6). Two kinds of call:

1. Every op with `CallsRuntime`: `idris_rt_` followed by the op's name
   without `idr.`, dots as underscores (`IdrDialect.h:100-116`); an op
   whose signedness or operand type picks the function adds `_s`, `_u` or
   `_f64` (`foreign/idr/lib/Conversion/RuntimeCalls.cpp:32-36, 81-101`);
   its parameters are its operands' components in order, flattened
   (`RuntimeCalls.cpp:25-30`). Unchanged; the buffer ops of §6 follow it.
2. By name, with their LLVM types:

| function | LLVM type | status |
| --- | --- | --- |
| `idris_rt_cell` | `ptr (i64, i32)` | unchanged |
| `idris_rt_array_new` | `ptr (i64, i32)` | count unsigned, slots NULL (§3) |
| `idris_rt_memref_copy` | `void (i64, ptr, ptr)` | new (§4) |
| `idris_rt_inc`, `idris_rt_dec`, `idris_rt_free_cell`, `idris_rt_caf_release` | `void (ptr)` | unchanged |
| `idris_rt_crash` | `void (ptr, i64)`, noreturn | unchanged |
| `idris_rt_start` | `i32 (ptr, i64, i32, ptr)` | unchanged |
| `idris_rt_main_return` | `void ()` | unchanged |
| `idris_rt_str_alloc` | `ptr (i64, i64, i32)` | unchanged |
| `idris_rt_str_put_char` | `i64 (ptr, i64, i32)` | unchanged |
| `idris_rt_str_put_str` | `i64 (ptr, i64, ptr)` | unchanged |
| `idris_rt_str_bytes_length`, `idris_rt_str_length` | `i64 (ptr)` | unchanged |
| `idris_rt_str_is_ascii` | `i32 (ptr)` | unchanged |
| `idris_rt_io_put_str` | `void (ptr)` | unchanged |
| `idris_rt_io_put_char` | `void (i32)` | unchanged |

The functions that never return are `idris_rt_crash`, `idris_rt_crash_str`
and `idris_rt_io_exit` (`foreign/idr/lib/Conversion/Runtime.cpp:86-88`),
unchanged.

### 8. Invariants other lanes rely on

- Every symbol a program reaches in the runtime is `idris_rt_` followed by
  a C identifier, with no dot: the prepared runtime internalizes every
  other (`foreign/idr/lib/Driver/Prepare.cpp:103-106`), and 0004 §5.3's
  namespace grouping puts every dotless name in one group.
- The runtime has no static constructor, no C++ runtime reference and no
  assembly (`runtime/check-archive.sh`); the new copy adds a `memmove`
  call only, one of the calls code generation makes on every target
  (`runtime/CMakeLists.txt:235`).
- No runtime entry point loops over an array's index space on the
  compiled code's behalf except `idris_rt_memref_copy`; the runtime has no
  other array operation (it never had a loop entry point: a search of
  `runtime/` finds none).

### 9. What this contract does not decide

The IR of the hooks' callers: the `allocationFn`, `memCpyFn` and
`bufferAlignment` of One-Shot (C15); a memref's components, the
descriptor idr-lower builds, the static data's names and linkage, and the
product of sizes (C16); the world-ordered ops and their operand order
(C11). This contract states what those must hand the runtime.
