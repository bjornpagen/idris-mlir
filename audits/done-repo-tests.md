<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Lane repo-tests: done

Scope: `tests/spec`, `tests/toolchain` (with `tests/toolchain/lib`),
`tests/upstream`, `tests/determinism`, `tests/fuzz`, `tests/bench`, and
the googletest boxes in `foreign/idr/unittests`. No compiler code was
changed, and nothing was built with ninja or cmake. Each googletest box I
changed was compiled and linked by hand into the scratchpad, from the
build's own compile and link commands, and run there. Every other test was
run through the runner or with the Makefile's environment. All runs were
on arm64 macOS; nothing here has run on x86_64 Linux.

## Deleted

| path | reason |
| --- | --- |
| tests/spec/content-names | greps for counter spellings that no longer exist; it cannot see a new counter. The behaviour is name-stability's |
| tests/spec/refusals-as-data | pins a file name (Attrs.cpp) and checks that a removed file (Rule.idr) is absent; its expected contradicted its own header |
| tests/spec/totality | its fuel heuristic had false positives that were dodged in the code; its category check copies tblgen's own check; its limits check only tested that three tests exist |
| tests/determinism/hello | duplicate (SUMMARY §3.7 item 5) |
| tests/determinism/leet-rotate | its fixture, tests/programs/linear/leet-rotate, was deleted by the programs lane, so it could not run. The parameterized corpus replaces it (below) |
| tests/determinism/threads-shapes | the same threads check as threads-rbtree on another program, in a second directory (merge verdict; SUMMARY §3.7 item 7 deletes it in the end) |
| tests/toolchain/archive-check-bitcode | merged into runtime-archive-check (below) |
| tests/upstream/one-shot-tensor-like-copy | greps the pinned source for `isa<TensorType>(operandType)`. That checks neither the bug nor a fix, and no tensor-like type outside the test dialect exists to reproduce the bug |
| tests/fuzz/seed-1, tests/fuzz/seed-2 | merged into tests/fuzz/seeds |
| tests/toolchain/runtime-{bigs,counting,doubles,strings,text,utf8}/report | derived output that every run rewrote in the tree; spec/licenses failed on them |
| foreign/idr/unittests/Tagged.cpp, TaggedBits.cpp | the same contract as runtime-bigs, held in a second harness. runtime-bigs now boxes the same values and amounts (below). The `tagged` box is gone from IDR_BOXES |
| the RUN-less, output-only directories: spec/{cpp-starter,module-links,time-trace}, toolchain/{arena-page,arena-page-boundary,double-print,module-imports,runtime-page-size}, upstream/clang-module-layout-forward-declaration | litter left by deleted tests |
| the idr half of tests/upstream/one-shot-module-function-interface (idr-call, idr-cycle) | our dialect's test inside an upstream reproducer, in stale idr text. AGENTS says reproducers use upstream dialects only |
| the NEEDS-ACCEPTANCE marks of toolchain/runtime-container, runtime-prepared, the 8 upstream fork reproducers, one-shot-module-function-interface, fuzz/two-hosts, fuzz seeds, bench/smoke and unittests/Main.cpp | each test now passes, or fails only on a listed code bug |

## Rewritten

- **spec/commands**: reads the commands from the Makefile's documented
  header instead of a hand list of 12 targets. Every documented `make X`
  must be a target. Every `make X` that AGENTS.md names must be documented.
  A planted header line is the witness that the check sees.
- **spec/configure-gate**: checks behaviour, not CMake text. It configures
  the real top-level CMakeLists.txt beside the real lock, and the gate must
  pass. Then it configures once per locked tool with that tool's `accept`
  set to `0.0`, and the gate must refuse and name `0.0.x`. It runs in about
  2 s.
- **spec/driver-shape**: down to two token rules, each with a planted unit:
  no `cl::opt`/`cl::list` outside Options.cpp in lib/Driver, and no
  `registerAll*`. The six file-name pins are gone.
