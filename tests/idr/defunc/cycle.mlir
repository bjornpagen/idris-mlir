// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: %status 1 idris-mlir-opt %s --idr-defunctionalize --idr-check-profile -o %t.out 2> %t.err
// RUN: FileCheck %s --check-prefix=ERR < %t.err
// rule: ELIM-CLOS-1, PROF-HEAP-1
// ping 0 = zero; ping n = p (pong (n - 1)); pong n = q (ping (n - 1)):
// @Main.p captures only closures of @Main.q, and @Main.q only closures of
// @Main.p or @Main.zero, so the two keys of the type have different labels,
// but each holds the other: a cycle, and no finite sum stands for either.
// Both stay closures, and the profile rejects the first one built at
// runtime.
// CHECK-NOT: idr.data @fn$
// CHECK-LABEL: func.func private @Main.p(
// CHECK-SAME: %{{.*}}: !idr.fn<(i64) -> (i64)>
// CHECK-LABEL: func.func private @Main.q(
// CHECK-SAME: %{{.*}}: !idr.fn<(i64) -> (i64)>
// CHECK-LABEL: func.func private @Main.ping(
// CHECK-SAME: -> !idr.fn<(i64) -> (i64)>
// CHECK: idr.closure @Main.p(%{{.*}}) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)>
// CHECK-LABEL: func.func private @Main.pong(
// CHECK: idr.closure @Main.q(%{{.*}}) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)>
// CHECK-LABEL: func.func @Main.main(
// CHECK: idr.apply %{{.*}}(%{{.*}}) : !idr.fn<(i64) -> (i64)>
// ERR: Main.idr:7:3: error: unsupported (PROF-HEAP-1): function value built at runtime: a closure of @Main.p that no finite choice of functions stands for
// ERR-NOT: error:
module attributes {idr.program} {
  func.func private @Main.zero(%x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    return %x : i64
  }
  func.func private @Main.p(%f: !idr.fn<(i64) -> (i64)> {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %c1 = arith.constant 1 : i64
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    %z = arith.addi %y, %c1 : i64
    return %z : i64
  }
  func.func private @Main.q(%f: !idr.fn<(i64) -> (i64)> {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    %z = arith.addi %y, %y : i64
    return %z : i64
  }
  func.func private @Main.ping(%n: i64 {idr.quantity = "w"}) -> !idr.fn<(i64) -> (i64)> {
    %r = idr.match_lit %n : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      %f = idr.closure @Main.zero() : () -> !idr.fn<(i64) -> (i64)>
      idr.yield %f : !idr.fn<(i64) -> (i64)>
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %g = func.call @Main.pong(%m) : (i64) -> !idr.fn<(i64) -> (i64)>
      %h = idr.closure @Main.p(%g) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)> loc("Main.idr":7:3)
      idr.yield %h : !idr.fn<(i64) -> (i64)>
    }
    }
    return %r : !idr.fn<(i64) -> (i64)>
  }
  func.func private @Main.pong(%n: i64 {idr.quantity = "w"}) -> !idr.fn<(i64) -> (i64)> {
    %c1 = arith.constant 1 : i64
    %m = arith.subi %n, %c1 : i64
    %g = func.call @Main.ping(%m) : (i64) -> !idr.fn<(i64) -> (i64)>
    %h = idr.closure @Main.q(%g) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)> loc("Main.idr":9:3)
    return %h : !idr.fn<(i64) -> (i64)>
  }
  func.func @Main.main(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
    %c, %w1 = idr.io.get_char %w
    %n = arith.extui %c : i32 to i64
    %f = func.call @Main.ping(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.apply %f(%n) : !idr.fn<(i64) -> (i64)>
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
