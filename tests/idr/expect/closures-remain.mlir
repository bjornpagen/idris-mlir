// The module of closures.mlir's failing run: a closure of each kind.
module {
  func.func private @add(%x: i64, %y: i64) -> i64 {
    %r = arith.addi %x, %y : i64
    return %r : i64
  }
  func.func @make(%x: i64) -> !idr.fn<(i64) -> (i64)> {
    %f = idr.closure @add(%x) : (i64) -> !idr.fn<(i64) -> (i64)>
    return %f : !idr.fn<(i64) -> (i64)>
  }
  func.func @use(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  func.func @known() -> !idr.fn<(i64, i64) -> (i64)> {
    %f = idr.constant #idr.closure<@add, []> : !idr.fn<(i64, i64) -> (i64)>
    return %f : !idr.fn<(i64, i64) -> (i64)>
  }
}
