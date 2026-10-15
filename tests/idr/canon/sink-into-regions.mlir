// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=no-heap-allocation=@write_in_both,\
// RUN: checks-every-path=@may_crash -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize=test-convergence=true -o /dev/null
// A value free of effects (an allocation aside) that only a match's regions
// use moves into each region that uses it; there it meets its consumer. A
// value the match itself or code after it uses cannot move, which the
// verifier holds after the pass; one that may crash stays where it runs on
// every path.

// putStr (show x) in both regions of a match on b: the string moves into
// each region, where output fusion writes the number without building it.
!Bool = !idr.data<"Bool", plain [@False(), @True()]>
idr.program @"sink-into-regions" root(@root) stage(first) {
  idr.func @write_in_both(%b: !Bool, %x: i64, %w: !idr.world) -> !idr.world {
    %s = idr.str.show signed %x : i64
    %r = idr.match %b : !Bool -> (!idr.world) {
    case @False() {
      %c = idr.constant "no: " : !idr.str
      %w1 = idr.io.put_str %c, %w
      %w2 = idr.io.put_str %s, %w1
      idr.yield %w2 : !idr.world
    }
    case @True() {
      %c = idr.constant "yes: " : !idr.str
      %w1 = idr.io.put_str %c, %w
      %w2 = idr.io.put_str %s, %w1
      idr.yield %w2 : !idr.world
    }
    }
    return %r : !idr.world
  }

  // Used by the match itself (its scrutinee): the value stays.
  idr.func @scrutinee(%x: i64) -> i64 {
    %n = arith.addi %x, %x : i64
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %n : i64
    }
    default {
      %c = arith.constant 7 : i64
      idr.yield %c : i64
    }
    }
    return %r : i64
  }

  // Used after the match too: the value stays.
  idr.func @keep(%a0: !idr.str) -> i64 {
    idr.crash "no body"
    ub.unreachable
  }
  idr.func @used_after(%n: i64, %a: !idr.str, %b: !idr.str) -> i64 {
    %s = idr.str.append %a, %b
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %k = idr.call @keep(%s) : (!idr.str) -> i64
      idr.yield %k : i64
    }
    default {
      idr.yield %n : i64
    }
    }
    %k2 = idr.call @keep(%s) : (!idr.str) -> i64
    %t = arith.addi %r, %k2 : i64
    return %t : i64
  }

  // A value with an effect (a guard, which may crash) stays before the match.
  idr.func @may_crash(%n: i64, %x: i64, %y: i64) -> i64 {
    %y1 = idr.check.nonzero %y, "division by zero" : i64
    %q = idr.div signed %x, %y1 : i64
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %q : i64
    }
    default {
      idr.yield %n : i64
    }
    }
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
