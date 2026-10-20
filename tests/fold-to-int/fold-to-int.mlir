// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns=@finite:-2/44/-8446744073709551616,returns=@nan:_,crash-sites=@nan:1,folded=@folded -o /dev/null
// RUN: sed 's/idr.call @folded(/idr.call @at_run_time(/' %s > %t.run.mlir
// RUN: %differential %t.run.mlir %s
// RUN: sed 's/%d = arith.constant 255.9 : f64/%d = arith.constant 256.9 : f64/' %s > %t.wrong.mlir
// RUN: not %differential %t.run.mlir %t.wrong.mlir 2>&1 | FileCheck %s --check-prefix=WRONG
// The cast of a Double to an integer folds: a finite value truncates
// toward zero and wraps to the result's width; NaN and the infinities have
// no integer, and their guard crashes.
//
// The cast the lowering computes, a second implementation of its meaning,
// is the oracle for every row of the table: each row folds in its own
// region (@folded), and is computed at run time from the row the byte read
// chose (@at_run_time, which the sed makes the program's). On the byte of
// each row, and on the empty input for the last, the two print the same:
// the row's operands, then its results; each operand is printed as well as
// used, so that no op on it is its one consumer, which case-of-case would
// move into the rows, where the run form would fold too. The rows:
// fractions of each sign, -0.0, the smallest subnormal, 2^63, -2^63 and
// 2^64, values past each of the three widths, values no word holds (which
// wrap to 0), and NaN and -inf, whose guard crashes before anything is
// printed, in both. A wrong fold is found on its row: the sed makes row
// 10's value 256.9, where the run casts 255.9.
// WRONG: differential: {{.*}}run.mlir and {{.*}}wrong.mlir differ on '\0012'
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
// STDIN:
idr.program @"to-int" root(@Prog.main) stage(first) types #idr.types<> {
  // Finite constants truncate toward zero and wrap to the result width.
  idr.func @finite() -> (i64, i8, i64) {
    %a = arith.constant -2.75 : f64
    %b = arith.constant 300.5 : f64
    %c = arith.constant 1.0e19 : f64
    %ra = idr.to_int %a : i64
    %rb = idr.to_int %b : i8
    %rc = idr.to_int %c : i64
    return %ra, %rb, %rc : i64, i8, i64
  }
  // The guard of NaN does not fold, and stays although nothing reads it,
  // because it crashes; a dead cast goes, and so does the guard of a finite
  // constant. A cast of NaN with no guard before it does not fold either:
  // NaN has no Int to fold to.
  idr.func @nan() -> i64 {
    %n = arith.constant 0x7FF8000000000000 : f64
    %f = arith.constant 1.5 : f64
    %ng = idr.check.finite %n, "cast of a non-finite Double"
    %a = idr.to_int %ng : i64
    %fg = idr.check.finite %f, "cast of a non-finite Double"
    %b = idr.to_int %fg : i64
    %r = idr.to_int %n : i64
    return %r : i64
  }
  // The operands of each row, the last the default one: the row the byte
  // chose, known only at run time.
  idr.func @rows(%row: i64) -> (f64) {
    %r:1 = idr.match_lit %row : i64 -> (f64) {
    case 0 {
      %d = arith.constant -2.75 : f64
      idr.yield %d : f64
    }
    case 1 {
      %d = arith.constant 300.5 : f64
      idr.yield %d : f64
    }
    case 2 {
      %d = arith.constant 1.0e19 : f64
      idr.yield %d : f64
    }
    case 3 {
      %d = arith.constant -0.0 : f64
      idr.yield %d : f64
    }
    case 4 {
      %d = arith.constant 0.5 : f64
      idr.yield %d : f64
    }
    case 5 {
      %d = arith.constant -0.5 : f64
      idr.yield %d : f64
    }
    case 6 {
      %d = arith.constant 9.2233720368547758e18 : f64
      idr.yield %d : f64
    }
    case 7 {
      %d = arith.constant -9.2233720368547758e18 : f64
      idr.yield %d : f64
    }
    case 8 {
      %d = arith.constant 1.8446744073709552e19 : f64
      idr.yield %d : f64
    }
    case 9 {
      %d = arith.constant 4.9406564584124654e-324 : f64
      idr.yield %d : f64
    }
    case 10 {
      %d = arith.constant 255.9 : f64
      idr.yield %d : f64
    }
    case 11 {
      %d = arith.constant -128.9 : f64
      idr.yield %d : f64
    }
    case 12 {
      %d = arith.constant 1.0e300 : f64
      idr.yield %d : f64
    }
    case 13 {
      %d = arith.constant -1.0e300 : f64
      idr.yield %d : f64
    }
    case 14 {
      %d = arith.constant 4294967296.5 : f64
      idr.yield %d : f64
    }
    case 15 {
      %d = arith.constant -2147483648.75 : f64
      idr.yield %d : f64
    }
    case 16 {
      %d = arith.constant 0x7FF8000000000000 : f64
      idr.yield %d : f64
    }
    case 17 {
      %d = arith.constant 0xFFF0000000000000 : f64
      idr.yield %d : f64
    }
    default(%other: i64) {
      %d = arith.constant 7.9 : f64
      idr.yield %d : f64
    }
    }
    return %r#0 : f64
  }
  // Each row's results, computed at run time from the row @rows chose.
  idr.func @at_run_time(%row: i64) -> (f64, i64, i32, i8) {
    %d = idr.call @rows(%row) : (i64) -> (f64)
    %g = idr.check.finite %d, "cast of a non-finite Double"
    %i = idr.to_int %g : i64
    %j = idr.to_int %g : i32
    %k = idr.to_int %g : i8
    return %d, %i, %j, %k : f64, i64, i32, i8
  }
  // Each row's results on its constants, which the folders compute.
  idr.func @folded(%row: i64) -> (f64, i64, i32, i8) {
    %r:4 = idr.match_lit %row : i64 -> (f64, i64, i32, i8) {
    case 0 {
      %d = arith.constant -2.75 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %j = idr.to_int %g : i32
      %k = idr.to_int %g : i8
      idr.yield %d, %i, %j, %k : f64, i64, i32, i8
    }
    case 1 {
      %d = arith.constant 300.5 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %j = idr.to_int %g : i32
      %k = idr.to_int %g : i8
      idr.yield %d, %i, %j, %k : f64, i64, i32, i8
    }
    case 2 {
      %d = arith.constant 1.0e19 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %j = idr.to_int %g : i32
      %k = idr.to_int %g : i8
      idr.yield %d, %i, %j, %k : f64, i64, i32, i8
    }
    case 3 {
      %d = arith.constant -0.0 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %j = idr.to_int %g : i32
      %k = idr.to_int %g : i8
      idr.yield %d, %i, %j, %k : f64, i64, i32, i8
    }
    case 4 {
      %d = arith.constant 0.5 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %j = idr.to_int %g : i32
      %k = idr.to_int %g : i8
      idr.yield %d, %i, %j, %k : f64, i64, i32, i8
    }
    case 5 {
      %d = arith.constant -0.5 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %j = idr.to_int %g : i32
      %k = idr.to_int %g : i8
      idr.yield %d, %i, %j, %k : f64, i64, i32, i8
    }
    case 6 {
      %d = arith.constant 9.2233720368547758e18 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %j = idr.to_int %g : i32
      %k = idr.to_int %g : i8
      idr.yield %d, %i, %j, %k : f64, i64, i32, i8
    }
    case 7 {
      %d = arith.constant -9.2233720368547758e18 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %j = idr.to_int %g : i32
      %k = idr.to_int %g : i8
      idr.yield %d, %i, %j, %k : f64, i64, i32, i8
    }
    case 8 {
      %d = arith.constant 1.8446744073709552e19 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %j = idr.to_int %g : i32
      %k = idr.to_int %g : i8
      idr.yield %d, %i, %j, %k : f64, i64, i32, i8
    }
    case 9 {
      %d = arith.constant 4.9406564584124654e-324 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %j = idr.to_int %g : i32
      %k = idr.to_int %g : i8
      idr.yield %d, %i, %j, %k : f64, i64, i32, i8
    }
    case 10 {
      %d = arith.constant 255.9 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %j = idr.to_int %g : i32
      %k = idr.to_int %g : i8
      idr.yield %d, %i, %j, %k : f64, i64, i32, i8
    }
    case 11 {
      %d = arith.constant -128.9 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %j = idr.to_int %g : i32
      %k = idr.to_int %g : i8
      idr.yield %d, %i, %j, %k : f64, i64, i32, i8
    }
    case 12 {
      %d = arith.constant 1.0e300 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %j = idr.to_int %g : i32
      %k = idr.to_int %g : i8
      idr.yield %d, %i, %j, %k : f64, i64, i32, i8
    }
    case 13 {
      %d = arith.constant -1.0e300 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %j = idr.to_int %g : i32
      %k = idr.to_int %g : i8
      idr.yield %d, %i, %j, %k : f64, i64, i32, i8
    }
    case 14 {
      %d = arith.constant 4294967296.5 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %j = idr.to_int %g : i32
      %k = idr.to_int %g : i8
      idr.yield %d, %i, %j, %k : f64, i64, i32, i8
    }
    case 15 {
      %d = arith.constant -2147483648.75 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %j = idr.to_int %g : i32
      %k = idr.to_int %g : i8
      idr.yield %d, %i, %j, %k : f64, i64, i32, i8
    }
    case 16 {
      %d = arith.constant 0x7FF8000000000000 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %j = idr.to_int %g : i32
      %k = idr.to_int %g : i8
      idr.yield %d, %i, %j, %k : f64, i64, i32, i8
    }
    case 17 {
      %d = arith.constant 0xFFF0000000000000 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %j = idr.to_int %g : i32
      %k = idr.to_int %g : i8
      idr.yield %d, %i, %j, %k : f64, i64, i32, i8
    }
    default(%other: i64) {
      %d = arith.constant 7.9 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %j = idr.to_int %g : i32
      %k = idr.to_int %g : i8
      idr.yield %d, %i, %j, %k : f64, i64, i32, i8
    }
    }
    return %r#0, %r#1, %r#2, %r#3 : f64, i64, i32, i8
  }
  // The program: the results of the row the byte read chooses, folded,
  // or, in the run form, computed at run time.
  idr.func @Prog.main(%w0: !idr.world) -> !idr.world {
    %byte, %w1 = idr.io.get_byte %w0
    %row = arith.extui %byte : i32 to i64
    %d, %i, %j, %k = idr.call @folded(%row) : (i64) -> (f64, i64, i32, i8)
    %space = arith.constant 32 : i32
    %newline = arith.constant 10 : i32
    %w2 = idr.io.put_double %d, %w1
    %w3 = idr.io.put_char %space, %w2
    %w4 = idr.io.put_sint %i, %w3 : i64
    %w5 = idr.io.put_char %space, %w4
    %w6 = idr.io.put_sint %j, %w5 : i32
    %w7 = idr.io.put_char %space, %w6
    %w8 = idr.io.put_sint %k, %w7 : i8
    %w9 = idr.io.put_char %newline, %w8
    return %w9 : !idr.world
  }
}
