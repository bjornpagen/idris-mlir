// NEEDS-ACCEPTANCE: that the -verify-diagnostics run passes: no-heap-allocation, stated of @boxes and of the whole module, reports the idr.con of @cons, which @boxes calls, each request once at that op (one expectation takes both), and nothing else.
// RUN: idris-mlir-opt %s --idr-expect=holds=no-heap-allocation=@scalar -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=no-heap-allocation=@boxes,no-heap-allocation -verify-diagnostics -o /dev/null
// @scalar builds only unboxed data and calls nothing that allocates, so it
// holds of it. @boxes allocates through the function it calls, which is
// in its scope; without a function, the whole module is.
!Pair = !idr.data<"Pair", plain [@MkPair(i64, i64)]>
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
idr.program @allocation root(@root) stage(first) {
  idr.func @scalar(%x: i64) -> !Pair {
    %p = idr.con !Pair @MkPair(%x : i64, %x : i64)
    return %p : !Pair
  }
  idr.func @cons(%x: i64, %l: !idr.box<!List>) -> !idr.box<!List> {
    // expected-error @below {{expected no-heap-allocation: idr.con allocates in @cons}}
    %r = idr.con !idr.box<!List> @Cons(%x : i64, %l : !idr.box<!List>)
    return %r : !idr.box<!List>
  }
  idr.func @boxes(%x: i64, %l: !idr.box<!List>) -> !idr.box<!List> {
    %r = idr.call @cons(%x, %l) : (i64, !idr.box<!List>) -> !idr.box<!List>
    return %r : !idr.box<!List>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
