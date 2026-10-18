// NEEDS-ACCEPTANCE: that typed-reads holds of @typed, and that the -verify-diagnostics run passes: @guarded fails at its tensor.extract of a checked index, and @none, which accesses no tensor, at the function.
// RUN: idris-mlir-opt %s --idr-expect=holds=typed-reads=@typed -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=typed-reads=@guarded,typed-reads=@none -verify-diagnostics -o /dev/null
// An access at an index Idris typed below its extent takes the index as it
// is: no guard stands between them (@typed). An index that went through a
// guard, through the casts that only change its width, is a checked
// access (@guarded). A function that accesses no tensor fails, so the
// property cannot hold of the wrong function.
idr.program @"typed-reads" root(@root) stage(first) {
  idr.func @typed(%x: tensor<?xi64>, %i: index) -> (i64, tensor<?xi64>) {
    %v = tensor.extract %x[%i] : tensor<?xi64>
    %y = tensor.insert %v into %x[%i] : tensor<?xi64>
    return %v, %y : i64, tensor<?xi64>
  }
  idr.func @guarded(%x: tensor<?xi64>, %i: i64) -> i64 {
    %c0 = arith.constant 0 : index
    %d = tensor.dim %x, %c0 : tensor<?xi64>
    %n = arith.index_cast %d : index to i64
    %g = idr.check.in_bounds %i, %x, "array index out of bounds" : tensor<?xi64>
    %j = arith.index_cast %g : i64 to index
    // expected-error @below {{expected typed-reads: tensor.extract in @guarded takes an index idr.check.in_bounds checked}}
    %v = tensor.extract %x[%j] : tensor<?xi64>
    return %v : i64
  }
  // expected-error @below {{expected typed-reads: no tensor is accessed in @none}}
  idr.func @none(%x: i64) -> i64 {
    return %x : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
