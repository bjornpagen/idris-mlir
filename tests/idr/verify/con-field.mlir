// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// rule: IDR-CON-1, IDR-FIELD-1, IDR-TAG-1

idr.data @T {
  idr.ctor @A tag 0 fields [i64] quantities ["w"]
}
func.func @f(%x: i32) -> !idr.data<@T> {
  // expected-error @+1 {{field has type 'i32', expected i64}}
  %v = idr.con @T::@A(%x) : (i32) -> !idr.data<@T>
  return %v : !idr.data<@T>
}

// -----

idr.data @T {
  idr.ctor @A tag 0 fields [i64] quantities ["w"]
}
func.func @f(%x: i64) -> !idr.data<@T> {
  // expected-error @+1 {{refers to an unknown constructor @T::@B}}
  %v = idr.con @T::@B(%x) : (i64) -> !idr.data<@T>
  return %v : !idr.data<@T>
}

// -----

idr.data @T {
  idr.ctor @A tag 0 fields [i64] quantities ["w"]
}
func.func @f(%x: i64) -> !idr.data<@T> {
  // expected-error @+1 {{expects 1 fields}}
  %v = idr.con @T::@A(%x, %x) : (i64, i64) -> !idr.data<@T>
  return %v : !idr.data<@T>
}

// -----

idr.data @T {
  idr.ctor @A tag 0 fields [i64] quantities ["w"]
}
func.func @f(%v: !idr.data<@T>) -> i64 {
  // expected-error @+1 {{field index out of range}}
  %x = idr.field %v[@A, 1] : !idr.data<@T> -> i64
  return %x : i64
}

// -----

idr.data @T {
  idr.ctor @A tag 0 fields [i64] quantities ["w"]
}
func.func @f(%v: !idr.data<@T>) -> i32 {
  // expected-error @+1 {{result type does not match the field type}}
  %x = idr.field %v[@A, 0] : !idr.data<@T> -> i32
  return %x : i32
}

// -----

idr.data @T {
  idr.ctor @A tag 0 fields [i64] quantities ["w"]
}
func.func @f(%v: !idr.data<@T>) -> index {
  %t = idr.tag %v : !idr.data<@T>
  return %t : index
}
