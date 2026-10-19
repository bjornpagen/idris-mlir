// RUN: idris-mlir-opt %s --canonicalize '--idr-expect=holds=returns-argument=@plus_zero:0,returns-argument=@zero_plus:0,returns-argument=@nat_plus_zero:0' -o /dev/null
// RUN: sed 's/idr.call @folded(/idr.call @at_run_time(/' %s > %t.run.mlir
// RUN: %differential %t.run.mlir %s
// RUN: sed 's/%a = idr.call @plus_zero(%x)/%a = idr.call @plus_zero(%z)/' %s > %t.wrong.mlir
// RUN: not %differential %t.run.mlir %t.wrong.mlir 2>&1 | FileCheck %s --check-prefix=WRONG
// A sum with zero is its other operand, whichever side the zero is on: a
// fact of idr.big.add, which its folder states, so every pass that builds
// x + 0 meets x. Each zero is a small made of a constant word.
//
// The runtime's sum at run time is the oracle, on operands no fold knows:
// the program adds the zeros of the row the byte read chose, which the run
// form (the sed makes @at_run_time the program's) adds at run time and the
// folded form, a zero it knows, folds away. On the byte of each row, and
// on the empty input for the last, the two print the same: the row's
// operands, then the sums. The rows: 0, 1 and -1, the edges of the
// runtime's small integers (2^62 and -2^62, one inside and one outside),
// of a word (2^63, -2^63, 2^64 - 1, 2^64), and of more than a word, as
// Integers and as naturals, the zero on either side; each zero is read
// twice, so that no consumer of it alone moves into the rows, where it
// would fold. A wrong fold is found: the sed makes the folded form's first
// sum the zero's, which is the Integer on row 0 alone.
// WRONG: differential: {{.*}}run.mlir and {{.*}}wrong.mlir differ on '\0001'
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
// STDIN:
idr.program @"add-zero" root(@Prog.main) stage(first) {
  idr.func @plus_zero(%x: !idr.big) -> !idr.big {
    %c0 = arith.constant 0 : i64
    %zero = idr.big.small %c0 : !idr.big
    %r = idr.big.add %x, %zero
    return %r : !idr.big
  }

  idr.func @zero_plus(%x: !idr.big) -> !idr.big {
    %c0 = arith.constant 0 : i64
    %zero = idr.big.small %c0 : !idr.big
    %r = idr.big.add %zero, %x
    return %r : !idr.big
  }

  idr.func @nat_plus_zero(%x: !idr.nat) -> !idr.nat {
    %c0 = arith.constant 0 : i64
    %zero = idr.big.small %c0 : !idr.nat
    %r = idr.big.add %x, %zero : !idr.nat
    return %r : !idr.nat
  }
  // The operands of each row, chosen by the byte: an Integer and a natural,
  // and the zeros the run form adds, which are 0 on every row a byte or the
  // empty input chooses; row 256, which none chooses, keeps them from being
  // one constant.
  idr.func @rows(%row: i64) -> (!idr.big, !idr.nat, !idr.big, !idr.nat) {
    %r:4 = idr.match_lit %row : i64 -> (!idr.big, !idr.nat, !idr.big, !idr.nat) {
    case 0 {
      %x = idr.constant !idr.big #idr.big<0>
      %n = idr.constant !idr.nat #idr.big<0>
      %z = idr.constant !idr.big #idr.big<0>
      %zn = idr.constant !idr.nat #idr.big<0>
      idr.yield %x, %n, %z, %zn : !idr.big, !idr.nat, !idr.big, !idr.nat
    }
    case 1 {
      %x = idr.constant !idr.big #idr.big<1>
      %n = idr.constant !idr.nat #idr.big<1>
      %z = idr.constant !idr.big #idr.big<0>
      %zn = idr.constant !idr.nat #idr.big<0>
      idr.yield %x, %n, %z, %zn : !idr.big, !idr.nat, !idr.big, !idr.nat
    }
    case 2 {
      %x = idr.constant !idr.big #idr.big<-1>
      %n = idr.constant !idr.nat #idr.big<2>
      %z = idr.constant !idr.big #idr.big<0>
      %zn = idr.constant !idr.nat #idr.big<0>
      idr.yield %x, %n, %z, %zn : !idr.big, !idr.nat, !idr.big, !idr.nat
    }
    case 3 {
      %x = idr.constant !idr.big #idr.big<4611686018427387903>
      %n = idr.constant !idr.nat #idr.big<4611686018427387903>
      %z = idr.constant !idr.big #idr.big<0>
      %zn = idr.constant !idr.nat #idr.big<0>
      idr.yield %x, %n, %z, %zn : !idr.big, !idr.nat, !idr.big, !idr.nat
    }
    case 4 {
      %x = idr.constant !idr.big #idr.big<4611686018427387904>
      %n = idr.constant !idr.nat #idr.big<4611686018427387904>
      %z = idr.constant !idr.big #idr.big<0>
      %zn = idr.constant !idr.nat #idr.big<0>
      idr.yield %x, %n, %z, %zn : !idr.big, !idr.nat, !idr.big, !idr.nat
    }
    case 5 {
      %x = idr.constant !idr.big #idr.big<-4611686018427387904>
      %n = idr.constant !idr.nat #idr.big<4611686018427387905>
      %z = idr.constant !idr.big #idr.big<0>
      %zn = idr.constant !idr.nat #idr.big<0>
      idr.yield %x, %n, %z, %zn : !idr.big, !idr.nat, !idr.big, !idr.nat
    }
    case 6 {
      %x = idr.constant !idr.big #idr.big<-4611686018427387905>
      %n = idr.constant !idr.nat #idr.big<9223372036854775808>
      %z = idr.constant !idr.big #idr.big<0>
      %zn = idr.constant !idr.nat #idr.big<0>
      idr.yield %x, %n, %z, %zn : !idr.big, !idr.nat, !idr.big, !idr.nat
    }
    case 7 {
      %x = idr.constant !idr.big #idr.big<9223372036854775808>
      %n = idr.constant !idr.nat #idr.big<18446744073709551615>
      %z = idr.constant !idr.big #idr.big<0>
      %zn = idr.constant !idr.nat #idr.big<0>
      idr.yield %x, %n, %z, %zn : !idr.big, !idr.nat, !idr.big, !idr.nat
    }
    case 8 {
      %x = idr.constant !idr.big #idr.big<-9223372036854775808>
      %n = idr.constant !idr.nat #idr.big<18446744073709551616>
      %z = idr.constant !idr.big #idr.big<0>
      %zn = idr.constant !idr.nat #idr.big<0>
      idr.yield %x, %n, %z, %zn : !idr.big, !idr.nat, !idr.big, !idr.nat
    }
    case 9 {
      %x = idr.constant !idr.big #idr.big<18446744073709551616>
      %n = idr.constant !idr.nat #idr.big<1000000000000000000000000000000>
      %z = idr.constant !idr.big #idr.big<0>
      %zn = idr.constant !idr.nat #idr.big<0>
      idr.yield %x, %n, %z, %zn : !idr.big, !idr.nat, !idr.big, !idr.nat
    }
    case 10 {
      %x = idr.constant !idr.big #idr.big<1000000000000000000000000000000>
      %n = idr.constant !idr.nat #idr.big<3>
      %z = idr.constant !idr.big #idr.big<0>
      %zn = idr.constant !idr.nat #idr.big<0>
      idr.yield %x, %n, %z, %zn : !idr.big, !idr.nat, !idr.big, !idr.nat
    }
    case 11 {
      %x = idr.constant !idr.big #idr.big<-1000000000000000000000000000000>
      %n = idr.constant !idr.nat #idr.big<5>
      %z = idr.constant !idr.big #idr.big<0>
      %zn = idr.constant !idr.nat #idr.big<0>
      idr.yield %x, %n, %z, %zn : !idr.big, !idr.nat, !idr.big, !idr.nat
    }
    case 256 {
      %x = idr.constant !idr.big #idr.big<0>
      %n = idr.constant !idr.nat #idr.big<0>
      %z = idr.constant !idr.big #idr.big<1>
      %zn = idr.constant !idr.nat #idr.big<1>
      idr.yield %x, %n, %z, %zn : !idr.big, !idr.nat, !idr.big, !idr.nat
    }
    default(%other: i64) {
      %x = idr.constant !idr.big #idr.big<7>
      %n = idr.constant !idr.nat #idr.big<9>
      %z = idr.constant !idr.big #idr.big<0>
      %zn = idr.constant !idr.nat #idr.big<0>
      idr.yield %x, %n, %z, %zn : !idr.big, !idr.nat, !idr.big, !idr.nat
    }
    }
    return %r#0, %r#1, %r#2, %r#3 : !idr.big, !idr.nat, !idr.big, !idr.nat
  }
  // The sums at run time: the row's operands plus its zeros, which the
  // program cannot know are 0.
  idr.func @at_run_time(%row: i64) -> (!idr.big, !idr.nat, !idr.big, !idr.big, !idr.nat, !idr.nat) {
    %x, %n, %z, %zn = idr.call @rows(%row) : (i64) -> (!idr.big, !idr.nat, !idr.big, !idr.nat)
    %a = idr.big.add %x, %z
    %b = idr.big.add %z, %x
    %c = idr.big.add %n, %zn : !idr.nat
    %d = idr.big.add %zn, %n : !idr.nat
    return %x, %n, %a, %b, %c, %d : !idr.big, !idr.nat, !idr.big, !idr.big, !idr.nat, !idr.nat
  }
  // The same sums with a zero the program knows, which fold away.
  idr.func @folded(%row: i64) -> (!idr.big, !idr.nat, !idr.big, !idr.big, !idr.nat, !idr.nat) {
    %x, %n, %z, %zn = idr.call @rows(%row) : (i64) -> (!idr.big, !idr.nat, !idr.big, !idr.nat)
    %a = idr.call @plus_zero(%x) : (!idr.big) -> !idr.big
    %b = idr.call @zero_plus(%x) : (!idr.big) -> !idr.big
    %c = idr.call @nat_plus_zero(%n) : (!idr.nat) -> !idr.nat
    %c0 = arith.constant 0 : i64
    %zero = idr.big.small %c0 : !idr.nat
    %d = idr.big.add %zero, %n : !idr.nat
    return %x, %n, %a, %b, %c, %d : !idr.big, !idr.nat, !idr.big, !idr.big, !idr.nat, !idr.nat
  }
  // The program: the operands and the sums of the row the byte read
  // chooses, folded, or, in the run form, computed at run time.
  idr.func @Prog.main(%w0: !idr.world) -> !idr.world {
    %byte, %w1 = idr.io.get_byte %w0
    %row = arith.extui %byte : i32 to i64
    %x, %n, %a, %b, %c, %d = idr.call @folded(%row) : (i64) -> (!idr.big, !idr.nat, !idr.big, !idr.big, !idr.nat, !idr.nat)
    %space = arith.constant 32 : i32
    %newline = arith.constant 10 : i32
    %nb = idr.nat.to_big %n
    %cb = idr.nat.to_big %c
    %db = idr.nat.to_big %d
    %xt = idr.big.show %x
    %nt = idr.big.show %nb
    %at = idr.big.show %a
    %bt = idr.big.show %b
    %ct = idr.big.show %cb
    %dt = idr.big.show %db
    %w2 = idr.io.put_str %xt, %w1
    %w3 = idr.io.put_char %space, %w2
    %w4 = idr.io.put_str %nt, %w3
    %w5 = idr.io.put_char %space, %w4
    %w6 = idr.io.put_str %at, %w5
    %w7 = idr.io.put_char %space, %w6
    %w8 = idr.io.put_str %bt, %w7
    %w9 = idr.io.put_char %space, %w8
    %w10 = idr.io.put_str %ct, %w9
    %w11 = idr.io.put_char %space, %w10
    %w12 = idr.io.put_str %dt, %w11
    %w13 = idr.io.put_char %newline, %w12
    return %w13 : !idr.world
  }
}
