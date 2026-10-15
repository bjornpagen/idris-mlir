// RUN: idris-mlir-opt %s --idr-effects --canonicalize --idr-expect=holds=moves-out=@other -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-effects --canonicalize --idr-expect=holds=moves-out=@same -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// An access to an array a world orders reads or writes that array's own
// memory, not all of the program's: so between a read of an element and
// the write of it back, a write to an array of another type, on a world of
// its own, cannot read what the first array holds, and the read still
// moves its element out (@other). A write to an array of the same type may
// be to the same array, so the read stays as it is (@same).
// CHECK: expected moves-out: no read of an element moves it out of its array in @same
// CHECK-NOT: in @other

!R = !idr.data<"R", plain [@MkR(i64, i64)]>
idr.func private @bump(%r: !idr.box<!R>) -> !idr.box<!R> attributes {total} {
  %a = idr.field %r[@MkR, 0] : !idr.box<!R> -> i64
  %b = idr.field %r[@MkR, 1] : !idr.box<!R> -> i64
  %one = arith.constant 1 : i64
  %a1 = arith.addi %a, %one : i64
  %n = idr.con @MkR(%a1, %b) : (i64, i64) -> !idr.box<!R>
  return %n : !idr.box<!R>
}

idr.func private @other(%ref: memref<!idr.box<!R>, #idr.world>, %count: memref<i64, #idr.world>, %w: !idr.world) -> !idr.world {
  %r, %w1 = idr.array.get %ref[], %w : memref<!idr.box<!R>, #idr.world> -> !idr.box<!R>
  %v = idr.world.new
  %z = arith.constant 0 : i64
  %v1 = idr.array.set %count[], %z, %v : memref<i64, #idr.world>, i64
  %n = idr.call @bump(%r) : (!idr.box<!R>) -> !idr.box<!R>
  %w2 = idr.array.set %ref[], %n, %w1 : memref<!idr.box<!R>, #idr.world>, !idr.box<!R>
  return %w2 : !idr.world
}

idr.func private @same(%ref: memref<!idr.box<!R>, #idr.world>, %alias: memref<!idr.box<!R>, #idr.world>, %w: !idr.world) -> !idr.world {
  %r, %w1 = idr.array.get %ref[], %w : memref<!idr.box<!R>, #idr.world> -> !idr.box<!R>
  %v = idr.world.new
  %z = arith.constant 0 : i64
  %x = idr.con @MkR(%z, %z) : (i64, i64) -> !idr.box<!R>
  %v1 = idr.array.set %alias[], %x, %v : memref<!idr.box<!R>, #idr.world>, !idr.box<!R>
  %n = idr.call @bump(%r) : (!idr.box<!R>) -> !idr.box<!R>
  %w2 = idr.array.set %ref[], %n, %w1 : memref<!idr.box<!R>, #idr.world>, !idr.box<!R>
  return %w2 : !idr.world
}
