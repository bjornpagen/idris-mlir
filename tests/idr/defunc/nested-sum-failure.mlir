// NEEDS-ACCEPTANCE: that idr-defunctionalize reports exactly this one internal error at an unknown location and stops cleanly, where the base handed a null data type to the outer sum's body and crashed.
// RUN: idris-mlir-opt %s --idr-defunctionalize -verify-diagnostics -o /dev/null
// A sum that fails to define, nested in another's: @outer captures a
// closure of @inner, and @inner captures an i1, which is no field type, so
// the body of @inner's sum is refused. The keys are met in program order,
// @run's parameter first, so @outer's sum is defined first and @inner's
// inside its body: the inner failure is returned to the outer body, which
// fails with it, and the decision stops at that one error, with no type
// made of a sum that has none.
// expected-error-re@unknown {{internal error: the constructor @inner of "{{.*}}" has a field of unsupported type i1}}
idr.program @"nested-sum-failure" root(@Main.main) stage(higher) {
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
    %k = idr.closure @inner(%b) : (i1) -> !idr.fn<(i64) -> (i64)>
    %f = idr.closure @outer(%k) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)>
    %r = idr.call @run(%f, %n) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    return %r : i64
  }
}
