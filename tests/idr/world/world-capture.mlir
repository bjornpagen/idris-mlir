// NEEDS-ACCEPTANCE: that a closure capturing a world is refused by its captures' operand constraint (Idr_Capture), whose message names the world's type.
// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A closure never captures a world; worlds pass only as arguments and
// results. A closure may take a world as an argument.

idr.program @"world-capture" root(@f) stage(higher) {
  idr.func @g(%w: !idr.world) -> !idr.world {
    return %w : !idr.world
  }
  idr.func @f(%w: !idr.world) {
    // expected-error @+1 {{but got '!idr.world'}}
    %c = idr.closure @g(%w) : (!idr.world) -> !idr.fn<() -> (!idr.world)>
    return
  }
}

// -----

idr.program @"world-capture" root(@f) stage(higher) {
  idr.func @g(%w: !idr.world) -> !idr.world {
    return %w : !idr.world
  }
  idr.func @f(%w: !idr.world) -> !idr.world {
    %c = idr.closure @g() : () -> !idr.fn<(!idr.world) -> (!idr.world)>
    %r = idr.apply %c(%w) : !idr.fn<(!idr.world) -> (!idr.world)>
    return %r : !idr.world
  }
}
