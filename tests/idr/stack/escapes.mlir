// NEEDS-ACCEPTANCE: that idr-rc's stack step puts the cell of a box only read in its frame on the stack, and leaves the cell of a returned box on the heap.
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-rc-stack),idr-expect{holds=no-heap-allocation=@local})' -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-rc-stack),idr-expect{holds=no-heap-allocation=@returned})' -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// The escape analysis follows a cell's address from its producer to the
// box its init gives: a box @head only reads leaves its cell in @local's
// frame, and a box @returned gives back takes its cell out of it.
// CHECK: error: expected no-heap-allocation: idr.cell.new allocates in @returned
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
idr.program @escapes root(@Prog.main) stage(first) {
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
  idr.func @local(%x: i64, %t: !idr.box<!List>) -> i64 {
    %c = idr.cell.new : !idr.cell<!idr.box<!List>, @Cons>
    %b = idr.cell.init %c : !idr.cell<!idr.box<!List>, @Cons> (%x : i64, %t : !idr.box<!List>) -> !idr.box<!List>
    %r = idr.call @head(%b) : (!idr.box<!List>) -> i64
    return %r : i64
  }
  idr.func @returned(%x: i64, %t: !idr.box<!List>) -> !idr.box<!List> {
    %c = idr.cell.new : !idr.cell<!idr.box<!List>, @Cons>
    %b = idr.cell.init %c : !idr.cell<!idr.box<!List>, @Cons> (%x : i64, %t : !idr.box<!List>) -> !idr.box<!List>
    return %b : !idr.box<!List>
  }
  idr.func @Prog.main() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
