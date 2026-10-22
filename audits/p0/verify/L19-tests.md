<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# L19: tests and qualification of the new design

Lane L19 of the P0 verification swarm. Scope (the dispatch): AGENTS.md's
test rules; every promise the rulings make (D24's boundary, D26's space,
D30 to D34, D35 to D38, D49 and D52's generated outputs); §7's S1 and S2.
HEAD `e96bb991` at start (2026-10-21T21:31Z) and at finish.

Marks: *read* (path:line at HEAD), *measured* (the command, or what was
counted and how), *recalled* (not in `sources/`), *conjecture*,
*decision* (a ruling Dn or a coordinator decision Cn). No build, test or
`make` target was run. The measurements are counts over the tree with
`grep`, `ls`, `wc`, `stat`, and one shell probe of this host's limits
(`sh -c 'ulimit -v 65536'`), which builds and runs nothing of ours.

Counting commands used below (from the repository root, under `bash`):
- *Fixtures*: a directory of `tests/` with no `run`, no `Main.idr` and
  exactly one `.mlir` (339). RUN lines: `grep -E '^ *// *RUN:'` over
  them (1,842). Lines with an `--idr-` flag: 644. Lines naming a
  transform pass, a pipeline flag or `--pass-pipeline`: 291, in 173
  fixtures (205 by flag, 86 by nest); lines whose only `--idr-` words are
  `--idr-expect`, `--idr-contracts`, `--idr-target`, `--idr-entry`: 439.
- *Distinct `--idr-` words*: `grep -rhoE -- "--idr-[a-z][a-z0-9-]*"
  tests/ harness/ | sort -u` (22). Registered passes:
  `grep -n 'Pass<"idr-' Passes.td` (29).
- *Program tests*: a directory with `Main.idr` whose first line is not
  `-- expect:` (235; 234 with `cases/`; 907 cases; 1,032 case
  directories counting the rejects' `near/`). Rejects: 47, each with
  `near/`. Crash cases: `ls tests/*/cases/*/expected-crash
  tests/*/near/cases/*/expected-crash` (86); exit cases (4). Distinct
  crash texts: `cat` of those files, `sort | uniq -c` (22).
- *mlir.expect*: `ls tests/*/mlir.expect` (44); step lines
  `grep -v '^#' | grep -o '^[^:]*:[a-z][a-z0-9-]*:'` (56).
- *Benchmarks*: `ls bench` less `README.md`, `records`, `report.sh`,
  `run.sh` (30).

## 1. Verification

Each ruling and load-bearing claim of my scope: *holds*, *holds with a
correction*, or *refuted*, with evidence and the class of each
observation (defect confirmed in the source; structural incompleteness;
integration mismatch; unverified behaviour; optional simplification).

### 1.1 AGENTS.md's test rules

**"Tests check behaviour ... Not clone numbers, function order or SSA
names"; "Never: a test that names a pass ... (644 RUN lines name 24
`--idr-*` passes, 19 T1-T3)". Holds with a correction.**
- *Measured*: 644 of 1,842 fixture RUN lines carry an `--idr-` flag. But
  the whole of `tests/` and `harness/` names 22 distinct `--idr-` words,
  not 24: 19 registered passes, two pipelines (`idr-rc`, `idr-pipeline`,
  *read* `Transforms/Pipeline.cpp:200-207`) and one instrumentation
  option (`idr-contracts`, *read* `Driver/Options.cpp:154`).
- 439 of the 644 lines name only the test vocabulary (`--idr-expect` and
  three flags no rename touches). The lines a P0 rename breaks are 291 in
  173 fixtures, by flag (205) or by a `--pass-pipeline` nest over
  `idr.program(...)` (86).
- Outside the fixtures, steps named by pass: 44 `mlir.expect` files (lane
  19 counted 41) with 56 step lines (24 `idr-rc-exclusive:`, 13
  `idr-tail-calls:`, 7 `idr-optimize:`, 3 each `idr-returned-arguments:`,
  `idr-contify:`, `idr-bufferize:`, 1 each `idr-rc-stack:`,
  `idr-narrow:`, `emitted:`; *measured*); `harness/lib/heap.sh:119`
  (`idr-lower`); the fuzzer's `after:idr-optimize` (`fuzz.sh:86, 101-103`,
  *read*); `determinism.sh:174` (`--remarks-filter=idr-narrow-lanes`);
  `actions.sh:22-27` (three action tags spelled by hand).
- Since 28274bd3 a renamed step fails loudly (`expect.sh:34-37` says "no
  module dumped after"; an unknown flag is a usage error), so the
  exposure is churn at every rename, not silent passes.
- *Class*: defect confirmed (tests name passes); integration mismatch
  (AGENTS.md's evidence line counts 24 distinct passes; the tree has 22
  words, 19 of them passes).

**"A brittle test means a missing test API." Holds.** The APIs the
cutover needs and lacks (*read*): a stage as a step (the harness finds a
step by parsing the IR tree printer's file names, `mlir.sh:63-116`, and
rebuilds a pipeline from `--dump-pass-pipeline` text,
`differential.sh:15-48`); the ending of a run as a record (inferred
from status and stderr in three places, below); a rule identity in the
report (grepped as text, `profile.sh:69-104`); a binder identity
(`Expect/Quantities.cpp:38-69` keys binders by location); a work count
per solve and a footprint per pass (none; lane 19 §3.1).

**"There is no oracle ... A test's committed expected files are its
specification." Holds.** The oracles in use are ours: `%differential`
(two forms of one program, `differential.sh:111-174`), `idr-expect`'s 82
properties (*measured*: 82 quoted names in `Expect/Lookup.cpp`), the
contracts (`Contracts.cpp:56-62`), `Sem.idr`'s tables, `Fuzz.idr`'s four
renderings and integer model (`Fuzz.idr:1-48`), clang's C for the
benchmarks (`bench/README.md:22-26`), the verifier after every pass
(`tests/verifier-every-pass/run:9-31`).

**"Every command a test runs times out." Holds** (`testutils.sh:60-88`:
60 s a step, 300 s a test, 256 KiB of output).

**"Do not report skipped tests as passed." Holds in the harness** (a
missing build prints a line no expected file holds, e.g.
`tests/page-size-mismatch/run:23-26`). D35 and D36 add tests whose case
exists only where the host can impose a limit (1.9, 1.10); §2.6 says how
such a test stays honest.

**"The Idris side compiles under two hosts ... the Idris test machinery."
Refuted for the runner.** `harness/harness.ipkg:7` depends on `contrib`
and `test`; `Main.idr:61` and `Runner.idr:17` import `Test.Golden`;
`Lock.idr:14` imports `Language.JSON`; `Runner.idr:53, 69, 73` shell out
through `system` (*read*). idris-mlir ships neither package (19 H1).
*Class*: defect confirmed.

**"Never ... every crash exited with status 1, its kind only in a message
the harness parsed from stderr in three copies (18 R-ABI-4; 19 C4)".
Stands at HEAD.** `idris_rt_crash` exits `IDRIS_RT_CRASHED` = 1
(`runtime/Io/Ending.cpp:61-67`, `runtime/idris_rt.h:297`), out of memory
(`Alloc/Cells.cpp`, `outOfMemory`) and the stack's guard
(`Start/Entry.cpp:77-80`) included. The three readers: `run.sh:26-39`
(the live-cells line), `e2e.sh:161-178` (status literal 1, prefix
`idris-mlir: `), `differential.sh:155-170`. *Class*: defect confirmed
(owed to D37).

**"Never ... every shipped program counting every allocation for a test
(18 R-AL-5)". Stands at HEAD.** `newCell` and `freeCell` move a
thread-local count in every runtime build (`Cells.cpp`, *read*), and
`idris_rt_main_return` reads `IDRIS_RT_LIVE` from the environment in
every shipped program (`Ending.cpp:18-31, 45-49`). *Class*: defect
confirmed.

### 1.2 D24's boundary

**Holds with a correction.**
- The boundary test exists and is shaped right (*read*):
  `tests/uniqueness-shared-rebuild` is refused at line 30 with
  `unsupported (uniqueness)` because the list is read again after `bump`;
  its `near/` builds the list a second time and passes four cases.
- But the pair passes today and after D24: it pins where the boundary is,
  not D24's claim that the verdict is read off the program and never off
  an optimization. By lane 08 (*read*, `08-counting.md:1219-1233`),
  skipping one `ReuseAction` (the debug counter
  `idr-reuse-site-count=0`, which `actions.sh:22-27` already drives)
  removes today's promise and its refusal. The discriminator is the same
  pair under every optimization skip set (§2.6). That today's compiler
  accepts the refused program with reuse skipped is *conjecture* from the
  read chain, not run.
- To run it, the harness needs the module a refused program's frontend
  emitted, and the driver leaves none: a rejection leaves "artifacts:
  none" (`harness/lib/compile.sh`, `no_artifacts`; the reject transcript,
  *read*).
- *Class*: structural incompleteness (no discriminating check); integration
  mismatch (no emitted module on refusal).

### 1.3 D26's space promise

**Holds as a statement; nothing qualifies it.**
- The runtime counts live cells exactly and keeps no high-water mark
  (`Cells.cpp:151-223`, *read*). Tests check zero live cells at a normal
  exit only (`run.sh:26-39`, `differential.sh:166`); no test bounds a
  peak (19 T19).
- D26's "a fixed number of bytes ... computed by the compiler for each
  function from its types" names no carrier (where the bound is kept,
  who constructs it, who reads it), and P0 names no check of the promise.
