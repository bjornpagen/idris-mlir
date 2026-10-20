// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,signature=@pass:(i64)->i64,returns-argument=@pass:0' -o /dev/null
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
// Linearity has no runtime form: a linear value is lowered as the value
// itself, and entering or using one is nothing, so a function that uses
// its linear parameter returns the parameter. The program, lowered and as
// written, exits with the 7 it passes through, as the reference at the end
// (REF) does (%differential, on the one input, none, since it reads none).
// STDIN:
idr.program @linear root(@Prog.main) stage(owned) types #idr.types<> {
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
// The reference:
// REF: idr.program @ref root(@Prog.main) stage(higher) types #idr.types<> {
// REF:   idr.func @Prog.main() -> i64 {
// REF:     %c = arith.constant 7 : i64
// REF:     return %c : i64
// REF:   }
// REF: }
