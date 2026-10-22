<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# upstream/

Bugs this repository found in the upstreams it pins (LLVM/MLIR, clang,
lld, Idris 2, and the runtime's simdutf and snmalloc), the patches it carries for them, and what to send
upstream. If you
are an agent pointed at this file with no other instructions, this file
is your task: read it all, then follow **Sending** from the first
directory whose status says "send next".

## Layout

Each `NN-<bug>/` is one bug. `NN` is the order to file in: lower first.

- `README.md`: the local report: symptom, reproducer, cause, what the
  patch does, when it is dropped. Its `## Upstreaming plan` says the
  status. `tests/upstream-patches` requires `## Upstreaming plan`,
  and `## Patch` with a `*.patch` file or `## Why there is no patch`
  without one.
- `submission.md`: the exact texts to post, in LLVM's review language:
  the issue (when one is needed), the pull request title and body, any
  comment, and which file is the diff.
- `llvm.patch`: the change applied to the pinned source, a commit of
  llvm main (`toolchain.lock.json`), so for a bug we send it is the pull
  request itself. `tools/bootstrap.sh` applies every
  `upstream/*/llvm.patch` in the order of their numbers (100 after 99)
  to a copy of the pinned llvm-project when it builds the toolchain;
  `tests/upstream-patches` checks they apply.
- `snmalloc.patch`: the same for the runtime's snmalloc, against
  third_party/snmalloc's gitlink (the lock's revision), which the
  bootstrap's `snmalloc` step applies, in the order of their numbers, to
  its export of the checkout for the runtime's build
  (`.toolchain/snmalloc/src`).
- `simdutf.patch`: the same for the runtime's simdutf, against
  third_party/simdutf's gitlink, which the bootstrap's `simdutf` step
  applies to its export (`.toolchain/simdutf/src`).
- `idris.patch`: the same for Idris 2, against third_party/Idris2's
  gitlink, which the bootstrap's `idris` step would apply to its copy of
  the checkout (the checkout itself stays unmodified). None is carried:
  the stock Idris only builds stage 0 (the fork, the frontend and the test
  runner) and the benchmarks' Chez baseline, and the Idris that elaborates
  programs, prelude and base is the fork in compiler/idris, whose fixes are
  its own code (its README). Nothing goes to Idris (**Idris** under
  **Rules for sending**).
- `pull-request.diff`: for LLVM, the pull request for a change this
  repository does not carry as a patch (08, 17, since the pipeline
  cutover 02, 16 and 22, 25 and 58, and since the P0 cutover 06, 23, 28,
  63 and 78, which nothing in the tree reaches, **When nothing reaches the
  bug** below), which the bootstrap therefore never applies; apply it
  with `git apply`, and take the commit message from `submission.md`,
  never from the file's header. For simdutf (48), the pull request to
  that project, which nothing reaches. For Idris: 96, a fix to the stock
  Idris nothing it builds reaches, recorded and not carried; and (18, 20,
  21, 50, 51, 52, 53, 59 and the eighteen fork-* directories) the change
  the fork carries as its own code (for 21, the smaller change the fork
  has since gone past), laid out against third_party/Idris2 at its
  gitlink, each applying to the pin alone or, for a series (50, 52, 53;
  18, 59), after the records before it, with the test upstream's suite
  would hold: the record a re-sync of the fork reads, never sent.
- `tests/upstream-<bug>/` (bug name without the number): this repository's
  check that the pinned tools still need the patch, or are fixed by it.
- `PINS.md`, entry `## <bug>` (or the name it gives): why we carry it and
  when it goes.

## Status (2026-10-15, the pin then 7208ba24)

The pin moved to llvm main at 416f328b on 2026-10-21; each row below
says where it stands there, and This repository's toolchain lists what
is carried.


