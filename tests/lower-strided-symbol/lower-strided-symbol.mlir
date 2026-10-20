// RUN: idris-mlir-opt %s --idr-lower '--idr-expect=holds=lowered,signature=@rows:(!llvm.ptr,i64,i64,i64,index,index)->i64' -o /dev/null
// RUN: sed 's/memref<?x?xi64, affine_map<(d0, d1)\[s0\] -> (d0 \* s0 + d1)>>/memref<?x?xi64>/g' %s > %t.dense.mlir
// RUN: idris-mlir-opt %t.dense.mlir --idr-lower '--idr-expect=holds=lowered,signature=@rows:(!llvm.ptr,i64,i64,index,index)->i64' -o /dev/null
// RUN: sed 's/affine_map<(d0, d1)\[s0\] -> (d0 \* s0 + d1)>/strided<[?, 1], offset: ?>/g' %s > %t.offset.mlir
// RUN: idris-mlir-opt %t.offset.mlir --idr-lower '--idr-expect=holds=lowered,signature=@rows:(!llvm.ptr,i64,i64,i64,i64,index,index)->i64' -o /dev/null
// The descriptor of @rows's buffer is its cell, its two sizes and the
// stride of its rows, which the map's symbol leaves to the value; the
// stride of its columns is 1 and its offset 0, which the type fixes. The
// descriptor holds what the type leaves open and nothing it fixes: the
// same buffer with no map (the second RUN line's), whose row stride is its
// second size, has no stride beside its sizes, and one whose offset is
// open too (the fourth's) has both.
idr.program @"strided-symbol" root(@root) stage(owned) types #idr.types<> {
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
