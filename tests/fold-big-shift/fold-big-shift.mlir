// RUN: idris-mlir-opt %s --canonicalize '--idr-expect=holds=returns=@shifts:#idr.big<-4>/#idr.big<-4>/#idr.big<18446744073709551616>/#idr.big<0>/#idr.big<-1>/#idr.big<0>,returns=@too_large:_/_,folded=@folded' -o /dev/null
// RUN: sed 's/idr.call @folded(/idr.call @at_run_time(/' %s > %t.run.mlir
// RUN: %differential %t.run.mlir %s
// RUN: sed 's/%a = idr.constant !idr.big #idr.big<-3>/%a = idr.constant !idr.big #idr.big<-4>/' %s > %t.wrong.mlir
// RUN: not %differential %t.run.mlir %t.wrong.mlir 2>&1 | FileCheck %s --check-prefix=WRONG
// idr.big.shl and idr.big.shr fold by calling the runtime: a left shift
// multiplies by 2^amount, a right shift is the floor of the quotient, a
// negative amount shifts the other way, and 0 shifted any amount is 0. A
// shift away from zero whose constant would take more static data than a
// constant made at compile time may stays, to run at runtime.
//
// The runtime's shifts at run time are the oracle for every row of the
// table: each row folds in its own region (@folded), and is computed at
// run time from the row the byte read chose (@at_run_time, which the sed
// makes the program's). On the byte of each row, and on the empty input
// for the last, the two print the same: the row's operands, then its
// results; each operand is printed as well as used, so that no op on it is
// its one consumer, which case-of-case would move into the rows, where the
// run form would fold too. The rows: values of each sign, at the edges of
// the runtime's small integers (2^62 and -2^62, one inside and one
// outside) and of a word (2^63 and -2^63), bigs of more than a word, and
// amounts of 0, 1, -1, a word's width, past it, 4096, and none a word
// holds (of 0, the one value such a shift leaves bounded both ways). A
// wrong fold is found on its row: the sed makes row 11's value -4, where
// the run shifts -3.
// WRONG: differential: {{.*}}run.mlir and {{.*}}wrong.mlir differ on '\0013'
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
// STDIN: \0015
// STDIN: \0016
// STDIN: \0017
// STDIN: \0020
// STDIN: \0021
// STDIN: \0022
// STDIN: \0023
// STDIN:
idr.program @"big-shift" root(@Prog.main) stage(first) types #idr.types<> {
  idr.func @shifts() -> (!idr.big, !idr.big, !idr.big, !idr.big, !idr.big, !idr.big) {
    %m7 = idr.constant !idr.big #idr.big<-7>
    %one = idr.constant !idr.big #idr.big<1>
    %m1 = idr.constant !idr.big #idr.big<-1>
    %c0 = idr.constant !idr.big #idr.big<0>
    %c64 = idr.constant !idr.big #idr.big<64>
    %huge = idr.constant !idr.big #idr.big<100000000000000000000>
    %mhuge = idr.constant !idr.big #idr.big<-100000000000000000000>
    // -7 >> 1 is the floor of -3.5.
    %a = idr.big.shr %m7, %one
    // A negative amount shifts the other way.
    %b = idr.big.shl %m7, %m1
    %c = idr.big.shl %one, %c64
    // 0 moved any amount, and anything moved toward zero by an amount no word
    // holds.
    %d = idr.big.shl %c0, %huge
    %e = idr.big.shr %m1, %huge
    %f = idr.big.shl %one, %mhuge
    return %a, %b, %c, %d, %e, %f : !idr.big, !idr.big, !idr.big, !idr.big, !idr.big, !idr.big
  }

  idr.func @too_large() -> (!idr.big, !idr.big) {
    %one = idr.constant !idr.big #idr.big<1>
    // One bit past 8 * 2^20.
    %n = idr.constant !idr.big #idr.big<8388609>
    %mn = idr.constant !idr.big #idr.big<-18446744073709551616>
    %a = idr.big.shl %one, %n
    // A right shift by a negative amount grows.
    %b = idr.big.shr %one, %mn
    return %a, %b : !idr.big, !idr.big
  }
  // The operands of each row, the last the default one: the row the byte
  // chose, known only at run time.
  idr.func @rows(%row: i64) -> (!idr.big, !idr.big) {
    %r:2 = idr.match_lit %row : i64 -> (!idr.big, !idr.big) {
    case 0 {
      %a = idr.constant !idr.big #idr.big<-7>
      %n = idr.constant !idr.big #idr.big<1>
      idr.yield %a, %n : !idr.big, !idr.big
    }
    case 1 {
      %a = idr.constant !idr.big #idr.big<-7>
      %n = idr.constant !idr.big #idr.big<-1>
      idr.yield %a, %n : !idr.big, !idr.big
    }
    case 2 {
      %a = idr.constant !idr.big #idr.big<1>
      %n = idr.constant !idr.big #idr.big<64>
      idr.yield %a, %n : !idr.big, !idr.big
    }
    case 3 {
      %a = idr.constant !idr.big #idr.big<0>
      %n = idr.constant !idr.big #idr.big<100000000000000000000>
      idr.yield %a, %n : !idr.big, !idr.big
    }
    case 4 {
      %a = idr.constant !idr.big #idr.big<-1>
      %n = idr.constant !idr.big #idr.big<4096>
      idr.yield %a, %n : !idr.big, !idr.big
    }
    case 5 {
      %a = idr.constant !idr.big #idr.big<1>
      %n = idr.constant !idr.big #idr.big<-4096>
      idr.yield %a, %n : !idr.big, !idr.big
    }
    case 6 {
      %a = idr.constant !idr.big #idr.big<5>
      %n = idr.constant !idr.big #idr.big<0>
      idr.yield %a, %n : !idr.big, !idr.big
    }
    case 7 {
      %a = idr.constant !idr.big #idr.big<-5>
      %n = idr.constant !idr.big #idr.big<0>
      idr.yield %a, %n : !idr.big, !idr.big
    }
    case 8 {
      %a = idr.constant !idr.big #idr.big<-1>
      %n = idr.constant !idr.big #idr.big<1>
      idr.yield %a, %n : !idr.big, !idr.big
    }
    case 9 {
      %a = idr.constant !idr.big #idr.big<-18446744073709551616>
      %n = idr.constant !idr.big #idr.big<64>
      idr.yield %a, %n : !idr.big, !idr.big
    }
    case 10 {
      %a = idr.constant !idr.big #idr.big<18446744073709551617>
      %n = idr.constant !idr.big #idr.big<-1>
      idr.yield %a, %n : !idr.big, !idr.big
    }
    case 11 {
      %a = idr.constant !idr.big #idr.big<-3>
      %n = idr.constant !idr.big #idr.big<1>
      idr.yield %a, %n : !idr.big, !idr.big
    }
    case 12 {
      %a = idr.constant !idr.big #idr.big<4611686018427387903>
      %n = idr.constant !idr.big #idr.big<1>
      idr.yield %a, %n : !idr.big, !idr.big
    }
    case 13 {
      %a = idr.constant !idr.big #idr.big<4611686018427387904>
      %n = idr.constant !idr.big #idr.big<-1>
      idr.yield %a, %n : !idr.big, !idr.big
    }
    case 14 {
      %a = idr.constant !idr.big #idr.big<-4611686018427387904>
      %n = idr.constant !idr.big #idr.big<1>
      idr.yield %a, %n : !idr.big, !idr.big
    }
    case 15 {
      %a = idr.constant !idr.big #idr.big<-4611686018427387905>
      %n = idr.constant !idr.big #idr.big<62>
      idr.yield %a, %n : !idr.big, !idr.big
    }
    case 16 {
      %a = idr.constant !idr.big #idr.big<12345678901234567890123>
      %n = idr.constant !idr.big #idr.big<7>
      idr.yield %a, %n : !idr.big, !idr.big
    }
    case 17 {
      %a = idr.constant !idr.big #idr.big<-12345678901234567890123>
      %n = idr.constant !idr.big #idr.big<70>
      idr.yield %a, %n : !idr.big, !idr.big
    }
    case 18 {
      %a = idr.constant !idr.big #idr.big<9223372036854775807>
      %n = idr.constant !idr.big #idr.big<1>
      idr.yield %a, %n : !idr.big, !idr.big
    }
    case 19 {
      %a = idr.constant !idr.big #idr.big<-9223372036854775808>
      %n = idr.constant !idr.big #idr.big<64>
      idr.yield %a, %n : !idr.big, !idr.big
    }
    default(%other: i64) {
      %a = idr.constant !idr.big #idr.big<3>
      %n = idr.constant !idr.big #idr.big<200>
      idr.yield %a, %n : !idr.big, !idr.big
    }
    }
    return %r#0, %r#1 : !idr.big, !idr.big
  }
  // Each row's results, computed at run time from the row @rows chose.
  idr.func @at_run_time(%row: i64) -> (!idr.big, !idr.big, !idr.big, !idr.big) {
    %a, %n = idr.call @rows(%row) : (i64) -> (!idr.big, !idr.big)
    %l = idr.big.shl %a, %n
    %r = idr.big.shr %a, %n
    return %a, %n, %l, %r : !idr.big, !idr.big, !idr.big, !idr.big
  }
  // Each row's results on its constants, which the folders compute.
  idr.func @folded(%row: i64) -> (!idr.big, !idr.big, !idr.big, !idr.big) {
    %r:4 = idr.match_lit %row : i64 -> (!idr.big, !idr.big, !idr.big, !idr.big) {
    case 0 {
      %a = idr.constant !idr.big #idr.big<-7>
      %n = idr.constant !idr.big #idr.big<1>
      %l = idr.big.shl %a, %n
      %r = idr.big.shr %a, %n
      idr.yield %a, %n, %l, %r : !idr.big, !idr.big, !idr.big, !idr.big
    }
    case 1 {
      %a = idr.constant !idr.big #idr.big<-7>
      %n = idr.constant !idr.big #idr.big<-1>
      %l = idr.big.shl %a, %n
      %r = idr.big.shr %a, %n
      idr.yield %a, %n, %l, %r : !idr.big, !idr.big, !idr.big, !idr.big
    }
    case 2 {
      %a = idr.constant !idr.big #idr.big<1>
      %n = idr.constant !idr.big #idr.big<64>
      %l = idr.big.shl %a, %n
      %r = idr.big.shr %a, %n
      idr.yield %a, %n, %l, %r : !idr.big, !idr.big, !idr.big, !idr.big
    }
    case 3 {
      %a = idr.constant !idr.big #idr.big<0>
      %n = idr.constant !idr.big #idr.big<100000000000000000000>
      %l = idr.big.shl %a, %n
      %r = idr.big.shr %a, %n
      idr.yield %a, %n, %l, %r : !idr.big, !idr.big, !idr.big, !idr.big
    }
    case 4 {
      %a = idr.constant !idr.big #idr.big<-1>
      %n = idr.constant !idr.big #idr.big<4096>
      %l = idr.big.shl %a, %n
      %r = idr.big.shr %a, %n
      idr.yield %a, %n, %l, %r : !idr.big, !idr.big, !idr.big, !idr.big
    }
    case 5 {
      %a = idr.constant !idr.big #idr.big<1>
      %n = idr.constant !idr.big #idr.big<-4096>
      %l = idr.big.shl %a, %n
      %r = idr.big.shr %a, %n
      idr.yield %a, %n, %l, %r : !idr.big, !idr.big, !idr.big, !idr.big
    }
    case 6 {
      %a = idr.constant !idr.big #idr.big<5>
      %n = idr.constant !idr.big #idr.big<0>
      %l = idr.big.shl %a, %n
      %r = idr.big.shr %a, %n
      idr.yield %a, %n, %l, %r : !idr.big, !idr.big, !idr.big, !idr.big
    }
    case 7 {
      %a = idr.constant !idr.big #idr.big<-5>
      %n = idr.constant !idr.big #idr.big<0>
      %l = idr.big.shl %a, %n
      %r = idr.big.shr %a, %n
      idr.yield %a, %n, %l, %r : !idr.big, !idr.big, !idr.big, !idr.big
    }
    case 8 {
      %a = idr.constant !idr.big #idr.big<-1>
      %n = idr.constant !idr.big #idr.big<1>
      %l = idr.big.shl %a, %n
      %r = idr.big.shr %a, %n
      idr.yield %a, %n, %l, %r : !idr.big, !idr.big, !idr.big, !idr.big
    }
    case 9 {
      %a = idr.constant !idr.big #idr.big<-18446744073709551616>
      %n = idr.constant !idr.big #idr.big<64>
      %l = idr.big.shl %a, %n
      %r = idr.big.shr %a, %n
      idr.yield %a, %n, %l, %r : !idr.big, !idr.big, !idr.big, !idr.big
    }
    case 10 {
      %a = idr.constant !idr.big #idr.big<18446744073709551617>
      %n = idr.constant !idr.big #idr.big<-1>
      %l = idr.big.shl %a, %n
      %r = idr.big.shr %a, %n
      idr.yield %a, %n, %l, %r : !idr.big, !idr.big, !idr.big, !idr.big
    }
    case 11 {
      %a = idr.constant !idr.big #idr.big<-3>
      %n = idr.constant !idr.big #idr.big<1>
      %l = idr.big.shl %a, %n
      %r = idr.big.shr %a, %n
      idr.yield %a, %n, %l, %r : !idr.big, !idr.big, !idr.big, !idr.big
    }
    case 12 {
      %a = idr.constant !idr.big #idr.big<4611686018427387903>
      %n = idr.constant !idr.big #idr.big<1>
      %l = idr.big.shl %a, %n
      %r = idr.big.shr %a, %n
      idr.yield %a, %n, %l, %r : !idr.big, !idr.big, !idr.big, !idr.big
    }
    case 13 {
      %a = idr.constant !idr.big #idr.big<4611686018427387904>
      %n = idr.constant !idr.big #idr.big<-1>
      %l = idr.big.shl %a, %n
      %r = idr.big.shr %a, %n
      idr.yield %a, %n, %l, %r : !idr.big, !idr.big, !idr.big, !idr.big
    }
    case 14 {
      %a = idr.constant !idr.big #idr.big<-4611686018427387904>
      %n = idr.constant !idr.big #idr.big<1>
      %l = idr.big.shl %a, %n
      %r = idr.big.shr %a, %n
      idr.yield %a, %n, %l, %r : !idr.big, !idr.big, !idr.big, !idr.big
    }
    case 15 {
      %a = idr.constant !idr.big #idr.big<-4611686018427387905>
      %n = idr.constant !idr.big #idr.big<62>
      %l = idr.big.shl %a, %n
      %r = idr.big.shr %a, %n
      idr.yield %a, %n, %l, %r : !idr.big, !idr.big, !idr.big, !idr.big
    }
    case 16 {
      %a = idr.constant !idr.big #idr.big<12345678901234567890123>
      %n = idr.constant !idr.big #idr.big<7>
      %l = idr.big.shl %a, %n
      %r = idr.big.shr %a, %n
      idr.yield %a, %n, %l, %r : !idr.big, !idr.big, !idr.big, !idr.big
    }
    case 17 {
      %a = idr.constant !idr.big #idr.big<-12345678901234567890123>
      %n = idr.constant !idr.big #idr.big<70>
      %l = idr.big.shl %a, %n
      %r = idr.big.shr %a, %n
      idr.yield %a, %n, %l, %r : !idr.big, !idr.big, !idr.big, !idr.big
    }
    case 18 {
      %a = idr.constant !idr.big #idr.big<9223372036854775807>
      %n = idr.constant !idr.big #idr.big<1>
      %l = idr.big.shl %a, %n
      %r = idr.big.shr %a, %n
      idr.yield %a, %n, %l, %r : !idr.big, !idr.big, !idr.big, !idr.big
    }
    case 19 {
      %a = idr.constant !idr.big #idr.big<-9223372036854775808>
      %n = idr.constant !idr.big #idr.big<64>
      %l = idr.big.shl %a, %n
      %r = idr.big.shr %a, %n
      idr.yield %a, %n, %l, %r : !idr.big, !idr.big, !idr.big, !idr.big
    }
    default(%other: i64) {
      %a = idr.constant !idr.big #idr.big<3>
      %n = idr.constant !idr.big #idr.big<200>
      %l = idr.big.shl %a, %n
      %r = idr.big.shr %a, %n
      idr.yield %a, %n, %l, %r : !idr.big, !idr.big, !idr.big, !idr.big
    }
    }
    return %r#0, %r#1, %r#2, %r#3 : !idr.big, !idr.big, !idr.big, !idr.big
  }
  // The program: the results of the row the byte read chooses, folded,
  // or, in the run form, computed at run time.
  idr.func @Prog.main(%w0: !idr.world) -> !idr.world {
    %byte, %w1 = idr.io.get_byte %w0
    %row = arith.extui %byte : i32 to i64
    %a, %n, %l, %r = idr.call @folded(%row) : (i64) -> (!idr.big, !idr.big, !idr.big, !idr.big)
    %space = arith.constant 32 : i32
    %newline = arith.constant 10 : i32
    %a.text = idr.big.show %a
    %w2 = idr.io.put_str %a.text, %w1
    %w3 = idr.io.put_char %space, %w2
    %n.text = idr.big.show %n
    %w4 = idr.io.put_str %n.text, %w3
    %w5 = idr.io.put_char %space, %w4
    %l.text = idr.big.show %l
    %w6 = idr.io.put_str %l.text, %w5
    %w7 = idr.io.put_char %space, %w6
    %r.text = idr.big.show %r
    %w8 = idr.io.put_str %r.text, %w7
    %w9 = idr.io.put_char %newline, %w8
    return %w9 : !idr.world
  }
}
