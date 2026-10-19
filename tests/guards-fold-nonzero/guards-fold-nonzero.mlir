// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=no-guards=@proving,crash-sites=@failing:2,crash-sites=@again:1 -o /dev/null
// The guard of a divisor folds to the divisor where the divisor shows it is
// not zero: a constant integer, or a constant big, other than zero. On zero
// it stays, to crash where it runs. A guard of what an identical guard
// already checked folds too: its operand is that guard's result.
idr.program @"fold-nonzero" root(@root) stage(first) {
  idr.func @proving(%x: i64, %b: !idr.big) -> (i64, !idr.big) {
    %seven = arith.constant 7 : i64
    %g = idr.check.nonzero %seven, "division by zero" : i64
    %q = idr.divs %x, %g : i64
    %three = idr.constant !idr.big #idr.big<-3>
    %h = idr.check.nonzero %three, "division by zero" : !idr.big
    %r = idr.big.div %b, %h
    return %q, %r : i64, !idr.big
  }

  idr.func @failing(%x: i64, %b: !idr.big) -> (i64, !idr.big) {
    %zero = arith.constant 0 : i64
    %g = idr.check.nonzero %zero, "division by zero" : i64
    %q = idr.divs %x, %g : i64
    %none = idr.constant !idr.big #idr.big<0>
    %h = idr.check.nonzero %none, "division by zero" : !idr.big
    %r = idr.big.div %b, %h
    return %q, %r : i64, !idr.big
  }

  idr.func @again(%x: i64, %y: i64) -> (i64, i64) {
    %g = idr.check.nonzero %y, "division by zero" : i64
    %q = idr.divs %x, %g : i64
    %h = idr.check.nonzero %g, "division by zero" : i64
    %m = idr.mods %x, %h : i64
    return %q, %m : i64, i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
