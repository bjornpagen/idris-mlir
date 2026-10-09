// RUN: idris-mlir-opt %s --idr-in-bounds --idr-expect=holds=in-bounds=@chained,in-bounds=@bridged,in-bounds=@measured,bounds-checked=@pastSize,bounds-checked=@otherMeasured -o /dev/null
// An array's size kept beside its backing, as a growable array keeps it:
// the index is checked against the size, then the access checks the
// guard's result against the backing's length.
// The program's test below the record's size proves both checks: the
// first by the path, the second because the first gave its index and the
// size the array was made with is its length.
// So does a test below the size the array was made with, which the
// backing's length bridges to the record's size.
// So does a size measured off a backing the caller passed, which is that
// backing's length however it was made.
// An index below the backing's length but not below the record's size
// keeps the check against the size; a size measured off some other array
// is not this one's length, and the access keeps its own check.
module {
  idr.data @Arr {
    idr.ctor @MkArray (i64, memref<?xi64>)
  }

  func.func @chained(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %o, %w1 = idr.array.new %n, %z, %w : i64 -> !idr.own<memref<?xi64>>
    %rec = idr.con @Arr::@MkArray(%n, %o) : (i64, !idr.own<memref<?xi64>>) -> !idr.own<!idr.data<@Arr>>
    %sz, %arr = idr.take %rec @Arr::@MkArray : !idr.own<!idr.data<@Arr>> -> (i64, !idr.own<memref<?xi64>>)
    %view = idr.borrow %arr : !idr.own<memref<?xi64>>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %sz : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %g1 = idr.check.in_bounds %i, %sz, "array index out of bounds"
      %c0 = arith.constant 0 : index
      %d = memref.dim %view, %c0 : memref<?xi64>
      %len = arith.index_cast %d : index to i64
      %g2 = idr.check.in_bounds %g1, %len, "array index out of bounds"
      %s = idr.array.set %view[%g2], %i, %w1 : memref<?xi64>, i64
      scf.yield %s : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    idr.drop %arr : !idr.own<memref<?xi64>>
    return %r : !idr.world
  }

  func.func @bridged(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %o, %w1 = idr.array.new %n, %z, %w : i64 -> !idr.own<memref<?xi64>>
    %rec = idr.con @Arr::@MkArray(%n, %o) : (i64, !idr.own<memref<?xi64>>) -> !idr.own<!idr.data<@Arr>>
    %sz, %arr = idr.take %rec @Arr::@MkArray : !idr.own<!idr.data<@Arr>> -> (i64, !idr.own<memref<?xi64>>)
    %view = idr.borrow %arr : !idr.own<memref<?xi64>>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %g1 = idr.check.in_bounds %i, %sz, "array index out of bounds"
      %c0 = arith.constant 0 : index
      %d = memref.dim %view, %c0 : memref<?xi64>
      %len = arith.index_cast %d : index to i64
      %g2 = idr.check.in_bounds %g1, %len, "array index out of bounds"
      %s = idr.array.set %view[%g2], %i, %w1 : memref<?xi64>, i64
      scf.yield %s : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    idr.drop %arr : !idr.own<memref<?xi64>>
    return %r : !idr.world
  }

  func.func @measured(%o: !idr.own<memref<?xi64>>, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %c0 = arith.constant 0 : index
    %ob = idr.borrow %o : !idr.own<memref<?xi64>>
    %od = memref.dim %ob, %c0 : memref<?xi64>
    %on = arith.index_cast %od : index to i64
    %rec = idr.con @Arr::@MkArray(%on, %o) : (i64, !idr.own<memref<?xi64>>) -> !idr.own<!idr.data<@Arr>>
    %sz, %arr = idr.take %rec @Arr::@MkArray : !idr.own<!idr.data<@Arr>> -> (i64, !idr.own<memref<?xi64>>)
    %view = idr.borrow %arr : !idr.own<memref<?xi64>>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %sz : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %g1 = idr.check.in_bounds %i, %sz, "array index out of bounds"
      %d = memref.dim %view, %c0 : memref<?xi64>
      %len = arith.index_cast %d : index to i64
      %g2 = idr.check.in_bounds %g1, %len, "array index out of bounds"
      %s = idr.array.set %view[%g2], %i, %w : memref<?xi64>, i64
      scf.yield %s : !idr.world
    } else {
      scf.yield %w : !idr.world
    }
    idr.drop %arr : !idr.own<memref<?xi64>>
    return %r : !idr.world
  }

  func.func @pastSize(%n: i64, %k: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %o, %w1 = idr.array.new %n, %z, %w : i64 -> !idr.own<memref<?xi64>>
    %rec = idr.con @Arr::@MkArray(%k, %o) : (i64, !idr.own<memref<?xi64>>) -> !idr.own<!idr.data<@Arr>>
    %sz, %arr = idr.take %rec @Arr::@MkArray : !idr.own<!idr.data<@Arr>> -> (i64, !idr.own<memref<?xi64>>)
    %view = idr.borrow %arr : !idr.own<memref<?xi64>>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %g1 = idr.check.in_bounds %i, %sz, "array index out of bounds"
      %c0 = arith.constant 0 : index
      %d = memref.dim %view, %c0 : memref<?xi64>
      %len = arith.index_cast %d : index to i64
      %g2 = idr.check.in_bounds %g1, %len, "array index out of bounds"
      %s = idr.array.set %view[%g2], %i, %w1 : memref<?xi64>, i64
      scf.yield %s : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    idr.drop %arr : !idr.own<memref<?xi64>>
    return %r : !idr.world
  }

  func.func @otherMeasured(%p: !idr.own<memref<?xi64>>, %n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %c0 = arith.constant 0 : index
    %pb = idr.borrow %p : !idr.own<memref<?xi64>>
    %pd = memref.dim %pb, %c0 : memref<?xi64>
    %pn = arith.index_cast %pd : index to i64
    %o, %w1 = idr.array.new %n, %z, %w : i64 -> !idr.own<memref<?xi64>>
    %rec = idr.con @Arr::@MkArray(%pn, %o) : (i64, !idr.own<memref<?xi64>>) -> !idr.own<!idr.data<@Arr>>
    %sz, %arr = idr.take %rec @Arr::@MkArray : !idr.own<!idr.data<@Arr>> -> (i64, !idr.own<memref<?xi64>>)
    %view = idr.borrow %arr : !idr.own<memref<?xi64>>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %sz : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %g1 = idr.check.in_bounds %i, %sz, "array index out of bounds"
      %d = memref.dim %view, %c0 : memref<?xi64>
      %len = arith.index_cast %d : index to i64
      %g2 = idr.check.in_bounds %g1, %len, "array index out of bounds"
      %s = idr.array.set %view[%g2], %i, %w1 : memref<?xi64>, i64
      scf.yield %s : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    idr.drop %arr : !idr.own<memref<?xi64>>
    idr.drop %p : !idr.own<memref<?xi64>>
    return %r : !idr.world
  }
}
