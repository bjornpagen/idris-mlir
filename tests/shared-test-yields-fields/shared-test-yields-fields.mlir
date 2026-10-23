// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=graded to=owned})' -o /dev/null
// The run-time test of sharing gives the fields of the value it takes
// apart out of whichever of its regions runs: the unique region yields
// the fields moved out of the cell, each a counted value of its own, and
// the shared region yields each field it read, with the reference a dup
// gave it, after dropping the value. Each yield moves a field's reference
// on to the test's result. @tail gives back the tail of the cell it is
// given, its last use a read of that field, so counting takes the cell
// apart there; @main passes it the same cell twice, so neither call's cell
// is proved unique, and the take becomes the test. The slice from the
// graded stage to the owned stage is verified after every pass, so it
// verifies, with nothing expected, only where the yields the test's
// expansion builds are the moves of the fields' references, and the drop
// in its shared region the move of the value's.
#List = #idr.family<"List" [] {
    @Nil ()
    @Cons (i64, !idr.self)
  }>
!List = !idr.data<#List>
!Nil = !idr.data<#List @Nil>
!Cons = !idr.data<#List @Cons>
idr.program @tests root(@main) stage(graded) {
  idr.func @main() {
    %one = arith.constant 1 : i64
    %nil = idr.data.con() : !Nil
    %c = idr.cell.new : !idr.cell<!Cons>
    %x = idr.cell.init %c : !idr.cell<!Cons> (%one : i64, %nil : !Nil) -> !Cons
    %t1 = idr.call @tail(%x) <{tail_kind = nontail}> : (!Cons) -> !List
    %t2 = idr.call @tail(%x) <{tail_kind = nontail}> : (!Cons) -> !List
    idr.return
  }
  idr.func @tail(%x: !Cons) -> !List {
    %t = idr.data.field %x[1] : !Cons -> !List
    idr.return %t : !List
  }
}
