<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Lane programs-1: `tests/programs/` arrays, basic, data, eval, interfaces, io

Scope: the six topics above, against the verdicts of `audits/programs.md` and
`audits/SUMMARY.md` §3, §5 and §8. Only test files were edited. No git
command was run.

## Result

- Before: 139 directories (5 of them output-only litter), 17
  NEEDS-ACCEPTANCE marks.
- After: 112 tests, 0 marks.
  - 59 pass.
  - 53 fail, each on a compiler bug listed below. No failure is the test's
    fault.
- Status comes from each test's `output` after a run of
  `make test only='programs/<topic>' threads=2` on today's build (18:05 to
  18:40). basic and io ran first. arrays, data, eval and interfaces were
  rerun after the edits.
- **Harness note.** From about 18:13 to 18:30 every test failed with an
  empty output. Another lane's edit to `tests/runner/one.sh` resolved the
  results directory against the test's own directory. It is fixed now
  (`stderr=$(pwd)/$results/...`). Verdicts from that window were thrown
  away and the tests rerun.
- **Hidden compile errors.** Ten compiles were hidden behind the tree
  printer's "File name too long" lines. I recompiled each one without dumps
  (`tools/compile.sh --num-threads=2`, in the scratchpad) to find its real
  error. That is the evidence column below.
- `make check`: 29/32. The three failures (licenses, dialect-text,
  file-size) are in other lanes' files: `audits/done-game-*.md` and
  `audits/machinery.md` have no SPDX line,
  `bench/chameneos-redux/compare`, and `tests/idr/reduce/regions.mlir`
  RUN 7.

## Deleted

| path | reason |
| --- | --- |
| arrays/buffer-byte-range, linarray-generate-bounds, linarray-generate-fill-once, linarray-generate-negative-size, linarray-rows-effects | output-only directories of deleted tests (SUMMARY §3.6) |
| arrays/linarray-fannkuch/build, arrays/linarray-qsort/build, arrays/ioarray-fannkuch/build, basic/hello/build | build litter of 7 Oct |
| basic/numbers | covered by Sem's convert tables and every-cast-export (§3.4) |
| basic/do-let | duplicate: a let in a do block is also in let-after-output and many others |
| basic/force-delay | duplicate of basic/laziness, which also crashes in the unchosen branch |
| eval/static-evaluation, deep-list-constant, deep-result, strings-at-compile-time | compile-time evaluation, which is not built (§3.1) |
| eval/dead-static, static-let, known-constructor, specialization | stdout only; the claimed property is never checked (§3.2) |
| eval/stream-share | duplicate of memo-shared-stream's top-level `fibs`, with the same live-cells pin |
| interfaces/interface-superclass | "no dictionary survives" is never checked (§3.2) |
| io/output-fusion | `output-fused` is never stated (§3.7 item 6) |
| io/echo | duplicate of io/prelude-input (getChar bytes, 255 at EOF, interleaved output); its comment appealed to "the reference" |
| io/prelude-io | duplicate of prelude/every-io-export |
| io/mandelbrot-pbm, data/pidigits | copies of a bench program with no mlir.expect: pure duplicates of bench/smoke (PROG-10) |
| arrays/ioarray-fannkuch, linarray-fannkuch, linarray-qsort, linarray-spectral-norm, linarray-unionfind | bench copies (PROG-10). Each fails before its mlir.expect is read: compile timeout, or bug 19, which bench/smoke shows too. Two of their properties pinned inlining choices. Their properties are listed below for `bench/<name>/mlir.expect` |
| data/complete-split | the only claim, "no default alternative", is unchecked; a 3-constructor enum match is in every data program |
| data/layout-768-counted-fields | 768 tests the same wrap of the 8-bit count to 0 as 512 |
| arrays/ioref-modify-in-place | `modifyIORef` is base's read then write, so after inlining it is ioref-record-in-place's loop |
| arrays/linarray-lanes-narrow | merged into linarray-lanes-wide: the same Main.idr and mlir.expect byte for byte |

## Rewritten

- **basic/chars:** the comment comparing putChar with "the reference", which
  basic/high-chars contradicts, now states the rule the cases check: an Int
  that is no scalar value casts to 0.
- **basic/let-after-output, io/prelude-input, io/prelude-getline:** removed
  the appeals to the stock backend and to C getchar (PROG-8).
