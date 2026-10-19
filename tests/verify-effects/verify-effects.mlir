// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// A function's declared effects cover what its body may do: what the body
// does itself (IO where a parameter may hold a world, a crash where an op
// may crash, not returning unless Idris proved it total) and what each call
// it makes declares, which holds its callee's. A solve says too much, never
// too little, so a set that misses a bit is the compiler's error, reported
// with the bits it misses. A function or a call without `effects` declares
// everything.

idr.program @effects root(@root) stage(first) {
  // expected-error @+1 {{declares the effects none, which do not cover what its body may do: io}}
  idr.func effects<none> @writes(%s: !idr.str, %w: !idr.world) -> !idr.world attributes {total} {
    %w1 = idr.io.put_str %s, %w
    return %w1 : !idr.world
  }
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @effects root(@root) stage(first) {
  idr.func effects<crash> @checks(%x: i64) -> i64 attributes {total} {
    %y = idr.check.nonzero %x, "division by zero" : i64
    return %y : i64
  }
  // expected-error @+1 {{declares the effects none, which do not cover what its body may do: crash}}
  idr.func effects<none> @calls(%x: i64) -> i64 attributes {total} {
    %r = idr.call @checks(%x) effects<crash> : (i64) -> i64
    return %r : i64
  }
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @effects root(@root) stage(first) {
  // expected-error @+1 {{declares the effects none, which do not cover what its body may do: diverge}}
  idr.func effects<none> @partial(%x: i64) -> i64 {
    return %x : i64
  }
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// Covered: a function that is not total says it may not return, its call
// and its caller say what it may do, and a function without `effects` calls
// anything.
idr.program @effects root(@root) stage(first) {
  idr.func effects<crash, diverge> @checks(%x: i64) -> i64 {
    %y = idr.check.nonzero %x, "division by zero" : i64
    return %y : i64
  }
  idr.func effects<crash, diverge> @calls(%x: i64) -> i64 attributes {total} {
    %r = idr.call @checks(%x) effects<crash, diverge> : (i64) -> i64
    return %r : i64
  }
  idr.func @root() -> i64 {
    %c = arith.constant 3 : i64
    %r = idr.call @calls(%c) : (i64) -> i64
    return %r : i64
  }
}
