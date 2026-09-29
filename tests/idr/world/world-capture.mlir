// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A closure never captures a world; worlds pass only as arguments and
// results. A closure may take a world as an argument.

func.func private @g(%w: !idr.world) -> !idr.world {
  return %w : !idr.world
}
func.func private @f(%w: !idr.world {idr.quantity = "1"}) {
  // expected-error @+1 {{captures a world; a world passes only as an argument or result}}
  %c = idr.closure @g(%w) : (!idr.world) -> !idr.fn<() -> (!idr.world)>
  return
}

// -----

func.func private @g(%w: !idr.world) -> !idr.world {
  return %w : !idr.world
}
func.func private @f(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
  %c = idr.closure @g() : () -> !idr.fn<(!idr.world) -> (!idr.world)>
  %r = idr.apply %c(%w) : !idr.fn<(!idr.world) -> (!idr.world)>
  return %r : !idr.world
}
