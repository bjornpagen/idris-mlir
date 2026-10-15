# U19 — The runtime: the allocation and copy hooks, immortal constants, one length

## Permitted outcome
1. Mandatory. `idris_rt_array_new(uint64_t count, uint32_t info)` (C17 §3):
   the count is unsigned and is the element count itself, with no clamp in
   the runtime; when the element holds objects (objs above 0) every byte
   of the elements is 0, so every object slot is NULL from the cell's
   birth; the size check and its crash message stay as today.
2. Mandatory. `idris_rt_memref`, the descriptor's three leading words, is
   declared in `idris_rt.h` (C17 §2), and `runtime/Alloc/Arrays.cpp`
   asserts its size and field offsets against LLVM's ranked descriptor.
3. Mandatory. `idris_rt_memref_copy(int64_t rank, const idris_rt_memref
   *from, const idris_rt_memref *to)` (C17 §4): the counted, strided copy
   that `memref.copy` lowers to, taking the element from the target cell's
   header, incrementing each copied object slot before releasing the one
   it overwrites, a row of slot-free elements with unit strides as one
   `memmove`.
4. Mandatory. The five buffer entry points take each buffer as `(cell,
   first byte, size)`, the first byte computed by idr-lower at the call,
   and address through the first byte (C17 §6). `idris_rt_buffer_at` is gone
   from the C ABI and from the runtime.
