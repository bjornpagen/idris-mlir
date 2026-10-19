// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns=@proving:4/4,no-guards=@proving,crash-sites=@failing:3,crash-sites=@again:1 -o /dev/null
// The guard of a byte range folds to its offset where the offset, the
// count and the size are constants and the range lies in the size: both at
// least 0, and their sum, without overflow, at most the size. A range past
// the size, a negative offset, and one whose end overflows keep their
// guard, to crash where it runs. A guard of what an identical guard, of the
// same count and size, already checked folds too.
idr.program @"fold-range" root(@root) stage(first) {
  idr.func @proving() -> (i64, i64) {
    %four = arith.constant 4 : i64
    %eight = arith.constant 8 : i64
    %zero = arith.constant 0 : i64
    %g = idr.check.range %four, %four, %eight, "a byte range outside the buffer"
    %h = idr.check.range %four, %zero, %four, "a byte range outside the buffer"
    return %g, %h : i64, i64
  }

  idr.func @failing() -> (i64, i64, i64) {
    %five = arith.constant 5 : i64
    %four = arith.constant 4 : i64
    %eight = arith.constant 8 : i64
    %g = idr.check.range %five, %four, %eight, "a byte range outside the buffer"
    %below = arith.constant -1 : i64
    %one = arith.constant 1 : i64
    %h = idr.check.range %below, %one, %eight, "a byte range outside the buffer"
    %largest = arith.constant 9223372036854775807 : i64
    %k = idr.check.range %largest, %one, %largest, "a byte range outside the buffer"
    return %g, %h, %k : i64, i64, i64
  }

  idr.func @again(%o: i64, %n: i64, %s: i64) -> (i64, i64) {
    %g = idr.check.range %o, %n, %s, "a byte range outside the buffer"
    %h = idr.check.range %g, %n, %s, "a byte range outside the buffer"
    return %g, %h : i64, i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
