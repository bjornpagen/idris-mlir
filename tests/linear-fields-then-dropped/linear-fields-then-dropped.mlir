// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=graded to=owned})' -o /dev/null
// A value Idris proved used once may have its fields read and then be given
// up: each read is a use of its field, and the drop counting places after
// the last of them gives up the cell, a use of no field. @both reads the two
// words of the cell it is given, each once, and nothing else, so placement
// drops the cell right after the second read. @main gives it a value it
// made, used once, which moves to its one use, so @both's parameter is
// counted and no borrow makes it a view. The slice from the graded stage to
// the owned stage is verified after every pass, the linearity rule among
// them, so it verifies, with nothing expected, only where the drop after
// the reads counts as no second use of either field, and as the cell's one
// giving up.
#Row = #idr.family<"Row" [] {
    @End ()
    @Cell (i64, i64, !idr.self)
  }>
!End = !idr.data<#Row @End>
!Cell = !idr.data<#Row @Cell>
!Once = !idr.graded<once, counted, !Cell>
idr.program @fields root(@main) stage(graded) {
  idr.func @main() {
    %a = arith.constant 1 : i64
    %b = arith.constant 2 : i64
    %end = idr.data.con() : !End
    %cell = idr.cell.new : !idr.cell<!Cell>
    %x = idr.cell.init %cell : !idr.cell<!Cell> (%a : i64, %b : i64, %end : !End) -> !Once
    %s = idr.call @both(%x) <{tail_kind = nontail}> : (!Once) -> i64
    idr.return
  }
  idr.func @both(%x: !Once) -> i64 {
    %a = idr.data.field %x[0] : !Once -> i64
    %b = idr.data.field %x[1] : !Once -> i64
    %s = arith.addi %a, %b : i64
    idr.return %s : i64
  }
}
