// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A world is used exactly once on every path: used twice on one path it
// is rejected, wherever the second use is, and used once on each path it
// is accepted (the last split). Each idr.func verifies its own body.

idr.program @once root(@root) stage(first) {
idr.func @f(%w: !idr.world) -> !idr.world {
  %c = arith.constant 65 : i32
  %w1 = idr.io.put_char %c, %w
  // expected-error @+1 {{uses a world that is already used on the same path}}
  %w2 = idr.io.put_char %c, %w
  return %w2 : !idr.world
}
idr.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

idr.program @once root(@root) stage(first) {
// A world produced inside the function counts too.
idr.func @f(%w: !idr.world) -> !idr.world {
  %c = arith.constant 65 : i32
  %w1 = idr.io.put_char %c, %w
  %w2 = idr.io.put_char %c, %w1
  // expected-error @+1 {{uses a world that is already used on the same path}}
  %w3 = idr.io.put_char %c, %w1
  return %w3 : !idr.world
}
idr.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

idr.program @once root(@root) stage(first) {
// Returned and used: two uses.
idr.func @f(%w: !idr.world) -> (!idr.world, !idr.world) {
  // expected-error @+1 {{uses a world that is already used on the same path}}
  return %w, %w : !idr.world, !idr.world
}
idr.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

!B = !idr.data<"B", plain [@F(), @T()]>
idr.program @once root(@root) stage(first) {
// A use in a region of a match, then one after the match, is one path.
idr.func @f(%b: !B,
                     %w: !idr.world) -> !idr.world {
  %c = arith.constant 65 : i32
  %r = idr.match %b : !B -> (!idr.world) {
  case @F() {
    %w1 = idr.io.put_char %c, %w
    idr.yield %w1 : !idr.world
  }
  default(%d: !B) {
    idr.yield %w : !idr.world
  }
  }
  // expected-error @+1 {{uses a world that is already used on the same path}}
  %w2 = idr.io.put_char %c, %w
  return %w2 : !idr.world
}
idr.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

idr.program @once root(@root) stage(first) {
// Two uses within one region.
idr.func @f(%n: i64, %w: !idr.world) -> !idr.world {
  %c = arith.constant 65 : i32
  // expected-error @+1 {{uses a world that is already used on the same path}}
  %r = idr.match_lit %n : i64 -> (!idr.world) {
  case 0 {
    %w1 = idr.io.put_char %c, %w
    %w2 = idr.io.put_char %c, %w
    idr.yield %w2 : !idr.world
  }
  default(%d: i64) {
    idr.yield %w : !idr.world
  }
  }
  return %r : !idr.world
}
idr.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

idr.program @once root(@root) stage(first) {
// A world from before a loop, used in its body, is used once per iteration.
idr.func @f(%w: !idr.world, %n: i64) -> i64 {
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
idr.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----
// Worlds used once on each path are accepted.


// A chain of IO ops.
!B = !idr.data<"B", plain [@F(), @T()]>
!IORes = !idr.data<"IORes", plain [@MkIORes(i64, !idr.world)]>
idr.program @once root(@chain) stage(first) {
  idr.func @chain(%w: !idr.world) -> !idr.world {
    %c = arith.constant 65 : i32
    %w1 = idr.io.put_char %c, %w
    %w2 = idr.io.put_char %c, %w1
    return %w2 : !idr.world
  }

  // One use in each region of a match is one use on each path.
  idr.func @branches(%b: !B,
                              %w: !idr.world) -> !idr.world {
    %c = arith.constant 65 : i32
    %r = idr.match %b : !B -> (!idr.world) {
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
  idr.func @crash(%n: i64, %w: !idr.world) -> !idr.world {
    %c = arith.constant 65 : i32
    %r = idr.match_lit %n : i64 -> (!idr.world) {
    case 0 {
      idr.yield %w : !idr.world
    }
    default(%d: i64) {
      idr.crash "no"
      ub.unreachable
    }
    }
    %w1 = idr.io.put_char %c, %r
    return %w1 : !idr.world
  }

  // A world stored in a constructor and returned is used once.
  idr.func @stored(%w: !idr.world) -> !IORes {
    %z = arith.constant 0 : i64
    %r = idr.con !IORes @MkIORes(%z : i64, %w : !idr.world)
    return %r : !IORes
  }

  // A loop carries the world from one iteration to the next.
  idr.func @loop(%w: !idr.world) -> !idr.world {
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
}
