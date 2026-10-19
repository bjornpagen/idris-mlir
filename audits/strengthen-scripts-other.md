<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Strengthening the suite: the scripts-other lane

Scope: every test of kind script outside scripts-runtime's: the 32
repository rules (suite check), the upstream reproducers (test-mlir-tools),
determinism-*, fuzz-*, handoff-*, frontend-*, bench-*, and the rest
(artifacts, cfold, rbtree, implementation-a-hundred-definitions-deep,
sum-of-seventy-thousand-constructors, registry-only, language-profile,
expect-coverage, ...). The runtime-surface scripts (runtime-*, big-cell,
io-buffer, heap-region, stack-guard-page, executable-pages,
page-size-mismatch, cpu-features-aarch64, static-linking, no-environment,
system-info, files-roundtrip, directory-listing, every-types-export) were
taken as scripts-runtime's and not touched; of the nine scripts the
vocabulary lane left broken, cfold, rbtree,
implementation-a-hundred-definitions-deep,
sum-of-seventy-thousand-constructors and fuzz-two-hosts are moved to
`cases/` here, and directory-listing, every-types-export, files-roundtrip
and system-info are left to scripts-runtime.

## The repository rules: planted witness and near miss

Every rule that is a search of the tree is now a shell function of a
tree's root that prints `path:line: what` (or `path: what`), run on the
repository and through `planted CHECK` on `witness/` and `near-miss/`
(harness/lib/planted.sh). Every witness file is named by a finding, and
the near miss gives none: both were checked by printing the findings on
each tree before the expected files were written. A walker of the whole
repository (dialect-text, frontend-imports, no-local-headers, pin-sites,
verifier-every-pass, zones) now prunes `tests/*/witness` and
`tests/*/near-miss`; tools/licenses.sh excludes `tests/licenses/witness/*`
(the files that test must refuse), and every other planted file carries
its licence line, or is of a kind licenses.sh excludes.

