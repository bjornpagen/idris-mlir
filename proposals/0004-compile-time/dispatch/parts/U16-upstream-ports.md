# U16: upstream patches and the Modular port

## Permitted outcome
1. Mandatory. One-Shot Module Bufferize runs on every function op that
   implements `FunctionOpInterface` and `BufferizableOpInterface`, with
   calls by `CallOpInterface`, through a new carried patch,
   `upstream/24-one-shot-module-function-interface/`: `llvm.patch`, the
   report (`README.md` with `## Patch` and `## Upstreaming plan`), the
   reproducers, a `tests/upstream/one-shot-module-function-interface`
   check, its `PINS.md` entry and its row in `upstream/README.md`. The
   patch applies to the pinned llvm-project alone and after every other
   carried patch (`git apply --check`), and the API it leaves is C18's,
   word for word.
2. Mandatory. Patches 02, 16 and 22 are no longer carried: each
   `llvm.patch` becomes `pull-request.diff` (the form 08 and 17 keep, which
   the bootstrap never applies), each report says why there is no patch
   and stays a submission, each `tests/upstream` check becomes a check that
   the pinned tools still have the bug, and the three `PINS.md` entries go.
   `upstream/README.md` states the retirement rule AGENTS.md points at.
3. Mandatory. `idr-deduplicate` is Modular's EliminateDuplicateFunctions,
   ported under proposal 0001's protocol: one pass merges transitively,
   bottom-up, keeps the lexicographically smallest member of each class,
   renames every use, erases the rest, and gives the kept function the
   fused location of its class (C23). A second run changes nothing; the
   output is the same at any thread count.
4. Mandatory. `PINS.md` is true of the tree after the cutover: the port's
   entry, the new patch's entry, and the sites and words of every entry
   whose site moves with the cutover (the ones named under Implement).
5. Mandatory. `LICENSES/THIRD-PARTY.md`'s GMP paragraph states proposal
   0001's default and the owner's open question, and its table lists the
   Modular port, which links into our tools (a port is a pin, and the file
   is kept by the change that adds one).
6. Mandatory, a decision recorded with no file: the Presburger emptiness
   patch 0004 §7 item 3 planned is not written (Fixed decisions 6).

Consumer adaptations this lane makes: none outside its writes. The pass
`def` is U06's (C12 already holds its row); the build list is the
coordinator's.

## Owner / exclusive writes
- `upstream` (U16 alone):
  - new `upstream/24-one-shot-module-function-interface/`: `README.md`,
    `llvm.patch`, `named-sequence.mlir`, `no-return.mlir`, `idr-call.mlir`;
  - `upstream/02-composite-fixed-point-sccp/`,
    `upstream/16-remove-dead-values-unchanged-call/`,
    `upstream/22-remove-dead-values-poison-operand/`: `llvm.patch` renamed
    to `pull-request.diff` (a plain `mv`, no git command), `README.md`
    restated, and 02's `submission.md` naming `pull-request.diff`;
  - `upstream/README.md`: the status table, the retirement rule, the
    toolchain paragraph.
- `PINS.md`.
- `tests/upstream`: new `tests/upstream/one-shot-module-function-interface/`
  (`run`, `expected`); `composite-fixed-point-sccp`,
  `remove-dead-values-unchanged-call` and `remove-dead-values-poison-operand`
  (`run`, `expected`) restated.
- `IDR/Transforms/Deduplicate` (`foreign/idr/lib/Transforms/Deduplicate`):
  new `EliminateDuplicateFunctions.cpp` (the port) and `Equivalence.cpp`
  (ours); `Deduplicate.cpp` deleted.
- `INC/Transforms/Deduplicate.h` (`foreign/idr/include/idr/Transforms/Deduplicate.h`).
- `LICENSES/THIRD-PARTY.md`.

