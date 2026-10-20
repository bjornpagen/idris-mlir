<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# The test suite the audit planned

**Status (2026-10-19):** queued after self-hosting, beside "Each fact
once"; nothing below is built. Self-hosting needs none of it, except
where a stage meets a test that lies (§1), which is then fixed first.
The runner under both hosts (§2.1) is the one item self-hosting was
waiting to hand over: it starts once `make self` holds.

What remains of the 2026-10-18 test-suite audit's plan (66fc1401), checked
against `tests/` and `harness/` at 77eaa5b1. The audit judged every test
against `.claude/skills/testing-by-search` and
`.claude/skills/representation-first`; its verdicts were carried out in
d346040c (the purge: `tests/` flat, the harness in `harness/`), ef45c0a7
(every test strengthened: `cases/`, `%differential`, `near/`, planted
witnesses, rotating seeds) and 4108916a (the bug phase), and its
observation step in 28274bd3 (contracts checked in process). The audit's
reports are at 77eaa5b1.

Compiler bugs are `audits/bugs.md`'s. Facts the harness throws away and
derives again (the ending of a run read from status and stderr, the
pipeline rebuilt from text for `%differential`, the googletest boxes found
by a glob, the file a refusal names, `quantities-kept`'s binders keyed by
location) are "Each fact once"'s, and are not repeated here.

No lane owns the test suite (tools/lanes/README.md); each item names the
lane whose area it touches, or `tests` where it is the harness's alone.
The order is the audit's rule: a harness that can lie is fixed before
anything is built on it, and a generator deletes an example only after its
tape replays that example's input and fails on a planted copy of the bug
the example guards.

## 1. Where the harness can still lie (tests)

1. **`%differential` is common-mode for every pass the pipeline runs.**
   BEFORE is compiled by `lit_pipeline_from`, which runs the pass under
   test too, so a miscompile by idr-optimize, idr-narrow, idr-rc or
   idr-lower agrees with itself. Owed: BEFORE compiled with the pass under
   test left out (its actions skipped, as `obs-debug-counter` does).
   Acceptance: a `differential-*` test plants a wrong rewrite inside a
   pipeline pass and the differential names the input that differs.
2. **The differential compares stdout and status, never stderr:** two
   runs that crash with different causes agree. Owed: the crash line
   compared too. Acceptance: a planted mutant that changes a guard's cause
   fails.
3. **`lit_lowered` takes a module's stage from the first line that
   mentions `idr.program ... stage(...)`, comments included**
   (`harness/lib/differential.sh`), so a `// REF:` module above its program
   lowers it from the wrong stage. Owed: the stage read from the module's
   own `idr.program`. Acceptance: a harness test with a reference at
   another stage above its program.
4. **lit substitutes `%s` and `%t` inside identifiers**
   (`harness/lib/lit.sh`, the sed of `lit`): a RUN line naming `%str` or
   `%twice` gets a path spliced in. Owed: a substitution that stops at an
   identifier character. Acceptance: a harness test whose RUN line holds
   `%str`.
5. **`dialect-text` reads `--check-prefix=` only**, so the prefixes of
   `--check-prefixes=A,B` count as orphans. Owed: the plural read too.
   Acceptance: a planted witness and near miss using the plural form.
6. **Dumps still go through `--mlir-print-ir-tree-dir`**
   (`dump_options`, `harness/lib/mlir.sh`): one directory per symbol, so a
   specialized name past NAME_MAX turns a read step into "File name too
   long" and hides the compiler's own error (show-dependent-pair in
   `audits/bugs.md`). Owed: no file name made from a symbol. Acceptance: a
   program whose read step holds a symbol longer than NAME_MAX compiles
   under the harness and its check reads the step.
7. **One verdict for many programs.** `bench-smoke` folds every
   benchmark into one verdict (four failed inside it on 2026-10-19), and
   the one parameterized test, `semantics`, is named in
   `harness/Main.idr`'s `parameterized`. Owed: `bench-smoke@<name>` from
   the bench listing and `determinism@<program>` (§5.6), each its own
   verdict, and every parameter list read from data, not from the
   runner's source. Acceptance: one failing benchmark is one failing
   test, and Main.idr names no test.

