// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=no-heap-allocation=@linear -o /dev/null 2> %t.err
// RUN: FileCheck %s --check-prefix=HEAP < %t.err
// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=no-heap-allocation=@linear -o /dev/null
// RUN: idris-mlir-opt %s --idr-rc -o %t.owned.mlir
// RUN: %differential %s %t.owned.mlir
// A constructor at quantity one is a box all the same: its cell is the
// box's, whatever grade the value has, so idr-rc's stack step, which reads
// where the cell goes, puts the one @head only reads in @linear's frame.
// Before idr-rc the con makes its cell on the heap. In the frame, it is a
// cell no use outlives: the program idr-rc made prints what the one as
// written printed, on every input byte, which is the number and says
// whether the tail is a cell, and @head runs on the empty list and on
// cells, and leaves no cell live.
// HEAP: error: expected no-heap-allocation: idr.con allocates in @linear
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
idr.program @linearbox root(@Prog.main) stage(first) {
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
  idr.func @linear(%x: i64, %t: !idr.box<!List>) -> i64 {
    %c = idr.con !idr.lin<!idr.box<!List>> @Cons(%x : i64, %t : !idr.box<!List>)
    %u = idr.lin.use %c : !idr.lin<!idr.box<!List>>
    %r = idr.call @head(%u) : (!idr.box<!List>) -> i64
    return %r : i64
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
    %r = idr.call @linear(%x, %t) : (i64, !idr.box<!List>) -> i64
    %e = idr.call @head(%t) : (!idr.box<!List>) -> i64
    %w1 = idr.io.put_sint %r, %w0 : i64
    %w2 = idr.io.put_sint %e, %w1 : i64
    return %w2 : !idr.world
  }
}