**Excluded:** `foreign/idr/include/idr/Transforms/Passes.td` and
`foreign/idr/lib/Transforms/Pipeline.cpp` (U06; C12 row 1 is
`idr-deduplicate`); `foreign/idr/lib/Transforms/CMakeLists.txt` (the
coordinator, who replaces `Deduplicate/Deduplicate.cpp` by the two new
units); `tools/bootstrap.sh`, `tools/patches.sh`, `tools/verify-pins.sh`
(the coordinator; they read `upstream/*/llvm.patch` as data and need no
change); `tests/idr/dedup` and every other dialect fixture (U17);
`tests/spec/upstream-patches`, `tests/spec/licenses`,
`tests/spec/pin-sites` (U18); `foreign/idr/lib/Transforms/Bufferize`
(U12, the models on C18); `.toolchain/` (never written; the coordinator's
`make typecheck` re-exports the patched tree); `NOTICE` and `LICENSE`
(the coordinator); `proposals/` (the coordinator).

## Read first
- `contracts.md`: C01 (identified types, the attributes of `idr.func`,
  `instance`), C02, C12 (row 1 and §1), C15, C22, C24 ("How `@f` finds its
  functions", the fused location), and this lane's C18 and C23.
- 0004 `README.md`: §4 stage 3 (lines 786-792), §6 rows "Upstream patches
  that lose their only site" (1293-1308), `InBounds/Empty.cpp` (1269) and
  "Kept" (1309-1327), §7 (1330-1374), §8 rank 4 and the licensing steps
  (1376-1420), §10's L6 row (1495), D23 and D24 (1601-1611). D23's text
  predates AGENTS.md's amended rule; this part follows AGENTS.md (Fixed
  decisions 3).
- 0003 `README.md`: U1 and D34 (lines 1885-1895, 1991-2011), owner point 5
  (2050-2052).
- `proposals/0001-licensing.md`: §1, §3's table, §4 (the protocol), §5
  (the GMP default), §6 L6 (the GMP paragraph), §9.
- AGENTS.md, the upstream rule (lines 122-143): "A patch goes when the pin
  moves past upstream's fix, or when nothing in the tree reaches the bug any
  more, its report kept as a submission".
- `upstream/README.md` whole; `upstream/08-*/README.md` and
  `upstream/17-*/README.md` (the not-carried form: `## Why there is no
  patch`, `pull-request.diff`); `upstream/16-*/README.md` (a report's
  sections).
- `PINS.md` whole; `tests/spec/upstream-patches/run`,
  `tests/spec/licenses/run`, `tests/spec/pin-sites/run`,
  `tests/spec/file-size/run` (400 lines a unit),
  `tests/spec/no-local-headers/run`.
- `foreign/idr/lib/Transforms/Deduplicate/Deduplicate.cpp:1-400` (every
  line: the hash, the comparison, the self reference, the renamable uses);
  `foreign/idr/include/idr/Transforms/Deduplicate.h`;
  `foreign/idr/include/idr/Transforms/Passes.td:284-310`; `tests/idr/dedup/`.
- `sources/code/modular/Mojo/lib/Transforms/EliminateDuplicateFunctions.cpp:1-301`
  (`SNAPSHOT.md` names revision `9211931`).
- Pinned MLIR (`.toolchain/llvm-project/mlir`, pristine, the tree
  `tests/spec/upstream-patches` checks against):
  `lib/Dialect/Bufferization/Transforms/OneShotModuleBufferize.cpp:1-652`,
  `FuncBufferizableOpInterfaceImpl.cpp:1-548`,
  `include/mlir/Dialect/Bufferization/Transforms/FuncBufferizableOpInterfaceImpl.h:1-85`,
  `include/mlir/Dialect/Bufferization/IR/BufferizableOpInterface.h:268-275`,
  `lib/Dialect/Bufferization/IR/BufferizableOpInterface.cpp:388-402, 466-487`,
  `test/lib/Dialect/Bufferization/TestOneShotModuleBufferize.cpp`,
  `test/lib/Dialect/Test/TestOps.td:724-790, 2374`,
  `include/mlir/IR/AttrTypeSubElements.h:134-235`,
  `lib/IR/SymbolTable.cpp:536-553`, `include/mlir/IR/Threading.h`,
  `llvm/include/llvm/ADT/SCCIterator.h`.
