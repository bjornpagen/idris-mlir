// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns=@proving:-2,no-guards=@proving,crash-sites=@failing:2,crash-sites=@again:1 -o /dev/null
// The guard of a Double cast to an integer folds to the Double where it is
// a finite constant; then the cast folds too. On NaN or an infinity the
// guard stays, to crash where it runs. A guard of what an identical guard
// already checked folds too.
idr.program @"fold-finite" root(@proving) stage(first) {
  idr.func @proving() -> i64 {
    %d = arith.constant -2.75 : f64
    %g = idr.check.finite %d, "cast of a non-finite Double"
    %i = idr.to_int %g : i64
    return %i : i64
  }

  idr.func @failing(%b: !idr.big) -> (i64, !idr.big) {
    %nan = arith.constant 0x7FF8000000000000 : f64
    %g = idr.check.finite %nan, "cast of a non-finite Double"
    %i = idr.to_int %g : i64
    %inf = arith.constant 0xFFF0000000000000 : f64
    %h = idr.check.finite %inf, "cast of a non-finite Double"
    %j = idr.big.from_double %h
    return %i, %j : i64, !idr.big
  }

  idr.func @again(%d: f64) -> (i64, !idr.big) {
    %g = idr.check.finite %d, "cast of a non-finite Double"
    %i = idr.to_int %g : i64
    %h = idr.check.finite %g, "cast of a non-finite Double"
    %j = idr.big.from_double %h
    return %i, %j : i64, !idr.big
  }
}
