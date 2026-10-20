<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Known compiler bugs, by lane

The bugs known on main, each under the lane that owns its fix (lanes:
tools/lanes/README.md). An entry gives the bug, the test or reproducer
that shows it, its cause when known, and what is owed; it goes when its
fix lands, the commit naming it. A bug in a pinned upstream is recorded
here only until its patch is carried: then its report is
`upstream/<bug>/README.md` and its status `PINS.md`'s.

**Status, main at c4d38e9b (2026-10-19).** `make check` 34/34. No full
suite has run on it: `make test`, `make test-idr` and
`make test-mlir-tools` are refused by the pin check until the shared
toolchain carries upstream 62 and 63 (4dde6b7f). The last full counts
(arm64 macOS, before the ownership lane's static-lifetime cutover, which
c4d38e9b took out) were `make test` 446-449 of 478, `make test-idr`
331-332 of 333, `make test-mlir-tools` 30 of 30. An entry marked *not
rerun since* X was last seen at X; the first full suite after the
toolchain rebuild confirms or strikes it.

## ownership

- **split-prefixes shares the lists its test says are new** (with the
  control lane). The test expects `span[Char]` and `splitAt[Char]` to take
  only exclusive cells. The lists reach them through `entry`'s do block,
  whose delayed statements are memo cells (the `(>>)` lambda's second
  action, `Main.entry.case0.case0.delay`): a force gives the value the
  cell keeps, so its reader's copy is shared (an `idr.dup` of the forced
  state), and with it the IO continuation's captures, the lists among
  them. That is right of a cell read twice; here each cell is forced once
  and dropped, which the exclusivity solve, by provenance, cannot see.
  Owed: the force by name (`Canon/Force.cpp`) reaching these cells, which
  are not fresh with one use where it runs, or a memo cell that dies at
  its force moving its forced value out (exclusive) instead of copying it.
  Acceptance: split-prefixes passes, and char-list-accumulated and
  char-list-pipeline still do.
- **A wide cell's take-apart is counted one field at a time.**
  records-past-the-cell's two largest functions are 17.3k and 11.5k LLVM
  lines: straight-line take-aparts of NN's and NF's cells (3840 and 257
  counted slots), each an `idris_rt_is_unique` test whose shared side
  increments every moving field and whose exclusive side decrements every
  dying one (`Conversion/Counting.cpp`, `LowerTake`): 4472 `idris_rt_inc`
  and 4472 `idris_rt_dec` calls in one function. The inlining budget
  (`idr::target::inlineCallerInstructions`, 0781ed93) keeps LLVM's
  live-range computation on them at 11 s instead of 65 s. Owed: the
  moving fields' increments as one runtime call over the cell's object
  slots (or contiguous runs of them), as release already walks them.
  Acceptance: records-past-the-cell's functions no longer reach the
  budget.
- **A static constant passed to an owned parameter is graded owned**
  (found 0ea323fa, during the cutover c4d38e9b took out; *not rerun
  since*). idr-rc-grades gave `idr.constant` an owned grade, which its
  verifier refuses ("cannot hold ... as '!idr.own<...>'"). Reduced: a
  stage(first) program with `!T = plain [@E(), @N(i64, !idr.box<T>)]`,
  `@sum` matching its box argument and calling itself on the tail, and a
  root calling `@sum(N(n, E))`: idr-optimize specializes `@sum` on the
  static `E`, and the node's `idr.constant` of `E` reaches `@sum`'s owned
  parameter. fuzz-two-hosts failed the same way on string literals at
  d40d3c32. escape-hatch-hole-at-runtime's near program, which failed in
  idr-rc-grades under the cutover, passes at c4d38e9b. Owed: rerun the
  reduction and fuzz-two-hosts; strike the entry if both pass.
- **every-interfaces-export fails idr-rc's exclusivity check** (*not
  rerun since* ed9b2a0b); at 6f774119 it, and the benchmarks regex-dna and
  regex-redux, were refused by the owned verifier's "'idr.cell.init' op
  builds an exclusive value of a field that may be shared", the verifier
  refusing counting's output. Cause not found.
- **show-dependent-pair** (*not rerun since* ef45c0a7):
  `printLn (2 ** [1,2])` then `printLn (0 ** [])` at `Vect n Int` gives
  "internal error: idr.match op leaves a value with 0 references on one
  path and 1 on another"; each alone compiles and prints right, as does
  `(2 ** ..)` with `(1 ** [3])`. Cause not found.
