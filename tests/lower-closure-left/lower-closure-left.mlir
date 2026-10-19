// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// RUN: awk '/^\/\/ -----/ { n++; next } n == 0' %s | sed 's/stage(first)/stage(higher)/' | idris-mlir-opt --idr-expect=holds=stage=higher -o /dev/null
// RUN: awk '/^\/\/ -----/ { n++; next } n == 1' %s | sed 's/stage(owned)/stage(higher)/' | idris-mlir-opt --idr-expect=holds=stage=higher -o /dev/null
// idr-defunctionalize makes every closure of the program a sum, and every
// suspension a cell of a memo sum whose force is a call, and says so by
// the stage it gives the program, `first`. So a closure, an application,
// a suspension or a force in a program past `higher` is no program the
// lowering meets: the program's own verifier refuses it, at any stage
// after `higher`, and idr-lower has no case for one. So is a value of a
// closure's or a suspension's type, a function's parameter among them,
// even one no op makes. And each is refused for its stage alone: the
// first two programs, the stage they say made `higher` (the second and
// third RUN lines), verify.
idr.program @"closure-left" root(@Main.main) stage(first) {
  idr.func @add(%a: i64, %b: i64) -> i64 {
    %r = arith.addi %a, %b : i64
    return %r : i64
  }
  idr.func @Main.main() -> i64 {
    %k = arith.constant 1 : i64
    // expected-error @+1 {{higher}}
    %c = idr.closure @add(%k) : (i64) -> !idr.fn<(i64) -> (i64)>
    %x = arith.constant 2 : i64
    %r = idr.apply %c(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
}

// -----

idr.program @"closure-left" root(@Main.main) stage(owned) {
  idr.func @two() -> i64 {
    %r = arith.constant 2 : i64
    return %r : i64
  }
  idr.func @Main.main() -> i64 {
    // expected-error @+1 {{higher}}
    %t = idr.suspend @two() : () -> !idr.lazy<i64>
    %r = idr.force %t : !idr.lazy<i64> -> i64
    return %r : i64
  }
}

// -----

idr.program @"closure-left" root(@Main.main) stage(first) {
  // expected-error @+1 {{higher}}
  idr.func @run(%f: !idr.fn<(i64) -> (i64)>) -> i64 {
    %x = arith.constant 2 : i64
    %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  idr.func @Main.main() -> i64 {
    %x = arith.constant 2 : i64
    return %x : i64
  }
}

// -----

idr.program @"closure-left" root(@Main.main) stage(owned) {
  // expected-error @+1 {{higher}}
  idr.func @get(%t: !idr.lazy<i64>) -> i64 {
    %r = idr.force %t : !idr.lazy<i64> -> i64
    return %r : i64
  }
  idr.func @Main.main() -> i64 {
    %x = arith.constant 2 : i64
    return %x : i64
  }
}