- **eval/arity-raising, eval/shared-result, eval/closure-result-roundtrip,
  data/identity-weakening, data/shapes:** removed the stale claims about
  compile-time evaluation (PROG-7).
- **eval/call-pattern:** the comment claimed specialization at m = 3, 2, 1
  and that "m = 0 folds". Neither was checked, and the second is stale. It
  now claims only what stdout checks: every call computes what the source
  says.
- **eval/compile-time-evaluation:** renamed `eval/closed-calls`, since its
  body tests that closed calls run at run time.
- **eval/specialize-growing-accumulator:** the claim is now stated, as
  `mlir.expect: idr-optimize: specialized-once=@Main.count`. It holds, and
  the test passes. Also removed the stale remark that a Nat cannot exist at
  run time.
- **eval/lazy-branch-loop, eval/lazy-list-branches:** removed
  `idr-defunctionalize: no-closures`, which the program verifier already
  implies after `higher` (SUMMARY §2.4). lazy-list-branches had nothing
  else, so its mlir.expect and its `mlir.expect: holds` line are gone.
- **data/dependent-pair-family-eta, interfaces/method-runtime-implicits:**
  these never elaborated (PROG-9). I added `import Prelude`, and
  method-runtime-implicits gets `packages: base`. Now:
  - dependent-pair-family-eta passes;
  - method-runtime-implicits prints its expected stdout, and fails only on
    a leak of 1 cell (bug A).
- **interfaces/show-rose-breakers:** removed the unchecked claim about where
  the cycle breaks.
- **interfaces/choice:** I tried the mark its comment promised
  (`heap-free`). It fails: `cell.new`/`show_sint` in `main.delay`.
  - Nothing shows that this program ever held, so I dropped the claim and
    the unchecked case-of-case narration rather than add an expectation
    that may never have been true.
  - It passes on stdout.
  - Its allocations have the same signature as bug D. If D is fixed, the
    mark can come back.
- **io/system-info:** the run script's `case $host_names` mapped macos to
  darwin and linux to unix: a per-target case outside the target entry
  (AGENTS, PROG-19). It is gone.
  - The program now prints only facts that are the same on every host: an
    OS name is present, no Windows, codegen `mlir`. It also prints the
    processor count, which is read from tools/host.sh's `ncpu_total`.
  - It passes.
  - The exact OS name comes back when the build exposes the target's OS as
    a fact.
- **arrays/ioarray-ends:** the claim "the access's own check is gone" is now
  stated, as `idr-optimize: no-guards=@Main.ends`. It holds; the test fails
  only on a leak (bug A).
- **arrays/ioarray-sieve:** removed the mlir.expect. Both functions it named
  (`@Main.mark`, `@Main.count`) are no longer in the module, so it pinned
  inlining and contification choices (PROG-4). It fails only on a leak
  (bug A).
- **arrays/ioref-record-in-place:**
  - `moves-out=@Main.loop reuses-in-place=@Main.loop` named a function that
    is contified away. It became the Roots form `moves-out`, which names no
    function.
  - `reuses-in-place` has no Roots form, so that claim was removed from the
    comment.
  - `moves-out` still fails, as it does in ioref-keeps-old-value (bug B).
- **arrays/linarray-lanes-wide:** now the merged narrow and wide fixture.
  - It runs `runAll` twice from one stdin: n = 1001 below every bound, then
    40003 above them.
  - Its expected-stdout is the two old files concatenated, and the comments
    say so.
- **NEEDS-ACCEPTANCE:** removed from all 11 surviving files. They are now
  passing, or failing on bugs C, F and G:
  - the 8 Linear.Vec programs (bug C);
  - data/sortedmap-map-after-insert (bug F);
  - data/dependent-pair-family-eta (passes);
  - interfaces/method-runtime-implicits (bug A).

## Tests left failing, by compiler bug

The letters are this report's own; SUMMARY §5 numbers are in brackets.

