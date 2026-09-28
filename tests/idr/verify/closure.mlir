// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// rule: IDR-CLOS-1, IDR-WORLD-1

func.func private @g(%a: i64, %b: f64) -> i64
func.func @f(%d: f64) {
  // expected-error @+1 {{captures 'f64', which are not the leading parameters of @g}}
  %c = idr.closure @g(%d) : (f64) -> !idr.fn<(f64) -> (i64)>
  return
}

// -----

func.func private @g(%a: i64, %b: f64) -> i64
func.func @f(%x: i64) {
  // expected-error @+1 {{has type '!idr.fn<(f64) -> ()>', but a closure of @g with these captures is '!idr.fn<(f64) -> (i64)>'}}
  %c = idr.closure @g(%x) : (i64) -> !idr.fn<(f64) -> ()>
  return
}

// -----

func.func @f(%x: i64) {
  // expected-error @+1 {{refers to an unknown function @nowhere}}
  %c = idr.closure @nowhere(%x) : (i64) -> !idr.fn<() -> ()>
  return
}

// -----

// IDR-WORLD-1: a closure never captures a world.
func.func private @g(%w: !idr.world) -> !idr.world
func.func @f(%w: !idr.world) {
  // expected-error @+1 {{captures a world; a world passes only as an argument or result (IDR-WORLD-1)}}
  %c = idr.closure @g(%w) : (!idr.world) -> !idr.fn<() -> (!idr.world)>
  return
}

// -----

func.func @f(%c: !idr.fn<(i64) -> (i64)>, %x: i32) -> i64 {
  // expected-error @+1 {{failed to verify that callee input types match argument types}}
  %r = "idr.apply"(%c, %x) : (!idr.fn<(i64) -> (i64)>, i32) -> i64
  return %r : i64
}

// -----

func.func @f(%c: !idr.fn<(i64) -> (i64)>, %x: i64) -> i32 {
  // expected-error @+1 {{failed to verify that callee result types match result types}}
  %r = "idr.apply"(%c, %x) : (!idr.fn<(i64) -> (i64)>, i64) -> i32
  return %r : i32
}
