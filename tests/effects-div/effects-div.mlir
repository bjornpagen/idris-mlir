// RUN: idris-mlir-opt %s --test-idr-facts -verify-diagnostics=only-expected -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize --cse --idr-expect=holds=computes-nothing=@dead,crash-sites=@dead:1,returns-argument=@dead:0 -o /dev/null
// RUN: sed -n 's|^// REFERENCE: ||p' %s > %t.reference.mlir
// RUN: %differential %s %t.reference.mlir
// RUN: idris-mlir-opt %s --canonicalize --cse --control-flow-sink --loop-invariant-code-motion -o %t.moved.mlir
// RUN: %differential %t.moved.mlir %t.reference.mlir
// RUN: sed 's/%first = arith.andi %bset, %ydead : i1/%first = arith.ori %ydead, %ydead : i1/' %t.reference.mlir > %t.wrong.mlir
// RUN: not %differential %s %t.wrong.mlir 2>&1 | FileCheck %s
// A division is its divisor's guard, which may crash, and the division
// itself, which only computes. A dead division goes, and its guard stays
// unless the divisor is a nonzero constant. The guard is not speculated:
// it may be delayed but not moved, so it stays inside the branch or the
// loop that runs it; and the division never runs before it, since it
// takes the guard's result. A division by a nonzero constant needs no
// guard, and may move anywhere, out of a loop that does not change it.
//
// So a guard runs exactly where the program runs it: the program reads a
// byte whose low three bits choose the branch, the divisor (0 or 1) and
// whether the loop runs once or not at all; it crashes when the branch
// taken or the loop that runs divides by 0, and otherwise writes 7 and the
// number of times the loop ran. The REFERENCE lines write exactly that,
// with no division; the program means the same as written, and after the
// folds, CSE, control-flow sinking and loop-invariant code motion, on every
// choice of the three bits and the empty input. A reference that also
// crashes where the branch not taken would divide by 0, as a guard moved
// out of its branch would, is told apart on the byte 0.
// CHECK: differential: effects-div.mlir and {{.*}}wrong.mlir differ on '\0000'
// STDIN: \0000
// STDIN: \0001
// STDIN: \0002
// STDIN: \0003
// STDIN: \0004
// STDIN: \0005
// STDIN: \0006
// STDIN: \0007
// STDIN:

idr.program @div root(@root) stage(first) types #idr.types<> {
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
  // The program: the branch, the divisor and the loop's count from the
  // byte's low bits.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %one = arith.constant 1 : i32
    %yb = arith.andi %c, %one : i32
    %c1 = arith.shrui %c, %one : i32
    %bb = arith.andi %c1, %one : i32
    %c2 = arith.shrui %c1, %one : i32
    %nb = arith.andi %c2, %one : i32
    %zero = arith.constant 0 : i32
    %b = arith.cmpi ne, %bb, %zero : i32
    %y = arith.extui %yb : i32 to i64
    %n64 = arith.extui %nb : i32 to i64
    %n = arith.index_cast %n64 : i64 to index
    %seven = arith.constant 7 : i64
    %g = idr.call @guarded(%b, %seven, %y) : (i1, i64, i64) -> i64
    %w2 = idr.io.put_sint %g, %w1 : i64
    %i = idr.call @invariant(%seven, %y, %n) : (i64, i64, index) -> i64
    %space = arith.constant 32 : i32
    %w3 = idr.io.put_char %space, %w2
    %w4 = idr.io.put_sint %i, %w3 : i64
    return %w4 : !idr.world
  }
}
// REFERENCE: idr.program @reference root(@root) stage(first) types #idr.types<> {
// REFERENCE:   idr.func @root(%w: !idr.world) -> !idr.world {
// REFERENCE:     %c, %w1 = idr.io.get_byte %w
// REFERENCE:     %one = arith.constant 1 : i32
// REFERENCE:     %y = arith.andi %c, %one : i32
// REFERENCE:     %c1 = arith.shrui %c, %one : i32
// REFERENCE:     %b = arith.andi %c1, %one : i32
// REFERENCE:     %c2 = arith.shrui %c1, %one : i32
// REFERENCE:     %n = arith.andi %c2, %one : i32
// REFERENCE:     %zero = arith.constant 0 : i32
// REFERENCE:     %ydead = arith.cmpi eq, %y, %zero : i32
// REFERENCE:     %bset = arith.cmpi ne, %b, %zero : i32
// REFERENCE:     %nset = arith.cmpi ne, %n, %zero : i32
// REFERENCE:     %first = arith.andi %bset, %ydead : i1
// REFERENCE:     %second = arith.andi %nset, %ydead : i1
// REFERENCE:     %w2 = idr.match_lit %first : i1 -> (!idr.world) {
// REFERENCE:     case true {
// REFERENCE:       idr.crash "division by zero"
// REFERENCE:       ub.unreachable
// REFERENCE:     }
// REFERENCE:     default(%d: i1) {
// REFERENCE:       %seven = arith.constant 7 : i64
// REFERENCE:       %v = idr.io.put_sint %seven, %w1 : i64
// REFERENCE:       idr.yield %v : !idr.world
// REFERENCE:     }
// REFERENCE:     }
// REFERENCE:     %w3 = idr.match_lit %second : i1 -> (!idr.world) {
// REFERENCE:     case true {
// REFERENCE:       idr.crash "division by zero"
// REFERENCE:       ub.unreachable
// REFERENCE:     }
// REFERENCE:     default(%d: i1) {
// REFERENCE:       %space = arith.constant 32 : i32
// REFERENCE:       %v = idr.io.put_char %space, %w2
// REFERENCE:       %runs = arith.extui %n : i32 to i64
// REFERENCE:       %v1 = idr.io.put_sint %runs, %v : i64
// REFERENCE:       idr.yield %v1 : !idr.world
// REFERENCE:     }
// REFERENCE:     }
// REFERENCE:     return %w3 : !idr.world
// REFERENCE:   }
// REFERENCE: }
