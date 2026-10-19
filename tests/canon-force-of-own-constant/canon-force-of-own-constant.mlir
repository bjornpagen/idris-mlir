// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=forces=@knot,never-calls=@knot:@knot,\
// RUN: forces=@mid,never-calls=@mid:@label,forces=@other,never-calls=@other:@leaf -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// A constant suspension is one cell in static data, whose force runs its
// label once. Every force of it stays a force: a call of the label in its
// place would run the label again at each force, and in a knot (the
// label's own constant, or one a function it calls holds) would recurse
// where the cell's running state ends the program. So canonicalize leaves
// every force of a constant, whatever the label reaches.

// The label forces its own constant.
idr.program @"force-of-own-constant" root(@other) stage(higher) {
  idr.func @knot() -> i64 {
    %c = idr.constant !idr.lazy<i64> #idr.closure<@knot, []>
    %v = idr.force %c : !idr.lazy<i64> -> i64
    %one = arith.constant 1 : i64
    %r = arith.addi %v, %one : i64
    return %r : i64
  }

  // The label calls the function that forces its constant.
  idr.func @label() -> i64 {
    %r = idr.call @mid() : () -> i64
    return %r : i64
  }
  idr.func @mid() -> i64 {
    %c = idr.constant !idr.lazy<i64> #idr.closure<@label, []>
    %v = idr.force %c : !idr.lazy<i64> -> i64
    return %v : i64
  }

  // The label reaches nothing that holds its constant.
  idr.func @leaf() -> i64 attributes {total} {
    %c = arith.constant 7 : i64
    return %c : i64
  }
  idr.func @other() -> i64 {
    %c = idr.constant !idr.lazy<i64> #idr.closure<@leaf, []>
    %v = idr.force %c : !idr.lazy<i64> -> i64
    return %v : i64
  }
}
