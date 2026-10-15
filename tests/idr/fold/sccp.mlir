// RUN: idris-mlir-opt %s --sccp | FileCheck %s
// SCCP propagates a constructor constant through a call into a private
// function, where the field read of it folds.


// CHECK-LABEL: idr.func private @second
// CHECK-NOT: {{(idr\.| )field }}
// CHECK: %[[C:.*]] = arith.constant 7 : i64
// CHECK-NEXT: return %[[C]] : i64
!P = !idr.data<"P", plain [@MkP(i64, i64)]>
idr.func private @second(%p: !P) -> i64 {
  %y = idr.field %p[@MkP, 1] : !P -> i64
  return %y : i64
}

// CHECK-LABEL: idr.func @main
// CHECK: %[[P:.*]] = {{(idr\.)?}}constant #idr.con<@MkP, [6, 7]> : !P
// CHECK: %[[C:.*]] = arith.constant 7 : i64
// CHECK: call @second(%[[P]])
// CHECK: return %[[C]] : i64
idr.func @main() -> i64 {
  %a = arith.constant 6 : i64
  %b = arith.constant 7 : i64
  %p = idr.con @MkP(%a, %b) : (i64, i64) -> !P
  %r = idr.call @second(%p) : (!P) -> i64
  return %r : i64
}