All of 01-08 (01 since fixed on main by #208881, 0edf6243) are still broken on llvm main at
7208ba24ca2894729cd394475a00d2a7b605e642. With the seven code diffs of
01-08 applied to that commit (02-07's `llvm.patch` and 08's
`pull-request.diff`), a Release build with assertions
(`-DLLVM_ENABLE_PROJECTS=mlir -DLLVM_TARGETS_TO_BUILD=Native
-DBUILD_SHARED_LIBS=ON -DLLVM_ENABLE_ASSERTIONS=ON`, clang 18, x86_64
Linux) passes `ninja check-mlir`: 4102 passed, 630 unsupported, 1
expectedly failed, 0 failed; each patch's own tests ran and passed, as
did the ExecutionEngine unit test. On the same build, each patch's own tests were then run with that
patch's source change alone reverted: they fail without it (sccp,
vectorize, remove-dead-values and inline fail; the bytecode cycle test
loops; the ExecutionEngine test does not build without the new option)
and pass with it. 01's test, run on main as a file of its own, fails
without a fix and passes with only #208881's change and with 06's. 05
adds no test. Each directory's `## Testing on main` has the details.
Those runs were scratch builds made before Bjorn ruled out building LLVM
locally (2026-10-09): a pull request now rests on LLVM's pre-merge CI
(**CI decides** below).

