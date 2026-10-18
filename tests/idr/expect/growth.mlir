// NEEDS-ACCEPTANCE: that grows-nothing holds of @f against the module itself, and that the -verify-diagnostics run passes: one error, at @f, against the smaller @f pulled out of the SMALL lines, a module that holds no expectation of its own.
// RUN: sed -n 's|^// SMALL: ||p' %s > %t.small.mlir
// RUN: idris-mlir-opt %s --idr-expect=holds=grows-nothing=@f:%s -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=grows-nothing=@f:%t.small.mlir -verify-diagnostics -o /dev/null
// A function grows nothing against the module it started in when it holds
// no more operations than it did there: as many as itself, and more than
// the one-operation @f the SMALL lines write.
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
  // expected-error @below {{expected grows-nothing: @f holds 3 operations, and 1 before}}
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
