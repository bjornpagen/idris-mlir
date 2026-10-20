// RUN: idris-mlir-opt %s --canonicalize '--idr-expect=holds=returns=@naturals:#idr.big<18446744073709551621>/#idr.big<92233720368547758080>/true/#idr.big<4>/_/#idr.big<0>/#idr.big<12>/#idr.big<5>,folded=@folded' -o /dev/null
// RUN: sed 's/idr.call @folded(/idr.call @at_run_time(/' %s > %t.run.mlir
// RUN: %differential %t.run.mlir %s
// RUN: sed 's/%i = idr.constant !idr.big #idr.big<-1>/%i = idr.constant !idr.big #idr.big<1>/' %s > %t.wrong.mlir
// RUN: not %differential %t.run.mlir %t.wrong.mlir 2>&1 | FileCheck %s --check-prefix=WRONG
// The runtime folds the operations on constant naturals, as it computes
// them at runtime, and the results stay naturals: a sum and a product; a
// comparison; a predecessor (zero has none: on a path a match excludes, it
// stays as it is); an Integer clamped at 0; a natural as an Integer.
//
// The runtime's operations at run time are the oracle for every row of the
// table: each row folds in its own region (@folded), and is computed at
// run time from the row the byte read chose (@at_run_time, which the sed
// makes the program's). On the byte of each row, and on the empty input
// for the last, the two print the same: the row's operands, then its
// results; each operand is printed as well as used, so that no op on it is
// its one consumer, which case-of-case would move into the rows, where the
// run form would fold too. The rows: 0 and 1, the edges of the runtime's
// small integers (2^62 - 1, 2^62, 2^62 + 1) and of a word (2^63, 2^64 - 1,
// 2^64, 2^64 + 1), equal operands, and Integers of each sign to clamp; the
// predecessor's operand is never 0. A wrong fold is found on its row: the
// sed makes row 7's Integer 1, where the run clamps -1.
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
// STDIN:
idr.program @nat root(@Prog.main) stage(first) types #idr.types<> {
  idr.func @naturals() -> (!idr.nat, !idr.nat, i1, !idr.nat, !idr.nat, !idr.nat, !idr.nat, !idr.big) {
    %five = idr.constant !idr.nat #idr.big<5>
    %zero = idr.constant !idr.nat #idr.big<0>
    %large = idr.constant !idr.nat #idr.big<18446744073709551616>
    %negative = idr.constant !idr.big #idr.big<-7>
    %twelve = idr.constant !idr.big #idr.big<12>
    %s = idr.big.add %five, %large : !idr.nat
    %p = idr.big.mul %five, %large : !idr.nat
    %c = idr.big.cmp lt %five, %large : !idr.nat
    %d = idr.big.pred %five
    %z = idr.big.pred %zero
    %n = idr.nat.from_big %negative
    %m = idr.nat.from_big %twelve
    %i = idr.nat.to_big %five
    return %s, %p, %c, %d, %z, %n, %m, %i
        : !idr.nat, !idr.nat, i1, !idr.nat, !idr.nat, !idr.nat, !idr.nat, !idr.big
  }
  // The operands of each row, the last the default one: the row the byte
  // chose, known only at run time.
  idr.func @rows(%row: i64) -> (!idr.nat, !idr.nat, !idr.nat, !idr.big) {
    %r:4 = idr.match_lit %row : i64 -> (!idr.nat, !idr.nat, !idr.nat, !idr.big) {
    case 0 {
      %a = idr.constant !idr.nat #idr.big<5>
      %b = idr.constant !idr.nat #idr.big<18446744073709551616>
      %c = idr.constant !idr.nat #idr.big<5>
      %i = idr.constant !idr.big #idr.big<-7>
      idr.yield %a, %b, %c, %i : !idr.nat, !idr.nat, !idr.nat, !idr.big
    }
    case 1 {
      %a = idr.constant !idr.nat #idr.big<0>
      %b = idr.constant !idr.nat #idr.big<0>
      %c = idr.constant !idr.nat #idr.big<1>
      %i = idr.constant !idr.big #idr.big<0>
      idr.yield %a, %b, %c, %i : !idr.nat, !idr.nat, !idr.nat, !idr.big
    }
    case 2 {
      %a = idr.constant !idr.nat #idr.big<1>
      %b = idr.constant !idr.nat #idr.big<0>
      %c = idr.constant !idr.nat #idr.big<2>
      %i = idr.constant !idr.big #idr.big<12>
      idr.yield %a, %b, %c, %i : !idr.nat, !idr.nat, !idr.nat, !idr.big
    }
    case 3 {
      %a = idr.constant !idr.nat #idr.big<18446744073709551616>
      %b = idr.constant !idr.nat #idr.big<18446744073709551616>
      %c = idr.constant !idr.nat #idr.big<18446744073709551616>
      %i = idr.constant !idr.big #idr.big<-18446744073709551616>
      idr.yield %a, %b, %c, %i : !idr.nat, !idr.nat, !idr.nat, !idr.big
    }
    case 4 {
      %a = idr.constant !idr.nat #idr.big<4611686018427387903>
      %b = idr.constant !idr.nat #idr.big<1>
      %c = idr.constant !idr.nat #idr.big<4611686018427387904>
      %i = idr.constant !idr.big #idr.big<4611686018427387904>
      idr.yield %a, %b, %c, %i : !idr.nat, !idr.nat, !idr.nat, !idr.big
    }
    case 5 {
      %a = idr.constant !idr.nat #idr.big<4611686018427387904>
      %b = idr.constant !idr.nat #idr.big<4611686018427387904>
      %c = idr.constant !idr.nat #idr.big<4611686018427387905>
      %i = idr.constant !idr.big #idr.big<-4611686018427387904>
      idr.yield %a, %b, %c, %i : !idr.nat, !idr.nat, !idr.nat, !idr.big
    }
    case 6 {
      %a = idr.constant !idr.nat #idr.big<9223372036854775808>
      %b = idr.constant !idr.nat #idr.big<2>
      %c = idr.constant !idr.nat #idr.big<9223372036854775808>
      %i = idr.constant !idr.big #idr.big<9223372036854775807>
      idr.yield %a, %b, %c, %i : !idr.nat, !idr.nat, !idr.nat, !idr.big
    }
    case 7 {
      %a = idr.constant !idr.nat #idr.big<18446744073709551615>
      %b = idr.constant !idr.nat #idr.big<18446744073709551615>
      %c = idr.constant !idr.nat #idr.big<18446744073709551617>
      %i = idr.constant !idr.big #idr.big<-1>
      idr.yield %a, %b, %c, %i : !idr.nat, !idr.nat, !idr.nat, !idr.big
    }
    case 8 {
      %a = idr.constant !idr.nat #idr.big<7>
      %b = idr.constant !idr.nat #idr.big<7>
      %c = idr.constant !idr.nat #idr.big<7>
      %i = idr.constant !idr.big #idr.big<1000000000000000000000000000000>
      idr.yield %a, %b, %c, %i : !idr.nat, !idr.nat, !idr.nat, !idr.big
    }
    case 9 {
      %a = idr.constant !idr.nat #idr.big<0>
      %b = idr.constant !idr.nat #idr.big<1000000000000000000000000000000>
      %c = idr.constant !idr.nat #idr.big<1000000000000000000000000000000>
      %i = idr.constant !idr.big #idr.big<-1000000000000000000000000000000>
      idr.yield %a, %b, %c, %i : !idr.nat, !idr.nat, !idr.nat, !idr.big
    }
    case 10 {
      %a = idr.constant !idr.nat #idr.big<12345678901234567890>
      %b = idr.constant !idr.nat #idr.big<98765432109876543210>
      %c = idr.constant !idr.nat #idr.big<3>
      %i = idr.constant !idr.big #idr.big<4611686018427387905>
      idr.yield %a, %b, %c, %i : !idr.nat, !idr.nat, !idr.nat, !idr.big
    }
    default(%other: i64) {
      %a = idr.constant !idr.nat #idr.big<3>
      %b = idr.constant !idr.nat #idr.big<2>
      %c = idr.constant !idr.nat #idr.big<1>
      %i = idr.constant !idr.big #idr.big<18446744073709551616>
      idr.yield %a, %b, %c, %i : !idr.nat, !idr.nat, !idr.nat, !idr.big
    }
    }
    return %r#0, %r#1, %r#2, %r#3 : !idr.nat, !idr.nat, !idr.nat, !idr.big
  }
  // Each row's results, computed at run time from the row @rows chose.
  idr.func @at_run_time(%row: i64) -> (!idr.nat, !idr.nat, !idr.nat, !idr.big, !idr.nat, !idr.nat, i1, i1, !idr.nat, !idr.nat, !idr.big) {
    %a, %b, %c, %i = idr.call @rows(%row) : (i64) -> (!idr.nat, !idr.nat, !idr.nat, !idr.big)
    %s = idr.big.add %a, %b : !idr.nat
    %p = idr.big.mul %a, %b : !idr.nat
    %lt = idr.big.cmp lt %a, %b : !idr.nat
    %eq = idr.big.cmp eq %a, %b : !idr.nat
    %d = idr.big.pred %c
    %n = idr.nat.from_big %i
    %m = idr.nat.to_big %a
    return %a, %b, %c, %i, %s, %p, %lt, %eq, %d, %n, %m : !idr.nat, !idr.nat, !idr.nat, !idr.big, !idr.nat, !idr.nat, i1, i1, !idr.nat, !idr.nat, !idr.big
  }
  // Each row's results on its constants, which the folders compute.
  idr.func @folded(%row: i64) -> (!idr.nat, !idr.nat, !idr.nat, !idr.big, !idr.nat, !idr.nat, i1, i1, !idr.nat, !idr.nat, !idr.big) {
    %r:11 = idr.match_lit %row : i64 -> (!idr.nat, !idr.nat, !idr.nat, !idr.big, !idr.nat, !idr.nat, i1, i1, !idr.nat, !idr.nat, !idr.big) {
    case 0 {
      %a = idr.constant !idr.nat #idr.big<5>
      %b = idr.constant !idr.nat #idr.big<18446744073709551616>
      %c = idr.constant !idr.nat #idr.big<5>
      %i = idr.constant !idr.big #idr.big<-7>
      %s = idr.big.add %a, %b : !idr.nat
      %p = idr.big.mul %a, %b : !idr.nat
      %lt = idr.big.cmp lt %a, %b : !idr.nat
      %eq = idr.big.cmp eq %a, %b : !idr.nat
      %d = idr.big.pred %c
      %n = idr.nat.from_big %i
      %m = idr.nat.to_big %a
      idr.yield %a, %b, %c, %i, %s, %p, %lt, %eq, %d, %n, %m : !idr.nat, !idr.nat, !idr.nat, !idr.big, !idr.nat, !idr.nat, i1, i1, !idr.nat, !idr.nat, !idr.big
    }
    case 1 {
      %a = idr.constant !idr.nat #idr.big<0>
      %b = idr.constant !idr.nat #idr.big<0>
      %c = idr.constant !idr.nat #idr.big<1>
      %i = idr.constant !idr.big #idr.big<0>
      %s = idr.big.add %a, %b : !idr.nat
      %p = idr.big.mul %a, %b : !idr.nat
      %lt = idr.big.cmp lt %a, %b : !idr.nat
      %eq = idr.big.cmp eq %a, %b : !idr.nat
      %d = idr.big.pred %c
      %n = idr.nat.from_big %i
      %m = idr.nat.to_big %a
      idr.yield %a, %b, %c, %i, %s, %p, %lt, %eq, %d, %n, %m : !idr.nat, !idr.nat, !idr.nat, !idr.big, !idr.nat, !idr.nat, i1, i1, !idr.nat, !idr.nat, !idr.big
    }
    case 2 {
      %a = idr.constant !idr.nat #idr.big<1>
      %b = idr.constant !idr.nat #idr.big<0>
      %c = idr.constant !idr.nat #idr.big<2>
      %i = idr.constant !idr.big #idr.big<12>
      %s = idr.big.add %a, %b : !idr.nat
      %p = idr.big.mul %a, %b : !idr.nat
      %lt = idr.big.cmp lt %a, %b : !idr.nat
      %eq = idr.big.cmp eq %a, %b : !idr.nat
      %d = idr.big.pred %c
      %n = idr.nat.from_big %i
      %m = idr.nat.to_big %a
      idr.yield %a, %b, %c, %i, %s, %p, %lt, %eq, %d, %n, %m : !idr.nat, !idr.nat, !idr.nat, !idr.big, !idr.nat, !idr.nat, i1, i1, !idr.nat, !idr.nat, !idr.big
    }
    case 3 {
      %a = idr.constant !idr.nat #idr.big<18446744073709551616>
      %b = idr.constant !idr.nat #idr.big<18446744073709551616>
      %c = idr.constant !idr.nat #idr.big<18446744073709551616>
      %i = idr.constant !idr.big #idr.big<-18446744073709551616>
      %s = idr.big.add %a, %b : !idr.nat
      %p = idr.big.mul %a, %b : !idr.nat
      %lt = idr.big.cmp lt %a, %b : !idr.nat
      %eq = idr.big.cmp eq %a, %b : !idr.nat
      %d = idr.big.pred %c
      %n = idr.nat.from_big %i
      %m = idr.nat.to_big %a
      idr.yield %a, %b, %c, %i, %s, %p, %lt, %eq, %d, %n, %m : !idr.nat, !idr.nat, !idr.nat, !idr.big, !idr.nat, !idr.nat, i1, i1, !idr.nat, !idr.nat, !idr.big
    }
    case 4 {
      %a = idr.constant !idr.nat #idr.big<4611686018427387903>
      %b = idr.constant !idr.nat #idr.big<1>
      %c = idr.constant !idr.nat #idr.big<4611686018427387904>
      %i = idr.constant !idr.big #idr.big<4611686018427387904>
      %s = idr.big.add %a, %b : !idr.nat
      %p = idr.big.mul %a, %b : !idr.nat
      %lt = idr.big.cmp lt %a, %b : !idr.nat
      %eq = idr.big.cmp eq %a, %b : !idr.nat
      %d = idr.big.pred %c
      %n = idr.nat.from_big %i
      %m = idr.nat.to_big %a
      idr.yield %a, %b, %c, %i, %s, %p, %lt, %eq, %d, %n, %m : !idr.nat, !idr.nat, !idr.nat, !idr.big, !idr.nat, !idr.nat, i1, i1, !idr.nat, !idr.nat, !idr.big
    }
    case 5 {
      %a = idr.constant !idr.nat #idr.big<4611686018427387904>
      %b = idr.constant !idr.nat #idr.big<4611686018427387904>
      %c = idr.constant !idr.nat #idr.big<4611686018427387905>
      %i = idr.constant !idr.big #idr.big<-4611686018427387904>
      %s = idr.big.add %a, %b : !idr.nat
      %p = idr.big.mul %a, %b : !idr.nat
      %lt = idr.big.cmp lt %a, %b : !idr.nat
      %eq = idr.big.cmp eq %a, %b : !idr.nat
      %d = idr.big.pred %c
      %n = idr.nat.from_big %i
      %m = idr.nat.to_big %a
      idr.yield %a, %b, %c, %i, %s, %p, %lt, %eq, %d, %n, %m : !idr.nat, !idr.nat, !idr.nat, !idr.big, !idr.nat, !idr.nat, i1, i1, !idr.nat, !idr.nat, !idr.big
    }
    case 6 {
      %a = idr.constant !idr.nat #idr.big<9223372036854775808>
      %b = idr.constant !idr.nat #idr.big<2>
      %c = idr.constant !idr.nat #idr.big<9223372036854775808>
      %i = idr.constant !idr.big #idr.big<9223372036854775807>
      %s = idr.big.add %a, %b : !idr.nat
      %p = idr.big.mul %a, %b : !idr.nat
      %lt = idr.big.cmp lt %a, %b : !idr.nat
      %eq = idr.big.cmp eq %a, %b : !idr.nat
      %d = idr.big.pred %c
      %n = idr.nat.from_big %i
      %m = idr.nat.to_big %a
      idr.yield %a, %b, %c, %i, %s, %p, %lt, %eq, %d, %n, %m : !idr.nat, !idr.nat, !idr.nat, !idr.big, !idr.nat, !idr.nat, i1, i1, !idr.nat, !idr.nat, !idr.big
    }
    case 7 {
      %a = idr.constant !idr.nat #idr.big<18446744073709551615>
      %b = idr.constant !idr.nat #idr.big<18446744073709551615>
      %c = idr.constant !idr.nat #idr.big<18446744073709551617>
      %i = idr.constant !idr.big #idr.big<-1>
      %s = idr.big.add %a, %b : !idr.nat
      %p = idr.big.mul %a, %b : !idr.nat
      %lt = idr.big.cmp lt %a, %b : !idr.nat
      %eq = idr.big.cmp eq %a, %b : !idr.nat
      %d = idr.big.pred %c
      %n = idr.nat.from_big %i
      %m = idr.nat.to_big %a
      idr.yield %a, %b, %c, %i, %s, %p, %lt, %eq, %d, %n, %m : !idr.nat, !idr.nat, !idr.nat, !idr.big, !idr.nat, !idr.nat, i1, i1, !idr.nat, !idr.nat, !idr.big
    }
    case 8 {
      %a = idr.constant !idr.nat #idr.big<7>
      %b = idr.constant !idr.nat #idr.big<7>
      %c = idr.constant !idr.nat #idr.big<7>
      %i = idr.constant !idr.big #idr.big<1000000000000000000000000000000>
      %s = idr.big.add %a, %b : !idr.nat
      %p = idr.big.mul %a, %b : !idr.nat
      %lt = idr.big.cmp lt %a, %b : !idr.nat
      %eq = idr.big.cmp eq %a, %b : !idr.nat
      %d = idr.big.pred %c
      %n = idr.nat.from_big %i
      %m = idr.nat.to_big %a
      idr.yield %a, %b, %c, %i, %s, %p, %lt, %eq, %d, %n, %m : !idr.nat, !idr.nat, !idr.nat, !idr.big, !idr.nat, !idr.nat, i1, i1, !idr.nat, !idr.nat, !idr.big
    }
    case 9 {
      %a = idr.constant !idr.nat #idr.big<0>
      %b = idr.constant !idr.nat #idr.big<1000000000000000000000000000000>
      %c = idr.constant !idr.nat #idr.big<1000000000000000000000000000000>
      %i = idr.constant !idr.big #idr.big<-1000000000000000000000000000000>
      %s = idr.big.add %a, %b : !idr.nat
      %p = idr.big.mul %a, %b : !idr.nat
      %lt = idr.big.cmp lt %a, %b : !idr.nat
      %eq = idr.big.cmp eq %a, %b : !idr.nat
      %d = idr.big.pred %c
      %n = idr.nat.from_big %i
      %m = idr.nat.to_big %a
      idr.yield %a, %b, %c, %i, %s, %p, %lt, %eq, %d, %n, %m : !idr.nat, !idr.nat, !idr.nat, !idr.big, !idr.nat, !idr.nat, i1, i1, !idr.nat, !idr.nat, !idr.big
    }
    case 10 {
      %a = idr.constant !idr.nat #idr.big<12345678901234567890>
      %b = idr.constant !idr.nat #idr.big<98765432109876543210>
      %c = idr.constant !idr.nat #idr.big<3>
      %i = idr.constant !idr.big #idr.big<4611686018427387905>
      %s = idr.big.add %a, %b : !idr.nat
      %p = idr.big.mul %a, %b : !idr.nat
      %lt = idr.big.cmp lt %a, %b : !idr.nat
      %eq = idr.big.cmp eq %a, %b : !idr.nat
      %d = idr.big.pred %c
      %n = idr.nat.from_big %i
      %m = idr.nat.to_big %a
      idr.yield %a, %b, %c, %i, %s, %p, %lt, %eq, %d, %n, %m : !idr.nat, !idr.nat, !idr.nat, !idr.big, !idr.nat, !idr.nat, i1, i1, !idr.nat, !idr.nat, !idr.big
    }
    default(%other: i64) {
      %a = idr.constant !idr.nat #idr.big<3>
      %b = idr.constant !idr.nat #idr.big<2>
      %c = idr.constant !idr.nat #idr.big<1>
      %i = idr.constant !idr.big #idr.big<18446744073709551616>
      %s = idr.big.add %a, %b : !idr.nat
      %p = idr.big.mul %a, %b : !idr.nat
      %lt = idr.big.cmp lt %a, %b : !idr.nat
      %eq = idr.big.cmp eq %a, %b : !idr.nat
      %d = idr.big.pred %c
      %n = idr.nat.from_big %i
      %m = idr.nat.to_big %a
      idr.yield %a, %b, %c, %i, %s, %p, %lt, %eq, %d, %n, %m : !idr.nat, !idr.nat, !idr.nat, !idr.big, !idr.nat, !idr.nat, i1, i1, !idr.nat, !idr.nat, !idr.big
    }
    }
    return %r#0, %r#1, %r#2, %r#3, %r#4, %r#5, %r#6, %r#7, %r#8, %r#9, %r#10 : !idr.nat, !idr.nat, !idr.nat, !idr.big, !idr.nat, !idr.nat, i1, i1, !idr.nat, !idr.nat, !idr.big
  }
  // The program: the results of the row the byte read chooses, folded,
  // or, in the run form, computed at run time.
  idr.func @Prog.main(%w0: !idr.world) -> !idr.world {
    %byte, %w1 = idr.io.get_byte %w0
    %row = arith.extui %byte : i32 to i64
    %a, %b, %c, %i, %s, %p, %lt, %eq, %d, %n, %m = idr.call @folded(%row) : (i64) -> (!idr.nat, !idr.nat, !idr.nat, !idr.big, !idr.nat, !idr.nat, i1, i1, !idr.nat, !idr.nat, !idr.big)
    %space = arith.constant 32 : i32
    %newline = arith.constant 10 : i32
    %a.big = idr.nat.to_big %a
    %a.big.text = idr.big.show %a.big
    %w2 = idr.io.put_str %a.big.text, %w1
    %w3 = idr.io.put_char %space, %w2
    %b.big = idr.nat.to_big %b
    %b.big.text = idr.big.show %b.big
    %w4 = idr.io.put_str %b.big.text, %w3
    %w5 = idr.io.put_char %space, %w4
    %c.big = idr.nat.to_big %c
    %c.big.text = idr.big.show %c.big
    %w6 = idr.io.put_str %c.big.text, %w5
    %w7 = idr.io.put_char %space, %w6
    %i.text = idr.big.show %i
    %w8 = idr.io.put_str %i.text, %w7
    %w9 = idr.io.put_char %space, %w8
    %s.big = idr.nat.to_big %s
    %s.big.text = idr.big.show %s.big
    %w10 = idr.io.put_str %s.big.text, %w9
    %w11 = idr.io.put_char %space, %w10
    %p.big = idr.nat.to_big %p
    %p.big.text = idr.big.show %p.big
    %w12 = idr.io.put_str %p.big.text, %w11
    %w13 = idr.io.put_char %space, %w12
    %lt.word = arith.extui %lt : i1 to i64
    %w14 = idr.io.put_sint %lt.word, %w13 : i64
    %w15 = idr.io.put_char %space, %w14
    %eq.word = arith.extui %eq : i1 to i64
    %w16 = idr.io.put_sint %eq.word, %w15 : i64
    %w17 = idr.io.put_char %space, %w16
    %d.big = idr.nat.to_big %d
    %d.big.text = idr.big.show %d.big
    %w18 = idr.io.put_str %d.big.text, %w17
    %w19 = idr.io.put_char %space, %w18
    %n.big = idr.nat.to_big %n
    %n.big.text = idr.big.show %n.big
    %w20 = idr.io.put_str %n.big.text, %w19
    %w21 = idr.io.put_char %space, %w20
    %m.text = idr.big.show %m
    %w22 = idr.io.put_str %m.text, %w21
    %w23 = idr.io.put_char %newline, %w22
    return %w23 : !idr.world
  }
}
