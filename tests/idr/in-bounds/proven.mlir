// RUN: idris-mlir-opt %s --idr-in-bounds --idr-expect=holds=in-bounds=@count,in-bounds=@related,in-bounds=@guarded,in-bounds=@positive,in-bounds=@carried,in-bounds=@made,in-bounds=@sameSide,in-bounds=@unsignedLength,in-bounds=@forDim,in-bounds=@emptyNegative -o /dev/null
// RUN: idris-mlir-opt %s --idr-in-bounds | FileCheck %s
// An access is proven when what holds on its path leaves no index outside
// its array: a loop between 0 and the size of the array it made; a size and the
// array made of it passed together to every call of a private function,
// carried together round a loop, returned together, or chosen by one
// condition; a size above 0 for its first and last elements; an unsigned
// index below the length; the index of a loop up to the length. An array
// of a negative size is empty, and a path on which its index is below the
// size never runs. And after an access runs, its index is within its
// array, so a second access there is proven whatever the first was.
// CHECK-LABEL: func.func @again(
// CHECK: idr.array.get %
// CHECK: idr.array.set in_bounds
module {
  func.func @count(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %r:2 = scf.while (%i = %z, %s = %w1) : (i64, !idr.world) -> (i64, !idr.world) {
      %lo = arith.cmpi sge, %i, %z : i64
      %hi = arith.cmpi slt, %i, %n : i64
      %c = arith.andi %lo, %hi : i1
      scf.condition(%c) %i, %s : i64, !idr.world
    } do {
    ^bb0(%i: i64, %s: !idr.world):
      %s1 = idr.array.set %a[%i], %i, %s : memref<?xi64>, i64
      %j = arith.addi %i, %one overflow<nsw> : i64
      scf.yield %j, %s1 : i64, !idr.world
    }
    return %r#1 : !idr.world
  }

  func.func @pairs(%n: i64, %m: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %w2 = func.call @related(%n, %a, %i, %w1) : (i64, memref<?xi64>, i64, !idr.world) -> !idr.world
    %c, %w3 = idr.array.new %m, %z, %w2 : i64 -> memref<?xi64>
    %w4 = func.call @related(%m, %c, %i, %w3) : (i64, memref<?xi64>, i64, !idr.world) -> !idr.world
    return %w4 : !idr.world
  }
  func.func private @related(%n: i64, %a: memref<?xi64>, %i: i64, %w: !idr.world) -> !idr.world {
    %r = func.call @guarded(%n, %a, %i, %w) : (i64, memref<?xi64>, i64, !idr.world) -> !idr.world
    %z = arith.constant 0 : i64
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %s = scf.if %ok -> !idr.world {
      %s1 = idr.array.set %a[%i], %i, %r : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %r : !idr.world
    }
    return %s : !idr.world
  }
  // The frontend's guards: each comparison made an integer, matched on.
  func.func private @guarded(%n: i64, %a: memref<?xi64>, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %neg = arith.cmpi slt, %i, %z : i64
    %negI = arith.extui %neg : i1 to i64
    %r = idr.match_lit %negI : i64 -> (!idr.world) {
    case 0 {
      %past = arith.cmpi sge, %i, %n : i64
      %pastI = arith.extui %past : i1 to i64
      %s = idr.match_lit %pastI : i64 -> (!idr.world) {
      case 0 {
        %s1 = idr.array.set %a[%i], %i, %w : memref<?xi64>, i64
        idr.yield %s1 : !idr.world
      }
      default {
        idr.yield %w : !idr.world
      }
      }
      idr.yield %s : !idr.world
    }
    default {
      idr.yield %w : !idr.world
    }
    }
    return %r : !idr.world
  }

  func.func @positive(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %some = arith.cmpi slt, %z, %n : i64
    %r = scf.if %some -> !idr.world {
      %v, %s1 = idr.array.get %a[%z], %w1 : memref<?xi64> -> i64
      %last = arith.subi %n, %one : i64
      %s2 = idr.array.set %a[%last], %v, %s1 : memref<?xi64>, i64
      scf.yield %s2 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  // The size and the array go round the loop together, the array taken
  // apart from the size as a record's fields are.
  func.func @carried(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %r:4 = scf.while (%k = %n, %arr = %a, %i = %z, %s = %w1) : (i64, memref<?xi64>, i64, !idr.world) -> (i64, memref<?xi64>, i64, !idr.world) {
      %lo = arith.cmpi sge, %i, %z : i64
      %hi = arith.cmpi slt, %i, %k : i64
      %c = arith.andi %lo, %hi : i1
      scf.condition(%c) %k, %arr, %i, %s : i64, memref<?xi64>, i64, !idr.world
    } do {
    ^bb0(%k: i64, %arr: memref<?xi64>, %i: i64, %s: !idr.world):
      %s1 = idr.array.set %arr[%i], %i, %s : memref<?xi64>, i64
      %j = arith.addi %i, %one overflow<nsw> : i64
      scf.yield %k, %arr, %j, %s1 : i64, memref<?xi64>, i64, !idr.world
    }
    return %r#3 : !idr.world
  }

  func.func private @make(%n: i64, %w: !idr.world) -> (i64, memref<?xi64>, !idr.world) {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    return %n, %a, %w1 : i64, memref<?xi64>, !idr.world
  }
  func.func @made(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %k, %a, %w1 = func.call @make(%n, %w) : (i64, !idr.world) -> (i64, memref<?xi64>, !idr.world)
    %z = arith.constant 0 : i64
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %k : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %s1 = idr.array.set %a[%i], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  func.func @sameSide(%p: i1, %n: i64, %m: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %c, %w2 = idr.array.new %m, %z, %w1 : i64 -> memref<?xi64>
    %k = arith.select %p, %n, %m : i64
    %arr = arith.select %p, %a, %c : memref<?xi64>
    %some = arith.cmpi sgt, %k, %z : i64
    %r = scf.if %some -> !idr.world {
      %s1 = idr.array.set %arr[%z], %z, %w2 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w2 : !idr.world
    }
    return %r : !idr.world
  }

  func.func @unsignedLength(%a: memref<?xi64>, %i: i64, %w: !idr.world) -> !idr.world {
    %c0 = arith.constant 0 : index
    %len = memref.dim %a, %c0 : memref<?xi64>
    %l = arith.index_cast %len : index to i64
    %ok = arith.cmpi ult, %i, %l : i64
    %r = scf.if %ok -> !idr.world {
      %s1 = idr.array.set %a[%i], %i, %w : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w : !idr.world
    }
    return %r : !idr.world
  }

  func.func @forDim(%a: memref<?xi64>, %w: !idr.world) -> !idr.world {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %len = memref.dim %a, %c0 : memref<?xi64>
    %r = scf.for %iv = %c0 to %len step %c1 iter_args(%s = %w) -> (!idr.world) {
      %i = arith.index_cast %iv : index to i64
      %s1 = idr.array.set %a[%i], %i, %s : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    }
    return %r : !idr.world
  }

  // Below a negative size there is no index at or above 0.
  func.func @emptyNegative(%i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %n = arith.constant -3 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %s1 = idr.array.set %a[%i], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  func.func @again(%a: memref<?xi64>, %i: i64, %w: !idr.world) -> !idr.world {
    %v, %w1 = idr.array.get %a[%i], %w : memref<?xi64> -> i64
    %w2 = idr.array.set %a[%i], %v, %w1 : memref<?xi64>, i64
    return %w2 : !idr.world
  }
}
