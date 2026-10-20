// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// The integers of Idris are 8, 16, 32 and 64 bits wide, and so is every
// integer an idr op computes on (idr.match_lit also branches on a
// condition); only what counts references is counted.

idr.program @widths root(@root) stage(first) types #idr.types<> {
  idr.func @f(%a: i7, %b: i7) -> i7 {
    // expected-error @+1 {{but got 'i7'}}
    %q = idr.divs %a, %b : i7
    return %q : i7
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @widths root(@root) stage(first) types #idr.types<> {
  idr.func @f(%a: i1) -> i32 {
    // expected-error @+1 {{but got 'i1'}}
    %c = idr.to_char_u %a : i1
    return %c : i32
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @widths root(@root) stage(first) types #idr.types<> {
  idr.func @f(%d: f64) -> i128 {
    // expected-error @+1 {{but got 'i128'}}
    %i = idr.to_int %d : i128
    return %i : i128
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @widths root(@root) stage(first) types #idr.types<> {
  idr.func @f(%a: i1, %w: !idr.world) -> !idr.world {
    // expected-error @+1 {{but got 'i1'}}
    %w1 = idr.io.put_uint %a, %w : i1
    return %w1 : !idr.world
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// A linear integer holds no reference, so nothing counts it.
idr.program @widths root(@root) stage(owned) types #idr.types<> {
  idr.func @f(%x: !idr.lin<i64>) {
    // expected-error @+1 {{but got '!idr.lin<i64>'}}
    %o = idr.dup %x : !idr.lin<i64>
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// The nearest each refusal above has that verifies: the same ops at the
// widths next to the refused ones, 8 bits for 7 and 1, 64 for 128, and
// the count of a value that holds a reference.
idr.program @widths root(@root) stage(first) types #idr.types<> {
  idr.func @f8(%a: i8, %b: i8) -> i8 {
    %q = idr.divs %a, %b : i8
    return %q : i8
  }
  idr.func @f64(%a: i64, %b: i64) -> i64 {
    %q = idr.divs %a, %b : i64
    return %q : i64
  }
  idr.func @char(%a: i8) -> i32 {
    %c = idr.to_char_u %a : i8
    return %c : i32
  }
  idr.func @int(%d: f64) -> i64 {
    %i = idr.to_int %d : i64
    return %i : i64
  }
  idr.func @put(%a: i8, %w: !idr.world) -> !idr.world {
    %w1 = idr.io.put_uint %a, %w : i8
    return %w1 : !idr.world
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @widths root(@root) stage(owned) types #idr.types<> {
  idr.func @f(%x: !idr.q<many, borrow, !idr.str>) -> !idr.own<!idr.str> {
    %o = idr.dup %x : !idr.q<many, borrow, !idr.str>
    return %o : !idr.own<!idr.str>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
