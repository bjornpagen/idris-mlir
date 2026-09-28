// RUN: idris-mlir-opt %s --idr-specialize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-specialize > %t2.mlir
// RUN: diff %t.mlir %t2.mlir
// RUN: idris-mlir-opt %s --idr-specialize="clone-limit=1" --remarks-filter-missed=idr-specialize > %t3.mlir 2> %t3.err
// RUN: FileCheck %s --check-prefix=LIMIT < %t3.mlir
// RUN: FileCheck %s --check-prefix=REMARK < %t3.err
// rule: ELIM-G-5, ELIM-SPEC-1, ELIM-SPEC-2, FE-DET-1
// A clone made by raising is keyed by its callee and the projection before
// the apply, named @<origin>$raise$<n>, and numbered with the other clones
// of its origin in order of first request. Calls with equal keys share a
// clone, and so does the next run, which finds the key in idr.spec_key: the
// second run changes nothing. A raised call is then specialized as any
// other (the constant 3): the clone that raising made has parameters @f
// does not have, so it is the origin of its own clones, which record it in
// idr.spec_history as a clone of any origin does, and that clone calls a
// clone of @add in turn. The clone limit counts the clones that raising
// makes: with a limit of one, the second projection of @pair is not raised,
// with a Missed remark.
// CHECK: module attributes {idr.clone_counts = {add = 1 : i64, f = 1 : i64, f$raise$1 = 1 : i64, g = 1 : i64, pair = 2 : i64}, idr.program}
// CHECK-LABEL: func.func private @use(
// CHECK-SAME: %[[N:[a-z0-9_]+]]: i64 {idr.quantity = "w"}, %[[X:[a-z0-9_]+]]: i64 {idr.quantity = "w"})
// CHECK: call @g$raise$1(%[[N]], %[[X]])
// CHECK-NEXT: call @f$raise$1(%[[N]], %[[X]])
// CHECK-NEXT: call @f$raise$1(%[[X]], %[[N]])
// CHECK-NEXT: call @pair$raise$1(%[[N]], %[[X]])
// CHECK-NEXT: call @pair$raise$2(%[[X]], %[[N]])
// CHECK-NEXT: call @f$raise$1$spec$1(%[[X]])
// CHECK-LABEL: func.func private @g$raise$1(
// CHECK-SAME: idr.origin = "g", idr.spec_key = "raise @g"
// CHECK: call @sub(
// CHECK-LABEL: func.func private @f$raise$1(
// CHECK-SAME: idr.origin = "f", idr.spec_key = "raise @f"
// CHECK: call @add(
// CHECK-LABEL: func.func private @pair$raise$1(
// CHECK-SAME: idr.spec_key = "raise @pair[@MkPair, 0]"
// CHECK: call @add(
// CHECK-LABEL: func.func private @pair$raise$2(
// CHECK-SAME: idr.spec_key = "raise @pair[@MkPair, 1]"
// CHECK: call @sub(
// CHECK-LABEL: func.func private @f$raise$1$spec$1(
// CHECK-SAME: idr.origin = "f$raise$1", idr.spec_history = {f$raise$1 = "[3, unit]"}, idr.spec_key = "[3, unit]"
// CHECK: call @add$spec$1(%{{.*}})
// CHECK-NOT: func.func private @f$raise$2
// LIMIT: module attributes {idr.clone_counts = {add = 1 : i64, f = 1 : i64, f$raise$1 = 1 : i64, g = 1 : i64, pair = 1 : i64}, idr.program}
// LIMIT: call @pair$raise$1(
// LIMIT-NEXT: %[[Q:.*]] = call @pair(
// LIMIT-NEXT: %[[Q1:.*]] = idr.field %[[Q]][@MkPair, 1]
// LIMIT-NEXT: idr.apply %[[Q1]](
// LIMIT-NOT: $raise$2
// REMARK: remark: [Missed] idr-specialize | Category:idr-specialize
// REMARK-SAME: arity raising of @pair stopped: the clone limit of 1 clones of @pair is reached
// REMARK-NOT: [Missed]
module attributes {idr.program} {
  idr.data @Pair {
    idr.ctor @MkPair tag 0 (!idr.fn<(i64) -> (i64)>, !idr.fn<(i64) -> (i64)>) {quantities = ["w", "w"]}
  }
  func.func private @add(%a: i64 {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  func.func private @sub(%a: i64 {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %y = arith.subi %a, %x : i64
    return %y : i64
  }
  func.func private @f(%a: i64 {idr.quantity = "w"}) -> !idr.fn<(i64) -> (i64)> attributes {idr.total} {
    %f = idr.closure @add(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
    return %f : !idr.fn<(i64) -> (i64)>
  }
  func.func private @g(%a: i64 {idr.quantity = "w"}) -> !idr.fn<(i64) -> (i64)> attributes {idr.total} {
    %f = idr.closure @sub(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
    return %f : !idr.fn<(i64) -> (i64)>
  }
  func.func private @pair(%a: i64 {idr.quantity = "w"}) -> !idr.data<@Pair> attributes {idr.total} {
    %f = idr.closure @add(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
    %g = idr.closure @sub(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
    %p = idr.con @Pair::@MkPair(%f, %g) : (!idr.fn<(i64) -> (i64)>, !idr.fn<(i64) -> (i64)>) -> !idr.data<@Pair>
    return %p : !idr.data<@Pair>
  }
  func.func private @use(%n: i64 {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
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
