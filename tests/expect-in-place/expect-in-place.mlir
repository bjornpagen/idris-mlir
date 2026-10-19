// RUN: idris-mlir-opt %s --idr-expect=holds=in-place=@written,in-place=@appended -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=in-place=@copied,in-place=@none -verify-diagnostics -o /dev/null
// After bufferization nothing copies a buffer: a write lands in the buffer
// it was given (@written). A copy into a cell made for it is a write that
// could not be in place (@copied); a copy into a view of a live buffer is
// what the program asked, an array appended into its place (@appended),
// and no lost write. A function without a buffer fails, so the property
// cannot hold of a module before bufferization.
idr.program @"in-place" root(@root) stage(first) {
  idr.func @written(%m: memref<?xi64>, %i: index, %v: i64) -> memref<?xi64> {
    memref.store %v, %m[%i] : memref<?xi64>
    return %m : memref<?xi64>
  }
  idr.func @copied(%m: memref<?xi64>, %i: index, %v: i64) -> memref<?xi64> {
    %c0 = arith.constant 0 : index
    %n = memref.dim %m, %c0 : memref<?xi64>
    %a = memref.alloc(%n) : memref<?xi64>
    // expected-error @below {{expected in-place: }}
    memref.copy %m, %a : memref<?xi64> to memref<?xi64>
    memref.store %v, %a[%i] : memref<?xi64>
    return %a : memref<?xi64>
  }
  idr.func @appended(%m: memref<?xi64>, %x: memref<?xi64>, %at: index) -> memref<?xi64> {
    %c0 = arith.constant 0 : index
    %n = memref.dim %x, %c0 : memref<?xi64>
    %view = memref.subview %m[%at] [%n] [1] : memref<?xi64> to memref<?xi64, strided<[1], offset: ?>>
    memref.copy %x, %view : memref<?xi64> to memref<?xi64, strided<[1], offset: ?>>
    return %m : memref<?xi64>
  }
  // expected-error @below {{expected in-place: }}
  idr.func @none(%x: i64) -> i64 {
    return %x : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
