<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Legacy in tests/ and bench/: what the survey found

A read-only survey of every file under `tests/` and `bench/` (2026-10-18,
against e5b05658; HEAD 1e5a8a8e changed neither directory). Its text is
`/tmp/s22/legacy-survey.md`, and its item codes (D1 to D8, C1 to C16, M1 to
M4) are cited below. The owner ruled on four items (2026-10-18):
`tests/spec/time-trace` is deleted (D8: the coordinator deletes it, and
`.gitignore:8`, D7, itself); the 72 generated `programs/semantics/prim-*`
directories fold into one fixture driven by `Sem.idr`'s list (C10);
`tests/fuzz/two-hosts` becomes seeded programs with committed expected
output derived from each program's meaning, never a run-time comparison
against Chez (C11); the test runner's dependency on `contrib` and `test` is
an open item after this wave (no finding here). The rest follows the
coordinator's defaults (README §9). `tests/idr/returned` (D6) is an
untracked empty directory with nothing to commit; `tests/registry/registry-only`
(M3) and `tests/idr/stack/hot-loop` (M4) stay where they are.

L25 owns the fixtures, the benchmarks and the documents (legacy-1 to -6);
L23 owns the test machinery, `tests/lib`, `tests/*.idr` and `tests/fuzz`
(legacy-7 to -10).

### legacy-1: `bench/ackdyn` is an ablation twin of `bench/ack` that no suite needs

| Field | Content |
|---|---|
| Evidence | Survey D1. `bench/ackdyn/Main.idr` differs from `bench/ack/Main.idr` by one line, `printLn (ack (n - 7) n)` against `printLn (ack 3 n)`; both take the input 10, so both compute ack(3, 10) = 8189; `bench/c/ackdyn.c` differs from `bench/c/ack.c` the same way. Both came in 564ba812 ("ELIM-G-18: call-pattern specialization on literals"), an ablation of that specialization. Readers: `tests/bench/smoke/ackdyn.in`, `ackdyn.out` and line 2 of `tests/bench/smoke/expected`; `bench/README.md:71` (the Numeric list) and `:238-241` (Caveats). `bench/README.md:166` says a mechanism's worth is now measured binary against binary |
| Counterexample | every `make bench` builds and times one function twice, three ways, and every `tests/bench/smoke` run compiles it twice; the Caveats describe a measurement no record is taken for |
| Root cause | an ablation of one compiler version kept as a benchmark after the ablation itself (leaving a step out from the command line) was removed |
| Correction | delete the benchmark: `bench/ackdyn/`, `bench/c/ackdyn.c`, the smoke's two files and its expected line, and README's two mentions. The kept record `bench/runs/2026-10-13-9a1b7b1-darwin-arm64` keeps its ackdyn rows (a record is kept as taken, and `tests/bench/records` regenerates it from its own samples); README's headline counts are stated as that record's |
| Deletion | `bench/ackdyn/Main.idr`, `bench/ackdyn/input`, `bench/c/ackdyn.c`, `tests/bench/smoke/ackdyn.in`, `tests/bench/smoke/ackdyn.out`, `tests/bench/smoke/expected:2`, the ackdyn words of `bench/README.md:71` and `:238-241` |
| Consumers | none outside L25 |
| Discriminator | `ls bench` lists no ackdyn; `grep -rn ackdyn bench tests` finds only `bench/runs/`; `bench/run.sh`'s `all` and `bench_smoke` meet 26 programs |
| Verification here | the greps; the smoke runs on the owner's build |
| Size and risk | five files and two README lines deleted; no behaviour of any other benchmark changes |
| Insight | 1, 16 |

### legacy-2: nine benchmark programs are held twice, as `bench/<name>/Main.idr` and as a fixture's copy, three of them drifted apart

