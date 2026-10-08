# Submission

Paste into GitHub, repository `llvm/llvm-project`. Not Bugzilla.

One commit. The author is Bjorn, as an individual, outside any employer.
No employer in the author name, the email, or the message. No
`Assisted-by`. No `Co-authored-by`. No `@` mentions.

The patch file is `llvm.patch` in this directory. Apply it as that one
commit. It is part 1 only; part 2 stays a proposal in the issue.

Open the issue, then the pull request. The squash commit message is the
pull request title, a blank line, and the pull request body. When the
issue number exists, replace `#<new>` in the last line of the pull request
body (and of the commit message in `llvm.patch`) with it.

## Issue title

[mlir] sccp changes the IR on every run; composite-fixed-point-pass never converges

## Issue body

At `llvmorg-23.1.2`, a run of `sccp` that propagates nothing still changes
the IR: it replaces every constant by an equal one it makes. The module
prints the same, but each constant is a new operation without its
location, and a constant that is not trivially dead is kept, so each run
adds a duplicate. `composite-fixed-point-pass`, which decides convergence
by `OperationFingerPrint` (a hash of object identity), never sees a
pipeline with `sccp` in it converge.

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

`pipeline=canonicalize` and `pipeline=cse` converge after one run on the
same module. With `-mlir-print-debuginfo`, the constant after `--sccp` is
at `loc(unknown)`, and `--sccp --mlir-print-ir-after-all
--mlir-print-ir-after-change` prints after `sccp`. With an `emitc.constant`
used by an `emitc.switch` in place of the `arith.constant`, `--sccp --sccp
--sccp` leaves four `emitc.constant` operations.

Cause: `rewrite` in `mlir/lib/Transforms/SCCP.cpp` replaces every value
whose lattice is a constant with `OperationFolder::getOrCreateConstant`'s
constant for it, and erases the operation if it is trivially dead. A
constant operation's own result has such a lattice. The folder is made
fresh for each run and is never told about the constants the IR already
holds (the greedy driver tells its folder with `insertKnownConstant`
before it rewrites), so it materializes a new constant with an erased
location; the original is erased, or kept when it is not trivially dead
(`emitc.constant` does not declare itself free of memory effects).

Proposed fix, in two parts:

1. `sccp`: give each constant the walk reaches to the folder
   (`insertKnownConstant`) and leave it, so the folder hands it out for its
   value and a run that propagates nothing changes nothing. This is a bug
   in `sccp` on its own, since the `emitc.constant` case grows the IR.
2. `composite-fixed-point-pass`: decide the fixpoint on the IR rather than
   on identity, so a pass that remakes an operation in place still
   converges. A fingerprint that hashes each operation as
   `OperationEquivalence::computeHash` does (name, attributes, properties,
   result types, location), with each operand hashed as the position of
   its defining value in a pre-order numbering of the block arguments and
   results. `OperationFingerPrint` would keep its use as an identity check
   in the greedy driver's and the dialect conversion's expensive checks.
   This changes what a public utility promises, so it is a proposal for
   discussion here.

## Pull request title

[mlir][SCCP] Keep the constants the IR already holds

## Pull request body

sccp's rewrite replaces every value whose lattice is a constant with
the OperationFolder's constant for it. A constant operation's own
result has such a lattice, and the folder, made fresh for each run,
does not know the constants the IR already holds, so every run
materializes an equal constant without a location, moves the uses to
it and erases the original. A constant that is not trivially dead,
such as emitc.constant, is kept, and each run adds a duplicate. A run
that propagates nothing still changes the IR, so
composite-fixed-point-pass, which compares OperationFingerPrints,
never sees sccp converge, and -mlir-print-ir-after-change prints
after it.

rewrite() now gives each constant it reaches to the folder
(insertKnownConstant), as the greedy driver does, and leaves it: a
constant is already the form the rewrite produces, and looking it up
in the folder would still erase its location. The folder hands it out
for its value from then on, so the output of sccp is its own fixed
point. Constants are given as the walk reaches them rather than up
front, so a constant nested in an operation sccp erases goes with it
instead of being hoisted out.

The new RUN line in sccp.mlir runs sccp under
composite-fixed-point-pass and checks that it stops after the second
run, without a warning, with the output of one run.

Part of #<new>.

## Patch file

`llvm.patch`
