// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// A closure's captures become the fields of a constructor of its sum, so a
// capture is a value a field can hold: one that no field holds, an i1
// here, is refused where it is written, by the closure's capture
// constraint, and never reaches idr-defunctionalize, which would otherwise
// meet a sum it cannot define. @outer captures a closure of @inner, so
// @inner's sum is met inside @outer's. The second split is the same
// program capturing the word the i1 was made from, which a field holds:
// it verifies.
idr.program @"capture-field" root(@Main.main) stage(higher) {
  idr.func @run(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 attributes {total} {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %y : i64
  }
  idr.func @outer(%k: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 attributes {total} {
    %y = idr.apply %k(%x) : !idr.fn<(i64) -> (i64)>
    return %y : i64
  }
  idr.func @inner(%b: i1, %x: i64) -> i64 attributes {total} {
    %one = arith.constant 1 : i64
    %y = arith.select %b, %x, %one : i64
    return %y : i64
  }
  idr.func @Main.main() -> i64 {
    %n = arith.constant 3 : i64
    %z = arith.constant 0 : i64
    %b = arith.cmpi eq, %n, %z : i64
    // expected-error @+1 {{operand #0 must be}}
    %k = idr.closure @inner(%b) : (i1) -> !idr.fn<(i64) -> (i64)>
    %f = idr.closure @outer(%k) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)>
    %r = idr.call @run(%f, %n) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    return %r : i64
  }
}

// -----

idr.program @"capture-field" root(@Main.main) stage(higher) {
  idr.func @run(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 attributes {total} {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %y : i64
  }
  idr.func @outer(%k: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 attributes {total} {
    %y = idr.apply %k(%x) : !idr.fn<(i64) -> (i64)>
    return %y : i64
  }
  idr.func @inner(%n: i64, %x: i64) -> i64 attributes {total} {
    %z = arith.constant 0 : i64
    %b = arith.cmpi eq, %n, %z : i64
    %one = arith.constant 1 : i64
    %y = arith.select %b, %x, %one : i64
    return %y : i64
  }
  idr.func @Main.main() -> i64 {
    %n = arith.constant 3 : i64
    %k = idr.closure @inner(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %f = idr.closure @outer(%k) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)>
    %r = idr.call @run(%f, %n) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    return %r : i64
  }
}
