// NEEDS-ACCEPTANCE: that reaches follows calls from body to body to @leaf, two steps from @top, and fails once for @apart, which nothing @top calls names.
// RUN: idris-mlir-opt %s --idr-expect=holds=reaches=@top:@leaf -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=reaches=@top:@apart -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 1
// A run of @top may run @leaf, through @mid: the functions its body names,
// followed from body to body, include it. @apart is no part of that chain.
// CHECK-DAG: error: expected reaches: @top reaches no function made from {{.*}}
idr.program @reaches root(@root) stage(first) {
  idr.func @leaf(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @mid(%x: i64) -> i64 {
    %y = idr.call @leaf(%x) : (i64) -> i64
    return %y : i64
  }
  idr.func @top(%x: i64) -> i64 {
    %y = idr.call @mid(%x) : (i64) -> i64
    return %y : i64
  }
  idr.func @apart(%x: i64) -> i64 {
    return %x : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
