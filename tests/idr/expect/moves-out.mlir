// NEEDS-ACCEPTANCE: that moves-out holds of an idr.array.update, and that the -verify-diagnostics run passes: it fails at @readWrite, which reads the element and writes it back as two accesses.
// RUN: idris-mlir-opt %s --idr-expect=holds=moves-out=@swap -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=moves-out=@readWrite -verify-diagnostics -o /dev/null
// An element rebuilt in its place moves out of the array into the
// rebuilding (@swap, an IORef's exchange); one read and then written back
// is two accesses, and nothing moves (@readWrite).
idr.program @"moves-out" root(@root) stage(first) {
  idr.func @swap(%r: memref<i64, #idr.world>, %y: i64, %w: !idr.world) -> (i64, !idr.world) {
    %x, %w1 = idr.array.update %r[], %w {
    ^bb0(%old: i64):
      idr.array.yield %y, %old : i64, i64
    } : memref<i64, #idr.world> -> i64
    return %x, %w1 : i64, !idr.world
  }
  // expected-error @below {{expected moves-out: no element of an array is rebuilt in its place in @readWrite}}
  idr.func @readWrite(%r: memref<i64, #idr.world>, %w: !idr.world) -> !idr.world {
    %x, %w1 = idr.array.get %r[], %w : memref<i64, #idr.world> -> i64
    %one = arith.constant 1 : i64
    %y = arith.addi %x, %one : i64
    %w2 = idr.array.set %r[], %y, %w1 : memref<i64, #idr.world>, i64
    return %w2 : !idr.world
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
