// NEEDS-ACCEPTANCE: a world captured is refused by the capture's operand constraint (Idr_Capture, S17), with the message ODS writes for it.
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
    // expected-error @+1 {{operand #0 must be variadic of a value other than the world, but got '!idr.world'}}
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
