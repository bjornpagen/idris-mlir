// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=graded to=owned})' -o /dev/null
// A part read from a part keeps reading memory the part it was read from
// holds, so where that part dies after its owner did, holding a reference
// of its own, the part read from it still needed takes its reference from
// it first, as from any owner, and is no view of memory its giving up may
// free. @nested reads the record held in its outer record, then the list
// held in that one; it reads a word of the outer record last, so the outer
// record is taken apart there and the inner one takes its reference from
// it; then a word of the inner record, its last use, after which the list
// is still given back. So the inner record is taken apart where it dies
// and the list takes its reference from it, never left a view of a record
// that is gone. The slice from the graded stage to the owned stage is
// verified after every pass, so it verifies, with nothing expected, only
// where the list given back holds a reference of its own, which a part
// read from an owner never moves on.
#List = #idr.family<"List" [] {
    @Nil ()
    @Cons (i64, !idr.self)
  }>
!List = !idr.data<#List>
!Nil = !idr.data<#List @Nil>
!Cons = !idr.data<#List @Cons>
#Inner = #idr.family<"Inner" [] {
    @MkInner (i64, !List)
  }>
!Inner = !idr.data<#Inner>
#Outer = #idr.family<"Outer" [] {
    @MkOuter (i64, !Inner)
  }>
!Outer = !idr.data<#Outer>
idr.program @holders root(@main) stage(graded) {
  idr.func @main() {
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %three = arith.constant 3 : i64
    %nil = idr.data.con() : !Nil
    %c = idr.cell.new : !idr.cell<!Cons>
    %list = idr.cell.init %c : !idr.cell<!Cons> (%one : i64, %nil : !Nil) -> !Cons
    %inner = idr.data.con(%two : i64, %list : !Cons) : !Inner
    %outer = idr.data.con(%three : i64, %inner : !Inner) : !Outer
    %r:3 = idr.call @nested(%outer) : (!Outer) -> (i64, i64, !List)
    idr.return
  }
  idr.func @nested(%o: !Outer) -> (i64, i64, !List) {
    %p = idr.data.field %o[1] : !Outer -> !Inner
    %q = idr.data.field %p[1] : !Inner -> !List
    %wo = idr.data.field %o[0] : !Outer -> i64
    %wp = idr.data.field %p[0] : !Inner -> i64
    idr.return %wo, %wp, %q : i64, i64, !List
  }
}
