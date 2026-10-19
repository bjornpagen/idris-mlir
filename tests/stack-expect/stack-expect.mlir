// RUN: idris-mlir-opt %s --idr-expect=holds=no-heap-allocation=@marked -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=no-heap-allocation=@unmarked -o /dev/null 2> %t.err
// RUN: FileCheck %s --check-prefix=UNMARKED < %t.err
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(idr-rc-cells),idr-rc-stack),idr-expect{holds=no-heap-allocation=@unmarked})' -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(idr-rc-cells),idr-rc-stack),idr-expect{holds=no-heap-allocation=@escapes})' -o /dev/null 2> %t.escapes.err
// RUN: FileCheck %s --check-prefix=ESCAPES < %t.escapes.err
// A cell on the stack is not a heap allocation: idr.cell.stack allocates
// in the frame, as an alloca does, and passes no-heap-allocation; the con
// of the same box, which makes its cell on the heap, fails it. After
// idr-rc's cells and stack steps, the cell of @unmarked, which only @head
// reads, is on the stack; the one of @escapes, which returns it, is not.
// UNMARKED: error: expected no-heap-allocation: idr.con allocates in @unmarked
// ESCAPES: error: expected no-heap-allocation: idr.cell.new allocates in @escapes
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
idr.program @expect root(@Prog.main) stage(first) {
  idr.func @head(%l: !idr.box<!List>) -> i64 {
    %r = idr.match %l : !idr.box<!List> -> (i64) {
    case @Cons(%h: i64, %t: !idr.box<!List>) {
      idr.yield %h : i64
    }
    default(%d0: !idr.box<!List>) {
      %zero = arith.constant 0 : i64
      idr.yield %zero : i64
    }
    }
    return %r : i64
  }
  idr.func @marked(%x: i64, %t: !idr.box<!List>) -> i64 {
    %cell = idr.cell.stack : !idr.cell<!idr.box<!List>, @Cons>
    %c = idr.cell.init %cell : !idr.cell<!idr.box<!List>, @Cons> (%x : i64, %t : !idr.box<!List>) -> !idr.box<!List>
    %r = idr.call @head(%c) : (!idr.box<!List>) -> i64
    return %r : i64
  }
  idr.func @unmarked(%x: i64, %t: !idr.box<!List>) -> i64 {
    %c = idr.con !idr.box<!List> @Cons(%x : i64, %t : !idr.box<!List>)
    %r = idr.call @head(%c) : (!idr.box<!List>) -> i64
    return %r : i64
  }
  idr.func @escapes(%x: i64, %t: !idr.box<!List>) -> !idr.box<!List> {
    %c = idr.con !idr.box<!List> @Cons(%x : i64, %t : !idr.box<!List>)
    return %c : !idr.box<!List>
  }
  idr.func @Prog.main() -> i64 {
    %x = arith.constant 7 : i64
    %nil = idr.constant !idr.box<!List> #idr.con<!List, @Nil, []>
    %a = idr.call @marked(%x, %nil) : (i64, !idr.box<!List>) -> i64
    %b = idr.call @unmarked(%x, %nil) : (i64, !idr.box<!List>) -> i64
    %l = idr.call @escapes(%x, %nil) : (i64, !idr.box<!List>) -> !idr.box<!List>
    %c = idr.call @head(%l) : (!idr.box<!List>) -> i64
    %ab = arith.addi %a, %b : i64
    %r = arith.addi %ab, %c : i64
    return %r : i64
  }
}
