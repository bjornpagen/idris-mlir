# Sending order

The eight LLVM submissions, smallest and least arguable first. Send one,
wait for its first review, and adjust the rest by what that review asks
for before sending the next. Each directory's `submission.md` has the
exact texts; each says which file is the diff (`llvm.patch` when one file
applies to both main and the pin, `pull-request.diff` when main needed its
own).

Before any of them: every pull request and comment ends with
`Assisted-by: <tool>` (llvm/docs/AIToolPolicy.md: substantial
tool-generated content is labelled, and the contributor reads, understands
and can defend every line). Rewrite any sentence you would not have
written yourself. None of these fixes a "good first issue".

Status on 2026-10-08: all eight bugs are still on llvm main at 7208ba24.
The trunk `check-mlir` run with the patches applied is in progress; do not
open a pull request before it is green.

| # | directory | what goes out | why this position |
| - | --------- | ------------- | ----------------- |
| 1 | remove-dead-values-address-taken | a test, as a comment on the approved #208881 | no code of ours; helps a pull request a maintainer already approved |
| 2 | composite-fixed-point-sccp | issue + PR, a few lines in SCCP.cpp | one file, the greedy driver already does the same, a RUN line tests it |
| 3 | bytecode-deferred-quadratic | issue + PR, BytecodeReader.cpp | one function, measured numbers, a hang turned into an error; overlaps the open #229910 |
| 4 | vectorize-precondition-body | issue + PR, Vectorization.cpp | one predicate shared by two places, but linalg vectorization is a busy area with opinionated owners |
| 5 | forward-dataflow-callee-lookup | PR only | adds a protected API to DataFlowAnalysis and drops a member; no new test, the existing ones cover it |
| 6 | remove-dead-values-unreachable | issue + PR, then a comment on #208881 | overlaps another author's approved #208881 and two other open PRs; send after #208881 lands or after its author answers the comment from step 1 |
| 7 | inline-unreachable-terminator | issue + PR | changes whose dialect a hook asks, a contract change reviewers will discuss |
| 8 | execution-engine-process-symbols | PR only | adds an option to ExecutionEngineOptions and changes how lookup searches; design, not a bug fix alone |

Fill in `#<issue>` (or `#ISSUE`, `#PR`) once the issue or pull request
exists.
