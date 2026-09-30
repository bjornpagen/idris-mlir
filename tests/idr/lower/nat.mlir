// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s --implicit-check-not=idr.
// A natural is the big it is: the same word at runtime, whose operations
// are the runtime's big ones. The sum, the product and the comparison of
// naturals call the big functions; the predecessor and the clamp from an
// Integer call the runtime's own; a natural as an Integer is itself.
// CHECK-LABEL: func.func private @naturals(
// CHECK-SAME: %[[A:[^:]*]]: i64, %[[B:[^:]*]]: i64, %[[I:[^:]*]]: i64
// CHECK: llvm.call @idris_rt_big_add(%[[A]], %[[B]]) : (i64, i64) -> i64
// CHECK: llvm.call @idris_rt_big_mul(%[[A]], %[[B]]) : (i64, i64) -> i64
// CHECK: llvm.call @idris_rt_big_cmp(%[[A]], %[[B]])
// CHECK: llvm.call @idris_rt_big_pred(%[[A]]) : (i64) -> i64
// CHECK: llvm.call @idris_rt_nat_from_big(%[[I]]) : (i64) -> i64
// CHECK: return {{.*}}, %[[A]] :
// Nat's zero and one are the small words of 0 and 1, as Integer's are.
// CHECK-LABEL: func.func @Prog.main(
// CHECK-DAG: arith.constant 1 : i64
// CHECK-DAG: arith.constant 3 : i64
module attributes {idr.program} {
  func.func private @naturals(%a: !idr.nat, %b: !idr.nat, %i: !idr.big)
      -> (!idr.nat, !idr.nat, i1, !idr.nat, !idr.nat, !idr.big) {
    %s = idr.big.add %a, %b : !idr.nat
    %p = idr.big.mul %a, %b : !idr.nat
    %c = idr.big.cmp lt %a, %b : !idr.nat
    %d = idr.big.pred %a
    %n = idr.nat.from_big %i
    %e = idr.nat.to_big %a
    return %s, %p, %c, %d, %n, %e : !idr.nat, !idr.nat, i1, !idr.nat, !idr.nat, !idr.big
  }
  func.func @Prog.main() -> i64 {
    %zero = idr.constant #idr.big<"0"> : !idr.nat
    %one = idr.constant #idr.big<"1"> : !idr.nat
    %i = idr.constant #idr.big<"-5"> : !idr.big
    %r:6 = func.call @naturals(%zero, %one, %i)
        : (!idr.nat, !idr.nat, !idr.big) -> (!idr.nat, !idr.nat, i1, !idr.nat, !idr.nat, !idr.big)
    %x = arith.extui %r#2 : i1 to i64
    return %x : i64
  }
}
