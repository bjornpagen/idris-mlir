// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns=@divfold:-4/1/-9223372036854775808/0/35/_,folded=@folded -o /dev/null
// RUN: sed 's/idr.call @folded(/idr.call @at_run_time(/' %s > %t.run.mlir
// RUN: %differential %t.run.mlir %s
// RUN: sed 's/%u = arith.constant 254 : i8/%u = arith.constant 253 : i8/' %s > %t.wrong.mlir
// RUN: not %differential %t.run.mlir %t.wrong.mlir 2>&1 | FileCheck %s --check-prefix=WRONG
// A division by zero does not fold: its guard crashes before it runs, and
// the folder computes nothing a program never reaches. Idris's div and mod
// of a signed integer are Euclidean.
//
// The quotient and remainder the lowering computes, a second
// implementation of their meaning, are the oracle for every row of the
// table: each row folds in its own region (@folded), and is computed at
// run time from the row the byte read chose (@at_run_time, which the sed
// makes the program's). On the byte of each row, and on the empty input
// for the last, the two print the same: the row's operands, then its
// results; each operand is printed as well as used, so that no op on it is
// its one consumer, which case-of-case would move into the rows, where the
// run form would fold too. The rows: signed operands of each sign, the
// most negative and the most positive Int with -1, 1 and each other,
// unsigned operands past 127, and a zero divisor of each kind, whose guard
// crashes before anything is printed, in both. A wrong fold is found on
// its row: the sed makes row 13's unsigned dividend 253, where the run
// divides 254.
// WRONG: differential: {{.*}}run.mlir and {{.*}}wrong.mlir differ on '\0015'
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
idr.program @division root(@Prog.main) stage(first) types #idr.types<> {
  // A division by zero is not folded: its guard crashes before it runs, and
  // the folder computes nothing a program never reaches.
  idr.func @divfold() -> (i64, i64, i64, i64, i8, i64) {
    %m7 = arith.constant -7 : i64
    %c2 = arith.constant 2 : i64
    %m2 = arith.constant -2 : i64
    %min = arith.constant -9223372036854775808 : i64
    %m1 = arith.constant -1 : i64
    %c0 = arith.constant 0 : i64
    %u250 = arith.constant 250 : i8
    %u7 = arith.constant 7 : i8
    %a = idr.divs %m7, %c2 : i64
    %b = idr.mods %m7, %m2 : i64
    %c = idr.divs %min, %m1 : i64
    %d = idr.mods %min, %m1 : i64
    %e = idr.divu %u250, %u7 : i8
    %z = idr.divs %c2, %c0 : i64
    return %a, %b, %c, %d, %e, %z : i64, i64, i64, i64, i8, i64
  }
  // The operands of each row, the last the default one: the row the byte
  // chose, known only at run time.
  idr.func @rows(%row: i64) -> (i64, i64, i8, i8) {
    %r:4 = idr.match_lit %row : i64 -> (i64, i64, i8, i8) {
    case 0 {
      %x = arith.constant -7 : i64
      %y = arith.constant 2 : i64
      %u = arith.constant 250 : i8
      %v = arith.constant 7 : i8
      idr.yield %x, %y, %u, %v : i64, i64, i8, i8
    }
    case 1 {
      %x = arith.constant -7 : i64
      %y = arith.constant -2 : i64
      %u = arith.constant 255 : i8
      %v = arith.constant 1 : i8
      idr.yield %x, %y, %u, %v : i64, i64, i8, i8
    }
    case 2 {
      %x = arith.constant 7 : i64
      %y = arith.constant -2 : i64
      %u = arith.constant 255 : i8
      %v = arith.constant 255 : i8
      idr.yield %x, %y, %u, %v : i64, i64, i8, i8
    }
    case 3 {
      %x = arith.constant 7 : i64
      %y = arith.constant 2 : i64
      %u = arith.constant 0 : i8
      %v = arith.constant 255 : i8
      idr.yield %x, %y, %u, %v : i64, i64, i8, i8
    }
    case 4 {
      %x = arith.constant -9223372036854775808 : i64
      %y = arith.constant -1 : i64
      %u = arith.constant 128 : i8
      %v = arith.constant 2 : i8
      idr.yield %x, %y, %u, %v : i64, i64, i8, i8
    }
    case 5 {
      %x = arith.constant -9223372036854775808 : i64
      %y = arith.constant 1 : i64
      %u = arith.constant 127 : i8
      %v = arith.constant 128 : i8
      idr.yield %x, %y, %u, %v : i64, i64, i8, i8
    }
    case 6 {
      %x = arith.constant 9223372036854775807 : i64
      %y = arith.constant -1 : i64
      %u = arith.constant 1 : i8
      %v = arith.constant 128 : i8
      idr.yield %x, %y, %u, %v : i64, i64, i8, i8
    }
    case 7 {
      %x = arith.constant -9223372036854775808 : i64
      %y = arith.constant -9223372036854775808 : i64
      %u = arith.constant 200 : i8
      %v = arith.constant 3 : i8
      idr.yield %x, %y, %u, %v : i64, i64, i8, i8
    }
    case 8 {
      %x = arith.constant 0 : i64
      %y = arith.constant 5 : i64
      %u = arith.constant 129 : i8
      %v = arith.constant 127 : i8
      idr.yield %x, %y, %u, %v : i64, i64, i8, i8
    }
    case 9 {
      %x = arith.constant -1 : i64
      %y = arith.constant 9223372036854775807 : i64
      %u = arith.constant 255 : i8
      %v = arith.constant 16 : i8
      idr.yield %x, %y, %u, %v : i64, i64, i8, i8
    }
    case 10 {
      %x = arith.constant -9223372036854775808 : i64
      %y = arith.constant 2 : i64
      %u = arith.constant 7 : i8
      %v = arith.constant 250 : i8
      idr.yield %x, %y, %u, %v : i64, i64, i8, i8
    }
    case 11 {
      %x = arith.constant 9223372036854775807 : i64
      %y = arith.constant -9223372036854775808 : i64
      %u = arith.constant 9 : i8
      %v = arith.constant 3 : i8
      idr.yield %x, %y, %u, %v : i64, i64, i8, i8
    }
    case 12 {
      %x = arith.constant -9 : i64
      %y = arith.constant 3 : i64
      %u = arith.constant 128 : i8
      %v = arith.constant 128 : i8
      idr.yield %x, %y, %u, %v : i64, i64, i8, i8
    }
    case 13 {
      %x = arith.constant -9223372036854775808 : i64
      %y = arith.constant 9223372036854775807 : i64
      %u = arith.constant 254 : i8
      %v = arith.constant 255 : i8
      idr.yield %x, %y, %u, %v : i64, i64, i8, i8
    }
    case 14 {
      %x = arith.constant 2 : i64
      %y = arith.constant 0 : i64
      %u = arith.constant 1 : i8
      %v = arith.constant 1 : i8
      idr.yield %x, %y, %u, %v : i64, i64, i8, i8
    }
    case 15 {
      %x = arith.constant 1 : i64
      %y = arith.constant 1 : i64
      %u = arith.constant 1 : i8
      %v = arith.constant 0 : i8
      idr.yield %x, %y, %u, %v : i64, i64, i8, i8
    }
    default(%other: i64) {
      %x = arith.constant 13 : i64
      %y = arith.constant -4 : i64
      %u = arith.constant 100 : i8
      %v = arith.constant 9 : i8
      idr.yield %x, %y, %u, %v : i64, i64, i8, i8
    }
    }
    return %r#0, %r#1, %r#2, %r#3 : i64, i64, i8, i8
  }
  // Each row's results, computed at run time from the row @rows chose.
  idr.func @at_run_time(%row: i64) -> (i64, i64, i8, i8, i64, i64, i8, i8) {
    %x, %y, %u, %v = idr.call @rows(%row) : (i64) -> (i64, i64, i8, i8)
    %g = idr.check.nonzero %y, "division by zero" : i64
    %q = idr.divs %x, %g : i64
    %m = idr.mods %x, %g : i64
    %gu = idr.check.nonzero %v, "division by zero" : i8
    %qu = idr.divu %u, %gu : i8
    %mu = idr.modu %u, %gu : i8
    return %x, %y, %u, %v, %q, %m, %qu, %mu : i64, i64, i8, i8, i64, i64, i8, i8
  }
  // Each row's results on its constants, which the folders compute.
  idr.func @folded(%row: i64) -> (i64, i64, i8, i8, i64, i64, i8, i8) {
    %r:8 = idr.match_lit %row : i64 -> (i64, i64, i8, i8, i64, i64, i8, i8) {
    case 0 {
      %x = arith.constant -7 : i64
      %y = arith.constant 2 : i64
      %u = arith.constant 250 : i8
      %v = arith.constant 7 : i8
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %m = idr.mods %x, %g : i64
      %gu = idr.check.nonzero %v, "division by zero" : i8
      %qu = idr.divu %u, %gu : i8
      %mu = idr.modu %u, %gu : i8
      idr.yield %x, %y, %u, %v, %q, %m, %qu, %mu : i64, i64, i8, i8, i64, i64, i8, i8
    }
    case 1 {
      %x = arith.constant -7 : i64
      %y = arith.constant -2 : i64
      %u = arith.constant 255 : i8
      %v = arith.constant 1 : i8
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %m = idr.mods %x, %g : i64
      %gu = idr.check.nonzero %v, "division by zero" : i8
      %qu = idr.divu %u, %gu : i8
      %mu = idr.modu %u, %gu : i8
      idr.yield %x, %y, %u, %v, %q, %m, %qu, %mu : i64, i64, i8, i8, i64, i64, i8, i8
    }
    case 2 {
      %x = arith.constant 7 : i64
      %y = arith.constant -2 : i64
      %u = arith.constant 255 : i8
      %v = arith.constant 255 : i8
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %m = idr.mods %x, %g : i64
      %gu = idr.check.nonzero %v, "division by zero" : i8
      %qu = idr.divu %u, %gu : i8
      %mu = idr.modu %u, %gu : i8
      idr.yield %x, %y, %u, %v, %q, %m, %qu, %mu : i64, i64, i8, i8, i64, i64, i8, i8
    }
    case 3 {
      %x = arith.constant 7 : i64
      %y = arith.constant 2 : i64
      %u = arith.constant 0 : i8
      %v = arith.constant 255 : i8
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %m = idr.mods %x, %g : i64
      %gu = idr.check.nonzero %v, "division by zero" : i8
      %qu = idr.divu %u, %gu : i8
      %mu = idr.modu %u, %gu : i8
      idr.yield %x, %y, %u, %v, %q, %m, %qu, %mu : i64, i64, i8, i8, i64, i64, i8, i8
    }
    case 4 {
      %x = arith.constant -9223372036854775808 : i64
      %y = arith.constant -1 : i64
      %u = arith.constant 128 : i8
      %v = arith.constant 2 : i8
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %m = idr.mods %x, %g : i64
      %gu = idr.check.nonzero %v, "division by zero" : i8
      %qu = idr.divu %u, %gu : i8
      %mu = idr.modu %u, %gu : i8
      idr.yield %x, %y, %u, %v, %q, %m, %qu, %mu : i64, i64, i8, i8, i64, i64, i8, i8
    }
    case 5 {
      %x = arith.constant -9223372036854775808 : i64
      %y = arith.constant 1 : i64
      %u = arith.constant 127 : i8
      %v = arith.constant 128 : i8
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %m = idr.mods %x, %g : i64
      %gu = idr.check.nonzero %v, "division by zero" : i8
      %qu = idr.divu %u, %gu : i8
      %mu = idr.modu %u, %gu : i8
      idr.yield %x, %y, %u, %v, %q, %m, %qu, %mu : i64, i64, i8, i8, i64, i64, i8, i8
    }
    case 6 {
      %x = arith.constant 9223372036854775807 : i64
      %y = arith.constant -1 : i64
      %u = arith.constant 1 : i8
      %v = arith.constant 128 : i8
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %m = idr.mods %x, %g : i64
      %gu = idr.check.nonzero %v, "division by zero" : i8
      %qu = idr.divu %u, %gu : i8
      %mu = idr.modu %u, %gu : i8
      idr.yield %x, %y, %u, %v, %q, %m, %qu, %mu : i64, i64, i8, i8, i64, i64, i8, i8
    }
    case 7 {
      %x = arith.constant -9223372036854775808 : i64
      %y = arith.constant -9223372036854775808 : i64
      %u = arith.constant 200 : i8
      %v = arith.constant 3 : i8
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %m = idr.mods %x, %g : i64
      %gu = idr.check.nonzero %v, "division by zero" : i8
      %qu = idr.divu %u, %gu : i8
      %mu = idr.modu %u, %gu : i8
      idr.yield %x, %y, %u, %v, %q, %m, %qu, %mu : i64, i64, i8, i8, i64, i64, i8, i8
    }
    case 8 {
      %x = arith.constant 0 : i64
      %y = arith.constant 5 : i64
      %u = arith.constant 129 : i8
      %v = arith.constant 127 : i8
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %m = idr.mods %x, %g : i64
      %gu = idr.check.nonzero %v, "division by zero" : i8
      %qu = idr.divu %u, %gu : i8
      %mu = idr.modu %u, %gu : i8
      idr.yield %x, %y, %u, %v, %q, %m, %qu, %mu : i64, i64, i8, i8, i64, i64, i8, i8
    }
    case 9 {
      %x = arith.constant -1 : i64
      %y = arith.constant 9223372036854775807 : i64
      %u = arith.constant 255 : i8
      %v = arith.constant 16 : i8
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %m = idr.mods %x, %g : i64
      %gu = idr.check.nonzero %v, "division by zero" : i8
      %qu = idr.divu %u, %gu : i8
      %mu = idr.modu %u, %gu : i8
      idr.yield %x, %y, %u, %v, %q, %m, %qu, %mu : i64, i64, i8, i8, i64, i64, i8, i8
    }
    case 10 {
      %x = arith.constant -9223372036854775808 : i64
      %y = arith.constant 2 : i64
      %u = arith.constant 7 : i8
      %v = arith.constant 250 : i8
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %m = idr.mods %x, %g : i64
      %gu = idr.check.nonzero %v, "division by zero" : i8
      %qu = idr.divu %u, %gu : i8
      %mu = idr.modu %u, %gu : i8
      idr.yield %x, %y, %u, %v, %q, %m, %qu, %mu : i64, i64, i8, i8, i64, i64, i8, i8
    }
    case 11 {
      %x = arith.constant 9223372036854775807 : i64
      %y = arith.constant -9223372036854775808 : i64
      %u = arith.constant 9 : i8
      %v = arith.constant 3 : i8
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %m = idr.mods %x, %g : i64
      %gu = idr.check.nonzero %v, "division by zero" : i8
      %qu = idr.divu %u, %gu : i8
      %mu = idr.modu %u, %gu : i8
      idr.yield %x, %y, %u, %v, %q, %m, %qu, %mu : i64, i64, i8, i8, i64, i64, i8, i8
    }
    case 12 {
      %x = arith.constant -9 : i64
      %y = arith.constant 3 : i64
      %u = arith.constant 128 : i8
      %v = arith.constant 128 : i8
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %m = idr.mods %x, %g : i64
      %gu = idr.check.nonzero %v, "division by zero" : i8
      %qu = idr.divu %u, %gu : i8
      %mu = idr.modu %u, %gu : i8
      idr.yield %x, %y, %u, %v, %q, %m, %qu, %mu : i64, i64, i8, i8, i64, i64, i8, i8
    }
    case 13 {
      %x = arith.constant -9223372036854775808 : i64
      %y = arith.constant 9223372036854775807 : i64
      %u = arith.constant 254 : i8
      %v = arith.constant 255 : i8
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %m = idr.mods %x, %g : i64
      %gu = idr.check.nonzero %v, "division by zero" : i8
      %qu = idr.divu %u, %gu : i8
      %mu = idr.modu %u, %gu : i8
      idr.yield %x, %y, %u, %v, %q, %m, %qu, %mu : i64, i64, i8, i8, i64, i64, i8, i8
    }
    case 14 {
      %x = arith.constant 2 : i64
      %y = arith.constant 0 : i64
      %u = arith.constant 1 : i8
      %v = arith.constant 1 : i8
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %m = idr.mods %x, %g : i64
      %gu = idr.check.nonzero %v, "division by zero" : i8
      %qu = idr.divu %u, %gu : i8
      %mu = idr.modu %u, %gu : i8
      idr.yield %x, %y, %u, %v, %q, %m, %qu, %mu : i64, i64, i8, i8, i64, i64, i8, i8
    }
    case 15 {
      %x = arith.constant 1 : i64
      %y = arith.constant 1 : i64
      %u = arith.constant 1 : i8
      %v = arith.constant 0 : i8
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %m = idr.mods %x, %g : i64
      %gu = idr.check.nonzero %v, "division by zero" : i8
      %qu = idr.divu %u, %gu : i8
      %mu = idr.modu %u, %gu : i8
      idr.yield %x, %y, %u, %v, %q, %m, %qu, %mu : i64, i64, i8, i8, i64, i64, i8, i8
    }
    default(%other: i64) {
      %x = arith.constant 13 : i64
      %y = arith.constant -4 : i64
      %u = arith.constant 100 : i8
      %v = arith.constant 9 : i8
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      %m = idr.mods %x, %g : i64
      %gu = idr.check.nonzero %v, "division by zero" : i8
      %qu = idr.divu %u, %gu : i8
      %mu = idr.modu %u, %gu : i8
      idr.yield %x, %y, %u, %v, %q, %m, %qu, %mu : i64, i64, i8, i8, i64, i64, i8, i8
    }
    }
    return %r#0, %r#1, %r#2, %r#3, %r#4, %r#5, %r#6, %r#7 : i64, i64, i8, i8, i64, i64, i8, i8
  }
  // The program: the results of the row the byte read chooses, folded,
  // or, in the run form, computed at run time.
  idr.func @Prog.main(%w0: !idr.world) -> !idr.world {
    %byte, %w1 = idr.io.get_byte %w0
    %row = arith.extui %byte : i32 to i64
    %x, %y, %u, %v, %q, %m, %qu, %mu = idr.call @folded(%row) : (i64) -> (i64, i64, i8, i8, i64, i64, i8, i8)
    %space = arith.constant 32 : i32
    %newline = arith.constant 10 : i32
    %w2 = idr.io.put_sint %x, %w1 : i64
    %w3 = idr.io.put_char %space, %w2
    %w4 = idr.io.put_sint %y, %w3 : i64
    %w5 = idr.io.put_char %space, %w4
    %w6 = idr.io.put_uint %u, %w5 : i8
    %w7 = idr.io.put_char %space, %w6
    %w8 = idr.io.put_uint %v, %w7 : i8
    %w9 = idr.io.put_char %space, %w8
    %w10 = idr.io.put_sint %q, %w9 : i64
    %w11 = idr.io.put_char %space, %w10
    %w12 = idr.io.put_sint %m, %w11 : i64
    %w13 = idr.io.put_char %space, %w12
    %w14 = idr.io.put_uint %qu, %w13 : i8
    %w15 = idr.io.put_char %space, %w14
    %w16 = idr.io.put_uint %mu, %w15 : i8
    %w17 = idr.io.put_char %newline, %w16
    return %w17 : !idr.world
  }
}