- Upstream's reverted generalization: llvm-project pull requests 110322
  (its diff) and 113124 (the revert), and the Discourse thread "Is the
  bufferization of func.func able to be reused on other
  FunctionOpInterface" (2025).

## Fixed decisions
1. **The bufferization patch is upstream's reverted 110322, relanded on
   the pin with its cause fixed.** Its number is 24: the next free one in
   filing order (23 is the CSE statistics patch; the earlier array drafts'
   "23" is wrong). Directory `upstream/24-one-shot-module-function-interface`.
   The function set of the module driver is every op of the module's
   blocks that implements both `FunctionOpInterface` and
   `BufferizableOpInterface`; a function op without a model
   (`transform.named_sequence`, which broke 110322) is an "other op", as at
   the pin. A call whose callee does not resolve to a function of the set
   orders nothing (no assertion). The analysis state is keyed by
   `FunctionOpInterface`; the queries other dialects' models need are
   exported (C18 lists each). A function none of whose blocks returns
   (every block ends in `ub.unreachable`, as a crash does) is analyzed with
   no result aliasing an argument instead of failing (U12's request; the
   pin fails it). 110322's edits to transform tests are not carried: the
   model filter makes them unnecessary.
   `BufferizationOptions::isOpAllowed` is unchanged.
2. **The upstream test** is three new files: a function interface test that
   runs `-test-one-shot-module-bufferize`, whose pass attaches models to
   `test.conversion_func_op`, `test.conversion_call_op` and `test.return`
   (in `TestOneShotModuleBufferize.cpp`, no new library), and a transform
   sequence test with `func.func` and `transform.named_sequence` side by
   side under `-one-shot-bufferize="bufferize-function-boundaries"`, and a
   no-return test (a function that ends in `ub.unreachable` and its
   caller).
3. **02, 16 and 22 are retired, not carried** (the brief, and AGENTS.md as
   amended in 19fe1332). After the cutover nothing in the tree runs a
   composite fixed point, so no code of ours observes `sccp` remaking a
   constant or `remove-dead-values` rebuilding a call or re-poisoning an
   operand. A retired patch takes the form a report never carried already
   has (08, 17): `pull-request.diff` (the pull request, not applied), a
   `## Why there is no patch` section, no `PINS.md` entry, and a
   `tests/upstream` check in 17's form ("still reproduces"), which fails
   when the pin has the fix and the report goes. 0004 D23 says "stay
   carried"; it was written against AGENTS.md's earlier rule, and the
   coordinator corrects its text.
4. **04 stays carried.** Its site moves from the deleted vectorize pass to
   C13's vectorization schedule: `transform.idr.vectorize_lanes` decides by
   `linalg::vectorizeOpPrecondition` and then calls `linalg::vectorize`,
   and a tile the precondition accepts but the vectorizer refuses is an
   internal error there, which the patch prevents. 03, 05, 06,
   07, 09, 19 and 23 stay carried; their sites move as Implement says.
5. **The port is one Apache file and one file of ours.** The ported file
   is `foreign/idr/lib/Transforms/Deduplicate/EliminateDuplicateFunctions.cpp`:
   Modular's header block verbatim (lines 1-12 of the source), above it
   `// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception`, below it
   one changes line exactly
   `// Modified by Bjorn Pagen, 2026, from Modular's 9211931: on idr.func, with a reference graph, llvm::scc_iterator and MLIR's thread pool for KGEN's call graph and AsyncRT, classes compared by idr::deduplicate, every use renamed and the copies erased.`
   and then `// PIN(eliminate-duplicate-functions)`. The comparison it
   calls is ours, unchanged in substance from today's `Deduplicate.cpp`,
   in `foreign/idr/lib/Transforms/Deduplicate/Equivalence.cpp` (`0BSD`),
   declared in `Deduplicate.h` (C23). Each unit stays under 400 lines.
6. **No Presburger patch.** U09 deletes the in-bounds prover, and with it
   `Empty.cpp`, in this wave. No other code of ours calls Presburger's
   integer emptiness, and the one upstream caller of
   `IntegerRelation::isIntegerEmpty` (affine fusion's slice checks,
   `mlir/lib/Dialect/Affine/Analysis/Utils.cpp:1103, 1160`) is not in the
   pipeline (C12). Nothing in the tree reaches the bug, so by AGENTS.md
   there is nothing to carry, and no report is written in this wave.
