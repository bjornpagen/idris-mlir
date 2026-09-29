// RUN: idris-mlir-opt %s --idr-expect=holds=no-heap-allocation=@marked -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=no-heap-allocation=@unmarked -o /dev/null 2> %t.err
// RUN: FileCheck %s --check-prefix=UNMARKED < %t.err
// RUN: idris-mlir-opt %s --idr-stack --idr-expect=holds=no-heap-allocation=@unmarked -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-stack --idr-expect=holds=no-heap-allocation=@escapes -o /dev/null 2> %t.escapes.err
// RUN: FileCheck %s --check-prefix=ESCAPES < %t.escapes.err
// A cell on the stack is not a heap allocation: a con idr-stack marks
// allocates stack memory, as an alloca does, and passes no-heap-allocation;
// the same con unmarked fails it. After idr-stack, the con of @unmarked,
// whose cell only @head reads, is on the stack; the one of @escapes, which
// returns it, is not.
// UNMARKED: error: expected no-heap-allocation: idr.con allocates in @unmarked
// ESCAPES: error: expected no-heap-allocation: idr.con allocates in @escapes
module attributes {idr.program} {
  idr.data @List box {
    idr.ctor @Nil tag 0 () {quantities = []}
    idr.ctor @Cons tag 1 (i64, !idr.box<@List>) {quantities = ["w", "w"]}
  }
  func.func private @head(%l: !idr.box<@List>) -> i64 {
    %r = idr.match %l : !idr.box<@List> -> (i64) {
    case @Cons(%h: i64, %t: !idr.box<@List>) {
      idr.yield %h : i64
    }
    default {
      %zero = arith.constant 0 : i64
      idr.yield %zero : i64
    }
    }
    return %r : i64
  }
  func.func private @marked(%x: i64, %t: !idr.box<@List>) -> i64 {
    %c = idr.con @List::@Cons(%x, %t) {idr.stack} : (i64, !idr.box<@List>) -> !idr.box<@List>
    %r = func.call @head(%c) : (!idr.box<@List>) -> i64
    return %r : i64
  }
  func.func private @unmarked(%x: i64, %t: !idr.box<@List>) -> i64 {
    %c = idr.con @List::@Cons(%x, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %r = func.call @head(%c) : (!idr.box<@List>) -> i64
    return %r : i64
  }
  func.func private @escapes(%x: i64, %t: !idr.box<@List>) -> !idr.box<@List> {
    %c = idr.con @List::@Cons(%x, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
    return %c : !idr.box<@List>
  }
  func.func @Prog.main() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
