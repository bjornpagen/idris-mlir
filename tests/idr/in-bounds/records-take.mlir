// RUN: idris-mlir-opt %s --idr-in-bounds --idr-expect=holds=in-bounds=@taken,in-bounds=@takenArr -o /dev/null
// Taking a record apart yields the components its constructor stored.
// The size and the array are two fields, or the array is the record's
// only field and the size is the one it was made with.
module attributes {idr.stage = "owned"} {
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
      %s1 = idr.array.set %view[%i], %i, %w1 : memref<?xi64>, i64
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
      %s1 = idr.array.set %view[%i], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    idr.drop %arr : !idr.own<memref<?xi64>>
    return %r : !idr.world
  }
}
