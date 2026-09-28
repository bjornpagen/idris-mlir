// RUN: idris-mlir-opt %s --idr-specialize="clone-limit=2" > %t.mlir
// RUN: FileCheck %s < %t.mlir
// rule: ELIM-SPEC-1, OPT-PIPE-3, OPT-PIPE-5
// iter passes itself a closure that grows: its self call specializes on
// after(f), and the clone's call on after(after(f)). The second clone is a
// copy of @iter as it is by then, calling the first clone, and the limit
// stops that call: the two clones form a cycle, which the inliner, refusing
// only self-recursion and a callee that calls its caller back, would unroll
// from outside; its newest clone becomes a loop breaker.
// CHECK-LABEL: func.func private @iter(
// CHECK-NOT: no_inline
// CHECK: call @iter$spec$1(
// CHECK-LABEL: func.func private @iter$spec$1(
// CHECK-NOT: no_inline
// CHECK: call @iter$spec$2(
// CHECK-LABEL: func.func private @iter$spec$2(
// CHECK-SAME: no_inline
// CHECK: call @iter$spec$1(%{{.*}}) {idr.clone_limit_hit}
module attributes {idr.program} {
  func.func private @after(%f: !idr.fn<(i64) -> (i64)> {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    %c1 = arith.constant 1 : i64
    %z = arith.addi %y, %c1 : i64
    return %z : i64
  }
  func.func private @iter(%f: !idr.fn<(i64) -> (i64)> {idr.quantity = "w"}, %n: i64 {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      idr.yield %y : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %g = idr.closure @after(%f) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)>
      %y = func.call @iter(%g, %m, %x) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
