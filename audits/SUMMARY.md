<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# The 2026-10-18 test-suite audit: synthesis

## 0. Header

- **Lane:** synthesis.
- **Scope:** the nine lane audits in this directory (`idr-a.md`, `idr-b.md`,
  `idr-c.md`, `programs.md`, `accept-reject.md`, `repo-tests.md`,
  `machinery.md`, `search.md`, `gaps.md`), read in full. Together they cover
  every test directory, fixture and harness component under `tests/`, the
  googletest boxes in `foreign/idr/unittests`, and the compiler's promises
  that no test states.
- **Also read:** `.claude/skills/testing-by-search/SKILL.md` (cited **TBS n.m**)
  and `.claude/skills/representation-first/SKILL.md` (cited **RF**, by the
  rule's name: "one fact, one place", "parse at the boundary", "every string
  that names a thing", "delete what the representation makes dead", "a switch
  on a tag", SPOV1 to 3, "MLIR grain"); `AGENTS.md`; `tests/README.md`;
  `audits/README.md`; the scratchpad logs' summary lines.
- **Spot checks of my own** (read-only), where two lanes disagreed or a lane
  was unsure:
  - the 181 output-only directories, listed by `find`;
  - `BigAttr::verify` in bfdcac70: a big is now an `APInt`, so `-0` and `007`
    cannot be two values (§5, reclassified);
  - `idr.func`'s `instance`, which is an `OptionalAttr` in `IdrOps.td`;
  - the knot rule in `Passes.td` against `reject/cycle-ioref-knot/Main.idr`;
  - the commits after the lanes' runs: f5c6ca69 (16:54) and e6d8d6d8 (17:02),
    which change `Specialization.cpp` and `Expect/Quantities.cpp`.
  Nothing was built or run.
- **Runs the lanes read:**

  | target | result | when | note |
  | --- | --- | --- | --- |
  | `make test` | 243/542 | 16:47 | third run; the task's 193/542 was the first |
  | `make test-idr` | 218/368 | 14:32 | older build |
  | `make test-mlir-tools` | 16/25 | 14:32 | |
  | `make check` | 24/35 in `check.log` | 13:57 | the spec outputs of 14:17 show 33/35 |

  A failure in these runs is often fixed by a later commit; the lanes say so
  per test, and §5 does per bug.

## 1. Headline numbers

### 1.1 Per lane

| lane | rows | keep | rewrite (of which as-property) | merge | delete | status at last run |
| --- | --- | --- | --- | --- | --- | --- |
| idr-a (`idr/` actions to defunc) | 84 | 38 | 34 (8) | 9 | 3 | 63 pass, 19 fail, 2 unknown |
| idr-b (`idr/` e2e to lower) | 153 | 99 | 43 (18) | 3 | 8 | 101 pass, 51 fail, 1 never ran |
| idr-c (`idr/` names to world) | 134 | 69 | 46 (7) | 14 | 5 | 54 pass, 78 fail, 2 never ran |
| programs | 237 | 117 | 60 (41) | 43 | 17 | 140 pass, 97 fail |
| accept-reject | 125 | 68 | 30 (6) | 7 | 20 | 90 pass, 34 fail, 1 no expected |
| repo-tests | 106 | 83 | 17 | 2 | 4 | spec 33/35, toolchain 19/22, upstream 16/25, determinism 4/8, bench 2/3, boxes 6/6 |
| **six scope lanes** | **839** | **474** | **230** | **78** | **57** | |
| machinery (components) | 39 | 19 | 17 | 0 | 3 | 8 components defective |
| search (overlaps idr-b, repo, accept-reject) | 115 | 96 | 10 (3) | 4 | 5 | 68 pass, 12 fail, 32 unknown, 3 no test |
| gaps (overlaps programs, idr-a, repo, accept-reject) | 97 | 8 | 33 | 56 | 0 | (rows are a contract's only coverage) |
| **all rows** | **1090** | **597** | **290** | **138** | **65** | |

Notes on the table:
- machinery's own summary says "merge 1": its one merge (profile_accept into
  e2e_io) is counted under rewrite in its table, and here too.
- The search and gaps rows mostly re-judge tests that a scope lane also
  judged, under a different question. They overlap the scope lanes here:
  - search: the expect/ and contracts/ fixtures, the runtime property
    programs, the googletest files, two-levels, semantics/prim;
  - gaps: about 60 programs, the determinism directories, the actions,
    accept/action-*.
- **Distinct tests:** about 861. That is the six scope lanes' 839, plus the
  three fuzz directories and 19 self-check rows of the Idris machinery that
  only search reviewed. semantics/prim is counted once, not as 144.
- **Beside these:** 181 directories hold only a git-ignored `output` left by
  a deleted test (§3.6), and gaps enumerates 63 contracts.

### 1.2 The suite after the verdicts are applied

| outcome | count | what it means |
| --- | --- | --- |
| delete | 59 tests | the 57 of the scope lanes, `Sem.checks`' budget row, and `expect/typed-reads` once its disagreement is resolved (§3.7) |
| delete with them | 181 output-only directories, `tests/ACCEPTANCE.md`, the `INTERACTIVE=--interactive` path | |
| delete as boilerplate | 304 dialect `run` and `expected` files | |
| | 102 `accept/` and `reject/` `run` and `expected` files | |
| | about 830 e2e, accept and dialect `expected` transcripts | they repeat what the fixture's files decide |
| rewrite | about 290 rows | most as a property, a generator entry or an expectation stated in a richer vocabulary (§4) |
| merge | 138 rows | most into a generated fixture whose generator does not exist yet (§7 says when each goes) |
| keep | about 600 rows | about half of the kept idr fixtures fail today on a compiler bug, not on the test |
| code bugs, after removing duplicates | 41 entries (§5) | 7 already fixed or likely fixed by later commits; 9 plausible or uncertain |

## 2. The problems across lanes, ranked by how much of the suite each covers

The counts are the lanes' own, added up. Where lanes overlap, the larger
count is used, so these are coverage estimates, not exact sums.

### 2.1 Derived data held twice: transcripts and files that restate the fixture (harness-representation). About all of the suite.

- **Guideline:** RF "one fact, one place" ("in a test and in the code under
  test"), RF Insight 6 (a validator throws away what it learned), TBS 1.1
  (the vocabulary is the tool's, and a weak one breeds copies).
- **Evidence:**
  - 368 of the 371 dialect `expected` files hold only `RUN 1: ok` ... `RUN n:
    ok`, and n is the count of `// RUN:` lines in the `.mlir`
    (MACH-1, IDRB-1, IDC-12). `obs/print-with-object` "fails" with every
    line ok, because its `expected` lists 6 lines for 7.
  - 280 of the 303 e2e and accept transcripts take one of 5 fixed forms
    (MACH-1, PROG-18), and the 47 reject `run` files have one md5 (AR-2).
  - `artifacts: core module objects executable`, the harness's own constant,
    is printed into about 300 transcripts (MACH-8).
  - NEEDS-ACCEPTANCE is one state with three encodings (MACH-2):
    - a mark in an `expected` file makes the test fail by construction
      (60 files);
    - a mark in a `.mlir` changes nothing (314 files);
    - `ACCEPTANCE.md` is a hand copy of a grep, and already wrong
      (445 entries for 376 files).
  - Pools and topics are listed by hand in `Main.idr` and again in the
    README, so a new directory runs nowhere (MACH-12).
- **Examples:** `idr/**/name/{run,expected}` (304 files); `reject/*/run`;
  `tests/ACCEPTANCE.md`.

### 2.2 No oracle for meaning: a pass's output is checked for shape, never for what it computes (wrong-or-missing-oracle). About 400 tests.

- **Guideline:** TBS 7 ("in a typed setting, the quality of your testing is
  almost entirely the quality of your oracle"); TBS 1.2 (a second
  implementation we own); TBS preamble (the oracles this repository may use).
- **Evidence:**
  - Every optimization fixture in idr-a and idr-c states only what is left:
    `not-called`, `one-clone`, `no-closures`, `word-loop` (IDR-A-23,
    IDC-3). That is roughly 170 files across canon, defunc, raise,
    specialize, optimize, narrow, contify, dedup, bufferize, loops and
    identity.
  - Most of them already read one stdin byte and print a number, so
    running before against after on all 256 bytes is an exhaustive oracle
    for little cost (IDC-3, TBS 8).
  - Passes.td's role contract for optimization is "skipping any one [action]
    ... leaves a valid module whose behaviour is the same". It is checked
    only as "skipping all is the identity", on ten hand copies (IDR-A-6,
    GAPS-2, IDRB-19, SEARCH-10).
  - `--idr-contracts` runs only on hand-written `idris-mlir-opt` RUN lines,
    never on a real program's pipeline (GAPS-5, SEARCH-10).
  - Emit's quantities are compared with the emitted module itself, never
    with Idris's TT (GAPS-4).
  - `two-levels` has had one level since 08a065e4. Its values are the
    compiler's own output frozen as golden, and its plan fills the missing
    56 values from the compiler under test (AR-16, SEARCH-5).
- **Examples:** `idr/defunc/memo-rebuild` ("@one does not run twice",
  unchecked); `idr/raise/shared-key`; the ten `idr/actions/*`.

### 2.3 One fixed input, two fixed seeds, no program generator (distribution). About 400 tests and the whole search.

- **Guideline:** TBS 4.1 (construct, do not filter), TBS 5 (an explicit
  distribution; swarm per run), TBS 8 (the turkey's third row: "absent, not
  rare"; small scope).
- **Evidence:**
  - Every program runs one `stdin`, mostly one digit (PROG-21).
  - The fuzzer runs seeds 1 and 2 with 30 cases, forever (SEARCH-2), and
    every runtime property program runs `--seed 1` (REPO-17).
  - Fuzz draws closed primitive expressions and one sum. No Nat, data,
    match, closure, laziness, linear value or array (SEARCH-18, GAPS-3).
    That is where this build's 40 leaks and 8 internal errors are.
  - Fuzz's preconditions are encoded as `Domain` constraints, so a
    division by zero or an empty `strHead` is never drawn (SEARCH-8, the
    TBS 4.3 trap).
  - Comparisons make up 60 of the 84 Int productions, a bias nobody chose
    (SEARCH-9).
  - The Integer pool lacks the runtime's 2^62 edge (SEARCH-18).
- **Examples:** `tests/fuzz/seed-{1,2}`; `programs/arrays/linarray-push-pop`
  (one command sequence); `determinism/*` (four hand-picked programs).

### 2.4 Tests that cannot fail, or check nothing they claim (cannot-fail, checks-nothing). About 200 tests.

- **Guideline:** TBS 9.2 step 5 ("Check that the real system actually
  entered each state the model claimed. Otherwise the test can silently
  check nothing"); TBS 1.1 (Winters' `DefaultConfigsArePrime`).
- **Evidence:**
  - **Already implied by another check.** 17 defunc fixtures assert only
    `no-closures` after `idr-defunctionalize`, which the program verifier
    implies past `higher`, and 35 files restate it. `quantities-kept=%s`
    repeats `--idr-contracts` (IDR-A-2, GAPS-13).
  - **Functions under test are dead code.** 79 of idr-b's 152 fixtures use
    a dummy `root(@root)`, so every function under test is private and
    uncalled, and upstream's dataflow treats it as dead (IDRB-3, IDC-15).
    `fold/range` fails that way.
  - **Copies are invisible.** Copies are found only by `NameLoc`, which no
    hand-written fixture has. So 5 specialize tests fail, and
    `specialized-once`, `one-clone` and `exclusive-copy` hold vacuously in
    about 6 more (IDC-2).
  - **A check that never ran prints `ok`.**
    - `fuzz.sh` prints `ok` for checks that never ran after a failed
      compile (SEARCH-1, GAPS-24).
    - `not diff` passes on two files never written: trmc RUN 5, and five
      others (IDR-A-5, MACH-5).
    - A bare `%status 1`, or a `not` with lit.sh's injected flags, accepts
      any failure. That covers at least 13 RUN lines and
      `rc/counted-linalg`'s whole check (IDR-A-5, MACH-5, SEARCH-13).
  - **The claim is in a comment and nowhere else** (PROG-6, IDRB-9,
    IDC-11, AR-12, IDR-A-3, IDR-A-25). This covers about 40 fixtures. For
    example `memo-by-name` never uses the existing `by-name` row, and
    `dedup/merge` passes a no-op pass.
  - **Pass-name filters fail open.** A check that picks its module or its
    remarks by a pass name holds vacuously after a rename (MACH-19).
    `names/edit` diffed two empty name lists and passed (IDC-4).
- **Examples:** `idr/defunc/many-labels`, `idr/dedup/merge`,
  `tests/fuzz/seed-1`'s three "ok" lines on 2026-10-18.

### 2.5 Assertions stronger than the contract (brittle-overspecified). About 130 tests, plus the transcript lines of 2.1.

- **Guideline:** TBS 1.1 (a brittle test distinguishes outputs the contract
  treats as equal; it signals a weak vocabulary); AGENTS.md ("Not clone
  numbers, function order or SSA names ... write the property once").
- **Evidence, by kind:**
  - **Diagnostic wording.** About 20 of today's failures are wording that
    moved while the behaviour held:
    - `expect/signature` gained quotes;
    - `func/call-type` reads "program" where it read "module";
    - verify/{cells, data, nat, ops, values}, tie-shape/verify,
      main-visible.
    Every expect/ and contracts/ fixture pins full text (IDRB-4, IDC-6,
    SEARCH-11, AR-20).
  - **Pass order spelled by hand.**
    - 20 fixtures chain passes by hand; five broke when the wave moved
      idr-entry (IDRB-2).
    - 9 program fixtures read "the step after a group" (PROG-5).
  - **Inlining choices.** Properties name helpers the inliner removes:
    "no function @Main.mark, and no copy of it" (PROG-4, 6 tests).
  - **Printed text scraped.** `asm/prefix`'s 16-line CHECK-NEXT chain,
    names/*' sed, `optimize/once`'s grep of the action log, the tree
    printer's file names, `guards/fold-unguarded`'s `idr.divs` (IDR-A-15,
    IDC-4, IDRB-8).
  - **Statistics, counts and logs.**
    - `rc/statistics`, `obs/stats`, `roles/optimize-statistics` (IDC-18);
    - `features: 29`, `101 of 101` (REPO-9);
    - live-cell budgets 3 and 2 (PROG-16);
    - `crash-sites=@delayed_crash:2` (IDR-A-26).
  - **Source-text heuristics.** spec/no-primitive-semantics, totality,
    no-fuel and emit-dialects gave false positives on the first post-wave
    run. c4d0b26b fixed them by loosening the regexes or rewriting the code
    to dodge them (REPO-1). Four more spec tests pin file names and exact
    CMake strings (REPO-4).
  - **Incompleteness pinned as a refusal.** `reject/polymorphism-growth-{family-sum,recursion}`
    expect a refusal of finite programs (AR-6).
- **Examples:** `idr/asm/prefix`, `programs/arrays/ioarray-sieve`,
  `spec/totality`.

### 2.6 One property written as many examples (example-should-be-property). About 100 tests.

- **Guideline:** TBS 1.1 (the property names no input), TBS 8 (exhaust the
  small cases; move the bug into the box), TBS 9 (a model as oracle), RF
  "one fact, one place".
- **Evidence:**
  - **Tables that restate a meaning computed elsewhere.**
    - fold tables: 8 files restate `Sem`'s meaning (IDRB-7);
    - guard folds: 6 files restate the `Idr_Guarded` records (IDRB-8);
    - effects remarks: about 9 files restate ODS effects (IDRB-15);
    - crash texts: 10-plus fixtures restate the runtime's crash strings
      (PROG-14);
    - Double text: 6 fixtures restate a round-trip rule (PROG-15).
  - **Families of hand-picked points.**
    - layout boundaries: 4 points of `IDRIS_RT_OBJS_WIDE`, plus 3 record
      fixtures (PROG-12);
    - Linear.Vec: 5 command sequences (PROG-13);
    - array bounds: 6 examples of `0 <= i < n` (PROG-12, GAPS-7);
    - linear-list "leet" programs: about 10, each one shape of a list
      model (GAPS 2b).
  - **Corpus relations stated once per directory.** Determinism and
    name-stability over 8 directories (REPO-18, GAPS-10). One reject
    fixture per forbidden-table entry (AR-14). The ten actions files
    (IDR-A-6).
  - **Analyses with an obvious model, tested on one example.**
    `CallCycles` on one call graph, `probe-names` on 19 hand-picked values
    (SEARCH-16, AR-13).
- **Examples:** `idr/fold/shift`, `programs/data/layout-256-counted-fields`,
  `unittests/Cycles.cpp`.

### 2.7 Removed behaviour, never-run fixtures, litter (stale-legacy). About 90 tests and 181 directories.

- **Guideline:** RF "delete what the representation makes dead in the same
  change ... the test that checked the impossible state"; AGENTS.md
  ("exercises removed behaviour"; static normalization "is not built").
- **Evidence:**
  - **Never elaborated.** 15 fixtures cannot elaborate: they lack the
    imports that an always-on `--no-prelude` needs (AR-1, PROG-9).
    - 11 accept fixtures and `reject/polymorphism-nested-data`;
    - `compiler/content-hash`'s copied `Ids.idr`;
    - registry/broken-entry case 2;
    - data/dependent-pair-family-eta and interfaces/method-runtime-implicits.
    Two of them guard fixed silent miscompiles.
  - **Compile-time evaluation.** About 32 tests describe it: 17 programs
    and 15 accept fixtures (PROG-7, AR-7).
  - **Removed ops, options and names.**
    - `canon/apply`: the apply canonicalization deleted in c7aa7b62;
    - `fold/pending`: holes in `idr.con`;
    - `expect/typed-reads`: `check.in_bounds` no longer takes a tensor;
    - `roles/pure-calls`, `roles/optimize-statistics`;
    - `world/world-carrier`, `obs/bitcode-section-option`, `lower/no-mode`;
    - the old attribute names in verify/attributes and verify/function;
    - spec/content-names and refusals-as-data;
    - verify/values' `-0` and `007`, which the `APInt` big makes
      unrepresentable as distinct values.
    (IDR-A-1, IDRB-12, IDC-7, REPO-3.)
  - **Hand-written dialect text that the wave invalidated.**
    - 7 owned-stage fixtures and actions/trmc (IDRB-5, IDR-A-11);
    - toolchain/runtime-container and upstream/one-shot-module-function-interface
      (REPO-8);
    - syntax/closures, syntax/grades, verify/program, verify/roundtrip (IDC).
  - **Comments.** They cite the Chez reference (PROG-8, SEARCH-26) and lane
    or rule ids (IDRB-17: 20 fixtures).
- **Examples:** `idr/canon/apply`, `accept/partial-integer`,
  `programs/eval/static-evaluation`.

### 2.8 What the harness lets a reader notice (perception). Every failure report; about 70 tests directly.

- **Guideline:** TBS 6 (what is perceived decides what is found), TBS 12
  ("a testing failure is information about the testing infrastructure").
- **Evidence:**
  - **The tree printer's noise.**
    - `--mlir-print-ir-after-all --mlir-print-ir-tree-dir` makes one
      directory per symbol, and specialized names exceed NAME_MAX. The
      resulting "File name too long" lines fill `show`'s 40 lines and hide
      the compiler's own error in 17 programs (PROG-1). One of them is an
      abort.
    - It is in 27 failures suite-wide (AR-10, GAPS-25). In
      registry/scalar-bytes, compile exit 1 shows nothing else.
    - The dumps of every pass of every function are also the main suspect
      for the 60 s timeouts (SEARCH-6, PROG-3).
  - **One cause, many alarms.**
    - One idr-rc defect shows as about 37 failures in lowering, loops,
      stack and expect suites, none of which says "idr-rc" (IDRB-6, IDC-B3).
    - bench/smoke folds 26 benchmarks into one verdict, and 14 fail inside
      it (REPO-19, MACH-20).
  - **The runner's report.**
    - The summary's denominator is passed+failed, so a test that never
      reports drops out; skipped tests are never named (MACH-3).
    - Failures print Expected and Given in full with no diff, and stderr
      leaks unattributed.
    - A signal is "exit 138", a program's own exit 124 reads as a timeout
      (MACH-11), and the live-cell count shares the program's stderr.
  - **Probes discard their evidence.** The escape-hatch and registry probes
    grep message text and keep nothing (MACH-9), so every-primio-export
    fails with no cause shown.
- **Examples:** `programs/arrays/transpose-last-two-axes` (exit 134,
  cause invisible); `bench/smoke`; `idr/lower/box`.

### 2.9 Duplicates (redundant). About 60 tests.

- **Guideline:** RF "one fact, one place"; the owner's stance ("duplicates
  another").
- **Evidence:**
  - **Built from bench/.** 9 program fixtures copy `bench/<name>/Main.idr`
    and repeat bench/smoke (PROG-10, REPO-20).
  - **Per-target copies.** vectorize/rows-x86-64 and rows-aarch64,
    lanes-x86-64, lower/cpu-features-x86-64, toolchain/cpu-features-aarch64.
    AGENTS: "Per-target cases elsewhere are bugs". Two of them never run on
    arm64 (IDC-10, IDRB-10).
  - **Same module or same mechanism.**
    - one module twice: loops/accumulate and actions/accumulate, loops/trmc
      and actions/trmc, actions/deduplicate and dedup/merge (IDRB-13,
      IDR-A-4);
    - one mechanism in four files: raise/{branches, chain, projection,
      through-linear} (IDC-8);
    - e2e/{crash, doubles, strings, hello} against programs/ (IDRB-13).
  - **Two harnesses for one contract.** `Tagged.cpp`/`TaggedBits.cpp`
    against runtime-bigs' boxes, with three definitions of the bigs' edge
    values (SEARCH-15, REPO-16). The two-levels integers against
    `Prims`/`Sem` (SEARCH-5).
  - **One rule under two names.** The `idris` and `elaboration` reject
    headers (AR-5).
- **Examples:** `programs/data/pidigits`, `idr/vectorize/rows-x86-64`,
  `unittests/Tagged.cpp`.

### 2.10 Contracts no test states (infrastructure-gap). 13 of the 63 contracts gaps enumerated.

- **Guideline:** TBS 9.3 (a missing check has no branch to reward; only a
  specification aims at it), TBS 7.
- **Not stated by any test** (gaps §2a):
  - user `%foreign`/`%extern` refused by name (GAPS-1; rules-covered counts
    rules, not cases);
  - Emit's quantities against TT (GAPS-4);
  - the behaviour half of "optimization is optional" (GAPS-2);
  - the role and stage lists "the tests read", which no test reads (GAPS-6,
    IDR-A-6);
  - idr-structure-loops' float fold order (GAPS-8);
  - idr-rc-stack's size bounds (GAPS-19);
  - use after free (GAPS-18);
  - per-target confinement (GAPS-17);
  - refusals composing (GAPS-15);
  - stage 2 = stage 3 (GAPS-23);
  - 0002 §9's generator (GAPS-3).
- **Partly stated:** 41 of the 93 verifier diagnostics have no fixture,
  an estimate (GAPS-21).
- **Outside the runner:** the googletest boxes, where a missing box is no
  failure (REPO-14, SEARCH-19). The fork reproducers run only in
  `make test-mlir-tools` (REPO-12).

## 3. The delete list

Every path a lane marked delete, grouped by reason. Paths are under
`tests/` unless rooted otherwise. A disagreement between lanes is marked
**[disputed]** and resolved in §3.7.

### 3.1 Removed behaviour (RF "delete what the representation makes dead"; AGENTS "exercises removed behaviour")

| path | lane | what was removed |
| --- | --- | --- |
| idr/canon/apply.mlir | idr-a | apply-of-known-closure canonicalization (`Canon/ClosureOf.cpp`, c7aa7b62) |
| idr/fold/pending.mlir | idr-b | `idr.con` holes (moved to `idr.cell.init`) |
| idr/lower/no-mode.mlir | idr-b | idr-lower's `jit` option |
| idr/obs/bitcode-section-option.mlir | idr-c | `--runtime-bitcode-section` |
| idr/world/world-carrier.mlir | idr-c | `!idr.world_carrier` |
| idr/roles/pure-calls.mlir | idr-c | `idr-pure-calls-*` actions (replaced by upstream canonicalize and CSE) |
| idr/roles/optimize-statistics.mlir | idr-c | `idr-canonicalize`; also pins statistics |
| idr/expect/typed-reads.mlir **[disputed]** | search (idr-b: rewrite) | `check.in_bounds` on a tensor; delete the `typed-reads` row of `Expect/Lookup.cpp` with it |
| spec/content-names | repo | historical counter suffixes |
| spec/refusals-as-data | repo | `Rule.idr`; pins `Attrs.cpp`; its expected contradicts its header |
| accept/division | accept-reject | the partial-division boundary |
| accept/partial-integer | accept-reject | compile-time evaluation of a partial closed call |
| accept/runtime-data-first-of-two, runtime-data-list, runtime-data-prelude-list | accept-reject | the refusal of runtime data |
| accept/runtime-integer, runtime-integer-prelude | accept-reject | the refusal of runtime Integer |
| accept/static-integers | accept-reject | the same, and cites a nonexistent fixture |
| accept/static-list | accept-reject | compile-time evaluation; claim unchecked |
| accept/runtime-string-compared | accept-reject | negative control of an unchecked claim |
| reject/escape-hatch-phrase-in-comment | accept-reject | a harness that counted phrases |
| programs/eval/static-evaluation, deep-list-constant, deep-result, strings-at-compile-time | programs | compile-time evaluation |
| programs/data/shapes **[disputed]** | programs | "reduced all the same" (compile-time evaluation); erased witness covered by semantics/erased-witness |
| programs/prelude/prelude, prelude-lists | programs | subsumed by every-*-export; stale claim |

### 3.2 Checks nothing it claims (TBS 1.1; TBS 9.2 step 5)

| path | lane | why |
| --- | --- | --- |
| accept/action-run-at-once **[disputed]** | accept-reject (gaps: merge) | prints 2; the closure claim is unchecked |
| accept/fib, map-pair, pair-maybe, partial-application | accept-reject | generic programs at no boundary |
| programs/eval/dead-static, static-let | programs | output only |
| programs/eval/known-constructor, specialization | programs | stdout only; the dialect suites own the property |
| programs/interfaces/interface-superclass | programs | "no dictionary survives" unchecked |
| programs/io/output-fusion **[disputed]** | programs (accept-reject merges into it) | `output-fused` never stated |
| programs/partial/loop-breakers | programs | loop-breaker claim unchecked; even/odd duplicated |
| programs/prelude/string-functions | programs | the claim is unstated |
| idr/e2e/partial-loop.mlir | idr-b | checks only exit 20 |
| `Sem.checks` "every table holds at most 120 cases" (tests/Sem.idr) | search | checks the test's own constant |

### 3.3 Pins incidental output (TBS 1.1; AGENTS "a pass's transcript")

| path | lane | what it pins |
| --- | --- | --- |
| idr/actions/inner-steps.mlir **[disputed]** | idr-a (gaps: rewrite-as-property) | which inner step of idr-optimize fires |
| idr/e2e/statics.mlir | idr-b | pass names in `--mlir-timing` |
| idr/rc/statistics.mlir | idr-c | statistic names and step order of a human report |
| compiler/module-location | accept-reject | the printed module's last line |
| spec/totality | repo | a fuel heuristic with false positives; copies tblgen's enum check; tests that tests exist |

### 3.4 Duplicates (RF "one fact, one place")

| path | lane | duplicate of |
| --- | --- | --- |
| idr/defunc/growing-lazy.mlir | idr-a | a strict subset of defunc/growing |
| idr/e2e/crash.mlir | idr-b | programs/partial/crash-after-output, missing-case |
| idr/e2e/doubles.mlir | idr-b | programs/semantics/closed-double-* (delete only after their replacement lands, §3.7 item 8) |
| idr/e2e/hello.mlir | idr-b | programs/basic/hello, plus the universal import check |
| idr/e2e/strings.mlir | idr-b | programs/semantics, basic/chars, high-chars |
| programs/basic/numbers | programs | Sem's convert tables, every-cast-export |
| programs/semantics/closed-shift-negative **[disputed]** | programs (gaps: merge into the Fuzz dictionary) | Sem's `shiftAmounts` holds -1 and -3 |
| reject/deprecated-buffer-data, deprecated-set-byte | accept-reject | one `deprecatedDef` entry kind; a table-generated pool replaces them (AR-14) |
| reject/pragma-inline | accept-reject | subsumed by pragma-default-with-inline |
| determinism/hello **[disputed]** | repo (gaps: rewrite-as-property) | the parameterized determinism corpus |

### 3.5 Machinery

| path | lane | why |
| --- | --- | --- |
| tests/ACCEPTANCE.md | machinery | a hand copy of a grep, 69 entries stale (MACH-2) |
| the `INTERACTIVE=--interactive` path (`Test.Golden.runnerWith` in `tests/Main.idr`) | machinery | ignores `expected.<host>`, would overwrite runtime-archive-check's Linux expectation on macOS, and is the runner Runner.idr says can hang (MACH-4) |

### 3.6 The 181 output-only directories (every lane; MACH-15)

Each holds only a git-ignored `output` of a deleted test. Delete them, and
have the runner write outputs under `tests/build/results/` (§6, step 1), so
that deleting a test deletes everything of it. Two whole directories,
`idr/in-bounds` (13) and `idr/isolate` (7), are in no lane's list; they
are litter too.

- `idr/actions/`: canonicalize
- `idr/canon/`: covered-default, match-in-generate, unused-call
- `idr/constants/`: run (the whole directory)
- `idr/contify/`: never-returns
- `idr/dedup/`: refuse
- `idr/defunc/`: block-argument, dead-move-empty-key, evaluated-refused, fit, numbering, unknown-lazy
- `idr/e2e/`: reduce
- `idr/effects/`: erased-consumer, stale
- `idr/expect/`: breakers, breaks-last
- `idr/func/`: clone-shape, facts-roundtrip, inline
- `idr/guards/`: byte-message, fold-byte, speculation
- `idr/in-bounds/` (all 13): counters, counters-kept, dominated, doubled, kept, masked, proven, ranges, records, records-take, returned-twice, size-guard, string-index
- `idr/isolate/` (all 7): captures, constants, delay, evaluated-keyed, linear, nested, verifier
- `idr/loops/`: breakers, invariant-fields
- `idr/lower/`: array-combinators, array-never-returns, to-byte
- `idr/narrow/`: constants
- `idr/obs/`: budget, canonicalize, round-failure, round-trace
- `idr/ownership/` (all): consumed-effects, owned-stage
- `idr/pipeline/`: do-block-forced, fixpoint, nested-constant, rdv-address-taken, rdv-unreachable
- `idr/raise/`: not-raised
- `idr/rc/`: array-loops, atom-reuse, loops
- `idr/returned/`: arguments
- `idr/specialize/`: accumulator, breaker-clones, budget, clone-callers, closed-call, linear-shared, quantity, redirect, shared-key, twice
- `idr/stack/`: budget, calls, local, loops, lower, stored, tail
- `idr/vectorize/`: generate-fill-first, lanes-loops, refused-rows-in-order
- `idr/verify/`: linear, module
- `programs/arrays/`: buffer-byte-range, linarray-generate-bounds, linarray-generate-fill-once, linarray-generate-negative-size, linarray-rows-effects
- `programs/semantics/`: the 72 `prim-<type>-<family>-<k>` directories of the old Sem naming (prim-bits8 ... prim-int64, families arith, bitwise, cast, compare-0, compare-1, div, mod, shift)
- `registry/`: base-surface, string-iterator
- `reject/`: layout-256-counted-fields, layout-512-counted-fields, layout-768-counted-fields, primitive-shl, program-base
- `spec/`: cpp-starter, module-links, time-trace
- `toolchain/`: arena-page, arena-page-boundary, double-print, module-imports, runtime-page-size
- `upstream/`: clang-module-layout-forward-declaration

gaps cites one test from this list as coverage:
`programs/arrays/linarray-generate-negative-size`. It is no test, so its
contract (generate with a negative size) has no fixture today. It goes into
the array index generator's dictionary (§4.5).

### 3.7 Disagreements, and how each is resolved

Each resolution applies a stated rule rather than a preference.

**1. `idr/expect/typed-reads`** (search: delete; idr-b: rewrite).
- Resolved: **delete** the fixture and the `typed-reads` property.
- Reason: no test outside its own fixture uses the property (SEARCH-14).
  The op form it reads cannot be written. A property with no user and no
  writable failing case is the dead state RF says to delete.

**2. `idr/actions/inner-steps`** (idr-a: delete; gaps: rewrite-as-property).
- Resolved: **delete**.
- Reason: the property gaps wants ("skipping an inner step keeps
  behaviour") is GAPS-2's corpus property. That property covers the inner
  tags of idr-optimize too, so a second fixture would be a copy.

**3. `accept/action-run-at-once`** (accept-reject: delete; gaps: merge into
an IO-trace property).
- Resolved: **delete now**. Its source becomes one dictionary entry of
  the laziness and IO-trace generator when that lands (§4.5 G9).
- Reason: a dictionary entry is a shape, not a directory.

**4. `programs/semantics/closed-shift-negative`** (programs: delete; gaps:
merge into the Fuzz dictionary).
- Resolved: **delete**.
- Reason: its only value, a shift by -1, is in Sem's `shiftAmounts`, and
  Fuzz's signed shift amounts already draw negatives.

**5. `determinism/hello`** (repo: delete; gaps: rewrite-as-property).
- Resolved: **delete**.
- Reason: the property is `determinism@<program>` over a corpus (§4.6),
  and hello needs no directory of its own.

**6. `programs/io/output-fusion`** (programs: delete; accept-reject merges
`accept/fused-stored-string` into it).
- Resolved: **delete** it. `accept/fused-stored-string` and
  `accept/recursive-string` move to `programs/io/` as fixtures that state
  `output-fused` and the `heap-free` mark: the claim io/output-fusion
  never stated.
- Reason: the merge target dies, but the claim survives in the fixtures
  that can state it.

**7. `programs/data/shapes`** (programs: delete). repo keeps
`determinism/shapes`, and merges `determinism/threads-shapes` into
threads-rbtree; both compile shapes. `compiler/handoff-round-trip` also
compiles it.
- Resolved: delete shapes, and with it **determinism/shapes and
  threads-shapes** when the parameterized determinism corpus lands (§7
  stage 5).
- Reason: the corpus is read from data (the bench list and the programs
  list), so it has no shapes entry. handoff-round-trip goes when the round
  trip is universal (§4.3).

**8. `programs/semantics/closed-double-*`, `closed-char-to-string` and
`closed-integer-shift`.** Three lanes give three targets:
- programs: prelude/double-text (a property) and tests/two-levels;
- gaps: the Fuzz dictionary;
- accept-reject and search dissolve two-levels' recorded values.

Resolved, by what can tell each answer apart:
- the literals go into **Fuzz's dictionary**, because folded-against-run
  agreement is Fuzz's relation;
- the shortest round trip and even ties become the **`double-text`**
  property, because Fuzz's agreement cannot see a non-shortest digit
  string;
- two-levels receives nothing.

`e2e/doubles` is deleted only once both are in place.

**9. `unittests/Tagged.cpp`, `TaggedBits.cpp`** (repo: keep; search: merge
into runtime-bigs).
- Resolved: **merge**. `boxB()` and the shift amount sets become
  `runtime-bigs` boxes, sharing one edge-value header (REPO-16). The part
  only these files check, that each ODS op is bound to its runtime entry
  (`Abi<Op>::function`), moves into `Words.cpp`, which already walks the
  generated op table.
- Reason: one contract, one harness; the binding is a fact of the
  generated table.

**10. `unittests/Labels.cpp`** (repo: keep; search: merge into
expect/closures).
- Resolved: **merge**: one vocabulary, `labels=@f:arg0:[...]`.

**11. `unittests/Cycles.cpp`** (repo: keep; search: rewrite-as-property).
- Resolved: **rewrite** as an exhaustive box over every call graph of at
  most 4 functions, against reachability (TBS 8).

**12. `idr/expect/one-clone-two-copies`** (idr-b: merge; search: keep).
- Resolved: **merge** as a split of `one-clone`: one property, one file.

**13. `idr/expect/facts`** (idr-b: keep; search: rewrite).
- Resolved: **rewrite**. Delete RUN 2: any failure satisfies it, and it
  pins upstream's DCE.

**14. `idr/expect/counting`** (idr-b: rewrite; search: keep).
- Resolved: **rewrite**: its failing case written as hand-made owned IR.
- Reason: an oracle's own fixture may not depend on the pass the oracle
  judges.

**15. `programs/semantics/prim`** (programs: keep; search: rewrite).
- Resolved: **rewrite** as 9 programs, one per type, each case on literals
  (`folded=`) and on stdin values, both against `Prims`.
- Reason: today all 144 programs fold to 0, so codegen is never checked
  (SEARCH-7).

**16. `idr/lower/match-lit`** (idr-b: keep; spec/dialect-text fails on its
RUN 3, a FileCheck of pass-made text).
- Resolved: **rewrite** RUN 3 as a property. The repository rule wins over
  a lane's keep.

**17. Programs that gaps merges into generators but programs keeps.**
These are nat-loop, nat-sum, bits8-past-127, prelude/double-basics,
closed-literal-conversion, the sortedmap family, sorted-set, the leet
programs, stack/mutual-*, io/action-forced-twice and partial/self-forcing-caf.
- Resolved: **keep until the generator that absorbs it replays its input**.
  Then delete it in the same change (§7).
- Reason: an example goes only after its replacement has been shown to
  fail on the bug the example guards (TBS 9.2 step 5; matklad's "fix the
  fuzzer first").

**18. `accept/action-after-effect`** (accept-reject: rewrite so the division
crashes; gaps: merge into the IO-trace property).
- Resolved: rewrite now, because it is cheap and cannot fail as written.
  It is absorbed by G9 later.

**19. Mild: spec/totality and spec/refusals-as-data.** gaps lists them as
source coverage of AG-3 and PT-9, and repo deletes both.
- Resolved: delete.
- Reason: AG-3 stays covered by dialects-current, emit-dialects and the
  universal no-discardable-attribute property (§4.3). PT-9 is covered by
  the crisp half of no-fuel and by GAPS-14's generator.

## 4. The rewrite list: what each area becomes

One line per area: the property, the oracle and the generator that replace
today's examples, and the findings behind it. "Universal" means run by the
harness on every compilation or every dialect input, never asked for by a
fixture.

### 4.1 `tests/idr/` (the dialect suite)

| area | becomes | oracle | replaces |
| --- | --- | --- | --- |
| actions/, roles/contify, obs/debug-counter | one generated property over (optimization pass, action tag) × corpus: skip-all is the identity; skip-one verifies and runs to the same stdout and exit; a corpus-wide census fails a tag that never fires. Tags declared as TableGen records beside each pass's role (one source for the C++ `tag` and the table tests read) | the unskipped run (TBS 1.2, 7) | the ten actions files, roles/contify, obs/debug-counter, `IdrPassRoles.txt`'s missing reader (IDR-A-6, GAPS-2, GAPS-6, IDC-14) |
| every runnable fixture (root reads a byte, prints) | translation validation in lit: the module compiled as written and after the pass under test, both run on all 256 one-byte inputs, stdout and exit equal | the module as a second form of itself (TBS 8, exhaust the box) | hand-computed values (e2e/loops), "does not run again" comments (memo-rebuild, link-read-after-release, @twoWrites) (IDR-A-23, IDC-3) |
| defunc/ | the claims stated with existing rows: `labels=`, `by-name`/`not-by-name`, `forces-nothing`, a new `boxed` row; `no-closures` and `quantities-kept=%s` dropped; grade-* one `-split-input-file` corpus; sum-names a harness-wide function-order shuffle | the verifier, the contracts, the run above; then G-HO (§4.5) | 17 `no-closures`-only fixtures (IDR-A-2, -3, -17) |
| canon/, raise/, specialize/, optimize/, contify/, dedup/ | properties kept; every negative states its reason (FileCheck on idr-expect's diagnostic key) or becomes a positive; `merged=` as the complement of `apart`; copies found by origin (§6 step 3); specialization constants generated (5, 10^6, random) | properties plus translation validation | bare `%status 1` negatives, vacuous `one-clone`, countdown/countdown-long pairs (IDR-A-4, -5, IDC-2, IDC-8) |
| bufferize/ | `in-place`, `moves-out` and a positive `copies` row; @twoWrites deleted (One-Shot's fresh allocation is correct) | properties plus a run | aliasing's four any-failure negatives (IDR-A-5, -13) |
| fold/ | fold-versus-run differential over Sem's table: per foldable op, every width, an edge dictionary (0, ±1, min, max, width, width±1, negative amounts, NaN, ±inf, surrogates, offsets inside a UTF-8 sequence); canonicalized constant equals the compiled program's run-time value; `folds-balanced` on every fold | `Prims`/runtime meaning (AGENTS: folders call the runtime) | fold/{big-shift, shift, division, nat, pred, to-char, to-int, string-offsets}, fold/data's values (IDRB-7) |
| guards/ | one family generated from the `Idr_Guarded` records: satisfying constant folds the guard away, refusing constant keeps one crash site, re-guard folds, unguarded op on a refusing constant does not fold | `no-guards`, `returns=_` | guards/* six files (IDRB-8) |
| effects/ | a model-based property: programs over the lattice none/crash/io/diverge (IO ops, forged worlds used once by construction, guards, allocations, calls of each class); observable trace (output, then crash or exit) unchanged after canonicalize, cse, control-flow-sink; a few `test-idr-facts` meta-tests of the reporter; long-cycle as generated call graphs against reachability | the unoptimized run (TBS 9) | per-op remark tables (IDRB-15); catches `world.new` by behaviour |
| lower/, loops/, rc/, stack/ | inputs made from first-stage sources by the real pipeline at a named step (`--idr-pipeline=from:<stage>`), a failure there reported once as that step's; lowering promises stated as reads-nothing, calls-only on runtime symbols, crash-sites, linker-names, lowered, in-llvm; one fixture owns each layout fact; counting judged by run-time live cells, not inc/dec order; size limits exhausted at n-1, n, n+1, 2n±1 by a Gen generator, not awk in RUN lines; cpu-features parametrised over every target entry on every host | properties, live cells 0 under the checked runtime | 7 invalid hand-written owned fixtures, 20 hand pass chains, internal-signature pins, mangled awk (IDRB-2, -5, -6, -10, -16, -18, -20) |
| verify/, syntax/, world/, tie-shape/verify, func/, rc/verify | one file per rule family; `-verify-diagnostics` matched on a rule key the diagnostic carries, not prose; upstream's and ODS's sentences unmatched beyond `operand #N must be`; inherent-attribute rule enumerated from the registered ops; verifier adequacy by a mutation pass whose named operators each must produce their diagnostic, over the corpus's dumps; old names, old carrier, `-0`/`007` splits deleted | the verifier (GAPS-21) | wording pins, four-example inherent-invalid (IDC-6, -7, -14) |
| asm/ | prefix checked per op without a CHECK-NEXT chain; aliases and names kept (the printer's contract); a universal custom-form round trip and canonicalize convergence on every fixture | printed form is the contract here | asm/prefix, the 25 hand copies of `test-convergence=true` (IDR-A-15, -16) |
| expect/, contracts/ | oracle meta-tests stay, matched on `{{expected <property>: @f}}`; coverage reads the property list from `idris-mlir-opt --idr-expect-list` and requires a real failing RUN line; seeded mutants for every oracle never shown failing (`folds-balanced` by a test folder that leaks) | the checker against planted breaks | sed-of-Lookup.cpp coverage (IDRB-14, SEARCH-11, -12) |
| obs/, pipeline/ (driver half) | a `driver/` pool: exit status, verdict, report, presence of outputs; report identical at every thread count; never MLIR's own sentences or the tree printer's file names; pipeline/timing's inner-pass list generated from the pipeline definition | the driver's contract | stats, print-ir-threads' upstream sentence, steps' dump names (IDC-4, -18, -19) |
| names/ | metamorphic generator over a random fixture: reorder functions, edit one body, add an unrelated function; every symbol not made from the edited code keeps its name, read from the module, not scraped | metamorphic (TBS 9.3) | names/edit, names/reorder (IDC-4) |
| vectorize/ | one host-target test per property, target facts (lane count) read from the target entry | | the three per-target files (IDC-10) |

### 4.2 `tests/programs/`

- **A golden core of about 100 programs**, kept where the contract fully
  decides stdout (TBS 1.3). These are:
  - the IO and runtime contracts, laziness, effect order and sharing (with
    timeouts as oracles);
  - the library contracts: SortedMap/Set, Vect, Buffer, the string
    iterator, LList;
  - the silent-miscompile regressions, the stack shapes with their marks,
    and the `every-*-export` coverage set.

  Each fixture states its pass properties of its root (Roots forms of
  `counts-nothing`, `tests-nothing`, `reuses-in-place`; PROG-4), at a stage
  rather than "the step after a group" (PROG-5).
- **Generated topics** replace the hand-picked families. Each is a
  parameterized directory like `prim@`, on Gen's tapes (§4.5):
  - G1 ADTs and layout (`data/adt`, `data/layout@<n>`);
  - G2 linear lists (`linear/lists`);
  - G3 Linear.Vec commands (`arrays/vec-model`, plus the IOArray index
    property);
  - G4 the crash table (`semantics/crash@<guard>`);
  - G5 text (`prelude/double-text`, the cast-from-string grammar, the
    UTF-8 decoder);
  - G6 Nat and Integer boundaries;
  - G7 recursion and tail-call graphs;
  - G8 leak growth: every kept program run at two input sizes, with equal
    live counts.
- **Programs built from bench/** move: each `mlir.expect` goes to
  `bench/<name>/`, run by `bench/smoke@<name>` through the one program
  runner, and the nine fixtures are deleted (PROG-10).
- **A shared helper package** (`readInt`, the IOArray helpers) replaces 45
  copies (PROG-17).
- **Target facts** (OS name, byte order) are read from the build, not from
  `io/system-info/run`'s case (PROG-19).

### 4.3 Universal checks (every compilation: e2e, accept, bench, Fuzz, the program generators)

Each check below runs inside the harness, so a fixture never asks for it.

1. The verifier after every pass (already).
2. The five contract relations, on real pipelines. The emitted module is
   replayed through `idris-mlir-opt --idr-contracts` at the step each dump
   names, and compared with the next dump (GAPS-5). This keeps `idris-mlir`
   free of test options: 0002 §4.1 and spec/no-behaviour-options both
   forbid giving it one. It replaces the dump-based `quantities_kept` and
   `dumps_verify` (PROG-2, PROG-3).
3. Emit's quantities against the program's Core: the parameter count is
   the non-erased binders' count, and each linear binder is `!idr.lin`
   (GAPS-4).
4. The lowered module's facts:
   - `linker-names`, `entry`, `aligned-access`, `lowered`, `in-llvm`;
   - `direct-calls` after defunctionalization;
   - `stage` per `IdrPassStages.txt`;
   - `stack-bytes<=N` (GAPS-5, GAPS-19).
5. The emitted module's byte round trip, in generic form and as bytecode.
   This replaces `compiler/handoff-round-trip` and the round-trip half of
   handoff-readable (AR-8, AR-9).
6. No `idr.*` discardable attribute, except `idr.refusals` on a module
   without a program. This replaces spec/facts-in-types' grep (REPO-7).
7. Objects import only what a program may (already).
8. A checked runtime build (GAPS-18, PROG-22):
   - freed cells poisoned and quarantined;
   - every decrement asserts a live counted cell;
   - every take and recycle asserts its exclusivity claim;
   - live cells reported to a file on every exit path, not to the
     program's stderr (MACH-11).
9. Sampled determinism: 1 in k compilations is redone at a random second
   thread count, with the seed printed (MACH, REPO-18, GAPS-10).

### 4.4 `tests/accept`, `reject`, `compiler`, `registry`, `two-levels`

- **A profile fixture is its sources and a header.**
  - The header reads `-- expect: <rule>, <file>:<line>` (AR-4), or
    `-- expect: <rule> or stdout, <file>:<line>` for a known limit (AR-6),
    with the named value read from a structured field of `--report`.
  - The runner enumerates the fixtures, so the 102 `run` and `expected`
    files go (AR-2).
  - A fixture that does not elaborate is reported as such before anything
    else (AR-1).
  - `idris` becomes `elaboration`, and `compiler/elaboration-error` joins
    reject/ (AR-5).
- **Pools generated from tables:**
  - one program per Forbidden or Deprecated registry entry, checking rule,
    site and named entry (AR-14);
  - one fixture per *case* a rule promises, read from a `cases` field
    beside the rule, so `%foreign`/`%extern` cannot be missing again
    (GAPS-1).
- **Growth, end to end.** A generator turns Box.idr growth graphs into
  Idris sources (type families, dictionaries, pairs). The oracle is the
  brute force on the generating graph: refused at the cycle iff it grows,
  otherwise it compiles and prints a value computed from the graph. It
  replaces the bounded-* and polymorphism-growth-* cases as regression
  seeds (AR §5, GAPS-15).
- **Refusal relations over the corpus** (GAPS-15):
  - the offending definition kept but unreached from main compiles;
  - two fixtures' offenders reached together give exactly two refusals,
    each at its line.
- **Unit properties against the installed fork:**
  - registry validation: every entry's perturbed shape is refused naming
    that entry, and the true table validates (AR-3);
  - probe names: every `Probe` at small arguments round-trips (AR-13);
  - fork termination: every call graph of at most 3 functions with
    size-change labels, against a brute-force closure.
- **Hook semantics by a second implementation.** The Nat hooks are checked
  against unary copies on Gen-drawn Nats.
- **Two-levels is dissolved:**
  - its integer terms go to Sem's tables;
  - Double, Char and String values become a reviewed table derived from
    the runtime's documentation, never accepted from the compiler's
    output;
  - the Prelude corpus becomes laws over generated values
    (`reverse . reverse = id`, ...) (AR-16, SEARCH-5).
- **Driver contracts stay exact:** artifacts, frontend-beside,
  frontend-named-file, no-environment, content-hash with its published
  vectors.
  - artifacts gains a command-sequence property: any {succeed, fail}
    sequence leaves exactly the last success's artifacts.
  - main-visible is split into an accept and a reject fixture, and
    frontend-command-line reads the refusal from the module the frontend
    wrote (AR-20).

### 4.5 The search (`Gen`, `Fuzz`, `Sem`, `tests/fuzz`, prop.h)

- **Keep `Gen` as it is.** Its foundation is right (TBS 4.1, 5, 8): the
  replayable choice tape, `Weights` that cannot be all zero, swarm, the
  odometer, the proved shrinker. Its shrinker self-checks become exhaustive
  over small tapes.
- **Fuzz widened** (SEARCH-8, -9, -18, GAPS-11):
  - Integer, Nat and stdin strings in the runtime part;
  - ±2^62 edges in the pools;
  - a named breach mode, judged by the documented crash with output before
    it;
  - families drawn first, then a primitive, so the weights written are the
    shares;
  - every rendering required exactly once (SEARCH-21).
- **Regression is a corpus.** `make test` replays a committed corpus of
  shrunk failing tapes plus two seeds. `make fuzz` draws seeds from the
  clock and appends failures (SEARCH-2).
- **A compile failure is isolated and shrunk:** delta debugging over the
  cases, then the tape shrinker, then `idris-mlir-reduce` (SEARCH-3).
- **Contracts and action-skip differentials on every fuzz build**
  (SEARCH-10), through the replay route of §4.3.
- **The typed program generator** (0002 §9, GAPS-3, SEARCH §4). Each stage
  is a named, weighted family:
  - first-order recursion over generated data (G1);
  - higher-order with bounded closure sets (G-HO: defunctionalization);
  - linear values and arrays (G2, G3, with `Live`/`Stale`/`Wild` indices
    by name, TBS 4.4);
  - laziness with `Share` and output (G9: a call-by-need model with traces
    and force counts, GAPS-9, GAPS-12);
  - growing static arguments (GAPS-14);
  - tail-call graphs, including results returned in memory (G7).

  The oracle is a small evaluator in the harness, written in Idris over
  the generator's own AST, with `Prims` for primitives. It is ours, so it
  is allowed (TBS preamble). Beside it, idr-expect properties are chosen
  from what the generator knows it built.
- **Sem:** 9 programs, both paths (§3.7 item 15). `two-hosts` keeps only
  the generators' self-checks; its 3600 lines of pinned generator output go
  (SEARCH-4).
- **Perception:** each run reports its (family, result type, construct)
  features and a Good–Turing estimate. Reports go to the work directory,
  never to tracked files (SEARCH-17, REPO-22). prop.h shrinks bytes as Gen
  shrinks tapes (SEARCH-20), checks the shared splitmix vectors
  (SEARCH-28), and gets rotating seeds and finer classes in a separate
  target (REPO-17).

### 4.6 `tests/spec`, `toolchain`, `upstream`, `determinism`, `bench`, googletest

- **spec/: one table of crisp rules.** Each row holds the rule, its
  matcher, a planted witness, and a shrink-only allowlist with reasons
  (REPO §5).
  - Module-graph rules: frontend/fork, and `MLIR.Internal` imported only
    from `Dialect.*`, which replaces emit-dialects' `=` parser.
  - Token rules, lexed: `prim__`, the iteration-limit APIs,
    `for(;;)`/`while(true)`, `%default total` against `tools/policies.txt`,
    no `registerAll`, no `cl::opt` outside Options.
  - One layout walk: zones, headers, modules, file size.
  - The behavioural pin and policy checks, as they are.
  - Lists the code owns are read from the code: option categories, the
    Makefile's command block, the build manifest, a CMake-generated box
    list (REPO-6).
  - A new `spec/target-confined` (GAPS-17).
- **toolchain/:**
  - check-archive becomes one table-driven test (REPO-15);
  - static-linking checks every built executable but idris-mlir-front
    (REPO-13);
  - runtime-container compiles an Idris fixture (REPO-8);
  - cpu-features uses the build's flags and prints no count;
  - big-cell reads the layout through `offsetof` (REPO-9).
  - io-buffer is the template for the rest: a constant shrunk into the
    box, the default build on the other side.
- **upstream/:**
  - MLIR reproducers in upstream dialects only, with the idr halves moved
    to `tests/idr/bufferize`;
  - the fork reproducers run in `make test` (REPO-12);
  - one-shot-tensor-like-copy reproduced on a real tensor-like type, or
    deleted (REPO-10);
  - work counts in place of wall-clock ratios (REPO-11);
  - every command `bounded`.
- **determinism/:**
  - `determinism@<program>` over the bench list and Fuzz seeds, with
    thread counts drawn per run;
  - `names@<seed>`, using the provenance rule of §8 (REPO-18, GAPS-10).
- **bench/:** `smoke@<name>`; records and report as they are.
- **googletest:**
  - a `unit` pool read from `IDR_BOXES`, each test in its own process
    (SEARCH-19);
  - Flow iterates the registered external models (REPO-9);
  - Cycles is exhaustive, Labels moves to expect/, and Tagged/TaggedBits
    are merged (§3.7).

### 4.7 The machinery

See §6. In short, one typed core replaces the transcripts:
- a `Fixture` record, parsed once;
- `Outcome = Exited | Signalled | TimedOut`;
- `Check = Holds | Fails Evidence`;
- `Verdict = Passed | Failed (List1 Check) | Unaccepted Host | Skipped Host`.

Shell only spawns processes.

## 5. Code bugs the tests reveal (with duplicates removed)

Each entry gives the failure as the outputs show it, the tests that show
it, the reading the lanes give, and its status. **Status** is one of:
- **open**: nothing after the run addresses it;
- **recheck**: a later commit names the cause;
- **plausible** or **uncertain**: the evidence does not settle it.

### 5.1 The oracles and the driver

1. **`foldsBalanced` dereferences an unloaded dialect.**
   - Failure: exit 139 in `IdrDialect::foldLeakCount` from
     `ContractInstrumentation::runAfterPass`.
   - Shown by: idr/actions/narrow-lanes, actions/returned-arguments,
     narrow/select-lanes, tail-calls/decided-loops, tail-calls/positions,
     returned/threaded.
   - Reading: `Expect/Folds.cpp:21` dereferences
     `getLoadedDialect<IdrDialect>()`, which is null for a module of
     upstream dialects. Confirmed in source.
   - Status: open.
2. **The driver aborts because complex's `ConvertToLLVMPatternInterface` was
   never registered.**
   - Shown by: 13 idr/e2e, lower/big-fast-path, and 16 idr-c driver tests
     (obs/*, pipeline/*, rc/live, tail-calls/mutual, vectorize/rows-aarch64).
   - Status: recheck (25f263da).
3. **`#idr.instance` printed an empty argument list that its parser
   refuses.**
   - Shown by: the 8 upstream fork reproducers and idr/stack/hot-loop.
   - Status: recheck (25f263da).
4. **`idr.refusals` was refused on an explicit top-level module.**
   - Shown by: idr/syntax/refusal, upstream/totality-unimported-callee.
   - Status: recheck (dcafd452).
5. **Two googletest boxes segfault.**
   - Shown by: Hooks.Pred, Words.EachBigOpIsItsWordOp, on old binaries.
   - Status: recheck (7589866c).

### 5.2 Reference counting (idr-rc and the runtime)

6. **idr-rc grading leaves IR the graded verifier refuses.** The outputs
   show:
   - an owned `match`/`match_lit` scrutinee;
   - plain returns under an `!idr.own` signature;
   - plain call results in a graded program;
   - `default` regions and case fields not regraded;
   - a guard borrowed while its result stays plain;
   - `nat.to_big` at the wrong grade;
   - `own.give` of a borrow;
   - linear results left ungraded.

   Shown by about 33 tests:
   - idr-a: actions/narrow, contracts/nested-run;
   - idr-b: lower/{atom, box, crash, nat, static-thunk, value-buffers,
     match-lit, strings-bigs}, loops/trmc-counter, expect/counting;
   - idr-c: rc/{arrays, atom-pairs, buffers, consumed, counts, dies-apart,
     exclusive, regions-counted, returned, second-redirect, share-trap,
     statistics, take-at-death}, narrow/{descending, versioned},
     verify/owned-stage, optimize/pure-call, raise/sunk-call-paths.

   Status: recheck (4c87dcc5, 3d279eb9).
7. **idr-rc's cells or stack step leaves `idr.cell.init` with an unlinked
   operand** (a use after erase).
   - Shown by: actions/stack, actions/tail-loops, loops/tail-loop,
     lower/llvm-facts, stack/{escapes, expect, linear-box},
     rc/{stack-cell, kept-fields, nested-reuse}, pipeline/rc-steps.
   - Status: recheck (a7bf77b4). Rerun under the sanitizers.
8. **The owned verifier refuses counting's output in front of
   `linalg.generic`.**
   - Failure: "consumes a view, which holds no reference".
   - Shown by: determinism/threads-linarray-lanes,
     compiler/handoff-round-trip (programs/arrays/linarray-combinators).
   - Status: open.
9. **idr-rc-exclusive writes an `!idr.own` yield where its solver proved
   `!idr.excl`.**
   - Shown by: programs/prelude/every-uninhabited-export,
     bench/smoke regex-redux.
   - Status: open.
10. **Live cells at exit** (leaks). About 40 programs and 8 benchmarks.

    | test | live cells |
    | --- | --- |
    | stack/replicate-take-deep | 10000000 |
    | eval/thunk-consumes-list | 1000003 |
    | arrays/ioref-closures | 1001 |
    | eval/memo-shared-stream | 358 |
    | data/pidigits | 90 |
    | accept/runtime-lazy-value-growing-choice | 48 |
    | eval/stream-share | 29 |
    | data/identity-weakening | 25 |
    | eval/memo-lazy | 20 |
    | prelude/split-prefixes | 18 |
    | io/action-forced-twice | 12 |
    | data/records-nested-past-the-cell | 9 |
    | prelude/show-values | 8 |
    | data/records-past-the-cell | 7 |
    | every IORef/IOArray program, and registry/nat-operations | 1 each |
    | bench: deriv 1750, fasta-redux 595, fasta 593, binary-trees 63, pidigits 90, reverse-complement 6, fannkuch-redux 3, mandelbrot-pbm 1 | |

    Reading: drops the counting step no longer places on these paths
    (3d279eb9, 9696ecc5): a forced memo cell's value, and an IORef
    element on write. deriv's and fasta's leaks grow per iteration.
    Status: open.
11. **Crashes after main returns.**
    - Shown by: io/directory-listing (SIGBUS, live cells 7),
      stack/io-loop-through-helper (SIGSEGV, live cells 30017).
    - Reading: the fault is in teardown, with cells still live.
    - Status: open.

### 5.3 Lowering and code generation

12. **`'llvm.call' op operand type mismatch: expected 'i64', provided
    '!llvm.ptr'`.**
    - Shown by: basic/guards-messages-str-head, guards-messages-str-index,
      string-loop-one-value-twice, prelude/string-pack, every-cast-export,
      data/bubble-sort, accept/string-primitive-runtime-match,
      two-levels/terms (prelude), bench nqueens.
    - Reading: a runtime string entry is called with a pointer where its
      ODS-generated declaration takes a word, which fits the wave's split
      of the string and show operations.
    - Status: open.
13. **Heap-free broken.** The allocations are show ops inside a delayed
    main, a `cell.new` in main.delay, and an `idr.con` in @Main.next.
    - Shown by: data/nbody, interfaces/interface-ring-power,
      prelude/double-basics, math-showcase, double-cast-nan,
      eval/lazy-branch-loop.
    - Status: open.
14. **Constant stack lost for `traverse_` and `for_`** (through `io_bind`
    and `foldr`).
    - Shown by: prelude/traverse-deep, stack/for-long-list.
    - Status: open.
15. **The string folders over-release.**
    - Failure: `folds-balanced` reports -1 and -2.
    - Shown by: canon/output-fusion, fold/strings.
    - Reading: plausibly `stringOfList` releases each intermediate twice.
    - Status: open.
16. **`idr.world.new` declares only `MemWrite<IO>`, so it answers "may be
    delayed".** Its own ODS description promises otherwise.
    - Shown by: effects/io.
    - Status: open.
17. **The idr-structure-loops pass.**
    - An `affine.delinearize_index` assertion in structure/dynamic-cells
      (open).
    - "no structured op" in structure/never-returns and ordered
      (plausible).
18. **The printed form of `idr.con` differs from its documented form.** It
    prints `@Just (` where IdrOps.td documents `@Just(`. Cosmetic.
    - Shown by: asm/prefix.
    - Status: open.

### 5.4 Analyses, optimization and the frontend

19. **Monomorphic programs are refused as `unsupported (polymorphism)`.**
    - Failure: on `Builtin.DPair.(#)`, `Linear.Notation.MkBang`,
      `PrimIO.MkIORes` and `Builtin.MkPair`, with "a shape whose rank no
      analysis fixes: [__]".
    - Shown by: 12 Linear.Vec programs; bench fannkuch-linear, k-nucleotide,
      qsort, spectral-norm-linear, unionfind; 16 non-reject tests in all.
    - Against: AGENTS (a bounded set compiles) and 0004 §1.3.
    - Status: open.
20. **Streams miscompile.**
    - accept/streams prints 34 for 55;
    - accept/partial-stream never ends.
    - Status: open.
21. **eval/closure-result-roundtrip hangs at run time.** Status: open.
22. **Quantities lost.**
    - Specialization clones (`rev.spec.*`) get quantity ω where Idris
      proved 1: 12 linear tests at the full run.
    - After defunctionalization, a bound field of a case is lost:
      linear-catch-all, linear-nested-match.
    - Status: recheck. f5c6ca69 changed Specialization.cpp, and e6d8d6d8
      changed how the checker identifies a binder. That is the
      location-identity problem of PROG-2 being patched on both sides
      again (§6 step 4 removes it).
23. **The identity analysis misses `@carry`.** Shown by: identity/identity.
    Status: open.
24. **The flow rule no longer refuses `arith.select` of a closure or a
    suspension.** Shown by: verify/flow. Status: open (a regression).
25. **Plain canonicalize moves a match past a call with default effects.**
    Shown by: optimize/case-of-case-calls RUN 3. Status: plausible.
26. **Calls with equal keys are not raised.** Shown by: raise/shared-key.
    Status: uncertain.
27. **idr-defunctionalize reaches an internal error from verified IR.**
    The error is an i1 capture with no sum field. Shown by:
    defunc/nested-sum-failure. Status: open. It is a representation gap:
    the capture constraint should refuse such a capture, or a sum field
    should hold an i1.
28. **idr-defunctionalize does not finish in 60 s on 65,537 labels.**
    Shown by: defunc/tag-limit. Status: plausible, confounded with the
    harness's round trips.
29. **The knot refusal is at main's line 16.** Passes.td's rule puts it at
    "a value of a type on it", the `Nothing` at line 18. Shown by:
    reject/cycle-ioref-knot. Status: open.
30. **unsafePerformIO is no longer reported as an escape hatch.** Shown
    by: prelude/every-primio-export. Status: uncertain until the probe
    shows its evidence (MACH-9).
31. **Two `Main.main` lambdas get new names after an unrelated edit.**
    Shown by: determinism/name-stability. Status: uncertain until the
    provenance rule of §8 is applied.

### 5.5 Driver, runtime surface, toolchain and code rules

32. **A stale hashed `.o` survives a failed rebuild.** Shown by:
    compiler/artifacts. Status: open.
33. **The dialect samples' root `@sample` breaks the root type rule.** The
    test data lives in `SyntaxSamples.idr`. Shown by:
    compiler/dialect-syntax. Status: open.
34. **The prepared runtime now needs `memcmp`.** Shown by:
    toolchain/runtime-prepared. Status: open; resolve by allowing it (§8).
35. **spectral-norm times out on its small input.** Shown by: bench/smoke.
    Status: open.
36. **A wrong user `--runtime` is reported as an internal error.** Shown
    by: toolchain/runtime-triple. Status: plausible.
37. **Seven C++ units are over 400 lines.** Shown by: spec/file-size.
    Status: open.
38. **Specialized symbols exceed NAME_MAX for MLIR's tree printer.**
    - Shown by: 27 tests. In registry/scalar-bytes the compile exits 1.
    - Status: open. §6 step 2 stops the harness's use of the tree printer.
39. **Compile timeouts at 60 s** (20 programs, 6 accept and registry tests,
    fuzz, two-levels) and at 600 s (two-hosts). Status: confounded. The
    rule in §8 decides.
40. **lit's `eval` cannot carry an unquoted `(`.**
    - Shown by: structure/columns, which can never pass as written (IDC-13).
    - Status: open. This is a harness defect, listed here because its
      fixture can never pass.
41. **idr-narrow's pass and `@carry`.** *(No such bug: deleted from this
    list.)*

Item 41 is struck through on purpose, to keep the numbering stable: it
was a duplicate of item 23. That leaves **40 distinct code bugs**:
- 5 likely fixed and to be rechecked (items 2 to 5, plus item 6's and
  item 7's commits, which change the count of what remains);
- about 9 plausible or uncertain;
- the rest open.

**Machinery defects** (the harness's own; §6 fixes them):
- the summary under-counts and never shows skips (MACH-3);
- `--interactive` reads the wrong expectation (MACH-4);
- `fuzz.sh` prints ok for unrun checks (SEARCH-1);
- lit.sh's `not` and `%status 1` are vacuous (MACH-5);
- a pass-name selection holds on empty (MACH-19);
- a missing googletest box is no failure (SEARCH-19);
- `--mlir-print-ir-tree-dir` changes outcomes (AR-10).

**Reclassified as not code bugs**, by evidence read in this synthesis:
- **verify/values `-0` and `007`:** `BigAttr` holds an `APInt` since
  bfdcac70, so two spellings of one value are now one attribute. The
  splits test removed behaviour.
- **compiler/handoff-readable's `instance`:** an `OptionalAttr` in
  IdrOps.td, so the check asserts more than the contract.
- **effects/crash 8 against 7:** a miscount in the fixture.
- **bufferize @twoWrites:** One-Shot's fresh allocation is correct.
- **fold/range:** dead functions under a dummy root.
- **dialect-text's 5 hits:** fixtures, not compiler.

## 6. Machinery the rewrite needs first, in build order

The order follows one rule: a later step must not be built on a harness
that can lie. Each step names what it deletes.

1. **Make the harness truthful.** These are small fixes, and nothing else
   can be trusted until they land.
   - Count verdicts against the selected list: unreported is a failure,
     and skipped tests are named (MACH-3).
   - Print a diff, and attribute a run script's stderr.
   - lit.sh stops at the first failing RUN line, injects
     `--verify-roundtrip --idr-contracts` only on lines expected to
     succeed, and handles `%%` (MACH-5).
   - fuzz.sh reports `not run: <step>` as a failure (SEARCH-1).
   - Fix `Folds.cpp:21`, and give the contracts a fixture of upstream
     dialects only (IDR-A-7).
   - Write outputs under `tests/build/results/`, and delete the 181
     directories (MACH-15).
   - Give the 15 never-elaborated fixtures their imports, with an
     `idris-mlir-front --check` gate before profile tests (AR-1).
   - Delete: the interactive path; `lib/rules.sh:refusal_rule`.
2. **Observe without distorting.**
   - Dump only the steps a fixture or a universal check reads, one file
     per step, at group boundaries too. This removes
     `--mlir-print-ir-tree-dir` from the harness (PROG-1, PROG-5,
     SEARCH-6, GAPS-25).
   - Split the CPU budget, so runner threads × compile threads ≤ NCPU
     (MACH-17).
   - `Outcome = Exited Int | Signalled Signal | TimedOut`, decided where
     the process ends (MACH-11).
   - The live-cell count goes to a file named by `IDRIS_RT_LIVE`.
   - Re-time every timed-out compile by the rule in §8.
3. **A typed result and fixtures as data.**
   - The `Fixture` record, parsed once (MACH-14). Unknown mark files are
     refused, and conflicting marks cannot be built.
   - `Check`/`Verdict` computed from the fixture's files (MACH-1).
   - Acceptance as `(test, host, expectation hash)` records with an
     `Unaccepted host` verdict, written by `make accept` (MACH-2).
   - Pools derived from the tree, and `targets` parsed into a closed
     `Host` (MACH-12).
   - `test-unit` as a pool read from `IDR_BOXES` (REPO-14). `bench/smoke@<name>`.
   - One program runner, so profile_accept, bench_smoke, fuzz and
     two-levels stop re-implementing it (MACH-7).
   - The runner drops `Test.Golden` and contrib, so it builds under
     idris-mlir (MACH-13; RF "the subset we compile").
   - Deletes: about 830 transcripts, 304 lit boilerplate files, the 102
     accept/reject `run`/`expected`, every NEEDS-ACCEPTANCE mark.
4. **A richer assertion vocabulary** (TBS 1.1: Winters' second point).
   - **In idr-expect:**
     - the origin of every function given at parse, a `NameLoc` from its
       symbol, so hand-written fixtures' copies are found (IDC-2);
     - Roots forms of `counts-nothing`, `tests-nothing`,
       `reuses-in-place` (PROG-4);
     - new rows: `merged=`, `boxed`, `stack-bytes<=N`, and bound forms
       (`crash-sites<=n`, `loops>=1`);
     - a request naming a function its root cannot reach is refused
       (IDRB-3);
     - `--idr-expect-list`;
     - expectations written as IR in the module (an `idr.expect`
       attribute), not in a pass-option string (IDRB-11).
   - **A rule identity on every verifier diagnostic**, so
     `-verify-diagnostics` matches the rule, not prose (IDC-6). A
     `%refuses <rule>` lit directive is read from `--report`.
   - **The pipeline from data:**
     - `idris-mlir-opt --idr-pipeline=from:<stage>` / `to:<step>`, read
       from the one pipeline definition (IDRB-2, IDC-16);
     - the generated table of (pass, role, stage, action tags), which the
       tests read (GAPS-6, IDR-A-6).
   - **Contracts compare a copy with its origin** (SEARCH-24). A binder is
     identified by its function and position, not by a location (PROG-2).
     This deletes the location-keyed check that f5c6ca69 and e6d8d6d8
     patched again.
   - **Deletes:** FileCheck of pass-made text, hand pass chains, dummy
     roots, wording pins, the mlir.check path (MACH-18).
5. **Universal oracles on every compilation.** These are the nine of §4.3.
   - They include the checked runtime pool and the replay of contracts
     through idris-mlir-opt.
   - Deletes: dump-based `quantities_kept`/`dumps_verify`,
     handoff-round-trip, handoff-readable, facts-in-types' grep, the
     post-defunc `no-closures` and `quantities-kept=%s` assertions.
6. **Differential oracles over the corpus.**
   - Action-skip, with swarm over the tags and bisection to one action
     instance (GAPS-2).
   - Translation validation of the runnable dialect fixtures over 256
     inputs (IDC-3).
   - Fold-versus-run over Sem's table (IDRB-7).
   - Sem's 9 two-path programs (SEARCH-7).
   - The determinism and name relations (REPO-18).
   - Refusal relations (GAPS-15).
7. **Generators, each with its own oracle and features.**
   - In this order:
     1. Fuzz widened, with the corpus and `make fuzz` (SEARCH-2, -3, -8,
        -9, -18);
     2. G1 ADTs and layout;
     3. G3 the Linear.Vec and IOArray command model;
     4. G4 the guard and crash table;
     5. G2 linear lists;
     6. G7 tail graphs;
     7. G9 laziness and IO traces;
     8. G-HO higher-order;
     9. growth schemes;
     10. the registry entry pool;
     11. the verifier mutation operators (GAPS-21);
     12. the effects model (IDRB-15);
     13. G5 text;
     14. G6 Nat and Integer;
     15. the simulated platform (GAPS-22).
   - The reason for the order: earlier generators reach where today's
     failures cluster (layout, arrays, guards, RC). The laziness and
     higher-order generators need the evaluator. The platform needs a
     runtime interface that does not exist yet.

## 7. The rebuilt suite, and a staged plan to reach it

### 7.1 The shape

| home | what lives there | oracle | form |
| --- | --- | --- | --- |
| `spec/` | the repository's rules as one table of rows with planted witnesses | the rule's matcher, witnessed | data |
| `unit/` (googletest boxes, runtime prop programs, Gen/Sem self-checks) | exhaustive boxes and model-based runtime properties | `__int128`, GMP, strtod, the Unicode tables, models | boxes and seeded search; rotating seeds in `make fuzz-runtime` |
| `idr/<pass>/` | `.mlir` fixtures only: each property with a fixture on which it must fail; expect/ and contracts/ as the oracles' own mutation tests; verify/ keyed by rule; asm/ and syntax/ for printed form | idr-expect, the verifier, contracts, translation validation over 256 inputs | small examples where they are a rule's discriminator; generated families (fold, guards, effects) |
| `driver/` | idris-mlir's command line: exit, verdict, report, outputs | exact (TBS 1.3) | examples |
| `programs/` | the golden core (about 100) | `expected-stdout`, marks, universal | examples whose output the contract decides |
| `gen/` (G1 to G9, G-HO, growth, registry, mutants) | the generated topics, each `name@<seed>` | the generator's evaluator or a value known by construction; universal; properties the generator knows | Gen tapes, swarm weights, shrinking; a corpus of failing tapes in `make test`, campaigns in `make fuzz` with a Good–Turing stopping rule |
| `relations/` | action-skip, determinism, names, unreached-edit, refusal composition | metamorphic | over the whole corpus |
| `accept/`, `reject/` | sources plus a header | `--report` (rule, file:line, named value) | one fixture per rule *and* per promised case |
| `toolchain/`, `upstream/` (MLIR only), `upstream-fork/` (in `make test`), `bench/` | as in §4.6 | behaviour, reproducers, records | |
| universal | on every compilation | §4.3 | none: it is the harness's |

Expected files survive only where the contract fully decides a text:
- program stdout and crashes;
- refusal headers;
- printed syntax;
- determinism's byte equality;
- the bench report.

### 7.2 Stages

Each stage ends with every failure in the suite being a code bug listed in
§5 (with its tests), never a test's or the harness's fault. Each stage
deletes what it replaces in the same change (RF "delete what the
representation makes dead"). Code bugs are fixed alongside, by their own
lanes. The suite passes when §5 is empty, on both targets.

**Stage 0: purge and recheck** (no new machinery).
- Delete the 59 tests of §3, the 181 directories, `ACCEPTANCE.md`, the
  interactive path, and the partial deletions:
  - the dead RUN lines and functions: canon/shared-action's @once,
    upstream-passes RUN 4, @twoWrites, expect/facts RUN 2,
    sink-into-regions' @scrutinee/@used_after;
  - the old-name splits of verify/attributes and verify/values, and
    handoff-readable's old-forms check;
  - the lane ids in comments;
  - the stale compile-time-evaluation comments.
- Rerun everything on today's build, so the recheck items of §5 (2 to 7,
  22) are settled.

**Stage 1: harness truthful** (§6 step 1).
- Fix the never-elaborated fixtures. They then report their real
  verdicts: two guard fixed silent miscompiles (PROG-9).

**Stage 2: observation** (§6 step 2).
- The FTL failures disappear or show their real error.
- Every timeout gets its verdict by the rule in §8.

**Stage 3: typed result** (§6 step 3).
- About 1,200 boilerplate and transcript files go.
- Acceptance becomes per host.
- `test-unit` and bench join the runner.
- From here on, a failure prints only the failing checks.

**Stage 4: vocabulary** (§6 step 4).
- Rewrite every fixture in the rewrite list whose fault is wording,
  printed text, pass order, a dummy root, a missing NameLoc, an inlining
  pin or a group-step pin, in the new terms:
  - IDRB-2, -3, -4, -5, -11;
  - IDC-2, -4, -5, -6;
  - PROG-4, -5, -24;
  - AR-4, -5, -6, -20;
  - SEARCH-11, -12.
- Merge the duplicates of §2.9.
- Parametrise the per-target tests over the target entries.

**Stage 5: universal and differential oracles** (§6 steps 5 and 6).
- **Delete:**
  - the ten actions files, roles/contify, obs/debug-counter;
  - e2e/loops' values;
  - the eight fold tables and six guard files;
  - the 144 `prim@` programs, now 9;
  - two-levels;
  - the determinism directories, determinism/shapes and threads-shapes
    included;
  - handoff-round-trip, handoff-readable;
  - the post-defunc `no-closures`.
- **Add** the oracles §2.10 found missing:
  - Emit against TT;
  - contracts on real pipelines;
  - the checked runtime;
  - `%foreign`/`%extern` cases;
  - `spec/target-confined`.

**Stage 6: generators** (§6 step 7, in its order). A generator's stage
deletes an example only after its tape replays that example's input and
fails on a planted version of the bug the example guards.
- G1 deletes layout-*, records-*, complete-split, enum-stepping,
  void-field, mixed-widths, literal-match, data/records.
- G3 deletes linarray-push-pop, reserve, read/write-past-size,
  vec-pop-then-push and the six bounds-*.
- G4 deletes guards-messages-*, crash-location, crash-mod-zero,
  buffer-range, double-cast-nan.
- G2 deletes the merged leet programs.
- G5 deletes the double-* and closed-double-*, and the examples in
  cast-from-string beyond its named invalid seeds.
- G6 deletes nat-large and integer-bits.
- G9 absorbs the memo and stream fixtures' shapes.
- Growth schemes reduce bounded-* and polymorphism-growth-* to seeds.
- The registry pool absorbs the per-entry reject fixtures beyond one
  smoke test per rule.

**Stage 7: both targets.**
- Run the whole suite on x86_64 Linux (musl, static PIE). The wave has
  never run there (gaps AG-19).
- Accept per host.
- Stage 2 = stage 3 enters `make test` once proposal 0003 lands (GAPS-23).
- **Done when:** `make check`, `make test`, `make test-idr`,
  `make test-mlir-tools` and `make test-unit` pass on arm64 macOS and
  x86_64 Linux, §5 is empty, and `make fuzz` reports its Good–Turing
  residual.

## 8. Decisions taken, and what only a measurement can decide

Following the owner's standing instruction, every choice the lanes left
open is decided here with its reason, and nothing is handed back as a
question. Where only data can decide, the rule and threshold are stated
instead.

**Decided** (beyond §3.7):
- **No test option in `idris-mlir`.** Contracts, debug counters and action
  skips run through `idris-mlir-opt`, replaying the emitted module, and
  the lowered module is linked by idris-mlir's lowered path.
  - Reason: 0002 §4.1 and spec/no-behaviour-options keep `idris-mlir` free
    of them, and the replay route needs nothing new from the driver.
  - This decides SEARCH-10 (a), which asked for `--idr-contracts` in
    `idris-mlir`.
- **The harness stops using `--mlir-print-ir-tree-dir`.** No upstream
  patch and no symbol-length rule is needed for the tests. A symbol's
  length is the compiler's business, and once nothing of ours creates a
  directory from it, a long name cannot change an outcome.
- **A reference evaluator over the generator's own AST is allowed as an
  oracle.** AGENTS forbids Chez and the stock evaluator, not a model we
  write. The TBS preamble names "a specification turned into a checker"
  and "a second implementation we own".
- **The runner must build under idris-mlir** (RF "the subset we
  compile"). It still runs on Chez, which is all AGENTS' exception says.
  So `Test.Golden` and contrib go.
- **`instance` stays optional, as IdrOps.td declares it.** If a later
  change makes every function name its instance, the ODS property becomes
  non-optional in that change, and the verifier states it. No grep does.
- **The knot site follows Passes.td's three placements.** The fixture's
  line 18 stands, and §5 item 29 is a compiler bug, unless the same
  commit changes the Passes.td text.
- **Allow `memcmp` in the runtime's target allowlists.** It is ISO C,
  present in libSystem and musl. Its reviewed entry is the acceptance the
  test asked for.
- **spec/file-size stays shrink-only.** The seven units are split, not
  allowlisted.
- **A bench program has one home:** `bench/<name>/` with its
  `mlir.expect`, run by `bench/smoke@<name>` through the one program
  runner.
- **Failing tests are not marked expected-to-fail.** A failing test whose
  expectation is right is a §5 entry. The verdict sum has no `KnownBug`
  case, so a bug cannot hide in a flag.

**Decided by a measurement, by these rules:**
- **Timeouts** (§5 item 39). Re-time each timed-out compile on today's
  build, without dumps, with runner threads × compile threads ≤ NCPU.
  - If it ends under half the step limit, the timeout was the harness's;
    the test is rerun and its own verdict stands.
  - Otherwise it is a compiler performance bug, recorded with its
    measured time.
  - The step limit is then set at three times the slowest measured
    passing compile of its pool, and recorded beside the pool (SEARCH-27).
- **name-stability** (§5 item 31). A symbol may change its name iff its
  final body holds an op whose location, fused locations included, lies
  in the edited definition's span. Rewrite the check to read that
  provenance from the dumps:
  - if the two `Main.main.lam.*` symbols hold such an op, the move is
    legitimate and the old check was too strict;
  - if not, the content key reads something it should not, and it is a
    naming bug.
- **`unsafePerformIO`** (§5 item 30). Make the escape-hatch probe read
  `--report` and print it (MACH-9):
  - the report holds an `escape hatch` refusal: the probe's text match
    was wrong;
  - it holds none: the compiler lost the rule, and that is a bug against
    AGENTS ("User code may not").
- **Stopping `make fuzz`.** The features are (family, result type,
  construct, stage reached). A campaign stops when Good–Turing's f1/n
  falls below 10^-3, or at its time budget, and reports the residual
  (TBS 8). The turkey's caveat applies: the number measures the pair
  (generator, features), never the compiler.

No question is left that the evidence cannot decide.
