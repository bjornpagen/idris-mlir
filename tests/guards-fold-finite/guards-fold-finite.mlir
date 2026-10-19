// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns=@proving:-2,no-guards=@proving,crash-sites=@failing:2,crash-sites=@again:1 -o /dev/null
// RUN: sed 's/idr.call @folded(/idr.call @at_run_time(/' %s > %t.run.mlir
// RUN: %differential %t.run.mlir %s
// RUN: sed 's/%d = arith.constant 1.0e300 : f64/%d = arith.constant 1.0e299 : f64/' %s > %t.wrong.mlir
// RUN: not %differential %t.run.mlir %t.wrong.mlir 2>&1 | FileCheck %s --check-prefix=WRONG
// The guard of a Double cast to an integer folds to the Double where it is
// a finite constant; then the cast folds too. On NaN or an infinity the
// guard stays, to crash where it runs. A guard of what an identical guard
// already checked folds too.
//
// Each guard's decision is the one the program makes at run time, on every
// row of the table: each row folds in its own region (@folded), where a
// guard of a finite Double folds away and the others stay, and is checked
// at run time on the row the byte read chose (@at_run_time, which the sed
// makes the program's). On the byte of each row, and on the empty input
// for the last, the two print the same, the row's operands and then its
// results, or both crash before printing; each operand is printed as well
// as used, so that no guard on it is its one consumer, which case-of-case
// would move into the rows. The rows: fractions, 0.0 and -0.0, the
// smallest subnormal and the largest finite Double, 2^63, an odd integer
// past 2^53, 1e300 as a big, each infinity, and NaN, quiet and with a
// payload and its sign set. A wrong decision is found on its row: the sed
// makes row 6's 1e300 1e299, where the run casts 1e300.
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
// STDIN:
idr.program @"fold-finite" root(@Prog.main) stage(first) {
  idr.func @proving() -> i64 {
    %d = arith.constant -2.75 : f64
    %g = idr.check.finite %d, "cast of a non-finite Double"
    %i = idr.to_int %g : i64
    return %i : i64
  }

  idr.func @failing(%b: !idr.big) -> (i64, !idr.big) {
    %nan = arith.constant 0x7FF8000000000000 : f64
    %g = idr.check.finite %nan, "cast of a non-finite Double"
    %i = idr.to_int %g : i64
    %inf = arith.constant 0xFFF0000000000000 : f64
    %h = idr.check.finite %inf, "cast of a non-finite Double"
    %j = idr.big.from_double %h
    return %i, %j : i64, !idr.big
  }

  idr.func @again(%d: f64) -> (i64, !idr.big) {
    %g = idr.check.finite %d, "cast of a non-finite Double"
    %i = idr.to_int %g : i64
    %h = idr.check.finite %g, "cast of a non-finite Double"
    %j = idr.big.from_double %h
    return %i, %j : i64, !idr.big
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
      %d = arith.constant 0.0 : f64
      idr.yield %d : f64
    }
    case 2 {
      %d = arith.constant -0.0 : f64
      idr.yield %d : f64
    }
    case 3 {
      %d = arith.constant 0x7FF8000000000000 : f64
      idr.yield %d : f64
    }
    case 4 {
      %d = arith.constant 0x7FF0000000000000 : f64
      idr.yield %d : f64
    }
    case 5 {
      %d = arith.constant 0xFFF0000000000000 : f64
      idr.yield %d : f64
    }
    case 6 {
      %d = arith.constant 1.0e300 : f64
      idr.yield %d : f64
    }
    case 7 {
      %d = arith.constant 4.9406564584124654e-324 : f64
      idr.yield %d : f64
    }
    case 8 {
      %d = arith.constant 9.2233720368547758e18 : f64
      idr.yield %d : f64
    }
    case 9 {
      %d = arith.constant -9007199254740993.0 : f64
      idr.yield %d : f64
    }
    case 10 {
      %d = arith.constant 1.7976931348623157e308 : f64
      idr.yield %d : f64
    }
    case 11 {
      %d = arith.constant 0xFFF8000000000001 : f64
      idr.yield %d : f64
    }
    default(%other: i64) {
      %d = arith.constant 0.999 : f64
      idr.yield %d : f64
    }
    }
    return %r#0 : f64
  }
  // Each row's results, computed at run time from the row @rows chose.
  idr.func @at_run_time(%row: i64) -> (f64, i64, !idr.big) {
    %d = idr.call @rows(%row) : (i64) -> (f64)
    %g = idr.check.finite %d, "cast of a non-finite Double"
    %i = idr.to_int %g : i64
    %h = idr.check.finite %d, "cast of a non-finite Double"
    %j = idr.big.from_double %h
    return %d, %i, %j : f64, i64, !idr.big
  }
  // Each row's results on its constants, which the folders compute.
  idr.func @folded(%row: i64) -> (f64, i64, !idr.big) {
    %r:3 = idr.match_lit %row : i64 -> (f64, i64, !idr.big) {
    case 0 {
      %d = arith.constant -2.75 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %h = idr.check.finite %d, "cast of a non-finite Double"
      %j = idr.big.from_double %h
      idr.yield %d, %i, %j : f64, i64, !idr.big
    }
    case 1 {
      %d = arith.constant 0.0 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %h = idr.check.finite %d, "cast of a non-finite Double"
      %j = idr.big.from_double %h
      idr.yield %d, %i, %j : f64, i64, !idr.big
    }
    case 2 {
      %d = arith.constant -0.0 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %h = idr.check.finite %d, "cast of a non-finite Double"
      %j = idr.big.from_double %h
      idr.yield %d, %i, %j : f64, i64, !idr.big
    }
    case 3 {
      %d = arith.constant 0x7FF8000000000000 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %h = idr.check.finite %d, "cast of a non-finite Double"
      %j = idr.big.from_double %h
      idr.yield %d, %i, %j : f64, i64, !idr.big
    }
    case 4 {
      %d = arith.constant 0x7FF0000000000000 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %h = idr.check.finite %d, "cast of a non-finite Double"
      %j = idr.big.from_double %h
      idr.yield %d, %i, %j : f64, i64, !idr.big
    }
    case 5 {
      %d = arith.constant 0xFFF0000000000000 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %h = idr.check.finite %d, "cast of a non-finite Double"
      %j = idr.big.from_double %h
      idr.yield %d, %i, %j : f64, i64, !idr.big
    }
    case 6 {
      %d = arith.constant 1.0e300 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %h = idr.check.finite %d, "cast of a non-finite Double"
      %j = idr.big.from_double %h
      idr.yield %d, %i, %j : f64, i64, !idr.big
    }
    case 7 {
      %d = arith.constant 4.9406564584124654e-324 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %h = idr.check.finite %d, "cast of a non-finite Double"
      %j = idr.big.from_double %h
      idr.yield %d, %i, %j : f64, i64, !idr.big
    }
    case 8 {
      %d = arith.constant 9.2233720368547758e18 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %h = idr.check.finite %d, "cast of a non-finite Double"
      %j = idr.big.from_double %h
      idr.yield %d, %i, %j : f64, i64, !idr.big
    }
    case 9 {
      %d = arith.constant -9007199254740993.0 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %h = idr.check.finite %d, "cast of a non-finite Double"
      %j = idr.big.from_double %h
      idr.yield %d, %i, %j : f64, i64, !idr.big
    }
    case 10 {
      %d = arith.constant 1.7976931348623157e308 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %h = idr.check.finite %d, "cast of a non-finite Double"
      %j = idr.big.from_double %h
      idr.yield %d, %i, %j : f64, i64, !idr.big
    }
    case 11 {
      %d = arith.constant 0xFFF8000000000001 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %h = idr.check.finite %d, "cast of a non-finite Double"
      %j = idr.big.from_double %h
      idr.yield %d, %i, %j : f64, i64, !idr.big
    }
    default(%other: i64) {
      %d = arith.constant 0.999 : f64
      %g = idr.check.finite %d, "cast of a non-finite Double"
      %i = idr.to_int %g : i64
      %h = idr.check.finite %d, "cast of a non-finite Double"
      %j = idr.big.from_double %h
      idr.yield %d, %i, %j : f64, i64, !idr.big
    }
    }
    return %r#0, %r#1, %r#2 : f64, i64, !idr.big
  }
  // The program: the results of the row the byte read chooses, folded,
  // or, in the run form, computed at run time.
  idr.func @Prog.main(%w0: !idr.world) -> !idr.world {
    %byte, %w1 = idr.io.get_byte %w0
    %row = arith.extui %byte : i32 to i64
    %d, %i, %j = idr.call @folded(%row) : (i64) -> (f64, i64, !idr.big)
    %space = arith.constant 32 : i32
    %newline = arith.constant 10 : i32
    %w2 = idr.io.put_double %d, %w1
    %w3 = idr.io.put_char %space, %w2
    %w4 = idr.io.put_sint %i, %w3 : i64
    %w5 = idr.io.put_char %space, %w4
    %j.text = idr.big.show %j
    %w6 = idr.io.put_str %j.text, %w5
    %w7 = idr.io.put_char %newline, %w6
    return %w7 : !idr.world
  }
}
