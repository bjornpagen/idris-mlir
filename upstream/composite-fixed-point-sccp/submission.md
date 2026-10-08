# Submission

Paste into GitHub, repository `llvm/llvm-project`. Not Bugzilla.

One commit. The author is Bjorn, as an individual, outside any employer.
No employer in the author name, the email, or the message. No
`Co-authored-by`. No `@` mentions. Add `Assisted-by: <tool>` as the last line of the pull request body
(llvm/docs/AIToolPolicy.md).

The pull request is `llvm.patch` in this directory, as that one commit. It
applies unchanged to llvm main at 7208ba24 and to llvmorg-23.1.2, so there
is no separate trunk diff.

Open the issue, then the pull request. The squash commit message is the
pull request title, a blank line, and the pull request body. When the
issue number exists, replace `#<issue>` in the last line of the pull
request body (and of the commit message in `llvm.patch`) with it.

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
7208ba24.

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

## Patch file

`llvm.patch`
