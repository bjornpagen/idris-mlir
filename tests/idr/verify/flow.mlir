// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// NEEDS-ACCEPTANCE: the texts of the flow rule's errors, as C05's verifyFlow and verifyFlowEdges write them.
// Every op that holds, takes or gives a closure or a suspension declares
// how it moves, through the flow interface or through upstream's branch
// and region-branch interfaces, and the verifier refuses one that does
// not, where it is written: no pass meets a closure whose labels it cannot
// follow. arith.select declares nothing, so a choice of two suspensions is
// written as a match (defunc/lazy-choice.mlir), never as a select.
module {
  idr.func private @one() -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    return %c : i64
  }
  idr.func private @two() -> i64 attributes {total} {
    %c = arith.constant 2 : i64
    return %c : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %z = arith.constant 65 : i32
    %b = arith.cmpi eq, %c, %z : i32
    %x = idr.suspend @one() : () -> !idr.lazy<i64>
    %y = idr.suspend @two() : () -> !idr.lazy<i64>
    // expected-error @+1 {{closure or suspension}}
    %t = arith.select %b, %x, %y : !idr.lazy<i64>
    %v = idr.force %t : !idr.lazy<i64> -> i64
    %w2 = idr.io.put_int signed %v, %w1 : i64
    return %w2 : !idr.world
  }
}

// -----

// The same for a closure.
idr.func private @inc(%x: i64) -> i64 attributes {total} {
  %c1 = arith.constant 1 : i64
  %y = arith.addi %x, %c1 : i64
  return %y : i64
}
idr.func private @pick(%b: i1) -> !idr.fn<(i64) -> (i64)> {
  %f = idr.closure @inc() : () -> !idr.fn<(i64) -> (i64)>
  %g = idr.closure @inc() : () -> !idr.fn<(i64) -> (i64)>
  // expected-error @+1 {{closure or suspension}}
  %h = arith.select %b, %f, %g : !idr.fn<(i64) -> (i64)>
  return %h : !idr.fn<(i64) -> (i64)>
}

// -----

// Every edge an op declares joins two values of one carrier, the type
// without its outermost grade: a label that enters a key always fits it.
// An evaluated suspension's value flows into the forced state of its lazy
// type, so the two must be one carrier.
idr.func private @inc(%x: i64) -> i64 attributes {total} {
  %c1 = arith.constant 1 : i64
  %y = arith.addi %x, %c1 : i64
  return %y : i64
}
idr.func private @held() -> !idr.lazy<!idr.fn<(i32) -> (i32)>> {
  %f = idr.closure @inc() : () -> !idr.fn<(i64) -> (i64)>
  // expected-error @+1 {{carrier}}
  %t = idr.delay %f : !idr.fn<(i64) -> (i64)> -> !idr.lazy<!idr.fn<(i32) -> (i32)>>
  return %t : !idr.lazy<!idr.fn<(i32) -> (i32)>>
}
