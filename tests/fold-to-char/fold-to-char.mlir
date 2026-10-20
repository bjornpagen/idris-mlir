// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns=@chars:955/0/0/200,folded=@folded -o /dev/null
// RUN: sed 's/idr.call @folded(/idr.call @at_run_time(/' %s > %t.run.mlir
// RUN: %differential %t.run.mlir %s
// RUN: sed 's/%x = arith.constant 57344 : i64/%x = arith.constant 57345 : i64/' %s > %t.wrong.mlir
// RUN: not %differential %t.run.mlir %t.wrong.mlir 2>&1 | FileCheck %s --check-prefix=WRONG
// A cast to Char folds to the character, or to 0 for what is no character:
// a surrogate, a negative value, one past U+10FFFF.
//
// The casts the lowering computes, a second implementation of that
// meaning, are the oracle for every row of the table: each row folds in
// its own region (@folded), and is computed at run time from the row the
// byte read chose (@at_run_time, which the sed makes the program's). On
// the byte of each row, and on the empty input for the last, the two print
// the same: the row's operands, then its results; each operand is printed
// as well as used, so that no op on it is its one consumer, which case-of-
// case would move into the rows, where the run form would fold too. The
// rows: 0, 127 and 128, both ends of the surrogates and one outside each,
// U+10FFFF and one past it, -1, the most negative and most positive Int, a
// value whose low 32 bits are a character, and bytes past 127, read as
// unsigned and as signed. A wrong fold is found on its row: the sed makes
// row 3's value 57345, where the run casts 57344.
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
// STDIN: \0011
// STDIN: \0012
// STDIN: \0013
// STDIN: \0014
// STDIN: \0015
// STDIN: \0016
// STDIN:
idr.program @"to-char" root(@Prog.main) stage(first) types #idr.types<> {
  idr.func @chars() -> (i32, i32, i32, i32) {
    %a = arith.constant 955 : i64
    %b = arith.constant 55296 : i64
    %c = arith.constant -5 : i64
    %d = arith.constant 200 : i8
    %ra = idr.to_char_s %a : i64
    %rb = idr.to_char_s %b : i64
    %rc = idr.to_char_s %c : i64
    %rd = idr.to_char_u %d : i8
    return %ra, %rb, %rc, %rd : i32, i32, i32, i32
  }
  // The operands of each row, the last the default one: the row the byte
  // chose, known only at run time.
  idr.func @rows(%row: i64) -> (i64, i8) {
    %r:2 = idr.match_lit %row : i64 -> (i64, i8) {
    case 0 {
      %x = arith.constant 955 : i64
      %u = arith.constant 200 : i8
      idr.yield %x, %u : i64, i8
    }
    case 1 {
      %x = arith.constant 55296 : i64
      %u = arith.constant 0 : i8
      idr.yield %x, %u : i64, i8
    }
    case 2 {
      %x = arith.constant 57343 : i64
      %u = arith.constant 127 : i8
      idr.yield %x, %u : i64, i8
    }
    case 3 {
      %x = arith.constant 57344 : i64
      %u = arith.constant 128 : i8
      idr.yield %x, %u : i64, i8
    }
    case 4 {
      %x = arith.constant 55295 : i64
      %u = arith.constant 255 : i8
      idr.yield %x, %u : i64, i8
    }
    case 5 {
      %x = arith.constant -5 : i64
      %u = arith.constant 65 : i8
      idr.yield %x, %u : i64, i8
    }
    case 6 {
      %x = arith.constant 0 : i64
      %u = arith.constant 1 : i8
      idr.yield %x, %u : i64, i8
    }
    case 7 {
      %x = arith.constant 1114111 : i64
      %u = arith.constant 254 : i8
      idr.yield %x, %u : i64, i8
    }
    case 8 {
      %x = arith.constant 1114112 : i64
      %u = arith.constant 129 : i8
      idr.yield %x, %u : i64, i8
    }
    case 9 {
      %x = arith.constant 9223372036854775807 : i64
      %u = arith.constant 127 : i8
      idr.yield %x, %u : i64, i8
    }
    case 10 {
      %x = arith.constant -9223372036854775808 : i64
      %u = arith.constant 128 : i8
      idr.yield %x, %u : i64, i8
    }
    case 11 {
      %x = arith.constant 127 : i64
      %u = arith.constant 255 : i8
      idr.yield %x, %u : i64, i8
    }
    case 12 {
      %x = arith.constant 128 : i64
      %u = arith.constant 0 : i8
      idr.yield %x, %u : i64, i8
    }
    case 13 {
      %x = arith.constant -1 : i64
      %u = arith.constant 200 : i8
      idr.yield %x, %u : i64, i8
    }
    case 14 {
      %x = arith.constant 4294967393 : i64
      %u = arith.constant 97 : i8
      idr.yield %x, %u : i64, i8
    }
    default(%other: i64) {
      %x = arith.constant 65 : i64
      %u = arith.constant 32 : i8
      idr.yield %x, %u : i64, i8
    }
    }
    return %r#0, %r#1 : i64, i8
  }
  // Each row's results, computed at run time from the row @rows chose.
  idr.func @at_run_time(%row: i64) -> (i64, i8, i32, i32, i32) {
    %x, %u = idr.call @rows(%row) : (i64) -> (i64, i8)
    %cs = idr.to_char_s %x : i64
    %cu = idr.to_char_u %u : i8
    %cb = idr.to_char_s %u : i8
    return %x, %u, %cs, %cu, %cb : i64, i8, i32, i32, i32
  }
  // Each row's results on its constants, which the folders compute.
  idr.func @folded(%row: i64) -> (i64, i8, i32, i32, i32) {
    %r:5 = idr.match_lit %row : i64 -> (i64, i8, i32, i32, i32) {
    case 0 {
      %x = arith.constant 955 : i64
      %u = arith.constant 200 : i8
      %cs = idr.to_char_s %x : i64
      %cu = idr.to_char_u %u : i8
      %cb = idr.to_char_s %u : i8
      idr.yield %x, %u, %cs, %cu, %cb : i64, i8, i32, i32, i32
    }
    case 1 {
      %x = arith.constant 55296 : i64
      %u = arith.constant 0 : i8
      %cs = idr.to_char_s %x : i64
      %cu = idr.to_char_u %u : i8
      %cb = idr.to_char_s %u : i8
      idr.yield %x, %u, %cs, %cu, %cb : i64, i8, i32, i32, i32
    }
    case 2 {
      %x = arith.constant 57343 : i64
      %u = arith.constant 127 : i8
      %cs = idr.to_char_s %x : i64
      %cu = idr.to_char_u %u : i8
      %cb = idr.to_char_s %u : i8
      idr.yield %x, %u, %cs, %cu, %cb : i64, i8, i32, i32, i32
    }
    case 3 {
      %x = arith.constant 57344 : i64
      %u = arith.constant 128 : i8
      %cs = idr.to_char_s %x : i64
      %cu = idr.to_char_u %u : i8
      %cb = idr.to_char_s %u : i8
      idr.yield %x, %u, %cs, %cu, %cb : i64, i8, i32, i32, i32
    }
    case 4 {
      %x = arith.constant 55295 : i64
      %u = arith.constant 255 : i8
      %cs = idr.to_char_s %x : i64
      %cu = idr.to_char_u %u : i8
      %cb = idr.to_char_s %u : i8
      idr.yield %x, %u, %cs, %cu, %cb : i64, i8, i32, i32, i32
    }
    case 5 {
      %x = arith.constant -5 : i64
      %u = arith.constant 65 : i8
      %cs = idr.to_char_s %x : i64
      %cu = idr.to_char_u %u : i8
      %cb = idr.to_char_s %u : i8
      idr.yield %x, %u, %cs, %cu, %cb : i64, i8, i32, i32, i32
    }
    case 6 {
      %x = arith.constant 0 : i64
      %u = arith.constant 1 : i8
      %cs = idr.to_char_s %x : i64
      %cu = idr.to_char_u %u : i8
      %cb = idr.to_char_s %u : i8
      idr.yield %x, %u, %cs, %cu, %cb : i64, i8, i32, i32, i32
    }
    case 7 {
      %x = arith.constant 1114111 : i64
      %u = arith.constant 254 : i8
      %cs = idr.to_char_s %x : i64
      %cu = idr.to_char_u %u : i8
      %cb = idr.to_char_s %u : i8
      idr.yield %x, %u, %cs, %cu, %cb : i64, i8, i32, i32, i32
    }
    case 8 {
      %x = arith.constant 1114112 : i64
      %u = arith.constant 129 : i8
      %cs = idr.to_char_s %x : i64
      %cu = idr.to_char_u %u : i8
      %cb = idr.to_char_s %u : i8
      idr.yield %x, %u, %cs, %cu, %cb : i64, i8, i32, i32, i32
    }
    case 9 {
      %x = arith.constant 9223372036854775807 : i64
      %u = arith.constant 127 : i8
      %cs = idr.to_char_s %x : i64
      %cu = idr.to_char_u %u : i8
      %cb = idr.to_char_s %u : i8
      idr.yield %x, %u, %cs, %cu, %cb : i64, i8, i32, i32, i32
    }
    case 10 {
      %x = arith.constant -9223372036854775808 : i64
      %u = arith.constant 128 : i8
      %cs = idr.to_char_s %x : i64
      %cu = idr.to_char_u %u : i8
      %cb = idr.to_char_s %u : i8
      idr.yield %x, %u, %cs, %cu, %cb : i64, i8, i32, i32, i32
    }
    case 11 {
      %x = arith.constant 127 : i64
      %u = arith.constant 255 : i8
      %cs = idr.to_char_s %x : i64
      %cu = idr.to_char_u %u : i8
      %cb = idr.to_char_s %u : i8
      idr.yield %x, %u, %cs, %cu, %cb : i64, i8, i32, i32, i32
    }
    case 12 {
      %x = arith.constant 128 : i64
      %u = arith.constant 0 : i8
      %cs = idr.to_char_s %x : i64
      %cu = idr.to_char_u %u : i8
      %cb = idr.to_char_s %u : i8
      idr.yield %x, %u, %cs, %cu, %cb : i64, i8, i32, i32, i32
    }
    case 13 {
      %x = arith.constant -1 : i64
      %u = arith.constant 200 : i8
      %cs = idr.to_char_s %x : i64
      %cu = idr.to_char_u %u : i8
      %cb = idr.to_char_s %u : i8
      idr.yield %x, %u, %cs, %cu, %cb : i64, i8, i32, i32, i32
    }
    case 14 {
      %x = arith.constant 4294967393 : i64
      %u = arith.constant 97 : i8
      %cs = idr.to_char_s %x : i64
      %cu = idr.to_char_u %u : i8
      %cb = idr.to_char_s %u : i8
      idr.yield %x, %u, %cs, %cu, %cb : i64, i8, i32, i32, i32
    }
    default(%other: i64) {
      %x = arith.constant 65 : i64
      %u = arith.constant 32 : i8
      %cs = idr.to_char_s %x : i64
      %cu = idr.to_char_u %u : i8
      %cb = idr.to_char_s %u : i8
      idr.yield %x, %u, %cs, %cu, %cb : i64, i8, i32, i32, i32
    }
    }
    return %r#0, %r#1, %r#2, %r#3, %r#4 : i64, i8, i32, i32, i32
  }
  // The program: the results of the row the byte read chooses, folded,
  // or, in the run form, computed at run time.
  idr.func @Prog.main(%w0: !idr.world) -> !idr.world {
    %byte, %w1 = idr.io.get_byte %w0
    %row = arith.extui %byte : i32 to i64
    %x, %u, %cs, %cu, %cb = idr.call @folded(%row) : (i64) -> (i64, i8, i32, i32, i32)
    %space = arith.constant 32 : i32
    %newline = arith.constant 10 : i32
    %w2 = idr.io.put_sint %x, %w1 : i64
    %w3 = idr.io.put_char %space, %w2
    %w4 = idr.io.put_uint %u, %w3 : i8
    %w5 = idr.io.put_char %space, %w4
    %w6 = idr.io.put_sint %cs, %w5 : i32
    %w7 = idr.io.put_char %space, %w6
    %w8 = idr.io.put_sint %cu, %w7 : i32
    %w9 = idr.io.put_char %space, %w8
    %w10 = idr.io.put_sint %cb, %w9 : i32
    %w11 = idr.io.put_char %newline, %w10
    return %w11 : !idr.world
  }
}
