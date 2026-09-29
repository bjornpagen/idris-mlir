// RUN: idris-mlir-opt %s --idr-specialize | FileCheck %s
// An interface dictionary: a record of closures without captures, built at
// the call. It is entirely static, the other argument is not, so the call
// is specialized on the whole dictionary. The clone is folded when it is
// made: its field read and application become a direct call of the
// implementation.
module attributes {idr.program} {
  idr.data @Num {
    idr.ctor @MkNum tag 0 (!idr.fn<(i64, i64) -> (i64)>, !idr.fn<(i64) -> (i64)>)
  }
  func.func private @plus(%a: i64, %b: i64) -> i64 attributes {idr.total} {
    %c = arith.addi %a, %b : i64
    return %c : i64
  }
  func.func private @neg(%a: i64) -> i64 attributes {idr.total} {
    %z = arith.constant 0 : i64
    %c = arith.subi %z, %a : i64
    return %c : i64
  }
  func.func private @double(%d: !idr.data<@Num>, %x: i64) -> i64 attributes {idr.total} {
    %plus = idr.field %d[@MkNum, 0] : !idr.data<@Num> -> !idr.fn<(i64, i64) -> (i64)>
    %r = idr.apply %plus(%x, %x) : !idr.fn<(i64, i64) -> (i64)>
    return %r : i64
  }
  // CHECK-LABEL: func.func private @use(
  // CHECK-SAME: %[[X:[a-z0-9_]+]]: i64
  // CHECK: call @[[D:double\$spec\$[0-9]+]](%[[X]]) : (i64) -> i64
  func.func private @use(%x: i64) -> i64 attributes {idr.total} {
    %p = idr.closure @plus() : () -> !idr.fn<(i64, i64) -> (i64)>
    %n = idr.closure @neg() : () -> !idr.fn<(i64) -> (i64)>
    %d = idr.con @Num::@MkNum(%p, %n) : (!idr.fn<(i64, i64) -> (i64)>, !idr.fn<(i64) -> (i64)>) -> !idr.data<@Num>
    %r = func.call @double(%d, %x) : (!idr.data<@Num>, i64) -> i64
    return %r : i64
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // CHECK: func.func private @[[D]](
  // CHECK-SAME: %[[Y:[a-z0-9_]+]]: i64 {{.*}}) -> i64
  // CHECK-SAME: idr.total
  // CHECK-NEXT: %[[R:.*]] = call @plus(%[[Y]], %[[Y]])
  // CHECK-NEXT: return %[[R]]
}