| Field | Content |
|---|---|
| Evidence | Survey C1 to C9. Copies that differ only in the SPDX lines or the leading comment: `tests/programs/data/cfold` and `bench/cfold`, `data/rbtree` and `bench/rbtree`, `data/pidigits` and `bench/pidigits`, `io/mandelbrot-pbm` and `bench/mandelbrot-pbm`, `arrays/ioarray-fannkuch` and `bench/fannkuch-redux`, `arrays/linarray-spectral-norm` and `bench/spectral-norm-linear`. Copies that drifted: `arrays/linarray-fannkuch` and `bench/fannkuch-linear`, `arrays/linarray-qsort` and `bench/qsort`, `arrays/linarray-unionfind` and `bench/unionfind`; the fixtures were ported to `Linear.Vec` (`tests/ACCEPTANCE.md:396`, `:399`, `:402`, "the port to the size-indexed vector"), the benchmarks are still over `Array`'s `LArray` (`Arr n = LArray [<n] Bits32` in qsort), and `bench/README.md:9`, `:78`, `:82`, `:159`, `:206` say `Linear.Vec`, while `grep Linear.Vec bench/*/Main.idr` finds nothing. The four linear fixtures' `packages` repeat their benchmarks' (`mlir-linear mlir-array`). `tests/determinism/rbtree/run` and `tests/determinism/threads-rbtree/run` compile `tests/programs/data/rbtree` |
| Counterexample | the program `make bench` measures for qsort is not the program whose module properties `tests/programs/arrays/linarray-qsort/mlir.expect` states; a fix to `bench/cfold/Main.idr` leaves the fixture testing the old program |
| Root cause | one program, two files: the fixtures copied the source instead of reading it |
| Correction | one program per benchmark, `bench/<name>/Main.idr`. Each of the nine fixtures keeps what is its own (`stdin`, `expected-stdout`, `mlir.expect` where it has one, `expected`), and its `run` builds the fixture in `$work` from `bench/<name>/Main.idr` and, where the benchmark has one, `bench/<name>/packages`, as `data/sum-of-seventy-thousand-constructors` builds its own. The drifted three settle on `Linear.Vec`, the form `bench/README.md` states: the fixture's program, under bench's SPDX lines, becomes `bench/<name>/Main.idr`. The determinism tests compile `bench/rbtree` |
| Deletion | the nine fixtures' `Main.idr`; the four linear fixtures' `packages`; the three `LArray` programs in `bench/fannkuch-linear`, `bench/qsort`, `bench/unionfind`; `tests/programs/data/rbtree` in the two determinism runs |
| Consumers | none outside L25 |
| Discriminator | none of the nine fixture directories holds a `Main.idr`; each `run` copies `$root/bench/<name>/Main.idr`; `grep -l Linear.Vec bench/fannkuch-linear/Main.idr bench/qsort/Main.idr bench/unionfind/Main.idr` lists three; `grep -rn programs/data/rbtree tests/determinism` finds nothing; the work fixture each `run` assembles equals the base's fixture directory but for `Main.idr`'s header (a scratch diff); on the owner's build every fixture prints its `expected` and the smoke the recorded outputs |
| Verification here | `sh -n` of each `run`; the scratch assembly diffed against the base; no compile |
| Size and risk | 13 files deleted; the three linear benchmarks now run their fixtures' programs, whose smoke outputs are unverified here (marked), and the kept record measured the `LArray` versions (it stays as taken) |
| Insight | 1, 2 |

### legacy-3: `io/system-info` keeps a per-target table for seven systems on a tree with two targets

