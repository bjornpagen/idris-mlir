# Submission

Status: file as a comment and a test on https://github.com/llvm/llvm-project/pull/208881. No new issue. No second pull request.

Not Bugzilla. Author is Bjorn, individual, work done outside any employer. No Assisted-by. No @mentions.

The patch that fixes it is `remove-dead-values-unreachable/llvm.patch`.

Paste the comment below. Leave this header out.

## Comment

Please add `@address_taken_callee` to `mlir/test/Transforms/remove-dead-values.mlir` as a test of this pull request. Replacing the remaining uses of a dead function argument with `ub.poison` covers a direct call of an address-taken function.

`processFuncOp` skips a private function when any user of its symbol is not a call, such as `func.constant`. The signature stays, every call keeps its operands, and that function gets no cleanup entry. Liveness still marks the caller's argument dead, because the callee never reads the parameter. The cleanup drops that argument's uses and erases it, and the call is left with a null operand.

At llvmorg-23.1.2, `mlir-opt --remove-dead-values` on the function bodies in the test below exits 1:

```
error: null operand found
  %t = func.call @ignores(%b) : (i64) -> i64
       ^
note: see current operation: %0 = "func.call"(<<NULL VALUE>>) <{callee = @ignores}> : (<<NULL TYPE>>) -> i64
```

When the value passed is an operation result, the pass already replaces it with `ub.poison` and the module stays valid. The same replacement for the dead block argument leaves `@caller` passing `ub.poison : i64` to `@ignores`.

```mlir
// @ignores keeps its signature, since a func.constant names it, and never
// reads its parameter, so the value @caller passes it is dead: the call
// keeps its operand, which becomes poison.
// CHECK-LABEL: module @address_taken_callee
// CHECK:         func.func private @caller(
// CHECK:           %[[P:.*]] = ub.poison : i64
// CHECK:           call @ignores(%[[P]])
// CHECK-CANONICALIZE-LABEL: module @address_taken_callee
// CHECK-CANONICALIZE:         call @ignores(
module @address_taken_callee {
  func.func private @ignores(%x: i64) -> i64 {
    %c = arith.constant 7 : i64
    return %c : i64
  }
  func.func private @caller(%a: i64, %b: i64) -> i64 {
    %t = func.call @ignores(%b) : (i64) -> i64
    %u = arith.addi %a, %t : i64
    return %u : i64
  }
  func.func @main(%a: i64) -> i64 {
    %f = func.constant @ignores : (i64) -> i64
    %r = func.call_indirect %f(%a) : (i64) -> i64
    %t = func.call @caller(%r, %a) : (i64, i64) -> i64
    return %t : i64
  }
}
```

I am Bjorn, an individual. This work was done outside any employer.
