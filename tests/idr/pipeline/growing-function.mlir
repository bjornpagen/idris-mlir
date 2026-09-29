// RUN: idris-mlir-opt %s --idr-simplify -o %t.mlir
// RUN: FileCheck %s < %t.mlir
// iter f n x = if n == 0 then f x else iter (\y => f y + 1) (n - 1) x:
// the closure grows on every iteration, so f is no fixed parameter of
// @iter, and the loop is not specialized on it however static the first
// closure is: the simplify loop ends with one @iter, which takes closures.
// CHECK-NOT: $spec$
// CHECK: func.func private @Main.iter(%{{[a-z0-9_]+}}: !idr.fn<(i64) -> (i64)>
// CHECK-NOT: $spec$
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
