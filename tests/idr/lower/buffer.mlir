// NEEDS-ACCEPTANCE: the runtime's copy takes each buffer as its cell alone (driver-runtime-T2), and a word's address is upstream's strided address over the buffer's descriptor (mlir-15); the calls are as before.
// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,signature=@load:(!llvm.ptr,i64,i64)->i16,signature=@store:(!llvm.ptr,i64,i64,i16)->(),crash-sites=@load:1,crash-sites=@store:1,crash-sites=@copy:2' -o /dev/null
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=calls-only=@load:[@idris_rt_crash],calls-only=@store:[@idris_rt_crash],call-order=@copy:[@idris_rt_crash,@idris_rt_crash,@idris_rt_io_buffer_copy],calls-only=@copy:[@idris_rt_crash,@idris_rt_io_buffer_copy]' -o /dev/null
// A word in a buffer is at its offset from the buffer's first byte, read or
// written by the target's own load or store at alignment 1. The guard of
// the offset crashes unless the word's bytes lie in the buffer, and the
// access then tests nothing and asks the runtime for nothing but that
// crash. A copy is the runtime's, after the guards of both of its ranges,
// and the runtime is given each buffer as its cell, which holds its size
// and its bytes, so no address in a buffer is asked of it: the arguments
// of the runtime's copy are its C interface.
idr.program @buffer root(@root) stage(owned) {
  idr.func @root(%w: !idr.world) -> !idr.world {
    %n = arith.constant 8 : i64
    %z = arith.constant 0 : i8
    %buf, %w1 = idr.array.new [%n], %z, %w : i8 -> !idr.own<memref<?xi8, #idr.world>>
    %b = idr.borrow %buf : !idr.own<memref<?xi8, #idr.world>>
    %i = arith.constant 1 : i64
    %v, %w2 = idr.call @load(%b, %i, %w1) : (memref<?xi8, #idr.world>, i64, !idr.world) -> (i16, !idr.world)
    %w3 = idr.call @store(%b, %i, %v, %w2) : (memref<?xi8, #idr.world>, i64, i16, !idr.world) -> !idr.world
    %w4 = idr.call @copy(%b, %i, %i, %b, %i, %w3) : (memref<?xi8, #idr.world>, i64, i64, memref<?xi8, #idr.world>, i64, !idr.world) -> !idr.world
    idr.drop %buf : !idr.own<memref<?xi8, #idr.world>>
    return %w4 : !idr.world
  }
  idr.func @load(%buf: memref<?xi8, #idr.world>, %i: i64, %w: !idr.world) -> (i16, !idr.world) {
    %c0 = arith.constant 0 : index
    %d = memref.dim %buf, %c0 : memref<?xi8, #idr.world>
    %size = arith.index_cast %d : index to i64
    %two = arith.constant 2 : i64
    %at = idr.check.range %i, %two, %size, "a byte range outside the buffer"
    %v, %w1 = idr.io.buffer_load %buf[%at], %w : memref<?xi8, #idr.world> -> i16
    return %v, %w1 : i16, !idr.world
  }
  idr.func @store(%buf: memref<?xi8, #idr.world>, %i: i64, %v: i16, %w: !idr.world) -> !idr.world {
    %wide = arith.extsi %v : i16 to i32
    %c0 = arith.constant 0 : index
    %d = memref.dim %buf, %c0 : memref<?xi8, #idr.world>
    %size = arith.index_cast %d : index to i64
    %four = arith.constant 4 : i64
    %at = idr.check.range %i, %four, %size, "a byte range outside the buffer"
    %w1 = idr.io.buffer_store %buf[%at], %wide, %w : memref<?xi8, #idr.world>, i32
    return %w1 : !idr.world
  }
  idr.func @copy(%src: memref<?xi8, #idr.world>, %so: i64, %n: i64, %dst: memref<?xi8, #idr.world>, %do: i64, %w: !idr.world) -> !idr.world {
    %c0 = arith.constant 0 : index
    %ds = memref.dim %src, %c0 : memref<?xi8, #idr.world>
    %ss = arith.index_cast %ds : index to i64
    %from = idr.check.range %so, %n, %ss, "a byte range outside the buffer"
    %dd = memref.dim %dst, %c0 : memref<?xi8, #idr.world>
    %sd = arith.index_cast %dd : index to i64
    %to = idr.check.range %do, %n, %sd, "a byte range outside the buffer"
    %w1 = idr.io.buffer_copy %src[%from, %n], %dst[%to], %w : memref<?xi8, #idr.world>, memref<?xi8, #idr.world>
    return %w1 : !idr.world
  }
}
