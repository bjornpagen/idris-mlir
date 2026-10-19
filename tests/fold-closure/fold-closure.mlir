// RUN: idris-mlir-opt %s --canonicalize '--idr-expect=holds=returns=@closures:(#idr.closure<@add,[5]>)/(#idr.closure<@add,[]>)/_' -o /dev/null
// A closure whose captures are constants is a constant.

idr.program @closure root(@root) stage(higher) {
  idr.func @add(%a: i64, %b: i64) -> i64 {
    %r = arith.addi %a, %b : i64
    return %r : i64
  }

  idr.func @closures(%x: i64) -> (!idr.fn<(i64) -> (i64)>, !idr.fn<(i64, i64) -> (i64)>,
                                    !idr.fn<(i64) -> (i64)>) {
    %five = arith.constant 5 : i64
    %c = idr.closure @add(%five) : (i64) -> !idr.fn<(i64) -> (i64)>
    %n = idr.closure @add() : () -> !idr.fn<(i64, i64) -> (i64)>
    %r = idr.closure @add(%x) : (i64) -> !idr.fn<(i64) -> (i64)>
    return %c, %n, %r : !idr.fn<(i64) -> (i64)>, !idr.fn<(i64, i64) -> (i64)>,
                        !idr.fn<(i64) -> (i64)>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
