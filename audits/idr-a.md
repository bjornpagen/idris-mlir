<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Audit lane idr-a: `tests/idr/` actions to defunc

## 1. Header

- **Lane:** idr-a.
- **Scope:** `tests/idr/{actions,arrays,asm,bufferize,canon,constants,contify,contracts,dedup,defunc}`.
  That is every `.mlir` fixture and its `name/{run,expected,output}` directory, plus
  the directories that hold only a leftover `output`.
- **What I read:**
  - Both guidelines in full: `.claude/skills/testing-by-search/SKILL.md` (cited as **TBS §n**) and
    `.claude/skills/representation-first/SKILL.md` (cited as **RF**, with the rule's name).
  - `AGENTS.md`, `tests/README.md`, the header of `tests/testutils.sh`, `tests/lib/lit.sh` and `tests/lib/expect.sh`.
  - `tests/spec/dialect-text/run` and `tests/ACCEPTANCE.md` (the entries for this scope).
  - All 84 fixtures, each with its `run`, `expected` and last `output`.
  - The C++ the failures point at: `Expect/Lookup.cpp`, `Expect/Folds.cpp`, `Expect/Closures.cpp`,
    `Contracts/Contracts.cpp`, `Verify/Program.cpp`, `Stack/Stack.cpp`, `Effects/Constants.cpp`,
    `Support/Actions.h`, `Passes.td`, `IdrOps.td` and `IdrClosureOps.td`.
  - The git history of the fixtures and of the deleted `Canon/ClosureOf.cpp`, and `HANDOFF.md`.
- **Logs and outputs:**
  - Every `output` file in scope dates from the `make test-idr` run of 10-18 14:30
    (`scratchpad/test-idr.log`).
  - That run came **before** a7bf77b4 (14:51, stack cells), dcafd452 (15:23), 3d279eb9 (16:07, counting
    grades) and the 14:53 edit of `asm/aliases.mlir` and `asm/names.mlir`. Some failures below may
    already be fixed. I say so where it applies.
  - Nothing was built or run for this audit.
- **Counts:**
  - **84 tests.** By directory: actions 10, arrays 4, asm 3, bufferize 8, canon 23, contify 2,
    contracts 4, dedup 3, defunc 27, and constants 0. `tests/idr/constants` holds no test, only leftover output.
  - **13 leftover directories** hold only an `output` file, which git ignores (§2.10).
  - **Status at the last run:** 63 pass, 19 fail, 2 unknown (the asm fixtures edited after the run).
  - **Verdicts:**

    | verdict | tests |
    | --- | --- |
    | keep | 38 |
    | rewrite-as-property | 8 |
    | rewrite | 26 |
    | merge | 9 |
    | delete | 3 |

## 2. Verdict table

Status is what the test's last `output` shows next to its `expected` (the 14:30 run).

### 2.1 actions/

The scheme every file here follows:
- RUN `none`: print the module.
- RUN `skipped`: run the pass with every action counter at 0.
- `diff` the two.
- RUN `done`: run the pass with its actions on.
- `not diff` against `none`.

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| actions/accumulate.mlir | skipping every idr-accumulate-countdown/-clone action leaves the module as it was; the pass changes it otherwise | rewrite-as-property | Should be one generated (pass, tag) × corpus property, not a hand copy per pass (IDR-A-6; RF "every string that names a thing"; TBS §1.1 vocabulary). Keep the module as a corpus input. | pass |
| actions/columns.mlir | the same, for idr-columns-convert | rewrite-as-property | IDR-A-6 | pass |
| actions/deduplicate.mlir | the same, for idr-deduplicate-merge | merge-into:tests/idr/dedup/merge.mlir | Its module is dedup/merge.mlir's, differing only in block-argument names (IDR-A-4; RF "one fact, one place") | pass |
| actions/inner-steps.mlir | idr-optimize-inline, idr-identity-call and idr-constants-replace each fire at least once in idr-optimize on this module, and skipping each changes the output | delete | Pins which inner step of idr-optimize does the work. That is incidental, not the role's contract (TBS §1.1, IDR-A-14). HANDOFF.md predicted it would fail falsely. | fail: `idr-constants-replace : {0,0,0}`, the action never fired |
| actions/narrow.mlir | skipping every idr-narrow-* action is the identity on the input that idr-rc plus idr-tail-loops makes; the pass changes it otherwise | rewrite-as-property | IDR-A-6. The input is made by two other passes, so idr-rc's bugs fail this test (TBS §1.1). Start from a graded fixture. | fail: RUN 1, idr-rc leaves `idr.match_lit` on `!idr.own<!idr.nat>` (code bug, §4.4). RUN 6 "ok" vacuously (IDR-A-5). |
| actions/narrow-lanes.mlir | the same, for idr-narrow-lanes-version, on a module of upstream dialects only | rewrite-as-property | IDR-A-6 | fail: exit 139, null dereference in `foldsBalanced` (§4.1) |
| actions/returned-arguments.mlir | the same, for idr-returned-arguments-drop, on func/scf/llvm only | rewrite-as-property | IDR-A-6 | fail: exit 139, the same null dereference (§4.1) |
| actions/stack.mlir | skipping idr-stack-cell leaves idr-rc-cells' output; idr-rc-stack changes it otherwise | rewrite-as-property | IDR-A-6 | fail: RUN 4 "operation's operand is unlinked" (§4.3; probably fixed by a7bf77b4). RUN 5 "ok" vacuously. |
| actions/tail-loops.mlir | the same, for idr-tail-loops-loop/-hoist/-uplift, on idr-rc's output | rewrite-as-property | IDR-A-6. The setup runs all of idr-rc. | fail: RUN 1, idr-rc gives an unlinked operand (§4.3). RUN 6 "ok" vacuously. |
| actions/trmc.mlir | the same, for idr-trmc-clone, on an owned-stage module | rewrite-as-property | IDR-A-6. The fixture never parsed (IDR-A-11). | fail: parse error `use of value '%nil' expects different type than prior uses`. RUN 5 "ok" vacuously. |

### 2.2 arrays/

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| arrays/byte-buffer.mlir | the Idr_ByteBuffer constraint refuses a buffer of i32 and accepts one of i8 | merge-into:tests/idr/verify/ops.mlir | A verifier rule, misfiled under arrays (IDR-A-20). The negative-plus-positive pair is a sound minimal witness (TBS §9.2 step 5). | pass |
| arrays/closure-linear.mlir | the closure rule: a closure with a linear capture must be at quantity one; that closure applies with no lin.use | merge-into:tests/idr/verify/closure.mlir | A verifier rule about closures, not arrays (IDR-A-20) | pass |
| arrays/delay-world.mlir | idr.delay of the world is refused (Idr_Capture) | merge-into:tests/idr/verify/closure.mlir | A verifier rule, misfiled (IDR-A-20). verify/closure.mlir already holds "a closure never captures a world". | pass |
| arrays/yield-parent.mlir | idr.array.yield under an op without YieldTargetsOpInterface is refused | merge-into:tests/idr/verify/ops.mlir | A verifier rule (IDR-A-20) | pass |

### 2.3 asm/

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| asm/aliases.mlir | the alias rule for data types and big constants (`!List_Nat`, `!Pair`/`!Pair1`, `#idr_value`), and that text reads back as itself | keep | The printed alias is the contract here, and asm/ is where printed syntax is checked (TBS preamble, spec/dialect-text). Drop the `| idris-mlir-opt | FileCheck` second RUN once a universal custom-form round trip exists (IDR-A-16). | unknown: fixture edited at 14:53. The 14:30 run failed on its old spelling `!Prelude.Types.List_...` ("type names with a '.' are reserved"). |
| asm/names.mlir | the value-name hints (`%w`, `%s`, `%clo`, `%thunk`, `%forced`, `%f0`...) and nameloc names | keep | The name hints are a documented printer contract (TBS §1.3). Likely to fail on `%just = con {{.*}}@Just(` because the printer writes `@Just (` (§4.7). | unknown: edited after the run, which failed as aliases did |
| asm/prefix.mlir | ops directly under idr.func print without `idr.`; ops in regions and two-dot ops keep it | rewrite | Its 16-line CHECK-NEXT chain pins the whole body: op order, SSA names, and the space in `@Just(`. The contract is only which op names carry the prefix (TBS §1.1, IDR-A-15). | fail: `CHECK-NEXT: ... idr.con !M @Just(%[[INC]]` against `%just = idr.con !M @Just (%inc_1 : i64)` |

### 2.4 bufferize/

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| bufferize/aliasing.mlir | @fresh is in place; @twoWrites, @afterCon, @sharedResult and @constant copy | rewrite | The @twoWrites expectation is wrong (IDR-A-13). The four `%status 1` lines pass on any failure, a misspelled name included (IDR-A-5, TBS §7). | fail: RUN 3 `idris-mlir-opt exited 0, expected 1` (in-place holds for @twoWrites) |
| bufferize/linear-thread.mlir | a linear array threaded through @fill is written in place, nothing copied | keep | The in-place promise is a fact the pass states (TBS §1.3). It still lacks a run that checks meaning (IDR-A-23). | pass |
| bufferize/link-read-after-release.mlir | a read after a release makes the release copy, "and the read sees the value the buffer held" | rewrite | The meaning claim is unchecked, and `%status 1` takes any failure as the expected one (IDR-A-5, IDR-A-23) | pass |
| bufferize/pop-box.mlir | a pop's read and fill become one element.update, in place | keep | Both are stated as properties (`moves-out`, `in-place`) | pass |
| bufferize/recursive-thread.mlir | a recursive linear thread is in place at every level | keep | A property of the boundary analysis, stated by name | pass |
| bufferize/recursive-value.mlir | a recursive value array is in place at every level | keep | The same | pass |
| bufferize/release-constant.mlir | thawing a constant array copies; the reason is FileChecked | keep | A negative with its reason checked: the model for IDR-A-5's fix | pass |
| bufferize/release-copies.mlir | a release whose array is read again copies; the reason is FileChecked | keep | The same | pass |

### 2.5 canon/

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| canon/apply.mlir | canonicalize turns an apply of a known closure into a call; the inliner then removes it | delete | Tests removed behaviour. `Canon/ClosureOf.cpp` was deleted in c7aa7b62, and ApplyOp has no canonicalizer, since defunctionalization owns this now (IDR-A-1; RF "delete what the representation makes dead") | fail: `expected no-closures: a closure is built in @of_closure`, ×11 |
| canon/array-moves.mlir | an element moves out across a pure call after idr-effects, but not across IO, a write in another block, or a word | rewrite | The positives are good properties. The five `%status 1` negatives accept any failure, "no function @printed" included (IDR-A-5). State their reasons. | pass |
| canon/case-of-case.mlir | case-of-case moves a consumer into regions where it folds; it never moves output before a crash; it copies nothing where nothing folds | keep | Every function has a named property, and `crashes-before-output` and `grows-nothing` are contract-level (TBS §1.1). Meaning is still unchecked (IDR-A-23). | pass |
| canon/eta-known.mlir | record eta from a known case or a one-constructor type; no eta in the wrong case, with swapped fields, or from two sources | keep | Positive and negative properties for each case | pass |
| canon/evaluated-memo.mlir | after idr-defunctionalize, the force of an evaluated suspension is a dispatch call: no force left | merge-into:tests/idr/defunc/evaluated-keyed.mlir | It tests idr-defunctionalize, not canonicalize (IDR-A-20) | pass |
| canon/evaluated-suspension.mlir | a force of `idr.delay` folds to the value; a force of a suspend used once becomes a call | keep | Stated as properties | pass |
| canon/facts.mlir | canonicalize moves code only as each op's effects allow; unused calls stay | keep | `crash-sites=@delayed_crash:2` pins how many copies were made, not the contract (low, IDR-A-26) | pass |
| canon/force-of-choice.mlir | a force moves into a match's regions and becomes a call where the suspension is the region's own | keep | Stated as properties | pass |
| canon/force-of-own-constant.mlir | a force of a constant suspension is never replaced by a call (knots) | keep | A safety property stated negatively, with `never-calls` | pass |
| canon/head.mlir | head of a cons/show string is its first char, so the string is not built; any other head keeps its guard | keep | Properties | pass |
| canon/held-not-read.mlir | consumers move into regions only where they fold; no chain blow-up | keep | `grows-nothing` is the right shape of property (TBS §1.1) | pass |
| canon/linear-match.mlir | a match on a linear parameter stays; a match on an entered constructor folds | keep | Properties | pass |
| canon/match-enclosing.mlir | an inner match on the same value takes the known region | keep | `returns-on-paths` is a semantic oracle (the values per path are kept): the best property in scope (TBS §9) | pass |
| canon/match-known.mlir | a match on a known constructor or literal is replaced by its region; a crashing region stays | keep | Properties, with `returns` as an oracle | pass |
| canon/match-lit-string.mlir | a nonempty string never takes case "" | keep | `returns` and `returns-on-paths` | pass |
| canon/match-merge.mlir | equal regions merge into the default | keep | `regions-distinct` is the contract | pass |
| canon/match-regions.mlir | the parser refuses two defaults, a default without its argument, a default at another type, and `cases` in attr-dict; an exhaustive match merges and folds | rewrite | The sweep gave the "default without its argument" case an argument. The `@+1` anchor is wrong for MLIR's previous-line diagnostic. Four syntax cases are misfiled under canon/ (IDR-A-12). | fail: RUN 1 `expected error "expected '('" was not produced`; `unexpected error: expected '}'` at 20:6 |
| canon/match-results.mlir | unused match results are dropped; a crashing match stays | keep | Properties | pass |
| canon/output-fusion.mlir | output of built strings is written piece by piece; nothing is allocated for output alone | keep | Properties. The failure is the compiler's (§4.2). | fail: `expected folds-balanced: -1 cells the folders left live`, broken by canonicalize |
| canon/record-eta.mlir | eta makes an IO fold a loop (constant stack); no eta when a field is shared or the constructor unknown | keep | Negatives with FileChecked reasons, as IDR-A-5 wants. Note that `constant-stack` failing for @unknown is a proxy for "no eta". | pass |
| canon/shared-action.mlir | an IO action read from a shared constructor stays applied; one read once becomes a call | rewrite | `calls=@once:@bind` depends on the removed apply canonicalization (IDR-A-1). Whether reads-no-fields is a regression is unknown (§4.9). | fail: `reads-no-fields: idr.field reads a field in @twice`; `@once calls no @bind` |
| canon/sink-into-regions.mlir | a pure value used only in regions sinks; one the scrutinee or later code uses stays; a guard stays | keep | Note that @scrutinee and @used_after have no property: the verifier holds them, so their "stays" is unchecked here (IDR-A-25) | pass |
| canon/upstream-passes.mlir | upstream remove-dead-values and inline work on idr ops; a never-returning callee is not inlined by upstream | rewrite | RUN 4's `returns=@main:8` needs the removed apply canonicalization (IDR-A-1). The rest is a sound interface-conformance check. | fail: RUN 4 `result 0 of @main is not the constant 8` |

### 2.6 contify/, contracts/, dedup/

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| contify/contify.mlir | `contified` fails before the pass and holds after it | keep | A property with its failing witness (TBS §9.2 step 5). The claim that @twice, @named and @lonely stay is unchecked (IDR-A-25). | pass |
| contify/never-returns-twice.mlir | two non-returning continuations both move in; the body is one block | keep | Properties | pass |
| contracts/break-linear.mlir | --idr-contracts names a pass that unrestricts a linear result; with contracts off it passes | keep | A mutation test of the oracle itself: it shows the contract can fail (TBS §7, §12) | pass |
| contracts/break.mlir | the same, for widened effects | keep | The same | pass |
| contracts/crash-sites.mlir | crash-sites-not-added is checked per function, not per answering name | keep | The same, with a regression witness | pass |
| contracts/nested-run.mlir | idr-rc's own nested pipeline is checked as one pass | keep | The failure is the compiler's (§4.4) | fail: `'idr.return' op returns '!idr.box<...>' ... but @both returns '!idr.own<...>'`; the call result is at the plain grade |
| dedup/keep-apart.mlir | pairs that differ in totality, effects, body or cycle membership stay apart | keep | `apart` is a property | pass |
| dedup/merge-named.mlir | instances of different definitions merge; the kept function answers to both names | keep | Properties. Its `%status 1 ... not-called=@b` has no reason (IDR-A-5, low). | pass |
| dedup/merge.mlir | equal private functions merge, transitively; output is deterministic and idempotent | rewrite | No line checks that anything merged: a no-op pass passes (IDR-A-4) | pass |

### 2.7 defunc/

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| defunc/choice.mlir | @pick's sum holds exactly @add and @dbl; main's dispatch calls each | keep | `labels` and `calls` are the contract | pass |
| defunc/coerce.mlir | each set of labels is its own sum | keep | `labels` | pass |
| defunc/curried-apply-poison.mlir | a curried apply of a closure no label reaches is poison | rewrite | Checks only `no-closures`, which the verifier already implies (IDR-A-2). The poison claim is unchecked. | pass |
| defunc/cycle.mlir | keys on a cycle become boxed sums | rewrite | IDR-A-2: "boxed" is unchecked | pass |
| defunc/evaluated-coerced.mlir | an evaluated suspension shares the memo sum and is never rebuilt | merge-into:tests/idr/defunc/evaluated-keyed.mlir | IDR-A-2; the evaluated-* family is three files | pass |
| defunc/evaluated-keyed.mlir | labels held by an evaluated suspension flow through its forced state | rewrite | IDR-A-2. Should state the `labels` of the forced value and run the program (IDR-A-23). | pass |
| defunc/force-call.mlir | each force becomes a call of a dispatch; the call graph reaches the label | keep | `forces-nothing`, `direct-calls` and `reaches` are the contract. `stage=first` is redundant with StagedPass (low). | pass |
| defunc/grade-linear-argument.mlir | a closure taking a linear argument converts and keeps quantities | merge-into:tests/idr/defunc/grade-plain.mlir | Three variants of one property. `quantities-kept=%s` repeats `--idr-contracts`' QuantitiesKept relation (IDR-A-2). | pass |
| defunc/grade-linear-result.mlir | the same, for a linear result | merge-into:tests/idr/defunc/grade-plain.mlir | The same | pass |
| defunc/grade-plain.mlir | the same, for a closure that went through lin.enter/use | rewrite | Becomes one `-split-input-file` corpus file of the grade shapes, without the redundant properties (IDR-A-2) | pass |
| defunc/growing-lazy.mlir | a Lazy key on a cycle becomes a boxed sum | delete | A strict subset of growing.mlir, which holds the same @Main.later, @Main.one and @Main.force (IDR-A-20) | pass |
| defunc/growing.mlir | closures that grow with recursion become boxed sums; an unrelated type stays unboxed | rewrite | IDR-A-2: neither boxed nor unboxed is checked | pass |
| defunc/ioref-closure.mlir | an IORef of functions: its read's apply calls both labels | rewrite | IDR-A-2: needs `labels` on the read, or a run | pass |
| defunc/lazy-choice.mlir | two suspensions chosen by a match share one memo sum | rewrite | IDR-A-2 | pass |
| defunc/lazy.mlir | a Lazy stored in a field becomes a sum constructor | rewrite | IDR-A-2 | pass |
| defunc/many-labels.mlir | eight labels join into one sum, in name order whatever the program order | rewrite | IDR-A-3. The 8-label set and the order-independence are both unchecked; `labels=` exists, and order-independence is a metamorphic property (TBS §9). | pass |
| defunc/match-field.mlir | a closure bound by a match region is a dispatch over both labels | rewrite | IDR-A-2 | pass |
| defunc/memo-by-name.mlir | traced and clocked are `by_name`; sized, shout and errtext keep their memo | rewrite | IDR-A-3. `by-name` and `not-by-name` exist and are not used. | pass |
| defunc/memo-forced-join.mlir | two suspensions return closures into one joined slot | rewrite | IDR-A-2 | pass |
| defunc/memo-rebuild.mlir | lazy sets are unified, never coerced; a forced cell keeps its state, so @one does not run twice | rewrite | IDR-A-2 and IDR-A-23: "does not run again" is about meaning, so it needs a run | pass |
| defunc/memo-sum.mlir | a memo sum has per-label, running and forced constructors; "the force keeps its op" | rewrite | IDR-A-3: its comment contradicts force-call.mlir's "no force is left", and only `no-closures` is checked | pass |
| defunc/nested-sum-failure.mlir | defunc reports exactly this internal error for an i1 capture | rewrite | It pins an internal error that a verified module can reach (IDR-A-18). AGENTS asks for `unsupported` or unrepresentable. | fail: quoting, `'i1'` against the expected `i1` |
| defunc/state.mlir | the state-monad shape keys each (type, labels) separately | keep | `labels` at five positions is the contract | pass |
| defunc/sum-names.mlir | sum names come from content: the same under reversed function order and under threading | rewrite | A good metamorphic property (TBS §9). But `grep '= !idr.data<' \| diff` passes vacuously when no alias is printed (IDR-A-17). | pass |
| defunc/tag-limit.mlir | 65,537 labels make a two-level sum, and no count refuses the program | keep | A real boundary that cannot be shrunk. The two-level claim itself is unchecked (IDR-A-19). | fail: RUN 2 `timed out after 60s` |
| defunc/unreached-cell.mlir | a cell no constructor builds still gets a memo sum; its apply is poison | rewrite | IDR-A-2 | pass |
| defunc/untaken-region.mlir | the solve follows edges in untaken regions: a dispatch over @add, nothing poison | rewrite | IDR-A-2: "nothing is poison" is unchecked | pass |

### 2.8 Leftover directories (not tests)

These directories hold only an `output` file, which `.gitignore` ignores (`/tests/**/output`). Their tests were deleted in earlier waves:
- actions/canonicalize
- canon/covered-default
- canon/match-in-generate
- canon/unused-call
- constants/run (all of `tests/idr/constants`)
- contify/never-returns
- dedup/refuse
- defunc/block-argument
- defunc/dead-move-empty-key
- defunc/evaluated-refused
- defunc/fit
- defunc/numbering
- defunc/unknown-lazy

Verdict: delete them locally (IDR-A-21). Status: they are not tests.

## 3. Findings

### IDR-A-1: canon tests exercise a deleted canonicalization

- **Category:** stale-legacy. **Severity:** high.
- **Paths:**
  - canon/apply.mlir
  - canon/shared-action.mlir (`calls=@once:@bind`)
  - canon/upstream-passes.mlir (RUN 4)
- **Evidence:**
  - c7aa7b62 deleted `foreign/idr/lib/IR/Canon/ClosureOf.cpp` ("The closure an apply runs, which its
    canonicalization turns into a call").
  - `IdrClosureOps.td` gives `Idr_ApplyOp` no `hasCanonicalizer`. No ApplyOp canonicalization pattern
    exists under `lib/IR`.
  - Outputs:
    - apply: `expected no-closures: a closure is built in @of_closure ... expected calls: @of_closure calls no @add`
    - shared-action: `expected calls: @once calls no @bind`
    - upstream-passes: `result 0 of @main is not the constant 8`
  - ACCEPTANCE.md marks apply.mlir only as "syntax swept to the data-type-first form": the sweep kept a
    test whose behaviour no longer existed.
- **Guideline:** RF "Delete what the representation makes dead in the same change"; AGENTS ("exercises removed behaviour").
- **Recommendation:**
  - Delete canon/apply.mlir.
  - Drop the @once case from shared-action and RUN 4 from upstream-passes.
  - Turning an apply of a known closure into a call is defunctionalization's job now. defunc/choice and
    pipeline/known-label state it there.

### IDR-A-2: post-defunctionalize `no-closures` and `quantities-kept` cannot fail where the verifier and contracts pass

- **Category:** cannot-fail / redundant. **Severity:** high.
- **Paths:** 17 defunc fixtures whose only property is `no-closures`:
  - curried-apply-poison
  - cycle
  - evaluated-coerced
  - evaluated-keyed
  - growing
  - growing-lazy
  - ioref-closure
  - lazy-choice
  - lazy
  - many-labels
  - match-field
  - memo-by-name (IDR-A-3)
  - memo-forced-join
  - memo-rebuild
  - memo-sum
  - unreached-cell
  - untaken-region

  Also the three grade-* fixtures, which add `quantities-kept=%s`, and sum-names, which also checks
  `no-closures`.
- **Evidence:**
  - `Verify/Program.cpp`, stageRules: past the higher stage, any value whose type names a closure or
    suspension is refused: `"holds a closure or a suspension in a program past the higher stage, where
    idr-defunctionalize has made each a sum"`.
  - idr-defunctionalize is a StagedPass that leaves the program at `first`, and the verifier runs after
    every pass.
  - `noClosures` (Expect/Closures.cpp) looks for ClosureOp, ApplyOp and closure constants, all of which
    produce or consume `!idr.fn` values. So after a successful pass it cannot fail.
  - Every idris-mlir-opt in lit.sh gets `--idr-contracts`, which checks `QuantitiesKept` against the
    module before the pass. That is the same relation `quantities-kept=%s` checks against the file.
- **What this hides:** each comment states a specific outcome that nothing asserts:
  - "Both become boxed sums" (cycle)
  - "its results are poison" (curried-apply-poison)
  - "nothing is poison" (untaken-region)
  - "The unrelated closure type ... is still an unboxed sum" (growing)
- **Guideline:**
  - RF "One fact, one place": the property and the verifier both hold the fact.
  - TBS §9.2 step 5: "Otherwise the test can silently check nothing."
  - TBS §1.1: the name checks less than it claims (Winters' `DefaultConfigsArePrime`).
- **Recommendation:**
  - Drop `no-closures` and `quantities-kept=%s` after defunc: they repeat the verifier and the contracts.
  - State each claim with an existing property: `labels=` for label sets, a "boxed" property (a new
    idr-expect row if none exists), and `forces-nothing`.
  - Better still, run the program (IDR-A-23).

### IDR-A-3: comments claim properties that idr-expect can state, and the tests do not

- **Category:** checks-nothing. **Severity:** high.
- **Paths:** defunc/memo-by-name.mlir, defunc/many-labels.mlir, defunc/memo-sum.mlir.
- **Evidence:**
  - memo-by-name claims "a label whose function reaches an effect ... is `by_name` ... One that forges a
    world only to use an array ... keeps its memo", and so on for five labels. Its only RUN is
    `--idr-expect=holds=no-closures`.
  - `Lookup.cpp` has `by-name` and `not-by-name` rows ("Every memo label ... whose function is @f ... runs
    again at every force").
  - many-labels claims "each sum holds every label that reaches it once, in name order, whatever order
    the program met them in", and checks only `no-closures`.
  - memo-sum's comment says "The force keeps its op and takes the box". force-call.mlir says "a force of
    a cell of the sum becomes a call of [the dispatch] ... So no force is left". The two comments
    contradict each other. They could drift apart only because memo-sum asserts nothing.
- **Guideline:**
  - TBS §1.1: the assertion must be the contract.
  - RF "Every string that names a thing is a missing type": a property in prose and not in a check.
- **Recommendation:**
  - memo-by-name: `by-name=@traced,not-by-name=@sized,not-by-name=@shout,by-name=@clocked,not-by-name=@errtext`.
  - many-labels: `labels=@pick:result:[@aa,@bb,@cc,@dd,@ee,@ff,@mid,@zz]`, plus the
    function-permutation metamorphic check of IDR-A-17.
  - memo-sum: assert `forces-nothing=@Main.main` and delete the stale sentence.

### IDR-A-4: dedup/merge never checks that anything merged; actions/deduplicate duplicates its module

- **Category:** cannot-fail / redundant. **Severity:** high.
- **Paths:** dedup/merge.mlir, actions/deduplicate.mlir.
- **Evidence:**
  - merge.mlir's RUN lines are only:
    - `cmp %t.mlir %t.serial.mlir` (determinism)
    - `diff %t.mlir %t.again.mlir` (idempotence)
  - A pass that does nothing passes both. Yet the comment claims "@B.inc is @A.inc, @B.id is @A.id ...
    Merging is transitive in one run".
  - `diff <(sed -n '/^idr.program/,$p' actions/deduplicate.mlir) <(... dedup/merge.mlir)` differs only
    in `default(%d0: i1)` against `default(%d: i1)`.
- **Guideline:**
  - TBS §1.1 and §9.2 step 5.
  - RF "One fact, one place": the same module, twice.
- **Recommendation:**
  - Make one file.
  - State the merges as `%status 1 ... apart=@A.inc:@B.inc` with the reason FileChecked, or better, add
    the complement of `apart` (say `merged=@A.inc:@B.inc`) as an idr-expect row.
  - Keep the determinism and idempotence lines (both are real properties) and the action-skip check.

### IDR-A-5: negative checks that accept any failure, and `not diff` that passes on missing files

- **Category:** cannot-fail / wrong-or-missing-oracle. **Severity:** medium.
- **Paths:**
  - **`not diff`:** actions/narrow RUN 6, trmc RUN 5, stack RUN 5, tail-loops RUN 6, narrow-lanes RUN 5,
    returned-arguments RUN 5.
  - **Bare `%status 1`:**
    - bufferize/aliasing RUNs 3-6
    - bufferize/link-read-after-release RUN 2
    - canon/array-moves RUNs 3-7
    - dedup/merge-named RUN 2
- **Evidence:**
  - The trmc output shows `RUN 1: failed ... RUN 4: failed ... RUN 5: ok`. RUN 5 is
    `not diff %t.none.mlir %t.done.mlir`, and neither file was ever written. diff exits 2 and `not`
    turns that into success.
  - The same holds in narrow, stack, tail-loops, narrow-lanes and returned-arguments.
  - `%status 1 idris-mlir-opt ... --idr-expect=holds=moves-out=@printed` succeeds for any reason
    idr-expect fails. That includes "no function @printed, and no copy of it", which the apply output
    shows is a failure idr-expect reports (`expected never-calls: no function @of_closure`).
  - The model to follow is already in scope: release-constant, release-copies and record-eta FileCheck
    the reason (`// CHECK: expected in-place: memref.copy copies a buffer in @thawed`).
- **Guideline:** TBS §7 (the oracle must recognize *this* bug); TBS §9.2 step 5.
- **Recommendation:**
  - Every negative states its reason (FileCheck on idr-expect's diagnostic, which spec/dialect-text
    allows), or is restated as a positive property.
  - Replace `not diff` with the per-tag count that `-mlir-print-debug-counter` prints (each tag fired
    at least once), which cannot pass on a missing file.

### IDR-A-6: actions/ is ten hand copies of one property; the action tags are strings, and six have no test

- **Category:** harness-representation / example-should-be-property. **Severity:** high.
- **Paths:** all of actions/, plus roles/contify.mlir and obs/debug-counter.mlir outside scope.
- **Evidence:**
  - Each action's tag is a string literal in its pass's C++ (`static constexpr llvm::StringLiteral tag = "idr-stack-cell";`), 24 in all.
  - The RUN lines spell them again (`-mlir-debug-counter=idr-narrow-version-count=0,idr-narrow-joint-count=0,...`).
  - `Passes.td` says the role is "the one fact the tests read of it (IdrPassRoles.txt ...)". No file
    under tests/ reads IdrPassRoles.txt; I grepped for `PassRoles`, `pass-roles` and `IdrPassRoles`.
  - These tags name no fixture at all: idr-constants-erase, idr-constants-unique, idr-optimize-node, idr-raise.
  - The role's contract (`Passes.td`): "every transform it makes is optional, an MLIR action ...
    skipping any one, or the pass, leaves a valid module whose behaviour is the same".
  - The fixtures check two things: skipping all actions gives the same text, and running the pass
    changes the text. Neither runs the program to check "behaviour is the same", and none skips one
    action at a time.
- **Guideline:**
  - RF "Every string that names a thing is a missing type" and "One fact, one place".
  - TBS §1.1 (a weak vocabulary makes people copy assertions).
  - TBS §5 (only the passes someone remembered are covered).
- **Recommendation:**
  - Declare each action as a TableGen record on its IdrPass, and generate both the C++ `tag` and a table
    the harness reads.
  - The harness runs, for every optimization pass × every corpus module:
    - **skip all:** the module is unchanged.
    - **skip one, for each tag:** the module verifies and, when it has a root, runs to the same output.
    - **non-vacuity, across the whole corpus:** every tag fires somewhere (a census over the corpus,
      not a per-fixture `not diff`).
  - The ten fixtures become corpus inputs.

### IDR-A-7: the folds-balanced contract crashes on a module with no idr op

- **Category:** code-bug-revealed. **Severity:** high.
- **Paths:** actions/narrow-lanes.mlir, actions/returned-arguments.mlir.
- **Evidence:**
  - Exit 139:
    `#5 idr::IdrDialect::foldLeakCount() const / #6 idr::expect::foldsBalanced(...) / #7 idr::ContractInstrumentation::runAfterPass`.
  - `Expect/Folds.cpp:21`:
    `module->getContext()->getLoadedDialect<IdrDialect>()->foldLeakCount();`
  - Its comment says "idr-expect loads the idr dialect". Under `--idr-contracts`, with an input of only
    func/scf/vector/llvm ops, nothing has loaded it.
- **Guideline:** TBS §7 (an oracle must not be the thing that crashes).
- **Recommendation:**
  - Read the count where the dialect is guaranteed: load IdrDialect in the instrumentation, or give a
    count of 0 when it is absent.
  - Add a fixture of upstream dialects only to the contracts suite.

### IDR-A-8: a folder leaves a negative live-cell count

- **Category:** code-bug-revealed. **Severity:** high.
- **Path:** canon/output-fusion.mlir.
- **Evidence:** `expected folds-balanced: -1 cells the folders left live` / `contract folds-balanced broken by canonicalize{...}`, in both RUNs.
- **Reading:** a fold released one more runtime reference than it took. The most likely sites are the
  pack/concat/put_list folders on the constant list in @constant_list, or the nil in @nil, with
  @cells_of_strings next. An over-release can be a use-after-free inside the compiler. The cause is
  unconfirmed.
- **Guideline:** TBS §7 (a universal oracle doing its job).
- **Recommendation:**
  - Keep the test: it is the witness.
  - Bisect the folders with `-mlir-debug-counter` on the canonicalizer's patterns, or narrow the module.

### IDR-A-9: idr-rc leaves ungraded values that the graded verifier refuses

- **Category:** code-bug-revealed. **Severity:** high.
- **Paths:** actions/narrow.mlir (RUN 1), contracts/nested-run.mlir.
- **Evidence:**
  - `'idr.match_lit' op operand #0 must be a value of a type with literals, read in place, but got '!idr.own<!idr.nat>'`.
  - `'idr.return' op returns '!idr.nat' as result 1, but @Main.main returns '!idr.own<!idr.nat>'`.
  - `'idr.call' op gives result #0 ... which holds references at the plain grade in a graded program`.
- **Note:** 3d279eb9 ("Counting grades only what holds references") and dcafd452 landed after this run.
  Recheck before acting.
- **Recommendation:** none for the tests themselves: nested-run's expectation is right. narrow should not
  depend on idr-rc to make its input (IDR-A-6).

### IDR-A-10: idr-rc-stack leaves an unlinked operand

- **Category:** code-bug-revealed. **Severity:** medium (probably fixed).
- **Paths:** actions/stack.mlir (RUN 4), actions/tail-loops.mlir (RUN 1).
- **Evidence:**
  - `error: operation's operand is unlinked ... "idr.cell.init"(<<UNKNOWN SSA VALUE>>, ...)`.
  - With every idr-stack-cell action skipped (stack RUN 2) the module is fine, so the stack-cell
    rewrite caused it.
  - a7bf77b4 (14:51) rewrote `Stack.cpp` to `rewriter.setInsertionPoint(cell); rewriter.replaceOpWithNewOp<idr::CellStackOp>(...)`
    after the 14:30 run.
- **Recommendation:** recheck. The tests' expectations are right.

### IDR-A-11: actions/trmc.mlir never parsed

- **Category:** stale-legacy. **Severity:** medium.
- **Evidence:**
  - Line 14 defines `%nil = idr.constant !idr.box<!List> #idr.con<...>`, then line 15 uses it as
    `%o = idr.dup %nil : !idr.q<many, borrow, !idr.box<!List>>`.
  - Parse error: `use of value '%nil' expects different type than prior uses`.
  - The form that works is asm/aliases.mlir's `idr.constant !idr.q<many, borrow, !idr.box<...>> #idr.con<...>`.
- **Guideline:** AGENTS ("tests that never ran on the code they describe").
- **Recommendation:** fix the fixture when it becomes a corpus input (IDR-A-6). Its owned-stage shape
  (dup, borrow, cell.new/init) is otherwise useful.

### IDR-A-12: canon/match-regions was damaged by the syntax sweep, and its diagnostics were never located

- **Category:** stale-legacy / wrong-or-missing-oracle. **Severity:** high.
- **Evidence:**
  - The second split claims "a default without its argument ("expected '(')"", but the sweep wrote
    line 45 as `default(%d: !T) {`. The negative case is now a valid module. Output:
    `expected error "expected '('" was not produced`.
  - The first split's `// expected-error @+1 {{expected '}'}}` sits above the second `default`. MLIR
    reports a wrong token at the start of a line at the end of the previous one. Output:
    `20:6: error: unexpected error: expected '}'`.
  - The four parse cases are syntax tests filed under canon/.
- **Guideline:** TBS §9.2 step 5 (check that the scenario reached the state it claims); RF "one topic, one home".
- **Recommendation:**
  - Move the four parse cases to syntax/.
  - Restore the argument-less default.
  - Anchor with `@-1`, or put the error on the token's line.
  - Keep the exhaustive-match canonicalization in canon/.

### IDR-A-13: bufferize/aliasing @twoWrites expects a copy that a correct bufferization does not make

- **Category:** wrong-or-missing-oracle. **Severity:** medium.
- **Evidence:**
  - The comment says "Two writes of one empty tensor ... the second writes a copy".
  - The output says `in-place` holds: `idris-mlir-opt exited 0, expected 1`.
  - One-Shot resolves a conflict on a `tensor.empty`, whose contents are undefined, with a fresh
    allocation and no copy. No `memref.copy` is correct, and it is better code.
- **Guideline:** TBS §1.1. The contract is that `%a[0] = 1` and `%b[0] = 2` are distinct buffers;
  whether a copy appears is not the contract.
- **Recommendation:** delete the @twoWrites case, or check it by running: return both, print both
  (IDR-A-23).

### IDR-A-14: actions/inner-steps pins which inner step of idr-optimize fires

- **Category:** brittle-overspecified. **Severity:** medium.
- **Evidence:**
  - Its check line is `// IDR_CONSTANTS_REPLACE: idr-constants-replace{{ +}}: {{[{][1-9][0-9]*}},0,0}`.
  - Output: `idr-constants-replace : {0,0,0}`.
  - HANDOFF.md: "`tests/idr/actions/inner-steps` may fail falsely if specialization folds `@inc(7)`".
  - Which step computes `@seven`'s 7 is the optimizer's internal order. It is no contract.
- **Guideline:** TBS §1.1.
- **Recommendation:** delete. IDR-A-6's per-tag census over the whole corpus states non-vacuity without
  pinning a fixture to a step.

### IDR-A-15: asm/prefix pins a whole body; the printer's `idr.con` spacing differs from its documented form

- **Category:** brittle-overspecified, plus a cosmetic code bug. **Severity:** medium.
- **Evidence:**
  - The CHECK-NEXT chain runs from `idr.func @prefix(` to `return`, with `%clo`, `%applied`, `@Just(`
    and op order all pinned.
  - The failure is only `@Just (%inc_1 : i64)` against `@Just(`.
  - `IdrOps.td` documents `` `idr.con !T @Cons(%x : i64)` ``. Two adjacent custom directives
    (`custom<CtorRef>` then `custom<Fields>`) print with a space between them.
- **Guideline:** TBS §1.1: the prefix rule is the contract, and spacing and names are not.
- **Recommendation:**
  - Check each op's prefix on its own line (`CHECK: {{^ *}}%{{.*}} = closure @inc`,
    `CHECK: idr.call @inc`), with no CHECK-NEXT chain.
  - Fix the format with an empty literal (`` `` ``) or update the documented form.

### IDR-A-16: a universal property is copied into fixtures

- **Category:** harness-representation / distribution. **Severity:** medium.
- **Evidence:**
  - `'--canonicalize=region-simplify=disabled test-convergence=true'` appears by hand in 25 fixtures:
    23 in canon/, one in optimize/, one in tie-shape/.
  - `| idris-mlir-opt | FileCheck` (a custom-form round trip) appears in asm/ only.
  - lit.sh already adds `--verify-roundtrip` (generic form and bytecode) to every idris-mlir-opt, which
    shows that the harness is the right place for such checks.
- **Guideline:** RF "One fact, one place"; TBS §7 (universal oracles); TBS §5 (today it covers only the
  files that remember it).
- **Recommendation:** lit.sh, or a pool over all fixtures, runs on every dialect fixture:
  - canonicalize convergence;
  - custom-form print → parse → generic-form equality.

  Then delete the copies.

### IDR-A-17: module text compared outside the FileCheck rule, with a vacuous pass

- **Category:** harness-representation / cannot-fail. **Severity:** medium.
- **Path:** defunc/sum-names.mlir. The actions/ `diff`s are the same pattern, but justified.
- **Evidence:**
  - `// RUN: grep '= !idr.data<' %t.mlir | sort > %t.sums` and the same for `%t2`, then `diff %t.sums %t2.sums`.
  - If the printer prints no data-type aliases (the alias policy changes, say), both files are empty and
    the diff passes.
  - spec/dialect-text checks only FileCheck reading module text, so grep, diff and cmp pass it unseen.
  - The reversal is a one-line awk program inside a RUN line.
- **Guideline:** TBS §9.2 step 5; RF "Parse at the boundary" (a string is compared where a typed
  identity exists).
- **Recommendation:**
  - Give the harness a metamorphic step, "shuffle function order", applied over the corpus, which
    compares the passes' outputs modulo order through a structural comparison (or `labels` properties).
  - Assert the expected number of sums.
  - Extend spec/dialect-text to grep, diff and cmp over module text, or document the differential
    exemption.

### IDR-A-18: defunc/nested-sum-failure enshrines an internal error that verified input can reach

- **Category:** wrong-or-missing-oracle / code-bug-revealed. **Severity:** medium.
- **Evidence:**
  - `// expected-error-re@unknown {{internal error: the constructor @inner of "{{.*}}" has a field of unsupported type i1}}`.
  - The module (an i1 capture) passes the verifier, and defunc then reports an *internal* error.
  - It now fails only on quoting: `unsupported type 'i1'`.
- **Guideline:** AGENTS ("Reject what the compiler cannot compile with an explicit `unsupported` error
  ...; never miscompile silently"); RF SPOV2 (make the state unrepresentable).
- **Recommendation:**
  - Either the closure's capture constraint refuses a non-field type in the verifier (so the negative
    moves to verify/ with ODS's message), or defunc supports i1 fields by widening.
  - Do not pin internal-error text.

### IDR-A-19: defunc/tag-limit times out and does not check its two-level claim

- **Category:** code-bug-revealed (performance) / checks-nothing. **Severity:** medium.
- **Evidence:**
  - `RUN 2: failed ... exited 124 / timed out after 60s`.
  - The RUN asserts only `stage=first,no-closures,forces-nothing=@Main.main`.
  - "a sum of more than 2^16 constructors is a two-level sum" is the claim.
- **Guideline:** TBS §8. The bug cannot be moved into a smaller box, because the 2^16 header is the
  runtime's.
- **Recommendation:**
  - Keep the boundary test.
  - Find why defunc is superlinear in the number of labels.
  - Assert the two-level shape with a property.

### IDR-A-20: misfiled and duplicate fixtures

- **Category:** redundant. **Severity:** low.
- **Evidence:**
  - canon/evaluated-memo runs `--idr-defunctionalize`.
  - defunc/growing.mlir holds growing-lazy.mlir's @Main.one, @Main.force and @Main.later verbatim.
  - grade-linear-argument, grade-linear-result and grade-plain are one property three times.
  - arrays/ holds verifier rules about worlds and closures (delay-world, closure-linear).
- **Guideline:** RF "One fact, one place"; MEMORY "one topic, one home".
- **Recommendation:** as the table says.

### IDR-A-21: leftover outputs of deleted tests

- **Category:** stale-legacy / infrastructure-gap. **Severity:** low.
- **Evidence:**
  - 13 directories hold only `output` (§2.8). `.gitignore:7:/tests/**/output` ignores them.
  - `tests/idr/constants/` holds nothing else, and `subpools "idr"` makes a pool of every subdirectory.
- **Recommendation:**
  - Delete them.
  - Have the runner (or `make clean`) remove an `output` whose directory has no `run`.

### IDR-A-22: no search reaches these passes

- **Category:** distribution. **Severity:** high.
- **Evidence:**
  - Every fixture in scope is hand-picked.
  - The fuzzer (`tests/Fuzz.idr`) draws "closed expressions over every primitive". It makes no closure,
    suspension, data type, match or array.
  - So defunctionalization's label solve, the canonicalizer's match patterns, bufferization and dedup
    meet only what someone thought to write.
- **Guideline:** TBS §1.2 (search with an oracle); TBS §4.1 (build valid inputs by construction); TBS §5 (swarm).
- **Recommendation:** see §5.

### IDR-A-23: no fixture in scope checks that a pass keeps the program's meaning

- **Category:** wrong-or-missing-oracle. **Severity:** high.
- **Evidence:**
  - Every RUN here checks the shape of the result. The closest thing to a semantic oracle is
    `returns`/`returns-on-paths` (match-enclosing, match-known, match-lit-string).
  - Wrong code with the expected shape passes. Examples: case-of-case swapping two regions' strings;
    record eta rebuilding the wrong constructor; a dispatch calling the wrong label in defunc.
  - Many fixtures already have a root that reads a byte and prints a value (`idr.io.get_byte` …
    `idr.io.put_sint`). Examples: choice, coerce, cycle, growing, lazy*, memo-*, state, sum-names,
    array-moves, contify, dedup.
  - idr/e2e already compiles `.mlir` with `idris-mlir -c` and `%cc`.
- **Guideline:** TBS §7 ("the quality of your testing is almost entirely the quality of your oracle");
  TBS preamble (a second implementation we own).
- **Recommendation:** a differential property in the harness. For each fixture with a root:
  - compile the module as written (stopping at the pass under test is not needed);
  - compile it again after the pass under test;
  - run both on the same stdin bytes and require equal output and exit status.

  The "before" side is the higher-stage program compiled by the full pipeline, so this is the module
  as a second form of itself. Where expected stdout is cheap to state, it is the specification
  (TBS preamble).

### IDR-A-24: ACCEPTANCE notes copied where they do not apply

- **Category:** perception. **Severity:** low.
- **Evidence:**
  - linear-thread, recursive-thread, release-constant and release-copies all carry the same note: "the
    allocation a copy targets: `idr::bufferize::copies` reads a memref.copy into a memref.alloc ...".
    It describes none of their RUN lines.
  - Many defunc notes read "that this test, rewritten to the representation wave's printed forms ...
    parses and passes as before". That records the sweep, not what to check.
- **Guideline:** TBS §9.2 step 5 (an acceptance that cannot be judged checks nothing).
- **Recommendation:** each NEEDS-ACCEPTANCE line names what the reviewer must see in the output. For
  this scope, the acceptance should go through these findings, not the notes.

### IDR-A-25: functions written as negative examples with no assertion

- **Category:** checks-nothing. **Severity:** low.
- **Evidence:**
  - sink-into-regions: @scrutinee and @used_after ("the value stays"). No property names them, though
    the comment says the verifier holds them.
  - contify: "A function called twice, one a closure names, and one only its own call reaches are not
    continuations, and stay" (@twice, @named, @lonely). No property names them.
- **Guideline:** TBS §1.1.
- **Recommendation:**
  - Assert, for example, `calls=@root:@twice,calls=@root:@named`, and for @lonely a `reaches`.
  - For sink-into-regions, delete the two functions, since the verifier states the rule.

### IDR-A-26: canon/facts pins a crash-site count

- **Category:** brittle-overspecified. **Severity:** low.
- **Evidence:** `crash-sites=@delayed_crash:2`. That the crash moved into both regions is how the
  pattern did it. The contract is that the crash still runs on every path, before anything it could
  hide, which `crashes-before-output` and a run state.
- **Guideline:** TBS §1.1.
- **Recommendation:** replace with `checks-every-path`, or a returns/crash run.

## 4. Code bugs the tests reveal

Each entry has the evidence I saw. None was reproduced; I ran nothing.

### 4.1 Null dialect dereference in the folds-balanced contract

- **Paths:** actions/narrow-lanes, actions/returned-arguments.
- **Output:** exit 139, `idr::IdrDialect::foldLeakCount() const` called from `idr::expect::foldsBalanced`
  called from `idr::ContractInstrumentation::runAfterPass`.
- **Cause:** `Expect/Folds.cpp:21` dereferences `getLoadedDialect<IdrDialect>()`. The dialect is not
  loaded when the input holds no idr op and only `--idr-contracts` is given. Confirmed by reading.

### 4.2 Negative fold-leak count

- **Path:** canon/output-fusion.
- **Output:** `expected folds-balanced: -1 cells the folders left live`, broken by canonicalize.
- **Cause:** a folder releases a runtime reference it did not take, or the count is updated on one side
  only. The likely candidates are the folds of pack, concat or put_list over constant lists. Unconfirmed.

### 4.3 idr-rc-stack leaves an unlinked operand

- **Paths:** actions/stack (RUN 4), actions/tail-loops (RUN 1, through idr-rc).
- **Output:** `operation's operand is unlinked`, with `idr.cell.init(<<UNKNOWN SSA VALUE>>, ...)`.
- **Cause:** replacing `idr.cell.new` with a stack cell left the init's operand dangling. Skipping every
  idr-stack-cell action avoids it.
- **Status:** a7bf77b4 changed `Stack.cpp` after the run, so this is probably fixed. Recheck.

### 4.4 idr-rc grading produces IR the graded verifier refuses

- **Paths:** actions/narrow (RUN 1), contracts/nested-run.
- **Output:**
  - `'idr.match_lit' op operand #0 must be a value of a type with literals, read in place, but got '!idr.own<!idr.nat>'`
  - `'idr.return' op returns '!idr.box<...T...>' ... but @both returns '!idr.own<...>'`
  - `'idr.call' ... holds references at the plain grade in a graded program`
- **Cause:** the grades step graded a parameter own where a literal match needs a borrow, and left
  call results and returns plain.
- **Status:** 3d279eb9 may have changed this since. Recheck.

### 4.5 idr-defunctionalize reaches an internal error from verified IR

- **Path:** defunc/nested-sum-failure.
- **Output:** `internal error: the constructor @inner of "fn$.sum.a17d5f89099491ba" has a field of unsupported type 'i1'`.
- **Cause:** the closure verifier accepts a capture that no sum field can hold. That is a representation
  gap (IDR-A-18), not an `unsupported` refusal.

### 4.6 idr-defunctionalize does not finish in 60 s on 65,537 labels

- **Path:** defunc/tag-limit.
- **Output:** `timed out after 60s: idris-mlir-opt`.
- **Cause:** defunc may be superlinear in labels per key (the solve, naming or two-level construction).
  The `--verify-roundtrip --idr-contracts` that lit adds also prints and parses the 65k-function module
  more than once, so part of the time may be the harness's. Unknown which.

### 4.7 The printed form of idr.con differs from its documented form

- **Path:** asm/prefix (and probably asm/names).
- **Output:** `%just = idr.con !M @Just (%inc_1 : i64)`.
- **Cause:** adjacent `custom<CtorRef>` and `custom<Fields>` directives print with a space between them.
  `IdrOps.td` documents `@Cons(%x : i64)`. Cosmetic: both forms parse.

### 4.8 (Not a bug) idr-constants-replace does not fire in actions/inner-steps

- The counter shows `{0,0,0}`. Another step probably computes the value first, as HANDOFF.md predicted.
- I do not count it as a bug (IDR-A-14).

### 4.9 (Uncertain) Field of a constructor that holds a linear closure no longer folds

- **Path:** canon/shared-action.
- **Output:** `reads-no-fields: idr.field reads a field in @twice` and in `@chosen_twice`.
- Either the field-of-con fold now declines linear fields on purpose (the fields are `!idr.lin<fn>`), or
  it regressed. The evidence does not tell which.

## 5. What the rebuilt scope should look like

1. **One corpus, many universal properties.**
   - Keep the hand-written modules worth keeping as a **corpus** (matklad's alphabet drawn from the
     existing tests, TBS §1.2):
     - the defunc shapes: cycle, growing, state, many-labels, memo-*, evaluated-*, grade-*,
       ioref-closure, match-field, untaken-region, unreached-cell;
     - the canon shapes;
     - the bufferize threads;
     - the actions/ modules.
   - The harness (lit.sh or a pool over all fixtures) runs every universal oracle on every corpus
     module and every fixture, with no fixture asking for them:
     - the verifier after every pass (already there);
     - `--idr-contracts` (already there);
     - canonicalize convergence (IDR-A-16);
     - custom-form round trip (IDR-A-16);
     - determinism across threads, and the function-order shuffle (from sum-names, IDR-A-17);
     - the action-skip properties below.
2. **Action properties, generated from data.** Each action is a TableGen record on its pass, which
   generates the C++ tag and a table the harness reads (IDR-A-6). For each (optimization pass, tag)
   × corpus module:
   - skip-all is the identity;
   - skip-one verifies and runs to the same output;
   - a corpus-wide census fails if some tag never fires.

   This replaces all ten actions/ files and inner-steps.
3. **A semantic oracle for every pass in scope** (IDR-A-23). For a corpus module with a root:
   - run it compiled as written, and again with the pass under test applied first;
   - the two must agree on stdout and exit status over a set of stdin bytes (exhaustive over the
     bytes a fixture branches on: 0, 1, 'A' = 65 and others; TBS §8 "exhaust the small cases").

   Expected stdout, where it is cheap, is the specification (TBS preamble). This is the check that
   gives memo-rebuild ("@one does not run twice"), link-read-after-release ("the read sees the value")
   and @twoWrites their meaning.
4. **A generator for higher-order and lazy programs** (IDR-A-22; TBS §4.1-§5).
   - Extend Gen.idr past closed primitive expressions to well-typed-by-construction programs with:
     - closures of a few types, and captures including closures (cycles);
     - suspensions, forced and evaluated;
     - small data types and matches;
     - IORefs of functions;
     - a choice on a stdin byte.
   - The representation is indexed so that every apply names a closure in scope (a harness invariant,
     TBS §4.3), while label sets, cycles and unreached keys stay expressible, including on purpose
     (TBS §4.4: a named "unreached" case).
   - Weights are explicit per run, as swarm testing does it (TBS §5).
   - The oracle is IDR-A-23's differential run, plus Sem's meaning for the primitives.
   - The features that steer it (TBS §6.2) are: (key is boxed/unboxed, labels count bucket, memo/by-name).
   - This generator replaces most of defunc's `no-closures`-only fixtures.
5. **Optimization promises as properties, stated once per promise.**
   - canon/ stays a set of small property fixtures. Its `returns-on-paths` and `grows-nothing`
     vocabulary is the model.
   - Each function's comment claim is a property on its RUN line (IDR-A-3, IDR-A-25), and every
     negative states its reason (IDR-A-5).
   - bufferize keeps `in-place`, `moves-out` and a positive "copies" row, so negatives stop meaning
     "any failure".
6. **Syntax and verifier rules where they belong.**
   - The parse cases of match-regions move to syntax/.
   - The four arrays/ verifier cases and delay-world move to verify/.
   - asm/ keeps aliases and names (the printer's contract), and prefix is rewritten to check prefixes
     only.
7. **The contract checker's mutation tests stay as they are** (contracts/break*, crash-sites). They are
   the model for "every property has a fixture that fails it". Add a fixture of upstream dialects only,
   which would have caught §4.1.
8. **Deleted outright:**
   - canon/apply (removed behaviour);
   - actions/inner-steps (brittle);
   - defunc/growing-lazy (duplicate);
   - the 13 leftover output directories;
   - the `no-closures` and `quantities-kept=%s` assertions after defunc, which repeat the verifier
     and the contracts.
