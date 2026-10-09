// RUN: idris-mlir-opt %s --idr-in-bounds --idr-expect=holds=in-bounds=@taken,in-bounds=@takenArr -o /dev/null
// Taking a record apart yields the components its constructor stored.
// The size and the array are two fields, or the array is the record's
// only field and the size is the one it was made with.
module {
  idr.data @Pair {
    idr.ctor @MkPair (i64, memref<?xi64>)
  }
  idr.data @Arr {
    idr.ctor @MkArr (memref<?xi64>)
  }

  func.func @taken(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %o, %w1 = idr.array.new %n, %z, %w : i64 -> !idr.own<memref<?xi64>>
    %rec = idr.con @Pair::@MkPair(%n, %o) : (i64, !idr.own<memref<?xi64>>) -> !idr.own<!idr.data<@Pair>>
    %sz, %arr = idr.take %rec @Pair::@MkPair : !idr.own<!idr.data<@Pair>> -> (i64, !idr.own<memref<?xi64>>)
    %view = idr.borrow %arr : !idr.own<memref<?xi64>>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %sz : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %ib1.z = arith.constant 0 : index
      %ib1.d = memref.dim %view, %ib1.z : memref<?xi64>
      %ib1.n = arith.index_cast %ib1.d : index to i64
      %ib1 = idr.check.in_bounds %i, %ib1.n, "array index out of bounds"
      %s1 = idr.array.set %view[%ib1], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    idr.drop %arr : !idr.own<memref<?xi64>>
    return %r : !idr.world
  }

  func.func @takenArr(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %o, %w1 = idr.array.new %n, %z, %w : i64 -> !idr.own<memref<?xi64>>
    %rec = idr.con @Arr::@MkArr(%o) : (!idr.own<memref<?xi64>>) -> !idr.own<!idr.data<@Arr>>
    %arr = idr.take %rec @Arr::@MkArr : !idr.own<!idr.data<@Arr>> -> (!idr.own<memref<?xi64>>)
    %view = idr.borrow %arr : !idr.own<memref<?xi64>>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi slt, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %ib2.z = arith.constant 0 : index
      %ib2.d = memref.dim %view, %ib2.z : memref<?xi64>
      %ib2.n = arith.index_cast %ib2.d : index to i64
      %ib2 = idr.check.in_bounds %i, %ib2.n, "array index out of bounds"
      %s1 = idr.array.set %view[%ib2], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    idr.drop %arr : !idr.own<memref<?xi64>>
    return %r : !idr.world
  }
}
