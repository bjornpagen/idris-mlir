<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Audit lane idr-b: `tests/idr/` e2e to lower

## 1. Header

- **Lane:** idr-b.
- **Scope:** `tests/idr/{e2e,effects,expect,fold,func,guards,identity,loops,lower}`: every
  `name.mlir` fixture with its `name/run` and `name/expected`, and the one shell test
  `expect/coverage`.
- **What I read:** `.claude/skills/testing-by-search/SKILL.md` (TBS) and
  `.claude/skills/representation-first/SKILL.md` (RF), both in full; `AGENTS.md`;
  `tests/README.md`; `tests/testutils.sh`; `tests/lib/lit.sh`; `tests/Main.idr` (how pools
  are found); `tests/ACCEPTANCE.md` (its head); `audits/README.md`; every fixture in scope
  with its run and expected files, and the `output` its last run left; the idr-expect
  property table (`foreign/idr/lib/Transforms/Expect/Lookup.cpp`), `Facts.cpp`,
  `TypedReads.cpp`, `IR/Effects.cpp`, and the ODS of `idr.func`, `idr.constant`,
  `idr.world.new`, `idr.check.in_bounds`; `lib/Conversion/Entry.cpp` and
  `lib/Transforms/Pipeline.cpp` (the pass order); `lib/IR/Fold/Strings.cpp`; the git
  history of the fixtures since the wave.
- **Which run the statuses are from:** every `output` in scope is from the
  `make test-idr` run that ended at 14:31 on 2026-10-18 (the same run as `test-idr.log`).
  Five commits that touch what these tests exercise landed after it: 25f263da (14:36,
  complex's lowering model), 4c87dcc5 (14:43, idr-rc-grades), 9696ecc5, a7bf77b4 (14:51,
  stack cells and recycles), 3d279eb9 (16:07, counting grades). One fixture in scope was
  edited after it (`fold/poison-fields`, in dcafd452). So "fail" below means "failed at
  14:31"; where a later commit names the cause, I say so, and today's status is unknown.
  I ran nothing.
