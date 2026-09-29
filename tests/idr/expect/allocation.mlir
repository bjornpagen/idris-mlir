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
module {
  idr.data @Pair {
    idr.ctor @MkPair tag 0 (i64, i64) {quantities = ["w", "w"]}
  }
  idr.data @List box {
    idr.ctor @Nil tag 0 () {quantities = []}
    idr.ctor @Cons tag 1 (i64, !idr.box<@List>) {quantities = ["w", "w"]}
  }
  func.func @scalar(%x: i64) -> !idr.data<@Pair> {
    %p = idr.con @Pair::@MkPair(%x, %x) : (i64, i64) -> !idr.data<@Pair>
    return %p : !idr.data<@Pair>
  }
  func.func private @cons(%x: i64, %l: !idr.box<@List>) -> !idr.box<@List> {
    %r = idr.con @List::@Cons(%x, %l) : (i64, !idr.box<@List>) -> !idr.box<@List>
    return %r : !idr.box<@List>
  }
  func.func @boxes(%x: i64, %l: !idr.box<@List>) -> !idr.box<@List> {
    %r = func.call @cons(%x, %l) : (i64, !idr.box<@List>) -> !idr.box<@List>
    return %r : !idr.box<@List>
  }
}
