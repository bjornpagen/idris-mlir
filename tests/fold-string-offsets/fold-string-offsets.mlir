// RUN: idris-mlir-opt %s --mlir-disable-threading --canonicalize '--idr-expect=holds=folds-balanced,returns=@offsets:104/104/233/233/0/0/128512/"h\C3\A9llo"/"\C3\A9llo"/"llo"/""/""/"\F0\9F\98\80b",folded=@folded' -o /dev/null
// RUN: sed 's/idr.call @folded(/idr.call @at_run_time(/' %s > %t.run.mlir
// RUN: %differential %t.run.mlir %s
// RUN: sed 's/%i = arith.constant 100 : i64/%i = arith.constant 4 : i64/' %s > %t.wrong.mlir
// RUN: not %differential %t.run.mlir %t.wrong.mlir 2>&1 | FileCheck %s --check-prefix=WRONG
// A string read by byte offset folds at every constant offset, since each
// offset has a meaning: below 0 is the start, past the end is the end, and
// an offset inside a character's encoding stands for that character's
// start. At the end there is no character (0), and nothing is left.
// Dropping no bytes gives the string itself and every byte the empty
// string, each with a reference the folder releases. "h\C3\A9llo" is h,
// U+00E9 in two bytes and llo; "a\F0\9F\98\80b" is a, U+1F600 in four
// bytes and b.
//
// The runtime's reads at run time are the oracle for every row of the
// table: each row folds in its own region (@folded), and is computed at
// run time from the row the byte read chose (@at_run_time, which the sed
// makes the program's). On the byte of each row, and on the empty input
// for the last, the two print the same: the row's operands, then its
// results; each operand is printed as well as used, so that no op on it is
// its one consumer, which case-of-case would move into the rows, where the
// run form would fold too. The rows: an offset at each byte of a two-byte
// and of a four-byte character and on each side of it, at the end and past
// it, below 0, the most negative and most positive Int, the empty string,
// and a three-byte character first. A wrong fold is found on its row: the
// sed makes row 6's offset 4, where the run reads at 100.
// WRONG: differential: {{.*}}run.mlir and {{.*}}wrong.mlir differ on '\0006'
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
// STDIN:
idr.program @"string-offsets" root(@Prog.main) stage(first) {
  idr.func @offsets() -> (i32, i32, i32, i32, i32, i32, i32,
                           !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str) {
    %s = idr.constant !idr.str "h\C3\A9llo"
    %t = idr.constant !idr.str "a\F0\9F\98\80b"
    %m4 = arith.constant -4 : i64
    %m3 = arith.constant -3 : i64
    %c0 = arith.constant 0 : i64
    %c1 = arith.constant 1 : i64
    %c2 = arith.constant 2 : i64
    %c3 = arith.constant 3 : i64
    %c4 = arith.constant 4 : i64
    %c6 = arith.constant 6 : i64
    %c99 = arith.constant 99 : i64
    %c100 = arith.constant 100 : i64
    %a0 = idr.str.scalar_at %s, %m3
    %a1 = idr.str.scalar_at %s, %c0
    %a2 = idr.str.scalar_at %s, %c1
    %a3 = idr.str.scalar_at %s, %c2
    %a4 = idr.str.scalar_at %s, %c6
    %a5 = idr.str.scalar_at %s, %c100
    %a6 = idr.str.scalar_at %t, %c3
    %d0 = idr.str.drop_bytes %s, %m4
    %d1 = idr.str.drop_bytes %s, %c2
    %d2 = idr.str.drop_bytes %s, %c3
    %d3 = idr.str.drop_bytes %s, %c6
    %d4 = idr.str.drop_bytes %s, %c99
    %d5 = idr.str.drop_bytes %t, %c4
    return %a0, %a1, %a2, %a3, %a4, %a5, %a6,
           %d0, %d1, %d2, %d3, %d4, %d5
        : i32, i32, i32, i32, i32, i32, i32,
          !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str
  }
  // The operands of each row, the last the default one: the row the byte
  // chose, known only at run time.
  idr.func @rows(%row: i64) -> (!idr.str, i64) {
    %r:2 = idr.match_lit %row : i64 -> (!idr.str, i64) {
    case 0 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant -3 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 1 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant 0 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 2 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant 1 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 3 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant 2 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 4 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant 3 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 5 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant 6 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 6 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant 100 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 7 {
      %s = idr.constant !idr.str "a\F0\9F\98\80b"
      %i = arith.constant 1 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 8 {
      %s = idr.constant !idr.str "a\F0\9F\98\80b"
      %i = arith.constant 2 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 9 {
      %s = idr.constant !idr.str "a\F0\9F\98\80b"
      %i = arith.constant 3 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 10 {
      %s = idr.constant !idr.str "a\F0\9F\98\80b"
      %i = arith.constant 4 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 11 {
      %s = idr.constant !idr.str "a\F0\9F\98\80b"
      %i = arith.constant 5 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 12 {
      %s = idr.constant !idr.str "a\F0\9F\98\80b"
      %i = arith.constant 6 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 13 {
      %s = idr.constant !idr.str ""
      %i = arith.constant 0 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 14 {
      %s = idr.constant !idr.str ""
      %i = arith.constant -1 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 15 {
      %s = idr.constant !idr.str "\E2\82\ACx"
      %i = arith.constant 1 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 16 {
      %s = idr.constant !idr.str "\E2\82\ACx"
      %i = arith.constant 3 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 17 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant -9223372036854775808 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    case 18 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant 9223372036854775807 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    default(%other: i64) {
      %s = idr.constant !idr.str "a\F0\9F\98\80b"
      %i = arith.constant -4 : i64
      idr.yield %s, %i : !idr.str, i64
    }
    }
    return %r#0, %r#1 : !idr.str, i64
  }
  // Each row's results, computed at run time from the row @rows chose.
  idr.func @at_run_time(%row: i64) -> (!idr.str, i64, i32, !idr.str) {
    %s, %i = idr.call @rows(%row) : (i64) -> (!idr.str, i64)
    %a = idr.str.scalar_at %s, %i
    %d = idr.str.drop_bytes %s, %i
    return %s, %i, %a, %d : !idr.str, i64, i32, !idr.str
  }
  // Each row's results on its constants, which the folders compute.
  idr.func @folded(%row: i64) -> (!idr.str, i64, i32, !idr.str) {
    %r:4 = idr.match_lit %row : i64 -> (!idr.str, i64, i32, !idr.str) {
    case 0 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant -3 : i64
      %a = idr.str.scalar_at %s, %i
      %d = idr.str.drop_bytes %s, %i
      idr.yield %s, %i, %a, %d : !idr.str, i64, i32, !idr.str
    }
    case 1 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant 0 : i64
      %a = idr.str.scalar_at %s, %i
      %d = idr.str.drop_bytes %s, %i
      idr.yield %s, %i, %a, %d : !idr.str, i64, i32, !idr.str
    }
    case 2 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant 1 : i64
      %a = idr.str.scalar_at %s, %i
      %d = idr.str.drop_bytes %s, %i
      idr.yield %s, %i, %a, %d : !idr.str, i64, i32, !idr.str
    }
    case 3 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant 2 : i64
      %a = idr.str.scalar_at %s, %i
      %d = idr.str.drop_bytes %s, %i
      idr.yield %s, %i, %a, %d : !idr.str, i64, i32, !idr.str
    }
    case 4 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant 3 : i64
      %a = idr.str.scalar_at %s, %i
      %d = idr.str.drop_bytes %s, %i
      idr.yield %s, %i, %a, %d : !idr.str, i64, i32, !idr.str
    }
    case 5 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant 6 : i64
      %a = idr.str.scalar_at %s, %i
      %d = idr.str.drop_bytes %s, %i
      idr.yield %s, %i, %a, %d : !idr.str, i64, i32, !idr.str
    }
    case 6 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant 100 : i64
      %a = idr.str.scalar_at %s, %i
      %d = idr.str.drop_bytes %s, %i
      idr.yield %s, %i, %a, %d : !idr.str, i64, i32, !idr.str
    }
    case 7 {
      %s = idr.constant !idr.str "a\F0\9F\98\80b"
      %i = arith.constant 1 : i64
      %a = idr.str.scalar_at %s, %i
      %d = idr.str.drop_bytes %s, %i
      idr.yield %s, %i, %a, %d : !idr.str, i64, i32, !idr.str
    }
    case 8 {
      %s = idr.constant !idr.str "a\F0\9F\98\80b"
      %i = arith.constant 2 : i64
      %a = idr.str.scalar_at %s, %i
      %d = idr.str.drop_bytes %s, %i
      idr.yield %s, %i, %a, %d : !idr.str, i64, i32, !idr.str
    }
    case 9 {
      %s = idr.constant !idr.str "a\F0\9F\98\80b"
      %i = arith.constant 3 : i64
      %a = idr.str.scalar_at %s, %i
      %d = idr.str.drop_bytes %s, %i
      idr.yield %s, %i, %a, %d : !idr.str, i64, i32, !idr.str
    }
    case 10 {
      %s = idr.constant !idr.str "a\F0\9F\98\80b"
      %i = arith.constant 4 : i64
      %a = idr.str.scalar_at %s, %i
      %d = idr.str.drop_bytes %s, %i
      idr.yield %s, %i, %a, %d : !idr.str, i64, i32, !idr.str
    }
    case 11 {
      %s = idr.constant !idr.str "a\F0\9F\98\80b"
      %i = arith.constant 5 : i64
      %a = idr.str.scalar_at %s, %i
      %d = idr.str.drop_bytes %s, %i
      idr.yield %s, %i, %a, %d : !idr.str, i64, i32, !idr.str
    }
    case 12 {
      %s = idr.constant !idr.str "a\F0\9F\98\80b"
      %i = arith.constant 6 : i64
      %a = idr.str.scalar_at %s, %i
      %d = idr.str.drop_bytes %s, %i
      idr.yield %s, %i, %a, %d : !idr.str, i64, i32, !idr.str
    }
    case 13 {
      %s = idr.constant !idr.str ""
      %i = arith.constant 0 : i64
      %a = idr.str.scalar_at %s, %i
      %d = idr.str.drop_bytes %s, %i
      idr.yield %s, %i, %a, %d : !idr.str, i64, i32, !idr.str
    }
    case 14 {
      %s = idr.constant !idr.str ""
      %i = arith.constant -1 : i64
      %a = idr.str.scalar_at %s, %i
      %d = idr.str.drop_bytes %s, %i
      idr.yield %s, %i, %a, %d : !idr.str, i64, i32, !idr.str
    }
    case 15 {
      %s = idr.constant !idr.str "\E2\82\ACx"
      %i = arith.constant 1 : i64
      %a = idr.str.scalar_at %s, %i
      %d = idr.str.drop_bytes %s, %i
      idr.yield %s, %i, %a, %d : !idr.str, i64, i32, !idr.str
    }
    case 16 {
      %s = idr.constant !idr.str "\E2\82\ACx"
      %i = arith.constant 3 : i64
      %a = idr.str.scalar_at %s, %i
      %d = idr.str.drop_bytes %s, %i
      idr.yield %s, %i, %a, %d : !idr.str, i64, i32, !idr.str
    }
    case 17 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant -9223372036854775808 : i64
      %a = idr.str.scalar_at %s, %i
      %d = idr.str.drop_bytes %s, %i
      idr.yield %s, %i, %a, %d : !idr.str, i64, i32, !idr.str
    }
    case 18 {
      %s = idr.constant !idr.str "h\C3\A9llo"
      %i = arith.constant 9223372036854775807 : i64
      %a = idr.str.scalar_at %s, %i
      %d = idr.str.drop_bytes %s, %i
      idr.yield %s, %i, %a, %d : !idr.str, i64, i32, !idr.str
    }
    default(%other: i64) {
      %s = idr.constant !idr.str "a\F0\9F\98\80b"
      %i = arith.constant -4 : i64
      %a = idr.str.scalar_at %s, %i
      %d = idr.str.drop_bytes %s, %i
      idr.yield %s, %i, %a, %d : !idr.str, i64, i32, !idr.str
    }
    }
    return %r#0, %r#1, %r#2, %r#3 : !idr.str, i64, i32, !idr.str
  }
  // The program: the results of the row the byte read chooses, folded,
  // or, in the run form, computed at run time.
  idr.func @Prog.main(%w0: !idr.world) -> !idr.world {
    %byte, %w1 = idr.io.get_byte %w0
    %row = arith.extui %byte : i32 to i64
    %s, %i, %a, %d = idr.call @folded(%row) : (i64) -> (!idr.str, i64, i32, !idr.str)
    %space = arith.constant 32 : i32
    %newline = arith.constant 10 : i32
    %w2 = idr.io.put_str %s, %w1
    %w3 = idr.io.put_char %space, %w2
    %w4 = idr.io.put_sint %i, %w3 : i64
    %w5 = idr.io.put_char %space, %w4
    %w6 = idr.io.put_sint %a, %w5 : i32
    %w7 = idr.io.put_char %space, %w6
    %w8 = idr.io.put_str %d, %w7
    %w9 = idr.io.put_char %newline, %w8
    return %w9 : !idr.world
  }
}