- **spec/emit-dialects**: the `=`-position awk parser and the copied
  `Omitted` list are gone. The string rule is now crisp: no literal in the
  Emit modules starts with a contract dialect's `<dialect>.`, and no
  `!d.`/`#d.` literal appears outside Syntax and Dialect. A planted module
  is the witness. "No sum found" is now a failure, not a vacuous pass.
- **spec/facts-in-types**: the removed-name half is gone. The ODS rule
  remains, with a planted declaration.
- **spec/mlir-layout**: keeps lint-with-stage-2-clang-tidy,
  add_mlir_library, and no mutable statics. The hand preset list, the
  exact CMake strings, the -freflection grep and the 12-directory list are
  gone. "No C++20 module" moved to spec/zones (with a witness). The
  compile flags moved to a new **toolchain/language-profile**, which reads
  build/dev/compile_commands.json: every foreign/idr and runtime C++ unit
  is compiled with -std=c++26, -fno-exceptions, -fno-rtti and -Werror, and
  none with -freflection.
- **spec/no-fuel**: only crisp tokens remain: iteration-limit APIs and
  `for(;;)`/`while(true)`, with a planted C++ witness, plus the Idris half
  (`%default total`, covering/partial, assert_*) with a planted module. The
  200-line counted-loop parser, the named-constant word heuristic and the
  `while(changed)` name heuristic are gone.
- **spec/no-primitive-semantics**: part 1 only (`prim__` calls), with a
  shrink-only allowlist: an entry that allows nothing is stale and fails.
  The four part 2/3 entries are gone.
- **toolchain/runtime-archive-check**: one table, merged with
  archive-check-bitcode. Each row is a format, the spellings it is read
  with, how the member is made (plain, carried bitcode, mixed native and
  bitcode, arm64 embedded), its source, and the verdict owed: exit status
  plus the name the report must hold. The report's prose is not pinned, so
  expected.macos is gone and one expected holds on both hosts.
- **toolchain/big-cell**: the limbs are read through `idris_rt_bignum`
  (`+ 1` on the struct), not `+ 16`. It prints no check count, and on a
  failure it names each failing check on stdout.
- **toolchain/runtime-api/rc.c**: no "101 of 101". It prints "every check
  holds", or the number that fail.
- **toolchain/cpu-features-aarch64**: the Cpu.cpp compile with invented
  flags is gone, and so is the count line. The build compiles Cpu.cpp with
  its real flags, and runtime-start runs it.
- **toolchain/runtime-container**: compiles an Idris fixture (Main.idr,
  which sums a recursively built list and prints 28) against each runtime,
  instead of hand-written idr text.
- **toolchain/runtime-prepared**: `memcmp` added to `allowed` (SUMMARY §8).
  The flagless-bitcode refusal now compiles an Idris fixture and checks
  that the refusal names the file, not its wording.
- **toolchain/runtime-triple**: checks that a refusal names the member, its
  triple and the target's. The `internal error:` prefix is no longer
  pinned, since it bakes in §5 item 36.
- **toolchain/static-linking**: every executable file of an object format
  under build/dev, plus a linked program, instead of a hand list of three.
- **toolchain/lib/prop.sh** and **prop.h**: reports go to the work
  directory, not the tree.
- **toolchain/runtime-bigs**: the edge box is now every integer within 2
  of 0 or of ±2^k for k ≤ 64 (631 values, about 398k pairs, every
  operation). The shift box is every edge by [-130, 130], ±2^k and
  ±(2^k+1) for k in [8, 61], and ±(2^62-1). This absorbs
  Tagged/TaggedBits' B and amounts. It runs in about 2 s.
- **upstream/totality-unimported-callee**: Count/Loop/ViaCount/ViaLoop
  never imported Prelude, so the program never elaborated and the test
  checked nothing. Each now imports it. The check is "caller refused as not
  total, counted not", not Idris's sentence.
- **upstream/vectorize-precondition-body**: its mlir-opt call is now
  `bounded`.