- **A. Live cells at exit, a leak [§5.10].** Live cells left at exit:

  | test | cells |
  | --- | --- |
  | arrays/array-of-arrays | 5 |
  | arrays/buffer-bytes | 1 |
  | arrays/ioarray-ends | 1 |
  | arrays/ioarray-sieve | 1 |
  | arrays/ioref-closures | 1001 |
  | arrays/ioref-counter | 1 |
  | arrays/ioref-keeps-old-value | 3 |
  | arrays/ioref-record-in-place | 2 |
  | arrays/lazy-elements | 4 |
  | arrays/st-sum | 1 |
  | data/identity-weakening | 25 |
  | data/records-nested-past-the-cell | 9 |
  | data/records-past-the-cell | 7 |
  | eval/latent-loop | 3 |
  | eval/latent-loop-accumulator | 11 |
  | eval/latent-loop-delay | 3 |
  | eval/lazy-branch-loop | 3 |
  | eval/lazy-list-branches | 3 |
  | eval/memo-lazy | 20 |
  | eval/memo-shared-stream | 355 (3 allowed for the CAF cycle) |
  | interfaces/implementation-runtime-scope | 1 |
  | interfaces/method-runtime-implicits | 1 |
  | io/action-forced-twice | 12 |

- **B. moves-out lost.** The output reads "expected moves-out: no element of
  an array is rebuilt in its place" at idr-rc-exclusive.
  - Shown by: arrays/ioref-keeps-old-value, arrays/ioref-record-in-place.
  - The property is the Roots form, so this is not a naming problem
    (programs.md §4 item 9).
- **C. `unsupported (polymorphism)` on monomorphic Linear.Vec programs
  [§5.19].** The refusals:
  `Linear.Notation.MkBang` / `Builtin.DPair.(#)`: "a shape whose rank no
  analysis fixes".
  - Shown by: arrays/linarray-bubble, linarray-fill-sum,
    linarray-map-fold-traverse, linarray-push-pop, linarray-read-past-size,
    linarray-reserve, linarray-write-past-size, vec-pop-then-push.
- **D. Heap-free broken [§5.13].**
  - data/nbody: `idr.str.show_double` and `idr.str.append` allocate in
    `@Main.main.delay`.
  - interfaces/interface-ring-power: `show_sint` and `str.append` allocate
    in `main.delay` and in a `(>>)` lambda.
  - eval/lazy-branch-loop: `no-heap-allocation=@Main.next` fails, because
    `idr.con` allocates in `@Main.next`.
- **E. The owned verifier refuses counting's output before `linalg.generic`
  [§5.8].** The error is "'linalg.generic' op consumes a view, which holds
  no reference". The tree printer hid it; it was found without dumps.
  - Shown by: arrays/linarray-combinators, linarray-lanes-exact,
    linarray-lanes-wide, linarray-rows-crash-order.
- **F. The `llvm.call` operand type mismatch [§5.12].** The error is
  "expected operand type 'i64', but provided '!llvm.ptr'". Shown by:
  - basic/guards-messages-str-head, guards-messages-str-index,
    string-loop-one-value-twice;
  - data/bubble-sort, sortedmap-map-after-insert, sortedmap-opaque-key;
  - these four, where the tree printer hid it:
    interfaces/implementation-index-function, io/environment-arguments,
    data/sorted-set, io/files-roundtrip.

  files-roundtrip showed exit 124 under the harness, but fails in 4 s
  without dumps.
- **G. idr-rc-exclusive's yield contradicts its solver [§5.9].** In
  data/sortedmap: "internal error: 'idr.yield' op idr-rc-exclusive: gives a
  value of '!idr.own<...List[Char]...>'".
- **H. idr-rc leaves IR its own verifier refuses (class of §5.6/§5.7).** In
  eval/thunk-consumes-list:
  - "'idr.cell.init' op builds an exclusive value of a field that may be
    shared";
  - "'idr.yield' op ends a path on which a value still holds a reference".
- **I. Abort in `idr::ownership::readFrom`.** In
  arrays/transpose-last-two-axes, compile exits 134.
  - Without dumps, the stack reads `cast<TypedValue<MemRefType>>` from
    `memref::LoadOp::getMemref`, then `ownership::readFrom`, `viewedFrom`,
    `definitionChain`, `isStatic` and `tracked`.
  - readFrom takes a LoadOp whose memref operand is not a MemRefType.
  - New in the §5 list.
