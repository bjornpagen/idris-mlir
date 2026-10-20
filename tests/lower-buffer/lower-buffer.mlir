// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
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
// The bytes are where the offsets say, in the target's order (each
// target's entry is little-endian): the root stores the Bits16 258 as 32
// bits at the offset it reads, loads 16 bits there and one byte on, and
// copies two bytes from there to the last two of the 8-byte buffer, where
// it loads them again. The program, lowered and as written, prints 258, 1
// and 258 for an offset at which the four bytes fit (0 to 4), and crashes
// at the store's guard past it, as the reference at the end (REF), with
// no buffer, does (%differential, on the offsets 0, 4, 5 and 255, and the
// end of input, which reads as 255).
// STDIN: \0000
// STDIN: \0004
// STDIN: \0005
// STDIN: \0377
// STDIN:
idr.program @buffer root(@root) stage(owned) types #idr.types<> {
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c, %w0 = idr.io.get_byte %w
    %i = arith.extui %c : i32 to i64
    %n = arith.constant 8 : i64
    %z = arith.constant 0 : i8
    %buf, %w1 = idr.array.new [%n], %z, %w0 : i8 -> !idr.own<memref<?xi8, #idr.world>>
    %b = idr.borrow %buf : !idr.own<memref<?xi8, #idr.world>>
    %v = arith.constant 258 : i16
    %w2 = idr.call @store(%b, %i, %v, %w1) : (memref<?xi8, #idr.world>, i64, i16, !idr.world) -> !idr.world
    %x, %w3 = idr.call @load(%b, %i, %w2) : (memref<?xi8, #idr.world>, i64, !idr.world) -> (i16, !idr.world)
    %one = arith.constant 1 : i64
    %j = arith.addi %i, %one : i64
    %y, %w4 = idr.call @load(%b, %j, %w3) : (memref<?xi8, #idr.world>, i64, !idr.world) -> (i16, !idr.world)
    %two = arith.constant 2 : i64
    %six = arith.constant 6 : i64
    %w5 = idr.call @copy(%b, %i, %two, %b, %six, %w4) : (memref<?xi8, #idr.world>, i64, i64, memref<?xi8, #idr.world>, i64, !idr.world) -> !idr.world
    %u, %w6 = idr.call @load(%b, %six, %w5) : (memref<?xi8, #idr.world>, i64, !idr.world) -> (i16, !idr.world)
    idr.drop %buf : !idr.own<memref<?xi8, #idr.world>>
    %nl = arith.constant 10 : i32
    %w7 = idr.io.put_sint %x, %w6 : i16
    %w8 = idr.io.put_char %nl, %w7
    %w9 = idr.io.put_sint %y, %w8 : i16
    %w10 = idr.io.put_char %nl, %w9
    %w11 = idr.io.put_sint %u, %w10 : i16
    %w12 = idr.io.put_char %nl, %w11
    return %w12 : !idr.world
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
// The reference:
// REF: idr.program @ref root(@root) stage(higher) types #idr.types<> {
// REF:   idr.func @root(%w: !idr.world) -> !idr.world {
// REF:     %c, %w1 = idr.io.get_byte %w
// REF:     %five = arith.constant 5 : i32
// REF:     %fits = arith.cmpi ult, %c, %five : i32
// REF:     %r = idr.match_lit %fits : i1 -> (i64) {
// REF:     case 1 {
// REF:       %k = arith.constant 258 : i64
// REF:       idr.yield %k : i64
// REF:     }
// REF:     default(%d: i1) {
// REF:       idr.crash "a byte range outside the buffer"
// REF:       ub.unreachable
// REF:     }
// REF:     }
// REF:     %one = arith.constant 1 : i64
// REF:     %nl = arith.constant 10 : i32
// REF:     %w2 = idr.io.put_sint %r, %w1 : i64
// REF:     %w3 = idr.io.put_char %nl, %w2
// REF:     %w4 = idr.io.put_sint %one, %w3 : i64
// REF:     %w5 = idr.io.put_char %nl, %w4
// REF:     %w6 = idr.io.put_sint %r, %w5 : i64
// REF:     %w7 = idr.io.put_char %nl, %w6
// REF:     return %w7 : !idr.world
// REF:   }
// REF: }
