// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// The verifier errors that the custom syntax cannot produce, in the generic
// form, where the default region is first and a case is a tag.

!T = !idr.data<"T", plain [@A()]>
idr.program @generic root(@root) stage(first) {
  idr.func @f(%v: !T) {
    // expected-error @+1 {{expects one key per case region}}
    "idr.match"(%v) <{cases = array<i32: 0>}> ({
    ^bb0(%d: !T):
      "idr.yield"() : () -> ()
    }, {
      "idr.yield"() : () -> ()
    }, {
      "idr.yield"() : () -> ()
    }) : (!T) -> ()
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
idr.program @generic root(@root) stage(first) {
  idr.func @f(%v: !T) {
    // expected-error @+1 {{names constructor 1 of "T", which has 1}}
    "idr.match"(%v) <{cases = array<i32: 1>}> ({
    ^bb0(%d: !T):
      "idr.yield"() : () -> ()
    }, {
      "idr.yield"() : () -> ()
    }) : (!T) -> ()
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
idr.program @generic root(@root) stage(first) {
  idr.func @f(%v: !T) {
    // expected-error @+1 {{expects a default region that takes the scrutinee back at its type}}
    "idr.match"(%v) <{cases = array<i32: 0>}> ({
    ^bb0(%x: i64):
      "idr.yield"() : () -> ()
    }, {
      "idr.yield"() : () -> ()
    }) : (!T) -> ()
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @generic root(@root) stage(first) {
  idr.func @f(%v: i64) {
    // expected-error @+1 {{expects case regions without arguments}}
    "idr.match_lit"(%v) <{cases = [0]}> ({
    ^bb0(%d: i64):
      "idr.yield"() : () -> ()
    }, {
    ^bb0(%x: i64):
      "idr.yield"() : () -> ()
    }) : (i64) -> ()
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @generic root(@root) stage(first) {
  idr.func @f(%v: i64) {
    // expected-error @+1 {{has a key 0 : i32 that is not a literal of 'i64'}}
    "idr.match_lit"(%v) <{cases = [0 : i32]}> ({
    ^bb0(%d: i64):
      "idr.yield"() : () -> ()
    }, {
      "idr.yield"() : () -> ()
    }) : (i64) -> ()
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @generic root(@root) stage(first) {
  idr.func @f(%v: i64) {
    // expected-error @+1 {{expects a non-empty block}}
    "idr.match_lit"(%v) <{cases = [0]}> ({
    ^bb0(%d: i64):
      "idr.yield"() : () -> ()
    }, {
    ^bb0:
    }) : (i64) -> ()
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// A constant names a constructor of its own type's body.
!T = !idr.data<"T", plain [@C()]>
idr.program @generic root(@root) stage(first) {
  idr.func @f() {
    // expected-error @+1 {{@D}}
    %c = idr.constant !T #idr.con<!T, @D, []>
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// The nearest each refusal above has that verifies, in the generic form
// too: one key for the one case region, constructor 0 of the one "T" has,
// a default region that takes the scrutinee back at its type; a literal
// match whose case region takes no argument, holds its terminator, and is
// keyed by a literal of the scrutinee's type; a constant of the
// constructor its type has.
!T = !idr.data<"T", plain [@C()]>
idr.program @generic root(@root) stage(first) {
  idr.func @f(%v: !T) {
    "idr.match"(%v) <{cases = array<i32: 0>}> ({
    ^bb0(%d: !T):
      "idr.yield"() : () -> ()
    }, {
      "idr.yield"() : () -> ()
    }) : (!T) -> ()
    return
  }
  idr.func @g(%v: i64) {
    "idr.match_lit"(%v) <{cases = [0]}> ({
    ^bb0(%d: i64):
      "idr.yield"() : () -> ()
    }, {
      "idr.yield"() : () -> ()
    }) : (i64) -> ()
    return
  }
  idr.func @h() {
    %c = idr.constant !T #idr.con<!T, @C, []>
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
