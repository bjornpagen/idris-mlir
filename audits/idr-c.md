<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Audit lane idr-c: `tests/idr/` names to world

## 1. Header

- **Lane:** idr-c.
- **Scope:** every directory of `tests/idr/` after `lower` in name order:
  `names`, `narrow`, `obs`, `optimize`, `ownership`, `pipeline`, `raise`, `rc`,
  `returned`, `roles`, `specialize`, `stack`, `structure`, `syntax`,
  `tail-calls`, `tie-shape`, `vectorize`, `verify`, `world`. A test is a
  `name.mlir` fixture with its `name/run` (`lit ../name.mlir`) and
  `name/expected` (`RUN i: ok` once per RUN line), run by `tests/lib/lit.sh`;
  one test (`stack/hot-loop`) is an end-to-end program, and one
  (`pipeline/timing`) a hand-written run script.
- **Read:** `.claude/skills/testing-by-search/SKILL.md` (cited TBS),
  `.claude/skills/representation-first/SKILL.md` (cited RF; RF SPOV1-3, RF
  "How it binds", RF MLIR = "Map onto MLIR's grain"), AGENTS.md,
  `tests/README.md`, `tests/testutils.sh`, `tests/lib/lit.sh`,
  `tests/ACCEPTANCE.md`; all 132 fixtures in scope, every `run`, `expected`
  and `output` file; the idr-expect property table
  (`foreign/idr/lib/Transforms/Expect/Lookup.cpp`) and the copy lookup it
  rests on (`Expect/Named.cpp`), `Expect/Folds.cpp`, the specializer's
  naming (`include/idr/IR/Symbols.h`), and `make test-idr`'s log of 14:32
  (`test-idr.log`; the `output` files in scope are all from that run, 14:31 to
  14:32, but `verify/attributes`, re-run at 15:23).
