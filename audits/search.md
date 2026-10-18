<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Lane: search

**Scope.** The search and its oracles: `tests/Gen.idr`, `tests/Fuzz.idr`,
`tests/Sem.idr`, `tests/Prims.idr`, `tests/TwoLevels.idr`, `tests/Lock.idr`;
`tests/fuzz/` (seed-1, seed-2, two-hosts), with `tests/lib/fuzz.sh`;
`tests/two-levels/terms` and `tests/programs/semantics/prim` (the runners of
TwoLevels and Sem); `tests/spec/lock` (the runner of Lock); the runtime
property programs on `tests/toolchain/lib/prop.h` (runtime-bigs, -counting,
-doubles, -strings, -text, -utf8) with `bigmodel.h`, `utf8model.h`,
`prop.sh`; the googletest boxes (`foreign/idr/unittests`,
`foreign/idr/include/idr/Testing/Box.h`, `make test-unit`); the property
checker `idr-expect` (`foreign/idr/lib/Transforms/Expect/`, 82 properties in
`Lookup.cpp`) with its fixtures `tests/idr/expect/`; the pass contracts
(`foreign/idr/lib/Transforms/Contracts/Contracts.cpp`, `--idr-contracts`) with
`tests/idr/contracts/`. The other `tests/toolchain/runtime-*` directories are
listed for completeness, judged only where they touch the search.

**Read.** Both guidelines in full (`testing-by-search`, cited TBS n.m;
`representation-first`, cited RF), AGENTS.md, `tests/README.md`,
`tests/testutils.sh`, every file named above in full except the larger
runtime property sources (`bigs.cpp`, `doubles.cpp`, ...) and the 50
`Expect/*.cpp` property implementations, of which I read the table, the
driver and the ones the fixtures fail on; every fixture's header, `run`,
`expected` and last `output`; the logs `test.log` (make test),
`test-idr.log` (older build), `test-unit.log` (13:35, older binaries).

**Counts.** 115 rows below (each fixture directory, fixture file, or
self-check of the Idris machinery; `programs/semantics/prim` is one row for
its 144 instances, each googletest file one row for its tests: 46 TESTs in
13 files). Verdicts: keep 96, rewrite-as-property 3, rewrite 7, merge 4,
delete 5. Status: 68 rows pass (programs/semantics/prim counted as passing:
all 144 print their expected transcript and differ only by the
NEEDS-ACCEPTANCE line), 12 fail, 32 unknown (googletest boxes not
built or not rerun, Gen/Fuzz self-checks never ran on idris-mlir because
two-hosts did not compile), 3 are directories with no test. 30 findings, 6 code bugs or plausible code bugs.

Status is from each directory's `output` against its `expected` (or
`expected.<host>`), which is the last run on this machine; googletest status
is from `test-unit.log`, whose binaries predate the current build (they were
rebuilt at 16:06 and the log is from 13:35).

---

## 1. Verdict table

### 1.1 The Idris machinery's own checks (Gen, Sem, TwoLevels, Fuzz)

These run inside `tests/fuzz/two-hosts` on idris-mlir (and, through the
runner, on the stock host). Their status is the stock host's where the
runner prints them; on idris-mlir they never ran (two-hosts did not
compile).

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| `tests/Gen.idr` checks: "splitmix64 from state 0, output 0/1/2" (3 rows) | Gen's `caseSeed` gives Vigna's published outputs | keep | a specification oracle, published vectors (TBS 7) | unknown on idris-mlir |
| `Gen.checks`: "replaying the tape of seed 1/2/3 gives its case" (3 rows) | `replay (seeded s).tape == seeded s` | keep | the replay contract, stated as a relation (TBS 1.1, 11) | unknown |
| `Gen.checks`: "seededEach gives each seed's case on one tape" | tape reuse changes no case | keep | relation between two entry points (TBS 7, second implementation) | unknown |
| `Gen.checks`: "every tape of pair: six values" | odometer enumerates a product | keep | small-scope exhaustion of the enumerator itself (TBS 8) | unknown |
| `Gen.checks`: "every tape of dep, in the odometer's order" | dependent bounds enumerate in order | keep | as above; order is the documented contract here | unknown |
| `Gen.checks`: "an enumeration past its limit is not whole" | `whole` is False on limit | keep | the box's honesty about its scope (TBS 8) | unknown |
| `Gen.checks`: "an enumeration past its capacity is not whole" | `whole` is False on overrun | keep | same | unknown |
| `Gen.checks`: "weighted picks by the running total, never an option of weight 0" | zero weight never drawn | keep | the zero-weight trap, checked (TBS 5) | unknown |
| `Gen.checks`: "swarm zeroes every option on some tape and keeps it on another" | swarm reaches every corner | keep | swarm's contract (TBS 5) | unknown |
| `Gen.checks`: "every candidate is before its tape in shortlex order" | shrink candidates are smaller, on 3 tapes | rewrite-as-property | three hand-picked tapes where `exhaustive` over all tapes of length <= 4, values <= 3 makes it a theorem in a box (TBS 8 small scope) | unknown |
| `Gen.checks`: "shrinking ends at a failing tape no candidate of which fails" | shrink is a local minimum, one tape, one predicate | rewrite-as-property | same: exhaust small tapes and a few predicates (TBS 8) | unknown |
| `Gen.checks`: "a draw's loop sums the same seeded and replayed" | the loop `mlir.expect` reads exists and agrees | keep | needed by the two-hosts mlir.expect; a relation (TBS 7) | unknown |
| `Gen.idr` 0-proofs `pairCount`, `depValues`, `depWhole`, `depLimited`, `replayPast` (5 rows) | the same facts as Refl at type-check time | keep | worst-case proofs are stronger than the runtime checks (TBS 8, 13); the runtime twins exist for the second host | pass (stock Idris type-checks Gen) |
| `Sem.checks`: "every table holds at most 120 cases" | Sem's own constant table stays under a budget | delete | checks the test's own constant, not the compiler; it cannot fail on any compiler change (cannot-fail, TBS preamble) | unknown |
| `TwoLevels.checks`: "every primitive has an argument set" | the corpus covers `Prims.prims` | keep | a coverage guard of the generator against its table (TBS 8.3: absent, not rare) | unknown |
| `TwoLevels.checks`: "every term's text is unique" | expected-file keys unique | keep | harness invariant (TBS 4.3) | unknown |
| `TwoLevels.checks`: "no term's text holds ' = '" | key/value separator never in a key | keep | harness invariant (TBS 4.3) | unknown |
| `Fuzz.checkerChecks` (2 rows) | the fuzz verdict names no case on agreeing output, names case 2 on a planted disagreement | keep | testing the oracle, matklad's "a bug in the fuzzer first" (TBS 1.2) | unknown |
| `TwoLevels.checkerChecks` (2 rows) | the two-levels verdict on agreeing and planted output | keep | same (TBS 1.2) | unknown |

