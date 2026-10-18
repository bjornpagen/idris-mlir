// NEEDS-ACCEPTANCE: that this module parses with the match's default binding its scrutinee, that loops counts @sum's one loop and @line's none, and that the -verify-diagnostics run passes: loops fails at @sum and @line for the counts they do not have, and straight-line at the match of @choose.
// RUN: idris-mlir-opt %s --idr-expect=holds=loops=@sum,loops=@sum:1,loops=@line:0,straight-line=@line -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=loops=@sum:2,loops=@line,straight-line=@choose -verify-diagnostics -o /dev/null
// The shape of a function's control: @sum has one loop, @line runs one
// path and has no loop, and @choose chooses between the regions of a
// match.
idr.program @paths root(@root) stage(first) {
  // expected-error @below {{expected loops: @sum has 1 loops, not 2}}
  idr.func @sum(%n: index) -> i64 {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %z = arith.constant 0 : i64
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %z) -> (i64) {
      %x = arith.index_cast %i : index to i64
      %b = arith.addi %a, %x : i64
      scf.yield %b : i64
    }
    return %r : i64
  }
  // expected-error @below {{expected loops: @line has 0 loops}}
  idr.func @line(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @choose(%n: i64) -> i64 {
    // expected-error @below {{expected straight-line: idr.match_lit branches in @choose}}
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %one = arith.constant 1 : i64
      idr.yield %one : i64
    }
    default(%d: i64) {
      idr.yield %d : i64
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
