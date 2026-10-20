// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns=@signed:0/-2/-2/-1/-9223372036854775808/0,returns=@unsigned:-112/25/0,returns-argument=@by_zero:0,folded=@folded -o /dev/null
// RUN: sed 's/idr.call @folded(/idr.call @at_run_time(/' %s > %t.run.mlir
// RUN: %differential %t.run.mlir %s
// RUN: sed 's/%u = arith.constant 64 : i8/%u = arith.constant 65 : i8/' %s > %t.wrong.mlir
// RUN: not %differential %t.run.mlir %t.wrong.mlir 2>&1 | FileCheck %s --check-prefix=WRONG
// The shifts fold to Idris's meaning for every amount: Scheme's ash
// wrapped to the width, a negative signed amount shifting the other way,
// and from the width up only the fill (0, or -1 for a negative value
// shifted right). A shift by 0 is its value.
//
// The shifts the lowering computes, a second implementation of that
// meaning, are the oracle for every row of the table: each row folds in
// its own region (@folded), and is computed at run time from the row the
// byte read chose (@at_run_time, which the sed makes the program's). On
// the byte of each row, and on the empty input for the last, the two print
// the same: the row's operands, then its results; each operand is printed
// as well as used, so that no op on it is its one consumer, which case-of-
// case would move into the rows, where the run form would fold too. The
// rows: amounts of 0, 1, the width less one, the width, past it, negative
// ones, the most negative Int (which stays negative) and the most
// positive; values of each sign and the most negative; and bytes past 127,
// read as unsigned and as signed. A wrong fold is found on its row: the
// sed makes row 11's byte 65, where the run shifts 64.
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
// STDIN:
idr.program @shift root(@Prog.main) stage(first) types #idr.types<> {
  idr.func @signed() -> (i64, i64, i64, i64, i64, i64) {
    %one = arith.constant 1 : i64
    %m8 = arith.constant -8 : i64
    %c2 = arith.constant 2 : i64
    %cm2 = arith.constant -2 : i64
    %c63 = arith.constant 63 : i64
    %c64 = arith.constant 64 : i64
    %c70 = arith.constant 70 : i64
    // 1 << 64: past the width, 0.
    %a = idr.shls %one, %c64 : i64
    // -8 << -2 is -8 >> 2.
    %b = idr.shls %m8, %cm2 : i64
    %c = idr.shrs %m8, %c2 : i64
    // A negative value shifted right past the width is its sign.
    %d = idr.shrs %m8, %c70 : i64
    // 1 << 63 wraps to the most negative Int.
    %e = idr.shls %one, %c63 : i64
    // A positive value shifted right past the width is 0.
    %f = idr.shrs %one, %c70 : i64
    return %a, %b, %c, %d, %e, %f : i64, i64, i64, i64, i64, i64
  }

  idr.func @unsigned() -> (i8, i8, i8) {
    %v = arith.constant 200 : i8
    %c1 = arith.constant 1 : i8
    %c3 = arith.constant 3 : i8
    %c9 = arith.constant 9 : i8
    // 200 << 1 is 400, wrapped to 144 (printed as the i8 -112).
    %a = idr.shlu %v, %c1 : i8
    // A right shift of an unsigned value fills with zeros.
    %b = idr.shru %v, %c3 : i8
    %c = idr.shru %v, %c9 : i8
    return %a, %b, %c : i8, i8, i8
  }

  idr.func @by_zero(%x: i64) -> i64 {
    %c0 = arith.constant 0 : i64
    %r = idr.shls %x, %c0 : i64
    return %r : i64
  }
  // The operands of each row, the last the default one: the row the byte
  // chose, known only at run time.
  idr.func @rows(%row: i64) -> (i64, i64, i8, i8) {
    %r:4 = idr.match_lit %row : i64 -> (i64, i64, i8, i8) {
    case 0 {
      %x = arith.constant 1 : i64
      %n = arith.constant 64 : i64
      %u = arith.constant 200 : i8
      %k = arith.constant 1 : i8
      idr.yield %x, %n, %u, %k : i64, i64, i8, i8
    }
    case 1 {
      %x = arith.constant -8 : i64
      %n = arith.constant -2 : i64
      %u = arith.constant 200 : i8
      %k = arith.constant 3 : i8
      idr.yield %x, %n, %u, %k : i64, i64, i8, i8
    }
    case 2 {
      %x = arith.constant -8 : i64
      %n = arith.constant 2 : i64
      %u = arith.constant 200 : i8
      %k = arith.constant 9 : i8
      idr.yield %x, %n, %u, %k : i64, i64, i8, i8
    }
    case 3 {
      %x = arith.constant -8 : i64
      %n = arith.constant 70 : i64
      %u = arith.constant 128 : i8
      %k = arith.constant 7 : i8
      idr.yield %x, %n, %u, %k : i64, i64, i8, i8
    }
    case 4 {
      %x = arith.constant 1 : i64
      %n = arith.constant 63 : i64
      %u = arith.constant 255 : i8
      %k = arith.constant 8 : i8
      idr.yield %x, %n, %u, %k : i64, i64, i8, i8
    }
    case 5 {
      %x = arith.constant 1 : i64
      %n = arith.constant 70 : i64
      %u = arith.constant 1 : i8
      %k = arith.constant 255 : i8
      idr.yield %x, %n, %u, %k : i64, i64, i8, i8
    }
    case 6 {
      %x = arith.constant -9223372036854775808 : i64
      %n = arith.constant 1 : i64
      %u = arith.constant 127 : i8
      %k = arith.constant 1 : i8
      idr.yield %x, %n, %u, %k : i64, i64, i8, i8
    }
    case 7 {
      %x = arith.constant -9223372036854775808 : i64
      %n = arith.constant -1 : i64
      %u = arith.constant 128 : i8
      %k = arith.constant 1 : i8
      idr.yield %x, %n, %u, %k : i64, i64, i8, i8
    }
    case 8 {
      %x = arith.constant 5 : i64
      %n = arith.constant -9223372036854775808 : i64
      %u = arith.constant 128 : i8
      %k = arith.constant 128 : i8
      idr.yield %x, %n, %u, %k : i64, i64, i8, i8
    }
    case 9 {
      %x = arith.constant -5 : i64
      %n = arith.constant -9223372036854775808 : i64
      %u = arith.constant 129 : i8
      %k = arith.constant 129 : i8
      idr.yield %x, %n, %u, %k : i64, i64, i8, i8
    }
    case 10 {
      %x = arith.constant 5 : i64
      %n = arith.constant 9223372036854775807 : i64
      %u = arith.constant 1 : i8
      %k = arith.constant 7 : i8
      idr.yield %x, %n, %u, %k : i64, i64, i8, i8
    }
    case 11 {
      %x = arith.constant -1 : i64
      %n = arith.constant 63 : i64
      %u = arith.constant 64 : i8
      %k = arith.constant 2 : i8
      idr.yield %x, %n, %u, %k : i64, i64, i8, i8
    }
    case 12 {
      %x = arith.constant 9223372036854775807 : i64
      %n = arith.constant 1 : i64
      %u = arith.constant 255 : i8
      %k = arith.constant 254 : i8
      idr.yield %x, %n, %u, %k : i64, i64, i8, i8
    }
    case 13 {
      %x = arith.constant -1 : i64
      %n = arith.constant -64 : i64
      %u = arith.constant 3 : i8
      %k = arith.constant 0 : i8
      idr.yield %x, %n, %u, %k : i64, i64, i8, i8
    }
    case 14 {
      %x = arith.constant -9223372036854775808 : i64
      %n = arith.constant 0 : i64
      %u = arith.constant 255 : i8
      %k = arith.constant 6 : i8
      idr.yield %x, %n, %u, %k : i64, i64, i8, i8
    }
    case 15 {
      %x = arith.constant 12345 : i64
      %n = arith.constant -65 : i64
      %u = arith.constant 129 : i8
      %k = arith.constant 127 : i8
      idr.yield %x, %n, %u, %k : i64, i64, i8, i8
    }
    default(%other: i64) {
      %x = arith.constant -7 : i64
      %n = arith.constant 1 : i64
      %u = arith.constant 200 : i8
      %k = arith.constant 0 : i8
      idr.yield %x, %n, %u, %k : i64, i64, i8, i8
    }
    }
    return %r#0, %r#1, %r#2, %r#3 : i64, i64, i8, i8
  }
  // Each row's results, computed at run time from the row @rows chose.
  idr.func @at_run_time(%row: i64) -> (i64, i64, i8, i8, i64, i64, i8, i8, i8, i8) {
    %x, %n, %u, %k = idr.call @rows(%row) : (i64) -> (i64, i64, i8, i8)
    %l = idr.shls %x, %n : i64
    %r = idr.shrs %x, %n : i64
    %lu = idr.shlu %u, %k : i8
    %ru = idr.shru %u, %k : i8
    %ls = idr.shls %u, %k : i8
    %rs = idr.shrs %u, %k : i8
    return %x, %n, %u, %k, %l, %r, %lu, %ru, %ls, %rs : i64, i64, i8, i8, i64, i64, i8, i8, i8, i8
  }
  // Each row's results on its constants, which the folders compute.
  idr.func @folded(%row: i64) -> (i64, i64, i8, i8, i64, i64, i8, i8, i8, i8) {
    %r:10 = idr.match_lit %row : i64 -> (i64, i64, i8, i8, i64, i64, i8, i8, i8, i8) {
    case 0 {
      %x = arith.constant 1 : i64
      %n = arith.constant 64 : i64
      %u = arith.constant 200 : i8
      %k = arith.constant 1 : i8
      %l = idr.shls %x, %n : i64
      %r = idr.shrs %x, %n : i64
      %lu = idr.shlu %u, %k : i8
      %ru = idr.shru %u, %k : i8
      %ls = idr.shls %u, %k : i8
      %rs = idr.shrs %u, %k : i8
      idr.yield %x, %n, %u, %k, %l, %r, %lu, %ru, %ls, %rs : i64, i64, i8, i8, i64, i64, i8, i8, i8, i8
    }
    case 1 {
      %x = arith.constant -8 : i64
      %n = arith.constant -2 : i64
      %u = arith.constant 200 : i8
      %k = arith.constant 3 : i8
      %l = idr.shls %x, %n : i64
      %r = idr.shrs %x, %n : i64
      %lu = idr.shlu %u, %k : i8
      %ru = idr.shru %u, %k : i8
      %ls = idr.shls %u, %k : i8
      %rs = idr.shrs %u, %k : i8
      idr.yield %x, %n, %u, %k, %l, %r, %lu, %ru, %ls, %rs : i64, i64, i8, i8, i64, i64, i8, i8, i8, i8
    }
    case 2 {
      %x = arith.constant -8 : i64
      %n = arith.constant 2 : i64
      %u = arith.constant 200 : i8
      %k = arith.constant 9 : i8
      %l = idr.shls %x, %n : i64
      %r = idr.shrs %x, %n : i64
      %lu = idr.shlu %u, %k : i8
      %ru = idr.shru %u, %k : i8
      %ls = idr.shls %u, %k : i8
      %rs = idr.shrs %u, %k : i8
      idr.yield %x, %n, %u, %k, %l, %r, %lu, %ru, %ls, %rs : i64, i64, i8, i8, i64, i64, i8, i8, i8, i8
    }
    case 3 {
      %x = arith.constant -8 : i64
      %n = arith.constant 70 : i64
      %u = arith.constant 128 : i8
      %k = arith.constant 7 : i8
      %l = idr.shls %x, %n : i64
      %r = idr.shrs %x, %n : i64
      %lu = idr.shlu %u, %k : i8
      %ru = idr.shru %u, %k : i8
      %ls = idr.shls %u, %k : i8
      %rs = idr.shrs %u, %k : i8
      idr.yield %x, %n, %u, %k, %l, %r, %lu, %ru, %ls, %rs : i64, i64, i8, i8, i64, i64, i8, i8, i8, i8
    }
    case 4 {
      %x = arith.constant 1 : i64
      %n = arith.constant 63 : i64
      %u = arith.constant 255 : i8
      %k = arith.constant 8 : i8
      %l = idr.shls %x, %n : i64
      %r = idr.shrs %x, %n : i64
      %lu = idr.shlu %u, %k : i8
      %ru = idr.shru %u, %k : i8
      %ls = idr.shls %u, %k : i8
      %rs = idr.shrs %u, %k : i8
      idr.yield %x, %n, %u, %k, %l, %r, %lu, %ru, %ls, %rs : i64, i64, i8, i8, i64, i64, i8, i8, i8, i8
    }
    case 5 {
      %x = arith.constant 1 : i64
      %n = arith.constant 70 : i64
      %u = arith.constant 1 : i8
      %k = arith.constant 255 : i8
      %l = idr.shls %x, %n : i64
      %r = idr.shrs %x, %n : i64
      %lu = idr.shlu %u, %k : i8
      %ru = idr.shru %u, %k : i8
      %ls = idr.shls %u, %k : i8
      %rs = idr.shrs %u, %k : i8
      idr.yield %x, %n, %u, %k, %l, %r, %lu, %ru, %ls, %rs : i64, i64, i8, i8, i64, i64, i8, i8, i8, i8
    }
    case 6 {
      %x = arith.constant -9223372036854775808 : i64
      %n = arith.constant 1 : i64
      %u = arith.constant 127 : i8
      %k = arith.constant 1 : i8
      %l = idr.shls %x, %n : i64
      %r = idr.shrs %x, %n : i64
      %lu = idr.shlu %u, %k : i8
      %ru = idr.shru %u, %k : i8
      %ls = idr.shls %u, %k : i8
      %rs = idr.shrs %u, %k : i8
      idr.yield %x, %n, %u, %k, %l, %r, %lu, %ru, %ls, %rs : i64, i64, i8, i8, i64, i64, i8, i8, i8, i8
    }
    case 7 {
      %x = arith.constant -9223372036854775808 : i64
      %n = arith.constant -1 : i64
      %u = arith.constant 128 : i8
      %k = arith.constant 1 : i8
      %l = idr.shls %x, %n : i64
      %r = idr.shrs %x, %n : i64
      %lu = idr.shlu %u, %k : i8
      %ru = idr.shru %u, %k : i8
      %ls = idr.shls %u, %k : i8
      %rs = idr.shrs %u, %k : i8
      idr.yield %x, %n, %u, %k, %l, %r, %lu, %ru, %ls, %rs : i64, i64, i8, i8, i64, i64, i8, i8, i8, i8
    }
    case 8 {
      %x = arith.constant 5 : i64
      %n = arith.constant -9223372036854775808 : i64
      %u = arith.constant 128 : i8
      %k = arith.constant 128 : i8
      %l = idr.shls %x, %n : i64
      %r = idr.shrs %x, %n : i64
      %lu = idr.shlu %u, %k : i8
      %ru = idr.shru %u, %k : i8
      %ls = idr.shls %u, %k : i8
      %rs = idr.shrs %u, %k : i8
      idr.yield %x, %n, %u, %k, %l, %r, %lu, %ru, %ls, %rs : i64, i64, i8, i8, i64, i64, i8, i8, i8, i8
    }
    case 9 {
      %x = arith.constant -5 : i64
      %n = arith.constant -9223372036854775808 : i64
      %u = arith.constant 129 : i8
      %k = arith.constant 129 : i8
      %l = idr.shls %x, %n : i64
      %r = idr.shrs %x, %n : i64
      %lu = idr.shlu %u, %k : i8
      %ru = idr.shru %u, %k : i8
      %ls = idr.shls %u, %k : i8
      %rs = idr.shrs %u, %k : i8
      idr.yield %x, %n, %u, %k, %l, %r, %lu, %ru, %ls, %rs : i64, i64, i8, i8, i64, i64, i8, i8, i8, i8
    }
    case 10 {
      %x = arith.constant 5 : i64
      %n = arith.constant 9223372036854775807 : i64
      %u = arith.constant 1 : i8
      %k = arith.constant 7 : i8
      %l = idr.shls %x, %n : i64
      %r = idr.shrs %x, %n : i64
      %lu = idr.shlu %u, %k : i8
      %ru = idr.shru %u, %k : i8
      %ls = idr.shls %u, %k : i8
      %rs = idr.shrs %u, %k : i8
      idr.yield %x, %n, %u, %k, %l, %r, %lu, %ru, %ls, %rs : i64, i64, i8, i8, i64, i64, i8, i8, i8, i8
    }
    case 11 {
      %x = arith.constant -1 : i64
      %n = arith.constant 63 : i64
      %u = arith.constant 64 : i8
      %k = arith.constant 2 : i8
      %l = idr.shls %x, %n : i64
      %r = idr.shrs %x, %n : i64
      %lu = idr.shlu %u, %k : i8
      %ru = idr.shru %u, %k : i8
      %ls = idr.shls %u, %k : i8
      %rs = idr.shrs %u, %k : i8
      idr.yield %x, %n, %u, %k, %l, %r, %lu, %ru, %ls, %rs : i64, i64, i8, i8, i64, i64, i8, i8, i8, i8
    }
    case 12 {
      %x = arith.constant 9223372036854775807 : i64
      %n = arith.constant 1 : i64
      %u = arith.constant 255 : i8
      %k = arith.constant 254 : i8
      %l = idr.shls %x, %n : i64
      %r = idr.shrs %x, %n : i64
      %lu = idr.shlu %u, %k : i8
      %ru = idr.shru %u, %k : i8
      %ls = idr.shls %u, %k : i8
      %rs = idr.shrs %u, %k : i8
      idr.yield %x, %n, %u, %k, %l, %r, %lu, %ru, %ls, %rs : i64, i64, i8, i8, i64, i64, i8, i8, i8, i8
    }
    case 13 {
      %x = arith.constant -1 : i64
      %n = arith.constant -64 : i64
      %u = arith.constant 3 : i8
      %k = arith.constant 0 : i8
      %l = idr.shls %x, %n : i64
      %r = idr.shrs %x, %n : i64
      %lu = idr.shlu %u, %k : i8
      %ru = idr.shru %u, %k : i8
      %ls = idr.shls %u, %k : i8
      %rs = idr.shrs %u, %k : i8
      idr.yield %x, %n, %u, %k, %l, %r, %lu, %ru, %ls, %rs : i64, i64, i8, i8, i64, i64, i8, i8, i8, i8
    }
    case 14 {
      %x = arith.constant -9223372036854775808 : i64
      %n = arith.constant 0 : i64
      %u = arith.constant 255 : i8
      %k = arith.constant 6 : i8
      %l = idr.shls %x, %n : i64
      %r = idr.shrs %x, %n : i64
      %lu = idr.shlu %u, %k : i8
      %ru = idr.shru %u, %k : i8
      %ls = idr.shls %u, %k : i8
      %rs = idr.shrs %u, %k : i8
      idr.yield %x, %n, %u, %k, %l, %r, %lu, %ru, %ls, %rs : i64, i64, i8, i8, i64, i64, i8, i8, i8, i8
    }
    case 15 {
      %x = arith.constant 12345 : i64
      %n = arith.constant -65 : i64
      %u = arith.constant 129 : i8
      %k = arith.constant 127 : i8
      %l = idr.shls %x, %n : i64
      %r = idr.shrs %x, %n : i64
      %lu = idr.shlu %u, %k : i8
      %ru = idr.shru %u, %k : i8
      %ls = idr.shls %u, %k : i8
      %rs = idr.shrs %u, %k : i8
      idr.yield %x, %n, %u, %k, %l, %r, %lu, %ru, %ls, %rs : i64, i64, i8, i8, i64, i64, i8, i8, i8, i8
    }
    default(%other: i64) {
      %x = arith.constant -7 : i64
      %n = arith.constant 1 : i64
      %u = arith.constant 200 : i8
      %k = arith.constant 0 : i8
      %l = idr.shls %x, %n : i64
      %r = idr.shrs %x, %n : i64
      %lu = idr.shlu %u, %k : i8
      %ru = idr.shru %u, %k : i8
      %ls = idr.shls %u, %k : i8
      %rs = idr.shrs %u, %k : i8
      idr.yield %x, %n, %u, %k, %l, %r, %lu, %ru, %ls, %rs : i64, i64, i8, i8, i64, i64, i8, i8, i8, i8
    }
    }
    return %r#0, %r#1, %r#2, %r#3, %r#4, %r#5, %r#6, %r#7, %r#8, %r#9 : i64, i64, i8, i8, i64, i64, i8, i8, i8, i8
  }
  // The program: the results of the row the byte read chooses, folded,
  // or, in the run form, computed at run time.
  idr.func @Prog.main(%w0: !idr.world) -> !idr.world {
    %byte, %w1 = idr.io.get_byte %w0
    %row = arith.extui %byte : i32 to i64
    %x, %n, %u, %k, %l, %r, %lu, %ru, %ls, %rs = idr.call @folded(%row) : (i64) -> (i64, i64, i8, i8, i64, i64, i8, i8, i8, i8)
    %space = arith.constant 32 : i32
    %newline = arith.constant 10 : i32
    %w2 = idr.io.put_sint %x, %w1 : i64
    %w3 = idr.io.put_char %space, %w2
    %w4 = idr.io.put_sint %n, %w3 : i64
    %w5 = idr.io.put_char %space, %w4
    %w6 = idr.io.put_uint %u, %w5 : i8
    %w7 = idr.io.put_char %space, %w6
    %w8 = idr.io.put_uint %k, %w7 : i8
    %w9 = idr.io.put_char %space, %w8
    %w10 = idr.io.put_sint %l, %w9 : i64
    %w11 = idr.io.put_char %space, %w10
    %w12 = idr.io.put_sint %r, %w11 : i64
    %w13 = idr.io.put_char %space, %w12
    %w14 = idr.io.put_uint %lu, %w13 : i8
    %w15 = idr.io.put_char %space, %w14
    %w16 = idr.io.put_uint %ru, %w15 : i8
    %w17 = idr.io.put_char %space, %w16
    %w18 = idr.io.put_sint %ls, %w17 : i8
    %w19 = idr.io.put_char %space, %w18
    %w20 = idr.io.put_sint %rs, %w19 : i8
    %w21 = idr.io.put_char %newline, %w20
    return %w21 : !idr.world
  }
}
