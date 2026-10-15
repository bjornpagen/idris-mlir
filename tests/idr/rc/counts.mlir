// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=reuses-in-place=@map,counts-nothing=@sum,counts-nothing=@scalars -o /dev/null
// RUN: idris-mlir-opt %s --idr-rc | FileCheck %s
// NEEDS-ACCEPTANCE: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer, if this fixture's output moves.
// NEEDS-ACCEPTANCE: syntax swept to the data-type-first form
// idr-rc makes every reference explicit. That each is consumed exactly once
// on every path is the owned stage's rule, which idris-mlir-opt verifies
// after the pass; this test checks what the passes choose.

// A map over a list takes each cell apart where it matches it, the fields
// moving out with no count changed, and builds the new cell in it: it
// reuses in place (the first RUN line). A function that only reads its
// list borrows it (a plain parameter, a view of the caller's), and counts
// nothing; neither do worlds and scalars.
// CHECK-LABEL: idr.func @sum(
// CHECK-SAME: %{{.*}}: !idr.box<!L>, %{{.*}}: i64)
// CHECK-LABEL: idr.func @both(

// A string consumed twice is owned, and the first consuming use takes a
// reference of its own from a view of it; one only read is borrowed.
// CHECK-SAME: %[[A:[^:]*]]: !idr.own<!idr.str>, %[[B:[^:]*]]: !idr.str)
// CHECK: %[[V:.*]] = {{(idr\.)?}}borrow %[[A]]
// CHECK-COUNT-1: dup %[[V]]
// CHECK-NOT: {{(idr\.| )dup }}
// CHECK-NOT: {{(idr\.| )drop }}%[[B]]
// CHECK-LABEL: idr.func @scalars(
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
!Two = !idr.data<"Two", plain [@Two(!idr.str, !idr.str)]>
idr.program @counts root(@root) stage(first) {
  idr.func @map(%l: !idr.box<!L>) -> !idr.box<!L> {
    %n = idr.constant #idr.con<!L, @N, []> : !idr.box<!L>
    %r = idr.match %l : !idr.box<!L> -> (!idr.box<!L>) {
    case @N() {
      idr.yield %n : !idr.box<!L>
    }
    case @C(%h: i64, %t: !idr.box<!L>) {
      %h2 = arith.muli %h, %h : i64
      %t2 = idr.call @map(%t) : (!idr.box<!L>) -> !idr.box<!L>
      %c = idr.con !idr.box<!L> @C(%h2 : i64, %t2 : !idr.box<!L>)
      idr.yield %c : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
  }
  idr.func @sum(%l: !idr.box<!L>, %acc: i64) -> i64 {
    %r = idr.match %l : !idr.box<!L> -> (i64) {
    case @N() {
      idr.yield %acc : i64
    }
    case @C(%h: i64, %t: !idr.box<!L>) {
      %a = arith.addi %acc, %h : i64
      %s = idr.call @sum(%t, %a) : (!idr.box<!L>, i64) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @both(%a: !idr.str, %b: !idr.str) -> (!Two, i64) {
    %p = idr.con !Two @Two(%a : !idr.str, %a : !idr.str)
    %n = idr.str.length %b
    return %p, %n : !Two, i64
  }
  idr.func @scalars(%w: !idr.world, %x: i64) -> !idr.world {
    %w2 = idr.io.put_int signed %x, %w : i64
    return %w2 : !idr.world
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c = idr.constant "x" : !idr.str
    %p:2 = idr.call @both(%c, %c) : (!idr.str, !idr.str) -> (!Two, i64)
    %l = idr.constant #idr.con<!L, @N, []> : !idr.box<!L>
    %m = idr.call @map(%l) : (!idr.box<!L>) -> !idr.box<!L>
    %z = arith.constant 0 : i64
    %s = idr.call @sum(%m, %z) : (!idr.box<!L>, i64) -> i64
    %w2 = idr.io.put_int signed %s, %w : i64
    %w3 = idr.call @scalars(%w2, %s) : (!idr.world, i64) -> !idr.world
    return %w3 : !idr.world
  }
}
