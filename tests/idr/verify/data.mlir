// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics

// A field's quantity is its type: linear fields are !idr.lin.
idr.data @T {
  idr.ctor @A (!idr.lin<i64>, i64)
}

// -----

idr.data @T {
  // expected-error @+1 {{expects a grade of a plain type, got one of '!idr.lin<i64>'}}
  idr.ctor @A (!idr.lin<!idr.lin<i64>>)
}

// -----

idr.data @T {
  // expected-error @+1 {{has a field of unsupported type 'f32'}}
  idr.ctor @A (f32)
}

// -----

idr.data @T {
  // expected-error @+1 {{has a field of unsupported type 'i1'}}
  idr.ctor @A (i1)
}

// -----

idr.data @T {
  // expected-error @+1 {{has a field of unsupported type 'index'}}
  idr.ctor @A (index)
}

// -----

idr.data @T {
  // expected-note @+1 {{see existing symbol definition here}}
  idr.ctor @A ()
  // expected-error @+1 {{redefinition of symbol named 'A'}}
  idr.ctor @A ()
}

// -----

idr.data @T {
  // expected-error @+1 {{is not allowed inside idr.data}}
  %c = arith.constant 0 : i64
}

// -----

idr.func @f() {
  // expected-error @+1 {{expects parent op 'builtin.module'}}
  idr.data @T {
  }
  return
}

// -----

// A memo sum's checks read its constructors, so they wait until each is
// verified: this one lacks its field types, and is rejected for that before
// the memo sum reads them.
idr.data @M box memo {
  // expected-error @+1 {{requires attribute 'field_types'}}
  "idr.ctor"() <{sym_name = "running"}> : () -> ()
}
