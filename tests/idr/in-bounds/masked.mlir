// RUN: idris-mlir-opt %s --idr-in-bounds --idr-expect=holds=in-bounds=@shifted,in-bounds=@eight,bounds-checked=@any,bounds-checked=@sign,bounds-checked=@six -o /dev/null
// `x & (c - 1)` is inside an array of length `c` when `c` is a positive
// power of two: the low bits of any word are a remainder below that power.
// A shift of 1 by an amount the path keeps in 0..62 is that power, and so
// is the constant 8, on either side of the and. A capacity only shown
// positive, a shift of 1 that may land on the sign, and the constant 6 are
// not powers of two the facts already have, so those masks stay checked.
module {
  func.func @shifted(%k: i64, %x: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %lim = arith.constant 62 : i64
    %lo = arith.cmpi sge, %k, %z : i64
    %hi = arith.cmpi sle, %k, %lim : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %cap = idr.shl signed %one, %k : i64
      %a, %w1 = idr.array.new %cap, %z, %w : i64 -> memref<?xi64>
      %mask = arith.subi %cap, %one : i64
      %j = arith.addi %x, %one : i64
      %i = arith.andi %j, %mask : i64
      %s1 = idr.array.set %a[%i], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w : !idr.world
    }
    return %r : !idr.world
  }

  func.func @eight(%x: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %cap = arith.constant 8 : i64
    %a, %w1 = idr.array.new %cap, %z, %w : i64 -> memref<?xi64>
    %mask = arith.subi %cap, %one : i64
    %i = arith.andi %mask, %x : i64
    %s1 = idr.array.set %a[%i], %i, %w1 : memref<?xi64>, i64
    return %s1 : !idr.world
  }

  func.func @any(%n: i64, %x: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %pos = arith.cmpi sgt, %n, %z : i64
    %r = scf.if %pos -> !idr.world {
      %mask = arith.subi %n, %one : i64
      %i = arith.andi %x, %mask : i64
      %s1 = idr.array.set %a[%i], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }

  // A shift by 63 sets the sign. The capacity may be the smallest word,
  // and the array made from it is then empty.
  func.func @sign(%k: i64, %x: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %lim = arith.constant 63 : i64
    %lo = arith.cmpi sge, %k, %z : i64
    %hi = arith.cmpi sle, %k, %lim : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %cap = idr.shl signed %one, %k : i64
      %a, %w1 = idr.array.new %cap, %z, %w : i64 -> memref<?xi64>
      %mask = arith.subi %cap, %one : i64
      %i = arith.andi %x, %mask : i64
      %s1 = idr.array.set %a[%i], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w : !idr.world
    }
    return %r : !idr.world
  }

  func.func @six(%x: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %cap = arith.constant 6 : i64
    %a, %w1 = idr.array.new %cap, %z, %w : i64 -> memref<?xi64>
    %mask = arith.subi %cap, %one : i64
    %i = arith.andi %x, %mask : i64
    %s1 = idr.array.set %a[%i], %i, %w1 : memref<?xi64>, i64
    return %s1 : !idr.world
  }
}
