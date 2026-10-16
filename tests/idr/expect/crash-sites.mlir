// NEEDS-ACCEPTANCE: that crash-sites counts a guard and a crash as one place each and nothing else, failing once for each function given another count.
// RUN: idris-mlir-opt %s --idr-expect=holds=crash-sites=@divides:1,crash-sites=@never:1,crash-sites=@safe:0 -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=crash-sites=@divides:0,crash-sites=@safe:1 -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 2
// A place that may crash is a guard, which crashes when its condition
// fails (@divides), or an op that never returns (@never); a function that
// only computes has none (@safe).
// CHECK-DAG: error: expected crash-sites: @divides may crash at {{.*}} places, not {{.*}}
// CHECK-DAG: error: expected crash-sites: @safe may crash at {{.*}} places, not {{.*}}
idr.program @"crash-sites" root(@root) stage(first) {
  idr.func @divides(%x: i64, %y: i64) -> i64 {
    %g = idr.check.nonzero %y, "division by zero" : i64
    %q = idr.div signed %x, %g : i64
    return %q : i64
  }
  idr.func @never(%x: i64) -> i64 {
    idr.crash "unhandled input for never"
    ub.unreachable
  }
  idr.func @safe(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
