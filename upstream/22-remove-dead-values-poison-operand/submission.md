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

The diff is `pull-request.diff`, one commit, a `git diff` against llvm
main at b43c0361 (2026-10-15), after #208881. It applies there with no
offset, and to the pin, 7208ba24. The squash commit message is the pull
request title, a blank line, and the pull request body. Apply the diff
with `git apply` and take the message from here. When the issue number
exists, replace `#<issue>` in the body.

## Checklist before posting

- [ ] Search llvm/llvm-project issues and pull requests again for
  remove-dead-values with poison, fixed points or
  composite-fixed-point-pass. On 2026-10-15 nothing covered it; the open
  remove-dead-values pull requests (#216652, #182711, #208742, #208940)
  change other steps. If one of them has landed, rebase and recheck the
  diff.
- [ ] `git fetch origin main`, `git switch -c remove-dead-values-poison-operand origin/main`,
  `git apply --check` then `git apply` the diff. If it does not apply,
  stop and show the conflict.
- [ ] Commit with the title and body below.
- [ ] `git clang-format origin/main` changes nothing. Not run here (no
  clang-format on the machine that prepared this); the C++ lines are
  within 80 columns.
- [ ] Bjorn decides whether to see the new test pass with the change and
  fail without it before posting. Neither was observed: no `mlir-opt`
  with the change was built (upstream/README.md, **CI decides**).
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
[mlir] remove-dead-values replaces a ub.poison operand with a new ub.poison
```

## Issue body

````
--remove-dead-values replaces each dead forwarded operand of a region
branch op, or of its terminators, with a new ub.poison, also when the
operand already is one. The module prints the same, but the poison is a
new operation, so composite-fixed-point-pass over the pass never
converges on such a module. Nor does it over the pass followed by cse,
which merges the new poison values back: the printed module is the same
after every run, the operations are not.

```mlir
func.func @f(%lb: index, %ub: index, %step: index, %m: memref<i64>) {
  %p = ub.poison : i64
  %r = scf.for %i = %lb to %ub step %step iter_args(%a = %p) -> (i64) {
    %c = arith.constant 1 : i64
    memref.store %c, %m[] : memref<i64>
    scf.yield %p : i64
  }
  return
}
```

```
$ mlir-opt poison-operand.mlir --composite-fixed-point-pass='pipeline=remove-dead-values{canonicalize=false} max-iterations=1 on-convergence-failure=error'
poison-operand.mlir:1:1: error: Composite pass "CompositeFixedPointPass"+ didn't converge in 1 iterations
```

Expected: the run leaves the function as it is, and the composite pass
stops after it. (With canonicalize=true the loop loses its dead
iteration value, which is a real change.)

Two steps of cleanUpDeadVals each put a new ub.poison where one already
is. processRegionBranchOp marks an operand dead when every successor
input it is forwarded to is dead, whatever value it is, and the first
step replaces it with a new ub.poison. And %p itself is dead, so it is
listed for erasure, and the operation step replaces its remaining uses
with another new ub.poison before erasing it.

Seen at 7208ba24; both steps are the same on main at b43c0361.

Assisted-by: Claude Code
````

## Pull request title

```
[mlir][RemoveDeadValues] Keep operands that are already ub.poison
```

## Pull request body

```
remove-dead-values replaces each dead forwarded operand of a region
branch op, or of its terminators, with a new ub.poison, also when the
operand already is one. The ub.poison it replaced is then dead too, so
the operation cleanup erases it, first replacing its remaining uses with
yet another new ub.poison. A run with nothing to remove still changes
the IR: composite-fixed-point-pass over the pass never converges on such
a module, nor over the pass followed by cse, which merges the new poison
values back so that the module prints the same after every run.

The operand cleanup now leaves an operand defined by ub.poison as it is.
The operation cleanup defers a ub.poison that operands still use, and
erases it after the poison cleanup only if those uses are gone by then.
Every use left on it is in a position the liveness analysis found dead:
the pass lists an op for erasure only when none of its results is live.

The new remove-dead-values-poison-operand.mlir runs the pass under
composite-fixed-point-pass{max-iterations=2} with -verify-diagnostics on
a loop whose dead iteration value is already poison, so it fails on the
non-convergence warning unless the pass leaves the loop as it is.

Fixes #<issue>.

Assisted-by: Claude Code
```

## Patch file

`pull-request.diff`
