// RUN: idris-mlir-opt %s --idr-expect=holds=contified -verify-diagnostics -o /dev/null
// A function called once, from a function it calls back, is a
// continuation of that function, still out of line (@step.case, the case
// block of @step's `if`); a recursion that is one function has none
// (@count).
idr.program @continuations root(@root) stage(first) {
  idr.func @step(%n: i64, %acc: i64) -> i64 {
    %c0 = arith.constant 0 : i64
    %done = arith.cmpi sle, %n, %c0 : i64
    // expected-error @below {{expected contified: }}
    %r = idr.call @step.case(%done, %n, %acc) : (i1, i64, i64) -> i64
    return %r : i64
  }
  idr.func @step.case(%done: i1, %n: i64, %acc: i64) -> i64 {
    %r = idr.match_lit %done : i1 -> (i64) {
    case 1 {
      idr.yield %acc : i64
    }
    default(%d: i1) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %s = idr.call @step(%m, %acc) : (i64, i64) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @count(%n: i64, %acc: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %s = idr.call @count(%m, %acc) : (i64, i64) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @root() -> i64 {
    %n = arith.constant 3 : i64
    %z = arith.constant 0 : i64
    %r = idr.call @step(%n, %z) : (i64, i64) -> i64
    %c = idr.call @count(%n, %z) : (i64, i64) -> i64
    %s = arith.addi %r, %c : i64
    return %s : i64
  }
}
