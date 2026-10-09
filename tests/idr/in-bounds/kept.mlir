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
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi sle, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %ib1.z = arith.constant 0 : index
      %ib1.d = memref.dim %a, %ib1.z : memref<?xi64>
      %ib1.n = arith.index_cast %ib1.d : index to i64
      %ib1 = idr.check.in_bounds %i, %ib1.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib1], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  func.func @negativeIndex(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %ok = arith.cmpi slt, %i, %n : i64
    %r = scf.if %ok -> !idr.world {
      %ib2.z = arith.constant 0 : index
      %ib2.d = memref.dim %a, %ib2.z : memref<?xi64>
      %ib2.n = arith.index_cast %ib2.d : index to i64
      %ib2 = idr.check.in_bounds %i, %ib2.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib2], %i, %w1 : memref<?xi64>, i64
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
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %ok = arith.cmpi sgt, %n, %m5 : i64
    %r = scf.if %ok -> !idr.world {
      %ib3.z = arith.constant 0 : index
      %ib3.d = memref.dim %a, %ib3.z : memref<?xi64>
      %ib3.n = arith.index_cast %ib3.d : index to i64
      %ib3 = idr.check.in_bounds %z, %ib3.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib3], %z, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  func.func @calls(%n: i64, %m: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %c, %w2 = idr.array.new [%m], %z, %w1 : i64 -> memref<?xi64>
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
      %ib4.z = arith.constant 0 : index
      %ib4.d = memref.dim %a, %ib4.z : memref<?xi64>
      %ib4.n = arith.index_cast %ib4.d : index to i64
      %ib4 = idr.check.in_bounds %i, %ib4.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib4], %i, %w : memref<?xi64>, i64
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
      %ib5.z = arith.constant 0 : index
      %ib5.d = memref.dim %a, %ib5.z : memref<?xi64>
      %ib5.n = arith.index_cast %ib5.d : index to i64
      %ib5 = idr.check.in_bounds %i, %ib5.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib5], %i, %w : memref<?xi64>, i64
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
      %ib6.z = arith.constant 0 : index
      %ib6.d = memref.dim %a, %ib6.z : memref<?xi64>
      %ib6.n = arith.index_cast %ib6.d : index to i64
      %ib6 = idr.check.in_bounds %i, %ib6.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib6], %i, %w : memref<?xi64>, i64
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
      %ib7.z = arith.constant 0 : index
      %ib7.d = memref.dim %a, %ib7.z : memref<?xi64>
      %ib7.n = arith.index_cast %ib7.d : index to i64
      %ib7 = idr.check.in_bounds %i, %ib7.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib7], %i, %w : memref<?xi64>, i64
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
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %r:4 = scf.while (%k = %n, %arr = %a, %i = %z, %s = %w1) : (i64, memref<?xi64>, i64, !idr.world) -> (i64, memref<?xi64>, i64, !idr.world) {
      %lo = arith.cmpi sge, %i, %z : i64
      %hi = arith.cmpi slt, %i, %k : i64
      %c = arith.andi %lo, %hi : i1
      scf.condition(%c) %k, %arr, %i, %s : i64, memref<?xi64>, i64, !idr.world
    } do {
    ^bb0(%k: i64, %arr: memref<?xi64>, %i: i64, %s: !idr.world):
      %ib8.z = arith.constant 0 : index
      %ib8.d = memref.dim %arr, %ib8.z : memref<?xi64>
      %ib8.n = arith.index_cast %ib8.d : index to i64
      %ib8 = idr.check.in_bounds %i, %ib8.n, "array index out of bounds"
      %s1 = idr.array.set %arr[%ib8], %i, %s : memref<?xi64>, i64
      %j = arith.addi %i, %one overflow<nsw> : i64
      %k1 = arith.addi %k, %one overflow<nsw> : i64
      scf.yield %k1, %arr, %j, %s1 : i64, memref<?xi64>, i64, !idr.world
    }
    return %r#3 : !idr.world
  }

  func.func private @makeOff(%n: i64, %w: !idr.world) -> (i64, memref<?xi64>, !idr.world) {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
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
      %ib9.z = arith.constant 0 : index
      %ib9.d = memref.dim %a, %ib9.z : memref<?xi64>
      %ib9.n = arith.index_cast %ib9.d : index to i64
      %ib9 = idr.check.in_bounds %i, %ib9.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib9], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  func.func @otherSide(%p: i1, %q: i1, %n: i64, %m: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %c, %w2 = idr.array.new [%m], %z, %w1 : i64 -> memref<?xi64>
    %k = arith.select %p, %n, %m : i64
    %arr = arith.select %q, %a, %c : memref<?xi64>
    %some = arith.cmpi sgt, %k, %z : i64
    %r = scf.if %some -> !idr.world {
      %ib10.z = arith.constant 0 : index
      %ib10.d = memref.dim %arr, %ib10.z : memref<?xi64>
      %ib10.n = arith.index_cast %ib10.d : index to i64
      %ib10 = idr.check.in_bounds %z, %ib10.n, "array index out of bounds"
      %s1 = idr.array.set %arr[%ib10], %z, %w2 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w2 : !idr.world
    }
    return %r : !idr.world
  }

  func.func @unsignedSize(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %ok = arith.cmpi ult, %i, %n : i64
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

  // i + 1 below n proves i below n only without wrapping: at the largest
  // i, i + 1 is the least integer.
  func.func @wraps(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %j = arith.addi %i, %one : i64
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %j, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %ib12.z = arith.constant 0 : index
      %ib12.d = memref.dim %a, %ib12.z : memref<?xi64>
      %ib12.n = arith.index_cast %ib12.d : index to i64
      %ib12 = idr.check.in_bounds %i, %ib12.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib12], %i, %w1 : memref<?xi64>, i64
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
    %a, %w1 = idr.array.new [%five], %z, %w : i64 -> memref<?xi64>
    %k, %arr = scf.if %p -> (i64, memref<?xi64>) {
      scf.yield %five, %a : i64, memref<?xi64>
    } else {
      %u = ub.poison : i64
      scf.yield %u, %b : i64, memref<?xi64>
    }
    %ib13.z = arith.constant 0 : index
    %ib13.d = memref.dim %arr, %ib13.z : memref<?xi64>
    %ib13.n = arith.index_cast %ib13.d : index to i64
    %ib13 = idr.check.in_bounds %z, %ib13.n, "array index out of bounds"
    %s1 = idr.array.set %arr[%ib13], %z, %w1 : memref<?xi64>, i64
    return %s1 : !idr.world
  }

  // The before block passes on one more than the size the array was made
  // of, beside that array: the body writes one past its end.
  func.func @laterSize(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %a0, %w0 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %r:3 = scf.while (%m = %n, %arr = %a0, %s = %w0) : (i64, memref<?xi64>, !idr.world) -> (i64, memref<?xi64>, !idr.world) {
      %m1 = arith.addi %m, %one overflow<nsw> : i64
      %some = arith.cmpi sgt, %m1, %z : i64
      scf.condition(%some) %m1, %arr, %s : i64, memref<?xi64>, !idr.world
    } do {
    ^bb0(%k: i64, %arr: memref<?xi64>, %s: !idr.world):
      %last = arith.subi %k, %one : i64
      %ib14.z = arith.constant 0 : index
      %ib14.d = memref.dim %arr, %ib14.z : memref<?xi64>
      %ib14.n = arith.index_cast %ib14.d : index to i64
      %ib14 = idr.check.in_bounds %last, %ib14.n, "array index out of bounds"
      %s1 = idr.array.set %arr[%ib14], %z, %s : memref<?xi64>, i64
      %b, %s2 = idr.array.new [%k], %z, %s1 : i64 -> memref<?xi64>
      scf.yield %k, %b, %s2 : i64, memref<?xi64>, !idr.world
    }
    return %r#2 : !idr.world
  }

  func.func private @handOther(%a: memref<?xi64>, %c: memref<?xi64>) -> memref<?xi64> {
    return %c : memref<?xi64>
  }
  func.func @returnedOther(%n: i64, %m: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %c, %w2 = idr.array.new [%m], %z, %w1 : i64 -> memref<?xi64>
    %b = func.call @handOther(%a, %c) : (memref<?xi64>, memref<?xi64>) -> memref<?xi64>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %ib15.z = arith.constant 0 : index
      %ib15.d = memref.dim %b, %ib15.z : memref<?xi64>
      %ib15.n = arith.index_cast %ib15.d : index to i64
      %ib15 = idr.check.in_bounds %i, %ib15.n, "array index out of bounds"
      %s1 = idr.array.set %b[%ib15], %i, %w2 : memref<?xi64>, i64
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
      %c, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
      idr.yield %c, %w1 : memref<?xi64>, !idr.world
    }
    }
    return %r#0, %r#1 : memref<?xi64>, !idr.world
  }
  func.func @returnedEither(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %b, %w2 = func.call @handEither(%a, %n, %w1) : (memref<?xi64>, i64, !idr.world) -> (memref<?xi64>, !idr.world)
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %ib16.z = arith.constant 0 : index
      %ib16.d = memref.dim %b, %ib16.z : memref<?xi64>
      %ib16.n = arith.index_cast %ib16.d : index to i64
      %ib16 = idr.check.in_bounds %i, %ib16.n, "array index out of bounds"
      %s1 = idr.array.set %b[%ib16], %i, %w2 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w2 : !idr.world
    }
    return %r : !idr.world
  }

  func.func private @handFresh(%n: i64, %w: !idr.world) -> (memref<?xi64>, !idr.world) {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    return %a, %w1 : memref<?xi64>, !idr.world
  }
  // `n >= 0` includes 0, and `0 / 2` is not inside an empty array.
  func.func @halfZero(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %two = arith.constant 2 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %nonneg = arith.cmpi sge, %n, %z : i64
    %r = scf.if %nonneg -> !idr.world {
      %i = idr.div signed %n, %two : i64
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

  // `m < 16` still allows a negative `m`, whose quotient is negative.
  func.func @underSixteen(%m: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %n = arith.constant 100 : i64
    %two = arith.constant 2 : i64
    %bound = arith.constant 16 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %below = arith.cmpi slt, %m, %bound : i64
    %r = scf.if %below -> !idr.world {
      %i = idr.div signed %m, %two : i64
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

  // Dividing by 1 leaves the length, which is not an index into it.
  func.func @byOne(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %pos = arith.cmpi sgt, %n, %z : i64
    %r = scf.if %pos -> !idr.world {
      %i = idr.div signed %n, %one : i64
      %ib19.z = arith.constant 0 : index
      %ib19.d = memref.dim %a, %ib19.z : memref<?xi64>
      %ib19.n = arith.index_cast %ib19.d : index to i64
      %ib19 = idr.check.in_bounds %i, %ib19.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib19], %i, %w1 : memref<?xi64>, i64
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
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %pos = arith.cmpi sgt, %n, %z : i64
    %r = scf.if %pos -> !idr.world {
      %i = idr.div signed %n, %m2 : i64
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

  func.func @byUnknown(%n: i64, %d: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %pos = arith.cmpi sgt, %n, %z : i64
    %r = scf.if %pos -> !idr.world {
      %i = idr.div signed %n, %d : i64
      %ib21.z = arith.constant 0 : index
      %ib21.d = memref.dim %a, %ib21.z : memref<?xi64>
      %ib21.n = arith.index_cast %ib21.d : index to i64
      %ib21 = idr.check.in_bounds %i, %ib21.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib21], %i, %w1 : memref<?xi64>, i64
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
    %ib22.z = arith.constant 0 : index
    %ib22.d = memref.dim %a, %ib22.z : memref<?xi64>
    %ib22.n = arith.index_cast %ib22.d : index to i64
    %ib22 = idr.check.in_bounds %i, %ib22.n, "array index out of bounds"
    %s = idr.array.set %a[%ib22], %i, %w : memref<?xi64>, i64
    return %s : !idr.world
  }

  // Unsigned `n > 0` holds for a negative signed `n`. That size is not
  // known non-negative, so its quotient is not a length.
  func.func @unsignedPositive(%n: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %two = arith.constant 2 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %pos = arith.cmpi ugt, %n, %z : i64
    %r = scf.if %pos -> !idr.world {
      %i = idr.div signed %n, %two : i64
      %ib23.z = arith.constant 0 : index
      %ib23.d = memref.dim %a, %ib23.z : memref<?xi64>
      %ib23.n = arith.index_cast %ib23.d : index to i64
      %ib23 = idr.check.in_bounds %i, %ib23.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib23], %i, %w1 : memref<?xi64>, i64
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
      %ib24.z = arith.constant 0 : index
      %ib24.d = memref.dim %a, %ib24.z : memref<?xi64>
      %ib24.n = arith.index_cast %ib24.d : index to i64
      %ib24 = idr.check.in_bounds %i, %ib24.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib24], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }
}
