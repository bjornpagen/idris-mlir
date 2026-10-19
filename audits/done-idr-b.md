<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Lane idr-b, done: `tests/idr/` e2e to lower

Scope: `tests/idr/{e2e,effects,expect,fold,func,guards,identity,loops,lower}`.
Final run, on today's build in `build/dev` (arm64 macOS):
`make test-idr only='idr/e2e/ idr/effects/ idr/expect/ idr/fold/ idr/func/ idr/guards/ idr/identity/ idr/loops/ idr/lower/' threads=2`
gives **134/141**. The 7 failures are compiler bugs, listed in section 4. At
the start of the lane the same selection gave 119/152. `make check` gives
30/32. Its two failures are outside this scope: spec/file-size (SUMMARY §5
item 37), and spec/licenses on other lanes' new files.

Nothing outside the scope was edited, and no compiler code was touched.

## 1. Deleted

Each fixture below went with its `name/` directory (run, expected, output).

| path | reason |
| --- | --- |
| e2e/crash | duplicates programs/partial/crash-after-output and missing-case |
| e2e/hello | duplicates programs/basic/hello; its import check is the universal one |
| e2e/strings | duplicates programs/semantics, basic/chars and high-chars. It failed on §5 item 12 (see 4.4), which those programs also show |
| e2e/partial-loop | checked only `%status 20`. Its claim (idr.may_loop survives to the object) was never checked, and lower/may-loop and effects/loop state may_loop |
| e2e/statics | pinned pass names in a `--mlir-timing` report |
| fold/pending | removed behaviour: `idr.con` no longer has holes (`dest`) |
| lower/no-mode | removed behaviour: idr-lower's `jit` option |
| expect/typed-reads | removed op form (`check.in_bounds` on a tensor); SUMMARY §3.7 item 1 |
| lower/cpu-features-x86-64 | checked only `entry,calls=@main:@idris_rt_start`, which lower/entry checks, and never the feature word its comment claims. It never ran on arm64 |
| effects/call-effects | merged into effects/queries (see 2) |
| expect/one-clone-two-copies | merged into expect/one-clone as `@step` |
| func/world-twice | duplicated world/world-twice (idr-c's scope). Its one case that no other test has (once in each region is once on each path) moved into func/linear-twice |

The 16 output-only directories in scope were also deleted:
e2e/reduce, effects/{erased-consumer, stale}, expect/{breakers, breaks-last},
func/{clone-shape, facts-roundtrip, inline},
guards/{byte-message, fold-byte, speculation},
loops/{breakers, invariant-fields},
lower/{array-combinators, array-never-returns, to-byte}.

Partial deletions inside kept fixtures:
- expect/facts RUN 2. Any failure satisfied it, and it pinned upstream's DCE.
- lower/arrays RUN 3 and 4 (internal signatures). RUN 6's per-element
  inc/dec call order went too, and with them the comment's claims about the
  boundary layout.
- The signature pins in lower/counting, lower/select and lower/constants:
  the sum layout belongs to lower/data-layout.
- lower/constants' large big. A dup of a static bignum calls `idris_rt_inc`,
  which "no runtime call makes one" does not allow. See section 5.
- lower/cells' two recycle producers, which duplicated lower/exclusive.
- lower/string-build's `@write_rev`. `put_list` of a `plain` data type whose
  cons is declared first is removed behaviour: a list is now declared by
  role.
- lower/match-lit RUN 3. A FileCheck of pass-made text became properties
  (SUMMARY §3.7 item 16).
- fold/poison-fields' two `--idr-rc --idr-lower` RUN lines. An apply that no
  label reaches only exists in dead code: idr-rc dropped `@wrap`, so the
  lowering half checked nothing.
- Stale or unchecked comment claims:
  - e2e/exit-42: "not total, so it is not evaluated";
  - lower/io: "the runtime's word 0".
- Every `NEEDS-ACCEPTANCE:` line in scope: 116 files, and none is left.
  lower/atom-unfolded's mark was its only prose, so it became the fixture's
  comment. The lane and rule ids the audit found (S2, S30, conversion-8,
  mlir-15, ...) were all inside those marks, so they went with them.

## 2. Rewritten

- **Diagnostics match the rule, not the prose.**
  - Every idr-expect expectation in scope (102, in 42 files) is now
    `{{expected <property>: }}` at its location.
  - At line 0 (the module), where no location names the function, it is
    `expected-error-re {{expected <property>: {{.*}}@f}}`: expect/by-name,
    one-clone and tests-nothing. MLIR's verifier does not consume a matched
    expectation, so two identical texts at one line could never both match.
  - In quantities' span variant, two binders share one location, so the
    expectation also names its binder (`parameter 0 of @wide`).
  - Verifier wording was trimmed the same way:
    - func/call-type: `{{calls @g}}`;
    - func/linear-twice: `{{already used on the same path}}` and
      `{{expects a default region}}`;
    - lower/internal-errors: `{{the module's target is not the runtime's}}`.
  - The FileCheck lines on idr-expect messages in loops/{accumulate,
    tail-loop, trmc} are now `expected <property>: {{.*}}@f`.
- **effects/array-memref-effects:** one `-verify-diagnostics` RUN line with
  the error at `@same`, replacing a FileCheck of a message that had been
  reworded.
- **effects/read-past-drop:** `CHECK-COUNT-2` on the verifier's rule with any
  idr op. Which op of the sunk chain the verifier names is control-flow-sink's
  choice. The second split has a single read.
- **effects/crash:** the expected count is 7, the guards the IR writes. It
  was 8.
- **effects/queries:** received call-effects. It has a second RUN line after
  `--idr-effects --cse --canonicalize`: `never-calls=@main:@square`, and a
  call-order that keeps every call that may crash, loop or do IO, including
  two equal `@divides` calls.
- **expect/counting:** rewritten as hand-made owned-stage IR, with no idr-rc
  (SUMMARY §3.7 item 14: an oracle's fixture must not depend on the pass it
  judges). Both halves were checked by hand to pass.
- **expect/coverage:** only counts `{{expected <name>: ` inside an
  expectation, never prose. The `@-N` designators that removing the marks
  moved off line 0 were repointed (by-name, largest-function, malformed,
  one-clone, tests-nothing, unknown).
- **expect/quantities:** `@wide`'s span line again equals its line in the
  file (71). It had drifted by one, which was the failure of RUN 12.
- **fold/data:** the constants are written without spaces. A pass option
  ends at a space, which was the "no such option plain" failure. The request
  was checked to fail on a wrong field.
- **fold/range:** the root calls `@ranges`, `@linear` and `@field` on values
  read at run time. Under the dummy root, upstream's dataflow treated their
  bodies as dead (IDRB-3).
- **guards/fold-unguarded:** `returns=@unguarded:_/.../_` (no result is a
  constant) replaces `CHECK-DAG` on printed op names.
- **e2e/statuses:**
  - the foreign op is `cf.assert`, because scf is now one of the handoff
    dialects;
  - the stale-output case names its failure (FileCheck of its stderr), which
    the stricter lit.sh now requires of `%status 1`.
- **e2e/eval:** states its claim that a closed call stays through the
  optimizer: `calls=@Prog.main:@fact,calls=@Prog.main:@dashes` after
  `--idr-defunctionalize --idr-optimize --canonicalize`.
- **lower/big-fast-path:**
  - `stage(higher)`, which the driver requires;
  - the large program's check is the runtime's big namespace (`_ZN2rt3big`),
    not the mangled `addLarge`.
- **Owned fixtures fixed to today's grading:** loops/trmc, lower/{to-llvm,
  counting, string-build, force-by-name, constants}. Constants are written at
  `!idr.q<many, borrow, T>`, `put_str` of a borrow is `put_str borrow`, and
  `str.pack`/`str.concat` lost the `borrow` keyword.
