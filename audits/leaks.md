<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Leaks: what leaked, why the verifier let it, and a representation in which it cannot be written

Taken on 6f774119 (arm64 macOS, `build/dev`), 2026-10-19. Every count below
was measured on that build; the reproducers and fixtures are now tests
(see Status), and `audits/leaks/` is gone.

## Status (2026-10-19, the ownership lane)

What §3.9 planned, as it landed:
- Step 1, the memo exchange: done. `idr.memo.run` in the dispatch, its
  lowering, bufferization and flow edges; `memo.enter`, `memo.settle`,
  `forceTakesCaptures`, `caseFieldType` and `labelRead` deleted. L1 is
  unrepresentable: a label's field read any way but the exchange is a view
  by its type (tests/verify-sources).
- Step 3, lifetimes: done for heap and frame. The grade's lifetime, a
  cell's own, the rules of the frame said once (IR/Lifetimes.h), the
  function verifier holding them, idr-rc-stack their inference; the escape
  analysis deleted. L2 closed: tests/lazy-list-frame (live cells 0, no
  crash), linear-string-iterator passes, tests/verify-frame refuses each
  shape. The verifier's tail rule is a self call (or a self call in tail
  position but for a context); a call in tail position of another function
  on the cycle is the inference's alone, since the lowering never makes a
  tail call that may reach the frame, so a miss there costs stack depth,
  not memory.
- Step 2: R1 (an owned value's declared source, OwnedWalk::make, with
  Idr_TakesReference on idr.dup and idr.array.get) and R2 (a write into
  memory that exists before the op is an exchange, an overwrite, which
  idr.array.set and memref.store now declare, or a hole), in the flow
  edges' verifier. R3 in the owned walk: a view read out of memory that
  may be written (a memoizing label's field of a memo cell, a buffer's
  element) is alive until that memory, as it was made (viewRoot), is
  written again by any op whose effects write it; loaded()'s rule (the one
  use of a loaded element is the idr.dup right after it) is deleted
  (tests/verify-sources). Within a loop's body a view read before the loop
  and used after a write of an earlier iteration is not yet seen: the walk
  runs a body once. The memo-state memory resource that would replace
  builtStateHolds is open.
