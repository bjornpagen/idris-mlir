// NEEDS-ACCEPTANCE: that effects reads each function's declared set, which covers its body as the program's verifier asks, and fails once for each function given another set.
// RUN: idris-mlir-opt %s --idr-expect=holds=effects=@pure:none,effects=@divides:crash,effects=@unsolved:io+crash+diverge -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=effects=@pure:crash,effects=@divides:none -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 2
// What a function may do is the set it holds: none for one that only
// computes and is total (@pure), crash for one whose guard may (@divides),
// and everything for one no pass solved, which holds no set (@unsolved).
// CHECK-DAG: error: expected effects: @pure may do {{.*}}, not {{.*}}
// CHECK-DAG: error: expected effects: @divides may do {{.*}}, not {{.*}}
idr.program @"solved-effects" root(@root) stage(first) {
  idr.func @pure(%x: i64) -> i64 attributes {total, effects = #idr.effects<none>} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @divides(%x: i64, %y: i64) -> i64 attributes {total, effects = #idr.effects<crash>} {
    %g = idr.check.nonzero %y, "division by zero" : i64
    %q = idr.div signed %x, %g : i64
    return %q : i64
  }
  idr.func @unsolved(%x: i64) -> i64 {
    return %x : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
