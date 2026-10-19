// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=no-heap-allocation=@write_in_both,\
// RUN: checks-every-path=@may_crash -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// A value free of effects (an allocation aside) that only a match's regions
// use moves into each region that uses it; there it meets its consumer.
// One that may crash stays where it runs on every path.

// putStr (show x) in both regions of a match on b: the string moves into
// each region, where output fusion writes the number without building it.
!Bool = !idr.data<"Bool", plain [@False(), @True()]>
idr.program @"sink-into-regions" root(@root) stage(first) {
  idr.func @write_in_both(%b: !Bool, %x: i64, %w: !idr.world) -> !idr.world {
    %s = idr.str.show_sint %x : i64
    %r = idr.match %b : !Bool -> (!idr.world) {
    case @False() {
      %c = idr.constant !idr.str "no: "
      %w1 = idr.io.put_str %c, %w
      %w2 = idr.io.put_str %s, %w1
      idr.yield %w2 : !idr.world
    }
    case @True() {
      %c = idr.constant !idr.str "yes: "
      %w1 = idr.io.put_str %c, %w
      %w2 = idr.io.put_str %s, %w1
      idr.yield %w2 : !idr.world
    }
    }
    return %r : !idr.world
  }

  // A value with an effect (a guard, which may crash) stays before the match.
  idr.func @may_crash(%n: i64, %x: i64, %y: i64) -> i64 {
    %y1 = idr.check.nonzero %y, "division by zero" : i64
    %q = idr.divs %x, %y1 : i64
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %q : i64
    }
    default(%d: i64) {
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
