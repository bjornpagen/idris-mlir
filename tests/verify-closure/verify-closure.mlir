// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics

idr.program @closure root(@root) stage(higher) {
  idr.func @g(%a: i64, %b: f64) -> i64 {
    idr.crash "no body"
    ub.unreachable
  }
  idr.func @f(%d: f64) {
    // expected-error @+1 {{captures 'f64', which are not the leading parameters of @g}}
    %c = idr.closure @g(%d) : (f64) -> !idr.fn<(f64) -> (i64)>
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @closure root(@root) stage(higher) {
  idr.func @g(%a: i64, %b: f64) -> i64 {
    idr.crash "no body"
    ub.unreachable
  }
  idr.func @f(%x: i64) {
    // expected-error @+1 {{has type '!idr.fn<(f64) -> ()>', but a closure of @g with these captures is '!idr.fn<(f64) -> i64>'}}
    %c = idr.closure @g(%x) : (i64) -> !idr.fn<(f64) -> ()>
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @closure root(@root) stage(higher) {
  idr.func @f(%x: i64) {
    // expected-error @+1 {{refers to an unknown function @nowhere}}
    %c = idr.closure @nowhere(%x) : (i64) -> !idr.fn<() -> ()>
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// A closure never captures a world.
idr.program @closure root(@f) stage(higher) {
  idr.func @g(%w: !idr.world) -> !idr.world {
    idr.crash "no body"
    ub.unreachable
  }
  idr.func @f(%w: !idr.world) {
    // expected-error @+1 {{operand #0 must be}}
    %c = idr.closure @g(%w) : (!idr.world) -> !idr.fn<() -> (!idr.world)>
    return
  }
}

// -----

idr.program @closure root(@root) stage(higher) {
  idr.func @f(%c: !idr.fn<(i64) -> (i64)>, %x: i32) -> i64 {
    // expected-error @+1 {{failed to verify that callee input types match argument types}}
    %r = "idr.apply"(%c, %x) : (!idr.fn<(i64) -> (i64)>, i32) -> i64
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @closure root(@root) stage(higher) {
  idr.func @f(%c: !idr.fn<(i64) -> (i64)>, %x: i64) -> i32 {
    // expected-error @+1 {{failed to verify that callee result types match result types}}
    %r = "idr.apply"(%c, %x) : (!idr.fn<(i64) -> (i64)>, i64) -> i32
    return %r : i32
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// A closure may take a world as an argument: worlds pass as arguments and
// results, never as captures.
idr.program @closure root(@f) stage(higher) {
  idr.func @g(%w: !idr.world) -> !idr.world {
    return %w : !idr.world
  }
  idr.func @f(%w: !idr.world) -> !idr.world {
    %c = idr.closure @g() : () -> !idr.fn<(!idr.world) -> (!idr.world)>
    %r = idr.apply %c(%w) : !idr.fn<(!idr.world) -> (!idr.world)>
    return %r : !idr.world
  }
}

// -----

// The nearest each refusal above has that verifies: @g's leading
// parameter captured, both, and none, each at the type it leaves; a
// closure of a function the program has; and an apply whose argument and
// result are the closure's types.
idr.program @closure root(@root) stage(higher) {
  idr.func @g(%a: i64, %b: f64) -> i64 {
    idr.crash "no body"
    ub.unreachable
  }
  idr.func @f(%x: i64, %d: f64) {
    %c = idr.closure @g(%x) : (i64) -> !idr.fn<(f64) -> (i64)>
    %e = idr.closure @g(%x, %d) : (i64, f64) -> !idr.fn<() -> (i64)>
    %n = idr.closure @g() : () -> !idr.fn<(i64, f64) -> (i64)>
    return
  }
  idr.func @apply(%c: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = "idr.apply"(%c, %x) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
