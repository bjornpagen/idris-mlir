// RUN: idris-mlir -c %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: %status 20 %t
// NEEDS-ACCEPTANCE: that each match's default region, which binds the scrutinee now, parses and lowers, and that the program's output is as before.
// A self tail call of a function that is not total becomes a loop that
// keeps idr.may_loop, the mark of a loop that may not end, down to the
// object code.
idr.program @"partial-loop" root(@Prog.main) stage(higher) {
  idr.func @count(%n: i64, %acc: i64) -> i64 {
    %zero = arith.constant 0 : i64
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %two = arith.constant 2 : i64
      %m = arith.subi %n, %one : i64
      %a = arith.addi %acc, %two : i64
      %s = idr.call @count(%m, %a) : (i64, i64) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main() -> i64 {
    %ten = arith.constant 10 : i64
    %zero = arith.constant 0 : i64
    %r = idr.call @count(%ten, %zero) : (i64, i64) -> i64
    return %r : i64
  }
}
