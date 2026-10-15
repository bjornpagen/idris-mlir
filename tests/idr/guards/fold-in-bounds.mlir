// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns=@proving:99,no-guards=@proving,crash-sites=@failing:2,crash-sites=@again:1 -o /dev/null
// The guard of an index folds to the index where both it and the length
// are constants and the index is at least 0 and below the length; then the
// character at it folds too. An index at the length, or below 0, keeps its
// guard, to crash where it runs. A guard of what an identical guard, of the
// same length, already checked folds too.
idr.program @"fold-in-bounds" root(@root) stage(first) {
  idr.func @proving() -> i32 {
    %abc = idr.constant "abc" : !idr.str
    %two = arith.constant 2 : i64
    %n = idr.str.length %abc
    %g = idr.check.in_bounds %two, %abc, "string index out of range" : !idr.str
    %c = idr.str.index %abc, %g
    return %c : i32
  }

  idr.func @failing() -> (i32, i32) {
    %abc = idr.constant "abc" : !idr.str
    %three = arith.constant 3 : i64
    %below = arith.constant -1 : i64
    %n = idr.str.length %abc
    %g = idr.check.in_bounds %three, %abc, "string index out of range" : !idr.str
    %c = idr.str.index %abc, %g
    %h = idr.check.in_bounds %below, %abc, "string index out of range" : !idr.str
    %d = idr.str.index %abc, %h
    return %c, %d : i32, i32
  }

  idr.func @again(%s: !idr.str, %i: i64) -> (i32, i32) {
    %n = idr.str.length %s
    %g = idr.check.in_bounds %i, %s, "string index out of range" : !idr.str
    %c = idr.str.index %s, %g
    %h = idr.check.in_bounds %g, %s, "string index out of range" : !idr.str
    %d = idr.str.index %s, %h
    return %c, %d : i32, i32
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