- **lower/cells:** the producers `cell.new` and `cell.stack` only. The
  recycle cases are lower/exclusive's.
- **Hand pass chains to LLVM run `--idr-entry`** after idr-lower, as the
  pipeline does: lower/arrays, internal-attrs and to-llvm.
- **lower/layout:**
  - the two awk generators were rebuilt, after an earlier rewrite had mangled
    them;
  - the wide and many programs have valid IO roots, which build and read
    their value through a `no_inline` call;
  - the 258-reference record is built at run time by an IO root and passed
    through `@hold`, which idr-rc had been dropping;
  - `%t` is never used inside generated text, since lit expands it.
- **Real roots where a whole-program pass dropped the functions under test:**
  - lower/strings-bigs: "no function @strings";
  - lower/value-buffers;
  - loops/tail-loop: `@until` was uncalled.
- **lower/match-lit:** `calls-only=@empty:[],straight-line=@empty` replaces
  the EMPTY FileCheck.
- **loops/accumulate:** the four functions its comment described with no
  property now have one:
  - `returns-argument=@down:0`;
  - `returns-argument=@down_out:0`;
  - `not-called` for `@down`, `@down_out` and `@as_integer`;
  - `straight-line=@as_integer`;
  - `constant-stack=@twos`.
- **fold/poison-fields:** `builds=@wrap` after canonicalize: the constructor
  with a poison field is still built.

