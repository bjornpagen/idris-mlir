// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns=@proving:99,no-guards=@proving,crash-sites=@failing:2,crash-sites=@again:1 -o /dev/null
// RUN: sed 's/idr.call @folded(/idr.call @at_run_time(/' %s > %t.run.mlir
// RUN: %differential %t.run.mlir %s
// RUN: sed 's/%i = arith.constant 5 : i64/%i = arith.constant 4 : i64/' %s > %t.wrong.mlir
// RUN: not %differential %t.run.mlir %t.wrong.mlir 2>&1 | FileCheck %s --check-prefix=WRONG
// The guard of an index folds to the index where both it and the length
// are constants and the index is at least 0 and below the length; then the
// character at it folds too. An index at the length, or below 0, keeps its
// guard, to crash where it runs. A guard of what an identical guard, of
// the same length, already checked folds too.
//
// Each guard's decision is the one the program makes at run time, on every
// row of the table: each row folds in its own region (@folded), where a
// guard that the index is in bounds folds away and the others stay, and is
// checked at run time on the row the byte read chose (@at_run_time, which
// the sed makes the program's). On the byte of each row, and on the empty
// input for the last, the two print the same, the row's operands and then
// its results, or both crash before printing; each operand is printed as
// well as used, so that no guard on it is its one consumer, which case-of-
// case would move into the rows. The rows: 0, the last index and the
// length of strings of one and three characters, of one with a character
// of two bytes and of one of a character of four (an index counts
// characters, not bytes), -1, the empty string, and the most negative and
// most positive Int. A wrong decision is found on its row: the sed makes
// row 7's index 4, where the run reads past the string at 5.
// WRONG: differential: {{.*}}run.mlir and {{.*}}wrong.mlir differ on '\0007'
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
idr.program @"fold-in-bounds" root(@Prog.main) stage(first) types #idr.types<> {
  idr.func @proving() -> i32 {
    %abc = idr.constant !idr.str "abc"
    %two = arith.constant 2 : i64
    %n = idr.str.length %abc
    %g = idr.check.in_bounds %two, %abc, "string index out of range" : !idr.str
    %c = idr.str.index %abc, %g
    return %c : i32
  }

  idr.func @failing() -> (i32, i32) {
    %abc = idr.constant !idr.str "abc"
    %three = arith.constant 3 : i64
    %below = arith.constant -1 : i64
    %n = idr.str.length %abc
    %g = idr.check.in_bounds %three, %abc, "string index out of range" : !idr.str
    %c = idr.str.index %abc, %g
    %h = idr.check.in_bounds %below, %abc, "string index out of range" : !idr.str
    %d = idr.str.index %abc, %h
    return %c, %d : i32, i32
  }

  idr.func @again(%s: !idr.str, %i: i64) -> (i32, i32) {
    %n = idr.str.length %s
    %g = idr.check.in_bounds %i, %s, "string index out of range" : !idr.str
    %c = idr.str.index %s, %g
    %h = idr.check.in_bounds %g, %s, "string index out of range" : !idr.str
    %d = idr.str.index %s, %h
    return %c, %d : i32, i32
  }
  // The operands of each row, the last the default one: the row the byte
  // chose, known only at run time.
  idr.func @rows(%row: i64) -> (!idr.str, i64) {
    %r:2 = idr.match_lit %row : i64 -> (!idr.str, i64) {
    case 0 {
      %s = idr.constant !idr.str "abc"
      %i = arith.constant 0 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 1 {
      %s = idr.constant !idr.str "abc"
      %i = arith.constant 2 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 2 {
      %s = idr.constant !idr.str "abc"
      %i = arith.constant 3 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 3 {
      %s = idr.constant !idr.str "abc"
      %i = arith.constant -1 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 4 {
      %s = idr.constant !idr.str ""
      %i = arith.constant 0 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 5 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant 1 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 6 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant 4 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 7 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant 5 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 8 {
      %s = idr.constant !idr.str "a"
      %i = arith.constant 0 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 9 {
      %s = idr.constant !idr.str "a"
      %i = arith.constant 1 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 10 {
      %s = idr.constant !idr.str "abc"
      %i = arith.constant -9223372036854775808 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 11 {
      %s = idr.constant !idr.str "abc"
      %i = arith.constant 9223372036854775807 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 12 {
      %s = idr.constant !idr.str "\F0\9F\98\80"
      %i = arith.constant 0 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    default(%other: i64) {
      %s = idr.constant !idr.str "xyz"
      %i = arith.constant 1 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    }
    return %r#0, %r#1 : !idr.str, i64
  }
  // Each row's results, computed at run time from the row @rows chose.
  idr.func @at_run_time(%row: i64) -> (!idr.str, i64, i32) {
    %s, %i = idr.call @rows(%row) : (i64) -> (!idr.str, i64)
    %g = idr.check.in_bounds %i, %s, "string index out of range" : !idr.str
    %c = idr.str.index %s, %g
    return %s, %i, %c : !idr.str, i64, i32
  }
  // Each row's results on its constants, which the folders compute.
  idr.func @folded(%row: i64) -> (!idr.str, i64, i32) {
    %r:3 = idr.match_lit %row : i64 -> (!idr.str, i64, i32) {
    case 0 {
      %s = idr.constant !idr.str "abc"
      %i = arith.constant 0 : i64
      %g = idr.check.in_bounds %i, %s, "string index out of range" : !idr.str
      %c = idr.str.index %s, %g
      idr.yield %s, %i, %c : !idr.str, i64, i32
    }
    case 1 {
      %s = idr.constant !idr.str "abc"
      %i = arith.constant 2 : i64
      %g = idr.check.in_bounds %i, %s, "string index out of range" : !idr.str
      %c = idr.str.index %s, %g
      idr.yield %s, %i, %c : !idr.str, i64, i32
    }
    case 2 {
      %s = idr.constant !idr.str "abc"
      %i = arith.constant 3 : i64
      %g = idr.check.in_bounds %i, %s, "string index out of range" : !idr.str
      %c = idr.str.index %s, %g
      idr.yield %s, %i, %c : !idr.str, i64, i32
    }
    case 3 {
      %s = idr.constant !idr.str "abc"
      %i = arith.constant -1 : i64
      %g = idr.check.in_bounds %i, %s, "string index out of range" : !idr.str
      %c = idr.str.index %s, %g
      idr.yield %s, %i, %c : !idr.str, i64, i32
    }
    case 4 {
      %s = idr.constant !idr.str ""
      %i = arith.constant 0 : i64
      %g = idr.check.in_bounds %i, %s, "string index out of range" : !idr.str
      %c = idr.str.index %s, %g
      idr.yield %s, %i, %c : !idr.str, i64, i32
    }
    case 5 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant 1 : i64
      %g = idr.check.in_bounds %i, %s, "string index out of range" : !idr.str
      %c = idr.str.index %s, %g
      idr.yield %s, %i, %c : !idr.str, i64, i32
    }
    case 6 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant 4 : i64
      %g = idr.check.in_bounds %i, %s, "string index out of range" : !idr.str
      %c = idr.str.index %s, %g
      idr.yield %s, %i, %c : !idr.str, i64, i32
    }
    case 7 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant 5 : i64
      %g = idr.check.in_bounds %i, %s, "string index out of range" : !idr.str
      %c = idr.str.index %s, %g
      idr.yield %s, %i, %c : !idr.str, i64, i32
    }
    case 8 {
      %s = idr.constant !idr.str "a"
      %i = arith.constant 0 : i64
      %g = idr.check.in_bounds %i, %s, "string index out of range" : !idr.str
      %c = idr.str.index %s, %g
      idr.yield %s, %i, %c : !idr.str, i64, i32
    }
    case 9 {
      %s = idr.constant !idr.str "a"
      %i = arith.constant 1 : i64
      %g = idr.check.in_bounds %i, %s, "string index out of range" : !idr.str
      %c = idr.str.index %s, %g
      idr.yield %s, %i, %c : !idr.str, i64, i32
    }
    case 10 {
      %s = idr.constant !idr.str "abc"
      %i = arith.constant -9223372036854775808 : i64
      %g = idr.check.in_bounds %i, %s, "string index out of range" : !idr.str
      %c = idr.str.index %s, %g
      idr.yield %s, %i, %c : !idr.str, i64, i32
    }
    case 11 {
      %s = idr.constant !idr.str "abc"
      %i = arith.constant 9223372036854775807 : i64
      %g = idr.check.in_bounds %i, %s, "string index out of range" : !idr.str
      %c = idr.str.index %s, %g
      idr.yield %s, %i, %c : !idr.str, i64, i32
    }
    case 12 {
      %s = idr.constant !idr.str "\F0\9F\98\80"
      %i = arith.constant 0 : i64
      %g = idr.check.in_bounds %i, %s, "string index out of range" : !idr.str
      %c = idr.str.index %s, %g
      idr.yield %s, %i, %c : !idr.str, i64, i32
    }
    default(%other: i64) {
      %s = idr.constant !idr.str "xyz"
      %i = arith.constant 1 : i64
      %g = idr.check.in_bounds %i, %s, "string index out of range" : !idr.str
      %c = idr.str.index %s, %g
      idr.yield %s, %i, %c : !idr.str, i64, i32
    }
    }
    return %r#0, %r#1, %r#2 : !idr.str, i64, i32
  }
  // The program: the results of the row the byte read chooses, folded,
  // or, in the run form, computed at run time.
  idr.func @Prog.main(%w0: !idr.world) -> !idr.world {
    %byte, %w1 = idr.io.get_byte %w0
    %row = arith.extui %byte : i32 to i64
    %s, %i, %c = idr.call @folded(%row) : (i64) -> (!idr.str, i64, i32)
    %space = arith.constant 32 : i32
    %newline = arith.constant 10 : i32
    %w2 = idr.io.put_str %s, %w1
    %w3 = idr.io.put_char %space, %w2
    %w4 = idr.io.put_sint %i, %w3 : i64
    %w5 = idr.io.put_char %space, %w4
    %w6 = idr.io.put_sint %c, %w5 : i32
    %w7 = idr.io.put_char %newline, %w6
    return %w7 : !idr.world
  }
}
