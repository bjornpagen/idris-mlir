// RUN: idris-mlir-opt %s --idr-in-bounds --idr-expect=holds=bounds-checked=@onePast,bounds-checked=@negativeIndex,bounds-checked=@negativeSize,bounds-checked=@unrelated,bounds-checked=@mixed,bounds-checked=@public,bounds-checked=@taken,bounds-checked=@backEdge,bounds-checked=@madeOff,bounds-checked=@otherSide,bounds-checked=@unsignedSize,bounds-checked=@wraps,bounds-checked=@poisonSize,bounds-checked=@laterSize,bounds-checked=@returnedOther,bounds-checked=@returnedEither,bounds-checked=@returnedFresh,bounds-checked=@halfZero,bounds-checked=@underSixteen,bounds-checked=@byOne,bounds-checked=@byNegative,bounds-checked=@byUnknown,bounds-checked=@dimZero,bounds-checked=@unsignedPositive -o /dev/null
// Each access here may run with its index outside its array, so each keeps
// its check: one past the end; below 0; an empty array of a negative size;
// the size of another array, passed at the one call, at one call of two,
// or to a function anyone may call (public, or its address taken); a loop
// that changes the size it carries and not the array; a size returned one
// above the array's; a size and an array chosen by different conditions;
// an unsigned index below a negative size, which is any index; a size
// that wraps; a size poison on one path, beside an array; and a size a
// loop's before block computes anew beside the array it carries. A call
// that returns a different array, either the argument or another array,
// or an array it allocated, does not keep the caller's length. A quotient
// stays checked when the length may be 0, when the dividend may be
// negative, when the divisor is 1 or negative or not a constant, and when
// an unsigned test of the size does not make that size non-negative.
module {
  func.func @onePast(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi sle, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %s1 = idr.array.set %a[%i], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  func.func @negativeIndex(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %ok = arith.cmpi slt, %i, %n : i64
    %r = scf.if %ok -> !idr.world {
      %s1 = idr.array.set %a[%i], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  // Above -5 is not above 0: a size of -3 makes an empty array.
  func.func @negativeSize(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %m5 = arith.constant -5 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %ok = arith.cmpi sgt, %n, %m5 : i64
    %r = scf.if %ok -> !idr.world {
      %s1 = idr.array.set %a[%z], %z, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  func.func @calls(%n: i64, %m: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %c, %w2 = idr.array.new %m, %z, %w1 : i64 -> memref<?xi64>
    %w3 = func.call @unrelated(%m, %a, %i, %w2) : (i64, memref<?xi64>, i64, !idr.world) -> !idr.world
    %w4 = func.call @mixed(%n, %a, %i, %w3) : (i64, memref<?xi64>, i64, !idr.world) -> !idr.world
    %w5 = func.call @mixed(%n, %c, %i, %w4) : (i64, memref<?xi64>, i64, !idr.world) -> !idr.world
    %w6 = func.call @taken(%n, %a, %i, %w5) : (i64, memref<?xi64>, i64, !idr.world) -> !idr.world
    %w7 = func.call @public(%n, %a, %i, %w6) : (i64, memref<?xi64>, i64, !idr.world) -> !idr.world
    %f = idr.closure @taken() : () -> !idr.fn<(i64, memref<?xi64>, i64, !idr.world) -> (!idr.world)>
    return %w7 : !idr.world
  }
  func.func private @unrelated(%n: i64, %a: memref<?xi64>, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %s1 = idr.array.set %a[%i], %i, %w : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w : !idr.world
    }
    return %r : !idr.world
  }
  func.func private @mixed(%n: i64, %a: memref<?xi64>, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %s1 = idr.array.set %a[%i], %i, %w : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w : !idr.world
    }
    return %r : !idr.world
  }
  func.func private @taken(%n: i64, %a: memref<?xi64>, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %s1 = idr.array.set %a[%i], %i, %w : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w : !idr.world
    }
    return %r : !idr.world
  }
  func.func @public(%n: i64, %a: memref<?xi64>, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %s1 = idr.array.set %a[%i], %i, %w : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w : !idr.world
    }
    return %r : !idr.world
  }

  // The size grows each time round; the array does not.
  func.func @backEdge(%n: i64, %w: !idr.world) -> !idr.world {
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
      %k1 = arith.addi %k, %one overflow<nsw> : i64
      scf.yield %k1, %arr, %j, %s1 : i64, memref<?xi64>, i64, !idr.world
    }
    return %r#3 : !idr.world
  }

  func.func private @makeOff(%n: i64, %w: !idr.world) -> (i64, memref<?xi64>, !idr.world) {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %k = arith.addi %n, %one : i64
    return %k, %a, %w1 : i64, memref<?xi64>, !idr.world
  }
  func.func @madeOff(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %k, %a, %w1 = func.call @makeOff(%n, %w) : (i64, !idr.world) -> (i64, memref<?xi64>, !idr.world)
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

  func.func @otherSide(%p: i1, %q: i1, %n: i64, %m: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %c, %w2 = idr.array.new %m, %z, %w1 : i64 -> memref<?xi64>
    %k = arith.select %p, %n, %m : i64
    %arr = arith.select %q, %a, %c : memref<?xi64>
    %some = arith.cmpi sgt, %k, %z : i64
    %r = scf.if %some -> !idr.world {
      %s1 = idr.array.set %arr[%z], %z, %w2 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w2 : !idr.world
    }
    return %r : !idr.world
  }

  func.func @unsignedSize(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %ok = arith.cmpi ult, %i, %n : i64
    %r = scf.if %ok -> !idr.world {
      %s1 = idr.array.set %a[%i], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  // i + 1 below n proves i below n only without wrapping: at the largest
  // i, i + 1 is the least integer.
  func.func @wraps(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %j = arith.addi %i, %one : i64
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %j, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %s1 = idr.array.set %a[%i], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  // The array is real on both paths, the size poison on one: nothing
  // branches on the size, so nothing makes that path no run.
  func.func @poisonSize(%p: i1, %b: memref<?xi64>, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %five = arith.constant 5 : i64
    %a, %w1 = idr.array.new %five, %z, %w : i64 -> memref<?xi64>
    %k, %arr = scf.if %p -> (i64, memref<?xi64>) {
      scf.yield %five, %a : i64, memref<?xi64>
    } else {
      %u = ub.poison : i64
      scf.yield %u, %b : i64, memref<?xi64>
    }
    %s1 = idr.array.set %arr[%z], %z, %w1 : memref<?xi64>, i64
    return %s1 : !idr.world
  }

  // The before block passes on one more than the size the array was made
  // of, beside that array: the body writes one past its end.
  func.func @laterSize(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %a0, %w0 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %r:3 = scf.while (%m = %n, %arr = %a0, %s = %w0) : (i64, memref<?xi64>, !idr.world) -> (i64, memref<?xi64>, !idr.world) {
      %m1 = arith.addi %m, %one overflow<nsw> : i64
      %some = arith.cmpi sgt, %m1, %z : i64
      scf.condition(%some) %m1, %arr, %s : i64, memref<?xi64>, !idr.world
    } do {
    ^bb0(%k: i64, %arr: memref<?xi64>, %s: !idr.world):
      %last = arith.subi %k, %one : i64
      %s1 = idr.array.set %arr[%last], %z, %s : memref<?xi64>, i64
      %b, %s2 = idr.array.new %k, %z, %s1 : i64 -> memref<?xi64>
      scf.yield %k, %b, %s2 : i64, memref<?xi64>, !idr.world
    }
    return %r#2 : !idr.world
  }

  func.func private @handOther(%a: memref<?xi64>, %c: memref<?xi64>) -> memref<?xi64> {
    return %c : memref<?xi64>
  }
  func.func @returnedOther(%n: i64, %m: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %c, %w2 = idr.array.new %m, %z, %w1 : i64 -> memref<?xi64>
    %b = func.call @handOther(%a, %c) : (memref<?xi64>, memref<?xi64>) -> memref<?xi64>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %s1 = idr.array.set %b[%i], %i, %w2 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w2 : !idr.world
    }
    return %r : !idr.world
  }

  func.func private @handEither(%a: memref<?xi64>, %n: i64, %w: !idr.world) -> (memref<?xi64>, !idr.world) {
    %z = arith.constant 0 : i64
    %neg = arith.cmpi slt, %n, %z : i64
    %negI = arith.extui %neg : i1 to i64
    %r:2 = idr.match_lit %negI : i64 -> (memref<?xi64>, !idr.world) {
    case 0 {
      idr.yield %a, %w : memref<?xi64>, !idr.world
    }
    default {
      %c, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
      idr.yield %c, %w1 : memref<?xi64>, !idr.world
    }
    }
    return %r#0, %r#1 : memref<?xi64>, !idr.world
  }
  func.func @returnedEither(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %b, %w2 = func.call @handEither(%a, %n, %w1) : (memref<?xi64>, i64, !idr.world) -> (memref<?xi64>, !idr.world)
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %s1 = idr.array.set %b[%i], %i, %w2 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w2 : !idr.world
    }
    return %r : !idr.world
  }

  func.func private @handFresh(%n: i64, %w: !idr.world) -> (memref<?xi64>, !idr.world) {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    return %a, %w1 : memref<?xi64>, !idr.world
  }
  // `n >= 0` includes 0, and `0 / 2` is not inside an empty array.
  func.func @halfZero(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %two = arith.constant 2 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %nonneg = arith.cmpi sge, %n, %z : i64
    %r = scf.if %nonneg -> !idr.world {
      %i = idr.div signed %n, %two : i64
      %s1 = idr.array.set %a[%i], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  // `m < 16` still allows a negative `m`, whose quotient is negative.
  func.func @underSixteen(%m: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %n = arith.constant 100 : i64
    %two = arith.constant 2 : i64
    %bound = arith.constant 16 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %below = arith.cmpi slt, %m, %bound : i64
    %r = scf.if %below -> !idr.world {
      %i = idr.div signed %m, %two : i64
      %s1 = idr.array.set %a[%i], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  // Dividing by 1 leaves the length, which is not an index into it.
  func.func @byOne(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %pos = arith.cmpi sgt, %n, %z : i64
    %r = scf.if %pos -> !idr.world {
      %i = idr.div signed %n, %one : i64
      %s1 = idr.array.set %a[%i], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  // A negative divisor's Euclidean quotient is not the positive one.
  func.func @byNegative(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %m2 = arith.constant -2 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %pos = arith.cmpi sgt, %n, %z : i64
    %r = scf.if %pos -> !idr.world {
      %i = idr.div signed %n, %m2 : i64
      %s1 = idr.array.set %a[%i], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  func.func @byUnknown(%n: i64, %d: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %pos = arith.cmpi sgt, %n, %z : i64
    %r = scf.if %pos -> !idr.world {
      %i = idr.div signed %n, %d : i64
      %s1 = idr.array.set %a[%i], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  // The length is non-negative, and it may still be 0.
  func.func @dimZero(%a: memref<?xi64>, %w: !idr.world) -> !idr.world {
    %c0 = arith.constant 0 : index
    %two = arith.constant 2 : i64
    %len = memref.dim %a, %c0 : memref<?xi64>
    %l = arith.index_cast %len : index to i64
    %i = idr.div signed %l, %two : i64
    %s = idr.array.set %a[%i], %i, %w : memref<?xi64>, i64
    return %s : !idr.world
  }

  // Unsigned `n > 0` holds for a negative signed `n`. That size is not
  // known non-negative, so its quotient is not a length.
  func.func @unsignedPositive(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %two = arith.constant 2 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %pos = arith.cmpi ugt, %n, %z : i64
    %r = scf.if %pos -> !idr.world {
      %i = idr.div signed %n, %two : i64
      %s1 = idr.array.set %a[%i], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  func.func @returnedFresh(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = func.call @handFresh(%n, %w) : (i64, !idr.world) -> (memref<?xi64>, !idr.world)
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
}
