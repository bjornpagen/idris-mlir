<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Submission

Status: send next (upstream/README.md). Ready to file, not filed. One
issue, then one pull request, on llvm/llvm-project. GitHub issues and
pull requests, not Bugzilla.

The author is Bjorn, as an individual, outside any employer: his name and
the public email of his GitHub account, no employer, no `Co-authored-by`,
no `@` mentions. The last line of the commit message, of the pull request
body and of the issue body is `Assisted-by: Claude Code`
(llvm/docs/AIToolPolicy.md).

The pull request is `pull-request.diff` in this directory, as that one
commit. It applies with no offset to llvm main at b43c0361 (2026-10-15)
and to the pin, 7208ba24: `SCCP.cpp`, `sccp.mlir`, `FoldUtils.cpp` and
`CompositePass.cpp` are unchanged between the two. Apply it with
`git apply` and take the message from here, never from the diff's header.

Open the issue, then the pull request. The squash commit message is the
pull request title, a blank line, and the pull request body. When the
issue number exists, replace `#<issue>` in the body.

## Checklist before posting

- [ ] Search llvm/llvm-project issues and pull requests again for sccp
  with constants, `insertKnownConstant` and composite-fixed-point-pass.
  On 2026-10-15 nothing covered it (the nearest: #213933, which reverts
  in-place folds during the analysis, and #218394, merged, which made the
  composite pass's convergence failure configurable).
- [ ] `git fetch origin main`, `git switch -c composite-fixed-point-sccp origin/main`,
  `git apply --check` then `git apply` the diff. If it does not apply,
  stop and show the conflict.
- [ ] Commit with the title and body below.
- [ ] `git clang-format origin/main` changes nothing (the patched
  `SCCP.cpp` was clang-format clean when the diff was made; not rerun).
- [ ] What was observed: on main at 7208ba24, with 01-08's code diffs
  applied together, `check-mlir` passed, and `sccp.mlir`'s new RUN line
  failed with this change alone reverted (README, Testing on main). Not
  rerun at b43c0361, where none of the files changed.
- [ ] Show Bjorn the issue, the pull request and each command; one "yes,
  post it" per command. File the issue, put its number in the body, push
  to his fork, open the pull request against `main`.
- [ ] Read the pre-merge CI (`check-mlir`) before anything else. A failure
  that also happens on main without the change is reported in the pull
  request.
- [ ] Afterwards: the issue and pull request numbers into
  upstream/README.md's row and this directory's README
  `## Upstreaming plan`.

## Issue title

[mlir][SCCP] sccp remakes every constant on every run

## Issue body

A run of sccp that propagates nothing still changes the IR: it replaces
each constant with an equal one it materializes, at an unknown location.
The module prints the same, but composite-fixed-point-pass, which
compares OperationFingerPrints, never sees a pipeline containing sccp
converge, and -mlir-print-ir-after-change prints after every sccp. A
constant that is not trivially dead is kept beside its copy, so the IR
grows with each run.

```mlir
func.func @one() -> i32 {
  %c = arith.constant 1 : i32
  return %c : i32
}
```

```
$ mlir-opt one.mlir --composite-fixed-point-pass='pipeline=sccp max-iterations=5'
one.mlir:0:0: warning: Composite pass "CompositeFixedPointPass"+ didn't converge in 5 iterations
one.mlir:0:0: note: see current operation:
module {
  func.func @one() -> i32 {
    %c1_i32 = arith.constant 1 : i32
    return %c1_i32 : i32
  }
}
```

Expected: no warning, as with pipeline=canonicalize or pipeline=cse on
the same input. With -mlir-print-debuginfo, the constant after --sccp is
at loc(unknown).

The growing case:

```mlir
func.func @two() {
  %0 = "emitc.constant"() <{value = 1 : ui32}> : () -> ui32
  emitc.switch %0 : ui32
  case 2 {
    emitc.yield
  }
  default {
    emitc.yield
  }
  return
}
```

`mlir-opt two.mlir --sccp --sccp --sccp` leaves four emitc.constant ops;
expected one.

rewrite() in mlir/lib/Transforms/SCCP.cpp replaces every value whose
lattice is a constant with OperationFolder::getOrCreateConstant's
constant for it. A constant op's own result has such a lattice, and the
folder, created fresh for each run, is never told about the constants
already in the IR (the greedy driver seeds its folder with
insertKnownConstant), so it makes a new one.

Seen at llvmorg-23.1.2; rewrite(), OperationFolder and
CompositeFixedPointPass's fingerprint check are the same on main at
b43c0361.

Assisted-by: Claude Code

## Pull request title

[mlir][SCCP] Keep the constants the IR already holds

## Pull request body

sccp's rewrite() replaces every value whose lattice is a constant with
the OperationFolder's constant for that value. A constant op's own
result has such a lattice, and the folder, created fresh for each run,
does not know the constants already in the IR. So every run
materializes an equal constant at an unknown location, moves the uses
to it and erases the original; a constant that is not trivially dead,
such as emitc.constant, is kept and gains a duplicate. A run that
propagates nothing still changes the IR: composite-fixed-point-pass,
which compares OperationFingerPrints, never sees sccp converge, and
-mlir-print-ir-after-change prints after every sccp.

rewrite() now hands each constant op it reaches to the folder with
insertKnownConstant, as the greedy driver does, and leaves it there.
The folder returns it for its value from then on, so the output of sccp
is a fixed point of sccp. Constants are handed over as the walk reaches
them rather than up front, so a constant nested in an op that sccp
erases goes with that op instead of being hoisted out of it. The
constant op itself is skipped rather than looked up, because a lookup
through getOrCreateConstant overwrites the location of the constant it
returns.

One visible change beyond the fix: insertKnownConstant hoists and
uniques what it is given, as in canonicalize, so a constant in a block
the analysis found dead is now moved to the entry block and merged with
equal constants, where before it was left in place. Live constants
ended up in the entry block before as well, as the folder's copies.

The new RUN line in sccp.mlir runs every case under
composite-fixed-point-pass{pipeline=sccp max-iterations=2} with
-verify-diagnostics, so the test fails on the non-convergence warning
unless a second run of sccp leaves the IR untouched, and checks the
output against the same CHECK lines as a single run. Without this
change it warns on most of the functions in the file.

Fixes #<issue>.

Assisted-by: Claude Code

## Patch file

`pull-request.diff`
