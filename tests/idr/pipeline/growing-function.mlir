// RUN: %status 1 idris-mlir-opt %s --idr-simplify="clone-limit=4 skip-unregistered=true" --idr-defunctionalize --canonicalize --idr-tail-loops --idr-check-profile -o %t.mlir 2> %t.err
// RUN: FileCheck %s < %t.err
// rule: PROF-HEAP-4, ELIM-SPEC-1, DIAG-HEAP-1
// iter f n x = if n == 0 then f x else iter (\y => f y + 1) (n - 1) x:
// each clone of @iter passes itself a larger closure, so specialization
// goes on until the clone limit stops it, and the closure that @iter builds
// survives in the stopped callee, whose self tail call is a loop by the
// time the profile is checked: PROF-HEAP-4.
// Note: idr-eval (the lowering package) is not in this branch yet, so the
// round runs without it (skip-unregistered, which only tests set).
// CHECK: Main.idr:8:3: error: unsupported (PROF-HEAP-4): function value grows: a closure of @Main.after is built in or passed to @Main.iter, whose specialization stopped
// CHECK-NOT: error:
module attributes {idr.program} {
  func.func private @Main.inc(%x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    return %y : i64
  }
  func.func private @Main.after(%f: !idr.fn<(i64) -> (i64)> {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    %c1 = arith.constant 1 : i64
    %z = arith.addi %y, %c1 : i64
    return %z : i64
  }
  func.func private @Main.iter(%f: !idr.fn<(i64) -> (i64)> {idr.quantity = "w"}, %n: i64 {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      idr.yield %y : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %g = idr.closure @Main.after(%f) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)> loc("Main.idr":8:3)
      %y = func.call @Main.iter(%g, %m, %x) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  func.func @Main.main(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
    %c, %w1 = idr.io.get_char %w
    %n = arith.extui %c : i32 to i64
    %f = idr.closure @Main.inc() : () -> !idr.fn<(i64) -> (i64)>
    %c0 = arith.constant 0 : i64
    %r = func.call @Main.iter(%f, %n, %c0) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