- **J. arrays/buffer-ops crashes at run time.**
  - Under the harness the compile timed out (124), because the dumps make
    it longer than 60 s.
  - Without dumps it compiles in 43 s, and the program ends with SIGSEGV
    (exit 139) before it writes any output.
  - New in the §5 list. The 43 s compile is also near the step limit
    (§5.39).
- **K. eval/closure-result-roundtrip hangs at run time [§5.21].** The run
  times out at 60 s and prints nothing.
- **L. Bus error after main returns [§5.11].** In io/directory-listing:
  exit 138, after "live cells 7".

## Cross-lane notes for the orchestrator

- **Kept against SUMMARY §3: data/shapes.** It is the input of three other
  lanes' tests: determinism/shapes, determinism/threads-shapes and
  compiler/handoff-round-trip.
  - §3.7 item 7 deletes it together with those, in stage 5.
  - I removed its stale comment instead. It passes.
- **arrays/linarray-lanes-wide keeps its old name.**
  determinism/threads-linarray-lanes/run line 10 compiles it. Rename it to
  `linarray-lanes` in the same change that repoints or deletes that test.
- **The `output-fused` claim.** §3.7 item 6 moves `accept/fused-stored-string`
  and `accept/recursive-string` to `programs/io/` as fixtures stating
  `output-fused`. That is the accept-reject lane's move. Nothing in io
  states `output-fused` until it lands. eval/arity-raising states it today.
- **No shared helper.** `readInt`, the bounds `Arr` scaffolding and the
  get/set/fill/next helpers are still copied across fixtures, because no
  shared test package exists (PROG-17).
- **The flat test layout** that the user asked for is not done here. It
  belongs to whoever restructures the tree.

## What the future generators and harness must cover for what was deleted or weakened

- **bench/<name>/mlir.expect** (§4.2, PROG-10), each run by
  `bench/smoke@<name>` through the one program runner. The deleted
  fixtures' properties, to restate in a Roots form wherever they named an
  inlined helper:
  - fannkuch-redux: `counts-nothing` in rev, flips, next, copy and loop
    (idr-rc-exclusive).
  - fannkuch-linear:
    - `in-place` in rev, flips, shift and copy (idr-bufferize);
    - `counts-nothing` in those and iota;
    - `no-heap-allocation` in rev, flips, shift and copy.
  - qsort:
    - `in-place` in partitionAux, qsortAux and checkSorted;
    - `counts-nothing` and `no-heap-allocation` in the same three. The old
      comment said `partition` is inlined.
  - spectral-norm-linear: `structured-loops` (the step after the structuring
    group), `vectorized` and `narrowed-lanes`.
  - unionfind: `counts-nothing` and `no-heap-allocation` in findEntryAux,
    mergePackAux, mkNodes and numEqsAux. The old comment said `union` is
    inlined.
  - pidigits and mandelbrot: stdout only, already bench/smoke's.
- **The Roots forms of `counts-nothing`, `reuses-in-place` and
  `tests-nothing`** (PROG-4, §6 step 4). They restate the two claims
  removed here:
  - ioarray-sieve: "no reference counted in the sieve's loops";
  - ioref-record-in-place: "the rebuild reuses the record's cell".
- **G1, ADTs and layout** (`data/layout@<n>`). It must draw n around 255,
  256, 511, 512 and 767, 768, which the deleted layout-768 held: a wrap of
  the 8-bit count at every multiple of 256. It must also cover complete
  matches with no default (complete-split) and enum stepping.
- **G9, laziness and IO traces.** stream-share's shape: a top-level
  self-referential stream whose finite prefix forces each cell once. It also
  needs force-delay's chosen-second-branch case.
- **G8, leak growth.** memo-shared-stream's `live-cells 3` pin should become
  "equal live counts at two input sizes" (PROG-16). The pin is kept until
  then.
- **Sem's tables.** basic/numbers' fixed-width cases are Convert entries:
  Int8 of 200, Bits64 of -1, Int of -(2^63-1).
- **The target-fact reader** (PROG-19). The build should publish the
  target's OS name and byte order. Then io/system-info can check `os`
  exactly, and arrays/buffer-ops' little-endian expectation can be read
  from the target instead of written in a comment.
- **The dump-free observation** of §6 step 2. Without it, ten compiles in
  this scope report only "File name too long" and exit 1, 124 or 134, and
  hide bugs E, F, I and J.
