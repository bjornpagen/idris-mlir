// RUN: idris-mlir-opt %s --idr-in-bounds --idr-expect=holds=bounds-checked=@onePast,bounds-checked=@negativeIndex,bounds-checked=@negativeSize,bounds-checked=@unrelated,bounds-checked=@mixed,bounds-checked=@public,bounds-checked=@taken,bounds-checked=@backEdge,bounds-checked=@madeOff,bounds-checked=@otherSide,bounds-checked=@unsignedSize,bounds-checked=@wraps,bounds-checked=@poisonSize,bounds-checked=@laterSize -o /dev/null
// Each access here may run with its index outside its array, so each keeps
// its check: one past the end; below 0; an empty array of a negative size;
// the size of another array, passed at the one call, at one call of two,
// or to a function anyone may call (public, or its address taken); a loop
// that changes the size it carries and not the array; a size returned one
// above the array's; a size and an array chosen by different conditions;
// an unsigned index below a negative size, which is any index; a size
// that wraps; a size poison on one path, beside an array; and a size a
// loop's before block computes anew beside the array it carries.
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
}
