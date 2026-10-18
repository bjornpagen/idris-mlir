// NEEDS-ACCEPTANCE: that the cell of a linear box only a callee reads goes on the stack after idr-rc (a box at any grade has a cell), where it made a heap cell before.
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=no-heap-allocation=@linear -o /dev/null
// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=no-heap-allocation=@linear -o /dev/null
// RUN: idris-mlir-opt %s --idr-rc -o - | FileCheck %s
// A constructor at quantity one is a box all the same: its cell is the
// box's, whatever grade the value has, so idr-rc's stack step, which reads
// where the cell goes, puts the one @head only reads in @linear's frame.
// CHECK-LABEL: idr.func @linear
// CHECK: idr.cell.stack : !idr.cell<!idr.box<!List>, @Cons>
// CHECK-NOT: idr.cell.new
// CHECK-LABEL: idr.func @Prog.main
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
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
