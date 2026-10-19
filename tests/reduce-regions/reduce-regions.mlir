// RUN: printf '#!/bin/sh\nfor op in "match " match_lit; do\n  if ! grep -q "$op" "$1"; then exit 0; fi\ndone\nexit 1\n' > %t.test
// RUN: chmod +x %t.test
// RUN: idris-mlir-reduce %s --reduction-tree="traversal-mode=0 test=%t.test" -o %t.reduced
// RUN: idris-mlir-opt %t.reduced -o /dev/null
// RUN: grep -q 'match ' %t.reduced
// RUN: grep -q match_lit %t.reduced
// idris-mlir-reduce erases ops and drops their uses, so a candidate that
// erases an op whose value an idr.yield or a return uses holds a null
// operand, which MLIR refuses before any region's own check reads it. The
// idr dialect's reduction pattern simplifies such an op instead: what it
// computes becomes ub.poison, which takes no operand. The test keeps every
// op with a region (a match on a constructor and one on a literal), so the
// reducer works inside each of them; it looks for each as idr.func prints
// it, without the prefix where the op name has one dot. The reduction
// ends, and its module verifies and is still what the test looks for; how
// far the search goes is the reducer's business.
!T = !idr.data<"T", plain [@A(i64)]>
idr.program @regions root(@root) stage(first) {
  idr.func @regions(%v: !T, %n: i64) -> (i64, i64) {
    %m = idr.match %v : !T -> (i64) {
    case @A(%x: i64) {
      %y = arith.addi %x, %x : i64
      idr.yield %y : i64
    }
    }
    %l = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %one = arith.constant 1 : i64
      idr.yield %one : i64
    }
    default(%d: i64) {
      %z = arith.subi %n, %n : i64
      idr.yield %z : i64
    }
    }
    return %m, %l : i64, i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
