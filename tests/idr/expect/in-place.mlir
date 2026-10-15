// RUN: idris-mlir-opt %s --idr-expect=holds=in-place=@written,in-place=@appended -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=in-place=@copied -o /dev/null 2> %t.copied.err
// RUN: FileCheck %s --check-prefix=COPIED < %t.copied.err
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=in-place=@none -o /dev/null 2> %t.none.err
// RUN: FileCheck %s --check-prefix=NONE < %t.none.err
// NEEDS-ACCEPTANCE: that idr::bufferize::copies answers for this copy into a fresh memref.alloc, as C15 defines it.
// After bufferization nothing copies a buffer: a write lands in the buffer
// it was given (@written). A copy into a cell made for it is a write that
// could not be in place (@copied); a copy into a view of a live buffer is
// what the program asked, an array appended into its place (@appended),
// and no lost write. A function without a buffer fails, so the property
// cannot hold of a module before bufferization.
// COPIED: error: expected in-place: memref.copy copies a buffer in @copied
// NONE: error: expected in-place: no buffer in @none
module {
  idr.func private @written(%m: memref<?xi64>, %i: index, %v: i64) -> memref<?xi64> {
    memref.store %v, %m[%i] : memref<?xi64>
    return %m : memref<?xi64>
  }
  idr.func private @copied(%m: memref<?xi64>, %i: index, %v: i64) -> memref<?xi64> {
    %c0 = arith.constant 0 : index
    %n = memref.dim %m, %c0 : memref<?xi64>
    %a = memref.alloc(%n) : memref<?xi64>
    memref.copy %m, %a : memref<?xi64> to memref<?xi64>
    memref.store %v, %a[%i] : memref<?xi64>
    return %a : memref<?xi64>
  }
  idr.func private @appended(%m: memref<?xi64>, %x: memref<?xi64>, %at: index) -> memref<?xi64> {
    %c0 = arith.constant 0 : index
    %n = memref.dim %x, %c0 : memref<?xi64>
    %view = memref.subview %m[%at] [%n] [1] : memref<?xi64> to memref<?xi64, strided<[1], offset: ?>>
    memref.copy %x, %view : memref<?xi64> to memref<?xi64, strided<[1], offset: ?>>
    return %m : memref<?xi64>
  }
  idr.func private @none(%x: i64) -> i64 {
    return %x : i64
  }
}
