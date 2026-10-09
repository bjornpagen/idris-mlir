// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s --implicit-check-not=idris_rt_buffer_at
// A word in a buffer is at its offset from the buffer's first byte, read or
// written by the target's own load or store at alignment 1. The guard of
// the offset crashes unless the word's bytes lie in the buffer, and the
// access then tests nothing and asks the runtime for nothing. A copy is
// the runtime's, after the guards of both of its ranges.
// CHECK-LABEL: func.func private @load(
// CHECK: scf.if
// CHECK: llvm.call @idris_rt_crash(
// CHECK: }
// CHECK-NOT: llvm.call
// CHECK: llvm.load %{{.*}} <alignment = 1> : !llvm.ptr -> i16
// CHECK-NOT: llvm.call
// CHECK: return
// CHECK-LABEL: func.func private @store(
// CHECK: scf.if
// CHECK: llvm.call @idris_rt_crash(
// CHECK: }
// CHECK-NOT: llvm.call
// CHECK: llvm.store %{{.*}}, %{{.*}} <alignment = 1> : i32, !llvm.ptr
// CHECK-NOT: llvm.call
// CHECK: return
// CHECK-LABEL: func.func private @copy(
// CHECK: llvm.call @idris_rt_crash(
// CHECK: llvm.call @idris_rt_crash(
// CHECK: llvm.call @idris_rt_io_buffer_copy({{.*}}) : (!llvm.ptr, i64, i64, i64, !llvm.ptr, i64, i64) -> ()
module attributes {idr.program} {
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
    %c0 = arith.constant 0 : index
    %d = memref.dim %buf, %c0 : memref<?xi8>
    %size = arith.index_cast %d : index to i64
    %two = arith.constant 2 : i64
    %at = idr.check.range %i, %two, %size, "a byte range outside the buffer"
    %v, %w1 = idr.io.buffer_load %buf[%at], %w : memref<?xi8> -> i16
    return %v, %w1 : i16, !idr.world
  }
  func.func private @store(%buf: memref<?xi8>, %i: i64, %v: i16, %w: !idr.world) -> !idr.world {
    %wide = arith.extsi %v : i16 to i32
    %c0 = arith.constant 0 : index
    %d = memref.dim %buf, %c0 : memref<?xi8>
    %size = arith.index_cast %d : index to i64
    %four = arith.constant 4 : i64
    %at = idr.check.range %i, %four, %size, "a byte range outside the buffer"
    %w1 = idr.io.buffer_store %buf[%at], %wide, %w : memref<?xi8>, i32
    return %w1 : !idr.world
  }
  func.func private @copy(%src: memref<?xi8>, %so: i64, %n: i64, %dst: memref<?xi8>, %do: i64, %w: !idr.world) -> !idr.world {
    %c0 = arith.constant 0 : index
    %ds = memref.dim %src, %c0 : memref<?xi8>
    %ss = arith.index_cast %ds : index to i64
    %from = idr.check.range %so, %n, %ss, "a byte range outside the buffer"
    %dd = memref.dim %dst, %c0 : memref<?xi8>
    %sd = arith.index_cast %dd : index to i64
    %to = idr.check.range %do, %n, %sd, "a byte range outside the buffer"
    %w1 = idr.io.buffer_copy %src[%from, %n], %dst[%to], %w : memref<?xi8>, memref<?xi8>
    return %w1 : !idr.world
  }
}
