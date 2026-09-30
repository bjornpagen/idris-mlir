// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A world used twice on one path is rejected, wherever the second use is.
// The program verifier checks every function of an idr.program module.

module attributes {idr.program} {
func.func private @f(%w: !idr.world) -> !idr.world {
  %c = arith.constant 65 : i32
  %w1 = idr.io.put_char %c, %w
  // expected-error @+1 {{uses a world that is already used on the same path}}
  %w2 = idr.io.put_char %c, %w
  return %w2 : !idr.world
}
func.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

module attributes {idr.program} {
// A world produced inside the function counts too.
func.func private @f(%w: !idr.world) -> !idr.world {
  %c = arith.constant 65 : i32
  %w1 = idr.io.put_char %c, %w
  %w2 = idr.io.put_char %c, %w1
  // expected-error @+1 {{uses a world that is already used on the same path}}
  %w3 = idr.io.put_char %c, %w1
  return %w3 : !idr.world
}
func.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

module attributes {idr.program} {
// Returned and used: two uses.
func.func private @f(%w: !idr.world) -> (!idr.world, !idr.world) {
  // expected-error @+1 {{uses a world that is already used on the same path}}
  return %w, %w : !idr.world, !idr.world
}
func.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

module attributes {idr.program} {
// A use in a region of a match, then one after the match, is one path.
idr.data @B {
  idr.ctor @F ()
  idr.ctor @T ()
}
func.func private @f(%b: !idr.data<@B>,
                     %w: !idr.world) -> !idr.world {
  %c = arith.constant 65 : i32
  %r = idr.match %b : !idr.data<@B> -> (!idr.world) {
  case @F() {
    %w1 = idr.io.put_char %c, %w
    idr.yield %w1 : !idr.world
  }
  default {
    idr.yield %w : !idr.world
  }
  }
  // expected-error @+1 {{uses a world that is already used on the same path}}
  %w2 = idr.io.put_char %c, %w
  return %w2 : !idr.world
}
func.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

module attributes {idr.program} {
// Two uses within one region.
func.func private @f(%n: i64, %w: !idr.world) -> !idr.world {
  %c = arith.constant 65 : i32
  // expected-error @+1 {{uses a world that is already used on the same path}}
  %r = idr.match_lit %n : i64 -> (!idr.world) {
  case 0 {
    %w1 = idr.io.put_char %c, %w
    %w2 = idr.io.put_char %c, %w
    idr.yield %w2 : !idr.world
  }
  default {
    idr.yield %w : !idr.world
  }
  }
  return %r : !idr.world
}
func.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

module attributes {idr.program} {
// A world from before a loop, used in its body, is used once per iteration.
func.func private @f(%w: !idr.world, %n: i64) -> i64 {
  %c = arith.constant 65 : i32
  // expected-error @+1 {{uses a world that is already used on the same path}}
  %r = scf.while (%i = %n) : (i64) -> i64 {
    %w1 = idr.io.put_char %c, %w
    %t = arith.constant true
    scf.condition(%t) %i : i64
  } do {
  ^bb0(%j: i64):
    scf.yield %j : i64
  }
  return %r : i64
}
func.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}