### 1.2 Test directories run by `make test`

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| `tests/fuzz/seed-1` | 30 generated closed expressions per part, four renderings each, agree; every d line folded; integer cases match `Prims` meaning | rewrite | right oracles, wrong search: fixed seed, unrun checks print `ok`, compile failures are never isolated or shrunk, every pass dumped (SEARCH-1, -2, -3, -6, -9) | fail: compile timed out at 60 s, both parts |
| `tests/fuzz/seed-2` | same on seed 2 | merge-into:`tests/fuzz/seed-1` | a second fixed seed is a second regression sample, not a search; one test over a seed corpus (TBS 1.2, 8) | fail: compile timed out at 60 s, both parts |
| `tests/fuzz/two-hosts` | idris-mlir compiles Gen/Prims/Fuzz/Sem/TwoLevels and prints `Fuzz.twoHosts` byte for byte as the 3652-line `expected-stdout`; mlir.expect on `Gen.drawLoop`, `Gen.reverseOnto` | rewrite | the check lines are properties and stay; the 3600 lines of generated programs, tapes, shrink candidates and term texts are a frozen stock-host run, unreviewable, rewritten by every generator change (SEARCH-4) | fail: compile exit 124 after 600 s, plus "File name too long" from the dump tree |
| `tests/two-levels/terms` | every primitive on chosen literals, and 48 Prelude terms, print the values `expected-primitives` / `expected-prelude` record | rewrite | integer values duplicate `Prims`' meaning as a recorded table, the missing 56 values are to be taken from the compiler's own output (self-oracle), the prelude corpus is example-based (SEARCH-5) | fail: primitives compile timed out at 60 s; prelude compile internal error `'llvm.call' op operand type mismatch` |
| `tests/programs/semantics/prim` (144 instances, `prim@prim-<type>-<op>`) | each fixed-width op on edge values equals `Prims`' meaning; heap-free | rewrite | the oracle is right and independent; but 144 compilations of programs that fold entirely to the constant 0 check only the folders, never codegen, and never say which path ran (SEARCH-7) | pass pending acceptance: all 144 outputs identical to expected but for the NEEDS-ACCEPTANCE line |
| `tests/spec/lock` (`tests/Lock.idr`) | every tool in `toolchain.lock.json` is pinned by revision, repository, version and tag/describe; accepted series hold the version | keep | a specification check of a data file; no search involved (TBS 9) | pass |

