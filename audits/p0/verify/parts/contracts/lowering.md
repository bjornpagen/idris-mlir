<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Contract: lowering seams (L21, 2026-10-21)

- **The word kind (C40), in L04's `Layout.h`:**
  `layout::Component { mlir::Type type; layout::Word word; }`, with
  `enum class layout::Word : uint8_t { Uncounted, Cell, MaybeCell, Big, Any }`
  replacing `bool counted`.
  - `Runtime::inc` and `dec` take components, never a bare `ValueRange`:
    `runtime.inc(b, loc, components, values)` and
    `runtime.dec(b, loc, layout::Word::Cell, cell)`.
  - The lowering picks `incCell`, `incMaybeCell`, `incBig` or `incAny`
    (and `dec`, and the `Run` forms) by the word.
- **The counting ops' lowering** (`dup`, `drop`, `token.free`,
  `match_unique` to `scf.if` on `is_unique`, `take_into`) is L21's, in
  `lib/Conversion/Lower/Counting.cpp`; `Conversion/Counting.cpp` goes.
- **Runtime helpers** in L11's `Spec.Runtime.Helpers` (final, L21), which
  the lowering calls as `helper::<name>`:
  - `framePush(bytes: i64) -> ptr`: the next frame's bytes on the thread's
    frame stack, contiguous within chunks.
  - `framePop(frame: ptr)`: the stack back to `frame`; the chunks past it
    are given back, keeping one spare (C63). A frame is laid out as a
    cell (L04's `Layouts::cells` of a FrameStack member), header count 0.
  - `arenaOpen(sizeHint: i64) -> ptr`: a chain's first cursor; null when
    the hint is 0.
  - `arenaChunk(cursor: ptr, bytes: i64) -> ptr`: where a cell of `bytes`
    goes in `cursor`'s chain (null starts a new chain). It returns the
    cursor itself when its chunk has room; the next cursor is the result
    plus `bytes`.
  - `arenaClose(cursor: ptr)`: every chunk of the chain given back (null:
    none).
  - `stackReset(mark: ptr)`: the chunks past the one `mark` is in given
    back.
  - `outOfMemory()`: never returns.
  - Not used, and dropped: `homeArena` (the homes are a thread-local array
    the lowering makes as a static datum), `stackTop`,
    `arenaCloseWithDrops`, `arenaNoteOwned`. A lexical cell's owned fields
    are not dropped by the lowering, so L05's decide step keeps such a
    site counted until that drop protocol is designed.
- **The program-symbol prefix (C62):** every program function is
  `idr.<mangle(name)>`, so it is never a C identifier, `main` or
  `llvm.*`. The runtime's reserved `__idr$` stays distinct.
