// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics

!T = !idr.data<"T", plain [@A(i64)]>
idr.program @values root(@root) stage(first) {
  idr.func @f(%x: i32) -> !T {
    // expected-error @+1 {{field has type 'i32', expected 'i64'}}
    %v = idr.con !T @A(%x : i32)
    return %v : !T
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!T = !idr.data<"T", plain [@A(i64)]>
idr.program @values root(@root) stage(first) {
  idr.func @f(%x: i64) -> !T {
    // expected-error @+1 {{the data type "T" has no constructor @B}}
    %v = idr.con !T @B(%x : i64)
    return %v : !T
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!T = !idr.data<"T", plain [@A(i64)]>
idr.program @values root(@root) stage(first) {
  idr.func @f(%x: i64) -> !T {
    // expected-error @+1 {{expects 1 fields}}
    %v = idr.con !T @A(%x : i64, %x : i64)
    return %v : !T
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!T = !idr.data<"T", plain [@A(i64)]>
idr.program @values root(@root) stage(first) {
  idr.func @f(%x: i64) -> !T {
    // expected-error @+1 {{has no constructor @T}}
    %v = idr.con !T @T(%x : i64)
    return %v : !T
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// Boxing is the value's type alone: one data type is built in place or
// in a cell, as the value's type says.
!T = !idr.data<"T", plain [@A()]>
idr.program @values root(@root) stage(first) {
  idr.func @f() -> (!T, !idr.box<!T>) {
    %v = idr.con !T @A()
    %b = idr.con !idr.box<!T> @A()
    return %v, %b : !T, !idr.box<!T>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!T = !idr.data<"T", plain [@A(i64)]>
idr.program @values root(@root) stage(first) {
  idr.func @f(%v: !T) -> i64 {
    // expected-error @+1 {{field index out of range}}
    %x = idr.field %v : !T @A[1] -> i64
    return %x : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!T = !idr.data<"T", plain [@A(i64)]>
idr.program @values root(@root) stage(first) {
  idr.func @f(%v: !T) -> i32 {
    // expected-error-re @+1 {{has result 'i32', but the field of a '!idr.data<"T"{{.*}}>' is read as 'i64'}}
    %x = idr.field %v : !T @A[0] -> i32
    return %x : i32
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!T = !idr.data<"T", plain [@A(i64)]>
idr.program @values root(@root) stage(first) {
  idr.func @f(%v: !T) -> i64 {
    // expected-error @+1 {{the data type "T" has no constructor @B}}
    %x = idr.field %v : !T @B[0] -> i64
    return %x : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @values root(@root) stage(first) {
  idr.func @f(%v: i64) -> i64 {
    // expected-error @+1 {{operand #0 must be}}
    %t = idr.tag %v : i64
    return %t : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @values root(@root) stage(first) {
  idr.func @f() {
    // expected-error @+1 {{cannot hold 1 : i64 as 'i64'}}
    %c = idr.constant i64 1
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @values root(@root) stage(first) {
  idr.func @f() {
    // expected-error @+1 {{cannot hold "x" as '!idr.big'}}
    %c = idr.constant !idr.big "x"
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!T = !idr.data<"T", plain [@A(i64, !idr.str)]>
idr.program @values root(@root) stage(first) {
  idr.func @f() {
    // expected-error @+1 {{has a constant 1 : i32 where 'i64' is expected}}
    %c = idr.constant !T #idr.con<!T, @A, [1 : i32, "x"]>
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!T = !idr.data<"T", plain [@A(i64, !idr.str)]>
idr.program @values root(@root) stage(first) {
  idr.func @f() {
    // expected-error @+1 {{expects the last cell of @A to hold its 2 fields}}
    %c = idr.constant !T #idr.con<!T, @A, [1 : i64]>
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// Values inside a constant are written without their types, but for
// integers and doubles.
!T = !idr.data<"T", plain [@A(!idr.str)]>
idr.program @values root(@root) stage(first) {
  idr.func @f() {
    // expected-error @+1 {{has a constant "x" : !idr.str where '!idr.str' is expected}}
    %c = idr.constant !T #idr.con<!T, @A, ["x" : !idr.str]>
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!T = !idr.data<"T", plain [@A()]>
idr.program @values root(@root) stage(first) {
  idr.func @f() {
    // expected-error @+1 {{the data type "T" has no constructor @B}}
    %c = idr.constant !T #idr.con<!T, @B, []>
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @values root(@root) stage(higher) {
  idr.func @g(%a: i64, %b: i64) -> i64 {
    idr.crash "no body"
    ub.unreachable
  }
  idr.func @f() {
    // expected-error @+1 {{has a closure of @g, of type '!idr.fn<(i64) -> i64>', where '!idr.fn<(i64, i64) -> i64>' is expected}}
    %c = idr.constant !idr.fn<(i64, i64) -> (i64)> #idr.closure<@g, [1 : i64]>
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @values root(@root) stage(higher) {
  idr.func @f() {
    // expected-error @+1 {{has a closure of an unknown function @nowhere}}
    %c = idr.constant !idr.fn<() -> ()> #idr.closure<@nowhere, []>
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// The nearest each refusal above has that verifies: a constructor the type
// has, its one field at its type; a field read at its index and its type,
// of the constructor the type has; the tag of a data value; constants of
// what a constant holds (a big from an integer, a string from a string);
// a constant constructor whose last cell holds its fields, each written
// at its type, integers with theirs and strings without.
!T = !idr.data<"T", plain [@A(i64)]>
!S = !idr.data<"S", plain [@A(i64, !idr.str)]>
!R = !idr.data<"R", plain [@A(!idr.str)]>
idr.program @values root(@root) stage(first) {
  idr.func @f(%x: i64) -> (!T, i64, i64) {
    %v = idr.con !T @A(%x : i64)
    %y = idr.field %v : !T @A[0] -> i64
    %t = idr.tag %v : !T
    return %v, %y, %t : !T, i64, i64
  }
  idr.func @g() -> (!idr.big, !idr.str, !S, !R) {
    %b = idr.constant !idr.big #idr.big<1>
    %s = idr.constant !idr.str "x"
    %c = idr.constant !S #idr.con<!S, @A, [1 : i64, "x"]>
    %r = idr.constant !R #idr.con<!R, @A, ["x"]>
    return %b, %s, %c, %r : !idr.big, !idr.str, !S, !R
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// A constant closure of a function the program has, at the type its
// captures leave.
idr.program @values root(@root) stage(higher) {
  idr.func @g(%a: i64, %b: i64) -> i64 {
    idr.crash "no body"
    ub.unreachable
  }
  idr.func @f() -> !idr.fn<(i64) -> (i64)> {
    %c = idr.constant !idr.fn<(i64) -> (i64)> #idr.closure<@g, [1 : i64]>
    return %c : !idr.fn<(i64) -> (i64)>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