- *Class*: structural incompleteness. §2.6 names a static and a dynamic
  discriminator; §6 holds the one question the dynamic one raises.

### 1.4 D30, proper tail calls

**Holds with corrections.**
- The fallback D30 deletes is at
  `foreign/idr/lib/Conversion/TailCallPlan.cpp:108-112`, not under
  `Tail/`: a tail-position call that reaches a frame cell is counted
  (`frameBound`) and left a plain call (*read*).
- Every program runs on a 64 GiB reserved stack
  (`runtime/Start/Runner.cpp:45`, 1445d894), so no run can show a missed
  tail call. The only check is the `constant-stack` and `tail-calls`
  properties (13 and 14 `mlir.expect` lines, *measured*), each bound to
  the step `idr-tail-calls:`, a pass name.
- Five tests still say a program runs "on the 1 MiB stack the harness
  gives" (`mutual-pure-tail-calls`, `io-loop-through-helper`,
  `mutual-io-if-case-with`, `forever-until-crash`, `when-unless-loops`;
  *measured* by `grep`); 1445d894 removed that stack ("the 1 MiB test
  stack ... gone", *read*).
- *Class*: defect confirmed (stale claims in five tests); structural
  incompleteness (no run can discriminate until D32 makes the stack
  small).

### 1.5 D31, actions never grow the native stack

**Holds; the three silent gaps are in the source.** `Tail/FramesPlan.cpp`
returns no plan, and so leaves a component's plain calls and native stack
growth, for a member with other than one result (`:151`), for members
whose effects differ (`:157-160`), and for a result no field may hold
(`:166-171`) (*read*; 21 P-10). That no test reaches any of the three is
*conjecture* (no test's name or comment says so; not searched
exhaustively). *Class*: defect confirmed (silent fallbacks); structural
incompleteness (no test).

### 1.6 D32, a small, statically bounded native stack

**Holds.** Facts it replaces (*read*): the stack constant `1 << 36`
(`Runner.cpp:45`); the 1 MiB guard (`:37`) whose comment says "a frame
larger than this could step over them, and none is", which nothing
checks (18 R-STK-1, 19 §6); reaching the guard is a crash "stack
exhausted" with status 1 (`Entry.cpp:77-80`), reached by no test (19
§3.2). One integration mismatch: `bench/run.sh:95-96, 201-207` raises
`ulimit -s` to the hard maximum "so the program runs" (cfold), which
D32 makes wrong (the program's stack is its own computed reservation)
and which would hide a D32 failure if the runner ever used the system
stack. *Class*: integration mismatch (bench); structural incompleteness.

### 1.7 D33, the tools' small stack

**Holds.** The model test exists:
`tests/upstream-recursive-attribute-parser/run:16` runs upstream
`mlir-opt` under `ulimit -s 8192`. No deep-nesting fixture exists for our
tools, and the tools run on the same 64 GiB constant (1445d894)
(*conjecture* for the first, by test names and a `grep` for nesting
generators). *Class*: structural incompleteness.

### 1.8 D34, tail recursion modulo context as a promise

**Holds.** `map-deep`, `loops-trmc` and `loops-trmc-counter` cover one
constructor around the call; "several constructors deep, across a
rejoin, an IO action inside the actions that run it" have no test
(*conjecture*, by names and comments). `map-deep`'s check is
`constant-stack` at `idr-tail-calls:` (`tests/map-deep/mlir.expect`,
*read*). *Class*: structural incompleteness.

### 1.9 D35, strict hosts

**Holds with a correction.**
- *Measured* on this host (arm64 macOS, Darwin 27, 16 KiB pages):
  `sh -c 'ulimit -v 65536'` fails, "cannot modify limit: Invalid
  argument". macOS refuses an address-space limit, so the strict host D35
  names cannot exist on one of the four targets; a test of it has no case
  there.
- On the Linux targets an address-space limit can be set (*recalled*:
  `RLIMIT_AS`), and today's reservations exceed any small one: 64 GiB of
  stack (`Runner.cpp:45`), the 4 GiB-aligned heap window (1445d894), and
  snmalloc's flat page map (C5's *conjecture* of about 256 GiB).
- *Class*: integration mismatch (one target has no case); §2.6 makes the
  case set the host's.

### 1.10 D36, the host's memory limit

**Holds as stated** ("macOS has none to read"). A test needs a cgroup
the user may create (*recalled*: `systemd-run --user --scope -p
MemoryMax=...` needs a user manager with delegated cgroup v2), which a
build host may lack. *Class*: unverified behaviour (a host capability);
§2.6 adds the platform layer's reader tested on planted files.

### 1.11 D37, one exit status per ending

**Holds with corrections.**
- The harness's three copies of the protocol and the literal 1 stand
  (1.1).
- The table changes what a crash shows in the invariant set: 86 case
  directories hold `expected-crash`, 4 hold `expected-exit`
  (*measured*); the prefix `idris-mlir: ` becomes `<program>: fatal: `
  in all 86, and the one out-of-memory case
  (`tests/crash-integer-shift-huge`) goes from status 1 to 111.
- "`<program>`, the program's own name" has to be a constant the compiler
  writes (the output name it was given), never `argv[0]`: stderr would
  otherwise depend on how the harness invokes the program and could not
  be compared byte for byte. D10 settles it (the name is known
  statically). Seam with L11.
- `exit n` outside 0 to 255 is a crash today (`Entry.cpp:88-107`) and
  becomes the internal error: `tests/exit-with` gains a case 256.
- "Tests read the status and the committed standard error, never parsed
  text" leaves today's leak check (the parsed line `idris-rt: live cells
  N`) without a channel (§4 I5).
- *Class*: integration mismatch (crash texts, leak channel); a correction
  (the program's name is a constant).

### 1.12 D38, a crash site as data

**Holds with a correction.**
- Sites are already in today's messages, one string per site: the
  invariant set's crash texts read `array index out of bounds at
  Main.idr:25:54` or `unhandled input for Main.name at Main.idr:10:1`
  (*measured*: 22 distinct texts over 86 cases). D38's
  `file:line:col: cause` reorders all 85 texts that carry a site.
- 11 of the 86 name a function in the cause (`unhandled input for
  Main.name`, `... for Main.case block in step`, `... for
  Prelude.Num.case block in mod`; *measured*). Under "one global per
  cause" either the name leaves the message (the site already names the
  clause) or a cause is per function, which is more globals than causes.
  Unfixed seam (L11).
- *Class*: integration mismatch.

### 1.13 D49, generated files committed

**Holds with corrections.**
- The model exists: `tests/dialects-current` runs `tools/dialects.sh
  check`, whose stamp is the checksum of the records and of the
  generator's source, then of the file's own text
  (`dialects.sh:26-33, 98-112`, *read*); its transcript shows a hand edit
  and a changed generator each failing.
- D49 stamps "the fingerprint of the specification"; the generator's
  source (`compiler/specgen/`, C7) must be in the fingerprint too, as
  `idris-mlir-tblgen.cpp` is in today's.
- D49 names no reader of the stamp: `make check` regenerates and compares,
  so there the stamp is unread. The reader that gives it a job is the C++
  build, a configure-time checksum that refuses a stale or hand-edited
  file without running Idris, which keeps "a C++ build never waits on
  Idris" and makes a hand edit fail at build time too (§4 I9).
- `make check` can regenerate: it builds the runner with the pinned stock
  Idris (`Makefile`, targets `check: runner` and `runner:`, *read*).
- *Class*: structural incompleteness (the stamp's reader); a correction
  (the generator in the fingerprint).

### 1.14 D52, byte-for-byte reproduction under idris-mlir

**Holds.** Its purity list (declaration order, no map iteration, no
directory listing, strings and integers only, no time, environment or
path) is enforceable by the generator's type: a pure core whose output
type's leaves are strings and integers makes every item unwritable
except declaration order, which the specification's lists fix (§4 I9).
No test exists, nor can before the generator. *Class*: structural
incompleteness.

### 1.15 §7 S1, scale fixtures as tests

**Holds with corrections.**
- The 20,000-case match is not in the tree: e96bb991's fixture was
  generated outside it (21 §2.3, *read*), and a `grep` for 20000 and
  20,000 under `tests/` finds case sizes and transcripts, no wide match
  (*measured*).
- The 65,536-label fixture is `tests/defunc-tag-limit`: an awk generator
  inside a RUN line, writing today's dialect (`#idr.types<>`, which D48
  deletes), run through `--idr-defunctionalize`, asserting only that the
  pass ends inside the test's limit (`defunc-tag-limit.mlir:1-2`, *read*).
  A finish-within-limit check passes a quadratic as long as N² fits the
  limit.
