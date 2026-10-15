// RUN: idris-mlir-opt %s --idr-defunctionalize -o %t.mlir
// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-expect=holds=no-closures,quantities-kept=%s -o /dev/null
// RUN: FileCheck %s < %t.mlir
// NEEDS-ACCEPTANCE: the dispatch's printed form, as C06's conversion writes it.
// A closure that returns a linear result, itself linear because it is
// entered at once, kept in a constructor's field and used once: its key
// is the carrier without the grade, so the label fits, and the result of
// the dispatch keeps its grade, as the verifier checks after the pass.
// CHECK-LABEL: idr.func @main(
// CHECK: case @make(
// CHECK: call @make(
!Box = !idr.data<"Box", plain [@MkBox(!idr.lin<!idr.fn<(i64) -> (!idr.lin<i64>)>>)]>
module {
  idr.func private @make(%k: i64, %x: i64) -> !idr.lin<i64> attributes {total} {
    %s = arith.addi %k, %x : i64
    %r = idr.lin.enter %s : !idr.lin<i64>
    return %r : !idr.lin<i64>
  }
  idr.func @main() -> i64 {
    %k = arith.constant 1 : i64
    %f = idr.closure @make(%k) : (i64) -> !idr.fn<(i64) -> (!idr.lin<i64>)>
    %fl = idr.lin.enter %f : !idr.lin<!idr.fn<(i64) -> (!idr.lin<i64>)>>
    %b = idr.con @MkBox(%fl) : (!idr.lin<!idr.fn<(i64) -> (!idr.lin<i64>)>>) -> !idr.lin<!Box>
    %r = idr.match %b : !idr.lin<!Box> -> (i64) {
    case @MkBox(%g: !idr.lin<!idr.fn<(i64) -> (!idr.lin<i64>)>>) {
      %two = arith.constant 2 : i64
      %gu = idr.lin.use %g : !idr.lin<!idr.fn<(i64) -> (!idr.lin<i64>)>>
      %y = idr.apply %gu(%two) : !idr.fn<(i64) -> (!idr.lin<i64>)>
      %v = idr.lin.use %y : !idr.lin<i64>
      idr.yield %v : i64
    }
    }
    return %r : i64
  }
}