7. **The algorithm of `idr-deduplicate`** (C23 states it as the contract):
   a reference graph of every `idr.func`; Tarjan's SCCs through
   `llvm::scc_iterator` from an entry node that reaches every function
   (Modular's external node); heights over the SCC DAG; waves by height,
   each wave first rewriting its functions' references to the kept names
   and hashing them in parallel (`mlir::parallelFor`), then forming classes
   serially in module order through a `DenseSet` whose equivalence is
   C23's; then the kept member of each class (the lexicographically
   smallest symbol) gets the fused location, and the rest are erased
   serially in module order. Classes never span heights, so a class is
   complete before any caller reads it, and every reference is rewritten
   once.
8. **The changes line names 9211931**, as the brief says; proposal 0001
   §4's default keeps path and revision in `PINS.md` alone. The
   `PINS.md` entry names both too. The disagreement is the owner's open
   question in 0001 §9, reported, not decided here.
9. **The GMP paragraph** states: GMP stays, statically linked; a shipped
   binary meets LGPL-3.0 §4(d)(0) with a relink kit (for a program, the
   archive `idris-mlir -c` writes, one object per codegen bin in bin-name
   order, the prepared runtime object, the link line's remaining
   arguments with GMP among them, and GMP's source at the pin; for a
   compiler release, the static libraries and final link command of its
   build); the notice and both license texts travel with the binary;
   nothing is owed while the repository distributes source only; whether
   the kit suffices, or GMP must go, is the owner's question with counsel.

## Inputs
- C01: the attributes of `idr.func` after the cutover (which are facts,
  that `instance` is provenance that no pass reads), the ops that name a
  function by symbol (`idr.call`, `idr.closure`, `idr.suspend`, and
  `idr.constant` holding `#idr.closure`), every function reference a
  `SymbolRefAttr`.
- C12: `idr-deduplicate`'s row (statistics `numGroups "groups"`,
  `numMerged "merged"`), row 1 of the pipeline, the generated
  `idr::createIdrDeduplicate()`.
- C13: the vectorization schedule's `transform.idr.vectorize_lanes`, which
  calls `linalg::vectorizeOpPrecondition` and `linalg::vectorize` (04's
  site).
- C15: U12's models of `idr.func`, `idr.call` and `idr.return` on C18, the
  pass `idr-bufferize`, and `idr::bufferize::copies` (for the
  `tests/upstream` check).
- C22: the emitted module deduplication reads (symbol-form closures, no
  type body naming a function before defunctionalization).
