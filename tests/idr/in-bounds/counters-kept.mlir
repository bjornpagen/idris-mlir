// RUN: idris-mlir-opt %s --idr-in-bounds --idr-expect=holds=bounds-checked=@mayShrink,bounds-checked=@wraps,bounds-checked=@unsignedGuard,bounds-checked=@belowZero,bounds-checked=@stepsDown,bounds-checked=@goesBackNegative,bounds-checked=@scaled -o /dev/null
// Each counter here may leave the bound it starts at, so no induction
// keeps it there and each access keeps its check: a step of an amount of
// either sign; a step of 2 below a size that may be the largest word, past
// which it wraps below 0; a step of 1 below an unsigned bound, which lets
// the counter reach the largest word and wrap; a counter that starts at
// -1; one that steps down from 0; one that a region passes back as -1 on
// a path that may go round again; and one that doubles, which wraps.
module {
  func.func @mayShrink(%n: i64, %k: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %r:2 = scf.while (%i = %z, %s = %w1) : (i64, !idr.world) -> (i64, !idr.world) {
      %c = arith.cmpi slt, %i, %n : i64
      scf.condition(%c) %i, %s : i64, !idr.world
    } do {
    ^bb0(%i: i64, %s: !idr.world):
      %ib1.z = arith.constant 0 : index
      %ib1.d = memref.dim %a, %ib1.z : memref<?xi64>
      %ib1.n = arith.index_cast %ib1.d : index to i64
      %ib1 = idr.check.in_bounds %i, %ib1.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib1], %i, %s : memref<?xi64>, i64
      %j = arith.addi %i, %k : i64
      scf.yield %j, %s1 : i64, !idr.world
    }
    return %r#1 : !idr.world
  }

  func.func @wraps(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %two = arith.constant 2 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %r:2 = scf.while (%i = %z, %s = %w1) : (i64, !idr.world) -> (i64, !idr.world) {
      %c = arith.cmpi slt, %i, %n : i64
      scf.condition(%c) %i, %s : i64, !idr.world
    } do {
    ^bb0(%i: i64, %s: !idr.world):
      %ib2.z = arith.constant 0 : index
      %ib2.d = memref.dim %a, %ib2.z : memref<?xi64>
      %ib2.n = arith.index_cast %ib2.d : index to i64
      %ib2 = idr.check.in_bounds %i, %ib2.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib2], %i, %s : memref<?xi64>, i64
      %j = arith.addi %i, %two : i64
      scf.yield %j, %s1 : i64, !idr.world
    }
    return %r#1 : !idr.world
  }

  func.func @unsignedGuard(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %r:2 = scf.while (%i = %z, %s = %w1) : (i64, !idr.world) -> (i64, !idr.world) {
      %c = arith.cmpi ult, %i, %n : i64
      scf.condition(%c) %i, %s : i64, !idr.world
    } do {
    ^bb0(%i: i64, %s: !idr.world):
      %ib3.z = arith.constant 0 : index
      %ib3.d = memref.dim %a, %ib3.z : memref<?xi64>
      %ib3.n = arith.index_cast %ib3.d : index to i64
      %ib3 = idr.check.in_bounds %i, %ib3.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib3], %i, %s : memref<?xi64>, i64
      %j = arith.addi %i, %one : i64
      scf.yield %j, %s1 : i64, !idr.world
    }
    return %r#1 : !idr.world
  }

  func.func @belowZero(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %m1 = arith.constant -1 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %r:2 = scf.while (%i = %m1, %s = %w1) : (i64, !idr.world) -> (i64, !idr.world) {
      %c = arith.cmpi slt, %i, %n : i64
      scf.condition(%c) %i, %s : i64, !idr.world
    } do {
    ^bb0(%i: i64, %s: !idr.world):
      %ib4.z = arith.constant 0 : index
      %ib4.d = memref.dim %a, %ib4.z : memref<?xi64>
      %ib4.n = arith.index_cast %ib4.d : index to i64
      %ib4 = idr.check.in_bounds %i, %ib4.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib4], %i, %s : memref<?xi64>, i64
      %j = arith.addi %i, %one : i64
      scf.yield %j, %s1 : i64, !idr.world
    }
    return %r#1 : !idr.world
  }

  func.func @stepsDown(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %m1 = arith.constant -1 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %r:2 = scf.while (%i = %z, %s = %w1) : (i64, !idr.world) -> (i64, !idr.world) {
      %c = arith.cmpi slt, %i, %n : i64
      scf.condition(%c) %i, %s : i64, !idr.world
    } do {
    ^bb0(%i: i64, %s: !idr.world):
      %ib5.z = arith.constant 0 : index
      %ib5.d = memref.dim %a, %ib5.z : memref<?xi64>
      %ib5.n = arith.index_cast %ib5.d : index to i64
      %ib5 = idr.check.in_bounds %i, %ib5.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib5], %i, %s : memref<?xi64>, i64
      %j = arith.addi %i, %m1 : i64
      scf.yield %j, %s1 : i64, !idr.world
    }
    return %r#1 : !idr.world
  }

  func.func @goesBackNegative(%n: i64, %again: i1, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %m1 = arith.constant -1 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %r:3 = scf.while (%i = %z, %s = %w1) : (i64, !idr.world) -> (i64, !idr.world, !idr.world) {
      %c = arith.cmpi slt, %i, %n : i64
      %e = arith.extui %c : i1 to i64
      %d:4 = idr.match_lit %e : i64 -> (i1, i64, !idr.world, !idr.world) {
      case 0 {
        %false = arith.constant false
        %p = ub.poison : !idr.world
        idr.yield %false, %i, %p, %s : i1, i64, !idr.world, !idr.world
      }
      default {
        %ib6.z = arith.constant 0 : index
        %ib6.d = memref.dim %a, %ib6.z : memref<?xi64>
        %ib6.n = arith.index_cast %ib6.d : index to i64
        %ib6 = idr.check.in_bounds %i, %ib6.n, "array index out of bounds"
        %s1 = idr.array.set %a[%ib6], %i, %s : memref<?xi64>, i64
        %p = ub.poison : !idr.world
        idr.yield %again, %m1, %s1, %p : i1, i64, !idr.world, !idr.world
      }
      }
      scf.condition(%d#0) %d#1, %d#2, %d#3 : i64, !idr.world, !idr.world
    } do {
    ^bb0(%i: i64, %s: !idr.world, %x: !idr.world):
      scf.yield %i, %s : i64, !idr.world
    }
    return %r#2 : !idr.world
  }

  func.func @scaled(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %r:2 = scf.while (%i = %one, %s = %w1) : (i64, !idr.world) -> (i64, !idr.world) {
      %c = arith.cmpi slt, %i, %n : i64
      scf.condition(%c) %i, %s : i64, !idr.world
    } do {
    ^bb0(%i: i64, %s: !idr.world):
      %ib7.z = arith.constant 0 : index
      %ib7.d = memref.dim %a, %ib7.z : memref<?xi64>
      %ib7.n = arith.index_cast %ib7.d : index to i64
      %ib7 = idr.check.in_bounds %i, %ib7.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib7], %i, %s : memref<?xi64>, i64
      %j = arith.muli %i, %two : i64
      scf.yield %j, %s1 : i64, !idr.world
    }
    return %r#1 : !idr.world
  }
}
