<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Cull audit: carried patches, pins, dependencies, libraries

Area: `upstream/` (95 directories), `PINS.md` (1,726 lines, 81 entries),
`third_party/` (7 gitlinks), `libs/` (4 libraries). Method: the Elon
algorithm of AGENTS.md's "Delete before you optimize" (2026-10-23): each
part names its rule and the fact only it supplies, or it goes.

- HEAD at start: `d378e120ee0813b9c170fa5b85c294bc49a45b6d`.
- HEAD at finish: `45599c62937e14eacf92514df208217506baf610`. Between the
  two, `AGENTS.md` changed (the `believe_me` rule, D133) and C286 landed
  in the frontend; nothing in
  this area changed (*measured*: `git diff --stat d378e120 45599c62 --
  upstream PINS.md third_party libs tools tests/upstream-* runtime`).
- The user's request for this run: "keep all the sources pls." Read as:
  `sources/` (the papers and upstream documentation AGENTS.md calls
  "sources") and every source checkout under `third_party/` stay. No
  verdict here deletes either. That includes `third_party/modular`, which
  no build step reads (candidate 13).
- Measurements ran on a `git archive HEAD` export at `/tmp/deps-patches`.
  No `make` ran in the checkout, and no LLVM was built.
- Modified files: none of the files a DELETE or MERGE verdict touches is
  modified in the checkout (`git status --porcelain` on each path, at
  finish). The submodule checkouts `third_party/modular` (9211931 against
  gitlink a1ccd095) and `third_party/simdutf` (bb77e7bb against gitlink
  8d82299) are behind their gitlinks, as INT-notes says. Every verdict
  keeps both.

Owners come from `audits/p0/verify/ownership.json`: `upstream/`,
`PINS.md`, `tools/` and `.gitmodules` belong to L06; `tests/` and
`harness/` to L19; `runtime/` to L11; `libs/` to L20; `compiler/src/`
and the frontend's ipkgs to L16; `compiler/checker/` to L17;
`CMakeLists.txt` and `Makefile` to INT. `LICENSE`, `NOTICE` and
`LICENSES/` have no owner, so they fall to the coordinator.

Candidates are ranked by how many lines they delete.

---

## 1. The Idris reports that hold no patch: upstream/18, 20, 21, 50 to 55, 59

- **Part.** `upstream/18-elaboration-primitive-folding/`,
  `20-evaluator-char-text/`, `21-termination-closure/`,
  `50-erased-coverage-nested-match/`, `51-totality-unimported-callee/`,
  `52-relevant-implicit-split/`, `53-constructor-implicit-mark/`,
  `54-erased-constant-pattern/`, `55-lazy-case-scrutinee/` and
  `59-literal-partial-fold/`. Each holds a README, plus `Fold.idr` (18)
  or `Lit.idr` (59). There is no `idris.patch` in any of them.
