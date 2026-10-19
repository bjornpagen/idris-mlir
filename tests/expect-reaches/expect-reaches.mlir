// RUN: idris-mlir-opt %s --idr-expect=holds=reaches=@top:@leaf -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=reaches=@top:@apart -verify-diagnostics -o /dev/null
// A run of @top may run @leaf, through @mid: the functions its body names,
// followed from body to body, include it. @apart is no part of that chain.
idr.program @reaches root(@root) stage(first) {
  idr.func @leaf(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @mid(%x: i64) -> i64 {
    %y = idr.call @leaf(%x) : (i64) -> i64
    return %y : i64
  }
  // expected-error @below {{expected reaches: }}
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
