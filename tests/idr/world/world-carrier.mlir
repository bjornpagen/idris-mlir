// NEEDS-ACCEPTANCE: that the world's old carrier spelling no longer parses, so no world can be written at quantity many; at the base this module verifies, a world used twice.
// RUN: idris-mlir-opt %s -verify-diagnostics
// The world is one type, used exactly once by its type: there is no
// carrier of it beneath a grade, which a stripped grade would leave used
// any number of times.

idr.program @"world-carrier" root(@root) stage(first) {
// expected-error @+1 {{unknown type}}
idr.func @f(%w: !idr.world_carrier) -> (!idr.world_carrier, !idr.world_carrier) {
  return %w, %w : !idr.world_carrier, !idr.world_carrier
}
idr.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}
