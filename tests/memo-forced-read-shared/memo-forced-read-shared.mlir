// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=graded to=owned})' -o /dev/null
// A read of a memo cell's field leaves the field what it holds, as a force
// does not: the value read is a second reference to what the field still
// holds, so it is shared however unshared the cell is. @make builds a
// suspension already forced to a list, reads the list out of the forced
// state and its tag, and gives back the tag and the suspension. The cell is
// fresh and @make alone holds it, so it is unshared; the list read out of
// it is not. The cell still lives where the tag is read, so counting gives
// the list no reference of its own, and what exclusivity answers of the
// list is all that grades it. The slice from the graded stage to the owned
// stage is verified after every pass, so it verifies, with nothing
// expected, only where exclusivity leaves that list shared: graded `unique
// deep`, it would claim more than a read of a field used many times gives,
// and the read's result is held to what the read gives.
#List = #idr.family<"List" [] {
    @Nil ()
    @Cons (i64, !idr.self)
  }>
!List = !idr.data<#List>
!Nil = !idr.data<#List @Nil>
!Cons = !idr.data<#List @Cons>
#Lazy = #idr.family<"Lazy" memo [] {
    @single fn @single (i64)
  } forced (!List)>
!Lazy = !idr.data<#Lazy>
!Forced = !idr.data<#Lazy @forced>
idr.program @memo root(@main) stage(graded) {
  idr.func @main() {
    %r:2 = idr.call @make() <{tail_kind = nontail}> : () -> (i64, !Lazy)
    idr.return
  }
  idr.func @single(%n: i64) -> !List {
    %nil = idr.data.con() : !Nil
    %c = idr.cell.new : !idr.cell<!Cons>
    %ys = idr.cell.init %c : !idr.cell<!Cons> (%n : i64, %nil : !Nil) -> !Cons
    %r = idr.data.reindex %ys : !Cons to !List
    idr.return %r : !List
  }
  idr.func @make() -> (i64, !Lazy) {
    %one = arith.constant 1 : i64
    %nil = idr.data.con() : !Nil
    %c = idr.cell.new : !idr.cell<!Cons>
    %xs = idr.cell.init %c : !idr.cell<!Cons> (%one : i64, %nil : !Nil) -> !Cons
    %s = idr.cell.new : !idr.cell<!Forced>
    %f = idr.cell.init %s : !idr.cell<!Forced> (%xs : !Cons) -> !Forced
    %x = idr.data.field %f[0] : !Forced -> !List
    %tag = idr.data.tag %x : !List
    %l = idr.data.reindex %f : !Forced to !Lazy
    idr.return %tag, %l : i64, !Lazy
  }
}
