// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// The rules of a whole module, checked on its idr.program attribute.

// expected-error @+1 {{expects exactly one public function (the root), found 2}}
module attributes {idr.program} {
  func.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  func.func @b() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

// expected-error @+1 {{expects exactly one public function (the root), found 0}}
module attributes {idr.program} {
  func.func private @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

module attributes {idr.program} {
  // expected-error @+1 {{is the root, so its type must be () -> i64 or (!idr.world) -> (...), not '(i64) -> i64'}}
  func.func @a(%x: i64 {idr.quantity = "w"}) -> i64 {
    return %x : i64
  }
}

// -----

// Both kinds of root.
module attributes {idr.program} {
  func.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

module attributes {idr.program} {
  func.func @a(%w: !idr.world {idr.quantity = "1"}) -> (i64, !idr.world) {
    %c = arith.constant 0 : i64
    return %c, %w : i64, !idr.world
  }
}

// -----

// Containment through unboxed sums is acyclic.
module attributes {idr.program} {
  // expected-error @+1 {{contains itself through unboxed sums; a recursive type must be declared box}}
  idr.data @T {
    idr.ctor @A tag 0 (!idr.data<@U>) {quantities = ["w"]}
  }
  idr.data @U {
    idr.ctor @B tag 0 (!idr.data<@T>) {quantities = ["w"]}
  }
  func.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

// Every cycle passes through a box.
module attributes {idr.program} {
  idr.data @T {
    idr.ctor @A tag 0 (!idr.data<@U>) {quantities = ["w"]}
  }
  idr.data @U {
    idr.ctor @B tag 0 (!idr.box<@L>) {quantities = ["w"]}
  }
  idr.data @L box {
    idr.ctor @Nil tag 0 () {quantities = []}
    idr.ctor @Cons tag 1 (!idr.data<@T>, !idr.box<@L>) {quantities = ["w", "w"]}
  }
  func.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

// A box declaration's values are !idr.box.
module attributes {idr.program} {
  idr.data @L box {
    idr.ctor @Nil tag 0 () {quantities = []}
  }
  func.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // expected-error @+1 {{uses '!idr.data<@L>', but @L is declared box, so its values are !idr.box}}
  func.func private @b(%l: !idr.data<@L> {idr.quantity = "w"}) {
    return
  }
}

// -----

module attributes {idr.program} {
  idr.data @T {
    idr.ctor @A tag 0 () {quantities = []}
  }
  func.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // expected-error @+1 {{uses '!idr.box<@T>', but @T is declared unboxed, so its values are !idr.data}}
  func.func private @b(%t: !idr.box<@T> {idr.quantity = "w"}) {
    return
  }
}

// -----

module attributes {idr.program} {
  func.func @a() -> i64 {
    // expected-error @+1 {{uses an undeclared data type @Nowhere}}
    %c = idr.constant #idr.erased : !idr.fn<() -> (!idr.data<@Nowhere>)>
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

// expected-error @+1 {{expects idr.program as a unit attribute of the module}}
module attributes {idr.program = 1 : i64} {
}
