// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,crash-sites=@proven:0,calls-only=@proven:[],crash-sites=@checked:1,calls-only=@checked:[@idris_rt_crash]' -o /dev/null
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
// An access to an array a world orders is tested by its guard alone. One
// with no guard (a guard folded where its index shows the condition)
// lowers with no test against the size and nothing that crashes; one that
// keeps its guard may crash there, once, and the access tests nothing of
// its own. The root fills 3 elements with the byte x it reads, gives
// @proven the index x mod 3, which is in bounds, and @checked x itself,
// then reads the element at x mod 3: the program, lowered and as written,
// prints x for x below 3 and crashes at @checked's guard from 3 on, as the
// reference at the end (REF), with no array, does (%differential, on 0,
// 2, 3, 255 and the end of input).
// STDIN: \0000
// STDIN: \0002
// STDIN: \0003
// STDIN: \0377
// STDIN:
idr.program @"in-bounds" root(@root) stage(owned) {
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c, %wc = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %n = arith.constant 3 : i64
    %j = arith.remui %x, %n : i64
    %o, %w0 = idr.array.new [%n], %x, %wc : i64 -> !idr.own<memref<?xi64, #idr.world>>
    %a = idr.borrow %o : !idr.own<memref<?xi64, #idr.world>>
    %w1 = idr.call @proven(%a, %j, %w0) : (memref<?xi64, #idr.world>, i64, !idr.world) -> !idr.world
    %w2 = idr.call @checked(%a, %x, %w1) : (memref<?xi64, #idr.world>, i64, !idr.world) -> !idr.world
    %v, %w3 = idr.array.get %a[%j], %w2 : memref<?xi64, #idr.world> -> i64
    idr.drop %o : !idr.own<memref<?xi64, #idr.world>>
    %w4 = idr.io.put_sint %v, %w3 : i64
    return %w4 : !idr.world
  }
  idr.func @proven(%a: memref<?xi64, #idr.world>, %i: i64, %w: !idr.world) -> !idr.world {
    %v, %w1 = idr.array.get %a[%i], %w : memref<?xi64, #idr.world> -> i64
    %w2 = idr.array.set %a[%i], %v, %w1 : memref<?xi64, #idr.world>, i64
    return %w2 : !idr.world
  }
  idr.func @checked(%a: memref<?xi64, #idr.world>, %i: i64, %w: !idr.world) -> !idr.world {
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
    %n = arith.index_cast %d : index to i64
    %j = idr.check.in_bounds %i, %a, "array index out of bounds" : memref<?xi64, #idr.world>
    %v, %w1 = idr.array.get %a[%j], %w : memref<?xi64, #idr.world> -> i64
    %w2 = idr.array.set %a[%j], %v, %w1 : memref<?xi64, #idr.world>, i64
    return %w2 : !idr.world
  }
}
// The reference:
// REF: idr.program @ref root(@root) stage(higher) {
// REF:   idr.func @root(%w: !idr.world) -> !idr.world {
// REF:     %c, %w1 = idr.io.get_byte %w
// REF:     %x = arith.extui %c : i32 to i64
// REF:     %three = arith.constant 3 : i64
// REF:     %in = arith.cmpi ult, %x, %three : i64
// REF:     %r = idr.match_lit %in : i1 -> (i64) {
// REF:     case 1 {
// REF:       idr.yield %x : i64
// REF:     }
// REF:     default(%d: i1) {
// REF:       idr.crash "array index out of bounds"
// REF:       ub.unreachable
// REF:     }
// REF:     }
// REF:     %w2 = idr.io.put_sint %r, %w1 : i64
// REF:     return %w2 : !idr.world
// REF:   }
// REF: }
