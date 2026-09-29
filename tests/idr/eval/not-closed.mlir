// RUN: idris-mlir-opt %s --mlir-disable-threading --idr-eval | FileCheck %s
// Only a closed call of a pure function is evaluated: not one with a
// runtime operand, not one of a function that performs IO, and not one
// whose constant operands name a closure of such a function. (Whether Idris
// proves the function terminating only decides whether the call runs
// metered: partial.mlir.)
// CHECK-LABEL: func.func @Prog.main(
// CHECK-SAME: %[[N:[^:]+]]: i64
// CHECK: call @inc(%[[N]])
// CHECK: call @loud(%{{.*}})
// CHECK: call @applyTo(%{{.*}})
// CHECK: %[[OK:.*]] = arith.constant 4 : i64
// CHECK: return {{.*}}%[[OK]]
module {
  func.func private @inc(%x: i64) -> i64 attributes {idr.total, idr.effects = #idr.effects<none>} {
    %one = arith.constant 1 : i64
    %r = arith.addi %x, %one : i64
    return %r : i64
  }
  func.func private @loud(%x: i64) -> i64 attributes {idr.total, idr.effects = #idr.effects<io>} {
    return %x : i64
  }
  func.func private @applyTo(%f: !idr.fn<(i64) -> (i64)>) -> i64 attributes {idr.total, idr.effects = #idr.effects<none>} {
    %one = arith.constant 1 : i64
    %r = idr.apply %f(%one) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  func.func @Prog.main(%n: i64) -> (i64, i64, i64, i64) {
    %a = func.call @inc(%n) : (i64) -> i64
    %three = arith.constant 3 : i64
    %c = func.call @loud(%three) : (i64) -> i64
    %p = idr.constant #idr.closure<@loud, []> : !idr.fn<(i64) -> (i64)>
    %d = func.call @applyTo(%p) : (!idr.fn<(i64) -> (i64)>) -> i64
    %e = func.call @inc(%three) : (i64) -> i64
    return %a, %c, %d, %e : i64, i64, i64, i64
  }
}
