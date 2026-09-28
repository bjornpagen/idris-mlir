// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics

idr.data @T {
  idr.ctor @A tag 0 () {quantities = []}
  // expected-error @+1 {{has tag 2; tags must be 0..n-1 in order}}
  idr.ctor @B tag 2 () {quantities = []}
}

// -----

idr.data @T {
  // expected-error @+1 {{needs one quantity per field}}
  idr.ctor @A tag 0 (i64) {quantities = []}
}

// -----

idr.data @T {
  // expected-error @+1 {{must use quantity 0 exactly for !idr.erased fields}}
  idr.ctor @A tag 0 (!idr.erased) {quantities = ["w"]}
}

// -----

idr.data @T {
  // expected-error @+1 {{must use quantity 0 exactly for !idr.erased fields}}
  idr.ctor @A tag 0 (i64) {quantities = ["0"]}
}

// -----

idr.data @T {
  // expected-error @+1 {{has quantity 'x'}}
  idr.ctor @A tag 0 (i64) {quantities = ["x"]}
}

// -----

idr.data @T {
  // expected-error @+1 {{has a field of unsupported type 'f32'}}
  idr.ctor @A tag 0 (f32) {quantities = ["w"]}
}

// -----

idr.data @T {
  // expected-error @+1 {{has a field of unsupported type 'i1'}}
  idr.ctor @A tag 0 (i1) {quantities = ["w"]}
}

// -----

idr.data @T {
  // expected-error @+1 {{has a field of unsupported type 'index'}}
  idr.ctor @A tag 0 (index) {quantities = ["w"]}
}

// -----

idr.data @T {
  // expected-note @+1 {{see existing symbol definition here}}
  idr.ctor @A tag 0 () {quantities = []}
  // expected-error @+1 {{redefinition of symbol named 'A'}}
  idr.ctor @A tag 1 () {quantities = []}
}

// -----

idr.data @T {
  // expected-error @+1 {{is not allowed inside idr.data}}
  %c = arith.constant 0 : i64
}

// -----

func.func @f() {
  // expected-error @+1 {{expects parent op 'builtin.module'}}
  idr.data @T {
  }
  return
}
