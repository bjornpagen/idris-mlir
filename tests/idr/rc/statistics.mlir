// NEEDS-ACCEPTANCE: that each step of idr-rc reports its own statistics under its own pass, in the pipeline's order, where it acts.
// RUN: idris-mlir-opt %s --idr-rc --mlir-pass-statistics -o /dev/null 2> %t.stats
// RUN: FileCheck %s < %t.stats
// idr-rc is a pipeline of passes, each counting what it does where it does
// it: the cells made, the cells put on the stack, the parameters borrowed,
// the takes, recycled cells, dups and drops placed, and the values proved
// exclusive. Here `bump` takes its dead list apart and builds the new cell
// in it.
// CHECK: IdrRcCells
// CHECK: (S) {{[1-9][0-9]*}} boxes
// CHECK: IdrRcStack
// CHECK-DAG: (S) {{[0-9]+}} boxes
// CHECK-DAG: (S) {{[0-9]+}} stack-cells
// CHECK: IdrRcGrades
// CHECK: (S) {{[0-9]+}} borrowed
// CHECK: IdrRcPlace
// CHECK-DAG: (S) {{[0-9]+}} drops
// CHECK-DAG: (S) {{[0-9]+}} dups
// CHECK-DAG: (S) {{[1-9][0-9]*}} reuses
// CHECK-DAG: (S) {{[1-9][0-9]*}} takes
// CHECK: IdrRcExclusive
// CHECK: (S) {{[0-9]+}} exclusive
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @statistics root(@root) stage(first) {
  idr.func @bump(%l: !idr.box<!L>) -> !idr.box<!L> {
    %n = idr.constant !idr.box<!L> #idr.con<!L, @N, []>
    %c1 = arith.constant 1 : i64
    %r = idr.match %l : !idr.box<!L> -> (!idr.box<!L>) {
    case @N() {
      idr.yield %n : !idr.box<!L>
    }
    case @C(%h: i64, %t: !idr.box<!L>) {
      %h2 = arith.addi %h, %c1 : i64
      %t2 = idr.call @bump(%t) : (!idr.box<!L>) -> !idr.box<!L>
      %c = idr.con !idr.box<!L> @C(%h2 : i64, %t2 : !idr.box<!L>)
      idr.yield %c : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %x = arith.constant 7 : i64
    %n = idr.constant !idr.box<!L> #idr.con<!L, @N, []>
    %l = idr.con !idr.box<!L> @C(%x : i64, %n : !idr.box<!L>)
    %b = idr.call @bump(%l) : (!idr.box<!L>) -> !idr.box<!L>
    %s = idr.match %b : !idr.box<!L> -> (i64) {
    case @N() {
      idr.yield %x : i64
    }
    case @C(%h: i64, %t: !idr.box<!L>) {
      idr.yield %h : i64
    }
    }
    %w2 = idr.io.put_sint %s, %w : i64
    return %w2 : !idr.world
  }
}
