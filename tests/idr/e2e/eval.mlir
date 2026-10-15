// RUN: rm -rf %t.dumps && mkdir -p %t.dumps
// RUN: idris-mlir -c %s -o %t.o -mlir-print-ir-after-all -mlir-print-ir-tree-dir=%t.dumps
// RUN: sh -c 'd=%t.dumps/builtin_module_no-symbol-name; cat "$d/$(ls "$d" | grep "[.]mlir$" | sort -n | tail -n 1)"' > %t.mlir
// RUN: FileCheck %s --check-prefix=LEFT < %t.mlir
// RUN: %cc %t.o -o %t
// RUN: %t | FileCheck %s
// A closed call of a pure, total function stays in the module and runs at
// run time.
// CHECK: 3628800 x-x-x
// LEFT: llvm.call @fact(
// LEFT: llvm.call @dashes(
module {
  idr.func private @fact(%n: i64) -> i64 attributes {total, no_inline} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %one = arith.constant 1 : i64
      idr.yield %one : i64
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %f = idr.call @fact(%m) : (i64) -> i64
      %p = arith.muli %n, %f : i64
      idr.yield %p : i64
    }
    }
    return %r : i64
  }
  idr.func private @dashes(%s: !idr.str, %n: i64) -> !idr.str attributes {total, no_inline} {
    %r = idr.match_lit %n : i64 -> (!idr.str) {
    case 0 {
      idr.yield %s : !idr.str
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %rest = idr.call @dashes(%s, %m) : (!idr.str, i64) -> !idr.str
      %dash = arith.constant 45 : i32
      %d = idr.str.cons %dash, %rest
      %x = idr.str.append %s, %d
      idr.yield %x : !idr.str
    }
    }
    return %r : !idr.str
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %ten = arith.constant 10 : i64
    %f = idr.call @fact(%ten) : (i64) -> i64
    %w1 = idr.io.put_int signed %f, %w : i64
    %sp = arith.constant 32 : i32
    %w2 = idr.io.put_char %sp, %w1
    %x = idr.constant "x" : !idr.str
    %two = arith.constant 2 : i64
    %s = idr.call @dashes(%x, %two) : (!idr.str, i64) -> !idr.str
    %w3 = idr.io.put_str %s, %w2
    %nl = arith.constant 10 : i32
    %w4 = idr.io.put_char %nl, %w3
    return %w4 : !idr.world
  }
}
