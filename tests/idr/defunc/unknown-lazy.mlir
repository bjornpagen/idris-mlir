// RUN: idris-mlir-opt %s --idr-defunctionalize -verify-diagnostics -o /dev/null
// A suspension the analysis of labels cannot follow would be a value
// nothing lowers, so the program is rejected where the analysis loses it:
// here a choice made by arith.select, an op the analysis does not see
// through, between two suspensions.
module attributes {idr.program} {
  func.func private @one() -> i64 attributes {idr.total} {
    %c = arith.constant 1 : i64
    return %c : i64
  }
  func.func private @two() -> i64 attributes {idr.total} {
    %c = arith.constant 2 : i64
    return %c : i64
  }
  func.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %z = arith.constant 65 : i32
    %b = arith.cmpi eq, %c, %z : i32
    %x = idr.suspend @one() : () -> !idr.lazy<i64>
    %y = idr.suspend @two() : () -> !idr.lazy<i64>
    // expected-error @+1 {{unsupported (laziness)}}
    %t = arith.select %b, %x, %y : !idr.lazy<i64>
    %v = idr.force %t : !idr.lazy<i64> -> i64
    %w2 = idr.io.put_int signed %v, %w1 : i64
    return %w2 : !idr.world
  }
}
