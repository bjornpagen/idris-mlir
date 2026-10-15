// RUN: idris-mlir-opt %s --idr-lower '--idr-expect=holds=lowered,signature=@pass:(i64)->i64,returns-argument=@pass:0' -o /dev/null
// Linearity has no runtime form: a linear value is lowered as the value
// itself, and entering or using one is nothing, so a function that uses
// its linear parameter returns the parameter.
idr.program @linear root(@Prog.main) stage(owned) {
  idr.func @pass(%x: !idr.lin<i64>) -> i64 {
    %v = idr.lin.use %x : !idr.lin<i64>
    return %v : i64
  }
  idr.func @Prog.main() -> i64 {
    %c = arith.constant 7 : i64
    %e = idr.lin.enter %c : !idr.lin<i64>
    %r = idr.call @pass(%e) : (!idr.lin<i64>) -> i64
    return %r : i64
  }
}
