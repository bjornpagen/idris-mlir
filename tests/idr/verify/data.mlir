// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics

// A field's quantity is its type: linear fields are !idr.lin.
idr.data @T {
  idr.ctor @A (!idr.lin<i64>, !idr.erased, i64)
}

// -----

idr.data @T {
  // expected-error @+1 {{expects !idr.lin of a runtime type other than the world, got '!idr.erased'}}
  idr.ctor @A (!idr.lin<!idr.erased>)
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

func.func @f() {
  // expected-error @+1 {{expects parent op 'builtin.module'}}
  idr.data @T {
  }
  return
}