| NN | bug | what goes out | status |
| -- | --- | ------------- | ------ |
| 01 | remove-dead-values-address-taken | a test-only PR (submission.md): #208881 merged without this case | test-only PR due: #208881 merged 2026-10-12 (0edf6243) without this case |
| 02 | composite-fixed-point-sccp | issue + PR: SCCP keeps existing constants | send next; ready: applies to main at b43c0361; submission.md has the checklist; not carried |
| 03 | bytecode-deferred-quadratic | issue + PR: deferred entries resolved along a path; cycle is an error | carried; ready; overlaps open #229910 |
| 04 | vectorize-precondition-body | issue + PR: precondition checks every body op | carried; ready |
| 05 | forward-dataflow-callee-lookup | PR: solver owns one SymbolTableCollection per run | carried; ready |
| 06 | remove-dead-values-unreachable | issue + PR + comment on #208881: poison for every erased value | not carried since 2026-10-21 (C35); rebase first: #208881 merged; pull-request.diff's function-argument hunk no longer applies to main; still applies to the pin |
| 07 | inline-unreachable-terminator | issue + PR: the hook is asked of the terminator's dialect | carried; ready |
| 08 | execution-engine-process-symbols | PR: process symbols optional, one JITDylib | not carried: the compiler no longer runs a JIT, so nothing here needs it; ready |
| 09 | int-range-narrowing-exactness | issue + PR: remsi and the unsigned ops keep their width when narrowing changes them | carried, the remainders only (the pin has 44a4dbf32, the shift); both still broken on main at 7208ba24; no submission.md text yet |
| 10 | recursive-attribute-parser | an RFC on Discourse first, then a PR: nested builtin arrays and dictionaries parsed, printed and visited for aliases from a stack | carried (2026-10-21); not filed; not ready (RFC first) |
| 16 | remove-dead-values-unchanged-call | issue + PR: `eraseOpResults` keeps an op it erases no result of, as `eraseOperands` does | not carried since the pipeline cutover (nothing reaches it); ready to file; applies to main at b43c0361; submission.md; test checked at the pin only; check-mlir not run |
| 17 | sccp-revert-unset-property | PR: sccp copies the properties storage around a simulated fold, so it reverts a property the fold set on an op that had none | not ready: not carried (the compiler is not affected); no `mlir-opt` with it built; `check-mlir` not run |
| 18 | elaboration-primitive-folding | nothing: Idris takes no tool-written contribution (**Idris**) | carried as fork code (compiler/idris); the diff records it for re-syncs |
| 19 | pass-timing-dynamic-pipeline | a test, as a comment on #169615 (open; its own test passes without its change) | ready, not posted; carried: #169615's change as main's rewritten `PassTiming.cpp` (#232948) spells it, and our test; still broken on main at 416f328b, where #169615 no longer applies |
| 20 | evaluator-char-text | nothing: Idris takes no tool-written contribution (**Idris**) | carried as fork code (compiler/idris); the diff records it for re-syncs |
| 21 | termination-closure | nothing: Idris takes no tool-written contribution (**Idris**) | carried as fork code (compiler/idris), gone past since 31013e5a: the fork closes no graphs and decides each component by its size-change search; the diff records the smaller change for re-syncs |
| 22 | remove-dead-values-poison-operand | issue + PR: the cleanup keeps an operand that is already poison | not carried since the pipeline cutover (nothing reaches it); ready to file; diff rebuilt on main after #208881; submission.md; test never run; check-mlir not run |
| 23 | cse-statistic-assignment | PR: CSE accumulates its pass statistics over nested runs (cse-statistics.mlir) | not carried since 2026-10-21 (no upstream cse, D98, D100); ready, not sent; pull-request.diff applies to main at 7a83be39 |
| 24 | one-shot-module-function-interface | four PRs: One-Shot Module Bufferize on `FunctionOpInterface` with the models as public templates and a function that never returns (a reland of #110322, reverted by #113124); cycles of calls analyzed to a fixpoint over the call graph's strongly connected components; a value that definitely aliases an operand writable on its own, with a call result writable only if its callee returns a writable buffer; the nearest symbol table, not ModuleOp, in empty tensor elimination and getGlobalFor | carried; not filed; check-mlir passes on a private build (2026-10-19), after two fixes (README) |
| 25 | bytecode-unregistered-properties | issue + PR: the reader tests the presence of the `wasRegistered` flag, not its value, so an op written unregistered has its properties attribute read as a properties index; the PR passes the writer's flag into `PropertiesSectionReader::read` and deletes the dead branch (`OpPropertiesTest.BytecodeWrittenUnregistered`) | never carried (nothing reaches it); ready to file; applies to main at b43c0361; submission.md; unit test never run; check-mlir not run |
| 27 | one-shot-tensor-like-copy | issue + PR: an out-of-place operand of a custom tensor-like type gets no copy and its allocation reaches `llvm_unreachable`; `BufferizationOptions::tensorAllocationFn`, whose default fails naming the type | carried since 2026-10-21 (C108, D43); not filed |
| 28 | liveness-non-forwarded-terminator | issue + PR: liveness subscribes a terminator to its parent's results, so one whose operands are all non-forwarded is revisited and remove-dead-values keeps them | not carried since 2026-10-21 (C35); not filed; the upstream test (test dialect) not written; pull-request.diff |
| 29 | dead-code-nested-symbol-use | issue + PR: dead-code analysis resolves a non-call symbol use in the nested table it names, so a function reached only through func.constant in a nested module keeps its callers unknown and remove-dead-values keeps what it returns | carried; not filed; check-mlir not run |
| 30 | aarch64-sibcall-callee-pop | issue + PR: AArch64 makes no sibling call from a function that pops its own stack arguments (tailcc), which returned with them still on the stack, in SelectionDAG and GlobalISel (tailcc-sibcall-callee-pop.ll) | carried; not filed; no submission.md yet; check-llvm not run |
| 48 | simdutf-avx512vpopcntdq-bit | issue + PR to simdutf/simdutf: AVX512VPOPCNTDQ gets an instruction_set bit of its own (0x20000), not AVX512CD's | not carried (the runtime never runs simdutf's detection); not filed; simdutf's AI policy wants a human author who answers for it; pull-request.diff applies to the pin; distinct-bits.cpp fails at the pin and holds with the diff |
| 49 | snmalloc-arm-yield-intrinsic | PR to microsoft/snmalloc: the Arm AAL's pause uses __builtin_arm_yield where the compiler has it, as prefetch uses __builtin_prefetch | carried since 2026-10-21 (snmalloc a patch project, C61); not filed; Microsoft CLA |
| 50 | erased-coverage-nested-match | nothing: Idris takes no tool-written contribution (**Idris**) | carried as fork code (compiler/idris); the diff records it for re-syncs |
| 51 | totality-unimported-callee | nothing (**Idris**) | carried as fork code (compiler/idris); the diff records it for re-syncs |
| 52 | relevant-implicit-split | nothing (**Idris**) | carried as fork code (compiler/idris); series 50 → 52 → 53, the diff applied after 50's |
| 53 | constructor-implicit-mark | nothing (**Idris**) | carried as fork code (compiler/idris); series 50 → 52 → 53, the diff applied after 52's and recording 54 too |
| 54 | erased-constant-pattern | nothing (**Idris**) | carried as fork code (compiler/idris), in 53's diff |
| 55 | lazy-case-scrutinee | nothing (**Idris**) | carried as fork code (compiler/idris); the diff records it for re-syncs |
| 56 | cse-nested-linalg-index | a comment on #62644 and a PR that fixes it: the trait `DependsOnParent` on `linalg.index`, and CSE's key for such an op holds its parent (cse.mlir), perhaps after an RFC for the trait | carried; not filed; check-mlir passes on a private build |
| 57 | linalg-index-int-range | PR: an `InferIntRangeInterface` model for `linalg.index`, [0, extent - 1] (Linalg int-range-interface.mlir) | carried; not filed; check-mlir passes on a private build |
| 58 | delinearize-empty-basis | issue + PR: affine.delinearize_index declares that it has a result, which the generated verifier checks before it reads the first result's type (Affine invalid.mlir) | not carried (nothing in the tree reaches it); not filed; pull-request.diff; check-mlir passes on a private build |
| 59 | literal-partial-fold | nothing (**Idris**) | carried as fork code (compiler/idris), after 18's change to `normalisePrims`; the diff records it for re-syncs |
| 61 | sqrt-negative-fold | PR: `math.sqrt` of a negative constant folds to a quiet NaN, of -0 to -0 | carried; not filed |
| 62 | greedy-multi-region-ancestors | PR: an ancestor with several regions is revisited once the worklist is empty | carried (the greedy driver inside D99's upstream passes); not filed |
| 63 | liveness-trivially-dead | NFC PR: liveness asks once per op whether it is trivially dead | not carried since 2026-10-21 (C35); not filed; applies at 416f328b |
| 64 | tensor-like-per-instance | PR: `isTensorLike`/`isBufferLike` through `extraClassOf`; `to_tensor`/`to_buffer` checked by the interface alone | carried (2026-10-21); not filed |
| 65 | early-exits | nothing of ours: llvm/llvm-project#166688 itself, rebased by hand | carried (D25, D82); #166688 open, no approval |
| 66 | early-exit-propagation-helpers | review comment on #166688: the propagation helpers exported | carried; not posted |
| 67 | early-exit-dead-match | review comment on #166688: an op an exit leaves is not trivially dead | carried; not posted |
| 68 | early-exit-region-inliner | review comment on #166688: the region inliner stops at an exit | carried; not posted |
| 69 | early-exit-successor-inputs | review comment on #166688: successor-input patterns edit only owned inputs | carried; not posted |
| 70 | early-exit-region-graph | review comment on #166688: the region-graph traversal stays inside its op | carried; not posted |
| 71 | early-exit-index-switch | review comment on #166688: scf.index_switch carries exits; scf.if and the switch accept a terminator that never returns | carried; not posted |
| 72 | scc-iterator-node-numbers | PR: scc_iterator keeps visit numbers by node number | carried; not filed |
| 73 | call-graph-dense-ids | RFC, then PR: CallGraph's dense node ids and kept components | carried; not filed |
| 74 | pass-adaptor-preserved-analyses | PR: an adaptor preserves what its nested passes preserve | carried; not filed |
| 75 | thread-pool-stack-size | PR: ThreadPoolStrategy::StackSizeInBytes | carried; not filed |
| 76 | pass-base-derived-class | NFC PR: a pass's CRTP baseClass documented | carried; not filed |
| 77 | dataflow-state-storage | PR: the solver's per-state maps and sets inline when small | carried; not filed; measured in the qualification |
| 78 | func-to-llvm-expanded-arg-attrs | PR: pointer attributes of a memref argument kept on its descriptor's aligned pointer (C163) | not carried since 2026-10-21 (C165: no program function passes through FuncToLLVM); not filed; pull-request.diff |
| 79 | operation-equivalence-symbol-hook | PR: OperationEquivalence compares symbol references through a hook | carried; not filed |
| 80 | walk-iterative | PR after the recursion RFC: every walk from one explicit stack | carried; not filed |
| 81 | attr-type-walker-iterative | PR after the recursion RFC: the attribute and type walker and replacers from an explicit stack | carried; not filed |
| 82 | clone-iterative | PR after the recursion RFC: Region::cloneInto from an explicit stack | carried; not filed |
| 83 | destruction-iterative | PR after the recursion RFC: destruction and dropAllReferences without recursion, and linear | carried; not filed |
| 84 | region-dce-iterative | PR after the recursion RFC: region DCE's liveness and deletion from explicit stacks | carried; not filed |
| 85 | slice-iterative | PR after the recursion RFC: backward and forward slices from explicit stacks | carried; not filed |
| 86 | darwin-stack-clash | PR: the driver passes -fstack-clash-protection for Darwin | carried; not filed |
| 87 | ub-unreachable-effects | PR: ub.unreachable declares NoMemoryEffect | carried; not filed |
| 88 | symbol-table-walk-iterative | PR after the recursion RFC and 80's: the symbol tables walked by the iterative stage walk, the same tables in the same order with the same visibility | carried (2026-10-21); not filed |
| 89 | dataflow-iterative-initialization | PR after the recursion RFC and 80's, 88's and 92's: the sparse and dense analyses initialized by one traversal from an explicit worklist, in the recursions' order | carried (2026-10-21); not filed |
| 90 | operation-equivalence-iterative | PR after the recursion RFC and 79's: OperationEquivalence compares operations and regions from an explicit stack, in the recursion's order, with the same callbacks in the same order | carried (2026-10-21); not filed |
| 91 | buffer-type-iterative | PR after the recursion RFC: bufferization computes buffer types from an explicit stack of the values in progress, an implementation run again once the value it asked for is known | carried (2026-10-21); not filed |
| 92 | dead-code-iterative-initialization | PR after the recursion RFC: dead-code analysis initialized from a worklist | carried; not filed |
| 93 | call-graph-iterative-construction | PR after the recursion RFC: the call graph built from a worklist | carried; not filed |
| 94 | snmalloc-pagemap-sanity-checks | PR to microsoft/snmalloc: a bounded pagemap's fast-path range tests under sanity_checks | carried; not filed; Microsoft CLA |
| 95 | snmalloc-notify-using-result | PR to microsoft/snmalloc: the PALs report a refused commit | carried; not filed; Microsoft CLA |
| 96 | effectful-argument-inline | nothing: Idris takes no tool-written contribution (**Idris**) | recorded, not carried (nothing stock-built reaches it); pull-request.diff against Idris main 89ba32eb |
| 97 | bytecode-numbering-iterative | PR after the recursion RFC: the bytecode writer numbers nested attributes and types from an explicit stack | carried (2026-10-21); not filed |
| 98 | simdutf-constexpr-implementation | PR to simdutf/simdutf: the implementation constructors constexpr, rvv's aside | carried (2026-10-21); not filed; simdutf's AI policy wants a human author who answers for it |
| 99 | function-interface-edits | PR: FunctionOpInterface's four signature edits are interface methods, the present bodies their defaults, so a caller holding the interface reaches an operation's own | carried (2026-10-21); not filed |
| 100 | mlir-opt-main-thread-pool | PR: MlirOptMainConfig::setThreadPool, the pool every context MlirOptMain makes for its input shares | carried (2026-10-22); not filed |
| 101 | thread-pool-thread-start | PR after 75's: ThreadPoolStrategy::OnThreadStart, a function each thread a pool starts runs before any task | carried (2026-10-22); not filed |
| 102 | int-range-ne-either-view | PR: isStaticallyTrue proves `ne` when either the signed or the unsigned ranges are apart (int-range-opts.mlir) | carried (2026-10-22); not filed |
| 103 | sparse-region-successors-protected | PR: the sparse forward analysis's visitRegionSuccessors protected, so an override may call the base | carried (2026-10-22); not filed |
| fork | fork-linear-ambiguous-let | nothing: Idris takes no tool-written contribution (**Idris**) | carried as fork code (compiler/idris); the diff records it for re-syncs |
| fork | fork-totality-depth | nothing (**Idris**) | carried as fork code (compiler/idris); the diff records it for re-syncs |
| fork | fork-interface-body | nothing (**Idris**) | carried as fork code (compiler/idris); the diff records it for re-syncs |
| fork | fork-with-application-scope | nothing (**Idris**) | carried as fork code (compiler/idris); the diff records it for re-syncs |
| fork | fork-build-main | nothing: no bug of Idris's; the frontend's entry point (**Idris**) | carried as fork code (compiler/idris); the diff records it for re-syncs |
| fork | fork-total-frontend-paths | nothing: no bug of Idris's; total code on the frontend's paths (**Idris**) | carried as fork code (compiler/idris); the diff records it for re-syncs |
| fork | fork-ttc-term-locations | nothing: no bug of Idris's; term locations kept in the TTC (**Idris**) | carried as fork code (compiler/idris); the diff records it for re-syncs |
| fork | fork-search-depth | nothing (**Idris**) | carried as fork code (a386fe4d); the diff records it for re-syncs |
| fork | fork-ambiguity-depth | nothing (**Idris**) | carried as fork code (a386fe4d); the diff records it for re-syncs |
| fork | fork-posix-paths | nothing (**Idris**) | carried as fork code (a386fe4d); the diff records it for re-syncs |
| fork | fork-no-runtime-tree | nothing (**Idris**) | carried as fork code (a386fe4d); the diff records it for re-syncs |
| fork | fork-ttc-facts | nothing (**Idris**) | carried as fork code (a386fe4d); the diff records it for re-syncs |
| fork | fork-block-parent | nothing (**Idris**) | carried as fork code (a386fe4d); the diff records it for re-syncs |
| fork | fork-param-pos | nothing (**Idris**) | carried as fork code (a386fe4d); the diff records it for re-syncs |
| fork | fork-erase-args | nothing (**Idris**) | carried as fork code (a386fe4d); the diff records it for re-syncs |
| fork | fork-parser-bounds | nothing (**Idris**) | carried as fork code (a386fe4d); the diff records it for re-syncs |
| fork | fork-dead-options | nothing (**Idris**) | carried as fork code (a386fe4d); the diff records it for re-syncs |
| fork | fork-tuple-node | nothing (**Idris**) | carried as fork code (e5b39cb2); the diff records it for re-syncs |

Gone when the pin moved from llvmorg-23.1.2 to main at 7208ba24, each
with its check and its PINS.md entry: 13 (uplift-final-counter) and 14
(while-move-if-down-duplicates), backports of fixes main has, and 12
(clang-module-predeclared-new), whose report's unit main's clang
compiles where 23.1.2's crashed (observed on arm64 macOS, where the pin
was first built; `make build` on each target is the check); the commit
that fixed it is not identified. Gone with the cutover to MLIR's layout
(2026-10-12), with its check and its PINS.md entry: 11
(clang-module-layout-forward-declaration), since no C++ module is left
in the tree to reproduce it.

