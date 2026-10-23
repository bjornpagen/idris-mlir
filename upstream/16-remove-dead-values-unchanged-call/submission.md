<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Submission

Status: ready to file, not filed. One issue, then one pull request, on
llvm/llvm-project. GitHub issues and pull requests, not Bugzilla.

The author is Bjorn, as an individual, outside any employer: their name and
the public email of their GitHub account, no employer, no `Co-authored-by`,
no `@` mentions. The last line of the commit message, of the pull request
body and of the issue body is `Assisted-by: Claude Code`
(llvm/docs/AIToolPolicy.md).

The diff is `pull-request.diff`, one commit. It applies with no offset to
llvm main at b43c0361 (2026-10-15) and to the pin, 7208ba24. The squash
commit message is the pull request title, a blank line, and the pull
request body. Apply the diff with `git apply` and take the message from
here. When the issue number exists, replace `#<issue>` in the body.

## Checklist before posting

- [ ] Search llvm/llvm-project issues and pull requests again for
  `eraseOpResults` and for remove-dead-values with
  composite-fixed-point-pass or fixed points. On 2026-10-15 nothing
  covered it (#174152 added `eraseOpResults`; #187992, open, adds other
  rewriter helpers and does not touch it).
- [ ] `git fetch origin main`, `git switch -c remove-dead-values-unchanged-call origin/main`,
  `git apply --check` then `git apply` the diff. If it does not apply,
  stop and show the conflict.
- [ ] Commit with the title and body below.
- [ ] `git clang-format origin/main` changes nothing (the changed C++
  lines were clang-format clean under trunk's `.clang-format` at the pin;
  not run on main).
- [ ] What was observed, at the pin only, with a scratch `mlir-opt` linked
  against the toolchain's libraries: both RUN lines of the new test pass
  with the change and fail without it (README, Testing at the pin). Not
  run on main, where neither file changed.
- [ ] Show Bjorn the issue, the pull request and each command; one "yes,
  post it" per command. File the issue, put its number in the body, push
  to their fork, open the pull request against `main`.
- [ ] Read the pre-merge CI (`check-mlir`) before anything else. A failure
  that also happens on main without the change is reported in the pull
  request.
- [ ] Afterwards: the issue and pull request numbers into
  upstream/README.md's row and this directory's README
  `## Upstreaming plan`.

## Issue title

```
[mlir] remove-dead-values replaces a call it erases nothing from
```

## Issue body

````
--remove-dead-values replaces every call of a private function that
returns a value with a new, identical call, even when it erases no
result from it. The module prints the same, but the call is a new
operation, so composite-fixed-point-pass over the pass never converges on
a module the pass leaves as it is, and -mlir-print-ir-after-change prints
after it.

```mlir
func.func private @inc(%x: i64) -> i64 {
  %c1 = arith.constant 1 : i64
  %y = arith.addi %x, %c1 : i64
  return %y : i64
}

func.func @main(%x: i64) -> i64 {
  %y = func.call @inc(%x) : (i64) -> i64
  return %y : i64
}
```

```
$ mlir-opt unchanged-call.mlir --composite-fixed-point-pass='pipeline=remove-dead-values max-iterations=1 on-convergence-failure=error'
unchanged-call.mlir:0:0: error: Composite pass "CompositeFixedPointPass"+ didn't converge in 1 iterations
```

The same with remove-dead-values{canonicalize=false}. mlir-opt
--remove-dead-values prints the input unchanged. With @inc public, or a
call without results, the composite pass converges after one run.

processFuncOp lists every call of such a function with the results to
erase from it, which may be none. The cleanup erases them with
RewriterBase::eraseOpResults, which has no case for an empty set: it
creates an identical operation and replaces the original with it.
RewriterBase::eraseOperands returns early on an empty set.

Seen at 7208ba24; PatternMatch.cpp and the pass's call handling are the
same on main at b43c0361.

Assisted-by: Claude Code
````

## Pull request title

```
[mlir] Keep the op in RewriterBase::eraseOpResults when nothing is erased
```

## Pull request body

```
RewriterBase::eraseOpResults has no case for an empty set of results:
it creates an operation with the same name, operands, result types,
attributes and properties, moves the regions into it, and replaces the
original with it. RewriterBase::eraseOperands returns early on an empty
set, and the two other callers of eraseOpResults in the tree check for
one before they call it.

remove-dead-values calls it for every call of a private function whose
users are all calls, with the results it found dead at that call, which
may be none. Such a call is then replaced by an identical new one. The
module prints the same, but composite-fixed-point-pass, which compares
OperationFingerPrints, never sees the pass converge on a module it
leaves as it is, and -mlir-print-ir-after-change prints after it.

eraseOpResults now returns the operation unchanged when `eraseIndices`
selects no result, and its comment says so.

The new remove-dead-values-fixed-point.mlir runs the pass under
composite-fixed-point-pass{max-iterations=2} with -verify-diagnostics,
with the pass's canonicalization and without, on a call none of whose
results is dead and on a call whose dead result the first run erases.
It fails on the non-convergence warning unless a second run of the pass
leaves the IR untouched; without this change both RUN lines warn.

Fixes #<issue>.

Assisted-by: Claude Code
```

## Patch file

`pull-request.diff`
