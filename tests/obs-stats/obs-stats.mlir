// RUN: idris-mlir -c %s -o %t.o --stats 2> %t.stats
// RUN: FileCheck %s < %t.stats
// RUN: idris-mlir -c %s -o %t.quiet.o 2> %t.quiet
// RUN: FileCheck %s --check-prefix=QUIET --allow-empty < %t.quiet
// RUN: cmp %t.o %t.quiet.o
// --stats prints the statistics report of the driver's pass manager;
// without --stats, nothing. Which statistics a pass keeps, and how MLIR
// words them, is the pass's own business and no part of this check. What
// is reported changes nothing compiled: the object is the same byte for
// byte with --stats and without.
// CHECK: Pass statistics report
// QUIET-NOT: statistics
idr.program @stats root(@Prog.main) stage(higher) {
  idr.func @fact(%n: i64) -> i64 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %one = arith.constant 1 : i64
      idr.yield %one : i64
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %f = idr.call @fact(%m) : (i64) -> i64
      %p = arith.muli %n, %f : i64
      idr.yield %p : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %ten = arith.constant 10 : i64
    %f = idr.call @fact(%ten) : (i64) -> i64
    %w1 = idr.io.put_sint %f, %w : i64
    %nl = arith.constant 10 : i32
    %w2 = idr.io.put_char %nl, %w1
    return %w2 : !idr.world
  }
}
