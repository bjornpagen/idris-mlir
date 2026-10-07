// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s
// A word in a buffer is the address idris_rt_buffer_at gives, then the
// target's own load or store at alignment 1. A copy is the runtime's.
// CHECK-LABEL: func.func private @load(
// CHECK: llvm.call @idris_rt_buffer_at({{.*}}) : (!llvm.ptr, i64, i64, i64) -> !llvm.ptr
// CHECK: llvm.load %{{.*}} {alignment = 1 : i64} : !llvm.ptr -> i16
// CHECK-LABEL: func.func private @store(
// CHECK: llvm.call @idris_rt_buffer_at({{.*}}) : (!llvm.ptr, i64, i64, i64) -> !llvm.ptr
// CHECK: llvm.store %{{.*}}, %{{.*}} {alignment = 1 : i64} : i32, !llvm.ptr
// CHECK-LABEL: func.func private @copy(
// CHECK: llvm.call @idris_rt_io_buffer_copy({{.*}}) : (!llvm.ptr, i64, i64, i64, !llvm.ptr, i64, i64) -> ()
module attributes {idr.program, idr.stage = "owned"} {
  func.func @root(%w: !idr.world) -> !idr.world {
    %n = arith.constant 8 : i64
    %z = arith.constant 0 : i8
    %buf, %w1 = idr.array.new %n, %z, %w : i8 -> !idr.own<memref<?xi8>>
    %b = idr.borrow %buf : !idr.own<memref<?xi8>>
    %i = arith.constant 1 : i64
    %v, %w2 = func.call @load(%b, %i, %w1) : (memref<?xi8>, i64, !idr.world) -> (i16, !idr.world)
    %w3 = func.call @store(%b, %i, %v, %w2) : (memref<?xi8>, i64, i16, !idr.world) -> !idr.world
    %w4 = func.call @copy(%b, %i, %i, %b, %i, %w3) : (memref<?xi8>, i64, i64, memref<?xi8>, i64, !idr.world) -> !idr.world
    idr.drop %buf : !idr.own<memref<?xi8>>
    return %w4 : !idr.world
  }
  func.func private @load(%buf: memref<?xi8>, %i: i64, %w: !idr.world) -> (i16, !idr.world) {
    %v, %w1 = idr.io.buffer_load %buf[%i], %w : memref<?xi8> -> i16
    return %v, %w1 : i16, !idr.world
  }
  func.func private @store(%buf: memref<?xi8>, %i: i64, %v: i16, %w: !idr.world) -> !idr.world {
    %wide = arith.extsi %v : i16 to i32
    %w1 = idr.io.buffer_store %buf[%i], %wide, %w : memref<?xi8>, i32
    return %w1 : !idr.world
  }
  func.func private @copy(%src: memref<?xi8>, %so: i64, %n: i64, %dst: memref<?xi8>, %do: i64, %w: !idr.world) -> !idr.world {
    %w1 = idr.io.buffer_copy %src[%so, %n], %dst[%do], %w : memref<?xi8>, memref<?xi8>
    return %w1 : !idr.world
  }
}
