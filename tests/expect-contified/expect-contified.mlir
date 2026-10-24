// RUN: idris-mlir-opt %s -split-input-file --idr-expect=holds=contified -verify-diagnostics -o /dev/null
// A continuation is a function called once, from a function it calls
// back, as a case block of a recursion through an `if` is. In the first
// program @step is called by @loop alone and calls @loop back: a
// continuation still a function, reported where it stands. In the second
// @step is called by @loop alone and calls nothing back, so it is no
// continuation of @loop's and nothing is reported.
idr.program @still root(@main) stage(first) {
  idr.func @loop(%n: i64) -> i64 {
    %r = idr.call @step(%n) : (i64) -> i64
    %s = arith.addi %r, %n : i64
    return %s : i64
  }
  // expected-error @below {{expected contified: }}
  idr.func @step(%n: i64) -> i64 {
    %r = idr.call @loop(%n) : (i64) -> i64
    %s = arith.addi %r, %n : i64
    return %s : i64
  }
  idr.func @main() {
    %c = arith.constant 7 : i64
    %r = idr.call @loop(%c) : (i64) -> i64
    %text = idr.str.show_sint %r : (i64) -> !idr.str
    idr.io.put_str %text : (!idr.str) -> ()
    return
  }
}

// -----

idr.program @leaf root(@main) stage(first) {
  idr.func @loop(%n: i64) -> i64 {
    %r = idr.call @step(%n) : (i64) -> i64
    %s = arith.addi %r, %n : i64
    return %s : i64
  }
  idr.func @step(%n: i64) -> i64 {
    %s = arith.addi %n, %n : i64
    return %s : i64
  }
  idr.func @main() {
    %c = arith.constant 7 : i64
    %r = idr.call @loop(%c) : (i64) -> i64
    %text = idr.str.show_sint %r : (i64) -> !idr.str
    idr.io.put_str %text : (!idr.str) -> ()
    return
  }
}
