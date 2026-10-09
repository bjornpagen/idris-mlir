# Submission

Paste into GitHub, repository `llvm/llvm-project`. Not Bugzilla.

One commit. The author is Bjorn, as an individual, outside any employer.
No employer in the author name, the email, or the message. No
`Co-authored-by`. No `@` mentions. The last line of the pull request body
is `Assisted-by: Claude Code` (llvm/docs/AIToolPolicy.md).

The pull request is `pull-request.diff` in this directory, as that one
commit. It applies unchanged to llvm main at 7208ba24. There is no issue:
the pull request carries the reproducer. The squash commit message is the
pull request title, a blank line, and the pull request body.

Not before its README's "Before sending" holds: the new test passes with
the change and fails without it, and `check-mlir` passes.

## Pull request title

[mlir][SCCP] Revert a property an in-place fold sets on an op that had none

## Pull request body

sccp simulates each operation's fold with speculative constants, then
reverts whatever the fold changed in place (#213933). It restores the
properties from their attribute form, with getPropertiesAsAttribute() and
setPropertiesFromAttribute() (#218878). That form cannot undo a property
the fold set where the operation had none. An operation with no property
set has no attribute form, so nothing is restored. And
setPropertiesFromAttribute() leaves an attribute-backed property whose
key is missing from the dictionary as it is.

The arith.extui folder shows it. Folding an extui of an extui in place, it
takes the inner one's nneg flag:

```mlir
func.func @f(%x: i3) -> i16 {
  %a = arith.extui %x nneg : i3 to i8
  %b = arith.extui %a : i8 to i16
  return %b : i16
}
```

`mlir-opt --sccp` prints `%1 = arith.extui %0 nneg : i8 to i16`: sccp
puts the operand back but keeps the flag. The flag happens to hold here,
since the operand is a zero extension, but the analysis should leave the
IR as it found it.

This copies the properties storage before the fold and copies it back
afterwards, as ModifyOperationRewrite does when the dialect conversion
rolls back an in-place modification. That restores every property
exactly, whether it was set before or not. The operands and discardable
attributes are restored as before.

The test is the reproducer, added to sccp.mlir after #213933's regression
test.

Assisted-by: Claude Code

## Patch file

`pull-request.diff`
