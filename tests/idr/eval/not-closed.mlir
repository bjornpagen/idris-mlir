// RUN: idris-mlir-opt %s --mlir-disable-threading --idr-eval | FileCheck %s
// Only a closed call of a pure, total function is evaluated: not one with a
// runtime operand, not one of a function Idris does not prove terminating
// (partial code is never evaluated) or that
// performs IO, and not one whose
// constant operands name a closure of such a function.
// CHECK-LABEL: func.func @Prog.main(
// CHECK: call @inc(%arg0)
// CHECK: call @partial(%{{.*}})
// CHECK: call @loud(%{{.*}})
// CHECK: call @applyTo(%{{.*}})
// CHECK: %[[OK:.*]] = arith.constant 4 : i64
// CHECK: return {{.*}}%[[OK]]
module {
  func.func private @inc(%x: i64) -> i64 attributes {idr.total, idr.effect = "pure"} {
    %one = arith.constant 1 : i64
    %r = arith.addi %x, %one : i64
    return %r : i64
  }
  func.func private @partial(%x: i64) -> i64 attributes {idr.effect = "pure"} {
    return %x : i64
  }
  func.func private @loud(%x: i64) -> i64 attributes {idr.total, idr.effect = "effectful"} {
    return %x : i64
  }
  func.func private @applyTo(%f: !idr.fn<(i64) -> (i64)>) -> i64 attributes {idr.total, idr.effect = "pure"} {
    %one = arith.constant 1 : i64
    %r = idr.apply %f(%one) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  func.func @Prog.main(%n: i64) -> (i64, i64, i64, i64, i64) {
    %a = func.call @inc(%n) : (i64) -> i64
    %three = arith.constant 3 : i64
    %b = func.call @partial(%three) : (i64) -> i64
    %c = func.call @loud(%three) : (i64) -> i64
    %p = idr.constant #idr.closure<@partial, []> : !idr.fn<(i64) -> (i64)>
    %d = func.call @applyTo(%p) : (!idr.fn<(i64) -> (i64)>) -> i64
    %e = func.call @inc(%three) : (i64) -> i64
    return %a, %b, %c, %d, %e : i64, i64, i64, i64, i64
  }
}
