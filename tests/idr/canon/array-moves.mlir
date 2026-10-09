// RUN: idris-mlir-opt %s --idr-effects --canonicalize --idr-expect=holds=moves-out=@update,moves-out=@updateAt -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-effects --canonicalize --idr-expect=holds=moves-out=@printed,moves-out=@callsIO,moves-out=@forced,moves-out=@applied,moves-out=@inMatch,moves-out=@word -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// A read of an element whose world goes next to a write of the same element
// moves the element out: a value read to be rebuilt and written back holds
// the one reference to its cell. An IORef's modify is one, and so is an
// array's read and write at one index, each access with its own guard of
// the index. Only computing may come between, which a call of a pure
// function does. Anything that may read what the array holds keeps the
// read as it is: output on a world of its own, a call that performs IO, a
// force, whose effects do not say what its suspension's code reads, an
// apply, which says nothing, and a write in another block. A word holds no
// reference to give up.
// CHECK-DAG: expected moves-out: no read of an element moves it out of its array in @printed
// CHECK-DAG: expected moves-out: no read of an element moves it out of its array in @callsIO
// CHECK-DAG: expected moves-out: no read of an element moves it out of its array in @forced
// CHECK-DAG: expected moves-out: no read of an element moves it out of its array in @applied
// CHECK-DAG: expected moves-out: no read of an element moves it out of its array in @inMatch
// CHECK-DAG: expected moves-out: no read of an element moves it out of its array in @word

idr.data @R box {
  idr.ctor @MkR (i64, i64)
}

func.func private @bump(%r: !idr.box<@R>) -> !idr.box<@R> attributes {idr.total} {
  %a = idr.field %r[@MkR, 0] : !idr.box<@R> -> i64
  %b = idr.field %r[@MkR, 1] : !idr.box<@R> -> i64
  %one = arith.constant 1 : i64
  %a1 = arith.addi %a, %one : i64
  %n = idr.con @R::@MkR(%a1, %b) : (i64, i64) -> !idr.box<@R>
  return %n : !idr.box<@R>
}

func.func private @sneaky(%s: !idr.str) -> i64 attributes {idr.total} {
  %v = idr.world.new
  %v1 = idr.io.put_str %s, %v
  %z = arith.constant 0 : i64
  return %z : i64
}

func.func @update(%ref: memref<!idr.box<@R>>, %w: !idr.world) -> !idr.world {
  %r, %w1 = idr.array.get %ref[], %w : memref<!idr.box<@R>> -> !idr.box<@R>
  %n = func.call @bump(%r) : (!idr.box<@R>) -> !idr.box<@R>
  %w2 = idr.array.set %ref[], %n, %w1 : memref<!idr.box<@R>>, !idr.box<@R>
  return %w2 : !idr.world
}

func.func @updateAt(%a: memref<?x!idr.box<@R>>, %i: i64, %w: !idr.world) -> !idr.world {
  %c0 = arith.constant 0 : index
  %d = memref.dim %a, %c0 : memref<?x!idr.box<@R>>
  %len = arith.index_cast %d : index to i64
  %j = idr.check.in_bounds %i, %len, "array index out of bounds"
  %r, %w1 = idr.array.get %a[%j], %w : memref<?x!idr.box<@R>> -> !idr.box<@R>
  %n = func.call @bump(%r) : (!idr.box<@R>) -> !idr.box<@R>
  %k = idr.check.in_bounds %i, %len, "array index out of bounds"
  %w2 = idr.array.set %a[%k], %n, %w1 : memref<?x!idr.box<@R>>, !idr.box<@R>
  return %w2 : !idr.world
}

func.func @printed(%ref: memref<!idr.box<@R>>, %s: !idr.str, %w: !idr.world) -> !idr.world {
  %r, %w1 = idr.array.get %ref[], %w : memref<!idr.box<@R>> -> !idr.box<@R>
  %v = idr.world.new
  %v1 = idr.io.put_str %s, %v
  %n = func.call @bump(%r) : (!idr.box<@R>) -> !idr.box<@R>
  %w2 = idr.array.set %ref[], %n, %w1 : memref<!idr.box<@R>>, !idr.box<@R>
  return %w2 : !idr.world
}

func.func @callsIO(%ref: memref<!idr.box<@R>>, %s: !idr.str, %w: !idr.world) -> (i64, !idr.world) {
  %r, %w1 = idr.array.get %ref[], %w : memref<!idr.box<@R>> -> !idr.box<@R>
  %z = func.call @sneaky(%s) : (!idr.str) -> i64
  %n = func.call @bump(%r) : (!idr.box<@R>) -> !idr.box<@R>
  %w2 = idr.array.set %ref[], %n, %w1 : memref<!idr.box<@R>>, !idr.box<@R>
  return %z, %w2 : i64, !idr.world
}

func.func @forced(%ref: memref<!idr.box<@R>>, %t: !idr.lazy<i64>, %w: !idr.world) -> (i64, !idr.world) {
  %r, %w1 = idr.array.get %ref[], %w : memref<!idr.box<@R>> -> !idr.box<@R>
  %x = idr.force %t : !idr.lazy<i64> -> i64
  %n = func.call @bump(%r) : (!idr.box<@R>) -> !idr.box<@R>
  %w2 = idr.array.set %ref[], %n, %w1 : memref<!idr.box<@R>>, !idr.box<@R>
  return %x, %w2 : i64, !idr.world
}

func.func @applied(%ref: memref<!idr.box<@R>>, %f: !idr.fn<(i64) -> (i64)>, %y: i64,
                   %w: !idr.world) -> (i64, !idr.world) {
  %r, %w1 = idr.array.get %ref[], %w : memref<!idr.box<@R>> -> !idr.box<@R>
  %x = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
  %n = func.call @bump(%r) : (!idr.box<@R>) -> !idr.box<@R>
  %w2 = idr.array.set %ref[], %n, %w1 : memref<!idr.box<@R>>, !idr.box<@R>
  return %x, %w2 : i64, !idr.world
}

func.func @inMatch(%ref: memref<!idr.box<@R>>, %b: i64, %w: !idr.world) -> !idr.world {
  %r, %w1 = idr.array.get %ref[], %w : memref<!idr.box<@R>> -> !idr.box<@R>
  %w3 = idr.match_lit %b : i64 -> (!idr.world) {
  case 0 {
    %n = func.call @bump(%r) : (!idr.box<@R>) -> !idr.box<@R>
    %w2 = idr.array.set %ref[], %n, %w1 : memref<!idr.box<@R>>, !idr.box<@R>
    idr.yield %w2 : !idr.world
  }
  default {
    idr.yield %w1 : !idr.world
  }
  }
  return %w3 : !idr.world
}

func.func @word(%ref: memref<i64>, %w: !idr.world) -> !idr.world {
  %x, %w1 = idr.array.get %ref[], %w : memref<i64> -> i64
  %one = arith.constant 1 : i64
  %y = arith.addi %x, %one : i64
  %w2 = idr.array.set %ref[], %y, %w1 : memref<i64>, i64
  return %w2 : !idr.world
}
