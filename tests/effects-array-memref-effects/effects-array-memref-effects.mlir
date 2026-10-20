// RUN: idris-mlir-opt %s --idr-effects --canonicalize --idr-expect=holds=moves-out=@other,moves-out=@same -verify-diagnostics -o /dev/null
// An access to an array a world orders reads or writes that array's own
// memory, not all of the program's: so between a read of an element and
// the write of it back, a write to an array of another type, on a world of
// its own, cannot read what the first array holds, and the read still
// moves its element out (@other). A write to an array of the same type may
// be to the same array, so the read stays as it is (@same).

!R = !idr.data<"R">
#types = #idr.types<
  "R" = plain [@MkR(i64, i64)]
>
idr.program @"array-memref-effects" root(@root) stage(first) types #types {
  idr.func @bump(%r: !idr.box<!R>) -> !idr.box<!R> attributes {total} {
    %a = idr.field %r : !idr.box<!R> @MkR[0] -> i64
    %b = idr.field %r : !idr.box<!R> @MkR[1] -> i64
    %one = arith.constant 1 : i64
    %a1 = arith.addi %a, %one : i64
    %n = idr.con !idr.box<!R> @MkR(%a1 : i64, %b : i64)
    return %n : !idr.box<!R>
  }

  idr.func @other(%ref: memref<!idr.box<!R>, #idr.world>, %count: memref<i64, #idr.world>, %w: !idr.world) -> !idr.world {
    %r, %w1 = idr.array.get %ref[], %w : memref<!idr.box<!R>, #idr.world> -> !idr.box<!R>
    %v = idr.world.new
    %z = arith.constant 0 : i64
    %v1 = idr.array.set %count[], %z, %v : memref<i64, #idr.world>, i64
    %n = idr.call @bump(%r) : (!idr.box<!R>) -> !idr.box<!R>
    %w2 = idr.array.set %ref[], %n, %w1 : memref<!idr.box<!R>, #idr.world>, !idr.box<!R>
    return %w2 : !idr.world
  }

  // expected-error @below {{expected moves-out: }}
  idr.func @same(%ref: memref<!idr.box<!R>, #idr.world>, %alias: memref<!idr.box<!R>, #idr.world>, %w: !idr.world) -> !idr.world {
    %r, %w1 = idr.array.get %ref[], %w : memref<!idr.box<!R>, #idr.world> -> !idr.box<!R>
    %v = idr.world.new
    %z = arith.constant 0 : i64
    %x = idr.con !idr.box<!R> @MkR(%z : i64, %z : i64)
    %v1 = idr.array.set %alias[], %x, %v : memref<!idr.box<!R>, #idr.world>, !idr.box<!R>
    %n = idr.call @bump(%r) : (!idr.box<!R>) -> !idr.box<!R>
    %w2 = idr.array.set %ref[], %n, %w1 : memref<!idr.box<!R>, #idr.world>, !idr.box<!R>
    return %w2 : !idr.world
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
