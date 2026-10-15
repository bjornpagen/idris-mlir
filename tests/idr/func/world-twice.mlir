// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// The world is used once on every path: each IO step takes the world the
// step before gave. The rule is one function's, checked by idr.func's own
// verifier after the ops of its body, whether or not the module is a whole
// program; a second use is refused where it is.

idr.program @"world-twice" root(@twice) stage(first) {
  idr.func @twice(%w: !idr.world) -> !idr.world {
    %c = arith.constant 65 : i32
    %w1 = idr.io.put_char %c, %w
    // expected-error @+1 {{uses a world that is already used on the same path}}
    %w2 = idr.io.put_char %c, %w
    return %w2 : !idr.world
  }
}

// -----

idr.program @"world-twice" root(@Prog.main) stage(first) {
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c = arith.constant 65 : i32
    %w1 = idr.io.put_char %c, %w
    %w2 = idr.io.put_char %c, %w1
    // expected-error @+1 {{uses a world that is already used on the same path}}
    %w3 = idr.io.put_char %c, %w1
    return %w3 : !idr.world
  }
}

// -----

// A world used in a region of a match is used by the match: using it again
// after the match is a second use on that path.
idr.program @"world-twice" root(@root) stage(first) {
  idr.func @after(%b: i64, %w: !idr.world) -> !idr.world {
    %c = arith.constant 65 : i32
    %r = idr.match_lit %b : i64 -> (i64) {
    case 0 {
      %w1 = idr.io.put_char %c, %w
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    default {
      idr.yield %b : i64
    }
    }
    // expected-error @+1 {{uses a world that is already used on the same path}}
    %w2 = idr.io.put_char %c, %w
    return %w2 : !idr.world
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// Once in each region of a match is once on each path.
idr.program @"world-twice" root(@root) stage(first) {
  idr.func @branch(%b: i64, %w: !idr.world) -> !idr.world {
    %c = arith.constant 65 : i32
    %r = idr.match_lit %b : i64 -> (!idr.world) {
    case 0 {
      %w1 = idr.io.put_char %c, %w
      idr.yield %w1 : !idr.world
    }
    default {
      idr.yield %w : !idr.world
    }
    }
    return %r : !idr.world
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
