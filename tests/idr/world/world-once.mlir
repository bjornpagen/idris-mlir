// RUN: idris-mlir-opt %s | FileCheck %s
// rule: IDR-WORLD-1, IDR-TY-5
// Worlds used once on each path are accepted.

idr.data @B {
  idr.ctor @F tag 0 () {quantities = []}
  idr.ctor @T tag 1 () {quantities = []}
}
idr.data @IORes {
  idr.ctor @MkIORes tag 0 (i64, !idr.world) {quantities = ["w", "1"]}
}

// A chain of IO ops.
// CHECK-LABEL: func.func private @chain
func.func private @chain(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
  %c = arith.constant 65 : i32
  %w1 = idr.io.put_char %c, %w
  %w2 = idr.io.put_char %c, %w1
  return %w2 : !idr.world
}

// One use in each region of a match is one use on each path.
// CHECK-LABEL: func.func private @branches
func.func private @branches(%b: !idr.data<@B> {idr.quantity = "w"},
                            %w: !idr.world {idr.quantity = "1"}) -> !idr.world {
  %c = arith.constant 65 : i32
  %r = idr.match %b : !idr.data<@B> -> (!idr.world) {
  case @F() {
    %w1 = idr.io.put_char %c, %w
    idr.yield %w1 : !idr.world
  }
  case @T() {
    %w1 = idr.io.put_char %c, %w
    %w2 = idr.io.put_char %c, %w1
    idr.yield %w2 : !idr.world
  }
  }
  %w3 = idr.io.put_char %c, %r
  return %w3 : !idr.world
}

// A region that crashes does not reach the use after the match, but no
// region is special: a region that yields the world unused is fine.
// CHECK-LABEL: func.func private @crash
func.func private @crash(%n: i64 {idr.quantity = "w"}, %w: !idr.world {idr.quantity = "1"}) -> !idr.world {
  %c = arith.constant 65 : i32
  %r = idr.match_lit %n : i64 -> (!idr.world) {
  case 0 {
    idr.yield %w : !idr.world
  }
  default {
    idr.crash "no"
    ub.unreachable
  }
  }
  %w1 = idr.io.put_char %c, %r
  return %w1 : !idr.world
}

// A world stored in a constructor and returned is used once.
// CHECK-LABEL: func.func private @stored
func.func private @stored(%w: !idr.world {idr.quantity = "1"}) -> !idr.data<@IORes> {
  %z = arith.constant 0 : i64
  %r = idr.con @IORes::@MkIORes(%z, %w) : (i64, !idr.world) -> !idr.data<@IORes>
  return %r : !idr.data<@IORes>
}

// A loop carries the world from one iteration to the next.
// CHECK-LABEL: func.func private @loop
func.func private @loop(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
  %c = arith.constant 65 : i32
  %r = scf.while (%v = %w) : (!idr.world) -> !idr.world {
    %v1 = idr.io.put_char %c, %v
    %t = arith.constant true
    scf.condition(%t) %v1 : !idr.world
  } do {
  ^bb0(%u: !idr.world):
    scf.yield %u : !idr.world
  }
  return %r : !idr.world
}
