// RUN: idris-mlir-opt %s --idr-expect=holds=no-heap-allocation=@marked -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=no-heap-allocation=@unmarked -o /dev/null 2> %t.err
// RUN: FileCheck %s --check-prefix=UNMARKED < %t.err
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(idr-rc-cells),idr-rc-stack),idr-expect{holds=no-heap-allocation=@unmarked})' -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(idr-rc-cells),idr-rc-stack),idr-expect{holds=no-heap-allocation=@escapes})' -o /dev/null 2> %t.escapes.err
// RUN: FileCheck %s --check-prefix=ESCAPES < %t.escapes.err
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(idr-rc-cells),idr-rc-stack))' -o %t.stack.mlir
// RUN: %differential %s %t.stack.mlir
// A cell on the stack is not a heap allocation: idr.cell.stack allocates
// in the frame, as an alloca does, and passes no-heap-allocation; the con
// of the same box, which makes its cell on the heap, fails it. After
// idr-rc's cells and stack steps, the cell of @unmarked, which only @head
// reads, is on the stack; the one of @escapes, which returns it, is not.
// A cell in the frame is one no use outlives: the program the steps made
// prints what the one as written printed, on every input byte, which is
// the number and says whether the tail is a cell, and @head runs on the
// empty list and on cells, and leaves no cell live.
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
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %x = arith.extui %ch : i32 to i64
    %one = arith.constant 1 : i64
    %bit = arith.andi %x, %one : i64
    %nil = idr.constant !idr.box<!List> #idr.con<!List, @Nil, []>
    %t = idr.match_lit %bit : i64 -> (!idr.box<!List>) {
    case 0 {
      idr.yield %nil : !idr.box<!List>
    }
    default(%d: i64) {
      %c = idr.con !idr.box<!List> @Cons(%one : i64, %nil : !idr.box<!List>)
      idr.yield %c : !idr.box<!List>
    }
    }
    %a = idr.call @marked(%x, %t) : (i64, !idr.box<!List>) -> i64
    %b = idr.call @unmarked(%x, %t) : (i64, !idr.box<!List>) -> i64
    %l = idr.call @escapes(%x, %t) : (i64, !idr.box<!List>) -> !idr.box<!List>
    %c = idr.call @head(%l) : (!idr.box<!List>) -> i64
    %e = idr.call @head(%t) : (!idr.box<!List>) -> i64
    %w1 = idr.io.put_sint %a, %w0 : i64
    %w2 = idr.io.put_sint %b, %w1 : i64
    %w3 = idr.io.put_sint %c, %w2 : i64
    %w4 = idr.io.put_sint %e, %w3 : i64
    return %w4 : !idr.world
  }
}