| test | witness (one file per way) | near miss | also |
| --- | --- | --- | --- |
| no-fuel | each limit name, `for ( ; ; )`, `while (true)`, `while(1)`, `%default covering`, no `%default`, `partial` alone on its line, `private covering`, `assert_total`, `assert_smaller`, a gone and a malformed policy | the words in comments, strings, raw strings and longer names, `for (; n > 0;)`, `while (trueish)`, a recursion on a Vect length (`bitsOf`, the false positive of the old fuel heuristic), a limit and a covering definition and an assertion its own policies name | the inline planted.cpp/Planted.idr moved into witness/ |
| facts-in-types | a discardable attribute alone, beside the report, and the report's name at another type | `(ins)`, the report, the declaration in a comment, an inherent `$discardableAttrsSeen` | the matcher now ignores comments and matches the word, which the near miss needed |
| driver-shape | cl::opt and cl::list outside Options.cpp, registerAllDialects | options in Options.cpp, `registry.insert<...>`, a tool's own options and registerAll outside the driver | |
| emit-dialects | an op name and a dialect prefix in Emit and MLIR/Text, a type and an attribute outside Syntax | the names in a comment, in Syntax/ and Dialect/, dialects outside the contract, no-dot names, `! idr.` text | |
| dialect-text | a pipe of module text from each of idris-mlir-opt, -reduce, mlir-translate and `not`, a `< %t.mlir` and a `< %t.ll`, an orphan prefix | diagnostics with 2>&1, `%status`, `not`, the printed-syntax fixtures by name, lower-llvm-facts, a capitalized NOTE, an idr-expect line | |
| file-size | a .cpp and a .h of 401 lines, of foreign/idr and runtime; a list naming a gone unit and a 400-line one | exactly 400 lines, idris_rt.h and a .td past it, a listed unit | a listed unit no longer over the limit is now a finding at the unit too |
| frontend-imports | a fork package claiming IdrisMLIR.*, compiler/src importing the fork (also publicly), the fork importing the frontend and the rest, a test and the harness importing both | the frontend (IdrisMLIR.Frontend itself among it), a test of the fork through the frontend, `CoreExtra.*`, an import in a comment | **the check missed IdrisMLIR.Frontend's own file**: it pruned Frontend/ but searched Frontend.idr, which the near miss found; fixed. Findings now carry line numbers |
| mlir-layout | presets with another clang-tidy, a plain add_library, IdrIR as add_mlir_library, a static mutable, a static container, std::atomic, thread_local | the three kinds of state, constants, a static function, the words in comments and strings | comments and literals are now lexed out (cpp_lex) |
| no-behaviour-options | a flag in the driver and in a tool (one line and across lines), a pass Option, a DebugCounter registration | kept flags, a positional input, `extern`, idr-expect's `holds`, the generator's flags, idris-mlir-opt's counter, the counter in a comment | findings now carry the line the declaration starts on |
| no-erased-inputs | getCompileData, NamedCExp, treeRT, `import Compiler.LambdaLift`, `import public Compiler.ANF.Opt` | the names in comments, documentation and strings, longer names, a `Lifted` the tree defines, Compiler.Common and Compiler.ANFExtra | |
| no-local-headers | a header beside a .cpp, foreign/idr and runtime units including one beside them, an unlisted runtime header, a gone list line | a public header by path, idris_rt.h, a runtime header from runtime/, a listed include, a generated .inc, a system header | a forbidden include is a finding at the includer and at the header |
| no-primitive-semantics | a primitive called plainly and qualified, a gone and a malformed allowlist entry | the name in comments, documentation, a string, `myprim__count`, a listed serialization | the matcher no longer takes `prim__` inside a longer name |
| pin-sites | sites naming no entry, in C++ and in a script | sites naming a PINS.md entry and an upstream bug, sites in a document and a patch | |
| verifier-every-pass | enableVerifier(false), verifyPasses(var), `--verify-each=false` in a RUN line, `=0` in a script, disable-verifier on parsing, an added patch line | both calls given true or nothing, `=true` and `=1`, the flags in a document, a patch's context and removed lines | |
| zones | a .cppm, a .hpp, a .cpp under include, a googletest two levels down, a .cc in the runtime, tools/gen.cpp, units declaring and importing a module | a file of every zone, MLIR text in a raw string, `importer.run()`, a reproducer under upstream/ | |
| upstream-patches | no README, no plan, neither patch nor reason, both, a patch for no project | a patch for each project, a reason with no patch | |
| commands | a documented command with no target, an AGENTS.md command not documented, a bootstrap that cannot run | targets with prerequisites, commands with arguments, `make` in a later comment and a continuation line | |
| prelude-coverage | a module with neither program nor line; a listed module a program covers (found at the list and the program) | a covered module, a listed one | |
| rules-covered | a rule both stated and listed, a header naming no rule, a bad kind, no reason, a line naming no rule, a rule listed twice | a fixture and a line of each kind, a first line that is no header | a header naming no rule was not a finding before |
| build-preset | a Makefile whose build runs ninja, `/usr/bin/clang++` after `&&`, gcc after `;`, and no preset | one through the presets and the pinned Idris that only says the tools' names | |
| licenses | no line, a wrong holder, 0BSD in the fork, an identifier with no text (MIT), a kind with no syntax | ours, a script's, the fork's own (BSD-3-Clause, ours) and upstream's (Edwin Brady, read from a pin), excluded kinds | each planted tree is made a repository of its own, with an Idris pin, so tools/licenses.sh runs on it unchanged |
| lock | one lock per way: short and upper-case revision, no repository, empty version, tag and describe, neither, not an object, a version outside its series, the series cut inside a number (1.1 for 1.13.2), not JSON | a tag, a describe, a series equal to the version's, a wider one, none, fields not read | **harness bug found and fixed** (below) |
| registry-only (suite test) | a qualified literal, a namespace alone, a name built from a literal, in Idris, C++ and ODS; an entry without its reason | the registry's own files, the samples and googletest boxes, includes, no-dot words, a listed line | **an entry without its reason allowed lines**; it now allows none |
| language-profile (suite test) | one commands file per way: c++23, -fexceptions, no -fno-rtti, `-fno-rtti-data`, only `-Werror=unused`, -freflection | flags in another order, a C unit, a third-party unit | |
| expect-coverage (suite test-idr) | a property no fixture fails, one a fixture names only in prose and a RUN line, one whose name only begins another's | every property failing, the exemption | a fixture that names an unfailed property is now named |

The rules that are behaviour of a tool on an input, not a search, got the
input that must be refused and the one that must pass where they lacked
one:
- configure-gate: the pinned series cut inside a number (24 to 2, 1.13
  to 1.1) is refused and named; its wider series (4 for 4.2, 1 for 1.13)
  passes. A series is matched up to its dot.
- dialects-current: a comment in the ODS and a touched generator leave
  every module current (fingerprints are of records and contents, not
  times).
- doctor-without-idris-source: an absent path as well as an empty
  directory; the real checkout is reported by its pin.
- pinned-test-tools: decoy FileCheck, not and count first on the
  caller's PATH; lit must still put the pinned ones first.
