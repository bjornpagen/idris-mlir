// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A grade written out is checked as any other: the verifier's canonical
// forms, and the parser's spellings of a quantity.

idr.program @"grades-invalid" root(@root) stage(first) {
  // expected-error @+1 {{expects a grade other than (many, plain), which is the plain type}}
  idr.func @plain(%a0: !idr.q<many, plain, i64>) {
    idr.crash "no body"
    ub.unreachable
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// A type whose every value is used exactly once by the type alone takes
// no grade, whichever grade is written: one rule for the world and a
// destination.
idr.program @"grades-invalid" root(@root) stage(owned) {
  // expected-error @+1 {{which is used exactly once by its type}}
  idr.func @world(%a0: !idr.q<many, own, !idr.world>) {
    idr.crash "no body"
    ub.unreachable
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @"grades-invalid" root(@root) stage(first) {
  // expected-error @+1 {{which is used exactly once by its type}}
  idr.func @world(%a0: !idr.lin<!idr.world>) {
    idr.crash "no body"
    ub.unreachable
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!T = !idr.data<"T", plain [@A()]>
idr.program @"grades-invalid" root(@root) stage(first) {
  // expected-error @+1 {{which is used exactly once by its type}}
  idr.func @dest(%a0: !idr.lin<!idr.dest<!idr.box<!T>>>) {
    idr.crash "no body"
    ub.unreachable
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @"grades-invalid" root(@root) stage(owned) {
  // expected-error @+1 {{expects a grade of a plain type, got one of}}
  idr.func @graded(%a0: !idr.q<one, own, !idr.lin<i64>>) {
    idr.crash "no body"
    ub.unreachable
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @"grades-invalid" root(@root) stage(first) {
  // A value of quantity zero has no runtime representation, so no grade holds
  // one: a grade is of a runtime type.
  // expected-error @+1 {{expects a grade of a runtime type, got 'none'}}
  idr.func @none(%a0: !idr.q<one, plain, none>) {
    idr.crash "no body"
    ub.unreachable
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @"grades-invalid" root(@root) stage(first) {
  // expected-error @+2 {{expected ::idr::Quantity to be one of: one, many}}
  // expected-error @+1 {{parameter 'quantity' which is to be a `::idr::Quantity`}}
  idr.func @two(%a0: !idr.q<two, plain, i64>) {
    idr.crash "no body"
    ub.unreachable
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
