// RUN: idris-mlir-opt %s --idr-rc --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,signature=@naturals:(i64,i64,i64)->(i64,i64,i1,i64,i64,i64)' -o /dev/null
// RUN: FileCheck %s < %t.mlir
// NEEDS-ACCEPTANCE: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded (R04), so the checks are of the counted program; confirm them against it.
// A natural is the big it is: the same word at runtime, so a natural as an
// Integer is its operand itself. Its ops have their small case inline, and
// call the runtime's big functions on the cold path (big-fast-path.mlir).
// CHECK-LABEL: func.func private @naturals(
// CHECK-SAME: %[[A:[^:]*]]: i64, %[[B:[^:]*]]: i64, %[[I:[^:]*]]: i64
// CHECK: return {{.*}}, %[[A]] :
// Nat's zero and one are the small words of 0 and 1, as Integer's are:
// the runtime's encoding, checked as written.
// CHECK-LABEL: func.func {{.*}}@Prog.main(
// CHECK-DAG: constant{{[( ]}}1 : i64
// CHECK-DAG: constant{{[( ]}}3 : i64
idr.program @nat root(@Prog.main) stage(first) {
  idr.func @naturals(%a: !idr.nat, %b: !idr.nat, %i: !idr.big)
      -> (!idr.nat, !idr.nat, i1, !idr.nat, !idr.nat, !idr.big) {
    %s = idr.big.add %a, %b : !idr.nat
    %p = idr.big.mul %a, %b : !idr.nat
    %c = idr.big.cmp lt %a, %b : !idr.nat
    %d = idr.big.pred %a
    %n = idr.nat.from_big %i
    %e = idr.nat.to_big %a
    return %s, %p, %c, %d, %n, %e : !idr.nat, !idr.nat, i1, !idr.nat, !idr.nat, !idr.big
  }
  idr.func @Prog.main() -> i64 {
    %zero = idr.constant #idr.big<0> : !idr.nat
    %one = idr.constant #idr.big<1> : !idr.nat
    %i = idr.constant #idr.big<-5> : !idr.big
    %r:6 = idr.call @naturals(%zero, %one, %i)
        : (!idr.nat, !idr.nat, !idr.big) -> (!idr.nat, !idr.nat, i1, !idr.nat, !idr.nat, !idr.big)
    %x = arith.extui %r#2 : i1 to i64
    return %x : i64
  }
}
