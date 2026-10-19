<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Strengthening the suite: fixtures, lane 1 (actions to defunc)

Scope: the 75 dialect fixtures whose names start with `actions-`,
`arrays-`, `asm-`, `bufferize-`, `canon-`, `contify`, `contracts-`,
`dedup-` and `defunc-`. Only those files changed; nothing of the
compiler, the harness or another lane's tests.

## What was done, one way each

1. **Meaning, by `%differential`.** Every fixture whose program can run
   and end now compares the module the pass under test was given with the
   one it made, on the empty input and every byte (or on the `// STDIN:`
   inputs it declares). 57 fixtures carry at least one differential.
   - A fixture whose root was a dummy (`@root() -> i64` returning 0, "the
     functions above are no part of") got an IO root that runs every
     function of the fixture on what it reads: the byte's low bits pick
     the function or its constructor, the rest is its argument, and each
     result is printed. Functions that may crash run only for their
     selector, so both the crash and the paths around it are compared
     (exit status and stdout). Inputs are chosen at the edges: 0, 1, the
     byte less 128 (-128 to 127, at i8/i16/i64 and as a double), sizes
     from 1 up to 32, a list as long as the byte, 255 (and the end of
     input, which reads as 255).
   - A root that called a function that never ends (`@spin`) or grows a
     value exponentially (`defunc-growing`'s `pick`) now calls it only on
     inputs outside the declared `// STDIN:` set, or the fixture declares
     small inputs (0 to 20).
   - What the root never runs is stated, with the reason, in the fixture
     (e.g. `@wrong_case` reads a Left's fields in its Right case, so it is
     given Lefts; `@unknown` likewise only the empty list; `@crashes`
     divides by its argument, which is never 0, since division is by a
     number that is not zero).
2. **Every `idr-expect` property with a case on which it must fail.**
   - Properties the pass makes hold are run on the module *before* the
     pass, where each must fail: one `%status 1` run per fixture, with one
     `BEFORE-DAG` line per property, matched on the property's key and its
     function (never its prose).
   - Properties that already held before the pass (the "X stays" claims,
     and every `labels=` list, whose before-failure is only "no sum yet")
     get a near miss *after* the pass, one `%status 1` RUN line per
     property (lit then requires the failure to be that property's):
     each `labels=` list with one label dropped or added, `by-name` and
     `not-by-name` flipped, `crash-sites` at n-1 and n+1, `returns-on-paths`
     without a path the pass must keep, the same property on the sibling
     function the pass did transform (`builds=@in_case`,
     `reads-fields=@in_case`, `forces=@choose`, `matches=@of_con`, ...),
     or the new root (`crashes-before-output=@root`).
   - `grows-nothing` held before and after everywhere: it got a planted
     case, a copy of the function with one more op made by awk from the
     fixture, on which it must fail (case-of-case, held-not-read).
   - A property that cannot fail on its fixture was deleted, with the
     reason in the fixture: `direct-calls` and `reaches=@main:@label` in
     defunc-force-call (both held before the pass), `forces-nothing=@Main.main`
     in defunc-memo-sum (main forces nothing before or after), and
     merge-named's `one-clone=@a,one-clone=@b` (true before the merge),
     replaced by `apart=@a:@b`, which holds before the pass and fails after
     it.
3. **Text pins replaced by properties or keys.** record-eta's
   `error: expected constant-stack: the stack grows with the recursion of
   @shared` (prose) is `expected constant-stack: {{.*}}@shared`;
   release-constant's and release-copies' `memref.copy copies a buffer in
   @f` is `memref.copy {{.*}} in @f`. Every new diagnostic check matches
   only the key and the function.
4. **Printer fixpoints.** asm-aliases, asm-names and asm-prefix print the
   module, read it back and print it again, and the two prints must be
   equal (asm-names also with the binders' names, whose locations are
   printed so that they survive).
5. **Verifier rules pinned from both sides.** arrays-delay-world and
   arrays-yield-parent gained the accepted neighbour as a second split
   (a delay of a word; a yield under `idr.tabulate`), as byte-buffer and
   closure-linear had; defunc-capture-field gained the same program
   capturing the word instead of the i1.

## Per test: what it checks now that it did not

| test | now also checks |
| --- | --- |
| actions-accumulate | IO root (natural of the byte; list as long as it); differential of `--idr-accumulate`; `@both` starts from 1 so that it computes 2^n instead of 0 (the pass makes the same clones) |
| actions-columns | IO root tabulating byte+1 records, reading the first, middle and last and summing the second field; differential of `--idr-columns` |
| actions-narrow | differential of `idr-narrow` on the counted program (passes); still fails on the known open bug (idr-narrow changes nothing) |
| actions-stack | IO root running `@largest`, `@large`, `@frame`, `@recursive`; differential of rc-cells + rc-stack |
| actions-tail-loops | IO root: every loop on the byte, `@spin` only on byte 200; differential of `idr-tail-loops` on the counted program over 9 declared inputs (0, 1, 2, 15, 16, 127, 128, 255, end of input) |
| actions-trmc | IO root at the owned stage (cells built explicitly), copying a three-cell list made from the byte and printing its digits; differential of `--idr-trmc` |
| actions-narrow-lanes, actions-returned-arguments | unchanged: modules of upstream dialects with no program or root, so no run; still fail on SUMMARY §5 item 1 |
| arrays-delay-world, arrays-yield-parent | the accepted neighbour as a second split |
| arrays-byte-buffer, arrays-closure-linear | unchanged (already pinned from both sides) |
| asm-aliases, asm-names, asm-prefix | print, read back, print again: equal |
| bufferize-aliasing, -link-read-after-release, -release-copies | IO roots printing what each copied array and the box or array beside it hold; differential of `--idr-bufferize` (fails, bug B6) |
| bufferize-linear-thread | IO root (array of byte%32+8 sevens, @fill writes byte%8+1); BEFORE for `in-place`; differential (passes) |
| bufferize-pop-box | IO root (byte%8+1 records, pop with a fill of 1000); BEFORE for `moves-out`, `in-place`; differential (fails, bug B7) |
| bufferize-recursive-thread, -recursive-value | IO root (@go writes byte%32 of 32); BEFORE for `in-place`; differential (fails, bug B7) |
| bufferize-release-constant | root thaws the constant twice and prints both (99 twice); differential; prose unpinned |
| canon-array-moves | BEFORE for `moves-out`; differential of `--idr-optimize` and of `--idr-effects --canonicalize` |
| canon-case-of-case | IO root over all 11 functions (byte%8 picks the crashing one); differential; BEFORE for 11 properties; `crashes-before-output=@root`, `reads-fields=@match_of_match` fail; planted grows-nothing |
| canon-eta-known | IO root (Left/Right by the low bit); differential; BEFORE; `builds=@in_case`, `reads-fields=@in_case` fail after |
| canon-evaluated-suspension | IO root; differential; BEFORE for 5; `builds=@forced` fails |
| canon-facts | IO root (byte%4 picks across_*/delayed_crash; choice 0/1/2; @unused first); differential; BEFORE; `crashes-before-output=@root`, `crash-sites=@delayed_crash:1` and `:3` fail |
| canon-force-of-choice | IO root; differential; BEFORE for 6; `forces=@choose`, `builds=@choose` fail |
| canon-force-of-own-constant | IO root (byte%3 picks @other, @knot, @mid); differential; `forces=@label`, `never-calls=@label:@mid` fail; compiled and run: @other prints 7, @knot and @mid must end with `idris-mlir: a suspension forced itself` (fails, bug B2) |
| canon-head | IO root (the byte as a character, at three widths less 128, as a quarter; @other on the empty string at byte 0, where its guard crashes); differential; BEFORE; `checks-every-path=@heads`, `no-heap-allocation=@root` fail |
| canon-held-not-read | IO root writing every list; differential; BEFORE for 3; `calls-closed=@open_call:@both` fails; planted grows-nothing |
| canon-linear-match | root is a new IO root (was `@gives_back`, which always crashed); differential; BEFORE for 5; `matches=@of_con`, `calls=@of_con:@keep` fail |
| canon-match-enclosing | IO root (literal 0..8, a second literal, a shape of each kind); differential; BEFORE for 7; four near misses (a kept path, a kept read) fail |
| canon-match-known | IO root (@crashes on the low bit); differential; BEFORE for 7; six near misses fail (including a wrong constant for `returns`) |
| canon-match-lit-string | IO root (the byte less 128 shown; a string of the byte, empty at 0); BEFORE; three near misses; differential (fails, bug B4) |
| canon-match-merge, canon-match-results, canon-sink-into-regions | IO roots; differential; BEFORE; near misses (`matches=@all_same`, `matches-nothing=@unused`, `crash-sites=@dead:0`, `checks-every-path=@write_in_both`); in sink-into-regions the divisor is 0 at bytes 0 and 1, where the guard must crash whichever region runs |
| canon-match-regions | the exhaustive split got an IO root; BEFORE for `regions-distinct`, `builds-nothing`; differential of the canonicalized split |
| canon-output-fusion | IO root over all 15 functions (what a function keeps is measured, not written again); BEFORE for 12; three near misses; differential. Still fails at RUN 1 on SUMMARY §5 item 15, so the new lines run once it is fixed (each checked by hand against today's build) |
| canon-record-eta | IO root (a list of byte%8 cells); without canonicalize, `idr-tail-loops` leaves @traverse and @known growing (must fail), @reindex allocates before; differential of canonicalize + tail-loops; prose unpinned |
| canon-upstream-passes | both roots renamed `@Main.main` (bug B1), the first made an IO root (Just of an odd byte, Nothing, where @fail crashes, of an even one); BEFORE for inline's and remove-dead-values' properties; differential of `--inline` and of each `--remove-dead-values` (the first fails, bug B3; it is last so the others run) |
| canon-shared-action | unchanged: its `@bind` is a stand-in with no body ("no body" crash), so no run means anything; its failing case is already RUN 1 |
| contify | the root reads the byte and doubles from 1 at each step; differential of `--idr-contify` |
| contify-never-returns-twice | BEFORE for all five properties; no differential: the program never ends (stated in the fixture) |
| contracts-nested-run | the root builds a node of the byte; differential of `--idr-rc` (the counted program at owned against the program at first) |
| contracts-break, -break-linear, -crash-sites | unchanged: oracle meta-tests that already fail with the contracts on and pass with them off |
| dedup-keep-apart, dedup-merge, dedup-merge-named | roots read a byte (keep-apart's ping runs on the byte, not on a number of order n^4); differential of `--idr-deduplicate`; merge-named: `apart=@a:@b` holds before and fails after (replacing the vacuous one-clone) |
| defunc-choice, -coerce, -cycle, -evaluated, -growing, -many-labels, -memo-rebuild, -memo-sum, -state, -sum-names, -untaken-region, -unreached-cell | differential of `--idr-defunctionalize`; BEFORE for every property; each `labels=` list with one label changed fails after the pass |
| defunc-ioref-closure, -lazy, -match-field, -memo-forced-join | differential; BEFORE for every property |
| defunc-curried-apply-poison | BEFORE; `labels=@both:arg0:[@both]` fails (no run: nothing runs @both) |
| defunc-force-call | split into pass, differential and properties; BEFORE; root renamed `@Main.main` (bug B1); two properties that held before deleted |
| defunc-grades | BEFORE: `calls=@main:@label` fails before the pass in each of the three splits (one line per split) |
| defunc-memo-by-name | the root forces @traced's and @shout's cells twice each and prints whether the clock reading came after the byte, not the reading, so its output is deterministic; differential; BEFORE; each property flipped fails (but by-name=@shout, bug B5) |
| defunc-capture-field | the accepted neighbour (a word captured) as a second split; still fails on SUMMARY §5 item 27 |
| defunc-tag-limit | unchanged (65,537 labels: a differential would compile them twice); still times out, SUMMARY §5 item 28 |

## Compiler bugs found (B1-B4 new; B5-B7 known, with new evidence)

- **B1. idr-entry: internal error on a root named `@main`.** A verified
  program whose root is `@main` (a hand-written name; the frontend writes
  `Main.main`) reaches `internal error: idr-entry: @main names a symbol
  already` (`Conversion/Entry.cpp`, `makeEntry`): the entry symbol is
  taken. Input: defunc-force-call as it was (root `@main`), through
  `%differential`. Expected: the program compiles (the root is made
  private like every other function, so it can be renamed), or the
  verifier refuses the name. Got: internal error. The fixtures that ran
  were renamed to `@Main.main`; contracts-*, defunc-grades still name a
  root `@main` but never lower.
- **B2. A constant memo cell's state is folded away: a force that meets
  its own running cell recurses instead of crashing.** canon-force-of-own-constant,
  RUN 12: input `1` runs `@knot`, whose label forces its own constant.
  Expected stderr `idris-mlir: a suspension forced itself` (the dispatch's
  Running case, `Defunctionalize/Forces.cpp`); got `idris-mlir: stack
  exhausted`. Same for `@mid` (input `2`). The lowered `@knot` writes the
  Running state into the static cell and calls `@knot` again without
  reading the state: the match on the cell's tag in the memo dispatch is
  folded because its scrutinee is the `#idr.con<..., @knot, []>` constant,
  though the cell is mutable. The same fold means a second force of a
  constant cell runs its label again instead of reading Forced.
- **B3. remove-dead-values turns a closure's label into `return poison`.**
  canon-upstream-passes, last RUN: on the empty input (255) the program
  prints 510 before `--remove-dead-values` and 255 after. Reduced: a
  program whose only use of `@inc` is `idr.closure @inc(%n)` applied by
  `idr.apply`; after the pass `@inc`'s body is `%0 = ub.poison; return %0`.
  The upstream equivalent (`func.constant` + `func.call_indirect`) is kept
  intact by the same pass, so the bug is ours: the liveness the pass reads
  does not see a closure's label as called (idr.closure / idr.apply's
  interfaces). It does not reach programs today, since remove-dead-values
  runs after defunctionalization, but the fixture states that the pass
  works on closures.
- **B4. A match on the text of a number against `"1"` does not lower.**
  canon-match-lit-string, differential: `idr.match_lit (idr.str.show_sint
  %x) { case "1" ... }` lowers to a call of `idris_rt_big_cmp` with a
  pointer where an i64 is declared: `'llvm.call' op operand type mismatch:
  expected operand type 'i64', but provided '!llvm.ptr'`. Reduced to a
  root that reads a byte and matches its shown text against "1". This is
  SUMMARY §5 item 12's message; this is a reproducer of 15 lines.
- **B5 (known, §5 / idr-a's memo-by-name regression).** Now visible at
  run time: forcing the static constant `#idr.closure<@shout, []>` twice
  prints `once` twice; the property `not-by-name=@shout` fails.
- **B6 (§5 item 8's family). The owned verifier refuses counting's output
  at a `memref.copy`.** bufferize-aliasing, -link-read-after-release,
  -release-copies: the module `--idr-bufferize` makes, compiled from its
  stage, fails with `'memref.copy' op consumes a view, which holds no
  reference; a reference of its own (idr.dup) is consumed, and an owned
  value's is given to a store (idr.own.give)`. The copy is the one these
  fixtures say bufferization must write; the source modules compile only
  because the optimizer inlines the copying function first.
- **B7. `idr::ownership::readFrom` asserts on memref ops.** In idr-rc's
  analyses: `cast<TypedValue<MemRefType>>` fails in
  `memref::LoadOp::getMemref` (Reuses: bufferize-pop-box) and in the
  ViewLikeOpInterface `getViewSource` of a `memref.cast` (Borrows:
  bufferize-recursive-thread, -recursive-value). Each crashes on the
  fixture's own program through the pipeline, the original constant root
  included (checked with the old root of recursive-value).

Not bugs, found on the way: `idr.divs` by zero is a precondition, not a
crash (canon-facts' first root divided by 0 and printed 0); an infinite
recursion with nothing after it may hang rather than exhaust the stack
(contify-never-returns-twice), so a never-ending program gets no
differential.

## Runs

- Before: `make test-idr` over the 75: 69 pass; actions-narrow-lanes,
  actions-narrow, actions-returned-arguments, canon-output-fusion,
  defunc-capture-field, defunc-memo-by-name fail (known).
- After (the 74 less defunc-tag-limit, which times out as before, plus
  roles-contify, which `only=contify` also selects; threads=2): 60/75.
  The 15 failures: the 6 known above, each at the same RUN line as
  before, and 9 on bugs B2-B4, B6 and B7, each at the RUN line that shows
  its bug: bufferize-aliasing, -link-read-after-release, -release-copies
  (B6), bufferize-pop-box, -recursive-thread, -recursive-value (B7),
  canon-match-lit-string (B4), canon-force-of-own-constant (B2, its KNOT
  line), canon-upstream-passes (B3, its last line). canon-output-fusion
  still stops at RUN 1 (§5 item 15); its new lines were run by hand on
  today's build: BEFORE fails as stated, the three near misses fail, and
  the program prints the same before and after canonicalize.
- 66 of the 75 fixtures changed; the 9 left as they were are named in the
  table with the reason.
- `make check`: 31/33; file-size (C++ units of foreign/idr) and
  dialect-text (fold-*, guards-fold-*, e2e-loops, other lanes' fixtures)
  fail, neither on a file of this lane.

## For other lanes

- The `%differential` of a module at `first` recompiles it through the
  whole pipeline after defunctionalization, the passes it already went
  through included (rc-cells, rc-stack, bufferize): that is how B6 shows.
  A harness that cut the pipeline after the *last* pass the module went
  through would need the pass named, not the stage.
- For a higher-stage pass (defunctionalize, canonicalize at higher), both
  sides go through idr-defunctionalize, so the differential checks
  consistency of each pass with the pipeline, not defunctionalization
  against an independent meaning; lower-cells' `// REF:` module (another
  lane) is the form for an independent reference.