- **Fact it supplies.** A long-form account of a bug in stock Idris that
  our type checker fixes as its own code. Nothing in the build reads it:
  the stock Idris carries no patch for these bugs (upstream/README.md's
  status rows: "not carried: nothing the stock Idris builds reaches it;
  our type checker (compiler/checker) fixes it as its own code"). The fix
  itself is already held by `compiler/checker`, and its check by the
  `tests/upstream-<bug>` program tests, which compile with our checker.
  `59/Lit.idr` is byte-identical to `tests/upstream-literal-partial-fold/Main.idr`
  (*measured*: `diff` empty), so it is a second copy.
- **Rule that once required it, and why none does now.** A report is
  "kept as a submission" (AGENTS.md's patch rule). For Idris there is no
  submission: "Nothing is sent to Idris", and the checker is "our code:
  a bug in it is fixed in it, like any of ours, with nothing kept against
  upstream". upstream/README.md's **Idris** rule says "nothing is drafted
  for it". So no rule keeps these directories.
- **Readers.** `git grep -l "upstream/NN-" -- . ':!audits'` for each:
  - `tests/upstream-elaboration-primitive-folding/run` copies `Fold.idr`
    from upstream/18;
  - comments cite the directories in `harness/Fuzz.idr:31`,
    `harness/Sem.idr:189`, `compiler/checker/README.md:602` and `:667`,
    each test's header, and the sibling reports' READMEs.
  - Nothing else reads them.
- **Exact deletion.**
  - The ten directories: 1,620 lines (`cat upstream/NN-*/* | wc -l`).
    `Fold.idr` (34 lines) moves into `tests/upstream-elaboration-primitive-folding/`.
    Net deletion: 1,586.
  - `upstream/README.md` table rows 102, 104, 105, 116 to 121 and 125: 10
    lines.
  - Edits, not deletions: the citations in `harness/Fuzz.idr:31`,
    `harness/Sem.idr:189` and `compiler/checker/README.md:602, 667`, and
    the test headers. These comments cite a document, which AGENTS.md's
    comment rule forbids anyway.
  - The tests stay: they check our checker. Whether they are renamed
    `checker-*` is L19's call.
- **Verdict.** DELETE, 1,596 lines. Confidence: *read*.
- **Owner.** L06 (`upstream/`), with edits by L19 (tests, harness) and L17
  (checker README). Waits on nothing; none of these files is modified.

## 2. Status and symptom held three times: PINS.md patch entries, the report READMEs, upstream/README.md's table

- **Part.**
  - In the 69 PINS.md entries whose workaround is an `upstream/NN`
    patch: the `- upstream:` and `- status` fields (196 lines) and the
    `- symptom:` field (381 lines). *Measured* with an awk pass over
    PINS.md that counts those fields in entries whose `workaround` names
    `upstream/NN-`.
  - `upstream/README.md:88-183`, the status table (94 rows plus the
    header).
  - `upstream/README.md:331-337`, the list of carried patches.
- **Fact it supplies.** Each patch's upstreaming status, its symptom, and
  whether it is carried. Every report's `README.md` already holds the
  first two (`## Upstreaming plan` with its status line, and the report
  itself). Which patches are carried is already held by which
  directories have an `llvm.patch`, `idris.patch`, `snmalloc.patch` or
  `simdutf.patch`, which is what `tools/patches.sh` and the bootstrap
  read. AGENTS.md: "a copy kept in step by a verifier is still a copy";
  these copies are kept in step by hand.
  - Evidence of drift: PINS.md's entries for 107 and 108 still say "code
    of ours bent around it before the patch, to go once the toolchain
    carries it" (harness/Fuzz.idr's `firstAgain`, harness/Main.idr's
    `parsePositive {a = Nat}`). Neither form is in the tree any more
    (*measured*: `grep -n firstAgain harness/Fuzz.idr` and `grep -n
    "parsePositive {a = Nat}" harness/Main.idr` give 0 hits; `checkOf`'s
    `OfFirst` is a pattern lambda again).
- **Rule.** AGENTS.md requires a PINS.md entry per patch ("its PINS.md
  entry"). It does not say what the entry holds. The PINS.md header says
  an entry is "why we carry it and when it goes". The facts only an entry
  supplies are `sites` (where our tree meets the bug), the `workaround`
  pointer, and `retire`.
- **Readers.** People, and `tests/upstream-patches`, which checks the
  READMEs' `## Upstreaming plan` and not PINS.md's status. Nothing parses
  the table (`git grep -n "upstream/README.md" -- tools tests harness`
  finds no parser of rows).
- **Exact deletion.**
  - The `upstream` and `status` lines of the 69 entries: 196 lines.
  - The table, `upstream/README.md:88-183`: 96 lines. The opening
    instruction ("follow **Sending** from the first directory whose
    status says 'send next'") then reads the READMEs.
  - The carried list, `upstream/README.md:331-337`: 7 lines.
  - Symptom lines: 381, where an entry's symptom adds nothing of our
    tree's beyond the report's.
- **Verdict.** MERGE into each `upstream/NN/README.md` (status, symptom),
  and into the file layout (what is carried). 299 lines at *read*
  confidence, plus up to 381 symptom lines at *conjecture* confidence
  (each entry needs a check that its README says the same).
- **Owner.** L06. Waits on nothing.

## 3. tests/upstream-* for reports whose patch is not carried

- **Part.** The checks that the pinned tools "still have the bug" for
  reports with no patch carried:
  - `tests/upstream-remove-dead-values-address-taken` (01, 24 lines)
  - `-composite-fixed-point-sccp` (02, 36)
  - `-remove-dead-values-unreachable` (06, 26)
  - `-remove-dead-values-unchanged-call` (16, 37)
  - `-sccp-revert-unset-property` (17, 28)
  - `-remove-dead-values-poison-operand` (22, 26)
  - `-cse-statistic-assignment` (23, 21)
  - `-bytecode-unregistered-properties` (25, 31)
  - `-liveness-non-forwarded-terminator` (28, 23)
  - `-delinearize-empty-basis` (58, 24)
  - `-liveness-trivially-dead` (63, 45)
- **Fact it supplies.** Whether upstream's tool at our pin still shows a
  bug that nothing of ours reaches. Each report says so: no
  `remove-dead-values` (C35), no upstream `cse` (D98, D100), no
  FuncToLLVM (C165). That fact only matters for sending, and sending
  checks something stronger: "Before a pull request, its diff applies to
  current main", and "CI decides". 01's test is stale on its own terms.
  It still names `upstream/06…/llvm.patch` as applied, which it is not,
  and its own comment says the report and the test go once the pin has
  #208881 (merged 2026-10-12; the pin, 416f328b, is from 2026-10-21).
- **Rule.** None in AGENTS.md. AGENTS.md keeps a report as a submission
  when its patch goes, and its patch rule's `tests/upstream-<bug>` check
  belongs to the patch. The "turned to check that the pinned tools still
  have the bug" bullet is upstream/README.md's own
  (`upstream/README.md:303-305`). The testing rule wants checks of
  behaviour our compiler guarantees; none of ours rests on these.
- **Readers.** The test runner; `tests/upstream-patches`, which reads the
  report directories and not these tests (*read*).
- **Exact deletion.** The 11 test directories: 321 lines.
  `upstream/README.md:57-58` loses "or are fixed by it" and
  `upstream/README.md:303-305` becomes "the check goes". The reports and
  their `pull-request.diff` stay (AGENTS.md).
- **Verdict.** DELETE, 321 lines. Confidence: *read*.
- **Owner.** L19 (tests), L06 (README). Waits on nothing.

## 4. PIN() markers, tests/pin-sites, and the PINS entries that record departures from cpp-starter

- **Part.**
  - 87 `PIN(name)` markers. 76 of them are the whole line `// PIN(runtime-quarantine) —
    see PINS.md` in every runtime source (75 files), plus
    `runtime/CMakeLists.txt:12`. Another is a whole line,
    `runtime/Strings/Simd.h:27`. The remaining 10 sit inside other
    comments: `CMakeLists.txt:70, 81, 252, 332, 382, 400, 455`,
    `runtime/CMakeLists.txt:25` and `tools/bootstrap.sh:1514, 1543`.
  - `tests/pin-sites/` (10 files, 84 lines), which checks that each
    marker names an entry.
  - The PINS.md entries whose "workaround" is a permanent design choice,
    each with "retire: never" or a profile departure:
    - `platform-gate` (1169-1183)
    - `darwin-inert-mitigations` (1184-1196)
    - `clang-libcxx` (1197-1211)
    - `clang-no-reflection` (1212-1221)
    - `no-sanitizer-runtimes` (1222-1235)
    - `runtime-quarantine` (1236-1250)
    - `runtime-cx16` (1251-1260)

    92 lines in all.
  - The PINS.md header's cpp-starter and PIN-site sentences (lines 8-13).
- **Fact it supplies.**
  - A pointer from code to the registry. The registry's `sites:` field
    already points from the entry to the code, so the marker is the
    reverse copy, and `tests/pin-sites` is the verifier that keeps the
    two copies in step. AGENTS.md: "a copy kept in step by a verifier is
    still a copy". A marker is also a comment that cites a document,
    which AGENTS.md's comment rule forbids.
  - `runtime-quarantine`'s site is "`runtime/`, every source there": one
    fact, about a directory, stated 76 times.
  - The seven entries restate what the CMake comment at the same site
    already says:
    - `CMakeLists.txt:251` says "snmalloc needs CMPXCHG16B, which the
      baseline lacks";
    - `:332` says "branch protection executes as NOP in a plain arm64
      Darwin process";
    - `:70` names the hosts;
    - the runtime's own profile is `runtime/CMakeLists.txt`'s.
  - `no-sanitizer-runtimes` claims "tests/mlir-layout checks that it has
    none". That is false: `tests/mlir-layout/run` checks only that the
    lint preset uses the stage-2 clang-tidy (*measured*: `grep -n -i
    "asan|sanitizer" tests/mlir-layout` gives 0 hits).
  - The facts `platform-gate` and `clang-libcxx` record (four targets;
    clang with pinned static libc++) are AGENTS.md's own rules.
- **Rule.** AGENTS.md scopes PINS.md to "every deliberate deviation from
  [upstream MLIR's layout and conventions] and every pinned workaround".
  The departures from bjornpagen/cpp-starter's profile are the PINS.md
  header's own scope, which no rule of AGENTS.md names. No rule requires
  markers.
- **Readers.** `tests/pin-sites/run` alone (`git grep -l "PIN(" -- tools
  tests harness Makefile`).
- **Exact deletion.**
  - The 76 runtime marker lines and `Simd.h:27`: 77 lines.
  - The marker clauses in the 10 shared comment lines (edits).
  - `tests/pin-sites/`: 84 lines.
  - The seven entries: 92 lines.
  - PINS.md header lines 12-13 and the cpp-starter clause (about 2 lines
    net).
  - Total: about 255 lines.
  - The entries for workarounds that stay (`runtime-library-export`,
    `simdutf-constexpr-implementation`, `idris-support-host-cc`) stay,
    found by their `sites:`.
- **Verdict.** DELETE, about 255 lines. Confidence: *read*. If the
  coordinator keeps markers for the entries that stay, the minimum is
  the 76 runtime lines and `runtime-quarantine`'s entry (91 lines).
- **Owner.** L11 (runtime), INT (CMakeLists.txt), L06 (PINS.md,
  bootstrap.sh), L19 (tests/pin-sites). Waits on a coordinator reading of
  PINS.md's scope against AGENTS.md's.

## 5. Retired history in PINS.md and upstream/README.md

- **Part.**
  - `PINS.md:24-117`, the "Retired with ... / Never carried ..." account
    (94 lines).
  - `upstream/README.md:69-86`, the 2026-10-09 test run of 01 to 08 on
    7208ba24 (18 lines).
  - `upstream/README.md:185-201`, "Gone when the pin moved ..." and "The
    order runs from least to most arguable", which describes 01 to 08 of
    a queue that has moved on (17 lines).
- **Fact it supplies.** History, which git holds. The two current facts
  inside it already live at their sites:
  - `static_assert(LLVM_ENABLE_STATS, ...)` is at
    `foreign/idr/lib/Transforms/Optimize/Optimize.cpp:44`;
  - stage 2 without LTO is at `tools/bootstrap.sh:1049, 1065`
    (`-DLLVM_ENABLE_LTO=OFF`).
- **Rule.** None. PINS.md's tombstone ritual (lines 22-24) says to
  delete what upstream fixed; it does not say to keep an account of it.
- **Readers.** None (*read*).
- **Exact deletion.** The three ranges: 129 lines. PINS.md:22-24 (the
  ritual) stays.
- **Verdict.** DELETE, 129 lines. Confidence: *read*.
- **Owner.** L06. Waits on nothing.

## 6. The licence machinery for ports (C10: "No more ports")

- **Part.**
  - `tools/licenses.sh`: lines 10-11, 23-29 (the port parts of the
    header), `port_parts()` (86-95), line 178 (`print "port"`), the port
    loop (251-279) and the `ports:` line (286). About 45 lines.
  - `LICENSE:23-26`, the bullet "Files ported from Modular's Mojo
    compiler or derived from MLIR/LLVM ...".
  - `NOTICE:5-8`, the clause "and any files ported from Modular's Mojo
    compiler ...".
  - `LICENSES/THIRD-PARTY.md:19`, the row "Modular's Mojo compiler
    (ported files, each named in PINS.md) | `idr-deduplicate`".
  - `tests/licenses/expected:2` and the port sentences of
    `tests/licenses/run:5-10, 41`.
- **Fact it supplies.** None: no file in the tree is a port.
  - *Measured* on the export: the script, instrumented to count the
    files it classes as ports, gives `PORTCOUNT 0`.
  - `git grep -l "Part of the LLVM Project|Modular Inc" -- foreign
    runtime compiler tools harness tests` finds only `tools/licenses.sh`
    itself.
  - C10 retired the deduplicator port ("its port replaced by partition
    refinement over upstream's `OperationEquivalence`"), and PINS.md's
    `eliminate-duplicate-functions` entry went with it. So the
    THIRD-PARTY row's claim, `idr-deduplicate` holding Modular's code,
    is false: `foreign/idr/lib/Transforms/Deduplicate/Deduplicate.cpp`
    is 0BSD and ours.
- **Rule that once required it.** The port of Modular's
  `EliminateDuplicateFunctions`. C10 removed it: "No more ports: fresh
  code from Modular's, CIRCT's and IREE's shapes".
- **Readers.** `tests/licenses` only.
- **Exact deletion.** About 60 lines over the files above.
  `LICENSES/Apache-2.0.txt` and `LLVM-exception.txt` stay: LLVM/MLIR are
  linked into the tools.
- **Verdict.** DELETE, about 60 lines. Confidence: *measured*.
- **Owner.** L06 (`tools/licenses.sh`), L19 (`tests/licenses`), the
  coordinator (`LICENSE`, `NOTICE`, `LICENSES/`). Waits on nothing.
- Unrelated to culling: at HEAD, `tools/licenses.sh` fails on the export
  (*measured*). The failures are `audits/` files without SPDX lines,
  `tests/musttail-matrix/*.ll`, `harness/prop/program.h`,
  `tests/shipped-accounts/calls.c`, and the fixture
  `upstream/76-pass-base-derived-class/crtp-pass.td` (candidate 7).

## 7. Patch 76, pass-base-derived-class: documentation carried into the build

- **Part.** `upstream/76-pass-base-derived-class/llvm.patch`, carried;
  its PINS.md entry (799-811); `tests/upstream-pass-base-derived-class`
  (22 lines); the test's fixture `crtp-pass.td` (14 lines).
- **Fact it supplies.** None to the build. The diff touches only
  `mlir/docs/PassManagement.md` and a comment in
  `mlir/include/mlir/Pass/PassBase.td` (*read*: every changed line of the
  diff), so no built artifact differs. The behaviour it documents (the
  CRTP splice of `baseClass`) is already proved by the build of every
  staged pass (`StagedPass`, `foreign/idr/include/idr/IR/IdrDialect.h:170`,
  29 uses in `Generated/IdrPasses.td`). The test's own comment admits it:
  "a pin that stops splicing fails before any staged pass does". The
  fixture also fails `tools/licenses.sh` (no SPDX line, *measured*).
- **Rule.** D25's "always carry the patch" covers "a change upstream we
  need, a fix or a feature". A documentation change is neither, and
  nothing of ours needs it.
- **Readers.** The bootstrap, which applies it; the test.
- **Exact deletion.**
  - `llvm.patch` → `pull-request.diff` (`mv`, the same bytes), so the
    report stays as a submission.
  - The PINS.md entry: 13 lines.
  - The test: 22 lines.
  - `crtp-pass.td`: 14 lines.
  - `upstream/README.md`'s carried list loses 76.
- **Verdict.** DELETE (stop carrying), 49 lines. Confidence: *read*.
- **Owner.** L06, L19. Waits on a coordinator reading of D25's "always
  carry" for a patch that changes no built file.

## 8. Patch 97, bytecode-numbering-iterative: reached only by another patch's test

- **Part.** `upstream/97-bytecode-numbering-iterative/llvm.patch`,
  carried; its PINS.md entry (1091-1109, 19 lines);
  `tests/upstream-bytecode-numbering-iterative` (30 lines).
- **Fact it supplies.** MLIR's bytecode writer numbering deep attributes
  without native recursion. No tool of ours writes bytecode through
  MLIR:
  - `git grep -n -E "writeBytecodeToFile|BytecodeWriterConfig" --
    foreign` gives 0 hits;
  - the frontend writes its bytecode in Idris
    (`compiler/src/IdrisMLIR/MLIR/Bytecode.idr`), and the driver only
    reads it (`foreign/idr/lib/Driver/Run.cpp:269`, 03's reader);
  - `--emit-bytecode` appears only in `tests/upstream-*` (*measured*,
    `git grep -n -- "--emit-bytecode"`: three hits, all upstream tests).

  PINS.md says it itself: "sites: none in our code; the patch. The
  toolchain's `mlir-opt` writing bytecode reaches it:
  tests/upstream-bytecode-deferred-quadratic writes an array nested
  32,000 deep on a small stack". The patch's only reader is 03's test
  building its input.
- **Rule.** C99 lists "the bytecode writer" among MLIR's recursions to
  patch, and D33 says the tools keep a small stack. C99 assumed the tools
  reach the writer; at HEAD they do not. A conversion path that ever
  writes bytecode in C++ would bring the patch back.
- **Readers.** The bootstrap; its own test; 03's test.
- **Exact deletion.**
  - `llvm.patch` → `pull-request.diff`; the report stays.
  - The PINS.md entry (19 lines) and the test (30 lines).
  - `(97)` drops out of `mlir-recursion`'s family list (PINS.md:332).
  - `tests/upstream-bytecode-deferred-quadratic` writes its input outside
    the small stack and reads it on it (its line 16 cites 97).
- **Verdict.** DELETE (stop carrying), 49 lines. Confidence: *read* for
  the reach, *conjecture* that no planned path writes bytecode.
- **Owner.** L06, L19. Waits on a coordinator reading of C99's family
  list against the reach.

## 9. Patch 10, recursive-attribute-parser: our IR does not nest builtin arrays

- **Part.** `upstream/10-recursive-attribute-parser/llvm.patch`, carried;
  `tests/upstream-recursive-attribute-parser` (27 lines); the `(10)`
  clause of PINS.md's `mlir-recursion`.
- **Fact it supplies.** The textual parser, printer and alias collection
  of *builtin* arrays and dictionaries nested in one another, from an
  explicit stack. Its motivating case, "a list of 10,000 elements becomes
  a constant nested 10,000 deep", is gone from our representation:
  - a constructor constant is `#idr.con`, "a run of its cells"
    (`Idr_ConAttr`: `cells` and `spine`, `Generated/IdrTypes.td:395-412`),
    so a list's spine is one flat run;
  - any deeper nesting goes ConAttr → cell ArrayAttr → ConAttr, which
    passes through the dialect attribute's own parser and printer. The
    patch does not cover those; PINS.md lists them as "left".

  So on our IR the patch is neither reached nor sufficient. The
  compile path also reads bytecode, not text (`Run.cpp:269`, 03).
  *Measured*: `git grep -l -E "\[\[\[\[" -- 'tests/*.mlir'
  'foreign/*.mlir'` finds 0 files.
- **Rule.** D33 names this report as the example of an upstream
  recursion to patch. The fact under D33 (a recursion that scales with
  *our* input) does not hold for builtin-in-builtin nesting.
- **Readers.** The bootstrap; its own test.
- **Exact deletion.** `llvm.patch` → `pull-request.diff` (the report
  stays: "RFC first"); the test (27 lines); the `(10)` clause of
  PINS.md:325-326.
- **Verdict.** DELETE (stop carrying), 27 lines. Confidence:
  *conjecture* (read of ConAttr; no measurement of a deep-tree constant
  printed by idris-mlir-opt).
- **Owner.** L06, L19. Waits on the owner or coordinator: D33 names the
  report.

## 10. libs/mlir-hash: a library with one reader

- **Part.** `libs/mlir-hash/` (`Hash/XXH3.idr`, 337 lines; ipkg, 11
  lines); `Makefile:265, 292-295, 305, 330` (SHIPPED, comments);
  `tools/self.sh:120` (`-p mlir-hash`);
  `compiler/src/IdrisMLIR/Registry/Libraries.idr:100`; the `depends` of
  `compiler/idris-mlir.ipkg:7` and `compiler/syntax-samples.ipkg:7`.
- **Fact it supplies.** XXH3-128 in Idris, for the frontend's content
  names (`IdrisMLIR/Ids.idr:200` `contentHash`, and
  `Frontend/Translate/Keys.idr:1136, 1200`). Its ipkg and header justify
  a library of its own because "the frontend and the type checker both
  import" it. The checker imports nothing of it (*measured*: `git grep
  -n -i "xxh3|mlir-hash" -- compiler/checker` gives 0 hits). No test,
  bench or library imports `Hash.XXH3` apart from the frontend, its
  syntax-samples package, and `tests/content-hash`, which imports it
  through `IdrisMLIR.Ids`.
- **Rule.** None names `mlir-hash`. AGENTS.md names only `mlir-array` and
  `mlir-linear` as the libraries of `libs/`.
- **Exact deletion.** The module moves to `compiler/src/IdrisMLIR/`
  (beside `Ids.idr`). What goes: the ipkg (11), the SHIPPED entry and
  its comments (about 4), the registry line (1), the `-p mlir-hash`
  flags and depends (about 4). About 20 lines.
- **Verdict.** MERGE into the frontend, about 20 lines. Confidence:
  *read*. Chained: its only reader, the frontend's hash of a printed key
  into a symbol (`contentName`), is L16's representation and may itself
  be a candidate under "a name is text for a human".
- **Owner.** L20 (libs), L16 (frontend, ipkgs), INT (Makefile), L06
  (self.sh). Waits on L16, whose `compiler/src` has files in flight
  (`Ids.idr` and `Keys.idr` themselves are not modified).

## 11. Idris patches 104 and 105: the site they name was rewritten (measure)

- **Part.** `upstream/104-coverage-repeated-split/` (269 lines, carried),
  `tests/upstream-coverage-repeated-split` (22), PINS.md 1422-1439 (18);
  `upstream/105-case-tree-fallthrough-copies/` (226), its test (23),
  PINS.md 1440-1456 (17). `tests/checker-*` stays either way: it checks
  our checker.
- **Fact it supplies.** The stock host checking a shape of our code. The
  only site either README names in our tree is the specification's old
  `Spec.Effects.Atom.kept`: 104 says the effect rows "had" it, and 105
  says it "ran 986 s ... before it was rewritten to avoid it (INT-5,
  70258ae5)". At HEAD, `kept` is one line over `indexAll`
  (`compiler/spec/IdrisMLIR/Spec/Effects/Atom.idr:230-231`), not a
  clause table. PINS.md's `sites:` for both say only "everything the
  stock host checks", which is not a site.
- **Rule.** AGENTS.md: "a patch goes ... when nothing in the tree
  reaches the bug any more". For Idris, no report survives as a
  submission, so the whole directory would go.
- **Measurement owed.** Bootstrap Idris at 89ba32eb with the series minus
  104 (then minus 105), and check stage 0 (checker, frontend,
  specification, `libs/`, harness). No LLVM is needed. A refusal means
  the bug is reached and the patch stays. 106 to 118 name live sites
  (e.g. `harness/Determinism.idr:28`, `harness/Verdict.idr:198`,
  `Spec/Families/Terms.idr:160`, `harness/Covers.idr:471`), and 96 is
  eager evaluation on the stock host, so they stay.
- **Verdict.** MEASURE; DELETE if unreached: up to 309 lines (104) and
  266 (105). Confidence: *conjecture*.
- **Owner.** L06. Waits on the measurement.

---

## KEEP

### 12. The carried patches whose bugs our tree reaches

Each site was checked at HEAD with `git grep` over `foreign/` (hits
outside `Generated/`, except where noted).

- **03**: the frontend writes bytecode (`MLIR/Bytecode.idr`); the driver
  reads it (`Run.cpp:269`). A deep non-spine constant still nests.
- **04**: `vectorizeOpPrecondition` in `Target/Schedules.cpp`.
- **05**: forward solves visiting `idr.call` (`DataFlowSolver`, 7
  files).
- **07**: `InlinerConfig` in `Inline/Inline.cpp:132`; Emit ends bodies in
  `ub.unreachable` (`Emit/Bodies.idr:266`).
- **09**: `populateIntRangeNarrowingPatterns` (Narrow).
- **19**: `runPipeline` in `InlinePass.cpp:51`, `Narrow.cpp:239` and
  `Optimize.cpp:63`.
- **24**: One-Shot Module Bufferize on idr.program
  (`Bufferize.cpp:126-128, 341-354`).
- **27, 64**: `TensorLikeType` (`Bufferize.cpp`, `Lifetimes/Loans.h:105`;
  D43).
- **29**: `DeadCodeAnalysis` loaded (`Effects/Constants.cpp:179`).
- **30**: tailcc (`Conversion/Entry.cpp:81`, `Lower/Functions.cpp:175`).
- **56**: `hasTrait<DependsOnParent>` (`EGraph/Build.cpp:52`).
- **57**: `Driver/Register.cpp:97`.
- **61**: `math.sqrt` emitted (`Emit/Operations.idr:305`); the e-graph
  reads folds (D98).
- **62, 84**: `createConvertLinalgToLoopsPass`,
  `createConvertVectorToSCFPass` and `createExpandStridedMetadataPass`
  in `Generated/Pipeline.h.inc`.
- **65 to 71**: join points carry `PropagateControlFlowBreak` and the
  rest (10 files). D25 and D82 are owner rulings.
- **72**: `scc_begin` (`Solver/Components.cpp:19`,
  `Optimize/Settle.cpp:279`).
- **73, 93**: `mlir::CallGraph` (`Solver/ProgramGraph.cpp:67, 94`;
  `InlinePass.cpp`).
- **74**: 9 nested `idr.func` groups; 32 preserved-analysis marks.
- **75, 101**: `Driver/Tool.h:95-96`.
- **77**: the solvers of Constants, Ranges and Narrow (C32).
- **79, 90**: `OperationEquivalence` in Deduplicate and
  IdenticalRegions.
- **80 to 83, 85, 88, 89, 91, 92**: every pass, the vectorizer and
  bufferization, under D33 and C99. Slices are reached through
  `eliminateEmptyTensors` (`Bufferize.cpp:342`) and the vectorizer.
- **86**: `CMakeLists.txt:431`, `tools/bootstrap.sh:1068`.
- **87**: every body ending in `ub.unreachable` (`NeverRuns` is deleted).
- **99**: `lib/IR/Func/Edits.cpp`.
- **100**: `idris-mlir-opt.cpp:236`.
- **102**: two readers of `evaluatePred`.
- **103**: `Analysis/Ranges.cpp:97-103`.

The patches to the runtime's libraries:

- snmalloc **49**: AGENTS.md says "no inline asm".
- snmalloc **94**: no static fact is paid at run time (C100).
- snmalloc **95**: status 111 on a strict host (D35, D37).
- simdutf **98**: C169.

The patches to the stock Idris: **96** and **106 to 118** (live sites
above; D121).

### 13. third_party

| Dependency | What of ours uses it | Verdict and rule |
| --- | --- | --- |
| `gmp` | `runtime/Big/*` (8 files), `runtime/Alloc/Gmp.cpp`; the bootstrap's `gmp` step | KEEP: `Integer`'s meaning in `runtime/` (AGENTS.md's primitive rule). THIRD-PARTY.md's question for counsel stays the owner's. |
| `simdutf` | `runtime/Strings/Simd.{h,cpp}`, `Making.cpp`, `Replacement.cpp` (`count_utf8`, `validate_utf8_with_counts`) | KEEP: strings' scalar count and validation (C169). |
| `fast_float` | `runtime/Doubles/Parsing.cpp` (`from_chars`) | KEEP: string to Double. |
| `ryu` | `runtime/Doubles/Printing.cpp` (`d2s_buffered_n`) | KEEP: Double to string. Its pin is a master commit, `2.0-108`. |
| `snmalloc` | `runtime/Alloc/Cells.cpp` | KEEP: the heap (C5, C100). |
| `Idris2` | the bootstrap host; prelude and base for the frontend's prefix; `tools/upstream-idris` (`third_party/Idris2/tests`) | KEEP: D116 to D118, D121. |
| `modular` | no build step: 0 hits in `tools/bootstrap.sh`, CMake and Makefile; `update = none` | KEEP. AGENTS.md's pin rule names it, C10 reads "Modular's shapes", and the user asked to keep the sources. Its port claims go (candidate 6). The L06 handoff's reason for moving its gitlink ("the deduplication port's pin") is stale since C10. |

A question for the coordinator, outside this audit's cull:
`tools/upstream-idris` (517 lines) scores our compiler against
upstream's test expectations. Those expectations were produced by the
stock Idris on Chez, which sits close to AGENTS.md's "Do not add a
comparison against Idris's Chez backend".

### 14. libs

- **mlir-array**: KEEP. AGENTS.md names it. Every module has a reader:
  `Array` (43 importers), `Linear.Vec` (11), `Linear.Bytes` (2),
  `Linear.Parser` (`bench/json-bytes`, the parser workload), `Array.Core`
  (through `Array`).
- **mlir-linear**: KEEP. AGENTS.md names it. Readers: `Linear.Notation`
  (59), `Linear.List` (34), `Linear.Nat` (3), `Linear.String.Iterator`
  (2).
- **mlir-relational**: KEEP, on D44 and C175, with 0 readers
  (*measured*: `git grep -nE '^import (public )?Relational' -- compiler
  harness tests bench` gives 0 hits). One fact is held twice: the
  frontend's own semi-naive worklist (`Frontend/Finite.idr`) and R2's
  fixpoint (`Relational/Fixpoint.idr`). One of them goes; which one is
  recheck6's open D44 reading for the coordinator (L16, L20). If that
  reading drops C175's shape, the library's 821 lines go, which is an
  owner question since D44 is a ruling.

### 15. The reports whose patch is not carried, and the other PINS entries

- Uncarried LLVM and simdutf reports, KEEP as submissions (AGENTS.md's
  patch rule): 01, 02, 06, 08, 16, 17, 22, 23, 25, 28, 48, 58, 63, 78.
  Only their tests go (candidate 3).
- Other PINS entries, KEEP, each a workaround with a site:
  - `fp-call-folding` (C198, C210);
  - `mirrored-sources` (GMP's host);
  - `idris-support-host-cc`, which AGENTS.md cites;
  - `runtime-library-export`, while 49, 94, 95 and 98 are carried;
  - `inline-unreachable` (07's entry);
  - `mlir-recursion` (the families left for the painting, D33).

---

## Summary

| # | Candidate | Verdict | Lines | Confidence | Owner | Waits on |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | upstream/18, 20, 21, 50-55, 59 (Idris reports, no patch) | DELETE | 1,596 | read | L06 (+L19, L17 edits) | nothing |
| 2 | PINS status/upstream fields, README status table, carried list | MERGE into each report | 299 (+381 symptom, conjecture) | read | L06 | nothing |
| 3 | tests/upstream-* of uncarried reports (11) | DELETE | 321 | read | L19, L06 | nothing |
| 4 | PIN() markers, tests/pin-sites, 7 cpp-starter PINS entries | DELETE | 255 | read | L11, INT, L06, L19 | coordinator reading of PINS scope |
| 5 | Retired history in PINS.md and upstream/README.md | DELETE | 129 | read | L06 | nothing |
| 6 | Port licence machinery (C10) | DELETE | 60 | measured | L06, L19, coordinator | nothing |
| 7 | Patch 76 (documentation only) | DELETE (stop carrying) | 49 | read | L06, L19 | coordinator reading of D25 |
| 8 | Patch 97 (bytecode writer, test-only reach) | DELETE (stop carrying) | 49 | read / conjecture | L06, L19 | coordinator reading of C99 |
| 9 | Patch 10 (builtin nesting our IR lacks) | DELETE (stop carrying) | 27 | conjecture | L06, L19 | owner or coordinator (D33) |
| 10 | libs/mlir-hash | MERGE into compiler/src | 20 | read | L20, L16, INT, L06 | L16 |
| 11 | Idris patches 104, 105 | MEASURE, then DELETE | (up to 575) | conjecture | L06 | stock-host bootstrap without each |
| 12 | Carried patches with live sites | KEEP | 0 | read | L06 | — |
| 13 | third_party (7 gitlinks) | KEEP | 0 | read | L06 | — |
| 14 | libs: mlir-array, mlir-linear, mlir-relational | KEEP | 0 | read / measured | L20 | D44 reading (relational) |
| 15 | Uncarried reports; other PINS entries | KEEP | 0 | read | L06 | — |

Totals:
- DELETE at *read* or *measured* confidence: 1,596 + 321 + 255 + 129 + 60
  + 49 = **2,410 lines**.
- DELETE at *conjecture* confidence: 49 + 27 = **76 lines**.
- MERGE at *read* confidence: 299 + 20 = **319 lines**.
- MERGE at *conjecture* confidence: up to 381 symptom lines.
- **DELETE and MERGE at read or measured: 2,729 lines.** With the
  conjectures: 3,186.
- Not counted: up to 575 lines of 104 and 105, pending the measurement.
