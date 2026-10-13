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
// CHECK-LABEL: idr.func private @use(
// CHECK-SAME: %[[N:[a-z0-9_]+]]: i64, %[[X:[a-z0-9_]+]]: i64)
// CHECK: call @[[G:g\.raise[0-9]+]](%[[N]], %[[X]])
// CHECK-NEXT: call @[[F:f\.raise[0-9]+]](%[[N]], %[[X]])
// CHECK-NEXT: call @[[F]](%[[X]], %[[N]])
// CHECK-NEXT: call @[[P0:pair\.raise[0-9]+]](%[[N]], %[[X]])
// CHECK-NEXT: call @[[P1:pair\.raise[0-9]+]](%[[X]], %[[N]])
// CHECK-NEXT: call @[[F]](%{{[a-z0-9_]+}}, %[[X]])
// CHECK: idr.func private @[[G]](
// CHECK: call @sub(
// CHECK: idr.func private @[[F]](
// CHECK: call @add(
// CHECK: idr.func private @[[P0]](
// CHECK: call @add(
// CHECK: idr.func private @[[P1]](
// CHECK: call @sub(
// CHECK-NOT: idr.func private @f.raise
module attributes {idr.program} {
  idr.data @Pair {
    idr.ctor @MkPair (!idr.fn<(i64) -> (i64)>, !idr.fn<(i64) -> (i64)>)
  }
  idr.func private @add(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  idr.func private @sub(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.subi %a, %x : i64
    return %y : i64
  }
  idr.func private @f(%a: i64) -> !idr.fn<(i64) -> (i64)> attributes {total} {
    %f = idr.closure @add(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
    return %f : !idr.fn<(i64) -> (i64)>
  }
  idr.func private @g(%a: i64) -> !idr.fn<(i64) -> (i64)> attributes {total} {
    %f = idr.closure @sub(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
    return %f : !idr.fn<(i64) -> (i64)>
  }
  idr.func private @pair(%a: i64) -> !idr.data<@Pair> attributes {total} {
    %f = idr.closure @add(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
    %g = idr.closure @sub(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
    %p = idr.con @Pair::@MkPair(%f, %g) : (!idr.fn<(i64) -> (i64)>, !idr.fn<(i64) -> (i64)>) -> !idr.data<@Pair>
    return %p : !idr.data<@Pair>
  }
  idr.func private @use(%n: i64, %x: i64) -> i64 attributes {total} {
    %c3 = arith.constant 3 : i64
    %g1 = idr.call @g(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r1 = idr.apply %g1(%x) : !idr.fn<(i64) -> (i64)>
    %f1 = idr.call @f(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r2 = idr.apply %f1(%x) : !idr.fn<(i64) -> (i64)>
    %f2 = idr.call @f(%x) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r3 = idr.apply %f2(%n) : !idr.fn<(i64) -> (i64)>
    %p = idr.call @pair(%n) : (i64) -> !idr.data<@Pair>
    %p0 = idr.field %p[@MkPair, 0] : !idr.data<@Pair> -> !idr.fn<(i64) -> (i64)>
    %r4 = idr.apply %p0(%x) : !idr.fn<(i64) -> (i64)>
    %q = idr.call @pair(%x) : (i64) -> !idr.data<@Pair>
    %q1 = idr.field %q[@MkPair, 1] : !idr.data<@Pair> -> !idr.fn<(i64) -> (i64)>
    %r5 = idr.apply %q1(%n) : !idr.fn<(i64) -> (i64)>
    %f3 = idr.call @f(%c3) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r6 = idr.apply %f3(%x) : !idr.fn<(i64) -> (i64)>
    %s1 = arith.addi %r1, %r2 : i64
    %s2 = arith.addi %s1, %r3 : i64
    %s3 = arith.addi %s2, %r4 : i64
    %s4 = arith.addi %s3, %r5 : i64
    %s5 = arith.addi %s4, %r6 : i64
    return %s5 : i64
  }
  idr.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
