// NEEDS-ACCEPTANCE: that grows-nothing holds of @f against the module itself and fails once against the smaller @f pulled out of the SMALL lines.
// RUN: sed -n 's|^// SMALL: ||p' %s > %t.small.mlir
// RUN: idris-mlir-opt %s --idr-expect=holds=grows-nothing=@f:%s -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=grows-nothing=@f:%t.small.mlir -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 1
// A function grows nothing against the module it started in when it holds
// no more operations than it did there: as many as itself, and more than
// the one-operation @f the SMALL lines write.
// CHECK-DAG: error: expected grows-nothing: @f holds {{.*}} operations, and {{.*}} before
// SMALL: idr.program @growth root(@root) stage(first) {
// SMALL:   idr.func @f(%x: i64) -> i64 {
// SMALL:     return %x : i64
// SMALL:   }
// SMALL:   idr.func @root() -> i64 {
// SMALL:     %zero = arith.constant 0 : i64
// SMALL:     return %zero : i64
// SMALL:   }
// SMALL: }
idr.program @growth root(@root) stage(first) {
  idr.func @f(%x: i64) -> i64 {
    %a = arith.addi %x, %x : i64
    %b = arith.muli %a, %a : i64
    return %b : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
