<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Lane idr-c, applied: `tests/idr/` names to world

## Scope and result

- **Scope:** `tests/idr/{names, narrow, obs, optimize, ownership, pipeline,
  raise, rc, returned, roles, specialize, stack, structure, syntax,
  tail-calls, tie-shape, vectorize, verify, world}`. I also took the two
  directories no lane owned, `in-bounds/` and `isolate/`, which held only
  litter. I added `tests/idr/reduce/`, the new home of the reducer's test.
- **Edited:** only fixtures, their `run` and `expected` files, and
  `pipeline/timing/run`. No compiler code, and no file of another lane.
- **Before:** 134 tests, 82 of 132 passing on today's build. 123 fixtures
  carried 157 `NEEDS-ACCEPTANCE` lines.
- **After:** 112 tests. `make test-idr` over the scope gives **95/112**.
  - Each of the 17 failures is a compiler bug, listed in §4 with its
    evidence.
  - No `NEEDS-ACCEPTANCE` mark is left in scope.
  - Every `expected` file matches its fixture's RUN-line count.
- **Checks run:**
  - `make test-idr` for each directory and for the whole scope, two
    threads.
  - My own sequential runner, one test at a time, while another lane's
    edit to the runner briefly broke `runner/one.sh`.
  - `make check`: 29/32. `spec/dialect-text` passes after my last edit.
    `spec/file-size` (§5 #37) and `spec/licenses` (other lanes' audit
    files, `bench/chameneos-redux/compare`) fail on things outside this
    lane.
  - Not run: `make build`, `make test` outside scope, x86_64 Linux.
- **The lit.sh rule mid-run:** another lane changed `tests/lib/lit.sh`
  while I worked. A RUN line now stops at its first failure, and a
  `%status 1`/`not` must name the failure it expects. Every test in scope
  was rerun under that lit.sh, and none fails on it.

## 1. Deleted

Every deleted fixture went with its `run`, `expected` and stale `output`.

### 1.1 Litter

59 directories held only a git-ignored `output` of an earlier deleted test:
- the 39 of the audit's list: all of `ownership/`, and `narrow/constants`,
  `obs/{budget, canonicalize, round-failure, round-trace}`,
  `pipeline/{do-block-forced, fixpoint, nested-constant,
  rdv-address-taken, rdv-unreachable}`, `raise/not-raised`,
  `rc/{array-loops, atom-reuse, loops}`, `returned/arguments`, the ten
  `specialize/*`, the seven `stack/*`, the three `vectorize/*` and
  `verify/{linear, module}`;
- all of `in-bounds/` (13) and `isolate/` (7).

### 1.2 Removed behaviour, or checks nothing

| path | why |
| --- | --- |
| obs/bitcode-section-option | checks that a removed option stays unknown, which LLVM's option parser does for every name |
| world/world-carrier | checks that a removed type stays unknown, which the parser does for every name |
| roles/pure-calls | `idr-pure-calls-*` actions exist nowhere; upstream canonicalize and cse replaced them, and optimize/pure-call holds the outcome |
| roles/optimize-statistics | `idr-canonicalize` exists nowhere; it pins statistics; its root type is refused |
| rc/statistics | pins statistic names and the step order of a human report |
| pipeline/rc-steps | `idr-rc-place` no longer exists, and the step that refused alone (no Reuses of the program) is gone, so its refusal case cannot be written; what remained was MLIR's own `--mlir-print-ir-after` |
| optimize/totality | its premise is gone: a lone constant is never a key, and scalars are lifted, so the 1,025 "requests" make no copy (checked: one `@apply`, no copy). The cap half duplicates optimize/caller-cap |

### 1.3 Duplicates, merged

