// RUN: idris-mlir-opt %s --sccp | FileCheck %s
// SCCP propagates a constructor constant through a call into a private
// function, where the field read of it folds.

idr.data @P {
  idr.ctor @MkP tag 0 (i64, i64) {quantities = ["w", "w"]}
}

// CHECK-LABEL: func.func private @second
// CHECK-NOT: idr.field
// CHECK: %[[C:.*]] = arith.constant 7 : i64
// CHECK-NEXT: return %[[C]] : i64
func.func private @second(%p: !idr.data<@P>) -> i64 {
  %y = idr.field %p[@MkP, 1] : !idr.data<@P> -> i64
  return %y : i64
}

// CHECK-LABEL: func.func @main
// CHECK: %[[P:.*]] = idr.constant #idr.con<@P::@MkP, [6, 7]> : !idr.data<@P>
// CHECK: %[[C:.*]] = arith.constant 7 : i64
// CHECK: call @second(%[[P]])
// CHECK: return %[[C]] : i64
func.func @main() -> i64 {
  %a = arith.constant 6 : i64
  %b = arith.constant 7 : i64
  %p = idr.con @P::@MkP(%a, %b) : (i64, i64) -> !idr.data<@P>
  %r = func.call @second(%p) : (!idr.data<@P>) -> i64
  return %r : i64
}
