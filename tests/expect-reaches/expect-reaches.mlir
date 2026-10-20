// RUN: idris-mlir-opt %s --idr-expect=holds=reaches=@top:@leaf,reaches=@top:@mid,reaches=@again:@again -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=reaches=@top:@apart,reaches=@leaf:@leaf -verify-diagnostics -o /dev/null
// A run of @top may run @leaf, through @mid, and @mid itself: the
// functions its body names, followed from body to body, include each.
// @apart is no part of that chain. A function reaches itself only through
// a body that names it: @again, which calls itself, does; @leaf, which
// calls nothing, does not.
idr.program @reaches root(@root) stage(first) types #idr.types<> {
  // expected-error @below {{expected reaches: }}
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
  idr.func @again(%x: i64) -> i64 {
    %y = idr.call @again(%x) : (i64) -> i64
    return %y : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