| path | merged into |
| --- | --- |
| names/edit, names/reorder | names/from-keys (§2) |
| specialize/countdown-long | specialize/countdown, as a sed of the constant |
| pipeline/accumulator | specialize/countdown (`@count`) |
| pipeline/growing-function | deleted: specialize/growing is the same module shape and claim |
| pipeline/known-label | specialize/higher-order (`@pow` over the label of `@inc`) |
| raise/branches, chain, projection, through-linear | raise/known-constructor: one function per form |
| rc/twice | pipeline/stages (`TWICE`: idr-rc run twice is refused by its first step's stage) |
| stack/escapes | already stack/expect RUN 5 to 7 |
| verify/function | verify/attributes: one unknown-argument-attribute split plus its accepting split; the old names `idr.hole`, `idr.quantity`, `idr.total`, `idr.entry` deleted |
| world/world-capture | verify/closure: its capture split was already there; the accepted world-argument split was moved |
| world/world-once, world/world-twice | world/once: the accepting module is the last split of the refusals' file |
| vectorize/rows-x86-64, rows-aarch64 | vectorize/rows, run on the host's target (no `targets` file); `vectorized` reads no lane count |
| vectorize/lanes-x86-64 | deleted, never run on arm64. Its target-independent contract (an op whose 32-bit form computes something else keeps 64-bit lanes) is checked by behaviour in programs/arrays/linarray-lanes-exact, and narrowed-lanes in linarray-lanes-wide |

### 1.4 Splits and RUN lines deleted inside kept fixtures

- **verify/attributes:** the `idr.origin`, `idr.program` and `idr.stack`
  splits. They are old names of the one unknown-attribute rule.
- **verify/values:** the `-0` and `007` splits. `BigAttr` is an `APInt`,
  so two spellings of one value are one attribute.
- **verify/data:** the memo split `[@f() running, @forced(i64) forced]`.
  It is valid by today's role table, and nothing names what was wrong
  with it.
- **verify/match:** the split that matched upstream's
  RegionBranchOpInterface sentence. That is upstream's verifier, tested
  upstream.
- **rc/verify:** the split "consumes a view". It cannot be written: the
  con's own field-type check refuses the borrow first, in custom and in
  generic form.
- **rc/atom-pairs:** `@header` and `tests-nothing=@header`. The pair is an
  unboxed sum now, so `@header` takes nothing apart and the property has
  nothing to test.
- **syntax/inherent-invalid:** the two wrong-kind splits. They now meet
  the same strict-properties rule as the right-kind ones, so they were
  duplicates.
- **The serial `cmp`s:** threaded against serial in names/*,
  optimize/specialize-ends, pipeline/steps and pipeline/time-trace. They
  duplicate the determinism pool.
- **FileChecks of op text that restated a property:** rc/stack-cell
  RUN 4, stack/linear-box RUN 4 and returned/threaded's CHECKs.
- **The STATS and COUNTED checks** of returned/threaded and
  obs/debug-counter.
- **optimize/totality's `not grep -q unsupported`.** The test itself was
  deleted later.

## 2. Rewritten

Grouped by the fault fixed.

### 2.1 Dummy roots made real

The code under test was dead under a root that called nothing.
- narrow/descending, narrow/versioned: the root reads a byte, calls both
  loops and prints their results. This exposed bug N1.
- rc/buffers: the root calls `@fill`.
- stack/linear-box, stack/expect: the root calls every function.

### 2.2 Copies made visible

idr-expect finds a copy through a `NameLoc`.
- Each function of specialize/{countdown, dictionary, growing,
  higher-order, partial-list, static-table}, optimize/specialize-ends and
  rc/second-redirect now carries `loc("<name>")`. That is the location
  Emit gives a function, and the form expect/one-clone already uses.
- The property is stated in the same `--pass-pipeline` as the passes:
  `...,idr-expect{holds=...}`. A module written to text without
  `-mlir-print-debuginfo` loses its locations, which is why higher-order
  failed although it had `loc("map")`.
- specialize/growing and partial-list state `specialized-once`. Their old
  `one-clone` held only vacuously. Since 7232d3e9 the entry copy calls the
  original, which is what the commit message says for partial-list.

### 2.3 The claim checked, not the comment

- **names/from-keys** (replaces edit and reorder):
  - the fixture specializes, on closures, as the old ones no longer did;
  - symbols are read off the generic form's `sym_name`, not by a sed of
    the custom form;
  - RUN 8 checks that copies exist;
  - the symbol set is the same after reversing the functions, and after
    editing `@scale`'s body for every symbol not made from `@scale`.
- **obs/debug-counter:** with the counter at 0 and symbol-dce, no
  function exists that the input lacks. Without the counter, the copy of
  `@pow` exists.
- **raise/closed-world:** "no copy is made" is now checked as the same
  symbol-set comparison.
- **tie-shape/dims-fold:** checks the folds it claims:
  `returns-argument` and `returns=@static:4` after canonicalize, and a
  failing `@untied` counterpart.
- **rc/counted-linalg:** `not idris-mlir-opt` became `-verify-diagnostics`
  on the linalg rule.
- **pipeline/do-block:** `no-closures` is implied by the stage, so it
  checked nothing. The claim is now `not-called=@bind,not-called=@seq`
  ("unfolds into the root"), which fails: bug N4.
- **pipeline/one-pipeline** (replaces steps): idris-mlir's object equals,
  byte for byte, the object idris-mlir compiles from
  `idris-mlir-opt --idr-target --idr-pipeline`'s output. This uses no tree
  printer and no file names.
- **pipeline/timing/run:**
  - the tree printer is gone;
  - the module passes at the top are compared with the top rows of
    `idris-mlir-opt --idr-target --idr-pipeline --mlir-timing` (a second
    implementation);
  - the hand list of the optimizer's inner passes is replaced by the
    names the report itself nests.
- **tail-calls/mutual:** the tree printer and the "idr-tail-calls is the
  last dump" pin are gone. The run on a 1 MiB stack stays, and
  `constant-stack` is now stated on `--idr-pipeline`'s module.
- **pipeline/time-trace:** checks traced equals untraced and that a trace
  is written. The zone names are gone.
- **reduce/regions** (from verify/reduce-regions):
  - the reduction ends, its module verifies, and it is still interesting
    (both matches, by grep);
  - `--implicit-check-not=arith.`, the LOG check of MLIR's text and the
    module-text FileCheck are gone.

### 2.4 Negatives that named no failure

- tail-calls/positions, decided-loops and long-continuation, and
  rc/stack-cell: each `%status 1` now names the property and function it
  expects to fail.
- positions' seven negatives became one run with seven `KEEPS-DAG` lines.
- stack/linear-box: the before-idr-rc negative names `idr.con` in
  `@linear`.

### 2.5 Wording made the rule, not the words

- **ODS and upstream messages** are matched as `operand #0 must be`, or by
  the attribute named:
  - verify/nat, verify/ops and verify/closure (the world capture);
  - tie-shape/verify, two splits;
  - syntax/inherent-invalid.
- **Our own diagnostics** keep their rule clause, and the explanatory
  tail is cut:
  - verify/program: the root type, "contains itself in place", the
    grades, the layouts;
  - verify/owned-stage: "builds a box with fields as a value in the owned
    stage".
- **New wording, kept to the rule's key:**
  - verify/data: "has two constructors @A", "has another body already";
  - verify/values: "has no constructor @T", "expects the last cell of @A
    to hold its 2 fields";
  - verify/cells: "has a hole at field 0 of type 'i64'";
  - rc/verify: the recycle size;
  - tie-shape/verify: "dynamic dimensions".
- **idr-expect's diagnostics** keep their key, `expected <property>: ...
  @f`, without the printed type: rc/{atom-pairs, exclusive, share-trap}.
- **Driver checks** name the option or op, never LLVM's or MLIR's
  sentence: obs/foreign-pass-name, lowered-mixed, lowered-untargeted and
  print-ir-threads.
- **pipeline/runtime-names:** the rule and the named symbol
  (`unsupported (program):.* write[ ,]`).
- **obs/stats:** only "a report with `--stats`, none without". The
  statistic names are gone.

### 2.6 Stale syntax and fixtures fixed

- **Syntax:**
  - syntax/closures: named arguments;
  - syntax/grades: declarations, so no stage's grade rule is read;
  - structure/columns: the parenthesized option is quoted.
- **Stage and form:**
  - obs/report-refused: stage(higher), since the knot rule is the pass
    idr-knots now;
  - verify/program: a borrowed constant, generic `memref.alloc` and
    `memref.global` for the alignment splits, and the bodiless data type
    as a plain argument type;
  - verify/cells: the custom form prints `take`;
  - rc/verify: `idr.str.pack` of a borrow, borrowed constants.
- **Harness and paths:**
  - optimize/once: the action log went to stdout, so it is now written
    with `--log-actions-to=%t.log`;
  - pipeline/link: the object is content-named (`%t.*.o`).
- **Expectations that were wrong:**
  - verify/roundtrip: `!Fields` was never used, so its alias never
    printed;
  - returned/threaded: `@either` was called only after the
    never-returning `@spin`, so dropping its result was correct. The call
    is now live, and the checks are `signature=` per function;
  - rc/second-redirect: in the old fixture the second call was rightly
    shared. Its first list now has one use, and `@bump` takes its list
    apart, so the claim it states can hold.
- **optimize/case-of-case-calls:** RUN 3 no longer asks
  `@lowered_past_crash` to keep its allocation under plain canonicalize.
  A match whose regions only compute orders against no call, so moving it
  down past one is right at any effects. This reclassifies SUMMARY §5 #25
  as a test error.
- **obs/print-with-object:** its `expected` listed 6 RUN lines for 7.

## 3. Kept as they were

Their marks were removed, since each passes:
- names/reserved;
- obs/{lowered-input, report-accepted, report-link-failure};
- optimize/{caller-cap, never-returns-twice, pure-call};
- pipeline/{endless-loop, inputs, layout, reported-error-fails};
- raise/{apply, io-loop, sunk-call, sunk-call-paths};
- rc/{arrays, consumed, counts, dies-apart, kept-fields, live,
  nested-reuse, returned, take-at-death};
- roles/contify, specialize/binding-times, stack/hot-loop;
- structure/{tabulate, transpose};
- syntax/{constants, facts-roundtrip, grades-invalid, nested-constant,
  refusal};
- verify/{con-owned-field, cycle, effects, generic, only-atoms, widths}.

21 verifier, syntax and function-pass fixtures keep a dummy root, where
liveness changes nothing:
- reduce/regions;
- structure/{ordered, dynamic-cells, tabulate, transpose};
- syntax/{facts-roundtrip, grades-invalid, constants, closures,
  inherent-invalid};
- tie-shape/{verify, dims-fold};
- verify/{widths, generic, match, flow, data, closure, ops, nat, values}.

## 4. Tests left failing, each on a compiler bug

| test | failure | bug |
| --- | --- | --- |
| narrow/select-lanes, returned/threaded, tail-calls/decided-loops, tail-calls/positions, vectorize/rows (RUN 4) | exit 139 in `IdrDialect::foldLeakCount` from `ContractInstrumentation::runAfterPass`; every module of upstream dialects alone | §5 #1, `Expect/Folds.cpp:21` |
| narrow/descending, narrow/versioned | `word-loop`: "@parity computes on bigs in each of its loops"; idr-narrow leaves the module byte-identical | **N1 (new):** idr-narrow no longer versions a descending natural after idr-rc grades it. The predecessor is `idr.big.pred borrow` of an `idr.borrow` of the loop argument. This should also break idr-a's actions/narrow `not diff` |
| rc/regions-counted | assertion `cast<TypedValue<MemRefType>>` in `memref::LoadOp::getMemref` from `idr::ownership::readFrom`, under idr-rc-grades' Placement | **N2 (new):** reproduced also by a `memref.load` of the buffer `@fill` returns (rc/buffers' first rewrite) |
| rc/second-redirect | "no copy of @bump takes its references exclusive". `@keep.excl.*` gives an `!idr.excl` result, which is `idr.share`d before `@bump` | **N3 (new, plausible):** idr-rc-exclusive does not follow an exclusive copy's result into the call it feeds |
| pipeline/do-block | `@bind is still called ... in @Main.main`: the 16-statement block keeps a recursive `@bind` dispatch | **N4 (plausible regression of 7232d3e9):** a do block no longer unfolds into the root |
| raise/builds-actions | the raised copy `@actions.raise.*.spec.*` calls the original `@actions` | **N4:** a copy's recursion stays a call of the original |
| raise/shared-key | `@f`, `@g`, `@pair` still called in `@Main.main`: no call is raised | §5 #26 (uncertain) |
| structure/dynamic-cells | assertion in `TypeRange::operator[]` (`AffineDelinearizeIndexOp` verify) | §5 #17 |
| structure/never-returns, structure/ordered | "no structured op in @gen / @sumi": both lowered to `scf.for` | §5 #17 (plausible) |
| vectorize/rows | behind RUN 4: "no loop computes on vectors in @squares/@rows" after the schedule, on aarch64 and on the former x86-64 copy's module alike | **N5 (new, plausible):** the scf.for-of-tensor.insert loops are not vectorized. The fixture's form may have relied on a raising that changed |
| verify/flow | "closure or suspension" not produced for `arith.select` of suspensions | §5 #24 |
| verify/roundtrip | `con !Shape @Circle (` where IdrOps.td documents `@Circle(` | §5 #18 |

Two more defects were seen in passing; no test in scope fails on them:
- `idr.cell.init` prints `)  -> ... ` with a doubled and a trailing
  space;
- `NameLoc`s are lost through a text round trip without
  `-mlir-print-debuginfo`. This is MLIR's behaviour, but every two-step
  copy property depended on it silently.

## 5. For other lanes and the orchestrator

These are outside my scope, so I did not edit them:
- `PINS.md:465` cites tests/idr/vectorize/lanes-x86-64 as the site of
  `upstream/09-int-range-narrowing-exactness`. Repoint it to
  tests/programs/arrays/linarray-lanes-exact.
- `upstream/22-remove-dead-values-poison-operand/README.md:44` names
  tests/idr/vectorize/rows-aarch64, which is now tests/idr/vectorize/rows.
  This is historical text.
- `tests/idr/func/linear-twice.mlir:5` (idr-b) names
  world/world-twice.mlir, which is now world/once.mlir.
- roles/contify is the same skip-all-actions form as idr-a's `actions/`.
  It belongs there, or with them in the generated action-skip property.
- stack/hot-loop is an Idris program and belongs in `programs/stack/`.
- The driver tests in `obs/` and `pipeline/` are idris-mlir's command
  line, which SUMMARY §4.1 puts in a `driver/` pool.
- `tests/ACCEPTANCE.md` (machinery lane) still lists the fixtures deleted
  here.

## 6. What a future generator or harness must cover

- **Translation validation** (SUMMARY §6 step 6). These fixtures read one
  byte and print, so before and after each pass must agree on all 256
  inputs:
  - names/from-keys, specialize/*, raise/*, optimize/*, narrow/*;
  - pipeline/do-block, obs/debug-counter.

  None checks meaning today.
- **A copy count and `merged=`:**
  - raise/shared-key's "equal keys share one copy";
  - partial-list's "one copy";
  - totality's old "many keys never refuse" (needs keys that are not
    lifted).
- **`--idr-pipeline=to:<step>` / `from:<stage>`** for:
  - vectorize/rows, which still uses the tree printer per function, the
    only fixture in scope that does;
  - tail-calls/mutual's "the module before idr-tail-calls grows the
    stack";
  - pipeline/rc-steps' per-step checks.
- **A rule key on every verifier diagnostic.** verify/, syntax/,
  tie-shape/verify and rc/verify still match prose fragments of our own
  messages.
- **The metamorphic name generator.** names/from-keys is one fixture with
  two perturbations (reorder, edit). The generator adds a random fixture,
  an unrelated added function, and a read of symbols that needs no text.
- **The action-skip property over every tag and fixture:** roles/contify
  and obs/debug-counter.
- **The registered-op enumeration for inherent attributes:**
  syntax/inherent-invalid keeps one split per op.
- **A registered-pass check:** obs/foreign-pass-name keeps one example.
