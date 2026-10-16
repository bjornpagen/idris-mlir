// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-expect=holds=no-closures,quantities-kept=%s -o /dev/null
// A plain closure, entered into a linear value and used back as plain,
// then kept in a constructor's field: lin.enter, lin.use, the field and
// the match move the one label along edges of one carrier, so it fits the
// key, and the value converts whatever grade it went through.
!Box = !idr.data<"Box", plain [@MkBox(!idr.fn<(i64) -> (i64)>)]>
idr.program @"grade-plain" root(@main) stage(higher) {
  idr.func @add(%k: i64, %x: i64) -> i64 attributes {total} {
    %r = arith.addi %k, %x : i64
    return %r : i64
  }
  idr.func @main() -> i64 {
    %k = arith.constant 1 : i64
    %f = idr.closure @add(%k) : (i64) -> !idr.fn<(i64) -> (i64)>
    %fl = idr.lin.enter %f : !idr.lin<!idr.fn<(i64) -> (i64)>>
    %fu = idr.lin.use %fl : !idr.lin<!idr.fn<(i64) -> (i64)>>
    %b = idr.con !Box @MkBox(%fu : !idr.fn<(i64) -> (i64)>)
    %r = idr.match %b : !Box -> (i64) {
    case @MkBox(%g: !idr.fn<(i64) -> (i64)>) {
      %two = arith.constant 2 : i64
      %y = idr.apply %g(%two) : !idr.fn<(i64) -> (i64)>
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
}
