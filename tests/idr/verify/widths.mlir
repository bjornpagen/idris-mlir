// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// The integers of Idris are 8, 16, 32 and 64 bits wide, and so is every
// integer an idr op computes on (idr.match_lit also branches on a
// condition); only what counts references is counted.

func.func private @f(%a: i7, %b: i7) -> i7 {
  // expected-error @+1 {{but got 'i7'}}
  %q = idr.div signed %a, %b : i7
  return %q : i7
}

// -----

func.func private @f(%a: i1) -> i32 {
  // expected-error @+1 {{but got 'i1'}}
  %c = idr.to_char unsigned %a : i1
  return %c : i32
}

// -----

func.func private @f(%d: f64) -> i128 {
  // expected-error @+1 {{but got 'i128'}}
  %i = idr.to_int %d : i128
  return %i : i128
}

// -----

func.func private @f(%a: i1, %w: !idr.world) -> !idr.world {
  // expected-error @+1 {{but got 'i1'}}
  %w1 = idr.io.put_int unsigned %a, %w : i1
  return %w1 : !idr.world
}

// -----

// A linear integer holds no reference, so nothing counts it.
func.func private @f(%x: !idr.lin<i64>) {
  // expected-error @+1 {{but got '!idr.lin<i64>'}}
  %o = idr.dup %x : !idr.lin<i64>
  return
}
