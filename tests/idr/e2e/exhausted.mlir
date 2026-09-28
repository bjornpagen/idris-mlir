// RUN: %status 4 bash -c 'ulimit -v 3000000; exec idris-mlir-cc %s -o %t.o' 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: not ls %t.o
// RUN: %status 4 bash -c 'ulimit -v 3000000; exec idris-mlir-cc %s --check' 2> %t.check.err
// RUN: FileCheck %s < %t.check.err
// rule: EVAL-1, DRV-CC-2
// A total evaluation the machine cannot finish (here, in an address space
// of 3 GB) is EVAL-1: status 4, at the call, and no output. --check runs the
// same evaluation, so it reports the same.
// CHECK: exhausted.mlir:{{[0-9]+}}:{{[0-9]+}}: error: unsupported (EVAL-1): the machine could not finish evaluating @range
module attributes {idr.program} {
  idr.data @List box {
    idr.ctor @Nil tag 0 () {quantities = []}
    idr.ctor @Cons tag 1 (i64, !idr.box<@List>) {quantities = ["w", "w"]}
  }
  func.func private @range(%n: i64) -> !idr.box<@List> attributes {idr.total, no_inline} {
    %r = idr.match_lit %n : i64 -> (!idr.box<@List>) {
    case 0 {
      %nil = idr.con @List::@Nil() : () -> !idr.box<@List>
      idr.yield %nil : !idr.box<@List>
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %rest = func.call @range(%m) : (i64) -> !idr.box<@List>
      %c = idr.con @List::@Cons(%n, %rest) : (i64, !idr.box<@List>) -> !idr.box<@List>
      idr.yield %c : !idr.box<@List>
    }
    }
    return %r : !idr.box<@List>
  }
  func.func private @first(%l: !idr.box<@List>) -> i64 {
    %r = idr.match %l : !idr.box<@List> -> (i64) {
    case @Cons(%h: i64, %t: !idr.box<@List>) {
      idr.yield %h : i64
    }
    default {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  func.func @Prog.main() -> i64 {
    %n = arith.constant 1000000000 : i64
    %l = func.call @range(%n) : (i64) -> !idr.box<@List>
    %h = func.call @first(%l) : (!idr.box<@List>) -> i64
    return %h : i64
  }
}
