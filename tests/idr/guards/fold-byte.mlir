// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns=@proving:-1,no-guards=@proving,crash-sites=@failing:2,crash-sites=@again:1 -o /dev/null
// The guard of an Int written as a byte folds to the Int where it is a
// constant from 0 to 255; then the byte folds too. Above 255, or below 0,
// the guard stays, to crash where it runs. A guard of what an identical
// guard already checked folds too.
idr.program @"fold-byte" root(@root) stage(first) {
  idr.func @proving() -> i8 {
    %x = arith.constant 255 : i64
    %g = idr.check.byte %x, "a byte outside 0 to 255"
    %b = idr.to_byte %g
    return %b : i8
  }

  idr.func @failing() -> (i8, i8) {
    %above = arith.constant 256 : i64
    %g = idr.check.byte %above, "a byte outside 0 to 255"
    %b = idr.to_byte %g
    %below = arith.constant -1 : i64
    %h = idr.check.byte %below, "a byte outside 0 to 255"
    %c = idr.to_byte %h
    return %b, %c : i8, i8
  }

  idr.func @again(%x: i64) -> (i8, i8) {
    %g = idr.check.byte %x, "a byte outside 0 to 255"
    %b = idr.to_byte %g
    %h = idr.check.byte %g, "a byte outside 0 to 255"
    %c = idr.to_byte %h
    return %b, %c : i8, i8
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
