Approach changed: the old patch added three inline poison loops at the three erase sites; now one helper, replaceUsesWithPoison, is the only way the pass removes a use, so no erased value can leave a null operand behind.

# Submission

Status: file. Three texts, in this order: a new issue, a short comment on
the open pull request https://github.com/llvm/llvm-project/pull/208881,
and a pull request whose diff is `pull-request.diff` (against llvm main,
checked with `git apply --check` at 7208ba24, 2026-10-08).

Author: Bjorn, as an individual; the work was done outside any employer.
No employer, no trailers, no @mentions. The pull request is one commit,
squash-merged with the title and body below as its message.

Why a pull request of its own, and not a review suggestion on #208881:
#208881 (jjppp) replaces the uses of a dead function argument with
`ub.poison`. It was approved on 2026-07-18 and has not been merged, and
its test hunk no longer applies at trunk (`@callee_with_dead_return` was
appended after `@func_with_non_call_users`). Asking it to grow to block
arguments and results would reopen an approved review. A pull request
stacked on it needs a user branch in llvm-project, which Bjorn cannot
push. So the pull request applies to trunk as it is: one helper retires
every value the pass erases, the function-argument site included. If
#208881 lands first, the rebase replaces #208881's loop with the helper
call, and nothing else changes. If this lands first, #208881 reduces to
its test.

Open pull requests that touch the same lines:
- #208940 ("[mlir] Coordinate branch argument cleanup", no review since
  2026-07-11) rewrites the block-argument cleanup and poisons its uses
  there too. Whichever lands second drops or rebases that one line.
- #182711 ("[mlir][RemoveDeadValues] Simplify branch op handling using
  ub.poison", under review) deletes the block-argument cleanup. If it
  lands first, the block-argument line and its test go, and the rest
  stands.

`@address_taken_callee` is posted on #208881 by
`remove-dead-values-address-taken`, not from here.

## Issue

### Title

```
[mlir] remove-dead-values leaves a null operand in unreachable code
```

### Body

----- paste -----

`-remove-dead-values` drops the uses of a dead block argument or a dead op result before it erases them. Liveness marks every value in code it finds unreachable as dead, but the pass keeps calls (and region branch ops with side effects) there, so a call in such code that uses the value is left with a null operand.

Block argument, only used under a condition that is false (`@never` returns false):

```mlir
func.func private @ext(i32)
func.func private @never() -> i1 {
  %false = arith.constant false
  return %false : i1
}
func.func @main(%v: i32) {
  %no = func.call @never() : () -> i1
  cf.br ^bb1(%v : i32)
^bb1(%a: i32):
  scf.if %no {
    func.call @ext(%a) : (i32) -> ()
  }
  return
}
```

```
$ mlir-opt dead-block-arg.mlir -remove-dead-values
dead-block-arg.mlir:13:5: error: null operand found
    func.call @ext(%a) : (i32) -> ()
    ^
dead-block-arg.mlir:13:5: note: see current operation: "func.call"(<<NULL VALUE>>) <{callee = @ext}> : (<<NULL TYPE>>) -> ()
```

Call result: the result of `@f` is dead at the reachable call, so the pass erases it from every call of `@f`, including the one under the false condition whose result is used:

```mlir
func.func private @ext(i32)
func.func private @never() -> i1 {
  %false = arith.constant false
  return %false : i1
}
func.func private @f() -> i32 {
  %c = arith.constant 1 : i32
  return %c : i32
}
func.func @main() {
  %r = func.call @f() : () -> i32
  %no = func.call @never() : () -> i1
  scf.if %no {
    %s = func.call @f() : () -> i32
    func.call @ext(%s) : (i32) -> ()
  }
  return
}
```

```
$ mlir-opt dead-result.mlir -remove-dead-values
dead-result.mlir:18:5: error: null operand found
    func.call @ext(%s) : (i32) -> ()
    ^
dead-result.mlir:18:5: note: see current operation: "func.call"(<<NULL VALUE>>) <{callee = @ext}> : (<<NULL TYPE>>) -> ()
```

Expected: the call keeps a `ub.poison : i32` operand, as it already does when the pass erases the op that defined the value.

Reproduced with llvmorg-23.1.2. The code is the same at 7208ba24: `dropAllUses` in the block-argument cleanup and in `dropUsesAndEraseResults` in RemoveDeadValues.cpp. #208881 fixes the same thing for function arguments (#206920, #203226).

----- end -----

## Comment on #208881

----- paste -----

The pass drops uses in two more places, a dead block argument and a dead call result, and they fail the same way (#ISSUE). I've put up #PR, which does the replacement in one helper for every value the pass erases, including function arguments. That overlaps with this PR. If this lands first, I'll rebase onto it. Note that the test hunk here no longer applies at trunk, since `@callee_with_dead_return` was appended after `@func_with_non_call_users`.

----- end -----

Replace #ISSUE and #PR with the numbers once filed. Post the comment
after the pull request is open.

## Pull request

### Title (66 characters)

```
[mlir][RemoveDeadValues] Replace uses of erased values with poison
```

### Body

```
The liveness analysis marks every value in code it finds unreachable as
dead, but remove-dead-values keeps some ops there: calls, which it never
erases, and region branch ops with side effects. Such an op may still use
a value the pass erases. The cleanup dropped the uses of dead function
arguments, block arguments and op results, which left that op with a null
operand ("null operand found", or a crash in the region branch
canonicalization that follows). Only the results of an erased op were
replaced with ub.poison.

Add replaceUsesWithPoison, which replaces the uses of a value with a
ub.poison at its definition, and use it for every value the pass erases.
The pass no longer drops a use. #208881 makes the same change for function
arguments alone.

Tests: one module each for a dead function argument, a dead block argument
and a dead call result used in code that is never executed.

Fixes #ISSUE
```