### 1.3 Runtime property programs (prop.h)

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| `tests/toolchain/runtime-bigs` | runtime bigs equal GMP's arithmetic, laws hold, small path = large path, ownership; two boxes over edge values and shift amounts | keep | spec oracle (GMP, laws) and boxes; property lines only (TBS 1.1, 7, 8) | pass |
| `tests/toolchain/runtime-counting` | RC and arrays agree with a model after every operation; nothing live at the end | keep | model-based testing, the strongest thing in the lane (TBS 9) | pass |
| `tests/toolchain/runtime-doubles` | `show_f64` judged on the exact interval, layout, `str_to_double` vs strtod, round trip, ownership | keep | spec oracle (exact interval) plus a second implementation (strtod) (TBS 7) | pass |
| `tests/toolchain/runtime-strings` | string ops equal a scalar model, canonical results, borrow/own; box of all strings of <= 3 scalars | keep | model plus small-scope box (TBS 8, 9) | pass |
| `tests/toolchain/runtime-text` | integer text vs snprintf/GMP, a literal grammar generated with values, named malformed literals, box of <= 3 chars | keep | generator of valid and named invalid inputs (TBS 4.4) | pass |
| `tests/toolchain/runtime-utf8` | UTF-8 decoding vs a Chapter 3 model, boxes at simdutf block boundaries | keep | spec model and boundary boxes; "moving the bug into the box" (TBS 8) | pass |
| `tests/toolchain/runtime-api` | (not a prop.h program) RC frees what it counts | keep (outside this lane's criteria) | example program; see repo-tests lane | pass |
| `tests/toolchain/runtime-archive-check` | (not prop.h) the archive check | keep (outside) | see repo-tests lane | pass |
| `tests/toolchain/runtime-container` | (not prop.h) prepared runtime keeps its bitcode | keep (outside) | see repo-tests lane | fail (container output differs) |
| `tests/toolchain/runtime-prepared` | (not prop.h) prepared runtime's symbols within allowlist | keep (outside) | see repo-tests lane | fail: "needs what its target's allowlist does not allow" |
| `tests/toolchain/runtime-start` | (not prop.h) entry, reserved stack | keep (outside) | see repo-tests lane | pass |
| `tests/toolchain/runtime-triple` | (not prop.h) triple comparison | keep (outside) | see repo-tests lane | pass |
| `tests/toolchain/runtime-page-size` | nothing: the directory holds only an untracked `output` from 2026-10-04 | delete | stale directory, no run, no expected (TBS preamble: checks nothing) | no test |

### 1.4 The googletest boxes (`foreign/idr/unittests`)

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| `Ranges.cpp` (8 tests) | range rules hold every member pair of every interval over D64, exact where promised; `ofInteger`, `boundsOf`, `ofType` | keep | small-scope exhaustion, soundness as a property (TBS 8) | pass (7 of 8 ran: the binary predates `OfType`) |
| `Hooks.cpp` (3 tests) | the big ops' range hooks contain the runtime's value of every member | keep | exhaustive box against the runtime as oracle (TBS 7, 8) | fail: segfault in `Hooks.Pred` (old binary); the other two never ran |
| `HooksCompare.cpp` (2 tests) | a decided comparison agrees with the runtime's order; `to_int` within its range | keep | same | unknown: in the `hooks` binary, after the segfault |
| `Words.cpp` (3 tests) | each big op's word op (from the ODS table) folds to the runtime's value on B; the mask; fits32 | keep | the generated table checked against its meaning (RF one fact, TBS 7) | fail: segfault in `Words.EachBigOpIsItsWordOp` (old binary); `Mask`, `Fits32` never ran |
| `Tagged.cpp` (8 tests) | the runtime's tagged small paths equal exact `__int128` arithmetic on B | merge-into:`tests/toolchain/runtime-bigs` | the same contract as runtime-bigs' "small path = large path" and its edge box, in a second harness (RF one fact, one place; SEARCH-15) | pass |
| `TaggedBits.cpp` (7 tests) | bitwise and shifts' small paths, every amount where a shift changes | merge-into:`tests/toolchain/runtime-bigs` | same; B and the amount sets become prop.h boxes | pass |
| `Constants.cpp` (4 tests) | `#idr.con` has one form for lists of every length to 64, trees, runs, remap names | keep | exhaustive over a size bound (TBS 8) | unknown (box `ir` not built at the logged run) |
| `Flow.cpp` (3 tests) | the flow rule at every stage; each upstream op's external model | keep | enumerates every external model (TBS 8.3: absent, not rare) | unknown |
| `Sources.cpp` (2 tests) | `sourceOf` on one parsed function | keep | two examples of a structural rule; low value, cheap; see SEARCH-16 | unknown |
| `Verify.cpp` (1 test) | the pass manager verifies the program's rules after a program pass | keep | the one infrastructure invariant it states is essential (RF limit) | unknown |
| `Cycles.cpp` (2 tests) | `CallCycles` on one hand-written call graph; a declaration is its own component | rewrite-as-property | an analysis with an obvious model (mutual reachability) checked on one example; exhaust every call graph on <= 4 functions (TBS 8, 9; SEARCH-16) | unknown |
| `Labels.cpp` (1 test) | the label solve names one node for a parameter and its block argument | merge-into:`tests/idr/expect/closures.mlir` | idr-expect already states `labels=` at a parameter (`arg<n>`); one vocabulary (Winters' vocabulary, TBS 1.1; RF one fact) | unknown |
| `Identities.cpp` (2 tests) | `givesBackOf` through a call that may or may not diverge | keep | the rule's two essential cases | unknown |

### 1.5 idr-expect fixtures (`tests/idr/expect/`)

Every fixture is a meta-test of the oracle: a RUN where the property holds
and a `-verify-diagnostics` RUN where it fails. That is the right shape
(TBS 1.2: test the fuzzer's oracle). The common defect, the full error text
pinned in `expected-error {{...}}`, is SEARCH-11; the rows below are kept
with that rewrite applied suite-wide.

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| `allocation` | no-heap-allocation holds of @scalar, fails at @cons via @boxes | keep | positive and negative of one property | pass |
| `apart` | apart fails at a function made from both | keep | same | pass |
| `by-name` | by-name / not-by-name read memo labels | keep | same | pass |
| `calls` | the call properties (calls, never-calls, calls-distinct, calls-read, calls-only, direct-calls, ...) | keep | same | pass |
| `closures` | labels and no-closures | keep | same | pass |
| `computes-nothing` | computes-nothing | keep | same | pass |
| `constant-stack` | constant-stack and tail-calls | keep | same | pass |
| `continuations` | contified | keep | same | pass |
| `counted-loop` | counted-loop | keep | same | pass |
| `counting` | reuses-in-place, counts-nothing, reuses-every-cell after idr-rc | keep | the expectation is right; the failure is idr-rc's (code bug 1) | fail: idr-rc output does not verify (`idr.match` operand owned; `idr.return` type mismatch) |
| `coverage` | every property has a fixture where it fails | rewrite | reads the table with sed and accepts the text `expected <name>: ` anywhere in a .mlir, so a comment satisfies it (SEARCH-12) | pass |
| `crash-sites` | crash-sites counts | keep | positive and negative | pass |
| `dims-known` | dims-known | keep | same | pass |
| `does` | the eight "does" properties and their complements | keep | same | pass |
| `facts` | test-idr-facts remarks; RUN 2 `%status 1` after canonicalize | rewrite | RUN 2 passes on any failure at all, and it pins canonicalize erasing a dead call, upstream's incidental behaviour (SEARCH-13) | pass |
| `folded` | folded | keep | used by the fuzzer's folded check | pass |
| `fused` | fused | keep | but no program states it (SEARCH-14) | pass |
| `growth` | grows-nothing | keep | positive and negative | pass |
| `guards` | no-guards | keep | same | pass |
| `in-place` | in-place | keep | same | pass |
| `largest-function` | largest-function and its malformed bound | keep | same | pass |
| `linker-names` | linker-names | keep | same | pass |
| `lowered` | lowered, in-llvm | keep | same | pass |
| `malformed` | an argument of the wrong shape is refused at the request | keep | the checker refuses rather than passes (TBS preamble: cannot-fail guard) | pass |
| `memory` | aligned-access, reads-nothing, writes-nothing | keep | positive and negative | pass |
| `moves-out` | moves-out | keep | same | pass |
| `narrowed-lanes` | narrowed-lanes | keep | same | pass |
| `not-called` | not-called, copies found by location | keep | same | pass |
| `one-clone` | one-clone, specialized-once | keep | same | pass |
| `one-clone-two-copies` | one-clone fails when calls reach two copies | keep | same | pass |
| `output-fused` | output-fused | keep | same | pass |
| `paths` | loops, straight-line | keep | `loops=n` is exact; see SEARCH-14 | pass |
| `placement` | builds-where-used, calls-where-used, matches-once, crashes-before-output, parameters-used, results-used, regions-distinct, checks-every-path | keep | positive and negative | pass |
| `proved` | total / not-total | keep | same | pass |
| `quantities` | quantities-kept against variants made by sed | keep | the AGENTS.md linearity rule's checker, its variants named (TBS 4.4) | pass |
| `reaches` | reaches | keep | same | pass |
| `resets-unshared` | resets-unshared | keep | same | pass |
| `returns` | returns, returns-argument, returns-on-paths | keep | same | pass |
| `reuses-every-cell` | reuses-every-cell | keep | same | pass |
| `signature` | signature, convention, entry | rewrite | fails only because the message now quotes the types; pins the checker's wording (SEARCH-11) | fail: `expected error "... (i64) -> i64, not (i64) -> i32" was not produced` |
| `solved-effects` | effects | keep | same | pass |
| `stage` | stage | keep | same | pass |
| `structured-loops` | structured-loops | keep | same | pass |
| `tests-nothing` | tests-nothing, exclusive-copy | keep | same | pass |
| `typed-reads` | typed-reads on `tensor.extract` after `idr.check.in_bounds` | delete | the dialect no longer lets `idr.check.in_bounds` take a tensor, and no other test states the property: the fixture and the property describe removed behaviour (stale-legacy; RF delete what is dead) | fail: `'idr.check.in_bounds' op operand #1 must be a string, read in place or an array ...` |
| `unknown` | an unknown property name is refused | keep | the misspelling guard (TBS preamble: cannot-fail) | pass |
| `vectorized` | vectorized | keep | same | pass |
| `words` | word-loop | keep | same | pass |
| `breakers` | nothing: only an untracked `output` | delete | stale directory | no test |
| `breaks-last` | nothing: only an untracked `output` | delete | stale directory | no test |

### 1.6 Pass contracts (`tests/idr/contracts/`)

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| `break` | the contracts name a pass that widens effects; idr-effects keeps them | keep | the checker tested on a planted break (TBS 1.2) | pass |
| `break-linear` | linear-kept names a pass that unrestricts a linear result | keep | same | pass |
| `crash-sites` | crash-sites-not-added at @f despite a lambda of f's name | keep | same | pass |
| `nested-run` | idr-rc keeps its contracts across its own nested pipeline | keep | the expectation is right; the failure is idr-rc's (code bug 1) | fail: `idr.return` returns `!idr.box` where `@both` returns `!idr.own<...>`; a plain-grade `idr.call` result in a graded program |

---

## 2. Findings

### SEARCH-1: a check that never ran prints `ok`
- **Category:** cannot-fail, perception. **Severity:** high.
- **Paths:** `tests/lib/fuzz.sh` (`fuzz`, `fuzz_check`, `fuzz_report`); `tests/fuzz/seed-1/output`, `seed-2/output`.
- **Evidence:** `fuzz_check` returns as soon as the compile fails (`if [ "$compiled" -ne 0 ]; then ... return`), leaving `fuzz.agree`, `fuzz.folded`, `fuzz.model` empty, and `fuzz_report` prints `ok` for an empty file. The last run:
  ```
  runtime: every build compiles, runs, exits 0 and writes nothing on stderr: failed
  1: compile exit 124
    | timed out after 60s: compile.sh
  runtime: each case prints one value, whoever computes it: ok
  runtime: every d line is folded: ok
  runtime: each case over integers prints its documented value: ok
  ```
- **Guideline:** TBS 9.2 step 5 ("Check that the real system actually entered each state ... Otherwise the test can silently check nothing"); TBS preamble (a check that cannot fail is deleted); RF SPOV2 (a validator that discards what it learned).
- **Recommendation:** make the verdict a sum, not an empty file: each check reports `ok`, `failed`, or `not run: <the step that failed>`. In `fuzz_report`, an unrun check is a failure line of its own. The same applies wherever the transcript prints a property line after an earlier step failed.

### SEARCH-2: the fuzzer is a regression test on two fixed seeds, not a search
- **Category:** distribution, perception. **Severity:** high.
- **Paths:** `tests/fuzz/seed-1/run` (`fuzz 1`), `seed-2/run` (`fuzz 2`), `tests/lib/fuzz.sh` (`fuzz_cases=30`); every prop.h run (`--seed 1`).
- **Evidence:** `fuzz 1`, `fuzz 2`, `fuzz_cases=30`: the same 120 cases every run, forever. Every runtime property program runs `prop_run "$work/bigs" --seed 1 --cases 20000` and so on. No make target, script or corpus runs fresh seeds; `grep -n fuzz Makefile` shows only the pool name.
- **Guideline:** TBS 1.2 (randomize the generator's own settings each run), TBS 5 (swarm per run), TBS 8 (a stopping rule and a residual risk, not "it ran").
- **Recommendation:** split the two jobs. (a) The regression test runs a committed corpus of tapes (every tape that ever failed, plus a few seeds), deterministic. (b) A `make fuzz` target draws seeds from the clock, runs until a budget or a Good-Turing threshold, and appends each failing tape (already shrunk) to the corpus. Swarm already exists per case; it should also cover per-run settings (depth bound, cases per program, thread count, the transforms switched off: SEARCH-10).

### SEARCH-3: a compile failure, the commonest failure of a compiler fuzzer, is neither isolated nor shrunk
- **Category:** perception, infrastructure-gap. **Severity:** high.
- **Paths:** `tests/lib/fuzz.sh` (`fuzz`, `fuzz_shrink`).
- **Evidence:** shrinking runs only for the agree and model checks: `case $fuzz_failing in *' agree') fuzz_shrink ...` and `*' model') ...`. A compile crash, a verifier error, an internal error or a timeout reports `"$fuzz_seed: compile exit $compiled"` and the first 10 lines of the log for a program of 30 cases, with no case named and no tape.
- **Guideline:** TBS 1.2 (small inputs; when a bug slips past, fix the fuzzer first), TBS 8 (small-scope hypothesis: the failure has a small counterexample).
- **Recommendation:** on a compile failure, first bisect the case list (delta debugging over the 30 cases, each subset a program `--fuzz-program replay` can already build), then shrink the remaining case's tape with the existing `Gen.shrink`, keeping a candidate when the compile fails with the same diagnostic (the error's first line, with the location stripped). `idris-mlir-reduce` exists in `foreign/idr/tools` for the module-level reduction that follows.

### SEARCH-4: two-hosts pins 3600 lines of generator output that a stock-host run produced
- **Category:** brittle-overspecified, wrong-or-missing-oracle. **Severity:** high.
- **Paths:** `tests/fuzz/two-hosts/{run,expected-stdout,mlir.expect}`, `Fuzz.twoHosts`.
- **Evidence:** `expected-stdout` is 3652 lines; after the 24 check lines it holds `== program 1 3 runtime main` (whole generated programs), `== tape 1 2 runtime`, `== shrink 1,0,0,1,...` (every shrink candidate), `== sem prim-int-add`, `== two-levels primitives terms` (3170 lines of terms). The run script admits it: "a change to the five modules that changes the text rewrites the file in the same change". No reviewer reads 3000 lines of generated terms; the file can only have come from running the modules on the stock host, which is a Chez comparison by another route.
- **Guideline:** TBS preamble (a transcript that pins incidental output is brittle; Chez is no oracle), TBS 1.1 (assert the contract, not the instance), AGENTS.md "There is no oracle".
- **Recommendation:** keep the self-check lines (`gen: ...: ok`, `sem`, `two-levels`, `fuzz-check`), which are properties the program checks of itself and which hold on any host. Delete the request sections. To test idris-mlir's compilation of the generators, add more self-checks of the kind that need no recorded output: replay is the inverse of seeded over 100 seeds, every shrink candidate is `Below` and shortlex-smaller, `parseTape . tapeText = Just`, every generated case's leaves equal `inputs` in order. Move the `mlir.expect` on `Gen.drawLoop` and `Gen.reverseOnto` to a program test of its own (`programs/linear`), where it states a compiler property, not a property of the search.

### SEARCH-5: TwoLevels records integer values that `Prims` already computes, and fills gaps from the compiler under test
- **Category:** redundant, wrong-or-missing-oracle. **Severity:** high.
- **Paths:** `tests/two-levels/terms/{expected,expected-primitives,expected-prelude}`, `tests/TwoLevels.idr`.
- **Evidence:** `expected-primitives` lines such as `(prim__add_Int 9223372036854775807 (-7)) = 9223372036854775800` are exactly `wrap (width FInt) (a + b)`, which `Prims.wrap`, `quotient`, `remainder`, `bitwise`, `shifted` compute and `Sem` and `Fuzz.meaning` already use. The expected file says: "expected-primitives lacks the values of the terms added for the 56 primitives TwoLevels did not cover; add each "no expected value" line the owner's build prints, after review". Those values would come from the compiler being tested.
- **Guideline:** RF "one fact, one place" (a fact held in a test and in the oracle), TBS 7 (the oracle must be independent of the system), AGENTS.md (a primitive's meaning is the runtime's documented semantics).
- **Recommendation:** split the corpus by oracle. Integer terms: compute the value from `Prims` (as `Fuzz.modelled` does) and merge them into the Sem rewrite (SEARCH-7). Double, Char and String terms whose value IEEE or the runtime's documentation fully determines: keep a recorded table, but only for terms whose recorded value is derived and reviewed against the documentation, one line per term, never accepted from the compiler's output. The prelude corpus (48 example terms such as `show [1 .. 5]`) is example-based and belongs with `tests/programs/prelude`, the topic for Prelude functions (I did not check which of these outputs it already covers); merge what it lacks there and delete the rest.

### SEARCH-6: every compilation dumps every pass of every function to disk, for one check that reads one step
- **Category:** infrastructure-gap, harness-representation. **Severity:** medium (high for the fuzz pool's time limit).
- **Paths:** `tests/lib/mlir.sh` (`dump_options`), `tests/lib/fuzz.sh` (`compile_program ... $(dump_options "$fuzz_dumps")`).
- **Evidence:** `dump_options` gives `--mlir-print-ir-after-all --mlir-print-ir-tree-dir=$1 --mlir-print-debuginfo`; the fuzzer reads only `step_module idr-optimize`. two-hosts output: 975 lines of `Error while creating directory .../idr_func_Prelude.Interfaces.foldMap[Data.DPair.Subset.Subset (Prelude.Basics.List Prelude.Types.Nat) (Gen.Below _), ...]: File name too long` in test.log, followed by `compile: exit 124`.
- **Guideline:** TBS 7 (co-design the system for testing: make the observation cheap), RF "use the infrastructure".
- **Recommendation:** dump only the steps a test's checks read: `--mlir-print-ir-after=<pass>` (MLIR's own option) for the fuzzer's `idr-optimize`, and for e2e fixtures the steps named in their `mlir.expect`. This also removes the dump-path failure from tests that never read the dump. The name-length bug itself is code bug 4.

### SEARCH-7: Sem compiles 144 programs that fold to one constant, checking the folders only
- **Category:** perception, distribution. **Severity:** medium.
- **Paths:** `tests/Sem.idr`, `tests/programs/semantics/prim`, `tests/lib/e2e.sh` (`sem_case`).
- **Evidence:** the header claims "this compiler computes every case, with compile-time evaluation and without it", but every case is a primitive applied to literals (`lit`), and `result` is a closed term, so it folds to `0`. Nothing checks which path ran: there is no `folded` property and no run-time input. 144 separate compilations, each printing one `0`, report only the first disagreeing case's number.
- **Guideline:** TBS 9.2 step 5 (check that the system entered the state the test claims), TBS 8 (small-scope exhaustion is the right idea here), TBS 7 (the folders and the code generator are two implementations; compare them).
- **Recommendation:** one program per type (9 programs, not 144), each case written twice, as in Fuzz: once on literals (folded, checked with `folded=@...`) and once on values read from stdin (run time). Both are held to `Prims`' meaning, and a failure prints the case's expression, operands and both values, not a number. Absorb TwoLevels' integer terms (SEARCH-5) into the same tables.

### SEARCH-8: the preconditions are encoded as constraints, so the crash paths are never searched
- **Category:** example-should-be-property, distribution (TBS 4.3 trap). **Severity:** medium.
- **Paths:** `tests/Prims.idr` (`Domain`: `NonZero`, `NonEmpty`, `Finite`, `SmallShift`, `IndexInto`), `tests/Fuzz.idr` (`origin`, `literal`, `castPool`).
- **Evidence:** `divisor (TIntegral _) = NonZero`; `whole StrHead (Param TString NonEmpty Done) TChar`; `StrIndex (Param TString NonEmpty (Param int (IndexInto Here) Done))`; `operand TDouble (TIntegral _) = Finite`. The comment says "the primitive's documented precondition, whose breach ends the program". The generator can never draw a division by zero, an empty `strHead`, an index past the string, or a cast of NaN, so the guards `idr-lower` inserts (`idr.check.nonzero`, `idr.check.in_bounds`, ...) and their messages are never fuzzed, nor are the passes that try to prove them away (`no-guards`).
- **Guideline:** TBS 4.3 ("encode the invariants of your test harness, not the expected behavior of the system under test"), TBS 4.4 ("represent the invalid cases too, by name").
- **Recommendation:** the `Domain` constructors already name each breach; add a generator mode that draws the breach on purpose (`Breach NonZero` gives 0, `Breach (IndexInto el)` an index at or past the end), and judge such a case by its own oracle: the program exits as a crash with the documented message, and nothing it should have printed before the crash is missing (`crashes-before-output`). Weight it explicitly, low, and let swarm turn it on.

### SEARCH-9: accidental bias, comparisons and casts dominate every integer node
- **Category:** distribution. **Severity:** medium.
- **Paths:** `tests/Fuzz.idr` (`weightIn`, `node`, `families`), `tests/Prims.idr` (`prims`).
- **Evidence:** a production's weight is its family's weight (`weightIn kept (Apply p) = index (familyIndex (family p.op)) kept`), so a family's share at a node is proportional to how many primitives it has of that type. For an `Int` node at run time, with every family kept: 60 comparisons (`compareOn op t | t <- primTypes`, 12 types without Integer, times 5) out of 84 productions, 71%; casts to Int 11, and arithmetic, division, shifts and bitwise 11 together. For `Bits8`: 11 casts out of 22. Since a comparison yields 0 or 1, most `Int` subexpressions are 0 or 1, and the wide-value arithmetic the model checks is rare. The comment says "every primitive of a kept family is as likely as each other", but no one chose the families' shares.
- **Guideline:** TBS 5 ("a strong, invisible bias ... chosen by nobody"; make the distribution an explicit value).
- **Recommendation:** draw in two stages, family first (by the swarmed family weights), then a primitive within it, so each family's share is the weight written. Report the realised family and type histogram per run (SEARCH-17) to keep it visible.

### SEARCH-10: there are oracles for every optional transform that the search does not use
- **Category:** wrong-or-missing-oracle, infrastructure-gap. **Severity:** high.
- **Paths:** `foreign/idr/tools/idris-mlir.cpp` (no `ContractInstrumentation`), `foreign/idr/tools/idris-mlir-opt.cpp:66` (adds it), `tests/lib/lit.sh:79` (contracts only on idris-mlir-opt), `tests/idr/actions/*.mlir` (`-mlir-debug-counter=idr-accumulate-countdown-count=0,...`).
- **Evidence:** `--idr-contracts` runs only on dialect fixtures: `sed ... 's/idris-mlir-opt /idris-mlir-opt --verify-roundtrip --idr-contracts /g'`. The driver that compiles every fuzz case, Sem table and e2e program attaches no contract instrumentation. Every optional transform is an MLIR action that a debug counter can skip (the actions tests do exactly that), yet no test compiles a program with transforms skipped and compares outputs.
- **Guideline:** TBS 7 (a second implementation; a universal oracle), TBS 5 (domain randomization: randomize the system's own settings), TBS 2 (feedback narrowing: a debug counter bisects to the one action instance at fault).
- **Recommendation:** (a) register `--idr-contracts` in `idris-mlir` and turn it on for every fuzz compile: each generated program then checks five relations at every pass boundary for free. (b) For each fuzz program, compile a second time with a random subset of actions skipped (`-mlir-debug-counter=<action>-count=0`), swarm-style, and require the same output: a differential oracle for every optional transform. On a mismatch, bisect with `<action>-skip=N,count=1` to the one rewrite, as LLVM's opt-bisect does.

### SEARCH-11: the oracle's own fixtures pin the checker's full error text
- **Category:** brittle-overspecified. **Severity:** medium.
- **Paths:** every `tests/idr/expect/*.mlir` and `tests/idr/contracts/*.mlir` `expected-error {{...}}`.
- **Evidence:** `signature` fails today only because the checker now quotes the types: `expected signature: @plain has the type '(i64) -> i64', not '(i64) -> i32'` against `{{expected signature: @plain has the type (i64) -> i64, not (i64) -> i32}}`.
- **Guideline:** TBS 1.1 (Winters: the contract here is "this property fails at this op for this function", not its wording), AGENTS.md (a test that goes stale on an unrelated change was a bad test).
- **Recommendation:** MLIR's `-verify-diagnostics` already matches a substring at a location. Write each expectation as the property name and the function, `{{expected signature: @plain}}`, which the coverage test (SEARCH-12) can still find. Keep the full wording only in `malformed.mlir` and `unknown.mlir`, whose contract is the wording of a refusal.

### SEARCH-12: the coverage test reads C++ with sed and accepts a comment as a failing fixture
- **Category:** harness-representation, cannot-fail. **Severity:** medium.
- **Paths:** `tests/idr/expect/coverage/run`.
- **Evidence:** `sed -n 's/^ *property<[^>]*>("\([^"]*\)".*/\1/p' foreign/idr/lib/Transforms/Expect/Lookup.cpp` then `grep -qF "expected $name: " tests/idr/expect/*.mlir`. Any line containing the text satisfies it, a comment or a dead fixture included, and a reformatting of `Lookup.cpp` empties the list (the test only says `properties: none found`).
- **Guideline:** RF ("every string that names a thing is a missing type"; parse at the boundary), TBS preamble (a check that cannot fail).
- **Recommendation:** have `idris-mlir-opt` list the table (`--idr-expect-list`, from the one `properties[]` array), and require, per property, a RUN line whose `--idr-expect=holds=` names it and which carries `-verify-diagnostics` with an `expected-error` naming it. lit's own parsing of RUN lines (`tests/lib/lit.sh`) can provide that.

### SEARCH-13: an expected failure that any failure satisfies
- **Category:** cannot-fail, brittle-overspecified. **Severity:** low.
- **Paths:** `tests/idr/expect/facts.mlir` RUN 2.
- **Evidence:** `// RUN: %status 1 idris-mlir-opt %s --idr-effects --canonicalize --test-idr-facts -verify-diagnostics=only-expected -o /dev/null`. It passes for a parse error, a crash or any verifier error. Its intent, that canonicalize erases an unused pure call, is upstream's behaviour and none of this property's contract.
- **Guideline:** TBS 1.1, TBS 9.2 step 5.
- **Recommendation:** delete RUN 2. If "a call idr-effects proved pure may be erased" matters, state it as a property of the erased module (`not-called=@square` after `--canonicalize`).

### SEARCH-14: vocabulary no test uses, and exact counts where the contract is a bound
- **Category:** stale-legacy, brittle-overspecified. **Severity:** low.
- **Paths:** `foreign/idr/lib/Transforms/Expect/Lookup.cpp`; `tests/idr/expect/typed-reads.mlir`, `fused.mlir`, `paths.mlir`.
- **Evidence:** a scan of `tests/` outside `tests/idr/expect/` finds no use of `typed-reads` or `fused`, and one use of each of 12 others (`by-name`, `not-total`, `specialized-once`, ...). `typed-reads`' own fixture no longer parses (`idr.check.in_bounds` refuses a tensor). `loops=n`, `crash-sites=n` and `call-order` state exact counts and orders.
- **Guideline:** RF ("delete what the representation makes dead in the same change"), TBS 1.1 (an exact count is brittle unless the contract fixes the count).
- **Recommendation:** delete `typed-reads` with its fixture. Give `fused` a program test (`programs/arrays`: `map f (map g xs)` is one loop) or delete it. Audit the program-side uses of `loops=n`, `crash-sites=n` and `call-order` for contracts that are really bounds (`crash-sites<=n`, `loops>=1`) and add those forms.

### SEARCH-15: two harnesses check the runtime's big arithmetic against exact arithmetic
- **Category:** redundant, harness-representation. **Severity:** low.
- **Paths:** `foreign/idr/unittests/Tagged.cpp`, `TaggedBits.cpp`; `tests/toolchain/runtime-bigs/bigs.cpp` ("small path = large path on small operands", "box: every pair of edge values, every operation", "box: every edge value shifted by every amount in [-130, 130]").
- **Evidence:** both walk small values near powers of two and the small range's ends through the same C entries (`Abi<idr::BigAddOp>::function`, ...) against `__int128` or GMP. The googletest version links MLIR to call the runtime; the prop.h version links as a program does.
- **Guideline:** RF ("one fact, one place"; a fact held twice drifts), AGENTS.md "One thing, one representation".
- **Recommendation:** move `boxB()` and the shift amount sets into `runtime-bigs` as `run.box` entries (prop.h has boxes), and delete `Tagged.cpp` and `TaggedBits.cpp`. The googletest boxes keep what needs MLIR: ranges, hooks, the word table.

### SEARCH-16: analyses with an obvious model are tested on one hand-written example
- **Category:** example-should-be-property. **Severity:** medium.
- **Paths:** `foreign/idr/unittests/Cycles.cpp`, `Labels.cpp`, `Sources.cpp`.
- **Evidence:** `CallCycles, MutualSelfAndLeaf` checks one six-function program (`EXPECT_EQ(cycles.components().size(), 5u)`, `together(even, odd)`, `callsItself(loop)`).
- **Guideline:** TBS 1.1 (Winters' `DefaultConfigsArePrime`: the property names no input), TBS 8 (exhaust the small cases), TBS 9 (a model as oracle).
- **Recommendation:** generate every call graph on at most 4 functions (2^16 edge sets, each a parsed `idr.program` built by a helper) and check `CallCycles` against reachability computed by Floyd–Warshall: `together(f, g)` exactly when each reaches the other, `callsItself(f)` exactly for a self edge, and components in reverse topological order. `Escapes::recursive` gets the same treatment with tail position drawn per edge. Move Labels into `tests/idr/expect/closures.mlir` (`labels=@call:arg0:[@inc]`).

### SEARCH-17: no feedback, and the one feature report saturates and is read by nothing
- **Category:** perception. **Severity:** medium.
- **Paths:** `tests/toolchain/lib/prop.h` (`writeReport`), the six `tests/toolchain/runtime-*/report` (tracked in git); `tests/Fuzz.idr` (no features at all).
- **Evidence:** every property in every report has `f1=0 f1/n=0.0000`, e.g. `add, sub, mul: the integer GMP computes: n=20000 classes=7 f1=0`, `counting: n=10000 classes=5 f1=0`. runtime-strings gives eight different properties the same four classes (`counted and counted: 259` ... in each), runtime-utf8 has `unclassified: 1000` twice. The fuzzer reports no class or feature at all: which families, types, depths and primitives a run covered is unknown.
- **Guideline:** TBS 6.2 (features too coarse saturate; choose features that distinguish situations), TBS 8 (Good-Turing measures the pair (generator, features); f1=0 with seven classes says nothing).
- **Recommendation:** classify by the situation the property is about: for bigs, the result's crossing of the small range and the operation; for strings, the operation, the scalar lengths present and whether the result is empty. For the fuzzer, report per run the (family, result type) pairs and the primitives reached, and the primitives never reached (SEARCH-18). Write reports to the work directory or the test's untracked output, never to a tracked file in the source tree (`prop_run ... --report "$here/report"` rewrites tracked files on every run).

### SEARCH-18: whole regions of the compiler are absent from the search
- **Category:** distribution (absent, not rare). **Severity:** high.
- **Paths:** `tests/Fuzz.idr` (`Expr`: literals, primitives, one sum type `S`), `tests/Prims.idr`.
- **Evidence:** the generator writes closed expressions over primitives and one three-constructor sum. It writes no Nat (a representation this compiler decides: `idr.nat`, `BigPredOp`), no recursive data, list, closure, higher-order function, laziness, interface, linear value, array or `Data.Buffer` operation. Yet the passes AGENTS.md names (specialization, defunctionalization, loops, RC and reuse, the heap-free check, lowering) act on exactly those. The Integer pool (`bigLiteral`) holds 2^63, 2^64 and 2^128 but not the runtime's small-range edge, `IDRIS_RT_SMALL_MAX = 2^62 - 1`, where `idr-narrow`'s word versioning and the tagged paths switch.
- **Guideline:** TBS 8 (the turkey's third row: "some inputs the representation cannot express at all"), TBS 1.2 (build the alphabet from the existing tests: the boxes' D64 and B are that alphabet), TBS 4.1–4.2 (a typed program generator).
- **Recommendation:** see section 4. At once: add ±2^62, ±2^62 ± 1, ±2^62 ± 2 to `bigLiteral` (D64 from `Box.h`), and Nat literals and `Nat` arithmetic to the static part.

### SEARCH-19: a missing googletest box is not a failure
- **Category:** infrastructure-gap, cannot-fail. **Severity:** medium.
- **Paths:** `Makefile` (`test-unit`), `foreign/idr/unittests/CMakeLists.txt` (`set(IDR_BOXES ranges hooks words tagged ir analyses)`).
- **Evidence:** `test-unit` runs whatever `find ... -name 'idr-box-*'` finds. The 13:35 log ran four boxes (hooks, ranges, tagged, words); `ir` and `analyses` were not built, and nothing said so. A segfault in the first test of a box (`Hooks.Pred`) also skips every later test in that binary (`NatFromBig`, `NatToBig`, both of HooksCompare).
- **Guideline:** TBS preamble (a check that cannot fail), RF (one fact, one place: the box list lives in CMake and should be read from there).
- **Recommendation:** generate the list of expected boxes from `IDR_BOXES` (a file CMake writes), fail on any missing box, and run each test in its own process (`--gtest_filter` per test from `--gtest_list_tests`), so one crash fails one test.

### SEARCH-20: prop.h's shrinker halves the byte length, which yields an unrelated case
- **Category:** perception (shrinking). **Severity:** low.
- **Paths:** `tests/toolchain/lib/prop.h` (`property`: `while (length > 0 && !holdsOn(body, bytes, length / 2, tally)) length /= 2;`).
- **Evidence:** `FuzzedDataProvider` takes integral values from the end of its buffer and bytes from the front, so a prefix of half the bytes gives different integers throughout. The "smaller" case is a different case, not a smaller one, and the loop stops at the first half that passes.
- **Guideline:** TBS 1.2, 8 (small counterexamples), TBS 4.1 (shrink in the representation the generator reads).
- **Recommendation:** shrink the bytes as Gen shrinks a tape: delete spans, zero spans, halve and decrement bytes, keeping a candidate that still fails. The case stays replayable by writing the shrunk bytes as hex in the failure line (`--bytes-hex`).

### SEARCH-21: missing renderings go unnoticed by the agreement check
- **Category:** perception. **Severity:** low.
- **Paths:** `tests/Fuzz.idr` (`checked`).
- **Evidence:** `step` reads only the lines present. `unprintedModel` reports a missing line only for a case with a model; a case with no model (Double, Char, String) whose `s` or `r` line is missing passes `agree`.
- **Guideline:** TBS 9.2 step 5.
- **Recommendation:** require each label of `renderings part c` exactly once; report a missing or doubled label as a failure of its case.

### SEARCH-22: swarm can leave a case with no production, which degenerates to a literal
- **Category:** distribution. **Severity:** low.
- **Paths:** `tests/Fuzz.idr` (`genCase`, `node`).
- **Evidence:** the case type is drawn independently of the kept families (`MkWeights kept <- swarm families; t <- caseTy part`). For `Char` (productions only in Text and Cast), about a quarter of cases keep neither family, and `node` falls back to `leaf t`. The case then prints a literal: four renderings of one literal.
- **Guideline:** TBS 5 (the zero-weight trap's cousin: a forced move is right, but a case that can only be trivial is wasted budget).
- **Recommendation:** draw the type among those with at least one production in the kept families, or report trivial cases in the per-run histogram so their share is visible.

### SEARCH-23: the primitive table is a hand copy with no check against its sources
- **Category:** harness-representation. **Severity:** low.
- **Paths:** `tests/Prims.idr` (`Op`, `opIndex`, `family`, `spelling`, `prims`, `fixedIndex`, `tyIndex`).
- **Evidence:** "one table, made in the order and the shape of Idris's own list of them (Core.Primitives)". It matches `third_party/Idris2/src/Core/TT/Primitive.idr`'s `PrimFn` today, but nothing compares them. Positions are written by hand three times (`fixedIndex`, `intIndex`, `tyIndex`, `opIndex`) to get `Eq` and `Ord`.
- **Guideline:** AGENTS.md "One thing, one representation", RF ("generate the second copy from the first"; "a switch on a tag").
- **Recommendation:** have the runner check `Prims.prims` against the frontend's primitive list (the fork already has it as data) and fail on a primitive the table lacks: absent, not rare (TBS 8). The hand-written positions could become one `Vect` of constructors with `Fin` positions.

### SEARCH-24: contracts compare only functions that survive under their own name with unchanged arity
- **Category:** wrong-or-missing-oracle. **Severity:** medium.
- **Paths:** `foreign/idr/lib/Transforms/Contracts/Contracts.cpp` (`Kept`, `linearKept`).
- **Evidence:** "A function the pass made or erased is compared with nothing: a copy it makes (a specialization's raise node, a trmc clone) has no predecessor with its contract." `linearKept`: "a list is compared only where its length is unchanged". A pass that drops a linear parameter, or a specialization clone that unrestricts one, is not checked, and those are where linearity is most likely lost (AGENTS.md: "No pass may drop what Idris proved").
- **Guideline:** TBS 10 (a protocol claim across functions), AGENTS.md (multiplicities kept through every transformation).
- **Recommendation:** compare a copy with its origin. idr-expect already finds "every function made from f's code" by location (`@f` names every copy), and `expect::functionsOf` is the same machinery. For a dropped parameter, require that a dropped linear parameter was proved consumed (the pass's own reason), or forbid dropping linear positions outright.

### SEARCH-25: Lock validates and throws the parse away
- **Category:** harness-representation. **Severity:** low.
- **Paths:** `tests/Lock.idr`.
- **Evidence:** `pin` builds a `Pin` with `ref : PinRef`, `revision`, `repository`, then only `accepted` reads it; `hexRevision : String -> Bool`.
- **Guideline:** RF SPOV2 (parse, don't validate).
- **Recommendation:** none urgent: the spec test is correct. If `toolchain.lock.json` gets a second reader, parse it once into `Pin` there.

### SEARCH-26: `bigShifted` defines Integer shifts by Chez's `ash`
- **Category:** wrong-or-missing-oracle. **Severity:** low.
- **Paths:** `tests/Prims.idr` (`bigShifted`: "An Integer shift, as Scheme's ash moves a value").
- **Evidence:** the doc comment names the meaning by the Chez primitive.
- **Guideline:** AGENTS.md ("the runtime's documented semantics are the meaning of a primitive"; Chez is no oracle).
- **Recommendation:** cite the runtime's documentation (`idris_rt.h`) for the meaning, and check that it says the same.

### SEARCH-27: the fuzzer's time limits were never measured, and the inner limit contradicts the outer
- **Category:** infrastructure-gap. **Severity:** medium.
- **Paths:** `tests/fuzz/seed-1/run` (`test_limit=1800`), `tests/lib/fuzz.sh` ("That thirty compile within the test's limits ... is for the owner's build to confirm"), `tests/lib/harness.sh` (`bounded` uses `step_limit`, default 60).
- **Evidence:** the run gives half an hour, but each compile is bounded at 60 s, and both parts died there: `1: compile exit 124 | timed out after 60s: compile.sh`. `two-levels` hit the same 60 s on the primitives corpus; `two-hosts` hit its 600 s.
- **Guideline:** TBS 8 (a budget should be a decision with a measured basis, reported as residual risk).
- **Recommendation:** measure the compile time of a 30-case program without the full dump (SEARCH-6). Set `step_limit` from the measurement, or size `fuzz_cases` to fit the limit (fewer cases per program, more programs).

### SEARCH-28: the two splitmix definitions are said to agree, and nothing checks it
- **Category:** infrastructure-gap. **Severity:** low.
- **Paths:** `tests/Gen.idr` (`caseSeed`: "tests/toolchain/lib/prop.h seeds its cases by the same definition"), `tests/toolchain/lib/prop.h` (`caseSeed`).
- **Evidence:** two implementations, in Idris and C++, of one definition, each tested only by its own comment's vectors (prop.h's are in a comment, not checked).
- **Guideline:** RF ("one fact, one place").
- **Recommendation:** have prop.h's programs check the three published vectors at start (a `box` of three inputs), the same vectors Gen checks.

### SEARCH-29: stale directories with only an `output`
- **Category:** stale-legacy. **Severity:** low.
- **Paths:** `tests/toolchain/runtime-page-size/`, `tests/idr/expect/breakers/`, `tests/idr/expect/breaks-last/`.
- **Evidence:** each holds an untracked `output` and nothing else (`git ls-files` lists nothing there).
- **Guideline:** TBS preamble (checks nothing).
- **Recommendation:** remove the directories; have the runner refuse a test directory without `run`.

### SEARCH-30: the model covers integers only, while the agreement oracle shares the runtime between its sides
- **Category:** wrong-or-missing-oracle. **Severity:** low (by design, stated here for the residual risk).
- **Paths:** `tests/Fuzz.idr` (`meaning`, `modelled`), `tests/toolchain/runtime-strings`, `runtime-doubles`.
- **Evidence:** "Nothing for a primitive the model leaves out, every one whose result or operands are not integers". For a String or Char primitive, the folded `d` line and the run-time `r`/`s` lines call the same runtime function (AGENTS.md: folders call the runtime), so agreement cannot see a runtime bug there. That is covered one layer down, where runtime-strings holds the same functions to a scalar model. For Double arithmetic, the folder (APFloat) and the hardware are two genuine implementations.
- **Guideline:** TBS 7 (know what each oracle can and cannot see).
- **Recommendation:** keep the layering, and state it in Fuzz's header: the runtime's functions are judged by the runtime property programs, and the compiler by agreement and the integer model. Where a lowering inlines a string or char operation instead of calling the runtime, give the fuzzer a model for it, ported from runtime-strings' scalar model.

---

## 3. Code bugs the tests reveal

Only what the outputs show; causes are my reading.

1. **idr-rc leaves a graded program that does not verify.**
   `tests/idr/expect/counting` and `tests/idr/contracts/nested-run` (and 19
   occurrences of the same verifier message in `test-idr.log`). Output:
   `'idr.match' op operand #0 must be a constructor value at any quantity, not owned, but got '!idr.own<!idr.box<...>>'`;
   `'idr.return' op returns '!idr.box<...>' as result 0, but @build returns '!idr.own<!idr.box<...>>'`;
   `'idr.match' op case @C must take the constructor's fields at the scrutinee's grade, 'i64', '!idr.q<many, borrow, ...>'`;
   `'idr.call' op gives result #0 ... which holds references at the plain grade in a graded program`.
   Reading: idr-rc's grading rewrites function signatures to `!idr.own` /
   borrowed grades but leaves the returns, the match operands and the case
   block arguments (and call results) at their plain types, or the match
   verifier was tightened without idr-rc inserting the take or borrow. This
   fits the last two commits (`423d9760`, `4c87dcc5`), both about where
   idr-rc writes grades. The fixtures' expectations are right.

2. **Lowering emits an `llvm.call` whose operand type does not match the callee.**
   `tests/two-levels/terms` (prelude corpus); the same error appears 9 times
   in `test.log`. Output:
   `idris-mlir: internal error: 'llvm.call' op operand type mismatch: expected operand type 'i64', but provided '!llvm.ptr' for operand number 0`.
   Reading: a runtime function declared to take a word (`i64`) is called
   with a pointer, or the reverse: a value lowered as a heap reference where
   the runtime ABI expects an unboxed word, plausibly a big or natural in
   the small range (a tagged word) against a declaration from the ABI table.
   Which call it is, the log does not show.

3. **Compiles too slow for the tests' limits (plausible, confounded).**
   The fuzz programs of 30 cases (seeds 1 and 2, both parts) are killed at
   60 s; the two-levels primitives corpus (about 700 terms in groups of 32)
   at 60 s; two-hosts (five modules, about 2800 lines) at 600 s; 19
   `timed out after 60s: compile.sh` in `test.log`. Every one of these
   compiles also dumps every pass of every function (SEARCH-6), so how much
   is the compiler and how much the dump is unknown until a compile without
   the dump is timed.

4. **Symbol names exceed the file-system's name limit, which breaks MLIR's IR tree printer.**
   two-hosts (975 lines in `test.log`): `Error while creating directory .../idr_func_Prelude.Interfaces.(<*>)[Data.Vect.Vect _ (Data.Fin.Fin (Prelude.Types.S^2 Prelude.Types.Z)) -> ..., Gen.Gen, Gen.__Impl_Applicative_Gen];a971d85f5a0e8ce2.lam.4cabc8d2b001b4bb: File name too long`.
   Reading: specialization names carry the whole instance list in the symbol
   and then add a hash. Either the symbol should be the hash with the
   readable name in the location (README: "A function a property is stated
   of is named by its Idris definition", by location), or upstream's
   `--mlir-print-ir-tree-dir` should shorten what exceeds NAME_MAX. Per
   AGENTS.md that is an upstream patch, if the names are deemed right.

5. **Two googletest boxes segfault (old binaries; cause unknown).**
   `test-unit.log`: `[ RUN ] Hooks.Pred` then `Segmentation fault: 11`;
   `[ RUN ] Words.EachBigOpIsItsWordOp` then `Segmentation fault: 11`.
   Both tests build idr ops in a `Scratch` module and call their hooks or
   folders; `Tagged.Pred`, which calls the same runtime entry without MLIR,
   passes. So the fault is more likely in op creation or the hook than in
   the runtime. The binaries were rebuilt after this log; rerun before
   reading more into it.

6. **`runtime-prepared`** (outside this lane, noted because the log has it):
   "the prepared runtime needs what its target's allowlist does not allow".
   See the repo-tests lane.

Not code bugs: `signature` (the checker's wording changed; fixture stale)
and `typed-reads` (the dialect no longer takes tensors there; fixture and
property stale).

---

## 4. The search rebuilt

What would replace what is recommended above, in order of value.

**One generator of programs, typed, over the whole language the compiler
accepts.** Keep `Gen` as it is: the choice tape, linear and replayable,
`Weights` that cannot be all zero, swarm, the exhaustive odometer, and the
proved shrinker are the right foundation, and better than most fuzzers'
(TBS 4.1, 5, 8). Replace `Fuzz`'s `Expr` with a typed program generator in
stages, each a named, weighted production family, so the search reaches
what it cannot express today (SEARCH-18):
- expressions over primitives (today's `Expr`), with Nat and the D64/B
  edges in the integer pools;
- first-order recursive functions over generated data types (sums and
  records, recursive lists and trees), totality by construction
  (structural recursion on a generated argument);
- higher-order: closures passed and returned, with the set of closures a
  site can meet bounded by construction (the monomorphic subset AGENTS.md
  commits to), so defunctionalization is searched;
- linear values and `mlir-linear` arrays used exactly once (the harness
  invariant is the quantity, TBS 4.3), so RC, reuse and in-place update are
  searched;
- `IO` sequences with output (the order is the oracle);
- named breaches (SEARCH-8): a precondition broken on purpose, judged by a
  crash with the documented message.
The typed representation keeps every case valid where the harness needs it
(`Fin`, `Elem`), never where the compiler's contract would hide a bug
(TBS 4.3).

**Oracles, all ours.**
- A reference evaluator of the generated programs, written in Idris over
  the generator's own AST (not Chez's evaluator: a model of the closed
  first-order language, with `Prims` for primitives), as the model for
  programs whose primitives are integers. This extends today's `modelled`
  from expressions to programs (TBS 9).
- Agreement among renderings (today's d/j/r/s) generalised: the same
  program compiled with folding forced (literals), with values from stdin,
  and with a random subset of optional actions skipped through debug
  counters (SEARCH-10). Any disagreement is bisected to one action
  instance.
- `--idr-contracts` on every compile of the search, and `--verify-each`
  (the pass manager's verifier), as universal oracles (TBS 7).
- `idr-expect` properties chosen per generated program from what the
  generator knows it built: a program with no allocation in its source
  states `no-heap-allocation`, a tail-recursive loop states
  `constant-stack`, a linear array update states `reuses-in-place`. The
  generator knows these facts, so they need no golden (TBS 6.2: types
  constrain, features steer; here the generator's knowledge is the spec).

**Small-scope boxes beside the random search (TBS 8).** Keep the
googletest boxes for range rules, hooks and the word table, and the
runtime prop.h boxes, with runtime-bigs absorbing Tagged/TaggedBits. Add:
every call graph on <= 4 functions for `CallCycles`/`Escapes` against
reachability (SEARCH-16); every tape of length <= 4 for Gen's shrinker
and `candidates` (Gen rows above); and for the program generator, an
exhaustive mode (Gen's `exhaustive`) over programs of depth <= 2 and one
family, run in `make test`, so "no bug at this size" is a theorem in the
box.

**Perception (TBS 6, 8).** Each run reports its features: (family, result
type) pairs, primitives reached, constructs reached (closure crosses a
call, linear value consumed by a match, ...), the share of trivial cases,
and a Good-Turing estimate on those features. Reports go to the work
directory, never to tracked files. The stopping rule of `make fuzz` is the
estimate falling below a set threshold, reported as residual risk.

**Shrinking everywhere a failure can occur.** Compile failures first
(SEARCH-3): bisect cases, shrink the tape, then `idris-mlir-reduce` on the
module. prop.h shrinks bytes as Gen shrinks tapes (SEARCH-20).

**Regression = a corpus.** `tests/fuzz/` becomes one test over a committed
corpus of failing tapes (each line a tape and the part, shrunk), plus the
current two seeds. Deterministic, quick, and growing only with real bugs.
`make fuzz` is the search; `make test` replays what it found.

**Fixed tables only where nothing computes the answer.** Sem's tables
become nine programs, each checked on both paths against `Prims`
(SEARCH-7). TwoLevels keeps only Double/Char/String terms whose values the
runtime's documentation determines, each derived and reviewed, never
accepted from the compiler's output (SEARCH-5). two-hosts keeps only the
generators' self-checks (SEARCH-4).

**The oracle's own tests stay, loosened.** idr-expect's positive and
negative fixtures match substrings (property and function), the coverage
test reads the table from the tool and requires a real failing RUN line
(SEARCH-11, -12), and dead properties go (SEARCH-14).

## Uncertainty

- I did not run anything; status is from each directory's last `output`
  and the logs named in the header, some of them from older builds
  (`test-idr.log`, `test-unit.log`).
- I read the property implementations only where a fixture fails or the
  fuzzer depends on them (`folded`); the other 80 properties' code is not
  audited here.
- The Int-node share (SEARCH-9) is counted from the `prims` table by hand:
  60 comparisons out of 84 productions with result Int at run time, every
  family kept.
- Whether the slow compiles (code bug 3) are the compiler or the dump is
  open until a compile without the dump is timed.
