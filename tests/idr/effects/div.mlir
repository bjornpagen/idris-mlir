// NEEDS-ACCEPTANCE: each op's answers, reported by test-idr-facts, are those its marks state.
// RUN: idris-mlir-opt %s --test-idr-facts -verify-diagnostics=only-expected -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize --cse --idr-expect=holds=computes-nothing=@dead,crash-sites=@dead:1,returns-argument=@dead:0 -o /dev/null
// A division is its divisor's guard, which may crash, and the division
// itself, which only computes. A dead division goes, and its guard stays
// unless the divisor is a nonzero constant. The guard is not speculated:
// it may be delayed but not moved, so it stays inside the branch or the
// loop that runs it; and the division never runs before it, since it
// takes the guard's result. A division by a nonzero constant needs no
// guard, and may move anywhere, out of a loop that does not change it.

idr.program @div root(@root) stage(first) {
  idr.func @dead(%x: i64, %y: i64) -> i64 {
    %c3 = arith.constant 3 : i64
    %y1 = idr.check.nonzero %y, "division by zero" : i64
    %q = idr.divs %x, %y1 : i64
    %c31 = idr.check.nonzero %c3, "division by zero" : i64
    %s = idr.divs %x, %c31 : i64
    %c32 = idr.check.nonzero %c3, "division by zero" : i64
    %r = idr.modu %x, %c32 : i64
    return %x : i64
  }

  idr.func @guarded(%b: i1, %x: i64, %y: i64) -> i64 {
    %r = scf.if %b -> i64 {
      // expected-remark @below {{facts: [delay]}}
      %y1 = idr.check.nonzero %y, "division by zero" : i64
      // expected-remark @below {{facts: [move delay merge]}}
      %q = idr.divs %x, %y1 : i64
      scf.yield %q : i64
    } else {
      scf.yield %x : i64
    }
    return %r : i64
  }

  // A loop-invariant division leaves the loop only when it cannot crash.
  idr.func @invariant(%x: i64, %y: i64, %n: index) -> i64 {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c7 = arith.constant 7 : i64
    %zero = arith.constant 0 : i64
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%acc = %zero) -> (i64) {
      // expected-remark @below {{facts: [move delay merge]}}
      %q = idr.divs %x, %c7 : i64
      // expected-remark @below {{facts: [delay]}}
      %y1 = idr.check.nonzero %y, "division by zero" : i64
      // expected-remark @below {{facts: [move delay merge]}}
      %m = idr.mods %x, %y1 : i64
      %s = arith.addi %q, %m : i64
      %t = arith.addi %acc, %s : i64
      scf.yield %t : i64
    }
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
