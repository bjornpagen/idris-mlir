// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics

idr.data @T {
  idr.ctor @A tag 0 ()
  // expected-error @+1 {{has tag 2; tags must be 0..n-1 in order}}
  idr.ctor @B tag 2 ()
}

// -----

// A field's quantity is its type: linear fields are !idr.lin.
idr.data @T {
  idr.ctor @A tag 0 (!idr.lin<i64>, !idr.erased, i64)
}

// -----

idr.data @T {
  // expected-error @+1 {{expects !idr.lin of a runtime type other than the world, got '!idr.erased'}}
  idr.ctor @A tag 0 (!idr.lin<!idr.erased>)
}

// -----

idr.data @T {
  // expected-error @+1 {{has a field of unsupported type 'f32'}}
  idr.ctor @A tag 0 (f32)
}

// -----

idr.data @T {
  // expected-error @+1 {{has a field of unsupported type 'i1'}}
  idr.ctor @A tag 0 (i1)
}

// -----

idr.data @T {
  // expected-error @+1 {{has a field of unsupported type 'index'}}
  idr.ctor @A tag 0 (index)
}

// -----

idr.data @T {
  // expected-note @+1 {{see existing symbol definition here}}
  idr.ctor @A tag 0 ()
  // expected-error @+1 {{redefinition of symbol named 'A'}}
  idr.ctor @A tag 1 ()
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
