// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// The integers of Idris are 8, 16, 32 and 64 bits wide, and so is every
// integer an idr op computes on; only what counts references is counted.

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

func.func private @f(%b: i1) -> i64 {
  // expected-error @+1 {{but got 'i1'}}
  %r = idr.match_lit %b : i1 -> (i64) {
  case 0 {
    %z = arith.constant 0 : i64
    idr.yield %z : i64
  }
  default {
    %o = arith.constant 1 : i64
    idr.yield %o : i64
  }
  }
  return %r : i64
}

// -----

// A linear integer holds no reference, so nothing counts it.
func.func private @f(%x: !idr.lin<i64>) {
  // expected-error @+1 {{but got '!idr.lin<i64>'}}
  idr.inc %x : !idr.lin<i64>
  return
}