- **Not run:** nothing was built or run (read-only lane). Commits after the
  14:31 run touch the code several failures point at: 25f263da (14:36,
  `#idr.instance` brackets, the `complex` dialect's lowering model),
  4c87dcc5, 9696ecc5, a7bf77b4, 3d279eb9 (idr-rc grading and stack cells),
  dcafd452 (refusals, `verify/attributes.mlir`, `verify/roundtrip.mlir`). A
  status below is the 14:31 run's; where a later commit names the cause it is
  said.

**Counts.** 134 tests in scope: 132 lit fixtures plus `stack/hot-loop` and
`pipeline/timing`. At the 14:31 run: **54 pass, 78 fail, 2 never ran on this
host** (`vectorize/lanes-x86-64`, `vectorize/rows-x86-64`, `targets` x86-64).
Beside them, **39 directories hold only a stale, git-ignored `output`** of a
deleted test (`ownership/` has nothing else; IDC-17). 123 of the 132 fixtures
carry 157 `NEEDS-ACCEPTANCE` lines.

**Verdicts (134):** keep 69, rewrite 39, rewrite-as-property 7,
merge 14, delete 5 (tallied from the table in section 2). Most rewrites are
small (a stale split, a NameLoc, a FileCheck line dropped); the larger change
is section 5's: a semantic oracle and four generated properties in place of
about twenty examples.

The failures fall into few causes (section 4): a crash of the contract
instrumentation itself on any module without the idr dialect (4 tests), the
driver's `complex` abort before 25f263da (16 tests), idr-rc producing
ill-graded or dangling IR before the later idr-rc commits (25 tests), the
fixtures' functions carrying no `NameLoc` so idr-expect cannot see a copy
(5 specialize tests failing, several more passing vacuously), stale
fixture syntax, stale expected wording or text scraping after the wave
(about 19), and a handful of compiler bugs.

## 2. Verdict table

Status is the 14:31 run's. "complex abort" is
`LLVM ERROR: checking for an interface (mlir::ConvertToLLVMPatternInterface) that was promised by dialect 'complex'`,
which 25f263da (14:36) addresses. "idr-rc ill-graded" is idr-rc's output
failing the graded verifier (`'idr.match' op operand #0 must be a constructor
value at any quantity, not owned`, or a return whose grade differs from the
signature's), which the idr-rc commits after 14:31 address. "unlinked" is
`error: operation's operand is unlinked` after idr-rc's stack step, which
a7bf77b4 addresses. "contracts crash" is the segfault in
`idr::expect::foldsBalanced` under `--idr-contracts` (IDC-B1).

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| names/edit | editing @scale's body changes no other symbol the optimizer keeps or makes | merge-into:names/reorder | one metamorphic property, two perturbations; scrapes `idr.func` text with sed, so a printed-form change (`effects<...>` before the symbol) emptied both name lists and RUN 10's `diff` of two empty files passed (TBS 1.1, TBS 9.2 step 5) | fail: name scrape empty, no `.spec.` symbol |
| names/reorder | reversing function order gives the same set of symbols | rewrite-as-property | right property (names are a function of the key), wrong perception: sed over printed text and `grep '[.]spec[.]'` pin syntax and the naming scheme; generate perturbations (reorder, edit one body, rename one unrelated function) and compare symbol sets read from the module, not its text (TBS 1.1, TBS 4.4, RF "Every string that names a thing") | fail: no `.spec.` symbol |
| names/reserved | a program may name functions `__idr_main`/`__idr_release_cafs`; reserved names do not collide | keep | contract stated with idr-expect (`linker-names`, `call-order`) (TBS 1.1) | pass |
| narrow/descending | a natural that only descends is versioned to a word loop; a growing one is not | keep | property `word-loop` with a failing counterpart (TBS 1.1, 9.2 step 5) | fail: idr-rc ill-graded (`match_lit` on `!idr.own<!idr.nat>`) |
| narrow/select-lanes | idr-narrow-lanes leaves a select-only loop alone | keep | identity by `diff` plus `narrowed-lanes` (TBS 1.1) | fail: contracts crash (exit 139) |
| narrow/versioned | 70-deep descent and a carried word are still versioned | keep | generated chain plus property (TBS 8, small scope moved into the box) | fail: idr-rc ill-graded |
| obs/bitcode-section-option | `--runtime-bitcode-section` is no option | delete | checks a removed option stays unknown, which LLVM's option parser guarantees for every name (TBS 1.1; stale-legacy) | pass |
| obs/debug-counter | the specialize action skipped at counter 0 leaves `@pow` called; idris-mlir has no debug counter | rewrite | the claimed outcome (`@pow` still called) is never checked, only the counter's report line, whose format `{N,0,0}` is MLIR's (TBS 1.1, 9.2 step 5) | pass |
| obs/foreign-pass-name | an option naming an unregistered pass is refused | rewrite-as-property | one example of "the driver registers exactly the passes it runs": compare the registered pass list with the pipeline's dumps (TBS 1.1 `DefaultConfigsArePrime`) | pass |
| obs/lowered-input | an LLVM-dialect module goes straight to LLVM and runs | keep | exit status of the real program is the contract (TBS 7) | pass |
| obs/lowered-mixed | a half-lowered or func.func module is refused, verdict internal | keep | exit status and report verdict (TBS 1.1) | pass |
| obs/lowered-untargeted | an LLVM module without `#llvm.target` is refused at the module | keep | exit status, verdict, no object (TBS 1.1) | pass |
| obs/print-ir-threads | module-scope printing needs threading off: usage error, no outputs | rewrite | keep exit 2 and no outputs; drop the FileCheck of MLIR's own sentence, which is upstream's text (TBS 1.1) | fail: complex abort (RUN 5) |
| obs/print-with-object | a `--print` option with `-c` is a usage error | keep | contract is exit status; its `expected` lists 6 RUN lines for a fixture of 7 (IDC-12) | fail: expected file stale (output all ok) |
| obs/report-accepted | the report's verdict and statistics, identical at 1, 3, 5, 13 threads | keep | determinism of the report is a real contract checked against itself (TBS 11) | fail: complex abort |
| obs/report-link-failure | an unreadable runtime is an internal error with a report line | keep | exit, stderr class, report (TBS 1.1) | fail: complex abort |
| obs/report-refused | a refusal exits 3 and the report names rule and line | keep | (TBS 1.1) | fail: complex abort |
| obs/stats | `--stats` prints statistics of contify, optimize, defunctionalize; none without | rewrite | pins statistic names and descriptions (`contified -`, `boxed -`), a human report; keep only "a report with, none without" (TBS 1.1) | fail: complex abort |
| optimize/caller-cap | the per-caller inline cap bounds every function at 10,000 ops and never refuses | keep | property with its own failing counterpart (`-verify-diagnostics` on the unoptimized chain) (TBS 9.2 step 5); `largest-function` belongs in `--idr-contracts` too (IDC-14) | pass |
| optimize/case-of-case-calls | case-of-case moves across calls only by the call's own effects | keep | properties plus a negative run with plain canonicalize (TBS 1.1) | fail: RUN 3 `expected error "allocates in @lowered_past_crash" was not produced` (IDC-B7) |
| optimize/never-returns-twice | inlining two never-returning callees leaves one block | keep | property `never-returns`, verifier after every pass (TBS 7) | pass |
| optimize/once | each optimizer node begins once | rewrite-as-property | greps MLIR's action-log text and seds symbols out of it; state "every function is a node once" as an expect property or a statistic equal to the function count (TBS 1.1, RF "Every string that names a thing") | fail: no `begins ... idr-optimize-node` line in the log |
| optimize/pure-call | unread pure calls go, equal ones merge, effectful ones stay | keep | properties with failing counterparts (TBS 1.1) | fail: RUN 6 idr-rc grades a `!idr.lin<!idr.str>` result plain (IDC-B3) |
| optimize/specialize-ends | lifted keys end every growing recursion | rewrite | `specialized-once` is vacuous on fixtures without `NameLoc` (IDC-2); `cmp` threaded vs serial duplicates the determinism pool (IDC-9) | pass (partly vacuous) |
| optimize/totality | 1,025 requests and a 24,000-op chain: no refusal, cap holds | keep | stress input plus property; `not grep -q unsupported` adds nothing to the exit status (TBS 1.1) | pass |
| pipeline/accumulator | an accumulator that changes is no key: no copy of @count | merge-into:specialize/countdown | same rule as countdown's count (a varying position keys nothing); one fixture with both (TBS 1.1) | pass |
| pipeline/do-block | a 16-statement do block unfolds, no closure left | keep | `no-closures` property (TBS 1.1) | pass |
| pipeline/endless-loop | a non-total effect-free loop is not deleted | keep | the program still runs after 2 s (TBS 7) | fail: complex abort |
| pipeline/growing-function | a growing closure is no key: one function for @iter | merge-into:specialize/growing | same claim, same shape (`iter` with a closure that grows) (TBS 1.1) | pass |
| pipeline/inputs | module vs Idris inputs; colliding outputs are a usage error | keep | exit statuses and messages of the driver's own (TBS 1.1) | fail: complex abort |
| pipeline/known-label | @pow specialized on a known label, @inc inlined | rewrite | `one-clone=@pow` without symbol-dce and without a `NameLoc` holds only if no copy was made, and `not-called=@inc` holds if @inc is inlined into the unspecialized dispatch: the properties cannot tell the claim from its negation (TBS 9.2 step 5, IDC-2) | pass (vacuous) |
| pipeline/layout | every function symbol starts on a 64-byte line | keep | read off the object (TBS 1.1) | fail: complex abort |
| pipeline/link | without `-c`, idris-mlir links and the program exits 42 | keep | (TBS 7) | fail: complex abort |
| pipeline/rc-steps | idr-rc's steps are named passes; place alone refuses | rewrite | pins MLIR's dump header `IR Dump After IdrRcPlace (idr-rc-place)`; state the step's output by `idr-expect` in a `--pass-pipeline` after idr-rc-place (TBS 1.1) | fail: unlinked |
| pipeline/reported-error-fails | an action log that cannot be opened stops with a usage error | keep | (TBS 1.1) | fail: complex abort (RUN 4) |
| pipeline/runtime-names | a program symbol the runtime defines or calls is refused | keep | exit 3 and the named symbol (TBS 1.1) | fail: complex abort |
| pipeline/stages | each pass sets its stage; a pass at the wrong stage refuses | keep | `stage=` property per pass (TBS 1.1) | pass |
| pipeline/steps | the driver dumps every module pass; idr-pipeline ends where the driver ends | rewrite | keep the equivalence of the driver's last dump with `--idr-pipeline` (a second implementation, TBS 7); drop the tree printer's file-name regex and `0_idr-target.mlir` (upstream's naming) and the serial `cmp` (IDC-9) | fail: complex abort |
| pipeline/time-trace | a time trace changes no byte of the module | rewrite | keep traced == untraced (a metamorphic property, TBS 9.1); drop the zone names (`Total CanonicalizerPass`) and the serial `cmp` (TBS 1.1, IDC-9) | pass |
| pipeline/timing | `--mlir-timing` rows: parse first, one row per pass, groups nest | rewrite | right properties, but the "inside" list (`IdrEffects\|IdrRedirect\|IdrIdentity\|Canonicalizer\|CSE\|...`) is a second copy of the optimizer's inner pipeline; generate it (RF "One fact, one place") | fail: complex abort |
| raise/apply | a call whose result is applied at once is raised | keep | `not-called` of the callee and its closures' functions (TBS 1.1) | pass |
| raise/branches | a dispatch in each region folds once @greet is inlined | merge-into:raise/projection | same mechanism (inline, then a dispatch meets its constructor); one fixture with one function per form (TBS 1.1) | pass |
| raise/builds-actions | a call that only builds actions is raised across output | keep | (TBS 1.1) | pass |
| raise/chain | a chain of applies folds | merge-into:raise/projection | same mechanism as branches/projection/through-linear | pass |
| raise/closed-world | the literal-started IO loop is no unrolled copy chain; constant stack | rewrite | claims "no copy is made" but checks only `constant-stack`; add a copy count, with a `NameLoc` (TBS 9.2 step 5, IDC-2) | pass |
| raise/io-loop | the IO loop becomes a self tail call that allocates nothing | keep | `constant-stack`, `no-heap-allocation` (TBS 1.1) | pass |
| raise/projection | a projected and applied result folds | keep | becomes the one known-constructor fixture of the four (TBS 1.1) | pass |
| raise/shared-key | equal raise keys share one copy; constants share too | rewrite | claims sharing, checks only `not-called`; state "one copy per key" (TBS 9.2 step 5) | fail: `@f is still called, as @f, in @Main.main` (IDC-B10) |
| raise/sunk-call | a pure call sinks into the one region that applies it; a partial one stays | keep | positive and negative property (TBS 1.1) | pass |
| raise/sunk-call-paths | crash/diverge calls sink only into every region; linear arguments released | keep | (TBS 1.1) | fail: RUN 4 idr-rc: `'idr.lin.use' op failed to verify` (IDC-B3) |
| raise/through-linear | a linear enter/use pair folds away | merge-into:raise/projection | same mechanism (TBS 1.1) | pass |
| rc/arrays | idr-rc and lowering accept arrays a world orders | keep | the verifier after every pass is the oracle (TBS 7) | fail: idr-rc ill-graded |
| rc/atom-pairs | pairs of static atoms keep a take test-free; a static cell does not | keep | positive and failing property (TBS 1.1) | fail: idr-rc ill-graded |
| rc/buffers | an alloc'd buffer filled with a given cell counts nothing | keep | (TBS 1.1) | fail: `'idr.own.give' op operand #0 must be a value that holds a reference` |
| rc/consumed | a box consumed by a call is not reused after it | keep | `resets-unshared`, `reuses-every-cell` (TBS 1.1) | fail: idr-rc ill-graded |
| rc/counted-linalg | a linalg payload over strings is no program | rewrite | `not idris-mlir-opt %s` passes on any failure, a parse error included; state the refusal by `-verify-diagnostics` (TBS 9.2 step 5; cannot-fail) | pass (vacuous) |
| rc/counts | map reuses in place; readers borrow | keep | (TBS 1.1) | fail: idr-rc ill-graded |
| rc/dies-apart | a dying box is taken apart once (drop specialization) | keep | (TBS 1.1) | fail: idr-rc ill-graded |
| rc/exclusive | exclusive lists take with no test; shared ones test | keep | positive and failing property (TBS 1.1) | fail: idr-rc ill-graded |
| rc/kept-fields | fields kept across a reuse count nothing | keep | (TBS 1.1) | fail: unlinked |
| rc/live | every cell is freed by program end | keep | live cells 0 after a real run, a universal oracle (TBS 7) | fail: complex abort |
| rc/nested-reuse | a box read by fields dies and is reused | keep | (TBS 1.1) | fail: unlinked |
| rc/regions-counted | region ops and loops are counted; the owned verifier accepts | keep | verifier as oracle plus `constant-stack` (TBS 7) | fail: idr-rc ill-graded |
| rc/returned | a returned parameter is owned, counts nothing | keep | (TBS 1.1) | fail: idr-rc ill-graded |
| rc/second-redirect | an exclusive copy's result redirects the next call | rewrite | `exclusive-copy` finds a copy only by `NameLoc`, which the fixture lacks (IDC-2) | fail: idr-rc ill-graded |
| rc/share-trap | exclusivity does not survive `idr.share` | keep | failing property, a negative of `tests-nothing` (TBS 1.1) | fail: idr-rc ill-graded |
| rc/stack-cell | a frame-dying cell goes on the stack, before reuse decides | rewrite | keep the two properties; delete RUN 4's FileCheck of `idr.cell.stack`/`idr.cell.init`/`CHECK-NOT: idr.cell.recycle`, which restates them in op text (TBS 1.1, RF "One fact, one place") | fail: unlinked |
| rc/statistics | each idr-rc step reports its statistics in pipeline order | delete | pins statistic names and pass order of a human report; the facts it guards (a reuse, a take) are properties checked elsewhere (TBS 1.1) | fail: idr-rc ill-graded |
| rc/take-at-death | a box used in its region is taken where it dies | keep | (TBS 1.1) | fail: idr-rc ill-graded |
| rc/twice | idr-rc refuses a program already owned | merge-into:pipeline/stages | the one StagedPass rule, stated there for idr-demand (TBS 1.1) | pass |
| rc/verify | the owned stage's rule: every reference consumed once | rewrite | right rule; four splits are stale after the wave (`!idr.q<many, borrow, ...>` uses, `expected SSA operand`, the recycle size text) (TBS 1.1) | fail: unexpected errors at lines 93, 177, 262, 282 |
| returned/threaded | returned arguments are dropped through scf.if/while/execute_region and mutual recursion | rewrite-as-property | FileCheck of call op text and `(S) 5 dropped` restate one fact; state `signature=@branch:(i64,i1)->()` per function (TBS 1.1, RF "One fact, one place") | fail: contracts crash (exit 139) |
| roles/contify | with every contify action skipped the module is unchanged | rewrite-as-property | the property ("every optional transform is an action; all skipped is identity") belongs to every action-gated pass on every fixture, not one example (TBS 1.1 last paragraph) | pass |
| roles/optimize-statistics | idr-optimize reports `idr-canonicalize.not-converged` and cse counts | delete | `idr-canonicalize` no longer exists (no source names it); stale-legacy, and it pins statistics (TBS 1.1); its fixture's root type is refused too | fail: root type refused; stale names |
| roles/pure-calls | skipping every idr-pure-calls action keeps @unread | delete | `idr-pure-calls-erase`/`-merge` exist nowhere in the source: the wave replaced the step with upstream canonicalize and CSE (stale-legacy); the outcome is optimize/pure-call's | fail: `@Main.main calls no @unread` |
| specialize/binding-times | each parameter's binding time, as remarks | keep | the analysis' result is its contract (TBS 1.1) | pass |
| specialize/countdown | a loop count keys nothing: one copy | rewrite | needs a `NameLoc` per function (IDC-2); the count should be generated (5, 10^6, random) rather than two files (TBS 8) | fail: `expected one-clone: no call of @loop or of a copy of it` |
| specialize/countdown-long | same at 1,000,000 | merge-into:specialize/countdown | the same fixture with another constant (TBS 1.1, TBS 8) | fail: as countdown |
| specialize/dictionary | a static dictionary record specializes @sumTo, @plus inlined | rewrite | `NameLoc` (IDC-2) | fail: as countdown |
| specialize/growing | a growing closure keys once: one copy | rewrite | `NameLoc` (IDC-2) | pass (vacuous: see IDC-2) |
| specialize/higher-order | @map specialized on a known closure, @add inlined | rewrite | `NameLoc` (IDC-2) | fail: as countdown |
| specialize/partial-list | only the entry copy for [1, 2, n]; tail passed as value | rewrite | `NameLoc` (IDC-2); as written, `one-clone=@sum` counts the copy's calls of @sum and cannot see the copy | pass (meaning unclear) |
| specialize/static-table | a static table keys once, the index never | rewrite | `NameLoc` (IDC-2) | fail: as countdown |
| stack/escapes | a read-only box's cell is on the stack; a returned one on the heap | merge-into:stack/expect | stack/expect RUN 5-7 state the same two facts on the same shape (TBS 1.1) | fail: unlinked |
| stack/expect | a stack cell is no heap allocation; idr-rc's steps place cells | keep | property and its failing counterpart (TBS 9.2 step 5) | fail: unlinked |
| stack/hot-loop | a hot loop's boxes go on the stack; program output, no live cell | merge-into:tests/programs/stack | an Idris program test in the dialect suite; it belongs with the program pools (README layout) | fail: `#idr.instance` bytecode parse (25f263da) |
| stack/linear-box | a linear box's cell goes on the stack after idr-rc | rewrite | keep the property pair; delete the FileCheck of `idr.cell.stack`/`CHECK-NOT: idr.cell.new`, which restates it (TBS 1.1) | fail: unlinked |
| structure/columns | idr-columns turns a tensor of records into one tensor per field | rewrite | the RUN line's unquoted `(index)->(...)` is a shell syntax error under lit.sh's `eval`: the test can never pass as written (IDC-13) | fail: `eval: syntax error near unexpected token '('` |
| structure/dynamic-cells | rows of dynamic size: first row at the zero index, one loop over the rest | keep | property; reveals a crash (IDC-B5) | fail: assertion in `AffineDelinearizeIndexOp::verifyInvariantsImpl` |
| structure/never-returns | a tabulation whose region never returns lowers with its crash | keep | `structured-loops`, `crash-sites` (TBS 1.1) | fail: `no structured op in @gen` (IDC-B6) |
| structure/ordered | an op's form follows its region's effects | keep | (TBS 1.1) | fail: `no structured op in @sumi` (IDC-B6) |
| structure/tabulate | a word tabulation is one linalg op | keep | property and its failing counterpart on the input (TBS 9.2 step 5) | pass |
| structure/transpose | identity and inverse transposes fold; others lower | keep | `returns-argument`, `structured-loops` (TBS 1.1) | pass |
| syntax/closures | a closure type prints a single result without parentheses | rewrite | printed syntax is the contract here, but the fixture writes unnamed `idr.func` arguments, which the parser no longer reads (stale) | fail: `custom op 'idr.func' expected SSA identifier` |
| syntax/constants | a list constant is a flat run; 10^4 cells round-trip text and bytecode | keep | printed syntax plus a stress round-trip (TBS 8) | pass |
| syntax/facts-roundtrip | a function's facts print and read back | keep | printed syntax is the contract (README) | pass |
| syntax/grades | long grades print as their short spellings | rewrite | stale: the `stage(owned)` program now refuses `!idr.lin<!idr.str>` at the plain grade; move the cases to a stage that admits them | fail: `binds argument #0 ... at the plain grade in a graded program` |
| syntax/grades-invalid | a written grade is checked: world and destination take none | keep | (TBS 1.1) | pass |
| syntax/inherent-invalid | an inherent fact restated in attr-dict is refused | rewrite-as-property | two of its cases fail on upstream's strict-properties wording; the rule holds of every op with an inherent attribute: enumerate them from the registered dialect instead of four examples (TBS 1.1, RF MLIR "Declare, don't write") | fail: `expected error ... array attribute was not produced` |
| syntax/nested-constant | a 100,000-deep attribute parses on the reserved stack | keep | the workaround's positive check, PINS.md mlir-recursion (AGENTS upstream rule) | pass |
| syntax/refusal | a frontend refusal round-trips text and bytecode | keep | (TBS 1.1) | fail: `'builtin.module' op has "idr.refusals", which is an array of #idr.refusal on the top-level module alone` (IDC-B9) |
| tail-calls/decided-loops | a loop its constants end keeps the call a tail call | keep | properties plus a failing counterpart (TBS 9.2 step 5) | fail: contracts crash (exit 139) |
| tail-calls/long-continuation | a 5,000-block path to the return is still a tail call | keep | generated stress plus counterpart (TBS 8) | pass |
| tail-calls/mutual | ten million mutual tail calls run in 1 MiB; constant stack | rewrite | keep the run (output and stack bound); drop RUN 7/9, which pin that idr-tail-calls is the last dump and the dump file names, while pipeline/steps says the order is the pipeline's own business (TBS 1.1) | fail: complex abort |
| tail-calls/positions | which calls are tail calls and which conventions | keep | each negative is its own failing run (TBS 9.2 step 5) | fail: contracts crash (exit 139) |
| tie-shape/dims-fold | a tied array's dimension folds to the size it was tied to | rewrite-as-property | the only RUN line checks that canonicalize converges; the folds it claims are never checked (TBS 9.2 step 5; checks-nothing) | pass (vacuous) |
| tie-shape/verify | a tie names one size per dynamic dimension, of a ranked array | rewrite | expected texts are the old messages (`one size for each dynamic dimension`; an ODS summary that changed) (IDC-6) | fail: four unexpected errors with the new wording |
| vectorize/lanes-x86-64 | idr-narrow-lanes versions vectorized loops to i32 lanes | rewrite | a per-target test (AGENTS: per-target cases are bugs) that reads the tree printer's file names; run on the host target with the property stated at the step (IDC-10) | not run (x86-64 only) |
| vectorize/rows-aarch64 | loops compute on lanes after the schedule (arm64) | rewrite | becomes the one host-target `vectorize/rows`; `vectorized` is target-independent (AGENTS, IDC-10) | fail: complex abort |
| vectorize/rows-x86-64 | the same on x86-64 | merge-into:vectorize/rows-aarch64 | duplicate per target (AGENTS, IDC-10) | not run (x86-64 only) |
| verify/attributes | an unknown idr attribute is refused; refusals verify on a module alone | rewrite | keep `idr.nonsense` and the refusal rules; delete the `idr.origin`, `idr.program`, `idr.stack` splits: old names of one rule (stale-legacy, TBS 1.1) | pass (re-run 15:23) |
| verify/cells | cell ops' rules; an exclusive recycle prints back | rewrite | the expected text quotes `i64` where the message now writes `'i64'`; the FileCheck of `idr.take` text is stale (IDC-6) | fail: wording |
| verify/closure | capture and type rules of idr.closure and idr.apply | keep | (TBS 1.1); absorbs world/world-capture | pass |
| verify/con-owned-field | an owned value fills a field, a borrow does not | keep | (TBS 1.1) | pass |
| verify/cycle | the knot rule refuses arrays that can reach themselves | keep | (TBS 1.1) | pass |
| verify/data | a data type's body rules | rewrite | expected texts drifted (`has two constructors named @A`, `already has a body`) (IDC-6) | fail: wording |
| verify/effects | declared effects must cover the body | keep | (TBS 1.1) | pass |
| verify/flow | an op that moves a closure or suspension must declare how | keep | reveals that the rule no longer fires (IDC-B4) | fail: `expected error "closure or suspension" was not produced` |
| verify/function | idr.* argument and function attributes are refused | merge-into:verify/attributes | the same unknown-attribute rule, four more old names (`idr.hole`, `idr.quantity`, `idr.total`, `idr.entry`) (stale-legacy, TBS 1.1) | pass |
| verify/generic | verifier errors only the generic form can reach | keep | (TBS 1.1) | pass |
| verify/match | match and match_lit verifier rules | rewrite | delete the split that expects upstream's RegionBranchOpInterface sentence (`along control flow edge from Operation idr.yield ...`), which is MLIR's (TBS 1.1) | pass |
| verify/nat | a natural is never negative by its type | rewrite | expected `must be a natural number`, now `must be a natural, read in place` (IDC-6) | fail: wording |
| verify/only-atoms | an exclusive reference to a multi-cell run is refused | keep | (TBS 1.1) | pass |
| verify/ops | assorted op constraints | rewrite | expected `writes a list of characters or of strings`; the constraint is now ODS's (IDC-6) | fail: wording |
| verify/owned-stage | the owned stage's rules; take/recycle/init print back | keep | (TBS 1.1) | fail: RUN 3 idr-rc ill-graded (`idr.str.append` result plain) |
| verify/program | whole-program rules per stage | rewrite | stale fixture syntax: `alignment` in `memref.alloc`'s attr-dict, an `!idr.fn` result spelled `(i64)` in an expected message, a `%s` used at two types (IDC-6) | fail: 5 unexpected errors |
| verify/reduce-regions | idris-mlir-reduce simplifies a used op to ub.poison | rewrite | `--implicit-check-not=arith.` pins how far the reducer's search went; check the contract (every candidate verifies, the result is interesting); move to a `reduce/` directory (TBS 1.1) | fail: `arith.subi` left in the default region |
| verify/roundtrip | every op, type and attribute round-trips | rewrite | `!Main.Shape` alias is a reserved name now (stale); dcafd452 edits this file after the run | fail: `type names with a '.' are reserved` |
| verify/values | constant and constructor value rules | rewrite | three expected texts drifted; two cases (bigs `-0`, `007`) no longer refused (IDC-B8) | fail: wording, 2 missing refusals |
| verify/widths | integer widths Idris has | keep | (TBS 1.1) | pass |
| world/world-capture | a closure never captures a world | merge-into:verify/closure | its first split is verify/closure's capture split, same op, same rule (TBS 1.1); the second (a world argument) goes with it | pass |
| world/world-carrier | the old carrier spelling no longer parses | delete | checks a removed type stays unknown, which the parser does for every unknown name (stale-legacy, TBS 1.1) | pass |
| world/world-once | worlds used once on each path are accepted | merge-into:world/world-twice | the accepting half of one rule; one file with the refusals (TBS 1.1) | pass |
| world/world-twice | a world used twice on a path is refused, wherever | keep | (TBS 1.1) | pass |

Directories holding only a stale `output` (no test; IDC-17): `narrow/constants`,
`obs/budget`, `obs/canonicalize`, `obs/round-failure`, `obs/round-trace`,
`ownership/consumed-effects`, `ownership/owned-stage`, `pipeline/do-block-forced`,
`pipeline/fixpoint`, `pipeline/nested-constant`, `pipeline/rdv-address-taken`,
`pipeline/rdv-unreachable`, `raise/not-raised`, `rc/array-loops`, `rc/atom-reuse`,
`rc/loops`, `returned/arguments`, `specialize/accumulator`,
`specialize/breaker-clones`, `specialize/budget`, `specialize/clone-callers`,
`specialize/closed-call`, `specialize/linear-shared`, `specialize/quantity`,
`specialize/redirect`, `specialize/shared-key`, `specialize/twice`,
`stack/budget`, `stack/calls`, `stack/local`, `stack/loops`, `stack/lower`,
`stack/stored`, `stack/tail`, `vectorize/generate-fill-first`,
`vectorize/lanes-loops`, `vectorize/refused-rows-in-order`, `verify/linear`,
`verify/module`.

## 3. Findings

### IDC-1. The contract oracle crashes on any module without the idr dialect

- **Category:** code-bug-revealed, wrong-or-missing-oracle. **Severity:** high.
- **Paths:** narrow/select-lanes, tail-calls/decided-loops,
  tail-calls/positions, returned/threaded; `foreign/idr/lib/Transforms/Expect/Folds.cpp:21`.
- **Evidence:** each exits 139 with
  `#5 idr::IdrDialect::foldLeakCount() const`,
  `#6 idr::expect::foldsBalanced(...)`,
  `#7 idr::ContractInstrumentation::runAfterPass(...)`. The source:
  `int64_t left = module->getContext()->getLoadedDialect<IdrDialect>()->foldLeakCount();`.
  The four inputs are modules of `func`/`vector` or `llvm` alone, so no idr
  op loaded the dialect. lit.sh adds `--idr-contracts` to every
  `idris-mlir-opt` of every RUN line.
- **Guideline:** TBS 7 (a universal oracle that crashes is no oracle; the
  failure reads as the pass's), TBS 12 ("a testing failure is information
  about the testing infrastructure").
- **Recommendation:** fix `foldsBalanced` (no loaded dialect, nothing folded:
  balanced) and give the contract instrumentation a fixture of its own, a
  module of upstream dialects alone, so the oracle is tested before it
  judges anything.

### IDC-2. Hand-written fixtures give idr-expect no way to see a copy

- **Category:** harness-representation, cannot-fail. **Severity:** high.
- **Paths:** specialize/countdown, countdown-long, dictionary, higher-order,
  static-table (failing); specialize/growing, partial-list,
  optimize/specialize-ends, pipeline/known-label, rc/second-redirect,
  raise/closed-world (passing, partly vacuous); `Expect/Named.cpp`.
- **Evidence:** `Named.cpp`: "What a function is made from is in its
  location ... a copy is a clone of its original with the original's
  location", and `names` matches only the symbol or a `NameLoc`. The
  specializer keeps the clone's own location (`Specialization.cpp:49`,
  `clone.getLoc()`). A fixture's function has a file-line location, so its
  copies name nothing. The expect suite's own fixture marks them by hand:
  `} loc("iter")` (tests/idr/expect/one-clone.mlir); no fixture in this
  lane does. Hence, after `symbol-dce` takes the original:
  `error: expected one-clone: no call of @loop or of a copy of it`. Without
  symbol-dce the original stays and `one-clone` or `specialized-once`
  quietly reads the original only: `specialized-once=@grow` holds whatever
  the copies call.
- **Guideline:** TBS 9.2 step 5 ("Check that the real system actually
  entered each state the model claimed. Otherwise the test can silently
  check nothing"); RF "One fact, one place" (the name would be written twice
  per function, symbol and `loc`, if fixed by hand); TBS 1.1 (the
  vocabulary is too weak).
- **Recommendation:** make the origin a fact the parser gives every function
  of a hand-written module: an `idr.func` read without a `NameLoc` gets one
  from its symbol (or the program op fills them on parse), so fixtures stay
  as written and copies are found. Then re-state the specialize properties
  and add, per property, a fixture where the copy exists and the property
  must fail.

### IDC-3. Optimization fixtures check shape, never meaning

- **Category:** wrong-or-missing-oracle. **Severity:** high.
- **Paths:** all of raise/, specialize/, optimize/, narrow/, names/,
  pipeline/do-block, known-label, growing-function, accumulator.
- **Evidence:** every one states only what is left (`not-called=@greet`,
  `one-clone=@map`, `word-loop=@parity`). An optimizer that deleted the
  calls' work would satisfy `not-called`. Yet most of these fixtures are
  runnable programs whose root reads one byte and prints a number:
  `%c, %w1 = idr.io.get_byte %w` ... `idr.io.put_sint %r, %w1`
  (raise/shared-key, specialize/countdown, names/edit, optimize/once,
  pipeline/known-label, ...).
- **Guideline:** TBS 7 ("in a typed setting, the quality of your testing is
  almost entirely the quality of your oracle"), TBS 8 (exhaust the small
  cases: one input byte is 256 inputs, "a proof inside a box"), TBS 1.2
  (a second implementation we own).
- **Recommendation:** a translation-validation oracle in lit.sh: compile the
  fixture as written and as the pass left it, run both on all 256 one-byte
  inputs, compare stdout and exit status. The unoptimized pipeline is the
  second implementation. This needs the pipeline to run from the stage a
  module is at (IDC-16).

### IDC-4. Text scraping of printed IR in place of properties

- **Category:** brittle-overspecified, perception. **Severity:** medium.
- **Paths:** names/edit, names/reorder (sed of `idr.func ... @name(`),
  optimize/once (grep and sed of MLIR's action log), pipeline/steps,
  tail-calls/mutual, vectorize/* (the tree printer's
  `builtin_module_no-symbol-name/func_func_<f>/*_<pass>.mlir`),
  pipeline/rc-steps (`IR Dump After IdrRcPlace (idr-rc-place)`).
- **Evidence:** names/edit RUN 7:
  `sed -n 's/^ *idr\.func \(private \)\{0,1\}@\([^(]*\)(.*/\2/p'`. Once the
  wave printed a function's effects before its symbol
  (`idr.func effects<io, crash> @f(`, syntax/facts-roundtrip), the scrape
  matched nothing; RUN 10's `diff %t.names %t.edited.names` then compared
  two empty files and passed. optimize/once: `Expected 5 lines, got 0.`
- **Guideline:** TBS 1.1 (brittle: fails "for an innocuous reason"; a
  brittle test signals a weak vocabulary), RF "Every string that names a
  thing is a missing type".
- **Recommendation:** add the missing test API rather than repairing the
  scrapes: an idr-expect property or an opt flag that lists symbols, and a
  way to run idr-expect at a named step of the driver's pipeline (the
  program pools already state `mlir.expect` per top-level pass; give lit the
  same).

### IDC-5. FileCheck restating a property in op text

- **Category:** redundant, brittle-overspecified. **Severity:** medium.
- **Paths:** rc/stack-cell RUN 4, stack/linear-box RUN 4, returned/threaded,
  rc/statistics, obs/stats.
- **Evidence:** stack/linear-box states `no-heap-allocation=@linear` and
  then `CHECK: idr.cell.stack : !idr.cell<!idr.box<!List>, @Cons>` /
  `CHECK-NOT: idr.cell.new`. returned/threaded checks
  `STATS: (S) 5 dropped` and five `CHECK: call @branch(...) : (i64, i1) -> ()`.
- **Guideline:** RF "One fact, one place"; TBS 1.1; tests/README.md ("a
  property of the compiled module is stated in idr-expect rather than by
  matching ops").
- **Recommendation:** delete the FileCheck lines where a property exists;
  where none does, write it once (`signature=` already exists for
  returned/threaded).

### IDC-6. Verifier tests pin the prose of diagnostics

- **Category:** brittle-overspecified, harness-representation. **Severity:** medium.
- **Paths:** verify/cells, data, nat, ops, program, values, tie-shape/verify,
  syntax/inherent-invalid, rc/verify, verify/match.
- **Evidence:** the behaviour held and the wording moved:
  `expected error "has two constructors named @A" was not produced` beside
  `unexpected error: the data type "T" has two constructors @A`;
  `expected ... of type i64, which is no box` beside the same text with
  `'i64'`; tie-shape's `one size for each dynamic dimension` beside
  `takes 1 sizes for 'tensor<?x?xi64>'`. About a third of the verify
  failures in this lane are this.
- **Guideline:** TBS 1.1 (the contract is "refused, at this op, for this
  rule"; the sentence is for a human); RF "Every string that names a thing is
  a missing type" (a verifier rule is named only by its prose).
- **Recommendation:** give each verifier rule an identity a diagnostic
  carries (as refusals carry `#idr.refusal<rule, ...>`), and have
  `-verify-diagnostics` match a short stable key (the rule) rather than a
  sentence; leave upstream's and ODS's messages unmatched beyond `operand #N
  must be`.

### IDC-7. Tests of removed behaviour

- **Category:** stale-legacy. **Severity:** medium.
- **Paths:** obs/bitcode-section-option, world/world-carrier,
  roles/pure-calls, roles/optimize-statistics, verify/attributes
  (`idr.origin`, `idr.program`, `idr.stack`), verify/function (`idr.hole`,
  `idr.quantity`, `idr.total`, `idr.entry`).
- **Evidence:** `CHECK: Unknown command line argument '--runtime-bitcode-section='`;
  `expected-error @+1 {{unknown type}}` on `!idr.world_carrier`;
  `-mlir-debug-counter=idr-pure-calls-erase-count=0`,
  `CHECK-DAG: idr-canonicalize.not-converged`. A search of
  `foreign/idr/lib` and `include` finds no `pure-calls` and no
  `idr-canonicalize`.
- **Guideline:** TBS 1.1; RF "Delete what the representation makes dead in
  the same change ... the test that checked the impossible state".
- **Recommendation:** delete them; one unknown-attribute split covers the
  rule all the old names exercise.

### IDC-8. Duplicates

- **Category:** redundant. **Severity:** low.
- **Paths and evidence:** world/world-capture split 1 is verify/closure's
  capture split (same `idr.closure @g(%w)`, same rule);
  specialize/countdown-long is countdown with `1000000` for `5`;
  pipeline/growing-function is specialize/growing (`iter` over a closure
  that grows); stack/escapes is stack/expect RUN 5-7; rc/twice is
  pipeline/stages' StagedPass refusal; raise/branches, chain, projection,
  through-linear are one mechanism (inline, then a dispatch meets its
  constructor) in four files; vectorize/rows-x86-64 and rows-aarch64 state
  the same target-independent `vectorized` property.
- **Guideline:** TBS 1.1, TBS 8 (a constant chosen twice by hand is a
  generator not written).
- **Recommendation:** merge as the table says; where two files differ only by
  a constant, generate the constant (`awk` already writes chains in
  optimize/caller-cap and narrow/versioned).

### IDC-9. Thread determinism re-checked by hand in single fixtures

- **Category:** redundant, distribution. **Severity:** low.
- **Paths:** names/edit, names/reorder, optimize/specialize-ends,
  pipeline/steps, pipeline/time-trace.
- **Evidence:** `RUN: idris-mlir-opt %s --idr-optimize --mlir-disable-threading -o %t.serial.mlir`
  then `RUN: cmp %t.mlir %t.serial.mlir`, five times, each with its own
  `NEEDS-ACCEPTANCE: the pipeline's output under one thread is byte-identical`.
- **Guideline:** TBS 7 (a universal oracle belongs everywhere, not in five
  examples), TBS 5 (which inputs it meets is chosen by nobody).
- **Recommendation:** make it universal as `--verify-roundtrip` is: lit.sh
  runs every `idris-mlir-opt` line threaded and serial and compares, and the
  determinism pool keeps the driver.

### IDC-10. Per-target tests

- **Category:** redundant, other (AGENTS target rule). **Severity:** medium.
- **Paths:** vectorize/lanes-x86-64, rows-x86-64, rows-aarch64.
- **Evidence:** `targets` files `x86-64`, `aarch64`, `x86-64`; rows-aarch64:
  "The arm64 counterpart of rows-x86-64: the same loops". Each checks
  `vectorized=@squares`, `vectorized=@rows`, `narrowed-lanes=@...`, none of
  which names a lane count. So on this host, two of the three never run.
- **Guideline:** AGENTS ("Per-target cases elsewhere are bugs"); TBS 1.1.
- **Recommendation:** one test per property, run on the host's target; a
  fact that really depends on the target (the lane count) is read from the
  target entry, never written in a test.

### IDC-11. Claims the RUN lines never check

- **Category:** checks-nothing, cannot-fail. **Severity:** medium.
- **Paths and evidence:** tie-shape/dims-fold (claims each `tensor.dim` and
  `memref.dim` folds to its tied size; its one RUN line checks only
  `test-convergence=true`); rc/counted-linalg (`not idris-mlir-opt %s`
  passes on a typo); obs/debug-counter (claims "the call of @pow ... stays a
  call of @pow", checks only the counter's report); raise/shared-key and
  raise/closed-world (claim one shared copy and no copy, check `not-called`
  and `constant-stack`); pipeline/known-label (IDC-2).
- **Guideline:** TBS 9.2 step 5, TBS 1.1 (a test named for a property that
  checks something else).
- **Recommendation:** state the claim (`returns=` of the tied size;
  `-verify-diagnostics` naming the refusal; `calls=@Main.main:@pow`; a copy
  count), and pair each with an input where it must fail.

### IDC-12. `expected` restates the fixture's RUN-line count

- **Category:** harness-representation. **Severity:** medium.
- **Paths:** every lit test in scope; obs/print-with-object.
- **Evidence:** each `name/run` is the same five lines ending
  `lit ../name.mlir`, and each `name/expected` is `RUN 1: ok` ... `RUN n: ok`,
  n being the number of RUN lines, a fact the `.mlir` already holds.
  obs/print-with-object has 7 RUN lines and an `expected` of 6, so it
  "fails" with every line `ok`.
- **Guideline:** RF "One fact, one place"; RF "The limit" does not apply (no
  second case: a lit test passes when every line holds).
- **Recommendation:** a dialect test is its `.mlir` alone: the runner finds
  `idr/**/*.mlir`, and the expectation is "every RUN line ok", printed as
  one line. 260 boilerplate files go.

### IDC-13. lit.sh's RUN language is `eval` of shell, not lit

- **Category:** infrastructure-gap. **Severity:** low.
- **Paths:** structure/columns.
- **Evidence:** `--idr-expect=holds=signature=@pairs:(index)->(tensor<?xi64>,tensor<?xf64>)`
  gives `eval: line 95: syntax error near unexpected token '('`, so the test
  could never have passed under this runner. Other fixtures quote the
  argument (`'--canonicalize=region-simplify=disabled test-convergence=true'`).
- **Guideline:** TBS 1.1 (a failure for an innocuous reason).
- **Recommendation:** quote it; and have lit.sh refuse a RUN line that does
  not parse before it runs anything, naming the line.

### IDC-14. Universal post-conditions stated as examples

- **Category:** example-should-be-property. **Severity:** medium.
- **Paths:** optimize/caller-cap and totality (`largest-function=10000`),
  roles/contify (skip every action: identity), names/* (names from keys),
  syntax/inherent-invalid (every inherent attribute refused in attr-dict).
- **Evidence:** caller-cap: "after the optimizer no function is larger than
  that", true of every compilation and checked on one; contify: "with every
  move skipped the pass leaves the module exactly as no pass does", true of
  every action-gated pass.
- **Guideline:** TBS 1.1 last paragraph ("Expressive assertions are the
  precondition for generated tests"), TBS 7 (universal oracles).
- **Recommendation:** put `largest-function` into `--idr-contracts` after
  idr-optimize; one harness that, for every pass with an action tag and every
  fixture, runs the counter at 0 and diffs; one generated check over the
  dialect's registered ops for inherent attributes.

### IDC-15. Boilerplate roots: a program op that forces an unrelated root

- **Category:** harness-representation. **Severity:** low.
- **Paths:** 27 files in scope, 100 occurrences.
- **Evidence:** "// The program's root, which the functions above are no part
  of." followed by an `idr.func @root() -> i64` returning 0, once per split.
- **Guideline:** RF SPOV3 (a special case of the representation), RF
  "Before every branch ... what representation would make this state
  impossible?" (here: what makes the boilerplate unnecessary).
- **Recommendation:** decide whether a fixture needs a program with a root at
  all; if the verifier needs one, let `-split-input-file` fixtures name a
  root among their functions (`root(@f)`, as several already do), and drop
  the invented one.

### IDC-16. No way to finish a module's pipeline from where it stands

- **Category:** infrastructure-gap. **Severity:** medium.
- **Paths:** pipeline/steps, vectorize/*, tail-calls/mutual (which reach a
  step's module through the tree printer's files), and IDC-3's oracle.
- **Evidence:** `sh -c 'idris-mlir-opt "%t.dumps/builtin_module_no-symbol-name/$(tail -n 2 %t.steps | head -n 1)" ...'`.
- **Guideline:** TBS 7 ("Making a system testable is a design activity").
- **Recommendation:** `idris-mlir-opt --idr-pipeline` that starts at the
  module's own stage, and a driver option to state idr-expect properties at
  a named step, both read from the one pipeline definition.

### IDC-17. Stale output directories

- **Category:** infrastructure-gap. **Severity:** low.
- **Paths:** the 39 directories listed after the table; `ownership/` is
  nothing else.
- **Evidence:** e.g. `specialize/budget/` holds only `output`, dated
  10-14 16:51; `.gitignore:7:/tests/**/output`.
- **Guideline:** RF "Delete what the representation makes dead in the same
  change".
- **Recommendation:** the runner removes an `output` whose directory has no
  `run`, or writes outputs outside the source tree.

### IDC-18. Statistics and logs used as oracles

- **Category:** brittle-overspecified. **Severity:** low.
- **Paths:** obs/stats, rc/statistics, roles/optimize-statistics,
  returned/threaded (STATS), optimize/once, obs/debug-counter (COUNTED).
- **Evidence:** `CHECK-DAG: (S) {{ *[0-9]+}} boxed -`;
  `CHECK: IdrRcCells` / `CHECK: IdrRcStack` / ... in pipeline order;
  `COUNTED: idr-specialize-clone{{ +}}: {{[{][1-9][0-9]*}},0,0}`.
- **Guideline:** TBS 1.1 (a human-facing report is not the contract).
- **Recommendation:** keep only obs/report-accepted's property (the report is
  the same at any thread count); delete or reduce the rest to "a report is
  printed".

### IDC-19. Misplaced tests

- **Category:** other. **Severity:** low.
- **Paths:** stack/hot-loop (an Idris program with `expected-stdout`,
  `stdin`, `mlir.expect`, run by `e2e_io`), verify/reduce-regions (a test of
  idris-mlir-reduce), the obs/ and pipeline/ driver tests (idris-mlir's
  command line, not the dialect).
- **Guideline:** tests/README.md layout ("`idr/<pass>/`: the dialect suite,
  one directory per pass or concern").
- **Recommendation:** hot-loop to `programs/stack`; a `driver/` pool for the
  command-line tests; `reduce/` for the reducer.

## 4. Code bugs the tests reveal

Only what the outputs show; the cause is my reading.

- **IDC-B1. `foldsBalanced` dereferences an unloaded dialect.**
  narrow/select-lanes, tail-calls/decided-loops, tail-calls/positions,
  returned/threaded: exit 139, trace through `IdrDialect::foldLeakCount` from
  `ContractInstrumentation::runAfterPass`. Cause:
  `getLoadedDialect<IdrDialect>()` is null for a module of upstream dialects
  (Folds.cpp:21, unchanged since). Confirmed in source.
- **IDC-B2. The driver aborts on the `complex` dialect.** 16 tests in scope
  (obs/print-ir-threads, report-*, stats; pipeline/endless-loop, inputs,
  layout, link, reported-error-fails, runtime-names, steps, timing;
  rc/live; tail-calls/mutual; vectorize/rows-aarch64; obs/print-ir-threads
  exits 134 with its stderr redirected, likely the same): `LLVM ERROR: checking for an
  interface (mlir::ConvertToLLVMPatternInterface) that was promised by
  dialect 'complex' but never implemented`. 25f263da ("complex's lowering
  model", 14:36) addresses it; unverified here.
- **IDC-B3. idr-rc leaves ill-graded IR.** rc/arrays, atom-pairs, consumed,
  counts, dies-apart, exclusive, regions-counted, returned, second-redirect,
  share-trap, statistics, take-at-death; narrow/descending, versioned;
  verify/owned-stage; optimize/pure-call; raise/sunk-call-paths:
  `'idr.match' op operand #0 must be a constructor value at any quantity,
  not owned, but got '!idr.own<...>'`; `'idr.match_lit' op operand #0 must
  be ... read in place, but got '!idr.own<!idr.nat>'`; `'idr.return' op
  returns '!idr.box<...>' as result 0, but @build returns '!idr.own<...>'`;
  `'idr.call' op gives result #0, of type '!idr.lin<!idr.str>', which holds
  references at the plain grade in a graded program`. Reading: grading
  rewrote signatures without the uses in bodies (a match's scrutinee, a
  return), and linear results stay ungraded. 4c87dcc5 ("places every body
  under the grades it writes") and 3d279eb9 follow the run.
- **IDC-B3b. idr-rc's stack step leaves a dangling operand.**
  stack/escapes, expect, linear-box; rc/stack-cell, kept-fields,
  nested-reuse; pipeline/rc-steps: `error: operation's operand is unlinked`
  at the box's con. a7bf77b4 ("Stack cells and recycles are built where
  their cells were") follows the run.
- **IDC-B4. The flow rule no longer refuses `arith.select` of closures or
  suspensions.** verify/flow: both `expected error "closure or suspension"
  was not produced`, and the module printed back with
  `%lazy = arith.select %0, %thunk, %thunk_0 : !idr.lazy<i64>`. AGENTS
  ("never miscompile silently"): a pass that follows labels meets a value
  whose labels it cannot follow. The expectation is right; this is a
  regression.
- **IDC-B5. idr-structure-loops builds an invalid `affine.delinearize_index`.**
  structure/dynamic-cells: `Assertion failed: (index < size() && "invalid
  index into type range")` in `AffineDelinearizeIndexOp::verifyInvariantsImpl`.
  Reading: the rank-0 (or empty-domain) case builds the op with no basis.
- **IDC-B6. idr-structure-loops makes no structured op where the fixtures
  expect one** (plausible, not confirmed). structure/never-returns:
  `no structured op in @gen`; structure/ordered: `no structured op in @sumi`.
  Both regions only compute (or crash); ordered runs idr-effects first.
  Reading: after the wave's move of effects onto each call and op, the pass
  may read a region as effectful. Could also be the fixture; confirm
  against the pass.
- **IDC-B7. Plain canonicalize moves a match past a call with default
  effects** (plausible). optimize/case-of-case-calls RUN 3: the expected
  `allocates in @lowered_past_crash` is not reported, so the match moved
  down past `idr.call @divides(%n)`, a call with no written effects, which
  verify/effects says "declares everything". Reading: an unwritten effects
  property defaults to less than everything.
- **IDC-B8. Non-canonical big constants are accepted** (plausible).
  verify/values: `expected error "expects a big in canonical decimal, got
  "-0""` and `"007"` not produced, with no other error at those lines. Two
  spellings of one value break "a constant compared by its cells" unless the
  parser now canonicalizes on purpose.
- **IDC-B9. `idr.refusals` refused on an explicit top-level module**
  (plausible). syntax/refusal: `'builtin.module' op has "idr.refusals",
  which is an array of #idr.refusal on the top-level module alone` on the
  file's only, top-level module. dcafd452 ("Refused programs report again")
  changes this rule's fixture verify/attributes after the run.
- **IDC-B10. Calls whose result is applied at once are not raised**
  (uncertain). raise/shared-key: `@f is still called, as @f, in
  @Main.main` at each call, though `%r1 = idr.apply %g1(%x)` follows its
  call directly. raise/apply (one call, inside `@use`) passes; the
  difference is several calls with equal keys in the root. Not confirmed.

## 5. The scope rebuilt

What the dialect suite of this lane would be, on these principles.

**Oracles (TBS 7).**
1. *Universal, on every RUN line* (lit.sh): the verifier after each pass,
   `--verify-roundtrip`, `--idr-contracts` (fixed by IDC-B1, extended with
   `largest-function` and `stage=`), and threaded == serial (IDC-9).
2. *Semantic, on every runnable fixture* (IDC-3): the fixture compiled as
   written and as each pass leaves it, both run on all 256 one-byte inputs,
   stdout and exit status equal. The fixtures already read one byte and print
   one number; this is TBS 8's exhaustive small scope, "a proof inside a box".
   It needs the pipeline to finish from any stage (IDC-16).
3. *Specification*: idr-expect properties, each with a fixture on which it
   must fail (TBS 9.2 step 5); copies found by a `NameLoc` the parser gives
   every function (IDC-2).

**Properties that replace examples (TBS 1.1).**
- *Names are functions of keys* (names/*): one metamorphic generator over a
  random fixture: reorder its functions, edit one body, add an unrelated
  function; the symbol set of everything not edited is unchanged. Symbols are
  read from the module, never scraped (IDC-4).
- *Every action-gated pass at counter 0 is the identity* (roles/contify,
  obs/debug-counter): one harness over every pass with an action tag
  (`idr-contify-move`, `idr-optimize-node`, `idr-specialize-clone`) and every
  fixture of the suite.
- *Every inherent attribute restated in attr-dict is refused*
  (syntax/inherent-invalid): enumerated from the registered ops.
- *Specialization ends and keys only fixed positions* (specialize/*,
  pipeline/accumulator, growing-function): the recursion constant generated
  (TBS 8: "randomize the constant across runs rather than fix it small");
  `one-clone`, `specialized-once` checked on real copies.
- *A tie's dimensions fold* (tie-shape/dims-fold): `returns=` of the tied
  size, with an untied counterpart that must fail.

**Verifier tests (verify/, world/, syntax/, tie-shape/verify, rc/verify).**
One file per rule family, each split an `-verify-diagnostics` case matched on
a rule key, not on prose (IDC-6); the old attribute names, the old carrier
spelling and the removed option deleted (IDC-7); duplicates merged (IDC-8).
The verifier's rules are the place a generator pays most: a mutation fuzzer
over valid fixtures (drop a use, duplicate a world, change a grade) whose
oracle is "the verifier refuses, or the module still means the same" (TBS 4.4,
invalid cases named and counted) would replace most hand-written negative
splits.

**Driver tests (obs/, pipeline/ driver half).** A `driver/` pool: exit status,
verdict, report and the presence or absence of outputs, never MLIR's own
sentences or the tree printer's file names (IDC-4, IDC-18); the report's
thread-independence kept as the one statistics property.

**Pipeline structure.** pipeline/stages as written; pipeline/steps reduced to
"the driver's last dump equals `--idr-pipeline`'s output"; pipeline/timing
with its list of inner passes generated from the pipeline definition (RF "One
fact, one place").

**Targets.** One vectorize test, run on the host's target, its properties
target-independent (IDC-10).

**Layout.** A dialect test is its `.mlir` alone (IDC-12); stale `output`
directories cleaned by the runner (IDC-17); stack/hot-loop with the
programs, the reducer and the driver in pools of their own (IDC-19).
