// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// What is known of a function is idr.func's own attributes, and what is
// known of a parameter is its type: its quantity and what it owns. So the
// dialect marks no argument, and refuses an idr.* argument attribute,
// a clone's hole included, whose position is its parameter's.

idr.program @function root(@root) stage(first) {
  // expected-error @+1 {{has an unknown idr argument attribute "idr.hole"}}
  idr.func @f(%x: i64 {idr.hole = 0 : i64}) -> i64 {
    return %x : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @function root(@root) stage(first) {
  // expected-error @+1 {{has an unknown idr argument attribute "idr.quantity"}}
  idr.func @f(%x: i64 {idr.quantity = "1"}) {
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @function root(@root) stage(first) {
  // A fact written as a discardable attribute is no fact: idr.func has its
  // own.
  // expected-error @+1 {{has an unknown idr attribute "idr.total"}}
  idr.func @f() attributes {idr.total} {
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @function root(@root) stage(first) {
  idr.func @f() {
    // expected-error @+1 {{has an unknown idr attribute "idr.entry"}}
    %c = arith.constant {idr.entry} 0 : i64
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// An argument attribute of no dialect is no business of ours.
idr.program @function root(@root) stage(first) {
  idr.func @f(%x: i64 {sample.x}) -> i64 {
    return %x : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// The facts a function may carry.
idr.program @function root(@root) stage(first) {
  idr.func @f(%x: !idr.lin<i64>, %y: i64)
      attributes {total, effects = #idr.effects<io, crash>, no_inline} {
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
