// RUN: idris-mlir-opt %s --idr-rc --mlir-pass-statistics -o /dev/null 2> %t.stats
// RUN: FileCheck %s < %t.stats
// NEEDS-ACCEPTANCE: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer, if this fixture's output moves.
// NEEDS-ACCEPTANCE: syntax swept to the data-type-first form
// idr-rc places and commits its counts through two function passes it runs
// itself, but the counts are its own: one walk after both runs reports what
// the module holds, under IdrRc, and the nested passes declare none. Here
// `bump` takes its dead list apart and builds the new cell in it.
// CHECK: IdrRc
// CHECK-DAG: (S) {{[0-9]+}} borrowed
// CHECK-DAG: (S) {{[0-9]+}} exclusive
// CHECK-DAG: (S) {{[1-9][0-9]*}} takes
// CHECK-DAG: (S) {{[1-9][0-9]*}} reuses
// CHECK-DAG: (S) {{[0-9]+}} dups
// CHECK-DAG: (S) {{[0-9]+}} drops
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @statistics root(@root) stage(first) {
  idr.func @bump(%l: !idr.box<!L>) -> !idr.box<!L> {
    %n = idr.constant #idr.con<!L, @N, []> : !idr.box<!L>
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
    %n = idr.constant #idr.con<!L, @N, []> : !idr.box<!L>
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
    %w2 = idr.io.put_int signed %s, %w : i64
    return %w2 : !idr.world
  }
}
