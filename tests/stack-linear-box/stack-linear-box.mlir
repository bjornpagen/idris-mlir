// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=no-heap-allocation=@linear -o /dev/null 2> %t.err
// RUN: FileCheck %s --check-prefix=HEAP < %t.err
// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=no-heap-allocation=@linear -o /dev/null
// A constructor at quantity one is a box all the same: its cell is the
// box's, whatever grade the value has, so idr-rc's stack step, which reads
// where the cell goes, puts the one @head only reads in @linear's frame.
// Before idr-rc the con makes its cell on the heap.
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
  idr.func @Prog.main() -> i64 {
    %x = arith.constant 7 : i64
    %nil = idr.constant !idr.box<!List> #idr.con<!List, @Nil, []>
    %r = idr.call @linear(%x, %nil) : (i64, !idr.box<!List>) -> i64
    return %r : i64
  }
}
