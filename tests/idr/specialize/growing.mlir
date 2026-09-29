// RUN: idris-mlir-opt %s --idr-specialize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// iter f n x = if n == 0 then f x else iter (\y => f (f y)) (n - 1) x: the
// closure grows on every iteration, so f is no fixed parameter and the
// static closure at the call stays a runtime value: specializing on it
// would make a clone per iteration.
// CHECK-NOT: $spec$
// CHECK-LABEL: func.func private @use(
// CHECK: %[[F:.*]] = idr.closure @inc()
// CHECK: call @iter(%[[F]], %{{.*}}, %{{.*}})
module attributes {idr.program} {
  func.func private @inc(%x: i64) -> i64 attributes {idr.total} {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    return %y : i64
  }
  func.func private @twice(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    %z = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
    return %z : i64
  }
  func.func private @iter(%f: !idr.fn<(i64) -> (i64)>, %n: i64, %x: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      idr.yield %y : i64
    }
    default {
      %g = idr.closure @twice(%f) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)>
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = func.call @iter(%g, %m, %x) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  func.func private @use(%n: i64, %x: i64) -> i64 {
    %f = idr.closure @inc() : () -> !idr.fn<(i64) -> (i64)>
    %r = func.call @iter(%f, %n, %x) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
    return %r : i64
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
