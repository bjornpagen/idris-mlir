// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// Every op that holds, takes or gives a closure or a suspension declares
// how it moves, through the flow interface or through upstream's branch,
// region-branch and select-like interfaces, and the verifier refuses one
// that does not, where it is written: no pass meets a closure whose labels
// it cannot follow. builtin.unrealized_conversion_cast declares nothing.
idr.program @flow root(@Main.main) stage(higher) {
  idr.func @one() -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    return %c : i64
  }
  idr.func @two() -> i64 attributes {total} {
    %c = arith.constant 2 : i64
    return %c : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %z = arith.constant 65 : i32
    %b = arith.cmpi eq, %c, %z : i32
    %x = idr.suspend @one() : () -> !idr.lazy<i64>
    %y = idr.suspend @two() : () -> !idr.lazy<i64>
    // expected-error @+1 {{takes a closure or a suspension as operand #0, and declares no edge}}
    %t = builtin.unrealized_conversion_cast %x : !idr.lazy<i64> to !idr.lazy<i64>
    %v = idr.force %t : !idr.lazy<i64> -> i64
    %w2 = idr.io.put_sint %v, %w1 : i64
    return %w2 : !idr.world
  }
}

// -----

// The same for a closure.
idr.program @flow root(@root) stage(higher) {
  idr.func @inc(%x: i64) -> i64 attributes {total} {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    return %y : i64
  }
  idr.func @pick(%b: i1) -> !idr.fn<(i64) -> (i64)> {
    %f = idr.closure @inc() : () -> !idr.fn<(i64) -> (i64)>
    %g = idr.closure @inc() : () -> !idr.fn<(i64) -> (i64)>
    // expected-error @+1 {{takes a closure or a suspension as operand #0, and declares no edge}}
    %h = builtin.unrealized_conversion_cast %f : !idr.fn<(i64) -> (i64)> to !idr.fn<(i64) -> (i64)>
    return %h : !idr.fn<(i64) -> (i64)>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// Every edge an op declares joins two values of one carrier, the type
// without its outermost grade: a label that enters a key always fits it.
// An evaluated suspension's value flows into the forced state of its lazy
// type, so the two must be one carrier.
idr.program @flow root(@root) stage(higher) {
  idr.func @inc(%x: i64) -> i64 attributes {total} {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    return %y : i64
  }
  idr.func @held() -> !idr.lazy<!idr.fn<(i32) -> (i32)>> {
    %f = idr.closure @inc() : () -> !idr.fn<(i64) -> (i64)>
    // expected-error @+1 {{carrier}}
    %t = idr.delay %f : !idr.fn<(i64) -> (i64)> -> !idr.lazy<!idr.fn<(i32) -> (i32)>>
    return %t : !idr.lazy<!idr.fn<(i32) -> (i32)>>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// The nearest each refusal above has that verifies: the choice of two
// suspensions, and of two closures, written as a select, which declares
// that its result is either operand, and as a match, whose regions declare
// their flow; and a delay into the lazy type of the closure's own carrier.
idr.program @flow root(@root) stage(higher) {
  idr.func @one() -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    return %c : i64
  }
  idr.func @inc(%x: i64) -> i64 attributes {total} {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    return %y : i64
  }
  idr.func @lazy(%b: i1) -> i64 {
    %x = idr.suspend @one() : () -> !idr.lazy<i64>
    %y = idr.suspend @one() : () -> !idr.lazy<i64>
    %t = idr.match_lit %b : i1 -> (!idr.lazy<i64>) {
    case true {
      idr.yield %x : !idr.lazy<i64>
    }
    default(%d: i1) {
      idr.yield %y : !idr.lazy<i64>
    }
    }
    %v = idr.force %t : !idr.lazy<i64> -> i64
    return %v : i64
  }
  idr.func @pick(%b: i1) -> !idr.fn<(i64) -> (i64)> {
    %f = idr.closure @inc() : () -> !idr.fn<(i64) -> (i64)>
    %g = idr.closure @inc() : () -> !idr.fn<(i64) -> (i64)>
    %h = idr.match_lit %b : i1 -> (!idr.fn<(i64) -> (i64)>) {
    case true {
      idr.yield %f : !idr.fn<(i64) -> (i64)>
    }
    default(%d: i1) {
      idr.yield %g : !idr.fn<(i64) -> (i64)>
    }
    }
    return %h : !idr.fn<(i64) -> (i64)>
  }
  idr.func @selected(%b: i1) -> i64 {
    %x = idr.suspend @one() : () -> !idr.lazy<i64>
    %y = idr.suspend @one() : () -> !idr.lazy<i64>
    %t = arith.select %b, %x, %y : !idr.lazy<i64>
    %v = idr.force %t : !idr.lazy<i64> -> i64
    return %v : i64
  }
  idr.func @selectedFn(%b: i1) -> !idr.fn<(i64) -> (i64)> {
    %f = idr.closure @inc() : () -> !idr.fn<(i64) -> (i64)>
    %g = idr.closure @inc() : () -> !idr.fn<(i64) -> (i64)>
    %h = arith.select %b, %f, %g : !idr.fn<(i64) -> (i64)>
    return %h : !idr.fn<(i64) -> (i64)>
  }
  idr.func @held() -> !idr.lazy<!idr.fn<(i64) -> (i64)>> {
    %f = idr.closure @inc() : () -> !idr.fn<(i64) -> (i64)>
    %t = idr.delay %f : !idr.fn<(i64) -> (i64)> -> !idr.lazy<!idr.fn<(i64) -> (i64)>>
    return %t : !idr.lazy<!idr.fn<(i64) -> (i64)>>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
