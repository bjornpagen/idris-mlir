<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Audit lane: repo-tests

**Scope.** `tests/spec` (`make check`: the repository's rules), `tests/toolchain`
(toolchain, runtime and static-linking checks, with `tests/toolchain/lib`),
`tests/upstream` (pinned-upstream and fork reproducers, `make test-mlir-tools`),
`tests/determinism`, `tests/bench`, and the googletest boxes in
`foreign/idr/unittests` (`make test-unit`).

**Read.** AGENTS.md; `.claude/skills/testing-by-search/SKILL.md` (TBS);
`.claude/skills/representation-first/SKILL.md` (RF); `tests/README.md`;
`tests/testutils.sh`; `tests/Main.idr`, `tests/Runner.idr`,
`tests/runner/one.sh`; `tests/lib/{rules,determinism,bench,compile}.sh`; every
`run`, `expected`, `expected.*`, allowlist and source file of every test in
scope; `tools/policies.txt`; `foreign/idr/include/idr/Testing/Box.h`;
`foreign/idr/unittests/*` and its CMakeLists; the `output` each test's last run
left; the logs `check.log` (13:57), `test.log` (16:43, `make test`),
`test-idr.log` and `test-mlir-tools.log` (14:32), `test-unit.log` (13:35); and
the commits since the wave (`c4d0b26b`, `7589866c`, `25f263da`, `dcafd452`,
`6911742a`) where they changed a test or the code a test checks. Nothing was
built or run; every status below is read from an `output` file or a log, and
dated where it matters.

**Counts.** 106 tests: spec 35, toolchain 22 (plus `lib/`, a helper), upstream
25, determinism 8, bench 3, googletest 13 source files (48 `TEST`/`TEST_F`
cases in 6 boxes). Also 9 directories that hold only a stale `output` and no
`run` (not tests; listed at the end of the table).

| verdict | spec | toolchain | upstream | determinism | bench | unittests | total |
| --- | --- | --- | --- | --- | --- | --- | --- |
| keep | 23 | 17 | 23 | 6 | 2 | 12 | 83 |
| rewrite / rewrite-as-property | 9 | 4 | 2 | 0 | 1 | 1 | 17 |
| merge | 0 | 1 | 0 | 1 | 0 | 0 | 2 |
| delete | 3 | 0 | 0 | 1 | 0 | 0 | 4 |

Last-run status in scope: spec 33/35 pass (14:17 outputs, before later code
changes; both failures re-verified read-only now); toolchain 19/22 (16:33);
upstream 16/25 (14:32, on a build two fixes older); determinism 4/8 at 16:30,
of which two failed only on their `NEEDS-ACCEPTANCE` line and were accepted at
16:47; bench 2/3; googletest 6/6 boxes per `7589866c` (the 13:35 log predates
the fix of two segfaulting boxes).

The short version: the runtime, toolchain and upstream checks are mostly
behavioural and good, several exemplary (`io-buffer`, `runtime-*` property
programs, `dialects-current`, the googletest boxes). The weak part is `spec/`:
about a third of it is grep and awk heuristics over source text that pin file
names, removed names and generator output, copy facts the code already holds,
and have false positives that were "fixed" on 2026-10-18 by loosening the
pattern or by rewriting the code to dodge it.

---

## 2. Verdict table

Status: `pass` / `fail: cause` / `unknown`, with the time of the run read
where it is not the latest.

### tests/spec

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| spec/build-preset | `make -n build` goes through `cmake --preset`/`--build --preset` and the pinned idris2, no direct ninja/compiler call | keep | a real contract checked on the Makefile's own dry run (behaviour, not text) — TBS 1.1 | pass |
| spec/commands | a hand list of 12 make targets exists in the Makefile; doctor names pinned cmake/ninja/llvm/sysroot | rewrite | the target list is a second copy of the Makefile's documented command block (RF one fact, one place); keep the doctor half, derive the targets from the Makefile's help header | pass |
| spec/configure-gate | CMakeLists.txt holds the exact line `string(JSON IDRIS_MLIR_<T>_SERIES GET ... accept)` per locked tool | rewrite | pins the implementation text, not the gate's behaviour; any refactor (a foreach) fails it — TBS 1.1; check behaviour: configure with a lock whose series excludes the tool and expect refusal | pass |
| spec/content-names | no C++/Idris source spells historical counter-suffix forms (`.lam`, `fn$ +`, `__idr_msg_`, `++ "'" ++ show`) | delete | a grep for past spellings cannot see a new counter; its own header says the behaviour is name-stability's — TBS 1.1/7 (wrong oracle), redundant | pass |
| spec/dialect-text | no FileCheck of pass-made module text outside asm/syntax/verify; no orphan check prefixes; planted witness first | keep | a real rule of the suite, self-tested by a planted witness (TBS 9.2 step 5: check the checker sees) | fail: 5 idr fixtures FileCheck module text (guards/fold-unguarded RUN 1, lower/match-lit RUN 3, rc/stack-cell RUN 3, returned/threaded RUN 3, stack/linear-box RUN 3) — the rule is right, the fixtures are other lanes' |
| spec/dialects-current | `tools/dialects.sh check` finds the Idris dialect modules current, finds a hand edit, finds all stale after a generator change | keep | mutation-tested generation check: one fact, one place enforced by behaviour (RF; TBS 7 second implementation = the generator) | pass |
| spec/doctor-without-idris-source | doctor reports a missing Idris checkout and exits 0 | keep | behaviour, exit status and message | pass |
| spec/driver-shape | 8 greps "as the representation wave left it": no `return failure(` outside Main.cpp, `"internal error: "` only in Outcome.cpp, cl::opt only in Options.cpp, `idris_rt_run_on_stack(` only in Stack.h, `"main"` only in Runtime.h, no registerAll | rewrite | a snapshot of an architecture pinned to file names (TBS 1.1: moving a function fails it); keep `no registerAll` and `cl::opt only in Options.cpp` as witnessed lint rules, drop the rest or make them types (RF "parse at the boundary") | pass |
| spec/emit-dialects | each generated `IdrisMLIR.Dialect.*` builds one contract dialect; no hand `MkOp` after `=`; no op/type name in string literals; a pinned list of 6 "not generated" ODS records | rewrite | the `=`-position awk parser is a heuristic (it flagged `"idr.refusals"` on 2026-10-18), and the exemption list is generator output copied into `expected` (RF one fact); enforce with Idris visibility/an import boundary | pass |
| spec/facts-in-types | no `discardableAttrs` in ODS but `idr.refusals`; no `DataOp`/`CtorOp`/`declarationOf`/`constructorOf` in C++ | rewrite-as-property | the AGENTS rule (no fact in a discardable attribute) is real, but `setAttr("idr.x", ...)` bypasses an ODS grep; state it as a universal property of every dump; the removed-name half is stale-legacy (TBS 1.1, RF delete what is dead) | pass |
| spec/failed-bootstrap | verify-pins refuses an idris2/llvm present without a provenance stamp | keep | behaviour | pass |
| spec/file-size | no C++ unit of foreign/idr or runtime over 400 lines but the shrink-only `allowed` list | keep | a stated house rule, shrink-only ratchet that fails on stale lines | fail: 7 units over 400 (IdrDialect.h 441, Expect.h 447, StaticData.cpp 405, Run.cpp 456, OpsCon.cpp 407, Expect/Arguments.cpp 470, Specialize.cpp 448; re-counted now) — the code's, not the test's |
| spec/frontend-imports | only IdrisMLIR.Frontend imports the fork; the fork imports no IdrisMLIR; tests that import the fork import nothing else of ours | keep | an AGENTS rule stated as a module-graph property; parsing `import` lines is crisp | pass |
| spec/idris-environment | `make env` ignores the caller's IDRIS2_* variables | keep | behaviour with a hostile environment | pass |
| spec/idris-pin | verify-pins: the Idris checkout is the staged gitlink | keep | behaviour | pass |
| spec/idris-pin-drift | a checkout at another commit is refused (git stand-in) | keep | behaviour, a planted failure | pass |
| spec/licenses | tools/licenses.sh: every file names its licence, ports are PINS.md's; prints the identifier set | keep | delegates to the one checker; the printed set is a deliberate review gate | pass |
| spec/lock | toolchain.lock.json schema 4 pins every tool (tests/Lock.idr) | keep | a typed checker of the lock (TBS 7 spec-as-checker) | pass |
| spec/mlir-layout | 19 lines: 4 presets, 6 exact CMake strings, no `-freflection`, lint uses stage-2 clang-tidy, no C++20 modules, add_mlir_library, a hand list of 12 CMakeLists dirs, no mutable statics | rewrite | a grab bag: exact-string CMake greps and a pinned directory list fail on innocuous change (TBS 1.1); split, check flags from `compile_commands.json`, move "no module"/"no mutable static" to clang-tidy or `zones` | pass |
| spec/no-behaviour-options | every cl::opt flag is in a hand `kept` list of 21; only `holds` among pass options; no DebugCounter registration | rewrite | the `kept` list is a second copy of the option set (RF one fact); give each option a cl::OptionCategory (input/output/resource/query) in the code and check the categories | pass |
| spec/no-erased-inputs | compiler/src names none of CExp/NamedCExp/ANF/VM/..., imports none of Compiler.CompileExpr/LambdaLift/...; planted witness | keep | an AGENTS rule; the import half is crisp, the name half is witnessed | pass |
| spec/no-fuel | a 200-line awk C++ loop parser: no counted loop, no maxIterations, no limit constant, no `while(changed)`, no `while(true)`; Idris: `%default total`, no covering/partial/assert_* but tools/policies.txt | rewrite | the C++ half is a heuristic parser (forced a code change in Specialize.cpp on 2026-10-18); keep the crisp tokens (iteration-limit APIs, `for(;;)`, `while(true)`) and the Idris half, fold `totality` into it — TBS 1.1/7 | pass |
| spec/no-local-headers | no header beside a .cpp in foreign/idr; repo includes only via include dirs, shrink-only `allowed` | keep | crisp layout rule with witnesses and a shrink-only ratchet | pass |
| spec/no-primitive-semantics | no `prim__*` call, no middle-end literal from a computed value, no pattern into a literal operand, in compiler/src | rewrite | parts 2–3 are an awk reading of Idris clauses with a known false positive (`LInt it 0`, "fixed" by skipping any argument); the behaviour is Fuzz's folded-vs-run oracle — keep part 1 only (TBS 7, 1.2) | pass |
| spec/pin-sites | every `PIN(name)` names a PINS.md entry or upstream bug; planted witness | keep | crisp, witnessed | pass |
| spec/pinned-test-tools | lit finds the pinned FileCheck/not/count first on PATH (stand-ins) | keep | behaviour of the harness | pass |
| spec/prelude-coverage | every prelude module has a `covers` fixture or a line of shrink-only `uncovered` | keep | coverage of the spec space read from the pin's ipkg (TBS 9.3), shrink-only | pass |
| spec/refusals-as-data | the phrase `unsupported (` is in a string of Attrs.cpp alone and of one Idris file; no Rule.idr | delete | pins a file name (Attrs.cpp), checks a removed file (Rule.idr), and its `expected` ("rendered nowhere") contradicts its own header ("one Idris file"); the rule enum is generated, and reject/rules-covered check refusals by data — RF, TBS 1.1 | pass |
| spec/rules-covered | every generated rule has a reject fixture or one reasoned line of without-fixture, never both | keep | a property of the suite over the generated rule list (TBS 9.3: aim at the spec's situations) | pass |
| spec/stale-stamps | verify-pins refuses missing/stale stamps and a Chez built with other patches | keep | behaviour with planted stamps | pass |
| spec/timeouts | a hanging step exits 124 and a hanging script is cut at the test limit | keep | the harness's own guarantee, tested with small limits | pass |
| spec/totality | no binder named fuel; no Z/S definition called with a numeral ≥16; each rule's category is one of three phrases; three lifted-limit test dirs exist | delete | the fuel heuristic flagged `bitsOf 63` (a Vect length) and the code was rewritten to dodge it; the category check copies the enum tblgen already enforces; the limits check tests that tests exist — TBS 1.1, RF one fact | pass |
| spec/upstream-patches | every upstream/<bug> has a README with a plan and a patch or a reason; patches apply alone and in order to the pinned sources | keep | AGENTS policy as data, and `git apply --check` behaviour | pass |
| spec/verifier-every-pass | nothing turns the verifier off (enableVerifier/verifyPasses(false), -verify-each=false) | keep | crisp tokens; its behavioural witness is unittests/Verify.cpp | pass |
| spec/zones | every C++ file is in a zone (path + extension) | keep | crisp; absorb mlir-layout's "no C++20 module" (a .cppm is already in no zone) | pass |

### tests/toolchain

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| toolchain/archive-check-bitcode | check-archive.sh reads both halves of a fat-LTO/embedded-bitcode member, ELF and Mach-O, carried and mixed | merge-into:tests/toolchain/runtime-archive-check | overlaps runtime-archive-check's clean/cxx/ctor members; one table (format × native × bitcode → verdict) — TBS 4.4, RF | pass |
| toolchain/big-cell | a large big's limbs are at word+16, 7 checks | rewrite | hard-codes the layout (`(uintptr_t)big + 16`) instead of `offsetof` from idris_rt.h (RF one fact); pins the check count "7 of 7" (TBS 1.1) | pass |
| toolchain/cpu-features-aarch64 | the AArch64 feature list: bits 0..n-1 under 64; FMV names map to LLVM names; Cpu.cpp compiles for arm64 macOS and calls the resolver | rewrite | compiles with its own invented flags (`-ffreestanding -nostdlibinc`), a copy of the build's that drifted; pins the count "features: 29" (TBS 1.1, RF) | fail: `Platform.h:25: 'string_view' file not found` under the test's `-nostdlibinc` (test drift, not code) |
| toolchain/executable-pages | every loaded segment is page-aligned for the target's page; Mach-O __PAGEZERO ≥ 4 GiB | keep | a property over the linked artifact, read from the format's headers | pass |
| toolchain/heap-region | the heap starts in one 4 GiB-aligned region and grows past it; all cells freed | keep | a property of the allocator, the AGENTS prefetcher requirement | pass |
| toolchain/io-buffer | output at IO buffer sizes 4 and 7 equals the default's, on boundary-heavy input | keep | exemplary: metamorphic oracle, and the buffer constant shrunk to move the bug into the box (TBS 8 small scope, 7 second implementation) | pass |
| toolchain/llvm-bootstrap | stage 2 installed every tool, the CMake packages, the recorded config, the triple's cfg and libc++ manifest | keep | checks the installed artifact | pass |
| toolchain/page-size-mismatch | a runtime built for another page size refuses to start and names both | keep | behaviour, planted mismatch both ways | pass |
| toolchain/runtime-api | rc.c's 101 checks (RC frees, odd words, CAF release, live cells); IDRIS_RT_LIVE settings; handles.c's per-handle results and errno table | keep | the runtime's documented semantics as the oracle (TBS 7); "101 of 101" count pin is low-grade brittleness (REPO-9) | pass |
| toolchain/runtime-archive-check | check-archive passes the runtime, fails cxx/ctor/blind members, both formats | keep | behaviour with planted bad members, including a "checked nothing" case (TBS 9.2 step 5) | pass |
| toolchain/runtime-bigs | 14 properties of runtime bigs against GMP over 20000 drawn cases and 2 boxes; class report | keep | second implementation (GMP), swarm, boxes, Good-Turing report (TBS 1.2, 5, 8) | pass |
| toolchain/runtime-container | --prepare-runtime is deterministic and keeps bitcode where the entry says; a hand-written idr module compiled against it runs, exit 28, 0 live cells | rewrite | its program is hand-written `idr` dialect text in a toolchain test; the dialect changed and the test went stale on an unrelated change (AGENTS, TBS 1.1) — compile an Idris fixture instead | fail: `sum.mlir:9:12: error: expected '(' in argument list` at `default {` (now `default(%d: i64)`); also carries NEEDS-ACCEPTANCE |
| toolchain/runtime-counting | RC properties over 10000 drawn cases | keep | property program (TBS 1.2) | pass |
| toolchain/runtime-doubles | show/read of doubles: shortest round-trip, strtod agreement, boxes | keep | spec-as-oracle and libc as second implementation | pass |
| toolchain/runtime-prepared | the prepared runtime behaves as the archive (rc.c 3 modes); flagless bitcode refused; every undefined symbol is in the target allowlist | keep | a reviewed external surface (allowlist) and a differential run | fail: the prepared runtime now needs `memcmp`, not in `allowed` (a real surface change; plus NEEDS-ACCEPTANCE) |
| toolchain/runtime-start | reserved stack depth, exhaustion message, exit status range, IDRIS_RT_STACK parsing, CPU refusal | keep | documented semantics, exit statuses | pass |
| toolchain/runtime-strings | string ops against a model, boxes over 3-scalar strings, ownership | keep | model oracle + exhaustive small box (TBS 8, 9) | pass |
| toolchain/runtime-text | integer text vs snprintf/GMP, a literal grammar, boxes | keep | second implementations + grammar generator (TBS 4) | pass |
| toolchain/runtime-triple | --prepare-runtime takes a member of the target's triple however spelled, refuses another vendor/environment | keep | behaviour; but the refusal is pinned as `internal error:` for a user-supplied input (REPO-25) | pass |
| toolchain/runtime-utf8 | UTF-8 decode vs a model and Unicode Table 3-7, boxes across block boundaries | keep | standard as oracle, small-scope boxes (TBS 8, 9) | pass |
| toolchain/stack-guard-page | the reserved stack's guard is rounded to pages and its fault exits as exhaustion | keep | behaviour at boundary sizes | pass |
| toolchain/static-linking | idris-mlir, idris-mlir-opt and one program need no shared library but the OS's | rewrite | a hand list of 3 of the build's executables; misses idris-mlir-reduce, idris-mlir-tblgen and the 6 idr-box-* programs (AGENTS: "our tools and programs"); derive the list from the build (RF one fact) | pass |
| toolchain/lib/ | prop.h, prop.sh, bigmodel.h, utf8model.h: helpers | n/a (infrastructure) | shared generator/report machinery; see REPO-16, REPO-17 | n/a |

### tests/upstream

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| upstream/bytecode-deferred-quadratic | patched mlir-opt reads 4× deeper bytecode in ≤8× time | keep | the bug is a complexity class; but wall-clock ratio is a hidden input (REPO-11, TBS 11) | pass |
| upstream/bytecode-unregistered-properties | unpatched bug still reproduces (bytecode read fails, text reads) | keep | crisp reproducer with "not this bug" guards | pass |
| upstream/composite-fixed-point-sccp | sccp does not converge under composite-fixed-point, canonicalize does | keep | crisp reproducer with a control | pass |
| upstream/constructor-implicit-mark | the fork accepts v1/v3 as covering; program runs | keep | reproducer of a fork fix; belongs in make test (REPO-12) | fail @14:32: `#idr.instance<"Builtin.Unit", >:1:30: error: expected '['` (fixed by 25f263da); unknown now |
| upstream/cse-statistic-assignment | CSE statistic is 3 under one and many threads | keep | crisp | pass |
| upstream/elaboration-primitive-folding | the fork keeps primitive calls on constants in the checked Core | keep | reads the .core print (low-grade brittle); a real fork contract | fail @14:32: same #idr.instance parse error; unknown now |
| upstream/erased-constant-pattern | quantity-0 constant patterns split; program prints 2 | keep | fork reproducer (REPO-12) | fail @14:32: #idr.instance; unknown now |
| upstream/erased-coverage-nested-match | erased definitions covering under %default total | keep | fork reproducer (REPO-12) | fail @14:32: #idr.instance; unknown now |
| upstream/evaluator-char-text | the fork computes a Char's text as the Char | keep | fork reproducer (REPO-12) | fail @14:32: #idr.instance; unknown now |
| upstream/forward-dataflow-callee-lookup | sccp over 4× functions in ≤8× time | keep | as bytecode-deferred-quadratic (REPO-11) | pass |
| upstream/inline-unreachable-terminator | inliner inlines a callee ending in ub.unreachable | keep | crisp | pass |
| upstream/int-range-narrowing-exactness | narrowing keeps remsi/remui at i64; remui of -2 by 7 folds to 0 | keep | crisp, semantic check of the folded value | pass |
| upstream/one-shot-module-function-interface | patch 24: 11 bufferization behaviours, 4 on `idr.func` programs | rewrite | the idr half is our dialect's test in an upstream reproducer, written in idr text that went stale; AGENTS: "reduce it to upstream dialects first" — move idr-call/idr-cycle to tests/idr | fail: `idr.func private @callee ... a function's visibility is not written` (fixture drift) + NEEDS-ACCEPTANCE |
| upstream/one-shot-tensor-like-copy | the unfixed bug is "still in the pinned source" | rewrite | greps `isa<TensorType>(operandType)` in BufferizableOpInterface.cpp: a text check, not the bug (TBS 7 wrong oracle); reproduce it on a tensor-like type that exists, or delete | pass |
| upstream/pass-timing-dynamic-pipeline | dynamic pipelines timed inside their pass | keep | reads the timing tree's structure, not times | pass |
| upstream/recursive-attribute-parser | 100k-deep attribute overflows 8 MiB, 1k does not | keep | crisp, with control | pass |
| upstream/relevant-implicit-split | fork: relevant index left to unification is covering | keep | fork reproducer (REPO-12) | fail @14:32: #idr.instance; unknown now |
| upstream/remove-dead-values-address-taken | unread operand becomes poison | keep | crisp | pass |
| upstream/remove-dead-values-poison-operand | unfixed: poison replaced, no convergence | keep | crisp | pass |
| upstream/remove-dead-values-unchanged-call | unfixed: call rebuilt, no convergence | keep | crisp, with "changes the module" guard | pass |
| upstream/remove-dead-values-unreachable | 4 inputs: dead values' uses take poison | keep | crisp | pass |
| upstream/sccp-revert-unset-property | unfixed: outer extui gains nneg, nothing else | keep | exact diff modulo the bug: the contract fully determines it (TBS 1.3) | pass |
| upstream/termination-closure | fork checks 25×240 functions within the step limit | keep | fork reproducer; a time bound by step limit (REPO-12) | fail @14:32: #idr.instance; unknown now |
| upstream/totality-unimported-callee | fork refuses caller via an unimported Loop.loop, accepts counted | keep | fork reproducer; greps Idris's English message (low) | fail @14:32: `internal error: 'builtin.module' op has "idr.refusals", which is an array of #idr.refusal on the top-level module alone` (dcafd452 "Refused programs report again"); unknown now |
| upstream/vectorize-precondition-body | vectorizer leaves both generics without vector code | keep | crisp; but runs `mlir-opt` without `bounded` (REPO-24) | pass |

### tests/determinism

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| determinism/hello | programs/basic/hello: every artifact and dump identical at 1/3/5/13 threads and a second process | delete | byte identity is the right oracle (TBS 1.3), but hello is subsumed by shapes/rbtree; fold into a parameterized corpus (REPO-18) | pass |
| determinism/leet-rotate | same, over linear lists | keep | as above; the linear library path | pass |
| determinism/name-stability | editing Main.step's body moves no symbol not made from Main.step, emitted and every step to lowering | keep | the real behaviour behind content-names; one hand edit today (REPO-18) | fail: at `symbol-dce`, `Main.main.lam.b3fe1b35bfddebff Main.main.lam.fcf07a71f74952cf` move (see §4) |
| determinism/rbtree | same, bench/rbtree | keep | data, specialization, TRMC, RC | pass (failed at 16:30 only on its NEEDS-ACCEPTANCE line; accepted 16:47, uncommitted) |
| determinism/shapes | same, programs/data/shapes | keep | | pass |
| determinism/threads-linarray-lanes | idr-pipeline under one thread vs pool: module, statistics, remarks identical; idr-narrow-lanes remarks | keep | the only one that checks remarks of a parallel function pass | fail: compile exit 1, `'linalg.generic' op consumes a view, which holds no reference ...` (code bug, §4) |
| determinism/threads-rbtree | same check on bench/rbtree | keep | | pass (as determinism/rbtree) |
| determinism/threads-shapes | same check on shapes | merge-into:tests/determinism/threads-rbtree | one parameterized `determinism_threads` over a corpus, not one directory per program (RF; REPO-18) | pass |

### tests/bench

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| bench/records | every bench/runs record's results.md and charts are what report.sh makes | keep | derived files regenerated and compared: one fact, one place (RF) | pass |
| bench/report | report.sh on a fixture: prints results.md, the fib/regex rows, best-of-2, three SVGs | keep | a golden of a deterministic tool on a fixed input: the contract fully determines it (TBS 1.3) | pass |
| bench/smoke | each of 26 benchmarks compiles and prints its recorded output on a small input | rewrite | one verdict for 26 programs hides how many fail (TBS 6 perception); 8 of them are compiled again by programs/* fixtures (REPO-20); parameterize per benchmark | fail: 14 of 26 (leaks, refusals, an internal error, a verifier error, a timeout; §4) |

### foreign/idr/unittests (make test-unit)

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| unittests/Constants.cpp | #idr.con has one form (get/getRun/walkFields) over lists to 64, trees, zig-zags; DataRemap names follow what a field becomes | keep | canonical-form property over a generated family (TBS 8 exhaust small) | pass (per 7589866c) |
| unittests/Cycles.cpp | CallCycles components, callees-first order, Escapes::recursive; a declaration is its own component | keep | properties of a cached analysis on a small program; counts are determined by it | pass |
| unittests/Flow.cpp | flow-edge rule: a bad model fails verification; read-back of part vs whole; external models keep the rule (7 models) | rewrite-as-property (ExternalModelsKeepTheRule) | the external-model case is a hand fixture plus `EXPECT_EQ(models, 7u)`; a model added for an op absent from the fixture is never checked — iterate the registered models (TBS 1.1, RF one fact) | pass |
| unittests/Hooks.cpp | range hooks of pred, nat_from_big, nat_to_big hold every member over every D64 interval, against the runtime | keep | exhaustive box with the runtime as oracle (TBS 7, 8) | pass (segfaulted at 13:35 before Scratch; fixed 7589866c) |
| unittests/HooksCompare.cpp | big.cmp's decided verdicts and big.to_int's ranges are sound against the runtime | keep | exhaustive box | pass |
| unittests/Identities.cpp | givesBackOf: a diverging call gives nothing back, a returning one gives its callee's | keep | two examples of a rule with two cases; small (low: example-should-be-property over generated call graphs) | pass |
| unittests/Labels.cpp | a parameter's point and block argument are one label node | keep | one example; low value but cheap | pass |
| unittests/Ranges.cpp | range rules (bounded, rangeOf, add, sub, mul, ofInteger, boundsOf, ofType) exhaustively over D64 / widths ≤ 4 against __int128 | keep | exemplary exhaustive box with exactness checks | pass |
| unittests/Sources.cpp | sourceOf on lin/field/match/borrow/share | keep | examples, determined by the contract | pass |
| unittests/Tagged.cpp | runtime small paths of arithmetic vs __int128 on boxB, through the ODS's op→entry binding | keep | box + binding check; its edge domain is a third copy (REPO-16) | pass |
| unittests/TaggedBits.cpp | bitwise ops and shifts vs infinite two's complement on boxB × amounts | keep | as Tagged | pass |
| unittests/Verify.cpp | the pass manager verifies a program between passes; the second pass never runs | keep | the behavioural witness of spec/verifier-every-pass | pass |
| unittests/Words.cpp | every big op's word op folds to the runtime's value; the versioning mask; fits32 | keep | box over the generated op list: a new op fails to compile until checked (RF generated table) | pass (segfaulted at 13:35; fixed 7589866c) |

### Directories with only a stale `output` (not tests)

| path | what it was | verdict | reason | status |
| --- | --- | --- | --- | --- |
| spec/cpp-starter | a removed spec (presets, C++26) | delete (the directory) | no `run`; ignored `output` left by a deleted test; confuses audits and `ls` | n/a |
| spec/module-links | removed with C++ modules | delete | as above | n/a |
| spec/time-trace | removed with the profiler cull | delete | as above | n/a |
| toolchain/arena-page | removed | delete | as above | n/a |
| toolchain/arena-page-boundary | removed | delete | as above | n/a |
| toolchain/double-print | removed | delete | as above | n/a |
| toolchain/module-imports | removed with C++ modules | delete | as above | n/a |
| toolchain/runtime-page-size | removed | delete | as above | n/a |
| upstream/clang-module-layout-forward-declaration | removed with C++ modules | delete | as above | n/a |

---

## 3. Findings

### REPO-1 — Source-text heuristics with false positives, "fixed" by loosening them or by changing the code
- **Category:** brittle-overspecified, wrong-or-missing-oracle. **Severity:** high.
- **Paths:** tests/spec/no-primitive-semantics, tests/spec/totality, tests/spec/no-fuel, tests/spec/emit-dialects.
- **Evidence.** `check.log` (13:57), the first run after the wave:
  - no-primitive-semantics: `primitive semantics in Idris: .../Translate/Primitives.idr:143: a literal made from a computed value (LInt): ... PrimApp loc (IntOp Sub it) Nothing [Literal loc (LInt it 0), x]`. That is a negation written as `0 - x` with a variable width `it`, not a computed literal.
  - totality: `compiler/src/IdrisMLIR/Frontend/Walk.idr:56: bitsOf 63, a count-down definition handed a budget`. `bitsOf : (d : Nat) -> Int -> Vect d Bool` is structural recursion on a Vect length, not fuel.
  - no-fuel: `foreign/idr/lib/Transforms/Specialize/Specialize.cpp:219: a loop that states no end`.
  - emit-dialects: `op names spelled by hand: 1 / compiler/src/IdrisMLIR/Emit.idr:103: "idr.refusals"`. That is an attribute name, not an op name.
  
  Commit `c4d0b26b` resolved them like this: `no-primitive-semantics: LInt's width may be a variable ... the check skips any one argument` (the regex went from `[A-Z][A-Za-z0-9]*` to `[A-Za-z_][A-Za-z0-9_]*`, so any one-word argument is now skipped). It also rewrote `bitsOf` as `bitsOf : {d : Nat} -> Int -> Vect d Bool` so the call site no longer has a numeral. Emit.idr was changed to `Idr.refusalsDiscardable`, and Specialize.cpp's loop was rewritten.
- **Guideline:** TBS 1.1. A brittle test fails for an innocuous reason, and each of these did. TBS 7: the "oracle" is a pattern over source text, not over the meaning. RF ("parse at the boundary") applies too: the awk scripts re-parse Idris and C++ by hand (`no-fuel/run` is 290 lines, much of it a C++ `for`-header parser) instead of asking a parser that already exists.
- **Recommendation.** Delete the heuristic halves:
  - no-primitive-semantics parts 2 and 3;
  - totality's fuel rule;
  - no-fuel's counted-loop and `words()`/`count_bound` analysis.

  Keep only crisp tokens: `prim__` calls with an allowlist; `maxIterations`/`setMaxIterations`/`maxNumRewrites`/`kNoLimit`; `for(;;)`/`while(true)`; `%default total`, `covering`/`partial`/`assert_*` against `tools/policies.txt`. Give each kept rule a planted witness, as dialect-text and pin-sites already do. The behaviour these heuristics stood in for already has better oracles:
  - Fuzz's folded-vs-run comparison catches an Idris-side primitive meaning;
  - Idris's own totality checker under `%default total` covers totality;
  - the step timeouts turn a non-terminating pass into a test failure.

### REPO-2 — Checks that copy a fact the code already enforces, or test that tests exist
- **Category:** redundant, cannot-fail. **Severity:** medium.
- **Paths:** tests/spec/totality (rules and limits), tests/spec/refusals-as-data.
- **Evidence:**
  - totality's `awk -F'\t' '$2 != "megamorphic" && $2 != "outside the language" && $2 != "user error"'`. idris-mlir-tblgen already refuses a rule without a category: `llvm::PrintFatalError(rules, "a rule's case names its category, and no other enum's case")` (idris-mlir-tblgen.cpp:3135). The check therefore fires only when a category is added or renamed. That happened once: c4d0b26b had to add `"user error"` to the test.
  - totality's limits: `[ -f "tests/$limit/run" ] && [ -f "tests/$limit/expected" ] || ...` for three directories that run in `make test` anyway.
  - refusals-as-data checks that `compiler/src/IdrisMLIR/Rule.idr` does not exist.
- **Guideline:** RF ("one fact, one place"; "delete what the representation makes dead in the same change"); TBS 1.1.
- **Recommendation:** delete totality and refusals-as-data. Fold totality's surviving Idris half into the rewritten no-fuel (REPO-1).

### REPO-3 — Removed names and historical spellings
- **Category:** stale-legacy. **Severity:** medium.
- **Paths:** tests/spec/facts-in-types, tests/spec/content-names, tests/spec/refusals-as-data, tests/spec/driver-shape.
- **Evidence:**
  - facts-in-types: `xargs grep -nwE 'declarationOf|constructorOf|DataOp|CtorOp'`. None of these exists any more (re-checked: no hits).
  - content-names greps the old suffix spellings `"\\.(la""m|del""ay|cap""ture|sp""ec|ra""ise)"` and `__idr_(msg|caf|box|str|big)_`.
  - driver-shape's header: "The driver's shape, as the representation wave left it".
- **Guideline:** TBS 1.1. A grep for yesterday's names cannot see tomorrow's counter or declaration op. RF: delete what is dead.
- **Recommendation:** delete content-names and the removed-name half of facts-in-types. Rewrite driver-shape (REPO-4). The behaviour content-names stood for is name-stability's, stated as a property (§5).

### REPO-4 — "One place" rules pinned to a file name, and exact CMake text
- **Category:** brittle-overspecified. **Severity:** medium.
- **Paths:** tests/spec/driver-shape, tests/spec/refusals-as-data, tests/spec/configure-gate, tests/spec/mlir-layout.
- **Evidence:**
  - driver-shape: `grep -v '/Outcome\.cpp:'`, `grep -v '/Support/Stack\.h:'`, `grep -v -e '/Support/Stack\.h:' -e '/unittests/Main\.cpp:'`, `grep -v '/include/idr/Conversion/Runtime\.h:'`.
  - refusals-as-data: `[ "$(cat "$work/cpp")" = foreign/idr/lib/IR/Attrs.cpp ]`.
  - configure-gate: `grep -qF "string(JSON IDRIS_MLIR_${upper}_SERIES GET \"\${IDRIS_MLIR_LOCK}\" $tool accept)"`.
  - mlir-layout: `for flag in 'set(CMAKE_CXX_STANDARD 26)' '-fno-exceptions -fno-rtti' '-Werror' ...`, plus a hand list of 12 CMakeLists directories (`for dir in "" include/idr include/idr/IR ...`).
- **Guideline:** TBS 1.1. Moving a function to a better file, or writing the CMake as a loop, fails the test with nothing wrong.
- **Recommendation:**
  - Where "one place" matters, make it a representation:
    - the options as one parsed struct handed down (then "none extern" cannot be written);
    - the entry symbol as one constant in a header, which the compiler resolves;
    - the internal-error prefix rendered by the printer's one function, so no string spells it.
  - Check configure-gate by behaviour: configure against a lock whose `accept` series excludes the pinned version, and expect the gate to refuse.
  - Check flags in `compile_commands.json`, i.e. the flags actually used.

### REPO-5 — refusals-as-data's expected contradicts its own rule
- **Category:** other (an expected file that accepts what the header calls wrong). **Severity:** medium.
- **Path:** tests/spec/refusals-as-data.
- **Evidence.** The header says: "So the phrase's opening is inside a string literal of one C++ file and of one Idris file". The expected file says `frontend: the refusal phrase rendered nowhere`. The script treats `0)` as a printed state rather than a failure.
- **Guideline:** TBS (preamble: "expected files are specifications"). A golden that records a state its own spec calls wrong is no specification.
- **Recommendation:** delete (REPO-2). If kept, the expected must be decided against the rule, not against the output.

### REPO-6 — Lists inside tests that copy data the code owns (ratchets that accrete)
- **Category:** harness-representation. **Severity:** high.
- **Paths:** tests/spec/no-behaviour-options, tests/spec/commands, tests/spec/emit-dialects, tests/toolchain/static-linking, the Makefile's `test-unit`.
- **Evidence:**
  - no-behaviour-options holds `kept='o c p package-path prefix no-prelude log-actions-tags runtime print-runtime ... report idr-contracts'`. Every new output option means an edit here.
  - commands holds `for target in bootstrap doctor verify-pins check build typecheck test test-idr test-mlir-tools test-unit compile bench`.
  - emit-dialects' expected copies the generator's `Omitted` lines (`-- attribute KeyConAttr: the passes' alone (idris = 0)`, written by idris-mlir-tblgen.cpp:2217). The list grew from 1 to 6 in c4d0b26b. Any new `idris = 0` record fails the test, so it is a third copy of an ODS fact.
  - static-linking: `for file in "$idris_mlir" "$idris_mlir_opt" "$program"`.
  - test-unit: `boxes=$(find .../unittests -maxdepth 1 -type f -name 'idr-box-*' ...)`. CMake already knows the list (`set(IDR_BOXES ranges hooks words tagged ir analyses)`), and a box that failed to build is simply not run.
- **Guideline:** RF ("one fact, one place"; "every string that names a thing is a missing type"); TBS 1.1.
- **Recommendation.** Move each list into the code and read it from there:
  - option categories as `cl::OptionCategory`, checked through `--help-list-hidden` or the registry;
  - the Makefile's documented command block parsed;
  - emit-dialects' exemption list dropped: the generator's `Omitted` reason already says why a record is not written;
  - the build's executables from its install manifest;
  - the box list from a CMake-generated file.

  The shrink-only ratchets (file-size, no-local-headers, prelude-coverage, tools/policies.txt's "still in its file") are sound and should stay. The accreting lists are the problem.

### REPO-7 — Rules a type or a module boundary could hold, kept as greps
- **Category:** harness-representation. **Severity:** medium.
- **Paths:** tests/spec/emit-dialects, tests/spec/facts-in-types, tests/spec/no-erased-inputs.
- **Evidence:**
  - emit-dialects decides "builds an op" by finding `MkOp` after the first `=` that is not `==`/`<=`/`>=`/`/=`, in awk over lexed lines.
  - facts-in-types greps `discardableAttrs` in .td files. C++ `op->setAttr("idr.foo", ...)` or Idris `attributes := [("idr.foo", ...)]` would bypass it; the second was how `idr.refusals` was first written.
- **Guideline:** RF ("make illegal states unrepresentable"; "parse at the boundary"). TBS 4.3: encode the harness's invariants as types.
- **Recommendation:**
  - Make `MkOp` constructible only through an internal module (`IdrisMLIR.MLIR.Internal`) that only `IdrisMLIR.Dialect.*` imports. "No hand-built op" then becomes an import rule, checked by the same module-graph check as frontend-imports.
  - State "no fact in a discardable attribute" as a universal property in `tests/lib/properties.sh`: no op of any dump carries an `idr.`-prefixed discardable attribute, and `idr.refusals` appears only on a module with no `idr.program`. It then holds of every compilation, not of one grep.

### REPO-8 — Hand-written dialect text and copied compile flags in tests that are not about them
- **Category:** stale-legacy, brittle-overspecified. **Severity:** high (two current failures).
- **Paths:**
  - tests/toolchain/runtime-container;
  - upstream/24-one-shot-module-function-interface/{idr-call,idr-cycle}.mlir, used by tests/upstream/one-shot-module-function-interface;
  - tests/toolchain/cpu-features-aarch64;
  - tests/toolchain/runtime-prepared (its flagless module is up to date today).
- **Evidence:**
  - runtime-container output: `sum.mlir:9:12: error: expected '(' in argument list / default {`. The dialect now writes `default(%d: i64) {`, as tests/idr/syntax does.
  - one-shot output: `error: custom op 'idr.func' a function's visibility is not written: its program's root is public, and every other function private / idr.func private @callee(...)`.
  - cpu-features compiles with `--target=... -std=c++26 -ffreestanding -nostdlibinc ...`, a set of flags no build uses, and fails with `Platform.h:25:10: fatal error: 'string_view' file not found`.
- **Guideline:** AGENTS ("A test that goes stale on an unrelated change was a bad test"); TBS 1.1; RF (one fact: the build's flags, the dialect's syntax).
- **Recommendation:**
  - runtime-container should compile an Idris fixture, e.g. a list sum, through `idris-mlir`, so the dialect is the compiler's business.
  - Move the idr half of one-shot-module-function-interface to `tests/idr/bufferize/`. AGENTS says to reduce an upstream bug to upstream dialects, and the upstream reproducer keeps only func/tensor.
  - cpu-features should take its flags from the build (the runtime's `c-flags` file, or `compile_commands.json` for `runtime/Platform/Aarch64/Cpu.cpp`).

### REPO-9 — Counts printed into transcripts
- **Category:** brittle-overspecified. **Severity:** low.
- **Paths:** tests/toolchain/cpu-features-aarch64 (`features: 29`), tests/toolchain/big-cell (`7 of 7 checks`), tests/toolchain/runtime-api/rc.c (`101 of 101 checks`), foreign/idr/unittests/Flow.cpp (`EXPECT_EQ(models, 7u)`).
- **Evidence:** adding a CPU feature, or one more check to rc.c, changes `expected` with nothing wrong. Flow's 7 is the number of ops in its own hand fixture.
- **Guideline:** TBS 1.1. The contract is "bits 0..n-1 under 64" and "every check holds", not n.
- **Recommendation:**
  - print `all N checks hold` only as `all checks hold`, and on failure the failing checks;
  - print the feature property without the count;
  - make Flow iterate the registered external models.

### REPO-10 — A reproducer that reads the source instead of running the bug
- **Category:** wrong-or-missing-oracle. **Severity:** medium.
- **Path:** tests/upstream/one-shot-tensor-like-copy.
- **Evidence:** `awk '/resolveTensorOpOperandConflicts\(/ { inside = 1 } inside && /isa<TensorType>\(operandType\)/ { found = 1 } ...' "$source"`. The header says: "Its reproducer needs the test dialect's tensor-like type, which the toolchain's mlir-opt does not build".
- **Guideline:** TBS 7. A text check passes against a fix that keeps that line, and fails on a reformatting that keeps the bug. It checks neither the bug nor its fix.
- **Recommendation:** reproduce the bug on a tensor-like type that exists: an `idr` type, if one implements `TensorLikeType`, through idris-mlir-opt; or build mlir-opt's test dialect into the toolchain (the bootstrap's choice). Otherwise delete the test and keep the report's text.

### REPO-11 — Wall-clock ratios as oracles
- **Category:** perception (a hidden input). **Severity:** medium.
- **Paths:** tests/upstream/bytecode-deferred-quadratic, tests/upstream/forward-dataflow-callee-lookup.
- **Evidence:** `if [ "$large" -le $((small * 8)) ]`, with each depth's time `the best of three reads, so that the load of other tests does not decide the ratio`. The pool runs tests in parallel (`xargs -P`).
- **Guideline:** TBS 11. Machine load is an input the test does not control; a heavily loaded `make test-mlir-tools -j` can push a linear run past 8×.
- **Recommendation:** measure the work, not the time, where the tool can count it (a pass statistic, or an instrumented count in the patch's own upstream test). Failing that, make the ratio test sequential (`threads=1` for that pool) and record its numbers in the transcript-free report, so a near-miss is visible before it fails.

### REPO-12 — Fork reproducers run only in `make test-mlir-tools`
- **Category:** infrastructure-gap. **Severity:** medium.
- **Paths:** tests/upstream/{constructor-implicit-mark, elaboration-primitive-folding, erased-constant-pattern, erased-coverage-nested-match, evaluator-char-text, relevant-implicit-split, termination-closure, totality-unimported-callee}.
- **Evidence:**
  - each runs `profile_accept .` or `compile_program`, so it needs the compiler, not just the MLIR tools;
  - Main.idr places them in `("test-mlir-tools", ... pool "upstream: ..." ["upstream"])`;
  - AGENTS runs `make test-mlir-tools` only "After changing MLIR usage".
- **Guideline:** TBS 8 (a test that is not run finds nothing); RF ("one thing, one representation": the upstream/ pool mixes two kinds of test).
- **Recommendation:** run the fork reproducers in `make test`: a pool `upstream-fork`, or move them under `tests/accept` with a pointer from the bug's README. Keep the MLIR-tool reproducers in `test-mlir-tools`.

### REPO-13 — static-linking does not check every executable
- **Category:** infrastructure-gap. **Severity:** medium.
- **Path:** tests/toolchain/static-linking.
- **Evidence:** it checks three files. The build also makes `idris-mlir-reduce`, `idris-mlir-tblgen` and six `idr-box-*` programs (`ls build/dev/foreign/idr`, `.../unittests`). AGENTS says `tests/toolchain/static-linking` "checks our tools and programs".
- **Guideline:** RF (one fact: the build's executables); TBS 9.3 (aim at the situations the spec names).
- **Recommendation:** check every executable under the build tree (or its install manifest) except `idris-mlir-front`, the host side AGENTS excepts.

### REPO-14 — The googletest boxes are outside the runner
- **Category:** infrastructure-gap. **Severity:** low.
- **Path:** Makefile `test-unit`, foreign/idr/unittests/CMakeLists.txt.
- **Evidence:**
  - the boxes run by `find` (REPO-6);
  - they give no verdict in the runner's `N/M tests successful`;
  - the 13:35 log shows two boxes segfaulting (`Segmentation fault: 11 ... idr-box-hooks`, `idr-box-words`) unseen by any pool;
  - Main.cpp still carries `NEEDS-ACCEPTANCE: ... on both targets`.
- **Guideline:** TBS 6 (perception: what the suite counts as progress).
- **Recommendation:** add a `unit` pool whose entries are `IDR_BOXES` from a generated list, each box one test.

### REPO-15 — Two tests of check-archive.sh
- **Category:** redundant. **Severity:** low.
- **Paths:** tests/toolchain/archive-check-bitcode, tests/toolchain/runtime-archive-check.
- **Evidence:** both build `clean`/`cxx`/`ctor` members for x86-64 Mach-O and run `runtime/check-archive.sh` with `__mod_init_func __mod_term_func __init_offsets`. The bitcode one adds carried and mixed members.
- **Guideline:** RF (one fact, one place); TBS 4.4 (name every case).
- **Recommendation:** one test, one table: format × native half × bitcode half (clean, cxx, ctor, absent) × the expected verdict, plus the build's own runtime and the "blind" case.

### REPO-16 — Three definitions of the bigs' edge values, two oracles over the same small paths
- **Category:** redundant (RF). **Severity:** low.
- **Paths:**
  - foreign/idr/include/idr/Testing/Box.h (`boxB()`);
  - tests/toolchain/lib/bigmodel.h (families "the small range's edges", "just past them, and the machine words' edges");
  - tests/toolchain/runtime-bigs/bigs.cpp (`constexpr Edge edges[] = {{-1, 62, -1}, ...}`);
  - unittests Tagged/TaggedBits next to runtime-bigs' `box: every pair of edge values, every operation`.
- **Guideline:** RF ("one fact, one place"); TBS 1.2 (matklad's alphabet drawn from one place).
- **Recommendation:** one header of edge values, shared by the boxes and the property programs. Tagged/TaggedBits keep the part only they check (the ODS op → runtime entry binding, `Abi<Op>::function`). runtime-bigs keeps GMP as its oracle.

### REPO-17 — Runtime property programs: a fixed seed, and coarse classes
- **Category:** distribution, perception. **Severity:** medium.
- **Paths:** tests/toolchain/runtime-{bigs,counting,doubles,strings,text,utf8}, tests/toolchain/lib/prop.h.
- **Evidence:**
  - every run is `--seed 1 --cases N`, with a "Debt" comment on N;
  - every report shows `f1=0 f1/n=0.0000` with 3–8 classes such as `large small large: 3733`.
- **Guideline:** TBS 5 (swarm, randomize per run); TBS 8 (f1/n measures the pair of generator and features). TBS 6.2's table: with features this coarse the estimate saturates after a handful of inputs, so f1=0 says the classes are exhausted, not that the search is.
- **Recommendation.** Keep seed 1 for the transcript, since the transcript must be deterministic. Then:
  - add a `make fuzz-runtime` (or a seed taken from the date and printed in the report) that runs fresh seeds;
  - refine classes to (operation, operand classes, result class, which path ran);
  - keep the report as the perception record.

### REPO-18 — Determinism and name stability over a handful of fixed programs
- **Category:** example-should-be-property, distribution. **Severity:** medium.
- **Paths:** tests/determinism/*.
- **Evidence:**
  - four `determinism <fixture>` directories (hello, leet-rotate, rbtree, shapes), each compiling five times;
  - three `determinism_threads` directories;
  - one hand edit in name-stability (`step x = x * 3 + 1` vs `x * 5 + 2`).
- **Guideline:** TBS 1.1 (byte identity is the right assertion for determinism: the contract fully determines it); TBS 5/8 (but the inputs are four programs chosen by hand); RF (a directory per program is a list kept as directories).
- **Recommendation:**
  - Make determinism a parameterized entry over a corpus read from data: the bench list, plus Fuzz programs by seed, as `programs/semantics/prim@<name>` does.
  - Randomize the thread counts per run (swarm over {1, 2, 3, 5, 13, cores}).
  - Make name-stability generated: take a Fuzz program, edit one definition's body, and require every moved symbol to be owned by it.
  - Delete hello; merge threads-shapes into the parameterized threads check.

### REPO-19 — One transcript, many checks: one failure hides the rest
- **Category:** perception, harness-representation. **Severity:** medium.
- **Paths:** tests/bench/smoke (26 benchmarks, one verdict), tests/spec/mlir-layout (19 rules), tests/spec/driver-shape (8), tests/spec/emit-dialects.
- **Evidence:** bench/smoke's single FAILURE carries 14 distinct failures (§4). The runner counts it as one of 542.
- **Guideline:** TBS 6.2 (choose features so progress is visible). RF ("a switch on a tag is a polymorphism not yet named": the runner already has `Instance dir parameter`).
- **Recommendation:** parameterize bench/smoke as `bench/smoke@<name>` from the `bench/` listing, and split the multi-rule specs, one rule per entry with its witness.

### REPO-20 — The same benchmark compiled by three pools
- **Category:** redundant. **Severity:** low.
- **Paths:** tests/bench/smoke; tests/programs/{arrays/ioarray-fannkuch, arrays/linarray-fannkuch, arrays/linarray-qsort, arrays/linarray-unionfind, arrays/linarray-spectral-norm, data/pidigits, data/rbtree, data/cfold, io/mandelbrot-pbm}, whose run scripts build `bench/<name>`; tests/determinism/{rbtree,threads-rbtree}.
- **Guideline:** RF (one fact, one place).
- **Recommendation:** one home per benchmark. The programs/ fixture adds the dumps, the universal check and `mlir.expect`. bench/smoke@name then only asserts what programs/ does not (the recorded output on the smoke input), or programs/ fixtures are generated from bench/.

### REPO-21 — The `NEEDS-ACCEPTANCE` mark makes "unreviewed" look like "failing"
- **Category:** harness-representation. **Severity:** low (machinery lane's, seen here).
- **Paths:**
  - tests/determinism/rbtree and threads-rbtree: failed at 16:30 only on their mark, as `Given:` equals `Expected:` less line 1 in test.log 7281–7304;
  - tests/toolchain/runtime-container and runtime-prepared;
  - tests/upstream/*;
  - tests/bench/smoke;
  - foreign/idr/unittests/Main.cpp;
  - tests/ACCEPTANCE.md, "the tree's own list ... as it stood on 2026-10-18".
- **Guideline:** RF (a flag inside a golden is a second state with no type; ACCEPTANCE.md is a copy of a grep); TBS 6.
- **Recommendation:** make "owed acceptance" a distinct verdict of the runner (pass, fail, unreviewed), read from a mark file beside `expected`, and generate ACCEPTANCE.md or delete it.

### REPO-22 — Property programs rewrite tracked files on every run
- **Category:** other (harness hygiene). **Severity:** low.
- **Path:** tests/toolchain/lib/prop.sh (`--report "$here/report"`); tests/toolchain/runtime-*/report are tracked by git.
- **Evidence:** `git ls-files tests/toolchain | grep report` lists six reports. A run with another seed or case count dirties the tree.
- **Guideline:** RF (the report is derived data).
- **Recommendation:** write reports beside `output` (ignored), and keep a committed report only when a person accepts it, as bench/runs does.

### REPO-23 — Stale directories with only `output`
- **Category:** stale-legacy. **Severity:** low.
- **Paths:** the 9 directories at the end of the table.
- **Evidence:**
  - `tests/toolchain/module-imports/output`: `an implementation unit that imports a library its library does not link: does not build / fatal error: module 'idr.a' not found`, from a C++-modules era that is gone;
  - `tests/spec/time-trace/output`: `the culled profiler: no mention outside proposals`.
- **Recommendation:** remove them (`git clean -X tests/` of ignored outputs, or delete the directories). Optionally make the runner, or `make check`, report a test directory without `run`.

### REPO-24 — An unbounded command
- **Category:** other (AGENTS). **Severity:** low.
- **Path:** tests/upstream/vectorize-precondition-body.
- **Evidence:** `"$llvm_bin/mlir-opt" "$root/upstream/04-vectorize-precondition-body/body.mlir" --transform-interpreter > ...`, with no `bounded`. AGENTS: "Every command a test runs times out". Only the script-level limit would catch a hang, with a worse message.
- **Recommendation:** `bounded "$llvm_bin/mlir-opt" ...`.

### REPO-25 — A wrong user input reported as an internal error
- **Category:** other (possible code issue). **Severity:** low.
- **Path:** tests/toolchain/runtime-triple.
- **Evidence:** expected `| idris-mlir: internal error: runtime member vendor.o is compiled for TRIPLE, and programs for TARGET`. The member came from `--runtime=`, the user's input.
- **Guideline:** AGENTS ("Reject ... with an explicit error that names the reason"); the driver's verdict fold (driver-shape).
- **Recommendation:** decide the driver's category for a bad `--runtime`. If it is the user's, the message is a diagnostic, not "internal error", and the expected changes with it.

### REPO-26 — Real failures the tests caught (see §4)
- **Category:** code-bug-revealed. **Severity:** high.
- **Paths:** tests/bench/smoke, tests/determinism/threads-linarray-lanes, tests/determinism/name-stability, tests/toolchain/runtime-prepared, tests/spec/file-size, tests/spec/dialect-text.
- **Recommendation:** fix the code (or, for dialect-text, the idr fixtures). These tests are right.

### REPO-27 — Overlapping layout rules
- **Category:** redundant. **Severity:** low.
- **Paths:** tests/spec/mlir-layout, tests/spec/zones, tests/spec/no-local-headers.
- **Evidence:** mlir-layout's `no C++20 module under foreign/idr` (`.cppm` files and `module;`/`import` declarations) and zones' ".cppm is in no zone" state the same rule. All three walk the same C++ tree with different prune lists (`-name build -prune` vs `\( -name third_party -o -name build -o -name sources -o -name upstream -o -name '.?*' \) -prune`).
- **Guideline:** RF (one fact, one place).
- **Recommendation:** one layout spec, with one file walk and one table of zones, each zone carrying its extensions and include rules.

---

## 4. Code bugs the tests reveal

Only what an output shows. Each test's expectation is right, and the failure is the compiler's or the runtime's.

1. **Reference-count leaks on benchmark programs** (tests/bench/smoke, 15:53 and 16:43 logs). Each of these runs exits 0 and reports live cells on stderr at exit:

   | benchmark | live cells |
   | --- | --- |
   | binary-trees | 63 |
   | deriv | 1750 |
   | fannkuch-redux | 3 |
   | fasta | 593 |
   | fasta-redux | 595 |
   | mandelbrot-pbm | 1 |
   | pidigits | 90 |
   | reverse-complement | 6 |

   Reading: cells released on some path are not decremented after the counting changes (`3d279eb9` "Counting grades only what holds references", `9696ecc5` unpack releases). deriv and fasta leak in the hundreds to thousands, so this is a per-iteration leak, not a constant.
2. **Monomorphic programs refused as megamorphic** (bench/smoke): `idris-mlir: unsupported (polymorphism): Builtin.DPair.(#): a shape whose rank no analysis fixes: [__]`, and the same for `Linear.Notation.MkBang`, `PrimIO.MkIORes` and `Builtin.MkPair`, in fannkuch-linear, k-nucleotide, qsort, spectral-norm-linear and unionfind. These are prelude/linear constructors at fixed types. AGENTS says such programs compile. Reading: the rank/growth analysis treats a constructor of a dependent pair or a world-carrying result as a growing shape (`[__]` is an unknown rank). The same message family shows in tests/accept failures (other lane).
3. **Lowering type mismatch** (bench/smoke nqueens): `internal error: 'llvm.call' op operand type mismatch: expected operand type 'i64', but provided '!llvm.ptr' for operand number 0`. A runtime call's ABI (Abi<Op> from the ODS) and the lowered value's type disagree: a boxed value is passed where the entry takes a word, or the reverse.
4. **idr-rc-exclusive verifier failure** (bench/smoke regex-redux): `'idr.yield' op idr-rc-exclusive: gives a value of '!idr.own<!idr.box<...List[Char]...>>' where the solver proved '!idr.excl<...>'`. The exclusivity solve and the grade written on a match's yield disagree, at `go : List Char -> List Char -> List Char` and `parseAlts`.
5. **A benchmark no longer ends on its small input** (bench/smoke spectral-norm): `exit 124 / timed out after 60s: prog`. A performance cliff or non-termination after the wave. Unknown which; spectral-norm-linear is refused (item 2), so the two cannot be compared.
6. **RC over linalg views** (tests/determinism/threads-linarray-lanes): `Main.idr:53:1: error: 'linalg.generic' op consumes a view, which holds no reference; a reference of its own (idr.dup) is consumed, and an owned value's is given to a store (idr.own.give)`. The verifier of the owned stage refuses what the counting pass produced for a vectorized loop. That is a counting bug in front of `linalg.generic`, not a determinism bug.
7. **Names moved by an unrelated edit** (tests/determinism/name-stability), uncertain: `steps up to lowering: symbols moved by an edit of Main.step: symbol-dce: Main.main.lam.b3fe1b35bfddebff Main.main.lam.fcf07a71f74952cf`. The emitted module and the earlier steps keep every name; only the late step shows two `Main.main` lambdas with new hashes. Two readings:
   - (a) a closure of `step` passed to `twice`/`sumWith` is lifted into a lambda owned by `main` whose content key includes the inlined body of `step`, so its name legitimately moves, and the test's ownership model (the owner's prefix) is too strict;
   - (b) the key is taken after inlining, where it should be taken over what the lambda names, which is a naming bug.

   Deciding it needs the dumps. Both readings mean the content key of a lifted lambda needs a stated rule.
8. **The runtime needs `memcmp`** (tests/toolchain/runtime-prepared): `the prepared runtime needs what its target's allowlist does not allow: memcmp`. The wave introduced a call; `runtime/Platform/Platform.h` now includes `<string_view>`, and string_view comparisons compile to memcmp. `memcmp` is ISO C, so the likely resolution is a line in `allowed`. Even so, the test did its job: the runtime's external surface changed without review.
9. **Repository rules the wave broke** (the specs are right):
   - spec/file-size: 7 units grew past 400 lines (listed in §2);
   - spec/dialect-text: 5 idr fixtures FileCheck module text.
10. **Fixed since the last run of their tests**, for the record (tests/upstream at 14:32):
    - `#idr.instance<"Builtin.Unit", >:1:30: error: expected '['`: the attribute printed an empty argument list that its parser refuses, a print/parse round-trip bug. Fixed by `25f263da` ("#idr.instance in brackets"); the 16:43 `make test` log has no such line.
    - `internal error: 'builtin.module' op has "idr.refusals", which is an array of #idr.refusal on the top-level module alone`: a refused program could not report. `dcafd452` ("Refused programs report again").
    - Two googletest boxes segfaulted because `OpBuilder::atBlockEnd` on a lone block has no context. Fixed by `7589866c`.

    Their tests should be re-run before their status is believed.

Not code bugs, though they fail: toolchain/cpu-features-aarch64, toolchain/runtime-container and upstream/one-shot-module-function-interface fail on test drift (REPO-8).

---

## 5. What this scope looks like rebuilt

**spec/ → a small set of crisp rules, each a row of data with a witness.** One
`spec/rules` table (or one directory per rule generated from it), each row:
- the rule's name and the AGENTS/RF sentence it states;
- the matcher: an import edge, a token in lexed code, a declaration in ODS, a file zone;
- a planted witness that must fire;
- a shrink-only allowlist where the rule has exceptions, each with a reason.

dialect-text, pin-sites and no-erased-inputs already have this shape. What is left:
- **Module-graph rules** (one checker over parsed `import` lines): frontend/fork; `MLIR.Internal` only from `Dialect.*`, replacing emit-dialects' `=` parser; the fork's erased-form modules from nothing.
- **Token rules** (lexed): `prim__` with its allowlist; the iteration-limit APIs; `for(;;)`/`while(true)`; `%default total` and `covering`/`partial`/`assert_*` against `tools/policies.txt`; nothing turns the verifier off; no `registerAll`; no `cl::opt` outside the options unit.
- **Layout rules** (one walk): zones with extensions, headers, no modules, file size (shrink-only).
- **Pin and policy rules:** pin-sites, upstream-patches, lock, licenses, stale-stamps, idris-pin(-drift), failed-bootstrap, idris-environment, timeouts, pinned-test-tools, rules-covered, prelude-coverage, dialects-current. These are already behavioural.

Gone: content-names, refusals-as-data, totality, the heuristic halves of
no-fuel and no-primitive-semantics, driver-shape's file pins, configure-gate's
text pin (replaced by a configure run), mlir-layout's CMake strings (replaced by
`compile_commands.json`), and every list that copies the code's data (REPO-6).

