// RUN: idris-mlir-opt %s --idr-in-bounds --idr-expect=holds=in-bounds=@byTwo,in-bounds=@byShift,in-bounds=@twice,in-bounds=@bounded,bounds-checked=@notPower,bounds-checked=@onlyPositive,bounds-checked=@overflow,bounds-checked=@signBit -o /dev/null
// Doubling a positive power of two stays one when the double cannot reach
// the sign. A multiply by 2, or a shift left by 1, of a shift of 1 whose
// amount the path keeps in 0..61 is at most 2^62. One more such step stays
// inside that bound when the amount is in 0..60. A path that keeps the
// shifted word itself below 2^62 leaves the same room. A start that is not
// a power of two, a start only known positive, a shift whose amount may be
// 62, and the constant 2^62 doubled all stay checked: the double may be
// the sign bit, or was never a power of two.
module {
  func.func @byTwo(%k: i64, %x: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %lim = arith.constant 61 : i64
    %lo = arith.cmpi sge, %k, %z : i64
    %hi = arith.cmpi sle, %k, %lim : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %pow = idr.shl signed %one, %k : i64
      %cap = arith.muli %two, %pow : i64
      %a, %w1 = idr.array.new [%cap], %z, %w : i64 -> memref<?xi64>
      %mask = arith.subi %cap, %one : i64
      %i = arith.andi %x, %mask : i64
      %ib1.z = arith.constant 0 : index
      %ib1.d = memref.dim %a, %ib1.z : memref<?xi64>
      %ib1.n = arith.index_cast %ib1.d : index to i64
      %ib1 = idr.check.in_bounds %i, %ib1.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib1], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w : !idr.world
    }
    return %r : !idr.world
  }

  func.func @byShift(%k: i64, %x: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %lim = arith.constant 61 : i64
    %lo = arith.cmpi sge, %k, %z : i64
    %hi = arith.cmpi sle, %k, %lim : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %pow = idr.shl signed %one, %k : i64
      %cap = idr.shl signed %pow, %one : i64
      %a, %w1 = idr.array.new [%cap], %z, %w : i64 -> memref<?xi64>
      %mask = arith.subi %cap, %one : i64
      %i = arith.andi %mask, %x : i64
      %ib2.z = arith.constant 0 : index
      %ib2.d = memref.dim %a, %ib2.z : memref<?xi64>
      %ib2.n = arith.index_cast %ib2.d : index to i64
      %ib2 = idr.check.in_bounds %i, %ib2.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib2], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w : !idr.world
    }
    return %r : !idr.world
  }

  func.func @twice(%k: i64, %x: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %lim = arith.constant 60 : i64
    %lo = arith.cmpi sge, %k, %z : i64
    %hi = arith.cmpi sle, %k, %lim : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %pow = idr.shl signed %one, %k : i64
      %once = arith.muli %pow, %two : i64
      %cap = arith.muli %once, %two : i64
      %a, %w1 = idr.array.new [%cap], %z, %w : i64 -> memref<?xi64>
      %mask = arith.subi %cap, %one : i64
      %i = arith.andi %x, %mask : i64
      %ib3.z = arith.constant 0 : index
      %ib3.d = memref.dim %a, %ib3.z : memref<?xi64>
      %ib3.n = arith.index_cast %ib3.d : index to i64
      %ib3 = idr.check.in_bounds %i, %ib3.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib3], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w : !idr.world
    }
    return %r : !idr.world
  }

  // 2^62, one past the powers a double of this word can still be.
  func.func @bounded(%k: i64, %x: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %lim = arith.constant 62 : i64
    %below = arith.constant 4611686018427387904 : i64
    %lo = arith.cmpi sge, %k, %z : i64
    %hi = arith.cmpi sle, %k, %lim : i64
    %pow = idr.shl signed %one, %k : i64
    %fit = arith.cmpi slt, %pow, %below : i64
    %span = arith.andi %lo, %hi : i1
    %ok = arith.andi %span, %fit : i1
    %r = scf.if %ok -> !idr.world {
      %cap = arith.muli %pow, %two : i64
      %a, %w1 = idr.array.new [%cap], %z, %w : i64 -> memref<?xi64>
      %mask = arith.subi %cap, %one : i64
      %i = arith.andi %x, %mask : i64
      %ib4.z = arith.constant 0 : index
      %ib4.d = memref.dim %a, %ib4.z : memref<?xi64>
      %ib4.n = arith.index_cast %ib4.d : index to i64
      %ib4 = idr.check.in_bounds %i, %ib4.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib4], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w : !idr.world
    }
    return %r : !idr.world
  }

  func.func @notPower(%x: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %six = arith.constant 6 : i64
    %cap = arith.muli %six, %two : i64
    %a, %w1 = idr.array.new [%cap], %z, %w : i64 -> memref<?xi64>
    %mask = arith.subi %cap, %one : i64
    %i = arith.andi %x, %mask : i64
    %ib5.z = arith.constant 0 : index
    %ib5.d = memref.dim %a, %ib5.z : memref<?xi64>
    %ib5.n = arith.index_cast %ib5.d : index to i64
    %ib5 = idr.check.in_bounds %i, %ib5.n, "array index out of bounds"
    %s1 = idr.array.set %a[%ib5], %i, %w1 : memref<?xi64>, i64
    return %s1 : !idr.world
  }

  func.func @onlyPositive(%n: i64, %x: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %pos = arith.cmpi sgt, %n, %z : i64
    %r = scf.if %pos -> !idr.world {
      %cap = arith.muli %n, %two : i64
      %a, %w1 = idr.array.new [%cap], %z, %w : i64 -> memref<?xi64>
      %mask = arith.subi %cap, %one : i64
      %i = arith.andi %x, %mask : i64
      %ib6.z = arith.constant 0 : index
      %ib6.d = memref.dim %a, %ib6.z : memref<?xi64>
      %ib6.n = arith.index_cast %ib6.d : index to i64
      %ib6 = idr.check.in_bounds %i, %ib6.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib6], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w : !idr.world
    }
    return %r : !idr.world
  }

  func.func @overflow(%k: i64, %x: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %lim = arith.constant 62 : i64
    %lo = arith.cmpi sge, %k, %z : i64
    %hi = arith.cmpi sle, %k, %lim : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %pow = idr.shl signed %one, %k : i64
      %cap = arith.muli %pow, %two : i64
      %a, %w1 = idr.array.new [%cap], %z, %w : i64 -> memref<?xi64>
      %mask = arith.subi %cap, %one : i64
      %i = arith.andi %x, %mask : i64
      %ib7.z = arith.constant 0 : index
      %ib7.d = memref.dim %a, %ib7.z : memref<?xi64>
      %ib7.n = arith.index_cast %ib7.d : index to i64
      %ib7 = idr.check.in_bounds %i, %ib7.n, "array index out of bounds"
      %s1 = idr.array.set %a[%ib7], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w : !idr.world
    }
    return %r : !idr.world
  }

  func.func @signBit(%x: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %bit = arith.constant 62 : i64
    %pow = idr.shl signed %one, %bit : i64
    %cap = arith.muli %pow, %two : i64
    %a, %w1 = idr.array.new [%cap], %z, %w : i64 -> memref<?xi64>
    %mask = arith.subi %cap, %one : i64
    %i = arith.andi %x, %mask : i64
    %ib8.z = arith.constant 0 : index
    %ib8.d = memref.dim %a, %ib8.z : memref<?xi64>
    %ib8.n = arith.index_cast %ib8.d : index to i64
    %ib8 = idr.check.in_bounds %i, %ib8.n, "array index out of bounds"
    %s1 = idr.array.set %a[%ib8], %i, %w1 : memref<?xi64>, i64
    return %s1 : !idr.world
  }
}
