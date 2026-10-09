// RUN: idris-mlir-opt %s --idr-in-bounds --idr-expect=holds=in-bounds=@count,in-bounds=@related,in-bounds=@guarded,in-bounds=@positive,in-bounds=@carried,in-bounds=@made,in-bounds=@sameSide,in-bounds=@unsignedLength,in-bounds=@forDim,in-bounds=@emptyNegative,in-bounds=@givenBack,in-bounds=@givenUse,in-bounds=@givenSecond,in-bounds=@givenAgain,in-bounds=@half,in-bounds=@quarter,in-bounds=@part,in-bounds=@dimHalf,in-bounds=@unsignedHalf,in-bounds=@halfBack -o /dev/null
// RUN: idris-mlir-opt %s --idr-in-bounds | FileCheck %s
// The guard of an access is proven, and goes, when what holds on its path
// leaves no index outside its array: a loop between 0 and the size of the
// array it made; a size and the array made of it passed together to every
// call of a private function, carried together round a loop, returned
// together, or chosen by one condition; a size above 0 for its first and
// last elements; an unsigned index below the length; the index of a loop up
// to the length. An array of a negative size is empty, and a path on which
// its index is below the size never runs. And after a guard runs, its index
// is within its array, so the guard of a second access there is proven
// whatever the first was. A call that returns the array it was given — that
// value, the linear use of it, another argument, or the same array from its
// recursive call — leaves the caller's length on what came back. Dividing a
// non-negative word by a positive constant stays inside that word: half of
// a length the path has shown positive, half of that again, half of an
// index already inside the array, half of the array's own length when that
// length is positive, and the same unsigned quotient. The array a call
// gives back keeps the length, so half of it is inside too.
// CHECK-LABEL: func.func @again(
// CHECK: idr.check.in_bounds
// CHECK: idr.array.get %
// CHECK-NOT: idr.check.in_bounds
// CHECK: idr.array.set %
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
      %ib1.z = arith.constant 0 : index
      %ib1.d = memref.dim %a, %ib1.z : memref<?xi64>
      %ib1.n = arith.index_cast %ib1.d : index to i64
      %ib1 = idr.check.in_bounds %i, %ib1.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib1], %i, %s : memref<?xi64>, i64
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
      %ib2.z = arith.constant 0 : index
      %ib2.d = memref.dim %a, %ib2.z : memref<?xi64>
      %ib2.n = arith.index_cast %ib2.d : index to i64
      %ib2 = idr.check.in_bounds %i, %ib2.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib2], %i, %r : memref<?xi64>, i64
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
        %ib3.z = arith.constant 0 : index
        %ib3.d = memref.dim %a, %ib3.z : memref<?xi64>
        %ib3.n = arith.index_cast %ib3.d : index to i64
        %ib3 = idr.check.in_bounds %i, %ib3.n, "array index out of bounds"
        %s1 = idr.array.set %a[%ib3], %i, %w : memref<?xi64>, i64
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
      %ib4.z = arith.constant 0 : index
      %ib4.d = memref.dim %a, %ib4.z : memref<?xi64>
      %ib4.n = arith.index_cast %ib4.d : index to i64
      %ib4 = idr.check.in_bounds %z, %ib4.n, "array index out of bounds"
      %v, %s1 = idr.array.get %a[%ib4], %w1 : memref<?xi64> -> i64
      %last = arith.subi %n, %one : i64
      %ib5.z = arith.constant 0 : index
      %ib5.d = memref.dim %a, %ib5.z : memref<?xi64>
      %ib5.n = arith.index_cast %ib5.d : index to i64
      %ib5 = idr.check.in_bounds %last, %ib5.n, "array index out of bounds"
      %s2 = idr.array.set %a[%ib5], %v, %s1 : memref<?xi64>, i64
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
      %ib6.z = arith.constant 0 : index
      %ib6.d = memref.dim %arr, %ib6.z : memref<?xi64>
      %ib6.n = arith.index_cast %ib6.d : index to i64
      %ib6 = idr.check.in_bounds %i, %ib6.n, "array index out of bounds"
      %s1 = idr.array.set %arr[%ib6], %i, %s : memref<?xi64>, i64
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
      %ib7.z = arith.constant 0 : index
      %ib7.d = memref.dim %a, %ib7.z : memref<?xi64>
      %ib7.n = arith.index_cast %ib7.d : index to i64
      %ib7 = idr.check.in_bounds %i, %ib7.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib7], %i, %w1 : memref<?xi64>, i64
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
      %ib8.z = arith.constant 0 : index
      %ib8.d = memref.dim %arr, %ib8.z : memref<?xi64>
      %ib8.n = arith.index_cast %ib8.d : index to i64
      %ib8 = idr.check.in_bounds %z, %ib8.n, "array index out of bounds"
      %s1 = idr.array.set %arr[%ib8], %z, %w2 : memref<?xi64>, i64
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
      %ib9.z = arith.constant 0 : index
      %ib9.d = memref.dim %a, %ib9.z : memref<?xi64>
      %ib9.n = arith.index_cast %ib9.d : index to i64
      %ib9 = idr.check.in_bounds %i, %ib9.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib9], %i, %w : memref<?xi64>, i64
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
      %ib10.z = arith.constant 0 : index
      %ib10.d = memref.dim %a, %ib10.z : memref<?xi64>
      %ib10.n = arith.index_cast %ib10.d : index to i64
      %ib10 = idr.check.in_bounds %i, %ib10.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib10], %i, %s : memref<?xi64>, i64
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
      %ib11.z = arith.constant 0 : index
      %ib11.d = memref.dim %a, %ib11.z : memref<?xi64>
      %ib11.n = arith.index_cast %ib11.d : index to i64
      %ib11 = idr.check.in_bounds %i, %ib11.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib11], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  func.func private @handBack(%a: memref<?xi64>) -> memref<?xi64> {
    return %a : memref<?xi64>
  }
  func.func @givenBack(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %b = func.call @handBack(%a) : (memref<?xi64>) -> memref<?xi64>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %ib12.z = arith.constant 0 : index
      %ib12.d = memref.dim %b, %ib12.z : memref<?xi64>
      %ib12.n = arith.index_cast %ib12.d : index to i64
      %ib12 = idr.check.in_bounds %i, %ib12.n, "array index out of bounds"
      %s1 = idr.array.set %b[%ib12], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  func.func private @useBack(%a: !idr.lin<memref<?xi64>>) -> memref<?xi64> {
    %u = idr.lin.use %a : !idr.lin<memref<?xi64>>
    return %u : memref<?xi64>
  }
  func.func @givenUse(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %e = idr.lin.enter %a : !idr.lin<memref<?xi64>>
    %b = func.call @useBack(%e) : (!idr.lin<memref<?xi64>>) -> memref<?xi64>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %ib13.z = arith.constant 0 : index
      %ib13.d = memref.dim %b, %ib13.z : memref<?xi64>
      %ib13.n = arith.index_cast %ib13.d : index to i64
      %ib13 = idr.check.in_bounds %i, %ib13.n, "array index out of bounds"
      %s1 = idr.array.set %b[%ib13], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  func.func private @handSecond(%a: memref<?xi64>, %c: memref<?xi64>) -> memref<?xi64> {
    return %c : memref<?xi64>
  }
  func.func @givenSecond(%n: i64, %m: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %c, %w2 = idr.array.new %m, %z, %w1 : i64 -> memref<?xi64>
    %b = func.call @handSecond(%a, %c) : (memref<?xi64>, memref<?xi64>) -> memref<?xi64>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %m : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %ib14.z = arith.constant 0 : index
      %ib14.d = memref.dim %b, %ib14.z : memref<?xi64>
      %ib14.n = arith.index_cast %ib14.d : index to i64
      %ib14 = idr.check.in_bounds %i, %ib14.n, "array index out of bounds"
      %s1 = idr.array.set %b[%ib14], %i, %w2 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w2 : !idr.world
    }
    return %r : !idr.world
  }

  func.func private @againBack(%a: memref<?xi64>, %k: i64) -> memref<?xi64> {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %neg = arith.cmpi slt, %k, %z : i64
    %negI = arith.extui %neg : i1 to i64
    %r = idr.match_lit %negI : i64 -> (memref<?xi64>) {
    case 0 {
      idr.yield %a : memref<?xi64>
    }
    default {
      %m = arith.subi %k, %one : i64
      %b = func.call @againBack(%a, %m) : (memref<?xi64>, i64) -> memref<?xi64>
      idr.yield %b : memref<?xi64>
    }
    }
    return %r : memref<?xi64>
  }
  func.func @givenAgain(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %b = func.call @againBack(%a, %n) : (memref<?xi64>, i64) -> memref<?xi64>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %ib15.z = arith.constant 0 : index
      %ib15.d = memref.dim %b, %ib15.z : memref<?xi64>
      %ib15.n = arith.index_cast %ib15.d : index to i64
      %ib15 = idr.check.in_bounds %i, %ib15.n, "array index out of bounds"
      %s1 = idr.array.set %b[%ib15], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  // `n > 0`, so `n / 2` is at least 0 and strictly below the length `n`.
  func.func @half(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %two = arith.constant 2 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %pos = arith.cmpi sgt, %n, %z : i64
    %r = scf.if %pos -> !idr.world {
      %i = idr.div signed %n, %two : i64
      %ib16.z = arith.constant 0 : index
      %ib16.d = memref.dim %a, %ib16.z : memref<?xi64>
      %ib16.n = arith.index_cast %ib16.d : index to i64
      %ib16 = idr.check.in_bounds %i, %ib16.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib16], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  // Half of `n` is non-negative because `n` is, so half of that half is too.
  func.func @quarter(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %two = arith.constant 2 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %pos = arith.cmpi sgt, %n, %z : i64
    %r = scf.if %pos -> !idr.world {
      %h = idr.div signed %n, %two : i64
      %i = idr.div signed %h, %two : i64
      %ib17.z = arith.constant 0 : index
      %ib17.d = memref.dim %a, %ib17.z : memref<?xi64>
      %ib17.n = arith.index_cast %ib17.d : index to i64
      %ib17 = idr.check.in_bounds %i, %ib17.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib17], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  // `k` is not the length. The path has `0 <= k < n`, so `k / 2` is too.
  func.func @part(%n: i64, %k: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %two = arith.constant 2 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %lo = arith.cmpi sge, %k, %z : i64
    %hi = arith.cmpi slt, %k, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %i = idr.div signed %k, %two : i64
      %ib18.z = arith.constant 0 : index
      %ib18.d = memref.dim %a, %ib18.z : memref<?xi64>
      %ib18.n = arith.index_cast %ib18.d : index to i64
      %ib18 = idr.check.in_bounds %i, %ib18.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib18], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  // The dimension is the length, hence non-negative, and the path excludes 0.
  func.func @dimHalf(%a: memref<?xi64>, %w: !idr.world) -> !idr.world {
    %c0 = arith.constant 0 : index
    %z = arith.constant 0 : i64
    %two = arith.constant 2 : i64
    %len = memref.dim %a, %c0 : memref<?xi64>
    %l = arith.index_cast %len : index to i64
    %pos = arith.cmpi sgt, %l, %z : i64
    %r = scf.if %pos -> !idr.world {
      %i = idr.div signed %l, %two : i64
      %ib19.z = arith.constant 0 : index
      %ib19.d = memref.dim %a, %ib19.z : memref<?xi64>
      %ib19.n = arith.index_cast %ib19.d : index to i64
      %ib19 = idr.check.in_bounds %i, %ib19.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib19], %i, %w : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w : !idr.world
    }
    return %r : !idr.world
  }

  // Unsigned division of a non-negative word by a positive constant is the
  // Euclidean quotient.
  func.func @unsignedHalf(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %two = arith.constant 2 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %pos = arith.cmpi sgt, %n, %z : i64
    %r = scf.if %pos -> !idr.world {
      %i = idr.div %n, %two : i64
      %ib20.z = arith.constant 0 : index
      %ib20.d = memref.dim %a, %ib20.z : memref<?xi64>
      %ib20.n = arith.index_cast %ib20.d : index to i64
      %ib20 = idr.check.in_bounds %i, %ib20.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib20], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  func.func @halfBack(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %two = arith.constant 2 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %b = func.call @handBack(%a) : (memref<?xi64>) -> memref<?xi64>
    %pos = arith.cmpi sgt, %n, %z : i64
    %r = scf.if %pos -> !idr.world {
      %i = idr.div signed %n, %two : i64
      %ib21.z = arith.constant 0 : index
      %ib21.d = memref.dim %b, %ib21.z : memref<?xi64>
      %ib21.n = arith.index_cast %ib21.d : index to i64
      %ib21 = idr.check.in_bounds %i, %ib21.n, "array index out of bounds"
      %s1 = idr.array.set %b[%ib21], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  func.func @again(%a: memref<?xi64>, %i: i64, %w: !idr.world) -> !idr.world {
    %ib22.z = arith.constant 0 : index
    %ib22.d = memref.dim %a, %ib22.z : memref<?xi64>
    %ib22.n = arith.index_cast %ib22.d : index to i64
    %ib22 = idr.check.in_bounds %i, %ib22.n, "array index out of bounds"
    %v, %w1 = idr.array.get %a[%ib22], %w : memref<?xi64> -> i64
    %ib23.z = arith.constant 0 : index
    %ib23.d = memref.dim %a, %ib23.z : memref<?xi64>
    %ib23.n = arith.index_cast %ib23.d : index to i64
    %ib23 = idr.check.in_bounds %i, %ib23.n, "array index out of bounds"
    %w2 = idr.array.set %a[%ib23], %v, %w1 : memref<?xi64>, i64
    return %w2 : !idr.world
  }
}