- Step 4: persistence done (idris_rt_persist_held after every force; the
  CAF release, `__idr$release$cafs`, its runtime function and the live-cells
  marks deleted, and the harness's `live-cells` case field with them).
  Static is a view in the verifier: static data its op makes from nothing
  a count reaches (ownership::madeStatic) is, at a view's grade, a view
  that lives as long as the program, and what is read from it a view of
  it, so consuming one takes an idr.dup (static-view-settled is refused,
  tests/verify-sources); at an owned grade (poison, a small big) it stands
  for a value and holds no reference. The verifier no longer asks
  isStatic's search of the definition chain. Still open: the lifetime in
  the grade (`static` beside heap and frame), which would delete isStatic
  from counting (Classes' Phantom/Constant/StaticRead), narrowing, reuse
  and the program verifier.
- Step 5: an unreached path ends in ub.unreachable (Commit.cpp).
- Tests: T1, the lazy fuzzer (harness/Lazy.idr, tests/fuzz-lazy): CAF
  streams, a static lazy list, streams and lazy lists made at run time,
  chains of memo cells, each read once, twice, in rounds of a loop or by
  two calls, compiled with the checked runtime, each case against its
  model, every run ending with live cells 0. T2 (verify-frame,
  verify-sources). T3 (actions-skip-programs: no action skipped too, every
  program linked with the checked runtime). T4 holds by the verifier after
  every pass. T5, the checked runtime (libidris_rt_checked.a,
  runtime/Alloc/Alloc.h; tests/runtime-checked): a cell that dies keeps its
  memory with its header marked, and a count operation on it, or on a
  stack cell below the frame of the operation, ends the program naming
  which. T6's measurement is open.
- Memo captures are exclusive where every init moved an exclusive value
  in and no read of the field as a view is used (exclusivity's Captures);
  the char-list and split-prefixes tests still find shared values before
  them (audits/bugs.md).

## 0. In short

- Every program of `tests/` (228 fixtures, 819 case runs), every `near`
  variant (45, 89 runs) and every benchmark that compiles (23, at small
  inputs) ends with the live cells its case expects. The leaks that
  `audits/bugs.md` and SUMMARY §5.10 list are gone, with one exception.
- That exception is no counting bug: it is a dangling pointer. A cell that
  `idr-rc-stack` puts in a frame is settled into a memo cell that outlives
  the frame. The static lazy list "leaks" n-2 cells only because later
  calls overwrite the dead frame. The same cause **crashes** a lazy list
  forced twice (SIGSEGV for every input of 2 or more), a new bug.
- Two tests record leaks as expected (`live-cells` marks:
  memo-shared-stream 3, every-types-export 2). These are knots through a
  CAF's forced value. `idr-knots`, which AGENTS.md calls a total refusal,
  takes arrays to be the only cells written after they exist, but memo
  cells are written too.
- All three classes, and the one fixed this week, come from one blind spot.
  The owned stage counts references in SSA values. Memory is treated as
  immutable trees that the runtime releases when a cell dies. Every place
  where memory is **written after it exists** (memo cells, array and
  buffer elements) or **outlives what made it** (frame cells, static data)
  is handled by a side rule or an analysis, and the verifier does not see
  it.
- §3 proposes the representation:
  - reference conservation in the verifier: every owned value has one
    declared source;
  - every write into existing memory is an exchange that says what the
    place held, with `idr.memo.run`, an update-shaped region op, in place
    of `memo.enter`/`memo.settle`;
  - a lifetime in the grade (`static`, `heap`, `frame`), in place of the
    escape analysis's verdict and `isStatic`'s definition-chain search;
  - persistence of what static data holds, in place of
    `idris_rt_caf_release`.

## 1. The leak classes

### 1.1 Status at 6f774119

| class | reproducer | status | root cause |
| --- | --- | --- | --- |
| L1 memo captures taken over by a side rule | `thunk-consumes-list` (was 1000003), sortedmap, every-show; fixtures `capture-*.mlir` | fixed for the shapes the rule names (4108916a, 4603d0cb, 6f774119); the rule admits double releases (§2, G1) | the force's take-over of its label's captures lives in `forceTakesCaptures`/`caseFieldType`/`labelRead`, not in the IR |
| L2 frame cell settled into a longer-lived memo cell | `audits/leaks/static-lazy-list.idr` (live cells 3), `linear-string-iterator.idr` (3), `shared-lazy-list.idr` (exit 139) | **open**: leak and crash | escape analysis: a write into a part of an existing cell takes that cell's lifetime from its uses, not from where it came from |
| L3 knots through a CAF's forced value | `tests/memo-shared-stream` (3), `tests/every-types-export` (2) | **open**, recorded as expected in `live-cells` | static memo cells hold counted values, and `idr-knots` does not count memo cells as written after they exist |
| L4 the earlier list (SUMMARY §5.10, bugs.md B2–B4, the do-let, Int-twice and trace reductions, IORef/IOArray, st-sum, nat-large, the benchmarks) | each named test and reproducer, rerun | fixed: live cells 0 everywhere | drops not placed on paths that write memory: a forced memo cell's value, an IORef element on write (SUMMARY's reading) |

How it was measured:
- Each test was compiled into a scratch copy with `tools/compile.sh` and
  its packages, and each case was run with `IDRIS_RT_LIVE=1`. The
  `constant-stack` cases were skipped.
- Every case not listed above ends with the count its case expects.
- 14 fixtures did not compile, none of them for a leak:
  - most for frontend refusals, or because the harness generates their
    source and the sweep compiled only `Main.idr`;
  - one, every-interfaces-export, and the benchmarks regex-dna and
    regex-redux, for the owned verifier's `'idr.cell.init' op builds an
    exclusive value of a field that may be shared`. That is the verifier
    refusing counting's output, which is the verifier doing its job.
- The six-line reductions from bugs.md all end with 0: the do-let used
  twice (stdin 4611686018427387904), `the Int (cast line)` twice, `trace`
  of a line, `traverse` in Either over `[0]`, `[-1]` and `[3]`, and a
  string used by three `putStrLn`.

### 1.2 L2, precisely

`static-lazy-list.idr` is
`putStrLn (show (pack (toList (from 5))))` over a hand-written
`from : Nat -> LazyList Char`. No library is needed. idr-optimize folds
`from 5` into static data: a cons whose tail is a **static memo cell**
`@Main.from.delay(4)`. The root passes it to a specialization of toList's
foldr lambda. Here is that specialization after `idr-rc-exclusive`,
shortened:

```mlir
idr.func @"foldr...lam.spec"(%arg0: !idr.own<LazyList>) -> ... {
  case @"::"(...) {
    %2:2 = idr.unpack %arg0 @"::"            // %2#1: the static memo cell
    %4 = idr.match (borrow %2#1) {
    case @Main.from.delay(%f0: !idr.own<!idr.nat>) {
      idr.memo.enter (borrow %2#1)
      ... default(...) {
        %15 = idr.cell.stack : !idr.cell<!idr.box<lazy$.sum>, @Main.from.delay>   // the next tail
        %r  = idr.cell.init %15 (%n_5)
        %c  = idr.con @"::"(%14, %r)          // LazyList is an unboxed sum: %c holds the frame cell
        idr.yield %c }
      %9 = idr.dup (borrow %7)
      idr.memo.settle (borrow %2#1), %9       // the frame cell is stored into the static cell
      ...
      idr.call @"foldr...lam"(%11, %7)        // and walked on by the general lambda
```

`idr-rc-stack` placed the label cell of the next tail in the frame:
- `idr.memo.settle` stores it, inside `"::"(c, cell)`, into the memo cell
  read from `%arg0`.
- That memo cell is static, so it lives until exit. For a list read at run
  time it is a heap cell the caller holds.
- After the return, the static cell's forced value points into the dead
  frame. The general lambda had settled each later tail (heap cells) into
  the frame cell, and each of those cells holds one reference, from the
  cell before it.
- show's calls then reuse that stack region (their closures are frame
  cells too). At exit `__idr$release$cafs` releases the static cell's
  forced value: a cons whose slot now holds whatever the frame was
  overwritten with. The chain from the frame cell is never released:
  n − 2 cells, the 3 for "hello" and the 8 for ten characters that
  bugs.md measured.

Evidence:
- The same `.mlirbc` through `idris-mlir-opt --idr-target --idr-pipeline`
  with `--mlir-debug-counter=idr-stack-cell-count=0` (no frame cells)
  ends with live cells 0 for `static-lazy-list`, `linear-string-iterator`
  and the variants that print twice.
- In `shared-lazy-list.idr` (`from (cast line)` traversed twice), stacking
  **only** that one cell (`idr-stack-cell-skip=0,idr-stack-cell-count=1`)
  gives exit 139, and every other single cell gives the right output.
- The leak's size depends on what overwrites the frame. With only the memo
  cell stacked, `static-lazy-list` happens to end with 0. Without `show`
  (`putStrLn (pack ...)`) nothing overwrites the slot and the run looks
  clean. It is undefined behaviour that shows up as a leak or a crash.
- bugs.md's reading ("show's lazy steps meet it") is wrong. The list is
  forced by toList, and show only overwrites the frame.

The bug is in the escape analysis (`lib/Analysis/Escapes.cpp`):
- It is backward: a value escapes when something it flows to escapes.
- `memo.settle`'s edge moves the value into a part of the cell operand,
  and `Solve::flow` gives the value the cell's own lattice element. That
  element is computed from the cell's uses: a match, `memo.enter`, the
  settle itself, none of which escapes. So it is bottom.
- But the cell was **read out of a parameter**. Its lifetime is the
  caller's, which a backward analysis never asks about. A write into memory
  that exists before the op is a write into memory the frame does not
  own.
- The analysis was patched for an unsound case before: c2ad4aa7's trmc
  tail call, which built a stream's cells in one frame slot. That patch,
  like this bug's fix would be, fixed one shape.
- The owned verifier knows nothing of frame cells beyond refusing an
  exclusive one. So it accepts `frame-cell-settled.mlir` and
  `frame-cell-returned.mlir`.

### 1.3 L3, precisely

In `fibs = 0 :: 1 :: addS fibs (tail fibs)`, `fibs`'s tail is a static
memo cell S:
- Its force builds `1 :: M2`, a heap memo cell. M2 captures `fibs`, which
  is static. Forcing M2 runs `addS fibs (tail fibs)`, and `tail fibs` is
  S's forced value, a **counted** heap cons, which the new cells capture.
- The forced cells capture cells forced before them, which hold them. At
  exit `idris_rt_caf_release` drops S's forced value, but the knot's own
  counts keep 3 cells (2 for every-types-export's `powers`).
- `idr-knots` (Passes.td) refuses only a type graph cycle through an
  array, "the one cell written after it exists". A memo cell is written
  after it exists too, so the refusal AGENTS.md calls total is not.
- A type-graph rule cannot simply add memo cells. Every recursive lazy
  type (Stream, LazyList) is such a cycle, and only a value that reaches
  its own CAF's forced value knots.

### 1.4 L1, as fixed

The memo sum's dispatch, `<sum>.force` (`Defunctionalize/Forces.cpp`):
- It matches the cell's state. In a label's case it marks the cell
  Running (`memo.enter`), calls the label, and stores the value
  (`memo.settle`).
- Settle writes the forced state over the label's captures without
  releasing them. So the force must *own* the captures and drop them. That
  fact is `idr::forceTakesCaptures` (Grades.cpp). `caseFieldType` gives
  such a case's fields the owned grade, and `Classes::classOf` gives them
  `Class::Owned` through `labelRead`.
- Inlining turned the dispatch's match into `idr.field` reads, which the
  rule did not cover (fixed in 4603d0cb). Then the captures were read as
  views, given references by dups, and the cell's own references were
  written over. A million cells leaked in thunk-consumes-list.
- 6f774119 then had to order the rule before `isStatic`, after a pass
  moved a static capture into a loop.

Each fix widened a rule that recognizes where captures are read. None made
the take-over a fact of the IR.

### 1.5 Not a leak, but met on the way

The crash after main (bugs.md; bounded-method-own, array-of-arrays,
io-loop-through-helper, directory-listing, files-roundtrip, buffer-ops)
still happens at 6f774119, and live cells are 0 when it does:
- It is nondeterministic. One binary exits 0 on one run and 139 on the
  next, from the same directory.
- It happens with frame cells off and with them on. So it is not L2, and
  bugs.md's "not a frame cell" stands.
- A double release fits "a write into memory the allocator holds". The
  conservation rule below (R1, R2) is what would refuse one statically.
  Until then, it needs the checked runtime of §4.

## 2. Why the verifier did not catch them

The owned stage's verifier (`lib/IR/Verify/Owned*.cpp`) checks that each
reference an SSA value holds is consumed exactly once on each path. What it
does not check:

- **G1, no conservation.** `OwnedWalk::make` and `enter` give every result
  and region argument whose grade is owned a reference of its own,
  whatever made it. Whether it came from a consumed operand, a dup, an
  allocation, or nowhere is never asked. So a capture read owned twice
  (`capture-taken-twice.mlir`) or read owned with no force
  (`capture-taken-without-force.mlir`) verifies, and each is a double
  release at run time. The verifier did catch the pre-4603d0cb shape
  (`capture-read-as-view.mlir`), but only because `caseFieldType` is a
  *type* rule of `idr.field` and `idr.match`. The side rule is the check,
  and it is wrong in the other direction.
- **G2, memory writes are not edges the walk counts.** `memo.enter`
  declares no edges. `memo.settle` declares only the value moving in, not
  what the place held (the captures, written over). `idr.array.set` and
  `memref.store` declare the new element. The release of the old one is
  `writeElement`'s, in the lowering (`Conversion/Elements.cpp`), by the
  convention that every element always holds a reference. The verifier
  sees none of what a write removes from memory. Both historical L4
  causes, "a forced memo cell's value, an IORef element on write", are
  places written over.
- **G3, no lifetimes.** A frame cell's box is `!idr.own<!idr.box<T>>`,
  the type a heap cell has. Whether it may leave its frame is the escape
  analysis's verdict, kept only in which op made the cell (`cell.stack`
  or `cell.new`), and the verifier never asks. L2, `frame-cell-settled`,
  `frame-cell-returned`.
- **G4, static is a definition-chain search, not a fact.**
  `ownership::isStatic` makes a value untracked when any value up its
  definition chain is pure and reads no reference, and anything read from
  it too. Two consequences:
  - The forced value of a static memo cell is read from static data but
    is a counted heap value, so a view of it can be consumed without a
    dup (`static-view-settled.mlir` verifies: two holders, one reference).
  - Staticness changes when a pass rewires a chain (6f774119: a capture
    became non-static once idr-tail-loops moved its match into a loop).
    The runtime has the same exception: "everything a persistent object
    points to is persistent, except a static memo cell" (`idris_rt.h`).
- **G5, the knot refusal has the wrong model.** It is G2 at the type
  graph: memo cells are written after they exist, and the analysis says
  only arrays are. L3.
- **G6, references conjured on dead paths.** idr-rc-commit replaces an
  owned operand in an exclusive position, on a path the solver never
  reached, by `ub.poison` of the exclusive type, and drops the original.
  The poison is an owned-typed value that holds nothing and that the
  verifier calls static. The path is dead, and the IR states a reference
  that is not there.

## 3. The proposed representation

The principle: **a reference lives in an SSA value or in a place in
memory, and every op that moves one between them declares the move.** The
verifier checks conservation for both, and the types say how long memory
lives.

### 3.1 The grade gets a lifetime

`Grade` becomes (quantity, permission, lifetime), with lifetime ordered
`static ≤ heap ≤ frame`:
- `static`: everything reachable is persistent (count 0). It lives until
  exit, and dup and drop of it lower to nothing. Constants, everything read
  from a static value, and everything a static memo cell holds (§3.4).
- `heap`: counted; it lives as long as a reference to it does. This is the
  default, and the printer omits it: `!idr.own<T>` keeps its spelling.
- `frame`: may reach a cell of the current frame (`idr.cell.stack`). It
  dies when the frame does, or when the loop iteration that made it ends.

The rules, each declared beside the op in ODS:
- `idr.cell.stack`'s box is frame. A constructor or closure holding a
  frame field or capture is frame. This is the shape of
  `Idr_LinearWhenACaptureIs`, which already computes a closure's quantity
  from its captures.
- A field read from a value has that value's lifetime.
- Values meet at a join at the larger lifetime, through `idr.share`. Its
  meaning becomes "forget what the grade proved": exclusivity, as today,
  and now also staticness or heapness. One op, no runtime form.
- `static` is a view's lifetime. Consuming a static value takes an
  `idr.dup`, as consuming any view does. This deletes `Class::Phantom`,
  `Class::Constant`, `Class::StaticRead` and `isStatic`'s search: static is
  in the type, so no pass that moves a value can change it.

A parameter's lifetime is the escape summary, written into the signature
as borrow inference writes the permission. A parameter of lifetime frame
may be given a frame value. Inside the callee it obeys the frame rules,
since its argument may die when the caller's frame does.

### 3.2 Memo cells: the force is an exchange

`idr.memo.enter` and `idr.memo.settle` are replaced by one op shaped like
`idr.array.update` and `idr.element.update` (`UpdateOpInterface`), which is
memref.generic_atomic_rmw's shape:
- the place's contents move out into the region's arguments;
- the region runs while the place is empty, which for a memo cell is the
  Running state a re-entrant force crashes on;
- the region's first yielded value moves into the place, and the rest
  leave the op.

```mlir
idr.func @T.force(%t: !idr.q<many, borrow, !idr.box<!T>>) -> !idr.own<!idr.str> {
  %r = idr.match %t : !idr.q<many, borrow, !idr.box<!T>> -> (!idr.own<!idr.str>) {
  case @lbl(%s: !idr.q<many, borrow, !idr.str>) {     // a view, alive until the cell is written
    %v = idr.memo.run %t @lbl : !idr.q<many, borrow, !idr.box<!T>> -> !idr.own<!idr.str> {
    ^bb0(%c: !idr.own<!idr.str>):                      // the capture, moved out: the cell is Running
      %x = idr.call @lbl(%c) : (!idr.own<!idr.str>) -> !idr.own<!idr.str>
      %x2 = idr.dup (idr.borrow %x)
      idr.yield %x2, %x                                // %x2 moves in: Forced; %x leaves
    }
    idr.yield %v : !idr.own<!idr.str>
  }
  case @running() { idr.crash "a suspension forced itself"  ub.unreachable }
  case @forced(%f: !idr.q<many, borrow, !idr.str>) { %d = idr.dup %f  idr.yield %d }
  }
  return %r : !idr.own<!idr.str>
}
```

What this makes true:
- The captures are owned **because `memo.run` moved them out of the
  cell**. That is an SSA fact, and nothing else can give them.
- A label's fields read any other way (a match's case, `idr.field` after
  inlining) are views, at `fieldType`, with no memo case.
- A view of a label's field is alive until the next write of that cell's
  place (rule R3 below), so using it after the force is refused.
- The forced value is consumed by the yield into the place. `memo.run`'s
  ODS requires the moved-in value owned and of lifetime heap or static,
  never frame (R4).
- Enter-without-settle, settle-without-enter, and a settle twice cannot be
  written: the region is the only Running interval.
- A label run by name has no `memo.run`. The dispatch calls it with its
  captures as views, and its cell is never written, so its views never
  die. No `byName` test is left in any typing rule; it remains only where
  the dispatch is built.
- `memo.run` declares `MemRead`/`MemWrite` on a memo-state resource of
  `%t`, and `idr.tag`, `idr.match` and `idr.field` of a memo sum declare
  `MemRead` on it. Today `idr.tag` is `Pure` with the comment "a cell never
  changes while a reference to it is live", which is false for a memo
  cell. `builtStateHolds` is the rule that stands in for the missing
  effect.

Lowering is today's two header writes around the region (MemoCells.cpp).
At its entry, the region arguments are loads of the label's fields.

### 3.3 Places: every write into existing memory says what the place held

A memory place is a field of a cell, an element of an array or buffer, a
memo cell's state, or a hole. Each op that writes one is one of:
- **init of empty memory**: `idr.cell.init` of a fresh cell, `array.new`'s
  fill, and `dest.write` of a hole, whose `!idr.dest` is linear by type, so
  the hole is written exactly once.
- **exchange**: `memo.run`, `array.update`, `element.update`. What moves out
  is the region's arguments.
- **overwrite with release**: `array.set` and `memref.store` of a counted
  element declare a `Release` edge of the old element in their flow edges
  (FlowOps.cpp, and the external model for memref.store). That is the
  `runtime.dec` `writeElement` already lowers, now stated where the
  verifier reads it.
- **take of a dying cell**: `idr.take` moves the fields out of a cell
  whose box it consumes.

An op that writes an existing place and declares none of these is refused.
`memo.settle` was exactly such an op, and it is deleted.

### 3.4 Static data: persistence in place of a counted exception

Today the runtime says "everything a persistent object points to is
persistent, except a static memo cell, whose forced value is counted and
released by `idris_rt_caf_release`". The proposal deletes the exception:
- The store of `memo.run` into a cell of count 0 **persists** the value:
  it walks the value and sets each counted cell it reaches to count 0,
  stopping at persistent cells, and takes them out of the live count.
- Which cells are static is a run-time fact: the dispatch is shared by
  static and heap cells. So this is the one branch, in the lowering of the
  store into the place, and it is the runtime's own count-0 rule.
- Then everything reachable from static data is static, at run time and in
  the grade, as §3.1 says. A view of a static memo cell's forced value is
  static, which is now true.
- `idris_rt_caf_release`, `__idr$release$cafs` and their declaration
  (`IdrRuntime.td`, Symbols, Entry, Runtime) go.
- No counted cell can then reach a CAF's forced value, so no knot runs
  through one (L3).
- A counted memo cell's captures exist before the cell, and its forced
  value is computed from them and from globals: arrays, which idr-knots
  refuses on the type graph, and CAFs, which are now persistent. So the
  only counted cells written after they exist that can close a knot are
  arrays, and the knot refusal is total as AGENTS.md says.
- memo-shared-stream and every-types-export end with live cells 0, and
  their `live-cells` marks are deleted.

The cost is a decision: what a forced CAF reaches stays until exit. The
forced value already does today, so the new cost is only the label captures
inside it that a later force would have released. That is GHC's retention
of CAFs, and here the CAF's meaning (a constant of the program) is the
type's. The measurement in §4 (T6) bounds it on the benchmarks that have
CAF streams.

### 3.5 The verifier

The owned walk gains one state per place, and four rules. The fixtures in
`audits/leaks/` are the refusals each rule must give.

- **R1, conservation of SSA references.** An owned result or region
  argument must have exactly one declared source in its op's flow edges:
  - `Fresh`: `cell.new`, `cell.stack` and `cell.recycle`, through their
    cell's init, and `own.adopt`;
  - `idr.dup` of a live view;
  - a flow from a consumed operand, whole (`share`, `lin.*`, a forwarded
    value) or out of its part (`take`, `unpack`);
  - the move-out of an exchange's place (`memo.run`, the updates).

  `make` refuses any other owned value: `capture-taken-twice` (the
  `idr.field`), `capture-taken-without-force` (the case binding). This
  replaces the `labelRead` class, `caseFieldType`, and the Carried role:
  `own.give`'s result is a flow from its consumed operand, and its one use
  moves it into a place.
- **R2, conservation of places.** A write into a place that exists before
  the op declares what the place held (§3.3), or is refused.
- **R3, views of places die at writes.** A view read from a place is
  alive while its owner holds a reference **and** until the next write of
  that place of that value. The places are a label's fields, a buffer's
  elements and an array's elements. This replaces `loaded()`'s "the one
  use of a loaded element is the idr.dup right after it" with the reason
  behind it, and gives memo labels the same rule.
- **R4, lifetimes.** A value of lifetime frame is never:
  - returned;
  - given to a parameter of lifetime heap;
  - moved into a place that exists before the op (R2's writes, and
    `cell.init` of a heap cell);
  - forwarded by the terminator of a repetitive region;
  - an operand of a call in tail position.

  These are the escape analysis's rules, checked on types: `frame-cell-*`
  and L2 are refused. `idr-rc-stack` becomes the inference of the least
  lifetimes these rules allow. It still decides which cells go in the
  frame, but it can no longer be wrong unnoticed, because the verifier
  runs after it.

Also:
- **Static is a view** (§3.1). `static-view-settled` is refused because it
  consumes a view.
- **Dead paths end.** idr-rc-commit ends a block its solver never reached
  with `ub.unreachable` in place of a poison reference and a drop (G6).

### 3.6 What upstream gives, and what it does not

- `RegionBranchOpInterface`, and memref.generic_atomic_rmw's shape: the
  exchange is an op whose region sees the empty place, as idr's updates
  already are.
- `MemoryEffects` with resources: `cell.stack` already allocates on
  `AutomaticAllocationScopeResource`. A memo-state resource gives the
  force's writes and the state's reads their order without `Pure` lying.
- Ownership-based buffer deallocation is the model for R1:
  - it declares how each op affects ownership through interfaces, and it
    refuses an op whose effects are unknown;
  - its function-boundary ABI (an argument is never owned, a result always
    is, a result never aliases an argument) is a declared rule, which our
    parameter grades refine.

  What it does not do is the part we need: it has no model of a buffer
  stored in memory. Places (R2, R3) and lifetimes in memory (R4) are ours
  to declare.
- The memref memory space is the precedent for putting where memory lives
  in the reference's type. `#idr.world` already does this for arrays, and
  the lifetime is the same idea for cells.

### 3.7 What is deleted

| deleted | where | made dead by |
| --- | --- | --- |
| `forceTakesCaptures`, `caseFieldType` | Grades.cpp/.h; uses in OpsMatch.cpp, OpsCon.cpp (FieldOp build and verify), Placement.cpp (`gradeViews`) | memo.run's region arguments (§3.2) |
| `labelRead` and its owned class | Classes.cpp | R1 |
| `idr.memo.enter`, `idr.memo.settle`, their flow edges, bufferize model and lowering | IdrClosureOps.td, FlowOps.cpp, Bufferize/Data.cpp, Releases.cpp, MemoCells.cpp, Forces.cpp, Symbols.cpp (`builtStateHolds`'s enter/settle test) | memo.run |
| `ownership::isStatic` and its static branches | Uses.cpp, Owned.cpp, Classes.cpp, Values.cpp, Reuses.cpp, Program.cpp, Narrow/Facts.cpp (11 files) | the static lifetime |
| `Class::Phantom`, `Constant`, `StaticRead` | Classes.cpp, Placement.cpp `plan` | the static lifetime |
| `idris_rt_caf_release`, `__idr$release$cafs`, the runtime header's static-memo exception | Counting.cpp, idris_rt.h, IdrRuntime.td, Symbols, Entry.cpp, Runtime.cpp | persistence (§3.4) |
| the poison and drop on an unreached path | Commit.cpp `meet` | `ub.unreachable` |
| `loaded()`'s dup-right-after rule, the Carried role, `takesCarried` | OwnedOps.cpp, Owned.cpp | R1, R3 |
| `live-cells` marks | tests/memo-shared-stream, tests/every-types-export | L3 closed |
| the escape analysis as a separate verdict | Escapes.cpp becomes lifetime inference, its frame rules checked by R4 | the frame lifetime |

### 3.8 States made unrepresentable

- An owned capture with no force that moved it out: R1, `memo.run`.
- A memo cell written over references it holds (the L1 leak):
  `memo.settle` no longer exists, and R2.
- A forced value stored twice, a settle without entering, an enter
  without settling: the region.
- A frame cell in memory that outlives its frame, or returned (L2): R4.
- A view of a static value consumed as a reference: static is a view.
- A counted value held by static data, so a knot through a CAF (L3):
  persistence.
- A reference standing on a path that never runs: `ub.unreachable`.

### 3.9 Scope

Five steps. Each lands with `make test`, `make test-idr` and
`make test-unit`, and the order keeps every step verifiable:

1. **Memo exchange**: memo.run, dispatch, lowering, bufferize model; delete
   enter/settle and the capture rules. About 10 C++ files and 4 fixtures
   (effects-memo-label, lower-force-view, lower-to-llvm,
   lower-static-thunk); 600–900 lines changed.
2. **R1–R3 in the walk**: Owned.cpp, OwnedOps.cpp, OwnedRegions.cpp, and
   the flow edges of array.set and memref.store; about 300 lines. It will
   surface counting's latent mismatches as internal errors, which is the
   point; budget for fixing them in placement.
3. **Lifetimes**: the Grade, QType's syntax, the lifetime rules in ODS,
   Escapes into inference, Stack.cpp, R4; 800–1200 lines and the rc-stack
   fixtures. Measure `numStackCells` before and after. A cell the typed
   rules leave on the heap is a performance change, never a refusal.
4. **Static and persistence**: the grade, `idris_rt_persist`, the
   deletions in §3.7; about 500 lines over 15 files and the two
   `live-cells` marks.
5. **Commit's dead paths**: about 30 lines.

In all, 30–40 files and 2.5–3.5k lines. Steps 1 and 3 each close an open
class by themselves (L1's holes, then L2), so they go first.

## 4. Test plan, as properties

- **T1, no live cells.** Every program the generators make (Gen/Fuzz,
  extended with lazy structures: CAF streams, lazy lists forced once and
  twice, a force inside a loop, a memo cell shared across calls), run on
  generated inputs with `IDRIS_RT_LIVE=1`, ends with `live cells 0` and
  exit 0. No `live-cells` mark exists: a knot is refused, never expected.
- **T2, the verifier refuses each class.** Each fixture of
  `audits/leaks/*.mlir` fails `idris-mlir-opt` with the rule that names it:
  - `capture-taken-twice`, `capture-taken-without-force`: R1;
  - `capture-read-as-view`, rewritten with memo.run (the view used after
    the run): R3;
  - `frame-cell-settled`, `frame-cell-returned`: R4;
  - `static-view-settled`: consumes a view.

  Each has a near neighbour that verifies: the same op with the reference
  taken by a dup, or the cell on the heap.
- **T3, skipped optimizations change nothing.** For any program and any
  skip set of the actions `idr-stack-cell`, reuse and inlining
  (`--mlir-debug-counter`; Actions.h says a skipped action leaves valid
  IR), stdout, exit status and `live cells 0` are the same. This is no
  oracle outside the program: it is the compiler's own claim that the
  actions only make code faster. It would have caught L2 (exit 139 against
  the right output) and c2ad4aa7.
- **T4, every stage verifies.** The owned verifier runs after every pass
  from `idr-rc-cells` to `idr-lower` on every program of the suite and the
  generators (PassInstrumentation): a pass that leaves an unbalanced count
  fails where it ran.
- **T5, a checked runtime.** A runtime mode that poisons a freed cell's
  header and traps a count operation on a poisoned or stack cell after its
  frame. Leaks are what live cells see; double releases and dangling
  pointers are what this sees. Run under it, the crash after main (§1.5)
  names its first bad write.
- **T6, persistence's cost is measured.** The peak RSS of the benchmarks
  and of memo-shared-stream before and after §3.4. The decision stands
  unless a CAF-heavy program's peak grows; that number is the record.
