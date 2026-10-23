// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=graded to=owned})' -o /dev/null
// A counted value yielded out of a region moves its reference on to the
// value the region gives, as a return moves it to the caller. @pick gives
// back one of the two lists it is passed, chosen by a literal match: each
// case yields one list out of its region, and counting drops the other at
// the case's head, so each list moves its reference on once on every path,
// by the yield on one and the drop on the other. @main passes two lists
// it built, which move into the call, and drops what it gets back. The
// slice from the graded stage to the owned stage is verified after every
// pass, so it verifies, with nothing expected, only where counting and the
// linearity rule read the yield alike: as the move of the one reference
// the list holds.
#List = #idr.family<"List" [] {
    @Nil ()
    @Cons (i64, !idr.self)
  }>
!List = !idr.data<#List>
!Nil = !idr.data<#List @Nil>
!Cons = !idr.data<#List @Cons>
idr.program @yields root(@main) stage(graded) {
  idr.func @main() {
    %k = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %nil = idr.data.con() : !Nil
    %ca = idr.cell.new : !idr.cell<!Cons>
    %a = idr.cell.init %ca : !idr.cell<!Cons> (%one : i64, %nil : !Nil) -> !Cons
    %cb = idr.cell.new : !idr.cell<!Cons>
    %b = idr.cell.init %cb : !idr.cell<!Cons> (%two : i64, %nil : !Nil) -> !Cons
    %r = idr.call @pick(%k, %a, %b) <{tail_kind = nontail}> : (i64, !Cons, !Cons) -> !Cons
    idr.return
  }
  idr.func @pick(%k: i64, %a: !Cons, %b: !Cons) -> !Cons {
    %r = idr.lit.match %k : i64 -> (!Cons) {
    case 0 {
      idr.yield %a : !Cons
    }
    default(%d: i64) {
      idr.yield %b : !Cons
    }
    }
    idr.return %r : !Cons
  }
}