- So S1's fixtures have to be generators that survive the dialect cutover
  (written over the specification's builders, D50), assert a scaling
  relation on counted work, and cover the walls' shapes (§2.5).
- *Class*: structural incompleteness.

### 1.16 §7 S2, tests that survive the cutover

**Holds with corrections.**
- Counts *measured*: 235 program tests, 234 with cases, 907 cases; 47
  rejects, each with `near/`; 30 benchmarks; 144 `semantics@` runs (lane
  19 §2.2, *read*).
- "The invariant set frozen ... unchanged at every step" cannot hold
  across rulings that change what a run shows: D37 (86 crash texts, one
  status), D38 (85 site texts), and D13 where an expected output rests on
  today's deletion of an unused crashing computation (*conjecture*,
  unmeasured). D37 and D38 have to land in S2 with "the runtime's one
  ending record", before the set is frozen; a later ruling that changes
  observable meaning re-records its cases in its own step, the ruling
  named.
- 44 of the 235 program tests carry an `mlir.expect` whose steps are pass
  names; those lines are not frozen behaviour until restated by stage.
- "The pipeline as one generated list with stage-named steps" is needed,
  not enough: a property checked at one stage-named dump still lets a
  later pass of the same stage break it (§4 I1).
- "idr-expect generated from records": by D15 and D16 those records are
  Idris, in or beside the specification, never TableGen of ours.
- *Class*: integration mismatch; corrections.

### 1.17 P0 §6, "pass names in tests" go

**Holds.** The deletions are §2.9.

### 1.18 The checkout

`tests/spec/` holds 36 directories of one `output` file each, dated
2026-10-18 19:48 (*measured*, `stat`), 32 of whose names live today as
`tests/<name>` (*measured*); with `tests/build`, these are no tests, and
`discover` refuses the whole run when any directory of `tests/` is no
test (`harness/Main.idr:192-200, 274-275`, *read*). In this checkout no
suite starts. The files predate P0 (the pre-purge layout of d346040c).
*Class*: a defect of the checkout, not of the design; the coordinator's
tree, untouched here.

## 2. Boundaries

### 2.1 The kinds of test, as records

- **Program test**: `Main.idr` and its modules, `packages`, and
  `cases/<case>/`. The case record, parsed once:
  `Case { stdin : Bytes; stdout : Bytes; ending : Spec.Ending;
  stderr : Bytes; libm : List Nat }`. `expected-exit` and
  `expected-crash` give way to `expected-ending` (a constructor of the
  specification's ending sum, an exit carrying its status) and
  `expected-stderr` (committed bytes, empty when absent). An exit beside a
  crash is unrepresentable. Module properties are `mlir.expect` lines
  `<Spec.Stage>: <property>...` (§2.2).
- **Reject**: `-- expect: <rule>, line N` and `-- message:` in
  `Main.idr`, and `near/`. Record `Reject { rule : Spec.Rule; line : Nat;
  message : Maybe String }`, compared with the typed report. The
  directory's name is free (the rule-phrase prefix, `profile.sh:63-67`,
  goes: the header holds the rule once).
- **Fixture**: one `.mlir`, its input in the dialect, its RUN lines a
  stage slice (`--idr-pipeline=from:<stage>,to:<stage>`) and a property
  (`--idr-expect=holds=...`) or `%differential`; its subject a shape a
  pass must handle that a program test cannot reach.
- **Script**: `run`, for what is no compilation (the tree's rules,
  upstream reproducers, generated-file checks).
- **Generated**: `semantics@<name>` (Sem), the fuzz seeds, and the scale
  fixtures (§2.5).

### 2.2 The compiler's test API

Every item is a test's check or an output; none selects how a program is
compiled (the rule of `Passes.td:3-5` and `tests/no-behaviour-options`).
- `--idr-contracts`: relations at every pass boundary, on per-function
  records (lane 19 C7) rather than a module clone (`Contracts.cpp:306`):
  `quantities-kept` and `linear-kept` restated (§3.3),
  `effects-not-widened` over D22's row, `crash-sites-not-added` over
  D27's `crash` resource, `folds-balanced`. Each keeps its planted breaker
  (`test-idr-break-contract`).
- `--idr-expect=holds=<properties>`: as today, the vocabulary generated
  from Idris records.
- `--idr-expect-at=<stage>:<properties>`: properties checked in process
  after every pass from the one that sets the stage to the one that
  leaves it (§4 I1). `mlir.expect` reads into it; no dump is printed.
- **Universal stage properties**, on whenever `--idr-contracts` is: D24's
  in-place obligation honoured (owned stage); D26's three frame-limited
  invariants (owned stage, §2.6); D30's every tail-position call a jump
  (lowered: `musttail` with `tailcc`, a loop or a join); D31 and D32's
  every call on a cycle a tail call, a loop or a frame push (lowered);
  the quantity rules of §3.3.
- `--idr-pipeline=from:<stage>,to:<stage>` on `idris-mlir-opt`: the
  registered pipeline's slice, from the generated table (L03).
- `--emitted=<path>` on `idris-mlir`: the module the frontend emitted,
  written whatever the verdict, an output as `--report` is.
- `--report=<path>`: verdict, diagnostics each with its `Spec.Rule`, and
  statistics, in a form the harness reads through generated code, never
  grepped.