- **determinism/name-stability**: rewritten to the provenance rule of
  SUMMARY §8. A symbol of one compilation that the other lacks must hold
  code of Main.step's span: its function body carries an op whose
  location, fused or call-site, is Main.step's, as printed with
  --mlir-print-local-scope. The steps are now paired in the order they ran.
  The old code compared each later symbol-dce dump with the first, because
  step_module takes a step's first dump. A renamed function is the witness.
  It passes, which settles §5 item 31: the two `Main.main.lam.*` moves hold
  Main.step's inlined body, so they are legitimate, and the old check was
  too strict. No naming bug.
- **fuzz/seeds**: one test over the seed corpus (1, 2). Each line is
  prefixed by its seed.
- **fuzz/two-hosts**: Main.idr prints only the generators' self-checks
  (Gen, Sem, TwoLevels and the checkers'). expected-stdout went from 3652
  lines of stock-host generator output to the 24 check lines. mlir.expect
  is kept. The compile now gets to the dump tree in about 2 minutes, where
  it used to time out at 600 s.
- **bench/records**: fails when bench/records holds no run record, where
  before it passed vacuously.
- **bench/smoke**: smoke data added for the four new game benchmarks
  (chameneos-redux 600, thread-ring 1000, meteor-contest 2098, and
  regex-dna on fasta 2500's output). Each `.out` is the benchmark's own
  main.c, built with the pinned clang. The expected is in bench_smoke's
  walk order.
- **unittests/Flow.cpp**: `ExternalModelsKeepTheRule` reads the models from
  the registry: every registered non-idr op that holds FlowOpInterface must
  be exercised by the fixture. That found an unchecked model,
  `ub.unreachable` (NeverRuns), which the fixture now holds. The
  `EXPECT_EQ(models, 7u)` is gone. The stage test checks "flow edge", not
  the full sentence.
- **unittests/Cycles.cpp**: an exhaustive box. It covers every call graph
  on 3 functions, with every choice of self call in tail position or not
  (1728 programs), under a root that calls them all. It checks
  `together`, `callsItself`, component order and `Escapes::recursive`
  against Floyd–Warshall reachability. It runs in 1.4 s. With 4 functions
  it would be 331,776 programs, about 250 s on the debug build, too slow
  for make test-unit. The declaration test is kept.

## Left failing, each on a listed compiler bug (SUMMARY §5)

| test | bug | evidence |
| --- | --- | --- |
| spec/file-size | §5 37 | 8 units over 400 lines now: IdrDialect.h, Expect.h, Optimize.h, StaticData.cpp, Run.cpp, OpsCon.cpp, Expect/Arguments.cpp, Specialize.cpp |
| determinism/threads-linarray-lanes | §5 8 | `'linalg.generic' op consumes a view, which holds no reference` at Main.idr:53 |
| fuzz/seeds | §5 39 (confounded with 38) | every compile `timed out after 60s`; the harness now reports the later checks as `not run` |
| fuzz/two-hosts | §5 38 | compile exit 1: `Error while creating directory .../idr_func_Prelude.Interfaces.foldMap[...]: File name too long` from the dump tree |
| bench/smoke | §5 10, 12, 9, 19, 35 | leaks (binary-trees, deriv, fannkuch-redux, fasta, fasta-redux, mandelbrot, pidigits, reverse-complement; and the new chameneos-redux 11, meteor-contest 100, regex-dna 84103, thread-ring 1 live cells); refusals (fannkuch-linear, qsort, k-nucleotide, spectral-norm-linear, unionfind); nqueens `llvm.call` operand mismatch; regex-redux idr-rc-exclusive; spectral-norm timeout. See bench.log of the last run |

spec/licenses also fails, but only on other lanes' files:
audits/{machinery,done-game-*}.md have no SPDX line, and
bench/chameneos-redux/compare is a file kind with no comment syntax. The
bench-flat lane says to delete that file.

Status of the rest of the scope, on the last run: spec 30/32; upstream
24/24; toolchain all pass (by hand with the make environment, and in the
pool); determinism rbtree, shapes, threads-rbtree and name-stability pass;
bench records and report pass; googletest boxes ranges, hooks, words, ir
and analyses pass (the last two as rebuilt by hand).

## For the orchestrator (outside my scope)

- tools/policies.txt: every C++ line (kCallerCap, kSinkDuplicationLimit,
  stackCellLimit, stackFrameLimit, recursiveStackFrameLimit, minExponent,
  cleanupRounds, aliasFrom, constantBytes, IDRIS_RT_TAG_LIMIT,
  IDRIS_RT_OBJS_LIMIT, secondsLimit) now exempts nothing in spec/no-fuel,
  because the named-constant heuristic is gone. Delete them; only the
  Host.idr `assert_total` line is still used.
- upstream/24-one-shot-module-function-interface/{idr-call,idr-cycle}.mlir:
  no test reads them now, and both are stale idr text (visibility written).
  Move them to tests/idr/bufferize in current syntax, stated with
  in-place=, or delete them. Also fix the README's lines 142 to 145.
- upstream/27-one-shot-tensor-like-copy/README.md:107 and
  upstream/README.md row 27 name the deleted test.
- tests/Fuzz.idr: `twoHosts` and `programOf ["two-hosts"]` no longer have a
  user. tests/Sem.idr's "at most 120 cases" check (SUMMARY §3.2) is still
  printed by two-hosts. If it is deleted, drop its line from
  fuzz/two-hosts/expected-stdout.
- build/dev/foreign/idr/unittests/idr-box-tagged is a stale binary that
  `make test-unit`'s `find` will still run until it is removed. The next
  `make build` must rebuild idr-box-ir and idr-box-analyses from the new
  Flow.cpp and Cycles.cpp.
- HANDOFF.md:135 and :560 name idr-box-tagged and fuzz seed-1/seed-2.
- determinism/shapes and threads-linarray-lanes read fixtures under
  tests/programs. If that tree is flattened, their paths change.

## What a future generator or harness must cover

- `determinism@<program>`, over the bench list and Fuzz seeds, with thread
  counts drawn per run. It replaces leet-rotate (the linear-library path),
  threads-shapes and shapes. This needs Main.idr's `parameterized`
  (machinery).
- `bench/smoke@<name>` from the bench listing, one verdict per benchmark.
  Smoke data could become bench/<name>/ data, made by main.c.
- The fork reproducers (8 under tests/upstream) belong in `make test`, as
  an upstream-fork pool. That is a Main.idr pool change.
- Wall-clock ratios in bytecode-deferred-quadratic and
  forward-dataflow-callee-lookup: replace with work counts, or run them
  serially.
- A rule identity on refusals, so runtime-triple and the flagless check can
  name the rule instead of what the message mentions.
- Options with a cl::OptionCategory in the code, so that
  spec/no-behaviour-options' `kept` list (kept as is) can be read from the
  code.
- An Idris import boundary (`MLIR.Internal` only from `Dialect.*`) to
  replace the hand-MkOp rule dropped from emit-dialects.
- The universal no-discardable-`idr.*`-attribute property over every dump,
  for the C++ `setAttr` half that facts-in-types cannot see.
- `IDR_BOXES` read by the runner, each test its own process (test-unit is
  the Makefile's `find`).
- One edge-value header shared by Box.h (`boxB`, foreign/idr/include, out
  of scope) and runtime-bigs. Today runtime-bigs generates the same family
  itself.
- A CallCycles box on 4 functions needs a faster harness (an -O build of
  the box, or building the IR without the parser).
- prop.h: check the splitmix vectors (SEARCH-28), shrink bytes as Gen
  shrinks tapes (SEARCH-20), and draw rotating seeds in a separate target
  (REPO-17).
- static-linking: a planted dynamic executable as a witness, which needs a
  shared library to link that is not the system's.
- cpu-features-aarch64: whether the processor test calls compiler-rt's
  resolver before it reads the features is no longer checked. It needs a
  per-target-entry parameterized test, or a runtime-start mode that
  requires a feature the machine has.
