// RUN: idris-mlir-opt %s --idr-expect=holds=no-guards=@proven -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=no-guards=@guarded -verify-diagnostics -o /dev/null
// A proof is a guard's absence. @proven divides by a constant that is not
// zero, with no guard; @guarded divides by its argument, whose guard is
// left: a guard is any op of the guard interface, whichever condition it
// checks.
module {
  func.func @proven(%x: i64) -> i64 {
    %two = arith.constant 2 : i64
    %y = arith.divsi %x, %two : i64
    return %y : i64
  }
  func.func @guarded(%x: i64, %d: i64) -> i64 {
    // expected-error @below {{expected no-guards: }}
    %checked = idr.check.nonzero %d, division_by_zero at #idr.site<"Main.idr", 3, 5, "Main.guarded"> : (i64) -> i64
    %y = arith.divsi %x, %checked : i64
    return %y : i64
  }
}
