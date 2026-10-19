<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Lane idr-a, done: `tests/idr/` actions to defunc

Scope: `tests/idr/{actions,arrays,asm,bufferize,canon,constants,contify,contracts,dedup,defunc}`.
I changed tests only. I ran nothing that builds; `build/dev` was used as it stood.

**Result.** 84 tests became 75. 68 pass. The other 7 fail, each on a compiler bug listed in §4.
No `NEEDS-ACCEPTANCE` mark is left in scope. `make check` shows no failure from this scope. The
two failures it does show, `spec/file-size` and `spec/licenses`, come from other lanes' files.

I ran the whole scope at the start. That run already differed from the audit's 14:30 run:
- **Now pass:** actions/stack, actions/tail-loops and contracts/nested-run. So SUMMARY §5 items 6
  and 7 no longer show in this scope.
- **Fixed by rewriting:** asm/aliases and asm/names now pass.

## 1. Deleted

| path | reason |
| --- | --- |
| actions/inner-steps.mlir + dir | Pinned which inner step of idr-optimize fires (`idr-constants-replace: {0,0,0}`). It was failing falsely (IDR-A-14, SUMMARY §3.7 item 2). |
| actions/deduplicate.mlir + dir | The same module as dedup/merge.mlir. Its skip-all check moved there (IDR-A-4). |
| canon/apply.mlir + dir | Tested a deleted canonicalization: apply of a known closure (`Canon/ClosureOf.cpp`, c7aa7b62). |
| canon/evaluated-memo.mlir + dir | A defunctionalization test filed under canon/. Merged into defunc/evaluated.mlir. |
| defunc/growing-lazy.mlir + dir | A strict subset of defunc/growing.mlir. |
| defunc/evaluated-keyed.mlir, evaluated-coerced.mlir + dirs | One topic in three files. Merged, with canon/evaluated-memo, into defunc/evaluated.mlir. |
| defunc/grade-plain.mlir, grade-linear-argument.mlir, grade-linear-result.mlir + dirs | One property three times. Merged into defunc/grades.mlir. |
| defunc/lazy-choice.mlir + dir | The same shape as memo-sum (a match choosing between two suspensions, then a force). Merged into defunc/memo-sum.mlir. |
| defunc/nested-sum-failure.mlir + dir | Expected an *internal error* that verified IR reaches (IDR-A-18). Replaced by defunc/capture-field.mlir (§2). |
| canon/match-regions, the `cases`-in-attr-dict split | A duplicate of syntax/inherent-invalid.mlir. |
| canon/sink-into-regions: @scrutinee, @used_after, @keep | Functions with no assertion: their "the value stays" was never checked (IDR-A-25). |
| canon/shared-action: @once and its properties | They depended on the deleted apply canonicalization. |
| canon/upstream-passes RUN 4 (`returns=@main:8`) | It depended on the deleted apply canonicalization. |
| `no-closures` and `quantities-kept=%s` after idr-defunctionalize, in every defunc fixture | The verifier's stage rule and `--idr-contracts`' QuantitiesKept already check them, so after a successful pass they cannot fail (IDR-A-2). |
| Leftover `output`-only directories | All 13 of them, including the whole of `tests/idr/constants/` (IDR-A-21). Also defunc/fit and dedup/refuse. |

## 2. Rewritten