## 2. A typed runner (tests)

The runner still depends on `Test.Golden` and `contrib`
(`harness/harness.ipkg`: `depends = contrib, test`), and a program's
`expected` is a hand-kept transcript of harness constants (`artifacts:
core module objects executable`, `cases: each as expected`).

1. **The runner builds and runs under idris-mlir,** while the stock host
   keeps running it (AGENTS.md: two hosts). What blocks it (*read*):
   `harness/Runner.idr` calls `system`; `harness/Main.idr` and `Runner.idr`
   import `Test.Golden`; `harness/Lock.idr` imports `Language.JSON`;
   `harness/harness.ipkg` depends on `contrib` and `test`, which this
   compiler does not ship. The fix: process creation moves into sh glue,
   `Test.Golden` and contrib go (the option parser, `filterTests`), JSON
   moves to base or `libs/`. The generators (`Gen`, `Sem`, `Fuzz`,
   `TwoLevels`, `Prims`, `Lazy`) are written for both hosts already, and
   `tests/fuzz-two-hosts` compiles them with idris-mlir (it fails on main
   today, `audits/bugs.md`). Acceptance: `harness.ipkg` depends on neither
   package, and `make test` runs with a runner idris-mlir built. After
   `make self`; the coordinator's, as a lane of its own.
