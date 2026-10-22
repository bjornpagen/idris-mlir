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
- **Runtime helpers** in L11's `Spec.Runtime.Helpers`, which the
  lowering calls as `helper::<name>`:
  - `outOfMemory`: no parameters, never returns;
  - `arenaChunk(cursor: ptr, bytes: i64) -> ptr`;
  - `arenaOpen(sizeHint: i64) -> ptr`;
  - `arenaClose(arena: ptr)`;
  - `arenaCloseWithDrops(arena: ptr)`;
  - `arenaNoteOwned(arena: ptr, slot: ptr)`;
  - `homeArena(site: i32) -> ptr`;
  - `stackTop() -> ptr` and `stackReset(mark: ptr)`.
- **The program-symbol prefix (C62):** every program function is
  `idr.<mangle(name)>`, so it is never a C identifier, `main` or
  `llvm.*`. The runtime's reserved `__idr$` stays distinct.
