// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=no-guards=@proving,crash-sites=@failing:2,crash-sites=@again:1 -o /dev/null
// RUN: sed 's/idr.call @folded(/idr.call @at_run_time(/' %s > %t.run.mlir
// RUN: %differential %t.run.mlir %s
// RUN: sed 's/%y = arith.constant 0 : i64/%y = arith.constant 1 : i64/' %s > %t.wrong.mlir
// RUN: not %differential %t.run.mlir %t.wrong.mlir 2>&1 | FileCheck %s --check-prefix=WRONG
// The guard of a divisor folds to the divisor where the divisor shows it
// is not zero: a constant integer, or a constant big, other than zero. On
// zero it stays, to crash where it runs. A guard of what an identical
// guard already checked folds too: its operand is that guard's result.
//
// Each guard's decision is the one the program makes at run time, on every
// row of the table: each row folds in its own region (@folded), where a
// guard of a divisor other than zero folds away and the others stay, and
// is checked at run time on the row the byte read chose (@at_run_time,
// which the sed makes the program's). On the byte of each row, and on the
// empty input for the last, the two print the same, the row's operands and
// then its results, or both crash before printing; each operand is printed
// as well as used, so that no guard on it is its one consumer, which case-
// of-case would move into the rows. The rows: divisors of 1, -1 and 2, the
// most negative and most positive Int, bigs at the edges of the runtime's
// small integers and of a word, and a zero of each kind. A wrong decision
// is found on its row: the sed makes row 3's zero divisor 1, where the run
// divides by 0.
// WRONG: differential: {{.*}}run.mlir and {{.*}}wrong.mlir differ on '\0003'
// STDIN: \0000
// STDIN: \0001
// STDIN: \0002
// STDIN: \0003
// STDIN: \0004
// STDIN: \0005
// STDIN: \0006
// STDIN: \0007
// STDIN: \0010
// STDIN:
idr.program @"fold-nonzero" root(@Prog.main) stage(first) types #idr.types<> {
  idr.func @proving(%x: i64, %b: !idr.big) -> (i64, !idr.big) {
    %seven = arith.constant 7 : i64
    %g = idr.check.nonzero %seven, "division by zero" : i64
    %q = idr.divs %x, %g : i64
    %three = idr.constant !idr.big #idr.big<-3>
    %h = idr.check.nonzero %three, "division by zero" : !idr.big
    %r = idr.big.div %b, %h
    return %q, %r : i64, !idr.big
  }

  idr.func @failing(%x: i64, %b: !idr.big) -> (i64, !idr.big) {
    %zero = arith.constant 0 : i64
    %g = idr.check.nonzero %zero, "division by zero" : i64
    %q = idr.divs %x, %g : i64
    %none = idr.constant !idr.big #idr.big<0>
    %h = idr.check.nonzero %none, "division by zero" : !idr.big
    %r = idr.big.div %b, %h
    return %q, %r : i64, !idr.big
  }

  idr.func @again(%x: i64, %y: i64) -> (i64, i64) {
    %g = idr.check.nonzero %y, "division by zero" : i64
    %q = idr.divs %x, %g : i64
    %h = idr.check.nonzero %g, "division by zero" : i64
    %m = idr.mods %x, %h : i64
    return %q, %m : i64, i64
  }
  // The operands of each row, the last the default one: the row the byte
  // chose, known only at run time.
  idr.func @rows(%row: i64) -> (i64, i64, !idr.big, !idr.big) {
    %r:4 = idr.match_lit %row : i64 -> (i64, i64, !idr.big, !idr.big) {
    case 0 {
      %x = arith.constant 7 : i64
      %y = arith.constant 7 : i64
      %b = idr.constant !idr.big #idr.big<10>
      %d = idr.constant !idr.big #idr.big<-3>
      idr.yield %x, %y, %b, %d : i64, i64, !idr.big, !idr.big
    }
    case 1 {
      %x = arith.constant -7 : i64
      %y = arith.constant 2 : i64
      %b = idr.constant !idr.big #idr.big<-10>
      %d = idr.constant !idr.big #idr.big<3>
      idr.yield %x, %y, %b, %d : i64, i64, !idr.big, !idr.big
    }
    case 2 {
      %x = arith.constant -9223372036854775808 : i64
      %y = arith.constant -1 : i64
      %b = idr.constant !idr.big #idr.big<18446744073709551616>
      %d = idr.constant !idr.big #idr.big<-1>
      idr.yield %x, %y, %b, %d : i64, i64, !idr.big, !idr.big
    }
    case 3 {
      %x = arith.constant 5 : i64
      %y = arith.constant 0 : i64
      %b = idr.constant !idr.big #idr.big<1>
      %d = idr.constant !idr.big #idr.big<1>
      idr.yield %x, %y, %b, %d : i64, i64, !idr.big, !idr.big
    }
    case 4 {
      %x = arith.constant 5 : i64
      %y = arith.constant 1 : i64
      %b = idr.constant !idr.big #idr.big<1>
      %d = idr.constant !idr.big #idr.big<0>
      idr.yield %x, %y, %b, %d : i64, i64, !idr.big, !idr.big
    }
    case 5 {
      %x = arith.constant 9223372036854775807 : i64
      %y = arith.constant 9223372036854775807 : i64
      %b = idr.constant !idr.big #idr.big<-18446744073709551616>
      %d = idr.constant !idr.big #idr.big<4611686018427387904>
      idr.yield %x, %y, %b, %d : i64, i64, !idr.big, !idr.big
    }
    case 6 {
      %x = arith.constant 0 : i64
      %y = arith.constant -9223372036854775808 : i64
      %b = idr.constant !idr.big #idr.big<9223372036854775808>
      %d = idr.constant !idr.big #idr.big<-9223372036854775808>
      idr.yield %x, %y, %b, %d : i64, i64, !idr.big, !idr.big
    }
    case 7 {
      %x = arith.constant 1 : i64
      %y = arith.constant 1 : i64
      %b = idr.constant !idr.big #idr.big<1000000000000000000000000000000>
      %d = idr.constant !idr.big #idr.big<7>
      idr.yield %x, %y, %b, %d : i64, i64, !idr.big, !idr.big
    }
    case 8 {
      %x = arith.constant 3 : i64
      %y = arith.constant -3 : i64
      %b = idr.constant !idr.big #idr.big<-7>
      %d = idr.constant !idr.big #idr.big<18446744073709551616>
      idr.yield %x, %y, %b, %d : i64, i64, !idr.big, !idr.big
    }
    default(%other: i64) {
      %x = arith.constant 9 : i64
      %y = arith.constant 4 : i64
      %b = idr.constant !idr.big #idr.big<9>
      %d = idr.constant !idr.big #idr.big<4>
      idr.yield %x, %y, %b, %d : i64, i64, !idr.big, !idr.big
    }
    }
    return %r#0, %r#1, %r#2, %r#3 : i64, i64, !idr.big, !idr.big
  }
  // Each row's results, computed at run time from the row @rows chose.
  idr.func @at_run_time(%row: i64) -> (i64, i64, !idr.big, !idr.big, i64, !idr.big) {
    %x, %y, %b, %d = idr.call @rows(%row) : (i64) -> (i64, i64, !idr.big, !idr.big)
    %g = idr.check.nonzero %y, "division by zero" : i64
    %q = idr.divs %x, %g : i64
    %h = idr.check.nonzero %d, "division by zero" : !idr.big
    %r = idr.big.div %b, %h
    return %x, %y, %b, %d, %q, %r : i64, i64, !idr.big, !idr.big, i64, !idr.big
  }
  // Each row's results on its constants, which the folders compute.
  idr.func @folded(%row: i64) -> (i64, i64, !idr.big, !idr.big, i64, !idr.big) {
    %r:6 = idr.match_lit %row : i64 -> (i64, i64, !idr.big, !idr.big, i64, !idr.big) {
    case 0 {
      %x = arith.constant 7 : i64
      %y = arith.constant 7 : i64
      %b = idr.constant !idr.big #idr.big<10>
      %d = idr.constant !idr.big #idr.big<-3>
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %h = idr.check.nonzero %d, "division by zero" : !idr.big
      %r = idr.big.div %b, %h
      idr.yield %x, %y, %b, %d, %q, %r : i64, i64, !idr.big, !idr.big, i64, !idr.big
    }
    case 1 {
      %x = arith.constant -7 : i64
      %y = arith.constant 2 : i64
      %b = idr.constant !idr.big #idr.big<-10>
      %d = idr.constant !idr.big #idr.big<3>
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %h = idr.check.nonzero %d, "division by zero" : !idr.big
      %r = idr.big.div %b, %h
      idr.yield %x, %y, %b, %d, %q, %r : i64, i64, !idr.big, !idr.big, i64, !idr.big
    }
    case 2 {
      %x = arith.constant -9223372036854775808 : i64
      %y = arith.constant -1 : i64
      %b = idr.constant !idr.big #idr.big<18446744073709551616>
      %d = idr.constant !idr.big #idr.big<-1>
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %h = idr.check.nonzero %d, "division by zero" : !idr.big
      %r = idr.big.div %b, %h
      idr.yield %x, %y, %b, %d, %q, %r : i64, i64, !idr.big, !idr.big, i64, !idr.big
    }
    case 3 {
      %x = arith.constant 5 : i64
      %y = arith.constant 0 : i64
      %b = idr.constant !idr.big #idr.big<1>
      %d = idr.constant !idr.big #idr.big<1>
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %h = idr.check.nonzero %d, "division by zero" : !idr.big
      %r = idr.big.div %b, %h
      idr.yield %x, %y, %b, %d, %q, %r : i64, i64, !idr.big, !idr.big, i64, !idr.big
    }
    case 4 {
      %x = arith.constant 5 : i64
      %y = arith.constant 1 : i64
      %b = idr.constant !idr.big #idr.big<1>
      %d = idr.constant !idr.big #idr.big<0>
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %h = idr.check.nonzero %d, "division by zero" : !idr.big
      %r = idr.big.div %b, %h
      idr.yield %x, %y, %b, %d, %q, %r : i64, i64, !idr.big, !idr.big, i64, !idr.big
    }
    case 5 {
      %x = arith.constant 9223372036854775807 : i64
      %y = arith.constant 9223372036854775807 : i64
      %b = idr.constant !idr.big #idr.big<-18446744073709551616>
      %d = idr.constant !idr.big #idr.big<4611686018427387904>
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %h = idr.check.nonzero %d, "division by zero" : !idr.big
      %r = idr.big.div %b, %h
      idr.yield %x, %y, %b, %d, %q, %r : i64, i64, !idr.big, !idr.big, i64, !idr.big
    }
    case 6 {
      %x = arith.constant 0 : i64
      %y = arith.constant -9223372036854775808 : i64
      %b = idr.constant !idr.big #idr.big<9223372036854775808>
      %d = idr.constant !idr.big #idr.big<-9223372036854775808>
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %h = idr.check.nonzero %d, "division by zero" : !idr.big
      %r = idr.big.div %b, %h
      idr.yield %x, %y, %b, %d, %q, %r : i64, i64, !idr.big, !idr.big, i64, !idr.big
    }
    case 7 {
      %x = arith.constant 1 : i64
      %y = arith.constant 1 : i64
      %b = idr.constant !idr.big #idr.big<1000000000000000000000000000000>
      %d = idr.constant !idr.big #idr.big<7>
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %h = idr.check.nonzero %d, "division by zero" : !idr.big
      %r = idr.big.div %b, %h
      idr.yield %x, %y, %b, %d, %q, %r : i64, i64, !idr.big, !idr.big, i64, !idr.big
    }
    case 8 {
      %x = arith.constant 3 : i64
      %y = arith.constant -3 : i64
      %b = idr.constant !idr.big #idr.big<-7>
      %d = idr.constant !idr.big #idr.big<18446744073709551616>
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %h = idr.check.nonzero %d, "division by zero" : !idr.big
      %r = idr.big.div %b, %h
      idr.yield %x, %y, %b, %d, %q, %r : i64, i64, !idr.big, !idr.big, i64, !idr.big
    }
    default(%other: i64) {
      %x = arith.constant 9 : i64
      %y = arith.constant 4 : i64
      %b = idr.constant !idr.big #idr.big<9>
      %d = idr.constant !idr.big #idr.big<4>
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %h = idr.check.nonzero %d, "division by zero" : !idr.big
      %r = idr.big.div %b, %h
      idr.yield %x, %y, %b, %d, %q, %r : i64, i64, !idr.big, !idr.big, i64, !idr.big
    }
    }
    return %r#0, %r#1, %r#2, %r#3, %r#4, %r#5 : i64, i64, !idr.big, !idr.big, i64, !idr.big
  }
  // The program: the results of the row the byte read chooses, folded,
  // or, in the run form, computed at run time.
  idr.func @Prog.main(%w0: !idr.world) -> !idr.world {
    %byte, %w1 = idr.io.get_byte %w0
    %row = arith.extui %byte : i32 to i64
    %x, %y, %b, %d, %q, %r = idr.call @folded(%row) : (i64) -> (i64, i64, !idr.big, !idr.big, i64, !idr.big)
    %space = arith.constant 32 : i32
    %newline = arith.constant 10 : i32
    %w2 = idr.io.put_sint %x, %w1 : i64
    %w3 = idr.io.put_char %space, %w2
    %w4 = idr.io.put_sint %y, %w3 : i64
    %w5 = idr.io.put_char %space, %w4
    %b.text = idr.big.show %b
    %w6 = idr.io.put_str %b.text, %w5
    %w7 = idr.io.put_char %space, %w6
    %d.text = idr.big.show %d
    %w8 = idr.io.put_str %d.text, %w7
    %w9 = idr.io.put_char %space, %w8
    %w10 = idr.io.put_sint %q, %w9 : i64
    %w11 = idr.io.put_char %space, %w10
    %r.text = idr.big.show %r
    %w12 = idr.io.put_str %r.text, %w11
    %w13 = idr.io.put_char %newline, %w12
    return %w13 : !idr.world
  }
}
