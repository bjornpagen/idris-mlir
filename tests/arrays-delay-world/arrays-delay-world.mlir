// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// An evaluated suspension holds its value, and a world is never held: it
// passes only as an argument or a result. A value other than the world,
// here a word, is held as it is (the second split).

idr.program @"delay-world" root(@f) stage(higher) types #idr.types<> {
  idr.func @f(%w: !idr.world) {
    // expected-error @+1 {{operand #0 must be a value a field holds, other than the world, but got '!idr.world'}}
    %t = idr.delay %w : !idr.world -> !idr.lazy<!idr.world>
    return
  }
}

// -----

idr.program @"delay-world" root(@f) stage(higher) types #idr.types<> {
  idr.func @f(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %t = idr.delay %x : i64 -> !idr.lazy<i64>
    %v = idr.force %t : !idr.lazy<i64> -> i64
    %w2 = idr.io.put_sint %v, %w1 : i64
    return %w2 : !idr.world
  }
}