| Field | Content |
|---|---|
| Evidence | Survey C12. `tests/programs/io/system-info/run:6-12`: `uname` arms for Linux, OpenBSD, FreeBSD, NetBSD, Darwin, CYGWIN and MINGW, and a `windows` flag; the processor count is `nproc` or `sysctl -n hw.ncpu`, while the runtime answers `sysconf(_SC_NPROCESSORS_ONLN)` (`runtime/Platform/Posix/Processors.cpp:12-13`) and `tools/host.sh` already holds the host's count as `ncpu_total` and its names as `host_names`. The `os` line is `idr.os` folded from the module's triple (`foreign/idr/lib/IR/OpsPlatform.cpp`, `osName`: "darwin" on Apple's, "unix" on Linux). AGENTS.md: per-target cases elsewhere are bugs |
| Counterexample | five arms expect values for targets the tree does not have; in a Linux container with restricted affinity `nproc` counts fewer processors than `sysconf` (selfhost-readiness R11), so the fixture fails while the program is right |
| Root cause | the test re-derives host facts the host layer already holds, for hosts the tree does not have |
| Correction | two arms over `tools/host.sh`'s `host_names` (`macos`: darwin; `linux`: unix), and any other host one line naming it, never a guess; the `isWindows` line is `no` on both targets; the count is `tools/host.sh`'s `ncpu_total` |
| Deletion | the five dead arms, `os=windows`, `windows=`, the `nproc`/`sysctl` fallback and its message |
| Consumers | none outside L25 |
| Discriminator | a grep of `tests/programs/io/system-info/run` for BSD, CYGWIN, MINGW, nproc, sysctl and uname finds nothing; on the owner's build the fixture prints its `expected` on both targets |
| Verification here | `sh -n`; the expectation part run with `tools/host.sh` sourced prints `darwin`, `no`, `mlir` and `sysctl -n hw.ncpu`'s count |
| Size and risk | a few lines; the count on macOS is `hw.ncpu`, as the base's fallback read |
| Insight | 4, 12 |

### legacy-4: bench/'s script and documents describe what is gone

| Field | Content |
|---|---|
| Evidence | Survey D2 and D3 (their `bench/run.sh` halves), C13, C14. `bench/run.sh:159-165`: `idris_sources` copies `bench/lib/*.idr`, deleted in a11f7701; `:68-70` document and `:174` test a `rejected` mark no benchmark has carried since 17622577; `:35-36` cite "fannkuch-redux took 1163 s in the 2026-10-07 record", a record deleted in 527de022 (the kept record, `bench/runs/2026-10-13-9a1b7b1-darwin-arm64/results.md:21`, measured Chez's fannkuch-redux at 1218.731 s). `bench/README.md:64` names a record `<date>-<revision>`, the kept one `<date>-<revision>-darwin-arm64`; `:142-193` (the fannkuch-redux item and "Ablation") narrate the deleted simplify loop and an ablation the compiler can no longer run; it never mentions `profiles/`. `bench/profiles/README.md:3-6` says the directory holds untracked traces and "only this file is" committed, while it holds four committed measurement records that proposals cite; `:36-37` name an `idr-simplify` `round` event, and neither the pass nor the event exists in `foreign/` |
| Counterexample | a reader of `bench/README.md` learns of a loop and an ablation the compiler does not have; a reader of `bench/profiles/README.md` takes the records for scratch; `bench/run.sh` copies from a directory that cannot exist and honours a mark nothing writes |
| Root cause | the documents and the script were not cut over with the deletions they describe |
| Correction | `bench/run.sh`: `idris_sources` copies `Main.idr` alone; the `rejected` lines go; the citation becomes the kept record's (Chez's fannkuch-redux, 1219 s, the 2026-10-13 record). `bench/README.md`: the record name as kept; every sentence that narrates the simplify loop, or names a mechanism `grep` does not find in `foreign/`, goes, and the Ablation item with its table; one line names `profiles/`; ackdyn by legacy-1; the headline counts stated as the kept record's. `bench/profiles/README.md`: both kinds described (untracked `*.time-trace.json` written by `tools/profile.sh`; dated `.md` measurement records, kept as taken), the `round` sentence and any sentence naming a mechanism `grep` does not find gone |
| Deletion | `bench/run.sh:159-165`'s `bench/lib` loop, `:68-70`, `:174`, the 2026-10-07 citation; the README sentences named |
| Consumers | none outside L25; the halves of D2 and D3 in L23's bench helper are legacy-9's |
| Discriminator | `grep -n 'bench/lib\|rejected\|2026-10-07' bench/run.sh` finds nothing; `grep -n 'simplify\|ackdyn\|round' bench/README.md bench/profiles/README.md` finds nothing; `bench/profiles/README.md` names both kinds |
| Verification here | `sh -n bench/run.sh`, `shellcheck` if installed; the greps |
| Size and risk | documents, and two dead branches of one script |
| Insight | 15 |

### legacy-5: two tools live in tests/ and look like tests

| Field | Content |
|---|---|
| Evidence | Survey M1, M2. `tests/upstream-idris/` (`run`, `one`, `common.sh`, `as-idris`) has no `expected`, is in no pool, no make target calls it, and writes to `build/upstream-idris/results`; 0006's D12 keeps it (`proposals/0006-qualification.md:82-95`); its `run` makes the directory look like a test. `tests/compile-times.sh` "reports; it gates nothing", no target calls it, 0006's D19 keeps it (`:64-69`), and it writes into `bench/profiles` as `tools/profile.sh` does. References: `Makefile:92` and `tools/toolchain.sh:6` (comments), `proposals/0006-qualification.md:64`, `:83`, `tests/lib/timing.sh:4`, `:17`, and the scripts' own paths (`run:7-8`, `:21`, `:33`, `:64`; `one:16`, `:37`; `common.sh:3`; `compile-times.sh:11-12`, `:64-70`). `HANDOFF.md:531` and `proposals/0002-sound/review.md:127` are history |
| Counterexample | `tests/README.md`'s "a test is a directory with a POSIX-sh `run` script and an `expected` file" is false of `tests/upstream-idris`, which a reader takes for a test whose expected file is missing |
| Root cause | tools filed under `tests/` |
| Correction | move both to `tools/`: `tools/upstream-idris/` and `tools/compile-times.sh`, every path inside them updated (their root computations keep their depth: `run`'s `../..`, `compile-times.sh`'s `..`); `tests/lib/timing.sh`'s two comments name `tools/compile-times.sh` (L23); `Makefile:92`, `tools/toolchain.sh:6` and 0006's two lines follow (coordinator, hub text); history stays |
| Deletion | `tests/upstream-idris/`, `tests/compile-times.sh` |
| Consumers | `tests/lib/timing.sh` (L23: its comments at lines 4 and 17 name `tools/compile-times.sh`) |
| Discriminator | `git grep -n 'tests/upstream-idris\|tests/compile-times'` finds only `HANDOFF.md`, `proposals/0002-sound/` and `bench/profiles/` records once the hub text is applied; `sh -n` of each moved script; `tools/upstream-idris/run --list` prints the groups |
| Verification here | `sh -n`; `--list` |
| Size and risk | five files moved, paths only |
| Insight | 13 |

### legacy-6: tests/README.md's layout omits what the tree holds

| Field | Content |
|---|---|
| Evidence | Survey C16. `tests/README.md` (Layout) omits `runner/` (`one.sh`), `toolchain/lib/` (helpers six runtime property tests source), the reject header `-- message:` (`tests/lib/profile.sh:52-58`; 25 fixtures carry it), the `targets` file and `expected.<name>` (`tests/Main.idr`'s `runsHere`, `tests/runner/one.sh`); `:34-35` describe the `prim-*` directories this wave folds (idris-frontend-9) |
| Counterexample | a contributor adding a per-host expectation or a reject message finds no word of either; after the fold the README names directories that do not exist |
| Root cause | the layout text did not follow the layout |
| Correction | the Layout documents what stays and what this wave makes: `runner/`; `toolchain/lib/`; `-- message:`; `targets` and `expected.<name>`; `programs/semantics/prim/`, run once per `Sem.names` entry as `programs/semantics/prim@<name>`; a fixture whose program is a benchmark's builds it from `bench/<name>`; nothing of `upstream-idris` or `compile-times.sh` (now tools); no `symbols` file (legacy-10) |
| Deletion | the `prim-*` sentence |
| Consumers | none outside L25 |
| Discriminator | each named path and header appears in `tests/README.md`; `grep -n 'prim-\*\|upstream-idris\|symbols' tests/README.md` finds nothing |
| Verification here | reading |
| Size and risk | documentation |
| Insight | 6 |

### legacy-7: tests/fuzz/two-hosts takes its expected output from the stock host at run time

| Field | Content |
|---|---|
| Evidence | Survey C11. `tests/fuzz/two-hosts/run:21` writes `expected-stdout` from `"$runtests" --fuzz-program two-hosts` (the runner, on Chez), checks the stock host's Gen lines (`:26-31`), then holds idris-mlir's compile of Gen, Prims, Fuzz, Sem and TwoLevels to that text byte for byte (`e2e_io`). AGENTS.md: "There is no oracle ... Do not add a comparison against Idris's Chez backend or stock evaluator". The owner's ruling (2026-10-18): two-hosts becomes seeded programs with committed expected output derived from each program's meaning, never a run-time comparison against Chez. `Fuzz.twoHosts` (`tests/Fuzz.idr:749-767`) is a `String`: Gen's checks and the generators' output for fixed seeded requests (seed 1's program, stdin and static program, `threads 1`, a tape and its shrink candidates, a semantics program, two two-levels programs) |
| Counterexample | a change to Gen that the stock host evaluates wrongly becomes idris-mlir's specification the same day, unreviewed; a stock host that cannot build its text fails idris-mlir's test |
| Root cause | the expectation is one host's output computed at test time, not a reviewed file |
| Correction | `tests/fuzz/two-hosts/expected-stdout` is committed: the text `Fuzz.twoHosts` means, every `gen:` line `ok` (a check holds by its definition; a committed `failed` is never a specification) and each section the seeded request it names. The `run` copies `Main.idr`, `expected-stdout`, `mlir.expect`, `packages` and the five modules into `$work/two-hosts` and calls `e2e_io`; it runs no stock host. A change to the five modules that changes `twoHosts` rewrites `expected-stdout` in the same change, reviewed section by section |
| Deletion | `run`'s `--fuzz-program two-hosts` call and its "stock host" lines; that line of `expected` |
| Consumers | none outside L23 |
| Discriminator | `grep -n runtests tests/fuzz/two-hosts/run` finds nothing; `expected-stdout` is tracked; every `gen:` line in it ends in `ok`; on the owner's build idris-mlir's program prints it |
| Verification here | the review of each section against its definition, and the runner's sections reproduced by its own requests (`--sem-program`, `--two-levels-program`, `--fuzz-program`) on Chez at authoring time; the fixture runs on the owner's build |
| Size and risk | one committed text, which changes with Gen |
| Insight | 6 |

### legacy-8: the 72 semantics chunk directories, as the survey measured them

| Field | Content |
|---|---|
| Evidence | Survey C10. `shasum` of the 72 `tests/programs/semantics/prim-*/expected` gives one hash; each `run` is `sem_case <its own directory name>`; the names end in ordinals (`-0`, `-1`), which `tests/README.md`'s rule ("words joined by dashes, no numbers") forbids; `sem-index` exists only to keep the two copies in step. The owner's ruling (2026-10-18): one fixture driven by `Sem.idr`'s list |
| Counterexample | as idris-frontend-9's: a chunk the table makes but no directory holds goes unrun until sem-index fails |
| Root cause | as idris-frontend-9's: the runner has no parameterized test |
| Correction | idris-frontend-9's (the parameterized entry), with the seam L23 and L25 share: the fixture is `tests/programs/semantics/prim/`, written by L25 |
| Deletion | idris-frontend-9's |
| Consumers | `tests/programs/semantics/` (L25: the 72 directories and `sem-index` deleted, `prim/` written) |
| Discriminator | as idris-frontend-9's |
| Verification here | as idris-frontend-9's |
| Size and risk | as idris-frontend-9's |
| Insight | 14 |

### legacy-9: test helpers kept for features that are gone

| Field | Content |
|---|---|
| Evidence | Survey D2 to D5. D4: `tests/lib/compile.sh:114-120` `rejection_reason`; `git grep -w rejection_reason` finds only the definition. D5: `tests/lib/e2e.sh:166` `[ -f "$1/translate.check" ] && filecheck ...` and its doc at `:161-162`; the last four `translate.check` files went in 1cd1193a; `filecheck`, `mlir_input` and `check_mlir` stay for the two `mlir.check` files ruling R2 keeps (`tests/programs/partial/{lambda-terminates,partial-divergent-call}`). D2, D3: `tests/lib/bench.sh:7`, `:18`, `:35` copy `bench/lib/*.idr` (deleted a11f7701); `:13-29` handle a `rejected` mark nothing has carried since 17622577 |
| Counterexample | nothing fails: each is a branch for a state no fixture can reach, read by every contributor and kept in step by hand |
| Root cause | the deletions of `bench/lib`, the `rejected` mark and `translate.check` left their readers |
| Correction | delete `rejection_reason`, the `translate.check` line and its doc words, `bench_smoke`'s `bench/lib` copies (it copies `Main.idr` alone) and its `rejected` arm with its comment. `refusal_rule` (`tests/lib/rules.sh`) stays: `tools/upstream-idris/common.sh` (legacy-5) calls it. The same dead paths in bench/run.sh are legacy-4's |
| Deletion | as listed |
| Consumers | none outside L23 |
| Discriminator | `grep -rn 'rejection_reason\|translate.check\|bench/lib\|rejected' tests/lib` finds nothing; `sh -n` of each changed file; the smoke on the owner's build |
| Verification here | `sh -n`, the greps |
| Size and risk | about thirty lines deleted |
| Insight | 1 |

### legacy-10: the libm symbol list is held five times

| Field | Content |
|---|---|
| Evidence | Survey C15. `tests/programs/arrays/symbols`, `data/symbols`, `io/symbols` and `prelude/symbols` are byte-identical (`exp log pow sin cos tan asin acos atan sqrt floor ceil exp2 ldexp`); `tests/accept/symbols` adds `write read _exit getenv`; the stack pool's own file holds those four alone. `tests/lib/heap.sh`'s `allowed_symbols` reads `<test>/../symbols` (`:9-10`, `:54-60`), and the test directory threads from `universal` (`tests/lib/properties.sh:64-77`) through `object_imports` only for that read; `universal`'s callers are `tests/lib/e2e.sh:125` and `tests/lib/profile.sh:145`. The four extra names are the runtime's own imports: `runtime/Platform/Posix/Files.cpp` calls `write` and `read`, `runtime/Platform/Posix/Process.cpp` `getenv` and `_exit`, and `runtime_symbols` lists what the runtime object imports. libm's calls come from the code generation of Double ops (the math dialect is legal through lowering, `foreign/idr/lib/Conversion/Lower.cpp:103`), which any program may hold |
| Counterexample | a Double program added to `programs/eval` (no `symbols` file) fails `universal` with `sin` undefined; a libm name LLVM starts substituting is added to one pool's copy and the others fail |
| Root cause | a fact of code generation held as a per-pool file |
| Correction | one list, `libm_symbols` in `tests/lib/heap.sh`, which `allowed_symbols` prints for every test after the code generation's and the runtime's symbols; `allowed_symbols`, `object_imports` and `universal` lose their test-directory argument, and `e2e.sh`'s and `profile.sh`'s calls follow. The pools' files go: the four in `tests/programs` (L25), `tests/accept/symbols` (coordinator, hub text), the stack pool's (L13's directory; the coordinator deletes it at integration); `tools/licenses.sh`'s `*/symbols` goes (coordinator, hub text) |
| Deletion | `allowed_tests` and the file read; the test-directory argument of the three functions; the five `symbols` files |
| Consumers | `tests/lib/heap.sh`, `tests/lib/properties.sh`, `tests/lib/e2e.sh`, `tests/lib/profile.sh` (L23); the four `tests/programs/*/symbols` files (L25) |
| Discriminator | `ls tests/programs/*/symbols` finds none; `grep -n 'symbols' tests/lib/heap.sh` shows the one list and no file read; on the owner's build every pool's `universal: holds` |
| Verification here | `sh -n`; the greps |
| Size and risk | five data files become one list; a pool without a Double program is allowed libm, which code generation may call for any program |
| Insight | 4, 6 |
