// RUN: rm -rf %t.dumps && mkdir -p %t.dumps
// RUN: idris-mlir -c %s -o %t.o --dump-dir=%t.dumps
// RUN: sh -c 'for dump in %t.dumps/*; do last=$dump; done; cat "$last"' > %t.mlir
// RUN: FileCheck %s --check-prefix=LEFT < %t.mlir
// RUN: %cc %t.o -o %t
// RUN: %t | FileCheck %s
// RUN: idris-mlir -c %s -o %t-no-eval.o --no-eval
// RUN: %cc %t-no-eval.o -o %t-no-eval
// RUN: %t-no-eval | FileCheck %s
// idr-eval is not in the simplify round, so a closed call of a pure, total
// function stays in the module and runs at run time. --no-eval is the same
// pipeline. The program prints the same either way. The pass's own tests
// are tests/idr/eval.
// CHECK: 3628800 x-x-x
// LEFT: llvm.call @fact(
// LEFT: llvm.call @dashes(
module attributes {idr.program} {
  func.func private @fact(%n: i64) -> i64 attributes {idr.total, no_inline} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %one = arith.constant 1 : i64
      idr.yield %one : i64
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %f = func.call @fact(%m) : (i64) -> i64
      %p = arith.muli %n, %f : i64
      idr.yield %p : i64
    }
    }
    return %r : i64
  }
  func.func private @dashes(%s: !idr.str, %n: i64) -> !idr.str attributes {idr.total, no_inline} {
    %r = idr.match_lit %n : i64 -> (!idr.str) {
    case 0 {
      idr.yield %s : !idr.str
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %rest = func.call @dashes(%s, %m) : (!idr.str, i64) -> !idr.str
      %dash = arith.constant 45 : i32
      %d = idr.str.cons %dash, %rest
      %x = idr.str.append %s, %d
      idr.yield %x : !idr.str
    }
    }
    return %r : !idr.str
  }
  func.func @Prog.main(%w: !idr.world) -> !idr.world {
    %ten = arith.constant 10 : i64
    %f = func.call @fact(%ten) : (i64) -> i64
    %w1 = idr.io.put_int signed %f, %w : i64
    %sp = arith.constant 32 : i32
    %w2 = idr.io.put_char %sp, %w1
    %x = idr.constant "x" : !idr.str
    %two = arith.constant 2 : i64
    %s = func.call @dashes(%x, %two) : (!idr.str, i64) -> !idr.str
    %w3 = idr.io.put_str %s, %w2
    %nl = arith.constant 10 : i32
    %w4 = idr.io.put_char %nl, %w3
    return %w4 : !idr.world
  }
}