5. Mandatory. `idris_rt.h` states the cell behind every memref, the one
   length (the cell's element count, read only by the runtime), a
   constant as one static cell (a persistent header, then its data, as for
   every cell), and no entry point writing a header whose count is 0 (C17
   §1, §5). The comment's claims that an
   array "is never exclusive" and that the cell is `idr.array.new`'s go.
6. Mandatory. The runtime still builds in the typecheck build: every
   changed unit passes `check-units.py`, and
   `tests/toolchain/runtime-api/rc.c` (U18's) still compiles against the
   new header unchanged (its `idris_rt_array_new(5, ...)` is a valid call).

No consumer adaptation lies outside `runtime/`: the runtime's callers
(idr-lower, the C tests) are other lanes' and code against C17.

## Owner / exclusive writes
`runtime` (ownership.json's one entry: every path under `runtime/`).

Changed:
- `runtime/idris_rt.h`: the array cell's comment, `idris_rt_memref`,
  `idris_rt_array_new`'s prototype and comment, `idris_rt_memref_copy`,
  the five buffer prototypes, `idris_rt_buffer_at` removed.
- `runtime/Alloc/Arrays.cpp`: the allocation, the descriptor's asserts,
  the copy, the file comment.
- `runtime/Io/Buffer.cpp`: the three buffer functions on the first byte;
  `idris_rt_buffer_at` removed.
- `runtime/Io/Bytes.cpp`: the two transfers on the first byte.

Unchanged and not to be touched: every other file under `runtime/`, among
them `runtime/Rc/Freeing.cpp` (it reads `length` only for a dying cell
whose elements hold objects, which stays true), `runtime/Rc/Rc.h`,
`runtime/Rc/Counting.cpp`, `runtime/Alloc/Alloc.h`, `runtime/Alloc/Cells.cpp`,
`runtime/Alloc/Classes.cpp`, `runtime/Io/Io.h` and `runtime/CMakeLists.txt`
(no source is added or removed). New files: none.

**Excluded:**
- `foreign/idr/lib/Conversion`, `foreign/idr/include/idr/Conversion`
  (U10): the calls of these hooks, the descriptor built for the copy, the
  constant's static data, the clamp of a negative size and the
  saturating product.
- `foreign/idr/include/idr/IR/Layout.h`, `foreign/idr/lib/IR/Layout`,
  `foreign/idr/include/idr/IR/IdrIOOps.td` (U01): the info word's builder,
  a memref's components, the buffer ops.
- `foreign/idr/include/idr/IR/IdrArrayOps.td`, `foreign/idr/lib/IR/OpsArrays.cpp` (U11).
- `foreign/idr/lib/Transforms/Bufferize` (U12): `allocationFn`, `memCpyFn`,
  `bufferAlignment`.
- `tests/toolchain/runtime-api`, `tests/lib` (U18); `tests/idr` (U17).
- `CMakeLists.txt` at the root, the target entries (coordinator); `PINS.md` (U16).
- `third_party/snmalloc` (vendored, unmodified).

## Read first
- `contracts.md`: C17 (this lane's, whole), C16 (a memref's components;
  which copies reach the runtime), C15 (the hooks' IR), C11 (the
  world-ordered allocation and buffer ops).
- `proposals/0003-typed-apl/README.md`: §1 "The runtime" and fact 5 (the
  length held twice), §4.5 (D17, the counted copy), §8 (D18, `allocationFn`
  and `memCpyFn`), §12 (D23, D40: immortal constants), §13 (D24:
  world-ordered arrays), §15 (the runtime row), §21 item 2.
- `proposals/0004-compile-time/README.md`: §4 stages 12 and 13, §5.3 items
  2 and 3 (the runtime's names).
- `runtime/idris_rt.h:27-73` (the header and info word), `:152-165` (the
  array cell), `:173-246` (allocation and counting), `:299-337` (buffers).
- `runtime/Alloc/Arrays.cpp:1-32`, `runtime/Alloc/Alloc.h:12-38`,
  `runtime/Alloc/Cells.cpp:21-39`, `runtime/Alloc/Blocks.cpp:11-27`.
- `runtime/Rc/Rc.h:18-62`, `runtime/Rc/Counting.cpp:10-42`,
  `runtime/Rc/Freeing.cpp:20-39, 86-113` (how a dying array releases its
  elements, and why `length`'s top bits must stay free).
- `runtime/Io/Buffer.cpp:1-38`, `runtime/Io/Bytes.cpp:46-60`,
  `runtime/Io/Io.h:13-60`.
- `runtime/CMakeLists.txt:23-89, 104-171` (sources, profile, warnings:
  `-Wpedantic`, `-Wcast-align`, `-Wconversion`, `-Wsign-conversion` from
  the root `CMakeLists.txt:263-280`).
- `foreign/idr/lib/Conversion/Arrays.cpp:82-148` (today's allocation call
  and fill), `foreign/idr/lib/Conversion/RuntimeCalls.cpp:25-36, 81-124`
  (operands flattened into a call), `foreign/idr/lib/Conversion/Runtime.cpp:65-91`.
- `foreign/idr/lib/IR/Layout/Layouts.cpp:161-179`,
  `foreign/idr/lib/IR/Layout/CellInfo.cpp:42-55` (the element's info word).
- `.toolchain/build/llvm-project/mlir/lib/Conversion/MemRefToLLVM/MemRefToLLVM.cpp:1150-1280`
  (how `memref.copy` lowers, and the descriptor it passes);
  `.toolchain/build/llvm-project/mlir/lib/ExecutionEngine/CRunnerUtils.cpp:75-130`
  (`memrefCopy`, the shape this copy takes);
  `.toolchain/build/llvm-project/mlir/include/mlir/Dialect/MemRef/IR/MemRefOps.td:580-607`;
  `.toolchain/build/llvm-project/mlir/include/mlir/Dialect/Bufferization/IR/BufferizableOpInterface.h:252-262, 336-346, 396-402`.
- `third_party/snmalloc/src/snmalloc/ds/sizeclasstable.h:504-512` (a
  block's alignment).
- `tests/toolchain/runtime-api/rc.c:212-250` (the C test that builds an
  array, U18's).

## Fixed decisions
- The cell layout is unchanged: `idris_rt_array` is the 8-byte header and a
  `uint64_t length`, 16 bytes, then the elements in a cell the runtime
  allocated. `info` is `idris_rt_info(elementBytes, objs,
  IDRIS_RT_KIND_ARRAY)`.
- One length: `length` is the cell's element count, written once at the
  cell's making and read only by the runtime (the release of a dying
  counted cell). A memref's shape is its descriptor's; the runtime never
  compares a passed size with `length`. Neither is derived from the other.
- Object slots are never garbage: `idris_rt_array_new` zeroes the
  elements' bytes with one `memset` exactly when `objs > 0`. Not through
  snmalloc's zeroing allocation: it memsets the whole size class anyway
  (`third_party/snmalloc/src/snmalloc/mem/corealloc.h:43-47`), so it buys
  nothing and adds a second allocation entry.
- `count` is `uint64_t`; the runtime's `length < 0 ? 0` clamp is deleted,
  since a negative Idris size is the caller's to clamp (C16), and two
  clamps are one rule held twice.
- The descriptor struct is `idris_rt_memref { idris_rt_array *allocated;
  char *aligned; int64_t offset; }`, the sizes then the strides following
  it in memory as `int64_t` words. No flexible array member (C++ under
  `-Wpedantic` refuses it). Its asserts are in `Alloc/Arrays.cpp`:
  `sizeof(idris_rt_memref) == 3 * IDRIS_RT_WORD_BYTES`, `offsetof` of
  `aligned` 8 and of `offset` 16.
- The copy reads the element's bytes and objs from
  `to->allocated->header.info` and takes no info argument: the cell
  carries its element's description, so no call can disagree with it.
- The copy's per-element rule: for each object slot `i`, `idris_rt_inc`
  of `from`'s slot, then `idris_rt_dec` of `to`'s slot; then `memmove` of
  the element's bytes. `memmove`, not `memcpy`, because the same view is
  an allowed pair.
- The copy walks the dimensions by recursion, one level per dimension,
  the innermost level copying a row: one `memmove` of the row when the
  element has no object slot and both innermost strides are 1, else
  element by element. Rank 0 is one element. A size of 0 makes its level
  copy nothing, with no test before the walk.
- The copy lives in `runtime/Alloc/Arrays.cpp`, beside the allocation:
  the one file that knows the array cell's layout. It counts through the
  C ABI's `idris_rt_inc` and `idris_rt_dec` and includes nothing of
  `Rc/`.
- The buffer entry points take each buffer as `(idris_rt_array *cell,
  char *bytes, int64_t size)`, `const char *` where the runtime only
  reads, the cell and the size unnamed in the definitions. Their order
  follows the op's operands, a buffer taking the three (C17 §6).
- Every file keeps its `// PIN(runtime-quarantine) — see PINS.md` line and
  its SPDX lines.

## Inputs
- C16: a buffer reaches a runtime call as `(ptr cell, ptr cell +
  sizeof(idris_rt_array), i64 size)`, idr-lower computing the first byte, since no idr value
  carries it; idr-lower calls `idris_rt_array_new` with the clamped,
  saturating product of the sizes and the element's info word; it lowers
  `memref.copy` to `idris_rt_memref_copy` except a contiguous copy of
  slot-free elements, building each view's descriptor with the aligned
  pointer the cell plus its header; it writes a constant as one static
  cell, a persistent header and then its data.
- C15: One-Shot emits `memref.alloc` with no alignment above 8 and
  `memref.copy` for its copies.
- C11: the world-ordered allocation and the buffer ops keep their operand
  order (`handle, buffer, offset, count`; `src, src_offset, len, dst,
  dst_offset`; `buffer, offset, str`; `buffer, offset, len`).

## Outputs
- C17, the runtime hooks: `idris_rt_array_new`'s new signature and
  meaning, `idris_rt_memref`, `idris_rt_memref_copy`, the constant
  header's layout and the persistent guarantee, the five buffer
  signatures, `idris_rt_buffer_at`'s removal, the table of by-name hooks
  with their LLVM types. Consumers: U10 (calls them), U12 (its hooks'
  IR lowers to them), U01 (the info word), U11 (operand order), U17 (the
  lowering fixtures' call types), U18 (the runtime-api test), U07 (the
  names).

## Implement
- `runtime/idris_rt.h`:
  - Rewrite the comment above `idris_rt_array` (`:152-161`) to C17 §1 and
    §5: the cell behind every memref; tag, objs and `length`; elements
    after the struct in every cell; the one length, written once,
    read only by the runtime when a counted cell dies; the shape is the
    descriptor's; an IORef is a cell of one element; a constant is one
    static cell, a persistent header (count 0) and then its data; no entry
    point writes a header whose count is 0.
  - After `idris_rt_array`, declare `idris_rt_memref` with its comment
    (C17 §2).
  - Replace `idris_rt_array_new`'s prototype and comment (`:208-212`) with
    C17 §3's.
  - Declare `idris_rt_memref_copy` after it, with C17 §4's meaning.
  - Replace the prototypes and comments of `idris_rt_io_write_bytes`,
    `idris_rt_io_read_bytes` (`:299-312`), `idris_rt_io_buffer_copy`,
    `idris_rt_io_buffer_set_string` and `idris_rt_io_buffer_get_string`
    (`:325-337`) with C17 §6's; one shared sentence says a buffer arrives
    as its cell, its first byte and its size, and only the first byte is
    read. Delete `idris_rt_buffer_at` and its comment (`:319-324`).
- `runtime/Alloc/Arrays.cpp`:
  - `idris_rt_array_new`: the size check as today on the unsigned count;
    `newCell`; `length = count`; `memset(array + 1, 0, bytes)` when
    `idris_rt_info_objs(info) != 0`, with a comment that says why (a store
    and the cell's death release what a slot holds).
  - The descriptor asserts, `#include <stddef.h>` for `offsetof`.
  - In an anonymous namespace: the sizes after a descriptor
    (`reinterpret_cast<const int64_t *>(view + 1)`), the assignment of one
    element (inc, dec, `memmove`; slots read through `static_cast<void
    **>(static_cast<void *>(...))`, as `Rc/Freeing.cpp:88-90` does, which
    `-Wcast-align` accepts), and the recursive walk over dimensions.
  - `extern "C" void idris_rt_memref_copy(...)`: reads the element from
    `to`'s cell, starts the walk at `aligned + offset * bytes` of each
    view. Arithmetic in `int64_t`, converted to `ptrdiff_t` and `size_t`
    with explicit casts for `-Wconversion` and `-Wsign-conversion`.
  - The file comment: the cell behind every memref, its allocation and
    the counted copy between two views of cells.
- `runtime/Io/Buffer.cpp`: the three functions take C17 §6's parameters
  and use `bytes + offset`; `buffer_copy` stays `memmove`, `set_string`
  `memcpy`, `get_string` `idris_rt_str_from_bytes`. The file comment
  drops "the address of a span" (no such entry point is left).
- `runtime/Io/Bytes.cpp`: the two transfers take C17 §6's parameters and
  pass `bytes + offset` to `rt::io::writeBytes` and `readBytes`; the
  negative-result-to-0 rule stays.
- Failure paths: a too-large count and exhausted memory crash as today;
  the copy has no failure path (its preconditions are the caller's, and
  nothing it is given can make it fail).

## Delete
- `idris_rt_buffer_at`: its declaration in `runtime/idris_rt.h:319-324`
  and its definition in `runtime/Io/Buffer.cpp:15-17`.
- The clamp `length < 0 ? 0 : ...` in `runtime/Alloc/Arrays.cpp:23` and
  the sentence "a negative length is 0" in `idris_rt.h:208`.
- In `idris_rt.h:152-161`, the attribution to `idr.array.new` and the
  sentences that elements are read and written "in the order of the world,
  so the array itself is never exclusive" and about a read that "takes
  that element's reference over": those are the world-ordered ops'
  lowering rules (C16), not facts of the cell.
- The runtime has no array-loop entry point to delete: the ArrayLoops and
  ArrayLoopReads lowerings (U10's) never called the runtime beyond
  `idris_rt_array_new`, and a search of `runtime/` finds no loop entry
  point. 0003 §15's "~90 lines" of runtime is this lane's rewrite of
  `Alloc/Arrays.cpp` and `Io/Buffer.cpp`, not a deletion.

## NOT TO DO
- No second copy entry point (a contiguous-only copy, a word-only copy, a
  copy that takes an info word or an element size): one copy, the cell
  describing its element.
- No allocation entry point beside `idris_rt_array_new` (an aligned
  allocation, a zeroing flag, a separate "constant array" constructor):
  constants are static data idr-lower writes (U10), and alignment beyond
  `IDRIS_RT_WORD_BYTES` is not offered.
- No runtime check that a descriptor's sizes fit its cell, that `from` and
  `to` are disjoint, or that a count matches `length`: these are the
  compiler's invariants, and a runtime guard would hold them twice.
- No change to `runtime/Rc/Freeing.cpp`, `Rc/Rc.h` or `Rc/Counting.cpp`;
  no inline counting helper moved into a header for the copy.
- No `memrefCopy` symbol, and no upstream runtime library: a program links
  nothing of MLIR's ExecutionEngine (AGENTS.md, static linking).
- No edit to `tests/toolchain/runtime-api` (U18) or to `tests/idr` (U17),
  even though their calls name these functions; report what they must
  check.
- No edit to the lowering (U10) to "keep the build green": the coordinator
  integrates; a caller with the old signature is U10's to change.
- No new `runtime/` source file and no change to `runtime/CMakeLists.txt`.

## Tempting partial solutions
- Keeping `idris_rt_array_new(int64_t length, ...)` and its clamp so the
  old lowering still links. Rejected by acceptance 1: the clamp is the
  caller's rule held twice, and C17 fixes an unsigned count.
- Zeroing only in the copy's target, or teaching the copy that a fresh
  target holds garbage. Rejected by acceptance 2 and 4: every object slot
  is NULL from birth, so the copy, a compiled store and the cell's death
  all read a valid slot, one rule.
- Passing the element's info word to `idris_rt_memref_copy`. Rejected by
  acceptance 3: the cell already carries it, and a second copy of a fact
  can disagree with the first.
- Releasing the target's old slot before incrementing the source's.
  Rejected by acceptance 4's same-view case: a slot shared by both would
  reach count 0 and be freed in the middle of its own copy.
- Computing a buffer's address as `cell + 1` and dropping the first-byte
  parameter. Rejected by acceptance 5: C17 §6 fixes the parameter lists,
  and the runtime reads the first byte it is given rather than deriving
  it a second time.
- Moving `idris_rt_buffer_at` into `Io/Io.h` as a helper. Rejected by
  acceptance 5: with the first byte passed, an address is `bytes +
  offset`, and a helper for that is a name for nothing.
- Copying the old ArrayView descriptor logic into the runtime to rebuild a
  descriptor from a cell. Rejected by acceptance 3: the runtime reads the
  descriptor it is given and never derives one.

## Acceptance
1. Source: `idris_rt.h` declares `idris_rt_array *idris_rt_array_new(uint64_t
   count, uint32_t info);`, and `Alloc/Arrays.cpp` contains no comparison
   of the count with 0 and no `int64_t length` parameter.
2. Source: `idris_rt_array_new` calls `memset` over exactly the elements'
   `count * elementBytes` bytes when `idris_rt_info_objs(info) != 0`, and
   writes nothing past `length` when it is 0. With a C caller (U18's to
   write, C17 §3): an array of five 16-byte elements with one object slot
   each reads NULL in every slot before any store, and `idris_rt_dec` of it
   leaves `idris_rt_live_cells` where it was before the allocation.
3. Source: `idris_rt_memref_copy(int64_t, const idris_rt_memref *, const
   idris_rt_memref *)` is declared and defined; it reads `info` only from
   `to->allocated->header`; it reads elements only through each view's
   `aligned`, `offset`, sizes and strides, never through `allocated + 1`.
   `Alloc/Arrays.cpp` asserts the descriptor's size and offsets.
4. Behaviour (U18's test, stated here as the property): copying a 2x3 view
   of boxes onto a fresh cell leaves every source box with one more
   reference and the target's six slots equal to the source's; copying
   onto a live cell releases each overwritten box once; copying a view
   onto itself leaves every count as it was; a copy with a size of 0
   touches nothing; a rank-0 copy assigns one element; a copy of `f64`
   between a column view (stride 3) and a contiguous cell moves the
   values in row-major order.
5. Source: no `idris_rt_buffer_at` anywhere in `runtime/`; the five buffer
   functions' parameter lists are exactly C17 §6's, and each addresses
   through its `bytes` parameter.
6. `python3 proposals/0004-compile-time/check-units.py runtime/Alloc/Arrays.cpp
   runtime/Io/Buffer.cpp runtime/Io/Bytes.cpp runtime/Alloc/Cells.cpp
   runtime/Rc/Counting.cpp runtime/Rc/Freeing.cpp` reports every unit
   checked and none failing (the last three include `idris_rt.h` and
   prove the header still parses for them).
7. Review: every changed comment states why the code is as it is now, in
   the repository's voice, and cites no document, decision, lane or rule
   number.

## Stop and return
The deliverable is the four changed files under `runtime/` meeting
acceptance 1 to 7, and the handoff the common obligations define. Report,
without stopping other work:
- that the C tests in `tests/toolchain/runtime-api` (U18) have no check of
  zeroed slots or of `idris_rt_memref_copy`, with acceptance 2 and 4 as
  the properties to add;
- that `tests/idr/lower/buffer.mlir:26` (U17) checks today's
  `idris_rt_io_buffer_copy` call type, which C17 §6 changes;
- any caller under `foreign/idr` (U10) still calling the old
  `idris_rt_array_new` or buffer signatures, by path and line, as the seam
  C16 closes;
- any disagreement between C17 and C15, C16 or C11 found while
  implementing, with the evidence and the change proposed.
