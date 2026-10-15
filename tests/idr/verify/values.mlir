// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics

!T = !idr.data<"T", plain [@A(i64)]>
idr.func private @f(%x: i32) -> !T {
  // expected-error @+1 {{field has type 'i32', expected 'i64'}}
  %v = idr.con @A(%x) : (i32) -> !T
  return %v : !T
}

// -----

!T = !idr.data<"T", plain [@A(i64)]>
idr.func private @f(%x: i64) -> !T {
  // expected-error @+1 {{refers to an unknown constructor @B}}
  %v = idr.con @B(%x) : (i64) -> !T
  return %v : !T
}

// -----

!T = !idr.data<"T", plain [@A(i64)]>
idr.func private @f(%x: i64) -> !T {
  // expected-error @+1 {{expects 1 fields}}
  %v = idr.con @A(%x, %x) : (i64, i64) -> !T
  return %v : !T
}

// -----

!T = !idr.data<"T", plain [@A(i64)]>
idr.func private @f(%x: i64) -> !T {
  // expected-error @+1 {{expects a constructor reference @C}}
  %v = idr.con @T(%x) : (i64) -> !T
  return %v : !T
}

// -----

// Boxing is the value's type alone: one data type is built in place or
// in a cell, as the value's type says.
!T = !idr.data<"T", plain [@A()]>
idr.func private @f() -> (!T, !idr.box<!T>) {
  %v = idr.con @A() : () -> !T
  %b = idr.con @A() : () -> !idr.box<!T>
  return %v, %b : !T, !idr.box<!T>
}

// -----

!T = !idr.data<"T", plain [@A(i64)]>
idr.func private @f(%v: !T) -> i64 {
  // expected-error @+1 {{field index out of range}}
  %x = idr.field %v[@A, 1] : !T -> i64
  return %x : i64
}

// -----

!T = !idr.data<"T", plain [@A(i64)]>
idr.func private @f(%v: !T) -> i32 {
  // expected-error-re @+1 {{has result 'i32', but the field of a '!idr.data<"T"{{.*}}>' is read as 'i64'}}
  %x = idr.field %v[@A, 0] : !T -> i32
  return %x : i32
}

// -----

!T = !idr.data<"T", plain [@A(i64)]>
idr.func private @f(%v: !T) -> i64 {
  // expected-error @+1 {{refers to an unknown constructor @B}}
  %x = idr.field %v[@B, 0] : !T -> i64
  return %x : i64
}

// -----

idr.func private @f(%v: i64) -> i64 {
  // expected-error @+1 {{operand #0 must be}}
  %t = idr.tag %v : i64
  return %t : i64
}

// -----

idr.func private @f() {
  // expected-error @+1 {{cannot hold 1 : i64 as 'i64'}}
  %c = idr.constant 1 : i64
  return
}

// -----

idr.func private @f() {
  // expected-error @+1 {{cannot hold "x" as '!idr.big'}}
  %c = idr.constant "x" : !idr.big
  return
}

// -----

idr.func private @f() {
  // expected-error @+1 {{expects a value followed by `:` and its type}}
  %c = idr.constant #idr.effects<io>
  return
}

// -----

idr.func private @f() {
  // expected-error @+1 {{expects a big in canonical decimal, got "-0"}}
  %c = idr.constant #idr.big<"-0"> : !idr.big
  return
}

// -----

idr.func private @f() {
  // expected-error @+1 {{expects a big in canonical decimal, got "007"}}
  %c = idr.constant #idr.big<"007"> : !idr.big
  return
}

// -----

!T = !idr.data<"T", plain [@A(i64, !idr.str)]>
idr.func private @f() {
  // expected-error @+1 {{has a constant 1 : i32 where 'i64' is expected}}
  %c = idr.constant #idr.con<@A, [1 : i32, "x"]> : !T
  return
}

// -----

!T = !idr.data<"T", plain [@A(i64, !idr.str)]>
idr.func private @f() {
  // expected-error @+1 {{has a constant with 1 fields or captures where 2 are expected}}
  %c = idr.constant #idr.con<@A, [1 : i64]> : !T
  return
}

// -----

// Values inside a constant are written without their types, but for
// integers and doubles.
!T = !idr.data<"T", plain [@A(!idr.str)]>
idr.func private @f() {
  // expected-error @+1 {{has a constant "x" : !idr.str where '!idr.str' is expected}}
  %c = idr.constant #idr.con<@A, ["x" : !idr.str]> : !T
  return
}

// -----

!T = !idr.data<"T", plain [@A()]>
idr.func private @f() {
  // expected-error @+1 {{has a constant of an unknown constructor @B}}
  %c = idr.constant #idr.con<@B, []> : !T
  return
}

// -----

idr.func private @g(%a: i64, %b: i64) -> i64 {
  idr.crash "no body"
  ub.unreachable
}
idr.func private @f() {
  // expected-error @+1 {{has a closure of @g, of type '!idr.fn<(i64) -> i64>', where '!idr.fn<(i64, i64) -> i64>' is expected}}
  %c = idr.constant #idr.closure<@g, [1 : i64]> : !idr.fn<(i64, i64) -> (i64)>
  return
}

// -----

idr.func private @f() {
  // expected-error @+1 {{has a closure of an unknown function @nowhere}}
  %c = idr.constant #idr.closure<@nowhere, []> : !idr.fn<() -> ()>
  return
}
