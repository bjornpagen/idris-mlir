// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-optimize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=one-clone=@Main.iter -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=not-called=@Main.iter -o /dev/null
// iter f n x = if n == 0 then f x else iter (\y => f y + 1) (n - 1) x:
// the closure grows on every iteration, so f is no static parameter of
// @iter, and the loop is not specialized on it however static the first
// closure is: @iter is still called, and every call reaches one function.
idr.program @"growing-function" root(@Main.main) stage(higher) {
  idr.func @Main.inc(%x: i64) -> i64 attributes {total} {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    return %y : i64
  }
  idr.func @Main.after(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 attributes {total} {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    %c1 = arith.constant 1 : i64
    %z = arith.addi %y, %c1 : i64
    return %z : i64
  }
  idr.func @Main.iter(%f: !idr.fn<(i64) -> (i64)>, %n: i64, %x: i64) -> i64 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      idr.yield %y : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %g = idr.closure @Main.after(%f) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)> loc("Main.idr":8:3)
      %y = idr.call @Main.iter(%g, %m, %x) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %f = idr.closure @Main.inc() : () -> !idr.fn<(i64) -> (i64)>
    %c0 = arith.constant 0 : i64
    %r = idr.call @Main.iter(%f, %n, %c0) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
