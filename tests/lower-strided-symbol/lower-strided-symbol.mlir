// RUN: idris-mlir-opt %s --idr-lower '--idr-expect=holds=lowered,signature=@rows:(!llvm.ptr,i64,i64,i64,index,index)->i64' -o /dev/null
// The descriptor of @rows's buffer is its cell, its two sizes and the
// stride of its rows, which the map's symbol leaves to the value; the
// stride of its columns is 1 and its offset 0, which the type fixes.
idr.program @"strided-symbol" root(@root) stage(owned) {
  idr.func @rows(%m: memref<?x?xi64, affine_map<(d0, d1)[s0] -> (d0 * s0 + d1)>>, %i: index, %j: index) -> i64 {
    %v = memref.load %m[%i, %j] : memref<?x?xi64, affine_map<(d0, d1)[s0] -> (d0 * s0 + d1)>>
    return %v : i64
  }
  // The program's root, which @rows is no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