Kept as they are, since each checks something today and its replacement
needs machinery that does not exist yet:
- the fold tables: big-shift, shift, division, nat, pred, to-char, to-int,
  string-offsets;
- guards/fold-{finite, in-bounds, nonempty, nonzero, range};
- effects/alloc;
- e2e/loops;
- e2e/doubles, kept by SUMMARY §3.7 item 8 until its replacements land.

## 3. Known compiler bugs, tests left failing

| test | bug | evidence |
| --- | --- | --- |
| effects/io | §5 item 16: `idr.world.new` answers "may be delayed" | `io.mlir:24:8` and `:28:8`: `expected remark "facts: []" was not produced`, at both world.new |
| fold/strings | §5 item 15: the string folders over-release | `expected folds-balanced: -2 cells the folders left live` |
| identity/identity | §5 item 23: the identity analysis misses `@carry` | `expected not-called: @carry is still called, as @carry, in @carry` (and `in @root`) |
| lower/match-lit | §5 item 12. New detail: a **string** `match_lit` (`@word`, line 29) lowers to a call of `idris_rt_big_cmp` with pointer operands | `'llvm.call' op operand type mismatch: expected operand type 'i64', but provided '!llvm.ptr'`, callee `@idris_rt_big_cmp`. The same happens with `@nat` removed |
| lower/value-buffers | §5 item 8's family: idr-rc leaves a `memref.copy` consuming a borrowed view, even of `memref<?xf64>`, which holds no reference. It reproduces with a real root | `'memref.copy' op consumes a view, which holds no reference; ...` at all three copies |
| lower/big-fast-path | **new, plausible.** The small program imports the runtime's big entries, so their fast paths were not inlined. LinkRuntime.cpp says the prepared runtime's bodies join available_externally and "the optimizer inlines what pays". If an inlined small case is the contract, this is a regression. If it is left to the inliner, RUN 3 is too strong and should go | `not grep` finds `_idris_rt_big_add`, `_cmp`, `_from_int_s`, `_from_int_u`, `_mul`, `_pred`, `_sub`, `_to_int`, `_idris_rt_nat_from_big` |
| expect/coverage | compiler leftover: the `typed-reads` row of `foreign/idr/lib/Transforms/Expect/Lookup.cpp` (and TypedReads.cpp) is still there after its only fixture was deleted. SUMMARY §3.7 item 1 deletes them together. The test passes once the row goes | `no fixture where it fails: typed-reads` |

Rechecked on today's build, and no longer failing: SUMMARY §5 item 2
(complex's ConvertToLLVM, all e2e), and the idr-rc grading failures of item 6
in lower/{atom, box, crash, nat, static-thunk}, loops/trmc-counter and
expect/counting.

## 4. What a future generator or harness must cover

- **Fold tables (IDRB-7):** fold-versus-run over Sem's table, at every width
  and over an edge dictionary.
- **Guard files (IDRB-8):** one family generated from the `Idr_Guarded`
  records. guards/fold-unguarded is now in that family's vocabulary
  (`returns=_`).
- **effects/ (IDRB-15):** the model-based trace property. effects/io's
  defect should show there by behaviour.
- **e2e/loops:** the action-skip differential.
- **cpu-features:** a test parametrised over every target entry and run on
  every host. It needs a way to state the feature word `@main` passes to
  `idris_rt_start`: a property on a call's constant operand, or a run-time
  probe. Nothing checks the word today.
- **e2e/partial-loop:** that `may_loop` reaches the object needs an
  object-level check, which no property gives today.
- **lower/constants:** whether a reference to a static large big may call
  `idris_rt_inc` is undecided. The future "static data counts nothing"
  property should include large bigs.
- **lower/layout's limits** (256, 65,537, 258): exhausted at n-1, n, n+1 and
  2n±1 by a Gen generator rather than awk (IDRB-18, -20).
- **Dummy roots (IDRB-3):** 70-odd fixtures still have a root "the functions
  above are no part of". Only passes that drop unreachable code made that
  fail: idr-rc, defunctionalize, and upstream dataflow. Those fixtures are
  fixed here. idr-expect should refuse a request on a function its root
  cannot reach (§6 step 4).
- **expect/quantities' span variant** depends on `@wide` being at line 71 of
  the file. Identifying a binder by function and position (§6 step 4)
  removes that.
- **Hand pass chains** (IDRB-2) remain in about 20 fixtures:
  `--idr-pipeline=from:<stage>` would replace them.
- **The 280 `run`/`expected` boilerplate files** (IDRB-1) go when the runner
  derives them (§6 step 3). This lane regenerated `expected` for every
  fixture whose RUN count changed.
