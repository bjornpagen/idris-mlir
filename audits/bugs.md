<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Known compiler bugs, by lane

The bugs known on main, each under the lane that owns its fix (lanes:
tools/lanes/README.md). An entry gives the bug, the test or reproducer
that shows it, its cause when known, and what is owed; it goes when its
fix lands, the commit naming it. A bug in a pinned upstream is recorded
here only until its patch is carried: then its report is
`upstream/<bug>/README.md` and its status `PINS.md`'s.

**Status, main at 7987388b plus the frames and pipeline change below
(2026-10-20), two cores throughout.** `make check` 34/34,
`make test-idr` 341/341 (the new frames fixture among them),
`make test-mlir-tools` 34/34, `make test-unit` passes, on the shared
toolchain with every carried patch. Stage 1's pipeline half OOMed
twice (proposal 0001 §2): in idr-frames' member-by-answer cloning of
`Libraries.Text.Parser.Core.bindGrammar`'s component, and in
upstream's remove-dead-values whole-program liveness solve. The
answer is now a sum per component — one run per member, one resume
per result type, each rest once — and the pipeline no longer
re-solves liveness over the whole program. The first full
`make test` since the data-table cutover ran at 017f5374: 451/480. Of
its 29 failures, 16 were crash locations the TTC kept per term node
since 374e0e77, where the expected files still named the definition
(fixed c4a046e0), one the registry's allowlist and one the handoff
check's program line (31daec54), and one the excl grade written at a
frame lifetime (276e887). Eleven remain, below; no full `make test`
has run since those fixes, so what the removal of remove-dead-values
leaves for counting to drop is unmeasured there.

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
- **fuzz-two-hosts compiles, and its counts are back.** Its cases pass,
  and what fails is mlir.expect at idr-rc-exclusive: `@Gen.drawLoop`
  drops and dups owned `Nat` and `big` values (its own parameters among
  them, where its `.spec` copy's are borrowed), so counts-nothing fails,
  and a box of `@Slot` gets a fresh cell in
  `@Gen.reverseOnto.spec.*.excl.*`, so reuses-in-place fails. The tape it
  draws from is linear, so a draw should count nothing and build each
  cell in the one it took. Which step grades those parameters owned, and
  what the reverseOnto copy lost, is not found. (The static-constant
  grading this entry replaced is struck: escape-hatch-hole-at-runtime
  passes, and fuzz-two-hosts' failure at 017f5374 was the excl grade at
  a frame lifetime, fixed 276e887; the entry's reduced program was not
  rerun.)
- **every-interfaces-export does not finish compiling in its step
  limit.** At 017f5374 it times out at 60 s of compile.sh on two cores;
  at 6f774119 it, and the benchmarks regex-dna and regex-redux, were
  refused by the owned verifier's "'idr.cell.init' op builds an exclusive
  value of a field that may be shared". Which pass its time is in, and
  whether the refusal is behind it, is not found.
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

- **k-nucleotide's time at 25M is unmeasured.** Its output is the C
  version's, byte for byte, at 1k, 10k and 20k nucleotides, and
  cd40ab41 (idr-yield-fields) removed the copy of the counting table on
  every write that made it quadratic (50 s at 10k, 196 s at 20k). It
  compiles again (bench-smoke at 017f5374). Owed: bench k-nucleotide at
  25M against the 2026-10-13 record (3 s).
- **buffer-ops does not finish compiling in its step limit.** At
  017f5374 it times out at 60 s of compile.sh on two cores (exit 124);
  it compiled before the waves. Which pass its time is in is not found.

## defunc

- **idr-contify adds a crash site** (harness-cases and exit-with, found
  once every e2e compilation checks the passes' contracts, 28274bd3;
  confirmed at 017f5374, where both fail to compile on it): "contract
  crash-sites-not-added broken by idr-contify:
  @System.exitWith[Builtin.Unit, PrimIO.IO, ...].lam.*". Owed: idr-contify
  adds no crash site a function did not have, or the contract states what
  contification may add. Acceptance: harness-cases and exit-with pass
  with their contracts checked.

## control

- **A call between members of one component is neither inlined nor
  redirected, so a do block's binds stay data.** lazy-branch-loop passes
  since 2a02891f got its first suite run (017f5374). What remains:
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
  inlined again in that member's turn. 2a02891f (a member call that
  applies closures built for it alone is granted a node) is that step for
  lazy-branch-loop, confirmed at 017f5374. Acceptance:
  ioref-keeps-old-value and ioref-record-in-place pass, lazy-branch-loop
  still does, and no program ed9b2a0b brought back within its time
  leaves it.
- **A static suspension forced once outside the root keeps its memo
  cell.** A constant suspension is forced by name in the root alone, the
  one function known to run once (6b997883). A do block in a function the
  root calls once still memoizes its delayed statements and builds the
  action each settles: a main that reads a byte and then runs two or more
  IO actions allocates `idr.cell.new` in `main.delay` and in the `(>>)`
  lambda, and a recursive `getChar` loop allocates in `io_bind`'s lambda.
  double-basics and interface-ring-power pin it (017f5374): each is marked
  heap-free and fails on `idr.cell.new` in `@Main.main.delay.*`, with the
  `idr.str.show_sint` and `idr.str.append` of a `putStrLn (cast n)` the
  delay keeps from meeting the output that writes a number in pieces.
  Owed: a fact that a function runs at most once (called once from code
  that runs once, on no cycle), read where the force is. Acceptance:
  double-basics and interface-ring-power pass.
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
- **dialect-text's orphan check reads only `--check-prefix=`**, so the
  lines of `--check-prefixes=A,B` count as orphans (e2e-loops uses one
  prefix per FileCheck to avoid it). Owed: the check reads both spellings,
  with a witness of `--check-prefixes`.

## upstream

- **The crash after main is confirmed fixed for five of its six.**
  LLVM AArch64 made a sibling call out of a `tailcc` function with stack
  arguments, leaving its argument area on the stack
  (upstream/30-aarch64-sibcall-callee-pop, carried in the toolchain since
  2026-10-19). The full `make test` at 017f5374 shows directory-listing,
  files-roundtrip, array-of-arrays, bounded-method-own and
  io-loop-through-helper exiting as their cases say. buffer-ops does not
  crash; it does not finish compiling, which is its own entry under
  arrays. Nothing is owed here but the record: the entry goes with the
  next full run that keeps the five green.
