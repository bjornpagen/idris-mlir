// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-optimize -o %t.mlir
// RUN: FileCheck %s --implicit-check-not=@iter.spec. < %t.mlir
// iter f n x = if n == 0 then f x else iter (\y => f (f y)) (n - 1) x: the
// closure grows on every iteration, so f is no fixed parameter and the
// static constructor at the call stays a runtime value: specializing on it
// would make a copy per iteration. @iter is on a cycle, so its call stays.
// CHECK: call @iter(
module {
  idr.func private @inc(%x: i64) -> i64 attributes {total} {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    return %y : i64
  }
  idr.func private @twice(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    %z = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
    return %z : i64
  }
  idr.func private @iter(%f: !idr.fn<(i64) -> (i64)>, %n: i64, %x: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      idr.yield %y : i64
    }
    default {
      %g = idr.closure @twice(%f) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)>
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = idr.call @iter(%g, %m, %x) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %f = idr.closure @inc() : () -> !idr.fn<(i64) -> (i64)>
    %r = idr.call @iter(%f, %x, %x) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
