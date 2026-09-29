// RUN: idris-mlir-cc %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: %t | FileCheck %s
// RUN: idris-mlir-cc %s -o %t-no-eval.o --no-eval
// RUN: %cc %t-no-eval.o -o %t-no-eval
// RUN: %t-no-eval | FileCheck %s
// RUN: idris-mlir-cc %s -o %t.mlir --emit=mlir
// RUN: FileCheck %s --check-prefix=EVALUATED < %t.mlir
// RUN: idris-mlir-cc %s -o %t-no-eval.mlir --emit=mlir --no-eval
// RUN: FileCheck %s --check-prefix=RUNTIME < %t-no-eval.mlir
// Evaluation changes when a result is computed, not what it is: the program
// prints the same with and without --no-eval (as tests/equivalence
// checks). With it, the call stays and runs.
// CHECK: 832040 -1.5e-7 250
// EVALUATED-NOT: @fib
// RUNTIME: @fib
module attributes {idr.program} {
  func.func private @fib(%n: i64) -> i64 attributes {idr.total, no_inline} {
    %two = arith.constant 2 : i64
    %small = arith.cmpi slt, %n, %two : i64
    %r = idr.match_lit %small : i1 -> (i64) {
    case true {
      idr.yield %n : i64
    }
    default {
      %one = arith.constant 1 : i64
      %a = arith.subi %n, %one : i64
      %b = arith.subi %n, %two : i64
      %fa = func.call @fib(%a) : (i64) -> i64
      %fb = func.call @fib(%b) : (i64) -> i64
      %s = arith.addi %fa, %fb : i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  func.func private @scale(%x: f64, %k: i8) -> (f64, i8) attributes {idr.total, no_inline} {
    %m = arith.constant -1.0e-7 : f64
    %y = arith.mulf %x, %m : f64
    %c = arith.constant 5 : i8
    %z = arith.muli %k, %c : i8
    return %y, %z : f64, i8
  }
  func.func @Prog.main(%w: !idr.world) -> !idr.world {
    %thirty = arith.constant 30 : i64
    %f = func.call @fib(%thirty) : (i64) -> i64
    %w1 = idr.io.put_int signed %f, %w : i64
    %sp = arith.constant 32 : i32
    %w2 = idr.io.put_char %sp, %w1
    %x = arith.constant 1.5 : f64
    %k = arith.constant 50 : i8
    %y:2 = func.call @scale(%x, %k) : (f64, i8) -> (f64, i8)
    %w3 = idr.io.put_double %y#0, %w2
    %w4 = idr.io.put_char %sp, %w3
    %w5 = idr.io.put_int %y#1, %w4 : i8
    %nl = arith.constant 10 : i32
    %w6 = idr.io.put_char %nl, %w5
    return %w6 : !idr.world
  }
}
