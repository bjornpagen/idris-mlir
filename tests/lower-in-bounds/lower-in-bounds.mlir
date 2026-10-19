// RUN: idris-mlir-opt %s --idr-lower '--idr-expect=holds=lowered,crash-sites=@proven:0,calls-only=@proven:[],crash-sites=@checked:1,calls-only=@checked:[@idris_rt_crash]' -o /dev/null
// An access to an array a world orders is tested by its guard alone. One
// with no guard (a guard folded where its index shows the condition)
// lowers with no test against the size and nothing that crashes; one that
// keeps its guard may crash there, once, and the access tests nothing of
// its own.
idr.program @"in-bounds" root(@root) stage(owned) {
  idr.func @root(%w: !idr.world) -> !idr.world {
    %n = arith.constant 3 : i64
    %i = arith.constant 0 : i64
    %o, %w0 = idr.array.new [%n], %i, %w : i64 -> !idr.own<memref<?xi64, #idr.world>>
    %a = idr.borrow %o : !idr.own<memref<?xi64, #idr.world>>
    %w1 = idr.call @proven(%a, %i, %w0) : (memref<?xi64, #idr.world>, i64, !idr.world) -> !idr.world
    %w2 = idr.call @checked(%a, %i, %w1) : (memref<?xi64, #idr.world>, i64, !idr.world) -> !idr.world
    idr.drop %o : !idr.own<memref<?xi64, #idr.world>>
    return %w2 : !idr.world
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