- **Action tags** from the generated pipeline table. An optimization
  role's transforms are actions, each skippable; a promise's obligation
  (D24's rebuild, D30's tail kind, D34's destination) is lowering-role and
  never an action.
- **Work counts**: one statistic per solve, declared with its pass in the
  table, read from the report.
- **Footprint per pass**: the instrumentation lanes 13 and 21 ask for, its
  measure named by the tools' platform layer.

### 2.3 The runtime's test API

- The **checked runtime** (`libidris_rt_checked.a`,
  `runtime/CMakeLists.txt:248-256`, *read*) keeps freed cells marked and
  never reuses them (`Cells.cpp`, `freeCell`). It gains: cells live at
  main's return end the run with D37's internal-error ending, naming the
  count. Pending §6: a typed record of peak live bytes and the stack's
  high water.
- The **shipped runtime** counts nothing and reads no environment.
- The **ending table** is generated from the specification (D37), and
  the runtime, the harness and the documentation read it.

### 2.4 The invariant set

The tests whose inputs P0 does not touch and whose checks are behaviour:
- the 907 cases of 234 program tests, each compared whole (stdout, ending,
  stderr) under the checked runtime;
- the 47 rejects (rule, line, message) and their 47 neighbours (compiled,
  every case holding);
- the 144 `semantics@` runs, each also on stdin values (§4 I10);
- the 30 benchmarks' outputs against clang's C;
- the fuzz seeds (1, 2 and a drawn seed, `tests/fuzz-seeds/run`) and the
  lazy fuzzer's.

Not in it: `mlir.expect` lines (module properties, restated by stage in
S2), fixtures (their input is the dialect), and `--idr-contracts` (the
compiler's own relations). It changes only in the step of a ruling that
changes what a run shows (D13, D37, D38 at the latest in S2), with that
ruling named.

### 2.5 The scale fixtures (S1)

Each is a generator in the harness's Idris over the specification's
generated builders (D50), so it emits the new dialect at S5 with no edit.
Each runs at two sizes and asserts relations: every solve's counted work
at 2N is at most 2.2 times its work at N, and every pass's footprint
likewise. 2.2 is *conjecture*, to calibrate on the first run (debt).

| fixture | shape at N | wall it reproduces | passes crossed |
| --- | --- | --- | --- |
| wide match | one function, a match of N = 20,000 cases, every tenth a crash case, each building and consuming a cell | e96bb991 (graph build per terminator and successor); 4dde6b7f (greedy driver over many-region ancestors, patch 62; liveness per region successor, patch 63); 101edbc5 (ancestor walks); 21 P-11 (crash cases unknown in e96bb991's) | every stage |
| labels | 65,536 closure labels on one key on a capture cycle (`defunc-tag-limit`'s program) | 7adc6095 (label solve, about 4.3·10⁹ items projected) | the higher stage |
| functions | 70,000 functions, a DAG with one SCC of 1,000 | ffa91113 (state per value, 627 GB); 16005000 (remove-dead-values, 52 GB); upstream/05 (callee lookup); 21 §3.4's predicted Ranges, Returned, Borrows | every stage |
| component | one SCC of M = 200 members over R = 20 result types, binds nested | 16005000 (frames' clones per member and answer, 43 GB): work O(M + R) under D31, never O(M·R) | frames |
| long function | one function of 100,000 values with candidate stack cells | b8301ebe (a bit vector per value per edge, 47 GB) | counting, the stack inference |
| types | 7,000 families, half reaching a chain of the rest | 73bba53f (table rebuilt per declaration, 843 s at 6,988 types); b9d4d592 (printed text holding every body) | the higher stage, the verifier |
| nesting | an `else if` ladder of depth 10,000, and a chain of 100,000 non-tail calls | D33 (MLIR's recursion on nesting; ours on call depth) | parse, verify, print, every pass, on the tools' stack |
| threads | `functions` at one thread and at the pool | 98c6315c (the context's write lock); determinism | every stage |

The nesting ladder also exists as Idris source, through the frontend
(the elaborator's own recursion, D45). The rest bypass the frontend,
whose cost at these sizes is not what they test.

### 2.6 The discriminator of every promise

"Type" is a representation that refuses the bad construction; "test" is
a check that fails before the change and passes after (FB/PA), with the
path it runs on.

| promise | discriminator | kind | path |
| --- | --- | --- | --- |
| D24 verdict read off the program | `uniqueness-shared-rebuild` refused and its `near/` passing under every optimization skip set | test, FB (*conjecture*, 08 NQ1) / PA | `idris-mlir --emitted`, then `idris-mlir-opt --idr-target --idr-pipeline` per skip set, `idris-mlir` link with the checked runtime |
| D24 (and AGENTS.md: acceptance a property of the program) | every reject and every invariant-set program keeps its verdict under one drawn skip set per run, seed named | test | as above, sampled |
| D24 rebuild obligatory | the near's rebuild recycles its parameter's cell with no uniqueness test and no new cell of its type, with every optimization action skipped | universal property (owned) + test | `--idr-contracts`; cases under the checked runtime |
| D24 exact against the rule | generated straight-line programs over `LList` (build, rebuild, read, share); the harness's own statement of "exclusive at the call" (no later use, no alias) against the verdict | test (search, specification oracle) | program path |
| D24 quantity 0 never a cell | `Idr_Quantity` has no zero case (`IdrBase.td:83-84`) | type | — |
| D26 frame-limited, static | at the owned stage, after every pass of it: (i) a borrowed argument is used by the caller after the call, or its type bounds what it reaches; (ii) between the last use of an owned value of dynamically sized type and its release no op acquires memory (`Allocate` on `heap`); (iii) a reuse token of a dynamically sized cell is consumed before the next acquisition on every path (C1) | universal property; planted breaker moving a drop past an allocation | `--idr-contracts` |
| D26 frame-limited, dynamic | peak live bytes at n and 2n for one program per "Never" (borrowed past its last use; a dead string across an allocation; a structure past its last use) and for the benchmarks: growth within the reachable growth plus depth times a constant | test (§6) | checked runtime |
| D30 tail position one fact | the verifier holds a call carrying the tail fact to tail position; a planted pass inserting an op after it fails naming the call | type (verified) + planted breaker | every pass |
| D30 every tail call a jump | lowered: every tail-position call `musttail` with `tailcc`, a loop or a join; FB on a program whose cyclic tail call passes a frame-candidate value (`TailCallPlan.cpp:108-112`) / PA | universal property | `--idr-contracts` |
| D30 at run time | `mutual-pure-tail-calls` (10⁷), the tail-call program above (10⁶ deep), on D32's stack | test | program path |
| D31 three gaps | one program per gap (members with different rows; a member with two results; a result no field may hold), 10⁶ binds deep, on D32's stack; lowered property as D32's | test, FB (on a small stack) / PA | program path |
| D31 one stack per result type | a push of a frame of another result type is a type error | type | verifier |
| D32 cycles off the native stack | lowered: every call on a cycle a tail call, a loop or a frame push; FB on `deep-recursion` (non-tail, on the native stack today) / PA | universal property | `--idr-contracts` |
| D32 small and bounded | the invariant set's deep programs (`deep-recursion`, `foldlm-deep`, `map-deep`, `traverse-deep`, `sequence-deep`, `replicate-take-deep`, `dup-deep`, `tail-loop-deep`) on the computed stack | test | program path |
| D32 the bound sound | the test re-derives the longest acyclic path from LLVM's `.stack_sizes` section and holds the executable's constant to it plus the margin; a chain of 200 tail calls weighs one frame | test (second derivation we own) | executable, pinned `llvm-readobj` |
| D32 no frame over the guard | a planted LLVM-dialect function with a frame larger than the guard: the build fails with an internal error naming it; FB (nothing checks, 18 R-STK-1) / PA | test | `idris-mlir -c` |
| D32 guard reached | a runtime program recursing on the runner's stack ends with SIGABRT after `fatal: ... stack guard`; FB ("stack exhausted", status 1) / PA | test | `tests/runtime-start`'s form |
| D33 | the nesting fixture finishes on the tools' stack; FB (on a small tools' stack, MLIR recurses) / PA, each upstream fix with its `tests/upstream-<bug>` | test | `idris-mlir`, `idris-mlir-opt` |
| D34 | one program per promised shape, 10⁶ deep, on D32's stack: two constructors around the call; across a rejoin (`filter`); an IO action (`mapM` in IO); a pair around the call; on an exclusive list, no new cell of its type (peak, §6) | test | program path |
| D35 | where the host accepts an address-space limit, hello and an allocating program pass under 512 MiB; FB (64 GiB of stack alone) / PA. Where it accepts none (macOS, *measured*), the test has no case and its transcript, the same on every host, says what was run | test | program path |
| D36 | where the host delegates a cgroup: a program allocating past `memory.max` ends 111 with the named message, output flushed; FB (a kernel kill) / PA. Everywhere: the platform layer's reader on planted files | test | program path; runtime box |
| D37 | `tests/endings`: one program per row (returned 0; `exit 42`; `exit 256` internal; crash 1; out of memory 111, `crash-integer-shift-huge`; cannot run 126, `page-size-mismatch`; internal error via the guard), committed stderr; FB (every crash 1) / PA. This test alone pins the table against the promise; every other case reads the table | test | program path |
| D38 | a crash at a known site: committed stderr `<program>: fatal: Main.idr:L:C: <cause>`; lowered module: one global per cause and per file, none per site; FB (per-site strings, 12 CV-16) / PA | test + lowered property | program path |
| D49 | `tests/spec-current`: regenerate into a temporary tree, compare byte for byte; on a copy, a hand edit fails naming the file, a specification or generator change makes the files stale, a comment-only change leaves them current; a planted stale stamp refuses the C++ configure | test | `make check` |
| D52 | `tests/spec-self`: the generator built by idris-mlir writes the committed files byte for byte; its core is pure and prints strings and integers only | test + type | `make test` |

### 2.7 Constructor provenance

| fact the design depends on | constructed by, and who alone may | read by |
| --- | --- | --- |
| a program's stage | the pass whose `sets` is that stage (the generated table); nothing else writes `stage` | slices, stage properties, `%differential`, `StagedPass` |
| the stages, endings, rules, crash causes, primitives as closed sets | the specification (D50, C6, C7) | compiler, frontend, harness |
| the ending of a run | the runtime's exit paths alone (return, exit, crash entry, out of memory, cannot run, internal) | the harness, by status and committed stderr |
| the status of each ending | the specification's ending table | runtime, harness, documentation; pinned by `tests/endings` |
| a crash site | the frontend, from the TTC's term locations (374e0e77), on the op; passes copy, the lowering hands it to `idris_rt_crash_at` | the runtime's message |
| a refusal's rule | the refusing check, from the specification's rules | the typed report, then the harness |
| a binder's quantity | Emit, from Idris's `RigCount` (lane 17 C5); a clone's, by one derivation from its source's (§3.3) | the verifier, the contracts |
| a binder's identity | Emit, as typed location metadata (§3.3) | `quantities-kept` |
| a field's quantity | the family's declaration (D48), Idris's or the declaring pass's | the verifier at `con` and `match` |
| the in-place obligation | D24's rule, read before counting, alone | counting, reuse, the stack inference, the universal property |
| a call's tail fact | the tail decision, once (D30) | the verifier, the lowering, the stack bound |
| a frame's size | LLVM's code generation | D32's bound; the test's second derivation |
| the stack bound | the build (D32) | the runner; the test |
| a solve's work count | that solve, declared in the table | scale fixtures |
| a pass's footprint | the footprint instrumentation | scale fixtures |
| an action tag | the generated table | the skip-set sampler |
| the emitted module | the frontend | `--emitted`'s readers |
| a generated file's stamp | the specification's generator | the C++ configure; `make check` |
| live cells, peak, high water | the checked runtime alone | the ending (leak); §6 |

### 2.8 Consumers, errors and cleanup

- A broken relation or property is an error naming the property, the
  stage and the pass that broke it (`Contracts.cpp:124-126` already
  writes `contract X broken by <pass>`); a pass's name in a diagnostic is
  text for a human.
- A failing case prints its name and the field that differs; a scale
  relation prints both sizes and both counts; a skip-set failure prints
  its seed.
- A rejection leaves no artifact but the outputs asked for (`--emitted`,
  `--report`), which `no_artifacts` must exempt.
- The work directory is the test's own (`one.sh`), removed with it.

### 2.9 What goes

| path | symbol or lines | replaced by |
| --- | --- | --- |
| `harness/lib/mlir.sh:5-116` | `checked_steps`, the tree-printer use of `dump_options`, `step_dumps`, `step_of`, `step_module` | stage properties in process (I1) |
| `harness/lib/expect.sh:29-47` | `check_expect`'s step lookup | `--idr-expect-at` |
| `harness/lib/differential.sh` | `lit_pipeline_from` (`:15-48`), the stage `sed` (`:58`), the live-cells `sed` (`:166`); status-and-stdout only (`:155`) | stage slices; the whole ending compared (I13) |
| `harness/lib/run.sh:26-39` | `run_ours` | the checked runtime's ending (I5) |
| `harness/lib/e2e.sh` | `expected-exit` beside `expected-crash` (`:108`), the literal 1 (`:161, :164`), the prefix (`:178`) | `Case`'s `ending` and `stderr` |
| `harness/lib/profile.sh` | report text parsing (`:69-104`), the directory-prefix rule (`:63-67`) | the typed report; the header |
| `harness/lib/lit.sh` | idris-mlir's statuses spelled (`:100-101`); RUN lines rewritten by `sed` (`:229-231`) | the driver's definitions; checks set by the harness's environment |
| `harness/lib/actions.sh:22-27`; `tests/actions-skip-programs/expected` | hand-spelled tags | the table's tags |
| `harness/lib/determinism.sh:174`; `heap.sh:119`; `fuzz.sh`'s `after:idr-optimize` | steps by pass | stages |
| `harness/Prims.idr:3-10` and the domains' guard comments (`:535-560`) | the hand copy of Idris's primitive list | the specification's list; meanings stay ours (I8) |
| `harness/harness.ipkg:7`; `Main.idr:61`; `Runner.idr:17, 53, 69, 73`; `Lock.idr:14` | `contrib`, `test`, `Test.Golden`, `system`, `Language.JSON` | the runner on both hosts (WU9) |
| `tests/expect-coverage/run:23-31` | the `sed` over `Lookup.cpp` | the generated list |
| `Transforms/Expect.h`'s declarations; `Expect/Lookup.cpp` | 82 hand declarations, the hand table | generated from Idris records |
| `Expect/Quantities.cpp` | `keyOf` (`:38-69`), the silent drop of a colliding key (`:117-119` in `quantitiesKept`), `spelled` | identity and derivation (I4) |
| `Contracts/Contracts.cpp` | the module clone (`:306`), the length guard (`:145`), hand `Relation` and `Breakable` | per-function records; derivation |
| `runtime/Io/Ending.cpp:18-31, 48`; `Alloc/Cells.cpp` `liveCells` in the shipped build | `reportLiveCells`, `IDRIS_RT_LIVE`, the shipped count | the checked runtime |
| 291 fixture RUN lines; 56 step lines in 44 `mlir.expect` | transform passes and steps by name | stage slices; stage properties; 13 `constant-stack` and 14 `tail-calls` lines become universal properties |
| `tests/defunc-tag-limit` | the awk generator, the pass flag | the `labels` scale fixture |
| `bench/run.sh:95-96, 201-207` | raising `ulimit -s` | nothing: the program's stack is its own |
| five tests' comments | "the 1 MiB stack the harness gives" | deleted |
| 260 prose `expected-error` lines, 53 SSA-name lines, 13 op-name lines, 84 `facts:` remarks (19 T4, T5, T7, T8) | brittle checks | deleted outright (the owner's rule), shared properties covering their claims |

### 2.10 Distinctions that must remain

- Program tests (Idris input, immune to the dialect) and fixtures (IR
  input): essential, since the frontend may never emit a shape a pass
  must handle.
- At most once before counting and exactly once after, for references:
  essential (before counting, an unused linear value is a release the
  counting inserts; after, every consumption is explicit).
- A lowering role (an obligation) and an optimization role (a skippable
  action): essential; D24, D30 and D34 are obligations.
- The checked runtime and the shipped one: essential; a universal oracle
  costs what no shipped program may pay (D10).
- Behaviour (the invariant set) and module properties (stage-scoped):
  essential; only the first is frozen.
- One test pinning the ending table against the promise, every other case
  reading the table: essential; otherwise a wrong table is checked by
  itself.

### 2.11 Seams

| lane | the declaration both sides write against | state |
| --- | --- | --- |
| L03 | the generated pipeline table (pass, role, `requires`, `sets`, tags, work count); `Spec.Stage`, `Spec.Ending`, `Spec.Rule`, the crash causes, the primitive list importable by the harness; the idr-expect records; the generator's pure core | unfixed: the table's work-count column and the records' module |
| L07 | D26's carrier ("computed ... for each function") and the three owned-stage invariants | unfixed |
| L08 | D24's rule read before counting; exclusivity's independence from every optimization role | fixed by D24; the skip test checks it |
| L10 | the tail fact on the call; one frame stack per result type; the stack bound as an executable constant | fixed by D30 to D32; the constant's symbol unfixed |
| L11 | the ending table; `idris_rt_crash_at`; the program's name as a constant; causes that name a function; the checked runtime's leak ending; §6's record | unfixed: the name, the function-naming causes |
| L13, L15 | D41's three instantiations | fixed; Sem on stdin needed (I10) |
| L14 | determinism across thread counts per solve (19 C5) | outside D24 to D52; noted |
| L16, L17 | `--emitted`; binder identity from the TTC; Emit reading quantities, never counting them (17 C5) | unfixed |
| L18, L20 | the quantity of a closure-sum constructor after defunctionalization (§3.2) | unfixed |

## 3. QTT

### 3.1 Where quantities travel through the tests' reach

- **Idris's checked TT**: every binder carries a `RigCount` (0, 1, ω).
- **TTC to frontend**: erasure is decided by five readers with different
  defaults today (17 FB-15); D44 makes it one, from the fork's
  `eraseArgs`.
- **Frontend to Emit**: Emit counts each linear binder's uses and holds
  it plain past one (`Emit/Bodies.idr`, `heldAs` and `holdFor`,
  *read*), because the translation copies `Rig1` onto terms it rewrote
  (17 FB-28). Every test of quantities takes the emitted module as its
  reference (`Quantities.cpp:102-104`), so a demotion at Emit is invisible
  to all of them (17 FB-31).
- **The IR**: quantity 0 is no value and unrepresentable (`Idr_Quantity`
  is `One | Many`, `IdrBase.td:83-84`); 1 is `!idr.lin<T>`; ω is the
  bare type (`IdrTypes.td:264-278`). A closure is at quantity one exactly
  when a capture is (`IdrClosureOps.td:18-26`).
- **After every pass**: the verifier holds each value of quantity one to
  at most one use on every path (`IR/Verify/Linearity.cpp`, called from
  `Program.cpp:304`), and, from the counted stage, each reference to
  exactly one consumption (`Verify/Owned.cpp:1-16`).
- **At pass boundaries, in tests**: `linear-kept` compares the
  parameter and result quantities of each function a pass kept
  (`Contracts.cpp:141-160`); `quantities-kept` compares binders found by
  location with the emitted module (`Quantities.cpp`).
- **Counting**: D24 makes a quantity-1 parameter of an `in_place` type
  subject to the rebuild; exclusivity (`!idr.excl`) is the caller's
  separate fact.
- **LLVM**: quantities end at the lowering; nothing after reads them.

### 3.2 Where a quantity is lost today

- **Clones.** `linear-kept` compares nothing for a function a pass made
  ("compared with nothing: a copy it makes", `Contracts.cpp:113`), so a
  specialization or TRMC clone may weaken `!idr.lin<T>` to `T` and use
  the parameter twice with no check failing.
- **Length changes.** `linear-kept` skips a parameter list whose length
  changed (`Contracts.cpp:145`): a pass that drops one parameter and
  weakens another escapes.
- **Binder identity.** `quantities-kept` drops a key two binders share
  (`Quantities.cpp:117-119`), skips binders whose location is unknown or
  a bare span (`:42-68`), and skips every binder a pass made.
- **Linear constants.** A constant of quantity one is exempt from the use
  count (`Linearity.cpp:143-151`); a constant passed twice to a rebuilding
  function is then held only by D24's exclusivity (static data is never
  exclusive), which a test should pin (§3.5).
- **Constructors.** A `con` takes a linear operand only into a linear
  field (`OpsCon.cpp:29-35`), but its result carries no quantity rule, and
  a match binds fields at the scrutinee's grade (`func-linear-twice`'s
  diagnostic, *read*). Whether a linear variable reaching a linear field
  can then be read twice through an unrestricted result after
  defunctionalization turns closures into constructors is *conjecture*:
  in Idris, `let p = MkLPair x y` at ω uses a linear `x` ω times and is
  refused, while a function returning `MkLPair x y` gives its caller an
  unrestricted value. The verifier fixture of §3.5 decides it.

### 3.3 "Quantities survive every pass", made a verifier-style property

What makes a quantity loss unwritable, in four parts, then the relation
that remains:
1. **No flow from quantity one to ω** but the one cast that is the
   value's one use (today `lin.use`, `IdrOwnershipOps.td:416-425`;
   §5.3 merges it with `lin.enter`). A call's operands, a `con`'s fields,
   a yield's and a return's operands match their positions' types
   exactly, quantity included, so weakening at any flow is a type error
   the verifier reports at the op.
2. **A match binder's type is derived, never written**: the family
   declares each field's quantity (D48), and the binder's type is the
   field's times the scrutinee's (Idris's product, `Grades.h`'s
   `times`). A pass cannot give a binder another quantity, because no
   operand or attribute holds one.
3. **A clone's signature is derived by one function** from its source's:
   a kept parameter keeps its quantity, a split one (arity raising) gives
   each part the whole's times the field's, a dropped one is gone; D48's
   substitution of erased parameters leaves quantities untouched by
   construction. The specializer, defunctionalization's dispatch and TRMC
   call that one function; none chooses a quantity.
4. **A binder's identity is a typed location**: Emit fuses each binder's
   location with `#idr.binder<definition, index>`, a typed identity (no
   string), which passes copy with the value as MLIR copies locations.
   Locations are not discardable attributes, so AGENTS.md's ban does not
   apply.

What remains a relation, checked by `--idr-contracts` on per-function
records: each kept function's signature quantities unchanged (no length
guard: positions map through the derivation), each made function's
signature equal to its derivation, and each binder found by its identity
at the quantity the emitted module gave it. The boundary's half (17 C5)
holds the emitted quantities to Idris's: Emit reads them from the typed
table and counts nothing. The planted breakers: weaken a binder, weaken
a clone's parameter, weaken a field; each fails at the op or at the
boundary, naming the pass.

### 3.4 "Used once on every path, after every pass"

- **Holds today** as at most once on every path for every value of
  quantity one (`Linearity.cpp`), and exactly once for every reference
  from the counted stage (`Owned.cpp`), both in the verifier after every
  pass (`tests/verifier-every-pass` forbids turning it off).
- **Essential split**: a linear word has nothing to release, so exactly
  once binds references alone; before counting, a linear reference
  unused on a path is a release counting inserts.
- **To pin**: a planted pass that duplicates a linear use, and one that
  removes the one consumption of a reference after counting, each failing
  at the op (lane 19 E28's form).

### 3.5 Using QTT harder in the tests

- **Linearity never changes meaning** (AGENTS.md: "a performance
  property, never a correctness one"): a generator of linear programs
  (`LList`, `-@`, `!*`, rebuild and read), each run against its
  de-linearized twin (`List`, `->`, no bang): the same output and ending,
  and the linear one's peak live bytes no greater (§6). A reuse that
  rebuilds a list a closure still shares makes the outputs differ.
  Today's fuzzer generates closed expressions over primitives only
  (`Fuzz.idr:1-48`).
- **D24's rule as an oracle** over the same generator (§2.6).
- **Linear constants**: a program passing one static linear list twice to
  a rebuilding function must not write static memory: refused, or copied
  first; under the checked runtime a write to static data is an internal
  error.
- **The constructor question** of §3.2: a verifier fixture with a linear
  value put into a linear field of an unrestricted result and the field
  read by two matches; the verifier must refuse it if Idris would.
- **Facts the tests pay for again**: `quantities-kept` re-keys every
  binder by location on every check, and the contracts clone the module
  per pass to compare quantities (19 E25); both go with §3.3's
  per-function records (D10 at the compiler's own run time).

## 4. Improvements

**I1. Stage-scoped properties, and the promises as universal stage
properties.** *Coordinator.*
- *Evidence*: properties are checked at one dump after one named pass
  (`mlir.sh:29-37`, `expect.sh:29-46`), and 13 `constant-stack` and 14
  `tail-calls` lines exist only because the promise is not universal.
- *Counterexample*: a pass P0 adds after the tail decision (the lowering
  split) moves a tail call; `mlir.expect` checked `constant-stack` after
  `idr-tail-calls` only; the program then overflows D32's stack in the
  field.
- *Root cause*: the step is a pass, not the stage whose contract the
  property states.
- *Correction*: `--idr-expect-at=<stage>:<properties>` checks the
  properties after every pass of the stage, in process; D24, D26, D30
  and D31/D32's properties are on for every compilation the suite makes.
- *Deletes*: `mlir.sh:5-116`, `checked_steps`, the IR tree printer's use,
  27 per-test promise lines, every `after:<pass>` step.
- *Discriminator*: the planted breaker that moves a tail call one pass
  after the decision passes today's check and fails this one.

**I2. The invariant set is behaviour, typed, and changes only in a
ruling's step.** *Coordinator.*
- *Evidence*: 86 crash texts and one status change at D37 and D38
  (1.11, 1.12); 44 `mlir.expect` files name passes.
- *Counterexample*: `crash-integer-shift-huge` exits 1 with "out of
  memory"; D37 makes it 111; frozen, the set fails at D37's step, or the
  step edits its own oracle in the commit that changes the behaviour (19
  §8).
- *Root cause*: the set is defined as files, not as the behaviour a
  ruling may change.
- *Correction*: §2.4's definition; D37 and D38, the crash-site lowering
  included, land in S2 before the freeze.
- *Deletes*: the `expected-exit`/`expected-crash` pair, three protocol
  copies.
- *Discriminator*: `Case` makes an exit beside a crash unrepresentable;
  `tests/endings` pins the table.

**I3. Acceptance invariant under every optimization skip.**
*Coordinator.*
- *Evidence*: 08 NQ1 (`08-counting.md:1219-1233`); AGENTS.md
  ("Acceptance is a property of the program"); `Passes.td:24-27` (an
  optimization's skip changes only stack and heap).
- *Counterexample*: `uniqueness-shared-rebuild` with
  `--mlir-debug-counter=idr-reuse-site-count=0` compiles (*conjecture*
  from the read chain).
- *Root cause*: the verdict was derived from an optimization's output
  (`Transforms/Demand/Demand.cpp:59-77`).
- *Correction*: `--emitted`, and a universal sampled property: every
  reject and every invariant-set program keeps its verdict and cases
  under a drawn skip set, seed named; D24's rebuild and D34's destination
  are lowering-role, never actions.
- *Deletes*: `actions.sh`'s hand tags, `actions-skip-programs`' four
  hand-picked programs (the property covers every program).
- *Discriminator*: the boundary pair under every skip set (§2.6).

**I4. Quantities survive every pass by construction (§3.3).**
*Coordinator* (AGENTS.md: "No pass may drop what Idris proved").
- *Evidence*: §3.2.
- *Counterexample*: a specialization of `bump` at a known tail whose
  parameter becomes `LList` and whose body reads it twice: no check fails
  today.
- *Root cause*: a clone's signature and a binder's type are written, and
  binders are known by text-like keys.
- *Correction*: the four parts of §3.3 and its per-function relation.
- *Deletes*: `keyOf`, the colliding-key drop, `spelled`, the length guard,
  the module clone per pass.
- *Discriminator*: the three planted breakers of §3.3.

**I5. The leak check is the checked runtime's ending.** *Coordinator*
(D10, D37, AGENTS.md's ban on shipped counting).
- *Evidence*: 1.1 (the count in every build, `IDRIS_RT_LIVE`, three
  readers).
- *Counterexample*: `main = exitWith ExitSuccess` fails the harness with
  "no count of live cells at exit" (the case `run.sh:23-25` describes).
- *Root cause*: a test fact written as text by every shipped program.
- *Correction*: the checked runtime ends a run whose main returns with
  cells live as an internal error naming the count; program cases link
  it; the shipped runtime counts nothing. The checked runtime's
  quarantine never reuses memory: the peak footprint of every case under
  it is a measurement owed (debt).
- *Deletes*: `reportLiveCells`, `IDRIS_RT_LIVE`, `run_ours`, the
  `differential.sh` count, the shipped `liveCells`.
- *Discriminator*: a planted program that leaks one cell ends with the
  internal error under the checked runtime; the shipped binary has no
  count symbol (a `llvm-nm` check).

**I6. The small stack as the tests' amplifier.** *Coordinator.*
- *Evidence*: 1.4 to 1.8; every program runs on 64 GiB today.
- *Counterexample*: a D32 that leaves the frames plan's three fallbacks
  in place passes every test today, since `deep-recursion` recurses 10⁶
  deep on the native stack and fits.
- *Root cause*: the test environment hides the property the promise is
  about.
- *Correction*: once D32 lands, the deep programs run on the computed
  bound; add §2.6's programs for D30, D31, D34; the test re-derives the
  bound from `.stack_sizes`; the bench stops raising `ulimit -s`; the
  five stale comments go.
- *Deletes*: `bench/run.sh:95-96, 201-207`; the stale comments; the 27
  per-test promise lines (with I1).
- *Discriminator*: `deep-recursion` fails the lowered property before
  D32 and passes after.

**I7. Scale fixtures as Idris generators with scaling relations.**
*Coordinator.*
- *Evidence*: 1.15.
- *Counterexample*: e96bb991's quadratic at N = 20,000 took long enough
  to be called unfinished on stage 1, yet a finish-within-limit fixture
  passes it whenever N² fits 300 s; work(2N) over work(N) is about 4 at
  any N.
- *Root cause*: the fixtures assert completion, not growth, and are text
  in today's dialect.
- *Correction*: §2.5, over the specification's builders, with work counts
  and footprints at two sizes.
- *Deletes*: `defunc-tag-limit`'s awk and flag.
- *Discriminator*: the wide-match fixture at e96bb991's parent fails the
  relation, and at e96bb991 passes (reproducible on that history).

**I8. The harness imports the specification's closed sets.**
*Coordinator* (D50, C6, C7; the harness may import the specification,
which imports no fork).
- *Evidence*: the hand primitive list (`Prims.idr:3-10`), the guard
  comments naming `idr-lower` (`:535-560`), statuses in `lit.sh:100-101`,
  the rule phrase in directory names (`profile.sh:63-67`).
- *Counterexample*: a primitive C6 adds to the specification is absent
  from the fuzzer's table and never generated; no test fails.
- *Root cause*: the harness copies lists the specification holds.
- *Correction*: stages, endings, rules, crash causes and the primitive
  list come from `IdrisMLIR.Spec.*`; the meanings stay the harness's own,
  a total function over the specification's list, so a new primitive
  without a meaning fails the harness's build.
- *Deletes*: the copies named.
- *Discriminator*: the type (coverage refuses a missing meaning).

**I9. D49's stamp read by the C++ configure; D52's purity by type.**
*Coordinator.*
- *Evidence*: 1.13, 1.14.
- *Counterexample*: a hand edit of a generated `.td`, built by a C++-only
  bisect that never runs `make check`, compiles silently.
- *Root cause*: the stamp has no reader; the generator's purity is a
  convention.
- *Correction*: the configure step checksums the specification and the
  generator's sources and each file's text and refuses on a mismatch; the
  generator's core is `generate : List (Path, Doc)` with no IO, and
  `Doc`'s leaves are `String` and `Integer`.
- *Deletes*: `tests/dialects-current` with D51's cull.
- *Discriminator*: `tests/spec-current`'s planted stale stamp; the type.

**I10. Sem on stdin values, required by D41.** *Coordinator.*
- *Evidence*: every Sem case applies a primitive to literals, so the
  compiler folds it and code generation never runs (`Sem.idr:67-70`,
  19 G11).
- *Counterexample*: under D41 the expansion of Euclidean division into
  `arith` is the IR-builder instantiation; a slip in it for `Int64`'s
  minimum by -1 passes every Sem case, which folds through the integer
  instantiation.
- *Root cause*: the oracle reaches one instantiation of three.
- *Correction*: every Sem case also on stdin values; a unit box holding
  the interval instantiation sound (random intervals and points: the
  integer result of points lies in the interval result).
- *Deletes*: `Sem.maxCases` and its self-check (19 G9).
- *Discriminator*: a planted wrong expansion fails the stdin variant only.

**I11. Linearity's metamorphic relation and D24's oracle, by search.**
*Coordinator.*
- *Evidence*: §3.5.
- *Counterexample*: a reuse that rebuilds in place a list a closure still
  shares prints a different list from the de-linearized twin; nothing
  generates such programs today.
- *Root cause*: the search space has no linear programs.
- *Correction*: a linear-program generator (Gen's typed tapes) with two
  oracles: the twin's output and ending, and the harness's statement of
  exclusivity for D24.
- *Deletes*: nothing.
- *Discriminator*: the planted unsound reuse (a reuse action forced on a
  shared cell) fails the twin relation.

**I12. D26 qualified dynamically through the checked runtime.** *Owner*
(§6; it extends D37's "tests read the status and the committed standard
error").
- *Evidence*: 1.3.
- *Counterexample*: a list borrowed past its last use across a second
  list of the same size: peak 2n where D26 allows n; every current test
  passes (zero live at exit).
- *Root cause*: no measure of the peak exists in any form a test reads.
- *Correction*: §6's option (a).
- *Deletes*: nothing.
- *Discriminator*: the planted programs of §2.6's dynamic row.

**I13. `%differential` compares the whole ending, without common mode.**
*Coordinator.*
- *Evidence*: status and stdout only (`differential.sh:155`); BEFORE is
  lowered by the same pipeline as AFTER (19 S10).
- *Counterexample*: a pass that turns a division-by-zero crash into an
  array-bounds crash passes: both exit 1 with empty stdout.
- *Root cause*: the ending reduced to its status; the reference shares
  the code under test.
- *Correction*: the ending and stderr compared; BEFORE lowered through the
  slice with every optimization action skipped, so the two programs share
  only lowering-role passes.
- *Deletes*: `differential.sh:15-48, 58, 166`.
- *Discriminator*: a planted pass that swaps two crash causes fails.

## 5. Work units

Drafts only; none is dispatched by this swarm. Each unit's acceptance is
behaviour. None names a pass in a test, adds an option that selects how a
program is compiled, or keeps the form it replaces.

**WU1. The driver's test outputs and checks.**
- *Writes*: `foreign/idr/lib/Driver/Options.cpp`,
  `foreign/idr/tools/idris-mlir-opt.cpp`,
  `foreign/idr/lib/Transforms/Contracts/Stages.cpp` (new),
  `foreign/idr/include/idr/Transforms/Contracts.h`.
- *Outcome*: `--emitted`, `--idr-expect-at`, the universal stage
  properties of §2.2.
- *Deletes*: nothing yet (WU2 and WU9 delete the shell side).
- *Must not*: name a pass in a property; dump a module to find a step.
- *Acceptance*: the I1 breaker fails; a rejection leaves exactly the
  outputs asked for.

**WU2. Endings and `%differential` in the harness.**
- *Writes*: `harness/lib/run.sh`, `harness/lib/e2e.sh`,
  `harness/lib/differential.sh`, `harness/README.md`, every
  `tests/*/cases/*/expected-{exit,crash}` and `near/` counterpart (86 and
  4), `tests/exit-with/cases/256`, `tests/endings` (new).
- *Outcome*: `Case` with `ending` and `stderr`; the whole ending compared
  in `%differential`; no common mode.
- *Deletes*: §2.9's rows for these files.
- *Must not*: parse stderr; spell a status.
- *Acceptance*: `tests/endings` shows every row; I13's breaker fails.
- *Depends*: L11's ending table and checked runtime.

**WU3. idr-expect from Idris records.**
- *Writes*: the records' module beside the specification (L03 fixes it),
  `foreign/idr/include/idr/Transforms/Expect.h`,
  `foreign/idr/lib/Transforms/Expect/Lookup.cpp` (generated),
  `tests/expect-coverage/run`.
- *Outcome*: one record per property (name, argument shape, sentence);
  declarations, table and the coverage list generated.
- *Deletes*: the hand declarations, the hand table, the `sed`.
- *Must not*: let a property name an op class (each reads a declared
  fact, lane 19 C1).
- *Acceptance*: a property declared and used by no test fails coverage.

**WU4. Quantities by construction.**
- *Writes*: `foreign/idr/lib/Transforms/Expect/Quantities.cpp`,
  `foreign/idr/lib/Transforms/Contracts/Contracts.cpp`, the verifier's
  match and `con` rules (L04 holds the family's).
- *Outcome*: §3.3's relation per function; the derivation function the
  cloning passes call.
- *Deletes*: §2.9's rows for these files.
- *Must not*: keep a binder by location text; skip a changed list.
- *Acceptance*: the three planted breakers fail; `--idr-contracts` costs a
  record per function (measured on the `functions` fixture).
- *Depends*: Emit's binder identity (L16, L17).

**WU5. Acceptance under skips, and D24's oracle.**
- *Writes*: `harness/lib/actions.sh`, `tests/acceptance-under-skips`
  (new), `tests/uniqueness-shared-rebuild/expected`,
  `tests/actions-skip-programs` (deleted).
- *Outcome*: §2.6's D24 rows.
- *Deletes*: the hand tags and four hand-picked programs.
- *Must not*: draw from the clock without printing the seed.
- *Acceptance*: every reject keeps its verdict under every skip set.
- *Depends*: WU1, the generated tags (L03).

**WU6. Stack, tail call, frames and TRMC programs.**
- *Writes*: new program tests for D30, D31 (three), D34 (four);
  `tests/stack-bound`, `tests/frame-over-guard` (new); the five stale
  comments; `bench/run.sh`.
- *Outcome*: §2.6's D30 to D34 rows.
- *Deletes*: the bench's stack raising.
- *Must not*: rely on a property naming a pass.
- *Acceptance*: each passes on D32's stack; `deep-recursion` passes the
  lowered property.
- *Depends*: L10's design, landed.

**WU7. Space.**
- *Writes*: the owned-stage invariants (with L07); planted programs per
  "Never"; the dynamic tests if §6 is (a).
- *Outcome*: §2.6's D26 rows.
- *Must not*: read RSS.
- *Acceptance*: each planted violation fails; the benchmarks hold the
  relation.

**WU8. Scale fixtures.**
- *Writes*: `harness/Scale.idr` (new), `tests/scale-*` (new),
  `tests/defunc-tag-limit` (deleted).
- *Outcome*: §2.5.
- *Must not*: assert seconds.
- *Acceptance*: the wide match fails at e96bb991's parent and passes at
  e96bb991.
- *Depends*: WU9 (the package's module list), L03's builders and work
  counts.

**WU9. The runner on both hosts, reading the specification.**
- *Writes*: `harness/Main.idr`, `Runner.idr`, `Lock.idr`, `Prims.idr`,
  `Gen.idr`, `Fuzz.idr`, `Lazy.idr`, `TwoLevels.idr` (deleted),
  `harness/harness.ipkg`, `harness/one.sh`, `harness/lib/profile.sh`,
  `harness/lib/lit.sh`, `harness/lib/mlir.sh` (deleted),
  `harness/lib/expect.sh`, the runner lines of `Makefile`.
- *Outcome*: lane 19 C8 with I8.
- *Deletes*: §2.9's rows for these files.
- *Must not*: depend on `contrib` or `test`; copy a closed set.
- *Acceptance*: the runner built by idris-mlir runs `make check`.

**WU10. Fixture triage at the dialect cutover.**
- *Writes*: the 339 fixture directories.
- *Outcome*: each fixture whose subject is a program's behaviour becomes
  a program test; each whose subject is a pass's IR shape is rewritten in
  the new dialect with a stage slice and a property or `%differential`;
  each brittle check deleted.
- *Must not*: regenerate a REF from the new pass's output (19 §8).
- *Acceptance*: no fixture names a transform pass or spells an SSA name.

**WU11. Generated files.**
- *Writes*: `tests/spec-current`, `tests/spec-self` (new);
  `tests/dialects-current` (deleted); the configure check (with L03).
- *Outcome*: §2.6's D49 and D52 rows.
- *Acceptance*: the planted hand edit and stale stamp fail.

**WU12. Hosts.**
- *Writes*: `tests/strict-host`, `tests/memory-limit` (new); the reader's
  box (with L11).
- *Outcome*: §2.6's D35 and D36 rows.
- *Must not*: branch on the operating system; the case set comes from
  probing the host's capability.
- *Acceptance*: on Linux both fail before and pass after; on macOS both
  print the same transcript and run what the host allows.

**WU13. Sem on stdin, and D41's soundness box.**
- *Writes*: `harness/Sem.idr`, `tests/semantics`,
  `foreign/idr/unittests/` (a new box).
- *Outcome*: I10.
- *Acceptance*: a planted wrong expansion fails.

## 6. Owner questions

**Q1. How is D26 qualified at run time?** D26 is a promise to users:
each call holds at most a fixed number of bytes it no longer needs. A
static check (§2.6's three owned-stage invariants) holds the IR to what
the counting placed; only a run shows that the bound the compiler
computed is the bound the program keeps. A run's peak is a number, and
D37 says tests read the status and the committed standard error, never
parsed text.
- **(a) A typed record from the checked runtime only**: peak live bytes
  and the stack's high water, in a layout generated from the
  specification, written where the harness reads it through the same
  generated code. *Buys*: relations between runs (peak at 2n against
  peak at n), the planted "Never" programs, the benchmarks' space. *Costs*:
  one channel beyond status and stderr, in the test runtime alone; the
  shipped runtime pays nothing.
- **(b) A bound handed in, and exceeding it an internal error**: the
  checked runtime reads a byte bound and ends with D37's internal error
  past it. *Buys*: D37's sentence kept to the letter. *Costs*: a bound per
  test written by hand (a constant that drifts), no relation between
  runs.
- **(c) Static only.** *Buys*: no runtime change. *Costs*: the promise is
  checked against the compiler's own reading of it, never against a run.

*Recommendation*: (a). A record generated from one source is not text
parsed back, the cost falls on a runtime no user links, and only (a)
lets a test state the promise's shape (growth within a bound) rather
than a number.
