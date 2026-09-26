// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// rule: IDR-DATA-1, IDR-DATA-2

idr.data @T {
  idr.ctor @A tag 0 fields [] quantities []
  // expected-error @+1 {{has tag 2; tags must be 0..n-1 in order}}
  idr.ctor @B tag 2 fields [] quantities []
}

// -----

idr.data @T {
  // expected-error @+1 {{needs one quantity per field}}
  idr.ctor @A tag 0 fields [i64] quantities []
}

// -----

idr.data @T {
  // expected-error @+1 {{must use quantity 0 exactly for !idr.erased fields}}
  idr.ctor @A tag 0 fields [!idr.erased] quantities ["w"]
}

// -----

idr.data @T {
  // expected-error @+1 {{has quantity 'x'}}
  idr.ctor @A tag 0 fields [i64] quantities ["x"]
}

// -----

func.func @f() {
  // expected-error @+1 {{expects parent op 'builtin.module'}}
  idr.data @T {
  }
  return
}
