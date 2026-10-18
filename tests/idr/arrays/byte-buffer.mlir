// NEEDS-ACCEPTANCE: idr.io.buffer_load of an array of i32 a world orders is refused by its buffer operand's constraint (Idr_ByteBuffer), whose message names the type given; a buffer of i8 is accepted.
// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A buffer holds bytes: the buffer operand of every buffer and byte
// transfer op is an array a world orders of one dimension of i8, which ODS
// checks.

idr.program @"byte-buffer" root(@root) stage(first) {
  idr.func @f(%buf: memref<?xi32, #idr.world>, %at: i64, %w: !idr.world) -> (i16, !idr.world) {
    // expected-error @+1 {{but got 'memref<?xi32, #idr.world>'}}
    %v, %w1 = idr.io.buffer_load %buf[%at], %w : memref<?xi32, #idr.world> -> i16
    return %v, %w1 : i16, !idr.world
  }
  // The program's root, which the function above is no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @"byte-buffer" root(@root) stage(first) {
  idr.func @f(%buf: memref<?xi8, #idr.world>, %at: i64, %w: !idr.world) -> (i16, !idr.world) {
    %v, %w1 = idr.io.buffer_load %buf[%at], %w : memref<?xi8, #idr.world> -> i16
    return %v, %w1 : i16, !idr.world
  }
  // The program's root, which the function above is no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