- timeouts, failed-bootstrap, idris-environment, idris-pin(-drift),
  stale-stamps already show both sides; unchanged.

## determinism-*

harness/lib/determinism.sh (only these tests use it):
- one more compilation at a thread count drawn from the clock (2 to 31,
  never 3, 5 or 13), named in the transcript as "a drawn count", with the
  count and `IDRIS_MLIR_DETERMINISM_SEED=<seed>` (which replays it)
  printed on any failure;
- every compilation's executable, each in a process of its own, run on
  the empty input, each case's stdin, and each input the test gives,
  compared byte for byte with exit status: "runs: every executable prints
  the same bytes and exits alike on each input".
- determinism-rbtree gives 0, 1, 9, 10, 11, 1000, 100000 and `x`;
  determinism-shapes runs its one case.
- determinism-threads-*: unchanged (MLIR's pool takes no count).

## fuzz-*

- fuzz-seeds: seeds 1 and 2, then one drawn from the clock whose lines
  name it only on failure, with `IDRIS_MLIR_FUZZ_SEED=<seed>` to replay;
  first, the checker's own checks on the runner (Chez), so a broken
  checker fails before any seed is trusted.
- harness/Fuzz.idr, the checker: every rendering of a case must be printed
  exactly once (a missing line, a line printed twice, or an empty output
  now names the case; before, a case that printed nothing agreed); two new
  self-checks plant a missing line and an empty output.
  `--fuzz-check modelled` counts the cases with a model; the model check
  says `not run` when none has one, instead of `ok`.
- harness/Main.idr reads the program's output byte for byte (fGetChar):
  readFile lost the rest of a line after a NUL, so a case that prints NUL
  (`prim__cast_IntChar (-1)`) merged lines and its checks saw less.
- harness/lib/fuzz.sh dumps only the module after idr-optimize, the one
  the folded check reads (`--mlir-print-ir-after=idr-optimize`): the dump
  after every pass took a 30-case compile from 16 s to over 60 s, past the
  step limit, so every check said `not run`.
- fuzz-two-hosts: moved to `cases/no-input/`; the two new checker checks
  are in its expected stdout.

## The rest

- cfold: nine cases (no input, not a number, depths 0 to 3, 5, 12); the
  two numbers of each are the sum before and after folding, so they
  agree, and are bench/cfold/main.c's. Depth 13 is the deepest a 1 MiB
  stack holds, so the largest case is 12.
- rbtree: ten cases, either side of the second true value (9, 10, 11) and
  up to 100000 keys; each prints n/10 rounded up, as main.c does.
- implementation-a-hundred-definitions-deep: the chain at 100 and at 1000,
  four cases each (g, r, G, no input).
- sum-of-seventy-thousand-constructors: six cases, constructors either
  side of 65,536 alone and together, a repeated one, an empty line.
- artifacts: no build before; after the failure, the good program again
  leaves every kind.
- handoff-readable: each of its four properties shown failing alone on the
  printed module changed to break it (six planted modules).
- handoff-round-trip: two more programs, Doubles at their ties and strings
  past ASCII.
- frontend-beside: the driver and the frontend copied together compile
  and run hello (the copy alone does not).
- The upstream reproducers already state the behaviour they guard, with
  a control where one is possible (sccp beside canonicalize, 1,000 deep
  beside 100,000, the module before and after); left as they are. The
  wall-clock ratio of the two quadratic reproducers stays: a work count
  needs instrumentation upstream does not have.
- bench-smoke: the C references agree byte for byte with the recorded
  outputs on 28 of 30 small inputs; harmonic and n-body differ only in
  Double formatting, which bench/run.sh's `agree` tolerates. Making main.c
  the oracle here would need that `agree` moved out of bench/run.sh into
  a shared file, so it was not done; the records stand.

## Bugs found

Fixed here (harness and checks, which this lane owns):
1. **harness/Lock.idr held the release series as a string prefix**, where
   the configure gate (CMakeLists.txt) matches it up to its dot: a lock
   accepting 1.1 for ninja 1.13.2 passed `runtests --lock` and is refused
   by the gate. Now a version continues its series after a dot. Found by
   tests/lock's witness `series-cut-in-a-number`.
2. **The fuzz checker could agree by saying less**: a case with a missing
   rendering line, or an empty output, agreed. Each rendering must now be
   printed exactly once.
3. **The fuzz checker read the program's output with readFile**, which
   loses the rest of a line after a NUL (seed 1, static, cases 13 and 14:
   `prim__cast_IntChar (-1)` prints NUL, and the reader merged `d13` with
   `d14`). It reads bytes now. Found by (2).
4. **The fuzz model check said `ok` when no case had a model.** It says
   `not run` now.
5. **fuzz-seeds could never run**: the dump after every pass took each
   30-case compile past the 60 s step limit, so every check said `not run`.
   Only the module after idr-optimize is dumped now.
6. frontend-imports searched compiler/src/IdrisMLIR/Frontend.idr, the
   module IdrisMLIR.Frontend itself, as outside the frontend (found by its
   near miss).
7. registry-only and no-fuel: an allowlist entry without its reason still
   allowed lines (registry-only; found by its witness).
8. dialect-text, facts-in-types, mlir-layout, no-behaviour-options read
   comments as code, or a longer name as the word; the near misses needed
   them read as code only.

Compiler and toolchain bugs, kept failing (test, input, expected, got):
1. **fuzz-seeds**, seed 1, part static, case 2: `math.sqrt` of the constant
   -2.5 (`prim__doubleSqrt (prim__mul_Double 1.0 (-2.5))`, the multiply folded first) in `Main.main.delay.137e76a0...`.
   Expected: folded by idr-optimize (the d line folded, its value NaN).
   Got: `expected folded: math.sqrt ... computes from constants alone and
   is left unfolded`; the same with every pass dumped, so not the printer.
   MLIR's `math::SqrtOp::fold` declines a negative operand, so this is a
   gap of the upstream folder that the fuzzer's folded property reaches.
2. **fuzz-two-hosts**: the five harness modules compiled by idris-mlir.
   Expected: compile exit 0. Got: exit 1, `idris-mlir: internal error:
   'idr.yield' op idr-rc-exclusive: gives a value of '!idr.own<...List...>'
   where the solver proved '!idr.excl<...>'` (25 such, on List, Vect and
   List Nat values). The same with HEAD's Fuzz.idr, so not this lane's
   change.
3. **determinism-threads-linarray-lanes and handoff-round-trip**
   (tests/linarray-lanes-wide, tests/linarray-combinators): compile exit 1,
   `'linalg.generic' op consumes a view, which holds no reference; a
   reference of its own (idr.dup) is consumed`. The program tests
   linarray-lanes-wide and linarray-combinators fail the same way.
4. **artifacts**: after a successful compile, the same module changed to a
   refused one (`f 0.5 = 1`, a Double match). Expected: no artifact.
   Got: `build/exec/Main.<hash>.o` left (SUMMARY §5 item 32, still open);
   the committed test fails the same way.
5. **frontend-beside** (new case): a frontend beside the driver that
   cannot start (exits 127). Expected: an error naming the frontend that
   is no internal error. Got: `idris-mlir: internal error:
   .../idris-mlir-front did not finish: No such file or directory`.
6. **registry-only** (not this lane's change; HEAD's test fails the same
   way): seven names built from literals outside the registry,
   Frontend/Walk.idr's probe names (`UN (Basic "idris-mlir-hole")` and
   five more) and Translate/Forced.idr:83's `UN (Basic "->")`. Either the
   registry holds them or the allowlist does, with reasons; not decided
   here.
