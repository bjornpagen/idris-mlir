// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-expect=holds=no-closures,quantities-kept=%s -o /dev/null
// A closure that takes a linear argument, kept in a constructor's field
// and read back by a match: every edge it moves along joins two values of
// one carrier, the type without its outermost grade, so its one label fits
// the key and it converts. The argument stays linear through the dispatch
// to the label's call, as the verifier checks after the pass, and every
// parameter keeps the quantity Idris proved.
!Box = !idr.data<"Box", plain [@MkBox(!idr.fn<(!idr.lin<i64>) -> (i64)>)]>
idr.program @"grade-linear-argument" root(@main) stage(higher) {
  idr.func @consume(%k: i64, %x: !idr.lin<i64>) -> i64 attributes {total} {
    %v = idr.lin.use %x : !idr.lin<i64>
    %r = arith.addi %k, %v : i64
    return %r : i64
  }
  idr.func @main() -> i64 {
    %k = arith.constant 1 : i64
    %f = idr.closure @consume(%k) : (i64) -> !idr.fn<(!idr.lin<i64>) -> (i64)>
    %b = idr.con !Box @MkBox(%f : !idr.fn<(!idr.lin<i64>) -> (i64)>)
    %r = idr.match %b : !Box -> (i64) {
    case @MkBox(%g: !idr.fn<(!idr.lin<i64>) -> (i64)>) {
      %two = arith.constant 2 : i64
      %x = idr.lin.enter %two : !idr.lin<i64>
      %y = idr.apply %g(%x) : !idr.fn<(!idr.lin<i64>) -> (i64)>
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
}
