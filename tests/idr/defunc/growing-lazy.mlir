// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: %status 1 idris-mlir-opt %s --idr-defunctionalize --idr-check-profile -o %t.out 2> %t.err
// RUN: FileCheck %s --check-prefix=ERR < %t.err
// rule: ELIM-CLOS-1, PROF-HEAP-2, SEM-LAZY-1
// later 0 = Delay 1; later n = Delay (force (later (n - 1))): each level
// suspends a computation that captures the suspension below, so no finite
// sum stands for the Lazy type, which stays a closure, and the profile
// rejects the suspension built at runtime.
// CHECK-NOT: idr.data @fn$
// CHECK-LABEL: func.func private @Main.later(
// CHECK-SAME: -> !idr.fn<() -> (i64)>
// CHECK: idr.closure @Main.force(%{{.*}}) : (!idr.fn<() -> (i64)>) -> !idr.fn<() -> (i64)>
// ERR: Main.idr:13:9: error: unsupported (PROF-HEAP-2){{.*}}@Main.force
// ERR-NOT: error:
module attributes {idr.program} {
  func.func private @Main.one() -> i64 attributes {idr.total} {
    %c1 = arith.constant 1 : i64
    return %c1 : i64
  }
  func.func private @Main.force(%l: !idr.fn<() -> (i64)> {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %c1 = arith.constant 1 : i64
    %v = idr.apply %l() : !idr.fn<() -> (i64)>
    %r = arith.addi %v, %c1 : i64
    return %r : i64
  }
  func.func private @Main.later(%n: i64 {idr.quantity = "w"}) -> !idr.fn<() -> (i64)> {
    %r = idr.match_lit %n : i64 -> (!idr.fn<() -> (i64)>) {
    case 0 {
      %f = idr.closure @Main.one() : () -> !idr.fn<() -> (i64)>
      idr.yield %f : !idr.fn<() -> (i64)>
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %g = func.call @Main.later(%m) : (i64) -> !idr.fn<() -> (i64)>
      %h = idr.closure @Main.force(%g) : (!idr.fn<() -> (i64)>) -> !idr.fn<() -> (i64)> loc("Main.idr":13:9)
      idr.yield %h : !idr.fn<() -> (i64)>
    }
    }
    return %r : !idr.fn<() -> (i64)>
  }
  func.func @Main.main(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
    %c, %w1 = idr.io.get_char %w
    %n = arith.extui %c : i32 to i64
    %l = func.call @Main.later(%n) : (i64) -> !idr.fn<() -> (i64)>
    %s = idr.apply %l() : !idr.fn<() -> (i64)>
    %w2 = idr.io.put_int signed %s, %w1 : i64
    return %w2 : !idr.world
  }
}
