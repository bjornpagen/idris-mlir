// RUN: %status 1 idris-mlir-opt %s --idr-simplify="clone-limit=4" --idr-defunctionalize --canonicalize --idr-tail-loops --idr-check-profile -o %t.mlir 2> %t.err
// RUN: FileCheck %s < %t.err
// iter f n x = if n == 0 then f x else iter (\y => f y + 1) (n - 1) x:
// the clone of @iter passes itself a larger closure, which contains its own:
// specialization stops at once, and the closure that @iter
// builds survives in the stopped callee, whose self tail call is a loop by
// the time the profile is checked, which rejects it.
// CHECK: Main.idr:8:3: error: unsupported (PROF-HEAP-4){{.*}}@Main.after{{.*}}@Main.iter
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
