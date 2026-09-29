// RUN: idris-mlir-opt %s --idr-specialize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-specialize > %t2.mlir
// RUN: diff %t.mlir %t2.mlir
// A clone made by raising is keyed by its callee and what consumes the
// result: an apply of it, or of one field of it. Calls with equal keys share
// a clone, whatever their arguments, and so does the next run, which finds
// the keys on the clones: it changes nothing. A call with a constant
// argument shares the clone too: a machine number is no structure to
// specialize on.
// CHECK-LABEL: func.func private @use(
// CHECK-SAME: %[[N:[a-z0-9_]+]]: i64, %[[X:[a-z0-9_]+]]: i64)
// CHECK: call @[[G:g\$raise\$[0-9]+]](%[[N]], %[[X]])
// CHECK-NEXT: call @[[F:f\$raise\$[0-9]+]](%[[N]], %[[X]])
// CHECK-NEXT: call @[[F]](%[[X]], %[[N]])
// CHECK-NEXT: call @[[P0:pair\$raise\$[0-9]+]](%[[N]], %[[X]])
// CHECK-NEXT: call @[[P1:pair\$raise\$[0-9]+]](%[[X]], %[[N]])
// CHECK-NEXT: call @[[F]](%{{[a-z0-9_]+}}, %[[X]])
// CHECK: func.func private @[[G]](
// CHECK: call @sub(
// CHECK: func.func private @[[F]](
// CHECK: call @add(
// CHECK: func.func private @[[P0]](
// CHECK: call @add(
// CHECK: func.func private @[[P1]](
// CHECK: call @sub(
// CHECK-NOT: func.func private @f$raise$
module attributes {idr.program} {
  idr.data @Pair {
    idr.ctor @MkPair tag 0 (!idr.fn<(i64) -> (i64)>, !idr.fn<(i64) -> (i64)>)
  }
  func.func private @add(%a: i64, %x: i64) -> i64 attributes {idr.total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  func.func private @sub(%a: i64, %x: i64) -> i64 attributes {idr.total} {
    %y = arith.subi %a, %x : i64
    return %y : i64
  }
  func.func private @f(%a: i64) -> !idr.fn<(i64) -> (i64)> attributes {idr.total} {
    %f = idr.closure @add(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
    return %f : !idr.fn<(i64) -> (i64)>
  }
  func.func private @g(%a: i64) -> !idr.fn<(i64) -> (i64)> attributes {idr.total} {
    %f = idr.closure @sub(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
    return %f : !idr.fn<(i64) -> (i64)>
  }
  func.func private @pair(%a: i64) -> !idr.data<@Pair> attributes {idr.total} {
    %f = idr.closure @add(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
    %g = idr.closure @sub(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
    %p = idr.con @Pair::@MkPair(%f, %g) : (!idr.fn<(i64) -> (i64)>, !idr.fn<(i64) -> (i64)>) -> !idr.data<@Pair>
    return %p : !idr.data<@Pair>
  }
  func.func private @use(%n: i64, %x: i64) -> i64 attributes {idr.total} {
    %c3 = arith.constant 3 : i64
    %g1 = func.call @g(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r1 = idr.apply %g1(%x) : !idr.fn<(i64) -> (i64)>
    %f1 = func.call @f(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r2 = idr.apply %f1(%x) : !idr.fn<(i64) -> (i64)>
    %f2 = func.call @f(%x) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r3 = idr.apply %f2(%n) : !idr.fn<(i64) -> (i64)>
    %p = func.call @pair(%n) : (i64) -> !idr.data<@Pair>
    %p0 = idr.field %p[@MkPair, 0] : !idr.data<@Pair> -> !idr.fn<(i64) -> (i64)>
    %r4 = idr.apply %p0(%x) : !idr.fn<(i64) -> (i64)>
    %q = func.call @pair(%x) : (i64) -> !idr.data<@Pair>
    %q1 = idr.field %q[@MkPair, 1] : !idr.data<@Pair> -> !idr.fn<(i64) -> (i64)>
    %r5 = idr.apply %q1(%n) : !idr.fn<(i64) -> (i64)>
    %f3 = func.call @f(%c3) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r6 = idr.apply %f3(%x) : !idr.fn<(i64) -> (i64)>
    %s1 = arith.addi %r1, %r2 : i64
    %s2 = arith.addi %s1, %r3 : i64
    %s3 = arith.addi %s2, %r4 : i64
    %s4 = arith.addi %s3, %r5 : i64
    %s5 = arith.addi %s4, %r6 : i64
    return %s5 : i64
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
