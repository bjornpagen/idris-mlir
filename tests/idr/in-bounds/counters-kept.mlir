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
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %r:2 = scf.while (%i = %z, %s = %w1) : (i64, !idr.world) -> (i64, !idr.world) {
      %c = arith.cmpi slt, %i, %n : i64
      scf.condition(%c) %i, %s : i64, !idr.world
    } do {
    ^bb0(%i: i64, %s: !idr.world):
      %s1 = idr.array.set %a[%i], %i, %s : memref<?xi64>, i64
      %j = arith.addi %i, %k : i64
      scf.yield %j, %s1 : i64, !idr.world
    }
    return %r#1 : !idr.world
  }

  func.func @wraps(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %two = arith.constant 2 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %r:2 = scf.while (%i = %z, %s = %w1) : (i64, !idr.world) -> (i64, !idr.world) {
      %c = arith.cmpi slt, %i, %n : i64
      scf.condition(%c) %i, %s : i64, !idr.world
    } do {
    ^bb0(%i: i64, %s: !idr.world):
      %s1 = idr.array.set %a[%i], %i, %s : memref<?xi64>, i64
      %j = arith.addi %i, %two : i64
      scf.yield %j, %s1 : i64, !idr.world
    }
    return %r#1 : !idr.world
  }

  func.func @unsignedGuard(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %r:2 = scf.while (%i = %z, %s = %w1) : (i64, !idr.world) -> (i64, !idr.world) {
      %c = arith.cmpi ult, %i, %n : i64
      scf.condition(%c) %i, %s : i64, !idr.world
    } do {
    ^bb0(%i: i64, %s: !idr.world):
      %s1 = idr.array.set %a[%i], %i, %s : memref<?xi64>, i64
      %j = arith.addi %i, %one : i64
      scf.yield %j, %s1 : i64, !idr.world
    }
    return %r#1 : !idr.world
  }

  func.func @belowZero(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %m1 = arith.constant -1 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %r:2 = scf.while (%i = %m1, %s = %w1) : (i64, !idr.world) -> (i64, !idr.world) {
      %c = arith.cmpi slt, %i, %n : i64
      scf.condition(%c) %i, %s : i64, !idr.world
    } do {
    ^bb0(%i: i64, %s: !idr.world):
      %s1 = idr.array.set %a[%i], %i, %s : memref<?xi64>, i64
      %j = arith.addi %i, %one : i64
      scf.yield %j, %s1 : i64, !idr.world
    }
    return %r#1 : !idr.world
  }

  func.func @stepsDown(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %m1 = arith.constant -1 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %r:2 = scf.while (%i = %z, %s = %w1) : (i64, !idr.world) -> (i64, !idr.world) {
      %c = arith.cmpi slt, %i, %n : i64
      scf.condition(%c) %i, %s : i64, !idr.world
    } do {
    ^bb0(%i: i64, %s: !idr.world):
      %s1 = idr.array.set %a[%i], %i, %s : memref<?xi64>, i64
      %j = arith.addi %i, %m1 : i64
      scf.yield %j, %s1 : i64, !idr.world
    }
    return %r#1 : !idr.world
  }

  func.func @goesBackNegative(%n: i64, %again: i1, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %m1 = arith.constant -1 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
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
        %s1 = idr.array.set %a[%i], %i, %s : memref<?xi64>, i64
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
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %r:2 = scf.while (%i = %one, %s = %w1) : (i64, !idr.world) -> (i64, !idr.world) {
      %c = arith.cmpi slt, %i, %n : i64
      scf.condition(%c) %i, %s : i64, !idr.world
    } do {
    ^bb0(%i: i64, %s: !idr.world):
      %s1 = idr.array.set %a[%i], %i, %s : memref<?xi64>, i64
      %j = arith.muli %i, %two : i64
      scf.yield %j, %s1 : i64, !idr.world
    }
    return %r#1 : !idr.world
  }
}
