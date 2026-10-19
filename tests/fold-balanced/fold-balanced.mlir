// RUN: idris-mlir-opt %s --canonicalize '--idr-expect=holds=folds-balanced,returns=@folds:"abc"/"abc"/""/#idr.big<-123456789012345678901234567890>,returns=@more:"cba"/#idr.big<98765432109876543210>,folded=@folded' -o /dev/null
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(canonicalize)),idr-expect{holds=folds-balanced})' -o /dev/null
// RUN: sed 's/idr.call @folded(/idr.call @at_run_time(/' %s > %t.run.mlir
// RUN: %differential %t.run.mlir %s
// RUN: sed 's/%b = idr.constant !idr.str "ba"/%b = idr.constant !idr.str "ab"/' %s > %t.wrong.mlir
// RUN: not %differential %t.run.mlir %t.wrong.mlir 2>&1 | FileCheck %s --check-prefix=WRONG
// The folders own what the runtime returns and release each reference
// once, also when an operation returns one of its arguments with one more
// reference: appending the empty string, reversing an empty one. No fold
// leaves a cell live. The count is per fold, whatever thread folds: the
// second run folds the functions on the pool's threads and checks on the
// main one, which shows that folding elsewhere does not fail the check. No
// folder leaks, so no fixture shows a leak on another thread being seen.
//
// The runtime's append, reverse and negation at run time are the oracle
// for every row of the table: each row folds in its own region (@folded),
// and is computed at run time from the row the byte read chose
// (@at_run_time, which the sed makes the program's). On the byte of each
// row, and on the empty input for the last, the two print the same: the
// row's operands, then its results; each operand is printed as well as
// used, so that no op on it is its one consumer, which case-of-case would
// move into the rows, where the run form would fold too. The rows: the
// empty string on either side and both, characters of two and four bytes,
// which reverse whole, palindromes, and Integers at 0, -1 and 1, at the
// edges of the runtime's small integers and of a word, and of more than a
// word; the append's length is printed too, so that it is built and not
// only written in pieces; the first two lines ask that every row's folds
// be balanced too. A wrong fold is found on its row: the sed makes row 9's
// second string "ab", where the run reverses "ba".
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
// STDIN:
idr.program @balanced root(@Prog.main) stage(first) {
  idr.func @folds() -> (!idr.str, !idr.str, !idr.str, !idr.big) {
    %e = idr.constant !idr.str ""
    %x = idr.constant !idr.str "abc"
    %a = idr.str.append %e, %x
    %b = idr.str.append %x, %e
    %r = idr.str.reverse %e
    %big = idr.constant !idr.big #idr.big<123456789012345678901234567890>
    %n = idr.big.neg %big
    return %a, %b, %r, %n : !idr.str, !idr.str, !idr.str, !idr.big
  }

  idr.func @more() -> (!idr.str, !idr.big) {
    %x = idr.constant !idr.str "abc"
    %r = idr.str.reverse %x
    %big = idr.constant !idr.big #idr.big<-98765432109876543210>
    %n = idr.big.neg %big
    return %r, %n : !idr.str, !idr.big
  }
  // The operands of each row, the last the default one: the row the byte
  // chose, known only at run time.
  idr.func @rows(%row: i64) -> (!idr.str, !idr.str, !idr.big) {
    %r:3 = idr.match_lit %row : i64 -> (!idr.str, !idr.str, !idr.big) {
    case 0 {
      %a = idr.constant !idr.str ""
      %b = idr.constant !idr.str "abc"
      %n = idr.constant !idr.big #idr.big<123456789012345678901234567890>
      idr.yield %a, %b, %n : !idr.str, !idr.str, !idr.big
    }
    case 1 {
      %a = idr.constant !idr.str "abc"
      %b = idr.constant !idr.str ""
      %n = idr.constant !idr.big #idr.big<-98765432109876543210>
      idr.yield %a, %b, %n : !idr.str, !idr.str, !idr.big
    }
    case 2 {
      %a = idr.constant !idr.str ""
      %b = idr.constant !idr.str ""
      %n = idr.constant !idr.big #idr.big<0>
      idr.yield %a, %b, %n : !idr.str, !idr.str, !idr.big
    }
    case 3 {
      %a = idr.constant !idr.str "\C3\A9"
      %b = idr.constant !idr.str "\F0\9F\98\80"
      %n = idr.constant !idr.big #idr.big<4611686018427387904>
      idr.yield %a, %b, %n : !idr.str, !idr.str, !idr.big
    }
    case 4 {
      %a = idr.constant !idr.str "x"
      %b = idr.constant !idr.str "y"
      %n = idr.constant !idr.big #idr.big<-4611686018427387904>
      idr.yield %a, %b, %n : !idr.str, !idr.str, !idr.big
    }
    case 5 {
      %a = idr.constant !idr.str "\C3\A9a"
      %b = idr.constant !idr.str ""
      %n = idr.constant !idr.big #idr.big<-9223372036854775808>
      idr.yield %a, %b, %n : !idr.str, !idr.str, !idr.big
    }
    case 6 {
      %a = idr.constant !idr.str "abc"
      %b = idr.constant !idr.str "def"
      %n = idr.constant !idr.big #idr.big<9223372036854775807>
      idr.yield %a, %b, %n : !idr.str, !idr.str, !idr.big
    }
    case 7 {
      %a = idr.constant !idr.str "\F0\9F\98\80b"
      %b = idr.constant !idr.str "a\C3\A9"
      %n = idr.constant !idr.big #idr.big<1>
      idr.yield %a, %b, %n : !idr.str, !idr.str, !idr.big
    }
    case 8 {
      %a = idr.constant !idr.str "a"
      %b = idr.constant !idr.str "\F0\9F\98\80"
      %n = idr.constant !idr.big #idr.big<-1>
      idr.yield %a, %b, %n : !idr.str, !idr.str, !idr.big
    }
    case 9 {
      %a = idr.constant !idr.str "ab"
      %b = idr.constant !idr.str "ba"
      %n = idr.constant !idr.big #idr.big<4611686018427387903>
      idr.yield %a, %b, %n : !idr.str, !idr.str, !idr.big
    }
    default(%other: i64) {
      %a = idr.constant !idr.str "z"
      %b = idr.constant !idr.str "z"
      %n = idr.constant !idr.big #idr.big<-4611686018427387905>
      idr.yield %a, %b, %n : !idr.str, !idr.str, !idr.big
    }
    }
    return %r#0, %r#1, %r#2 : !idr.str, !idr.str, !idr.big
  }
  // Each row's results, computed at run time from the row @rows chose.
  idr.func @at_run_time(%row: i64) -> (!idr.str, !idr.str, !idr.big, !idr.str, i64, !idr.str, !idr.str, !idr.big) {
    %a, %b, %n = idr.call @rows(%row) : (i64) -> (!idr.str, !idr.str, !idr.big)
    %ab = idr.str.append %a, %b
    %nab = idr.str.length %ab
    %ra = idr.str.reverse %a
    %rb = idr.str.reverse %b
    %m = idr.big.neg %n
    return %a, %b, %n, %ab, %nab, %ra, %rb, %m : !idr.str, !idr.str, !idr.big, !idr.str, i64, !idr.str, !idr.str, !idr.big
  }
  // Each row's results on its constants, which the folders compute.
  idr.func @folded(%row: i64) -> (!idr.str, !idr.str, !idr.big, !idr.str, i64, !idr.str, !idr.str, !idr.big) {
    %r:8 = idr.match_lit %row : i64 -> (!idr.str, !idr.str, !idr.big, !idr.str, i64, !idr.str, !idr.str, !idr.big) {
    case 0 {
      %a = idr.constant !idr.str ""
      %b = idr.constant !idr.str "abc"
      %n = idr.constant !idr.big #idr.big<123456789012345678901234567890>
      %ab = idr.str.append %a, %b
      %nab = idr.str.length %ab
      %ra = idr.str.reverse %a
      %rb = idr.str.reverse %b
      %m = idr.big.neg %n
      idr.yield %a, %b, %n, %ab, %nab, %ra, %rb, %m : !idr.str, !idr.str, !idr.big, !idr.str, i64, !idr.str, !idr.str, !idr.big
    }
    case 1 {
      %a = idr.constant !idr.str "abc"
      %b = idr.constant !idr.str ""
      %n = idr.constant !idr.big #idr.big<-98765432109876543210>
      %ab = idr.str.append %a, %b
      %nab = idr.str.length %ab
      %ra = idr.str.reverse %a
      %rb = idr.str.reverse %b
      %m = idr.big.neg %n
      idr.yield %a, %b, %n, %ab, %nab, %ra, %rb, %m : !idr.str, !idr.str, !idr.big, !idr.str, i64, !idr.str, !idr.str, !idr.big
    }
    case 2 {
      %a = idr.constant !idr.str ""
      %b = idr.constant !idr.str ""
      %n = idr.constant !idr.big #idr.big<0>
      %ab = idr.str.append %a, %b
      %nab = idr.str.length %ab
      %ra = idr.str.reverse %a
      %rb = idr.str.reverse %b
      %m = idr.big.neg %n
      idr.yield %a, %b, %n, %ab, %nab, %ra, %rb, %m : !idr.str, !idr.str, !idr.big, !idr.str, i64, !idr.str, !idr.str, !idr.big
    }
    case 3 {
      %a = idr.constant !idr.str "\C3\A9"
      %b = idr.constant !idr.str "\F0\9F\98\80"
      %n = idr.constant !idr.big #idr.big<4611686018427387904>
      %ab = idr.str.append %a, %b
      %nab = idr.str.length %ab
      %ra = idr.str.reverse %a
      %rb = idr.str.reverse %b
      %m = idr.big.neg %n
      idr.yield %a, %b, %n, %ab, %nab, %ra, %rb, %m : !idr.str, !idr.str, !idr.big, !idr.str, i64, !idr.str, !idr.str, !idr.big
    }
    case 4 {
      %a = idr.constant !idr.str "x"
      %b = idr.constant !idr.str "y"
      %n = idr.constant !idr.big #idr.big<-4611686018427387904>
      %ab = idr.str.append %a, %b
      %nab = idr.str.length %ab
      %ra = idr.str.reverse %a
      %rb = idr.str.reverse %b
      %m = idr.big.neg %n
      idr.yield %a, %b, %n, %ab, %nab, %ra, %rb, %m : !idr.str, !idr.str, !idr.big, !idr.str, i64, !idr.str, !idr.str, !idr.big
    }
    case 5 {
      %a = idr.constant !idr.str "\C3\A9a"
      %b = idr.constant !idr.str ""
      %n = idr.constant !idr.big #idr.big<-9223372036854775808>
      %ab = idr.str.append %a, %b
      %nab = idr.str.length %ab
      %ra = idr.str.reverse %a
      %rb = idr.str.reverse %b
      %m = idr.big.neg %n
      idr.yield %a, %b, %n, %ab, %nab, %ra, %rb, %m : !idr.str, !idr.str, !idr.big, !idr.str, i64, !idr.str, !idr.str, !idr.big
    }
    case 6 {
      %a = idr.constant !idr.str "abc"
      %b = idr.constant !idr.str "def"
      %n = idr.constant !idr.big #idr.big<9223372036854775807>
      %ab = idr.str.append %a, %b
      %nab = idr.str.length %ab
      %ra = idr.str.reverse %a
      %rb = idr.str.reverse %b
      %m = idr.big.neg %n
      idr.yield %a, %b, %n, %ab, %nab, %ra, %rb, %m : !idr.str, !idr.str, !idr.big, !idr.str, i64, !idr.str, !idr.str, !idr.big
    }
    case 7 {
      %a = idr.constant !idr.str "\F0\9F\98\80b"
      %b = idr.constant !idr.str "a\C3\A9"
      %n = idr.constant !idr.big #idr.big<1>
      %ab = idr.str.append %a, %b
      %nab = idr.str.length %ab
      %ra = idr.str.reverse %a
      %rb = idr.str.reverse %b
      %m = idr.big.neg %n
      idr.yield %a, %b, %n, %ab, %nab, %ra, %rb, %m : !idr.str, !idr.str, !idr.big, !idr.str, i64, !idr.str, !idr.str, !idr.big
    }
    case 8 {
      %a = idr.constant !idr.str "a"
      %b = idr.constant !idr.str "\F0\9F\98\80"
      %n = idr.constant !idr.big #idr.big<-1>
      %ab = idr.str.append %a, %b
      %nab = idr.str.length %ab
      %ra = idr.str.reverse %a
      %rb = idr.str.reverse %b
      %m = idr.big.neg %n
      idr.yield %a, %b, %n, %ab, %nab, %ra, %rb, %m : !idr.str, !idr.str, !idr.big, !idr.str, i64, !idr.str, !idr.str, !idr.big
    }
    case 9 {
      %a = idr.constant !idr.str "ab"
      %b = idr.constant !idr.str "ba"
      %n = idr.constant !idr.big #idr.big<4611686018427387903>
      %ab = idr.str.append %a, %b
      %nab = idr.str.length %ab
      %ra = idr.str.reverse %a
      %rb = idr.str.reverse %b
      %m = idr.big.neg %n
      idr.yield %a, %b, %n, %ab, %nab, %ra, %rb, %m : !idr.str, !idr.str, !idr.big, !idr.str, i64, !idr.str, !idr.str, !idr.big
    }
    default(%other: i64) {
      %a = idr.constant !idr.str "z"
      %b = idr.constant !idr.str "z"
      %n = idr.constant !idr.big #idr.big<-4611686018427387905>
      %ab = idr.str.append %a, %b
      %nab = idr.str.length %ab
      %ra = idr.str.reverse %a
      %rb = idr.str.reverse %b
      %m = idr.big.neg %n
      idr.yield %a, %b, %n, %ab, %nab, %ra, %rb, %m : !idr.str, !idr.str, !idr.big, !idr.str, i64, !idr.str, !idr.str, !idr.big
    }
    }
    return %r#0, %r#1, %r#2, %r#3, %r#4, %r#5, %r#6, %r#7 : !idr.str, !idr.str, !idr.big, !idr.str, i64, !idr.str, !idr.str, !idr.big
  }
  // The program: the results of the row the byte read chooses, folded,
  // or, in the run form, computed at run time.
  idr.func @Prog.main(%w0: !idr.world) -> !idr.world {
    %byte, %w1 = idr.io.get_byte %w0
    %row = arith.extui %byte : i32 to i64
    %a, %b, %n, %ab, %nab, %ra, %rb, %m = idr.call @folded(%row) : (i64) -> (!idr.str, !idr.str, !idr.big, !idr.str, i64, !idr.str, !idr.str, !idr.big)
    %space = arith.constant 32 : i32
    %newline = arith.constant 10 : i32
    %w2 = idr.io.put_str %a, %w1
    %w3 = idr.io.put_char %space, %w2
    %w4 = idr.io.put_str %b, %w3
    %w5 = idr.io.put_char %space, %w4
    %n.text = idr.big.show %n
    %w6 = idr.io.put_str %n.text, %w5
    %w7 = idr.io.put_char %space, %w6
    %w8 = idr.io.put_str %ab, %w7
    %w9 = idr.io.put_char %space, %w8
    %w10 = idr.io.put_sint %nab, %w9 : i64
    %w11 = idr.io.put_char %space, %w10
    %w12 = idr.io.put_str %ra, %w11
    %w13 = idr.io.put_char %space, %w12
    %w14 = idr.io.put_str %rb, %w13
    %w15 = idr.io.put_char %space, %w14
    %m.text = idr.big.show %m
    %w16 = idr.io.put_str %m.text, %w15
    %w17 = idr.io.put_char %newline, %w16
    return %w17 : !idr.world
  }
}
