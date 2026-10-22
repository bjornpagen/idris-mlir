// RUN: idris-mlir-opt %s --idr-expect=holds=in-place=@fills -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=in-place=@copies,in-place=@scalar,moves-out=@fills,structured-loops=@fills -verify-diagnostics -o /dev/null
// What the arrays leave once they are buffers. @fills writes its buffer in
// place; @copies copies one into a buffer made for the copy, which a write
// that could not be in place does; @scalar has no buffer, so nothing can
// be said of one. No element of an array is rebuilt in its place in
// @fills, and no structured op is there.
module {
  // expected-error @below {{expected moves-out: }}
  // expected-error @below {{expected structured-loops: }}
  func.func @fills(%b: memref<4xi64>, %x: i64) {
    %zero = arith.constant 0 : index
    memref.store %x, %b[%zero] : memref<4xi64>
    return
  }
  func.func @copies(%b: memref<4xi64>) -> memref<4xi64> {
    %c = memref.alloc() : memref<4xi64>
    // expected-error @below {{expected in-place: }}
    memref.copy %b, %c : memref<4xi64> to memref<4xi64>
    return %c : memref<4xi64>
  }
  // expected-error @below {{expected in-place: }}
  func.func @scalar(%x: i64) -> i64 {
    return %x : i64
  }
}