**Universal properties instead of greps** (tests/lib/properties.sh, on every compilation's dumps):
- no `idr.*` discardable attribute but `idr.refusals` on a program-less module (facts-in-types);
- live cells 0 at exit (already the e2e check);
- for a sampled fraction of compilations, a second compilation at another thread count gives the same bytes (determinism as a property of the suite, not of four directories).

**Determinism and names, searched:**
- `determinism@<program>` over a corpus read from data: bench/ plus Fuzz seeds;
- thread counts drawn per run;
- `names@<seed>`: a Fuzz program, one definition's body mutated, and every symbol that moves owned by it. That needs §4.7's rule for lifted lambdas written down first.

The oracle stays byte identity (TBS 1.3). The distribution becomes swarm over programs and thread counts (TBS 5).

**toolchain/:**
- check-archive as one table-driven test (REPO-15);
- static-linking over every built executable (REPO-13);
- runtime-container compiling an Idris fixture (REPO-8);
- cpu-features with the build's flags and no count (REPO-8, REPO-9);
- big-cell reading the layout through `offsetof` (or folded into runtime-bigs as one more property: "a large big's limbs are where idris_rt.h's struct says");
- the property programs: seed 1 in the transcript, rotating seeds in a separate target, finer classes, one shared edge-value header with the googletest boxes (REPO-16, REPO-17).

io-buffer, heap-region, page-size-mismatch, stack-guard-page, runtime-start, runtime-api and executable-pages stay as they are. io-buffer is the template for others: a constant of the implementation shrunk so its boundaries come into the box, with the default build as the other side of a metamorphic relation.

**upstream/:**
- MLIR reproducers in upstream dialects only, with idr cases moved to tests/idr;
- fork reproducers in `make test` (REPO-12);
- the source-grep reproducer replaced by a run or deleted (REPO-10);
- time ratios replaced by counts where the tool can count, otherwise run serially (REPO-11);
- every command bounded.

**bench/:** records and report as they are; smoke parameterized per benchmark, with one home per benchmark shared with programs/ (REPO-19, REPO-20).

**googletest boxes:** a runner pool from the CMake box list (REPO-14). Flow's external models iterated from the registry. The exhaustive boxes (Ranges, Hooks, HooksCompare, Words, Tagged, TaggedBits, Constants) are the best tests in this scope and the model for the rest: a reduced domain exhausted, an exact oracle (__int128, the runtime, MLIR's folder), and a generated op list, so a new op cannot go unchecked.
