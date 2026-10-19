// RUN: idris-mlir-opt %s --canonicalize '--idr-expect=holds=returns=@closures:(#idr.closure<@add,[5]>)/(#idr.closure<@add,[]>)/_' -o /dev/null
// RUN: sed 's/idr.call @folded(/idr.call @at_run_time(/' %s > %t.run.mlir
// RUN: %differential %t.run.mlir %s
// RUN: sed 's/%c = arith.constant 7 : i64/%c = arith.constant 8 : i64/' %s > %t.wrong.mlir
// RUN: not %differential %t.run.mlir %t.wrong.mlir 2>&1 | FileCheck %s --check-prefix=WRONG
// A closure whose captures are constants is a constant.
//
// A closure built at run time, of the capture the row the byte read chose,
// and applied there, is the oracle for every row of the table: each row
// folds in its own region (@folded), and is computed at run time from the
// row the byte read chose (@at_run_time, which the sed makes the
// program's). On the byte of each row, and on the empty input for the
// last, the two print the same: the row's operands, then its results; each
// operand is printed as well as used, so that no op on it is its one
// consumer, which case-of-case would move into the rows, where the run
// form would fold too. The rows: captures and arguments of 0, 1 and -1,
// the most negative and the most positive Int, whose sums wrap, and a
// closure of no capture applied to the capture twice; a closure is no
// output, so a row prints what its closures give. A wrong fold is found on
// its row: the sed makes row 5's capture 8, where the run captures 7.
// WRONG: differential: {{.*}}run.mlir and {{.*}}wrong.mlir differ on '\0005'
// STDIN: \0000
// STDIN: \0001
// STDIN: \0002
// STDIN: \0003
// STDIN: \0004
// STDIN: \0005
// STDIN: \0006
// STDIN:
idr.program @closure root(@Prog.main) stage(higher) {
  idr.func @add(%a: i64, %b: i64) -> i64 {
    %r = arith.addi %a, %b : i64
    return %r : i64
  }

  idr.func @closures(%x: i64) -> (!idr.fn<(i64) -> (i64)>, !idr.fn<(i64, i64) -> (i64)>,
                                    !idr.fn<(i64) -> (i64)>) {
    %five = arith.constant 5 : i64
    %c = idr.closure @add(%five) : (i64) -> !idr.fn<(i64) -> (i64)>
    %n = idr.closure @add() : () -> !idr.fn<(i64, i64) -> (i64)>
    %r = idr.closure @add(%x) : (i64) -> !idr.fn<(i64) -> (i64)>
    return %c, %n, %r : !idr.fn<(i64) -> (i64)>, !idr.fn<(i64, i64) -> (i64)>,
                        !idr.fn<(i64) -> (i64)>
  }
  // The operands of each row, the last the default one: the row the byte
  // chose, known only at run time.
  idr.func @rows(%row: i64) -> (i64, i64) {
    %r:2 = idr.match_lit %row : i64 -> (i64, i64) {
    case 0 {
      %c = arith.constant 5 : i64
      %a = arith.constant 1 : i64
      idr.yield %c, %a : i64, i64
    }
    case 1 {
      %c = arith.constant 0 : i64
      %a = arith.constant 0 : i64
      idr.yield %c, %a : i64, i64
    }
    case 2 {
      %c = arith.constant -9223372036854775808 : i64
      %a = arith.constant -1 : i64
      idr.yield %c, %a : i64, i64
    }
    case 3 {
      %c = arith.constant 9223372036854775807 : i64
      %a = arith.constant 1 : i64
      idr.yield %c, %a : i64, i64
    }
    case 4 {
      %c = arith.constant -1 : i64
      %a = arith.constant 1 : i64
      idr.yield %c, %a : i64, i64
    }
    case 5 {
      %c = arith.constant 7 : i64
      %a = arith.constant -7 : i64
      idr.yield %c, %a : i64, i64
    }
    case 6 {
      %c = arith.constant -9223372036854775808 : i64
      %a = arith.constant -9223372036854775808 : i64
      idr.yield %c, %a : i64, i64
    }
    default(%other: i64) {
      %c = arith.constant 2 : i64
      %a = arith.constant 3 : i64
      idr.yield %c, %a : i64, i64
    }
    }
    return %r#0, %r#1 : i64, i64
  }
  // Each row's results, computed at run time from the row @rows chose.
  idr.func @at_run_time(%row: i64) -> (i64, i64, i64, i64) {
    %c, %a = idr.call @rows(%row) : (i64) -> (i64, i64)
    %f = idr.closure @add(%c) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.apply %f(%a) : !idr.fn<(i64) -> (i64)>
    %g = idr.closure @add() : () -> !idr.fn<(i64, i64) -> (i64)>
    %s = idr.apply %g(%c, %c) : !idr.fn<(i64, i64) -> (i64)>
    return %c, %a, %r, %s : i64, i64, i64, i64
  }
  // Each row's results on its constants, which the folders compute.
  idr.func @folded(%row: i64) -> (i64, i64, i64, i64) {
    %r:4 = idr.match_lit %row : i64 -> (i64, i64, i64, i64) {
    case 0 {
      %c = arith.constant 5 : i64
      %a = arith.constant 1 : i64
      %f = idr.closure @add(%c) : (i64) -> !idr.fn<(i64) -> (i64)>
      %r = idr.apply %f(%a) : !idr.fn<(i64) -> (i64)>
      %g = idr.closure @add() : () -> !idr.fn<(i64, i64) -> (i64)>
      %s = idr.apply %g(%c, %c) : !idr.fn<(i64, i64) -> (i64)>
      idr.yield %c, %a, %r, %s : i64, i64, i64, i64
    }
    case 1 {
      %c = arith.constant 0 : i64
      %a = arith.constant 0 : i64
      %f = idr.closure @add(%c) : (i64) -> !idr.fn<(i64) -> (i64)>
      %r = idr.apply %f(%a) : !idr.fn<(i64) -> (i64)>
      %g = idr.closure @add() : () -> !idr.fn<(i64, i64) -> (i64)>
      %s = idr.apply %g(%c, %c) : !idr.fn<(i64, i64) -> (i64)>
      idr.yield %c, %a, %r, %s : i64, i64, i64, i64
    }
    case 2 {
      %c = arith.constant -9223372036854775808 : i64
      %a = arith.constant -1 : i64
      %f = idr.closure @add(%c) : (i64) -> !idr.fn<(i64) -> (i64)>
      %r = idr.apply %f(%a) : !idr.fn<(i64) -> (i64)>
      %g = idr.closure @add() : () -> !idr.fn<(i64, i64) -> (i64)>
      %s = idr.apply %g(%c, %c) : !idr.fn<(i64, i64) -> (i64)>
      idr.yield %c, %a, %r, %s : i64, i64, i64, i64
    }
    case 3 {
      %c = arith.constant 9223372036854775807 : i64
      %a = arith.constant 1 : i64
      %f = idr.closure @add(%c) : (i64) -> !idr.fn<(i64) -> (i64)>
      %r = idr.apply %f(%a) : !idr.fn<(i64) -> (i64)>
      %g = idr.closure @add() : () -> !idr.fn<(i64, i64) -> (i64)>
      %s = idr.apply %g(%c, %c) : !idr.fn<(i64, i64) -> (i64)>
      idr.yield %c, %a, %r, %s : i64, i64, i64, i64
    }
    case 4 {
      %c = arith.constant -1 : i64
      %a = arith.constant 1 : i64
      %f = idr.closure @add(%c) : (i64) -> !idr.fn<(i64) -> (i64)>
      %r = idr.apply %f(%a) : !idr.fn<(i64) -> (i64)>
      %g = idr.closure @add() : () -> !idr.fn<(i64, i64) -> (i64)>
      %s = idr.apply %g(%c, %c) : !idr.fn<(i64, i64) -> (i64)>
      idr.yield %c, %a, %r, %s : i64, i64, i64, i64
    }
    case 5 {
      %c = arith.constant 7 : i64
      %a = arith.constant -7 : i64
      %f = idr.closure @add(%c) : (i64) -> !idr.fn<(i64) -> (i64)>
      %r = idr.apply %f(%a) : !idr.fn<(i64) -> (i64)>
      %g = idr.closure @add() : () -> !idr.fn<(i64, i64) -> (i64)>
      %s = idr.apply %g(%c, %c) : !idr.fn<(i64, i64) -> (i64)>
      idr.yield %c, %a, %r, %s : i64, i64, i64, i64
    }
    case 6 {
      %c = arith.constant -9223372036854775808 : i64
      %a = arith.constant -9223372036854775808 : i64
      %f = idr.closure @add(%c) : (i64) -> !idr.fn<(i64) -> (i64)>
      %r = idr.apply %f(%a) : !idr.fn<(i64) -> (i64)>
      %g = idr.closure @add() : () -> !idr.fn<(i64, i64) -> (i64)>
      %s = idr.apply %g(%c, %c) : !idr.fn<(i64, i64) -> (i64)>
      idr.yield %c, %a, %r, %s : i64, i64, i64, i64
    }
    default(%other: i64) {
      %c = arith.constant 2 : i64
      %a = arith.constant 3 : i64
      %f = idr.closure @add(%c) : (i64) -> !idr.fn<(i64) -> (i64)>
      %r = idr.apply %f(%a) : !idr.fn<(i64) -> (i64)>
      %g = idr.closure @add() : () -> !idr.fn<(i64, i64) -> (i64)>
      %s = idr.apply %g(%c, %c) : !idr.fn<(i64, i64) -> (i64)>
      idr.yield %c, %a, %r, %s : i64, i64, i64, i64
    }
    }
    return %r#0, %r#1, %r#2, %r#3 : i64, i64, i64, i64
  }
  // The program: the results of the row the byte read chooses, folded,
  // or, in the run form, computed at run time.
  idr.func @Prog.main(%w0: !idr.world) -> !idr.world {
    %byte, %w1 = idr.io.get_byte %w0
    %row = arith.extui %byte : i32 to i64
    %c, %a, %r, %s = idr.call @folded(%row) : (i64) -> (i64, i64, i64, i64)
    %space = arith.constant 32 : i32
    %newline = arith.constant 10 : i32
    %w2 = idr.io.put_sint %c, %w1 : i64
    %w3 = idr.io.put_char %space, %w2
    %w4 = idr.io.put_sint %a, %w3 : i64
    %w5 = idr.io.put_char %space, %w4
    %w6 = idr.io.put_sint %r, %w5 : i64
    %w7 = idr.io.put_char %space, %w6
    %w8 = idr.io.put_sint %s, %w7 : i64
    %w9 = idr.io.put_char %newline, %w8
    return %w9 : !idr.world
  }
}
