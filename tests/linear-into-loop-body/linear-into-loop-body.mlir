// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=graded to=owned})' -o /dev/null
// A value Idris proved used once, entered into a loop, is moved into it:
// the loop's body runs once, before anything repeats, so its one use there
// takes the value in as a region run once would, and nothing holds it
// across the loop. Holding it would duplicate it at the entry and drop it
// after, and only a value used many is duplicated or dropped. @run is given
// a cell used once, which its loop's body passes to the loop's join point,
// as the frontend and contification write a loop: the entry jump alone. Each run of the join point reads the cell's two words, each once,
// so counting takes the cell apart after the second read, and the run that
// goes round again passes a new cell, built used once. @main gives @run a
// value it made, used once, which moves to its one use, so @run's
// parameter is counted and no borrow makes it a view. The slice from the
// graded stage to the owned stage is verified after every pass, so it
// verifies, with nothing expected, only where nothing duplicates or drops
// a value used once and the loop's parameter is used once on every run.
#Row = #idr.family<"Row" [] {
    @End ()
    @Cell (i64, i64, !idr.self)
  }>
!End = !idr.data<#Row @End>
!Cell = !idr.data<#Row @Cell>
!Once = !idr.graded<once, counted, !Cell>
idr.program @loops root(@main) stage(graded) {
  idr.func @main() {
    %n = arith.constant 3 : i64
    %zero = arith.constant 0 : i64
    %end = idr.data.con() : !End
    %cell = idr.cell.new : !idr.cell<!Cell>
    %x = idr.cell.init %cell : !idr.cell<!Cell> (%n : i64, %zero : i64, %end : !End) -> !Once
    %s = idr.call @run(%x) <{tail_kind = nontail}> : (!Once) -> i64
    idr.return
  }
  idr.func @run(%x: !Once) -> i64 {
    %r = idr.loop tokens(%k) -> (i64) attributes {binders = [#idr.index_binders<[]>]} {
      idr.jump %k(%x : !Once)
    } join tokens(%again)(%y: !Once) {
      idr.may_loop
      %count = idr.data.field %y[0] : !Once -> i64
      %sum = idr.data.field %y[1] : !Once -> i64
      %s = idr.lit.match %count : i64 -> (i64) {
        case 0(%key: i64) {
          idr.yield %sum : i64
        } default(%d: i64) {
          %one = arith.constant 1 : i64
          %next = arith.subi %d, %one : i64
          %more = arith.addi %sum, %d : i64
          %end = idr.data.con() : !End
          %cell = idr.cell.new : !idr.cell<!Cell>
          %z = idr.cell.init %cell : !idr.cell<!Cell> (%next : i64, %more : i64, %end : !End) -> !Once
          idr.jump %again(%z : !Once)
        }
      }
      idr.yield %s : i64
    }
    idr.return %r : i64
  }
}