7. **expect-coverage**: `typed-reads` has no failing fixture (known, the
   vocabulary lane's report).
8. **file-size**: eight units of foreign/idr over 400 lines (known).
9. cfold at depth 13 is the deepest bench/cfold reaches on the 1 MiB stack
   every case runs on (14 ends in `stack exhausted`): not a bug, the
   reason the largest case is 12.

## Runs

| run | result |
| --- | --- |
| `make check` (threads=2) | 32/33; file-size fails on the compiler's units. dialect-text failed once on another lane's fixtures in flight, then passed |
| check tests one by one | every witness found, every near miss silent |
| `make test only=` determinism-rbtree, determinism-shapes, determinism-threads-rbtree, cfold, rbtree, implementation-a-hundred-definitions-deep, sum-of-seventy-thousand-constructors, handoff-readable, frontend-named-file, language-profile | pass |
| fuzz-seeds | fails only on compiler bug 1 (about 12 minutes at threads=2, a shrink included before (3) was fixed) |
| fuzz-two-hosts, determinism-threads-linarray-lanes, handoff-round-trip, artifacts, frontend-beside, registry-only | fail only on compiler bugs 2 to 6 |
| `make test-idr only=expect-coverage` | fails only on typed-reads |
| upstream reproducers, bench-*, the rest | unchanged, not rerun |
