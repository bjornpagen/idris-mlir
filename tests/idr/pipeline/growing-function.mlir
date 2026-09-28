// RUN: %status 1 idris-mlir-opt %s --idr-simplify="clone-limit=4 skip-unregistered=true" --idr-defunctionalize --canonicalize --idr-check-profile -o %t.mlir 2> %t.err
// RUN: FileCheck %s < %t.err
// rule: PROF-HEAP-4, ELIM-SPEC-1, DIAG-HEAP-1
// iter f n x = if n == 0 then f x else iter (\y => f (f y)) (n - 1) x:
// each clone of @iter passes itself a larger closure, so specialization
// goes on until the clone limit stops it, and the closure that @iter builds
// survives into the stopped callee: PROF-HEAP-4.
// Note: idr-eval (the lowering package) is not in this branch yet, so the
// round runs without it (skip-unregistered, which only tests set).
// CHECK: Main.idr:8:3: error: unsupported (PROF-HEAP-4): function value grows: a closure of @Main.twice is passed to @Main.iter, whose specialization stopped at the clone limit
// CHECK-NOT: error:
module attributes {idr.program} {
  func.func private @Main.inc(%x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    return %y : i64
  }
  func.func private @Main.twice(%f: !idr.fn<(i64) -> (i64)> {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    %z = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
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
      %g = idr.closure @Main.twice(%f) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)> loc("Main.idr":8:3)
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
