// RUN: idris-mlir-opt %s --pass-pipeline="builtin.module(idr-specialize{clone-limit=3},canonicalize,idr-specialize{clone-limit=3})" --remarks-filter-missed=idr-specialize > %t.mlir 2> %t.remarks
// RUN: FileCheck %s < %t.mlir
// RUN: FileCheck %s --check-prefix=REMARK < %t.remarks
// An Integer counter that @count matches on, called with the constant 100
// and a runtime accumulator: each clone's own call has the next constant
// counter, which stays static (an Integer the callee matches on, as a Nat
// that unrolls a vector's length), and each clone is folded when it is made,
// so the chain grows within one run. The clone limit
// ends it: after three clones of @count, the call stays and gets a Missed
// remark, once: the call is marked so that later runs leave it, and so is
// its callee, for idr-check-profile. The count is kept on the module, so
// separate runs of the pass share the limit.
// CHECK: idr.clone_counts = {count = 3 : i64}
// CHECK: func.func private @count(
// CHECK-SAME: idr.spec_stopped
// CHECK: func.func private @count$spec$1(
// CHECK: func.func private @count$spec$2(
// CHECK: func.func private @count$spec$3(
// CHECK-NOT: idr.spec_stopped
// CHECK: call @count(%{{.*}}, %{{.*}}) {{{.*}}idr.spec_stopped, idr.spec_stopped_at = "[unit, #idr.big<\22{{97}}\22>]"}
// CHECK-NOT: func.func private @count$spec$4
// REMARK: remark: [Missed] idr-specialize | Category:idr-specialize
// REMARK-SAME: specialization of @count stopped: the clone limit of 3 clones of @count is reached
// REMARK-NOT: [Missed]
module attributes {idr.program} {
  func.func private @count(%acc: i64 {idr.quantity = "w"}, %n: !idr.big {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %r = idr.match_lit %n : !idr.big -> (i64) {
    case #idr.big<"0"> {
      idr.yield %acc : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %one = idr.constant #idr.big<"1"> : !idr.big
      %a = arith.addi %acc, %c1 : i64
      %m = idr.big.sub %n, %one
      %x = func.call @count(%a, %m) : (i64, !idr.big) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  func.func private @use(%acc: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %c100 = idr.constant #idr.big<"100"> : !idr.big
    %r = func.call @count(%acc, %c100) : (i64, !idr.big) -> i64
    return %r : i64
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