- **Counts:** 153 tests (152 `.mlir` fixtures and 1 shell test). At 14:31: 101 passed,
  51 failed, 1 never ran (x86-64 only). There are also 16 directories that hold only an
  ignored `output` file, left over from deleted tests (listed in finding IDRB-21); they
  are not tests.
  - Verdicts: keep 99, rewrite 25, rewrite-as-property 18, merge 3, delete 8. About a
    third of the keeps are expect/'s oracle meta-tests. About half of the other keeps
    fail today because of the compiler, not the test.
  - 125 of the 152 fixtures still carry a `NEEDS-ACCEPTANCE:` line. 29 of those lines
    say only "as before". 14 say only "syntax swept to the data-type-first form".
  - 20 fixtures cite lane or rule ids in their comments (S2, S3, S30, S38, conversion-8,
    mlir-15, ir-ops-6, §7, driver-runtime-T2). AGENTS.md forbids this ("Comments ... do
    not cite documents or rule numbers").

How the 51 failures at 14:31 break down by cause:

| cause | tests | whose |
| --- | --- | --- |
| idris-mlir aborts: complex's `ConvertToLLVMPatternInterface` was never registered | 13 e2e, lower/big-fast-path | compiler (fixed by 25f263da after the run) |
| idr-rc leaves values at the wrong grade, or an `idr.cell.init` whose operand was erased | lower/atom, box, crash, nat, static-thunk, value-buffers, match-lit, strings-bigs, llvm-facts; loops/tail-loop, trmc-counter; expect/counting | compiler (likely 4c87dcc5 and later) |
| hand-written owned-stage IR that does not verify under the wave's grading | loops/trmc; lower/constants, counting, string-build, to-llvm, force-by-name, cells | fixture |
| a hand-written chain of passes that skips idr-entry before convert-to-llvm | lower/arrays (RUN 8), lower/internal-attrs | fixture |
| the expected wording of a diagnostic changed | expect/signature, func/call-type, func/linear-twice, effects/array-memref-effects | fixture (brittle) |
| expects a particular op to be the first one reported | effects/read-past-drop | fixture (brittle) |
| removed syntax, or a removed op form | fold/pending (`idr.con` with holes), expect/typed-reads (`check.in_bounds` on a tensor), guards/fold-unguarded (prints `divs`, not `idr.divs`) | fixture (stale) |
| the harness cannot carry the request | fold/data (a comma in an `idr-expect` argument) | harness |
| the functions under test are dead to upstream's dataflow | fold/range | fixture (the status root) |
| a RUN line was mangled | lower/layout | fixture |
| the expected count is wrong | effects/crash (expects 8 guards; the IR writes 7) | fixture |
| a pipeline that has since changed | fold/poison-fields | fixture (fixed in dcafd452) |
| a real defect | fold/strings (folders over-release), effects/io (`world.new` answers delay), identity/identity (`@carry` keeps its calls) | compiler |

## 2. Verdict table

Abbreviations:
- **TBS n**: a section of testing-by-search. TBS 1.1 is Winters (assert the contract,
  nothing stronger), 1.2 is matklad (build an oracle, then search), 4 is representation,
  5 is distribution, 6 is perception, 7 is the oracle, 8 is stopping and the small-scope
  hypothesis, 9 is model-based testing.
- **RF**: representation-first. "RF one-fact" is "One fact, one place". "RF delete-dead"
  is "Delete what the representation makes dead". RF SPOV2 and SPOV3 are its second and
  third spiky points of view. "RF grain" is "Map onto MLIR's grain".
- **Status** is the 14:31 run.

| path | what it claims to check | verdict | reason | status |
| --- | --- | --- | --- | --- |
| e2e/crash-callsite | a crash at a callsite location names the caller's file:line:col | keep | the only check of how a callsite loc is rendered; contract-level (TBS 1.1) | fail: complex ConvertToLLVM unregistered (fixed 25f263da) |
| e2e/crash | a crash flushes pending output, prints message+loc, exits 1, nothing after runs | delete | programs/partial/crash-after-output and missing-case state this from Idris source (RF one-fact) | fail: complex ConvertToLLVM |
| e2e/doubles | runtime prints shortest round-trip doubles; to_int truncates and wraps | delete | programs/semantics/closed-double-{tie,subnormal,infinity} cover it; a runtime round-trip property belongs to the runtime (TBS 1.2, RF one-fact) | fail: complex ConvertToLLVM |
| e2e/eval | a closed call of a pure total function stays and runs at run time | rewrite-as-property | the claim (not folded) is never checked, only the output; state `calls=@Prog.main:@fact` on the final dump (TBS 1.1) | fail: complex ConvertToLLVM |
| e2e/even-group | the cells of groups 0, 1 and 2 of a 131,073-constructor sum are matched and freed | keep | a boundary property run end to end (TBS 8, move the bug into the box); the awk generator should be Gen's | fail: complex ConvertToLLVM |
| e2e/exit-42 | a status root's result is the exit status | keep | the one run-level check of a status root; drop the stale claim "not evaluated" (TBS 1.1) | fail: complex ConvertToLLVM |
| e2e/hello | IO through the runtime buffer; the object imports nothing beyond the runtime | delete | the output is covered by programs/basic/hello and programs/io; the import check is the universal property (RF one-fact) | fail: complex ConvertToLLVM |
| e2e/loops | each loop shape idr-tail-loops makes prints what the recursion would | rewrite-as-property | hand-computed values; the oracle should be the same program with the tail-loop actions skipped (TBS 1.2, 7) | fail: complex ConvertToLLVM |
| e2e/partial-loop | a non-total self tail call keeps idr.may_loop down to the object code | delete | only checks exit 20; may_loop is checked by lower/may-loop and effects/loop (TBS 1.1: checks nothing it claims) | fail: complex ConvertToLLVM |
| e2e/put-list | a list written as it is walked prints the same bytes as the string built from it | keep | it carries its own two-forms oracle (TBS 1.2) | fail: complex ConvertToLLVM |
| e2e/statics | a list of strings is walked; --mlir-timing names IdrLower and LLVM | delete | TIMING pins pass names in a timing report (TBS 1.1, AGENTS "a pass's transcript"); the walk is covered elsewhere | fail: complex ConvertToLLVM |
| e2e/statuses | usage error exits 2; a foreign op exits 1; a failed compile leaves no output, stale or new | keep | the driver's CLI contract (TBS 1.1) | fail: abort 134 before the parse error (complex) |
| e2e/strings | length, head and index of a UTF-8 string chosen at run time; a match on it | delete | covered by programs/semantics, basic/chars and high-chars (RF one-fact) | fail: complex ConvertToLLVM |
| effects/alloc | allocating ops answer move+delay but not merge; unboxed con merges; dead ops go | rewrite-as-property | the remark per op restates ODS effects (RF one-fact); keep RUN 2's behaviour, generate the rest from the op table | pass |
| effects/array-memref-effects | an array access orders only its own memory: moves-out holds @other, fails @same | rewrite | CHECK pins the wording of the idr-expect message (TBS 1.1); use -verify-diagnostics at the op | fail: message reworded |
| effects/call-effects | idr-effects writes call effects; calls answer from them; CSE and DCE act accordingly | merge-into:tests/idr/effects/queries | its facts duplicate queries; its CSE run duplicates func/call-effects-cse (RF one-fact) | pass |
| effects/crash-call | a call that only crashes declares what an inline crash declares, stays before output | keep | crashes-before-output is the contract (TBS 1.1) | pass |
| effects/crash | each guard of 8 is kept; guards rule crashes out on proving operands | rewrite | expects `crash-sites=@may_crash:8`; the IR writes 7 guards (wrong expectation) | fail: count 7 vs 8 |
| effects/div | a division's guard may be delayed, never speculated; a constant divisor moves | keep | placement contract (TBS 1.1) | pass |
| effects/force-strict | a force before defunctionalization only delays | keep | small, contract-level | pass |
| effects/forced-labels | after defunc a force's effects are its labels'; by_name inferred | keep | properties over the pass output (TBS 1.1) | pass |
| effects/idr-effects | effects of 20 functions; the pass is idempotent | keep | contract; RUN 2's idempotence should be a harness-wide property (TBS 7) | pass |
| effects/inlined-proof | total is lost when a non-total body is absorbed | keep | property (TBS 1.1) | pass |
| effects/io | IO ops and forged worlds answer no fact | keep | expectation matches world.new's documented contract; the failure is a code bug (section 4) | fail: world.new answers [delay] |
| effects/long-cycle | the effects solve reaches every member of a 3,001-function cycle | keep | a scale property; becomes generated call graphs (TBS 9) | pass |
| effects/loop | may_loop keeps a dead loop; an effect-free loop goes | keep | property (TBS 1.1) | pass |
| effects/memo-label | a label's effects flow through the memo dispatch | keep | property | pass |
| effects/queries | drop/move/delay/merge of calls, guards, divisions, matches | keep | receives call-effects (RF one-fact) | pass |
| effects/read-past-drop | moving a read past its drop fails the owned verifier | rewrite | the second split expects the verifier to name idr.tag, but it names the idr.field that also sank (op order, TBS 1.1) | fail: verifier named field, not tag |
| expect/allocation | no-heap-allocation holds, and fails through a call | keep | the checker's own fixture, which shows it can fail (TBS 7) | pass |
| expect/apart | apart holds, and fails on a fused location | keep | oracle meta-test (TBS 7) | pass |
| expect/by-name | by-name and not-by-name read memo labels | keep | oracle meta-test | pass |
| expect/calls | call-order, calls-distinct, calls-read, calls-only, direct-calls | keep | oracle meta-test | pass |
| expect/closures | no-closures and labels | keep | oracle meta-test | pass |
| expect/computes-nothing | computes-nothing | keep | oracle meta-test | pass |
| expect/constant-stack | constant-stack and tail-calls on llvm.func | keep | oracle meta-test | pass |
| expect/continuations | contified | keep | oracle meta-test | pass |
| expect/counted-loop | counted-loop | keep | oracle meta-test | pass |
| expect/counting | reuses-in-place and counts-nothing on idr-rc's output | rewrite | the checker's failing case depends on where idr-rc happens to place a dup (TBS 1.1); write the owned IR by hand, as its neighbours do | fail: idr-rc owned scrutinee (code bug) |
| expect/coverage | every idr-expect property has a fixture where it fails | rewrite | scrapes C++ with sed and greps for text, so a comment counts (TBS 7, RF "every string that names a thing") | pass |
| expect/crash-sites | crash-sites | keep | oracle meta-test | pass |
| expect/dims-known | dims-known | keep | oracle meta-test | pass |
| expect/does | matches, forces, builds, reads-fields, applies, never-returns, calls, calls-closed | keep | each holds and fails on its complement (TBS 7) | pass |
| expect/facts | test-idr-facts reports at the op; an erased op's expectation fails | keep | the reporter's meta-test | pass |
| expect/folded | folded | keep | oracle meta-test | pass |
| expect/fused | fused, with and without upstream elementwise fusion | keep | oracle meta-test | pass |
| expect/growth | grows-nothing against a smaller module | keep | oracle meta-test | pass |
| expect/guards | no-guards | keep | oracle meta-test | pass |
| expect/in-place | in-place | keep | oracle meta-test | pass |
| expect/largest-function | largest-function; a malformed bound is refused | keep | oracle meta-test | pass |
| expect/linker-names | linker-names | keep | oracle meta-test | pass |
| expect/lowered | lowered and in-llvm | keep | oracle meta-test | pass |
| expect/malformed | a malformed request is refused in one wording | keep | oracle robustness: a request that cannot run cannot pass silently (TBS 7) | pass |
| expect/memory | aligned-access, reads-nothing, writes-nothing | keep | oracle meta-test | pass |
| expect/moves-out | moves-out | keep | oracle meta-test | pass |
| expect/narrowed-lanes | narrowed-lanes | keep | oracle meta-test | pass |
| expect/not-called | not-called follows copies by location | keep | oracle meta-test | pass |
| expect/one-clone-two-copies | one-clone fails when calls reach two copies | merge-into:tests/idr/expect/one-clone | one property, two files; one split each (RF one-fact) | pass |
| expect/one-clone | one-clone and specialized-once | keep | oracle meta-test | pass |
| expect/output-fused | output-fused | keep | oracle meta-test | pass |
| expect/paths | loops and straight-line | keep | oracle meta-test | pass |
| expect/placement | eight placement properties | keep | oracle meta-test | pass |
| expect/proved | total and not-total | keep | oracle meta-test | pass |
| expect/quantities | quantities-kept against seeded mutants that drop linearity | keep | mutation testing of the oracle (TBS 7, 1.2) | pass |
| expect/reaches | reaches | keep | oracle meta-test | pass |
| expect/resets-unshared | resets-unshared | keep | oracle meta-test | pass |
| expect/returns | returns, returns-argument, returns-on-paths | keep | oracle meta-test | pass |
| expect/reuses-every-cell | reuses-every-cell | keep | oracle meta-test | pass |
| expect/signature | signature, convention, entry | rewrite | the message now quotes the types; wording pin (TBS 1.1) | fail: message reworded |
| expect/solved-effects | effects reads declared sets | keep | oracle meta-test | pass |
| expect/stage | stage | keep | oracle meta-test | pass |
| expect/structured-loops | structured-loops | keep | oracle meta-test | pass |
| expect/tests-nothing | tests-nothing and exclusive-copy | keep | oracle meta-test | pass |
| expect/typed-reads | typed-reads fails at an index that went through a guard | rewrite | `check.in_bounds` no longer takes a tensor, so the failing case cannot be written as it is; build it from a guard that exists (RF delete-dead) | fail: verifier refuses fixture |
| expect/unknown | an unknown property name is refused | keep | an unknown name cannot pass where it stands (TBS 7) | pass |
| expect/vectorized | vectorized | keep | oracle meta-test | pass |
| expect/words | word-loop | keep | oracle meta-test | pass |
| fold/add-zero | x+0 and 0+x fold to x, Integer and Nat | keep | an algebraic law stated as returns-argument (TBS 1.1) | pass |
| fold/array-dim | memref.dim of idr.array.new folds, clamped at 0 | keep | property (dims-known plus returns) | pass |
| fold/balanced | folders release each reference once | keep | the folds-balanced oracle; see IDRB-14 (never shown failing) | pass |
| fold/big-shift | big shl and shr fold to the runtime's values; huge shifts stay | rewrite-as-property | an example table restating the runtime's meaning (RF one-fact, TBS 1.2) | pass |
| fold/closure | a closure of constants folds to a constant | keep | small property | pass |
| fold/data | constructors of constants fold; fields and tags of known constructors fold | rewrite | the request spells whole data type bodies inside a pass option and breaks at the comma (harness, RF "every string") | fail: pass-option parser |
| fold/division | divs, mods, divu fold; division by zero does not | rewrite-as-property | example table; Sem.idr is the meaning (RF one-fact) | pass |
| fold/nat | Nat ops fold to the runtime's values | rewrite-as-property | example table | pass |
| fold/pending | a read of an `idr.con` hole folds to nothing | delete | `idr.con` no longer has holes; they moved to `idr.cell.init`, so this exercises removed behaviour (RF delete-dead) | fail: `dest` does not parse |
| fold/poison-fields | a constructor with a poison field stays an op and lowers | keep | regression; better stated as a verifier rule "no constant holds poison" | unknown (edited after the run) |
| fold/pred | big.pred folds; pred 0 stays | rewrite-as-property | example table | pass |
| fold/range | int-range-optimizations reads ranges of tag, char, int_head, length | rewrite | under `root(@root)` the functions are private and uncalled, so upstream's dataflow treats them as dead (IDRB-3) | fail: no range folded |
| fold/sccp | SCCP propagates a constructor into a private callee | keep | property | pass |
| fold/shift | fixed-width shifts fold to Idris's meaning for every amount | rewrite-as-property | example table | pass |
| fold/string-offsets | scalar_at and drop_bytes fold at every constant offset | rewrite-as-property | example table; the boundary set should be generated from string encodings | pass |
| fold/strings | pack and concat of constant lists fold, balanced | keep | its failure is a code bug (section 4) | fail: folds-balanced -2 |
| fold/to-char | to_char_s and to_char_u fold | rewrite-as-property | example table | pass |
| fold/to-int | to_int folds finite values; NaN's guard stays | rewrite-as-property | example table; the guard half belongs to guards/ | pass |
| func/call-effects-contain | a call's effects contain its callee's (verifier); bare syntax round trip | keep | verifier contract | pass |
| func/call-effects-cse | canonicalize and CSE erase and merge pure calls, keep linear ones | keep | behaviour (TBS 1.1) | pass |
| func/call-effects | a call answers from the effects it holds, by default everything | keep | contract | pass |
| func/call-type | the call and return type rules of the verifier | rewrite | "module" became "program" in a message; wording pin (TBS 1.1) | fail: message reworded |
| func/linear-twice | the linear-use rule; grades of fields; linear closures | rewrite | one split pins old wording (TBS 1.1); also receives world-twice | fail: message reworded |
| func/owned-not-consumed | the owned verifier refuses a leaked reference | keep | verifier contract | pass |
| func/two-blocks | a function body is one block | keep | verifier contract (pins upstream's text; low) | pass |
| func/world-twice | the world is used once on every path | merge-into:tests/idr/func/linear-twice | the world is linear by its type; one rule, one family over every type linear by its type (RF one-fact) | pass |
| guards/fold-finite | check.finite folds on a finite constant, stays on NaN/inf, a re-guard folds | rewrite-as-property | one family generated from the guard table (RF one-fact, TBS 9) | pass |
| guards/fold-in-bounds | check.in_bounds the same | rewrite-as-property | as above | pass |
| guards/fold-nonempty | check.nonempty the same | rewrite-as-property | as above | pass |
| guards/fold-nonzero | check.nonzero the same | rewrite-as-property | as above | pass |
| guards/fold-range | check.range the same | rewrite-as-property | as above | pass |
| guards/fold-unguarded | no folder of a guarded op folds on constants its guard refuses | rewrite-as-property | FileCheck matches `idr.divs` but the op prints as `divs` inside idr.func (printed syntax, TBS 1.1); `returns=@unguarded:_/.../_` says it, generated from the guard table | fail: prefix elided in print |
| identity/identity | each function that rebuilds its argument has its calls replaced | rewrite-as-property | expectation right (a code bug shows, section 4); 12 cases hand-written into one module that depends on which calls are inlined; generate them (TBS 9) | fail: @carry still called |
| loops/accumulate | accumulator clones make loops; thread-independent; idempotent | rewrite | 4 of its 9 functions (@down, @twos, @down_out, @as_integer) have no property though the comment describes them (TBS 1.1, checks nothing); its module duplicates actions/accumulate | pass |
| loops/tail-loop | self tail calls become loops; counting up becomes scf.for | keep | properties; the failure is idr-rc's (section 4) | fail: idr-rc unlinked operand |
| loops/trmc-counter | replicate and take run in constant stack after rc and trmc | keep | properties; the failure is idr-rc's | fail: idr-rc owned match_lit scrutinee |
| loops/trmc | idr-trmc's clone of a constructor around its own result is a loop | rewrite | the hand-written owned IR does not verify (`idr.dup` of an ungraded constant); its module duplicates actions/trmc | fail: fixture type mismatch |
| lower/arrays | array lowering: signatures, guards, counting, fill loop, LLVM conversion | rewrite | RUN 8 converts to LLVM without idr-entry (hand-spelled pipeline); signature and inc-per-element call-order pin internal lowering choices (TBS 1.1) | fail: RUN 8 program root not func.func |
| lower/atom-unfolded | a nullary boxed con lowers to its static atom | keep | property | pass |
| lower/atom | a nullary boxed con after idr-rc allocates nothing | keep | property; idr-rc failure | fail: idr-rc grades |
| lower/big-fast-path | small bigs import no runtime big function; large ones import addLarge | rewrite | greps for the mangled C++ name `_ZN2rt3big8addLarge`, a runtime-internal name (TBS 1.1) | fail: complex ConvertToLLVM |
| lower/box | box cell lowering, match reads tag and fields | keep | properties; idr-rc failure | fail: idr-rc grades |
| lower/buffer | buffer load, store, copy: guards and runtime calls | keep | properties at the runtime boundary | pass |
| lower/cells | each cell producer lowers alone | rewrite | the verifier now refuses a recycle of a token passed in ("no idr.take made"); rebuild the producers from takes (RF delete-dead) | fail: fixture refused by verifier |
| lower/closure-left | a closure or force past higher is refused by the program verifier | keep | verifier contract (belongs in verify/) | pass |
| lower/constants | static data for strings, bigs, boxes; unboxed constants | rewrite | an owned-stage root receives plain-grade results (invalid fixture); its signature pins the sum layout that data-layout owns (RF one-fact) | fail: fixture grade |
| lower/counting | dup/drop/take/recycle call the runtime per counted component | rewrite | `idr.dup` of an ungraded constant: hand-written owned IR invalid | fail: fixture type mismatch |
| lower/cpu-features-x86-64 | @main passes the x86-64-v3 feature word to the runtime | rewrite | checks only `entry` and that @main calls idris_rt_start, never the word; restricted to x86 hosts though it needs none (TBS 1.1, 5) | unknown: never runs on arm64 |
| lower/crash | crash and guard lowering, crash sites | keep | properties; idr-rc failure | fail: idr-rc grades |
| lower/data-layout | an unboxed sum's tag and slots; a match reads no memory | keep | owns the layout fact; keep RUN 1's properties | pass |
| lower/entry | idr-entry's protocol for status, IO and IORes roots | keep | the runtime entry contract | pass |
| lower/exclusive | an exclusive take and recycle test nothing | keep | property | pass |
| lower/force-by-name | a by_name label's case calls the label and writes nothing | rewrite | `idr.io.put_str %v` of a borrowed string is old syntax (needs the `borrow` form) | fail: fixture type mismatch |
| lower/force-excl | an exclusive memo cell is forced once, freed, never written | keep | property | pass |
| lower/force-view | the memo dispatch lowers to enter, call, settle | keep | property | pass |
| lower/in-bounds | an access is tested by its guard alone | keep | property | pass |
| lower/internal-attrs | no idr fact reaches LLVM | rewrite | converts to LLVM without idr-entry (hand-spelled pipeline) | fail: program root not func.func |
| lower/internal-errors | a module of another data layout is refused, never as `unsupported` | keep | contract | pass |
| lower/io | IO ops lower to runtime calls in world order; the entry body | keep | runtime ABI contract | pass |
| lower/layout | header limits lifted: 256 strings, 65,537 constructors, 258 refs | rewrite | the RUN lines' awk programs were mangled; a size boundary should be exhausted around each limit (TBS 8) | fail: RUN 2 and 4 shell syntax |
| lower/linear-constant | linearity has no runtime form in static data | keep | property | pass |
| lower/linear | a linear parameter lowers to the value | keep | property | pass |
| lower/llvm-facts | parameter attributes, alignment, cold crash, ranges LLVM reads | keep | FileCheck is allowed here (README); idr-rc failure | fail: idr-rc unlinked operand |
| lower/mangle | every symbol is in the linker's alphabet | keep | property | pass |
| lower/match-lit | literal match lowering: switch, comparisons, empty match | keep | properties; idr-rc failure | fail: idr-rc default region |
| lower/may-loop | may_loop survives lowering and canonicalize | keep | property | pass |
| lower/nat | a natural lowers to the big's word | keep | property; idr-rc failure | fail: idr-rc nat.to_big grade |
| lower/no-mode | idr-lower has no `jit` option | delete | guards an option that is gone; MLIR's option parser is the whole oracle (RF delete-dead) | pass |
| lower/select | arith.select of an unboxed sum selects each component | rewrite | its signature pins the sum layout that data-layout owns; keep straight-line and calls-only (RF one-fact) | pass |
| lower/static-thunk | a lazy constant is a mutable memo cell in static data; CAFs released | keep | properties; idr-rc failure | fail: idr-rc grades |
| lower/strided-symbol | an affine-map memref carries its symbol stride as a component | keep | the descriptor plan (low) | pass |
| lower/string-build | pack and concat allocate once; put_list writes as it walks | rewrite | an ungraded constant is passed where a borrow is expected (invalid fixture) | fail: fixture type mismatch |
| lower/strings-bigs | string and big ops call their runtime functions; guards crash | keep | properties; idr-rc failure | fail: idr-rc guard grade |
| lower/to-llvm | upstream conversions take the program to LLVM, no casts left | rewrite | constant used as a borrow (invalid), and it converts to LLVM without idr-entry | fail: fixture type mismatch |
| lower/value-buffers | buffers of bufferization lower to runtime cells and copies | keep | properties; idr-rc failure | fail: idr-rc grades |
| lower/world | a forged world has no runtime form | keep | property | pass |

## 3. Findings

**IDRB-1. harness-representation, medium.** The 152 `run` and 152 `expected` files of the fixtures in scope
only repeat what the `.mlir` fixture already says.
- Paths: every `tests/idr/<dir>/<name>/{run,expected}` in scope except `expect/coverage`.
- Evidence: every `run` is the same three lines plus `lit ../<name>.mlir`.
  `e2e/even-group/run` alone adds a line: `step_limit=300 / test_limit=900`. Every
  `expected` is `RUN 1: ok` ... `RUN n: ok`, with n exactly the number of RUN lines in the
  fixture. I checked this mechanically for all 152 fixtures.
- Guideline: RF one-fact ("A fact held twice ... is generated from its one source or
  deleted"); TBS 1.1 (the vocabulary is the tool's).
- Recommendation: let the runner find each `idr/**/*.mlir` itself, with the expectation
  "every RUN line passes". Delete the 304 boilerplate files. Put a fixture's limits in a
  header line of the fixture. With this, a `.mlir` that has no `run` directory can no
  longer be silently skipped.

**IDRB-2. harness-representation, high.** Fixtures spell out the pipeline's pass order by
hand, so the order now lives in two places, and the wave broke five fixtures where the
two disagree.
- Paths: lower/arrays (RUN 8), lower/internal-attrs, lower/to-llvm, lower/llvm-facts
  (RUN 4), fold/poison-fields (fixed by hand in dcafd452). 20 fixtures in all chain idr
  passes by hand: effects/forced-labels, fold/poison-fields, loops/{trmc-counter,
  tail-loop}, lower/{atom, arrays, cpu-features-x86-64, box, entry, layout, io, llvm-facts,
  crash, nat, static-thunk, value-buffers, internal-attrs, to-llvm, match-lit,
  strings-bigs}.
- Evidence: `RUN: idris-mlir-opt %t.mlir --canonicalize --cse --convert-scf-to-cf
  --convert-to-llvm --reconcile-unrealized-casts ...` fails with `'idr.program' op has
  root @root, which is no func.func of the program`. The real pipeline runs idr-entry
  first: `lib/Conversion/Entry.cpp` "takes the program idr-lower lowered apart into the
  module", and `Pipeline.cpp` adds `createConvertToLLVMPass` after that. In
  fold/poison-fields, the fixture's `--idr-defunctionalize --idr-lower` had to become
  `--idr-defunctionalize --idr-rc --idr-lower` in dcafd452.
- Guideline: RF one-fact; RF "Use the infrastructure" (`Passes.td` for pass facts); TBS 1.1.
- Recommendation: give idris-mlir-opt one entry to the real pipeline up to or from a named
  step (for example `--idr-pipeline=from:lowered`), or state the property at the step dump
  as `mlir.expect` does in tests/programs. A fixture then names a step, never a sequence
  of passes.

**IDRB-3. harness-representation, high.** In 79 of the 152 fixtures, the functions under
test are dead code to upstream's analyses.
- Paths: every fixture with `root(@root)` and the comment "The program's root, which the
  functions above are no part of" (79 files). Shown failing: fold/range.
- Evidence: the ODS of `idr.func` says "it is public exactly when it is its program's
  root ... and private otherwise, so that upstream's symbol walks ... may drop any other
  function without uses". fold/range runs `--int-range-optimizations` over private
  functions that nothing calls. Every result fails, including
  `str.length >= 0`: `expected returns: result 5 of @ranges is not the constant true`.
  That is DeadCodeAnalysis never marking the bodies live, not six range methods breaking
  at once. Any `symbol-dce`, inliner or `remove-dead-values` in a RUN line would delete
  these functions too.
- Guideline: RF SPOV3 (a coordinate error: the dummy root satisfies "one root per program"
  without keeping the code under test reachable); TBS 9.2 step 5 ("Check that the real
  system actually entered each state the model claimed. Otherwise the test can silently
  check nothing").
- Recommendation: a fixture's root calls every function under test, as identity/identity's
  `@observe` does. Or idr-expect refuses a request that names a function its root cannot
  reach, so the dead state cannot pass unnoticed.

**IDRB-4. brittle-overspecified, medium.** Four failures, and a fifth that depends on
which op is reported first, are wording changes in diagnostics, not defects.
- Paths: expect/signature, func/call-type, func/linear-twice,
  effects/array-memref-effects, effects/read-past-drop. The same pinning appears in
  loops/{accumulate, tail-loop, trmc} (FileCheck on idr-expect messages) and in every
  expect/ fixture's `expected-error {{...}}`.
- Evidence:
  - expect/signature: `expected signature: @plain has the type '(i64) -> i64', not
    '(i64) -> i32'` against the expected `... (i64) -> i64, not (i64) -> i32`.
  - func/call-type: `which the program does not define` against `which the module does
    not define`.
  - func/linear-twice: `expects a default region that takes the scrutinee back at its
    type` against `... without arguments, or one that ...`.
  - effects/array-memref-effects: `no element of an array is rebuilt in its place` against
    `no read of an element moves it out of its array`.
  - effects/read-past-drop: the verifier names the `idr.field` that also sank, not the
    `idr.tag`.
- Guideline: TBS 1.1 (asserts more than the contract: the contract is that the request
  fails at that op, under that property).
- Recommendation: `expected-error-re @below {{expected <property>: .*}}`, or a prefix that
  names only the property and the op. For read-past-drop, give each split exactly one
  read that can sink. Keep full wording only where the text is the contract
  (`spec/dialect-text`).

**IDRB-5. stale-legacy, high.** Seven hand-written owned-stage fixtures do not verify
under the wave's grading, and none was ever built.
- Paths: loops/trmc, lower/{counting, string-build, to-llvm, constants, force-by-name,
  cells}. tests/idr/actions/trmc (lane idr-a) holds the same module.
- Evidence:
  - `%nil = idr.constant !idr.box<!List> ...` then `%o = idr.dup %nil :
    !idr.q<many, borrow, !idr.box<!List>>` gives `use of value '%nil' expects different
    type than prior uses`.
  - constants: `'idr.call' op gives result #0, of type '!idr.str', which holds references
    at the plain grade in a graded program`.
  - force-by-name: `idr.io.put_str %v` of a borrowed `%v`.
  - cells: `'idr.cell.recycle' op recycles a token that no idr.take made`.
- Guideline: RF one-fact (the grading rules are spelled again by hand in every owned
  fixture, and drift); TBS 4.1 (construct valid inputs, do not hand-write them).
- Recommendation: produce owned-stage inputs from first-stage sources through the real
  idr-rc step and state the lowering properties on that dump. Keep hand-written owned IR
  only in a few minimal verifier fixtures.

**IDRB-6. perception, high.** A defect in idr-rc shows up as a dozen failures in other
passes' suites.
- Paths: lower/{atom, box, crash, nat, static-thunk, value-buffers, match-lit,
  strings-bigs, llvm-facts}, loops/{tail-loop, trmc-counter}, expect/counting.
- Evidence: each runs `--idr-rc` (or `idr-rc,`) before the pass under test, and each
  fails inside idr-rc's output. For example lower/box fails with `'idr.return' op returns
  '!idr.box<...>' as result 0, but @push returns '!idr.own<...>'`.
- Guideline: TBS 6.2 (features too coarse: one cause, many alarms that do not say where);
  TBS 1.3.
- Recommendation: have the harness run the prerequisite step once and report a failure
  there as that step's (one line, "idr-rc failed on ..."), not as the lowering's. Tests of
  idr-rc itself belong in rc/ (lane idr-c).

**IDRB-7. example-should-be-property, medium.** The fold tables in fold/ write the runtime's
meaning out by hand, value by value.
- Paths: fold/{big-shift, shift, division, nat, pred, to-char, to-int, string-offsets}.
- Evidence: fold/shift has `returns=@signed:0/-2/-2/-1/-9223372036854775808/0`, with
  comments such as "Scheme's ash wrapped to the width". AGENTS.md says "No primitive has an
  implementation in Idris: its one meaning is the runtime's, which folders call too". So
  what can go wrong in a fold is the marshalling between attribute and runtime value
  (width, sign, wrap), which these few examples barely sample.
- Guideline: TBS 1.2 (an oracle: the fold against the program run); TBS 8 (exhaust the
  small cases); RF one-fact.
- Recommendation: one generated property over Sem.idr's table. For each foldable op, at
  every width, over a dictionary of edge constants (0, ±1, min, max, the width, width±1,
  negative amounts, NaN, ±inf, surrogates, offsets inside a UTF-8 sequence): the
  canonicalized constant equals what the compiled program prints at run time.
  `tests/two-levels` is the machinery to extend.

**IDRB-8. example-should-be-property, medium.** The guard-fold fixtures are one family of
cases written out by hand, five times.
- Paths: guards/{fold-finite, fold-in-bounds, fold-nonempty, fold-nonzero, fold-range,
  fold-unguarded}.
- Evidence: each file has `@proving`, `@failing` and `@again` (re-guard idempotence) for
  one guard. fold-unguarded uses `CHECK-DAG: idr.divs %`, which fails because the op
  prints as `divs` inside `idr.func`. Its claim is already expressible:
  `returns=@unguarded:_/_/...`.
- Guideline: RF "A switch on a tag is a polymorphism not yet named"; "Declare, don't
  write" (the guards are ODS records, `Idr_Guarded`); TBS 1.1 (printed syntax pinned
  outside asm/ and syntax/, which tests/README.md forbids).
- Recommendation: generate one family from the guard records. For each guard: a constant
  that satisfies it folds the guard away (no-guards); a constant that refuses it keeps one
  crash site; a guard of its own result folds; the guarded op on a refusing constant
  without its guard does not fold.

**IDRB-9. checks-nothing, medium.** Fixtures whose comments state a claim that no RUN
line checks.
- Paths: lower/cpu-features-x86-64, loops/accumulate, e2e/partial-loop, e2e/exit-42,
  e2e/eval, lower/io, fold/poison-fields.
- Evidence:
  - cpu-features: the comment says "x86-64-v3 is bits 0 to 15 ... and no AVX-512", but the
    RUN lines check only `entry,calls=@main:@idris_rt_start`.
  - accumulate: the comment describes @down, @twos, @down_out and @as_integer, and no
    property names any of them.
  - partial-loop: the comment says it "keeps idr.may_loop ... down to the object code";
    the test checks only `%status 20`.
  - exit-42: "not total, so it is not evaluated" is unchecked, and is stale anyway (AGENTS:
    static normalization "is not built").
  - eval: "stays in the module and runs at run time" is unchecked.
  - io: "a module with no target asks the processor for no feature, the runtime's word 0"
    is unchecked.
  - poison-fields: "no constant holds poison" is unchecked.
- Guideline: TBS 1.1; TBS 9.2 step 5.
- Recommendation: state each claim as a property, or delete the claim and the test.
  cpu-features should check the word, computed from the runtime's feature table, which is
  the one source.

**IDRB-10. distribution, medium.** A target-lowering test runs only on one host, though it
needs no host of that target.
- Paths: lower/cpu-features-x86-64 (`targets`: `x86-64`).
- Evidence: it only runs `idris-mlir-opt` on a module that carries
  `llvm.target = #llvm.target<triple = "x86_64-unknown-linux-musl" ...>`, which any host
  can lower. On the arm64 macOS build it never ran (there is no `output`). There is no
  aarch64 counterpart in scope.
- Guideline: TBS 5 (what the search tries often); AGENTS.md (two first-class targets;
  "Per-target cases elsewhere are bugs").
- Recommendation: one test parametrised over the target entries in CMakeLists.txt, run on
  every host, each checking its target's feature word.

**IDRB-11. harness-representation, medium.** idr-expect arguments are text inside a pass
option, and MLIR attribute syntax does not fit there.
- Paths: fold/data, fold/closure, fold/balanced, fold/big-shift, and every request that
  carries an attribute.
- Evidence: fold/data fails with `<Pass-Options-Parser>: no such option plain`, because
  the request spells `#idr.con<!idr.data<"S", plain [@A(), @B(i64, !idr.str)]>, ...>`,
  whose comma ends the option. The request also repeats each data type's whole printed
  body, which is a printed form.
- Guideline: RF "Every string that names a thing is a missing type"; RF "Parse at the
  boundary, once"; TBS 1.1 (printed forms pinned).
- Recommendation: state expectations in the fixture as IR, not in the option string. For
  example an `idr.expect` op or attribute inside the module, parsed by MLIR's own parser,
  with values written in the module's own aliases. Or let `returns=` name a constant
  defined in the fixture.

**IDRB-12. stale-legacy, medium.** Fixtures that exercise removed behaviour.
- Paths: fold/pending, expect/typed-reads, lower/no-mode, lower/cells.
- Evidence:
  - fold/pending: `%c, %d = idr.con !idr.box<!List> @Cons(%x : i64, dest)` gives `expected
    SSA operand`. `dest` is parsed only by `idr.cell.init` (`parseFields`, Ops.cpp); the
    wave's log says "con's stack and holes gone".
  - typed-reads: `'idr.check.in_bounds' op operand #1 must be a string, read in place or an
    array a world orders`.
  - no-mode: checks `no such option jit`.
  - cells: a token as a parameter, which the verifier now refuses.
- Guideline: RF delete-dead ("the test that checked the impossible state").
- Recommendation: delete fold/pending and lower/no-mode. Rebuild typed-reads' failing case
  and lower/cells on states that can still be written.

**IDRB-13. redundant, low.** Fixture bodies and claims are duplicated across files and
across lanes.
- Paths: loops/accumulate and actions/accumulate (the same module); loops/trmc and
  actions/trmc (the same module); effects/call-effects with effects/queries and
  func/call-effects-cse; e2e/{crash, doubles, strings, hello} with tests/programs;
  expect/one-clone-two-copies with expect/one-clone; func/world-twice with
  func/linear-twice; e2e/loops with loops/tail-loop (the same functions).
- Guideline: RF one-fact.
- Recommendation: merge or delete as the table says. A fixture module that two
  directories need lives once and is referenced by both, or the action property
  (lane idr-a) becomes generic over a corpus (IDRB-19).

**IDRB-14. wrong-or-missing-oracle, medium.** One oracle has never been shown able to
fail, and the meta-test of the oracles reads text.
- Paths: expect/coverage, fold/balanced, fold/string-offsets, fold/strings.
- Evidence: coverage's run has `exempt='folds-balanced'` and the comment "No folder leaks,
  so no fixture shows a leak". Coverage itself is
  `sed -n 's/^ *property<[^>]*>("\([^"]*\)".*/\1/p' .../Lookup.cpp` followed by
  `grep -qF "expected $name: " tests/idr/expect/*.mlir`, so a comment or a stale
  expectation counts as a failing fixture.
- Guideline: TBS 7 ("A search can only find a bug if something recognizes the bug"); TBS
  1.1 (the testing vocabulary).
- Recommendation: have idris-mlir-opt list its properties (the one source). Coverage
  checks that each name appears in an `expected-error` of a `-verify-diagnostics` RUN
  line that passed. Give folds-balanced a failing fixture through a test-only folder that
  leaks deliberately (a seeded mutant, as expect/quantities does for linearity).
  fold/strings fails today, which shows the oracle can fail, but only because of a bug.

**IDRB-15. example-should-be-property, medium.** The facts remarks restate each op's
declared effects, one op at a time.
- Paths: effects/{alloc, call-effects, crash-call, div, force-strict, io, queries},
  func/call-effects, expect/facts.
- Evidence: `// expected-remark @below {{facts: [move delay]}}` above
  `%c = idr.str.append %s, %s`, and the same over and over. `test-idr-facts` computes the
  answers from the op's MemoryEffects (Facts.cpp: `isOpTriviallyDead`, `onlyAllocates`,
  `!performsIO`, `isMemoryEffectFree`), so each remark repeats the ODS declaration.
- Guideline: RF one-fact; TBS 9 (model-based testing).
- Recommendation: keep one facts fixture per kind of answer, as a meta-test of the
  reporter. Replace the per-op tables with a model-based property:
  1. Generate programs over the effect lattice (none, crash, io, diverge; IO ops, guards,
     allocations, calls of functions of each class).
  2. Run canonicalize, cse and control-flow-sink.
  3. Check that the program's observable trace (its output, then its crash or exit) is
     unchanged, run against the unoptimized program.

  This catches the world.new defect (section 4) by behaviour, not by its label.

**IDRB-16. brittle-overspecified, medium.** Lowering fixtures pin internal choices that no
contract fixes.
- Paths: lower/{arrays, select, constants, data-layout, strided-symbol, big-fast-path}.
- Evidence:
  - arrays: `signature=@make:(i64,i8,!llvm.ptr)->(!llvm.ptr,i64)`, and
    `call-order=@make:[@idris_rt_array_new,@idris_rt_inc,@idris_rt_dec],loops=@make:1`.
    That is a fill strategy of one increment per element; a single runtime fill call
    would break it while meaning the same.
  - select and constants: their signatures repeat data-layout's slot layout ("as
    data-layout.mlir lays a sum out").
  - big-fast-path: `grep -E '^_?_ZN2rt3big8addLarge'`, a mangled C++ name inside the
    runtime.
- Guideline: TBS 1.1; RF one-fact.
- Recommendation: one fixture owns the unboxed-sum layout. The others state reads-nothing,
  calls-only and crash-sites. Reference counting is checked by its run-time oracle (the
  live-cells count at exit), not by the order of inc and dec calls. big-fast-path keeps
  "imports no `idris_rt_big_*` entry" and drops the mangled name.

**IDRB-17. stale-legacy, low.** Comments cite lane and rule ids, and NEEDS-ACCEPTANCE
lines say only "as before".
- Paths: 20 fixtures with ids such as `(S2)`, `(S3)`, `(S30)`, `S38`, `conversion-8`,
  `mlir-15`, `ir-ops-6`, `§7`, `driver-runtime-T2` (for example lower/atom, lower/buffer,
  identity/identity, lower/entry); 125 fixtures with a mark, of them 29 "as before" and 14
  "syntax swept to the data-type-first form".
- Guideline: AGENTS.md ("Comments ... do not cite documents or rule numbers"); TBS 1.1 (an
  expectation nobody has confirmed is no specification).
- Recommendation: accept or delete per section 2 on the build. Strip the ids.

**IDRB-18. harness-representation, low.** Generators written as awk inside RUN lines.
- Paths: e2e/even-group, lower/layout, effects/long-cycle.
- Evidence: lower/layout's RUN 2 and RUN 4 fail with `syntax error near unexpected token
  '('`. A rewrite mangled the awk text: `> %t.wide.mlir @A("; for (i = 0; i < 256; i++)
  printf (i ? " : "; ...`.
- Guideline: TBS 4.1 (generate by construction); RF "make control flow into data".
- Recommendation: generators belong in Gen (Idris) or a small tool with a typed
  description of the shape (size n, at each boundary). The fixture names the shape and
  the sizes; the boundaries are exhausted (IDRB-20).

**IDRB-19. infrastructure-gap, medium.** No differential oracle exists for the optional
transforms.
- Paths: e2e/loops, e2e/put-list, loops/*, identity/identity.
- Evidence: e2e/loops checks hand-computed values (`CHECK: 285`, ...). Only e2e/put-list
  compares two forms of one computation (`[xé€😀] [xé€😀] 4`). Every optional transform is
  an MLIR action (lane idr-a's actions/ fixtures use
  `-mlir-debug-counter=<action>-count=0`).
- Guideline: TBS 1.2 and 7 (a second implementation we own); TBS 2 (feedback).
- Recommendation: the same e2e program, run with each action skipped (and with random
  subsets skipped, swarm-style, TBS 5), must print the same and exit the same. This
  replaces most hand-computed e2e values and covers the transform passes' semantics on
  any program, the tests/programs corpus included.

**IDRB-20. distribution, low.** The size boundaries are sampled once, not exhausted.
- Paths: lower/layout (256 counted references, 65,537 constructors, 258 references),
  e2e/even-group (131,073).
- Evidence: one point past each limit.
- Guideline: TBS 8 (the small-scope hypothesis; "move a bug into the box ... randomize the
  constant across runs").
- Recommendation: each limit at n-1, n, n+1 and 2n±1, run to the end, with run-time
  matching of every group, as even-group does.

**IDRB-21. infrastructure-gap, low.** Directories of deleted tests remain on disk.
- Paths: e2e/reduce, effects/{erased-consumer, stale}, expect/{breakers, breaks-last},
  func/{clone-shape, facts-roundtrip, inline}, guards/{byte-message, fold-byte,
  speculation}, loops/{breakers, invariant-fields},
  lower/{array-combinators, array-never-returns, to-byte}.
- Evidence: each holds only `output`, which `.gitignore` ignores (`/tests/**/output`).
- Guideline: RF delete-dead.
- Recommendation: the runner removes an `output` whose directory has no `run`, or writes
  outputs under `tests/build/`.

**IDRB-22. code-bug-revealed, high.** See section 4, items 1 to 6.

## 4. Code bugs the tests reveal

1. **idris-mlir aborts: complex's lowering interface was never registered.** Fails all 13
   e2e fixtures and lower/big-fast-path.
   - Output: `LLVM ERROR: checking for an interface (mlir::ConvertToLLVMPatternInterface)
     that was promised by dialect 'complex' but never implemented`. The trace runs through
     `LoadDependentDialectExtension::apply` while `TensorDialect` loads.
   - Reading: tensor loads complex, and the driver registered no complex-to-LLVM
     extension. 25f263da ("complex's lowering model") landed 5 minutes after the run; the
     newer test.log has no such line. Very likely fixed.
2. **idr-rc leaves values at the wrong grade** (as of 14:31). The outputs show:
   - a return of plain `!idr.box`/`!idr.str` where the function now returns `!idr.own<...>`
     (lower/atom, box, crash, static-thunk, value-buffers);
   - a `default` region not retyped (`expects a default region that takes the scrutinee
     back at its type`: lower/atom, match-lit);
   - case fields not graded (lower/box, static-thunk, expect/counting);
   - an owned scrutinee (`'idr.match' op operand #0 must be ... not owned`: expect/counting;
     `'idr.match_lit' op operand #0 ... got '!idr.own<!idr.nat>'`: loops/trmc-counter);
   - plain call results in a graded program (lower/crash, nat);
   - a guard whose operand is borrowed while its result stays plain (`'idr.check.nonempty'
     op requires the same type for all operands and results`: lower/strings-bigs);
   - `nat.to_big` at the wrong grade (lower/nat);
   - `idr.own.give` of a borrow at a `memref.store` (lower/value-buffers).

   Reading: idr-rc-grades does not regrade every region and result it touches. 4c87dcc5
   ("idr-rc-grades places every body under the grades it writes") and 3d279eb9 came after
   the run and plausibly address it. The expectations are right.
3. **idr-rc's cells step leaves `idr.cell.init` with an erased operand.** Fails
   loops/tail-loop and lower/llvm-facts.
   - Output: `error: operation's operand is unlinked ... "idr.cell.init"(<<UNKNOWN SSA
     VALUE>>, ...)`.
   - Reading: the cell producer is erased or replaced before its init's use is rewired, a
     use after erase inside the compiler. a7bf77b4 ("Stack cells and recycles are built
     where their cells were") is the likely fix. Run this one under the sanitizers.
4. **`idr.world.new` answers "may be delayed".** Fails effects/io.
   - Output: `io.mlir:25:8` and `:29:8`: `expected remark "facts: []" was not produced`, at
     both world.new ops.
   - Reading: the ODS declares only `MemoryEffects<[MemWrite<Idr_IOResource>]>`, and
     `performsIO` (IR/Effects.cpp) counts only a *read* of the IO resource as IO ("A crash
     and a loop that may not end only write the IO resource"). So world.new answers
     `[delay]`, like a crash. Its own description says "no pass merges two, moves one past
     an IO op, or deletes one". The expectation is right; world.new should read the IO
     resource as the other IO ops do. I have not checked whether a sink can actually
     reorder a forged chain's output today.
5. **The string folders over-release.** Fails fold/strings.
   - Output: `expected folds-balanced: -2 cells the folders left live`, then
     `contract folds-balanced broken by canonicalize`.
   - Reading: `stringOfList` (Fold/Strings.cpp) chains
     `scope.keep(fold::runtime<StrAppendOp>(s, scope.str(...)))` and the same for
     `StrConsOp`. If the runtime's append and cons consume their string argument, each
     intermediate `s` is released twice, once by the runtime and once by the scope. That
     matches a negative count. This reading is plausible, not verified.
6. **identity: `@carry` keeps its calls.** Fails identity/identity.
   - Output: `expected not-called: @carry is still called, as @carry, in @carry`, and the
     same `in @root`.
   - Reading: `@carry` is total and gives back its argument on every path (base case `x`;
     recursive case the call on `(n-1, x)`). The identity analysis does not find it, or
     loses `total` on the way (absorb clears it when a body takes in a callee without
     it). I have not localized it.

Not code bugs, though they fail: fold/range (IDRB-3, high confidence), fold/data
(IDRB-11), fold/pending and expect/typed-reads (IDRB-12), effects/crash (the expectation
of 8 is a miscount; the IR writes 7 guards), lower/layout (IDRB-18), and the fixture
failures of IDRB-2, 4 and 5.

## 5. What a rebuilt scope should look like

- **No boilerplate.** The runner finds `idr/**/*.mlir`; a fixture passes when every RUN line
  passes, and its limits sit in a header line (IDRB-1). Expectations sit in the module as IR
  that MLIR parses (IDRB-11), and no RUN line spells a pass sequence: it names a step of the
  real pipeline (IDRB-2).
- **Fixtures keep what they test reachable.** The root calls each function under test, or
  idr-expect refuses a request on a function its root cannot reach (IDRB-3).
- **expect/ stays as the oracle suite,** one holds case and one fails case per property, with
  coverage driven by the tool's own list of properties (IDRB-14). Add seeded mutants for every
  oracle that can never fail on real code: folds-balanced (a leaking test folder), and the
  analogue of expect/quantities for the effects, counting and placement checkers.
- **The fold tables become a differential property over Sem.idr's table** (IDRB-7). The
  operands are generated per op and width from an edge dictionary, with swarm weights per
  run. The oracle is the same closed expression compiled and run, and folds-balanced holds on
  every fold. This replaces fold/{big-shift, shift, division, nat, pred, to-char, to-int,
  string-offsets} and the value halves of fold/data.
- **Guards become one family generated from the `Idr_Guarded` records** (IDRB-8): satisfies,
  refuses, re-guard, unguarded op on a refusing constant. This replaces guards/*.
- **Effects get one model-based property** (IDRB-15). A generator builds programs over the
  lattice none, crash, io and diverge, mixing IO ops, forged worlds, guards, allocations and
  calls of each class; it is indexed so that every world is used once (a harness invariant,
  TBS 4.3), with invalid states named, not filtered out. The oracle is the observable trace
  after canonicalize, cse and control-flow-sink, against the unoptimized run; the verifier
  runs after each pass. A handful of facts fixtures remain as meta-tests of the reporter.
  effects/long-cycle becomes generated call graphs, checked against a reference
  reachability computed in the test.
- **Transform semantics get the action-skipping differential** (IDRB-19). Each e2e program,
  and every tests/programs program, runs with random subsets of its actions skipped and must
  give the same output and exit. This replaces e2e/loops and the value checks in loops/*.
  identity/identity becomes generated rebuild functions over generated data types: not-called
  holds for total rebuilders, and the calls stay for non-total ones and for swaps.
- **Lowering tests start from first-stage sources at a named step.** The owned IR comes from
  the real idr-rc step, and a failure there is reported once as idr-rc's (IDRB-5, IDRB-6).
  What lowering promises is stated as reads-nothing, calls-only on runtime symbols,
  crash-sites, linker-names, in-llvm and lowered, never internal signatures. One fixture owns
  each layout fact, and run-time live-cell counts are the oracle for counting (IDRB-16).
- **Boundaries are exhausted.** Header limits are tested at n-1, n, n+1 and 2n±1 by a Gen
  generator, run to the end (IDRB-18, IDRB-20).
- **Target lowering is parametrised over every target entry** and runs on every host
  (IDRB-10).
- **e2e/ keeps only what tests/programs cannot express:** crash-callsite, even-group, put-list,
  statuses and exit-42. The rest is deleted (section 2).
