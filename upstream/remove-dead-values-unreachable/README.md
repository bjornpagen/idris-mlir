# [mlir] `remove-dead-values` erases the arguments of an unreachable function but keeps their uses

At `llvmorg-23.1.2`, `--remove-dead-values` leaves operations with null
operands (a verifier failure, or an assertion in `matchPattern` from the
region-branch canonicalization that the pass runs afterwards) when a
private function is never reached, because nothing calls it or because its
only call is in a region that constant propagation rules out.

## Reproduce

`unreachable.mlir` (the call of `@g` is under a false `scf.if`):

```mlir
func.func private @ext(i32)

func.func private @g(%x: i32) {
  func.call @ext(%x) : (i32) -> ()
  return
}

func.func @main(%v: i32) {
  %false = arith.constant false
  scf.if %false {
    func.call @g(%v) : (i32) -> ()
  }
  return
}
```

`uncalled.mlir` is the same without `@main`: nothing calls `@g`.

```
$ mlir-opt unreachable.mlir --remove-dead-values
unreachable.mlir:4:3: error: null operand found
  func.call @ext(%x) : (i32) -> ()
  ^
note: see current operation: "func.call"(<<NULL VALUE>>) <{callee = @ext}> : (<<NULL TYPE>>) -> ()
```

`mlir-opt` exits 1. `uncalled.mlir` fails the same way. In a larger module,
where a region op keeps the orphaned use, the pass instead asserts in
`matchPattern` (`mlir/include/mlir/IR/Matchers.h:491`) during its final
region-branch canonicalization, or crashes.

Expected: the module is left valid. Either the unreachable function is left
alone, or its body is deleted with its arguments.

The same happens to a dead result and to a dead block argument used in
code the analysis never reaches. In `dead-result.mlir` the result of `@f`
is unused at the call `@main` makes, and used after a second call under a
condition only the interprocedural analysis knows is false (a call of
`@never`, which returns `false`); `dead-block-arg.mlir` is the same for a
block argument whose one use is under that condition:

```
$ mlir-opt dead-result.mlir --remove-dead-values
dead-result.mlir:18:5: error: null operand found
    func.call @ext(%s) : (i32) -> ()
$ mlir-opt dead-block-arg.mlir --remove-dead-values
dead-block-arg.mlir:13:5: error: null operand found
    func.call @ext(%a) : (i32) -> ()
```

## Cause

`RunLivenessAnalysis` runs with dead-code analysis, so it never visits the
body of a function that dead-code analysis finds unreachable: its arguments
have no liveness state and count as dead (`LivenessAnalysis.cpp`, "has no
liveness info, mark dead"). `processFuncOp`
(`mlir/lib/Transforms/RemoveDeadValues.cpp:271`) then marks them non-live,
and the cleanup drops all their uses and erases them
(`RemoveDeadValues.cpp:644-649`). The operations that used them are not in
the cleanup list, because the analysis never looked at them either, so they
keep null operands. The cleanup drops uses the same way when it erases a
dead block argument (`:597`) and the dead results of an op
(`dropUsesAndEraseResults`, `:207`, for the calls of a function whose
result goes): a use in code the analysis never reached is left null.

## Proposed fix

In `processFuncOp`, skip a function whose entry block the solver did not
find executable (`solver.lookupState<dataflow::Executable>(
solver.getProgramPointBefore(&entry))`), as the pass already skips public
and external functions; or erase such a function's body along with its
arguments. The same check belongs wherever the pass treats a value without
liveness state as dead: a value is only dead if the analysis reached its
uses.

## Status upstream

Already reported by others: the open issues
[#206920](https://github.com/llvm/llvm-project/issues/206920) and
[#203226](https://github.com/llvm/llvm-project/issues/203226) are this bug,
and the open pull request
[#208881](https://github.com/llvm/llvm-project/pull/208881) fixes it; it is
not merged (checked at main ed390ca4, October 2026). Add `uncalled.mlir`
and `unreachable.mlir` to those issues rather than filing again. #208881
gives poison to the uses of dead function arguments only; main (checked at
155462f440f, October 2026) still drops the uses of a dead block argument
and of dead results, so `dead-result.mlir` and `dead-block-arg.mlir` fail
there too.

## Our workaround

None: the patch below is carried. Before it, `idr-prune` ran the same
analyses before `remove-dead-values` and emptied every block they prove
unreachable, and `symbol-dce` then removed the functions that only that
code referred to. With the patch, the simplify round without them gave
k-nucleotide and every-types-export the same objects, byte for byte, in
as many rounds, so both went. What emptying did beyond the bug (a region a
constant rules out ended in `ub.unreachable`, so that a match whose taken
region crashes was seen never to complete) the match canonicalization now
decides from the region the constant selects.

## Patch

`llvm.patch`: the open pull request #208881, unchanged (the cleanup
replaces a dead argument's remaining uses with `ub.poison` instead of
dropping them), and the same at the two other places the cleanup dropped
uses: a dead block argument's and a dead result's remaining uses take
`ub.poison` too. `uncalled.mlir`, `unreachable.mlir`,
`../remove-dead-values-address-taken/address-taken.mlir`, `dead-result.mlir`
and `dead-block-arg.mlir` are added to
`mlir/test/Transforms/remove-dead-values.mlir`. It fixes
`remove-dead-values-address-taken` too. Built into the pinned toolchain;
the test cases it adds pass with its `mlir-opt`, under both prefixes, and
it leaves the output of every other case of the file as it was (the rest
of the file uses the test dialect, which the pinned build does not have,
so FileCheck cannot run all of it); `tests/upstream/remove-dead-values-unreachable`
checks the reproducers.

## Upstreaming plan

Status: file upstream.

- Where: review of #208881; comment on #206920 and #203226 with the two
  reproducers, and on the pull request with the address-taken one. The
  block-argument and result parts go to #208881 as a suggestion, or as a
  pull request of their own on top of it, with `dead-result.mlir` and
  `dead-block-arg.mlir`.
- Upstream test: the five modules this patch adds to
  `remove-dead-values.mlir`.
- The patch is dropped when the pin includes #208881 and a fix for the
  other two places.
