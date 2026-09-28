// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics

func.func @f(%d: f64) {
  // expected-error @+1 {{shows a Double, which has no signedness}}
  %s = idr.str.show signed %d : f64
  return
}

// -----

func.func @f(%x: i1) {
  // expected-error @+1 {{operand #0 must be}}
  %s = idr.str.show %x : i1
  return
}

// -----

// idr.big.cmp has no `ne`, as Idris's Integer primitives have none.
func.func @f(%x: !idr.big) {
  // expected-error @+1 {{'predicate'}}
  %b = idr.big.cmp ne %x, %x
  return
}
