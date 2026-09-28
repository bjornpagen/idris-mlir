// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// rule: IDR-WORLD-1, IDR-TY-5
// A world used twice on one path is rejected, wherever the second use is.

func.func private @f(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
  %c = arith.constant 65 : i32
  %w1 = idr.io.put_char %c, %w
  // expected-error @+1 {{uses a world that is already used on the same path (IDR-WORLD-1)}}
  %w2 = idr.io.put_char %c, %w
  return %w2 : !idr.world
}

// -----

// A world produced inside the function counts too.
func.func private @f(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
  %c = arith.constant 65 : i32
  %w1 = idr.io.put_char %c, %w
  %w2 = idr.io.put_char %c, %w1
  // expected-error @+1 {{uses a world that is already used on the same path (IDR-WORLD-1)}}
  %w3 = idr.io.put_char %c, %w1
  return %w3 : !idr.world
}

// -----

// Returned and used: two uses.
func.func private @f(%w: !idr.world {idr.quantity = "1"}) -> (!idr.world, !idr.world) {
  // expected-error @+1 {{uses a world that is already used on the same path (IDR-WORLD-1)}}
  return %w, %w : !idr.world, !idr.world
}

// -----

// A use in a region of a match, then one after the match, is one path.
idr.data @B {
  idr.ctor @F tag 0 () {quantities = []}
  idr.ctor @T tag 1 () {quantities = []}
}
func.func private @f(%b: !idr.data<@B> {idr.quantity = "w"},
                     %w: !idr.world {idr.quantity = "1"}) -> !idr.world {
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
  // expected-error @+1 {{uses a world that is already used on the same path (IDR-WORLD-1)}}
  %w2 = idr.io.put_char %c, %w
  return %w2 : !idr.world
}

// -----

// Two uses within one region.
func.func private @f(%n: i64 {idr.quantity = "w"}, %w: !idr.world {idr.quantity = "1"}) -> !idr.world {
  %c = arith.constant 65 : i32
  // expected-error @+1 {{uses a world that is already used on the same path (IDR-WORLD-1)}}
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

// -----

// A world from before a loop, used in its body, is used once per iteration.
func.func private @f(%w: !idr.world {idr.quantity = "1"}, %n: i64 {idr.quantity = "w"}) -> i64 {
  %c = arith.constant 65 : i32
  // expected-error @+1 {{uses a world that is already used on the same path (IDR-WORLD-1)}}
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
