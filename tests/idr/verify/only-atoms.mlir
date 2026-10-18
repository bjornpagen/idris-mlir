// NEEDS-ACCEPTANCE: that an exclusive reference to a constant run held in place, whose second cell is a box with fields, is refused (it verifies at the base, which read the run's cells and its tail and never the box its spine holds).
// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// A reference of its own to static data is exclusive only when the data
// reaches no cell but atoms. A run of more than one cell, even held in
// place, holds every cell after its first in a box at its spine, which has
// fields: a take of it would hand that cell out to build in, while every
// other copy of the constant still holds it.
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
idr.program @"only-atoms" root(@root) stage(owned) {
  idr.func @run() -> !idr.excl<!List> {
    // expected-note @+1 {{the value is defined here}}
    %l = idr.constant !idr.q<many, borrow, !List> #idr.con<!List, @Cons, [1], [2, #idr.con<!List, @Nil, []>] along 1>
    // expected-error @+1 {{takes an exclusive reference to a value that reaches cells other than atoms, which it shares}}
    %e = idr.dup %l : !idr.q<many, borrow, !List> -> !idr.excl<!List>
    return %e : !idr.excl<!List>
  }
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
