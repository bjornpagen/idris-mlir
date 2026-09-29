// RUN: idris-mlir-cc %s -o %t.o --no-eval
// RUN: %cc %t.o -o %t
// RUN: %status 20 %t
// A self tail call of a function that is not total becomes a loop that
// keeps idr.may_loop, the mark of a loop that may not end, down to the
// object code.
module attributes {idr.program} {
  func.func private @count(%n: i64, %acc: i64) -> i64 {
    %zero = arith.constant 0 : i64
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default {
      %one = arith.constant 1 : i64
      %two = arith.constant 2 : i64
      %m = arith.subi %n, %one : i64
      %a = arith.addi %acc, %two : i64
      %s = func.call @count(%m, %a) : (i64, i64) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  func.func @Prog.main() -> i64 {
    %ten = arith.constant 10 : i64
    %zero = arith.constant 0 : i64
    %r = func.call @count(%ten, %zero) : (i64, i64) -> i64
    return %r : i64
  }
}
