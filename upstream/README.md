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
  `upstream/*/llvm.patch` in name order to a copy of the pinned
  llvm-project when it builds the toolchain; `tests/upstream-patches`
  checks they apply.
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
  cutover 02, 16 and 22, and 25, 27 and 58, which nothing in the tree
  reaches, **When nothing reaches the bug** below), which the
  bootstrap therefore never applies; apply it with `git apply`, and take the commit
  message from `submission.md`, never from the file's header. For simdutf
  and snmalloc (48, 49), the pull request to that project, which no patch
  project applies. For Idris (18, 20, 21, 50, 51, 52, 53, 59 and the seven fork-* directories),
  the change the fork carries as its own code, laid out
  against third_party/Idris2's pin with the test upstream's suite would
  hold: the record a re-sync of the fork reads, never sent.
- `tests/upstream-<bug>/` (bug name without the number): this repository's
  check that the pinned tools still need the patch, or are fixed by it.
- `PINS.md`, entry `## <bug>` (or the name it gives): why we carry it and
  when it goes.

## Status (2026-10-15)

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
| 03 | bytecode-deferred-quadratic | issue + PR: deferred entries resolved along a path; cycle is an error | ready; overlaps open #229910 |
| 04 | vectorize-precondition-body | issue + PR: precondition checks every body op | ready |
| 05 | forward-dataflow-callee-lookup | PR: solver owns one SymbolTableCollection per run | ready |
| 06 | remove-dead-values-unreachable | issue + PR + comment on #208881: poison for every erased value | rebase first: #208881 merged; llvm.patch's function-argument hunk no longer applies to main; still applies to the pin |
| 07 | inline-unreachable-terminator | issue + PR: the hook is asked of the terminator's dialect | ready |
| 08 | execution-engine-process-symbols | PR: process symbols optional, one JITDylib | ready; the compiler no longer runs a JIT, so nothing here needs it |
| 09 | int-range-narrowing-exactness | issue + PR: remsi and the unsigned ops keep their width when narrowing changes them | carried, the remainders only (the pin has 44a4dbf32, the shift); both still broken on main at 7208ba24; no submission.md text yet |
| 10 | recursive-attribute-parser | an RFC on Discourse first | not ready; no patch; still reproduces at 7208ba24 (arm64 macOS) |
| 16 | remove-dead-values-unchanged-call | issue + PR: `eraseOpResults` keeps an op it erases no result of, as `eraseOperands` does | ready to file; applies to main at b43c0361; submission.md; test checked at the pin only; check-mlir not run |
| 17 | sccp-revert-unset-property | PR: sccp copies the properties storage around a simulated fold, so it reverts a property the fold set on an op that had none | not ready: not carried (the compiler is not affected); no `mlir-opt` with it built; `check-mlir` not run |
| 18 | elaboration-primitive-folding | nothing: Idris takes no tool-written contribution (**Idris**) | carried as fork code (compiler/idris); the diff records it for re-syncs |
| 19 | pass-timing-dynamic-pipeline | a test, as a comment on #169615 (open; its own test passes without its change) | ready, not posted; carried: #169615's change and our test; still broken on main at 626eeb8e; the toolchain is not yet rebuilt with it |
| 20 | evaluator-char-text | nothing: Idris takes no tool-written contribution (**Idris**) | carried as fork code (compiler/idris); the diff records it for re-syncs |
| 21 | termination-closure | nothing: Idris takes no tool-written contribution (**Idris**) | carried as fork code (compiler/idris); the diff records it for re-syncs |
| 22 | remove-dead-values-poison-operand | issue + PR: the cleanup keeps an operand that is already poison | ready to file; diff rebuilt on main after #208881; submission.md; test never run; check-mlir not run |
| 23 | cse-statistic-assignment | PR: CSE accumulates its pass statistics over nested runs (cse-statistics.mlir) | ready, not sent; carried; applies to main at 7a83be39 |
| 24 | one-shot-module-function-interface | four PRs: One-Shot Module Bufferize on `FunctionOpInterface` with the models as public templates and a function that never returns (a reland of #110322, reverted by #113124); cycles of calls analyzed to a fixpoint over the call graph's strongly connected components; a value that definitely aliases an operand writable on its own, with a call result writable only if its callee returns a writable buffer; the nearest symbol table, not ModuleOp, in empty tensor elimination and getGlobalFor | carried; not filed; check-mlir passes on a private build (2026-10-19), after two fixes (README) |
| 25 | bytecode-unregistered-properties | issue + PR: the reader tests the presence of the `wasRegistered` flag, not its value, so an op written unregistered has its properties attribute read as a properties index; the PR passes the writer's flag into `PropertiesSectionReader::read` and deletes the dead branch (`OpPropertiesTest.BytecodeWrittenUnregistered`) | ready to file; applies to main at b43c0361; submission.md; unit test never run; check-mlir not run |
| 27 | one-shot-tensor-like-copy | issue + PR: an out-of-place operand of a custom tensor-like type gets no copy and its allocation reaches `llvm_unreachable`; `BufferizationOptions::tensorAllocationFn`, whose default fails naming the type | not carried (nothing in the tree reaches it); not filed; pull-request.diff |
| 28 | liveness-non-forwarded-terminator | issue + PR: liveness subscribes a terminator to its parent's results, so one whose operands are all non-forwarded is revisited and remove-dead-values keeps them | carried; not filed; the upstream test (test dialect) not written; check-mlir not run |
| 29 | dead-code-nested-symbol-use | issue + PR: dead-code analysis resolves a non-call symbol use in the nested table it names, so a function reached only through func.constant in a nested module keeps its callers unknown and remove-dead-values keeps what it returns | carried; not filed; check-mlir not run |
| 30 | aarch64-sibcall-callee-pop | issue + PR: AArch64 makes no sibling call from a function that pops its own stack arguments (tailcc), which returned with them still on the stack, in SelectionDAG and GlobalISel (tailcc-sibcall-callee-pop.ll) | carried; not filed; no submission.md yet; check-llvm not run |
| 48 | simdutf-avx512vpopcntdq-bit | issue + PR to simdutf/simdutf: AVX512VPOPCNTDQ gets an instruction_set bit of its own (0x20000), not AVX512CD's | not carried (the runtime never runs simdutf's detection); not filed; simdutf's AI policy wants a human author who answers for it; pull-request.diff applies to the pin; distinct-bits.cpp fails at the pin and holds with the diff |
| 49 | snmalloc-arm-yield-intrinsic | PR to microsoft/snmalloc: the Arm AAL's pause uses __builtin_arm_yield where the compiler has it, as prefetch uses __builtin_prefetch | not carried (snmalloc is no patch project; PINS.md snmalloc-arm-yield-asm); not filed; Microsoft CLA; pull-request.diff applies to the pin |
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
| 60 | print-local-aliases | PR: a nested operation's print may write its aliases first (`-mlir-print-local-aliases`), so a dump writes each type once | carried; not filed |
| 61 | sqrt-negative-fold | PR: `math.sqrt` of a negative constant folds to a quiet NaN, of -0 to -0 | carried; not filed |
| fork | fork-linear-ambiguous-let | nothing: Idris takes no tool-written contribution (**Idris**) | carried as fork code (compiler/idris); the diff records it for re-syncs |
| fork | fork-totality-depth | nothing (**Idris**) | carried as fork code (compiler/idris); the diff records it for re-syncs |
| fork | fork-interface-body | nothing (**Idris**) | carried as fork code (compiler/idris); the diff records it for re-syncs |
| fork | fork-with-application-scope | nothing (**Idris**) | carried as fork code (compiler/idris); the diff records it for re-syncs |
| fork | fork-build-main | nothing: no bug of Idris's; the frontend's entry point (**Idris**) | carried as fork code (compiler/idris); the diff records it for re-syncs |
| fork | fork-total-frontend-paths | nothing: no bug of Idris's; total code on the frontend's paths (**Idris**) | carried as fork code (compiler/idris); the diff records it for re-syncs |
| fork | fork-ttc-term-locations | nothing: no bug of Idris's; term locations kept in the TTC (**Idris**) | carried as fork code (compiler/idris); the diff records it for re-syncs |

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

The LLVM pin is llvm main at 7208ba24ca2894729cd394475a00d2a7b605e642
(LLVM 24.0.0git, `toolchain.lock.json`), moved from `llvmorg-23.1.2` so
that the patch we carry for a bug we send is its pull request (PINS.md). One recipe builds the toolchain
on both targets: `tools/bootstrap.sh llvm` (stage 1, the target's C
library, the runtimes and stage 2, into `.toolchain/llvm`) applies every
`upstream/*/llvm.patch` in name order, and stage 2's stamp records each by
SHA-256. The pin was first built on arm64 macOS, with 02-07 and 09 among its
patches, by the bootstrap's earlier one-stage Darwin recipe. No toolchain is built
yet with the patches the tree carries now (03-07, 09, 19, 23 and 24 for
LLVM; none for Idris), on either target, and `make build` refuses until one
is. That is this repository's build, not a precondition for sending
anything upstream.
