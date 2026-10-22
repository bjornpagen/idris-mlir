// RUN: idris-mlir-opt %s -split-input-file --idr-expect=holds=reached -verify-diagnostics -o /dev/null
// Every function of the program is reached from its root by the symbols
// the bodies reached before it name. In the first program @main calls
// @twice, which calls @inc, so all three are reached and nothing is
// reported. In the second @orphan calls @inc, but no body reached names
// @orphan, so it alone is reported: @inc, which @main calls too, is
// reached, and what an unreached function names reaches nothing.
idr.program @reached root(@main) stage(first) {
  idr.func @inc(%x: i64) -> i64 {
    %one = arith.constant 1 : i64
    %y = arith.addi %x, %one : i64
    return %y : i64
  }
  idr.func @twice(%x: i64) -> i64 {
    %y = idr.call @inc(%x) <{tail_kind = nontail}> : (i64) -> i64
    %z = arith.addi %y, %y : i64
    return %z : i64
  }
  idr.func @main() -> i64 {
    %c = arith.constant 20 : i64
    %y = idr.call @twice(%c) <{tail_kind = nontail}> : (i64) -> i64
    %z = arith.addi %y, %c : i64
    return %z : i64
  }
}

// -----

idr.program @unreached root(@main) stage(first) {
  idr.func @inc(%x: i64) -> i64 {
    %one = arith.constant 1 : i64
    %y = arith.addi %x, %one : i64
    return %y : i64
  }
  // expected-error @below {{expected reached: }}
  idr.func @orphan(%x: i64) -> i64 {
    %y = idr.call @inc(%x) <{tail_kind = nontail}> : (i64) -> i64
    %z = arith.addi %y, %y : i64
    return %z : i64
  }
  idr.func @main() -> i64 {
    %c = arith.constant 20 : i64
    %y = idr.call @inc(%c) <{tail_kind = nontail}> : (i64) -> i64
    %z = arith.addi %y, %c : i64
    return %z : i64
  }
}