- C24: `in-place[=@f]` and the location rule ("Deduplication keeps one
  function of each class and gives it the location `FusedLoc`").

## Outputs
- C18, produced here: the patched upstream API (headers, functions,
  semantics of the module driver), the patch directory, and the retired
  patches' new form.
- C23, produced here: `Deduplicate.h`'s declarations, the two units, the
  pass's behaviour and invariants, the fused location.
- Consumers: U12 (C18), U06 (the pipeline's empty tensor elimination,
  which runs through the generalized `analyzeModuleOp`; the
  `IdrDeduplicate` description from C23), U17 (`tests/idr/dedup`, the
  bufferization fixtures, idr-expect's lookup), U18
  (`tests/spec/upstream-patches` and `licenses` read these files), the
  coordinator (the build list; the toolchain re-export).

## Implement
**A. Patch 24.** Copy the pinned files into a scratch git repository under
`/tmp`, edit, and write `git diff --abbrev=9` as `llvm.patch`. Files and
changes (C18 has the resulting declarations):
- `mlir/include/mlir/Dialect/Bufferization/IR/BufferizableOpInterface.h`:
  include `mlir/Interfaces/FunctionInterfaces.h`; drop the `func::FuncOp`
  forward declaration; `FunctionArgTypeConverterFn` takes
  `FunctionOpInterface`.
- `mlir/lib/Dialect/Bufferization/IR/BufferizableOpInterface.cpp`: the
  default converter and `setFunctionBoundaryTypeConversion`'s lambda take
  `FunctionOpInterface`.
- `FuncBufferizableOpInterfaceImpl.h/.cpp`: `getReturnOps` returns the
  `ReturnLike` terminators as `Operation *`; the state's five maps and
  `startFunctionAnalysis` on `FunctionOpInterface`; the six queries
  exported; the func models adapted (`getArgumentTypes`, `getResultTypes`,
  `returnOp->setOperands`).
- `OneShotModuleBufferize.cpp`: every `func::FuncOp` becomes
  `FunctionOpInterface`; `isBufferizableFunction(op)` decides the set; the
  call walk on `CallOpInterface` skips calls outside the set; `isExternal`
  for `getBody().empty()`; `cloneTypeWith` in `foldMemRefCasts`;
  `SymbolTable::getSymbolName` for the no-analysis filter; the other-ops
  loop skips the set; a function with no return-like terminator is
  analyzed with no aliasing result; no include of the func dialect.
- `mlir/test/lib/Dialect/Bufferization/TestOneShotModuleBufferize.cpp`:
  the converter lambda's parameter; the three test models, written on the
  exported queries, attached in `getDependentDialects`.
- New `mlir/test/Dialect/Bufferization/Transforms/one-shot-module-bufferize-function-interface.mlir`,
  `one-shot-module-bufferize-transform-sequence.mlir` and
  `one-shot-module-bufferize-no-return.mlir`.
Check: `git -C .toolchain/llvm-project apply --check` (pristine pin), no
file shared with another carried patch (`apply --numstat`), and a
`-fsyntax-only` of the four changed `.cpp` files in the scratch copy
against `.toolchain/build/typecheck-llvm`'s generated headers (the test
dialect's generated into `/tmp` with that tree's `mlir-tblgen`).
Reproducers: `named-sequence.mlir` (upstream dialects: the revert's case),
`no-return.mlir` (upstream dialects: a function that never returns, which
the pin refuses) and `idr-call.mlir` (an `idr.func` callee that writes its
tensor argument, a caller that passes a tensor it does not read again, a
function that never returns, and a root; first line
`// NEEDS-ACCEPTANCE: ...`). The report's sections: title, Reproduce,
Expected, Cause, History upstream, Patch, Testing at the pin, Upstreaming
plan.
`tests/upstream/one-shot-module-function-interface/run`: (1) the pinned
`mlir-opt` on `named-sequence.mlir` with
`--one-shot-bufferize=bufferize-function-boundaries`: exit 0, the function
takes a memref, the sequence prints unchanged; (2) the same on
`no-return.mlir`: exit 0 (the pin exits 1); (3) `idris-mlir-opt
--idr-bufferize` on `idr-call.mlir`, then `expect_holds` with
`in-place=@callee in-place=@caller`. `expected`: the three success lines.

**B. Retire 02, 16, 22.** `mv llvm.patch pull-request.diff` in each. In
each README: the `## Patch` section becomes `## The fix` (what the diff
does, unchanged), a new `## Why there is no patch` says that no code of
ours runs a composite fixed point after the cutover, so nothing reaches
the bug, and that the report stays a submission; it replaces 02's `## Our
workaround`, 16's becomes `## What it replaced`, and the plans' last
paragraphs say the check fails when the pin has the fix. Each
`tests/upstream/<bug>/run` turns to 17's form: the unpatched pin still
shows the bug ("still reproduces"), anything else is a failure that says
which; `expected` holds the "still reproduces" lines. `upstream/README.md`:
rows 02, 16, 22 "not carried (nothing in the tree reaches it after the
pipeline cutover); report kept"; a section "When nothing reaches the bug"
with the rule and the form; the toolchain paragraph lists the carried
LLVM patches as 03-07, 09, 19, 23 and 24; the `pull-request.diff` bullet
names 02, 16 and 22 beside 08 and 17; row 24.

**C. The port.** `Equivalence.cpp` takes today's `hashAttr`, `sameAttr`,
`sameAttrs`, `BodyHash`, `BodyEqual` (`Deduplicate.cpp:53-257`) unchanged,
and defines C23's `hashFunction` and `sameFunction`: the function's
attribute dictionary without `sym_name` and `instance`, compared with the
self rule, then the body. `EliminateDuplicateFunctions.cpp` carries the
Modular skeleton: the `DuplicateFuncOpEquivalenceInfo` (on a candidate of
cached hash and function), the graph with its entry node and the comment
on it, the cycle comment, the class table (`uniqueFuncSet`,
`representativeToLexMin`), `replaceCallSitesWithLexMin` as the per-wave
rewrite to kept names, and `runOnOperation`. Statistics: `numGroups` (each
class of two or more), `numMerged` (each function erased). The pass never
fails: a module it cannot improve is left as it is.

**D. PINS.md.** Delete `simplify-structural-fixpoint`,
`remove-dead-values-unchanged-call`, `remove-dead-values-poison-operand`;
add to the opening paragraph that they retired with the pipeline cutover
and why. Add `one-shot-module-function-interface` and
`eliminate-duplicate-functions` (what, from where, at what revision, what
changed, when it goes: when the pin carries upstream's
`duplicate-function-elimination` generalized to `FunctionOpInterface`).
Restate sites: `remove-dead-values-unreachable` (the pipeline's one
`remove-dead-values{canonicalize=false}`, C12 row 5), `cse-statistic-assignment`
(CSE in `idr-optimize`'s inner pipeline and the pipeline's cleans),
`inline-unreachable` (`mlir::inlineCall` from `idr-optimize`),
`bytecode-deferred-quadratic` (the frontend hands the driver bytecode),
`vectorize-precondition-body` (C13's schedule), `pass-timing-dynamic-pipeline`
(the passes that run pipelines after the cutover), and the opening
paragraph's note on the statistics `static_assert` (its unit after the
cutover is C07's).

**E. LICENSES/THIRD-PARTY.md.** Replace lines 21-26 with Fixed decisions 9;
add the row "Modular's Mojo compiler (ported files, each named in
PINS.md) | `idr-deduplicate`, linked into our tools | Apache-2.0 WITH
LLVM-exception" after LLVM/MLIR's.

## Delete
- `upstream/02-composite-fixed-point-sccp/llvm.patch`,
  `upstream/16-remove-dead-values-unchanged-call/llvm.patch`,
  `upstream/22-remove-dead-values-poison-operand/llvm.patch` as carried
  patches (each becomes `pull-request.diff`): they exist because the
  composite fixed point read an `OperationFingerPrint` change as a change,
  and that loop is gone with the simplify rounds.
- `PINS.md` entries `simplify-structural-fixpoint`,
  `remove-dead-values-unchanged-call`, `remove-dead-values-poison-operand`,
  and every mention of `max-rounds`, the round budget and
  `unsupported (compile-time budget)` they hold.
- `foreign/idr/lib/Transforms/Deduplicate/Deduplicate.cpp` whole, with:
  the comparison of `break_last`; the refusal of functions with an
  `instance` fact and its comment; the `held` set built from `idr.data`
  labels and clone keys (`copiedFrom`); the "crossed" group check; the
  "left for a later run" fixpoint by rerunning; `no_inline` merged into
  the kept function; the first-in-module-order choice of the kept
  function.
- `INC/Transforms/Deduplicate.h`'s header comment's "first" wording.
- `LICENSES/THIRD-PARTY.md:21-26` (the paragraph that names the question
  but not the default).

## NOT TO DO
- No Presburger patch or report (Fixed decisions 6). No region-simplifier
  report, no statistics-of-dynamic-pipelines patch and no
  `duplicate-function-elimination` generalization patch in this wave
  (0004 §7 items 1, 2 and 4): none has a reproducer this machine can
  reduce, and nothing in the brief asks for them.
- Never post, file, push or comment upstream (upstream/README.md's rules).
- Never edit `.toolchain/`, `third_party/`, `tools/bootstrap.sh` or
  `tools/patches.sh`; never run the bootstrap, `make` or a build.
- Never write `Passes.td`, `Pipeline.cpp` or a CMake list; report the
  lines instead.
- No dialect fixture under `tests/idr` (U17), no program test (U18).
- No model of an idr op (U12): the patch exports queries, the models are
  C15's.
- Do not keep a carried patch "in case": 02, 16, 22 retire whole, and no
  `PINS.md` entry stays for them.
- Do not port Modular's `CallGraphUtils.h` or AsyncRT, and do not use
  upstream's `CallGraph` analysis (it sees calls, not closures and
  constants).

## Tempting partial solutions
- **Keep 110322's transform test edits instead of the model filter.**
  Rejected by `one-shot-module-bufferize-transform-sequence.mlir`: a module
  with a payload function and a named sequence at top level bufferizes
  with no payload tag.
- **Have the idr models rebuild the boundary analysis themselves.**
  Rejected by C18: the analysis is held once, in upstream's state, and the
  models read it through the exported queries.
- **Merge across heights or rerun the pass until nothing changes.**
  Rejected by C23's idempotence: a second run on the output changes
  nothing, and each reference is rewritten once.
- **Keep the first member in module order.** Rejected by C23's
  determinism and lex-min rule: the kept symbol is the smallest name of
  its class whatever the order or thread count.
- **Compare `instance`, or keep the old refusal.** Rejected by U17's
  `dedup/merge-named`: two functions with different `instance` facts and
  locations merge, and both names find the kept one.
- **Retire 02, 16, 22 by deleting their directories.** Rejected by
  AGENTS.md: the report is kept as a submission.
- **Leave `PINS.md` naming `Simplify.cpp` or the vectorize pass as
  sites.** Rejected by Acceptance 6.

## Acceptance
1. `git -C .toolchain/llvm-project apply --check upstream/24-one-shot-module-function-interface/llvm.patch`
   succeeds; `apply --numstat` of it shares no path with any other
   `upstream/*/llvm.patch`; no `upstream/*/llvm.patch` is left in 02, 16
   or 22.
2. The patch's four changed `.cpp` files pass `-fsyntax-only` in a scratch
   copy against the typecheck tree's headers.
3. Every `upstream/*/README.md` has `## Upstreaming plan`, and `## Patch`
   exactly where an `llvm.patch` is, `## Why there is no patch` exactly
   where none is (what `tests/spec/upstream-patches` reads).
4. `EliminateDuplicateFunctions.cpp` has the SPDX line, Modular's header
   verbatim, the changes line and the PIN site, and `PINS.md` names its
   path (what `tests/spec/licenses` reads); `Equivalence.cpp` and
   `Deduplicate.h` carry the `0BSD` line; each unit is at most 400 lines.
5. `python3 proposals/0004-compile-time/check-units.py` on the two units:
   they are new, so the script reports them not in the build; a
   `-fsyntax-only` with the typecheck flags (the compile command of
   `Identity.cpp` with the file swapped) is clean except for seams of
   C01 or C12 that do not exist yet, each reported.
6. `PINS.md` names no deleted file as a site (`Simplify`, `InBounds`,
   `Vectorize`, `Isolate`, `Inline`, `Specialize/Clones`), and every
   `PIN(...)` in this lane's files names an entry.
7. `tests/upstream/*/expected` of the three retired checks hold "still
   reproduces" lines; the new check's `expected` holds its three success
   lines.
8. `LICENSES/THIRD-PARTY.md` names the default and the open question.

## Stop and return
Return when A to E are written and the checks above ran. Report, without
stopping other work: the build list change for the coordinator
(`Deduplicate/Deduplicate.cpp` out, `Deduplicate/EliminateDuplicateFunctions.cpp`
and `Deduplicate/Equivalence.cpp` in, in `IdrSmallPasses`); that `make
typecheck` must re-export `.toolchain/build/llvm-project` with patch 24
in and 02, 16, 22 out before U12's units see C18; that stage 2 must be
rebuilt on both targets on the owner's machine; the C01 seams (the
attribute names of `idr.func`, `instance`'s role, the ops that name a
function) if C01 says otherwise; 0004 D23's text for the coordinator; and
0001 §9's open question.