The order runs from least to most arguable. 01 is no code of ours and
helps a PR a maintainer approved. 02-04 are each one function in one
file. 05 adds a protected API. 06 overlaps another author's approved PR
and two other open PRs (#208940, #182711; its submission.md says how to
rebase on each). 07 changes which dialect a hook asks. 08 adds an option
and changes how `lookup` searches.

## Rules for sending

These are not optional.

- **Idris.** Nothing written here goes to idris-lang/Idris2: no issue,
  pull request, commit or comment. Its CONTRIBUTING.md ("Things We Will
  Not Accept", at the pin and on main as of 2026-10-13) wants all of
  them written and submitted by humans and will not consider anything
  that arises from generative AI or a coding agent. A bug of Idris's is
  fixed in the fork as its own code (AGENTS.md); its `pull-request.diff`
  is the record of that change against the pin, which a re-sync reads to
  drop it once upstream has fixed the bug its own way. Whether Bjorn
  reports such a bug is his call, in his own words; nothing is drafted
  for it, and no agent posts there.
- **Author.** Bjorn, as an individual, outside any employer: his own
  name and the public email on his GitHub account, no employer anywhere,
  no Co-authored-by, no @mentions.
- **Tool use is labelled.** llvm/docs/AIToolPolicy.md: content with
  substantial tool-generated parts is labelled, and the contributor has
  read and understood every line and can answer for it in review. Every
  commit message, pull request body and comment ends with
  `Assisted-by: Claude Code` as its last line. Bjorn rewrites in his own
  words whatever he would not have written; his wording is used verbatim.
- **A human approves every post.** The same policy bans agents that act
  in LLVM's spaces without human approval. An agent never runs
  `gh issue create`, `gh pr create`, `gh pr comment`, `gh issue comment`,
  a writing `gh api` call, or `git push`, without first showing Bjorn the
  exact command and full text and getting an explicit "yes, post it" for
  that one command. One approval covers one command.
- **Only to Bjorn's fork.** Never push to llvm/llvm-project.
- **No "good first issue".** Never work on an issue with that label.
- **One at a time.** Send one submission, stop, and continue only when
  Bjorn says so, normally after its first review. Adjust the rest by what
  that review asked for.
- **Trunk only.** Every pull request is against llvm main. No backports.
- **CI decides.** LLVM is not built locally for a submission (Bjorn,
  2026-10-09). Before a pull request, its diff applies to current main
  (`git apply --check`) and `git clang-format origin/main` changes nothing;
  `check-mlir` is LLVM's pre-merge CI's, on the pull request. A CI failure
  is read before anything else: one that also fails on main without the
  change is reported in the pull request, not ignored.

## Sending

Run this on Bjorn's machine, in a local Claude Code session with `gh`
logged in as him (`gh auth status`) and git's `user.name`/`user.email`
set to the name and public email for LLVM commits.

Once:
1. Clone this repository (read only) and llvm: `git clone
   --filter=blob:none https://github.com/llvm/llvm-project.git`. If Bjorn
   has no fork, ask before `gh repo fork llvm/llvm-project
   --clone=false`; add the fork as remote `fork`.

For the next submission (first row whose status says "send next", or,
after Bjorn says to go on, the next ready row):
1. Read its `README.md` and `submission.md` in full.
2. `git fetch origin main`; `git switch -c <bug> origin/main`.
3. `git apply` its `llvm.patch` (08: `pull-request.diff`). If it does
   not apply, stop and show the conflict; do not resolve it alone.
4. Commit: subject = PR title, body = PR body, last line
   `Assisted-by: Claude Code`. Leave `#<issue>` (or `#ISSUE`, `#PR`) in
   place until the number exists.
5. `git clang-format origin/main` must change nothing. No local
   `check-mlir`: the pull request's pre-merge CI runs it (**CI decides**).
6. Show Bjorn each text exactly as it will be posted (issue, PR, comment)
   and each command. Take his edits verbatim.
7. On his approval of each command: file the issue; put its number into
   the commit (`git commit --amend`); push the branch to `fork`; open the
   PR against `llvm/llvm-project:main`. Post comments the same way.
8. Stop. Give Bjorn the URLs.
9. Update this repository: the row's status here (the issue and PR
   numbers), the directory's `README.md` `## Upstreaming plan`, and its
   PINS.md entry. Commit that.