- **stream-take-before hangs** (*not rerun since* ef45c0a7): bounds 40, 64
  and 2^61 time out (expected 63, 127 and 2^62-1); 0 and 1 are right.
  stream-take's wrong sums of the same date were a frame cell built in a
  slot the previous iteration's list still read (fixed c2ad4aa7); whether
  this is the same cause is *conjecture*.
- **R3 holds within one iteration only.** The owned walk runs a loop's
  body once, so a view read out of memory before the loop and used after a
  write of that memory in an earlier iteration is not refused. **Owed:**
  the walk carries the places written in the body around the back edge (a
  second pass over the body with the first pass's writes, or the loop's
  written places computed once and applied at the body's entry).
  **Acceptance:** a verify-sources fixture of that shape is refused,
  beside its neighbour (the view taken inside the iteration) that
  verifies.

## arrays

- **optimize-case-of-case-calls expects the constructors a match's regions
  yield to stay** (cd40ab41, idr-yield-fields; found by the data-table
  cutover's test-idr run, 2026-10-20): its negative run
  (`--canonicalize ... builds-nothing=@raised_past_call` under
  `-verify-diagnostics`) expects "idr.con builds a value in
  @raised_past_call" twice, and the new canonicalization yields the fields
  instead, so nothing is built. Owed: the fixture states what the
  canonicalization leaves (the match yields fields, the consumer is raised
  past the call) rather than the constructors it no longer builds.

- **k-nucleotide's time at 25M is unmeasured.** Its output is the C
  version's, byte for byte, at 1k, 10k and 20k nucleotides, and
  cd40ab41 (idr-yield-fields) removed the copy of the counting table on
  every write that made it quadratic (50 s at 10k, 196 s at 20k). Owed:
  bench k-nucleotide at 25M against the 2026-10-13 record (3 s). Waits on
  k-nucleotide compiling on main: under the cutover idr-rc-grades refused
  a constructor of closures it graded static (Main.idr:48); *not rerun
  since* c4d38e9b.

## defunc

- **An apply's case binds its captures at the label's parameters, which
  `quantities-kept` keys by location** (8e2fbec7; found by the data-table
  cutover's test-idr run, 2026-10-20): expect-quantities, pipeline-do-block,
  raise-closed-world and raise-io-loop fail after idr-defunctionalize with
  "bound field 0 of @bind has quantity w, and Idris proved 1": the case
  `@bind(%f0 ..., %f1 ...)` of the closure sum's dispatch binds the captures
  at @bind's parameters' locations (63:18, 63:67 in raise-io-loop), the
  captures are unrestricted, and the contract reads a binder by its location
  alone (`Expect/Quantities.cpp`, "under every name, its line and columns
  without its file"), so the parameters Idris proved linear read as widened.
  Owed: the contract keyed by the binder, not its location (proposal 0003,
  ownership section); until then an apply's captures carry a location of
  their own beside the label's.

- **idr-contify adds a crash site** (harness-cases, found once every e2e
  compilation checks the passes' contracts, 28274bd3): "contract
  crash-sites-not-added broken by idr-contify:
  @System.exitWith[Builtin.Unit, PrimIO.IO, ...].lam.*". Owed: idr-contify
  adds no crash site a function did not have, or the contract states what
  contification may add. Acceptance: harness-cases passes with its
  contracts checked.

## control

- **A call between members of one component is neither inlined nor
  redirected, so a do block's binds stay data.** Two tests:
  - lazy-branch-loop: `no-heap-allocation=@Main.next` fails at
    idr-optimize on the closures `PrimIO.io_bind[Maybe Int, Int].lam.*`
    builds for its call of `io_bind[Maybe Int, Unit].lam.*`: the
    `set ...; if ...` statement's bind (a bind closure of the set, and
    `(>>)`'s closure capturing the `if` as a suspension), built per round
    and run by the callee, a member of the same component.
  - ioref-keeps-old-value and ioref-record-in-place fail moves-out: the
    IORef's read and its write are no longer in one function after
    idr-optimize, so MoveOut, which rewrites a read and a write in one
    block, never meets them. The root reads the IORef and calls
    `io_bind[Unit, Unit].lam.spec.*`, which writes it; that lambda is
    recursive (it dispatches the IO closure sum, which holds it), so
    `Scheduler::stepOfRecursion` (ed9b2a0b) makes its node a step of the
    recursion, never inlined, although every closure it fixes was built
    by the root, outside the recursion.

  Inlining a member is beta reduction (Inline.cpp, `betaReduces`, d69ae5d6)
  only where the inline leaves no call of the component, against the
  unrolling ed9b2a0b removed (CPS and static data). Owed: beta reduction
  decided by where the fixed closures were built, bounded otherwise: a
  node requested from outside its component is beta reduction, one
  requested by a member a step, and a member inlined once at a call whose
  every closure argument is built at the call, the calls it brings in not
  inlined again in that member's turn. 2a02891f (WIP: a member call that
  applies closures built for it alone is granted a node) is that step for
  lazy-branch-loop and has had no suite run. Acceptance: lazy-branch-loop,
  ioref-keeps-old-value and ioref-record-in-place pass, and no program
  ed9b2a0b brought back within its time leaves it.
- **A static suspension forced once outside the root keeps its memo
  cell.** A constant suspension is forced by name in the root alone, the
  one function known to run once (6b997883). A do block in a function the
  root calls once still memoizes its delayed statements and builds the
  action each settles: a main that reads a byte and then runs two or more
  IO actions allocates `idr.cell.new` in `main.delay` and in the `(>>)`
  lambda, and a recursive `getChar` loop allocates in `io_bind`'s lambda.
  No test pins it (literal-match was made to avoid it). Owed: a fact that
  a function runs at most once (called once from code that runs once, on
  no cycle), read where the force is; then a heap-free test of that shape.
- **e2e-eval RUN 4**: `@Prog.main` no longer calls `@dashes` after
  idr-optimize (fails at 651164af and 15cc58aa). Cause not found.
- **A skipped inline leaves IR idr-tail-loops cannot take.**
  linear-string-iterator with every idr-optimize-inline action skipped
  (`--mlir-debug-counter=idr-optimize-inline-count=0`,
  tests/actions-skip-programs) fails idr-tail-loops: "idr.tag op operand
  #0 must be a constructor value, read in place, but got
  !idr.lin<...UnconsResult>" at Main.idr:14 (codeSum's
  `case uncons str it of`). A skipped action must leave valid IR
  (Actions.h), so a pass after it may not build an `idr.tag` of a linear
  value. Acceptance: actions-skip-programs passes on
  linear-string-iterator.

## target

- **A user's bad `--runtime` is an internal error.** Another triple, a
  missing file or a non-archive is reported "idris-mlir: internal error:";
  the driver's verdicts (Driver/Verdict.h) have none for the user's own
  input, so every error that names no rule is internal. Owed: such an
  error is the user's, with its verdict, and runtime-triple holds a
  missing file and a non-archive to it.
- **`llvm.call` operand type mismatch, i64 against !llvm.ptr** (*not
  rerun since* ef45c0a7): bounded-field, bounded-synonym and
  implementation-index-function failed to compile on it, and so did
  leet-insertion-sort with `same : (Int,Int,Int) -> (Int,Int,Int) -> Bool`
  (an `&&` of Int `==`) added. 4108916a fixed the one cause then found
  (`idr.match_lit` on a graded string); whether these share it is
  unknown.
- **dialect-text's orphan check reads only `--check-prefix=`**, so the
  lines of `--check-prefixes=A,B` count as orphans (e2e-loops uses one
  prefix per FileCheck to avoid it). Owed: the check reads both spellings,
  with a witness of `--check-prefixes`.

## upstream

- **The crash after main is not yet confirmed fixed.** LLVM AArch64 made a
  sibling call out of a `tailcc` function with stack arguments, leaving
  its argument area on the stack (upstream/30-aarch64-sibcall-callee-pop,
  carried in the toolchain rebuilt 2026-10-19). Owed: the first full
  suite on it shows directory-listing, files-roundtrip, array-of-arrays
  (stdin 0), bounded-method-own, buffer-ops and io-loop-through-helper
  (its 100-character buffer-edges case included) exiting as their cases
  say; that all six shared the cause was never verified, so one still
  crashing is a new entry.
