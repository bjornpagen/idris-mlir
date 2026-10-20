// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=no-guards=@proving,crash-sites=@failing:1,crash-sites=@again:1 -o /dev/null
// RUN: sed 's/idr.call @folded(/idr.call @at_run_time(/' %s > %t.run.mlir
// RUN: %differential %t.run.mlir %s
// RUN: sed 's/%v = idr.constant !idr.str " "/%v = idr.constant !idr.str "-"/' %s > %t.wrong.mlir
// RUN: not %differential %t.run.mlir %t.wrong.mlir 2>&1 | FileCheck %s --check-prefix=WRONG
// The guard of a string's head or tail folds to the string where the
// string shows it has a character: a constant other than "", or one built
// with a character or a number in it. The head of a string built with a
// character is then that character. On "" the guard stays, to crash where
// it runs. A guard of what an identical guard already checked folds too.
//
// Each guard's decision is the one the program makes at run time, on every
// row of the table: each row folds in its own region (@folded), where a
// guard of a string with a character folds away and the others stay, and
// is checked at run time on the row the byte read chose (@at_run_time,
// which the sed makes the program's). On the byte of each row, and on the
// empty input for the last, the two print the same, the row's operands and
// then its results, or both crash before printing; each operand is printed
// as well as used, so that no guard on it is its one consumer, which case-
// of-case would move into the rows. The rows: strings of one character, of
// one byte, two and four, of more than one, whose tail starts inside them,
// and the empty string. A wrong decision is found on its row: the sed
// makes row 5's space a dash, where the run reads a space.
// WRONG: differential: {{.*}}run.mlir and {{.*}}wrong.mlir differ on '\0005'
// STDIN: \0000
// STDIN: \0001
// STDIN: \0002
// STDIN: \0003
// STDIN: \0004
// STDIN: \0005
// STDIN: \0006
// STDIN:
idr.program @"fold-nonempty" root(@Prog.main) stage(first) types #idr.types<> {
  idr.func @proving(%c: i32, %s: !idr.str, %x: i64) -> (i32, !idr.str, !idr.str, !idr.str) {
    %t = idr.str.cons %c, %s
    %g = idr.check.nonempty %t, "head of an empty string" : !idr.str
    %h = idr.str.head %g
    %abc = idr.constant !idr.str "abc"
    %g1 = idr.check.nonempty %abc, "tail of an empty string" : !idr.str
    %bc = idr.str.tail %g1
    %shown = idr.str.show_sint %x : i64
    %g2 = idr.check.nonempty %shown, "tail of an empty string" : !idr.str
    %rest = idr.str.tail %g2
    %both = idr.str.append %s, %abc
    %g3 = idr.check.nonempty %both, "tail of an empty string" : !idr.str
    %more = idr.str.tail %g3
    return %h, %bc, %rest, %more : i32, !idr.str, !idr.str, !idr.str
  }

  idr.func @failing() -> i32 {
    %empty = idr.constant !idr.str ""
    %g = idr.check.nonempty %empty, "head of an empty string" : !idr.str
    %h = idr.str.head %g
    return %h : i32
  }

  idr.func @again(%s: !idr.str) -> (i32, !idr.str) {
    %g = idr.check.nonempty %s, "head of an empty string" : !idr.str
    %h = idr.str.head %g
    %g1 = idr.check.nonempty %g, "tail of an empty string" : !idr.str
    %t = idr.str.tail %g1
    return %h, %t : i32, !idr.str
  }
  // The operands of each row, the last the default one: the row the byte
  // chose, known only at run time.
  idr.func @rows(%row: i64) -> (!idr.str) {
    %r:1 = idr.match_lit %row : i64 -> (!idr.str) {
    case 0 {
      %v = idr.constant !idr.str "abc"
      idr.yield %v : !idr.str
    }
    case 1 {
      %v = idr.constant !idr.str "a"
      idr.yield %v : !idr.str
    }
    case 2 {
      %v = idr.constant !idr.str ""
      idr.yield %v : !idr.str
    }
    case 3 {
      %v = idr.constant !idr.str "\C3\A9"
      idr.yield %v : !idr.str
    }
    case 4 {
      %v = idr.constant !idr.str "\F0\9F\98\80b"
      idr.yield %v : !idr.str
    }
    case 5 {
      %v = idr.constant !idr.str " "
      idr.yield %v : !idr.str
    }
    case 6 {
      %v = idr.constant !idr.str "b\C3\A9"
      idr.yield %v : !idr.str
    }
    default(%other: i64) {
      %v = idr.constant !idr.str "xy"
      idr.yield %v : !idr.str
    }
    }
    return %r#0 : !idr.str
  }
  // Each row's results, computed at run time from the row @rows chose.
  idr.func @at_run_time(%row: i64) -> (!idr.str, i32, !idr.str) {
    %v = idr.call @rows(%row) : (i64) -> (!idr.str)
    %g = idr.check.nonempty %v, "head of an empty string" : !idr.str
    %h = idr.str.head %g
    %g1 = idr.check.nonempty %v, "tail of an empty string" : !idr.str
    %t = idr.str.tail %g1
    return %v, %h, %t : !idr.str, i32, !idr.str
  }
  // Each row's results on its constants, which the folders compute.
  idr.func @folded(%row: i64) -> (!idr.str, i32, !idr.str) {
    %r:3 = idr.match_lit %row : i64 -> (!idr.str, i32, !idr.str) {
    case 0 {
      %v = idr.constant !idr.str "abc"
      %g = idr.check.nonempty %v, "head of an empty string" : !idr.str
      %h = idr.str.head %g
      %g1 = idr.check.nonempty %v, "tail of an empty string" : !idr.str
      %t = idr.str.tail %g1
      idr.yield %v, %h, %t : !idr.str, i32, !idr.str
    }
    case 1 {
      %v = idr.constant !idr.str "a"
      %g = idr.check.nonempty %v, "head of an empty string" : !idr.str
      %h = idr.str.head %g
      %g1 = idr.check.nonempty %v, "tail of an empty string" : !idr.str
      %t = idr.str.tail %g1
      idr.yield %v, %h, %t : !idr.str, i32, !idr.str
    }
    case 2 {
      %v = idr.constant !idr.str ""
      %g = idr.check.nonempty %v, "head of an empty string" : !idr.str
      %h = idr.str.head %g
      %g1 = idr.check.nonempty %v, "tail of an empty string" : !idr.str
      %t = idr.str.tail %g1
      idr.yield %v, %h, %t : !idr.str, i32, !idr.str
    }
    case 3 {
      %v = idr.constant !idr.str "\C3\A9"
      %g = idr.check.nonempty %v, "head of an empty string" : !idr.str
      %h = idr.str.head %g
      %g1 = idr.check.nonempty %v, "tail of an empty string" : !idr.str
      %t = idr.str.tail %g1
      idr.yield %v, %h, %t : !idr.str, i32, !idr.str
    }
    case 4 {
      %v = idr.constant !idr.str "\F0\9F\98\80b"
      %g = idr.check.nonempty %v, "head of an empty string" : !idr.str
      %h = idr.str.head %g
      %g1 = idr.check.nonempty %v, "tail of an empty string" : !idr.str
      %t = idr.str.tail %g1
      idr.yield %v, %h, %t : !idr.str, i32, !idr.str
    }
    case 5 {
      %v = idr.constant !idr.str " "
      %g = idr.check.nonempty %v, "head of an empty string" : !idr.str
      %h = idr.str.head %g
      %g1 = idr.check.nonempty %v, "tail of an empty string" : !idr.str
      %t = idr.str.tail %g1
      idr.yield %v, %h, %t : !idr.str, i32, !idr.str
    }
    case 6 {
      %v = idr.constant !idr.str "b\C3\A9"
      %g = idr.check.nonempty %v, "head of an empty string" : !idr.str
      %h = idr.str.head %g
      %g1 = idr.check.nonempty %v, "tail of an empty string" : !idr.str
      %t = idr.str.tail %g1
      idr.yield %v, %h, %t : !idr.str, i32, !idr.str
    }
    default(%other: i64) {
      %v = idr.constant !idr.str "xy"
      %g = idr.check.nonempty %v, "head of an empty string" : !idr.str
      %h = idr.str.head %g
      %g1 = idr.check.nonempty %v, "tail of an empty string" : !idr.str
      %t = idr.str.tail %g1
      idr.yield %v, %h, %t : !idr.str, i32, !idr.str
    }
    }
    return %r#0, %r#1, %r#2 : !idr.str, i32, !idr.str
  }
  // The program: the results of the row the byte read chooses, folded,
  // or, in the run form, computed at run time.
  idr.func @Prog.main(%w0: !idr.world) -> !idr.world {
    %byte, %w1 = idr.io.get_byte %w0
    %row = arith.extui %byte : i32 to i64
    %v, %h, %t = idr.call @folded(%row) : (i64) -> (!idr.str, i32, !idr.str)
    %space = arith.constant 32 : i32
    %newline = arith.constant 10 : i32
    %w2 = idr.io.put_str %v, %w1
    %w3 = idr.io.put_char %space, %w2
    %w4 = idr.io.put_sint %h, %w3 : i32
    %w5 = idr.io.put_char %space, %w4
    %w6 = idr.io.put_str %t, %w5
    %w7 = idr.io.put_char %newline, %w6
    return %w7 : !idr.world
  }
}