2. **A `Fixture` record parsed once and a typed verdict** (`Check`,
   `Verdict`, with the outcome of "Each fact once"'s "ending lost"):
   unknown files and conflicting marks unrepresentable, and a program's
   transcript computed from its fixture, so the constant lines go.
   Acceptance: no program test holds an `expected`; a failure prints only
   the failing checks.
3. **Acceptance per host as data:** `(test, host, expectation hash)`
   records written by `make accept`, an `Unaccepted host` verdict, and
   `targets` parsed into a closed host type (a misspelt word is refused,
   not a test that runs nowhere). Acceptance: a new `expected.<host>` is
   reported unaccepted until accepted.
4. **One program runner:** `profile_compile`, `bench_smoke` and
   `fuzz_check` run programs through `e2e_io`'s path. Acceptance: one
   function compiles, links and runs every program the harness runs.
5. **`make test-unit` a pool of the runner,** each box a test of its own
   (with "Each fact once"'s box list read from the build).
   Acceptance: a missing or crashing box is a named failure in the summary.

## 3. The vocabulary (tests, with the area's lane for each row)

1. **idr-expect rows the audit found missing** (`Lookup.cpp` has none of
   them): `boxed` (defunc: keys on a cycle become boxed sums, a sum past
   2^16 constructors is two levels, memo-sum's running and forced
   states); `merged=` as the complement of `apart` (control: dedup's merge,
   raise-shared-key's one copy); a positive `copies` row for bufferize
   (arrays); `stack-bytes<=N` (ownership); bound forms `crash-sites<=n` and
   `loops>=1`. Acceptance: each row in `expect-coverage`'s table with a
   fixture where it fails.
2. **Roots forms of `counts-nothing`, `tests-nothing` and
   `reuses-in-place`** (today `Functions` forms, which name helpers the
   inliner removes), and a `reuses-in-place` restricted to one data type's
   boxes. Acceptance: ioarray-sieve, ioref-record-in-place,
   char-list-pipeline and split-prefixes state their claims of the root;
   the bench programs' claims below (§6.6) can be written.
3. **A request on a function the root cannot reach is refused.**
   Acceptance: a fixture asking a property of an unreached function fails
   naming it.
4. **A frontend lambda named apart from its definition** (today both
   carry the definition's `NameLoc`), so `total` is stated of main's
   lambdas and `not-total` of main. Acceptance: a program states both.
5. **A rule identity on every verifier diagnostic, and `%refuses
   <rule>`** read from `--report`: `verify-*`, `syntax-*`,
   `tie-shape-verify` and `rc-verify` still match prose. Acceptance: no
   fixture matches our own diagnostic's wording beyond the rule key.
6. **The pipeline as data:** `idris-mlir-opt --idr-pipeline=from:<stage>`
   and `to:<step>` from the one pipeline definition (the harness builds
   `from:` in shell today), and a generated table of (pass, role, stage,
   action tags) that the tests read; `IdrPassStages.txt` is read,
   `IdrPassRoles.txt` by no test. Acceptance: no fixture chains passes by
   hand; the action census (§5.1) reads its tags from the table.

## 4. Universal checks not yet on every compilation (tests)

Every e2e compilation checks today: the passes' contracts in process
(`--idr-contracts`), the read dumps parsing and verifying again, the
object's imports, and no cell live at a normal exit. Owed, each added to
`universal` (`harness/lib/properties.sh`) with no transcript change:

1. **Emit's quantities against Idris's TT:** each parameter is a
   non-erased binder and each linear binder is `!idr.lin`. Acceptance: a
   planted Emit that keeps an erased binder fails every program.
2. **The lowered module's facts:** `linker-names`, `entry`,
   `aligned-access`, `lowered`, `in-llvm`, `direct-calls` after
   defunctionalization, `stage`. Acceptance: on every program; a fixture
   copy of them goes.
3. **The emitted module's byte round trip,** generic form and bytecode;
   `handoff-round-trip` and `handoff-readable` go with it.
4. **No `idr.*` discardable attribute on any dump**; `facts-in-types`'
   grep goes with it.
5. **The checked runtime on every program** (today only
   `actions-skip-programs` and `fuzz-lazy` link `idris_rt_checked.o`), so a
   use after free fails the run where it happens.
6. **Sampled determinism:** one compilation in k redone at a drawn thread
   count, the seed printed.

## 5. Relations and differentials over the corpus (tests)

1. **The action census** (Passes.td: skipping any one transform of an
   optimization keeps the behaviour). `actions-skip-programs` runs four
   programs with three tags (stack cell, reuse site, inline). Owed: every
   tag of every optimization pass, idr-optimize's inner tags included,
   skipped alone and in drawn sets over the program corpus, with a census
   that fails a tag that never fires. It deletes `actions-accumulate`,
   `-columns`, `-narrow`, `-narrow-lanes`, `-returned-arguments`,
   `-stack`, `-tail-loops`, `-trmc`, `roles-contify` and
   `obs-debug-counter`. Waits on §3.6's table.
2. **Fold against run generated from Sem's table:** per foldable op, every
   width, an edge dictionary (0, ±1, min, max, the width ±1, negative
   amounts, NaN, ±inf, surrogates, offsets inside a UTF-8 sequence). The
   `fold-*` fixtures write each table twice by hand (run form and folded
   form); the generator emits that shape and they go.
3. **The guard family generated from the `Idr_Guarded` records**
   (satisfying constant folds the guard, refusing constant keeps one crash
   site, an unguarded op on a refusing constant does not fold); the six
   `guards-fold-*` go.
4. **Sem both ways.** `harness/Sem.idr` writes every case on literals, so
   each `semantics@` program folds to one constant and codegen is never
   checked. Owed: one program per type, each case on literals and on
   stdin values, against `Prims`; and the `maxCases` self-check, which
   checks the harness's own constant, deleted.
5. **TwoLevels dissolved.** `harness/TwoLevels.idr` is still read by
   `Fuzz.idr`'s self-checks and `fuzz-two-hosts`. Owed: its integer terms
   in Sem's tables, Double, Char and String values as a table from the
   runtime's documented meaning, the Prelude corpus as laws over generated
   values (`reverse . reverse = id`); then the module goes.
6. **`determinism@<program>`** over the bench list and fuzz seeds, thread
   counts drawn per run, deleting `determinism-rbtree`, `-shapes`,
   `-threads-rbtree` and `-threads-linarray-lanes` (whose remark filter
   names a pass, not a role); and `names@<seed>`, a metamorphic generator
   (reorder, edit one body, add an unrelated function; every symbol not
   made from the edit keeps its name, read from the module), in place of
   `names-from-keys` and `determinism-name-stability`.
7. **Refusal relations:** a refused definition kept but unreached from
   main compiles; two fixtures' offenders reached together give exactly
   two refusals, each at its line.
8. **The effects model:** programs over none, crash, io and diverge whose
   observable trace (output, then crash or exit) is unchanged by
   canonicalize, cse and control-flow-sink, in place of the per-op
   `effects-*` tables.

## 6. The search: Fuzz and the generators (tests)

1. **Fuzz widened.** Its runtime part still has no Integer ("At run time
   no Integer exists", `Fuzz.idr`), no Nat and no run-time string. Owed:
   those, the ±2^62 edges in the pools, preconditions drawn as a named
   breach mode judged by the documented crash (not `Domain` constraints
   that never draw a division by zero), families drawn before primitives
   so the weights are the shares.
2. **Regression as a corpus and `make fuzz`.** `fuzz-seeds` runs seeds 1
   and 2 and one drawn seed. Owed: a committed corpus of shrunk failing
   tapes replayed by `make test`, and a `make fuzz` target that draws from
   the clock, appends failures and stops at a Good–Turing residual under
   10^-3 or its budget, over the features (family, result type, construct,
   stage reached).
3. **A compile failure isolated and shrunk** (delta debugging over the
   cases, then the tape, then `idris-mlir-reduce`); `fuzz_shrink` shrinks
   only `agree` and `model` failures.
4. **The typed program generator** (planned by the soundness proposal,
   whose last text is at 77eaa5b1) with its oracle, an
   evaluator over the generator's own AST with `Prims` for primitives. Its
   families, in this order, each with the examples it deletes once shown
   failing on the planted bug:
   1. G1 ADTs and layout, n around 255/256, 511/512, 767/768 (the wrap of
      an 8-bit count) and 2n±1: the `layout-*`, `records-*`,
      complete-split, enum-stepping, void-field, mixed-widths,
      literal-match; lower-layout's limits (256, 65,537, 258).
   2. G3 the Linear.Vec and IOArray command model, indices `Live`,
      `Stale`, `Wild`, a negative generate size: linarray-push-pop,
      reserve, read/write-past-size, vec-pop-then-push, the `bounds-*`.
   3. G4 the guard and crash table, with output before the crash and the
      located form `<cause> at Prog.idr:L:C`: the `guards-messages-*`,
      crash-location, crash-mod-zero, buffer-range, double-cast-nan.
   4. G2 linear lists, the `leet-*` programs as seeds.
   5. G7 tail-call graphs, even/odd mutual recursion, a divergent callee
      on an untaken path, results returned in memory; idr-rc-stack's
      bounds (a cell over 256 bytes, a frame past 1024, 64 on a cycle,
      stated by no test today) at n-1, n, n+1.
   6. G9 laziness and IO traces, a call-by-need model with force counts
      (`harness/Lazy.idr` covers CAF streams and memo chains): the
      memo and stream shapes, action-after-effect and action-run-at-once.
   7. G-HO higher-order with bounded closure sets, and user dictionaries
      (an `Arith` over Int, Double and Complex, which only `nbody` holds).
   8. Growth schemes: `Box.idr`'s growth graphs as Idris sources, refused
      at the cycle iff the graph grows, else the value the graph computes;
      the `bounded-*` and `polymorphism-*` fixtures become seeds.
   9. The registry pool: one program per Forbidden or Deprecated entry,
      `deprecatedForeign` included, checking rule, site and entry.
   10. Verifier mutation operators over the corpus's dumps, each of which
       must produce its diagnostic.
   11. G5 text: shortest round trip and even ties of Double's show, the
       cast-from-string grammar, the UTF-8 decoder: the `double-*`,
       closed-double-*, cast-from-string's examples past its named
       invalid seeds.
   12. G6 Nat and Integer across 2^62: nat-large, integer-bits.
   13. A simulated platform for base's IO primitives (files, directories,
       env, clock, errno), which waits on a runtime interface that does
       not exist.
5. **prop.h:** shrink bytes as Gen shrinks tapes (it halves the length),
   check the splitmix vectors both definitions share, finer classes, and a
   report kept past the run.
6. **The bench programs' properties,** each in `bench/<name>/mlir.expect`
   run by `bench-smoke@<name>` (§1.7), once §3.2's Roots forms exist:
   fannkuch-redux and fannkuch-linear `counts-nothing`, `in-place` and
   `no-heap-allocation` in their loops; qsort's and unionfind's;
   spectral-norm-linear's `structured-loops`, `vectorized`,
   `narrowed-lanes`; and each game program checked against the game's
   published output at a small size, not only against `main.c`.
7. **`Labels.cpp`'s one example** stated as an `idr-expect` `labels=`
   fixture, and the box deleted.

## 7. Repository rules, toolchain and upstream tests

1. **`spec/target-confined`** (tests): no target predicate (x86, arm64,
   Linux, ELF, glibc, a page size) outside the target's entry and the
   runtime's platform layer, with a planted witness. No test states it.
2. **Module-graph rules** (tests): `MLIR.Internal` imported only from
   `Dialect.*`; `no-behaviour-options`' kept list read from the options'
   `cl::OptionCategory`, not written in the test.
3. **`static-linking` with a planted dynamic executable** (target).
4. **cpu-features per target entry** (target): `cpu-features-aarch64` runs
   on one host and nothing checks the feature word `@main` passes to
   `idris_rt_start`. Owed: one test over every target entry, on every host.
5. **The fork reproducers in `make test`** (tests): the Idris-side
   `upstream-*` tests are in the `test-mlir-tools` suite. And work counts in
   place of wall-clock ratios in `upstream-bytecode-deferred-quadratic`
   and `upstream-forward-dataflow-callee-lookup` (upstream).
6. **Linux confirmations** (target), waiting on the first Linux build:
   `page-size-mismatch`'s quarter page at 4 KiB, and `runtime-triple`'s
   environment row.
7. **Target facts from the build** (target): `system-info` checks its `os`
   only as "a name", and `buffer-ops` writes its byte order in a comment;
   both read from the target's entry.
8. **A shared test package** (tests): `readInt` and the array helpers are
   copied into 51 tests.
9. **Reject headers** (tests): a form for a refusal at no source line
   (idr-knots' third placement, `static argument` through a library
   projection, both at location `-`), and `<file>:<line>` for a refusal in
   another module.
10. **Stage 2 equals stage 3 as a test** (tests): `make self`'s fixed
    point checked by the suite, once `proposals/0001-self-host.md` makes
    `make self` hold.

## 8. Left by the representation wave (checked at 77eaa5b1)

- **The stage chain, unchecked.** `-gen-pass-stages` writes
  `IdrPassStages.txt` and `Passes.td` says the tests read every pass's
  `requires` and `sets` in the pipeline's order, but nothing does
  (`harness/lib/differential.sh` reads it only to start a pipeline). Owed:
  a test joining `--idr-pipeline --dump-pass-pipeline` with the table and
  checking the chain (`any` passes through). Acceptance: it fails when
  two passes are swapped across a stage change.
- **Negative idr-expect runs read stderr.** About 75 `%status 1 ...
  --idr-expect` runs check FileCheck on stderr or the status alone; the
  ones on `%s` take `// expected-error @below` under `-verify-diagnostics`
  (the ones on a generated `%t.mlir` need another form, stated).
- **Discriminators never written:** a defunctionalization test of a sum
  over a field type it cannot hold, expecting an internal error, not a
  crash (`Slots::define`'s `FailureOr`); a program with a complete literal
  match and no default (`LitNoDefault`, 0892609d).
- **Generated output nobody compares:** `Fuzz.twoHosts`' `== <request>`
  sections (seeded programs, tape, shrink, the sem and two-levels
  programs) are read by no test, `fuzz-seeds` reads only the
  `fuzz-check:` lines; `TwoLevels.checkOf` and `verdict` are dead since
  `tests/two-levels` went (§5's dissolving of TwoLevels takes them);
  `harness/lib/fuzz.sh` still greps the `[djrs]1` label grammar.
