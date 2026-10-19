// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns=@proving:4/4,no-guards=@proving,crash-sites=@failing:3,crash-sites=@again:1 -o /dev/null
// RUN: sed 's/idr.call @folded(/idr.call @at_run_time(/' %s > %t.run.mlir
// RUN: %differential %t.run.mlir %s
// RUN: sed 's/%n = arith.constant 9 : i64/%n = arith.constant 8 : i64/' %s > %t.wrong.mlir
// RUN: not %differential %t.run.mlir %t.wrong.mlir 2>&1 | FileCheck %s --check-prefix=WRONG
// The guard of a byte range folds to its offset where the offset, the
// count and the size are constants and the range lies in the size: both at
// least 0, and their sum, without overflow, at most the size. A range past
// the size, a negative offset, and one whose end overflows keep their
// guard, to crash where it runs. A guard of what an identical guard, of
// the same count and size, already checked folds too.
//
// Each guard's decision is the one the program makes at run time, on every
// row of the table: each row folds in its own region (@folded), where a
// guard of a range in the size folds away and the others stay, and is
// checked at run time on the row the byte read chose (@at_run_time, which
// the sed makes the program's). On the byte of each row, and on the empty
// input for the last, the two print the same, the row's operands and then
// its results, or both crash before printing; each operand is printed as
// well as used, so that no guard on it is its one consumer, which case-of-
// case would move into the rows. The rows: ranges that end at the size and
// one past it, empty ones at the start and at the end and one past the
// end, a negative offset and count, the most negative offset, and ends
// that overflow. A wrong decision is found on its row: the sed makes row
// 12's count 8, where the run checks 9.
// WRONG: differential: {{.*}}run.mlir and {{.*}}wrong.mlir differ on '\0014'
// STDIN: \0000
// STDIN: \0001
// STDIN: \0002
// STDIN: \0003
// STDIN: \0004
// STDIN: \0005
// STDIN: \0006
// STDIN: \0007
// STDIN: \0010
// STDIN: \0011
// STDIN: \0012
// STDIN: \0013
// STDIN: \0014
// STDIN:
idr.program @"fold-range" root(@Prog.main) stage(first) {
  idr.func @proving() -> (i64, i64) {
    %four = arith.constant 4 : i64
    %eight = arith.constant 8 : i64
    %zero = arith.constant 0 : i64
    %g = idr.check.range %four, %four, %eight, "a byte range outside the buffer"
    %h = idr.check.range %four, %zero, %four, "a byte range outside the buffer"
    return %g, %h : i64, i64
  }

  idr.func @failing() -> (i64, i64, i64) {
    %five = arith.constant 5 : i64
    %four = arith.constant 4 : i64
    %eight = arith.constant 8 : i64
    %g = idr.check.range %five, %four, %eight, "a byte range outside the buffer"
    %below = arith.constant -1 : i64
    %one = arith.constant 1 : i64
    %h = idr.check.range %below, %one, %eight, "a byte range outside the buffer"
    %largest = arith.constant 9223372036854775807 : i64
    %k = idr.check.range %largest, %one, %largest, "a byte range outside the buffer"
    return %g, %h, %k : i64, i64, i64
  }

  idr.func @again(%o: i64, %n: i64, %s: i64) -> (i64, i64) {
    %g = idr.check.range %o, %n, %s, "a byte range outside the buffer"
    %h = idr.check.range %g, %n, %s, "a byte range outside the buffer"
    return %g, %h : i64, i64
  }
  // The operands of each row, the last the default one: the row the byte
  // chose, known only at run time.
  idr.func @rows(%row: i64) -> (i64, i64, i64) {
    %r:3 = idr.match_lit %row : i64 -> (i64, i64, i64) {
    case 0 {
      %o = arith.constant 4 : i64
      %n = arith.constant 4 : i64
      %s = arith.constant 8 : i64
      idr.yield %o, %n, %s : i64, i64, i64
    }
    case 1 {
      %o = arith.constant 4 : i64
      %n = arith.constant 0 : i64
      %s = arith.constant 4 : i64
      idr.yield %o, %n, %s : i64, i64, i64
    }
    case 2 {
      %o = arith.constant 5 : i64
      %n = arith.constant 4 : i64
      %s = arith.constant 8 : i64
      idr.yield %o, %n, %s : i64, i64, i64
    }
    case 3 {
      %o = arith.constant -1 : i64
      %n = arith.constant 1 : i64
      %s = arith.constant 8 : i64
      idr.yield %o, %n, %s : i64, i64, i64
    }
    case 4 {
      %o = arith.constant 9223372036854775807 : i64
      %n = arith.constant 1 : i64
      %s = arith.constant 9223372036854775807 : i64
      idr.yield %o, %n, %s : i64, i64, i64
    }
    case 5 {
      %o = arith.constant 0 : i64
      %n = arith.constant 0 : i64
      %s = arith.constant 0 : i64
      idr.yield %o, %n, %s : i64, i64, i64
    }
    case 6 {
      %o = arith.constant 0 : i64
      %n = arith.constant 8 : i64
      %s = arith.constant 8 : i64
      idr.yield %o, %n, %s : i64, i64, i64
    }
    case 7 {
      %o = arith.constant 8 : i64
      %n = arith.constant 0 : i64
      %s = arith.constant 8 : i64
      idr.yield %o, %n, %s : i64, i64, i64
    }
    case 8 {
      %o = arith.constant 8 : i64
      %n = arith.constant 1 : i64
      %s = arith.constant 8 : i64
      idr.yield %o, %n, %s : i64, i64, i64
    }
    case 9 {
      %o = arith.constant 0 : i64
      %n = arith.constant -1 : i64
      %s = arith.constant 8 : i64
      idr.yield %o, %n, %s : i64, i64, i64
    }
    case 10 {
      %o = arith.constant 1 : i64
      %n = arith.constant 9223372036854775807 : i64
      %s = arith.constant 9223372036854775807 : i64
      idr.yield %o, %n, %s : i64, i64, i64
    }
    case 11 {
      %o = arith.constant -9223372036854775808 : i64
      %n = arith.constant 0 : i64
      %s = arith.constant 8 : i64
      idr.yield %o, %n, %s : i64, i64, i64
    }
    case 12 {
      %o = arith.constant 0 : i64
      %n = arith.constant 9 : i64
      %s = arith.constant 8 : i64
      idr.yield %o, %n, %s : i64, i64, i64
    }
    default(%other: i64) {
      %o = arith.constant 3 : i64
      %n = arith.constant 2 : i64
      %s = arith.constant 6 : i64
      idr.yield %o, %n, %s : i64, i64, i64
    }
    }
    return %r#0, %r#1, %r#2 : i64, i64, i64
  }
  // Each row's results, computed at run time from the row @rows chose.
  idr.func @at_run_time(%row: i64) -> (i64, i64, i64, i64) {
    %o, %n, %s = idr.call @rows(%row) : (i64) -> (i64, i64, i64)
    %g = idr.check.range %o, %n, %s, "a byte range outside the buffer"
    return %o, %n, %s, %g : i64, i64, i64, i64
  }
  // Each row's results on its constants, which the folders compute.
  idr.func @folded(%row: i64) -> (i64, i64, i64, i64) {
    %r:4 = idr.match_lit %row : i64 -> (i64, i64, i64, i64) {
    case 0 {
      %o = arith.constant 4 : i64
      %n = arith.constant 4 : i64
      %s = arith.constant 8 : i64
      %g = idr.check.range %o, %n, %s, "a byte range outside the buffer"
      idr.yield %o, %n, %s, %g : i64, i64, i64, i64
    }
    case 1 {
      %o = arith.constant 4 : i64
      %n = arith.constant 0 : i64
      %s = arith.constant 4 : i64
      %g = idr.check.range %o, %n, %s, "a byte range outside the buffer"
      idr.yield %o, %n, %s, %g : i64, i64, i64, i64
    }
    case 2 {
      %o = arith.constant 5 : i64
      %n = arith.constant 4 : i64
      %s = arith.constant 8 : i64
      %g = idr.check.range %o, %n, %s, "a byte range outside the buffer"
      idr.yield %o, %n, %s, %g : i64, i64, i64, i64
    }
    case 3 {
      %o = arith.constant -1 : i64
      %n = arith.constant 1 : i64
      %s = arith.constant 8 : i64
      %g = idr.check.range %o, %n, %s, "a byte range outside the buffer"
      idr.yield %o, %n, %s, %g : i64, i64, i64, i64
    }
    case 4 {
      %o = arith.constant 9223372036854775807 : i64
      %n = arith.constant 1 : i64
      %s = arith.constant 9223372036854775807 : i64
      %g = idr.check.range %o, %n, %s, "a byte range outside the buffer"
      idr.yield %o, %n, %s, %g : i64, i64, i64, i64
    }
    case 5 {
      %o = arith.constant 0 : i64
      %n = arith.constant 0 : i64
      %s = arith.constant 0 : i64
      %g = idr.check.range %o, %n, %s, "a byte range outside the buffer"
      idr.yield %o, %n, %s, %g : i64, i64, i64, i64
    }
    case 6 {
      %o = arith.constant 0 : i64
      %n = arith.constant 8 : i64
      %s = arith.constant 8 : i64
      %g = idr.check.range %o, %n, %s, "a byte range outside the buffer"
      idr.yield %o, %n, %s, %g : i64, i64, i64, i64
    }
    case 7 {
      %o = arith.constant 8 : i64
      %n = arith.constant 0 : i64
      %s = arith.constant 8 : i64
      %g = idr.check.range %o, %n, %s, "a byte range outside the buffer"
      idr.yield %o, %n, %s, %g : i64, i64, i64, i64
    }
    case 8 {
      %o = arith.constant 8 : i64
      %n = arith.constant 1 : i64
      %s = arith.constant 8 : i64
      %g = idr.check.range %o, %n, %s, "a byte range outside the buffer"
      idr.yield %o, %n, %s, %g : i64, i64, i64, i64
    }
    case 9 {
      %o = arith.constant 0 : i64
      %n = arith.constant -1 : i64
      %s = arith.constant 8 : i64
      %g = idr.check.range %o, %n, %s, "a byte range outside the buffer"
      idr.yield %o, %n, %s, %g : i64, i64, i64, i64
    }
    case 10 {
      %o = arith.constant 1 : i64
      %n = arith.constant 9223372036854775807 : i64
      %s = arith.constant 9223372036854775807 : i64
      %g = idr.check.range %o, %n, %s, "a byte range outside the buffer"
      idr.yield %o, %n, %s, %g : i64, i64, i64, i64
    }
    case 11 {
      %o = arith.constant -9223372036854775808 : i64
      %n = arith.constant 0 : i64
      %s = arith.constant 8 : i64
      %g = idr.check.range %o, %n, %s, "a byte range outside the buffer"
      idr.yield %o, %n, %s, %g : i64, i64, i64, i64
    }
    case 12 {
      %o = arith.constant 0 : i64
      %n = arith.constant 9 : i64
      %s = arith.constant 8 : i64
      %g = idr.check.range %o, %n, %s, "a byte range outside the buffer"
      idr.yield %o, %n, %s, %g : i64, i64, i64, i64
    }
    default(%other: i64) {
      %o = arith.constant 3 : i64
      %n = arith.constant 2 : i64
      %s = arith.constant 6 : i64
      %g = idr.check.range %o, %n, %s, "a byte range outside the buffer"
      idr.yield %o, %n, %s, %g : i64, i64, i64, i64
    }
    }
    return %r#0, %r#1, %r#2, %r#3 : i64, i64, i64, i64
  }
  // The program: the results of the row the byte read chooses, folded,
  // or, in the run form, computed at run time.
  idr.func @Prog.main(%w0: !idr.world) -> !idr.world {
    %byte, %w1 = idr.io.get_byte %w0
    %row = arith.extui %byte : i32 to i64
    %o, %n, %s, %g = idr.call @folded(%row) : (i64) -> (i64, i64, i64, i64)
    %space = arith.constant 32 : i32
    %newline = arith.constant 10 : i32
    %w2 = idr.io.put_sint %o, %w1 : i64
    %w3 = idr.io.put_char %space, %w2
    %w4 = idr.io.put_sint %n, %w3 : i64
    %w5 = idr.io.put_char %space, %w4
    %w6 = idr.io.put_sint %s, %w5 : i64
    %w7 = idr.io.put_char %space, %w6
    %w8 = idr.io.put_sint %g, %w7 : i64
    %w9 = idr.io.put_char %newline, %w8
    return %w9 : !idr.world
  }
}
