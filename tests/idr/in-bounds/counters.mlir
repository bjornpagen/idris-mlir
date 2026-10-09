// RUN: idris-mlir-opt %s --idr-in-bounds --idr-expect=holds=in-bounds=@upTo,in-bounds=@decides,in-bounds=@poisonExit,in-bounds=@down,in-bounds=@byTwo,in-bounds=@byAmount,in-bounds=@nested -o /dev/null
// A loop's counter keeps the bound it starts at when every back edge
// passes it on within that bound, which the loop's own guard decides: no
// access below guards its index against 0, so each is proven only by the
// counter's induction. Counting up from 0 below the size, in a loop that
// tests before its body or that decides in one region whether to go round
// (passing -1, or poison, on the way out, which no iteration sees); down
// from 9 to 0 in an array of more than 9; by 2 below a bound 2 below the
// largest word; by an amount from 0 to 255; and from where an outer
// counter stands.
module {
  func.func @upTo(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
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
      %j = arith.addi %i, %one : i64
      scf.yield %j, %s1 : i64, !idr.world
    }
    return %r#1 : !idr.world
  }

  func.func @decides(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %m1 = arith.constant -1 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %r:3 = scf.while (%i = %z, %s = %w1) : (i64, !idr.world) -> (i64, !idr.world, !idr.world) {
      %c = arith.cmpi slt, %i, %n : i64
      %e = arith.extui %c : i1 to i64
      %d:4 = idr.match_lit %e : i64 -> (i1, i64, !idr.world, !idr.world) {
      case 0 {
        %false = arith.constant false
        %p = ub.poison : !idr.world
        idr.yield %false, %m1, %p, %s : i1, i64, !idr.world, !idr.world
      }
      default {
        %ib2.z = arith.constant 0 : index
        %ib2.d = memref.dim %a, %ib2.z : memref<?xi64>
        %ib2.n = arith.index_cast %ib2.d : index to i64
        %ib2 = idr.check.in_bounds %i, %ib2.n, "array index out of bounds"
        %s1 = idr.array.set %a[%ib2], %i, %s : memref<?xi64>, i64
        %j = arith.addi %i, %one : i64
        %true = arith.constant true
        %p = ub.poison : !idr.world
        idr.yield %true, %j, %s1, %p : i1, i64, !idr.world, !idr.world
      }
      }
      scf.condition(%d#0) %d#1, %d#2, %d#3 : i64, !idr.world, !idr.world
    } do {
    ^bb0(%i: i64, %s: !idr.world, %x: !idr.world):
      scf.yield %i, %s : i64, !idr.world
    }
    return %r#2 : !idr.world
  }

  // Poison on the way out is not a value the next iteration steps from.
  func.func @poisonExit(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %r:3 = scf.while (%i = %z, %s = %w1) : (i64, !idr.world) -> (i64, !idr.world, !idr.world) {
      %c = arith.cmpi slt, %i, %n : i64
      %e = arith.extui %c : i1 to i64
      %d:4 = idr.match_lit %e : i64 -> (i1, i64, !idr.world, !idr.world) {
      case 0 {
        %false = arith.constant false
        %p = ub.poison : i64
        %q = ub.poison : !idr.world
        idr.yield %false, %p, %q, %s : i1, i64, !idr.world, !idr.world
      }
      default {
        %ib3.z = arith.constant 0 : index
        %ib3.d = memref.dim %a, %ib3.z : memref<?xi64>
        %ib3.n = arith.index_cast %ib3.d : index to i64
        %ib3 = idr.check.in_bounds %i, %ib3.n, "array index out of bounds"
        %s1 = idr.array.set %a[%ib3], %i, %s : memref<?xi64>, i64
        %j = arith.addi %i, %one : i64
        %true = arith.constant true
        %q = ub.poison : !idr.world
        idr.yield %true, %j, %s1, %q : i1, i64, !idr.world, !idr.world
      }
      }
      scf.condition(%d#0) %d#1, %d#2, %d#3 : i64, !idr.world, !idr.world
    } do {
    ^bb0(%i: i64, %s: !idr.world, %x: !idr.world):
      scf.yield %i, %s : i64, !idr.world
    }
    return %r#2 : !idr.world
  }

  func.func @down(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %nine = arith.constant 9 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %big = arith.cmpi sgt, %n, %nine : i64
    %out = scf.if %big -> !idr.world {
      %r:2 = scf.while (%i = %nine, %s = %w1) : (i64, !idr.world) -> (i64, !idr.world) {
        %c = arith.cmpi sge, %i, %z : i64
        scf.condition(%c) %i, %s : i64, !idr.world
      } do {
      ^bb0(%i: i64, %s: !idr.world):
        %ib4.z = arith.constant 0 : index
        %ib4.d = memref.dim %a, %ib4.z : memref<?xi64>
        %ib4.n = arith.index_cast %ib4.d : index to i64
        %ib4 = idr.check.in_bounds %i, %ib4.n, "array index out of bounds"
        %s1 = idr.array.set %a[%ib4], %i, %s : memref<?xi64>, i64
        %j = arith.subi %i, %one : i64
        scf.yield %j, %s1 : i64, !idr.world
      }
      scf.yield %r#1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %out : !idr.world
  }

  func.func @byTwo(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %two = arith.constant 2 : i64
    %top = arith.constant 9223372036854775805 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %r:2 = scf.while (%i = %z, %s = %w1) : (i64, !idr.world) -> (i64, !idr.world) {
      %below = arith.cmpi slt, %i, %n : i64
      %room = arith.cmpi slt, %i, %top : i64
      %c = arith.andi %below, %room : i1
      scf.condition(%c) %i, %s : i64, !idr.world
    } do {
    ^bb0(%i: i64, %s: !idr.world):
      %ib5.z = arith.constant 0 : index
      %ib5.d = memref.dim %a, %ib5.z : memref<?xi64>
      %ib5.n = arith.index_cast %ib5.d : index to i64
      %ib5 = idr.check.in_bounds %i, %ib5.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib5], %i, %s : memref<?xi64>, i64
      %j = arith.addi %i, %two : i64
      scf.yield %j, %s1 : i64, !idr.world
    }
    return %r#1 : !idr.world
  }

  func.func @byAmount(%b: i8, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %thousand = arith.constant 1000 : i64
    %a, %w1 = idr.array.new %thousand, %z, %w : i64 -> memref<?xi64>
    %r:2 = scf.while (%i = %z, %s = %w1) : (i64, !idr.world) -> (i64, !idr.world) {
      %c = arith.cmpi slt, %i, %thousand : i64
      scf.condition(%c) %i, %s : i64, !idr.world
    } do {
    ^bb0(%i: i64, %s: !idr.world):
      %ib6.z = arith.constant 0 : index
      %ib6.d = memref.dim %a, %ib6.z : memref<?xi64>
      %ib6.n = arith.index_cast %ib6.d : index to i64
      %ib6 = idr.check.in_bounds %i, %ib6.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib6], %i, %s : memref<?xi64>, i64
      %k = arith.extui %b : i8 to i64
      %j = arith.addi %i, %k : i64
      scf.yield %j, %s1 : i64, !idr.world
    }
    return %r#1 : !idr.world
  }

  func.func @nested(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %r:2 = scf.while (%i = %z, %s = %w1) : (i64, !idr.world) -> (i64, !idr.world) {
      %c = arith.cmpi slt, %i, %n : i64
      scf.condition(%c) %i, %s : i64, !idr.world
    } do {
    ^bb0(%i: i64, %s: !idr.world):
      %q:2 = scf.while (%j = %i, %t = %s) : (i64, !idr.world) -> (i64, !idr.world) {
        %d = arith.cmpi slt, %j, %n : i64
        scf.condition(%d) %j, %t : i64, !idr.world
      } do {
      ^bb0(%j: i64, %t: !idr.world):
        %ib7.z = arith.constant 0 : index
        %ib7.d = memref.dim %a, %ib7.z : memref<?xi64>
        %ib7.n = arith.index_cast %ib7.d : index to i64
        %ib7 = idr.check.in_bounds %j, %ib7.n, "array index out of bounds"
        %t1 = idr.array.set %a[%ib7], %j, %t : memref<?xi64>, i64
        %k = arith.addi %j, %one : i64
        scf.yield %k, %t1 : i64, !idr.world
      }
      %i1 = arith.addi %i, %one : i64
      scf.yield %i1, %q#1 : i64, !idr.world
    }
    return %r#1 : !idr.world
  }
}
