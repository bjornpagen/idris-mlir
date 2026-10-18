// NEEDS-ACCEPTANCE: a sum with zero folds to its other operand on either side, of Integers and of naturals; the property fails where idr.big.add folds only constant pairs.
// RUN: idris-mlir-opt %s --canonicalize '--idr-expect=holds=returns-argument=@plus_zero:0,returns-argument=@zero_plus:0,returns-argument=@nat_plus_zero:0' -o /dev/null
// A sum with zero is its other operand, whichever side the zero is on: a
// fact of idr.big.add, which its folder states, so every pass that builds
// x + 0 meets x. Each zero is a small made of a constant word.
idr.program @"add-zero" root(@root) stage(first) {
  idr.func @plus_zero(%x: !idr.big) -> !idr.big {
    %c0 = arith.constant 0 : i64
    %zero = idr.big.small %c0 : !idr.big
    %r = idr.big.add %x, %zero
    return %r : !idr.big
  }

  idr.func @zero_plus(%x: !idr.big) -> !idr.big {
    %c0 = arith.constant 0 : i64
    %zero = idr.big.small %c0 : !idr.big
    %r = idr.big.add %zero, %x
    return %r : !idr.big
  }

  idr.func @nat_plus_zero(%x: !idr.nat) -> !idr.nat {
    %c0 = arith.constant 0 : i64
    %zero = idr.big.small %c0 : !idr.nat
    %r = idr.big.add %x, %zero : !idr.nat
    return %r : !idr.nat
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