**actions/**
- Every `not diff %t.none.mlir %t.done.mlir` is now `%status 1 diff ...`.
  - `not diff` also passed when diff exited 2 on a missing file. `%status 1` asks for "the files
    differ" and nothing else.
  - This is the one form for "the pass changed the module" (IDR-A-5).
- **narrow:** its root was a dummy `@root`, so idr-rc dropped every function and the test was
  vacuous. The root is now an IO root: it reads a byte as a natural and prints both results.
- **trmc:** its constants are written at their grade
  (`idr.constant !idr.q<many, borrow, ...>`), so the fixture parses for the first time.

**asm/**
- **names:** the check of `%just` accepts `@Just(` or `@Just (`. Spacing is not this test's
  contract; the value-name hint is.
- **prefix:** the 16-line CHECK-NEXT chain is replaced by one check per op of the prefix rule. It no
  longer pins SSA names, spacing or adjacency (IDR-A-15).

**bufferize/**
- **aliasing:**
  - @twoWrites is deleted. One-Shot's fresh allocation for a `tensor.empty` conflict is correct
    (IDR-A-13).
  - The three any-failure negatives are now one run whose reasons are checked:
    `expected in-place: memref.copy {{.*}} in @f`.
- **link-read-after-release:** the negative states its reason. The unchecked claim that "the read
  sees the value" is removed.

**canon/**
- **array-moves:** the five bare `%status 1` negatives are two runs whose reasons are checked
  (`expected moves-out: {{.*}} in @f`).
- **facts:** the negative states its reason. I kept `crash-sites=@delayed_crash:2`. Given
  `builds-nothing` (the match moved into both regions), a crash in each region is the only correct
  result, so the number is fully determined.
- **match-regions:**
  - The "two defaults" error is anchored at `@-1`, the line MLIR reports.
  - The "default without its argument" case is argument-less again.
  - The split index of the exhaustive case is fixed.
- **shared-action:**
  - The action type is now `(!idr.world) -> (!idr.world)`. `reads-no-fields` had been failing on
    the field read of the apply's *result*, which can never fold. That failure was the test's, not
    a regression, so SUMMARY's uncertain item 4.9 is settled as no bug.
  - A RUN before the pass shows that `reads-fields` holds there.
- **upstream-passes:**
  - inline is now checked as `never-calls=@main:@get,applies=@main`.
  - The second split has a real IO root.
  - The claim "upstream never inlines a never-returning callee into a body" is deleted: upstream
    does inline it, correctly, ending the body at the crash.
- **sink-into-regions:** the comment now states only what the remaining functions check.

**contify/contify**
- `calls=@root:@twice,calls=@root:@named,calls=@lonely:@lonely` state that the three
  non-continuations stay (IDR-A-25).
- The expected diagnostic is matched on its key, `expected contified: @step.case1`.

**contracts/break, break-linear, crash-sites:** each expected diagnostic is matched on the contract
name, the pass and the function. The sentence after them is no longer matched.

**dedup/**
- **merge:**
  - Each function is named by its location.
  - The merges are stated: `apart` holds before the pass, and fails after it for every pair, with
    the reasons checked.
  - It gains the skip-all identity from actions/deduplicate (IDR-A-4).
- **merge-named:** the negative states its reason (`@b ... @A.inst`).

**defunc/** (each claim is now a property that exists today)

| fixture | what it now checks |
| --- | --- |
| choice, coerce, state, force-call | `no-closures` and `stage=first` dropped; their properties kept |
| curried-apply-poison | `labels=@both:arg0:[]` |
| cycle | `labels=` on all four functions |
| growing | `labels=` on pick, twice, later and force; `calls=@Main.main:@Main.neg` |
| ioref-closure | `calls=@Main.main:@add,@dbl` |
| lazy | `calls=@Main.main:@now,@later` |
| match-field | `calls=@run:@add,@dbl` |
| many-labels | `labels=@pick:result:[all 8]`. The "in name order" claim is deleted: constructor order is the pass's business. |
| memo-by-name | by-name / not-by-name for all five labels (IDR-A-3) |
| memo-forced-join | `forces-nothing` plus both calls |
| memo-rebuild | `labels=@use:arg0:[@one,@two]` and `forces-nothing`. The "does not run @one again" claim is deleted: it needs a run. |
| memo-sum (absorbs lazy-choice) | The forced cell now goes through `@use`: `labels=@use:arg0:[@one,@twice]` and `forces-nothing`. The stale sentence "the force keeps its op" is deleted (IDR-A-3). |
| unreached-cell | Helpers at the boundaries: `labels=@step:arg0:[]`, `labels=@run:arg0:[]`, `forces-nothing=@step` |
| untaken-region | `labels=@g:arg0:[@add]`, `calls=@g:@add` |
| sum-names | `count 3` on the alias list, so the reversal diff can no longer pass on two empty files (IDR-A-17); plus `labels=` for the three sums |
| tag-limit | RUN 2 is a plain run of the pass: "no count refuses it" is the claim checked |
| grades (new) | One `-split-input-file` file of the three grade shapes. Each label is named `@label`, so one property, `calls=@main:@label`, states every shape; it fails before the pass. |
| evaluated (new) | Each shape is a function of one program: `calls=@closureHeld:@add`, `labels=@use:arg0:[@later]`, `forces-nothing` on each |
| capture-field (new) | The i1 capture must be refused where it is written: `expected-error @+1 {{operand #0 must be}}` on the `idr.closure` (§4) |

**Marks.** Every `NEEDS-ACCEPTANCE` line in scope is gone. That includes the copied bufferize note
(IDR-A-24) and the "syntax swept" notes, whose tests pass.

**Expected files.** Each fixture's `expected` is one `RUN n: ok` line per RUN line.

## 3. Kept as they were

These keep their checks and lose only their marks:
- arrays/: all four. Their verdict is a merge into verify/, which is outside my scope (§5).
- asm/aliases.
- bufferize/: linear-thread, pop-box, recursive-thread, recursive-value, release-constant,
  release-copies.
- canon/: case-of-case, eta-known, evaluated-suspension, force-of-choice, force-of-own-constant,
  head, held-not-read, linear-match, match-enclosing, match-known, match-lit-string, match-merge,
  match-results, output-fusion, record-eta.
- contify/never-returns-twice, contracts/nested-run, dedup/keep-apart.
- actions/: accumulate, columns, stack, tail-loops, returned-arguments and narrow-lanes, apart from
  the `%status 1 diff` change.

## 4. Left failing, each on a compiler bug

| test | bug | evidence |
| --- | --- | --- |
| actions/narrow-lanes, actions/returned-arguments | SUMMARY §5 item 1: `foldsBalanced` dereferences the IdrDialect, which is not loaded for a module of upstream dialects only | exit 139 in `IdrDialect::foldLeakCount` from `ContractInstrumentation::runAfterPass` (RUN 2 and RUN 4) |
| canon/output-fusion | SUMMARY §5 item 15: a string folder over-releases | `expected folds-balanced: -1 cells the folders left live`, broken by canonicalize |
| defunc/tag-limit | SUMMARY §5 item 28 | Measured by §8's rule. On today's build, single-threaded, with no `--verify-roundtrip` and no contracts, `--idr-defunctionalize` was still running at 390 s on the 65,537-label module, at about 10 GB RSS, so I stopped it. That is far over half the 60 s step limit. The slowness is the pass's, not the harness's. |
| actions/narrow | **New, open.** With a real root, idr-narrow leaves idr-rc's counted program unchanged: the `%status 1 diff` RUN fails. | `word-loop=@parity` fails after idr-narrow on the same input. Under `-mlir-print-debug-counter`, idr-narrow-word fires 42 times and idr-narrow-fold 3, and the output still equals the input. Passes.td says a loop on a descending natural is versioned. narrow/descending and narrow/versioned (idr-c) hide this with dummy roots (§5). |
| defunc/memo-by-name | **New, open (a regression).** A label that a static constant names (`#idr.closure<@shout, []>`) is made `by_name`. The fixture's comment, its original FileCheck (`idr.ctor @shout (){{$}}`, 327c2e30) and AGENTS ("evaluated once, and its effect is observed that once") say it keeps its memo. | `expected not-by-name: the label @shout of @shout is by_name`. `observableRuns` (Analysis/Effects.cpp) has no case for constants. 1cd1193a deleted the FileCheck without stating the property, so the regression went unseen. |
| defunc/capture-field | SUMMARY §5 item 27, decided | The verifier accepts a closure that captures an i1, and idr-defunctionalize then reports `internal error: the constructor @inner ... unsupported type 'i1'`. I chose the verifier refusal because a capture becomes a field of its sum: one representation means the capture constraint is the field constraint (RF "one fact, one place"; AGENTS: refuse rather than fail internally). The fix is the closure's capture constraint. |

## 5. For other lanes and the orchestrator

- **verify/ lane:** `tests/idr/verify/flow.mlir:8` cites `defunc/lazy-choice.mlir`, which is now
  `defunc/memo-sum.mlir`.
- **verify/ and syntax/:**
  - arrays/{byte-buffer, closure-linear, delay-world, yield-parent} are verifier rules. Their
    verdict is a merge into verify/ops.mlir and verify/closure.mlir; they pass as they are.
  - The parser and verifier splits of canon/match-regions belong in syntax/ (two defaults, a
    default without its argument) and in verify/match.mlir (a default at another type).
  - I fixed them in place because I could not edit those directories.
- **idr-c (narrow/):**
  - narrow/descending.mlir and narrow/versioned.mlir have dummy roots, so idr-rc drops every
    function before idr-narrow runs. Today versioned fails with "no function @deep".
  - Given a real root, the descending case fails as actions/narrow does (§4).
- **HANDOFF.md:180** still mentions actions/inner-steps.

## 6. What a future generator or harness must cover

- **Action census (IDR-A-6, SUMMARY §4.1).**
  - The actions/ files are kept as corpus modules.
  - The generated property must do three things:
    - skip each tag on its own, then verify and run the result;
    - require every tag to fire somewhere in the corpus;
    - cover idr-optimize's inner tags too: idr-optimize-inline, idr-identity-call and
      idr-constants-replace, which inner-steps tried to pin.
  - accumulate and columns still have dummy roots, so they cannot be run until each gets an IO
    root.
- **Translation validation (IDR-A-23).** These deleted claims need a run, and the differential run
  must state each one:
  - memo-rebuild's "the force in @use does not run @one again";
  - link-read-after-release's "the read sees the value";
  - @twoWrites' two distinct buffers (`%a[0] = 1`, `%b[0] = 2`);
  - unreached-cell's and curried-apply-poison's "the apply gives poison".
- **A `boxed` idr-expect row.** Nothing states these claims today:
  - cycle's and growing's "keys on a cycle become boxed sums";
  - growing's "the unrelated type is still unboxed";
  - memo-sum's "a box, with running and forced states";
  - tag-limit's "a sum of more than 2^16 constructors is two levels".
- **Universal harness checks (IDR-A-16):**
  - canonicalize convergence (`test-convergence=true`), which canon/evaluated-memo also ran;
  - the custom-form round trip that asm/ runs by hand;
  - a function-order shuffle in place of sum-names' awk reversal.
- **The higher-order and lazy generator (SUMMARY G-HO).** These were the deleted shapes. They
  belong in its dictionary:
  - an evaluated suspension of a closure, of a suspension, and coerced into a slot with a label;
  - the three grade shapes;
  - a match choosing between two suspensions;
  - a Lazy that grows with its recursion.
- **A positive `copies` row for bufferize, and `merged=` as the complement of `apart` (dedup).**
  With them, the reason-checked negatives in aliasing, link-read-after-release and dedup/merge
  become positive properties.