Reviews: summarize what the reviewer asks, propose a change and a reply,
and wait. Push follow-ups to the same branch only after Bjorn approves
the diff and the reply. When the change on main differs from the pin's
`llvm.patch` in substance, update `llvm.patch` to match what landed.

## After a pull request lands

The patch stays until the pin moves past the merged commit. When it
does: delete `NN-<bug>/llvm.patch` (or the directory, with its
`tests/upstream-<bug>/` check and PINS.md entry, if nothing else is
left), and rebuild the toolchain (`tools/bootstrap.sh llvm`).

## When nothing reaches the bug

A patch also goes when nothing in the tree reaches its bug any more
(AGENTS.md), as 02, 16 and 22 went when the pipeline cutover deleted the
simplify rounds, the one loop of ours that met them. The report stays, as
a submission:
- `llvm.patch` becomes `pull-request.diff` (`mv`, the same bytes), so the
  bootstrap no longer applies it and the pull request is still the diff
  to send;
- the README's `## Patch` becomes `## The fix`, and a `## Why there is no
  patch` says what reached the bug and why nothing does now;
- the `PINS.md` entry goes, since nothing of ours stands in for the
  patch;
- `tests/upstream-<bug>/` stays, turned to check that the pinned tools
  still have the bug, as 17's does: when the pin has the fix it fails,
  and the directory and the check go;
- the toolchain is rebuilt without the patch (`tools/bootstrap.sh llvm`).

## Adding a bug

A new bug gets a directory numbered by when it should be filed; renumber
with `git mv` and update every `upstream/NN-<bug>` path (`git grep`)
when the order changes. Reduce it to upstream dialects and tools first;
if it does not reproduce there, it is ours, not upstream's. Add the
report, reproducer, patch, `tests/upstream-<bug>/` check and PINS.md
entry in one change, and a `submission.md` once it is ready to send.

## This repository's toolchain

The LLVM pin is llvm main at 416f328b939fe1373ddc9060f6773ad4c5039f59
(LLVM 24.0.0git, llvmorg-24-init-15655, `toolchain.lock.json`), moved
from 7208ba24 on 2026-10-21, so that the patch we carry for a bug we send
is its pull request (PINS.md); every dependency moves to its latest about
weekly. One recipe builds the toolchain on all four targets:
`tools/bootstrap.sh llvm` (stage 1, the target's C library, the runtimes
and stage 2, into `.toolchain/llvm`, with LLVM's and MLIR's assertions
on in every stage) applies every
`upstream/*/llvm.patch` in the order of their numbers to the one tree
stage 1, the runtimes and stage 2 build from, and their stamps record each by
SHA-256; `tools/bootstrap.sh snmalloc` and `tools/bootstrap.sh simdutf`
do the same for `upstream/*/snmalloc.patch` and `upstream/*/simdutf.patch`
on exports of third_party/snmalloc and third_party/simdutf. Carried
for LLVM: 03, 04, 05, 07, 09, 10, 19, 24, 27, 29, 30, 56, 57, 61, 62,
64 to 77, 79 to 93, 97 and 99, every one applying at 416f328b in that
order (`git apply`, the series in order, on the pinned files they touch,
2026-10-21); for snmalloc: 49, 94 and 95; for simdutf: 98, applying at
its gitlink (8d82299, 9.3.2); for Idris and Chez: none. No toolchain is built yet with them, on any
target, and `make build` refuses until one is. That is this repository's
build, not a precondition for sending anything upstream.
