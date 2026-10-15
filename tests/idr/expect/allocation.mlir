// RUN: idris-mlir-opt %s --idr-expect=holds=no-heap-allocation=@scalar -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=no-heap-allocation=@boxes -o /dev/null 2> %t.one.err
// RUN: FileCheck %s --check-prefix=ONE < %t.one.err
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=no-heap-allocation -o /dev/null 2> %t.all.err
// RUN: FileCheck %s --check-prefix=ALL < %t.all.err
// @scalar builds only unboxed data and calls nothing that allocates, so it
// holds of it. @boxes allocates through the function it calls, which is
// in its scope; without a function, the whole module is.
// ONE: error: expected no-heap-allocation: idr.con allocates in @cons
// ONE-NOT: error:
// ALL: error: expected no-heap-allocation: idr.con allocates in @cons
// ALL-NOT: error:
!Pair = !idr.data<"Pair", plain [@MkPair(i64, i64)]>
!List = !idr.data<"List", list [@Nil(), @Cons(i64, !idr.box<!idr.data<"List">>)]>
module {
  idr.func private @scalar(%x: i64) -> !Pair {
    %p = idr.con @MkPair(%x, %x) : (i64, i64) -> !Pair
    return %p : !Pair
  }
  idr.func private @cons(%x: i64, %l: !idr.box<!List>) -> !idr.box<!List> {
    %r = idr.con @Cons(%x, %l) : (i64, !idr.box<!List>) -> !idr.box<!List>
    return %r : !idr.box<!List>
  }
  idr.func private @boxes(%x: i64, %l: !idr.box<!List>) -> !idr.box<!List> {
    %r = idr.call @cons(%x, %l) : (i64, !idr.box<!List>) -> !idr.box<!List>
    return %r : !idr.box<!List>
  }
}
