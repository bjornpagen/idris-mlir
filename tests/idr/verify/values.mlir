// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics

idr.data @T {
  idr.ctor @A (i64)
}
func.func @f(%x: i32) -> !idr.data<@T> {
  // expected-error @+1 {{field has type 'i32', expected 'i64'}}
  %v = idr.con @T::@A(%x) : (i32) -> !idr.data<@T>
  return %v : !idr.data<@T>
}

// -----

idr.data @T {
  idr.ctor @A (i64)
}
func.func @f(%x: i64) -> !idr.data<@T> {
  // expected-error @+1 {{refers to an unknown constructor @T::@B}}
  %v = idr.con @T::@B(%x) : (i64) -> !idr.data<@T>
  return %v : !idr.data<@T>
}

// -----

idr.data @T {
  idr.ctor @A (i64)
}
func.func @f(%x: i64) -> !idr.data<@T> {
  // expected-error @+1 {{expects 1 fields}}
  %v = idr.con @T::@A(%x, %x) : (i64, i64) -> !idr.data<@T>
  return %v : !idr.data<@T>
}

// -----

idr.data @T {
  idr.ctor @A (i64)
}
func.func @f(%x: i64) -> !idr.data<@T> {
  // expected-error @+1 {{expects a constructor reference @T::@C}}
  %v = idr.con @T(%x) : (i64) -> !idr.data<@T>
  return %v : !idr.data<@T>
}

// -----

// A box's values are !idr.box.
idr.data @L box {
  idr.ctor @Nil ()
}
func.func @f() -> !idr.data<@L> {
  // expected-error @+1 {{builds @L::@Nil but has type '!idr.data<@L>'}}
  %v = idr.con @L::@Nil() : () -> !idr.data<@L>
  return %v : !idr.data<@L>
}

// -----

idr.data @T {
  idr.ctor @A ()
}
func.func @f() -> !idr.box<@T> {
  // expected-error @+1 {{builds @T::@A but has type '!idr.box<@T>'}}
  %v = idr.con @T::@A() : () -> !idr.box<@T>
  return %v : !idr.box<@T>
}

// -----

idr.data @T {
  idr.ctor @A (i64)
}
func.func @f(%v: !idr.data<@T>) -> i64 {
  // expected-error @+1 {{field index out of range}}
  %x = idr.field %v[@A, 1] : !idr.data<@T> -> i64
  return %x : i64
}

// -----

idr.data @T {
  idr.ctor @A (i64)
}
func.func @f(%v: !idr.data<@T>) -> i32 {
  // expected-error @+1 {{has result 'i32', but the field of a '!idr.data<@T>' is read as 'i64'}}
  %x = idr.field %v[@A, 0] : !idr.data<@T> -> i32
  return %x : i32
}

// -----

idr.data @T {
  idr.ctor @A (i64)
}
func.func @f(%v: !idr.data<@T>) -> i64 {
  // expected-error @+1 {{refers to an unknown constructor @B}}
  %x = idr.field %v[@B, 0] : !idr.data<@T> -> i64
  return %x : i64
}

// -----

func.func @f(%v: i64) -> i64 {
  // expected-error @+1 {{operand #0 must be}}
  %t = idr.tag %v : i64
  return %t : i64
}

// -----

func.func @f() {
  // expected-error @+1 {{cannot hold 1 : i64 as 'i64'}}
  %c = idr.constant 1 : i64
  return
}

// -----

func.func @f() {
  // expected-error @+1 {{cannot hold "x" as '!idr.big'}}
  %c = idr.constant "x" : !idr.big
  return
}

// -----

func.func @f() {
  // expected-error @+1 {{expects a value followed by `:` and its type}}
  %c = idr.constant #idr.erased
  return
}

// -----

func.func @f() {
  // expected-error @+1 {{expects a big in canonical decimal, got "-0"}}
  %c = idr.constant #idr.big<"-0"> : !idr.big
  return
}

// -----

func.func @f() {
  // expected-error @+1 {{expects a big in canonical decimal, got "007"}}
  %c = idr.constant #idr.big<"007"> : !idr.big
  return
}

// -----

idr.data @T {
  idr.ctor @A (i64, !idr.str)
}
func.func @f() {
  // expected-error @+1 {{has a constant 1 : i32 where 'i64' is expected}}
  %c = idr.constant #idr.con<@T::@A, [1 : i32, "x"]> : !idr.data<@T>
  return
}

// -----

idr.data @T {
  idr.ctor @A (i64, !idr.str)
}
func.func @f() {
  // expected-error @+1 {{has a constant with 1 fields or captures where 2 are expected}}
  %c = idr.constant #idr.con<@T::@A, [1 : i64]> : !idr.data<@T>
  return
}

// -----

// Values inside a constant are written without their types, but for
// integers and doubles.
idr.data @T {
  idr.ctor @A (!idr.str)
}
func.func @f() {
  // expected-error @+1 {{has a constant "x" : !idr.str where '!idr.str' is expected}}
  %c = idr.constant #idr.con<@T::@A, ["x" : !idr.str]> : !idr.data<@T>
  return
}

// -----

idr.data @T {
  idr.ctor @A ()
}
func.func @f() {
  // expected-error @+1 {{has a constant of an unknown constructor @T::@B}}
  %c = idr.constant #idr.con<@T::@B, []> : !idr.data<@T>
  return
}

// -----

func.func private @g(%a: i64, %b: i64) -> i64
func.func @f() {
  // expected-error @+1 {{has a closure of @g, of type '!idr.fn<(i64) -> (i64)>', where '!idr.fn<(i64, i64) -> (i64)>' is expected}}
  %c = idr.constant #idr.closure<@g, [1 : i64]> : !idr.fn<(i64, i64) -> (i64)>
  return
}

// -----

func.func @f() {
  // expected-error @+1 {{has a closure of an unknown function @nowhere}}
  %c = idr.constant #idr.closure<@nowhere, []> : !idr.fn<() -> ()>
  return
}
