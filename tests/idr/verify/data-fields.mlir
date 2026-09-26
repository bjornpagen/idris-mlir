// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// rule: IDR-DATA-3, IDR-TY-3

idr.data @T {
  // expected-error @+1 {{has a field of unsupported type 'f64'}}
  idr.ctor @A tag 0 fields [f64] quantities ["w"]
}

// -----

idr.data @T {
  // expected-error @+1 {{has a field of unsupported type 'index'}}
  idr.ctor @A tag 0 fields [index] quantities ["w"]
}

// -----

// Integer widths, other data, erased, strings and characters are fields.
idr.data @U {
  idr.ctor @MkU tag 0 fields [i8, i16, i32, i64] quantities ["w", "w", "1", "w"]
}
idr.data @T {
  idr.ctor @A tag 0 fields [!idr.data<@U>, !idr.erased, !idr.str] quantities ["w", "0", "w"]
}
