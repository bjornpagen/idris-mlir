// RUN: idris-mlir-opt %s --canonicalize '--idr-expect=holds=returns=@preds:#idr.big<4>/_/#idr.big<18446744073709551616>,folded=@folded' -o /dev/null
// RUN: sed 's/idr.call @folded(/idr.call @at_run_time(/' %s > %t.run.mlir
// RUN: %differential %t.run.mlir %s
// RUN: sed 's/%p = idr.constant !idr.nat #idr.big<18446744073709551616>/%p = idr.constant !idr.nat #idr.big<18446744073709551615>/' %s > %t.wrong.mlir
// RUN: not %differential %t.run.mlir %t.wrong.mlir 2>&1 | FileCheck %s --check-prefix=WRONG
// The runtime folds the predecessor of a constant; zero has none, so its
// predecessor, on a path a match excludes, stays as it is.
//
// The runtime's predecessor at run time is the oracle for every row of the
// table: each row folds in its own region (@folded), and is computed at
// run time from the row the byte read chose (@at_run_time, which the sed
// makes the program's). On the byte of each row, and on the empty input
// for the last, the two print the same: the row's operands, then its
// results; each operand is printed as well as used, so that no op on it is
// its one consumer, which case-of-case would move into the rows, where the
// run form would fold too. The rows: 1, where the predecessor is 0; the
// edges of the runtime's small integers (2^62 - 1, 2^62, 2^62 + 1), where
// a small becomes a big or a big a small; those of a word (2^63, 2^64),
// each with its neighbours; and a natural of more than a word; never 0,
// which no program reaches. A wrong fold is found on its row: the sed
// makes row 9's natural 2^64 - 1, where the run takes 2^64.
// WRONG: differential: {{.*}}run.mlir and {{.*}}wrong.mlir differ on '\0011'
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
idr.program @pred root(@Prog.main) stage(first) types #idr.types<> {
  idr.func @preds() -> (!idr.nat, !idr.nat, !idr.nat) {
    %five = idr.constant !idr.nat #idr.big<5>
    %zero = idr.constant !idr.nat #idr.big<0>
    %large = idr.constant !idr.nat #idr.big<18446744073709551617>
    %a = idr.big.pred %five
    %b = idr.big.pred %zero
    %c = idr.big.pred %large
    return %a, %b, %c : !idr.nat, !idr.nat, !idr.nat
  }
  // The operands of each row, the last the default one: the row the byte
  // chose, known only at run time.
  idr.func @rows(%row: i64) -> (!idr.nat) {
    %r:1 = idr.match_lit %row : i64 -> (!idr.nat) {
    case 0 {
      %p = idr.constant !idr.nat #idr.big<1>
      idr.yield %p : !idr.nat
    }
    case 1 {
      %p = idr.constant !idr.nat #idr.big<2>
      idr.yield %p : !idr.nat
    }
    case 2 {
      %p = idr.constant !idr.nat #idr.big<5>
      idr.yield %p : !idr.nat
    }
    case 3 {
      %p = idr.constant !idr.nat #idr.big<4611686018427387903>
      idr.yield %p : !idr.nat
    }
    case 4 {
      %p = idr.constant !idr.nat #idr.big<4611686018427387904>
      idr.yield %p : !idr.nat
    }
    case 5 {
      %p = idr.constant !idr.nat #idr.big<4611686018427387905>
      idr.yield %p : !idr.nat
    }
    case 6 {
      %p = idr.constant !idr.nat #idr.big<9223372036854775808>
      idr.yield %p : !idr.nat
    }
    case 7 {
      %p = idr.constant !idr.nat #idr.big<9223372036854775809>
      idr.yield %p : !idr.nat
    }
    case 8 {
      %p = idr.constant !idr.nat #idr.big<18446744073709551615>
      idr.yield %p : !idr.nat
    }
    case 9 {
      %p = idr.constant !idr.nat #idr.big<18446744073709551616>
      idr.yield %p : !idr.nat
    }
    case 10 {
      %p = idr.constant !idr.nat #idr.big<18446744073709551617>
      idr.yield %p : !idr.nat
    }
    case 11 {
      %p = idr.constant !idr.nat #idr.big<1000000000000000000000000000000>
      idr.yield %p : !idr.nat
    }
    case 12 {
      %p = idr.constant !idr.nat #idr.big<1000000000000000000000000000001>
      idr.yield %p : !idr.nat
    }
    default(%other: i64) {
      %p = idr.constant !idr.nat #idr.big<3>
      idr.yield %p : !idr.nat
    }
    }
    return %r#0 : !idr.nat
  }
  // Each row's results, computed at run time from the row @rows chose.
  idr.func @at_run_time(%row: i64) -> (!idr.nat, !idr.nat) {
    %p = idr.call @rows(%row) : (i64) -> (!idr.nat)
    %d = idr.big.pred %p
    return %p, %d : !idr.nat, !idr.nat
  }
  // Each row's results on its constants, which the folders compute.
  idr.func @folded(%row: i64) -> (!idr.nat, !idr.nat) {
    %r:2 = idr.match_lit %row : i64 -> (!idr.nat, !idr.nat) {
    case 0 {
      %p = idr.constant !idr.nat #idr.big<1>
      %d = idr.big.pred %p
      idr.yield %p, %d : !idr.nat, !idr.nat
    }
    case 1 {
      %p = idr.constant !idr.nat #idr.big<2>
      %d = idr.big.pred %p
      idr.yield %p, %d : !idr.nat, !idr.nat
    }
    case 2 {
      %p = idr.constant !idr.nat #idr.big<5>
      %d = idr.big.pred %p
      idr.yield %p, %d : !idr.nat, !idr.nat
    }
    case 3 {
      %p = idr.constant !idr.nat #idr.big<4611686018427387903>
      %d = idr.big.pred %p
      idr.yield %p, %d : !idr.nat, !idr.nat
    }
    case 4 {
      %p = idr.constant !idr.nat #idr.big<4611686018427387904>
      %d = idr.big.pred %p
      idr.yield %p, %d : !idr.nat, !idr.nat
    }
    case 5 {
      %p = idr.constant !idr.nat #idr.big<4611686018427387905>
      %d = idr.big.pred %p
      idr.yield %p, %d : !idr.nat, !idr.nat
    }
    case 6 {
      %p = idr.constant !idr.nat #idr.big<9223372036854775808>
      %d = idr.big.pred %p
      idr.yield %p, %d : !idr.nat, !idr.nat
    }
    case 7 {
      %p = idr.constant !idr.nat #idr.big<9223372036854775809>
      %d = idr.big.pred %p
      idr.yield %p, %d : !idr.nat, !idr.nat
    }
    case 8 {
      %p = idr.constant !idr.nat #idr.big<18446744073709551615>
      %d = idr.big.pred %p
      idr.yield %p, %d : !idr.nat, !idr.nat
    }
    case 9 {
      %p = idr.constant !idr.nat #idr.big<18446744073709551616>
      %d = idr.big.pred %p
      idr.yield %p, %d : !idr.nat, !idr.nat
    }
    case 10 {
      %p = idr.constant !idr.nat #idr.big<18446744073709551617>
      %d = idr.big.pred %p
      idr.yield %p, %d : !idr.nat, !idr.nat
    }
    case 11 {
      %p = idr.constant !idr.nat #idr.big<1000000000000000000000000000000>
      %d = idr.big.pred %p
      idr.yield %p, %d : !idr.nat, !idr.nat
    }
    case 12 {
      %p = idr.constant !idr.nat #idr.big<1000000000000000000000000000001>
      %d = idr.big.pred %p
      idr.yield %p, %d : !idr.nat, !idr.nat
    }
    default(%other: i64) {
      %p = idr.constant !idr.nat #idr.big<3>
      %d = idr.big.pred %p
      idr.yield %p, %d : !idr.nat, !idr.nat
    }
    }
    return %r#0, %r#1 : !idr.nat, !idr.nat
  }
  // The program: the results of the row the byte read chooses, folded,
  // or, in the run form, computed at run time.
  idr.func @Prog.main(%w0: !idr.world) -> !idr.world {
    %byte, %w1 = idr.io.get_byte %w0
    %row = arith.extui %byte : i32 to i64
    %p, %d = idr.call @folded(%row) : (i64) -> (!idr.nat, !idr.nat)
    %space = arith.constant 32 : i32
    %newline = arith.constant 10 : i32
    %p.big = idr.nat.to_big %p
    %p.big.text = idr.big.show %p.big
    %w2 = idr.io.put_str %p.big.text, %w1
    %w3 = idr.io.put_char %space, %w2
    %d.big = idr.nat.to_big %d
    %d.big.text = idr.big.show %d.big
    %w4 = idr.io.put_str %d.big.text, %w3
    %w5 = idr.io.put_char %newline, %w4
    return %w5 : !idr.world
  }
}
